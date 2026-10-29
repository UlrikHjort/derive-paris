--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Containers.Vectors;
with Ada.Environment_Variables;
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with Almanac;
with Figures;
with Geo;
with Meshes;
with Road_Network;
with Shaders;
with Terrain;

package body Match is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;
   use Ada.Strings.Unbounded;

   --  the middle of the stadium's ring (the building, from OpenStreetMap)
   Stadium_Lat : constant := 48.841465;
   Stadium_Lon : constant := 2.253029;
   Kick_Off    : constant := 21.0;

   Opponents : constant array (0 .. 7) of access constant String :=
     (new String'("Lyon"), new String'("Marseille"), new String'("Monaco"), new String'("Lille"),
      new String'("Rennes"), new String'("Nice"), new String'("Lens"), new String'("Nantes"));

   Placed : Boolean := False;
   Centre : Vec3 := (0.0, 0.0, 0.0);
   Now    : Float := 12.0;
   Closed : Boolean := False;
   Pending_News : Unbounded_String;
   Roar   : Float := 0.0;   --  a goal: the stadium erupts, then dies down

   type Seg is record
      W, Pos : Natural;
   end record;
   package Seg_Vectors is new Ada.Containers.Vectors (Positive, Seg);
   Shut : Seg_Vectors.Vector;

   --  the fans: on a street near the stadium, walking along it
   type Fan is record
      A, B  : Vec3;       --  their stretch of street, B the stadium's end
      Phase : Float;
      Shirt : Natural;
   end record;
   package Fan_Vectors is new Ada.Containers.Vectors (Positive, Fan);
   Fans : Fan_Vectors.Vector;

   Lights_M : Meshes.Mesh;
   Built : Boolean := False;

   function Day_Number return Integer is
     (Almanac.Year * 372 + Almanac.Month * 31 + Almanac.Day);

   --  Every other weekend, a match (the same days each year)
   function Match_Day return Boolean is
     (Ada.Environment_Variables.Exists ("PARIS_MATCH")
      or else ((Almanac.Saturday or else Almanac.Sunday)
               and then (Almanac.Month * 31 + Almanac.Day) / 7 mod 2 = 0
               and then Almanac.Month /= 6 and then Almanac.Month /= 7));

   function Opponent return String is (Opponents (Day_Number mod 8).all);

   --  how it ends, decided by the day: home goals, away goals
   procedure Score (Home, Away : out Natural) is
      H : constant Natural := ((Day_Number mod 10_007) * 7919) mod 101;
   begin
      Home := (H mod 4);
      Away := ((H / 4) mod 3);
      if H mod 5 /= 0 and then Home <= Away then
         Home := Away + 1;   --  mostly a home win
      end if;
   end Score;

   --  the goals' minutes in the match (seconds of game time are short:
   --  the match lasts from 21:00 to about 22:50)
   function Goal_Hour (K : Natural) return Float is
     (Kick_Off + 0.1 + 1.6 * Float ((Day_Number * (K + 3) * 37) mod 100) / 100.0);

   procedure Place is
      X, Z : Long_Float;
   begin
      if Placed then
         return;
      end if;
      Geo.To_Local (Stadium_Lat, Stadium_Lon, X, Z);
      Centre := (Float (X), Terrain.Height (Float (X), Float (Z)), Float (Z));
      Placed := True;
   end Place;

   function Before return Boolean is (Now >= 19.0 and then Now < Kick_Off);
   function During return Boolean is (Now >= Kick_Off and then Now < Kick_Off + 1.85);
   function After return Boolean is (Now >= Kick_Off + 1.85 and then Now < Kick_Off + 2.6);
   function On return Boolean is (Match_Day and then (Before or else During or else After));

   procedure Close_Streets is
      use Road_Network;
      procedure Visit (W, Pos : Natural; AX, AZ, BX, BZ : Float) is
         MX : constant Float := (AX + BX) / 2.0;
         MZ : constant Float := (AZ + BZ) / 2.0;
      begin
         if (MX - Centre.X) ** 2 + (MZ - Centre.Z) ** 2 < 150.0 ** 2 then
            Close (W, Pos);
            Shut.Append ((W, Pos));
         end if;
      end Visit;
      procedure Each is new For_Segment_Ids_Near (Visit);
   begin
      Each (Centre.X, Centre.Z, 160.0);
      Closed := True;
      Pending_News := To_Unbounded_String
        ("Match tonight at the Parc des Princes: the streets round it are closed");
   end Close_Streets;

   procedure Open_Streets is
   begin
      for S of Shut loop
         Road_Network.Reopen (S.W, S.Pos);
      end loop;
      Shut.Clear;
      Closed := False;
   end Open_Streets;

   procedure Find_Fans is
      use Road_Network;
   begin
      Fans.Clear;
      for K in 1 .. 60 loop
         declare
            Found : Boolean;
            W, Pos : Natural;
            R1 : constant Float := Float ((K * 7919) mod 997) / 997.0;
            R2 : constant Float := Float ((K * 104_729) mod 991) / 991.0;
            R3 : constant Float := Float ((K * 1_299_709) mod 983) / 983.0;
         begin
            Pick_Segment (Centre.X, Centre.Z, 90.0, 420.0, R1, R2, R3, Found, W, Pos);
            if Found then
               declare
                  P : constant Node := Point (W, Pos);
                  Q : constant Node := Point (W, Pos + 1);
                  A : Vec3 := (P.X, 0.0, P.Z);
                  B : Vec3 := (Q.X, 0.0, Q.Z);
                  Side : constant Float := Ways (W).Width / 2.0 - 1.0;
                  D : constant Vec3 := (if Length (B - A) > 0.1 then (1.0 / Length (B - A)) * (B - A)
                                        else Vec3'(1.0, 0.0, 0.0));
                  Off : constant Vec3 := (Side * (if K mod 2 = 0 then 1.0 else -1.0)) * Vec3'(-D.Z, 0.0, D.X);
               begin
                  if Length (A - Centre) < Length (B - Centre) then
                     declare
                        T : constant Vec3 := A;
                     begin
                        A := B;
                        B := T;
                     end;
                  end if;
                  for J in 0 .. 2 loop
                     Fans.Append ((A + Off + (0.8 * Float (J)) * D, B + Off + (0.8 * Float (J)) * D,
                                   Float (K * 3 + J) * 0.137, (K + J) mod 5));
                  end loop;
               end;
            end if;
         end;
      end loop;
   end Find_Fans;

   procedure Update (Dt, Hour : Float; Cam : Vec3) is
      pragma Unreferenced (Cam);
      Was : constant Float := Now;
   begin
      Now := Hour;
      Place;
      if not Road_Network.Loaded then
         return;
      end if;
      if On and then not Closed then
         Close_Streets;
         Find_Fans;
      elsif not On and then Closed then
         Open_Streets;
      end if;
      --  a goal for Paris: the stadium erupts
      Roar := Float'Max (0.0, Roar - Dt / 8.0);
      if Match_Day and then During then
         declare
            Home, Away : Natural;
         begin
            Score (Home, Away);
            for K in 0 .. Home - 1 loop
               if Was < Goal_Hour (K) and then Now >= Goal_Hour (K) then
                  Roar := 1.0;
               end if;
            end loop;
         end;
      end if;
   end Update;

   function News return String is
      N : constant String := To_String (Pending_News);
   begin
      Pending_News := Null_Unbounded_String;
      return N;
   end News;

   function Crowd (Listener : Vec3) return Float is
      D : Float;
   begin
      if not On then
         return 0.0;
      end if;
      D := Sqrt ((Listener.X - Centre.X) ** 2 + (Listener.Z - Centre.Z) ** 2);
      return Float'Max (0.0, 1.0 - D / 1200.0)
        * (if During then 0.45 + 0.55 * Roar else 0.25);
   end Crowd;

   function Radio_Line (French : Boolean) return String is
      Home, Away : Natural;
      function Img (N : Natural) return String is
        (Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Left));
   begin
      if not Match_Day or else Now < 12.0 then
         return "";
      end if;
      Score (Home, Away);
      if Now < Kick_Off then
         return (if French then "Ce soir à 21 h au Parc des Princes : Paris contre " & Opponent & "."
                 else "Tonight at 9 at the Parc des Princes: Paris against " & Opponent & ".");
      elsif Now < Kick_Off + 1.85 then
         return (if French then "En direct du Parc des Princes : Paris - " & Opponent & ", le match est en cours."
                 else "Live from the Parc des Princes: Paris - " & Opponent & ", the match is on.");
      end if;
      return (if French then
                (if Home > Away then "Victoire de Paris contre " & Opponent & ", " & Img (Home) & " à " & Img (Away) & " !"
                 elsif Home = Away then "Match nul entre Paris et " & Opponent & ", " & Img (Home) & " partout."
                 else "Défaite de Paris contre " & Opponent & ", " & Img (Home) & " à " & Img (Away) & ".")
              else
                (if Home > Away then "Paris beat " & Opponent & ", " & Img (Home) & "-" & Img (Away) & "!"
                 elsif Home = Away then "Paris and " & Opponent & " draw, " & Img (Home) & "-" & Img (Away) & "."
                 else "Paris lose to " & Opponent & ", " & Img (Home) & "-" & Img (Away) & "."));
   end Radio_Line;

   procedure Build is
      use Meshes;
   begin
      --  the floodlights along the inner rim of the roof (48 m up), all
      --  round, facing in
      Start;
      for K in 0 .. 47 loop
         declare
            A : constant Float := 2.0 * Ada.Numerics.Pi * Float (K) / 48.0;
            X : constant Float := 80.0 * Cos (A);
            Z : constant Float := 88.0 * Sin (A);
         begin
            Box (X - 1.5, X + 1.5, 47.0, 49.0, Z - 1.5, Z + 1.5, 50.0);
         end;
      end loop;
      Finish (Lights_M);
      Built := True;
   end Build;

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint; Cam : Vec3; Time : Float) is
   begin
      if not On then
         return;
      end if;
      Place;
      if not Built then
         Build;
      end if;
      --  the lights: seen from far over the roofs
      Shaders.Set (Skin, Vec3'(1.0, 1.0, 0.95));
      Shaders.Set (Model, Translation (Centre));
      Meshes.Draw (Lights_M);
      Shaders.Set (Model, Identity);
      --  the fans, walking to the stadium before, away after (none
      --  outside while it is played)
      if During or else (Cam.X - Centre.X) ** 2 + (Cam.Z - Centre.Z) ** 2 > 700.0 ** 2 then
         return;
      end if;
      Figures.Set_Locations ((Model, Paint, Skin, Legs));
      for F of Fans loop
         declare
            Len : constant Float := Float'Max (0.1, Length (F.B - F.A));
            U   : Float := (Time * 1.3 / Len + F.Phase);
            P   : Vec3;
            Dir : Vec3 := (1.0 / Len) * (F.B - F.A);
         begin
            U := U - Float'Floor (U);
            if After then
               U := 1.0 - U;
               Dir := (-1.0) * Dir;
            end if;
            P := F.A + (U * Len) * ((1.0 / Len) * (F.B - F.A));
            Figures.Person
              (Translation ((P.X, Terrain.Height (P.X, P.Z), P.Z)) * Rotation_Y (-Arctan (Dir.X, -Dir.Z)),
               (case F.Shirt is
                   when 0 | 1 => (0.05, 0.12, 0.38), when 2 => (0.75, 0.08, 0.1),
                   when 3 => (0.95, 0.95, 0.95), when others => (0.12, 0.12, 0.14)),
               (0.8, 0.62, 0.5), (0.12, 0.12, 0.16),
               Stride => 0.5 * Sin (Time * 7.0 + F.Phase * 10.0),
               Hat => (if F.Shirt = 2 then Figures.Cap else Figures.None),
               Hat_Colour => (0.05, 0.12, 0.38),
               Arm_Up => (if F.Shirt = 4 then -2.6 else 0.0));
         end;
      end loop;
   end Draw;

end Match;
