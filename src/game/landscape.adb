--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Math3D;
with Meshes;
with Terrain;

package body Landscape is

   Sheet : Meshes.Mesh;
   Built : Boolean := False;

   Cell  : constant := 60.0;   --  metres
   Below : constant := 9.0;    --  under the streets (and under the river)

   procedure Create is
      X0, Z0, X1, Z1 : Float;
   begin
      if not Terrain.Loaded then
         return;
      end if;
      Terrain.Bounds (X0, Z0, X1, Z1);
      Meshes.Start;
      declare
         NX : constant Positive := Positive (Float'Ceiling ((X1 - X0) / Cell));
         NZ : constant Positive := Positive (Float'Ceiling ((Z1 - Z0) / Cell));
         function P (I, J : Natural) return Math3D.Vec3 is
            X : constant Float := X0 + Float (I) * Cell;
            Z : constant Float := Z0 + Float (J) * Cell;
         begin
            return (X, Terrain.Height (X, Z) - Below, Z);
         end P;
      begin
         for J in 0 .. NZ - 1 loop
            for I in 0 .. NX - 1 loop
               --  wound so that the face looks up
               Meshes.Quad (P (I, J), P (I, J + 1), P (I + 1, J + 1), P (I + 1, J), 0.0);
            end loop;
         end loop;
      end;
      Meshes.Finish (Sheet);
      Built := True;
   end Create;

   procedure Draw is
   begin
      if Built then
         Meshes.Draw (Sheet);
      end if;
   end Draw;

end Landscape;
