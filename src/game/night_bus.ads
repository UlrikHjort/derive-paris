--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The night bus: after midnight, a twelve-metre bus along a line of real
--  stops (data/night_bus.txt).  At each stop the night owls wait under the
--  sign; pull in, the doors open, some get off, some get on with a
--  ticket; and the timetable: never leave a stop early, try not to be
--  late, and drive gently, they are tired.  At the terminus the account,
--  and the best run of each line in ~/.derive_nightbus.

with Ada.Strings.Unbounded;

with Car;
with GL;

package Night_Bus is

   type Phase_Kind is (Off, Driving, At_Stop, Done);

   procedure Load;
   function Count return Natural;
   function Name (I : Positive) return String;
   function Best (I : Positive) return Natural;   --  stars (0: none yet)

   procedure Start (I : Positive; Player : out Car.State; Hour : in out Float);
   procedure Again (Player : out Car.State; Hour : in out Float);
   procedure Stop;

   function Phase return Phase_Kind;
   function Active return Boolean;
   function Holding return Boolean;      --  the doors are open: wait
   function Clock_Pace return Float;     --  game hours a second (0: as usual)

   procedure Impact (Loss : Float);

   procedure Update (Dt : Float; Player : Car.State; Hour : Float);

   procedure Goal (Serial : out Natural; X, Z : out Float;
                   Name : out Ada.Strings.Unbounded.Unbounded_String);

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint; Time : Float);
   --  The stops (pole and sign) and the people waiting

   function Hud_Text return String;
   function Banner return String;
   function Panel_Text return String;

end Night_Bus;
