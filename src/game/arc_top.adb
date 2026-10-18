--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Directories;
with Ada.Numerics.Elementary_Functions;
with Ada.Text_IO;

with Geo;
with Math3D;
with Meshes;
with Shaders;

package body Arc_Top is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Is_Known : Boolean := False;
   CX, CZ   : Float := 0.0;    --  centre
   UX, UZ   : Float := 1.0;    --  along the facade (V runs through the vault)
   Top_Y    : Float := 0.0;
   HU, HV   : Float := 22.0;   --  half the size of the roof
   Vault    : Float := 7.0;    --  half the width of the great vault
   Railing  : Meshes.Mesh;
   Built    : Boolean := False;

   function Known return Boolean is (Is_Known);
   function Roof_Y return Float is (Top_Y);

   procedure Centre (X, Z : out Float) is
   begin
      X := CX;
      Z := CZ;
   end Centre;

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
      F_IO.Get (F, Top_Y);
      F_IO.Get (F, HU);
      F_IO.Get (F, HV);
      F_IO.Get (F, Vault);
      Ada.Text_IO.Close (F);
      Is_Known := True;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
   end Load;

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

   --  Which way along V the Champs-Élysées runs (towards Concorde)
   function Champs_Side return Float is
      X, Z : Long_Float;
      U, V : Float;
   begin
      Geo.To_Local (48.86560, 2.32120, X, Z);
      To_UV (Float (X), Float (Z), U, V);
      return (if V >= 0.0 then 1.0 else -1.0);
   end Champs_Side;

   procedure Front (AX, AZ, BX, BZ, Out_X, Out_Z : out Float) is
      S : constant Float := Champs_Side;
   begin
      From_UV (-HU, S * (HV + 0.4), AX, AZ);
      From_UV (HU, S * (HV + 0.4), BX, BZ);
      Out_X := -S * UZ;
      Out_Z := S * UX;
   end Front;

   function Under (X, Z : Float) return Boolean is
      U, V : Float;
   begin
      if not Is_Known then
         return False;
      end if;
      To_UV (X, Z, U, V);
      return abs U < 0.8 * Vault and then abs V < 0.6 * HV;
   end Under;

   procedure Arrival (X, Z, Yaw : out Float) is
      S : constant Float := Champs_Side;
   begin
      --  a few steps from the railing over the avenue, looking down it
      From_UV (0.0, S * (HV - 4.5), X, Z);
      Yaw := Arctan (S * (-UZ), -(S * UX));
   end Arrival;

   procedure Ground (X, Z, Yaw : out Float) is
      S : constant Float := Champs_Side;
   begin
      --  out on the Champs-Élysées side, looking back up at the arch
      From_UV (0.0, S * (HV + 5.0), X, Z);
      Yaw := Arctan (-S * (-UZ), S * UX);
   end Ground;

   procedure Keep_On_Roof (X, Z : in out Float) is
      U, V : Float;
   begin
      To_UV (X, Z, U, V);
      U := Float'Max (-(HU - 0.6), Float'Min (HU - 0.6, U));
      V := Float'Max (-(HV - 0.6), Float'Min (HV - 0.6, V));
      From_UV (U, V, X, Z);
   end Keep_On_Roof;

   procedure Create is
      Mat_Railing : constant := 34.0;
      Mat_Iron    : constant := 17.0;
      procedure Side (U0, V0, U1, V1 : Float) is
         X0, Z0, X1, Z1 : Float;
         A, B : Vec3;
      begin
         From_UV (U0, V0, X0, Z0);
         From_UV (U1, V1, X1, Z1);
         A := (X0, Top_Y, Z0);
         B := (X1, Top_Y, Z1);
         --  railing to chest height, an iron rail along the top
         Meshes.Quad_UV (A, B, B + Vec3'(0.0, 1.2, 0.0), A + Vec3'(0.0, 1.2, 0.0),
                         Normalize (Cross (B - A, (0.0, 1.0, 0.0))), Mat_Railing, 0.0,
                         Length (B - A), 1.2);
         Meshes.Quad_UV (B, A, A + Vec3'(0.0, 1.2, 0.0), B + Vec3'(0.0, 1.2, 0.0),
                         Normalize (Cross (A - B, (0.0, 1.0, 0.0))), Mat_Railing, 0.0,
                         Length (B - A), 1.2);
         --  the rail: a flat top and two faces, along the side
         declare
            N  : constant Vec3 := 0.05 * Normalize (Cross (B - A, (0.0, 1.0, 0.0)));
            Lo : constant Vec3 := (0.0, 1.17, 0.0);
            Hi : constant Vec3 := (0.0, 1.17 + 0.08, 0.0);
         begin
            Meshes.Quad (A + Hi - N, A + Hi + N, B + Hi + N, B + Hi - N, Mat_Iron);
            Meshes.Quad (A + Lo + N, B + Lo + N, B + Hi + N, A + Hi + N, Mat_Iron);
            Meshes.Quad (B + Lo - N, A + Lo - N, A + Hi - N, B + Hi - N, Mat_Iron);
         end;
      end Side;
      U : constant Float := HU - 0.3;
      V : constant Float := HV - 0.3;
   begin
      if not Is_Known then
         return;
      end if;
      Meshes.Start;
      Side (-U, -V, U, -V);
      Side (U, -V, U, V);
      Side (U, V, -U, V);
      Side (-U, V, -U, -V);
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

end Arc_Top;
