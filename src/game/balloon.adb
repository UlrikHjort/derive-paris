--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;

with Geo;
with Meshes;
with Shaders;
with Terrain;

package body Balloon is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Pi : constant := Ada.Numerics.Pi;

   Site_Lat : constant := 48.840880;
   Site_Lon : constant := 2.274200;

   Top    : constant := 150.0;   --  the gondola's floor at the top
   Down_T : constant := 30.0;    --  seconds on the ground, boarding
   Rise_T : constant := 90.0;    --  up (or down)
   Stay_T : constant := 60.0;    --  at the top

   Placed : Boolean := False;
   Site   : Vec3;
   Clock  : Float := 0.0;
   Lift   : Float := 0.0;        --  the gondola's floor above the ground
   Aboard : Boolean := False;
   Up_Once : Boolean := False;   --  (has it left the ground since boarding?)
   Over   : Boolean := False;
   Sway   : Float := 0.0;

   Envelope_M, Gondola_M, Cable_M : Meshes.Mesh;
   Built : Boolean := False;

   procedure Place is
      X, Z : Long_Float;
   begin
      if not Placed then
         Geo.To_Local (Site_Lat, Site_Lon, X, Z);
         Site := (Float (X), Terrain.Height (Float (X), Float (Z)), Float (Z));
         Placed := True;
      end if;
   end Place;

   function Height_At (C : Float) return Float is
      Cycle : constant Float := Down_T + 2.0 * Rise_T + Stay_T;
      T : constant Float := C - Cycle * Float'Floor (C / Cycle);
      function Ease (U : Float) return Float is (U * U * (3.0 - 2.0 * U));
   begin
      if T < Down_T then
         return 0.0;
      elsif T < Down_T + Rise_T then
         return Top * Ease ((T - Down_T) / Rise_T);
      elsif T < Down_T + Rise_T + Stay_T then
         return Top;
      else
         return Top * (1.0 - Ease ((T - Down_T - Rise_T - Stay_T) / Rise_T));
      end if;
   end Height_At;

   procedure Update (Dt : Float) is
   begin
      Place;
      Clock := Clock + Dt;
      Lift := Height_At (Clock);
      Sway := 0.6 * Sin (Clock * 0.23) * Lift / Top;
      if Aboard then
         if Lift > 1.0 then
            Up_Once := True;
         elsif Up_Once and then Lift = 0.0 then
            Over := True;
         end if;
      end if;
   end Update;

   procedure Mark (X, Z : out Float) is
   begin
      Place;
      X := Site.X + 4.0;
      Z := Site.Z;
   end Mark;

   function At_Mark (X, Z : Float) return Boolean is
      MX, MZ : Float;
   begin
      Mark (MX, MZ);
      return not Aboard and then Lift = 0.0 and then (X - MX) ** 2 + (Z - MZ) ** 2 < 1.5 ** 2;
   end At_Mark;

   procedure Board is
   begin
      Aboard := True;
      Up_Once := False;
      Over := False;
   end Board;

   function Riding return Boolean is (Aboard);

   procedure Ride_Eye (X, Z, Floor_Y : out Float) is
   begin
      X := Site.X + Sway + 1.2;
      Z := Site.Z;
      Floor_Y := Site.Y + Lift + 0.1;
   end Ride_Eye;

   function Landed return Boolean is (Aboard and then Over);

   procedure Alight (X, Z : out Float) is
   begin
      Aboard := False;
      Over := False;
      X := Site.X + 5.5;
      Z := Site.Z + 1.0;
   end Alight;

   procedure Build is
      use Meshes;
      R  : constant Float := 11.0;   --  the envelope's radius
      Cy : constant Float := 17.0;   --  its middle, above the gondola floor
      Segs : constant := 24;
      Rings : constant := 14;
      function P (I, J : Integer) return Vec3 is
         A : constant Float := 2.0 * Pi * Float (I) / Float (Segs);
         E : constant Float := Pi * (Float (J) / Float (Rings) - 0.5);
      begin
         return (R * Cos (E) * Cos (A), Cy + R * Sin (E), R * Cos (E) * Sin (A));
      end P;
   begin
      --  the envelope: in the paint, a white band round the middle
      Start;
      for I in 0 .. Segs - 1 loop
         for J in 0 .. Rings - 1 loop
            declare
               Mid : constant Vec3 := 0.25 * (P (I, J) + P (I + 1, J) + P (I + 1, J + 1) + P (I, J + 1));
               N   : constant Vec3 := Normalize (Mid - Vec3'(0.0, Cy, 0.0));
               M   : constant Float := (if J in 6 .. 7 then 80.0 else Mat_Paint);
            begin
               Quad_UV (P (I, J), P (I + 1, J), P (I + 1, J + 1), P (I, J + 1), N, M, 0.0);
            end;
         end loop;
      end loop;
      --  the net's lines down to the ring over the gondola
      for I in 0 .. 11 loop
         declare
            A : constant Float := 2.0 * Pi * Float (I) / 12.0;
            Q : constant Vec3 := (R * 0.75 * Cos (A), Cy - R * 0.66, R * 0.75 * Sin (A));
            G : constant Vec3 := (3.0 * Cos (A), 2.4, 3.0 * Sin (A));
            Side : constant Vec3 := (0.03 * Sin (A), 0.0, -0.03 * Cos (A));
         begin
            Quad (G - Side, G + Side, Q + Side, Q - Side, 17.0);
            Quad (G + Side, G - Side, Q - Side, Q + Side, 17.0);
         end;
      end loop;
      Finish (Envelope_M);
      --  the gondola: a ring of railing round an open floor
      Start;
      for I in 0 .. 15 loop
         declare
            A0 : constant Float := 2.0 * Pi * Float (I) / 16.0;
            A1 : constant Float := 2.0 * Pi * Float (I + 1) / 16.0;
            P0 : constant Vec3 := (3.0 * Cos (A0), 0.0, 3.0 * Sin (A0));
            P1 : constant Vec3 := (3.0 * Cos (A1), 0.0, 3.0 * Sin (A1));
            U  : constant Vec3 := (0.0, 1.1, 0.0);
         begin
            Quad (P0, P1, P1 + U, P0 + U, 34.0);
            Quad (P1, P0, P0 + U, P1 + U, 34.0);
            Quad ((0.0, 0.0, 0.0), P1, P0, P0, 17.0);
            Quad ((0.0, 0.0, 0.0), P0, P1, P1, 17.0);
         end;
      end loop;
      Box (-0.05, 0.05, 1.1, 2.4, -3.0, -2.9, 26.0);
      Box (-0.05, 0.05, 1.1, 2.4, 2.9, 3.0, 26.0);
      Finish (Gondola_M);
      --  the cable, a metre long (stretched when drawn)
      Start;
      Box (-0.06, 0.06, 0.0, 1.0, -0.06, 0.06, 26.0);
      Finish (Cable_M);
      Built := True;
   end Build;

   procedure Draw (Model, Paint : GL.GLint; Cam : Vec3) is
      Base : Mat4;
   begin
      Place;
      if (Cam.X - Site.X) ** 2 + (Cam.Z - Site.Z) ** 2 > 3000.0 ** 2 then
         return;
      end if;
      if not Built then
         Build;
      end if;
      Base := Translation ((Site.X + Sway, Site.Y + Lift, Site.Z));
      Shaders.Set (Paint, Vec3'(0.12, 0.55, 0.45));   --  sea green, as the real one
      Shaders.Set (Model, Base);
      Meshes.Draw (Envelope_M);
      Meshes.Draw (Gondola_M);
      if Lift > 0.5 then
         Shaders.Set (Model, Translation ((Site.X, Site.Y, Site.Z))
                      * Rotation_Z (-Arctan (Sway, Lift)) * Scale_XYZ (1.0, Lift, 1.0));
         Meshes.Draw (Cable_M);
      end if;
      Shaders.Set (Model, Identity);
   end Draw;

end Balloon;
