--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Directories;
with Ada.Real_Time;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with GNAT.OS_Lib;
with Interfaces;
with Interfaces.C;
with System;

package body Wheel is

   use Interfaces;
   use type Interfaces.C.int;
   use type Interfaces.C.long;
   use type Interfaces.C.size_t;
   use type Interfaces.C.unsigned_long;

   --  Linux input event (x86_64): struct timeval, type, code, value
   type Event is record
      Sec, Usec : Interfaces.C.long;
      Kind      : Unsigned_16;
      Code      : Unsigned_16;
      Value     : Integer_32;
   end record
     with Convention => C;
   for Event'Size use 24 * 8;

   type Event_Array is array (1 .. 64) of Event with Convention => C;

   type Unsigned_16_Array is array (Positive range <>) of Unsigned_16;

   --  struct ff_effect for a constant force (48 bytes, the union at 16)
   type FF_Effect is record
      Kind       : Unsigned_16 := 16#52#;   --  FF_CONSTANT
      Id         : Integer_16 := -1;        --  -1: new effect
      Direction  : Unsigned_16 := 16#4000#; --  along the wheel's axis
      Trig_Button, Trig_Interval : Unsigned_16 := 0;
      Length, Delay_Ms : Unsigned_16 := 0;  --  0: play until stopped
      Pad        : Unsigned_16 := 0;
      Level      : Integer_16 := 0;
      Rest       : Unsigned_16_Array (1 .. 15) := (others => 0);  --  envelope
   end record
     with Convention => C;
   for FF_Effect'Size use 48 * 8;

   EV_KEY : constant := 1;
   EV_ABS : constant := 3;
   EV_FF  : constant := 16#15#;
   FF_GAIN       : constant := 16#60#;
   FF_AUTOCENTER : constant := 16#61#;

   EVIOCSFF  : constant := 16#4030_4580#;
   EVIOCGABS : constant := 16#8018_4540#;   --  + axis
   EVIOCGNAME_64 : constant := 16#8040_4506#;
   EVIOCGKEY_96  : constant := 16#8060_4518#;

   O_RDWR     : constant := 2;
   O_NONBLOCK : constant := 8#4000#;

   function C_Open (Path : Interfaces.C.char_array; Flags : Interfaces.C.int)
     return Interfaces.C.int with Import, Convention => C, External_Name => "open";
   function C_Close (Fd : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C, External_Name => "close";
   function C_Read (Fd : Interfaces.C.int; Buf : System.Address; N : Interfaces.C.size_t)
     return Interfaces.C.long with Import, Convention => C, External_Name => "read";
   function C_Write (Fd : Interfaces.C.int; Buf : System.Address; N : Interfaces.C.size_t)
     return Interfaces.C.long with Import, Convention => C, External_Name => "write";
   function C_Ioctl (Fd : Interfaces.C.int; Request : Interfaces.C.unsigned_long;
                     Arg : System.Address) return Interfaces.C.int
     with Import, Convention => C, External_Name => "ioctl";

   Fd        : Interfaces.C.int := -1;
   Alive     : Boolean := False;   --  switched on (see Open)
   Current   : Input;
   Pressed   : array (Button) of Boolean := (others => False);
   Queue     : array (1 .. 32) of Button;
   Queued    : Natural := 0;
   Taken     : Natural := 0;
   Effect    : FF_Effect;
   Uploaded  : Boolean := False;
   Sent_Level : Integer_16 := 0;
   Gain      : Float := 0.7;
   Last_Look : Ada.Real_Time.Time := Ada.Real_Time.Time_First;

   --  Axis ranges, read from the device
   type Axis is (Steer_Axis, Clutch_Axis, Throttle_Axis, Brake_Axis);
   Axis_Code : constant array (Axis) of Unsigned_16 := (0, 1, 2, 5);
   Low, High : array (Axis) of Float := (others => 0.0);

   procedure Send (Kind, Code : Unsigned_16; Value : Integer_32) is
      E : Event := (0, 0, Kind, Code, Value);
      R : Interfaces.C.long;
   begin
      R := C_Write (Fd, E'Address, 24);
      pragma Unreferenced (R);
   end Send;

   function Pedal (A : Axis; Raw : Integer_32) return Float is
      --  The pedals report the full range when released
      V : constant Float := (High (A) - Float (Raw)) / Float'Max (1.0, High (A) - Low (A));
   begin
      return Float'Max (0.0, Float'Min (1.0, (V - 0.03) / 0.95));
   end Pedal;

   procedure Close is
      R : Interfaces.C.int;
   begin
      if Fd >= 0 then
         R := C_Close (Fd);
         pragma Unreferenced (R);
      end if;
      Fd := -1;
      Alive := False;
      Uploaded := False;
      Current := (others => <>);
      Pressed := (others => False);
   end Close;

   procedure Key (Code : Unsigned_16; Down : Boolean) is
      procedure Gear (G : Gear_Position) is
      begin
         if Down then
            Current.Shifter := G;
         elsif Current.Shifter = G then
            Current.Shifter := 0;
         end if;
      end Gear;

      procedure Press (B : Button) is
      begin
         if Down and then not Pressed (B) and then Queued < Queue'Last then
            Queued := Queued + 1;
            Queue (Queued) := B;
         end if;
         Pressed (B) := Down;
      end Press;
   begin
      case Code is
         when 16#120# .. 16#12B# =>
            Press (Button'Val (Integer (Code) - 16#120#));
         when 16#12C# .. 16#12F# => Gear (Gear_Position (Integer (Code) - 16#12C# + 1));
         when 16#2C0# => Gear (5);
         when 16#2C1# => Gear (6);
         when 16#2C2# => Gear (-1);
         when 16#2C3# => Press (Plus);
         when 16#2C4# => Press (Minus);
         when 16#2C5# => Press (Dial_Right);
         when 16#2C6# => Press (Dial_Left);
         when 16#2C7# => Press (Enter);
         when 16#2C8# => Press (PS);
         when others => null;
      end case;
   end Key;

   function Try (Path : String) return Boolean is
      Name : Interfaces.C.char_array (1 .. 64) := (others => Interfaces.C.nul);
   begin
      Fd := C_Open (Interfaces.C.To_C (Path), O_RDWR + O_NONBLOCK);
      if Fd < 0 then
         return False;
      end if;
      if C_Ioctl (Fd, EVIOCGNAME_64, Name'Address) < 0 then
         Close;
         return False;
      end if;
      declare
         N : constant String := Interfaces.C.To_Ada (Name);
      begin
         if Ada.Strings.Fixed.Index (N, "Wheel") = 0
           and then Ada.Strings.Fixed.Index (N, "Driving Force") = 0
         then
            Close;
            return False;
         end if;
         Ada.Text_IO.Put_Line ("Wheel: " & N);
      end;
      for A in Axis loop
         declare
            Info : array (1 .. 6) of Integer_32 := (others => 0);
         begin
            if C_Ioctl (Fd, Interfaces.C.unsigned_long (EVIOCGABS) + Interfaces.C.unsigned_long (Axis_Code (A)),
                        Info'Address) = 0
            then
               Low (A) := Float (Info (2));
               High (A) := Float (Info (3));
               case A is
                  when Steer_Axis =>
                     Current.Steering :=
                       (Float (Info (1)) - Low (A)) / Float'Max (1.0, High (A) - Low (A)) * 2.0 - 1.0;
                  when Clutch_Axis   => Current.Clutch := Pedal (A, Info (1));
                  when Throttle_Axis => Current.Throttle := Pedal (A, Info (1));
                  when Brake_Axis    => Current.Brake := Pedal (A, Info (1));
               end case;
            end if;
         end;
      end loop;
      --  A wheel on USB but switched off reports its pedals floored and
      --  sends nothing: it counts once a pedal rests released or it moves
      Alive := Current.Throttle < 0.1 or else Current.Brake < 0.1;
      --  Where the shifter is now (it only reports changes)
      declare
         Bits : array (0 .. 95) of Unsigned_8 := (others => 0);
      begin
         if C_Ioctl (Fd, EVIOCGKEY_96, Bits'Address) >= 0 then
            for Code in 16#12C# .. 16#2C2# loop
               if (Bits (Code / 8) and Shift_Left (1, Code mod 8)) /= 0 then
                  Key (Unsigned_16 (Code), True);
               end if;
            end loop;
         end if;
      end;
      --  We make our own centring force
      Send (EV_FF, FF_AUTOCENTER, 0);
      Set_Gain (Gain);
      Effect.Id := -1;
      Effect.Level := 0;
      if C_Ioctl (Fd, EVIOCSFF, Effect'Address) = 0 then
         Uploaded := True;
         Sent_Level := 0;
         Send (EV_FF, Unsigned_16 (Effect.Id), 1);
      end if;
      return True;
   end Try;

   procedure Open is
      use Ada.Directories;
      Dir : constant String := "/dev/input/by-id";
      S : Search_Type;
      E : Directory_Entry_Type;
   begin
      Last_Look := Ada.Real_Time.Clock;
      if not Exists (Dir) then
         return;
      end if;
      Start_Search (S, Dir, "*-event-joystick");
      while More_Entries (S) loop
         Get_Next_Entry (S, E);
         exit when Try (Full_Name (E));
      end loop;
      End_Search (S);
   exception
      when others => null;
   end Open;

   function Present return Boolean is (Fd >= 0 and then Alive);


   procedure Hat (X : Boolean; V : Integer) is
      procedure Set (B : Button; Down : Boolean) is
      begin
         if Down and then not Pressed (B) and then Queued < Queue'Last then
            Queued := Queued + 1;
            Queue (Queued) := B;
         end if;
         Pressed (B) := Down;
      end Set;
   begin
      if X then
         Current.Hat_X := V;
         Set (Pad_Left, V < 0);
         Set (Pad_Right, V > 0);
      else
         Current.Hat_Y := V;
         Set (Pad_Up, V < 0);
         Set (Pad_Down, V > 0);
      end if;
   end Hat;

   procedure Poll is
      use Ada.Real_Time;
      Buf : Event_Array;
      N   : Interfaces.C.long;
   begin
      Queued := 0;
      Taken := 0;
      if Fd < 0 then
         if Last_Look /= Time_First and then Clock - Last_Look > Seconds (3) then
            Open;
         end if;
         return;
      end if;
      loop
         N := C_Read (Fd, Buf'Address, Buf'Size / 8);
         if N < 0 then
            --  EAGAIN: nothing more; anything else: unplugged
            if GNAT.OS_Lib.Errno /= 11 then
               Ada.Text_IO.Put_Line ("Wheel disconnected");
               Close;
            end if;
            exit;
         elsif N = 0 then
            Close;
            exit;
         end if;
         for I in 1 .. Integer (N) / 24 loop
            declare
               E : Event renames Buf (I);
            begin
               if E.Kind = EV_ABS or else E.Kind = EV_KEY then
                  if not Alive then
                     Ada.Text_IO.Put_Line ("Wheel: switched on");
                  end if;
                  Alive := True;
               end if;
               if E.Kind = EV_ABS then
                  case E.Code is
                     when 0 =>
                        Current.Steering :=
                          (Float (E.Value) - Low (Steer_Axis))
                          / Float'Max (1.0, High (Steer_Axis) - Low (Steer_Axis)) * 2.0 - 1.0;
                     when 1 => Current.Clutch := Pedal (Clutch_Axis, E.Value);
                     when 2 => Current.Throttle := Pedal (Throttle_Axis, E.Value);
                     when 5 => Current.Brake := Pedal (Brake_Axis, E.Value);
                     when 16#10# => Hat (True, Integer (E.Value));
                     when 16#11# => Hat (False, Integer (E.Value));
                     when others => null;
                  end case;
               elsif E.Kind = EV_KEY then
                  Key (E.Code, E.Value /= 0);
               end if;
            end;
         end loop;
         exit when Integer (N) < Buf'Size / 8;
      end loop;
   end Poll;

   function State return Input is (if Alive then Current else (others => <>));

   function Next_Press (B : out Button) return Boolean is
   begin
      if Taken >= Queued then
         B := Cross;
         return False;
      end if;
      Taken := Taken + 1;
      B := Queue (Taken);
      return True;
   end Next_Press;

   function Held (B : Button) return Boolean is (Pressed (B));

   procedure Set_Gain (G : Float) is
   begin
      Gain := Float'Max (0.0, Float'Min (1.0, G));
      if Fd >= 0 then
         Send (EV_FF, FF_GAIN, Integer_32 (Gain * 65535.0));
      end if;
   end Set_Gain;

   procedure Set_Force (Level : Float) is
      --  The G29 turns left for a positive level
      L : constant Integer_16 :=
        Integer_16 (-Float'Max (-1.0, Float'Min (1.0, Level)) * 32767.0);
   begin
      if not Uploaded or else abs (Integer (L) - Integer (Sent_Level)) < 160 then
         return;
      end if;
      Effect.Level := L;
      if C_Ioctl (Fd, EVIOCSFF, Effect'Address) = 0 then
         Sent_Level := L;
      end if;
   end Set_Force;

end Wheel;
