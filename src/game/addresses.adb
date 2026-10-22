--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Characters.Handling;
with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Road_Network;

package body Addresses is

   use Ada.Strings.Unbounded;

   type House is record
      Number : Unbounded_String;
      X, Z   : Float;
   end record;
   package House_Vectors is new Ada.Containers.Vectors (Positive, House);

   type Street is record
      Name   : Unbounded_String;    --  as written
      Folded : Unbounded_String;    --  lower case, no accents, for matching
      Houses : House_Vectors.Vector;
      X, Z   : Float := 0.0;        --  somewhere along it
      Has_Point : Boolean := False;
   end record;

   package Street_Maps is new Ada.Containers.Indefinite_Ordered_Maps (String, Street);
   Streets : Street_Maps.Map;   --  by folded name

   --  Lower case, accents off, hyphens and apostrophes to spaces, single
   --  spaces (UTF-8 in, ASCII out)
   function Sqrt_Dist (DX, DZ : Float) return Float;

   function Fold (S : String) return String is
      R : Unbounded_String;
      I : Positive := S'First;
      procedure Add (C : Character) is
      begin
         if C = ' ' then
            if Length (R) > 0 and then Element (R, Length (R)) /= ' ' then
               Append (R, ' ');
            end if;
         else
            Append (R, C);
         end if;
      end Add;
   begin
      while I <= S'Last loop
         declare
            C : constant Character := S (I);
            B : constant Natural := Character'Pos (C);
         begin
            if B < 128 then
               if C = '-' or else C = ''' or else C = ',' or else C = '.' or else C = ' ' then
                  Add (' ');
               else
                  Add (Ada.Characters.Handling.To_Lower (C));
               end if;
               I := I + 1;
            elsif B = 16#C3# and then I < S'Last then
               declare
                  N : constant Natural := Character'Pos (S (I + 1)) mod 16#20#;   --  upper and lower alike
                  M : constant Character :=
                    (case N is
                        when 0 .. 5 => 'a', when 7 => 'c', when 8 .. 11 => 'e', when 12 .. 15 => 'i',
                        when 17 => 'n', when 18 .. 22 => 'o', when 25 .. 28 => 'u', when 29 => 'y',
                        when others => ' ');
               begin
                  Add (M);
               end;
               I := I + 2;
            elsif B = 16#C5# and then I < S'Last and then (Character'Pos (S (I + 1)) = 16#93#
                                                         or else Character'Pos (S (I + 1)) = 16#92#)
            then
               Add ('o');
               Add ('e');
               I := I + 2;
            elsif B >= 16#E0# then
               Add (' ');    --  a typographic apostrophe, a dash...
               I := I + 3;
            else
               I := I + (if B >= 16#C0# then 2 else 1);
            end if;
         end;
      end loop;
      declare
         T : constant String := To_String (R);
      begin
         return Ada.Strings.Fixed.Trim (T, Ada.Strings.Both);
      end;
   end Fold;

   function Entry_For (Name : String) return Street_Maps.Cursor is
      K : constant String := Fold (Name);
   begin
      if not Streets.Contains (K) then
         Streets.Insert (K, (Name => To_Unbounded_String (Name), Folded => To_Unbounded_String (K), others => <>));
      end if;
      return Streets.Find (K);
   end Entry_For;

   procedure Add_House (Name, Number : String; X, Z : Float) is
      C : constant Street_Maps.Cursor := Entry_For (Name);
   begin
      Streets (C).Houses.Append ((To_Unbounded_String (Number), X, Z));
      if not Streets (C).Has_Point then
         Streets (C).X := X;
         Streets (C).Z := Z;
         Streets (C).Has_Point := True;
      end if;
   end Add_House;

   procedure Read_File (Name : String) is
      F : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Name);
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            L  : constant String := Ada.Text_IO.Get_Line (F);
            T1 : constant Natural := Ada.Strings.Fixed.Index (L, (1 => ASCII.HT));
            T2 : constant Natural := (if T1 > 0 then Ada.Strings.Fixed.Index (L, (1 => ASCII.HT), T1 + 1) else 0);
            T3 : constant Natural := (if T2 > 0 then Ada.Strings.Fixed.Index (L, (1 => ASCII.HT), T2 + 1) else 0);
         begin
            if T3 > 0 then
               declare
                  HX : constant Float := Float'Value (L (T2 + 1 .. T3 - 1));
                  HZ : constant Float := Float'Value (L (T3 + 1 .. L'Last));
                  --  without a street: the nearest named one (the number
                  --  is at the door)
                  Named : constant String :=
                    (if T1 > L'First then L (L'First .. T1 - 1)
                     else Road_Network.Street_At (HX, HZ, 35.0));
               begin
                  if Named /= "" and then T2 > T1 + 1 then
                     Add_House (Named, L (T1 + 1 .. T2 - 1), HX, HZ);
                  end if;
               end;
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
   end Read_File;

   procedure Load (Dir : String) is
      use Ada.Directories;
      Search_It : Search_Type;
      Item : Directory_Entry_Type;
   begin
      Streets.Clear;
      --  the named streets themselves
      if Road_Network."/=" (Road_Network.Ways, null) then
         for W in Road_Network.Ways'Range loop
            declare
               Name : constant String := To_String (Road_Network.Ways (W).Name);
            begin
               if Name'Length > 2 then
                  declare
                     C : constant Street_Maps.Cursor := Entry_For (Name);
                     P : constant Road_Network.Node := Road_Network.Point (W, Road_Network.Ways (W).Count / 2);
                  begin
                     if not Streets (C).Has_Point then
                        Streets (C).X := P.X;
                        Streets (C).Z := P.Z;
                        Streets (C).Has_Point := True;
                     end if;
                  end;
               end if;
            end;
         end loop;
      end if;
      --  the house numbers
      if Exists (Dir) then
         Start_Search (Search_It, Dir, "addresses_*.txt", (Ordinary_File => True, others => False));
         while More_Entries (Search_It) loop
            Get_Next_Entry (Search_It, Item);
            Read_File (Full_Name (Item));
         end loop;
         End_Search (Search_It);
      end if;
   end Load;

   function Sqrt_Dist (DX, DZ : Float) return Float is
      D2 : constant Float := DX * DX + DZ * DZ;
      R  : Float := Float'Max (1.0, D2 / 2.0);
   begin
      for I in 1 .. 12 loop   --  Newton, enough for ordering
         R := 0.5 * (R + D2 / R);
      end loop;
      return R;
   end Sqrt_Dist;

   procedure Search (Query : String; Near_X, Near_Z : Float;
                     Found : out Result_Array; Count : out Natural) is
      Q : constant String := Fold (Query);
      Words : array (1 .. 8) of Unbounded_String;
      N_Words : Natural := 0;
      Number : Unbounded_String;
      Scores : array (1 .. Max_Results) of Float := (others => Float'Last);

      procedure Offer (Label : String; X, Z, Score : Float) is
         Slot : Natural := 0;
      begin
         for I in 1 .. Max_Results loop
            if Score < Scores (I) and then (Slot = 0 or else Scores (I) > Scores (Slot)) then
               Slot := I;
            end if;
         end loop;
         if Slot = 0 then
            return;
         end if;
         --  the worst of those better ones goes
         declare
            Worst : Natural := 1;
         begin
            for I in 1 .. Max_Results loop
               if Scores (I) > Scores (Worst) then
                  Worst := I;
               end if;
            end loop;
            if Score >= Scores (Worst) then
               return;
            end if;
            Scores (Worst) := Score;
            Found (Worst).Last := Natural'Min (120, Label'Length);
            Found (Worst).Label (1 .. Found (Worst).Last) := Label (Label'First .. Label'First + Found (Worst).Last - 1);
            Found (Worst).X := X;
            Found (Worst).Z := Z;
         end;
      end Offer;
   begin
      Count := 0;
      Found := (others => <>);
      --  the words, and the number among them
      declare
         S : constant String := Q & " ";
         Start : Positive := S'First;
      begin
         for I in S'Range loop
            if S (I) = ' ' then
               if I > Start then
                  declare
                     W : constant String := S (Start .. I - 1);
                  begin
                     if W (W'First) in '0' .. '9' then
                        Number := To_Unbounded_String (W);
                     elsif N_Words < Words'Last then
                        N_Words := N_Words + 1;
                        Words (N_Words) := To_Unbounded_String (W);
                     end if;
                  end;
               end if;
               Start := I + 1;
            end if;
         end loop;
      end;
      if N_Words = 0 then
         return;
      end if;
      for C in Streets.Iterate loop
         declare
            St : Street renames Streets (C);
            F  : constant String := " " & To_String (St.Folded) & " ";
            Ok : Boolean := True;
         begin
            for I in 1 .. N_Words loop
               --  each word typed starts a word of the name
               if Ada.Strings.Fixed.Index (F, " " & To_String (Words (I))) = 0 then
                  Ok := False;
               end if;
            end loop;
            if Ok and then St.Has_Point then
               declare
                  D : constant Float := Sqrt_Dist (St.X - Near_X, St.Z - Near_Z);
                  --  shorter names first (a closer match), then nearer
                  Base : constant Float := Float (Length (St.Folded)) * 100.0 + D / 100.0;
               begin
                  if Length (Number) > 0 then
                     declare
                        Want : constant String := To_String (Number);
                        Best : Natural := 0;
                     begin
                        for H in St.Houses.First_Index .. St.Houses.Last_Index loop
                           declare
                              Num : constant String := Fold (To_String (St.Houses (H).Number));
                           begin
                              if Num = Want then
                                 Best := H;
                                 exit;
                              elsif Best = 0 and then Num'Length >= Want'Length
                                and then Num (Num'First .. Num'First + Want'Length - 1) = Want
                              then
                                 Best := H;   --  "76" for "76 bis"
                              end if;
                           end;
                        end loop;
                        if Best > 0 then
                           Offer (To_String (St.Houses (Best).Number) & " " & To_String (St.Name),
                                  St.Houses (Best).X, St.Houses (Best).Z, Base);
                        end if;
                     end;
                  else
                     Offer (To_String (St.Name), St.X, St.Z, Base);
                  end if;
               end;
            end if;
         end;
      end loop;
      --  in order, best first
      for I in 1 .. Max_Results loop
         for J in I + 1 .. Max_Results loop
            if Scores (J) < Scores (I) then
               declare
                  T : constant Result := Found (I);
                  S : constant Float := Scores (I);
               begin
                  Found (I) := Found (J);
                  Scores (I) := Scores (J);
                  Found (J) := T;
                  Scores (J) := S;
               end;
            end if;
         end loop;
      end loop;
      for I in 1 .. Max_Results loop
         if Scores (I) < Float'Last then
            Count := I;
         end if;
      end loop;
   end Search;

end Addresses;
