--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Small GPU meshes built from boxes (the cars, the plane, pedestrians),
--  in the world shader's vertex format.

with GL;
with Math3D;

package Meshes is

   type Mesh is record
      VAO, VBO, EBO : aliased GL.GLuint := 0;
      Count         : Natural := 0;
   end record;

   --  Material codes of world.frag used by these meshes
   Mat_Paint     : constant := 15.0;   --  uCarColor, glossy
   Mat_Glass     : constant := 16.0;
   Mat_Tyre      : constant := 17.0;
   Mat_Headlight : constant := 18.0;
   Mat_Taillight : constant := 19.0;
   Mat_Cloth     : constant := 30.0;   --  uCarColor, matt
   Mat_Skin      : constant := 31.0;   --  uExtraColor
   Mat_Trousers  : constant := 32.0;   --  uExtraColor2

   procedure Start;
   --  Begin a new mesh

   procedure Quad (A, B, C, D : Math3D.Vec3; Mat : Float);

   procedure Quad_UV (A, B, C, D : Math3D.Vec3; N : Math3D.Vec3; Mat, Seed : Float;
                      U_Size, V_Size : Float := 1.0);
   --  With texture coordinates (A 0,0  B 1,0  C 1,1  D 0,1) and a seed

   procedure Box (X0, X1, Y0, Y1, Z0, Z1 : Float; Mat : Float;
                  Top_Inset_X     : Float := 0.0;
                  Top_Inset_Front : Float := 0.0;
                  Top_Inset_Back  : Float := 0.0;
                  Side_Mat        : Float := -1.0);
   --  A box, optionally with a narrower or shorter top (Z0 is the front,
   --  -Z); Side_Mat gives the four sides another material

   procedure Finish (M : out Mesh);
   --  Upload what was built since Start (GL context must be current)

   procedure Draw (M : Mesh);

   procedure Free (M : in out Mesh);
   --  Give the GPU memory back

end Meshes;
