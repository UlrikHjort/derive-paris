--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;

with Beacon;
with Figures;
with Geo;
with Meshes;
with River;
with Road_Network;
with Shaders;
with Terrain;

package body Boats is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Pi : constant := Ada.Numerics.Pi;

   type Float_List is array (Positive range <>) of Float;

   Mat_Paint : constant := 15.0;   --  uCarColor
   Mat_Glass : constant := 16.0;
   Mat_Black : constant := 17.0;
   Mat_Lamp  : constant := 18.0;
   Mat_Red   : constant := 86.0;
   Mat_White : constant := 39.0;
   Mat_Glow  : constant := 41.0;   --  dark by day, warm light at night
   Mat_Wood  : constant := 13.0;
   Mat_Sand  : constant := 84.0;
   Mat_Iron  : constant := 26.0;

   type Kind_T is (Mouche, Peniche);

   type Boat is record
      Kind  : Kind_T := Mouche;
      S     : Float := 0.0;    --  metres along the river from Austerlitz
      Dir   : Float := 1.0;    --  +1 downstream, -1 up
      Speed : Float := 4.0;
      Seed  : Float := 0.0;
      Wait  : Float := 0.0;    --  turning round at the end of its run
   end record;

   Fleet : array (1 .. 18) of Boat;
   Placed : Boolean := False;
   Len : Float := 0.0;

   Mouche_M, Peniche_M, Cargo_M, Sign_M : Meshes.Mesh;
   Built : Boolean := False;

   Ridden : Natural := 0;          --  the boat you are on (0: none)
   Clock  : Float := 0.0;

   --  where the bateaux-mouches land: the Port de la Conférence, upstream of
   --  the Pont de l'Alma, on the right bank
   Landing_Lat : constant := 48.864020;
   Landing_Lon : constant := 2.302300;
   Land_X, Land_Z : Float := 0.0;
   Land_Known : Boolean := False;

   procedure Find_Landing is
      X, Z : Long_Float;
   begin
      if not Land_Known then
         Geo.To_Local (Landing_Lat, Landing_Lon, X, Z);
         Land_X := Float (X);
         Land_Z := Float (Z);
         Land_Known := True;
      end if;
   end Find_Landing;

   procedure Landing (X, Z : out Float) is
   begin
      Find_Landing;
      X := Land_X;
      Z := Land_Z;
   end Landing;

   --  Where a boat is: the water under it, its way, and its right
   procedure Place (B : Boat; P, D : out Vec3) is
      X, Z, DX, DZ : Float;
   begin
      River.At_Distance (B.S, X, Z, DX, DZ);
      D := B.Dir * Vec3'(DX, 0.0, DZ);
      declare
         Right : constant Vec3 := (-D.Z, 0.0, D.X);
         --  keep to the right of the middle, the péniches a little further
         Off : constant Float := (if B.Kind = Peniche then 13.0 else 9.0);
         C : constant Vec3 := (X, 0.0, Z) + Off * Right;
      begin
         P := (C.X, Terrain.Height (C.X, C.Z) - River.Depth, C.Z);
      end;
   end Place;

   function Model_Of (B : Boat) return Mat4 is
      P, D : Vec3;
   begin
      Place (B, P, D);
      --  rocking gently on the water
      return Translation (P + Vec3'(0.0, 0.05 * Sin (Clock * 0.9 + B.Seed * 10.0), 0.0))
        * Rotation_Y (-Arctan (D.X, -D.Z))
        * Rotation_Z (0.012 * Sin (Clock * 0.7 + B.Seed * 7.0));
   end Model_Of;

   procedure Update (Dt : Float) is
   begin
      Clock := Clock + Dt;
      if not Placed then
         Len := River.Length;
         if Len < 100.0 then
            return;
         end if;
         for I in Fleet'Range loop
            declare
               M : constant Boolean := I <= 12;
            begin
               Fleet (I) := (Kind  => (if M then Mouche else Peniche),
                             S     => Len * (Float (I) - 0.3) / Float (Fleet'Length) + 40.0,
                             Dir   => (if I mod 2 = 0 then 1.0 else -1.0),
                             Speed => (if M then 4.2 else 2.6),
                             Seed  => Float (I) * 0.137,
                             Wait  => 0.0);
            end;
         end loop;
         Placed := True;
      end if;
      for B of Fleet loop
         if B.Wait > 0.0 then
            B.Wait := B.Wait - Dt;
         else
            B.S := B.S + B.Dir * B.Speed * Dt;
            if B.S > Len - 40.0 then
               B.Dir := -1.0;
               B.Wait := 20.0;
            elsif B.S < 40.0 then
               B.Dir := 1.0;
               B.Wait := 20.0;
            end if;
         end if;
      end loop;
   end Update;

   ---------------------------------------------------------------------------
   --  Shapes (front is -Z, the waterline at Y = 0)

   procedure Build is
      use Meshes;
   begin
      --  a bateau-mouche: a long hull with a pointed bow, a glazed cabin
      --  lit at night, the open upper deck with its rows of seats and a
      --  railing, floodlights along the sides
      Start;
      Box (-3.4, 3.4, -0.8, 0.9, -14.0, 16.0, Mat_Paint, Top_Inset_Front => 0.0);
      Box (-3.4, 3.4, -0.8, 0.9, -17.0, -14.0, Mat_Paint, Top_Inset_X => 2.9, Top_Inset_Back => 0.0);
      Box (-3.45, 3.45, 0.55, 0.75, -16.0, 16.0, Mat_White);                  --  the white band
      Box (-3.1, 3.1, 0.9, 2.6, -11.0, 13.0, Mat_Glow, Side_Mat => Mat_Glass); --  the cabin
      Box (-3.3, 3.3, 2.6, 2.75, -12.0, 14.0, Mat_White);                     --  the upper deck
      for Z of Float_List'(-11.0, 13.5) loop
         Box (-3.3, 3.3, 2.75, 3.6, Z, Z + 0.06, Mat_Iron);
      end loop;
      for Side of Float_List'(-1.0, 1.0) loop
         Box (Side * 3.3 - 0.03, Side * 3.3 + 0.03, 2.75, 3.6, -12.0, 14.0, Mat_Iron);   --  railing
         Box (Side * 3.3 - 0.03, Side * 3.3 + 0.03, 3.55, 3.65, -12.0, 14.0, Mat_Iron);
         for K in 0 .. 7 loop
            declare
               Z : constant Float := -9.0 + 3.0 * Float (K);
            begin
               Box (Side * 3.45 - 0.08, Side * 3.45 + 0.08, 1.9, 2.25, Z - 0.3, Z + 0.3, Mat_Lamp);   --  floodlights
            end;
         end loop;
      end loop;
      --  rows of benches on the deck
      for R in 0 .. 9 loop
         for Side of Float_List'(-1.0, 1.0) loop
            Box (Side * 0.4, Side * 2.9, 2.75, 3.15, -9.0 + 2.2 * Float (R), -8.5 + 2.2 * Float (R), Mat_Wood);
         end loop;
      end loop;
      --  the wheelhouse at the back of the deck
      Box (-1.2, 1.2, 2.75, 4.0, 12.0, 14.0, Mat_White, Top_Inset_Front => 0.3);
      Box (-1.22, 1.22, 3.2, 3.8, 11.95, 13.5, Mat_Glass);
      Finish (Mouche_M);

      --  a péniche: long and black, a red line, the wheelhouse at the stern
      --  and the hatch covers of the hold, a little car on the deck behind
      Start;
      Box (-2.55, 2.55, -1.6, 1.0, -18.0, 19.0, Mat_Black);
      Box (-2.55, 2.55, -1.6, 1.0, -20.0, -18.0, Mat_Black, Top_Inset_X => 2.0, Top_Inset_Back => 0.0);
      Box (-2.6, 2.6, 0.75, 0.95, -19.5, 19.0, Mat_Red);
      Box (-2.2, 2.2, 1.0, 1.9, -15.0, 11.0, Mat_Black);                       --  the hold's coaming
      Box (-1.7, 1.7, 2.0, 3.6, 14.0, 17.5, Mat_White);                        --  the wheelhouse
      Box (-1.72, 1.72, 2.8, 3.4, 14.0, 17.0, Mat_Glass);
      Box (-1.8, 1.8, 3.6, 3.75, 13.8, 17.7, Mat_Black);
      Box (-0.9, 0.9, 1.0, 2.0, 11.8, 13.6, Mat_Paint);                        --  the little car
      Box (-0.85, 0.85, 1.6, 2.0, 12.2, 13.2, Mat_Glass);
      for Z of Float_List'(-19.0, 18.6) loop                                    --  pots of flowers
         Box (-0.25, 0.25, 1.0, 1.4, Z, Z + 0.4, Mat_Red);
      end loop;
      Finish (Peniche_M);
      --  the cargo in the open hold: sand and gravel in heaps
      Start;
      for K in 0 .. 3 loop
         declare
            Z : constant Float := -13.5 + 6.2 * Float (K);
         begin
            Box (-2.0, 2.0, 1.0, 2.2, Z, Z + 5.6, Mat_Sand, Top_Inset_X => 1.2, Top_Inset_Front => 1.6,
                 Top_Inset_Back => 1.6);
         end;
      end loop;
      Finish (Cargo_M);

      --  the landing: a sign on a post (in the paint, blue) and a blue mark
      --  on the pavement to stand on
      Start;
      Box (-0.05, 0.05, 0.0, 2.6, -0.05, 0.05, Mat_Iron);
      Box (-0.7, 0.7, 2.6, 3.1, -0.04, 0.04, Mat_Paint);
      Box (-0.68, 0.68, 2.72, 2.98, -0.05, 0.05, Mat_White);
      Box (-0.9, 0.9, 0.0, 0.02, 0.6, 2.4, Mat_Paint);
      Finish (Sign_M);
      Built := True;
   end Build;

   ---------------------------------------------------------------------------

   Shirts : constant array (0 .. 7) of Vec3 :=
     ((0.8, 0.15, 0.15), (0.15, 0.3, 0.75), (0.9, 0.85, 0.75), (0.2, 0.5, 0.25),
      (0.9, 0.7, 0.15), (0.25, 0.25, 0.28), (0.95, 0.95, 0.92), (0.55, 0.3, 0.45));
   Skins : constant array (0 .. 3) of Vec3 :=
     ((0.86, 0.68, 0.56), (0.76, 0.57, 0.44), (0.58, 0.40, 0.29), (0.40, 0.27, 0.19));

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint; Cam : Vec3; Night : Float) is
      pragma Unreferenced (Night);
   begin
      if not Placed then
         return;
      end if;
      if not Built then
         Build;
      end if;
      Figures.Set_Locations ((Model, Paint, Skin, Legs));
      for I in Fleet'Range loop
         declare
            B : Boat renames Fleet (I);
            M : constant Mat4 := Model_Of (B);
            P, D : Vec3;
         begin
            Place (B, P, D);
            if (P.X - Cam.X) ** 2 + (P.Z - Cam.Z) ** 2 < 1500.0 ** 2 then
               case B.Kind is
                  when Mouche =>
                     Shaders.Set (Paint, (if I mod 3 = 0 then Vec3'(0.12, 0.17, 0.32)
                                          elsif I mod 3 = 1 then Vec3'(0.85, 0.85, 0.82)
                                          else Vec3'(0.1, 0.32, 0.45)));
                     Shaders.Set (Model, M);
                     Meshes.Draw (Mouche_M);
                     --  the passengers on the upper deck, when close
                     if (P.X - Cam.X) ** 2 + (P.Z - Cam.Z) ** 2 < 220.0 ** 2 then
                        for R in 0 .. 9 loop
                           for Seat in 0 .. 3 loop
                              declare
                                 H : constant Natural := (I * 31 + R * 7 + Seat * 3) mod 11;
                                 X : constant Float := (if Seat < 2 then -2.4 + 0.9 * Float (Seat)
                                                        else 0.9 + 0.9 * Float (Seat - 2));
                              begin
                                 if H < 7 and then not (I = Ridden and then R = 0 and then Seat = 2) then
                                    --  seated: a person sunk into the bench
                                    Figures.Person (M * Translation ((X, 2.75 - 0.45, -8.7 + 2.2 * Float (R)))
                                                    * Rotation_Y (Pi),
                                                    Shirts (H mod 8), Skins (H mod 4), (0.15, 0.17, 0.25),
                                                    Arm_Up => (if H = 2 then -1.4 else 0.0));
                                 end if;
                              end;
                           end loop;
                        end loop;
                     end if;
                  when Peniche =>
                     Shaders.Set (Paint, (if I mod 2 = 0 then Vec3'(0.6, 0.1, 0.1) else Vec3'(0.2, 0.3, 0.5)));
                     Shaders.Set (Model, M);
                     Meshes.Draw (Peniche_M);
                     if I mod 3 /= 1 then   --  some go empty, riding high
                        Meshes.Draw (Cargo_M);
                     end if;
               end case;
            end if;
         end;
      end loop;
      --  the landing
      Find_Landing;
      if (Land_X - Cam.X) ** 2 + (Land_Z - Cam.Z) ** 2 < 300.0 ** 2 then
         Shaders.Set (Paint, Vec3'(0.1, 0.25, 0.6));
         Shaders.Set (Model, Translation ((Land_X, Terrain.Height (Land_X, Land_Z), Land_Z)));
         Meshes.Draw (Sign_M);
      end if;
      Shaders.Set (Model, Identity);
   end Draw;

   procedure Draw_Lights (VP : Mat4; Cam : Vec3; Night : Float) is
   begin
      if not Placed or else Night < 0.3 then
         return;
      end if;
      for B of Fleet loop
         if B.Kind = Mouche then
            declare
               P, D : Vec3;
            begin
               Place (B, P, D);
               if (P.X - Cam.X) ** 2 + (P.Z - Cam.Z) ** 2 < 1200.0 ** 2 then
                  declare
                     Right : constant Vec3 := (-D.Z, 0.0, D.X);
                  begin
                     for Side of Float_List'(-1.0, 1.0) loop
                        Beacon.Draw_Shaft (VP, Cam, P + (3.5 * Side) * Right + Vec3'(0.0, 2.1, 0.0),
                                           P + (34.0 * Side) * Right + Vec3'(0.0, 11.0, 0.0),
                                           1.2, 10.0, (1.0, 0.9, 0.7), 0.35 * Night);
                     end loop;
                  end;
               end if;
            end;
         end if;
      end loop;
   end Draw_Lights;

   ---------------------------------------------------------------------------
   --  Riding

   function At_Landing (X, Z : Float) return Boolean is
   begin
      Find_Landing;
      return Ridden = 0 and then (X - Land_X) ** 2 + (Z - (Land_Z + 1.5)) ** 2 < 0.9 ** 2;
   end At_Landing;

   procedure Board is
      Here : Float;
      Best : Float := Float'Last;
   begin
      if not Placed then
         return;
      end if;
      Find_Landing;
      --  the nearest bateau-mouche is brought alongside, heading downstream
      --  towards the Eiffel Tower
      Here := River.Distance_Of (Land_X, Land_Z);
      for I in Fleet'Range loop
         if Fleet (I).Kind = Mouche and then abs (Fleet (I).S - Here) < Best then
            Best := abs (Fleet (I).S - Here);
            Ridden := I;
         end if;
      end loop;
      if Ridden /= 0 then
         Fleet (Ridden).S := Here;
         Fleet (Ridden).Dir := 1.0;
         Fleet (Ridden).Wait := 0.0;
      end if;
   end Board;

   function Riding return Boolean is (Ridden /= 0);

   procedure Ride_Eye (X, Z, Deck_Y, Heading : out Float) is
      P, D : Vec3;
   begin
      Place (Fleet (Ridden), P, D);
      declare
         Right : constant Vec3 := (-D.Z, 0.0, D.X);
         --  at the front of the upper deck, the passengers behind
         E : constant Vec3 := P + 10.8 * D + 0.6 * Right;
      begin
         X := E.X;
         Z := E.Z;
         Deck_Y := P.Y + 2.75;
         Heading := Arctan (D.X, -D.Z);
      end;
   end Ride_Eye;

   procedure Ashore (X, Z : out Float) is
      P, D : Vec3;
      Found : Boolean;
      RH : Float;
   begin
      Place (Fleet (Ridden), P, D);
      Ridden := 0;
      --  the quay road beside the boat
      Road_Network.Nearest_Road (P.X, P.Z, Found, X, Z, RH);
      if not Found then
         X := P.X;
         Z := P.Z;
      end if;
   end Ashore;

end Boats;
