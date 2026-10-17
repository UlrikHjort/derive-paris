--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Directories;
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Text_IO;

with Math3D;
with Meshes;
with Shaders;

package body Tower is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Is_Known : Boolean := False;
   CX, CZ   : Float := 0.0;    --  centre
   UX, UZ   : Float := 1.0;    --  one axis of the tower (V is across it)
   Floor_Y  : Float := 0.0;
   Deck     : Float := 5.0;    --  half size of the platform
   Spire    : Float := 3.5;    --  half size of the spire's foot
   Foot     : Float := 30.0;   --  half size of the opening between the legs
   Railing  : Meshes.Mesh;
   Built    : Boolean := False;

   function Known return Boolean is (Is_Known);
   function Top_Floor_Y return Float is (Floor_Y);

   procedure Load (File_Name : String) is
      F : Ada.Text_IO.File_Type;
      package F_IO is new Ada.Text_IO.Float_IO (Float);
   begin
      if not Ada.Directories.Exists (File_Name) then
         return;
      end if;
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, File_Name);
      Ada.Text_IO.Skip_Line (F);   --  the comment
      F_IO.Get (F, CX);
      F_IO.Get (F, CZ);
      F_IO.Get (F, UX);
      F_IO.Get (F, UZ);
      F_IO.Get (F, Floor_Y);
      F_IO.Get (F, Deck);
      F_IO.Get (F, Spire);
      F_IO.Get (F, Foot);
      Ada.Text_IO.Close (F);
      Is_Known := True;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
   end Load;

   --  Local coordinates: U along the tower's axis, V across it
   procedure To_UV (X, Z : Float; U, V : out Float) is
   begin
      U := (X - CX) * UX + (Z - CZ) * UZ;
      V := -(X - CX) * UZ + (Z - CZ) * UX;
   end To_UV;

   procedure From_UV (U, V : Float; X, Z : out Float) is
   begin
      X := CX + U * UX - V * UZ;
      Z := CZ + U * UZ + V * UX;
   end From_UV;

   function Under (X, Z : Float) return Boolean is
      U, V : Float;
   begin
      if not Is_Known then
         return False;
      end if;
      To_UV (X, Z, U, V);
      return abs U < 0.45 * Foot and then abs V < 0.45 * Foot;
   end Under;

   procedure Arrival (X, Z, Yaw : out Float) is
      U : constant Float := 0.0;
      V : constant Float := 0.5 * (Deck + Spire);   --  on the walkway
   begin
      From_UV (U, V, X, Z);
      --  looking outwards, along +V
      declare
         DX : constant Float := -UZ;
         DZ : constant Float := UX;
      begin
         Yaw := Arctan (DX, -DZ);
      end;
   end Arrival;

   procedure Ground (X, Z, Yaw : out Float) is
   begin
      From_UV (0.0, 0.3 * Foot, X, Z);
      Yaw := Arctan (UZ, -(-UX));
   end Ground;

   procedure Keep_On_Deck (X, Z : in out Float) is
      U, V : Float;
      Inner : constant Float := Spire + 0.4;
      Outer : constant Float := Deck - 0.35;
   begin
      To_UV (X, Z, U, V);
      U := Float'Max (-Outer, Float'Min (Outer, U));
      V := Float'Max (-Outer, Float'Min (Outer, V));
      --  not into the spire: out to the nearest side of it
      if abs U < Inner and then abs V < Inner then
         if Inner - abs U < Inner - abs V then
            U := (if U < 0.0 then -Inner else Inner);
         else
            V := (if V < 0.0 then -Inner else Inner);
         end if;
      end if;
      From_UV (U, V, X, Z);
   end Keep_On_Deck;

   procedure Create is
      Mat_Railing : constant := 34.0;
      Mat_Iron    : constant := 17.0;
      procedure Side (U0, V0, U1, V1 : Float) is
         X0, Z0, X1, Z1 : Float;
         A, B : Vec3;
      begin
         From_UV (U0, V0, X0, Z0);
         From_UV (U1, V1, X1, Z1);
         A := (X0, Floor_Y, Z0);
         B := (X1, Floor_Y, Z1);
         --  the railing net up to chest height, and an iron rail on top
         Meshes.Quad_UV (A, B, B + Vec3'(0.0, 1.25, 0.0), A + Vec3'(0.0, 1.25, 0.0),
                         Normalize (Cross (B - A, (0.0, 1.0, 0.0))), Mat_Railing, 0.0,
                         Length (B - A), 1.25);
         Meshes.Box (Float'Min (X0, X1) - 0.04, Float'Max (X0, X1) + 0.04,
                     Floor_Y + 1.22, Floor_Y + 1.3,
                     Float'Min (Z0, Z1) - 0.04, Float'Max (Z0, Z1) + 0.04, Mat_Iron);
      end Side;
      D : constant Float := Deck;
   begin
      if not Is_Known then
         return;
      end if;
      Meshes.Start;
      Side (-D, -D, D, -D);
      Side (D, -D, D, D);
      Side (D, D, -D, D);
      Side (-D, D, -D, -D);
      Meshes.Finish (Railing);
      Built := True;
   end Create;

   procedure Draw (Model : GL.GLint) is
   begin
      if Built then
         Shaders.Set (Model, Identity);
         Meshes.Draw (Railing);
      end if;
   end Draw;

end Tower;
