with Ada.Containers.Vectors;
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
      V : array (0 .. Natural (Verts.Length) - 1) of aliased Float;
      I : array (0 .. Natural (Index.Length) - 1) of aliased Interfaces.Unsigned_32;
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
      Start;
   end Finish;

   procedure Draw (M : Mesh) is
      use GL;
   begin
      glBindVertexArray (M.VAO);
      glDrawElements (GL_TRIANGLES, GLsizei (M.Count), GL_UNSIGNED_INT,
                      System.Null_Address);
      glBindVertexArray (0);
   end Draw;

end Meshes;
