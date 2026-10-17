--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;
with Ada.Strings.Fixed;
with Ada.Strings.Maps.Constants;
with Ada.Text_IO;

with Almanac;
with Beacon;
with Figures;
with Geo;
with Meshes;
with Road_Network;
with Shaders;
with Sound;
with Traffic;
with Tyre_Effects;
with World;

package body Surprises is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;
   use type GL.GLint;

   Pi : constant := Ada.Numerics.Pi;

   type Float_Array is array (Positive range <>) of Float;

   --  one of N, from a number in 0 .. 1
   function Pick (H : Float; N : Positive) return Natural is
     (Natural (Float'Floor (H * Float (N))) mod N);

   Gen : Ada.Numerics.Float_Random.Generator;
   function Rnd return Float is (Ada.Numerics.Float_Random.Random (Gen));
   function Sym return Float is (2.0 * Rnd - 1.0);

   --  A stable random number for a place
   function Hash (X, Z : Float) return Float is
      V : constant Float := Sin (X * 12.9898 + Z * 78.233) * 43_758.547;
   begin
      return V - Float'Floor (V);
   end Hash;

   function Local (Lat, Lon : Long_Float; Y : Float := 0.0) return Vec3 is
      X, Z : Long_Float;
   begin
      Geo.To_Local (Lat, Lon, X, Z);
      return (Float (X), Y, Float (Z));
   end Local;

   function Heading_Of (D : Vec3) return Float is
     (if abs D.X + abs D.Z < 1.0E-6 then 0.0 else Arctan (D.X, -D.Z));

   --  a model matrix: at P, facing heading H (front is -Z), scaled
   function Place (P : Vec3; H : Float; Scale : Float := 1.0) return Mat4 is
      M : Mat4 := Translation (P) * Rotation_Y (-H);
   begin
      if Scale /= 1.0 then
         for K in 0 .. 10 loop
            if K mod 4 /= 3 then
               M (K) := M (K) * Scale;
            end if;
         end loop;
      end if;
      return M;
   end Place;

   function Dist2 (A, B : Vec3) return Float is ((A.X - B.X) ** 2 + (A.Z - B.Z) ** 2);

   Now   : Situation;
   Clock : Float := 0.0;
   Locs  : Figures.Locations;

   type Forced_Kind is (Parade_F, Jets_F, Tour_F, Music_F, Plages_F, Pigeons_F,
                        Snowball_F, Balloon_F, Asteroid_F, Phantom_F, Boats_F, Everywhere_F);
   Forced : array (Forced_Kind) of Boolean := (others => False);

   procedure Force (Name : String) is
   begin
      for F in Forced_Kind loop
         declare
            Img : constant String := Forced_Kind'Image (F);
         begin
            if Ada.Strings.Fixed.Translate
                 (Name, Ada.Strings.Maps.Constants.Upper_Case_Map) & "_F" = Img
            then
               Forced (F) := True;
            end if;
         end;
      end loop;
   end Force;

   ---------------------------------------------------------------------------
   --  Polylines from data files (the Seine, the beach of Paris-Plages)
   ---------------------------------------------------------------------------

   Max_Points : constant := 120;
   type Point_Array is array (1 .. Max_Points) of Vec3;
   type Length_Array is array (1 .. Max_Points) of Float;
   type Polyline is record
      P   : Point_Array;
      Cum : Length_Array := (others => 0.0);
      N   : Natural := 0;
   end record;

   function Length_Of (L : Polyline) return Float is
     (if L.N = 0 then 0.0 else L.Cum (L.N));

   procedure Load (File : String; Y : Float; L : out Polyline) is
      use Ada.Text_IO;
      F : File_Type;
   begin
      L.N := 0;
      Open (F, In_File, File);
      while not End_Of_File (F) loop
         declare
            Line : constant String := Get_Line (F);
            Sp   : constant Natural := Ada.Strings.Fixed.Index (Line, " ");
         begin
            if Line'Length > 0 and then Line (Line'First) /= '#' and then Sp > 0
              and then L.N < Max_Points
            then
               L.N := L.N + 1;
               L.P (L.N) := Local (Long_Float'Value (Line (Line'First .. Sp - 1)),
                                   Long_Float'Value (Line (Sp + 1 .. Line'Last)), Y);
               L.Cum (L.N) := (if L.N = 1 then 0.0
                               else L.Cum (L.N - 1) + Length (L.P (L.N) - L.P (L.N - 1)));
            end if;
         end;
      end loop;
      Close (F);
   exception
      when others =>
         if Is_Open (F) then
            Close (F);
         end if;
   end Load;

   --  Position and direction at distance S along the line
   procedure At_Distance (L : Polyline; S : Float; P, D : out Vec3) is
      T : constant Float := Float'Max (0.0, Float'Min (Length_Of (L), S));
   begin
      P := (0.0, 0.0, 0.0);
      D := (1.0, 0.0, 0.0);
      for I in 2 .. L.N loop
         if T <= L.Cum (I) or else I = L.N then
            declare
               Seg : constant Float := Float'Max (0.01, L.Cum (I) - L.Cum (I - 1));
               F   : constant Float := Float'Min (1.0, (T - L.Cum (I - 1)) / Seg);
            begin
               D := Normalize (L.P (I) - L.P (I - 1));
               P := L.P (I - 1) + F * (L.P (I) - L.P (I - 1));
               return;
            end;
         end if;
      end loop;
   end At_Distance;

   function Right_Of (D : Vec3) return Vec3 is ((-D.Z, 0.0, D.X));

   Seine, Beach : Polyline;

   ---------------------------------------------------------------------------
   --  Meshes
   ---------------------------------------------------------------------------

   Mat_Hide  : constant := 13.0;
   Mat_Paint : constant := 15.0;
   Mat_Glass : constant := 16.0;
   Mat_Black : constant := 17.0;
   Mat_Lamp  : constant := 18.0;
   Mat_Red   : constant := 19.0;
   Mat_Crown : constant := 14.0;
   Mat_Sand  : constant := 5.0;
   Mat_Stone : constant := 29.0;
   Mat_Gold  : constant := 38.0;
   Mat_White : constant := 39.0;
   Mat_Glow  : constant := 41.0;   --  dark by day, warm light at night
   Mat_Ghost : constant := 42.0;
   Mat_Asteroid : constant := 43.0;   --  a little planet, glowing softly at night

   Tank, Truck, Jet, Boat, Balloon_M, Cable, Asteroid_M, Mask : Meshes.Mesh;
   Beach_Plain : Meshes.Mesh;
   Beach_Colour : array (0 .. 3) of Meshes.Mesh;
   Beach_Tint : constant array (0 .. 3) of Vec3 :=
     ((0.1, 0.35, 0.8), (0.95, 0.82, 0.2), (0.9, 0.2, 0.2), (0.1, 0.6, 0.55));

   type Chair is record
      P : Vec3;
      H : Float;
      Sunbather : Boolean;
      Swimsuit : Vec3;
   end record;
   Chairs : array (1 .. 200) of Chair;
   Chair_Count : Natural := 0;

   --  a ball of quads (faces outwards); Stripe picks the material per segment
   procedure Ball (C : Vec3; R, Squash : Float; Segs, Rings : Positive;
                   Mat_A, Mat_B : Float) is
      function P (I, J : Integer) return Vec3 is
         Phi   : constant Float := 2.0 * Pi * Float (I) / Float (Segs);
         Theta : constant Float := Pi * Float (J) / Float (Rings);
      begin
         return C + Vec3'(R * Sin (Theta) * Cos (Phi), -R * Squash * Cos (Theta),
                          R * Sin (Theta) * Sin (Phi));
      end P;
   begin
      for J in 0 .. Rings - 1 loop
         for I in 0 .. Segs - 1 loop
            Meshes.Quad (P (I, J), P (I, J + 1), P (I + 1, J + 1), P (I + 1, J),
                         (if I mod 2 = 0 then Mat_A else Mat_B));
         end loop;
      end loop;
   end Ball;

   procedure Cone (C : Vec3; R, H : Float; Mat : Float; Segs : Positive := 10) is
      Apex : constant Vec3 := C + Vec3'(0.0, H, 0.0);
   begin
      for I in 0 .. Segs - 1 loop
         declare
            A0 : constant Float := 2.0 * Pi * Float (I) / Float (Segs);
            A1 : constant Float := 2.0 * Pi * Float (I + 1) / Float (Segs);
            P0 : constant Vec3 := C + Vec3'(R * Cos (A0), 0.0, R * Sin (A0));
            P1 : constant Vec3 := C + Vec3'(R * Cos (A1), 0.0, R * Sin (A1));
         begin
            Meshes.Quad (P1, Apex, Apex, P0, Mat);
         end;
      end loop;
   end Cone;

   procedure Build_Beach is
      use Meshes;
      Step : constant := 6.0;
      S    : Float := 4.0;
      K    : Natural := 0;
      P, D : Vec3;
   begin
      if Beach.N < 2 then
         return;
      end if;
      --  sand, poles and palm trees in one mesh
      Start;
      while S < Length_Of (Beach) loop
         At_Distance (Beach, S, P, D);
         declare
            R : constant Vec3 := Right_Of (D);
            Q : constant Vec3 := P + (if K mod 2 = 0 then 3.0 else -3.0) * R;
         begin
            --  a patch of sand under everything
            Box (P.X - 3.2, P.X + 3.2, P.Y, P.Y + 0.08, P.Z - 3.2, P.Z + 3.2, Mat_Sand);
            if K mod 7 = 3 then
               --  a palm tree in a tub
               Box (Q.X - 0.5, Q.X + 0.5, P.Y, P.Y + 0.7, Q.Z - 0.5, Q.Z + 0.5, Mat_Hide);
               Box (Q.X - 0.12, Q.X + 0.12, P.Y + 0.7, P.Y + 4.2, Q.Z - 0.12, Q.Z + 0.12, Mat_Hide);
               for Leaf in 0 .. 5 loop
                  declare
                     A : constant Float := Float (Leaf) * Pi / 3.0;
                     T : constant Vec3 := Q + Vec3'(0.0, 4.2, 0.0);
                     E : constant Vec3 := T + Vec3'(1.8 * Cos (A), -0.6, 1.8 * Sin (A));
                     W : constant Vec3 := 0.3 * Vec3'(-Sin (A), 0.0, Cos (A));
                  begin
                     Quad (T - W, T + W, E + W, E - W, Mat_Crown);
                     Quad (E - W, E + W, T + W, T - W, Mat_Crown);
                  end;
               end loop;
            elsif K mod 2 = 0 then
               --  a parasol pole (its canopy is coloured)
               Box (Q.X - 0.04, Q.X + 0.04, P.Y, P.Y + 2.2, Q.Z - 0.04, Q.Z + 0.04, Mat_White);
            end if;
         end;
         S := S + Step;
         K := K + 1;
      end loop;
      Finish (Beach_Plain);
      --  canopies and deckchairs, one mesh per colour
      for C in Beach_Colour'Range loop
         Start;
         S := 4.0;
         K := 0;
         while S < Length_Of (Beach) loop
            At_Distance (Beach, S, P, D);
            declare
               R : constant Vec3 := Right_Of (D);
               Q : constant Vec3 := P + (if K mod 2 = 0 then 3.0 else -3.0) * R;
               Col : constant Natural := K mod 4;
            begin
               if Col = C and then K mod 7 /= 3 then
                  if K mod 2 = 0 then
                     Box (Q.X - 1.3, Q.X + 1.3, P.Y + 2.0, P.Y + 2.5, Q.Z - 1.3, Q.Z + 1.3,
                          Mat_Paint, Top_Inset_X => 1.25, Top_Inset_Front => 1.25,
                          Top_Inset_Back => 1.25);
                  end if;
                  --  two deckchairs beside it, facing the river
                  for Side of Float_Array'(-1.0, 1.0) loop
                     declare
                        Ch : constant Vec3 := Q + (1.1 * Side) * D;
                     begin
                        Box (Ch.X - 0.3, Ch.X + 0.3, P.Y + 0.25, P.Y + 0.33,
                             Ch.Z - 0.7, Ch.Z + 0.7, Mat_Paint);
                        if Chair_Count < Chairs'Last then
                           Chair_Count := Chair_Count + 1;
                           Chairs (Chair_Count) :=
                             (P => (Ch.X, P.Y + 0.33, Ch.Z),
                              H => Heading_Of ((if K mod 2 = 0 then -1.0 else 1.0) * R),
                              Sunbather => Hash (Ch.X, Ch.Z) < 0.55,
                              Swimsuit => Beach_Tint ((Col + 1 + Pick (Hash (Ch.Z, Ch.X), 3)) mod 4));
                        end if;
                     end;
                  end loop;
               end if;
            end;
            S := S + Step;
            K := K + 1;
         end loop;
         Finish (Beach_Colour (C));
      end loop;
   end Build_Beach;

   procedure Create is
      use Meshes;
   begin
      Ada.Numerics.Float_Random.Reset (Gen);
      Figures.Create;

      --  a Leclerc tank (front is -Z), in its paint
      Start;
      Box (-1.85, 1.85, 0.0, 0.9, -4.8, 4.6, Mat_Black);                   --  tracks
      Box (-1.75, 1.75, 0.9, 1.75, -4.9, 4.7, Mat_Paint, Top_Inset_Front => 0.6);
      Box (-1.2, 1.2, 1.75, 2.45, -1.6, 1.8, Mat_Paint, Top_Inset_X => 0.15,
           Top_Inset_Front => 0.3);                                         --  turret
      Box (-0.12, 0.12, 2.0, 2.24, -7.8, -1.5, Mat_Paint);                 --  gun
      Box (-0.4, 0.4, 2.45, 2.75, 0.2, 0.9, Mat_Paint);                    --  hatch
      Finish (Tank);
      --  an armoured truck (VAB): six wheels, a box
      Start;
      Box (-1.25, 1.25, 0.6, 2.2, -3.0, 3.0, Mat_Paint, Top_Inset_Front => 0.5);
      for Z of Float_Array'(-2.0, 0.0, 2.0) loop
         Box (-1.3, -1.0, 0.0, 1.1, Z - 0.55, Z + 0.55, Mat_Black);
         Box (1.0, 1.3, 0.0, 1.1, Z - 0.55, Z + 0.55, Mat_Black);
      end loop;
      Box (-1.0, 1.0, 1.5, 1.9, -3.05, -2.95, Mat_Glass);
      Finish (Truck);
      --  an Alpha Jet of the Patrouille de France
      Start;
      Box (-0.6, 0.6, -0.5, 0.7, -6.0, 6.0, Mat_Paint, Top_Inset_Front => 0.5);
      Box (-0.45, 0.45, 0.6, 1.2, -4.0, -1.5, Mat_Glass);                   --  canopy
      Box (-4.6, 4.6, -0.1, 0.1, -1.0, 2.0, Mat_Paint, Top_Inset_Front => 1.0); --  wings
      Box (-2.0, 2.0, 0.1, 0.25, 4.0, 5.6, Mat_Paint);                      --  tailplane
      Box (-0.1, 0.1, 0.6, 2.6, 3.8, 6.0, Mat_Paint, Top_Inset_Front => 1.2); --  fin
      Finish (Jet);
      --  a bateau-mouche: a long low hull, a glass cabin lit at night
      Start;
      Box (-3.2, 3.2, -6.7, -5.0, -15.0, 15.0, Mat_Paint, Top_Inset_Front => 1.5);
      Box (-2.9, 2.9, -5.0, -3.2, -10.0, 12.0, Mat_Glow, Side_Mat => Mat_Glass);
      Box (-3.0, 3.0, -3.2, -3.0, -10.5, 12.5, Mat_White);                 --  roof deck
      for Z of Float_Array'(-8.0, -2.0, 4.0, 10.0) loop
         Box (-3.25, -3.1, -4.6, -4.3, Z - 0.4, Z + 0.4, Mat_Lamp);          --  floodlights
         Box (3.1, 3.25, -4.6, -4.3, Z - 0.4, Z + 0.4, Mat_Lamp);
      end loop;
      Finish (Boat);
      --  the balloon: striped, with the basket ring under it
      Start;
      Ball ((0.0, 0.0, 0.0), 11.0, 1.05, 16, 10, Mat_Paint, Mat_White);
      Box (-3.0, 3.0, -13.5, -12.3, -3.0, 3.0, Mat_Gold);
      Box (-2.6, 2.6, -12.3, -11.5, -2.6, 2.6, Mat_Black);
      Finish (Balloon_M);
      Start;
      Box (-0.05, 0.05, 0.0, 1.0, -0.05, 0.05, Mat_Black);
      Finish (Cable);
      --  the Little Prince's asteroid, with its volcanoes and the rose
      Start;
      Ball ((0.0, 0.0, 0.0), 30.0, 1.0, 14, 9, Mat_Asteroid, Mat_Asteroid);
      Cone ((12.0, 26.0, 8.0), 6.0, 7.0, Mat_Stone);
      Cone ((-10.0, 27.0, 10.0), 5.0, 6.0, Mat_Stone);
      Box (-14.5, -13.5, 27.0, 30.0, -6.5, -5.5, Mat_Glow);                 --  a little fire
      Box (5.2, 5.6, 29.0, 33.0, -8.2, -7.8, Mat_Crown);                    --  the rose's stem
      Cone ((5.4, 33.0, -8.0), 1.2, 1.8, Mat_Red);                          --  the rose
      Finish (Asteroid_M);
      --  the Phantom's half mask (front is +Z, it looks south)
      Start;
      Box (0.0, 0.2, -0.28, 0.16, 0.0, 0.07, Mat_Ghost, Top_Inset_X => 0.03,
           Top_Inset_Front => 0.02, Top_Inset_Back => 0.02);
      Box (0.05, 0.15, 0.0, 0.07, 0.065, 0.08, Mat_Black);                 --  the eye
      Finish (Mask);

      Load ("data/seine.txt", 0.0, Seine);   --  the boat meshes carry the water level
      Load ("data/paris_plages.txt", 0.02, Beach);   --  the quay is at street level in the game
      Build_Beach;
   end Create;

   ---------------------------------------------------------------------------
   --  The 14th of July: the parade down the Champs-Élysées, the jets
   ---------------------------------------------------------------------------

   function Arc return Vec3 is (Local (48.87378, 2.29504));
   function Concorde return Vec3 is (Local (48.86560, 2.32120));

   Parade_Active, Tour_Active : Boolean := False;
   Jets_On   : Boolean := False;
   Jets_T    : Float := 0.0;
   Jets_Next : Float := 5.0;
   Jets_Level, Crowd_Level : Float := 0.0;

   type Formation_Slot is record
      Along, Side : Float;
   end record;
   Formation : constant array (1 .. 9) of Formation_Slot :=
     ((0.0, 0.0), (-18.0, -15.0), (-18.0, 15.0), (-36.0, -30.0), (-36.0, 30.0),
      (-36.0, 0.0), (-54.0, -15.0), (-54.0, 15.0), (-72.0, 0.0));
   Smoke_Due : Float := 0.0;

   function Jet_Pos (I : Positive) return Vec3 is
      D : constant Vec3 := Normalize (Concorde - Arc);
   begin
      return Arc + (Jets_T * 150.0 - 2500.0 + Formation (I).Along) * D
        + Formation (I).Side * Right_Of (D) + Vec3'(0.0, 260.0, 0.0);
   end Jet_Pos;

   ---------------------------------------------------------------------------
   --  Pigeons, street musicians and children throwing snowballs live by
   --  the street lamps near you
   ---------------------------------------------------------------------------

   type Lamp is record
      P : Vec3;
      H : Float;   --  its stable random number
   end record;
   Lamps : array (1 .. World.Max_Lights) of Lamp;
   Lamp_Count : Natural := 0;
   Look_Again : Float := 0.0;

   type Bird is record
      P, V : Vec3 := (0.0, 0.0, 0.0);
      Yaw  : Float := 0.0;
   end record;
   type Bird_Array is array (1 .. 9) of Bird;
   type Flock is record
      Key     : Vec3 := (0.0, -999.0, 0.0);
      Birds   : Bird_Array;
      Flying  : Float := -1.0;    --  seconds since they took off (< 0: on the ground)
      Gone    : Float := 0.0;     --  seconds until they come back
   end record;
   Flocks : array (1 .. 14) of Flock;

   type Snowball is record
      Live   : Boolean := False;
      From, To : Vec3;
      T, Time : Float := 0.0;
      At_Car : Boolean := False;
   end record;
   Balls : array (1 .. 24) of Snowball;

   type Kid is record
      Key   : Vec3 := (0.0, -999.0, 0.0);
      Wait  : Float := 1.0;
      Throw : Float := 0.0;    --  > 0: the arm is up
   end record;
   Kids : array (1 .. 18) of Kid;

   Busker_Tune : Natural := 0;
   Drawn_Musicians : Natural := 0;
   Last_Musician : Vec3 := (0.0, 0.0, 0.0);
   Busker_Loud, Busker_Side : Float := 0.0;

   function Side_Of (P : Vec3) return Float is
      D  : constant Vec3 := P - Now.Listener;
      DH : constant Float := Float'Max (0.5, Sqrt (D.X * D.X + D.Z * D.Z));
   begin
      return (D.X * Cos (Now.Heading) + D.Z * Sin (Now.Heading)) / DH;
   end Side_Of;

   --  which lamps have a musician, a flock of pigeons, children (testing:
   --  "everywhere" puts one of them at every lamp)
   function Musician_At (I : Positive) return Boolean is
     (if Forced (Everywhere_F) then I mod 3 = 0 else Lamps (I).H in 0.15 .. 0.27);
   function Pigeons_At (I : Positive) return Boolean is
     (if Forced (Everywhere_F) then I mod 3 = 1 else Lamps (I).H in 0.27 .. 0.37);
   function Children_At (I : Positive) return Boolean is
     (if Forced (Everywhere_F) then I mod 3 = 2 else Lamps (I).H in 0.37 .. 0.43);

   procedure Refresh_Lamps is
      Data : World.Light_Data;
      N    : Natural;
   begin
      World.Nearest_Lights (Now.Listener.X, Now.Listener.Z, Data, N);
      Lamp_Count := N;
      for I in 0 .. N - 1 loop
         Lamps (I + 1) := ((Data (4 * I), 0.14, Data (4 * I + 2)),
                           Hash (Data (4 * I), Data (4 * I + 2)));
      end loop;
   end Refresh_Lamps;

   --  facing the street from P
   function Street_Heading (P : Vec3) return Float is
      Found : Boolean;
      RX, RZ, RH : Float;
   begin
      Road_Network.Nearest_Road (P.X, P.Z, Found, RX, RZ, RH);
      return (if Found and then abs (RX - P.X) + abs (RZ - P.Z) > 0.2
              then Heading_Of ((RX - P.X, 0.0, RZ - P.Z)) else RH);
   end Street_Heading;

   function Music_On return Boolean is
     (Forced (Music_F)
      or else (Almanac.Month = 6 and then Almanac.Day = 21 and then Now.Hour >= 17.0)
      or else (Almanac.Month = 6 and then Almanac.Day = 22 and then Now.Hour < 2.0));

   function Plages_On return Boolean is
     (Forced (Plages_F)
      or else (Almanac.Month = 7 and then Almanac.Day >= 10)
      or else (Almanac.Month = 8 and then Almanac.Day <= 20));

   function Pigeons_On return Boolean is
     (Forced (Pigeons_F)
      or else (Now.Night < 0.4 and then Now.Rain < 0.2 and then Now.Snow < 0.3));

   function Snowballs_On return Boolean is
     (Forced (Snowball_F) or else (Now.Snow > 0.5 and then Now.Night < 0.4));

   ---------------------------------------------------------------------------
   --  The cat on the balconies
   ---------------------------------------------------------------------------

   Cat_Known  : Boolean := False;
   Cat_Origin, Cat_Along, Cat_Out : Vec3;
   Cat_From, Cat_To, Cat_Y : Float := 0.0;
   Cat_S      : Float := 0.0;
   Cat_Dir    : Float := 1.0;
   Cat_Sit    : Float := 0.0;
   Cat_Meow   : Float := 20.0;

   procedure Set_Balcony (Origin, Along, Outward : Vec3; From, To, Floor_Y : Float) is
   begin
      Cat_Known := True;
      Cat_Origin := Origin;
      Cat_Along := Along;
      Cat_Out := Outward;
      Cat_From := From;
      Cat_To := To;
      Cat_Y := Floor_Y;
      Cat_S := 0.5 * (From + To);
   end Set_Balcony;

   function Cat_Pos return Vec3 is
     (Cat_Origin + Cat_S * Cat_Along + 0.68 * Cat_Out + Vec3'(0.0, Cat_Y + 1.0 - Cat_Origin.Y, 0.0));

   ---------------------------------------------------------------------------
   --  Rare nights and the curiosities
   ---------------------------------------------------------------------------

   Asteroid_Tonight : Boolean := False;
   Rolled_Night     : Boolean := False;
   Phantom_T        : Float := 0.0;
   Balloon_Y        : Float := 0.0;

   function Balloon_Pos return Vec3 is (Local (48.84133, 2.27427, Balloon_Y + 14.0));

   function Asteroid_Pos return Vec3 is
      Az : constant Float := 0.8 + Clock * 0.0025;
      El : constant Float := 0.38;
   begin
      return Now.Listener + 1500.0 * Vec3'(Cos (El) * Sin (Az), Sin (El), -Cos (El) * Cos (Az));
   end Asteroid_Pos;

   function Opera_Mask return Vec3 is (Local (48.87131, 2.33173, 22.0));

   type Boat_State is record
      S, Dir : Float := 0.0;
   end record;
   Boats : array (1 .. 6) of Boat_State;
   Boats_Placed : Boolean := False;

   procedure Boat_At (B : Boat_State; P, D : out Vec3) is
      C : Vec3;
   begin
      At_Distance (Seine, B.S, C, D);
      D := B.Dir * D;
      P := C + 16.0 * Right_Of (D);
   end Boat_At;

   ---------------------------------------------------------------------------

   procedure Update (S : Situation) is
      Dt : constant Float := S.Dt;
   begin
      Now := S;
      Clock := Clock + Dt;

      --  the 14th of July, from half past nine to half past twelve
      Parade_Active := Forced (Parade_F)
        or else (Almanac.Bastille_Day and then S.Hour >= 9.5 and then S.Hour < 12.5);
      Tour_Active := Forced (Tour_F)
        or else (Almanac.Month = 7 and then Almanac.Sunday and then Almanac.Day >= 25
                 and then S.Hour >= 15.5 and then S.Hour < 19.5);
      Crowd_Level := 0.0;
      if Parade_Active or else Tour_Active then
         Traffic.Clear_Corridor (Arc, Concorde, 32.0);
         declare
            D  : constant Vec3 := Concorde - Arc;
            T  : constant Float := Float'Max (0.0, Float'Min (1.0,
                   Dot (S.Listener - Arc, D) / Dot (D, D)));
            Off : constant Float := Sqrt (Dist2 (S.Listener, Arc + T * D));
         begin
            Crowd_Level := Float'Max (0.0, 1.0 - Off / 180.0) * (if Tour_Active then 1.0 else 0.6);
         end;
      end if;

      --  the Patrouille de France goes over every couple of minutes
      if Parade_Active or else Forced (Jets_F) then
         if not Jets_On then
            Jets_Next := Jets_Next - Dt;
            if Jets_Next <= 0.0 or else Forced (Jets_F) then
               Jets_On := True;
               Jets_T := 0.0;
               Forced (Jets_F) := False;
            end if;
         end if;
      end if;
      Jets_Level := 0.0;
      if Jets_On then
         Jets_T := Jets_T + Dt;
         Smoke_Due := Smoke_Due + Dt;
         if Smoke_Due > 0.12 then
            Smoke_Due := 0.0;
            for I in Formation'Range loop
               declare
                  Colour : constant Natural :=
                    (if Formation (I).Side < -1.0 then 1
                     elsif Formation (I).Side > 1.0 then 3 else 2);
               begin
                  if I /= 1 and then I /= 9 then
                     Tyre_Effects.Add_Puff (Jet_Pos (I) + Vec3'(0.0, -0.5, 0.0)
                                            - 8.0 * Normalize (Concorde - Arc),
                                            (0.5 * Sym, -0.4, 0.5 * Sym), Colour, 4.0, 22.0);
                  end if;
               end;
            end loop;
         end if;
         Jets_Level := Float'Min (1.0, 300.0 / (Length (Jet_Pos (6) - S.Listener) + 60.0));
         if Jets_T * 150.0 > 7000.0 then
            Jets_On := False;
            Jets_Next := 120.0;
         end if;
      end if;

      --  lamps near you, for pigeons, musicians and snowball fights
      Look_Again := Look_Again - Dt;
      if Look_Again <= 0.0 then
         Look_Again := 0.5;
         Refresh_Lamps;
      end if;

      --  the nearest musician plays
      Busker_Tune := 0;
      Busker_Loud := 0.0;
      if Music_On then
         declare
            Best : Float := 30.0;
         begin
            for I in 1 .. Lamp_Count loop
               if Musician_At (I) then
                  declare
                     D : constant Float := Length (Lamps (I).P - S.Listener);
                  begin
                     if D < Best then
                        Best := D;
                        Busker_Tune := 1 + Natural (Float'Floor (Hash (Lamps (I).P.Z, Lamps (I).P.X) * 4.99));
                        Busker_Loud := 1.0 - D / 30.0;
                        Busker_Side := Side_Of (Lamps (I).P);
                     end if;
                  end;
               end if;
            end loop;
         end;
      end if;

      --  pigeons: a flock by about one lamp in ten, flying up from the car
      for I in 1 .. Lamp_Count loop
         if Pigeons_On and then Pigeons_At (I) then
            declare
               Key   : constant Vec3 := Lamps (I).P;
               Found : Natural := 0;
               Free  : Natural := 0;
            begin
               for F in Flocks'Range loop
                  if Dist2 (Flocks (F).Key, Key) < 0.01 then
                     Found := F;
                  elsif Free = 0 and then (Flocks (F).Key.Y < -100.0
                                           or else Dist2 (Flocks (F).Key, S.Listener) > 160.0 ** 2)
                  then
                     Free := F;
                  end if;
               end loop;
               if Found = 0 and then Free > 0 then
                  Flocks (Free).Key := Key;
                  Flocks (Free).Flying := -1.0;
                  Flocks (Free).Gone := 0.0;
                  for B of Flocks (Free).Birds loop
                     B := (P => Key + Vec3'(3.0 * Sym + 1.5, -0.1, 3.0 * Sym),
                           V => (0.0, 0.0, 0.0), Yaw => 2.0 * Pi * Rnd);
                  end loop;
               end if;
            end;
         end if;
      end loop;
      for F of Flocks loop
         if F.Key.Y > -100.0 then
            if F.Gone > 0.0 then
               F.Gone := F.Gone - Dt;
               if F.Gone <= 0.0 then
                  F.Key := (0.0, -999.0, 0.0);   --  will land again later
               end if;
            elsif F.Flying < 0.0 then
               --  pecking about; off they go when the car comes
               for B of F.Birds loop
                  if Rnd < Dt * 0.5 then
                     B.Yaw := B.Yaw + Sym;
                     B.P := B.P + 0.15 * Vec3'(Sin (B.Yaw), 0.0, -Cos (B.Yaw));
                  end if;
               end loop;
               if S.Driving and then S.Car_Speed > 1.0 and then Dist2 (S.Car_Pos, F.Key) < 11.0 ** 2 then
                  F.Flying := 0.0;
                  for B of F.Birds loop
                     declare
                        Away : constant Vec3 := Normalize (Vec3'(B.P.X - S.Car_Pos.X, 0.0, B.P.Z - S.Car_Pos.Z));
                     begin
                        B.V := (3.0 * Away.X + 1.5 * Sym, 3.5 + 2.0 * Rnd, 3.0 * Away.Z + 1.5 * Sym);
                        B.Yaw := Heading_Of (B.V);
                     end;
                  end loop;
                  Sound.Effect (Sound.Flutter,
                                Float'Min (1.0, 12.0 / (Length (F.Key - S.Listener) + 4.0)),
                                Side_Of (F.Key));
               end if;
            else
               F.Flying := F.Flying + Dt;
               for B of F.Birds loop
                  B.P := B.P + Dt * B.V;
                  B.V.Y := B.V.Y + 0.3 * Dt;
               end loop;
               if F.Flying > 7.0 then
                  F.Gone := 60.0;
               end if;
            end if;
         end if;
      end loop;

      --  snowball fights: three children by about one lamp in sixteen
      if Snowballs_On then
         for I in 1 .. Lamp_Count loop
            if Children_At (I) then
               for K in 0 .. 2 loop
                  declare
                     Me : constant Vec3 := Lamps (I).P
                       + Vec3'(3.0 * Cos (Float (K) * 2.1), 0.0, 3.0 * Sin (Float (K) * 2.1));
                     Slot : Natural := 0;
                  begin
                     for J in Kids'Range loop
                        if Dist2 (Kids (J).Key, Me) < 0.01 then
                           Slot := J;
                        end if;
                     end loop;
                     if Slot = 0 then
                        for J in Kids'Range loop
                           if Kids (J).Key.Y < -100.0
                             or else Dist2 (Kids (J).Key, S.Listener) > 140.0 ** 2
                           then
                              Kids (J) := (Key => Me, Wait => 1.0 + 2.0 * Rnd, Throw => 0.0);
                              Slot := J;
                              exit;
                           end if;
                        end loop;
                     end if;
                     if Slot > 0 then
                        declare
                           Kd : Kid renames Kids (Slot);
                        begin
                           Kd.Throw := Float'Max (0.0, Kd.Throw - Dt);
                           Kd.Wait := Kd.Wait - Dt;
                           if Kd.Wait <= 0.0 then
                              Kd.Wait := 1.5 + 2.0 * Rnd;
                              Kd.Throw := 0.35;
                              for B of Balls loop
                                 if not B.Live then
                                    declare
                                       At_Car : constant Boolean := S.Driving
                                         and then Dist2 (S.Car_Pos, Me) < 18.0 ** 2 and then Rnd < 0.45;
                                       Other  : constant Vec3 := Lamps (I).P
                                         + Vec3'(3.0 * Cos (Float ((K + 1) mod 3) * 2.1), 0.0,
                                                 3.0 * Sin (Float ((K + 1) mod 3) * 2.1));
                                    begin
                                       B := (Live => True, From => Me + Vec3'(0.0, 1.0, 0.0),
                                             To => (if At_Car then S.Car_Pos + Vec3'(0.0, 1.2, 0.0)
                                                    else Other + Vec3'(0.0, 0.9, 0.0)),
                                             T => 0.0, Time => 0.7, At_Car => At_Car);
                                    end;
                                    exit;
                                 end if;
                              end loop;
                           end if;
                        end;
                     end if;
                  end;
               end loop;
            end if;
         end loop;
      end if;
      for B of Balls loop
         if B.Live then
            B.T := B.T + Dt;
            if B.T >= B.Time then
               B.Live := False;
               if B.At_Car and then Dist2 (S.Car_Pos, B.To) < 3.0 ** 2 then
                  Sound.Effect (Sound.Thud, 0.8, Side_Of (B.To));
               end if;
               for K in 1 .. 4 loop
                  Tyre_Effects.Add_Puff (B.To, (0.8 * Sym, 0.5, 0.8 * Sym), 0, 0.25, 0.8);
               end loop;
            end if;
         end if;
      end loop;

      --  the cat walks the railings, sits, and miaows now and then
      if Cat_Known then
         if Cat_Sit > 0.0 then
            Cat_Sit := Cat_Sit - Dt;
         else
            Cat_S := Cat_S + Cat_Dir * 0.35 * Dt;
            if Cat_S > Cat_To then
               Cat_Dir := -1.0;
            elsif Cat_S < Cat_From then
               Cat_Dir := 1.0;
            end if;
            if Rnd < Dt / 14.0 then
               Cat_Sit := 4.0 + 6.0 * Rnd;
            end if;
         end if;
         Cat_Meow := Cat_Meow - Dt;
         if Cat_Meow <= 0.0 then
            Cat_Meow := 20.0 + 40.0 * Rnd;
            declare
               D : constant Float := Length (Cat_Pos - S.Listener);
            begin
               if D < 40.0 then
                  Sound.Effect (Sound.Meow, Float'Min (1.0, 6.0 / (D + 1.0)), Side_Of (Cat_Pos));
               end if;
            end;
         end if;
      end if;

      --  the boats go up and down the Seine
      if Seine.N > 1 then
         if not Boats_Placed then
            Boats_Placed := True;
            for I in Boats'Range loop
               Boats (I) := (S => Length_Of (Seine) * (Float (I) - 0.5) / Float (Boats'Length),
                             Dir => (if I mod 2 = 0 then 1.0 else -1.0));
            end loop;
         end if;
         for B of Boats loop
            B.S := B.S + B.Dir * 3.5 * Dt;
            if B.S > Length_Of (Seine) - 30.0 then
               B.Dir := -1.0;
            elsif B.S < 30.0 then
               B.Dir := 1.0;
            end if;
         end loop;
      end if;

      --  the balloon goes up and down every ten minutes, in fair weather
      declare
         Phase : constant Float := (Clock + 250.0) - 600.0 * Float'Floor ((Clock + 250.0) / 600.0);
         Fair  : constant Boolean := Forced (Balloon_F)
           or else (S.Night < 0.5 and then S.Rain < 0.1 and then S.Snow < 0.1);
         Target : constant Float :=
           (if not Fair or else Phase < 120.0 then 0.0
            elsif Phase < 300.0 then 150.0 * (Phase - 120.0) / 180.0
            elsif Phase < 420.0 then 150.0
            else 150.0 * (600.0 - Phase) / 180.0);
      begin
         Balloon_Y := Balloon_Y + (Target - Balloon_Y) * Float'Min (1.0, Dt);
      end;

      --  the Little Prince's asteroid: on about one night in ten
      if S.Hour > 12.0 and then S.Hour < 21.0 then
         Rolled_Night := False;
         Asteroid_Tonight := False;
      elsif S.Night > 0.6 and then not Rolled_Night then
         Rolled_Night := True;
         Asteroid_Tonight := Rnd < 0.1;
      end if;

      --  the Phantom shows himself at the Opéra, with his organ
      if S.Night > 0.6 and then Length (Opera_Mask - S.Listener) < 180.0 then
         if Phantom_T = 0.0 or else Phantom_T >= 45.0 then
            Phantom_T := 0.001;
            Sound.Effect (Sound.Organ, Float'Min (1.0, 90.0 / (Length (Opera_Mask - S.Listener) + 20.0)),
                          Side_Of (Opera_Mask));
         else
            Phantom_T := Phantom_T + Dt;
         end if;
      elsif Forced (Phantom_F) then
         Phantom_T := 1.0;
      else
         Phantom_T := 0.0;
      end if;
   end Update;

   ---------------------------------------------------------------------------

   procedure Paint (C : Vec3) is
   begin
      if Locs.Cloth >= 0 then
         Shaders.Set (Locs.Cloth, C);
      end if;
   end Paint;

   function Near (P : Vec3; R : Float) return Boolean is (Dist2 (P, Now.Listener) < R * R);

   procedure Draw (Model, Paint_Loc, Skin, Legs : GL.GLint) is
      Skin_Tones : constant array (0 .. 3) of Vec3 :=
        ((0.86, 0.68, 0.56), (0.76, 0.57, 0.44), (0.58, 0.40, 0.29), (0.40, 0.27, 0.19));
   begin
      Locs := (Model, Paint_Loc, Skin, Legs);
      Figures.Set_Locations (Locs);

      --  the parade: marching units, tanks and trucks going down the avenue
      if Parade_Active then
         declare
            D : constant Vec3 := Normalize (Concorde - Arc);
            L : constant Float := Length (Concorde - Arc);
            H : constant Float := Heading_Of (D);
            R : constant Vec3 := Right_Of (D);
            Step : constant Float := 0.4 * Sin (Clock * 5.4);
         begin
            for U in 0 .. 23 loop
               declare
                  S0 : constant Float := Float (U) * 45.0 + Clock * 1.6;
                  S  : constant Float := S0 - L * Float'Floor (S0 / L);
                  P  : constant Vec3 := Arc + S * D;
               begin
                  if Near (P, 320.0) then
                     case U mod 6 is
                        when 2 =>
                           Paint ((0.36, 0.38, 0.26));
                           for Side of Float_Array'(-3.5, 3.5) loop
                              Shaders.Set (Model, Place (P + Side * R, H));
                              Meshes.Draw (Tank);
                           end loop;
                        when 4 =>
                           Paint ((0.36, 0.38, 0.26));
                           for Side of Float_Array'(-3.0, 3.0) loop
                              Shaders.Set (Model, Place (P + Side * R, H));
                              Meshes.Draw (Truck);
                           end loop;
                        when others =>
                           --  a block of soldiers in step
                           declare
                              Unit : constant Natural := (U / 6 + U) mod 3;
                              Coat : constant Vec3 := (case Unit is
                                 when 0 => (0.72, 0.62, 0.42),    --  the Légion: khaki
                                 when 1 => (0.08, 0.1, 0.22),     --  Saint-Cyr: dark blue
                                 when others => (0.1, 0.13, 0.25));  --  the pompiers
                              Trs : constant Vec3 := (case Unit is
                                 when 0 => (0.72, 0.62, 0.42), when 1 => (0.6, 0.06, 0.08),
                                 when others => (0.1, 0.13, 0.25));
                              Hat : constant Figures.Hat_Kind :=
                                (if Unit = 2 then Figures.Helmet else Figures.Kepi);
                              Hat_C : constant Vec3 := (case Unit is
                                 when 0 => (0.95, 0.95, 0.93), when 1 => (0.1, 0.1, 0.25),
                                 when others => (0.85, 0.7, 0.3));
                           begin
                              for Row in 0 .. 5 loop
                                 for Col in 0 .. 4 loop
                                    Figures.Person
                                      (Place (P - (Float (Row) * 1.6) * D + (Float (Col) * 1.3 - 2.6) * R, H),
                                       Coat, Skin_Tones (Pick (Hash (Float (Row), Float (Col + U)), 4)),
                                       Trs, Stride => Step, Hat => Hat, Hat_Colour => Hat_C);
                                 end loop;
                              end loop;
                           end;
                     end case;
                  end if;
               end;
            end loop;
         end;
      end if;

      --  the jets
      if Jets_On then
         Paint ((0.1, 0.18, 0.55));
         for I in Formation'Range loop
            Shaders.Set (Model, Place (Jet_Pos (I), Heading_Of (Concorde - Arc)));
            Meshes.Draw (Jet);
         end loop;
      end if;

      --  the Tour de France: round and round the Champs-Élysées
      if Tour_Active then
         declare
            D : constant Vec3 := Normalize (Concorde - Arc);
            L : constant Float := Length (Concorde - Arc);
            R : constant Vec3 := Right_Of (D);
            Teams : constant array (0 .. 7) of Vec3 :=
              ((0.9, 0.1, 0.1), (0.1, 0.3, 0.8), (0.1, 0.55, 0.3), (0.95, 0.5, 0.1),
               (0.15, 0.15, 0.15), (0.6, 0.1, 0.6), (0.1, 0.7, 0.8), (0.95, 0.95, 0.95));
            Lead : constant Float := 560.0 + Clock * 13.0;
         begin
            for I in 0 .. 69 loop
               declare
                  Behind : constant Float :=
                    (if I < 4 then -180.0 - 4.0 * Float (I)
                     else Float ((I - 4) / 6) * 3.4 + 2.0 * Hash (Float (I), 1.0));
                  U0 : constant Float := Lead - Behind;
                  U  : constant Float := U0 - 2.0 * L * Float'Floor (U0 / (2.0 * L));
                  Lane : constant Float := 6.0 + Float ((I - 4) mod 6) * 1.1
                    + 0.5 * Sin (Clock * 0.7 + Float (I));
                  P  : constant Vec3 := (if U < L then Arc + U * D + Lane * R
                                         else Concorde - (U - L) * D - Lane * R);
                  H  : constant Float := Heading_Of ((if U < L then D else (-1.0) * D));
                  Jersey : constant Vec3 :=
                    (if I = 4 then (1.0, 0.85, 0.1)          --  the yellow jersey
                     elsif I = 5 then (0.1, 0.7, 0.2)        --  the green one
                     else Teams (Pick (Hash (Float (I), 3.0), 8)));
               begin
                  if Near (P, 350.0) then
                     Figures.Cyclist (Place (P, H), Jersey,
                                      Skin_Tones (I mod 4), Clock * 9.0 + Float (I));
                  end if;
               end;
            end loop;
         end;
      end if;

      --  street musicians
      Drawn_Musicians := 0;
      if Music_On then
         for I in 1 .. Lamp_Count loop
            if Musician_At (I) and then Near (Lamps (I).P, 120.0) then
               declare
                  P    : constant Vec3 := Lamps (I).P + Vec3'(0.9, 0.0, 0.6);
                  Tune : constant Natural := 1 + Natural (Float'Floor (Hash (Lamps (I).P.Z, Lamps (I).P.X) * 4.99));
                  Prop : constant Figures.Prop_Kind :=
                    (case Tune is when 2 => Figures.Guitar, when 3 => Figures.Violin,
                                  when 5 => Figures.Drum, when others => Figures.Accordion);
               begin
                  Drawn_Musicians := Drawn_Musicians + 1;
                  Last_Musician := P;
                  Figures.Person
                    (Place (P, Street_Heading (P) + 0.1 * Sin (Clock * 2.0 + Lamps (I).H * 9.0)),
                     (0.2 + 0.6 * Lamps (I).H, 0.3, 0.5 - 0.3 * Lamps (I).H),
                     Skin_Tones (Natural (Lamps (I).H * 37.0) mod 4), (0.15, 0.15, 0.2),
                     Hat => (if Tune = 1 then Figures.Cap else Figures.None),
                     Hat_Colour => (0.1, 0.1, 0.1), Prop => Prop);
               end;
            end if;
         end loop;
      end if;

      --  Paris-Plages
      if Plages_On and then Beach.N > 1 and then Near (Beach.P (Beach.N / 2), 700.0) then
         Shaders.Set (Model, Identity);
         Meshes.Draw (Beach_Plain);
         for C in Beach_Colour'Range loop
            Paint (Beach_Tint (C));
            Shaders.Set (Model, Identity);
            Meshes.Draw (Beach_Colour (C));
         end loop;
         if Now.Night < 0.5 then
            for I in 1 .. Chair_Count loop
               declare
                  C : Chair renames Chairs (I);
               begin
                  if C.Sunbather and then Near (C.P, 250.0) then
                     Figures.Person
                       (Translation (C.P) * Rotation_Y (-C.H) * Rotation_X (-1.25)
                        * Translation ((0.0, -0.9, 0.0)),
                        C.Swimsuit, Skin_Tones (Pick (Hash (C.P.X, 7.0), 4)), C.Swimsuit);
                  end if;
               end;
            end loop;
         end if;
      end if;

      --  pigeons
      for F of Flocks loop
         if F.Key.Y > -100.0 and then F.Gone <= 0.0 and then Near (F.Key, 120.0) then
            for B of F.Birds loop
               Figures.Pigeon (Place (B.P, B.Yaw),
                               (if F.Flying >= 0.0 then 0.9 * Sin (Clock * 26.0 + B.Yaw * 5.0) else 0.0));
            end loop;
         end if;
      end loop;

      --  children and snowballs
      if Snowballs_On then
         for K of Kids loop
            if K.Key.Y > -100.0 and then Near (K.Key, 100.0) then
               declare
                  Coat : constant Vec3 := Beach_Tint (Pick (Hash (K.Key.X, K.Key.Z), 4));
               begin
                  Figures.Person (Place (K.Key, Hash (K.Key.Z, K.Key.X) * 6.3, 0.62),
                                  Coat, Skin_Tones (Pick (Hash (K.Key.X, 3.0), 4)),
                                  (0.15, 0.15, 0.25), Hat => Figures.Cap,
                                  Hat_Colour => (0.9, 0.2, 0.2),
                                  Arm_Up => (if K.Throw > 0.0 then -2.6 else 0.0));
               end;
            end if;
         end loop;
         for B of Balls loop
            if B.Live then
               declare
                  F : constant Float := B.T / B.Time;
               begin
                  Figures.Ball (B.From + F * (B.To - B.From) + Vec3'(0.0, 2.0 * F * (1.0 - F), 0.0), 0.08);
               end;
            end if;
         end loop;
      end if;

      --  the cat
      if Cat_Known and then Near (Cat_Pos, 90.0) then
         Figures.Cat (Place (Cat_Pos, Heading_Of (Cat_Dir * Cat_Along)),
                      (if Cat_Sit > 0.0 then 0.0 else Sin (Clock * 8.0)), Cat_Sit > 0.0);
      end if;

      --  the boats
      if Seine.N > 1 then
         Paint ((0.12, 0.17, 0.32));
         for B of Boats loop
            declare
               P, D : Vec3;
            begin
               Boat_At (B, P, D);
               if Near (P, 1500.0) then
                  Shaders.Set (Model, Place (P, Heading_Of (D)));
                  Meshes.Draw (Boat);
               end if;
            end;
         end loop;
      end if;

      --  the balloon
      if Near (Balloon_Pos, 3000.0) then
         Paint ((0.1, 0.5, 0.3));
         Shaders.Set (Model, Translation (Balloon_Pos));
         Meshes.Draw (Balloon_M);
         if Balloon_Y > 0.5 then
            declare
               M : Mat4 := Translation ((Balloon_Pos.X, 0.0, Balloon_Pos.Z));
            begin
               M (5) := Balloon_Y + 1.0;
               Shaders.Set (Model, M);
               Meshes.Draw (Cable);
            end;
         end if;
      end if;

      --  the Little Prince
      if (Asteroid_Tonight and then Now.Night > 0.6) or else Forced (Asteroid_F) then
         declare
            A : constant Vec3 := Asteroid_Pos;
            Spin : constant Float := Clock * 0.05;
         begin
            Shaders.Set (Model, Translation (A) * Rotation_Y (Spin) * Place ((0.0, 0.0, 0.0), 0.0, 2.0));
            Meshes.Draw (Asteroid_M);
            Figures.Person (Translation (A) * Rotation_Y (Spin)
                            * Place ((0.0, 59.0, 0.0), 2.4, 18.0),
                            (0.25, 0.6, 0.3), (0.95, 0.8, 0.7), (0.25, 0.6, 0.3),
                            Hat => Figures.Cap, Hat_Colour => (1.0, 0.85, 0.3));
         end;
      end if;

      --  the Phantom of the Opera
      if Phantom_T > 0.0 and then Phantom_T < 10.0 then
         --  a big pale mask, looking out of the façade over the square
         Shaders.Set (Model, Translation (Opera_Mask) * Place ((0.0, 0.0, 0.0), 0.0, 14.0));
         Meshes.Draw (Mask);
      end if;
   end Draw;

   procedure Draw_Lights (VP : Mat4; Cam : Vec3) is
   begin
      --  the boats' floodlights on the quays at night
      if Seine.N > 1 and then Now.Night > 0.3 then
         for B of Boats loop
            declare
               P, D : Vec3;
            begin
               Boat_At (B, P, D);
               if Dist2 (P, Cam) < 1200.0 ** 2 then
                  for Side of Float_Array'(-1.0, 1.0) loop
                     Beacon.Draw_Shaft (VP, Cam, P + (3.3 * Side) * Right_Of (D) + Vec3'(0.0, 1.6, 0.0),
                                        P + (30.0 * Side) * Right_Of (D) + Vec3'(0.0, 7.0, 0.0),
                                        1.2, 10.0, (1.0, 0.9, 0.7), 0.35 * Now.Night);
                  end loop;
               end if;
            end;
         end loop;
      end if;
   end Draw_Lights;

   function Kids_Report return String is
      N : Natural := 0;
      Best : Vec3 := (0.0, 0.0, 0.0);
      D : Float := Float'Last;
      B : Natural := 0;
   begin
      for K of Kids loop
         if K.Key.Y > -100.0 then
            N := N + 1;
            if Dist2 (K.Key, Now.Car_Pos) < D then
               D := Dist2 (K.Key, Now.Car_Pos);
               Best := K.Key - Now.Car_Pos;
            end if;
         end if;
      end loop;
      for Bl of Balls loop
         if Bl.Live then
            B := B + 1;
         end if;
      end loop;
      return "kids" & N'Image & " balls" & B'Image & " snow " & Boolean'Image (Snowballs_On)
        & " nearest kid" & Integer'Image (Integer (Best.X)) & Integer'Image (Integer (Best.Z));
   end Kids_Report;

   function Report return String is
      Musicians, Birds_Near : Natural := 0;
      Best_M, Best_F : Vec3 := (0.0, 0.0, 0.0);
      DM, DF : Float := Float'Last;
   begin
      for I in 1 .. Lamp_Count loop
         if Musician_At (I) then
            Musicians := Musicians + 1;
            if Dist2 (Lamps (I).P, Now.Listener) < DM then
               DM := Dist2 (Lamps (I).P, Now.Listener);
               Best_M := Lamps (I).P - Now.Listener;
            end if;
         end if;
      end loop;
      for F of Flocks loop
         if F.Key.Y > -100.0 then
            Birds_Near := Birds_Near + 1;
            if Dist2 (F.Key, Now.Car_Pos) < DF then
               DF := Dist2 (F.Key, Now.Car_Pos);
               Best_F := F.Key - Now.Car_Pos;
            end if;
         end if;
      end loop;
      return Kids_Report & " cat " & Boolean'Image (Cat_Known) & Integer'Image (Integer (Cat_Pos.X))
        & Integer'Image (Integer (Cat_Pos.Y)) & Integer'Image (Integer (Cat_Pos.Z))
        & " out" & Integer'Image (Integer (Cat_Out.X * 100.0)) & Integer'Image (Integer (Cat_Out.Z * 100.0))
        & " beach" & Beach.N'Image & Integer'Image (Integer (Length_Of (Beach))) & " m, chairs"
        & Chair_Count'Image & " first" & Integer'Image (Integer (Beach.P (1).X))
        & Integer'Image (Integer (Beach.P (1).Y)) & Integer'Image (Integer (Beach.P (1).Z))
        & " seine" & Seine.N'Image & "  drawn" & Drawn_Musicians'Image & " at" & Integer'Image (Integer (Last_Musician.X))
        & Integer'Image (Integer (Last_Musician.Y)) & Integer'Image (Integer (Last_Musician.Z))
        & " music " & Boolean'Image (Music_On) & " pigeons " & Boolean'Image (Pigeons_On)
        & " hour" & Integer'Image (Integer (Now.Hour)) & " lamps" & Lamp_Count'Image & " musicians" & Musicians'Image
        & " nearest" & Integer'Image (Integer (Best_M.X)) & Integer'Image (Integer (Best_M.Z))
        & "  flocks" & Birds_Near'Image
        & " nearest" & Integer'Image (Integer (Best_F.X)) & Integer'Image (Integer (Best_F.Z));
   end Report;

   function Jets return Float is (Jets_Level);
   function Crowd return Float is (Crowd_Level);
   function Busker return Natural is (Busker_Tune);
   function Busker_Level return Float is (Busker_Loud);
   function Busker_Pan return Float is (Busker_Side);

end Surprises;
