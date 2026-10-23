--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Taxi!  Someone waves at the kerb not far away: pick them up and drive
--  them to a real place in Paris.  The meter runs (day and night tariffs),
--  a bonus counts down from the moment they get in, and every passenger
--  has a mind of their own: the businessman wants speed, the old lady
--  wants a gentle ride.  The speed limits are the real ones, and now and
--  then the police stand by the road with a speed gun.  After each ride:
--  the next fare, or the end of the shift.

with Ada.Strings.Unbounded;

with Car;
with GL;

package Taxi is

   type Phase_Kind is
     (Off,
      Finding,    --  a fare is waiting at the kerb
      Carrying,   --  on the way to the destination
      Paid,       --  the ride is done: next fare or end of the shift?
      Summary);   --  the shift is over

   procedure Start_Shift (Player : Car.State);
   procedure Next_Fare (Player : Car.State);   --  from Paid
   procedure End_Shift;                        --  to Summary
   procedure Close;                            --  back to free driving

   function Phase return Phase_Kind;
   function Active return Boolean;             --  not Off

   procedure Impact (Loss : Float);
   --  The car lost this much speed (m/s) in a knock this step

   procedure Update (Dt : Float; Player : Car.State; Hour : Float; Sunday : Boolean; Rain : Float := 0.0);
   --  Rain (0 .. 1): more people want a taxi, and they tip better

   procedure Goal (Serial : out Natural; X, Z : out Float;
                   Name : out Ada.Strings.Unbounded.Unbounded_String);
   --  Where the GPS should take you; Serial changes when the goal does
   --  (0: none)

   function Hud_Text return String;      --  Pango markup
   function Panel_Text return String;    --  the ride or the shift, when Paid / Summary
   function Warning return String;       --  "!TITLE|text" for a while after a fine

   function Limit return Natural;        --  the speed limit here (0: unknown)
   function Over_Limit return Boolean;   --  too fast just now

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint; Player : Car.State; Time : Float);
   --  The fare at the kerb, the police, and the sign on the roof of your
   --  taxi (green: free, red: taken)

end Taxi;
