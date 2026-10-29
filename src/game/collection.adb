--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Interfaces;

package body Collection is

   package Line_Vectors is new Ada.Containers.Indefinite_Vectors (Positive, String);

   type Section is record
      Name  : String (1 .. 16) := (others => ' ');
      Lines : Line_Vectors.Vector;
   end record;
   Sections : array (1 .. 8) of Section;
   N_Sections : Natural := 0;
   Loaded : Boolean := False;

   procedure Load is
      use type Interfaces.Unsigned_8;
      Key : constant String := "derive-paris";
      F   : Ada.Text_IO.File_Type;
      function Plain (Hex : String) return String is
         R : String (1 .. Hex'Length / 2);
      begin
         for I in R'Range loop
            R (I) := Character'Val
              (Interfaces.Unsigned_8'Value ("16#" & Hex (Hex'First + 2 * (I - 1) .. Hex'First + 2 * I - 1) & "#")
               xor Interfaces.Unsigned_8 (Character'Pos (Key (Key'First + (I - 1) mod Key'Length))));
         end loop;
         return R;
      end Plain;
   begin
      Loaded := True;
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, "data/collection.dat");
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            L : constant String := Ada.Text_IO.Get_Line (F);
         begin
            if L'Length > 2 and then L (L'First) = '[' and then N_Sections < Sections'Last then
               N_Sections := N_Sections + 1;
               Ada.Strings.Fixed.Move (L (L'First + 1 .. L'Last - 1), Sections (N_Sections).Name);
            elsif L'Length > 1 and then N_Sections > 0 then
               Sections (N_Sections).Lines.Append (Plain (L));
            end if;
         exception
            when Constraint_Error => null;
         end;
      end loop;
      Ada.Text_IO.Close (F);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
   end Load;

   function Find (Name : String) return Natural is
   begin
      if not Loaded then
         Load;
      end if;
      for I in 1 .. N_Sections loop
         if Ada.Strings.Fixed.Trim (Sections (I).Name, Ada.Strings.Right) = Name then
            return I;
         end if;
      end loop;
      return 0;
   end Find;

   function Word (Section : String; I : Positive) return String is
      S : constant Natural := Find (Section);
   begin
      if S = 0 or else I > Natural (Sections (S).Lines.Length) then
         return "";
      end if;
      return Sections (S).Lines (I);
   end Word;

   function Panel (I : Positive) return String is (Word ("lilies", I));
   function Painter (P : Natural) return String is (Word ("painters", P + 1));

   function Works return Natural is
      S : constant Natural := Find ("works");
   begin
      return (if S = 0 then 0 else Natural (Sections (S).Lines.Length));
   end Works;

   --  a work's line: painter|title|year
   function Field (I : Positive; N : Positive) return String is
      L : constant String := Word ("works", I);
      Start : Positive := L'First;
      K : Positive := 1;
   begin
      for J in L'Range loop
         if L (J) = '|' then
            if K = N then
               return L (Start .. J - 1);
            end if;
            K := K + 1;
            Start := J + 1;
         end if;
      end loop;
      return (if K = N then L (Start .. L'Last) else "");
   end Field;

   function Work_Painter (I : Positive) return Natural is
   begin
      return Natural'Value (Field (I, 1));
   exception
      when Constraint_Error =>
         return 0;
   end Work_Painter;

   function Work_Title (I : Positive) return String is (Field (I, 2));
   function Work_Year (I : Positive) return String is (Field (I, 3));

end Collection;
