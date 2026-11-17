--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Real_Time;
with Ada.Strings.Fixed;
with GNAT.OS_Lib;
with Interfaces;
with Interfaces.C;
with System.Storage_Elements;
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

   --  Steam Input shows one controller as several virtual pads, and only
   --  one of them gets its input: all of them are read, and the one that
   --  sent something last is the one that counts
   Max_Pads : constant := 8;
   type Axis_Floats is array (Unsigned_16 range 0 .. 16#13#) of Float;
   type Axis_Flags is array (Unsigned_16 range 0 .. 16#13#) of Boolean;
   type Pad is record
      Fd        : Interfaces.C.int := -1;
      Low, High : Axis_Floats := (others => 0.0);   --  axis ranges, read from the device
      Has_Axis  : Axis_Flags := (others => False);
      --  An axis resting at its low end is a trigger; one resting in the
      --  middle is a stick (Z and RZ are the right stick on some pads)
      Is_Trigger : Axis_Flags := (others => False);
   end record;
   Pads   : array (1 .. Max_Pads) of Pad;
   N_Pads : Natural := 0;
   --  One state for all of them: each pad's events are interpreted with that
   --  pad's own ranges, but written into the same state, so a button that
   --  Steam puts on a different virtual pad than the sticks cannot steal the
   --  input away (picking "the pad that sent something last" drops the
   --  sticks the moment another pad blips)
   Current : Input;
   Rest    : Input;   --  how the pad lies untouched

   Pressed   : array (Button) of Boolean := (others => False);
   Queue     : array (1 .. 32) of Button;
   Queued    : Natural := 0;
   Taken     : Natural := 0;
   Last_Look : Ada.Real_Time.Time := Ada.Real_Time.Time_First;

   procedure Close_All is
      R : Interfaces.C.int;
      pragma Unreferenced (R);
   begin
      for P of Pads (1 .. N_Pads) loop
         R := C_Close (P.Fd);
      end loop;
      N_Pads := 0;
      Current := (others => <>);
      Pressed := (others => False);
   end Close_All;

   --  A stick: -1 .. 1, with a dead zone in the middle
   function Stick (P : Pad; Code : Unsigned_16; Raw : Integer_32) return Float is
      Mid  : constant Float := (P.Low (Code) + P.High (Code)) / 2.0;
      Half : constant Float := Float'Max (1.0, (P.High (Code) - P.Low (Code)) / 2.0);
      V    : constant Float := Float'Max (-1.0, Float'Min (1.0, (Float (Raw) - Mid) / Half));
      Dead : constant := 0.15;
   begin
      if abs V < Dead then
         return 0.0;
      end if;
      return (if V > 0.0 then (V - Dead) / (1.0 - Dead) else (V + Dead) / (1.0 - Dead));
   end Stick;

   function Trigger (P : Pad; Code : Unsigned_16; Raw : Integer_32) return Float is
      V : constant Float :=
        (Float (Raw) - P.Low (Code)) / Float'Max (1.0, P.High (Code) - P.Low (Code));
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

   procedure Axis_Value (P : in out Pad; Code : Unsigned_16; Raw : Integer_32) is
   begin
      case Code is
         when 0 => Current.Left_X := Stick (P, Code, Raw);
         when 1 => Current.Left_Y := Stick (P, Code, Raw);
         when 3 => Current.Right_X := Stick (P, Code, Raw);
         when 4 => Current.Right_Y := Stick (P, Code, Raw);
         --  the triggers: Z and RZ on most pads, HAT2Y / HAT2X on hid-steam,
         --  BRAKE / GAS on Android pads; or Z and RZ are the right stick
         when 2 =>
            if P.Is_Trigger (Code) then
               Current.Left_Trigger := Trigger (P, Code, Raw);
            else
               Current.Right_X := Stick (P, Code, Raw);
            end if;
         when 5 =>
            if P.Is_Trigger (Code) then
               Current.Right_Trigger := Trigger (P, Code, Raw);
            else
               Current.Right_Y := Stick (P, Code, Raw);
            end if;
         when 16#A# | 16#13# => Current.Left_Trigger := Trigger (P, Code, Raw);
         when 9 | 16#12# => Current.Right_Trigger := Trigger (P, Code, Raw);
         when 16#10# =>
            Set (Pad_Left, Raw < 0);
            Set (Pad_Right, Raw > 0);
         when 16#11# =>
            Set (Pad_Up, Raw < 0);
            Set (Pad_Down, Raw > 0);
         when others => null;
      end case;
   end Axis_Value;

   --  Is Path a game pad (it has the south button, and is not a wheel)?
   --  If so it is added to Pads.
   procedure Try (Path : String) is
      Name : Interfaces.C.char_array (1 .. 64) := (others => Interfaces.C.nul);
      Bits : array (0 .. 95) of Unsigned_8 := (others => 0);
      Fd   : constant Interfaces.C.int := C_Open (Interfaces.C.To_C (Path), O_RDONLY + O_NONBLOCK);
      R    : Interfaces.C.int;
   begin
      if Fd < 0 then
         return;
      end if;
      if N_Pads = Max_Pads
        or else C_Ioctl (Fd, EVIOCGNAME_64, Name'Address) < 0
        or else C_Ioctl (Fd, EVIOCGBIT_KEY, Bits'Address) < 0
        or else (Bits (BTN_SOUTH / 8) and Shift_Left (1, BTN_SOUTH mod 8)) = 0
        or else Ada.Strings.Fixed.Index (Interfaces.C.To_Ada (Name), "Wheel") > 0
        or else Ada.Strings.Fixed.Index (Interfaces.C.To_Ada (Name), "Driving Force") > 0
      then
         R := C_Close (Fd);
         pragma Unreferenced (R);
         return;
      end if;
      Notes.Say ("Game controller: " & Interfaces.C.To_Ada (Name) & " (" & Path & ")");
      N_Pads := N_Pads + 1;
      declare
         P : Pad renames Pads (N_Pads);
      begin
         P := (Fd => Fd, others => <>);
         for Code in P.Low'Range loop
            declare
               Info : array (1 .. 6) of Integer_32 := (others => 0);
            begin
               if C_Ioctl (Fd, Interfaces.C.unsigned_long (EVIOCGABS) + Interfaces.C.unsigned_long (Code),
                           Info'Address) = 0 and then Info (3) > Info (2)
               then
                  P.Has_Axis (Code) := True;
                  P.Low (Code) := Float (Info (2));
                  P.High (Code) := Float (Info (3));
                  P.Is_Trigger (Code) :=
                    Float (Info (1)) - P.Low (Code) < 0.2 * (P.High (Code) - P.Low (Code));
                  Axis_Value (P, Code, Info (1));
               end if;
            end;
         end loop;
         Rest := Current;
      end;
      Queued := 0;
   end Try;

   --  (opendir and readdir: Ada.Directories gives up on the whole of
   --  /dev/input over one entry it cannot look at)
   function C_Opendir (Path : Interfaces.C.char_array) return System.Address
     with Import, Convention => C, External_Name => "opendir";
   function C_Readdir (Dir : System.Address) return System.Address
     with Import, Convention => C, External_Name => "readdir";
   function C_Closedir (Dir : System.Address) return Interfaces.C.int
     with Import, Convention => C, External_Name => "closedir";
   Name_Offset : constant := 19;   --  struct dirent's d_name, on Linux

   procedure Open is
      use type System.Address;
      Dir : System.Address;
      R   : Interfaces.C.int;
   begin
      Last_Look := Ada.Real_Time.Clock;
      Dir := C_Opendir (Interfaces.C.To_C ("/dev/input"));
      if Dir = System.Null_Address then
         return;
      end if;
      --  (all of them: Steam Input's pads are made up and have no by-id name)
      loop
         declare
            use System.Storage_Elements;
            Entry_Address : constant System.Address := C_Readdir (Dir);
         begin
            exit when Entry_Address = System.Null_Address;
            declare
               Chars : Interfaces.C.char_array (0 .. 255)
                 with Import, Address => Entry_Address + Storage_Offset (Name_Offset);
               Name : constant String := Interfaces.C.To_Ada (Chars);
            begin
               if Name'Length > 5 and then Name (Name'First .. Name'First + 4) = "event" then
                  Try ("/dev/input/" & Name);
               end if;
            end;
         end;
      end loop;
      R := C_Closedir (Dir);
      pragma Unreferenced (R);
   exception
      when others => null;
   end Open;

   function Present return Boolean is (N_Pads > 0);
   function State return Input is (Current);

   --  (against how it lay when found: a pad whose axes rest off the middle
   --  does not take over by itself)
   function Touched return Boolean is
   begin
      return abs (Current.Left_X - Rest.Left_X) > 0.25
        or else abs (Current.Left_Y - Rest.Left_Y) > 0.25
        or else abs (Current.Right_X - Rest.Right_X) > 0.25
        or else abs (Current.Right_Y - Rest.Right_Y) > 0.25
        or else Current.Left_Trigger - Rest.Left_Trigger > 0.2
        or else Current.Right_Trigger - Rest.Right_Trigger > 0.2;
   end Touched;

   procedure Poll is
      use Ada.Real_Time;
      Buf  : Event_Array;
      N    : Interfaces.C.long;
      Lost : Boolean := False;
   begin
      Queued := 0;
      Taken := 0;
      if N_Pads = 0 then
         if Last_Look /= Time_First and then Clock - Last_Look > Seconds (3) then
            Open;
         end if;
         return;
      end if;
      for K in 1 .. N_Pads loop
         Lost := False;   --  one pad going away does not mean the rest have
         loop
            N := C_Read (Pads (K).Fd, Buf'Address, Buf'Size / 8);
            if N < 0 then
               Lost := GNAT.OS_Lib.Errno /= 11;   --  EAGAIN: nothing more
               exit;
            elsif N = 0 then
               Lost := True;
               exit;
            end if;
            for I in 1 .. Integer (N) / 24 loop
               declare
                  E : Event renames Buf (I);
               begin
                  if E.Kind = EV_ABS and then E.Code in Pads (K).Low'Range
                    and then Pads (K).Has_Axis (E.Code)
                  then
                     Axis_Value (Pads (K), E.Code, E.Value);
                  elsif E.Kind = EV_KEY then
                     Key (E.Code, E.Value /= 0);
                  end if;
               end;
            end loop;
            exit when Integer (N) < Buf'Size / 8;
         end loop;
         exit when Lost;
      end loop;
      --  one unplugged: look again for all of them
      if Lost then
         Notes.Say ("Game controller disconnected");
         Close_All;
         Last_Look := Clock;
      end if;
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
