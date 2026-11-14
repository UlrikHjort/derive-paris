--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Directories;
with Ada.Real_Time;
with Ada.Strings.Fixed;
with GNAT.OS_Lib;
with Interfaces;
with Interfaces.C;
with System;

with Notes;

package body Gamepad is

   use Interfaces;
   use Wheel;
   use type Interfaces.C.int;
   use type Interfaces.C.long;
   use type Interfaces.C.unsigned_long;
   use type Interfaces.C.size_t;

   type Event is record
      Sec, Usec : Interfaces.C.long;
      Kind      : Unsigned_16;
      Code      : Unsigned_16;
      Value     : Integer_32;
   end record
     with Convention => C;
   for Event'Size use 24 * 8;
   type Event_Array is array (1 .. 64) of Event with Convention => C;

   EV_KEY : constant := 1;
   EV_ABS : constant := 3;
   EVIOCGABS     : constant := 16#8018_4540#;   --  + axis
   EVIOCGNAME_64 : constant := 16#8040_4506#;
   EVIOCGBIT_KEY : constant := 16#8060_4521#;   --  96 bytes of key bits
   BTN_SOUTH     : constant := 16#130#;
   O_RDONLY   : constant := 0;
   O_NONBLOCK : constant := 8#4000#;

   function C_Open (Path : Interfaces.C.char_array; Flags : Interfaces.C.int)
     return Interfaces.C.int with Import, Convention => C, External_Name => "open";
   function C_Close (Fd : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C, External_Name => "close";
   function C_Read (Fd : Interfaces.C.int; Buf : System.Address; N : Interfaces.C.size_t)
     return Interfaces.C.long with Import, Convention => C, External_Name => "read";
   function C_Ioctl (Fd : Interfaces.C.int; Request : Interfaces.C.unsigned_long;
                     Arg : System.Address) return Interfaces.C.int
     with Import, Convention => C, External_Name => "ioctl";

   Fd        : Interfaces.C.int := -1;
   Current   : Input;
   Pressed   : array (Button) of Boolean := (others => False);
   Queue     : array (1 .. 32) of Button;
   Queued    : Natural := 0;
   Taken     : Natural := 0;
   Last_Look : Ada.Real_Time.Time := Ada.Real_Time.Time_First;

   --  Axis ranges, read from the device (codes 0 .. 16#13#)
   Low, High : array (Unsigned_16 range 0 .. 16#13#) of Float := (others => 0.0);
   Has_Axis  : array (Unsigned_16 range 0 .. 16#13#) of Boolean := (others => False);
   --  An axis resting at its low end is a trigger; one resting in the
   --  middle is a stick (Z and RZ are the right stick on some pads)
   Is_Trigger : array (Unsigned_16 range 0 .. 16#13#) of Boolean := (others => False);
   Rest      : Input;   --  how the pad lies untouched

   procedure Close is
      R : Interfaces.C.int;
   begin
      if Fd >= 0 then
         R := C_Close (Fd);
         pragma Unreferenced (R);
      end if;
      Fd := -1;
      Current := (others => <>);
      Pressed := (others => False);
   end Close;

   --  A stick: -1 .. 1, with a dead zone in the middle
   function Stick (Code : Unsigned_16; Raw : Integer_32) return Float is
      Mid  : constant Float := (Low (Code) + High (Code)) / 2.0;
      Half : constant Float := Float'Max (1.0, (High (Code) - Low (Code)) / 2.0);
      V    : constant Float := Float'Max (-1.0, Float'Min (1.0, (Float (Raw) - Mid) / Half));
      Dead : constant := 0.15;
   begin
      if abs V < Dead then
         return 0.0;
      end if;
      return (if V > 0.0 then (V - Dead) / (1.0 - Dead) else (V + Dead) / (1.0 - Dead));
   end Stick;

   function Trigger (Code : Unsigned_16; Raw : Integer_32) return Float is
      V : constant Float := (Float (Raw) - Low (Code)) / Float'Max (1.0, High (Code) - Low (Code));
   begin
      return Float'Max (0.0, Float'Min (1.0, (V - 0.04) / 0.96));
   end Trigger;

   procedure Set (B : Button; Down : Boolean) is
   begin
      if Down and then not Pressed (B) and then Queued < Queue'Last then
         Queued := Queued + 1;
         Queue (Queued) := B;
      end if;
      Pressed (B) := Down;
   end Set;

   procedure Key (Code : Unsigned_16; Down : Boolean) is
   begin
      case Code is
         when 16#130# => Set (Cross, Down);          --  A / south
         when 16#131# => Set (Circle, Down);         --  B / east
         when 16#133# => Set (Square, Down);         --  X
         when 16#134# => Set (Triangle, Down);       --  Y
         when 16#136# => Set (Paddle_Left, Down);    --  LB
         when 16#137# => Set (Paddle_Right, Down);   --  RB
         when 16#13A# => Set (Share, Down);          --  back / view
         when 16#13B# => Set (Options, Down);        --  start / menu
         when 16#13C# => Set (PS, Down);             --  guide / Steam
         when 16#13D# => Set (L3, Down);
         when 16#13E# => Set (R3, Down);
         when 16#220# => Set (Pad_Up, Down);         --  a d-pad of buttons
         when 16#221# => Set (Pad_Down, Down);
         when 16#222# => Set (Pad_Left, Down);
         when 16#223# => Set (Pad_Right, Down);
         when others => null;
      end case;
   end Key;

   procedure Axis_Value (Code : Unsigned_16; Raw : Integer_32) is
   begin
      case Code is
         when 0 => Current.Left_X := Stick (Code, Raw);
         when 1 => Current.Left_Y := Stick (Code, Raw);
         when 3 => Current.Right_X := Stick (Code, Raw);
         when 4 => Current.Right_Y := Stick (Code, Raw);
         --  the triggers: Z and RZ on most pads, HAT2Y / HAT2X on hid-steam,
         --  BRAKE / GAS on Android pads; or Z and RZ are the right stick
         when 2 =>
            if Is_Trigger (Code) then
               Current.Left_Trigger := Trigger (Code, Raw);
            else
               Current.Right_X := Stick (Code, Raw);
            end if;
         when 5 =>
            if Is_Trigger (Code) then
               Current.Right_Trigger := Trigger (Code, Raw);
            else
               Current.Right_Y := Stick (Code, Raw);
            end if;
         when 16#A# | 16#13# => Current.Left_Trigger := Trigger (Code, Raw);
         when 9 | 16#12# => Current.Right_Trigger := Trigger (Code, Raw);
         when 16#10# =>
            Set (Pad_Left, Raw < 0);
            Set (Pad_Right, Raw > 0);
         when 16#11# =>
            Set (Pad_Up, Raw < 0);
            Set (Pad_Down, Raw > 0);
         when others => null;
      end case;
   end Axis_Value;

   function Try (Path : String) return Boolean is
      Name : Interfaces.C.char_array (1 .. 64) := (others => Interfaces.C.nul);
      Bits : array (0 .. 95) of Unsigned_8 := (others => 0);
   begin
      Fd := C_Open (Interfaces.C.To_C (Path), O_RDONLY + O_NONBLOCK);
      if Fd < 0 then
         return False;
      end if;
      if C_Ioctl (Fd, EVIOCGNAME_64, Name'Address) < 0
        or else C_Ioctl (Fd, EVIOCGBIT_KEY, Bits'Address) < 0
        or else (Bits (BTN_SOUTH / 8) and Shift_Left (1, BTN_SOUTH mod 8)) = 0
      then
         Close;
         return False;
      end if;
      declare
         N : constant String := Interfaces.C.To_Ada (Name);
      begin
         if Ada.Strings.Fixed.Index (N, "Wheel") > 0
           or else Ada.Strings.Fixed.Index (N, "Driving Force") > 0
         then
            Close;
            return False;
         end if;
         Notes.Say ("Game controller: " & N);
      end;
      for Code in Low'Range loop
         declare
            Info : array (1 .. 6) of Integer_32 := (others => 0);
         begin
            Has_Axis (Code) := False;
            if C_Ioctl (Fd, Interfaces.C.unsigned_long (EVIOCGABS) + Interfaces.C.unsigned_long (Code),
                        Info'Address) = 0 and then Info (3) > Info (2)
            then
               Has_Axis (Code) := True;
               Low (Code) := Float (Info (2));
               High (Code) := Float (Info (3));
               Is_Trigger (Code) :=
                 Float (Info (1)) - Low (Code) < 0.2 * (High (Code) - Low (Code));
               Axis_Value (Code, Info (1));
            end if;
         end;
      end loop;
      Rest := Current;
      Queued := 0;
      return True;
   end Try;

   procedure Open is
      use Ada.Directories;
      S : Search_Type;
      E : Directory_Entry_Type;
   begin
      Last_Look := Ada.Real_Time.Clock;
      if not Exists ("/dev/input") then
         return;
      end if;
      --  (all of them: Steam Input's pad is made up and has no by-id name)
      Start_Search (S, "/dev/input", "event*");
      while More_Entries (S) loop
         Get_Next_Entry (S, E);
         exit when Try (Full_Name (E));
      end loop;
      End_Search (S);
   exception
      when others => null;
   end Open;

   function Present return Boolean is (Fd >= 0);
   function State return Input is (Current);

   --  (against how it lay when found: a pad whose axes rest off the middle
   --  does not take over by itself)
   function Touched return Boolean is
     (Fd >= 0 and then
        (abs (Current.Left_X - Rest.Left_X) > 0.25 or else abs (Current.Left_Y - Rest.Left_Y) > 0.25
         or else abs (Current.Right_X - Rest.Right_X) > 0.25
         or else abs (Current.Right_Y - Rest.Right_Y) > 0.25
         or else Current.Left_Trigger - Rest.Left_Trigger > 0.2
         or else Current.Right_Trigger - Rest.Right_Trigger > 0.2));

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
            if GNAT.OS_Lib.Errno /= 11 then
               Notes.Say ("Game controller disconnected");
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
               if E.Kind = EV_ABS and then E.Code in Low'Range and then Has_Axis (E.Code) then
                  Axis_Value (E.Code, E.Value);
               elsif E.Kind = EV_KEY then
                  Key (E.Code, E.Value /= 0);
               end if;
            end;
         end loop;
         exit when Integer (N) < Buf'Size / 8;
      end loop;
   end Poll;

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

end Gamepad;
