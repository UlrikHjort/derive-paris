--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions;

package body Math3D is

   use Ada.Numerics.Elementary_Functions;

   function Length (A : Vec3) return Float is (Sqrt (Dot (A, A)));

   function Normalize (A : Vec3) return Vec3 is
      L : constant Float := Length (A);
   begin
      if L < 1.0E-12 then
         return A;
      end if;
      return (1.0 / L) * A;
   end Normalize;

   function "*" (A, B : Mat4) return Mat4 is
      R : Mat4 := (others => 0.0);
   begin
      for Col in 0 .. 3 loop
         for Row in 0 .. 3 loop
            declare
               S : Float := 0.0;
            begin
               for K in 0 .. 3 loop
                  S := S + A (K * 4 + Row) * B (Col * 4 + K);
               end loop;
               R (Col * 4 + Row) := S;
            end;
         end loop;
      end loop;
      return R;
   end "*";

   function Perspective (Fov_Y, Aspect, Near, Far : Float) return Mat4 is
      F : constant Float := 1.0 / Tan (Fov_Y / 2.0);
      R : Mat4 := (others => 0.0);
   begin
      R (0) := F / Aspect;
      R (5) := F;
      R (10) := (Far + Near) / (Near - Far);
      R (11) := -1.0;
      R (14) := 2.0 * Far * Near / (Near - Far);
      return R;
   end Perspective;

   function Ortho (L, R, B, T, N, F : Float) return Mat4 is
      M : Mat4 := Identity;
   begin
      M (0) := 2.0 / (R - L);
      M (5) := 2.0 / (T - B);
      M (10) := -2.0 / (F - N);
      M (12) := -(R + L) / (R - L);
      M (13) := -(T + B) / (T - B);
      M (14) := -(F + N) / (F - N);
      return M;
   end Ortho;

   function Look_At (Eye, Target, Up : Vec3) return Mat4 is
      F : constant Vec3 := Normalize (Target - Eye);
      S : constant Vec3 := Normalize (Cross (F, Up));
      U : constant Vec3 := Cross (S, F);
      M : Mat4 := Identity;
   begin
      M (0) := S.X;
      M (4) := S.Y;
      M (8) := S.Z;
      M (1) := U.X;
      M (5) := U.Y;
      M (9) := U.Z;
      M (2) := -F.X;
      M (6) := -F.Y;
      M (10) := -F.Z;
      M (12) := -Dot (S, Eye);
      M (13) := -Dot (U, Eye);
      M (14) := Dot (F, Eye);
      return M;
   end Look_At;

   function Translation (V : Vec3) return Mat4 is
      M : Mat4 := Identity;
   begin
      M (12) := V.X;
      M (13) := V.Y;
      M (14) := V.Z;
      return M;
   end Translation;

   function About (A : Vec3; Angle : Float) return Mat4 is
      C : constant Float := Cos (Angle);
      S : constant Float := Sin (Angle);
      T : constant Float := 1.0 - C;
      M : Mat4 := Identity;
      procedure Put (Row, Col : Natural; V : Float) is
      begin
         M (Col * 4 + Row) := V;
      end Put;
   begin
      Put (0, 0, T * A.X * A.X + C);       Put (0, 1, T * A.X * A.Y - S * A.Z); Put (0, 2, T * A.X * A.Z + S * A.Y);
      Put (1, 0, T * A.X * A.Y + S * A.Z); Put (1, 1, T * A.Y * A.Y + C);       Put (1, 2, T * A.Y * A.Z - S * A.X);
      Put (2, 0, T * A.X * A.Z - S * A.Y); Put (2, 1, T * A.Y * A.Z + S * A.X); Put (2, 2, T * A.Z * A.Z + C);
      return M;
   end About;

   function Rotation_Y (Angle : Float) return Mat4 is
      C : constant Float := Cos (Angle);
      S : constant Float := Sin (Angle);
      M : Mat4 := Identity;
   begin
      M (0) := C;
      M (2) := -S;
      M (8) := S;
      M (10) := C;
      return M;
   end Rotation_Y;

   function Rotation_X (Angle : Float) return Mat4 is
      C : constant Float := Cos (Angle);
      S : constant Float := Sin (Angle);
      M : Mat4 := Identity;
   begin
      M (5) := C;
      M (6) := S;
      M (9) := -S;
      M (10) := C;
      return M;
   end Rotation_X;

   function Rotation_Z (Angle : Float) return Mat4 is
      C : constant Float := Cos (Angle);
      S : constant Float := Sin (Angle);
      M : Mat4 := Identity;
   begin
      M (0) := C;
      M (1) := S;
      M (4) := -S;
      M (5) := C;
      return M;
   end Rotation_Z;

   function Inverse (M : Mat4) return Mat4 is
      Inv : Mat4;
      Det : Float;
   begin
      Inv (0) := M (5) * M (10) * M (15) - M (5) * M (11) * M (14) - M (9) * M (6) * M (15)
        + M (9) * M (7) * M (14) + M (13) * M (6) * M (11) - M (13) * M (7) * M (10);
      Inv (4) := -M (4) * M (10) * M (15) + M (4) * M (11) * M (14) + M (8) * M (6) * M (15)
        - M (8) * M (7) * M (14) - M (12) * M (6) * M (11) + M (12) * M (7) * M (10);
      Inv (8) := M (4) * M (9) * M (15) - M (4) * M (11) * M (13) - M (8) * M (5) * M (15)
        + M (8) * M (7) * M (13) + M (12) * M (5) * M (11) - M (12) * M (7) * M (9);
      Inv (12) := -M (4) * M (9) * M (14) + M (4) * M (10) * M (13) + M (8) * M (5) * M (14)
        - M (8) * M (6) * M (13) - M (12) * M (5) * M (10) + M (12) * M (6) * M (9);
      Inv (1) := -M (1) * M (10) * M (15) + M (1) * M (11) * M (14) + M (9) * M (2) * M (15)
        - M (9) * M (3) * M (14) - M (13) * M (2) * M (11) + M (13) * M (3) * M (10);
      Inv (5) := M (0) * M (10) * M (15) - M (0) * M (11) * M (14) - M (8) * M (2) * M (15)
        + M (8) * M (3) * M (14) + M (12) * M (2) * M (11) - M (12) * M (3) * M (10);
      Inv (9) := -M (0) * M (9) * M (15) + M (0) * M (11) * M (13) + M (8) * M (1) * M (15)
        - M (8) * M (3) * M (13) - M (12) * M (1) * M (11) + M (12) * M (3) * M (9);
      Inv (13) := M (0) * M (9) * M (14) - M (0) * M (10) * M (13) - M (8) * M (1) * M (14)
        + M (8) * M (2) * M (13) + M (12) * M (1) * M (10) - M (12) * M (2) * M (9);
      Inv (2) := M (1) * M (6) * M (15) - M (1) * M (7) * M (14) - M (5) * M (2) * M (15)
        + M (5) * M (3) * M (14) + M (13) * M (2) * M (7) - M (13) * M (3) * M (6);
      Inv (6) := -M (0) * M (6) * M (15) + M (0) * M (7) * M (14) + M (4) * M (2) * M (15)
        - M (4) * M (3) * M (14) - M (12) * M (2) * M (7) + M (12) * M (3) * M (6);
      Inv (10) := M (0) * M (5) * M (15) - M (0) * M (7) * M (13) - M (4) * M (1) * M (15)
        + M (4) * M (3) * M (13) + M (12) * M (1) * M (7) - M (12) * M (3) * M (5);
      Inv (14) := -M (0) * M (5) * M (14) + M (0) * M (6) * M (13) + M (4) * M (1) * M (14)
        - M (4) * M (2) * M (13) - M (12) * M (1) * M (6) + M (12) * M (2) * M (5);
      Inv (3) := -M (1) * M (6) * M (11) + M (1) * M (7) * M (10) + M (5) * M (2) * M (11)
        - M (5) * M (3) * M (10) - M (9) * M (2) * M (7) + M (9) * M (3) * M (6);
      Inv (7) := M (0) * M (6) * M (11) - M (0) * M (7) * M (10) - M (4) * M (2) * M (11)
        + M (4) * M (3) * M (10) + M (8) * M (2) * M (7) - M (8) * M (3) * M (6);
      Inv (11) := -M (0) * M (5) * M (11) + M (0) * M (7) * M (9) + M (4) * M (1) * M (11)
        - M (4) * M (3) * M (9) - M (8) * M (1) * M (7) + M (8) * M (3) * M (5);
      Inv (15) := M (0) * M (5) * M (10) - M (0) * M (6) * M (9) - M (4) * M (1) * M (10)
        + M (4) * M (2) * M (9) + M (8) * M (1) * M (6) - M (8) * M (2) * M (5);
      Det := M (0) * Inv (0) + M (1) * Inv (4) + M (2) * Inv (8) + M (3) * Inv (12);
      if abs Det < 1.0E-20 then
         return Identity;
      end if;
      for I in Inv'Range loop
         Inv (I) := Inv (I) / Det;
      end loop;
      return Inv;
   end Inverse;

end Math3D;
