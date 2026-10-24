--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Containers.Vectors;
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces;

with Figures;
with Geo;
with Math3D;
with Meshes;
with Shaders;
with Terrain;

package body Hall_B is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;
   use Ada.Strings.Unbounded;

   Pi : constant := Ada.Numerics.Pi;

   Gen    : Ada.Numerics.Float_Random.Generator;
   Seeded : Boolean := False;
   function Rnd return Float is (Ada.Numerics.Float_Random.Random (Gen));
   function Pick (N : Positive) return Positive is
     (1 + Natural'Min (N - 1, Natural (Float'Floor (Rnd * Float (N)))));

   function "+" (S : String) return Unbounded_String renames To_Unbounded_String;

   type Float_List is array (Positive range <>) of Float;

   --  Materials (world.frag)
   Mat_Canvas : constant := 51.0;  --  seed: pattern, colours, variant
   Mat_Drawing : constant := 92.0; --  ink on paper, under a mount
   Mat_Video  : constant := 93.0;  --  a screen, moving
   Mat_Floor : constant := 52.0;   --  polished concrete
   Mat_White : constant := 53.0;
   Mat_Steel : constant := 54.0;   --  painted, in the paint colour
   Mat_Door  : constant := 17.0;
   Mat_Exit  : constant := 49.0;   --  the green SORTIE sign

   --  The hall: along +X from the door (X 0), Z from -10 to 10, well
   --  under the ground, so nothing of the city reaches in
   Length : constant := 56.0;
   Half_W : constant := 10.0;
   Height : constant := 7.5;
   Depth  : constant := 40.0;

   Origin     : Vec3 := (0.0, 0.0, 0.0);
   Origin_Set : Boolean := False;
   Out_N      : Vec3 := (-1.0, 0.0, 0.0);   --  from the facade out onto the piazza
   Door_Mid   : Vec3 := (0.0, 0.0, 0.0);
   Clock      : Float := 0.0;

   function G (X, Y, Z : Float) return Vec3 is (Origin + Vec3'(X, Y, Z));

   --  Where the way in is (from OpenStreetMap)
   procedure Facade (AX, AZ, BX, BZ : out Float) is
      X, Z : Long_Float;
   begin
      Geo.To_Local (48.859915, 2.351657, X, Z);
      AX := Float (X);
      AZ := Float (Z);
      Geo.To_Local (48.861102, 2.352304, X, Z);
      BX := Float (X);
      BZ := Float (Z);
   end Facade;

   procedure Place is
      AX, AZ, BX, BZ : Float;
   begin
      if Origin_Set then
         return;
      end if;
      Facade (AX, AZ, BX, BZ);
      declare
         D : constant Vec3 := Normalize (Vec3'(BX - AX, 0.0, BZ - AZ));
         N : Vec3 := (D.Z, 0.0, -D.X);
      begin
         if N.X > 0.0 then   --  out is to the west
            N := (-1.0) * N;
         end if;
         Out_N := N;
         Door_Mid := ((AX + BX) / 2.0, 0.0, (AZ + BZ) / 2.0);
         Door_Mid.Y := Terrain.Height (Door_Mid.X, Door_Mid.Z);
         Origin := Door_Mid + 30.0 * Out_N;
         Origin.Y := Door_Mid.Y - Depth;
      end;
      Origin_Set := True;
   end Place;

   procedure Mark_Point (X, Z : out Float) is
   begin
      Place;
      X := Door_Mid.X + 2.6 * Out_N.X;
      Z := Door_Mid.Z + 2.6 * Out_N.Z;
   end Mark_Point;

   function Touching_Entrance (X, Z : Float) return Boolean is
      AX, AZ, BX, BZ : Float;
   begin
      Facade (AX, AZ, BX, BZ);
      declare
         EX : constant Float := BX - AX;
         EZ : constant Float := BZ - AZ;
         T  : constant Float := ((X - AX) * EX + (Z - AZ) * EZ) / (EX * EX + EZ * EZ);
         D  : constant Float := Sqrt ((AX + T * EX - X) ** 2 + (AZ + T * EZ - Z) ** 2);
      begin
         --  the middle of the facade
         return T > 0.3 and then T < 0.7 and then D < 2.2;
      end;
   end Touching_Entrance;

   function Floor_Y return Float is (Origin.Y);

   procedure Entrance (X, Z, Yaw : out Float) is
   begin
      Place;
      X := Origin.X + 3.0;
      Z := Origin.Z;
      Yaw := Pi / 2.0;   --  east, into the hall
   end Entrance;

   procedure Way_Out (X, Z, Yaw : out Float) is
   begin
      Place;
      X := Door_Mid.X + 12.0 * Out_N.X;
      Z := Door_Mid.Z + 12.0 * Out_N.Z;
      Yaw := Arctan (-Out_N.X, Out_N.Z);   --  looking back at the building
   end Way_Out;

   function At_Exit (X, Z : Float) return Boolean is
     (X - Origin.X < 1.2 and then abs (Z - Origin.Z) < 1.6);

   ---------------------------------------------------------------------------
   --  The works
   ---------------------------------------------------------------------------

   --  Places for paintings: centre (hall coordinates, at the wall), the
   --  way the wall faces, the most room there is
   type Slot is record
      C          : Vec3;
      N          : Vec3;
      Max_W, Max_H : Float;
   end record;
   Slots : constant array (Positive range <>) of Slot :=
     (((6.0, 0.0, -Half_W + 0.02), (0.0, 0.0, 1.0), 5.0, 3.6),
      ((14.0, 0.0, -Half_W + 0.02), (0.0, 0.0, 1.0), 5.0, 3.6),
      ((23.0, 0.0, -Half_W + 0.02), (0.0, 0.0, 1.0), 5.5, 3.8),
      ((32.0, 0.0, -Half_W + 0.02), (0.0, 0.0, 1.0), 5.5, 3.8),
      ((43.0, 0.0, -Half_W + 0.02), (0.0, 0.0, 1.0), 5.0, 3.6),
      ((51.0, 0.0, -Half_W + 0.02), (0.0, 0.0, 1.0), 4.5, 3.6),
      ((6.0, 0.0, Half_W - 0.02), (0.0, 0.0, -1.0), 5.0, 3.6),
      ((14.0, 0.0, Half_W - 0.02), (0.0, 0.0, -1.0), 5.0, 3.6),
      ((23.0, 0.0, Half_W - 0.02), (0.0, 0.0, -1.0), 5.5, 3.8),
      ((32.0, 0.0, Half_W - 0.02), (0.0, 0.0, -1.0), 5.5, 3.8),
      ((43.0, 0.0, Half_W - 0.02), (0.0, 0.0, -1.0), 5.0, 3.6),
      ((51.0, 0.0, Half_W - 0.02), (0.0, 0.0, -1.0), 4.5, 3.6),
      ((17.83, 0.0, 0.0), (-1.0, 0.0, 0.0), 3.4, 3.0),       --  the partitions
      ((18.17, 0.0, 0.0), (1.0, 0.0, 0.0), 3.4, 3.0),
      ((37.83, 0.0, 0.0), (-1.0, 0.0, 0.0), 3.4, 3.0),
      ((38.17, 0.0, 0.0), (1.0, 0.0, 0.0), 3.4, 3.0),
      ((Length - 0.02, 0.0, 0.0), (-1.0, 0.0, 0.0), 9.0, 5.2),  --  the far wall
      ((0.02, 0.0, -6.0), (1.0, 0.0, 0.0), 4.0, 3.0),          --  either side of the door
      ((0.02, 0.0, 6.0), (1.0, 0.0, 0.0), 4.0, 3.0));

   --  What hangs where: paintings mostly; drawings on the first partition
   --  and by the door, a video on the second partition, and the shop on
   --  the first stretch of wall, where you come in
   type Slot_Kind is (Painting, Drawing, Video, Shop);
   function Kind_Of (I : Positive) return Slot_Kind is
     (case I is
         when 1 => Shop,
         when 13 | 14 | 18 | 19 => Drawing,
         when 15 | 16 => Video,
         when others => Painting);

   --  The shop's counter (hall coordinates)
   Shop_X0 : constant := 3.6;
   Shop_X1 : constant := 8.4;
   Shop_Z1 : constant := -8.4;

   --  Plinths for the sculptures (hall coordinates)
   Plinths : constant array (1 .. 3) of Vec3 := ((9.0, 0.0, 0.0), (28.0, 0.0, 0.0), (47.0, 0.0, 0.0));

   type Sculpture_Kind is (Network, Twist, Ring, Cloud, Mobile, Endless, Stack, Arch);

   type Work is record
      C      : Vec3;               --  world: the middle of a canvas, or the foot of a sculpture
      N      : Vec3;               --  the way a canvas faces (zero for a sculpture)
      Kind   : Slot_Kind := Painting;
      Name   : Unbounded_String;
      Medium : Unbounded_String;
   end record;
   Works      : array (1 .. Slots'Length + Plinths'Length) of Work;
   Work_Count : Natural := 0;

   Show_Title : Unbounded_String;
   Seeds      : array (Slots'Range) of Float := (others => 0.0);
   Sizes_W, Sizes_H : array (Slots'Range) of Float := (others => 2.0);
   Kinds      : array (Plinths'Range) of Sculpture_Kind := (Network, Twist, Ring);
   Colours    : array (Plinths'Range) of Vec3 := (others => (0.8, 0.1, 0.1));

   type Visitor is record
      P     : Vec3;
      Face  : Float;
      Coat, Skin : Vec3;
   end record;
   Visitors : array (1 .. 9) of Visitor;

   function Title return String is (To_String (Show_Title));

   --  The words (titles, labels) come from data/gallery.dat, scrambled
   package Text_Vectors is new Ada.Containers.Vectors (Positive, Unbounded_String);
   Artist_Name, Heading_Text, Exit_Text, Sculpture_Medium, Shop_Text : Unbounded_String;
   Exhibitions, Firsts, Seconds, Wholes, Media, Sculptures, Drawing_Media, Video_Media : Text_Vectors.Vector;
   Loaded : Boolean := False;

   procedure Load_Texts is
      use type Interfaces.Unsigned_8;
      Key  : constant String := "derive-paris";
      F    : Ada.Text_IO.File_Type;
      Part : Unbounded_String;
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
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, "data/gallery.dat");
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            L : constant String := Ada.Text_IO.Get_Line (F);
         begin
            if L'Length > 0 and then L (L'First) = '[' then
               Part := +L;
            elsif L'Length > 1 then
               declare
                  T : constant Unbounded_String := +Plain (L);
                  P : constant String := To_String (Part);
               begin
                  if P = "[artist]" then Artist_Name := T;
                  elsif P = "[heading]" then Heading_Text := T;
                  elsif P = "[exit]" then Exit_Text := T;
                  elsif P = "[sculpture_medium]" then Sculpture_Medium := T;
                  elsif P = "[exhibitions]" then Exhibitions.Append (T);
                  elsif P = "[first]" then Firsts.Append (T);
                  elsif P = "[second]" then Seconds.Append (T);
                  elsif P = "[whole]" then Wholes.Append (T);
                  elsif P = "[media]" then Media.Append (T);
                  elsif P = "[sculptures]" then Sculptures.Append (T);
                  elsif P = "[drawing_media]" then Drawing_Media.Append (T);
                  elsif P = "[video_media]" then Video_Media.Append (T);
                  elsif P = "[shop]" then Shop_Text := T;
                  end if;
               end;
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (F);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
   end Load_Texts;

   function Any (V : Text_Vectors.Vector; Default : String) return String is
     (if V.Is_Empty then Default else To_String (V.Element (Pick (Natural (V.Length)))));

   function Nth (V : Text_Vectors.Vector; I : Positive; Default : String) return String is
     (if I <= Natural (V.Length) then To_String (V.Element (I)) else Default);

   function Artist return String is
     (if Ada.Strings.Unbounded.Length (Artist_Name) = 0 then "Anonymous" else To_String (Artist_Name));
   function Heading return String is (To_String (Heading_Text));
   function Exit_Name return String is (To_String (Exit_Text));

   function Painting_Title return String is
   begin
      if Rnd < 0.3 then
         return Any (Wholes, "Untitled");
      elsif Rnd < 0.25 then
         return Any (Firsts, "Study") & " No." & Natural'Image (2 + Natural (Rnd * 97.0));
      end if;
      return Any (Firsts, "Study") & " " & Any (Seconds, "No. 1");
   end Painting_Title;

   function Sculpture_Title (K : Sculpture_Kind) return String is
     (Nth (Sculptures, Sculpture_Kind'Pos (K) + 1, "Untitled"));

   Need_Build : Boolean := True;

   procedure New_Exhibition is
      Sculpture_Colours : constant array (1 .. 7) of Vec3 :=
        ((0.82, 0.1, 0.08), (0.0, 0.18, 0.65), (0.95, 0.75, 0.08), (0.06, 0.06, 0.07),
         (0.92, 0.92, 0.9), (0.85, 0.47, 0.34), (0.55, 0.58, 0.62));
      Skins : constant array (1 .. 4) of Vec3 :=
        ((0.86, 0.68, 0.56), (0.76, 0.57, 0.44), (0.58, 0.40, 0.29), (0.40, 0.27, 0.19));
      Coats : constant array (1 .. 7) of Vec3 :=
        ((0.1, 0.1, 0.12), (0.85, 0.85, 0.82), (0.2, 0.3, 0.55), (0.6, 0.15, 0.15),
         (0.75, 0.6, 0.35), (0.25, 0.45, 0.3), (0.5, 0.5, 0.52));
   begin
      if not Seeded then
         Ada.Numerics.Float_Random.Reset (Gen);
         Seeded := True;
      end if;
      Place;
      if not Loaded then
         Load_Texts;
      end if;
      Show_Title := +Any (Exhibitions, "New Work");
      Work_Count := 0;
      for I in Slots'Range loop
         declare
            S      : Slot renames Slots (I);
            K      : constant Slot_Kind := Kind_Of (I);
            Style  : constant Natural := Natural (Float'Floor (Rnd * 15.99));
            Pal    : constant Natural := Natural (Float'Floor (Rnd * 7.99));
            Aspect : constant Float :=
              (case Pick (5) is when 1 => 1.0, when 2 => 1.33, when 3 => 0.75,
                                when 4 => 1.5, when others => 0.66);
            W : Float := (case K is
                             when Drawing => 1.1 + 0.5 * Rnd,
                             when Video   => S.Max_W * 0.95,
                             when Shop    => 4.4,
                             when Painting => S.Max_W * (0.55 + 0.35 * Rnd));
            H : Float := (case K is
                             when Video => W * 0.5625,
                             when Shop  => 1.1,
                             when others => W / Aspect);
         begin
            if H > S.Max_H then
               W := W * S.Max_H / H;
               H := S.Max_H;
            end if;
            Sizes_W (I) := W;
            Sizes_H (I) := H;
            Seeds (I) := (case K is
                             when Drawing => Float (Natural (Float'Floor (Rnd * 999.0))),
                             when Video   => Float (Natural (Float'Floor (Rnd * 6.0))),
                             when others  => Float (Style + 16 * Pal + 128 * Natural (Float'Floor (Rnd * 999.0))));
            Work_Count := Work_Count + 1;
            Works (Work_Count) :=
              (C      => G (S.C.X, (if K = Shop then 1.75 elsif K = Drawing then 1.6
                                    else Float'Max (2.4, 1.0 + H / 2.0)), S.C.Z),
               N      => S.N,
               Kind   => K,
               Name   => +(if K = Shop then "" elsif K = Drawing and then Rnd < 0.5
                           then "Study for " & Painting_Title else Painting_Title),
               Medium => +(case K is
                              when Drawing => Any (Drawing_Media, "ink on paper"),
                              when Video   => Any (Video_Media, "video, colour, silent"),
                              when Shop    => "",
                              when Painting => Nth (Media, Style + 1, "mixed media")));
         end;
      end loop;
      for I in Plinths'Range loop
         Kinds (I) := Sculpture_Kind'Val (Pick (8) - 1);
         Colours (I) := Sculpture_Colours (Pick (Sculpture_Colours'Length));
         Work_Count := Work_Count + 1;
         Works (Work_Count) :=
           (C => G (Plinths (I).X, 0.0, Plinths (I).Z), N => (0.0, 0.0, 0.0), Kind => Painting,
            Name => +Sculpture_Title (Kinds (I)), Medium => Sculpture_Medium);
      end loop;
      --  people looking at the paintings
      for V of Visitors loop
         declare
            S : Slot renames Slots (1 + Pick (Slots'Length - 1));   --  (not at the shop)
            Along : constant Vec3 := Cross ((0.0, 1.0, 0.0), S.N);
            P : constant Vec3 := S.C + (1.8 + 1.2 * Rnd) * S.N + (1.6 * (Rnd - 0.5)) * Along;
         begin
            V := (P    => G (P.X, 0.0, P.Z),
                  Face => Arctan (-S.N.X, S.N.Z) + 0.3 * (Rnd - 0.5),
                  Coat => Coats (Pick (Coats'Length)),
                  Skin => Skins (Pick (Skins'Length)));
         end;
      end loop;
      Need_Build := True;
   end New_Exhibition;

   ---------------------------------------------------------------------------
   --  Building
   ---------------------------------------------------------------------------

   Hall, Ceiling : Meshes.Mesh;
   Pipes : array (1 .. 4) of Meshes.Mesh;
   Pipe_Colours : constant array (1 .. 4) of Vec3 :=
     ((0.1, 0.3, 0.85), (0.1, 0.6, 0.25), (0.85, 0.12, 0.1), (0.95, 0.78, 0.1));
   Statues : array (Plinths'Range) of Meshes.Mesh;
   Built : Boolean := False;

   --  A quad with the corners put in order for the normal it should have
   procedure Face (A, B, C, D, N : Vec3; Mat : Float) is
   begin
      if Dot (Cross (B - A, D - A), N) >= 0.0 then
         Meshes.Quad (A, B, C, D, Mat);
      else
         Meshes.Quad (D, C, B, A, Mat);
      end if;
   end Face;

   procedure Sphere (C : Vec3; R : Float; Mat : Float; Segs : Positive := 12) is
      Rings : constant Positive := Segs / 2;
      function P (I, J : Integer) return Vec3 is
         Phi   : constant Float := 2.0 * Pi * Float (I) / Float (Segs);
         Theta : constant Float := Pi * Float (J) / Float (Rings);
      begin
         return C + R * Vec3'(Sin (Theta) * Cos (Phi), -Cos (Theta), Sin (Theta) * Sin (Phi));
      end P;
   begin
      for J in 0 .. Rings - 1 loop
         for I in 0 .. Segs - 1 loop
            Face (P (I, J), P (I, J + 1), P (I + 1, J + 1), P (I + 1, J),
                  0.25 * (P (I, J) + P (I, J + 1) + P (I + 1, J + 1) + P (I + 1, J)) - C, Mat);
         end loop;
      end loop;
   end Sphere;

   --  A round bar from P0 to P1
   procedure Tube (P0, P1 : Vec3; R : Float; Mat : Float; Segs : Positive := 10) is
      D : constant Vec3 := Normalize (P1 - P0);
      U : constant Vec3 :=
        Normalize (Cross (D, (if abs D.Y < 0.9 then Vec3'(0.0, 1.0, 0.0) else Vec3'(1.0, 0.0, 0.0))));
      V : constant Vec3 := Cross (D, U);
      function Rim (I : Integer) return Vec3 is
         A : constant Float := 2.0 * Pi * Float (I) / Float (Segs);
      begin
         return R * (Cos (A) * U + Sin (A) * V);
      end Rim;
   begin
      for I in 0 .. Segs - 1 loop
         Face (P0 + Rim (I), P1 + Rim (I), P1 + Rim (I + 1), P0 + Rim (I + 1),
               Rim (I) + Rim (I + 1), Mat);
      end loop;
      for I in 1 .. Segs - 2 loop   --  the ends
         Face (P0 + Rim (0), P0 + Rim (I), P0 + Rim (I + 1), P0 + Rim (I + 1), (-1.0) * D, Mat);
         Face (P1 + Rim (0), P1 + Rim (I), P1 + Rim (I + 1), P1 + Rim (I + 1), D, Mat);
      end loop;
   end Tube;

   --  A box turned about the vertical
   procedure Turned_Box (C : Vec3; HX, HY, HZ, Yaw : Float; Mat : Float) is
      AX : constant Vec3 := (Cos (Yaw), 0.0, Sin (Yaw));
      AZ : constant Vec3 := (-Sin (Yaw), 0.0, Cos (Yaw));
      AY : constant Vec3 := (0.0, 1.0, 0.0);
      function K (SX, SY, SZ : Float) return Vec3 is (C + (SX * HX) * AX + (SY * HY) * AY + (SZ * HZ) * AZ);
   begin
      Face (K (-1.0, -1.0, 1.0), K (1.0, -1.0, 1.0), K (1.0, 1.0, 1.0), K (-1.0, 1.0, 1.0), AZ, Mat);
      Face (K (-1.0, -1.0, -1.0), K (1.0, -1.0, -1.0), K (1.0, 1.0, -1.0), K (-1.0, 1.0, -1.0), (-1.0) * AZ, Mat);
      Face (K (1.0, -1.0, -1.0), K (1.0, -1.0, 1.0), K (1.0, 1.0, 1.0), K (1.0, 1.0, -1.0), AX, Mat);
      Face (K (-1.0, -1.0, -1.0), K (-1.0, -1.0, 1.0), K (-1.0, 1.0, 1.0), K (-1.0, 1.0, -1.0), (-1.0) * AX, Mat);
      Face (K (-1.0, 1.0, -1.0), K (1.0, 1.0, -1.0), K (1.0, 1.0, 1.0), K (-1.0, 1.0, 1.0), AY, Mat);
      Face (K (-1.0, -1.0, -1.0), K (1.0, -1.0, -1.0), K (1.0, -1.0, 1.0), K (-1.0, -1.0, 1.0), (-1.0) * AY, Mat);
   end Turned_Box;

   --  A four-sided ring band between two heights, turned 45 degrees
   procedure Band (C : Vec3; Y0, Y1, R0, R1 : Float; Mat : Float) is
      function P (I : Integer; Top : Boolean) return Vec3 is
         A : constant Float := Pi / 4.0 + Pi / 2.0 * Float (I);
         R : constant Float := (if Top then R1 else R0);
      begin
         return C + Vec3'(R * Cos (A), (if Top then Y1 else Y0), R * Sin (A));
      end P;
   begin
      for I in 0 .. 3 loop
         declare
            A : constant Float := Pi / 2.0 * (Float (I) + 1.0);
         begin
            Face (P (I, False), P (I + 1, False), P (I + 1, True), P (I, True),
                  (Cos (A), 0.0, Sin (A)), Mat);
         end;
      end loop;
   end Band;

   procedure Build_Sculpture (K : Sculpture_Kind; Base : Vec3) is
      B : constant Vec3 := Base + Vec3'(0.0, 0.6, 0.0);   --  on the plinth
   begin
      case K is
         when Network =>
            declare
               type Layer is array (1 .. 5) of Vec3;
               Layers : array (1 .. 4) of Layer;
               Counts : array (1 .. 4) of Positive;
            begin
               for L in 1 .. 4 loop
                  Counts (L) := 2 + Pick (3);
                  for I in 1 .. Counts (L) loop
                     Layers (L) (I) := B + Vec3'(-0.9 + 0.6 * Float (L - 1),
                                                 0.6 + 1.6 * Float (I) / Float (Counts (L) + 1),
                                                 0.35 * Sin (Float (I * L)));
                     Sphere (Layers (L) (I), 0.09, Mat_Steel, 10);
                  end loop;
               end loop;
               for L in 1 .. 3 loop
                  for I in 1 .. Counts (L) loop
                     for J in 1 .. Counts (L + 1) loop
                        Tube (Layers (L) (I), Layers (L + 1) (J), 0.012, Mat_Steel, 5);
                     end loop;
                  end loop;
               end loop;
               Tube (B, B + Vec3'(0.0, 0.5, 0.0), 0.03, Mat_Steel, 6);   --  a stand
            end;
         when Twist =>
            for K2 in 0 .. 13 loop
               declare
                  S : constant Float := 0.36 - 0.015 * Float (K2);
               begin
                  Turned_Box (B + Vec3'(0.0, 0.2 + 0.36 * Float (K2), 0.0), S, 0.17, S,
                              0.22 * Float (K2), Mat_Steel);
               end;
            end loop;
         when Ring =>
            declare
               Ctr : constant Vec3 := B + Vec3'(0.0, 1.15, 0.0);
               R   : constant Float := 0.95;
               T   : constant Float := 0.16;
               function P (I, J : Integer) return Vec3 is
                  A : constant Float := 2.0 * Pi * Float (I) / 28.0;
                  Q : constant Float := 2.0 * Pi * Float (J) / 10.0;
               begin
                  return Ctr + Vec3'((R + T * Cos (Q)) * Cos (A), (R + T * Cos (Q)) * Sin (A), T * Sin (Q));
               end P;
            begin
               for I in 0 .. 27 loop
                  for J in 0 .. 9 loop
                     declare
                        A : constant Float := 2.0 * Pi * (Float (I) + 0.5) / 28.0;
                        Ring_C : constant Vec3 := Ctr + Vec3'(R * Cos (A), R * Sin (A), 0.0);
                     begin
                        Face (P (I, J), P (I + 1, J), P (I + 1, J + 1), P (I, J + 1),
                              0.25 * (P (I, J) + P (I + 1, J) + P (I + 1, J + 1) + P (I, J + 1)) - Ring_C,
                              Mat_Steel);
                     end;
                  end loop;
               end loop;
            end;
         when Cloud =>
            for I in 1 .. 26 loop
               declare
                  A : constant Float := 2.0 * Pi * Rnd;
                  E : constant Float := Pi * (Rnd - 0.5);
                  D : constant Float := 0.75 * Sqrt (Rnd);
               begin
                  Sphere (B + Vec3'(D * Cos (E) * Cos (A), 1.3 + D * Sin (E), D * Cos (E) * Sin (A)),
                          0.07 + 0.2 * Rnd, Mat_Steel, 12);
               end;
            end loop;
            Tube (B, B + Vec3'(0.0, 0.7, 0.0), 0.03, Mat_Steel, 6);
         when Mobile =>
            declare
               Top : constant Vec3 := (B.X, Origin.Y + Height, B.Z);
               Hang : Vec3 := (B.X, Origin.Y + 5.2, B.Z);
            begin
               Tube (Top, Hang, 0.008, Mat_Steel, 4);
               for Level in 1 .. 3 loop
                  declare
                     A   : constant Float := 2.0 * Pi * Rnd;
                     Arm : constant Float := 1.4 - 0.3 * Float (Level);
                     L   : constant Vec3 := Hang + Vec3'(-Arm * Cos (A) * 0.4, 0.0, -Arm * Sin (A) * 0.4);
                     Rt  : constant Vec3 := Hang + Vec3'(Arm * Cos (A), 0.0, Arm * Sin (A));
                     Disc : constant Vec3 := L + Vec3'(0.0, -0.45, 0.0);
                  begin
                     Tube (L, Rt, 0.012, Mat_Steel, 4);
                     Tube (L, Disc, 0.006, Mat_Steel, 4);
                     Tube (Disc, Disc + Vec3'(0.02 * Cos (A), 0.0, 0.02 * Sin (A)),
                           0.22 + 0.08 * Rnd, Mat_Steel, 16);   --  a flat disc
                     Hang := Rt + Vec3'(0.0, -0.6, 0.0);
                     Tube (Rt, Hang, 0.006, Mat_Steel, 4);
                  end;
               end loop;
               Tube (Hang, Hang + Vec3'(0.02, 0.0, 0.0), 0.3, Mat_Steel, 16);
            end;
         when Stack =>
            --  cubes piled up, each turned and a little off the one below
            declare
               Y : Float := 0.0;
               X, Z : Float := 0.0;
            begin
               for K2 in 0 .. 7 loop
                  declare
                     S : constant Float := 0.3 - 0.02 * Float (K2);
                  begin
                     Turned_Box (B + Vec3'(X, Y + S, Z), S, S, S, 0.5 * Rnd, Mat_Steel);
                     Y := Y + 2.0 * S;
                     X := X + 0.08 * (Rnd - 0.3);
                     Z := Z + 0.06 * (Rnd - 0.5);
                  end;
               end loop;
            end;
         when Arch =>
            --  an arch of blocks from one side of the plinth to the other
            for K2 in 0 .. 12 loop
               declare
                  A : constant Float := Pi * (Float (K2) + 0.5) / 13.0;
               begin
                  Turned_Box (B + Vec3'(0.65 * Cos (A), 1.5 * Sin (A) + 0.05, 0.0), 0.09, 0.14, 0.2,
                              0.0, Mat_Steel);
               end;
            end loop;
         when Endless =>
            for K2 in 0 .. 6 loop
               declare
                  Y : constant Float := 0.45 * Float (K2);
               begin
                  Band (B, Y, Y + 0.225, 0.13, 0.27, Mat_Steel);
                  Band (B, Y + 0.225, Y + 0.45, 0.27, 0.13, Mat_Steel);
               end;
            end loop;
      end case;
   end Build_Sculpture;

   procedure Free_All is
   begin
      if Built then
         Meshes.Free (Hall);
         Meshes.Free (Ceiling);
         for M of Pipes loop
            Meshes.Free (M);
         end loop;
         for M of Statues loop
            Meshes.Free (M);
         end loop;
         Built := False;
      end if;
   end Free_All;

   procedure Build is
      Up : constant Vec3 := (0.0, 1.0, 0.0);
   begin
      Free_All;

      --  the hall: concrete floor, white walls, partitions, plinths, the door
      Meshes.Start;
      Meshes.Quad_UV (G (0.0, 0.0, -Half_W), G (Length, 0.0, -Half_W), G (Length, 0.0, Half_W),
                      G (0.0, 0.0, Half_W), Up, Mat_Floor, 0.0, Length, 2.0 * Half_W);
      Face (G (0.0, 0.0, -Half_W), G (Length, 0.0, -Half_W), G (Length, Height, -Half_W),
            G (0.0, Height, -Half_W), (0.0, 0.0, 1.0), Mat_White);
      Face (G (0.0, 0.0, Half_W), G (Length, 0.0, Half_W), G (Length, Height, Half_W),
            G (0.0, Height, Half_W), (0.0, 0.0, -1.0), Mat_White);
      Face (G (0.0, 0.0, -Half_W), G (0.0, 0.0, Half_W), G (0.0, Height, Half_W),
            G (0.0, Height, -Half_W), (1.0, 0.0, 0.0), Mat_White);
      Face (G (Length, 0.0, -Half_W), G (Length, 0.0, Half_W), G (Length, Height, Half_W),
            G (Length, Height, -Half_W), (-1.0, 0.0, 0.0), Mat_White);
      for X of Float_List'(18.0, 38.0) loop
         Meshes.Box (Origin.X + X - 0.15, Origin.X + X + 0.15, Origin.Y, Origin.Y + 4.6,
                     Origin.Z - 4.5, Origin.Z + 4.5, Mat_White);
      end loop;
      for P of Plinths loop
         Meshes.Box (Origin.X + P.X - 0.8, Origin.X + P.X + 0.8, Origin.Y, Origin.Y + 0.6,
                     Origin.Z + P.Z - 0.8, Origin.Z + P.Z + 0.8, Mat_White);
      end loop;
      Face (G (0.03, 0.0, -1.2), G (0.03, 0.0, 1.2), G (0.03, 2.8, 1.2), G (0.03, 2.8, -1.2),
            (1.0, 0.0, 0.0), Mat_Door);
      Meshes.Box (Origin.X + 0.03, Origin.X + 0.12, Origin.Y + 3.0, Origin.Y + 3.45,
                  Origin.Z - 0.8, Origin.Z + 0.8, Mat_Exit);
      --  the paintings
      for I in Slots'Range loop
         declare
            S  : Slot renames Slots (I);
            Al : constant Vec3 := Cross (Up, S.N);
            C  : constant Vec3 := Works (I).C + 0.03 * S.N;
            W2 : constant Float := Sizes_W (I) / 2.0;
            H2 : constant Float := Sizes_H (I) / 2.0;
         begin
            case Kind_Of (I) is
               when Painting =>
                  Meshes.Quad_UV (C - W2 * Al - H2 * Up, C + W2 * Al - H2 * Up,
                                  C + W2 * Al + H2 * Up, C - W2 * Al + H2 * Up,
                                  S.N, Mat_Canvas, Seeds (I));
               when Drawing =>
                  Meshes.Quad_UV (C - W2 * Al - H2 * Up, C + W2 * Al - H2 * Up,
                                  C + W2 * Al + H2 * Up, C - W2 * Al + H2 * Up,
                                  S.N, Mat_Drawing, Seeds (I));
               when Video =>
                  --  a screen with a dark rim
                  Meshes.Quad_UV (C - W2 * Al - H2 * Up, C + W2 * Al - H2 * Up,
                                  C + W2 * Al + H2 * Up, C - W2 * Al + H2 * Up,
                                  S.N, Mat_Video, Seeds (I));
                  Meshes.Quad_UV (C - 0.01 * S.N - (W2 + 0.08) * Al - (H2 + 0.08) * Up,
                                  C - 0.01 * S.N + (W2 + 0.08) * Al - (H2 + 0.08) * Up,
                                  C - 0.01 * S.N + (W2 + 0.08) * Al + (H2 + 0.08) * Up,
                                  C - 0.01 * S.N - (W2 + 0.08) * Al + (H2 + 0.08) * Up,
                                  S.N, Mat_Door, 0.0);
               when Shop =>
                  --  postcards of the paintings, in rows on a board
                  Face (C - 0.01 * S.N - W2 * Al - H2 * Up, C - 0.01 * S.N + W2 * Al - H2 * Up,
                        C - 0.01 * S.N + W2 * Al + H2 * Up, C - 0.01 * S.N - W2 * Al + H2 * Up,
                        S.N, 60.0);
                  for Col in 0 .. 9 loop
                     for Row in 0 .. 3 loop
                        declare
                           Src : constant Positive := 2 + (Col + 10 * Row) mod 11;   --  the paintings' seeds
                           P : constant Vec3 := C - W2 * Al - H2 * Up
                             + (0.25 + 0.43 * Float (Col)) * Al + (0.16 + 0.26 * Float (Row)) * Up;
                        begin
                           Meshes.Quad_UV (P - 0.15 * Al - 0.1 * Up, P + 0.15 * Al - 0.1 * Up,
                                           P + 0.15 * Al + 0.1 * Up, P - 0.15 * Al + 0.1 * Up,
                                           S.N, Mat_Canvas, Seeds (Src));
                        end;
                     end loop;
                  end loop;
            end case;
         end;
      end loop;
      --  the shop's counter, and its sign
      Meshes.Box (Origin.X + Shop_X0, Origin.X + Shop_X1, Origin.Y, Origin.Y + 1.0,
                  Origin.Z + Shop_Z1 - 0.6, Origin.Z + Shop_Z1, Mat_White);
      Meshes.Box (Origin.X + Shop_X0 - 0.02, Origin.X + Shop_X1 + 0.02, Origin.Y + 1.0, Origin.Y + 1.05,
                  Origin.Z + Shop_Z1 - 0.62, Origin.Z + Shop_Z1 + 0.02, Mat_Door);
      Meshes.Box (Origin.X + 4.6, Origin.X + 7.4, Origin.Y + 2.75, Origin.Y + 3.15,
                  Origin.Z - Half_W + 0.02, Origin.Z - Half_W + 0.06, Mat_Door);
      Meshes.Finish (Hall);

      --  the ceiling, dark, and pipes under it in four colours
      Meshes.Start;
      Face (G (0.0, Height, -Half_W), G (Length, Height, -Half_W), G (Length, Height, Half_W),
            G (0.0, Height, Half_W), (0.0, -1.0, 0.0), Mat_Steel);
      Meshes.Finish (Ceiling);
      for K in Pipes'Range loop
         declare
            Z : constant Float := -7.5 + 5.0 * Float (K - 1);
            R : constant Float := (case K is when 1 => 0.38, when 2 => 0.22, when 3 => 0.3, when others => 0.16);
            Y : constant Float := Height - 0.4 - R;
         begin
            Meshes.Start;
            Tube (G (0.2, Y, Z), G (Length - 0.2, Y, Z), R, Mat_Steel, 12);
            --  hangers
            for X in 1 .. 6 loop
               Tube (G (Float (X) * 8.0, Y, Z), G (Float (X) * 8.0, Height, Z), 0.03, Mat_Steel, 5);
            end loop;
            Meshes.Finish (Pipes (K));
         end;
      end loop;

      for I in Plinths'Range loop
         Meshes.Start;
         Build_Sculpture (Kinds (I), G (Plinths (I).X, 0.0, Plinths (I).Z));
         Meshes.Finish (Statues (I));
      end loop;
      Built := True;
   end Build;

   ---------------------------------------------------------------------------

   procedure Keep_Inside (X, Z : in out Float) is
      LX : Float := X - Origin.X;
      LZ : Float := Z - Origin.Z;
   begin
      LX := Float'Max (0.4, Float'Min (Length - 0.4, LX));
      LZ := Float'Max (-Half_W + 0.4, Float'Min (Half_W - 0.4, LZ));
      --  round the partitions
      for PX of Float_List'(18.0, 38.0) loop
         if abs (LX - PX) < 0.55 and then abs LZ < 4.85 then
            if 0.55 - abs (LX - PX) < 4.85 - abs LZ then
               LX := PX + (if LX < PX then -0.55 else 0.55);
            else
               LZ := (if LZ < 0.0 then -4.85 else 4.85);
            end if;
         end if;
      end loop;
      --  the shop's counter
      if LX > Shop_X0 - 0.4 and then LX < Shop_X1 + 0.4 and then LZ < Shop_Z1 + 0.4 then
         if LZ > Shop_Z1 - 0.2 then
            LZ := Shop_Z1 + 0.4;
         end if;
      end if;
      --  and the plinths
      for P of Plinths loop
         declare
            DX : constant Float := LX - P.X;
            DZ : constant Float := LZ - P.Z;
         begin
            if abs DX < 1.2 and then abs DZ < 1.2 then
               if abs DX > abs DZ then
                  LX := P.X + (if DX < 0.0 then -1.2 else 1.2);
               else
                  LZ := P.Z + (if DZ < 0.0 then -1.2 else 1.2);
               end if;
            end if;
         end;
      end loop;
      X := Origin.X + LX;
      Z := Origin.Z + LZ;
   end Keep_Inside;

   function Looked_At (X, Z, Yaw : Float) return Natural;

   function Caption (X, Z, Yaw : Float) return String is
      Best : constant Natural := Looked_At (X, Z, Yaw);
   begin
      if Best = 0 then
         return "";
      end if;
      if Works (Best).Kind = Shop then
         return "<span font_family='sans' size='large'><b>"
           & (if Ada.Strings.Unbounded.Length (Shop_Text) > 0 then To_String (Shop_Text) else "The shop") & "</b></span>" & ASCII.LF
           & "<span font_family='sans'>" & Title & "  ·  postcards, 1.50 €  ·  Enter: buy one</span>";
      end if;
      return "<span font_family='serif' size='large'><i>" & To_String (Works (Best).Name)
        & "</i>, 2026</span>" & ASCII.LF
        & "<span font_family='sans'>" & Artist & "  ·  " & To_String (Works (Best).Medium) & "</span>";
   end Caption;

   --  The work you look at, as Caption picks it (0: none)
   function Looked_At (X, Z, Yaw : Float) return Natural is
      Look_X : constant Float := Sin (Yaw);
      Look_Z : constant Float := -Cos (Yaw);
      Best   : Natural := 0;
      Best_D : Float := Float'Last;
   begin
      for I in 1 .. Work_Count loop
         declare
            W  : Work renames Works (I);
            DX : constant Float := W.C.X - X;
            DZ : constant Float := W.C.Z - Z;
            D  : constant Float := Sqrt (DX * DX + DZ * DZ);
            Sculpture : constant Boolean := W.N.X = 0.0 and then W.N.Z = 0.0;
         begin
            if D < (if Sculpture then 3.5 else 5.0) and then D > 0.1
              and then (DX * Look_X + DZ * Look_Z) / D > 0.75
              and then (Sculpture or else -(DX * W.N.X + DZ * W.N.Z) > 0.5)
              and then D < Best_D
            then
               Best := I;
               Best_D := D;
            end if;
         end;
      end loop;
      return Best;
   end Looked_At;

   function At_Shop (X, Z, Yaw : Float) return Boolean is
      I : constant Natural := Looked_At (X, Z, Yaw);
   begin
      return I /= 0 and then Works (I).Kind = Shop;
   end At_Shop;

   Card_Turn : Natural := 0;

   procedure Next_Card (Name, Text : out Unbounded_String; Eye, Look : out Vec3) is
      I : Positive := 1;
   begin
      --  the next painting in turn
      for K in 1 .. Slots'Length loop
         Card_Turn := Card_Turn mod Slots'Length + 1;
         if Kind_Of (Card_Turn) = Painting then
            I := Card_Turn;
            exit;
         end if;
      end loop;
      declare
         W : Work renames Works (I);
         --  far enough back for it to fill the picture
         D : constant Float := 1.3 * Float'Max (Sizes_H (I) / 1.2, Sizes_W (I) / 2.2) + 0.05;
      begin
         Look := W.C;
         Eye := W.C + D * W.N;
         Name := +(To_String (W.Name) & " (" & Title & ")");
         Text := +(Artist & ", " & To_String (W.Name) & ", 2026, " & To_String (W.Medium) & ".  From "
                   & Title & ", " & Heading & "; a postcard from the shop, 1.50 €.");
      end;
   end Next_Card;

   procedure Update (Dt : Float) is
   begin
      Clock := Clock + Dt;
   end Update;

   procedure Draw (Model, Paint, Skin, Legs, Gallery : GL.GLint) is
   begin
      if Need_Build then
         Build;
         Need_Build := False;
      end if;
      if not Built then
         return;
      end if;
      Shaders.Set (Gallery, 2.0);
      Shaders.Set (Model, Identity);
      Meshes.Draw (Hall);
      Shaders.Set (Paint, Vec3'(0.2, 0.21, 0.23));
      Meshes.Draw (Ceiling);
      for K in Pipes'Range loop
         Shaders.Set (Paint, Pipe_Colours (K));
         Meshes.Draw (Pipes (K));
      end loop;
      for I in Plinths'Range loop
         Shaders.Set (Paint, Colours (I));
         if Kinds (I) = Mobile then
            --  turning slowly
            declare
               C : constant Vec3 := G (Plinths (I).X, 0.0, Plinths (I).Z);
            begin
               Shaders.Set (Model, Translation (C) * Rotation_Y (0.15 * Clock)
                            * Translation ((-1.0) * C));
            end;
         else
            Shaders.Set (Model, Identity);
         end if;
         Meshes.Draw (Statues (I));
      end loop;
      Figures.Set_Locations ((Model, Paint, Skin, Legs));
      Figures.Person (Translation (G (6.0, 0.0, Shop_Z1 - 1.1)) * Rotation_Y (Pi), (0.1, 0.1, 0.12),
                      (0.76, 0.57, 0.44), (0.12, 0.12, 0.14));   --  at the till
      for K in Visitors'Range loop
         exit when Snapping;
         declare
            V : Visitor renames Visitors (K);
         begin
            Figures.Person (Translation (V.P) * Rotation_Y (-V.Face + 0.05 * Sin (Clock * 0.5 + Float (K))),
                            V.Coat, V.Skin, (0.15, 0.15, 0.18));
         end;
      end loop;
      Shaders.Set (Gallery, 0.0);
   end Draw;

end Hall_B;
