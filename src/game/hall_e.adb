--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;

with Collection;
with Figures;
with Meshes;
with Shaders;

package body Hall_E is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Pi : constant := Ada.Numerics.Pi;

   Mat_White   : constant := 53.0;
   Mat_Floor   : constant := 52.0;
   Mat_Sky     : constant := 47.0;   --  the light through the velum
   Mat_Lilies  : constant := 94.0;
   Mat_Manner  : constant := 95.0;
   Mat_Wood    : constant := 13.0;
   Mat_Exit    : constant := 49.0;
   Mat_Door    : constant := 17.0;

   --  the plan, along +X from the door (Z across): the vestibule, the two
   --  ovals with a passage between, a stair down to the gallery
   Oval_A, Oval_B : constant := 11.5;   --  half the long and the short axis
   Oval_Short     : constant := 7.5;
   C1 : constant := 18.0;               --  the ovals' middles
   C2 : constant := 47.0;
   G0 : constant := 62.0;               --  the gallery, X G0 .. G1, |Z| < GW
   G1 : constant := 92.0;
   GW : constant := 7.0;
   Height : constant := 5.5;

   Origin : Vec3 := (0.0, 0.0, 0.0);
   Clock  : Float := 0.0;
   Last_X, Last_Z : Float := 0.0;       --  the last place that was inside
   Hall   : Meshes.Mesh;
   Built  : Boolean := False;
   Need   : Boolean := False;

   --  the paintings in the gallery: where (hall coordinates), which way
   type Hung is record
      C : Vec3;
      N : Vec3;
      Work : Positive;
   end record;
   Hung_Works : array (1 .. 24) of Hung;
   N_Hung : Natural := 0;

   function G (X, Y, Z : Float) return Vec3 is (Origin + Vec3'(X, Y, Z));

   function In_Oval (X, Z, C : Float) return Boolean is
     (((X - C) / (Oval_A - 0.5)) ** 2 + (Z / (Oval_Short - 0.5)) ** 2 < 1.0);

   --  Is a point of the hall's floor (hall coordinates) inside?
   function Inside (X, Z : Float) return Boolean is
     ((X > 0.4 and then X < 7.0 and then abs Z < 2.0)
      or else In_Oval (X, Z, C1) or else In_Oval (X, Z, C2)
      or else (X > 28.5 and then X < 36.5 and then abs Z < 1.3)
      or else (X > 57.5 and then X < 63.0 and then abs Z < 1.3)
      or else (X > G0 + 0.4 and then X < G1 - 0.4 and then abs Z < GW - 0.4));

   procedure Enter (Origin : Vec3) is
   begin
      Hall_E.Origin := Origin;
      Need := True;
      Last_X := Origin.X + 3.0;
      Last_Z := Origin.Z;
   end Enter;

   procedure Entrance (X, Z, Yaw : out Float) is
   begin
      X := Origin.X + 3.0;
      Z := Origin.Z;
      Yaw := Pi / 2.0;
   end Entrance;

   function Floor_Y return Float is (Origin.Y);

   procedure Keep_Inside (X, Z : in out Float) is
   begin
      if Inside (X - Origin.X, Z - Origin.Z) then
         Last_X := X;
         Last_Z := Z;
      else
         X := Last_X;
         Z := Last_Z;
      end if;
   end Keep_Inside;

   function At_Exit (X, Z : Float) return Boolean is
     (X - Origin.X < 1.2 and then abs (Z - Origin.Z) < 1.6);

   procedure Update (Dt : Float) is
   begin
      Clock := Clock + Dt;
   end Update;

   ---------------------------------------------------------------------------

   procedure Face (A, B, C, D, N : Vec3; Mat : Float; Seed : Float := 0.0;
                   U : Float := 1.0; V : Float := 1.0; U0 : Float := 0.0) is
   begin
      Meshes.Quad_UV (A, B, C, D, N, Mat, Seed, U, V, U0);
   end Face;

   --  A point on an oval's wall at angle T, a little in from the wall by In
   function On_Wall (C, T, Y, In_By : Float) return Vec3 is
     (G (C + (Oval_A - In_By) * Cos (T), Y, (Oval_Short - In_By) * Sin (T)));

   procedure Build_Oval (C : Float; First_Panel : Positive) is
      Segs : constant := 64;
      Door : constant Float := 0.16;   --  the openings at the ends of the long axis (radians each side)
   begin
      for K in 0 .. Segs - 1 loop
         declare
            T0 : constant Float := 2.0 * Pi * Float (K) / Float (Segs);
            T1 : constant Float := 2.0 * Pi * Float (K + 1) / Float (Segs);
            Mid : constant Float := (T0 + T1) / 2.0;
            Open : constant Boolean :=
              abs (Mid) < Door or else abs (Mid - Pi) < Door or else abs (Mid - 2.0 * Pi) < Door;
            A0 : constant Vec3 := On_Wall (C, T0, 0.0, 0.0);
            A1 : constant Vec3 := On_Wall (C, T1, 0.0, 0.0);
            N  : constant Vec3 := Normalize (Vec3'(-Cos (Mid) / Oval_A, 0.0, -Sin (Mid) / Oval_Short));
            Up : constant Vec3 := (0.0, Height, 0.0);
         begin
            --  the floor and the ceiling's light, as a fan
            Face (G (C, 0.0, 0.0), A1, A0, A0, (0.0, 1.0, 0.0), Mat_Floor);
            Face (G (C, Height, 0.0), A0 + Up, A1 + Up, A1 + Up, (0.0, -1.0, 0.0), Mat_Sky);
            if Open then
               --  over the opening, the wall above the door
               Face (A0 + Vec3'(0.0, 3.0, 0.0), A1 + Vec3'(0.0, 3.0, 0.0), A1 + Up, A0 + Up, N, Mat_White);
            else
               Face (A0, A1, A1 + Up, A0 + Up, N, Mat_White);
               --  the painting, from 0.9 to 2.9 m, the panel by which side
               --  and half of the oval it is on
               declare
                  Quarter : constant Natural :=
                    (if Mid < Pi / 2.0 then 0 elsif Mid < Pi then 1 elsif Mid < 1.5 * Pi then 2 else 3);
                  Panel : constant Positive := First_Panel + Quarter;
                  --  the distance along the wall, for the pattern to run on
                  Arc0 : constant Float := 9.3 * T0;
                  Arc1 : constant Float := 9.3 * T1;
                  P0 : constant Vec3 := On_Wall (C, T0, 0.9, 0.04);
                  P1 : constant Vec3 := On_Wall (C, T1, 0.9, 0.04);
                  Hg : constant Vec3 := (0.0, 2.0, 0.0);
               begin
                  Face (P0, P1, P1 + Hg, P0 + Hg, N, Mat_Lilies, Float (Panel - 1),
                        Arc1 - Arc0, 2.0, Arc0);
               end;
            end if;
         end;
      end loop;
      --  the bench in the middle, long and low
      Meshes.Box (Origin.X + C - 3.0, Origin.X + C + 3.0, Origin.Y, Origin.Y + 0.45,
                  Origin.Z - 0.5, Origin.Z + 0.5, Mat_Wood);
   end Build_Oval;

   procedure Build is
      Up : constant Vec3 := (0.0, 1.0, 0.0);
      procedure Room (X0, X1, W, H : Float) is
      begin
         Face (G (X0, 0.0, -W), G (X0, 0.0, W), G (X1, 0.0, W), G (X1, 0.0, -W), Up, Mat_Floor);
         Face (G (X0, H, -W), G (X1, H, -W), G (X1, H, W), G (X0, H, W), (0.0, -1.0, 0.0), Mat_White);
         Face (G (X0, 0.0, -W), G (X1, 0.0, -W), G (X1, H, -W), G (X0, H, -W), (0.0, 0.0, 1.0), Mat_White);
         Face (G (X1, 0.0, W), G (X0, 0.0, W), G (X0, H, W), G (X1, H, W), (0.0, 0.0, -1.0), Mat_White);
      end Room;
   begin
      Meshes.Start;
      --  the vestibule and its door back out, the passages
      Room (0.0, 7.0, 2.5, 3.5);
      Face (G (0.02, 0.0, 1.2), G (0.02, 0.0, -1.2), G (0.02, 2.6, -1.2), G (0.02, 2.6, 1.2),
            (1.0, 0.0, 0.0), Mat_Door);
      Meshes.Box (Origin.X + 0.03, Origin.X + 0.1, Origin.Y + 2.8, Origin.Y + 3.2,
                  Origin.Z - 0.7, Origin.Z + 0.7, Mat_Exit);
      Room (28.5, 36.5, 1.6, 3.0);
      Room (57.5, 63.0, 1.6, 3.0);
      Build_Oval (C1, 1);
      Build_Oval (C2, 5);
      --  the gallery: white walls, darker floor, the paintings hung round
      Room (G0, G1, GW, 4.2);
      Face (G (G1, 0.0, GW), G (G1, 0.0, -GW), G (G1, 4.2, -GW), G (G1, 4.2, GW), (-1.0, 0.0, 0.0), Mat_White);
      N_Hung := 0;
      for I in 1 .. Collection.Works loop
         exit when N_Hung = Hung_Works'Last;
         declare
            Side : constant Float := (if I mod 2 = 1 then -1.0 else 1.0);
            Along : constant Float := G0 + 3.0 + 3.0 * Float ((I - 1) / 2);
            C : constant Vec3 := (Along, 1.75, Side * (GW - 0.03));
            N : constant Vec3 := (0.0, 0.0, -Side);
            P : constant Natural := Collection.Work_Painter (I);
            W : constant Float := (if P in 2 | 4 | 6 then 1.6 else 1.1);   --  a few big ones
            Hh : constant Float := (if P = 3 then 1.5 else W * 0.8);       --  Modigliani's tall portraits
            Al : constant Vec3 := (Side, 0.0, 0.0);
         begin
            if Along + W < G1 - 1.0 then
               N_Hung := N_Hung + 1;
               Hung_Works (N_Hung) := (C, N, I);
               Face (G (C.X, C.Y, C.Z) - (W / 2.0) * Al - (Hh / 2.0) * Up,
                     G (C.X, C.Y, C.Z) + (W / 2.0) * Al - (Hh / 2.0) * Up,
                     G (C.X, C.Y, C.Z) + (W / 2.0) * Al + (Hh / 2.0) * Up,
                     G (C.X, C.Y, C.Z) - (W / 2.0) * Al + (Hh / 2.0) * Up,
                     N, Mat_Manner, Float (8 * P + I mod 8));
            end if;
         end;
      end loop;
      Meshes.Finish (Hall);
      Built := True;
   end Build;

   ---------------------------------------------------------------------------

   function Caption (X, Z, Yaw : Float) return String is
      LX : constant Float := X - Origin.X;
      LZ : constant Float := Z - Origin.Z;
      FX : constant Float := Sin (Yaw);
      FZ : constant Float := -Cos (Yaw);
      function Lily (C : Float; First : Positive) return String is
         --  the wall you look at: where the view meets the oval
         T : constant Float := Arctan ((LZ + 5.0 * FZ) / Oval_Short, (LX - C + 5.0 * FX) / Oval_A);
         A : constant Float := (if T < 0.0 then T + 2.0 * Pi else T);
         Q : constant Natural := (if A < Pi / 2.0 then 0 elsif A < Pi then 1 elsif A < 1.5 * Pi then 2 else 3);
      begin
         return "<span font_family='serif' size='large'><i>" & Collection.Painter (0) & "</i></span>" & ASCII.LF
           & "<span font_family='sans'>Les Nymphéas : " & Collection.Panel (First + Q) & ", 1914-1926</span>";
      end Lily;
   begin
      if In_Oval (LX, LZ, C1) then
         return Lily (C1, 1);
      elsif In_Oval (LX, LZ, C2) then
         return Lily (C2, 5);
      end if;
      --  the gallery: the painting before you
      for K in 1 .. N_Hung loop
         declare
            H : Hung renames Hung_Works (K);
            DX : constant Float := H.C.X - LX;
            DZ : constant Float := H.C.Z - LZ;
            D  : constant Float := Sqrt (DX * DX + DZ * DZ);
         begin
            if D < 4.0 and then D > 0.1 and then (DX * FX + DZ * FZ) / D > 0.8 then
               return "<span font_family='serif' size='large'><i>" & Collection.Work_Title (H.Work)
                 & "</i>, " & Collection.Work_Year (H.Work) & "</span>" & ASCII.LF
                 & "<span font_family='sans'>" & Collection.Painter (Collection.Work_Painter (H.Work))
                 & "  ·  huile sur toile</span>";
            end if;
         end;
      end loop;
      return "";
   end Caption;

   procedure Draw (Model, Paint, Skin, Legs, Gallery : GL.GLint) is
      Skins : constant array (0 .. 3) of Vec3 :=
        ((0.86, 0.68, 0.56), (0.76, 0.57, 0.44), (0.58, 0.40, 0.29), (0.40, 0.27, 0.19));
      Coats : constant array (0 .. 4) of Vec3 :=
        ((0.1, 0.1, 0.12), (0.55, 0.5, 0.42), (0.2, 0.3, 0.45), (0.6, 0.2, 0.18), (0.85, 0.85, 0.82));
   begin
      if Need then
         Need := False;
         if Built then
            Meshes.Free (Hall);
         end if;
         Build;
      end if;
      if not Built then
         return;
      end if;
      Shaders.Set (Gallery, 2.0);   --  an even light from above, by day and night alike
      Shaders.Set (Model, Identity);
      Meshes.Draw (Hall);
      --  people sitting on the benches, a few standing at the walls
      Figures.Set_Locations ((Model, Paint, Skin, Legs));
      for K in 0 .. 5 loop
         declare
            C : constant Float := (if K < 3 then C1 else C2);
            A : constant Float := 0.6 + 1.9 * Float (K mod 3) + 0.15 * Sin (Clock * 0.2 + Float (K));
            P : constant Vec3 := G (C + 8.5 * Cos (A), 0.0, 5.5 * Sin (A));
         begin
            Figures.Person (Translation (P) * Rotation_Y (-Arctan (Cos (A), -Sin (A))),
                            Coats (K mod 5), Skins (K mod 4), (0.15, 0.15, 0.2));
         end;
      end loop;
      Shaders.Set (Gallery, 0.0);
      Shaders.Set (Model, Identity);
   end Draw;

end Hall_E;
