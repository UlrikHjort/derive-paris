--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Small vector/matrix library.  Matrices are column-major like OpenGL.

package Math3D is

   type Vec3 is record
      X, Y, Z : Float;
   end record;

   function "+" (A, B : Vec3) return Vec3 is (A.X + B.X, A.Y + B.Y, A.Z + B.Z);
   function "-" (A, B : Vec3) return Vec3 is (A.X - B.X, A.Y - B.Y, A.Z - B.Z);
   function "*" (S : Float; A : Vec3) return Vec3 is (S * A.X, S * A.Y, S * A.Z);
   function Dot (A, B : Vec3) return Float is (A.X * B.X + A.Y * B.Y + A.Z * B.Z);
   function Cross (A, B : Vec3) return Vec3 is
     (A.Y * B.Z - A.Z * B.Y, A.Z * B.X - A.X * B.Z, A.X * B.Y - A.Y * B.X);
   function Length (A : Vec3) return Float;
   function Normalize (A : Vec3) return Vec3;
   function Lerp (A, B : Vec3; T : Float) return Vec3 is (A + T * (B - A));

   type Mat4 is array (0 .. 15) of aliased Float;
   pragma Convention (C, Mat4);

   Identity : constant Mat4 :=
     (1.0, 0.0, 0.0, 0.0,
      0.0, 1.0, 0.0, 0.0,
      0.0, 0.0, 1.0, 0.0,
      0.0, 0.0, 0.0, 1.0);

   function "*" (A, B : Mat4) return Mat4;

   function Perspective (Fov_Y, Aspect, Near, Far : Float) return Mat4;
   function Ortho (L, R, B, T, N, F : Float) return Mat4;
   function Look_At (Eye, Target, Up : Vec3) return Mat4;
   function Translation (V : Vec3) return Mat4;
   function Scale (S : Float) return Mat4 is
     (S, 0.0, 0.0, 0.0,  0.0, S, 0.0, 0.0,  0.0, 0.0, S, 0.0,  0.0, 0.0, 0.0, 1.0);
   --  The same in every direction
   function Rotation_Y (Angle : Float) return Mat4;
   function Rotation_X (Angle : Float) return Mat4;
   function Rotation_Z (Angle : Float) return Mat4;
   function Inverse (M : Mat4) return Mat4;

end Math3D;
