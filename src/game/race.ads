--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Street races through Paris: a few ready-made tracks, a random track
--  around you, and tracks you make yourself (drive and drop the
--  checkpoints).  A track is a loop of points; the race follows the real
--  streets between them.  Five opponents, gates at the checkpoints,
--  spectators at the gates, no other traffic.

with Ada.Strings.Unbounded;

with Car;
with GL;
with Math3D;
with Road_Network;

package Race is

   ---------------------------------------------------------------------------
   --  Tracks
   ---------------------------------------------------------------------------

   function Track_Count return Natural;
   --  The ready-made tracks, then the saved ones
   function Track_Name (I : Positive) return String;

   procedure Load_Saved;
   --  ~/.derive_tracks

   ---------------------------------------------------------------------------
   --  The track editor: drive, and drop checkpoints where you are
   ---------------------------------------------------------------------------

   procedure Edit_Start;
   procedure Edit_Drop (X, Z : Float; Ok : out Boolean);
   --  Not Ok: too close to the one before
   procedure Edit_Undo;
   procedure Edit_Save (Name : out Ada.Strings.Unbounded.Unbounded_String);
   procedure Edit_Cancel;
   function Editing return Boolean;
   function Edit_Points return Natural;

   ---------------------------------------------------------------------------
   --  Racing
   ---------------------------------------------------------------------------

   type Phase_Kind is (Idle, Countdown, Racing, Finished);

   procedure Start (Track : Positive; Player : in out Car.State; Ok : out Boolean);
   --  Build the course and put everyone on the grid
   procedure Start_Random (Near_X, Near_Z : Float; Player : in out Car.State; Ok : out Boolean);

   procedure Restart (Player : in out Car.State; Ok : out Boolean);
   --  The same course again, back on the grid

   procedure Set_Laps (N : Natural);
   --  For the next race; 0: by the length of the track
   function Laps_Setting return Natural;

   procedure Stop;
   --  Give up (or tidy away after the finish)

   function Phase return Phase_Kind;
   function Active return Boolean;   --  not Idle

   procedure Update (Dt : Float; Player : in out Car.State);
   --  Opponents, laps, positions; pushes the player out of opponents

   procedure Impact (Loss : Float);
   --  The player's car lost this much speed (m/s) in a knock this step

   function Damage return Float;      --  0 .. 1
   function Wrecked return Boolean;
   function Power return Float;       --  for Car.Controls (1 outside races)
   function Steer_Pull return Float;  --  for Car.Controls
   function Shake return Float;       --  0 .. ~0.12: the wheel trembles
   function Misfiring return Boolean;

   function Frozen return Boolean;
   --  The player must stay on the grid (the countdown)

   function Next_Gate (X, Z : out Float) return Boolean;
   --  Where to go next (for the GPS)

   procedure Route_To_Gate (X, Z : Float; Route : out Road_Network.Route_Vectors.Vector);
   --  The course from (X, Z) to the next gate, street by street (for the
   --  GPS: the race's own way, not the quickest)

   function Hud_Text return String;
   --  Lap, position, time (Pango markup)

   function Results_Text return String;
   --  The finishing order (Pango markup), when Finished

   function Crowd return Float;
   --  0 .. 1: spectators cheering near you

   function Banner return String;
   --  ... and "FINISHED  2nd" for a while after the finish

   function Seconds_Since_Finish return Float;
   --  "3", "2", "1", "GO!" during the countdown, "" otherwise

   function Warning return String;
   --  "OFF THE COURSE|The course is to your left", "WRONG WAY|Turn round",
   --  or ""

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint; Cam : Math3D.Vec3);
   --  Gates, spectators and the opponents

end Race;
