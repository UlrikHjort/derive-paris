--  osm2tiles: convert OpenStreetMap extracts into game tiles.
--
--  osm2tiles <input.osm> <out_dir> <south> <west> <north> <east>
--     convert one extract covering the given box
--
--  osm2tiles plan <south> <west> <north> <east> [chunk_tiles]
--     split the box into chunks of chunk_tiles x chunk_tiles tiles (default
--     8, i.e. 2 km) and print one line per chunk:
--        tx0 tx1 tz0 tz1 south west north east
--     the lat/lon box includes a margin around the chunk, for downloading
--
--  osm2tiles chunk <input.osm> <out_dir> <tx0> <tx1> <tz0> <tz1>
--     convert exactly those tiles from an extract made with the plan box

with Ada.Command_Line;
with Ada.Directories;
with Ada.Text_IO;

with Geo;
with Osm_Model;
with World_Builder;

procedure Osm2tiles is
   use Ada.Command_Line;

   Download_Margin : constant := 300.0;   --  metres around a chunk

   procedure Usage is
   begin
      Ada.Text_IO.Put_Line
        ("usage: osm2tiles <input.osm> <out_dir> <south> <west> <north> <east>");
      Ada.Text_IO.Put_Line
        ("       osm2tiles plan <south> <west> <north> <east> [chunk_tiles]");
      Ada.Text_IO.Put_Line
        ("       osm2tiles chunk <input.osm> <out_dir> <tx0> <tx1> <tz0> <tz1>");
      Set_Exit_Status (Failure);
   end Usage;

   function F (V : Long_Float) return String is
      S : constant String := Integer'Image (Integer (V * 1.0E6));
      --  fixed 6 decimals, without exponent notation
      Neg  : constant Boolean := V < 0.0;
      Digs : constant String := S (S'First + 1 .. S'Last);
      Pad  : constant String := (1 .. Integer'Max (0, 7 - Digs'Length) => '0') & Digs;
   begin
      return (if Neg then "-" else "") & Pad (Pad'First .. Pad'Last - 6) & "."
        & Pad (Pad'Last - 5 .. Pad'Last);
   end F;

   function I (V : Integer) return String is
     (if V < 0 then Integer'Image (V) else Integer'Image (V) (2 .. Integer'Image (V)'Last));

   procedure Load (Name : String; M : in out Osm_Model.Model) is
   begin
      Ada.Text_IO.Put_Line ("Reading " & Name);
      Osm_Model.Load (Name, M);
      Ada.Text_IO.Put_Line
        ("Nodes:" & M.Nodes.Length'Image & "  ways:" & M.Ways.Length'Image
         & "  relations:" & M.Rels.Length'Image);
   end Load;

   procedure Ensure_Dir (Dir : String) is
   begin
      if not Ada.Directories.Exists (Dir) then
         Ada.Directories.Create_Path (Dir);
      end if;
   end Ensure_Dir;
begin
   if Argument_Count >= 5 and then Argument (1) = "plan" then
      declare
         South : constant Long_Float := Long_Float'Value (Argument (2));
         West  : constant Long_Float := Long_Float'Value (Argument (3));
         North : constant Long_Float := Long_Float'Value (Argument (4));
         East  : constant Long_Float := Long_Float'Value (Argument (5));
         Size  : constant Positive :=
           (if Argument_Count >= 6 then Positive'Value (Argument (6)) else 8);
         X0, X1, Z0, Z1 : Long_Float;
      begin
         Geo.To_Local (North, West, X0, Z0);
         Geo.To_Local (South, East, X1, Z1);
         declare
            TX0 : constant Integer := Geo.Tile_Of (X0);
            TX1 : constant Integer := Geo.Tile_Of (X1);
            TZ0 : constant Integer := Geo.Tile_Of (Z0);
            TZ1 : constant Integer := Geo.Tile_Of (Z1);
            CX  : Integer := TX0;
            CZ  : Integer;
         begin
            while CX <= TX1 loop
               CZ := TZ0;
               while CZ <= TZ1 loop
                  declare
                     EX : constant Integer := Integer'Min (TX1, CX + Size - 1);
                     EZ : constant Integer := Integer'Min (TZ1, CZ + Size - 1);
                     S, W, N, E : Long_Float;
                  begin
                     Geo.To_Lat_Lon (Long_Float (CX) * Geo.Tile_Size - Download_Margin,
                                     Long_Float (CZ) * Geo.Tile_Size - Download_Margin, N, W);
                     Geo.To_Lat_Lon (Long_Float (EX + 1) * Geo.Tile_Size + Download_Margin,
                                     Long_Float (EZ + 1) * Geo.Tile_Size + Download_Margin, S, E);
                     Ada.Text_IO.Put_Line
                       (I (CX) & " " & I (EX) & " " & I (CZ) & " " & I (EZ) & " "
                        & F (S) & " " & F (W) & " " & F (N) & " " & F (E));
                  end;
                  CZ := CZ + Size;
               end loop;
               CX := CX + Size;
            end loop;
         end;
      end;

   elsif Argument_Count = 7 and then Argument (1) = "chunk" then
      declare
         M : Osm_Model.Model;
      begin
         Load (Argument (2), M);
         Ensure_Dir (Argument (3));
         World_Builder.Build_Tiles
           (M,
            TX0     => Integer'Value (Argument (4)),
            TX1     => Integer'Value (Argument (5)),
            TZ0     => Integer'Value (Argument (6)),
            TZ1     => Integer'Value (Argument (7)),
            Out_Dir => Argument (3));
      end;

   elsif Argument_Count = 6 then
      declare
         M : Osm_Model.Model;
      begin
         Load (Argument (1), M);
         Ensure_Dir (Argument (2));
         World_Builder.Build
           (M,
            South   => Long_Float'Value (Argument (3)),
            West    => Long_Float'Value (Argument (4)),
            North   => Long_Float'Value (Argument (5)),
            East    => Long_Float'Value (Argument (6)),
            Out_Dir => Argument (2));
      end;

   else
      Usage;
   end if;
end Osm2tiles;
