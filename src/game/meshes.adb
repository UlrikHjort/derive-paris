--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Containers.Vectors;
with Ada.Unchecked_Deallocation;
with Interfaces;
with System.Storage_Elements;

package body Meshes is

   use Math3D;
   use type Interfaces.Unsigned_32;

   package Float_Vectors is new Ada.Containers.Vectors (Natural, Float);
   package U32_Vectors is new Ada.Containers.Vectors (Natural, Interfaces.Unsigned_32);

   Verts : Float_Vectors.Vector;
   Index : U32_Vectors.Vector;

   procedure Start is
   begin
      Verts.Clear;
      Index.Clear;
   end Start;

   procedure Vertex (P, N : Vec3; Mat : Float) is
   begin
      Verts.Append (P.X);
      Verts.Append (P.Y);
      Verts.Append (P.Z);
      Verts.Append (N.X);
      Verts.Append (N.Y);
      Verts.Append (N.Z);
      Verts.Append (0.0);
      Verts.Append (0.0);
      Verts.Append (Mat);
      Verts.Append (0.0);
   end Vertex;

   --  A quad with texture coordinates (A: 0,0  B: 1,0  C: 1,1  D: 0,1), a
   --  seed, and the normal it should have (the corners are ordered so)
   procedure Quad_UV (A, B, C, D : Vec3; N : Vec3; Mat, Seed : Float;
                      U_Size, V_Size : Float := 1.0) is
      Base : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Natural (Verts.Length) / 10);
      procedure Put (P : Vec3; U, V : Float) is
      begin
         Verts.Append (P.X);
         Verts.Append (P.Y);
         Verts.Append (P.Z);
         Verts.Append (N.X);
         Verts.Append (N.Y);
         Verts.Append (N.Z);
         Verts.Append (U);
         Verts.Append (V);
         Verts.Append (Mat);
         Verts.Append (Seed);
      end Put;
   begin
      Put (A, 0.0, 0.0);
      Put (B, U_Size, 0.0);
      Put (C, U_Size, V_Size);
      Put (D, 0.0, V_Size);
      Index.Append (Base);
      Index.Append (Base + 1);
      Index.Append (Base + 2);
      Index.Append (Base);
      Index.Append (Base + 2);
      Index.Append (Base + 3);
   end Quad_UV;

   procedure Quad (A, B, C, D : Vec3; Mat : Float) is
      Base : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Natural (Verts.Length) / 10);
      N : constant Vec3 := Normalize (Cross (B - A, D - A));
   begin
      Vertex (A, N, Mat);
      Vertex (B, N, Mat);
      Vertex (C, N, Mat);
      Vertex (D, N, Mat);
      Index.Append (Base);
      Index.Append (Base + 1);
      Index.Append (Base + 2);
      Index.Append (Base);
      Index.Append (Base + 2);
      Index.Append (Base + 3);
   end Quad;

   procedure Box (X0, X1, Y0, Y1, Z0, Z1 : Float; Mat : Float;
                  Top_Inset_X     : Float := 0.0;
                  Top_Inset_Front : Float := 0.0;
                  Top_Inset_Back  : Float := 0.0;
                  Side_Mat        : Float := -1.0)
   is
      SM : constant Float := (if Side_Mat < 0.0 then Mat else Side_Mat);
      B000 : constant Vec3 := (X0, Y0, Z0);
      B100 : constant Vec3 := (X1, Y0, Z0);
      B001 : constant Vec3 := (X0, Y0, Z1);
      B101 : constant Vec3 := (X1, Y0, Z1);
      T010 : constant Vec3 := (X0 + Top_Inset_X, Y1, Z0 + Top_Inset_Front);
      T110 : constant Vec3 := (X1 - Top_Inset_X, Y1, Z0 + Top_Inset_Front);
      T011 : constant Vec3 := (X0 + Top_Inset_X, Y1, Z1 - Top_Inset_Back);
      T111 : constant Vec3 := (X1 - Top_Inset_X, Y1, Z1 - Top_Inset_Back);
   begin
      Quad (T010, T011, T111, T110, Mat);          --  top
      Quad (B000, B100, B101, B001, Mat);          --  bottom
      Quad (B000, T010, T110, B100, SM);           --  front
      Quad (B101, T111, T011, B001, SM);           --  back
      Quad (B001, T011, T010, B000, SM);           --  left
      Quad (B100, T110, T111, B101, SM);           --  right
   end Box;

   function Offset (Bytes : Natural) return System.Address is
     (System.Storage_Elements.To_Address
        (System.Storage_Elements.Integer_Address (Bytes)));

   procedure Finish (M : out Mesh) is
      use GL;
      Stride : constant := 40;
      --  on the heap: a big mesh (a whole cemetery) would not fit the stack
      type Float_Array is array (Natural range <>) of aliased Float;
      type U32_Array is array (Natural range <>) of aliased Interfaces.Unsigned_32;
      type Float_Access is access Float_Array;
      type U32_Access is access U32_Array;
      procedure Free is new Ada.Unchecked_Deallocation (Float_Array, Float_Access);
      procedure Free is new Ada.Unchecked_Deallocation (U32_Array, U32_Access);
      VA : Float_Access := new Float_Array (0 .. Natural (Verts.Length) - 1);
      IA : U32_Access := new U32_Array (0 .. Natural (Index.Length) - 1);
      V  : Float_Array renames VA.all;
      I  : U32_Array renames IA.all;
   begin
      for K in V'Range loop
         V (K) := Verts (K);
      end loop;
      for K in I'Range loop
         I (K) := Index (K);
      end loop;
      M.Count := I'Length;
      glGenVertexArrays (1, M.VAO'Address);
      glBindVertexArray (M.VAO);
      glGenBuffers (1, M.VBO'Address);
      glBindBuffer (GL_ARRAY_BUFFER, M.VBO);
      glBufferData (GL_ARRAY_BUFFER, GLsizeiptr (V'Length * 4), V'Address, GL_STATIC_DRAW);
      glGenBuffers (1, M.EBO'Address);
      glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, M.EBO);
      glBufferData (GL_ELEMENT_ARRAY_BUFFER, GLsizeiptr (I'Length * 4), I'Address,
                    GL_STATIC_DRAW);
      glVertexAttribPointer (0, 3, GL_FLOAT, GL_FALSE, Stride, Offset (0));
      glEnableVertexAttribArray (0);
      glVertexAttribPointer (1, 3, GL_FLOAT, GL_FALSE, Stride, Offset (12));
      glEnableVertexAttribArray (1);
      glVertexAttribPointer (2, 2, GL_FLOAT, GL_FALSE, Stride, Offset (24));
      glEnableVertexAttribArray (2);
      glVertexAttribPointer (3, 1, GL_FLOAT, GL_FALSE, Stride, Offset (32));
      glEnableVertexAttribArray (3);
      glVertexAttribPointer (4, 1, GL_FLOAT, GL_FALSE, Stride, Offset (36));
      glEnableVertexAttribArray (4);
      glBindVertexArray (0);
      Free (VA);
      Free (IA);
      Start;
   end Finish;

   procedure Free (M : in out Mesh) is
      use GL;
   begin
      if M.Count > 0 then
         glDeleteVertexArrays (1, M.VAO'Address);
         glDeleteBuffers (1, M.VBO'Address);
         glDeleteBuffers (1, M.EBO'Address);
      end if;
      M := (others => <>);
   end Free;

   procedure Draw (M : Mesh) is
      use GL;
   begin
      glBindVertexArray (M.VAO);
      glDrawElements (GL_TRIANGLES, GLsizei (M.Count), GL_UNSIGNED_INT,
                      System.Null_Address);
      glBindVertexArray (0);
   end Draw;

end Meshes;
