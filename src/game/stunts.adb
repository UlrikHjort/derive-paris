--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Containers.Indefinite_Ordered_Sets;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Arc_Top;
with River;
with Road_Network;
with Sound;
with Terrain;
with Notes;

package body Stunts is

   use Math3D;
   use Ada.Strings.Unbounded;

   package Name_Sets is new Ada.Containers.Indefinite_Ordered_Sets (String);

   Ever      : Name_Sets.Set;     --  the bridges flown under, ever
   This_Run  : Name_Sets.Set;     --  ... in this flight
   Best_Run  : Natural := 0;
   Godefroy  : Boolean := False;  --  through the great vault, ever
   Loaded    : Boolean := False;
   Fresh     : Unbounded_String;
   Last_Bridge : Unbounded_String;   --  (one bridge is often two roads)
   Arc_Wait  : Float := 0.0;

   function File return String is
     (Ada.Environment_Variables.Value ("HOME", ".") & "/.derive_stunts");

   function Img (N : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Left));

   procedure Load is
      F : Ada.Text_IO.File_Type;
   begin
      Loaded := True;
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, File);
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            L : constant String := Ada.Text_IO.Get_Line (F);
         begin
            if L'Length > 7 and then L (L'First .. L'First + 6) = "bridge " then
               Ever.Include (L (L'First + 7 .. L'Last));
            elsif L'Length > 9 and then L (L'First .. L'First + 8) = "best_run " then
               Best_Run := Natural'Value (L (L'First + 9 .. L'Last));
            elsif L = "godefroy" then
               Godefroy := True;
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

   procedure Save is
      F : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, File);
      Ada.Text_IO.Put_Line (F, "# Dérive: your stunts in the plane");
      if Godefroy then
         Ada.Text_IO.Put_Line (F, "godefroy");
      end if;
      Ada.Text_IO.Put_Line (F, "best_run " & Img (Best_Run));
      for B of Ever loop
         Ada.Text_IO.Put_Line (F, "bridge " & B);
      end loop;
      Ada.Text_IO.Close (F);
   exception
      when others => null;
   end Save;

   procedure Tell (S : String) is
   begin
      Fresh := To_Unbounded_String (S);
      Notes.Say ("Stunt: " & S);
      Sound.Effect (Sound.Go_Beep, 0.7, 0.0);
   end Tell;

   --  The bridge over the line From -> To, if the plane went under one:
   --  a road segment crossing it above the plane, over the river
   function Bridge_Under (From, To : Vec3) return String is
      Found : Unbounded_String;
      procedure Visit (W, Seg : Natural; AX, AZ, BX, BZ : Float) is
         pragma Unreferenced (Seg);
         --  do the two segments cross?
         DX  : constant Float := To.X - From.X;
         DZ  : constant Float := To.Z - From.Z;
         EX  : constant Float := BX - AX;
         EZ  : constant Float := BZ - AZ;
         Den : constant Float := DX * EZ - DZ * EX;
      begin
         if Length (Found) = 0 and then abs Den > 1.0E-6 then
            declare
               T : constant Float := ((AX - From.X) * EZ - (AZ - From.Z) * EX) / Den;
               S : constant Float := ((AX - From.X) * DZ - (AZ - From.Z) * DX) / Den;
            begin
               if T >= 0.0 and then T <= 1.0 and then S >= 0.0 and then S <= 1.0 then
                  declare
                     Name : constant String := To_String (Road_Network.Ways (W).Name);
                  begin
                     Found := To_Unbounded_String (if Name = "" then "a footbridge" else Name);
                  end;
               end if;
            end;
         end if;
      end Visit;
      procedure Each is new Road_Network.For_Segment_Ids_Near (Visit);
   begin
      Each (To.X, To.Z, 160.0);   --  (a bridge is often one long segment)
      return To_String (Found);
   end Bridge_Under;

   procedure Update (From, To : Vec3; Flying : Boolean) is
   begin
      if not Loaded then
         Load;
      end if;
      if not Flying then
         This_Run.Clear;
         Last_Bridge := Null_Unbounded_String;
         return;
      end if;
      Arc_Wait := Float'Max (0.0, Arc_Wait - 1.0 / 60.0);

      --  the Arc de Triomphe
      if Arc_Wait = 0.0 then
         case Arc_Top.Through (From, To) is
            when Arc_Top.Great_Vault =>
               Arc_Wait := 3.0;
               if not Godefroy then
                  Godefroy := True;
                  Save;
               end if;
               Tell ("Through the Arc de Triomphe!  Like Charles Godefroy, 7 August 1919");
            when Arc_Top.Side_Arches =>
               Arc_Wait := 3.0;
               Tell ("Through the narrow arches of the Arc de Triomphe!");
            when Arc_Top.None =>
               null;
         end case;
      end if;

      --  under a bridge: low over the water, below the street
      if River.In_Channel (To.X, To.Z)
        and then To.Y < Terrain.Height (To.X, To.Z) - 0.5
      then
         declare
            B : constant String := Bridge_Under (From, To);
         begin
            if B /= "" and then B /= To_String (Last_Bridge) then
               Last_Bridge := To_Unbounded_String (B);
               declare
                  New_Ever : constant Boolean := not Ever.Contains (B);
               begin
                  This_Run.Include (B);
                  Ever.Include (B);
                  if Natural (This_Run.Length) > Best_Run then
                     Best_Run := Natural (This_Run.Length);
                  end if;
                  if New_Ever or else Natural (This_Run.Length) = Best_Run then
                     Save;
                  end if;
                  Tell ("Under the " & B & "   (" & Img (Natural (This_Run.Length)) & " this flight, "
                        & Img (Natural (Ever.Length)) & " bridges ever"
                        & (if New_Ever then ", a new one" else "") & ")");
               end;
            end if;
         end;
      elsif To.Y > Terrain.Height (To.X, To.Z) + 15.0 then
         Last_Bridge := Null_Unbounded_String;   --  up again: the same bridge counts once more
      end if;
   end Update;

   function News return String is
      S : constant String := To_String (Fresh);
   begin
      Fresh := Null_Unbounded_String;
      return S;
   end News;

end Stunts;
