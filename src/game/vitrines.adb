--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Containers.Vectors;
with Ada.Environment_Variables;
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Strings.Fixed;
with Ada.Text_IO;

with Almanac;
with Figures;
with Geo;
with Meshes;
with Road_Network;
with Shaders;
with Terrain;

package body Vitrines is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Pi : constant := Ada.Numerics.Pi;

   --  a window: where it is, the way it looks out, which scene it shows
   type Bay is record
      C     : Vec3;      --  the middle of its foot, at the wall
      Out_N : Vec3;      --  out of the wall, to the pavement
      Along : Vec3;
      Scene : Natural;
   end record;
   package Bay_Vectors is new Ada.Containers.Vectors (Positive, Bay);
   Bays : Bay_Vectors.Vector;
   Loaded : Boolean := False;
   Centre : Vec3 := (0.0, 0.0, 0.0);

   Width  : constant := 3.4;    --  a window
   Pitch  : constant := 5.0;    --  one every so far
   Deep   : constant := 0.7;    --  how far the vitrine stands out

   Frame_M, Bear_M, Star_M, Tree_M, Garland_M : Meshes.Mesh;
   Back_M : array (0 .. 5) of Meshes.Mesh;   --  the backdrops, each its own light
   Built : Boolean := False;

   function Season return Boolean is
     ((Almanac.Month = 11 and then Almanac.Day >= 15) or else Almanac.Christmas
      or else Ada.Environment_Variables.Exists ("PARIS_VITRINES"));

   procedure Load is
      F : Ada.Text_IO.File_Type;
      N : Natural := 0;
   begin
      Loaded := True;
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, "data/windows.txt");
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            L : constant String := Ada.Text_IO.Get_Line (F);
            V : array (1 .. 4) of Long_Float;
            First : Positive := L'First;
            K : Natural := 0;
         begin
            if L'Length > 0 and then L (L'First) /= '#' then
               for I in L'First .. L'Last + 1 loop
                  if I > L'Last or else L (I) = ' ' then
                     if I > First and then K < 4 then
                        K := K + 1;
                        V (K) := Long_Float'Value (L (First .. I - 1));
                     end if;
                     First := I + 1;
                  end if;
               end loop;
               if K = 4 then
                  declare
                     AX, AZ, BX, BZ : Long_Float;
                  begin
                     Geo.To_Local (V (1), V (2), AX, AZ);
                     Geo.To_Local (V (3), V (4), BX, BZ);
                     declare
                        A : constant Vec3 := (Float (AX), 0.0, Float (AZ));
                        B : constant Vec3 := (Float (BX), 0.0, Float (BZ));
                        Len : constant Float := Length (B - A);
                        U : constant Vec3 := (1.0 / Len) * (B - A);
                        Mid : constant Vec3 := 0.5 * (A + B);
                        Ok : Boolean;
                        RX, RZ, RH : Float;
                        Nrm : Vec3 := (-U.Z, 0.0, U.X);
                        Count : constant Natural := Natural (Float'Floor (Len / Pitch));
                     begin
                        --  out of the wall: towards the boulevard
                        Road_Network.Nearest_Road (Mid.X, Mid.Z, Ok, RX, RZ, RH);
                        if Ok and then Dot (Nrm, Vec3'(RX - Mid.X, 0.0, RZ - Mid.Z)) < 0.0 then
                           Nrm := (-1.0) * Nrm;
                        end if;
                        for I in 0 .. Count - 1 loop
                           declare
                              P : constant Vec3 := A + ((Float (I) + 0.5) * Len / Float (Count)) * U;
                           begin
                              N := N + 1;
                              Bays.Append ((C => (P.X, Terrain.Height (P.X, P.Z), P.Z), Out_N => Nrm,
                                            Along => U, Scene => N mod 4));
                              Centre := Centre + P;
                           end;
                        end loop;
                     end;
                  end;
               end if;
            end if;
         exception
            when Constraint_Error => null;
         end;
      end loop;
      Ada.Text_IO.Close (F);
      if N > 0 then
         Centre := (1.0 / Float (N)) * Centre;
      end if;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
   end Load;

   --  The shapes, in a window's frame: X along it, Y up, Z out of the wall
   procedure Build is
      use Meshes;
      H : constant Float := Width / 2.0;
   begin
      --  the vitrine: dark stone frame, a red plinth, a gold top, glass
      Start;
      Box (-H - 0.25, -H, 0.0, 3.8, 0.0, Deep, 29.0);
      Box (H, H + 0.25, 0.0, 3.8, 0.0, Deep, 29.0);
      Box (-H - 0.25, H + 0.25, 3.5, 3.9, 0.0, Deep, 29.0);
      Box (-H, H, 0.0, 0.55, 0.0, Deep, 86.0);
      Box (-H, H, 3.3, 3.5, Deep - 0.05, Deep, 78.0);
      Finish (Frame_M);
      --  the back: moving light (lit at night, bright by day too)
      for K in Back_M'Range loop
         Start;
         Quad_UV ((-H, 0.55, 0.05), (H, 0.55, 0.05), (H, 3.3, 0.05), (-H, 3.3, 0.05),
                  (0.0, 0.0, 1.0), 63.0, Float (K));
         Finish (Back_M (K));
      end loop;
      --  a teddy bear: body, head, ears, arms (in the paint)
      Start;
      Box (-0.28, 0.28, 0.0, 0.6, -0.22, 0.22, 54.0, Top_Inset_X => 0.06);
      Box (-0.2, 0.2, 0.6, 0.95, -0.18, 0.18, 54.0, Top_Inset_X => 0.03);
      Box (-0.22, -0.12, 0.92, 1.04, -0.05, 0.05, 54.0);
      Box (0.12, 0.22, 0.92, 1.04, -0.05, 0.05, 54.0);
      Box (-0.4, -0.28, 0.25, 0.55, -0.08, 0.08, 54.0);
      Box (0.28, 0.4, 0.25, 0.55, -0.08, 0.08, 54.0);
      Box (-0.06, 0.06, 0.72, 0.8, 0.18, 0.24, 17.0);   --  the nose
      Finish (Bear_M);
      --  a star, gold, turning
      Start;
      for K in 0 .. 4 loop
         declare
            A : constant Float := 2.0 * Pi * Float (K) / 5.0;
            T : constant Vec3 := (0.5 * Sin (A), 0.5 * Cos (A), 0.0);
            L : constant Vec3 := (0.18 * Sin (A - 0.6), 0.18 * Cos (A - 0.6), 0.0);
            R : constant Vec3 := (0.18 * Sin (A + 0.6), 0.18 * Cos (A + 0.6), 0.0);
            Z : constant Vec3 := (0.0, 0.0, 0.06);
         begin
            Quad (L + Z, R + Z, T + Z, T + Z, 78.0);
            Quad (R - Z, L - Z, T - Z, T - Z, 78.0);
            Quad (L - Z, L + Z, T + Z, T - Z, 78.0);
            Quad (R + Z, R - Z, T - Z, T + Z, 78.0);
         end;
      end loop;
      Box (-0.18, 0.18, -0.18, 0.18, -0.06, 0.06, 78.0);
      Finish (Star_M);
      --  a little fir hung with lights
      Start;
      for K in 0 .. 3 loop
         declare
            W : constant Float := 0.55 - 0.12 * Float (K);
            Y : constant Float := 0.2 + 0.38 * Float (K);
         begin
            Box (-W, W, Y, Y + 0.45, -W, W, 37.0, Top_Inset_X => W * 0.8,
                 Top_Inset_Front => W * 0.8, Top_Inset_Back => W * 0.8);
         end;
      end loop;
      Box (-0.06, 0.06, 0.0, 0.25, -0.06, 0.06, 17.0);
      Finish (Tree_M);
      --  the garland over the windows: a row of small warm lights
      Start;
      for K in -8 .. 8 loop
         declare
            X : constant Float := Float (K) * 0.24;
            Y : constant Float := 4.15 - 0.25 * (1.0 - (X / 2.0) ** 2);
         begin
            Box (X - 0.04, X + 0.04, Y - 0.04, Y + 0.04, Deep - 0.04, Deep + 0.04, 79.0);
         end;
      end loop;
      Finish (Garland_M);
      Built := True;
   end Build;

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint; Cam : Vec3; Hour, Time : Float) is
      Evening : constant Boolean := Hour >= 16.0 and then Hour < 22.0;
   begin
      if not Season then
         return;
      end if;
      if not Loaded then
         Load;
      end if;
      if Bays.Is_Empty or else (Cam.X - Centre.X) ** 2 + (Cam.Z - Centre.Z) ** 2 > 450.0 ** 2 then
         return;
      end if;
      if not Built then
         Build;
      end if;
      Figures.Set_Locations ((Model, Paint, Skin, Legs));
      for I in Bays.First_Index .. Bays.Last_Index loop
         declare
            B : Bay renames Bays (I);
            --  the window's frame: X along, Z out
            Base : constant Mat4 := Translation (B.C) * Rotation_Y (-Arctan (B.Out_N.X, -B.Out_N.Z) + Pi);
            Inside : constant Mat4 := Base * Translation ((0.0, 0.55, 0.35));
            T : constant Float := Time + Float (I) * 1.3;
         begin
            Shaders.Set (Model, Base);
            Meshes.Draw (Frame_M);
            Meshes.Draw (Garland_M);
            Shaders.Set (Model, Base * Translation ((0.0, 0.0, 0.01 * Float (I mod 3))));
            Meshes.Draw (Back_M (I mod 6));
            case B.Scene is
               when 0 =>   --  three bears, turning on their stand, one waving
                  for K in -1 .. 1 loop
                     Shaders.Set (Paint, (case K is when -1 => Vec3'(0.55, 0.35, 0.2),
                                                    when 0 => Vec3'(0.85, 0.7, 0.45),
                                                    when others => Vec3'(0.95, 0.95, 0.92)));
                     Shaders.Set (Model, Inside * Translation ((Float (K) * 1.0, 0.05 * abs Sin (T * 2.0 + Float (K)), 0.0))
                                  * Rotation_Y (0.6 * Sin (T * 0.7 + Float (K))));
                     Meshes.Draw (Bear_M);
                  end loop;
               when 1 =>   --  a big star turning over a little fir
                  Shaders.Set (Model, Inside * Translation ((0.0, 1.9, 0.0)) * Rotation_Y (T * 1.2));
                  Meshes.Draw (Star_M);
                  Shaders.Set (Model, Inside);
                  Meshes.Draw (Tree_M);
               when 2 =>   --  bears riding round and round
                  for K in 0 .. 2 loop
                     declare
                        A : constant Float := T * 0.9 + 2.0 * Pi * Float (K) / 3.0;
                     begin
                        Shaders.Set (Paint, (case K is when 0 => Vec3'(0.85, 0.15, 0.15),
                                                       when 1 => Vec3'(0.2, 0.35, 0.8),
                                                       when others => Vec3'(0.95, 0.8, 0.2)));
                        Shaders.Set (Model, Inside * Translation ((1.1 * Cos (A), 0.15 + 0.15 * Sin (A * 2.0),
                                                                   -0.1 + 0.15 * Sin (A)))
                                     * Rotation_Y (-A) * Scale (0.75));
                        Meshes.Draw (Bear_M);
                     end;
                  end loop;
               when others =>   --  stars falling, a fir in the middle
                  Shaders.Set (Model, Inside * Translation ((0.0, 0.0, 0.0)) * Scale (1.3));
                  Meshes.Draw (Tree_M);
                  for K in 0 .. 3 loop
                     declare
                        U : constant Float := (T * 0.4 + Float (K) * 0.7) / 2.6;
                        Y : constant Float := 2.6 * (1.0 - (U - Float'Floor (U)));
                     begin
                        Shaders.Set (Model, Inside * Translation ((-1.2 + 0.8 * Float (K), Y, 0.05))
                                     * Rotation_Y (T * 2.0 + Float (K)) * Scale (0.35));
                        Meshes.Draw (Star_M);
                     end;
                  end loop;
            end case;
            --  people looking in: by day a few, in the evening the crowd,
            --  children in front
            if (B.C.X - Cam.X) ** 2 + (B.C.Z - Cam.Z) ** 2 < 150.0 ** 2 then
               for K in 1 .. (if Evening then 3 else (if I mod 2 = 0 then 1 else 0)) loop
                  declare
                     Child : constant Boolean := K = 1 or else (K = 3 and then I mod 3 = 0);
                     Side  : constant Float := (Float (K) - 2.0) * 0.9 + 0.3 * Sin (Float (I * K));
                     Back  : constant Float := Deep + (if Child then 0.5 else 1.3);
                     P : constant Vec3 := B.C + Side * B.Along + Back * B.Out_N;
                     Seed : constant Natural := (I * 7 + K * 3) mod 6;
                  begin
                     Figures.Person
                       (Translation ((P.X, Terrain.Height (P.X, P.Z), P.Z))
                        * Rotation_Y (-Arctan (-B.Out_N.X, B.Out_N.Z))
                        * Scale (if Child then 0.62 else 1.0),
                        (case Seed is
                            when 0 => (0.7, 0.1, 0.12), when 1 => (0.15, 0.2, 0.4), when 2 => (0.2, 0.2, 0.22),
                            when 3 => (0.85, 0.75, 0.6), when 4 => (0.25, 0.4, 0.3), when others => (0.5, 0.3, 0.55)),
                        (case Seed mod 4 is
                            when 0 => (0.86, 0.68, 0.56), when 1 => (0.76, 0.57, 0.44),
                            when 2 => (0.58, 0.40, 0.29), when others => (0.40, 0.27, 0.19)),
                        (0.12, 0.13, 0.18),
                        Hat => (if Child and then Seed mod 2 = 0 then Figures.Cap else Figures.None),
                        Hat_Colour => (0.8, 0.15, 0.15),
                        Arm_Up => (if Child and then Seed mod 3 = 0 then -1.2 + 0.3 * Sin (Time * 3.0 + Float (I))
                                   else 0.0));
                  end;
               end loop;
            end if;
         end;
      end loop;
      Shaders.Set (Model, Identity);
   end Draw;

end Vitrines;
