--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Time trials (data/trials.txt): from a start to a finish through the
--  real streets, past points on the way, in the traffic, against the
--  clock.  A countdown, then the time runs until you reach the finish;
--  the best time of each run is kept in ~/.derive_trials.

with Ada.Strings.Unbounded;

with Car;
with GL;

package Trials is

   type Phase_Kind is (Off, Countdown, Running, Done);

   procedure Load;
   function Count return Natural;
   function Name (I : Positive) return String;
   function Best (I : Positive) return Float;   --  seconds, 0: none yet

   procedure Start (I : Positive; Player : out Car.State; Hour : in out Float);
   --  Put the car at the start (and the clock at the run's hour, if any)

   procedure Again (Player : out Car.State; Hour : in out Float);
   procedure Stop;

   function Phase return Phase_Kind;
   function Active return Boolean;      --  not Off
   function Holding return Boolean;     --  the countdown: the car must wait

   procedure Update (Dt : Float; Player : Car.State);

   procedure Goal (Serial : out Natural; X, Z : out Float;
                   Name : out Ada.Strings.Unbounded.Unbounded_String);
   --  Where the GPS should take you; Serial changes with the goal

   procedure Draw (Model, Skin : GL.GLint; Time : Float);
   --  The next checkpoint's arrow, and the finish arch across the road

   function Hud_Text return String;      --  the run and the time (markup)
   function Banner return String;        --  the countdown's big number, or ""
   function Panel_Text return String;    --  the result, when Done

end Trials;
