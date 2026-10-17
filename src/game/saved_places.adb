--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

package body Saved_Places is

   use Ada.Strings.Unbounded;

   type Place is record
      Name     : Unbounded_String;
      Lat, Lon : Long_Float;
   end record;

   package Place_Vectors is new Ada.Containers.Vectors (Positive, Place);
   List : Place_Vectors.Vector;

   function File_Name return String is
     (Ada.Environment_Variables.Value ("HOME", ".") & "/.derive_places");

   --  Fixed six decimals (about 10 cm), no exponent
   function Image (V : Long_Float) return String is
      Micro : constant Long_Long_Integer := Long_Long_Integer (V * 1.0E6);
      Whole : constant String := Long_Long_Integer'Image (abs Micro / 1_000_000);
      Frac  : constant String := Long_Long_Integer'Image (1_000_000 + abs Micro mod 1_000_000);
   begin
      return (if Micro < 0 then "-" else "") & Whole (Whole'First + 1 .. Whole'Last)
        & "." & Frac (Frac'First + 2 .. Frac'Last);
   end Image;

   procedure Save is
      F : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, File_Name);
      Ada.Text_IO.Put_Line (F, "# Places saved in Derive (L in the game): latitude longitude name");
      for P of List loop
         Ada.Text_IO.Put_Line (F, Image (P.Lat) & " " & Image (P.Lon) & " " & To_String (P.Name));
      end loop;
      Ada.Text_IO.Close (F);
   exception
      when others =>
         Ada.Text_IO.Put_Line ("Could not write " & File_Name);
   end Save;

   procedure Load is
      use Ada.Strings.Fixed;
      F : Ada.Text_IO.File_Type;
   begin
      List.Clear;
      if not Ada.Directories.Exists (File_Name) then
         return;
      end if;
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, File_Name);
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            Line : constant String := Trim (Ada.Text_IO.Get_Line (F), Ada.Strings.Both);
            S1   : constant Natural := Index (Line, " ");
            S2   : constant Natural := (if S1 = 0 then 0 else Index (Line (S1 + 1 .. Line'Last), " "));
         begin
            if Line'Length > 0 and then Line (Line'First) /= '#' and then S2 > 0 then
               List.Append
                 ((Name => To_Unbounded_String (Trim (Line (S2 + 1 .. Line'Last), Ada.Strings.Both)),
                   Lat  => Long_Float'Value (Line (Line'First .. S1 - 1)),
                   Lon  => Long_Float'Value (Line (S1 + 1 .. S2 - 1))));
            end if;
         exception
            when Constraint_Error => null;   --  skip a bad line
         end;
      end loop;
      Ada.Text_IO.Close (F);
   exception
      when others =>
         Ada.Text_IO.Put_Line ("Could not read " & File_Name);
   end Load;

   function Count return Natural is (Natural (List.Length));
   function Name (I : Positive) return String is (To_String (List (I).Name));
   function Lat (I : Positive) return Long_Float is (List (I).Lat);
   function Lon (I : Positive) return Long_Float is (List (I).Lon);

   procedure Add (Name : String; Lat, Lon : Long_Float) is
   begin
      if Count >= Max then
         List.Delete_First;
      end if;
      List.Append ((To_Unbounded_String (Name), Lat, Lon));
      Save;
   end Add;

   procedure Remove (I : Positive) is
   begin
      if I <= Count then
         List.Delete (I);
         Save;
      end if;
   end Remove;

end Saved_Places;
