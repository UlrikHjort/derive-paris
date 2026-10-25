--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions;

with Geo;
with Meshes;
with Shaders;
with Terrain;

package body Funicular is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   --  the two ends of the line, between the stations (from OpenStreetMap)
   Low_Lat  : constant := 48.884640;
   Low_Lon  : constant := 2.342650;
   High_Lat : constant := 48.885690;
   High_Lon : constant := 2.342540;

   Gap      : constant := 1.6;    --  either cabin this far from the middle line
   Trip     : constant := 45.0;   --  seconds up (or down)
   Wait     : constant := 25.0;   --  at the stations, doors open

   Placed : Boolean := False;
   Low, High : Vec3;              --  on the ground at the two ends
   Along, Side : Vec3;            --  up the line (level), across it
   Len    : Float := 0.0;

   Clock  : Float := 0.0;
   T      : Float := 0.0;         --  0 .. 1 how far cabin A is up (B the other way)
   Rider  : Natural := 0;         --  0: not riding; 1: cabin A, 2: cabin B
   From_Low : Boolean := True;
   Done   : Boolean := False;

   Track_M, Cabin_M : Meshes.Mesh;
   type Float_Array is array (Positive range <>) of Float;
   Built : Boolean := False;

   procedure Place is
      X, Z : Long_Float;
   begin
      if Placed then
         return;
      end if;
      Geo.To_Local (Low_Lat, Low_Lon, X, Z);
      Low := (Float (X), 0.0, Float (Z));
      Geo.To_Local (High_Lat, High_Lon, X, Z);
      High := (Float (X), 0.0, Float (Z));
      Low.Y := Terrain.Height (Low.X, Low.Z);
      High.Y := Terrain.Height (High.X, High.Z);
      Len := Sqrt ((High.X - Low.X) ** 2 + (High.Z - Low.Z) ** 2);
      Along := (1.0 / Len) * Vec3'(High.X - Low.X, 0.0, High.Z - Low.Z);
      Side := (-Along.Z, 0.0, Along.X);
      Placed := True;
   end Place;

   --  How far up a cabin is, 0 .. 1, in the cycle (A from the bottom)
   function Phase return Float is
      Cycle : constant Float := 2.0 * (Trip + Wait);
      C : constant Float := Clock - Cycle * Float'Floor (Clock / Cycle);
      function Ease (U : Float) return Float is (U * U * (3.0 - 2.0 * U));
   begin
      if C < Wait then
         return 0.0;
      elsif C < Wait + Trip then
         return Ease ((C - Wait) / Trip);
      elsif C < 2.0 * Wait + Trip then
         return 1.0;
      else
         return 1.0 - Ease ((C - 2.0 * Wait - Trip) / Trip);
      end if;
   end Phase;

   function Stopped return Boolean is (T = 0.0 or else T = 1.0);

   --  A point on the line: S metres up (level distance), across by Off,
   --  at the slope's height
   function On_Line (S, Off : Float) return Vec3 is
      P : constant Vec3 := Low + S * Along + Off * Side;
   begin
      return (P.X, Low.Y + (High.Y - Low.Y) * S / Len, P.Z);
   end On_Line;

   function Cabin_At (K : Positive) return Vec3 is
     (On_Line (Len * (if K = 1 then T else 1.0 - T) * 0.9 + 0.05 * Len,
               (if K = 1 then -Gap else Gap)));

   procedure Update (Dt : Float) is
      Was : constant Float := T;
   begin
      Place;
      Clock := Clock + Dt;
      T := Phase;
      --  arrived: the cabin stopped at the other end
      if Rider /= 0 and then Stopped and then Was /= T then
         Done := True;
      end if;
   end Update;

   function At_Station (X, Z : Float) return Boolean is
      Mark_Low  : constant Vec3 := On_Line (-3.0, 0.0);
      Mark_High : constant Vec3 := On_Line (Len + 3.0, 0.0);
   begin
      Place;
      return Rider = 0 and then Stopped
        and then ((X - Mark_Low.X) ** 2 + (Z - Mark_Low.Z) ** 2 < 1.2 ** 2
                  or else (X - Mark_High.X) ** 2 + (Z - Mark_High.Z) ** 2 < 1.2 ** 2);
   end At_Station;

   procedure Lower_Mark (X, Z : out Float) is
      P : Vec3;
   begin
      Place;
      P := On_Line (-3.0, 0.0);
      X := P.X;
      Z := P.Z;
   end Lower_Mark;

   procedure Board (X, Z : Float) is
      Mark_Low : constant Vec3 := On_Line (-3.0, 0.0);
   begin
      From_Low := (X - Mark_Low.X) ** 2 + (Z - Mark_Low.Z) ** 2 < 4.0 ** 2;
      --  the cabin at this end
      Rider := (if From_Low = (T = 0.0) then 1 else 2);
      Done := False;
   end Board;

   function Riding return Boolean is (Rider /= 0);

   procedure Ride_Eye (X, Z, Floor_Y : out Float) is
      C : constant Vec3 := Cabin_At (Rider);
   begin
      X := C.X;
      Z := C.Z;
      Floor_Y := C.Y + 0.4;
   end Ride_Eye;

   function Arrived return Boolean is (Rider /= 0 and then Done);

   procedure Alight (X, Z : out Float) is
      P : constant Vec3 := (if From_Low then On_Line (Len + 4.5, 0.0) else On_Line (-4.5, 0.0));
   begin
      X := P.X;
      Z := P.Z;
      Rider := 0;
      Done := False;
   end Alight;

   procedure Build is
      use Meshes;
      Steps : constant := 12;
   begin
      --  the track: a stone bed up the slope, two pairs of rails, the
      --  stations' platforms at either end
      Start;
      for K in 0 .. Steps - 1 loop
         declare
            S0 : constant Float := Len * Float (K) / Float (Steps);
            S1 : constant Float := Len * Float (K + 1) / Float (Steps);
         begin
            Quad (On_Line (S0, -3.2) + Vec3'(0.0, 0.05, 0.0), On_Line (S0, 3.2) + Vec3'(0.0, 0.05, 0.0),
                  On_Line (S1, 3.2) + Vec3'(0.0, 0.05, 0.0), On_Line (S1, -3.2) + Vec3'(0.0, 0.05, 0.0), 29.0);
            for R of Float_Array'(-Gap - 0.7, -Gap + 0.7, Gap - 0.7, Gap + 0.7) loop
               Quad (On_Line (S0, R - 0.04) + Vec3'(0.0, 0.15, 0.0), On_Line (S0, R + 0.04) + Vec3'(0.0, 0.15, 0.0),
                     On_Line (S1, R + 0.04) + Vec3'(0.0, 0.15, 0.0), On_Line (S1, R - 0.04) + Vec3'(0.0, 0.15, 0.0),
                     26.0);
            end loop;
         end;
      end loop;
      Finish (Track_M);

      --  a cabin: a dark frame, a low wall all round, corner and middle
      --  posts holding the roof, open between them so you see out (front
      --  is +X up the slope, made level; tilted when drawn)
      Start;
      Box (-2.6, 2.6, 0.0, 0.4, -1.1, 1.1, 17.0);                       --  the floor's frame
      Box (-2.6, 2.6, 0.4, 1.3, -1.1, -1.0, Mat_Paint);                 --  low walls
      Box (-2.6, 2.6, 0.4, 1.3, 1.0, 1.1, Mat_Paint);
      Box (-2.6, -2.5, 0.4, 1.3, -1.1, 1.1, Mat_Paint);
      Box (2.5, 2.6, 0.4, 1.3, -1.1, 1.1, Mat_Paint);
      for PX of Float_Array'(-2.55, 0.0, 2.55) loop
         for PZ of Float_Array'(-1.05, 1.05) loop
            Box (PX - 0.06, PX + 0.06, 1.3, 2.7, PZ - 0.05, PZ + 0.05, Mat_Paint);
         end loop;
      end loop;
      Box (-2.65, 2.65, 2.7, 2.9, -1.15, 1.15, Mat_Paint);              --  the roof
      Box (-0.9, 0.9, 2.9, 3.1, -0.5, 0.5, 18.0);                       --  the lamp on top
      Finish (Cabin_M);
      Built := True;
   end Build;

   procedure Draw (Model, Paint : GL.GLint; Cam : Vec3) is
      Slope : Float;
   begin
      Place;
      if (Cam.X - Low.X) ** 2 + (Cam.Z - Low.Z) ** 2 > 700.0 ** 2 then
         return;
      end if;
      if not Built then
         Build;
      end if;
      Slope := Arctan ((High.Y - Low.Y) / Len);
      Shaders.Set (Model, Identity);
      Meshes.Draw (Track_M);
      Shaders.Set (Paint, Vec3'(0.12, 0.28, 0.25));   --  a dark Paris green
      for K in 1 .. 2 loop
         declare
            C : constant Vec3 := Cabin_At (K);
         begin
            Shaders.Set (Model, Translation (C + Vec3'(0.0, 0.2, 0.0))
                         * Rotation_Y (-Arctan (Along.Z, Along.X)) * Rotation_Z (Slope));
            Meshes.Draw (Cabin_M);
         end;
      end loop;
      Shaders.Set (Model, Identity);
   end Draw;

end Funicular;
