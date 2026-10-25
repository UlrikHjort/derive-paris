--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Environment_Variables;
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with Ada.Text_IO;

with Figures;
with Geo;
with Meshes;
with Road_Network;
with Shaders;
with Terrain;
with Notes;

package body Closures is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;
   use Road_Network;

   Pi : constant := Ada.Numerics.Pi;

   type Float_List is array (Positive range <>) of Float;

   Mat_Paint  : constant := 15.0;   --  uCarColor
   Mat_Glass  : constant := 16.0;
   Mat_Tyre   : constant := 17.0;
   Mat_White  : constant := 39.0;
   Mat_Iron   : constant := 26.0;
   Mat_Lamp   : constant := 50.0;   --  uExtraColor, lit
   Mat_Dark   : constant := 70.0;
   Mat_Earth  : constant := 84.0;
   Mat_Cone   : constant := 85.0;
   Mat_Red    : constant := 86.0;

   type Kind_T is (Works, Accident, Demo);

   Max_Segs : constant := 10;
   type Seg_List is array (1 .. Max_Segs) of Natural;

   type Event is record
      Active : Boolean := False;
      Kind   : Kind_T := Works;
      W      : Natural := 0;
      Segs   : Seg_List := (others => 0);
      N      : Natural := 0;           --  segments closed (Seg .. Seg + N - 1)
      A, B   : Vec3 := (0.0, 0.0, 0.0);   --  the ends of the closed stretch
      Width  : Float := 8.0;
      Life   : Float := 0.0;           --  seconds left (accident), or time walked (demo)
      Mesh   : Meshes.Mesh;
      Built  : Boolean := False;
      Seed   : Float := 0.0;
   end record;

   Events : array (1 .. 6) of Event;
   Gen    : Ada.Numerics.Float_Random.Generator;
   Seeded : Boolean := False;
   function Rnd return Float is (Ada.Numerics.Float_Random.Random (Gen));

   Next_Accident : Float := 120.0;   --  seconds until the next may happen
   Look_Again    : Float := 0.0;

   Car_Mesh, Van_Mesh, Banner_Mesh, Lights_Mesh : Meshes.Mesh;
   Shapes_Built : Boolean := False;

   function Test (Name : String) return Boolean is (Ada.Environment_Variables.Exists (Name));

   ---------------------------------------------------------------------------
   --  Closing and opening

   procedure Shut (E : in out Event) is
   begin
      for I in 1 .. E.N loop
         Close (E.W, E.Segs (I));
      end loop;
   end Shut;

   procedure Finish (E : in out Event) is
   begin
      if E.Active then
         for I in 1 .. E.N loop
            Reopen (E.W, E.Segs (I));
         end loop;
         if E.Built then
            Meshes.Free (E.Mesh);
            E.Built := False;
         end if;
         E.Active := False;
      end if;
   end Finish;

   procedure Clear is
   begin
      for E of Events loop
         Finish (E);
      end loop;
   end Clear;

   function Count (K : Kind_T) return Natural is
      N : Natural := 0;
   begin
      for E of Events loop
         if E.Active and then E.Kind = K then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Count;

   --  Find a street segment between Near and Far from the focus, out of
   --  sight ahead, at least Min_W wide and Min_L long, not near another
   --  closure; Wide: a boulevard for a demonstration
   procedure Find_Place (FX, FZ, Heading, Near, Far, Min_W, Min_L : Float;
                         Found : out Boolean; W, Seg : out Natural; Ahead : Boolean := False) is
      Seen : Natural := 0;
      procedure Visit (VW, VS : Natural; AX, AZ, BX, BZ : Float) is
         MX : constant Float := (AX + BX) / 2.0;
         MZ : constant Float := (AZ + BZ) / 2.0;
         D  : constant Float := Sqrt ((MX - FX) ** 2 + (MZ - FZ) ** 2);
         L  : constant Float := Sqrt ((BX - AX) ** 2 + (BZ - AZ) ** 2);
         Ok : Boolean := D > Near and then D < Far and then L >= Min_L
           and then Ways (VW).Width >= Min_W
           and then Ada.Strings.Unbounded.Length (Ways (VW).Name) > 0
           and then not Is_Closed (VW, VS);
      begin
         if Ahead then
            --  (testing) right ahead, along the way you look
            declare
               Fwd_A : constant Float := (AX - FX) * Sin (Heading) - (AZ - FZ) * Cos (Heading);
               Fwd_B : constant Float := (BX - FX) * Sin (Heading) - (BZ - FZ) * Cos (Heading);
            begin
               Ok := Ok and then ((MX - FX) * Sin (Heading) - (MZ - FZ) * Cos (Heading)) / D > 0.95
                 and then Float'Min (Fwd_A, Fwd_B) > 15.0;
            end;
         elsif Ok and then D < 250.0
           and then ((MX - FX) * Sin (Heading) - (MZ - FZ) * Cos (Heading)) / D > 0.5
         then
            Ok := False;   --  right before the driver's eyes
         end if;
         if Ok then
            for E of Events loop
               if E.Active and then (E.A.X - MX) ** 2 + (E.A.Z - MZ) ** 2 < 120.0 ** 2 then
                  Ok := False;
               end if;
            end loop;
         end if;
         if Ok then
            --  pick one of them all, evenly (reservoir)
            Seen := Seen + 1;
            if Rnd * Float (Seen) < 1.0 then
               W := VW;
               Seg := VS;
            end if;
         end if;
      end Visit;
      procedure Each is new For_Segment_Ids_Near (Visit);
   begin
      W := 0;
      Seg := 0;
      Each (FX, FZ, Far);
      Found := Seen > 0;
   end Find_Place;

   procedure Begin_Event (K : Kind_T; W, Seg : Natural; Life : Float) is
   begin
      for E of Events loop
         if not E.Active then
            E := (Active => True, Kind => K, W => W, Width => Ways (W).Width, Life => Life,
                  Seed => Rnd, others => <>);
            --  one segment, or (a march) a few along the same way
            if K = Demo then
               for S in Integer'Max (0, Seg - 4) .. Natural'Min (Ways (W).Count - 2, Seg + 4) loop
                  if E.N < Max_Segs then
                     E.N := E.N + 1;
                     E.Segs (E.N) := S;
                  end if;
               end loop;
            else
               E.N := 1;
               E.Segs (1) := Seg;
            end if;
            declare
               P : constant Node := Point (W, E.Segs (1));
               Q : constant Node := Point (W, E.Segs (E.N) + 1);
            begin
               E.A := (P.X, Terrain.Height (P.X, P.Z), P.Z);
               E.B := (Q.X, Terrain.Height (Q.X, Q.Z), Q.Z);
            end;
            Shut (E);
            declare
               Lat, Lon : Long_Float;
            begin
               Geo.To_Lat_Lon (Long_Float (E.A.X), Long_Float (E.A.Z), Lat, Lon);
               Notes.Say ("Closed for " & (case K is when Works => "roadworks",
                                                      when Accident => "an accident",
                                                      when Demo => "a demonstration")
                                     & ": " & Ada.Strings.Unbounded.To_String (Ways (W).Name)
                                     & Long_Float'Image (Lat) & Long_Float'Image (Lon));
            end;
            return;
         end if;
      end loop;
   end Begin_Event;

   procedure Update (Dt : Float; Hour : Float; Saturday : Boolean; Focus_X, Focus_Z, Heading : Float) is
      Found : Boolean;
      W, Seg : Natural;
   begin
      if not Loaded then
         return;
      end if;
      if not Seeded then
         if Test ("PARIS_WORKS") or else Test ("PARIS_ACCIDENT") or else Test ("PARIS_DEMO") then
            Ada.Numerics.Float_Random.Reset (Gen, 7);   --  the same place each time (testing)
         else
            Ada.Numerics.Float_Random.Reset (Gen);
         end if;
         Seeded := True;
      end if;
      for E of Events loop
         if E.Active then
            --  far behind: open again
            if (E.A.X - Focus_X) ** 2 + (E.A.Z - Focus_Z) ** 2 > 900.0 ** 2 then
               Finish (E);
            elsif E.Kind = Accident then
               E.Life := E.Life - Dt;
               if E.Life <= 0.0 then
                  Finish (E);
               end if;
            elsif E.Kind = Demo then
               E.Life := E.Life + Dt;   --  how far they have walked
               if not ((Saturday and then Hour >= 14.0 and then Hour < 18.5) or else Test ("PARIS_DEMO")) then
                  Finish (E);
               end if;
            end if;
         end if;
      end loop;
      Next_Accident := Next_Accident - Dt;
      Look_Again := Look_Again - Dt;
      if Look_Again > 0.0 then
         return;
      end if;
      Look_Again := 2.0;
      --  test switches: one close by, ahead
      if Test ("PARIS_WORKS") and then Count (Works) = 0 then
         Find_Place (Focus_X, Focus_Z, Heading, 20.0, 90.0, 5.0, 15.0, Found, W, Seg, Ahead => True);
         if Found then
            Begin_Event (Works, W, Seg, 0.0);
         end if;
      end if;
      if Test ("PARIS_ACCIDENT") and then Count (Accident) = 0 then
         Find_Place (Focus_X, Focus_Z, Heading, 20.0, 90.0, 5.0, 15.0, Found, W, Seg, Ahead => True);
         if Found then
            Begin_Event (Accident, W, Seg, 600.0);
         end if;
      end if;
      if Test ("PARIS_DEMO") and then Count (Demo) = 0 then
         declare
            V  : constant String := Ada.Environment_Variables.Value ("PARIS_DEMO");
            Sp : constant Natural := Ada.Strings.Fixed.Index (V, " ");
            X, Z : Long_Float;
         begin
            if Sp > 0 then   --  "lat lon": the wide street nearest there
               Geo.To_Local (Long_Float'Value (V (V'First .. Sp - 1)), Long_Float'Value (V (Sp + 1 .. V'Last)),
                             X, Z);
               Find_Place (Float (X), Float (Z), Heading, 0.0, 80.0, 12.0, 15.0, Found, W, Seg);
               if Found then
                  Begin_Event (Demo, W, Seg, 0.0);
               end if;
            end if;
         end;
      end if;
      if Test ("PARIS_DEMO") and then Count (Demo) = 0 then
         Find_Place (Focus_X, Focus_Z, Heading, 30.0, 250.0, 12.0, 15.0, Found, W, Seg, Ahead => True);
         if not Found then   --  no boulevard ahead: the nearest wide street
            Find_Place (Focus_X, Focus_Z, Heading + Pi, 30.0, 500.0, 12.0, 15.0, Found, W, Seg);
         end if;
         if Found then
            Begin_Event (Demo, W, Seg, 0.0);
         end if;
      end if;
      --  roadworks: about three around you
      if Count (Works) < 3 then
         Find_Place (Focus_X, Focus_Z, Heading, 150.0, 550.0, 6.0, 25.0, Found, W, Seg);
         if Found then
            Begin_Event (Works, W, Seg, 0.0);
         end if;
      end if;
      --  an accident now and then, for a few minutes
      if Count (Accident) = 0 and then Next_Accident <= 0.0 then
         Next_Accident := 300.0 + 400.0 * Rnd;
         Find_Place (Focus_X, Focus_Z, Heading, 150.0, 450.0, 7.0, 20.0, Found, W, Seg);
         if Found then
            Begin_Event (Accident, W, Seg, 180.0 + 120.0 * Rnd);
         end if;
      end if;
      --  Saturday afternoon: a march on a boulevard
      if Saturday and then Hour >= 14.0 and then Hour < 18.0 and then Count (Demo) = 0 then
         Find_Place (Focus_X, Focus_Z, Heading, 200.0, 600.0, 12.0, 25.0, Found, W, Seg);
         if Found then
            Begin_Event (Demo, W, Seg, 0.0);
         end if;
      end if;
   end Update;

   ---------------------------------------------------------------------------
   --  Shapes

   procedure Quad2 (A, B, C, D : Vec3; Mat : Float) is
   begin
      Meshes.Quad (A, B, C, D, Mat);
      Meshes.Quad (D, C, B, A, Mat);
   end Quad2;

   --  a box along U (length), V (width), up; centre C on the ground
   procedure OBox (C, U, V : Vec3; HU, HV, Y0, Y1 : Float; Mat : Float) is
      function K (SU, SV, Y : Float) return Vec3 is (C + SU * HU * U + SV * HV * V + Vec3'(0.0, Y, 0.0));
   begin
      Quad2 (K (-1.0, -1.0, Y0), K (1.0, -1.0, Y0), K (1.0, -1.0, Y1), K (-1.0, -1.0, Y1), Mat);
      Quad2 (K (-1.0, 1.0, Y0), K (1.0, 1.0, Y0), K (1.0, 1.0, Y1), K (-1.0, 1.0, Y1), Mat);
      Quad2 (K (-1.0, -1.0, Y0), K (-1.0, 1.0, Y0), K (-1.0, 1.0, Y1), K (-1.0, -1.0, Y1), Mat);
      Quad2 (K (1.0, -1.0, Y0), K (1.0, 1.0, Y0), K (1.0, 1.0, Y1), K (1.0, -1.0, Y1), Mat);
      Quad2 (K (-1.0, -1.0, Y1), K (1.0, -1.0, Y1), K (1.0, 1.0, Y1), K (-1.0, 1.0, Y1), Mat);
   end OBox;

   --  a barrier across the road at P (D: along the road), red and white
   procedure Barrier (P, D : Vec3; Half : Float) is
      N : constant Vec3 := (-D.Z, 0.0, D.X);
      Pieces : constant Positive := Positive'Max (1, Integer (Float'Ceiling (2.0 * Half / 2.0)));
   begin
      for K in 0 .. Pieces - 1 loop
         declare
            S0 : constant Float := -Half + 2.0 * Half * Float (K) / Float (Pieces);
            S1 : constant Float := -Half + 2.0 * Half * Float (K + 1) / Float (Pieces);
            A  : constant Vec3 := P + S0 * N;
            B  : constant Vec3 := P + S1 * N;
            YA : constant Float := Terrain.Height (A.X, A.Z);
            YB : constant Float := Terrain.Height (B.X, B.Z);
         begin
            for Foot of Float_List'(0.1, 0.9) loop
               declare
                  F : constant Vec3 := A + Foot * (B - A);
                  YF : constant Float := Terrain.Height (F.X, F.Z);
               begin
                  Meshes.Box (F.X - 0.04, F.X + 0.04, YF, YF + 1.05, F.Z - 0.04, F.Z + 0.04, Mat_Iron);
                  OBox ((F.X, YF, F.Z), D, N, 0.3, 0.05, 0.0, 0.05, Mat_Iron);
               end;
            end loop;
            Quad2 ((A.X, YA + 0.5, A.Z), (B.X, YB + 0.5, B.Z), (B.X, YB + 1.0, B.Z), (A.X, YA + 1.0, A.Z),
                   (if K mod 2 = 0 then Mat_Red else Mat_White));
         end;
      end loop;
   end Barrier;

   --  the "travaux" sign: a white triangle in a red frame, a man digging
   procedure Works_Sign (P, Face : Vec3) is
      N  : constant Vec3 := (-Face.Z, 0.0, Face.X);
      Y  : constant Float := Terrain.Height (P.X, P.Z);
      B  : constant Vec3 := (P.X, Y, P.Z);
      Up : constant Vec3 := (0.0, 1.0, 0.0);
      function T (S, H : Float; Out_Off : Float := 0.0) return Vec3 is (B + S * N + H * Up + Out_Off * Face);
   begin
      Meshes.Box (P.X - 0.03, P.X + 0.03, Y, Y + 1.3, P.Z - 0.03, P.Z + 0.03, Mat_Iron);
      Meshes.Quad (T (-0.45, 1.25, 0.04), T (0.45, 1.25, 0.04), T (0.0, 2.03, 0.04), T (0.0, 2.03, 0.04), Mat_Red);
      Meshes.Quad (T (0.0, 2.03, 0.04), T (0.0, 2.03, 0.04), T (0.45, 1.25, 0.04), T (-0.45, 1.25, 0.04), Mat_Red);
      Meshes.Quad (T (-0.33, 1.32, 0.05), T (0.33, 1.32, 0.05), T (0.0, 1.88, 0.05), T (0.0, 1.88, 0.05), Mat_White);
      Meshes.Quad (T (0.0, 1.88, 0.05), T (0.0, 1.88, 0.05), T (0.33, 1.32, 0.05), T (-0.33, 1.32, 0.05), Mat_White);
      --  the little man and his spade, and the heap
      Meshes.Quad (T (-0.04, 1.42, 0.06), T (0.04, 1.42, 0.06), T (0.06, 1.62, 0.06), T (-0.02, 1.62, 0.06), Mat_Tyre);
      Meshes.Quad (T (0.06, 1.62, 0.06), T (-0.02, 1.62, 0.06), T (-0.04, 1.42, 0.06), T (0.04, 1.42, 0.06), Mat_Tyre);
      Meshes.Quad (T (0.0, 1.64, 0.06), T (0.06, 1.64, 0.06), T (0.06, 1.7, 0.06), T (0.0, 1.7, 0.06), Mat_Tyre);
      Meshes.Quad (T (0.0, 1.7, 0.06), T (0.06, 1.7, 0.06), T (0.06, 1.64, 0.06), T (0.0, 1.64, 0.06), Mat_Tyre);
      Meshes.Quad (T (0.08, 1.38, 0.06), T (0.24, 1.38, 0.06), T (0.16, 1.47, 0.06), T (0.16, 1.47, 0.06), Mat_Tyre);
      Meshes.Quad (T (0.16, 1.47, 0.06), T (0.16, 1.47, 0.06), T (0.24, 1.38, 0.06), T (0.08, 1.38, 0.06), Mat_Tyre);
   end Works_Sign;

   procedure Cone (P : Vec3) is
      Y : constant Float := Terrain.Height (P.X, P.Z);
   begin
      Meshes.Box (P.X - 0.2, P.X + 0.2, Y, Y + 0.04, P.Z - 0.2, P.Z + 0.2, Mat_Tyre);
      Meshes.Box (P.X - 0.13, P.X + 0.13, Y + 0.04, Y + 0.7, P.Z - 0.13, P.Z + 0.13, Mat_Cone,
                  Top_Inset_X => 0.11, Top_Inset_Front => 0.11, Top_Inset_Back => 0.11);
   end Cone;

   procedure Build (E : in out Event) is
      D   : constant Vec3 := Normalize (Vec3'(E.B.X - E.A.X, 0.0, E.B.Z - E.A.Z));
      N   : constant Vec3 := (-D.Z, 0.0, D.X);
      L   : constant Float := Sqrt ((E.B.X - E.A.X) ** 2 + (E.B.Z - E.A.Z) ** 2);
      Half : constant Float := E.Width / 2.0 + 0.3;
      Mid : constant Vec3 := E.A + (0.5 * L) * D;
      In0 : constant Float := Float'Min (4.0, L / 4.0);   --  the barriers, a little inside
   begin
      Meshes.Start;
      Barrier (E.A + In0 * D, D, Half);
      Barrier (E.B - In0 * D, D, Half);
      case E.Kind is
         when Works =>
            Works_Sign (E.A - 3.0 * D + (Half - 0.6) * N, (-1.0) * D);
            Works_Sign (E.B + 3.0 * D - (Half - 0.6) * N, D);
            declare
               PL : constant Float := Float'Min (8.0, L / 3.0);   --  half the trench
               Y  : constant Float := Terrain.Height (Mid.X, Mid.Z);
               C  : constant Vec3 := (Mid.X, Y, Mid.Z);
               function G (U, V, H : Float) return Vec3 is (C + U * D + V * N + Vec3'(0.0, H, 0.0));
            begin
               --  the trench, its rim and the heap of earth beside it
               Meshes.Quad (G (-PL, -1.0, 0.03), G (PL, -1.0, 0.03), G (PL, 1.0, 0.03), G (-PL, 1.0, 0.03), Mat_Dark);
               Meshes.Quad (G (-PL, 1.0, 0.03), G (PL, 1.0, 0.03), G (PL, -1.0, 0.03), G (-PL, -1.0, 0.03), Mat_Dark);
               OBox (G (0.0, 2.2, 0.0), D, N, 0.75 * PL, 1.0, 0.0, 0.35, Mat_Earth);
               OBox (G (0.0, 2.2, 0.0), D, N, 0.5 * PL, 0.6, 0.35, 0.7, Mat_Earth);
               for K in -2 .. 2 loop
                  Cone (G (Float (K) * PL / 2.0, -1.5, 0.0));
               end loop;
               --  a small digger, yellow (in the paint), arm down to the trench
               OBox (G (-0.5 * PL, -3.0, 0.0), D, N, 1.3, 0.85, 0.0, 0.45, Mat_Tyre);
               OBox (G (-0.5 * PL, -3.0, 0.0), D, N, 1.1, 0.8, 0.45, 1.3, Mat_Paint);
               OBox (G (-0.5 * PL - 0.4, -3.0, 0.0), D, N, 0.5, 0.6, 1.3, 2.2, Mat_Paint);
               OBox (G (-0.5 * PL - 0.4, -3.0, 0.0), D, N, 0.45, 0.62, 1.5, 2.1, Mat_Glass);
               declare
                  S0 : constant Vec3 := G (-0.5 * PL + 0.9, -2.5, 1.5);
                  S1 : constant Vec3 := G (-0.5 * PL + 2.6, -1.6, 2.4);
                  S2 : constant Vec3 := G (-0.5 * PL + 3.4, -0.6, 0.4);
               begin
                  for Pair of Float_List'(0.0, 1.0) loop
                     declare
                        P0 : constant Vec3 := (if Pair = 0.0 then S0 else S1);
                        P1 : constant Vec3 := (if Pair = 0.0 then S1 else S2);
                        W  : constant Vec3 := 0.12 * N;
                     begin
                        Quad2 (P0 - W, P1 - W, P1 + W + Vec3'(0.0, 0.25, 0.0), P0 + W + Vec3'(0.0, 0.25, 0.0),
                               Mat_Paint);
                     end;
                  end loop;
                  OBox (S2, D, N, 0.35, 0.35, -0.2, 0.25, Mat_Iron);   --  the bucket
               end;
            end;
         when Accident =>
            for K in -1 .. 1 loop
               Cone (E.A + (In0 - 2.0) * D + (Float (K) * 1.4) * N);
               Cone (E.B - (In0 - 2.0) * D + (Float (K) * 1.4) * N);
            end loop;
            --  broken glass on the road
            for K in 0 .. 11 loop
               declare
                  P : constant Vec3 := Mid + ((Rnd - 0.5) * 3.0) * D + ((Rnd - 0.5) * 2.5) * N;
                  Y : constant Float := Terrain.Height (P.X, P.Z) + 0.02;
                  S : constant Float := 0.06 + 0.08 * Rnd;
               begin
                  Meshes.Quad ((P.X - S, Y, P.Z - S), (P.X + S, Y, P.Z - S), (P.X + S, Y, P.Z + S),
                               (P.X - S, Y, P.Z + S), Mat_Glass);
               end;
            end loop;
         when Demo =>
            null;
      end case;
      Meshes.Finish (E.Mesh);
      E.Built := True;
   end Build;

   --  the cars, the vans, the banners: drawn where they stand with the paint
   procedure Build_Shapes is
      U : constant Vec3 := (0.0, 0.0, -1.0);   --  front is -Z
      V : constant Vec3 := (1.0, 0.0, 0.0);
      O : constant Vec3 := (0.0, 0.0, 0.0);
   begin
      Meshes.Start;
      OBox (O, U, V, 2.2, 0.85, 0.3, 0.95, Mat_Paint);
      OBox (O + 0.2 * U, U, V, 1.15, 0.78, 0.95, 1.45, Mat_Paint);
      OBox (O + 0.2 * U, U, V, 1.17, 0.8, 1.0, 1.4, Mat_Glass);
      for SU of Float_List'(-1.4, 1.4) loop
         for SV of Float_List'(-0.78, 0.78) loop
            OBox (O + SU * U + SV * V, U, V, 0.33, 0.12, 0.0, 0.62, Mat_Tyre);
         end loop;
      end loop;
      Meshes.Finish (Car_Mesh);
      Meshes.Start;
      OBox (O, U, V, 2.7, 1.0, 0.35, 2.4, Mat_Paint);
      OBox (O + 2.2 * U, U, V, 0.52, 0.98, 1.3, 2.1, Mat_Glass);
      for SU of Float_List'(-1.8, 1.8) loop
         for SV of Float_List'(-0.9, 0.9) loop
            OBox (O + SU * U + SV * V, U, V, 0.35, 0.13, 0.0, 0.7, Mat_Tyre);
         end loop;
      end loop;
      Meshes.Finish (Van_Mesh);
      Meshes.Start;   --  the blue lights on a roof (lit in uExtraColor)
      OBox (O, U, V, 0.15, 0.55, 0.0, 0.12, Mat_Lamp);
      Meshes.Finish (Lights_Mesh);
      Meshes.Start;   --  a banner between two poles, carried at 2 m
      for SV of Float_List'(-1.4, 1.4) loop
         OBox (O + SV * V, U, V, 0.03, 0.03, 0.9, 2.5, Mat_Iron);
      end loop;
      Quad2 (O + Vec3'(-1.4, 1.6, 0.0), O + Vec3'(1.4, 1.6, 0.0), O + Vec3'(1.4, 2.35, 0.0), O + Vec3'(-1.4, 2.35, 0.0),
             30.0);   --  cloth in the paint
      Meshes.Finish (Banner_Mesh);
      Shapes_Built := True;
   end Build_Shapes;

   ---------------------------------------------------------------------------

   procedure Draw (Model, Paint, Skin, Legs, Extra : GL.GLint; Cam : Vec3; Time : Float) is
      Flash : constant Boolean := Time - Float'Floor (Time) < 0.5;
   begin
      for E of Events loop
         if E.Active and then (E.A.X - Cam.X) ** 2 + (E.A.Z - Cam.Z) ** 2 < 500.0 ** 2 then
            if not Shapes_Built then
               Build_Shapes;
            end if;
            if not E.Built then
               Build (E);
            end if;
            declare
               D   : constant Vec3 := Normalize (Vec3'(E.B.X - E.A.X, 0.0, E.B.Z - E.A.Z));
               N   : constant Vec3 := (-D.Z, 0.0, D.X);
               L   : constant Float := Sqrt ((E.B.X - E.A.X) ** 2 + (E.B.Z - E.A.Z) ** 2);
               Mid : constant Vec3 := E.A + (0.5 * L) * D;
               Yaw : constant Float := Arctan (D.X, -D.Z);   --  heading along the road
               function On (P : Vec3; Turn : Float) return Mat4 is
                 (Translation ((P.X, Terrain.Height (P.X, P.Z), P.Z)) * Rotation_Y (-(Yaw + Turn)));
               procedure Vehicle (M : Meshes.Mesh; P : Vec3; Turn : Float; Colour : Vec3; Lights : Boolean;
                                  Roof : Float := 1.45) is
               begin
                  Shaders.Set (Paint, Colour);
                  Shaders.Set (Model, On (P, Turn));
                  Meshes.Draw (M);
                  if Lights then
                     Shaders.Set (Extra, (if Flash then Vec3'(0.1, 0.25, 1.0) else Vec3'(0.02, 0.04, 0.2)));
                     Shaders.Set (Model, On (P, Turn) * Translation ((0.0, Roof, 0.0)));
                     Meshes.Draw (Lights_Mesh);
                  end if;
               end Vehicle;
            begin
               Shaders.Set (Model, Identity);
               Shaders.Set (Paint, Vec3'(0.95, 0.75, 0.1));   --  the digger's yellow
               Meshes.Draw (E.Mesh);
               Figures.Set_Locations ((Model, Paint, Skin, Legs));
               case E.Kind is
                  when Works =>
                     --  a workman in orange by the trench, now and then digging
                     Figures.Person (On (Mid + 2.0 * D - 1.6 * N, Pi / 2.0),
                                     (0.95, 0.45, 0.08), (0.8, 0.62, 0.5), (0.2, 0.25, 0.35),
                                     Hat => Figures.Helmet, Hat_Colour => (0.95, 0.9, 0.15),
                                     Arm_Up => -0.8 + 0.6 * Sin (Time * 2.0 + E.Seed * 10.0));
                  when Accident =>
                     Vehicle (Car_Mesh, Mid - 1.2 * D - 0.8 * N, 0.5, (0.12, 0.2, 0.45), False);
                     Vehicle (Car_Mesh, Mid + 1.6 * D + 0.4 * N, 2.4, (0.75, 0.74, 0.7), False);
                     --  the police: their car (white, blue lights), an officer waving you round
                     Vehicle (Car_Mesh, Mid - 6.0 * D + 1.5 * N, 0.1, (0.92, 0.92, 0.94), True);
                     Figures.Person (On (E.A + 1.5 * D + (E.Width / 2.0 - 1.0) * N, Pi),
                                     (0.1, 0.14, 0.3), (0.85, 0.66, 0.54), (0.1, 0.12, 0.25),
                                     Hat => Figures.Kepi, Hat_Colour => (0.1, 0.12, 0.25),
                                     Arm_Up => -1.2 + 0.5 * Sin (Time * 3.0));
                  when Demo =>
                     --  police vans across both ends
                     Vehicle (Van_Mesh, E.A + 1.0 * D, Pi / 2.0, (0.12, 0.16, 0.38), True, 2.4);
                     Vehicle (Van_Mesh, E.B - 1.0 * D, Pi / 2.0, (0.12, 0.16, 0.38), True, 2.4);
                     --  the march: rows of walkers going slowly along, banners in front
                     declare
                        Span : constant Float := Float'Max (10.0, L - 16.0);
                        Rows : constant Natural := Natural (Span / 2.2);
                        Per  : constant Natural := Natural'Max (3, Natural (E.Width / 1.6));
                        Go   : constant Float := 0.7 * E.Life;
                        Colours : constant array (0 .. 5) of Vec3 :=
                          ((0.85, 0.1, 0.1), (0.95, 0.95, 0.9), (0.1, 0.3, 0.75), (0.95, 0.75, 0.1),
                           (0.2, 0.6, 0.3), (0.9, 0.4, 0.1));
                     begin
                        for R in 0 .. Rows - 1 loop
                           declare
                              T : constant Float := 8.0 + (Float (R) * 2.2 + Go)
                                - Span * Float'Floor ((Float (R) * 2.2 + Go) / Span);
                              Row_C : constant Vec3 := E.A + T * D;
                           begin
                              if R mod 6 = 0 then
                                 Shaders.Set (Paint, Colours ((R / 6 + Natural (E.Seed * 6.0)) mod 6));
                                 Shaders.Set (Model, On (Row_C, Pi / 2.0) * Rotation_Y (Pi / 2.0));
                                 Meshes.Draw (Banner_Mesh);
                              end if;
                              for K in 0 .. Per - 1 loop
                                 declare
                                    S : constant Float :=
                                      (Float (K) - Float (Per - 1) / 2.0) * (E.Width - 2.0) / Float (Per)
                                      + 0.3 * Sin (Float (R * 7 + K));
                                    H : constant Natural := (R * 13 + K * 7) mod 6;
                                 begin
                                    Figures.Person (On (Row_C + S * N, 0.0),
                                                    Colours (H), (0.86 - 0.08 * Float (K mod 4), 0.66, 0.54),
                                                    (0.15, 0.17, 0.25),
                                                    Stride => 0.35 * Sin (Time * 4.5 + Float (R + K)),
                                                    Arm_Up => (if (R + K) mod 5 = 0
                                                               then -2.4 + 0.3 * Sin (Time * 3.0 + Float (K))
                                                               else 0.0));
                                 end;
                              end loop;
                           end;
                        end loop;
                     end;
               end case;
            end;
         end if;
      end loop;
      Shaders.Set (Model, Identity);
   end Draw;

   function Report (French : Boolean) return String is
      R : Ada.Strings.Unbounded.Unbounded_String;
      N : Natural := 0;
      function Lower_First (S : String) return String is
        (if S'Length > 0 and then S (S'First) in 'A' .. 'Z'
         then Character'Val (Character'Pos (S (S'First)) + 32) & S (S'First + 1 .. S'Last) else S);
   begin
      for E of Events loop
         if E.Active and then N < 3 then
            declare
               Street : constant String :=
                 Ada.Strings.Unbounded.To_String (Road_Network.Ways (E.W).Name);
            begin
               if Street /= "" then
                  Ada.Strings.Unbounded.Append
                    (R, (if N > 0 then (if French then " ; " else "; ") else "")
                     & (if French then
                          (case E.Kind is when Works => "travaux ", when Accident => "accident ",
                                          when Demo => "manifestation ")
                          & Lower_First (Street)
                        else
                          (case E.Kind is when Works => "roadworks in ", when Accident => "an accident in ",
                                          when Demo => "a demonstration in ")
                          & Street));
                  N := N + 1;
               end if;
            end;
         end if;
      end loop;
      declare
         S : constant String := Ada.Strings.Unbounded.To_String (R);
      begin
         return (if S = "" then "" else Character'Val (Character'Pos (S (S'First)) - 32) & S (S'First + 1 .. S'Last));
      end;
   end Report;

   function Count return Natural is
      N : Natural := 0;
   begin
      for E of Events loop
         if E.Active then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Count;

   procedure Collide (S : in out Car.State) is
      procedure Push (PX, PZ, R : Float) is
         EX : constant Float := S.X - PX;
         EZ : constant Float := S.Z - PZ;
         D  : constant Float := Sqrt (EX * EX + EZ * EZ);
      begin
         if D < R and then D > 0.001 then
            S.X := S.X + EX / D * (R - D);
            S.Z := S.Z + EZ / D * (R - D);
            S.Speed := S.Speed * 0.5;
         end if;
      end Push;
   begin
      for E of Events loop
         if E.Active and then (E.A.X - S.X) ** 2 + (E.A.Z - S.Z) ** 2 < 300.0 ** 2 then
            declare
               D  : constant Vec3 := Normalize (Vec3'(E.B.X - E.A.X, 0.0, E.B.Z - E.A.Z));
               N  : constant Vec3 := (-D.Z, 0.0, D.X);
               L  : constant Float := Sqrt ((E.B.X - E.A.X) ** 2 + (E.B.Z - E.A.Z) ** 2);
               In0 : constant Float := Float'Min (4.0, L / 4.0);
               Half : constant Float := E.Width / 2.0 + 0.3;
               --  the barriers, as a row of posts the car cannot pass
               S0 : Float := -Half;
            begin
               while S0 <= Half loop
                  for Q of Float_List'(In0, L - In0) loop
                     declare
                        P : constant Vec3 := E.A + Q * D + S0 * N;
                     begin
                        Push (P.X, P.Z, 1.6);
                     end;
                  end loop;
                  S0 := S0 + 1.0;
               end loop;
            end;
         end if;
      end loop;
   end Collide;

end Closures;
