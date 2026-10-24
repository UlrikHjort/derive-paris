--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions;
with Ada.Text_IO;

with Geo;

package body River is

   use Ada.Numerics.Elementary_Functions;

   Half_Width : constant := 24.0;   --  of the part counted as open water

   Max : constant := 200;
   type Point is record
      X, Z : Float;
   end record;
   Line   : array (1 .. Max) of Point;
   Count  : Natural := 0;
   Loaded : Boolean := False;
   X0, X1, Z0, Z1 : Float := 0.0;   --  the box round it all

   procedure Load is
      F : Ada.Text_IO.File_Type;
   begin
      Loaded := True;
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, "data/seine.txt");
      while not Ada.Text_IO.End_Of_File (F) and then Count < Max loop
         declare
            L  : constant String := Ada.Text_IO.Get_Line (F);
            Sp : Natural := 0;
            X, Z : Long_Float;
         begin
            if L'Length > 0 and then L (L'First) /= '#' then
               for I in L'Range loop
                  if L (I) = ' ' then
                     Sp := I;
                     exit;
                  end if;
               end loop;
               if Sp > 0 then
                  Geo.To_Local (Long_Float'Value (L (L'First .. Sp - 1)), Long_Float'Value (L (Sp + 1 .. L'Last)),
                                X, Z);
                  Count := Count + 1;
                  Line (Count) := (Float (X), Float (Z));
               end if;
            end if;
         exception
            when Constraint_Error => null;
         end;
      end loop;
      Ada.Text_IO.Close (F);
      if Count > 0 then
         X0 := Line (1).X;
         X1 := X0;
         Z0 := Line (1).Z;
         Z1 := Z0;
         for P of Line (1 .. Count) loop
            X0 := Float'Min (X0, P.X);
            X1 := Float'Max (X1, P.X);
            Z0 := Float'Min (Z0, P.Z);
            Z1 := Float'Max (Z1, P.Z);
         end loop;
      end if;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
   end Load;

   function Length return Float is
      L : Float := 0.0;
   begin
      if not Loaded then
         Load;
      end if;
      for I in 1 .. Count - 1 loop
         L := L + Sqrt ((Line (I + 1).X - Line (I).X) ** 2 + (Line (I + 1).Z - Line (I).Z) ** 2);
      end loop;
      return L;
   end Length;

   procedure At_Distance (S : Float; X, Z, DX, DZ : out Float) is
      Left : Float := Float'Max (0.0, S);
   begin
      if not Loaded then
         Load;
      end if;
      X := 0.0;
      Z := 0.0;
      DX := 1.0;
      DZ := 0.0;
      for I in 1 .. Count - 1 loop
         declare
            A : constant Point := Line (I);
            B : constant Point := Line (I + 1);
            L : constant Float := Sqrt ((B.X - A.X) ** 2 + (B.Z - A.Z) ** 2);
         begin
            if L > 0.01 then
               DX := (B.X - A.X) / L;
               DZ := (B.Z - A.Z) / L;
               if Left <= L or else I = Count - 1 then
                  X := A.X + Float'Min (Left, L) * DX;
                  Z := A.Z + Float'Min (Left, L) * DZ;
                  return;
               end if;
               Left := Left - L;
            end if;
         end;
      end loop;
   end At_Distance;

   function Distance_Of (X, Z : Float) return Float is
      Best, Best_S, Run : Float := 0.0;
      First : Boolean := True;
   begin
      if not Loaded then
         Load;
      end if;
      for I in 1 .. Count - 1 loop
         declare
            A  : constant Point := Line (I);
            B  : constant Point := Line (I + 1);
            DX : constant Float := B.X - A.X;
            DZ : constant Float := B.Z - A.Z;
            L2 : constant Float := Float'Max (1.0E-6, DX * DX + DZ * DZ);
            T  : constant Float := Float'Max (0.0, Float'Min (1.0, ((X - A.X) * DX + (Z - A.Z) * DZ) / L2));
            D2 : constant Float := (A.X + T * DX - X) ** 2 + (A.Z + T * DZ - Z) ** 2;
         begin
            if First or else D2 < Best then
               First := False;
               Best := D2;
               Best_S := Run + T * Sqrt (L2);
            end if;
            Run := Run + Sqrt (L2);
         end;
      end loop;
      return Best_S;
   end Distance_Of;

   function In_Channel (X, Z : Float) return Boolean is
   begin
      if not Loaded then
         Load;
      end if;
      if Count < 2 or else X < X0 - Half_Width or else X > X1 + Half_Width
        or else Z < Z0 - Half_Width or else Z > Z1 + Half_Width
      then
         return False;
      end if;
      for I in 1 .. Count - 1 loop
         declare
            A  : constant Point := Line (I);
            B  : constant Point := Line (I + 1);
            DX : constant Float := B.X - A.X;
            DZ : constant Float := B.Z - A.Z;
            L2 : constant Float := DX * DX + DZ * DZ;
            T  : constant Float :=
              (if L2 > 0.0 then Float'Max (0.0, Float'Min (1.0, ((X - A.X) * DX + (Z - A.Z) * DZ) / L2)) else 0.0);
            PX : constant Float := A.X + T * DX - X;
            PZ : constant Float := A.Z + T * DZ - Z;
         begin
            if PX * PX + PZ * PZ < Half_Width ** 2 then
               return True;
            end if;
         end;
      end loop;
      return False;
   end In_Channel;

end River;
