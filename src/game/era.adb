--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;

with Meshes;
with Shaders;
with Terrain;

package body Era is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   On_Now : Boolean := False;

   function In_1973 return Boolean is (On_Now);

   procedure Set (On : Boolean) is
   begin
      On_Now := On;
   end Set;

   --  What was not there yet, from the OpenStreetMap outlines: the middle,
   --  the turn of the long side (degrees in the X/Z plane), the half sizes
   type Place is record
      CX, CZ, Angle, HU, HV : Float;
   end record;
   Places : constant array (1 .. 4) of Place :=
     ((-1197.4, -491.1, 21.0, 20.0, 20.0),     --  the Pyramid of the Louvre (1989)
      (16.1, -437.7, 19.0, 35.0, 86.0),        --  the Centre Pompidou (1977)
      (1365.9, 551.5, 74.0, 153.0, 59.0),      --  the Opéra Bastille (1989)
      (-372.3, -591.5, 19.0, 63.0, 73.0));     --  the Canopée of Les Halles (2016)
   Halles : constant Natural := 4;

   procedure Set_Uniforms (Erase, Erase_B, Erase_N, Grade : GL.GLint) is
   begin
      Set_Shadow_Uniforms (Erase, Erase_B, Erase_N);
      Shaders.Set (Grade, (if On_Now then 1.0 else 0.0));
   end Set_Uniforms;

   Cut_On : Boolean := False;
   Cut    : Place;
   Cut_Y  : Float := 0.0;

   procedure Set_Cut (On : Boolean; CX, CZ, Angle, HU, HV, Y : Float := 0.0) is
   begin
      Cut_On := On;
      Cut := (CX, CZ, Angle, HU, HV);
      Cut_Y := Y;
   end Set_Cut;

   procedure Set_Shadow_Uniforms (Erase, Erase_B, Erase_N : GL.GLint) is
      use type GL.GLint;
      A, B : array (0 .. 4 * (Places'Length + 1) - 1) of GL.GLfloat := (others => 0.0);
      N : Natural := 0;
      procedure Add (P : Place; Y : Float) is
         R : constant Float := P.Angle * Ada.Numerics.Pi / 180.0;
         K : constant Natural := 4 * N;
      begin
         A (K) := GL.GLfloat (P.CX);
         A (K + 1) := GL.GLfloat (P.CZ);
         A (K + 2) := GL.GLfloat (P.HU);
         A (K + 3) := GL.GLfloat (P.HV);
         B (K) := GL.GLfloat (Cos (R));
         B (K + 1) := GL.GLfloat (Sin (R));
         B (K + 2) := GL.GLfloat (Y);
         N := N + 1;
      end Add;
   begin
      if Erase_N < 0 then
         return;
      end if;
      if On_Now then
         for P of Places loop
            Add (P, Terrain.Height (P.CX, P.CZ) + 0.3);   --  above the ground
         end loop;
      end if;
      if Cut_On then
         Add (Cut, Cut_Y);
      end if;
      if N > 0 then
         GL.glUniform4fv (Erase, GL.GLsizei (N), A'Address);
         GL.glUniform4fv (Erase_B, GL.GLsizei (N), B'Address);
      end if;
      Shaders.Set (Erase_N, Integer'(N));
   end Set_Shadow_Uniforms;

   ---------------------------------------------------------------------------
   --  Les Halles: the hole behind the hoardings, earth, two tower cranes

   Works : Meshes.Mesh;
   Built : Boolean := False;

   procedure Build is
      P  : Place renames Places (Halles);
      R  : constant Float := P.Angle * Ada.Numerics.Pi / 180.0;
      U  : constant Vec3 := (Cos (R), 0.0, Sin (R));
      V  : constant Vec3 := (-Sin (R), 0.0, Cos (R));
      HU : constant Float := P.HU + 25.0;   --  the works reach beyond the Canopée
      HV : constant Float := P.HV + 15.0;
      Y  : constant Float := Terrain.Height (P.CX, P.CZ);
      C  : constant Vec3 := (P.CX, Y, P.CZ);
      function At_UV (A, B, H : Float) return Vec3 is (C + A * U + B * V + Vec3'(0.0, H, 0.0));
      procedure Quad2 (A, B, Cc, D : Vec3; Mat : Float) is
      begin
         Meshes.Quad (A, B, Cc, D, Mat);
         Meshes.Quad (D, Cc, B, A, Mat);
      end Quad2;
      procedure OBox (Ctr : Vec3; HA, HB, Y0, Y1 : Float; Mat : Float) is
         function K (SA, SB, H : Float) return Vec3 is (Ctr + (SA * HA) * U + (SB * HB) * V + Vec3'(0.0, H, 0.0));
      begin
         Quad2 (K (-1.0, -1.0, Y0), K (1.0, -1.0, Y0), K (1.0, -1.0, Y1), K (-1.0, -1.0, Y1), Mat);
         Quad2 (K (-1.0, 1.0, Y0), K (1.0, 1.0, Y0), K (1.0, 1.0, Y1), K (-1.0, 1.0, Y1), Mat);
         Quad2 (K (-1.0, -1.0, Y0), K (-1.0, 1.0, Y0), K (-1.0, 1.0, Y1), K (-1.0, -1.0, Y1), Mat);
         Quad2 (K (1.0, -1.0, Y0), K (1.0, 1.0, Y0), K (1.0, 1.0, Y1), K (1.0, -1.0, Y1), Mat);
         Quad2 (K (-1.0, -1.0, Y1), K (1.0, -1.0, Y1), K (1.0, 1.0, Y1), K (-1.0, 1.0, Y1), Mat);
      end OBox;
      Mat_Board : constant := 15.0;   --  the hoardings, in the paint
      Mat_Poster : constant := 55.0;
      Mat_Earth : constant := 84.0;
      Mat_Iron  : constant := 26.0;
      Mat_Yellow : constant := 85.0;
   begin
      Meshes.Start;
      --  the bottom of the hole, earth, a little lower than the street,
      --  with the hoardings all round (posters on them here and there)
      Quad2 (At_UV (-HU, -HV, 0.08), At_UV (HU, -HV, 0.08), At_UV (HU, HV, 0.08), At_UV (-HU, HV, 0.08), Mat_Earth);
      for Side in 0 .. 3 loop
         declare
            A0 : constant Vec3 := (case Side is when 0 => At_UV (-HU, -HV, 0.0), when 1 => At_UV (HU, -HV, 0.0),
                                   when 2 => At_UV (HU, HV, 0.0), when others => At_UV (-HU, HV, 0.0));
            A1 : constant Vec3 := (case Side is when 0 => At_UV (HU, -HV, 0.0), when 1 => At_UV (HU, HV, 0.0),
                                   when 2 => At_UV (-HU, HV, 0.0), when others => At_UV (-HU, -HV, 0.0));
            L  : constant Float := Sqrt ((A1.X - A0.X) ** 2 + (A1.Z - A0.Z) ** 2);
            N  : constant Natural := Natural (L / 4.0);
         begin
            for K in 0 .. N - 1 loop
               declare
                  P0 : constant Vec3 := A0 + (Float (K) / Float (N)) * (A1 - A0);
                  P1 : constant Vec3 := A0 + (Float (K + 1) / Float (N)) * (A1 - A0);
                  Up : constant Vec3 := (0.0, 2.4, 0.0);
               begin
                  Quad2 (P0, P1, P1 + Up, P0 + Up, (if K mod 5 = 2 then Mat_Poster else Mat_Board));
               end;
            end loop;
         end;
      end loop;
      --  heaps of earth and a ramp down
      OBox (At_UV (-HU * 0.5, HV * 0.4, 0.0), 14.0, 9.0, 0.0, 4.0, Mat_Earth);
      OBox (At_UV (HU * 0.4, -HV * 0.5, 0.0), 10.0, 8.0, 0.0, 3.0, Mat_Earth);
      --  two tower cranes: the mast, the jib, the counter-jib and its weight
      for K in 0 .. 1 loop
         declare
            Base : constant Vec3 := At_UV ((if K = 0 then -HU * 0.3 else HU * 0.35), (if K = 0 then -HV * 0.2 else HV * 0.3), 0.0);
            Turn : constant Float := (if K = 0 then 0.7 else 2.6);
            JU : constant Vec3 := (Cos (Turn), 0.0, Sin (Turn));
            JV : constant Vec3 := (-Sin (Turn), 0.0, Cos (Turn));
            H  : constant Float := (if K = 0 then 38.0 else 32.0);
         begin
            Meshes.Box (Base.X - 0.8, Base.X + 0.8, Base.Y, Base.Y + H, Base.Z - 0.8, Base.Z + 0.8, Mat_Yellow);
            for S in 0 .. 1 loop
               declare
                  A : constant Vec3 := Base + Vec3'(0.0, H, 0.0);
                  B : constant Vec3 := A + (if S = 0 then 45.0 else -14.0) * JU;
                  W : constant Vec3 := 0.5 * JV;
                  T : constant Vec3 := (0.0, 1.2, 0.0);
               begin
                  Quad2 (A - W, B - W, B - W + T, A - W + T, Mat_Yellow);
                  Quad2 (A + W, B + W, B + W + T, A + W + T, Mat_Yellow);
                  Quad2 (A - W + T, B - W + T, B + W + T, A + W + T, Mat_Yellow);
                  if S = 1 then
                     Meshes.Box (B.X - 1.5, B.X + 1.5, B.Y - 2.0, B.Y, B.Z - 1.5, B.Z + 1.5, Mat_Iron);
                  end if;
               end;
            end loop;
            --  the hook's cable
            declare
               Hook : constant Vec3 := Base + Vec3'(0.0, H, 0.0) + 30.0 * JU;
            begin
               Meshes.Box (Hook.X - 0.04, Hook.X + 0.04, Base.Y + 6.0, Hook.Y, Hook.Z - 0.04, Hook.Z + 0.04, Mat_Iron);
               Meshes.Box (Hook.X - 0.6, Hook.X + 0.6, Base.Y + 5.0, Base.Y + 6.0, Hook.Z - 0.6, Hook.Z + 0.6, Mat_Iron);
            end;
         end;
      end loop;
      Meshes.Finish (Works);
      Built := True;
   end Build;

   procedure Draw (Model, Paint : GL.GLint; Cam : Vec3) is
      P : Place renames Places (Halles);
   begin
      if not On_Now or else (Cam.X - P.CX) ** 2 + (Cam.Z - P.CZ) ** 2 > 1500.0 ** 2 then
         return;
      end if;
      if not Built then
         Build;
      end if;
      Shaders.Set (Paint, Vec3'(0.25, 0.32, 0.27));   --  the hoardings' green
      Shaders.Set (Model, Identity);
      Meshes.Draw (Works);
   end Draw;

end Era;
