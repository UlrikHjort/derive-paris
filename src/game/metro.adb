--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Containers.Vectors;
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Glib.Convert;

with Geo;
with Math3D;
with Meshes;
with Road_Network;
with Shaders;
with Sound;
with Street_Life;
with Terrain;

package body Metro is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;
   use Ada.Strings.Unbounded;

   Pi : constant := Ada.Numerics.Pi;

   type Float_List is array (Positive range <>) of Float;

   Mat_Tile   : constant := 88.0;   --  the white bevelled tiles
   Mat_Floor  : constant := 2.0;
   Mat_Edge   : constant := 39.0;
   Mat_Dark   : constant := 17.0;
   Mat_Iron   : constant := 26.0;
   Mat_Lamp   : constant := 50.0;   --  uExtraColor
   Mat_Paint  : constant := 15.0;   --  uCarColor
   Mat_Glass  : constant := 16.0;
   Mat_Seat   : constant := 54.0;

   type Station is record
      Name, Lines : Unbounded_String;
      X, Z : Float := 0.0;
   end record;
   package Station_Vectors is new Ada.Containers.Vectors (Positive, Station);
   Stations : Station_Vectors.Vector;
   Loaded : Boolean := False;

   type Phase_Kind is (Platform, Riding, Arrived);
   Phase  : Phase_Kind := Platform;
   Here   : Natural := 0;         --  the station you went down at
   Choice : Positive := 1;
   Going  : Natural := 0;
   Ride_T, Ride_Len : Float := 0.0;
   Origin : Vec3 := (0.0, 0.0, 0.0);
   Hall, Lamps : Meshes.Mesh;
   Built, Need_Build : Boolean := False;

   Plat_Len : constant := 76.0;
   Car_Z    : constant := -40.0;   --  the train's car, out of sight of the platform
   Lamp_Gap : constant := 9.0;

   function G (X, Y, Z : Float) return Vec3 is (Origin + Vec3'(X, Y, Z));

   procedure Load is
      F : Ada.Text_IO.File_Type;
   begin
      Loaded := True;
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, "data/metro_stations.txt");
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            L  : constant String := Ada.Text_IO.Get_Line (F);
            S1 : constant Natural := Ada.Strings.Fixed.Index (L, " ");
            S2 : constant Natural := (if S1 > 0 then Ada.Strings.Fixed.Index (L, " ", S1 + 1) else 0);
            S3 : constant Natural := (if S2 > 0 then Ada.Strings.Fixed.Index (L, " ", S2 + 1) else 0);
            X, Z : Long_Float;
         begin
            if L'Length > 0 and then L (L'First) /= '#' and then S3 > 0 then
               Geo.To_Local (Long_Float'Value (L (L'First .. S1 - 1)), Long_Float'Value (L (S1 + 1 .. S2 - 1)), X, Z);
               Stations.Append ((Name => To_Unbounded_String (L (S3 + 1 .. L'Last)),
                                 Lines => To_Unbounded_String (L (S2 + 1 .. S3 - 1)),
                                 X => Float (X), Z => Float (Z)));
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

   function Nearest_Station (X, Z : Float) return Natural is
      Best : Float := Float'Last;
      N : Natural := 0;
   begin
      for I in Stations.First_Index .. Stations.Last_Index loop
         declare
            D : constant Float := (Stations (I).X - X) ** 2 + (Stations (I).Z - Z) ** 2;
         begin
            if D < Best then
               Best := D;
               N := I;
            end if;
         end;
      end loop;
      return N;
   end Nearest_Station;

   function Name_Of (I : Natural) return String is
     (if I = 0 then "the metro" else To_String (Stations (I).Name));

   ---------------------------------------------------------------------------

   procedure Enter (From_X, From_Z : Float) is
   begin
      if not Loaded then
         Load;
      end if;
      Here := Nearest_Station (From_X, From_Z);
      Origin := (From_X, Terrain.Height (From_X, From_Z) - 40.0, From_Z);
      Phase := Platform;
      Choice := (if Here = 1 then 2 else 1);
      Going := 0;
      Need_Build := True;
      Sound.Effect (Sound.Thud, 0.2, 0.0);
   end Enter;

   procedure Entrance (X, Z, Yaw : out Float) is
   begin
      --  at the foot of the stairs, at the end of the platform
      X := Origin.X + 3.0;
      Z := Origin.Z + 2.0;
      Yaw := Pi / 2.0;
   end Entrance;

   procedure Way_Out (X, Z, Yaw : out Float) is
      I : constant Natural := (if Phase = Arrived then Going else Here);
      Found : Boolean;
      EX, EZ, UX, UZ : Float;
      SX : constant Float := (if I = 0 then Origin.X else Stations (I).X);
      SZ : constant Float := (if I = 0 then Origin.Z else Stations (I).Z);
   begin
      --  up the stairs of the entrance nearest the station
      Street_Life.Nearest_Entrance (SX, SZ, 400.0, Found, EX, EZ, UX, UZ);
      if Found then
         --  stepping off the top of the stairs, away from them
         X := EX - 1.5 * UX;
         Z := EZ - 1.5 * UZ;
         Yaw := Arctan (-UX, UZ);
      else
         declare
            RH : Float;
         begin
            Road_Network.Nearest_Road (SX, SZ, Found, X, Z, RH);
            if not Found then
               X := SX;
               Z := SZ;
            end if;
            Yaw := RH;
         end;
      end if;
   end Way_Out;

   function Floor_Y return Float is (Origin.Y);

   procedure Keep_Inside (X, Z : in out Float) is
      LX : Float := X - Origin.X;
      LZ : Float := Z - Origin.Z;
   begin
      if Phase = Platform then
         LX := Float'Max (1.5, Float'Min (Plat_Len - 1.5, LX));
         LZ := Float'Max (0.7, Float'Min (4.3, LZ));
      else
         --  in the car
         LX := Float'Max (1.0, Float'Min (14.0, LX));
         LZ := Float'Max (Car_Z + 0.5, Float'Min (Car_Z + 2.1, LZ));
      end if;
      X := Origin.X + LX;
      Z := Origin.Z + LZ;
   end Keep_Inside;

   function At_Exit (X, Z : Float) return Boolean is
      pragma Unreferenced (X, Z);
   begin
      return Phase = Arrived;
   end At_Exit;

   procedure Update (Dt : Float; X, Z : Float) is
      pragma Unreferenced (X, Z);
   begin
      if Phase = Riding then
         Ride_T := Ride_T + Dt;
         if Ride_T >= Ride_Len then
            Phase := Arrived;
            Sound.Effect (Sound.Go_Beep, 0.5, 0.0);
         end if;
      end if;
   end Update;

   function Key (K : Natural) return Boolean is
      N : constant Natural := Natural (Stations.Length);
   begin
      if Phase /= Platform or else N < 2 then
         return False;
      end if;
      case K is
         when 16#FF52# =>   --  up (W and S still walk)
            Choice := (if Choice = 1 then N else Choice - 1);
            if Choice = Here then
               Choice := (if Choice = 1 then N else Choice - 1);
            end if;
         when 16#FF54# =>   --  down
            Choice := (if Choice = N then 1 else Choice + 1);
            if Choice = Here then
               Choice := (if Choice = N then 1 else Choice + 1);
            end if;
         when 16#FF0D# | 16#FF8D# =>   --  Enter: aboard
            Going := Choice;
            Phase := Riding;
            Ride_T := 0.0;
            declare
               D : constant Float := Sqrt ((Stations (Going).X - Stations (Here).X) ** 2
                                           + (Stations (Going).Z - Stations (Here).Z) ** 2);
            begin
               --  a short ride, a little longer the farther
               Ride_Len := Float'Max (8.0, Float'Min (20.0, 6.0 + D / 300.0));
            end;
            Sound.Effect (Sound.Beep, 0.6, 0.0);
         when others =>
            return False;
      end case;
      return True;
   end Key;

   function Status return String is
      function Esc (S : String) return String renames Glib.Convert.Escape_Text;
      T : Unbounded_String;
      LF : constant String := (1 => ASCII.LF);
   begin
      case Phase is
         when Platform =>
            T := To_Unbounded_String
              ("<span font_family='sans'><b><span foreground='#1d3b72' background='#f2f2f2'>  "
               & Esc (Name_Of (Here)) & "  </span></b>" & LF
               & "<span size='small'>Where to?  up/down, Enter: aboard    Q: up the stairs</span>" & LF);
            for I in Stations.First_Index .. Stations.Last_Index loop
               if I /= Here then
                  if I = Choice then
                     Append (T, "<span background='#3a6fd8' foreground='white'> " & Esc (Name_Of (I))
                             & "  <small>" & Esc (To_String (Stations (I).Lines)) & "</small> </span>" & LF);
                  elsif abs (I - Choice) <= 4 or else (Choice <= 4 and then I <= 9) then
                     Append (T, " " & Esc (Name_Of (I)) & "  <small>" & Esc (To_String (Stations (I).Lines))
                             & "</small>" & LF);
                  end if;
               end if;
            end loop;
            Append (T, "</span>");
            return To_String (T);
         when Riding =>
            return "<span font_family='sans'>Next station: <b>" & Esc (Name_Of (Going)) & "</b></span>";
         when Arrived =>
            return "";
      end case;
   end Status;

   function Heading return String is ("In the metro");
   function Arrival return String is ("Métro: " & Name_Of (Here));
   function Leaving return String is
     (if Phase = Arrived then Name_Of (Going) else Name_Of (Here));

   ---------------------------------------------------------------------------

   procedure Face (A, B, C, D, N : Vec3; Mat : Float) is
   begin
      if Dot (Cross (B - A, D - A), N) >= 0.0 then
         Meshes.Quad (A, B, C, D, Mat);
      else
         Meshes.Quad (D, C, B, A, Mat);
      end if;
   end Face;

   procedure Box (X0, X1, Y0, Y1, Z0, Z1, Mat : Float) is
   begin
      Meshes.Box (Origin.X + X0, Origin.X + X1, Origin.Y + Y0, Origin.Y + Y1, Origin.Z + Z0, Origin.Z + Z1, Mat);
   end Box;

   procedure Build is
      Steps : constant := 14;
      --  the vault over platform and track: centre at Z = 0.3, 7 m across
      R  : constant Float := 6.2;
      CZ : constant Float := 0.3;
      Spring : constant Float := 2.4;
   begin
      Meshes.Start;
      --  the platform and the track bed
      Box (0.0, Plat_Len, -0.05, 0.0, 0.0, 5.0, Mat_Floor);
      Box (0.0, Plat_Len, 0.0, 0.02, 0.0, 0.35, Mat_Edge);         --  the white edge
      Box (0.0, Plat_Len, -1.2, -1.15, -5.6, 0.0, Mat_Dark);         --  the track bed
      Face (G (0.0, -1.15, 0.0), G (Plat_Len, -1.15, 0.0), G (Plat_Len, 0.0, 0.0), G (0.0, 0.0, 0.0),
            (0.0, 0.0, -1.0), Mat_Tile);
      for Z of Float_List'(-4.3, -2.8) loop
         Box (0.0, Plat_Len, -1.15, -1.0, Z - 0.04, Z + 0.04, Mat_Iron);   --  rails
      end loop;
      --  the walls up to the springing, and the vault of tiles
      Face (G (0.0, 0.0, 5.0), G (Plat_Len, 0.0, 5.0), G (Plat_Len, Spring, 5.0), G (0.0, Spring, 5.0),
            (0.0, 0.0, -1.0), Mat_Tile);
      Face (G (0.0, -1.15, -5.6), G (Plat_Len, -1.15, -5.6), G (Plat_Len, Spring, -5.6), G (0.0, Spring, -5.6),
            (0.0, 0.0, 1.0), Mat_Tile);
      for K in 0 .. Steps - 1 loop
         declare
            A0 : constant Float := Pi * Float (K) / Float (Steps);
            A1 : constant Float := Pi * Float (K + 1) / Float (Steps);
            function V (A : Float; X : Float) return Vec3 is
              (G (X, Spring + 0.75 * R * Sin (A), CZ + 5.3 * Cos (A)));
         begin
            Face (V (A0, 0.0), V (A1, 0.0), V (A1, Plat_Len), V (A0, Plat_Len),
                  (0.0, -Sin (0.5 * (A0 + A1)), -Cos (0.5 * (A0 + A1))), Mat_Tile);
         end;
      end loop;
      --  the ends, dark tunnel mouths
      for X of Float_List'(0.0, Plat_Len) loop
         Face (G (X, -1.2, -5.6), G (X, -1.2, 5.0), G (X, Spring + 4.7, 5.0), G (X, Spring + 4.7, -5.6),
               (if X = 0.0 then Vec3'(1.0, 0.0, 0.0) else Vec3'(-1.0, 0.0, 0.0)), Mat_Dark);
      end loop;
      --  lights along the crown, the station's name on the wall (blue
      --  enamel), benches, the stairs up at the near end
      for K in 0 .. 11 loop
         Box (3.0 + 6.0 * Float (K), 5.0 + 6.0 * Float (K), Spring + 4.4, Spring + 4.5, -0.15, 0.15, Mat_Lamp);
      end loop;
      for K in 0 .. 3 loop
         declare
            X : constant Float := 10.0 + 18.0 * Float (K);
         begin
            Box (X, X + 3.4, 1.4, 2.1, 4.93, 4.98, 82.0);   --  blue enamel
            Box (X - 0.08, X + 3.48, 1.32, 2.18, 4.96, 4.99, Mat_Edge);
            Box (X + 5.0, X + 7.5, 0.0, 0.45, 4.2, 4.7, Mat_Seat);       --  a row of seats
            Box (X + 5.0, X + 7.5, 0.45, 0.9, 4.65, 4.75, Mat_Seat);
         end;
      end loop;
      Box (0.3, 1.3, 0.0, 3.0, 1.0, 4.0, Mat_Tile);
      for K in 0 .. 5 loop
         Box (0.0, 1.4 - 0.2 * Float (K), 0.0, 0.5 + 0.5 * Float (K), 0.9, 4.1, Mat_Floor);
      end loop;

      --  the car: floor, ceiling, the walls with their windows, the seats,
      --  the poles, the lights (from X 0 to 15, Z Car_Z .. Car_Z + 2.6)
      Box (0.0, 15.0, -0.05, 0.0, Car_Z, Car_Z + 2.6, Mat_Floor);
      Box (0.0, 15.0, 2.3, 2.35, Car_Z, Car_Z + 2.6, Mat_Paint);
      for Side of Float_List'(Car_Z, Car_Z + 2.6) loop
         Box (0.0, 15.0, 0.0, 0.85, Side - 0.03, Side + 0.03, Mat_Paint);
         Box (0.0, 15.0, 1.9, 2.3, Side - 0.03, Side + 0.03, Mat_Paint);
         for K in 0 .. 5 loop
            declare
               X : constant Float := 2.5 * Float (K);
            begin
               Box (X, X + 0.25, 0.85, 1.9, Side - 0.03, Side + 0.03, Mat_Paint);   --  between the windows
               Box (X + 0.25, X + 2.5, 0.85, 1.9, Side - 0.01, Side + 0.01, Mat_Glass);
            end;
         end loop;
         for K in 0 .. 4 loop
            Box (1.0 + 3.0 * Float (K), 2.6 + 3.0 * Float (K), 0.0, 0.48,
                 (if Side = Car_Z then Side + 0.05 else Side - 0.55), (if Side = Car_Z then Side + 0.55 else Side - 0.05),
                 Mat_Seat);
         end loop;
      end loop;
      for X of Float_List'(0.0, 15.0) loop
         Box (X - 0.03, X + 0.03, 0.0, 2.3, Car_Z, Car_Z + 2.6, Mat_Paint);
      end loop;
      for K in 0 .. 4 loop
         Box (2.8 + 3.0 * Float (K), 2.85 + 3.0 * Float (K), 0.0, 2.3, Car_Z + 1.27, Car_Z + 1.33, Mat_Iron);
      end loop;
      Box (0.5, 14.5, 2.25, 2.3, Car_Z + 1.2, Car_Z + 1.4, Mat_Lamp);
      --  the tunnel walls outside, dark
      for Z of Float_List'(Car_Z - 1.2, Car_Z + 3.8) loop
         Face (G (-60.0, -0.5, Z), G (75.0, -0.5, Z), G (75.0, 3.5, Z), G (-60.0, 3.5, Z),
               (0.0, 0.0, (if Z < Car_Z then 1.0 else -1.0)), Mat_Dark);
      end loop;
      Meshes.Finish (Hall);
      --  the tunnel lamps, one row's worth, slid along in Draw
      Meshes.Start;
      for K in 0 .. 14 loop
         for Z of Float_List'(Car_Z - 1.15, Car_Z + 3.75) loop
            Meshes.Box (-60.0 + Lamp_Gap * Float (K), -59.6 + Lamp_Gap * Float (K), 1.5, 1.62, Z - 0.04, Z + 0.04,
                        Mat_Lamp);
         end loop;
      end loop;
      Meshes.Finish (Lamps);
   end Build;

   --  How far the train has gone after T seconds: 18 m/s at the most, in
   --  a sine from standstill to standstill
   function Speed_Distance (T : Float) return Float is
     (18.0 * Ride_Len / Pi * (1.0 - Cos (Pi * Float'Min (1.0, T / Ride_Len))));

   procedure Draw (Model, Paint, Skin, Gallery : GL.GLint) is
   begin
      if Need_Build then
         Need_Build := False;
         if Built then
            Meshes.Free (Hall);
            Meshes.Free (Lamps);
         end if;
         Build;
         Built := True;
      end if;
      if not Built then
         return;
      end if;
      Shaders.Set (Gallery, 1.0);
      Shaders.Set (Skin, Vec3'(1.0, 0.9, 0.7));   --  the lamps' warm white
      Shaders.Set (Model, Identity);
      Shaders.Set (Paint, Vec3'(0.2, 0.42, 0.55));   --  the car's blue-green
      Meshes.Draw (Hall);
      if Phase = Riding then
         --  the lamps rush by: fast in the middle of the ride, slow at the ends
         declare
            Gone : constant Float := Speed_Distance (Ride_T);
            Off  : constant Float := Gone - Lamp_Gap * Float'Floor (Gone / Lamp_Gap);
         begin
            Shaders.Set (Skin, Vec3'(1.0, 0.85, 0.6));
            Shaders.Set (Model, Translation ((Origin.X - Off, Origin.Y, Origin.Z)));
            Meshes.Draw (Lamps);
         end;
      end if;
      Shaders.Set (Model, Identity);
      Shaders.Set (Gallery, 0.0);
   end Draw;

end Metro;
