with Ada.Strings.Fixed;
with Ada.Text_IO;

package body Osm_Model is

   function Tag
     (Tags : Tag_Maps.Map; Key : String; Default : String := "") return String
   is
      C : constant Tag_Maps.Cursor := Tags.Find (Key);
   begin
      if Tag_Maps.Has_Element (C) then
         return Tag_Maps.Element (C);
      else
         return Default;
      end if;
   end Tag;

   --  OSM XML as written by the API and Overpass has one element per line,
   --  so a small line-based reader is enough (and much faster than a
   --  general SAX parser on large extracts).

   --  Replace the predefined entities and numeric character references
   function Unescape (S : String) return String is
      Result : String (1 .. S'Length * 4);
      Last   : Natural := 0;
      I      : Positive := S'First;

      procedure Add (B : Natural) is
      begin
         Last := Last + 1;
         Result (Last) := Character'Val (B);
      end Add;

      procedure Put_Code (Code : Natural) is   --  UTF-8 encode
      begin
         if Code < 16#80# then
            Add (Code);
         elsif Code < 16#800# then
            Add (16#C0# + Code / 64);
            Add (16#80# + Code mod 64);
         elsif Code < 16#10000# then
            Add (16#E0# + Code / 4096);
            Add (16#80# + (Code / 64) mod 64);
            Add (16#80# + Code mod 64);
         else
            Add (16#F0# + Code / 262144);
            Add (16#80# + (Code / 4096) mod 64);
            Add (16#80# + (Code / 64) mod 64);
            Add (16#80# + Code mod 64);
         end if;
      end Put_Code;
   begin
      if Ada.Strings.Fixed.Index (S, "&") = 0 then
         return S;
      end if;
      while I <= S'Last loop
         if S (I) = '&' then
            declare
               Semi : constant Natural := Ada.Strings.Fixed.Index (S (I .. S'Last), ";");
               Name : constant String := (if Semi = 0 then "" else S (I + 1 .. Semi - 1));
               Known : Boolean := True;
            begin
               if Name = "amp" then
                  Add (Character'Pos ('&'));
               elsif Name = "lt" then
                  Add (Character'Pos ('<'));
               elsif Name = "gt" then
                  Add (Character'Pos ('>'));
               elsif Name = "quot" then
                  Add (Character'Pos ('"'));
               elsif Name = "apos" then
                  Add (Character'Pos ('''));
               elsif Name'Length > 1 and then Name (Name'First) = '#' then
                  begin
                     if Name (Name'First + 1) = 'x' then
                        Put_Code (Natural'Value
                                    ("16#" & Name (Name'First + 2 .. Name'Last) & "#"));
                     else
                        Put_Code (Natural'Value (Name (Name'First + 1 .. Name'Last)));
                     end if;
                  exception
                     when Constraint_Error => null;
                  end;
               else
                  Known := False;
               end if;
               if Known then
                  I := Semi + 1;
               else
                  Add (Character'Pos ('&'));
                  I := I + 1;
               end if;
            end;
         else
            Add (Character'Pos (S (I)));
            I := I + 1;
         end if;
      end loop;
      return Result (1 .. Last);
   end Unescape;

   --  Value of attribute Name in an element line, "" when absent
   function Attr (Line, Name : String) return String is
      Key   : constant String := " " & Name & "=""";
      Start : constant Natural := Ada.Strings.Fixed.Index (Line, Key);
   begin
      if Start = 0 then
         return "";
      end if;
      declare
         First : constant Positive := Start + Key'Length;
         Stop  : constant Natural := Ada.Strings.Fixed.Index (Line (First .. Line'Last), """");
      begin
         if Stop = 0 then
            return "";
         end if;
         return Unescape (Line (First .. Stop - 1));
      end;
   end Attr;

   function Starts (Line, Prefix : String) return Boolean is
     (Line'Length >= Prefix'Length
      and then Line (Line'First .. Line'First + Prefix'Length - 1) = Prefix);

   function Self_Closing (Line : String) return Boolean is
     (Line'Length >= 2 and then Line (Line'Last - 1 .. Line'Last) = "/>");

   procedure Load (File_Name : String; M : in out Model) is
      type State_Kind is (None, In_Node, In_Way, In_Rel);
      F       : Ada.Text_IO.File_Type;
      State   : State_Kind := None;
      Id      : Osm_Id := 0;
      Pos     : Node_Pos;
      Tags    : Tag_Maps.Map;
      Refs    : Id_Vectors.Vector;
      Members : Member_Vectors.Vector;

      procedure Finish_Node is
      begin
         M.Nodes.Include (Id, Pos);
         if not Tags.Is_Empty then
            M.Points.Append ((Id, Pos, Tags));
         end if;
         State := None;
      end Finish_Node;
   begin
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, File_Name);
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            Line : constant String :=
              Ada.Strings.Fixed.Trim (Ada.Text_IO.Get_Line (F), Ada.Strings.Both);
         begin
            if Starts (Line, "<node ") then
               Id := Osm_Id'Value (Attr (Line, "id"));
               Pos := (Lat => Long_Float'Value (Attr (Line, "lat")),
                       Lon => Long_Float'Value (Attr (Line, "lon")));
               Tags.Clear;
               State := In_Node;
               if Self_Closing (Line) then
                  Finish_Node;
               end if;
            elsif Starts (Line, "</node>") then
               Finish_Node;
            elsif Starts (Line, "<way ") then
               Id := Osm_Id'Value (Attr (Line, "id"));
               Tags.Clear;
               Refs.Clear;
               State := In_Way;
            elsif Starts (Line, "</way>") then
               M.Ways.Append ((Id, Refs, Tags));
               M.Way_Index.Include (Id, M.Ways.Last_Index);
               State := None;
            elsif Starts (Line, "<relation ") then
               Id := Osm_Id'Value (Attr (Line, "id"));
               Tags.Clear;
               Members.Clear;
               State := In_Rel;
            elsif Starts (Line, "</relation>") then
               M.Rels.Append ((Id, Members, Tags));
               State := None;
            elsif Starts (Line, "<tag ") and then State /= None then
               Tags.Include (Attr (Line, "k"), Attr (Line, "v"));
            elsif Starts (Line, "<nd ") and then State = In_Way then
               Refs.Append (Osm_Id'Value (Attr (Line, "ref")));
            elsif Starts (Line, "<member ") and then State = In_Rel then
               declare
                  Role : constant String := Attr (Line, "role");
               begin
                  Members.Append
                    ((Is_Way => Attr (Line, "type") = "way",
                      Ref    => Osm_Id'Value (Attr (Line, "ref")),
                      Role   => (if Role = "outer" or else Role = "" then Outer
                                 elsif Role = "inner" then Inner
                                 else Other)));
               end;
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (F);
   end Load;

end Osm_Model;
