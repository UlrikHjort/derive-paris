--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;

with Collection;
with Era;
with Figures;
with Geo;
with Meshes;
with Shaders;
with Terrain;

package body Hall_F is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Pi : constant := Ada.Numerics.Pi;

   Mat_Stone : constant := 29.0;
   Mat_Floor : constant := 52.0;
   Mat_White : constant := 53.0;
   Mat_Glass : constant := 47.0;   --  the vault's glass, light coming through
   Mat_Gilt  : constant := 48.0;
   Mat_Dark  : constant := 70.0;
   Mat_Iron  : constant := 17.0;
   Mat_Exit  : constant := 49.0;
   Mat_Door  : constant := 17.0;

   --  the nave, along +X from the door: length, half width, the walls'
   --  height and the vault on top
   Len    : constant := 110.0;
   Half   : constant := 18.0;
   Wall_H : constant := 14.0;

   --  the clock room: on the river facade, by its west pavilion (from
   --  OpenStreetMap), facing out at heading 25 degrees
   Face_Lat : constant := 48.860500;
   Face_Lon : constant := 2.325870;
   Face_Heading : constant := 25.0;
   Room_Up  : constant := 24.0;   --  its floor above the street
   Clock_R  : constant := 3.6;

   type Float_Array is array (Positive range <>) of Float;
   type Part_Kind is (Nave, Clock_Room);
   Part : Part_Kind := Nave;

   Origin : Vec3 := (0.0, 0.0, 0.0);
   Hour   : Float := 12.0;
   Last_X, Last_Z : Float := 0.0;
   Nave_M, Room_M, Hand_M, Statue_M : Meshes.Mesh;
   Built, Room_Built : Boolean := False;
   Need  : Boolean := False;

   --  the clock room's frame: its face's middle on the facade, out of it
   --  (to the river), along it, and its floor
   Face_P : Vec3 := (0.0, 0.0, 0.0);
   Out_N, Along : Vec3 := (0.0, 0.0, 0.0);
   Room_Floor : Float := 0.0;

   function G (X, Y, Z : Float) return Vec3 is (Origin + Vec3'(X, Y, Z));

   procedure Place_Room is
      X, Z : Long_Float;
      H : constant Float := Face_Heading * Pi / 180.0;
   begin
      Geo.To_Local (Face_Lat, Face_Lon, X, Z);
      Out_N := (Sin (H), 0.0, -Cos (H));
      Along := (Cos (H), 0.0, Sin (H));
      Room_Floor := Terrain.Height (Float (X), Float (Z)) + Room_Up;
      Face_P := (Float (X), Room_Floor + 3.8, Float (Z));
   end Place_Room;

   --  a point of the clock room: In metres in from the face, Side along it
   function R (In_By, Side, Y : Float) return Vec3 is
     ((Face_P.X - In_By * Out_N.X + Side * Along.X, Room_Floor + Y, Face_P.Z - In_By * Out_N.Z + Side * Along.Z));

   procedure Enter (Origin : Vec3) is
   begin
      Hall_F.Origin := Origin;
      Part := Nave;
      Need := True;
      Last_X := Origin.X + 3.0;
      Last_Z := Origin.Z;
      Place_Room;
   end Enter;

   procedure Entrance (X, Z, Yaw : out Float) is
   begin
      X := Origin.X + 3.0;
      Z := Origin.Z;
      Yaw := Pi / 2.0;
   end Entrance;

   function Floor_Y return Float is (if Part = Nave then Origin.Y else Room_Floor);

   procedure Leave is
   begin
      Era.Set_Cut (False);
      Part := Nave;
   end Leave;

   procedure Keep_Inside (X, Z : in out Float; Yaw : in out Float) is
   begin
      case Part is
         when Nave =>
            declare
               LX : constant Float := X - Origin.X;
               LZ : constant Float := Z - Origin.Z;
            begin
               --  the door under the great clock: up to the clock room
               if LX > Len - 1.5 and then abs LZ < 1.5 then
                  Part := Clock_Room;
                  declare
                     P : constant Vec3 := R (5.0, 0.0, 0.0);
                  begin
                     X := P.X;
                     Z := P.Z;
                     Yaw := Face_Heading * Pi / 180.0;
                  end;
                  Last_X := X;
                  Last_Z := Z;
                  --  the facade cut away before the clock, to see out
                  Era.Set_Cut (True, Face_P.X - 2.5 * Out_N.X, Face_P.Z - 2.5 * Out_N.Z,
                               Arctan (Out_N.Z, Out_N.X) * 180.0 / Pi, 5.0, 7.5, Room_Floor - 0.3);
                  return;
               end if;
               if LX > 0.4 and then LX < Len - 0.4 and then abs LZ < Half - 3.5
                 and then not (abs LZ < 1.2 and then abs ((LX - 15.0) - 10.0 * Float'Rounding ((LX - 15.0) / 10.0)) < 1.0
                               and then LX > 14.0 and then LX < 96.0)   --  the statues' plinths
               then
                  Last_X := X;
                  Last_Z := Z;
               else
                  X := Last_X;
                  Z := Last_Z;
               end if;
            end;
         when Clock_Room =>
            declare
               D : constant Vec3 := Vec3'(X, 0.0, Z) - Vec3'(Face_P.X, 0.0, Face_P.Z);
               In_By : constant Float := -(D.X * Out_N.X + D.Z * Out_N.Z);
               Side  : constant Float := D.X * Along.X + D.Z * Along.Z;
            begin
               --  back down: the door at the back of the room
               if In_By > 6.6 and then abs Side < 1.2 then
                  Leave;
                  X := Origin.X + Len - 4.0;
                  Z := Origin.Z;
                  Yaw := -Pi / 2.0;
                  Last_X := X;
                  Last_Z := Z;
                  return;
               end if;
               if In_By > 0.9 and then In_By < 7.0 and then abs Side < 5.6 then
                  Last_X := X;
                  Last_Z := Z;
               else
                  X := Last_X;
                  Z := Last_Z;
               end if;
            end;
      end case;
   end Keep_Inside;

   function At_Exit (X, Z : Float) return Boolean is
     (Part = Nave and then X - Origin.X < 1.2 and then abs (Z - Origin.Z) < 1.6);

   procedure Update (Dt, Hour : Float) is
      pragma Unreferenced (Dt);
   begin
      Hall_F.Hour := Hour;
   end Update;

   ---------------------------------------------------------------------------

   procedure Face (A, B, C, D, N : Vec3; Mat : Float) is
   begin
      Meshes.Quad_UV (A, B, C, D, N, Mat, 0.0);
   end Face;

   procedure Build_Nave is
      Up : constant Vec3 := (0.0, 1.0, 0.0);
      Segs : constant := 16;
   begin
      Meshes.Start;
      Face (G (0.0, 0.0, -Half), G (0.0, 0.0, Half), G (Len, 0.0, Half), G (Len, 0.0, -Half), Up, Mat_Floor);
      --  the side walls: stone, in three tiers of arches (dark openings)
      for S of Float_Array'(-1.0, 1.0) loop
         declare
            Z : constant Float := S * Half;
            N : constant Vec3 := (0.0, 0.0, -S);
         begin
            Face (G (0.0, 0.0, Z), G (Len, 0.0, Z), G (Len, Wall_H, Z), G (0.0, Wall_H, Z), N, Mat_Stone);
            for K in 0 .. 17 loop
               for Tier in 0 .. 2 loop
                  declare
                     X0 : constant Float := 3.0 + 6.0 * Float (K);
                     Y0 : constant Float := 0.5 + 4.5 * Float (Tier);
                     Zz : constant Float := Z - S * 0.03;
                  begin
                     Face (G (X0, Y0, Zz), G (X0 + 3.6, Y0, Zz), G (X0 + 3.6, Y0 + 3.2, Zz), G (X0, Y0 + 3.2, Zz),
                           N, Mat_Dark);
                  end;
               end loop;
            end loop;
            --  the terraces' edges, stepping in
            Meshes.Box (Origin.X, Origin.X + Len, Origin.Y, Origin.Y + 1.0,
                        Origin.Z + Z - S * 3.5 - 0.3, Origin.Z + Z - S * 3.5 + 0.3, Mat_Stone);
         end;
      end loop;
      --  the vault: half a cylinder of glass, ribs across every 6 m
      for K in 0 .. Segs - 1 loop
         declare
            A0 : constant Float := Pi * Float (K) / Float (Segs);
            A1 : constant Float := Pi * Float (K + 1) / Float (Segs);
            Z0 : constant Float := -Half * Cos (A0);
            Z1 : constant Float := -Half * Cos (A1);
            Y0 : constant Float := Wall_H + Half * Sin (A0);
            Y1 : constant Float := Wall_H + Half * Sin (A1);
            N  : constant Vec3 := (0.0, -Sin ((A0 + A1) / 2.0), Cos ((A0 + A1) / 2.0));
         begin
            Face (G (0.0, Y0, Z0), G (0.0, Y1, Z1), G (Len, Y1, Z1), G (Len, Y0, Z0), N, Mat_Glass);
            for Rib in 0 .. 18 loop
               declare
                  X : constant Float := 6.0 * Float (Rib) - 0.3;
               begin
                  Face (G (X, Y0 - 0.1, Z0), G (X + 0.6, Y0 - 0.1, Z0), G (X + 0.6, Y1 - 0.1, Z1), G (X, Y1 - 0.1, Z1),
                        N, Mat_White);
               end;
            end loop;
         end;
      end loop;
      --  the end walls: the entrance, and the far one with the clock
      Face (G (0.0, 0.0, Half), G (0.0, 0.0, -Half), G (0.0, Wall_H + Half, -Half), G (0.0, Wall_H + Half, Half),
            (1.0, 0.0, 0.0), Mat_Stone);
      Face (G (Len, 0.0, -Half), G (Len, 0.0, Half), G (Len, Wall_H + Half, Half), G (Len, Wall_H + Half, -Half),
            (-1.0, 0.0, 0.0), Mat_Stone);
      Face (G (0.02, 0.0, 1.2), G (0.02, 0.0, -1.2), G (0.02, 2.6, -1.2), G (0.02, 2.6, 1.2), (1.0, 0.0, 0.0), Mat_Door);
      Meshes.Box (Origin.X + 0.03, Origin.X + 0.1, Origin.Y + 2.8, Origin.Y + 3.2, Origin.Z - 0.7, Origin.Z + 0.7,
                  Mat_Exit);
      Face (G (Len - 0.02, 0.0, -1.2), G (Len - 0.02, 0.0, 1.2), G (Len - 0.02, 2.6, 1.2), G (Len - 0.02, 2.6, -1.2),
            (-1.0, 0.0, 0.0), Mat_Door);
      --  the great clock, gilded, high on the far wall
      declare
         C : constant Vec3 := G (Len - 0.2, 20.0, 0.0);
      begin
         for K in 0 .. 47 loop
            declare
               A0 : constant Float := 2.0 * Pi * Float (K) / 48.0;
               A1 : constant Float := 2.0 * Pi * Float (K + 1) / 48.0;
               function P (A, Rad : Float) return Vec3 is (C + Vec3'(0.0, Rad * Cos (A), Rad * Sin (A)));
            begin
               Face (P (A0, 4.4), P (A1, 4.4), P (A1, 5.0), P (A0, 5.0), (-1.0, 0.0, 0.0), Mat_Gilt);
               Face (C, P (A1, 4.4), P (A0, 4.4), P (A0, 4.4), (-1.0, 0.0, 0.0), Mat_White);
            end;
         end loop;
         for H in 0 .. 11 loop
            declare
               A : constant Float := 2.0 * Pi * Float (H) / 12.0;
               P : constant Vec3 := C + Vec3'(-0.05, 3.8 * Cos (A), 3.8 * Sin (A));
            begin
               Meshes.Box (P.X - 0.05, P.X, P.Y - 0.25, P.Y + 0.25, P.Z - 0.25, P.Z + 0.25, Mat_Iron);
            end;
         end loop;
      end;
      Meshes.Finish (Nave_M);

      --  a hand: a bar from the middle up (local +Y), a metre long
      Meshes.Start;
      Meshes.Box (-0.09, 0.09, -0.15, 1.0, -0.04, 0.04, Mat_Iron);
      Meshes.Finish (Hand_M);
      --  a plinth for a statue
      Meshes.Start;
      Meshes.Box (-0.8, 0.8, 0.0, 1.3, -0.8, 0.8, Mat_White);
      Meshes.Finish (Statue_M);
      Built := True;
   end Build_Nave;

   procedure Build_Room is
   begin
      Meshes.Start;
      --  floor, ceiling, back and sides; the front is the clock
      Face (R (0.0, -6.0, 0.0), R (0.0, 6.0, 0.0), R (7.0, 6.0, 0.0), R (7.0, -6.0, 0.0), (0.0, 1.0, 0.0), Mat_Floor);
      Face (R (7.0, -6.0, 7.5), R (7.0, 6.0, 7.5), R (0.0, 6.0, 7.5), R (0.0, -6.0, 7.5), (0.0, -1.0, 0.0), Mat_White);
      Face (R (7.0, 6.0, 0.0), R (7.0, -6.0, 0.0), R (7.0, -6.0, 7.5), R (7.0, 6.0, 7.5), Out_N, Mat_White);
      for S of Float_Array'(-6.0, 6.0) loop
         Face (R (0.0, S, 0.0), R (7.0, S, 0.0), R (7.0, S, 7.5), R (0.0, S, 7.5),
               (if S > 0.0 then (-1.0) * Along else Along), Mat_Stone);
      end loop;
      --  the wall of the front round the clock: stone, with the round hole
      for K in 0 .. 47 loop
         declare
            A0 : constant Float := 2.0 * Pi * Float (K) / 48.0;
            A1 : constant Float := 2.0 * Pi * Float (K + 1) / 48.0;
            function P (A, Rad : Float) return Vec3 is (R (0.0, Rad * Cos (A), 3.8 + Rad * Sin (A)));
            function Edge (A : Float) return Vec3 is
               --  out to the room's rectangle (12 x 7.5) along the ray
               CA : constant Float := Cos (A);
               SA : constant Float := Sin (A);
               T  : constant Float := Float'Min ((if abs CA > 0.01 then 6.0 / abs CA else 99.0),
                                                  (if SA > 0.01 then 3.7 / SA elsif SA < -0.01 then 3.8 / (-SA) else 99.0));
            begin
               return R (0.0, T * CA, 3.8 + T * SA);
            end Edge;
         begin
            Face (P (A0, Clock_R + 0.25), P (A1, Clock_R + 0.25), Edge (A1), Edge (A0), (-1.0) * Out_N, Mat_Stone);
            Face (P (A0, Clock_R), P (A1, Clock_R), P (A1, Clock_R + 0.25), P (A0, Clock_R + 0.25),
                  (-1.0) * Out_N, Mat_Gilt);
         end;
      end loop;
      --  the numerals and the spokes, in dark iron against the light
      for H in 0 .. 11 loop
         declare
            A : constant Float := 2.0 * Pi * Float (H) / 12.0;
         begin
            for K in 0 .. 3 loop
               declare
                  Rr : constant Float := Clock_R - 0.15 - 0.12 * Float (K);
                  P : constant Vec3 := R (0.02, Rr * Cos (A), 3.8 + Rr * Sin (A));
               begin
                  Meshes.Box (P.X - 0.08, P.X + 0.08, P.Y - 0.08, P.Y + 0.08, P.Z - 0.08, P.Z + 0.08, Mat_Iron);
               end;
            end loop;
            declare
               P0 : constant Vec3 := R (0.03, 0.3 * Cos (A), 3.8 + 0.3 * Sin (A));
               P1 : constant Vec3 := R (0.03, (Clock_R - 0.6) * Cos (A), 3.8 + (Clock_R - 0.6) * Sin (A));
               W  : constant Vec3 := 0.025 * Vec3'(-Sin (A) * Along.X, Cos (A), -Sin (A) * Along.Z);
            begin
               Face (P0 - W, P1 - W, P1 + W, P0 + W, (-1.0) * Out_N, Mat_Iron);
            end;
         end;
      end loop;
      Meshes.Finish (Room_M);
      Room_Built := True;
   end Build_Room;

   ---------------------------------------------------------------------------

   function Caption (X, Z, Yaw : Float) return String is
      FX : constant Float := Sin (Yaw);
      FZ : constant Float := -Cos (Yaw);
   begin
      case Part is
         when Nave =>
            if X - Origin.X > Len - 30.0 and then FX > 0.7 then
               return "<span font_family='serif' size='large'><i>" & Collection.Word ("orsay", 1)
                 & "</i></span>" & ASCII.LF & "<span font_family='sans'>" & Collection.Word ("orsay", 4)
                 & "  ·  the door below</span>";
            elsif X - Origin.X < 30.0 then
               return "<span font_family='serif' size='large'><i>" & Collection.Word ("orsay", 1)
                 & "</i></span>" & ASCII.LF & "<span font_family='sans'>" & Collection.Word ("orsay", 2) & "</span>";
            end if;
         when Clock_Room =>
            if FX * Out_N.X + FZ * Out_N.Z > 0.6 then
               return "<span font_family='serif' size='large'><i>" & Collection.Word ("orsay", 4)
                 & "</i></span>" & ASCII.LF
                 & "<span font_family='sans'>La Seine, le Louvre, et au loin le Sacré-Cœur</span>";
            end if;
      end case;
      return "";
   end Caption;

   procedure Draw (Model, Paint, Skin, Legs, Gallery : GL.GLint) is
      Hr : constant Float := Hour - 12.0 * Float'Floor (Hour / 12.0);
      Mn : constant Float := Hour - Float'Floor (Hour);
      Skins : constant Vec3 := (0.82, 0.80, 0.74);   --  marble
   begin
      if Need then
         Need := False;
         if Built then
            Meshes.Free (Nave_M);
            Meshes.Free (Hand_M);
            Meshes.Free (Statue_M);
         end if;
         Build_Nave;
         if Room_Built then
            Meshes.Free (Room_M);
         end if;
         Build_Room;
      end if;
      if not Built then
         return;
      end if;
      Shaders.Set (Gallery, 2.0);
      case Part is
         when Nave =>
            Shaders.Set (Model, Identity);
            Meshes.Draw (Nave_M);
            --  the hands of the great clock (seen from the nave)
            for K in 0 .. 1 loop
               declare
                  A : constant Float := 2.0 * Pi * (if K = 0 then Hr / 12.0 else Mn);
               begin
                  Shaders.Set (Model, Translation (G (Len - 0.4, 20.0, 0.0)) * Rotation_Y (Pi / 2.0)
                               * Rotation_Z (-A) * Scale_XYZ (1.0, (if K = 0 then 2.4 else 3.6), 1.0));
                  Meshes.Draw (Hand_M);
               end;
            end loop;
            --  the statues down the middle, white on their plinths
            Figures.Set_Locations ((Model, Paint, Skin, Legs));
            for K in 0 .. 8 loop
               declare
                  P : constant Vec3 := G (15.0 + 10.0 * Float (K), 0.0, 0.0);
               begin
                  Shaders.Set (Model, Translation (P));
                  Meshes.Draw (Statue_M);
                  Figures.Person (Translation (P + Vec3'(0.0, 1.3, 0.0)) * Rotation_Y (Float (K) * 1.1) * Scale (1.25),
                                  Skins, Skins, Skins, Arm_Up => (if K mod 3 = 0 then -1.8 else 0.0));
               end;
            end loop;
            --  visitors walking slowly
            for K in 0 .. 9 loop
               declare
                  X : constant Float := 8.0 + 9.0 * Float (K);
                  Z : constant Float := (if K mod 2 = 0 then -4.0 else 4.5);
               begin
                  Figures.Person (Translation (G (X, 0.0, Z)) * Rotation_Y (Float (K) * 0.9),
                                  (case K mod 4 is when 0 => (0.15, 0.15, 0.2), when 1 => (0.6, 0.2, 0.2),
                                                   when 2 => (0.85, 0.82, 0.7), when others => (0.25, 0.35, 0.3)),
                                  (0.8, 0.62, 0.5), (0.15, 0.15, 0.2));
               end;
            end loop;
         when Clock_Room =>
            Shaders.Set (Model, Identity);
            Meshes.Draw (Room_M);
            --  the hands, seen from behind: they go round the other way
            for K in 0 .. 1 loop
               declare
                  A : constant Float := 2.0 * Pi * (if K = 0 then Hr / 12.0 else Mn);
               begin
                  Shaders.Set (Model, Translation (R (0.05, 0.0, 3.8)) * Rotation_Y (-Face_Heading * Pi / 180.0)
                               * Rotation_Z (A) * Scale_XYZ (1.0, (if K = 0 then 2.0 else 3.0), 1.0));
                  Meshes.Draw (Hand_M);
               end;
            end loop;
      end case;
      Shaders.Set (Gallery, 0.0);
      Shaders.Set (Model, Identity);
   end Draw;

end Hall_F;
