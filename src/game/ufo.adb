--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;

with Beacon;
with Geo;
with Meshes;
with Shaders;

package body Ufo is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Pi : constant := Ada.Numerics.Pi;

   Gen : Ada.Numerics.Float_Random.Generator;
   function Rnd return Float is (Ada.Numerics.Float_Random.Random (Gen));

   Saucer : Meshes.Mesh;

   type Phase_Kind is (Away, Arriving, Hovering, Leaving);
   Phase   : Phase_Kind := Away;
   Pos     : Vec3 := (0.0, -1000.0, 0.0);
   Target  : Vec3;
   Vel     : Vec3 := (0.0, 0.0, 0.0);
   Clock   : Float := 0.0;
   Timer   : Float := 0.0;
   Spin    : Float := 0.0;
   Near    : Float := 0.0;
   Side    : Float := 0.0;
   Ear_Head : Float := 0.0;
   Rolled_Night : Boolean := False;
   Visit_At : Float := -1.0;
   Last_Hour : Float := -1.0;

   --  What it likes to look at, and how high it is
   type Sight is record
      Lat, Lon : Long_Float;
      Height   : Float;
   end record;
   Sights : constant array (1 .. 7) of Sight :=
     ((48.858222, 2.294500, 330.0),   --  Tour Eiffel
      (48.852970, 2.349900, 90.0),    --  Notre-Dame
      (48.886700, 2.343100, 210.0),   --  Sacré-Cœur, on its hill
      (48.873780, 2.295040, 55.0),    --  Arc de Triomphe
      (48.846200, 2.346100, 85.0),    --  Panthéon
      (48.851000, 2.334800, 75.0),    --  Saint-Sulpice
      (48.865600, 2.321200, 25.0));   --  Concorde

   procedure Create_Mesh is
      use Meshes;
      Segs : constant := 20;
      Mat_Hull  : constant := 15.0;   --  paint (uCarColor): polished metal
      Mat_Glass : constant := 16.0;
      function Ring (R, Y : Float; I : Integer) return Vec3 is
        (R * Cos (2.0 * Pi * Float (I) / Float (Segs)), Y,
         R * Sin (2.0 * Pi * Float (I) / Float (Segs)));
   begin
      Start;
      for I in 0 .. Segs - 1 loop
         --  upper and lower hull, and the dome (faces outwards)
         Quad (Ring (9.0, 0.0, I), Ring (4.5, 1.6, I), Ring (4.5, 1.6, I + 1),
               Ring (9.0, 0.0, I + 1), Mat_Hull);
         Quad (Ring (9.0, 0.0, I + 1), Ring (3.5, -2.0, I + 1), Ring (3.5, -2.0, I),
               Ring (9.0, 0.0, I), Mat_Hull);
         Quad (Ring (3.5, -2.0, I), Ring (3.5, -2.0, I + 1), Ring (0.0, -2.0, I + 1),
               Ring (0.0, -2.0, I), Mat_Hull);
         Quad (Ring (3.2, 1.6, I), Ring (2.0, 3.4, I), Ring (2.0, 3.4, I + 1),
               Ring (3.2, 1.6, I + 1), Mat_Glass);
         Quad (Ring (2.0, 3.4, I), Ring (0.0, 3.9, I), Ring (0.0, 3.9, I + 1),
               Ring (2.0, 3.4, I + 1), Mat_Glass);
      end loop;
      --  lights round the rim: white, red and orange
      for I in 0 .. 11 loop
         declare
            P : constant Vec3 := Ring (9.05, 0.0, I * Segs / 12);
            M : constant Float := (case I mod 3 is when 0 => 18.0, when 1 => 19.0,
                                                   when others => 41.0);
         begin
            Box (P.X - 0.35, P.X + 0.35, -0.3, 0.3, P.Z - 0.35, P.Z + 0.35, M);
         end;
      end loop;
      --  a glowing ring underneath
      for I in 0 .. 7 loop
         declare
            P : constant Vec3 := Ring (2.5, -2.0, I * Segs / 8);
         begin
            Box (P.X - 0.4, P.X + 0.4, -2.15, -1.95, P.Z - 0.4, P.Z + 0.4, 18.0);
         end;
      end loop;
      Finish (Saucer);
      Ada.Numerics.Float_Random.Reset (Gen);
   end Create_Mesh;

   procedure Visit (Listener : Vec3) is
      Best : Natural := 0;
      Best_D : Float := 3000.0;
      X, Z : Long_Float;
      A : constant Float := 2.0 * Pi * Rnd;
   begin
      --  the landmark nearest you, or right above you if none is near
      for I in Sights'Range loop
         Geo.To_Local (Sights (I).Lat, Sights (I).Lon, X, Z);
         declare
            D : constant Float := Length (Vec3'(Float (X), 0.0, Float (Z))
                                          - Vec3'(Listener.X, 0.0, Listener.Z));
         begin
            if D < Best_D then
               Best_D := D;
               Best := I;
               Target := (Float (X), Sights (I).Height + 60.0, Float (Z));
            end if;
         end;
      end loop;
      if Best = 0 then
         Target := (Listener.X + 60.0 * Cos (A), 120.0, Listener.Z + 60.0 * Sin (A));
      end if;
      Pos := Target + Vec3'(4000.0 * Cos (A + 1.0), 700.0, 4000.0 * Sin (A + 1.0));
      Phase := Arriving;
      Timer := 0.0;
   end Visit;

   procedure Update (Dt, Hour, Night : Float; Listener : Vec3) is
   begin
      Clock := Clock + Dt;
      Timer := Timer + Dt;
      Spin := Spin + Dt * (if Phase = Hovering then 1.2 else 3.0);

      --  once a night, maybe: about one night in six
      if Hour > 12.0 and then Hour < 21.0 then
         Rolled_Night := False;
      elsif Hour >= 21.0 and then not Rolled_Night then
         Rolled_Night := True;
         Visit_At := (if Rnd < 0.17 then 22.0 + 4.0 * Rnd else -1.0);
         if Visit_At >= 24.0 then
            Visit_At := Visit_At - 24.0;
         end if;
      end if;
      if Visit_At >= 0.0 and then Phase = Away and then Night > 0.6
        and then Last_Hour >= 0.0 and then Last_Hour < Visit_At and then Hour >= Visit_At
        and then Hour - Last_Hour < 1.0
      then
         Visit_At := -1.0;
         Visit (Listener);
      end if;
      Last_Hour := Hour;

      case Phase is
         when Away =>
            null;
         when Arriving =>
            --  very fast at first, slowing down sharply at the end
            declare
               D : constant Vec3 := Target - Pos;
            begin
               Pos := Pos + Float'Min (1.0, 2.2 * Dt) * D;
               if Length (D) < 2.0 then
                  Phase := Hovering;
                  Timer := 0.0;
               end if;
            end;
         when Hovering =>
            Pos := Target + Vec3'(1.5 * Sin (Clock * 0.7), 1.2 * Sin (Clock * 1.3), 1.5 * Cos (Clock * 0.5));
            if Timer > 50.0 then
               Phase := Leaving;
               Timer := 0.0;
               Vel := (30.0 * (Rnd - 0.5), 40.0, 30.0 * (Rnd - 0.5));
            end if;
         when Leaving =>
            Vel := (1.0 + 3.0 * Dt) * Vel;   --  faster and faster
            Pos := Pos + Dt * Vel;
            if Length (Pos - Listener) > 6000.0 then
               Phase := Away;
               Pos := (0.0, -1000.0, 0.0);
            end if;
      end case;

      if Phase = Away then
         Near := 0.0;
      else
         declare
            D  : constant Vec3 := Pos - Listener;
            DH : constant Float := Float'Max (0.5, Sqrt (D.X * D.X + D.Z * D.Z));
         begin
            Near := Float'Min (1.0, 250.0 / (Length (D) + 50.0));
            Side := (D.X * Cos (Ear_Head) + D.Z * Sin (Ear_Head)) / DH;
         end;
      end if;
   end Update;

   procedure Draw (Model_Loc, Paint_Loc : GL.GLint) is
      use type GL.GLint;
      Tilt : constant Float := (if Phase = Hovering then 0.06 * Sin (Clock * 0.9) else 0.15);
   begin
      if Phase = Away then
         return;
      end if;
      if Paint_Loc >= 0 then
         Shaders.Set (Paint_Loc, Vec3'(0.62, 0.64, 0.68));
      end if;
      Shaders.Set (Model_Loc, Translation (Pos) * Rotation_X (Tilt) * Rotation_Y (Spin));
      Meshes.Draw (Saucer);
   end Draw;

   procedure Draw_Beam (VP : Mat4; Cam : Vec3) is
   begin
      --  the beam shines in the middle of its visit
      if Phase = Hovering and then Timer > 12.0 and then Timer < 38.0 then
         Beacon.Draw_Shaft (VP, Cam, Pos - Vec3'(0.0, 2.0, 0.0),
                            (Pos.X, 0.0, Pos.Z), 3.0, 14.0, (0.6, 1.0, 0.75),
                            0.5 * Float'Min (1.0, Float'Min (Timer - 12.0, 38.0 - Timer)));
      end if;
   end Draw_Beam;

   function In_Beam (X, Z : Float) return Boolean is
     (Phase = Hovering and then Timer > 12.0 and then Timer < 38.0
      and then (X - Pos.X) ** 2 + (Z - Pos.Z) ** 2 < 6.0 ** 2);

   function Nearness return Float is (Near);
   function Pan return Float is (Side);

   procedure Set_Listener_Heading (Heading : Float) is
   begin
      Ear_Head := Heading;
   end Set_Listener_Heading;

end Ufo;
