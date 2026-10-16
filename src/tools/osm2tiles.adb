--  osm2tiles: convert an OSM XML extract into game tiles.
--
--  usage: osm2tiles <input.osm> <out_dir> <south> <west> <north> <east>

with Ada.Command_Line;
with Ada.Directories;
with Ada.Text_IO;

with Osm_Model;
with World_Builder;

procedure Osm2tiles is
   use Ada.Command_Line;
   M : Osm_Model.Model;
begin
   if Argument_Count /= 6 then
      Ada.Text_IO.Put_Line
        ("usage: osm2tiles <input.osm> <out_dir> <south> <west> <north> <east>");
      Set_Exit_Status (Failure);
      return;
   end if;

   Ada.Text_IO.Put_Line ("Reading " & Argument (1));
   Osm_Model.Load (Argument (1), M);
   Ada.Text_IO.Put_Line
     ("Nodes:" & M.Nodes.Length'Image & "  ways:" & M.Ways.Length'Image
      & "  relations:" & M.Rels.Length'Image);

   if not Ada.Directories.Exists (Argument (2)) then
      Ada.Directories.Create_Path (Argument (2));
   end if;

   World_Builder.Build
     (M,
      South   => Long_Float'Value (Argument (3)),
      West    => Long_Float'Value (Argument (4)),
      North   => Long_Float'Value (Argument (5)),
      East    => Long_Float'Value (Argument (6)),
      Out_Dir => Argument (2));
end Osm2tiles;
