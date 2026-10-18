--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Containers.Ordered_Maps;
with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Environment_Variables;
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;
with Ada.Strings.Fixed;
with Ada.Text_IO;

with Figures;
with Geo;
with Meshes;
with Shaders;
with Sound;
with Tyre_Effects;
with Terrain;

package body Race is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;
   use Ada.Strings.Unbounded;
   use type Car.Model_Kind;
   subtype Count_Type is Ada.Containers.Count_Type;

   Pi : constant := Ada.Numerics.Pi;

   Gen : Ada.Numerics.Float_Random.Generator;
   Seeded : Boolean := False;
   function Rnd return Float is (Ada.Numerics.Float_Random.Random (Gen));

   ---------------------------------------------------------------------------
   --  Tracks: loops of points (latitude, longitude)
   ---------------------------------------------------------------------------

   type Point is record
      Lat, Lon : Long_Float;
   end record;
   package Point_Vectors is new Ada.Containers.Vectors (Positive, Point);

   type Track is record
      Name   : Unbounded_String;
      Points : Point_Vectors.Vector;
   end record;
   package Track_Vectors is new Ada.Containers.Vectors (Positive, Track);
   Tracks : Track_Vectors.Vector;
   Ready_Made : Natural := 0;

   procedure Add (Name : String; P : Point_Vectors.Vector) is
   begin
      Tracks.Append ((To_Unbounded_String (Name), P));
   end Add;

   procedure Built_In is
      V : Point_Vectors.Vector;
      procedure P (Lat, Lon : Long_Float) is
      begin
         V.Append ((Lat, Lon));
      end P;
   begin
      --  The Champs-Élysées: up to the Étoile, down to the Alma and back
      --  along the Seine
      V.Clear;
      P (48.86600, 2.32000);   --  Concorde
      P (48.86935, 2.30920);   --  Rond-point des Champs-Élysées
      P (48.87330, 2.29800);   --  the top of the avenue
      P (48.86880, 2.29880);   --  avenue Marceau
      P (48.86450, 2.30140);   --  place de l'Alma
      P (48.86450, 2.31500);   --  cours la Reine
      Add ("Champs-Élysées", V);
      --  The quays of the Seine, the Louvre and Orsay
      V.Clear;
      P (48.85660, 2.35050);   --  Hôtel de Ville
      P (48.85900, 2.33900);   --  quai du Louvre
      P (48.86260, 2.32350);   --  Concorde side
      P (48.86040, 2.32480);   --  over the river: quai Anatole-France
      P (48.85780, 2.33470);   --  quai Voltaire
      P (48.85470, 2.34580);   --  quai des Grands-Augustins
      Add ("Quais de Seine", V);
      --  Saint-Germain: round the church and the Odéon
      V.Clear;
      P (48.85190, 2.33302);   --  Saint-Sulpice
      P (48.85380, 2.33420);   --  Saint-Germain-des-Prés
      P (48.85310, 2.34200);   --  rue Dauphine side
      P (48.85060, 2.33880);   --  Odéon
      P (48.84850, 2.33200);   --  rue de Vaugirard
      Add ("Saint-Germain", V);
      --  Montmartre: up the hill and round its back
      V.Clear;
      P (48.88208, 2.33768);   --  Pigalle
      P (48.88440, 2.33840);   --  Abbesses
      P (48.88900, 2.33850);   --  rue Caulaincourt
      P (48.88850, 2.34560);   --  rue Custine
      P (48.88360, 2.34900);   --  boulevard de Rochechouart
      Add ("Montmartre", V);
      --  The Marais and the Bastille
      V.Clear;
      P (48.85590, 2.35830);   --  rue de Rivoli
      P (48.85520, 2.36580);   --  place des Vosges side
      P (48.85320, 2.36900);   --  Bastille
      P (48.85070, 2.36200);   --  quai des Célestins
      P (48.85350, 2.35700);   --  Saint-Paul
      Add ("Le Marais", V);
      Ready_Made := Natural (Tracks.Length);
   end Built_In;

   function Tracks_File return String is
     (Ada.Environment_Variables.Value ("HOME", ".") & "/.derive_tracks");

   procedure Load_Saved is
      use Ada.Text_IO;
      F : File_Type;
      Cur : Track;
      Open_Track : Boolean := False;
   begin
      if Ready_Made = 0 then
         Built_In;
      end if;
      while Natural (Tracks.Length) > Ready_Made loop
         Tracks.Delete_Last;
      end loop;
      if not Ada.Directories.Exists (Tracks_File) then
         return;
      end if;
      Open (F, In_File, Tracks_File);
      while not End_Of_File (F) loop
         declare
            Line : constant String := Ada.Strings.Fixed.Trim (Get_Line (F), Ada.Strings.Both);
         begin
            if Line'Length > 6 and then Line (Line'First .. Line'First + 5) = "track " then
               if Open_Track and then Natural (Cur.Points.Length) >= 2 then
                  Tracks.Append (Cur);
               end if;
               Cur := (To_Unbounded_String (Line (Line'First + 6 .. Line'Last)), Point_Vectors.Empty_Vector);
               Open_Track := True;
            elsif Line'Length > 0 and then Line (Line'First) /= '#' and then Open_Track then
               declare
                  Sp : constant Natural := Ada.Strings.Fixed.Index (Line, " ");
               begin
                  if Sp > 0 then
                     Cur.Points.Append ((Long_Float'Value (Line (Line'First .. Sp - 1)),
                                         Long_Float'Value (Line (Sp + 1 .. Line'Last))));
                  end if;
               exception
                  when Constraint_Error => null;
               end;
            end if;
         end;
      end loop;
      if Open_Track and then Natural (Cur.Points.Length) >= 2 then
         Tracks.Append (Cur);
      end if;
      Close (F);
   exception
      when others =>
         if Is_Open (F) then
            Close (F);
         end if;
   end Load_Saved;

   function Track_Count return Natural is
   begin
      if Ready_Made = 0 then
         Load_Saved;
      end if;
      return Natural (Tracks.Length);
   end Track_Count;

   function Track_Name (I : Positive) return String is
     (To_String (Tracks (I).Name)
      & (if I > Ready_Made then "  (yours)" else ""));

   ---------------------------------------------------------------------------
   --  The editor
   ---------------------------------------------------------------------------

   Edit_On : Boolean := False;
   Edit_List : Point_Vectors.Vector;

   function Editing return Boolean is (Edit_On);
   function Edit_Points return Natural is (Natural (Edit_List.Length));

   procedure Edit_Start is
   begin
      Edit_On := True;
      Edit_List.Clear;
   end Edit_Start;

   procedure Edit_Drop (X, Z : Float; Ok : out Boolean) is
      Lat, Lon : Long_Float;
      PX, PZ   : Long_Float;
   begin
      if not Edit_List.Is_Empty then
         Geo.To_Local (Edit_List.Last_Element.Lat, Edit_List.Last_Element.Lon, PX, PZ);
         if (Float (PX) - X) ** 2 + (Float (PZ) - Z) ** 2 < 40.0 ** 2 then
            Ok := False;
            return;
         end if;
      end if;
      Geo.To_Lat_Lon (Long_Float (X), Long_Float (Z), Lat, Lon);
      Edit_List.Append ((Lat, Lon));
      Ok := True;
   end Edit_Drop;

   procedure Edit_Undo is
   begin
      if not Edit_List.Is_Empty then
         Edit_List.Delete_Last;
      end if;
   end Edit_Undo;

   procedure Edit_Cancel is
   begin
      Edit_On := False;
      Edit_List.Clear;
   end Edit_Cancel;

   function Fixed6 (V : Long_Float) return String is
      Micro : constant Long_Long_Integer := Long_Long_Integer (V * 1.0E6);
      Whole : constant String := Long_Long_Integer'Image (abs Micro / 1_000_000);
      Frac  : constant String := Long_Long_Integer'Image (1_000_000 + abs Micro mod 1_000_000);
   begin
      return (if Micro < 0 then "-" else "") & Whole (Whole'First + 1 .. Whole'Last)
        & "." & Frac (Frac'First + 2 .. Frac'Last);
   end Fixed6;

   procedure Edit_Save (Name : out Unbounded_String) is
      use Ada.Text_IO;
      F : File_Type;
   begin
      Name := Null_Unbounded_String;
      if Natural (Edit_List.Length) < 2 then
         return;
      end if;
      Name := To_Unbounded_String
        ("My track" & Natural'Image (Natural (Tracks.Length) - Ready_Made + 1));
      if Ada.Directories.Exists (Tracks_File) then
         Open (F, Append_File, Tracks_File);
      else
         Create (F, Out_File, Tracks_File);
         Put_Line (F, "# Race tracks made in Derive (the names can be changed here)");
      end if;
      Put_Line (F, "track " & To_String (Name));
      for P of Edit_List loop
         Put_Line (F, Fixed6 (P.Lat) & " " & Fixed6 (P.Lon));
      end loop;
      Close (F);
      Edit_On := False;
      Edit_List.Clear;
      Load_Saved;
   exception
      when E : others =>
         Ada.Text_IO.Put_Line ("race: could not save the track: "
                               & Ada.Exceptions.Exception_Message (E));
         if Is_Open (F) then
            Close (F);
         end if;
   end Edit_Save;

   ---------------------------------------------------------------------------
   --  The course: the loop through the streets
   ---------------------------------------------------------------------------

   package Vec_Vectors is new Ada.Containers.Vectors (Natural, Vec3);
   package Float_Vectors is new Ada.Containers.Vectors (Natural, Float);

   Course : Vec_Vectors.Vector;     --  every few metres, closed loop
   Cum    : Float_Vectors.Vector;   --  distance from the start to each point
   Widths : Float_Vectors.Vector;   --  the width of the road there
   Start_Off : Float := 0.0;        --  where on the loop the start line is
   package Way_Vectors is new Ada.Containers.Vectors (Natural, Natural);
   Line   : Road_Network.Route_Vectors.Vector;   --  the course street by street
   Line_S : Float_Vectors.Vector;                --  where each point is on the loop

   --  The course in cells of 16 m, to find the nearby stretch quickly
   Cell : constant := 16.0;
   package Index_Vectors is new Ada.Containers.Vectors (Positive, Natural);
   package Cell_Maps is new Ada.Containers.Ordered_Maps
     (Integer, Index_Vectors.Vector, "<", Index_Vectors."=");
   Cells : Cell_Maps.Map;

   function Cell_Key (CX, CZ : Integer) return Integer is ((CX + 10_000) * 20_000 + (CZ + 10_000));

   procedure Index_Course is
   begin
      Cells.Clear;
      for I in Course.First_Index .. Course.Last_Index - 1 loop
         declare
            K : constant Integer :=
              Cell_Key (Integer (Float'Floor ((Course (I).X + Course (I + 1).X) / 2.0 / Cell)),
                        Integer (Float'Floor ((Course (I).Z + Course (I + 1).Z) / 2.0 / Cell)));
            C : constant Cell_Maps.Cursor := Cells.Find (K);
         begin
            if Cell_Maps.Has_Element (C) then
               Cells.Reference (C).Append (I);
            else
               declare
                  V : Index_Vectors.Vector;
               begin
                  V.Append (I);
                  Cells.Insert (K, V);
               end;
            end if;
         end;
      end loop;
   end Index_Course;
   Total  : Float := 0.0;
   Gates  : Float_Vectors.Vector;   --  where the checkpoints are (distance)
   Laps   : Positive := 2;
   Laps_Wanted : Natural := 0;      --  0: by the length of the track
   Course_Name : Unbounded_String;
   Course_Mesh : Meshes.Mesh;
   Mesh_Built  : Boolean := False;
   Need_Mesh   : Boolean := False;   --  built at the next Draw (GL there)

   --  The segment of the loop at a distance from the start line
   procedure Locate (S : Float; U : out Float; Lo, Hi : out Natural) is
      W : constant Float := S + Start_Off;
   begin
      U := W - Total * Float'Floor (W / Total);
      Lo := 0;
      Hi := Course.Last_Index;
      --  binary search for the segment
      while Hi - Lo > 1 loop
         declare
            Mid : constant Natural := (Lo + Hi) / 2;
         begin
            if Cum (Mid) <= U then
               Lo := Mid;
            else
               Hi := Mid;
            end if;
         end;
      end loop;
   end Locate;

   --  Position and direction at a distance along the loop
   procedure At_S (S : Float; P, T : out Vec3) is
      U : Float;
      Lo, Hi : Natural;
   begin
      Locate (S, U, Lo, Hi);
      declare
         A : constant Vec3 := Course (Lo);
         B : constant Vec3 := Course (Hi);
         L : constant Float := Float'Max (0.01, Cum (Hi) - Cum (Lo));
         F : constant Float := Float'Max (0.0, Float'Min (1.0, (U - Cum (Lo)) / L));
      begin
         U := F;
         P := A + U * (B - A);
         T := Normalize (B - A);
      end;
   end At_S;

   --  How far from the middle of the road a car can be
   function Room (S : Float) return Float is
      U : Float;
      Lo, Hi : Natural;
   begin
      Locate (S, U, Lo, Hi);
      return Float'Max (0.0, Float'Min (Widths (Lo), Widths (Hi)) / 2.0 - 1.3);
   end Room;

   function Right_Of (T : Vec3) return Vec3 is ((-T.Z, 0.0, T.X));

   type Sides is array (1 .. 2) of Float;
   Side_List : constant Sides := (-1.0, 1.0);
   type Spots is array (1 .. 3) of Float;
   Car_Points : constant Spots := (-1.5, 0.0, 1.6);   --  tail, middle, nose

   procedure Find_Barriers;
   --  (below) close the side streets
   procedure Find_Signs;
   --  (below) chevrons at the turns

   procedure Build_Course (Waypoints : Point_Vectors.Vector; Ok : out Boolean) is
      use Road_Network;
      N : constant Natural := Natural (Waypoints.Length);
      XS, ZS : array (1 .. N) of Float;
      Raw : Vec_Vectors.Vector;
      Raw_W : Float_Vectors.Vector;
      Raw_Way : Way_Vectors.Vector;
   begin
      Line.Clear;
      Line_S.Clear;
      Ok := False;
      Course.Clear;
      Cum.Clear;
      Widths.Clear;
      Gates.Clear;
      Start_Off := 0.0;
      if N < 2 then
         return;
      end if;
      for I in 1 .. N loop
         declare
            X, Z : Long_Float;
         begin
            Geo.To_Local (Waypoints (I).Lat, Waypoints (I).Lon, X, Z);
            XS (I) := Float (X);
            ZS (I) := Float (Z);
         end;
      end loop;
      --  start on the road itself, where the last leg will end
      declare
         Found : Boolean;
         RX, RZ, RH : Float;
      begin
         Road_Network.Nearest_Road (XS (1), ZS (1), Found, RX, RZ, RH);
         if Found then
            XS (1) := RX;
            ZS (1) := RZ;
         end if;
      end;
      --  route from each point to the next, and from the last back
      for I in 1 .. N loop
         declare
            J : constant Positive := (if I = N then 1 else I + 1);
            Heading : constant Float :=
              (if Natural (Raw.Length) < 2 then Arctan (XS (J) - XS (I), -(ZS (J) - ZS (I)))
               else Arctan (Raw.Last_Element.X - Raw (Raw.Last_Index - 1).X,
                            -(Raw.Last_Element.Z - Raw (Raw.Last_Index - 1).Z)));
            Leg   : Route_Vectors.Vector;
            Found : Boolean;
            FX : constant Float := (if Raw.Is_Empty then XS (I) else Raw.Last_Element.X);
            FZ : constant Float := (if Raw.Is_Empty then ZS (I) else Raw.Last_Element.Z);
         begin
            Find_Route (FX, FZ, Heading, XS (J), ZS (J), Leg, Found, Any_Way => True);
            if not Found or else Leg.Is_Empty then
               Ada.Text_IO.Put_Line ("race: no way from point" & Integer'Image (I) & " to" & Integer'Image (J));
               return;
            end if;
            for P of Leg loop
               if Raw.Is_Empty
                 or else (P.X - Raw.Last_Element.X) ** 2 + (P.Z - Raw.Last_Element.Z) ** 2 > 0.25
               then
                  Raw.Append ((P.X, 0.0, P.Z));
                  Raw_W.Append
                    (if Road_Network.Ways /= null and then P.Way in Road_Network.Ways'Range
                     then Float'Max (3.0, Road_Network.Ways (P.Way).Width) else 7.0);
                  Raw_Way.Append (P.Way);
               end if;
            end loop;
         end;
      end loop;
      --  No dead ends: where a checkpoint lies up a side street the route
      --  goes there and straight back; cut that out (it would be a U-turn,
      --  and the barrier where the street goes on would be in the way)
      declare
         --  distance from point I to the route between points From .. To
         function Near (I : Natural; From, To : Integer) return Float is
            Best : Float := Float'Last;
         begin
            for K in Integer'Max (Raw.First_Index, From) .. Integer'Min (Raw.Last_Index, To) - 1 loop
               declare
                  A  : Vec3 renames Raw (K);
                  B  : Vec3 renames Raw (K + 1);
                  EX : constant Float := B.X - A.X;
                  EZ : constant Float := B.Z - A.Z;
                  T  : constant Float := Float'Max (0.0, Float'Min (1.0,
                    ((Raw (I).X - A.X) * EX + (Raw (I).Z - A.Z) * EZ)
                    / Float'Max (0.0001, EX * EX + EZ * EZ)));
               begin
                  Best := Float'Min (Best, Sqrt ((A.X + T * EX - Raw (I).X) ** 2
                                                 + (A.Z + T * EZ - Raw (I).Z) ** 2));
               end;
            end loop;
            return Best;
         end Near;

         procedure Cut_Spurs is
            Again : Boolean := True;
         begin
            while Again and then Natural (Raw.Length) > 6 loop
               Again := False;
               for K in Raw.First_Index + 1 .. Raw.Last_Index - 1 loop
                  declare
                     U : constant Vec3 := Raw (K) - Raw (K - 1);
                     V : constant Vec3 := Raw (K + 1) - Raw (K);
                  begin
                     if Dot (U, V) < -0.7 * Length (U) * Length (V) then
                        declare
                           A : Natural := K - 1;
                           B : Natural := K + 1;
                        begin
                           --  back along the way out while the way back runs
                           --  on it, and on along the way back likewise
                           while A > Raw.First_Index and then Near (A, K, K + 200) < 2.0 loop
                              A := A - 1;
                           end loop;
                           while B < Raw.Last_Index and then Near (B, K - 200, K) < 2.0 loop
                              B := B + 1;
                           end loop;
                           if B - A > 2 and then (A < K - 1 or else B > K + 1) then
                              Raw.Delete (A + 1, Count_Type (B - A - 1));
                              Raw_W.Delete (A + 1, Count_Type (B - A - 1));
                              Raw_Way.Delete (A + 1, Count_Type (B - A - 1));
                              Again := True;
                              exit;
                           end if;
                        end;
                     end if;
                  end;
               end loop;
            end loop;
         end Cut_Spurs;

         procedure Rotate_Half is
            Half : constant Natural := Natural (Raw.Length) / 2;
         begin
            for K in 1 .. Half loop
               Raw.Append (Raw.First_Element);
               Raw_W.Append (Raw_W.First_Element);
               Raw_Way.Append (Raw_Way.First_Element);
               Raw.Delete_First;
               Raw_W.Delete_First;
               Raw_Way.Delete_First;
            end loop;
         end Rotate_Half;
      begin
         --  a loop, without the end repeating the start
         while Natural (Raw.Length) > 3
           and then Length (Raw.Last_Element - Raw.First_Element) < 1.0
         loop
            Raw.Delete_Last;
            Raw_W.Delete_Last;
            Raw_Way.Delete_Last;
         end loop;
         Cut_Spurs;
         Rotate_Half;   --  for one round the start
         Cut_Spurs;
      end;
      if Natural (Raw.Length) < 3 then
         return;
      end if;
      --  every 4 m, closed
      Raw.Append (Raw.First_Element);
      Raw_W.Append (Raw_W.First_Element);
      Raw_Way.Append (Raw_Way.First_Element);
      Course.Append (Raw.First_Element);
      Widths.Append (Raw_W.First_Element);
      Cum.Append (0.0);
      declare
         Carry : Float := 0.0;
      begin
         for I in Raw.First_Index .. Raw.Last_Index - 1 loop
            declare
               A : constant Vec3 := Raw (I);
               B : constant Vec3 := Raw (I + 1);
               L : constant Float := Length (B - A);
               S : Float := 4.0 - Carry;
            begin
               while S <= L loop
                  Course.Append (A + (S / Float'Max (L, 0.001)) * (B - A));
                  Widths.Append (Raw_W (I));
                  Cum.Append (Cum.Last_Element + Length (Course.Last_Element - Course (Course.Last_Index - 1)));
                  S := S + 4.0;
               end loop;
               Carry := L - (S - 4.0);
            end;
         end loop;
      end;
      Course.Append (Course.First_Element);
      Widths.Append (Widths.First_Element);
      Cum.Append (Cum.Last_Element + Length (Course.First_Element - Course (Course.Last_Index - 1)));
      for P of Course loop
         P.Y := Terrain.Height (P.X, P.Z);
      end loop;
      Total := Cum.Last_Element;
      if Total < 300.0 then
         return;
      end if;
      --  the streets themselves, for the GPS (their turns and names)
      declare
         D : Float := 0.0;
         Raw_Total : Float := 0.0;
      begin
         for I in Raw.First_Index .. Raw.Last_Index - 1 loop
            Raw_Total := Raw_Total + Length (Raw (I + 1) - Raw (I));
         end loop;
         for I in Raw.First_Index .. Raw.Last_Index - 1 loop
            Line.Append ((Raw (I).X, Raw (I).Z, Raw_Way (I)));
            Line_S.Append (D * Total / Float'Max (1.0, Raw_Total));
            D := D + Length (Raw (I + 1) - Raw (I));
         end loop;
      end;
      Laps := (if Laps_Wanted > 0 then Laps_Wanted
               elsif Total < 2500.0 then 3 elsif Total < 6000.0 then 2 else 1);
      --  the start on the straightest, widest stretch: the grid is behind
      --  the line, so look back 70 m and a little ahead
      declare
         Best : Float := Float'Last;
         Best_S : Float := 0.0;
         C : Float := 0.0;
      begin
         while C < Total loop
            declare
               Bend : Float := 0.0;
               P0, T0, P1, T1 : Vec3;
            begin
               At_S (C - 70.0, P0, T0);
               for K in 1 .. 9 loop
                  At_S (C - 70.0 + 10.0 * Float (K), P1, T1);
                  Bend := Bend + Arccos (Float'Max (-1.0, Float'Min (1.0, Dot (T0, T1))));
                  T0 := T1;
               end loop;
               Bend := Bend + 0.4 / Float'Max (0.3, Room (C - 20.0));
               if Bend < Best then
                  Best := Bend;
                  Best_S := C;
               end if;
            end;
            C := C + 20.0;
         end loop;
         Start_Off := Best_S;
      end;
      Index_Course;
      Find_Barriers;
      Find_Signs;
      --  a checkpoint every 250 m or so; the first is the start and finish
      declare
         K : constant Positive := Positive'Max (4, Positive (Total / 250.0));
      begin
         for G in 0 .. K - 1 loop
            Gates.Append (Total * Float (G) / Float (K));
         end loop;
      end;
      Ok := True;
   end Build_Course;

   ---------------------------------------------------------------------------
   --  Damage: knocks add up (the harder, the much worse); past 30 % the car
   --  smokes and loses power, past 60 % the engine misfires, at 100 % it
   --  is wrecked and out of the race
   ---------------------------------------------------------------------------

   Me_Damage  : Float := 0.0;      --  0 .. 1
   Me_Wrecked : Boolean := False;
   Pending    : Float := 0.0;      --  speed lost in the knock going on now
   Pending_Time : Float := 0.0;
   Critical_Time : Float := 0.0;   --  the warning, for a few seconds
   Misfire_Time  : Float := 0.0;   --  the engine cut out, for a moment
   Pull_Side  : Float := 1.0;      --  which way a bent car pulls

   Quiet_Time : Float := 0.0;      --  since the last knock that did harm

   --  How much a knock does: nothing below about 10 km/h lost, and
   --  growing with the square of it (a crash at 60 km/h is about 13 %,
   --  at 100 km/h about 40 %)
   function Harm (Loss : Float) return Float is
     (if Loss <= 3.0 then 0.0 else ((Loss - 3.0) / 38.0) ** 2);

   procedure Impact (Loss : Float) is
   begin
      --  a knock lasts a few steps: add up what is lost in 0.12 s from
      --  the first touch (a long scrape is many small, harmless knocks)
      if Pending_Time <= 0.0 then
         Pending_Time := 0.12;
      end if;
      Pending := Pending + Loss;
   end Impact;

   function Damage return Float is (Me_Damage);
   function Wrecked return Boolean is (Me_Wrecked);

   ---------------------------------------------------------------------------
   --  Barriers: every street leaving the course is closed off, so there is
   --  only one way to go
   ---------------------------------------------------------------------------

   type Barrier is record
      C    : Vec3;            --  the middle, on the ground
      D    : Vec3;            --  along the barrier (unit)
      Half : Float;           --  half its length
   end record;
   package Barrier_Vectors is new Ada.Containers.Vectors (Positive, Barrier);
   Barriers : Barrier_Vectors.Vector;

   --  How far a point is from the course, and the half width of the road
   --  at the nearest place
   procedure Nearest (X, Z : Float; D, Half, NX, NZ : out Float) is
      Best : Float := 1.0E12;
   begin
      Half := 4.0;
      NX := X;
      NZ := Z;
      for I in Course.First_Index .. Course.Last_Index - 1 loop
         declare
            A  : Vec3 renames Course (I);
            B  : Vec3 renames Course (I + 1);
            EX : constant Float := B.X - A.X;
            EZ : constant Float := B.Z - A.Z;
            --  quick reject: the segments are 4 m long
            Q  : constant Float := (X - A.X) ** 2 + (Z - A.Z) ** 2;
         begin
            if Q < Best + 9.0 * Sqrt (Best) + 20.25 then
               declare
                  L2 : constant Float := Float'Max (0.0001, EX * EX + EZ * EZ);
                  T  : constant Float :=
                    Float'Max (0.0, Float'Min (1.0, ((X - A.X) * EX + (Z - A.Z) * EZ) / L2));
                  PX : constant Float := A.X + T * EX - X;
                  PZ : constant Float := A.Z + T * EZ - Z;
                  D2 : constant Float := PX * PX + PZ * PZ;
               begin
                  if D2 < Best then
                     Best := D2;
                     Half := Widths (I) / 2.0;
                     NX := X + PX;
                     NZ := Z + PZ;
                  end if;
               end;
            end if;
         end;
      end loop;
      D := Sqrt (Best);
   end Nearest;

   procedure Off_Course (X, Z : Float; D, Half : out Float) is
      NX, NZ : Float;
   begin
      Nearest (X, Z, D, Half, NX, NZ);
   end Off_Course;

   ---------------------------------------------------------------------------
   --  Signs: at each turn a board straight ahead, red chevrons on white
   --  pointing the way
   ---------------------------------------------------------------------------

   type Sign is record
      C     : Vec3;     --  the middle, on the ground
      Ahead : Vec3;     --  the way the cars come (the board faces back)
      Turn  : Float;    --  +1 right, -1 left
   end record;
   package Sign_Vectors is new Ada.Containers.Vectors (Positive, Sign);
   Signs : Sign_Vectors.Vector;

   procedure Find_Signs is
      S : Float := 0.0;
      Last : Float := -1000.0;
   begin
      Signs.Clear;
      while S < Total loop
         declare
            P, T, P0, T0, P1, T1 : Vec3;
            Angle : Float;
         begin
            At_S (S, P, T);
            At_S (S - 20.0, P0, T0);
            At_S (S + 20.0, P1, T1);
            Angle := Arctan (T0.X * T1.Z - T0.Z * T1.X, T0.X * T1.X + T0.Z * T1.Z);
            if abs Angle > 0.75 and then S - Last > 50.0 then
               --  the corner itself: where the bend is sharpest near here
               declare
                  Best : Float := 0.0;
                  Best_S : Float := S;
               begin
                  for K in 0 .. 5 loop
                     declare
                        Q0, U0, Q1, U1 : Vec3;
                        A : Float;
                     begin
                        At_S (S + 4.0 * Float (K) - 8.0, Q0, U0);
                        At_S (S + 4.0 * Float (K), Q1, U1);
                        A := abs Arctan (U0.X * U1.Z - U0.Z * U1.X, U0.X * U1.X + U0.Z * U1.Z);
                        if A > Best then
                           Best := A;
                           Best_S := S + 4.0 * Float (K) - 4.0;
                        end if;
                     end;
                  end loop;
                  At_S (Best_S, P, T);
                  --  straight on from the way in, just off the course
                  for Out_D in 0 .. 4 loop
                     declare
                        Q : constant Vec3 := P + (Room (Best_S) + 4.0 + 2.0 * Float (Out_D)) * T0;
                        D, H : Float;
                     begin
                        Off_Course (Q.X, Q.Z, D, H);
                        if D > H + 1.5 then
                           Signs.Append ((C     => (Q.X, Terrain.Height (Q.X, Q.Z), Q.Z),
                                          Ahead => T0,
                                          Turn  => (if Angle > 0.0 then 1.0 else -1.0)));
                           exit;
                        end if;
                     end;
                  end loop;
                  Last := Best_S;
                  S := Best_S + 30.0;
               end;
            end if;
         end;
         S := S + 6.0;
      end loop;
   end Find_Signs;

   procedure Find_Barriers is
      procedure Visit (AX, AZ, BX, BZ, Width : Float; Named : Boolean) is
         pragma Unreferenced (Named);
         DA, HA, DB, HB : Float;
         --  from the course end (In) outwards (Out)
         IX, IZ, OX, OZ, Limit : Float;
      begin
         Off_Course (AX, AZ, DA, HA);
         Off_Course (BX, BZ, DB, HB);
         if DA < HA + 3.0 and then DB >= HA + 3.0 then
            IX := AX; IZ := AZ; OX := BX; OZ := BZ; Limit := HA + 3.0;
         elsif DB < HB + 3.0 and then DA >= HB + 3.0 then
            IX := BX; IZ := BZ; OX := AX; OZ := AZ; Limit := HB + 3.0;
         else
            return;
         end if;
         --  where along it the street is just clear of the course
         declare
            Lo : Float := 0.0;
            Hi : Float := 1.0;
            D, H : Float;
         begin
            for K in 1 .. 10 loop
               Off_Course (IX + (Lo + Hi) / 2.0 * (OX - IX), IZ + (Lo + Hi) / 2.0 * (OZ - IZ), D, H);
               if D < Limit then
                  Lo := (Lo + Hi) / 2.0;
               else
                  Hi := (Lo + Hi) / 2.0;
               end if;
            end loop;
            declare
               Dir : constant Vec3 := Normalize (Vec3'(OX - IX, 0.0, OZ - IZ));
               Seg : constant Float := Sqrt ((OX - IX) ** 2 + (OZ - IZ) ** 2);
               Across : constant Vec3 := (-Dir.Z, 0.0, Dir.X);
               Want : constant Float := Width / 2.0 + 3.5;   --  over the pavements
               --  how far the barrier can reach to one side before the course
               function Reach (CX, CZ, Side : Float) return Float is
                  L : Float := Want;
                  D, H : Float;
               begin
                  loop
                     Off_Course (CX + Side * L * Across.X, CZ + Side * L * Across.Z, D, H);
                     exit when D > H + 1.0 or else L <= 0.0;
                     L := L - 0.5;
                  end loop;
                  return Float'Max (0.0, L);
               end Reach;
               Best_Cover : Float := -1.0;
               BX, BZ, L1, L2 : Float := 0.0;
            begin
               --  just clear of the course; further up the street if there
               --  it would not close the whole carriageway
               for Step in 0 .. 4 loop
                  declare
                     Along : constant Float := Hi * Seg + 3.0 * Float (Step);
                     CX : constant Float := IX + Along * Dir.X;
                     CZ : constant Float := IZ + Along * Dir.Z;
                     R1 : constant Float := Reach (CX, CZ, -1.0);
                     R2 : constant Float := Reach (CX, CZ, 1.0);
                     Cover : constant Float := Float'Min (R1, Width / 2.0 + 0.5)
                       + Float'Min (R2, Width / 2.0 + 0.5);
                  begin
                     exit when Step > 0 and then Along > Seg + 5.0;
                     if Cover > Best_Cover + 0.5 then
                        Best_Cover := Cover;
                        BX := CX;
                        BZ := CZ;
                        L1 := R1;
                        L2 := R2;
                     end if;
                     exit when Cover >= Width + 0.9;
                  end;
               end loop;
               if L1 + L2 < 2.0 then
                  return;
               end if;
               declare
                  MX : constant Float := BX + (L2 - L1) / 2.0 * Across.X;
                  MZ : constant Float := BZ + (L2 - L1) / 2.0 * Across.Z;
               begin
                  --  the same street found again (not another at the same corner)
                  for B of Barriers loop
                     if (B.C.X - MX) ** 2 + (B.C.Z - MZ) ** 2 < 4.0 ** 2
                       and then abs (B.D.X * Dir.Z - B.D.Z * Dir.X) > 0.9
                     then
                        return;
                     end if;
                  end loop;
                  Barriers.Append ((C    => (MX, Terrain.Height (MX, MZ), MZ),
                                    D    => Across,
                                    Half => (L1 + L2) / 2.0));
               end;
            end;
         end;
      end Visit;
      procedure Scan is new Road_Network.For_Segments_Near (Visit);
      S : Float := 0.0;
      P, T : Vec3;
   begin
      Barriers.Clear;
      while S < Total loop
         At_S (S, P, T);
         Scan (P.X, P.Z, 100.0);   --  wide: a long street is found by its far end
         S := S + 40.0;
      end loop;
   end Find_Barriers;

   --  Keep the car out of the barriers (its middle, nose and tail)
   procedure Hit_Barriers (Player : in out Car.State) is
      F : constant Vec3 := Car.Forward (Player);
      Before : constant Float := abs Player.Speed;
   begin
      for B of Barriers loop
         if (B.C.X - Player.X) ** 2 + (B.C.Z - Player.Z) ** 2 < (B.Half + 4.0) ** 2 then
            for Along_Car of Car_Points loop
               declare
                  QX : constant Float := Player.X + Along_Car * F.X;
                  QZ : constant Float := Player.Z + Along_Car * F.Z;
                  T  : constant Float := Float'Max
                    (-B.Half, Float'Min (B.Half, (QX - B.C.X) * B.D.X + (QZ - B.C.Z) * B.D.Z));
                  NX : Float := QX - (B.C.X + T * B.D.X);
                  NZ : Float := QZ - (B.C.Z + T * B.D.Z);
                  D  : constant Float := Sqrt (NX * NX + NZ * NZ);
               begin
                  if D < 1.0 then
                     if D < 0.001 then
                        NX := B.D.Z;
                        NZ := -B.D.X;
                     else
                        NX := NX / D;
                        NZ := NZ / D;
                     end if;
                     Player.X := Player.X + NX * (1.0 - D);
                     Player.Z := Player.Z + NZ * (1.0 - D);
                     --  running into it stops you; scraping along slows you
                     if (F.X * NX + F.Z * NZ) * Player.Speed < 0.0 then
                        Player.Speed := Player.Speed
                          * (1.0 - 0.8 * abs (F.X * NX + F.Z * NZ));
                     end if;
                     Player.Bumped := True;
                     Player.Hit_NX := NX;
                     Player.Hit_NZ := NZ;
                  end if;
               end;
            end loop;
         end if;
      end loop;
      if Before - abs Player.Speed > 0.0 then
         Impact (Before - abs Player.Speed);
      end if;
   end Hit_Barriers;

   ---------------------------------------------------------------------------
   --  The racers
   ---------------------------------------------------------------------------

   Opponents : constant := 5;
   type Racer is record
      S       : Float := 0.0;     --  distance raced (counting the laps)
      Speed   : Float := 0.0;
      Lane    : Float := 0.0;     --  to the right of the middle of the road
      Want    : Float := 0.0;
      Skill   : Float := 1.0;
      Colour  : Vec3 := (0.8, 0.1, 0.1);
      Model   : Car.Model_Kind := Car.Modern;
      Done    : Boolean := False;
      Time    : Float := 0.0;
      Place   : Natural := 0;     --  in the finishing order
      Damage  : Float := 0.0;
      Retired : Boolean := False; --  wrecked, parked at the side
      Cool    : Float := 0.0;     --  after a knock from you
      Name    : Unbounded_String;
   end record;
   Racers : array (1 .. Opponents) of Racer;

   Names : constant array (1 .. 8) of Unbounded_String :=
     (To_Unbounded_String ("Amélie"), To_Unbounded_String ("Jules"),
      To_Unbounded_String ("Louise"), To_Unbounded_String ("Hugo"),
      To_Unbounded_String ("Chloé"), To_Unbounded_String ("Léon"),
      To_Unbounded_String ("Inès"), To_Unbounded_String ("Gaston"));
   Colours : constant array (1 .. 6) of Vec3 :=
     ((0.1, 0.25, 0.75), (0.95, 0.75, 0.1), (0.1, 0.55, 0.25), (0.9, 0.9, 0.9),
      (0.15, 0.15, 0.15), (0.85, 0.35, 0.05));

   Off_Time, Wrong_Time : Float := 0.0;   --  how long off the course / the wrong way
   Warn     : Unbounded_String;
   Warn_Beep : Float := 0.0;
   Current  : Phase_Kind := Idle;
   Clock    : Float := 0.0;     --  since the start (negative: the countdown)
   Me_S     : Float := 0.0;     --  the player's distance raced
   Me_Done  : Boolean := False;
   Me_Time  : Float := 0.0;
   Lap_Start, Best_Lap : Float := 0.0;
   Me_Lap   : Natural := 0;
   Last_Beep : Integer := 99;
   Done_Count : Natural := 0;
   Me_Place : Natural := 0;
   After    : Float := 0.0;     --  seconds since the player finished
   Cheer    : Float := 0.0;

   function Phase return Phase_Kind is (Current);

   --  On the course's road, widened by Margin
   function Inside (X, Z, Margin : Float) return Boolean is
      CX : constant Integer := Integer (Float'Floor (X / Cell));
      CZ : constant Integer := Integer (Float'Floor (Z / Cell));
   begin
      if Current = Idle then
         return False;
      end if;
      for DX in -1 .. 1 loop
         for DZ in -1 .. 1 loop
            declare
               C : constant Cell_Maps.Cursor := Cells.Find (Cell_Key (CX + DX, CZ + DZ));
            begin
               if Cell_Maps.Has_Element (C) then
                  for I of Cells.Constant_Reference (C) loop
                     declare
                        A  : Vec3 renames Course (I);
                        B  : Vec3 renames Course (I + 1);
                        EX : constant Float := B.X - A.X;
                        EZ : constant Float := B.Z - A.Z;
                        T  : constant Float := Float'Max (0.0, Float'Min (1.0,
                          ((X - A.X) * EX + (Z - A.Z) * EZ) / Float'Max (0.0001, EX * EX + EZ * EZ)));
                        H  : constant Float := Widths (I) / 2.0 + Margin;
                     begin
                        if (A.X + T * EX - X) ** 2 + (A.Z + T * EZ - Z) ** 2 < H * H then
                           return True;
                        end if;
                     end;
                  end loop;
               end if;
            end;
         end loop;
      end loop;
      return False;
   end Inside;

   function On_Course (X, Z : Float) return Boolean is (Inside (X, Z, 0.4));
   --  (on the road, or within 0.4 m of it)
   function Active return Boolean is (Current /= Idle);
   function Frozen return Boolean is (Current = Countdown);

   procedure Free_Mesh is
   begin
      if Mesh_Built then
         Meshes.Free (Course_Mesh);
         Mesh_Built := False;
      end if;
   end Free_Mesh;

   --  Gates: two posts and a banner, the start chequered
   procedure Build_Mesh is
      Mat_Post : constant := 26.0;   --  lamp-post iron
      Mat_Red  : constant := 19.0;
      Mat_White : constant := 39.0;
      Mat_Black : constant := 17.0;
   begin
      Free_Mesh;
      Meshes.Start;
      for G in Gates.First_Index .. Gates.Last_Index loop
         declare
            P, T : Vec3;
            R : Vec3;
            Half : constant Float := Room (Gates (G)) + 2.6;
         begin
            At_S (Gates (G), P, T);
            R := Right_Of (T);
            for Side of Side_List loop
               declare
                  Q : constant Vec3 := P + (Side * Half) * R;
                  Y : constant Float := Terrain.Height (Q.X, Q.Z);
               begin
                  Meshes.Box (Q.X - 0.15, Q.X + 0.15, Y, Y + 5.2, Q.Z - 0.15, Q.Z + 0.15, Mat_Post);
               end;
            end loop;
            --  the banner, in squares
            for K in 0 .. 11 loop
               declare
                  A : constant Vec3 := P + (-Half + 2.0 * Half * Float (K) / 12.0) * R;
                  B : constant Vec3 := P + (-Half + 2.0 * Half * Float (K + 1) / 12.0) * R;
                  Y : constant Float := P.Y + 4.3;
               begin
                  for Row in 0 .. 1 loop
                     declare
                        Mat : constant Float :=
                          (if G = Gates.First_Index
                           then (if (K + Row) mod 2 = 0 then Mat_White else Mat_Black)
                           else (if Row = 0 then Mat_Red else Mat_White));
                        Y0 : constant Float := Y + 0.45 * Float (Row);
                     begin
                        Meshes.Quad (A + Vec3'(0.0, Y0 - P.Y, 0.0), B + Vec3'(0.0, Y0 - P.Y, 0.0),
                                     B + Vec3'(0.0, Y0 + 0.45 - P.Y, 0.0), A + Vec3'(0.0, Y0 + 0.45 - P.Y, 0.0),
                                     Mat);
                     end;
                  end loop;
               end;
            end loop;
         end;
      end loop;
      --  the barriers: iron posts and rails, red and white boards
      for B of Barriers loop
         declare
            N : constant Positive := Positive'Max (1, Integer (Float'Ceiling (2.0 * B.Half / 2.2)));
         begin
            for K in 0 .. N - 1 loop
               declare
                  A  : constant Vec3 := B.C + (-B.Half + 2.0 * B.Half * Float (K) / Float (N)) * B.D;
                  E  : constant Vec3 := B.C + (-B.Half + 2.0 * B.Half * Float (K + 1) / Float (N)) * B.D;
                  YA : constant Float := Terrain.Height (A.X, A.Z);
                  YE : constant Float := Terrain.Height (E.X, E.Z);
                  procedure Plank (Y0, Y1 : Float; Mat : Float) is
                     A0 : constant Vec3 := (A.X, YA + Y0, A.Z);
                     A1 : constant Vec3 := (A.X, YA + Y1, A.Z);
                     E0 : constant Vec3 := (E.X, YE + Y0, E.Z);
                     E1 : constant Vec3 := (E.X, YE + Y1, E.Z);
                  begin
                     Meshes.Quad (A0, E0, E1, A1, Mat);
                     Meshes.Quad (E0, A0, A1, E1, Mat);
                  end Plank;
               begin
                  Meshes.Box (A.X - 0.05, A.X + 0.05, YA, YA + 1.1, A.Z - 0.05, A.Z + 0.05, Mat_Post);
                  Plank (0.15, 0.2, Mat_Post);
                  Plank (1.02, 1.08, Mat_Post);
                  Plank (0.45, 0.85, (if K mod 2 = 0 then Meshes.Mat_Paint else Mat_White));
                  if K = N - 1 then
                     Meshes.Box (E.X - 0.05, E.X + 0.05, YE, YE + 1.1, E.Z - 0.05, E.Z + 0.05, Mat_Post);
                  end if;
               end;
            end loop;
         end;
      end loop;
      --  the turn signs
      for G of Signs loop
         declare
            R    : constant Vec3 := Right_Of (G.Ahead);   --  to the driver's right
            Base : constant Float := G.C.Y + 1.0;
            Wide : constant Float := 2.4;
            High : constant Float := 1.3;
            function At_UV (U, V : Float; Out_D : Float := 0.0) return Vec3 is
              (Vec3'(G.C.X, Base + V, G.C.Z) + U * R - Out_D * G.Ahead);
         begin
            for Side of Side_List loop
               declare
                  Q : constant Vec3 := G.C + (Side * (Wide - 0.3)) * R;
               begin
                  Meshes.Box (Q.X - 0.06, Q.X + 0.06, G.C.Y, Base + High, Q.Z - 0.06, Q.Z + 0.06, Mat_Post);
               end;
            end loop;
            --  the board, white in front, dark behind
            Meshes.Quad (At_UV (-Wide, 0.0), At_UV (Wide, 0.0), At_UV (Wide, High), At_UV (-Wide, High),
                         Mat_White);
            Meshes.Quad (At_UV (Wide, 0.0, -0.03), At_UV (-Wide, 0.0, -0.03),
                         At_UV (-Wide, High, -0.03), At_UV (Wide, High, -0.03), Mat_Black);
            --  three chevrons pointing the way
            for K in -1 .. 1 loop
               declare
                  D  : constant Float := G.Turn;
                  U0 : constant Float := 1.35 * Float (K);
                  M  : constant Float := High / 2.0;
                  procedure Arm (Up : Float) is
                  begin
                     Meshes.Quad (At_UV (U0 - D * 0.35, M + Up * 0.5, 0.05),
                                  At_UV (U0 - D * 0.35 + D * 0.3, M + Up * 0.5, 0.05),
                                  At_UV (U0 + D * 0.35 + D * 0.3, M, 0.05),
                                  At_UV (U0 + D * 0.35, M, 0.05),
                                  Meshes.Mat_Paint);
                     Meshes.Quad (At_UV (U0 + D * 0.35, M, 0.05),
                                  At_UV (U0 + D * 0.35 + D * 0.3, M, 0.05),
                                  At_UV (U0 - D * 0.35 + D * 0.3, M + Up * 0.5, 0.05),
                                  At_UV (U0 - D * 0.35, M + Up * 0.5, 0.05),
                                  Meshes.Mat_Paint);
                  end Arm;
               begin
                  Arm (1.0);
                  Arm (-1.0);
               end;
            end loop;
         end;
      end loop;
      Meshes.Finish (Course_Mesh);
      Mesh_Built := True;
   end Build_Mesh;

   procedure On_Grid (Player : in out Car.State) is
      P, T : Vec3;
      Order : array (Names'Range) of Positive;
   begin
      --  five different names
      for I in Order'Range loop
         Order (I) := I;
      end loop;
      for I in reverse 2 .. Order'Last loop
         declare
            J : constant Positive := 1 + Natural (Rnd * Float (I - 1));
            Tmp : constant Positive := Order (I);
         begin
            Order (I) := Order (J);
            Order (J) := Tmp;
         end;
      end loop;
      --  everyone behind the start line, two by two; you at the back
      for I in Racers'Range loop
         declare
            Row  : constant Natural := (I - 1) / 2;
            Side : constant Float := Float'Min (2.0, Room (-8.0 - 9.0 * Float (Row)))
              * (if I mod 2 = 1 then -1.0 else 1.0);
         begin
            Racers (I) := (S => -8.0 - 9.0 * Float (Row),
                           Speed => 0.0,
                           Lane => Side,
                           Want => Side,
                           Skill => 0.86 + 0.13 * Rnd,
                           Colour => Colours (1 + (I mod 6)),
                           Model => (if I = 3 then Car.DS elsif I = 5 then Car.Deux_Chevaux
                                     else Car.Modern),
                           Done => False, Time => 0.0, Place => 0,
                           Damage => 0.0, Retired => False, Cool => 0.0,
                           Name => Names (Order (I)));
            if Racers (I).Model = Car.Deux_Chevaux then
               Racers (I).Skill := Racers (I).Skill * 0.85;   --  brave but slow
            end if;
         end;
      end loop;
      Me_S := -8.0 - 9.0 * Float ((Opponents) / 2);
      At_S (Me_S, P, T);
      P := P + Float'Min (2.0, Room (Me_S)) * Right_Of (T);
      Player := (X => P.X, Z => P.Z, Heading => Arctan (T.X, -T.Z), others => <>);
      Current := Countdown;
      Clock := -3.0;
      Me_Done := False;
      Me_Time := 0.0;
      Me_Lap := 0;
      Lap_Start := 0.0;
      Best_Lap := 0.0;
      Last_Beep := 99;
      Done_Count := 0;
      Me_Place := 0;
      After := 0.0;
      Off_Time := 0.0;
      Wrong_Time := 0.0;
      Me_Damage := 0.0;
      Me_Wrecked := False;
      Pending := 0.0;
      Pending_Time := 0.0;
      Critical_Time := 0.0;
      Misfire_Time := 0.0;
      Quiet_Time := 0.0;
      Pull_Side := (if Rnd < 0.5 then -1.0 else 1.0);
      --  PARIS_DAMAGE=0.5: start dented (testing)
      if Ada.Environment_Variables.Exists ("PARIS_DAMAGE") then
         Me_Damage := Float'Value (Ada.Environment_Variables.Value ("PARIS_DAMAGE"));
      end if;
      Warn := Null_Unbounded_String;
      Need_Mesh := True;
   end On_Grid;

   procedure Start (Track : Positive; Player : in out Car.State; Ok : out Boolean) is
   begin
      if not Seeded then
         Ada.Numerics.Float_Random.Reset (Gen);
         Seeded := True;
      end if;
      if Track > Track_Count then
         Ok := False;
         return;
      end if;
      Build_Course (Tracks (Track).Points, Ok);
      if Ok then
         Course_Name := Tracks (Track).Name;
         On_Grid (Player);
      end if;
   end Start;

   procedure Start_Random (Near_X, Near_Z : Float; Player : in out Car.State; Ok : out Boolean) is
      V : Point_Vectors.Vector;
   begin
      if not Seeded then
         Ada.Numerics.Float_Random.Reset (Gen);
         Seeded := True;
      end if;
      for Attempt in 1 .. 6 loop
         V.Clear;
         declare
            N  : constant Positive := 4 + Natural (Rnd * 2.0);
            A0 : constant Float := 2.0 * Pi * Rnd;
         begin
            for K in 0 .. N - 1 loop
               declare
                  A : constant Float := A0 + 2.0 * Pi * (Float (K) + 0.3 * Rnd) / Float (N);
                  R : constant Float := 300.0 + 350.0 * Rnd;
                  Found : Boolean;
                  RX, RZ, RH : Float;
                  Lat, Lon : Long_Float;
               begin
                  Road_Network.Nearest_Road (Near_X + R * Cos (A), Near_Z + R * Sin (A),
                                             Found, RX, RZ, RH);
                  if Found then
                     Geo.To_Lat_Lon (Long_Float (RX), Long_Float (RZ), Lat, Lon);
                     V.Append ((Lat, Lon));
                  end if;
               end;
            end loop;
         end;
         Build_Course (V, Ok);
         if Ok and then Total < 6000.0 then
            Course_Name := To_Unbounded_String ("Random");
            On_Grid (Player);
            return;
         end if;
      end loop;
      Ok := False;
   end Start_Random;

   procedure Stop is
   begin
      if Current /= Idle then
         Ada.Text_IO.Put_Line ("race: " & To_String (Course_Name) & Integer'Image (Integer (Total)) & " m,"
                               & Natural'Image (Natural (Gates.Length)) & " gates,"
                               & Natural'Image (Natural (Barriers.Length)) & " barriers, you"
                               & Integer'Image (Integer (Me_S)) & " m, the others"
                               & Integer'Image (Integer (Racers (1).S)) & Integer'Image (Integer (Racers (2).S))
                               & Integer'Image (Integer (Racers (3).S)) & Integer'Image (Integer (Racers (4).S))
                               & Integer'Image (Integer (Racers (5).S)));
      end if;
      Current := Idle;
      Need_Mesh := False;   --  the gates go at the next Draw
   end Stop;

   ---------------------------------------------------------------------------
   --  Driving the opponents
   ---------------------------------------------------------------------------

   --  How fast one can take the road ahead: the sharpest bend in the next
   --  stretch sets the speed
   function Corner_Speed (S : Float) return Float is
      Best : Float := 40.0;
      P0, T0 : Vec3;
   begin
      At_S (S, P0, T0);
      for K in 1 .. 8 loop
         declare
            D : constant Float := 10.0 * Float (K);
            P1, T1 : Vec3;
            Turn : Float;
         begin
            At_S (S + D, P1, T1);
            Turn := Arccos (Float'Max (-1.0, Float'Min (1.0, Dot (T0, T1))));
            if Turn > 0.05 then
               --  the radius of the turn, and the speed it allows (plus
               --  what can be braked away before it)
               declare
                  Radius : constant Float := D / Turn;
                  V      : constant Float := Sqrt (7.5 * Radius);
               begin
                  Best := Float'Min (Best, Sqrt (V * V + 2.0 * 8.0 * Float'Max (0.0, D - 15.0)));
               end;
            end if;
         end;
      end loop;
      return Best;
   end Corner_Speed;

   function Position_Of (R : Racer) return Vec3 is
      P, T : Vec3;
   begin
      At_S (R.S, P, T);
      return P + R.Lane * Right_Of (T);
   end Position_Of;

   function Heading_Of (R : Racer) return Float is
      P, T : Vec3;
   begin
      At_S (R.S, P, T);
      return Arctan (T.X, -T.Z);
   end Heading_Of;

   --  The player's progress along the loop: the nearest point a little
   --  around where they were (so a short cut does not count)
   procedure Track_Player (Player : Car.State) is
      Best_S : Float := Me_S;
      Best_D : Float := Float'Last;
      S : Float := Me_S - 40.0;
   begin
      while S <= Me_S + 150.0 loop
         declare
            P, T : Vec3;
            D : Float;
         begin
            At_S (S, P, T);
            D := (P.X - Player.X) ** 2 + (P.Z - Player.Z) ** 2;
            if D < Best_D then
               Best_D := D;
               Best_S := S;
            end if;
         end;
         S := S + 4.0;
      end loop;
      --  and closer, around the best
      declare
         Around : constant Float := Best_S;
      begin
         for K in -16 .. 16 loop
            declare
               P, T : Vec3;
               D : Float;
            begin
               At_S (Around + 0.25 * Float (K), P, T);
               D := (P.X - Player.X) ** 2 + (P.Z - Player.Z) ** 2;
               if D < Best_D then
                  Best_D := D;
                  Best_S := Around + 0.25 * Float (K);
               end if;
            end;
         end loop;
      end;
      if Best_D < 30.0 ** 2 then
         Me_S := Float'Max (Me_S - 40.0, Best_S);
      end if;
   end Track_Player;

   Smoke_Time : Float := 0.0;
   From_Done  : Boolean := False;   --  PARIS_RACE_FROM, once

   --  A puff from under the bonnet: white, grey, black as it gets worse
   procedure Smoke_From (X, Z, Y, Heading, Dmg : Float; Dead : Boolean) is
      F : constant Vec3 := (Sin (Heading), 0.0, -Cos (Heading));
   begin
      Tyre_Effects.Add_Puff
        (Where    => Vec3'(X, Y + 0.95, Z) + 1.5 * F + Vec3'(0.3 * (Rnd - 0.5), 0.0, 0.3 * (Rnd - 0.5)),
         Velocity => (0.4 * (Rnd - 0.5), 1.0 + 0.8 * Dmg, 0.4 * (Rnd - 0.5)),
         Colour   => (if Dead or else Dmg >= 1.0 then 5 elsif Dmg >= 0.6 then 4 else 0),
         Size     => 0.5 + 0.7 * Dmg,
         Life     => 2.0 + 1.5 * Dmg);
   end Smoke_From;

   procedure Wreck is
   begin
      Me_Wrecked := True;
      Me_Damage := 1.0;
      Me_Done := True;
      Me_Time := Clock;
      Me_Place := 0;
      Current := Finished;
      After := 0.0;
      Warn := Null_Unbounded_String;
      Sound.Effect (Sound.Thud, 1.0, 0.0);
   end Wreck;

   procedure Wear (Dt : Float; Player : Car.State) is
   begin
      --  a knock is over: what did it do?
      if Pending_Time > 0.0 then
         Pending_Time := Pending_Time - Dt;
         if Pending_Time <= 0.0 then
            if Current = Racing and then not Me_Done then
               declare
                  Was : constant Float := Me_Damage;
               begin
                  Me_Damage := Float'Min (1.0, Me_Damage + Harm (Pending));
                  if Harm (Pending) > 0.0 then
                     Quiet_Time := 0.0;
                  end if;
                  if Me_Damage >= 1.0 then
                     Wreck;
                  elsif Was < 0.6 and then Me_Damage >= 0.6 then
                     Critical_Time := 4.0;
                  end if;
               end;
            end if;
            Pending := 0.0;
         end if;
      end if;
      Critical_Time := Float'Max (0.0, Critical_Time - Dt);
      --  a few seconds without a knock, and driving fast mends the car
      --  (the faster, the quicker); a wreck stays a wreck
      Quiet_Time := Quiet_Time + Dt;
      if Current = Racing and then not Me_Wrecked and then Quiet_Time > 3.0
        and then abs Player.Speed > 14.0
      then
         Me_Damage := Float'Max (0.0, Me_Damage - Dt * 0.01 * Float'Min (1.5, abs Player.Speed / 22.0));
      end if;
      --  the engine coughs now and then when badly hurt
      if Misfire_Time > 0.0 then
         Misfire_Time := Misfire_Time - Dt;
      elsif Me_Damage >= 0.6 and then not Me_Wrecked
        and then Rnd < Dt * 3.0 * (Me_Damage - 0.45)
      then
         Misfire_Time := 0.08 + 0.15 * Rnd;
      end if;
      --  smoke
      Smoke_Time := Smoke_Time + Dt;
      if Smoke_Time >= 0.09 then
         Smoke_Time := 0.0;
         if Me_Damage >= 0.3 then
            Smoke_From (Player.X, Player.Z, Player.Ground, Player.Heading, Me_Damage, Me_Wrecked);
         end if;
         for R of Racers loop
            if R.Damage >= 0.3 then
               declare
                  P : constant Vec3 := Position_Of (R);
               begin
                  Smoke_From (P.X, P.Z, Terrain.Height (P.X, P.Z), Heading_Of (R), R.Damage, R.Retired);
               end;
            end if;
         end loop;
      end if;
   end Wear;

   function Power return Float is
     (if Current = Idle then 1.0
      elsif Me_Wrecked then 0.0
      elsif Misfire_Time > 0.0 then 0.05
      else 1.0 - 0.45 * Float'Max (0.0, Me_Damage - 0.3) / 0.7);

   function Steer_Pull return Float is
     (if Current = Idle then 0.0
      else Pull_Side * 0.06 * Float'Max (0.0, Me_Damage - 0.3) / 0.7);

   function Shake return Float is
     (if Current = Idle or else Me_Wrecked or else Me_Damage < 0.6 then 0.0
      else 0.25 * (Me_Damage - 0.5));

   function Misfiring return Boolean is (Current /= Idle and then Misfire_Time > 0.0);

   function Place_Of_Player return Positive is
      Ahead : Natural := 0;
   begin
      for R of Racers loop
         if (R.Done and then not Me_Done)
           or else (not Me_Done and then not R.Retired and then R.S > Me_S)
         then
            Ahead := Ahead + 1;
         end if;
      end loop;
      return Ahead + 1;
   end Place_Of_Player;

   procedure Update (Dt : Float; Player : in out Car.State) is
   begin
      if Current = Idle then
         return;
      end if;
      Clock := Clock + Dt;

      --  the countdown: a beep each second, a higher one for GO
      if Current = Countdown then
         declare
            Second : constant Integer := Integer (Float'Ceiling (-Clock));
         begin
            if Second /= Last_Beep and then Second in 0 .. 3 then
               Last_Beep := Second;
               Sound.Effect ((if Second = 0 then Sound.Go_Beep else Sound.Beep), 1.0, 0.0);
            end if;
         end;
         if Clock >= 0.0 then
            Current := Racing;
            Lap_Start := 0.0;
         end if;
         return;
      end if;

      --  the opponents
      for I in Racers'Range loop
         declare
            R : Racer renames Racers (I);
            Rm : constant Float := Room (R.S);
            Target : Float;
            Me     : constant Vec3 := Position_Of (R);
         begin
            if R.Done then
               --  after the line: slow down, pull over to the right and park
               --  behind the ones who came in before
               declare
                  Line   : constant Float := Float (Laps) * Total;
                  Park_S : constant Float := Line + 40.0 + 9.0 * Float (R.Place - 1);
                  To_Go  : constant Float := Park_S - R.S;
               begin
                  if R.S > Line + 10.0 then
                     R.Want := Float'Max (0.0, Rm - 0.3);
                  end if;
                  Target := (if To_Go <= 0.0 then 0.0
                             else Float'Min (16.0, Sqrt (2.0 * 3.0 * To_Go)));
                  if R.Speed > Target then
                     R.Speed := Float'Max (Target, R.Speed - 6.0 * Dt);
                  else
                     R.Speed := Float'Min (Target, R.Speed + 3.0 * Dt);
                  end if;
                  if To_Go <= 0.0 then
                     R.Speed := 0.0;
                  end if;
               end;
            elsif R.Retired then
               --  wrecked: to the side of the road, and stop
               R.Want := Float'Max (0.0, Rm - 0.3);
               R.Speed := Float'Max (0.0, R.Speed - 6.0 * Dt);
            else
               Target := Float'Min (36.0 * R.Skill, Corner_Speed (R.S) * (0.92 + 0.08 * R.Skill))
                 * (1.0 - 0.45 * Float'Max (0.0, R.Damage - 0.3));
               --  keep the race close: a little slower far ahead of you,
               --  faster far behind
               if R.S - Me_S > 150.0 then
                  Target := Target * 0.93;
               elsif Me_S - R.S > 150.0 then
                  Target := Target * 1.07;
               end if;
               --  someone in front in the same lane: pass on the other side,
               --  or wait
               for J in Racers'Range loop
                  if J /= I then
                     declare
                        Gap : constant Float := Racers (J).S - R.S;
                     begin
                        if Gap > 0.0 and then Gap < 12.0 and then abs (Racers (J).Lane - R.Lane) < 2.2 then
                           R.Want := Float'Min (2.0, Rm) * (if Racers (J).Lane > 0.0 then -1.0 else 1.0);
                           if Gap < 6.0 then
                              Target := Float'Min (Target, Racers (J).Speed);
                           end if;
                        end if;
                     end;
                  end if;
               end loop;
               --  and you
               declare
                  P, T : Vec3;
                  Gap, Side : Float;
               begin
                  At_S (R.S, P, T);
                  Gap := (Player.X - Me.X) * T.X + (Player.Z - Me.Z) * T.Z;
                  Side := (Player.X - Me.X) * (-T.Z) + (Player.Z - Me.Z) * T.X;
                  if Gap > 0.0 and then Gap < 12.0 and then abs Side < 2.2 then
                     R.Want := (if Side > 0.0 then R.Lane - 3.0 else R.Lane + 3.0);
                     R.Want := Float'Max (-Rm, Float'Min (Rm, R.Want));
                     if Gap < 6.0 then
                        Target := Float'Min (Target, abs Player.Speed);
                     end if;
                  end if;
               end;
               if R.Speed < Target then
                  R.Speed := Float'Min (Target, R.Speed + 4.5 * R.Skill * Dt);
               else
                  R.Speed := Float'Max (Target, R.Speed - 9.0 * Dt);
               end if;
            end if;
            R.S := R.S + R.Speed * Dt;
            R.Want := Float'Max (-Rm, Float'Min (Rm, R.Want));
            if R.Lane > Rm or else R.Lane < -Rm then   --  the road narrows
               R.Lane := Float'Max (-Rm, Float'Min (Rm, R.Lane));
            end if;
            if R.Lane < R.Want then
               R.Lane := Float'Min (R.Want, R.Lane + 1.5 * Dt);
            else
               R.Lane := Float'Max (R.Want, R.Lane - 1.5 * Dt);
            end if;
            if not R.Done and then R.S >= Float (Laps) * Total then
               R.Done := True;
               R.Time := Clock;
               Done_Count := Done_Count + 1;
               R.Place := Done_Count;
            end if;
            --  bumping into the player
            declare
               Q  : constant Vec3 := Position_Of (R);
               DX : constant Float := Player.X - Q.X;
               DZ : constant Float := Player.Z - Q.Z;
               D  : constant Float := Sqrt (DX * DX + DZ * DZ);
            begin
               R.Cool := Float'Max (0.0, R.Cool - Dt);
               if D < 2.4 and then D > 0.01 then
                  --  how fast the two came together: that is the knock,
                  --  for both of you
                  declare
                     P, T : Vec3;
                     F  : constant Vec3 := Car.Forward (Player);
                     NX : constant Float := DX / D;
                     NZ : constant Float := DZ / D;
                     Closing : Float;
                  begin
                     At_S (R.S, P, T);
                     Closing := (R.Speed * T.X - Player.Speed * F.X) * NX
                       + (R.Speed * T.Z - Player.Speed * F.Z) * NZ;
                     if Closing > 2.5 and then R.Cool = 0.0 then
                        Impact (0.8 * Closing);
                        if not R.Done then
                           R.Damage := Float'Min (1.0, R.Damage + Harm (0.8 * Closing));
                           if R.Damage >= 1.0 and then not R.Retired then
                              R.Retired := True;
                              Sound.Effect (Sound.Thud, 0.8, 0.0);
                           end if;
                        end if;
                        R.Cool := 0.5;
                        Player.Speed := Player.Speed * 0.85;
                        R.Speed := R.Speed * 0.8;
                     end if;
                  end;
                  Player.X := Player.X + DX / D * (2.4 - D);
                  Player.Z := Player.Z + DZ / D * (2.4 - D);
                  Player.Bumped := True;
                  Player.Speed := Player.Speed * 0.97;
                  R.Speed := R.Speed * 0.95;
               end if;
            end;
         end;
      end loop;

      Hit_Barriers (Player);
      Wear (Dt, Player);

      --  PARIS_RACE_FROM=<m>: you start there instead (testing)
      if not From_Done and then Ada.Environment_Variables.Exists ("PARIS_RACE_FROM") then
         From_Done := True;
         declare
            P, T : Vec3;
         begin
            Me_S := Float'Value (Ada.Environment_Variables.Value ("PARIS_RACE_FROM"));
            At_S (Me_S, P, T);
            Player.X := P.X;
            Player.Z := P.Z;
            Player.Heading := Arctan (T.X, -T.Z);
         end;
      end if;

      --  PARIS_RACE_AUTO=<m/s>: you are driven round (testing)
      if Ada.Environment_Variables.Exists ("PARIS_RACE_AUTO") and then Me_Done then
         Player.Speed := 0.0;   --  stop at the line
      elsif Ada.Environment_Variables.Exists ("PARIS_RACE_AUTO") and then not Me_Done then
         declare
            P, T : Vec3;
            V : constant Float := Float'Value (Ada.Environment_Variables.Value ("PARIS_RACE_AUTO"));
         begin
            At_S (Me_S + V * Dt, P, T);
            Player.X := P.X;
            Player.Z := P.Z;
            Player.Heading := Arctan (T.X, -T.Z);
            Player.Speed := V;
         end;
      end if;

      --  you
      if not Me_Done then
         Track_Player (Player);
         --  off the course, or the wrong way round?
         declare
            D, H, NX, NZ, P_S : Float;
            P, T : Vec3;
            F    : constant Vec3 := Car.Forward (Player);
            Go   : constant Vec3 := (if Player.Speed < 0.0 then (-1.0) * F else F);
         begin
            Nearest (Player.X, Player.Z, D, H, NX, NZ);
            P_S := Float'Max (0.0, Me_S);
            At_S (P_S, P, T);
            Off_Time := (if D > H + 4.0 then Off_Time + Dt else 0.0);
            Wrong_Time := (if D <= H + 4.0 and then abs Player.Speed > 3.0
                             and then Dot (Go, T) < -0.5
                           then Wrong_Time + Dt else 0.0);
            if Off_Time > 0.7 then
               declare
                  VX : constant Float := NX - Player.X;
                  VZ : constant Float := NZ - Player.Z;
                  Fwd  : constant Float := VX * F.X + VZ * F.Z;
                  Side : constant Float := VX * (-F.Z) + VZ * F.X;
                  Where : constant String :=
                    (if Fwd > 2.0 * abs Side then "ahead of you"
                     elsif Fwd < -2.0 * abs Side then "behind you"
                     elsif Side > 0.0 then "to your right" else "to your left");
               begin
                  Warn := To_Unbounded_String ("OFF THE COURSE|The course is " & Where);
               end;
            elsif Wrong_Time > 1.0 then
               Warn := To_Unbounded_String ("WRONG WAY|Turn round");
            elsif Critical_Time > 0.0 then
               Warn := To_Unbounded_String ("DAMAGE CRITICAL|One more knock and you are out");
            else
               Warn := Null_Unbounded_String;
            end if;
            if Length (Warn) > 0 then
               Warn_Beep := Warn_Beep - Dt;
               if Warn_Beep <= 0.0 then
                  Sound.Effect (Sound.Beep, 0.6, 0.0);
                  Warn_Beep := 2.0;
               end if;
            else
               Warn_Beep := 0.0;
            end if;
         end;
         declare
            Lap : constant Natural := Natural (Float'Floor (Float'Max (0.0, Me_S) / Total));
         begin
            if Lap > Me_Lap then
               Me_Lap := Lap;
               declare
                  This : constant Float := Clock - Lap_Start;
               begin
                  if Best_Lap = 0.0 or else This < Best_Lap then
                     Best_Lap := This;
                  end if;
               end;
               Lap_Start := Clock;
               Sound.Effect (Sound.Beep, 0.8, 0.0);
            end if;
         end;
         if Me_S >= Float (Laps) * Total then
            Me_Done := True;
            Me_Time := Clock;
            Me_Place := Done_Count + 1;
            Done_Count := Done_Count + 1;
            Current := Finished;
            After := 0.0;
            Sound.Effect (Sound.Go_Beep, 1.0, 0.0);
         end if;
      else
         After := After + Dt;
      end if;

      --  the crowd near you, louder when you pass the gates
      Cheer := 0.0;
      for G of Gates loop
         declare
            P, T : Vec3;
            D : Float;
         begin
            At_S (G, P, T);
            D := Sqrt ((P.X - Player.X) ** 2 + (P.Z - Player.Z) ** 2);
            Cheer := Float'Max (Cheer, 1.0 - D / 90.0);
         end;
      end loop;
   end Update;

   function Next_Gate (X, Z : out Float) return Boolean is
      P, T : Vec3;
      Here : constant Float := Float'Max (0.0, Me_S);
      U    : constant Float := Here - Total * Float'Floor (Here / Total);
      Next : Float := Total;
   begin
      X := 0.0;
      Z := 0.0;
      if Current /= Racing or else Gates.Is_Empty then
         return False;
      end if;
      for G of Gates loop
         if G > U + 35.0 then   --  before the GPS says "arrived"
            Next := G;
            exit;
         end if;
      end loop;
      At_S (Next, P, T);
      X := P.X;
      Z := P.Z;
      return True;
   end Next_Gate;

   procedure Route_To_Gate (X, Z : Float; Route : out Road_Network.Route_Vectors.Vector) is
      GX, GZ : Float;
      Here   : constant Float := Float'Max (0.0, Me_S);
      U      : constant Float := Here - Total * Float'Floor (Here / Total);
      Next   : Float := Total;
      W0, W1 : Float;
   begin
      Route.Clear;
      if not Next_Gate (GX, GZ) or else Line.Is_Empty then
         return;
      end if;
      for G of Gates loop
         if G > U + 35.0 then
            Next := G;
            exit;
         end if;
      end loop;
      --  in the loop's own measure (it starts where the streets start)
      W0 := U + Start_Off;
      W1 := Next + Start_Off;
      Route.Append ((X, Z, Line (Line.First_Index).Way));
      for Lap in 0 .. 2 loop
         for I in Line.First_Index .. Line.Last_Index loop
            declare
               W : constant Float := Line_S (I) + Total * Float (Lap);
            begin
               if W > W0 and then W < W1 then
                  if Natural (Route.Length) = 1 then
                     Route (Route.First_Index).Way := Line (I).Way;
                  end if;
                  Route.Append (Line (I));
               end if;
            end;
         end loop;
      end loop;
      Route.Append ((GX, GZ, Route.Last_Element.Way));
   end Route_To_Gate;

   function Time_Image (T : Float) return String is
      Tenths : constant Natural := Natural (Float'Floor (Float'Max (0.0, T) * 10.0));
      M : constant Natural := Tenths / 600;
      S : constant Natural := (Tenths / 10) mod 60;
      SS : constant String := Natural'Image (100 + S);
      D : constant String := Natural'Image (Tenths mod 10);
   begin
      return Ada.Strings.Fixed.Trim (Natural'Image (M), Ada.Strings.Left) & ":"
        & SS (SS'Last - 1 .. SS'Last) & "." & D (D'Last .. D'Last);
   end Time_Image;

   --  0 .. 1 as ten blocks
   function Bar (V : Float) return String is
      Full : constant Natural := Natural (Float'Min (10.0, Float'Ceiling (V * 10.0 - 0.001)));
      R    : Unbounded_String;
   begin
      for K in 1 .. 10 loop
         Append (R, (if K <= Full then "&#x2588;" else "&#x2591;"));
      end loop;
      return To_String (R);
   end Bar;

   function Hud_Text return String is
   begin
      if Current = Idle then
         return "";
      end if;
      return "<span font_family='sans' weight='bold' foreground='white' background='#000000a0'>"
        & "  " & To_String (Course_Name) & "   LAP "
        & Ada.Strings.Fixed.Trim (Natural'Image (Natural'Min (Laps, Me_Lap + 1)), Ada.Strings.Left)
        & "/" & Ada.Strings.Fixed.Trim (Natural'Image (Laps), Ada.Strings.Left)
        & "   POS " & Ada.Strings.Fixed.Trim
          ((if Me_Wrecked then "out"
            else Natural'Image (if Me_Done then Me_Place else Place_Of_Player)), Ada.Strings.Left)
        & (if Me_Wrecked then ""
           else "/" & Ada.Strings.Fixed.Trim (Natural'Image (Opponents + 1), Ada.Strings.Left))
        & "   " & Time_Image (if Me_Done then Me_Time else Clock)
        & (if Best_Lap > 0.0 then "   best lap " & Time_Image (Best_Lap) else "")
        & "   DAMAGE <span foreground='"
        & (if Me_Damage < 0.3 then "#7ddc7a" elsif Me_Damage < 0.6 then "#ffb347" else "#ff5040")
        & "'>" & Bar (Me_Damage) & "</span>  </span>";
   end Hud_Text;

   --  Characters, not bytes (for the columns)
   function Letters (S : String) return Natural is
      N : Natural := 0;
   begin
      for C of S loop
         if Character'Pos (C) not in 16#80# .. 16#BF# then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Letters;

   function Results_Text return String is
      type Entry_Rec is record
         Name : Unbounded_String;
         Time : Float;
         Dist : Float;
         Done : Boolean;
         You  : Boolean;
         Retired : Boolean;
      end record;
      function Rank (E : Entry_Rec) return Natural is
        (if E.Done then 0 elsif E.Retired then 2 else 1);
      List : array (1 .. Opponents + 1) of Entry_Rec;
      Text : Unbounded_String;
      LF   : constant String := (1 => ASCII.LF);
   begin
      if Current /= Finished then
         return "";
      end if;
      for I in Racers'Range loop
         List (I) := (Racers (I).Name, Racers (I).Time, Racers (I).S, Racers (I).Done, False,
                      Racers (I).Retired);
      end loop;
      List (List'Last) := (To_Unbounded_String ("You"), Me_Time, Me_S, not Me_Wrecked, True,
                           Me_Wrecked);
      --  sort: finished by time, then still racing by distance, then the
      --  wrecks
      for I in List'Range loop
         for J in I + 1 .. List'Last loop
            declare
               A : Entry_Rec renames List (I);
               B : Entry_Rec renames List (J);
               B_First : constant Boolean :=
                 Rank (B) < Rank (A)
                 or else (Rank (A) = Rank (B)
                          and then (if A.Done then B.Time < A.Time else B.Dist > A.Dist));
               Tmp : constant Entry_Rec := A;
            begin
               if B_First then
                  List (I) := B;
                  List (J) := Tmp;
               end if;
            end;
         end loop;
      end loop;
      Append (Text, "<span font_family='monospace'><b><span foreground='#ffd27a'>"
              & To_String (Course_Name) & ": results</span></b>" & LF & LF);
      for I in List'Range loop
         declare
            Line : constant String :=
              Natural'Image (I) & ".  " & To_String (List (I).Name)
              & (1 .. Natural'Max (1, 10 - Letters (To_String (List (I).Name))) => ' ')
              & (if List (I).Done then Time_Image (List (I).Time)
                 elsif List (I).Retired then "out (wrecked)" else "racing");
         begin
            if List (I).You then
               Append (Text, "<span background='#3a6fd8'>" & Line & "  </span>" & LF);
            else
               Append (Text, Line & LF);
            end if;
         end;
      end loop;
      if Best_Lap > 0.0 then
         Append (Text, LF & "  your best lap  " & Time_Image (Best_Lap) & LF);
      end if;
      Append (Text, LF & "<span foreground='#aab'>  Esc: close    F2: race again or back to the city</span></span>");
      return To_String (Text);
   end Results_Text;

   function Crowd return Float is (if Current = Idle then 0.0 else Cheer);

   function Ordinal (N : Natural) return String is
      Num : constant String := Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Left);
   begin
      return Num & (case N is when 1 => "st", when 2 => "nd", when 3 => "rd", when others => "th");
   end Ordinal;

   function Warning return String is
     (if Current = Racing then To_String (Warn) else "");

   function Banner return String is
   begin
      if Current = Countdown then
         return Ada.Strings.Fixed.Trim (Integer'Image (Integer (Float'Ceiling (-Clock))), Ada.Strings.Left);
      elsif Current = Racing and then Clock < 1.0 then
         return "GO!";
      elsif Current = Finished and then After < 3.0 then
         return (if Me_Wrecked then "WRECKED" else "FINISHED  " & Ordinal (Me_Place));
      end if;
      return "";
   end Banner;

   function Seconds_Since_Finish return Float is
     (if Current = Finished then After else 0.0);

   procedure Set_Laps (N : Natural) is
   begin
      Laps_Wanted := N;
   end Set_Laps;

   function Laps_Setting return Natural is (Laps_Wanted);

   procedure Restart (Player : in out Car.State; Ok : out Boolean) is
   begin
      Ok := Current /= Idle and then Total > 0.0;
      if Ok then
         Laps := (if Laps_Wanted > 0 then Laps_Wanted
                  elsif Total < 2500.0 then 3 elsif Total < 6000.0 then 2 else 1);
         On_Grid (Player);
      end if;
   end Restart;

   ---------------------------------------------------------------------------

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint; Cam : Vec3) is
      Skins : constant array (0 .. 3) of Vec3 :=
        ((0.86, 0.68, 0.56), (0.76, 0.57, 0.44), (0.58, 0.40, 0.29), (0.40, 0.27, 0.19));
      Shirts : constant array (0 .. 5) of Vec3 :=
        ((0.8, 0.15, 0.15), (0.15, 0.3, 0.75), (0.9, 0.85, 0.75), (0.2, 0.5, 0.25),
         (0.9, 0.7, 0.15), (0.25, 0.25, 0.28));
   begin
      if Current = Idle then
         Free_Mesh;
         return;
      end if;
      if Need_Mesh then
         Build_Mesh;
         Need_Mesh := False;
      end if;
      if Mesh_Built then
         Shaders.Set (Paint, Vec3'(0.85, 0.08, 0.08));   --  the barrier boards
         Shaders.Set (Model, Identity);
         Meshes.Draw (Course_Mesh);
      end if;
      --  the opponents
      for R of Racers loop
         Shaders.Set (Paint, (1.0 - 0.35 * R.Damage) * R.Colour);   --  dented, dirty
         declare
            P : constant Vec3 := Position_Of (R);
         begin
            Shaders.Set (Model, Car.Model_Matrix (Car.On_Ground (P.X, P.Z, Heading_Of (R))));
            Car.Draw_Model (R.Model);
         end;
      end loop;
      --  spectators at the gates (only those near you), waving
      Figures.Set_Locations ((Model, Paint, Skin, Legs));
      for G in Gates.First_Index .. Gates.Last_Index loop
         declare
            P, T : Vec3;
            R : Vec3;
            Many : constant Natural := (if G = Gates.First_Index then 9 else 4);
         begin
            At_S (Gates (G), P, T);
            if (P.X - Cam.X) ** 2 + (P.Z - Cam.Z) ** 2 < 220.0 ** 2 then
               R := Right_Of (T);
               for Side of Side_List loop
                  for K in 0 .. Many - 1 loop
                     declare
                        Along : constant Float := -6.0 + 12.0 * Float (K) / Float (Many);
                        Out_D : constant Float := 8.6 + 0.8 * Float (K mod 2);
                        Q : constant Vec3 := P + Along * T + (Side * Out_D) * R;
                        H : constant Natural := (G * 7 + K * 3 + (if Side > 0.0 then 1 else 0)) mod 6;
                        Face : constant Float := Arctan (-Side * R.X, Side * R.Z);
                     begin
                        Figures.Person
                          (Translation ((Q.X, Terrain.Height (Q.X, Q.Z), Q.Z)) * Rotation_Y (-Face),
                           Shirts (H), Skins ((K + G) mod 4), (0.15, 0.15, 0.2),
                           Arm_Up => (if (K + G) mod 3 = 0
                                      then -2.4 + 0.5 * Sin (Clock * 6.0 + Float (K))
                                      else 0.0));
                     end;
                  end loop;
               end loop;
            end if;
         end;
      end loop;
   end Draw;

end Race;
