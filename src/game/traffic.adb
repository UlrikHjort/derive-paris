--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;

with Meshes;
with Road_Network;
with Shaders;

package body Traffic is

   use Ada.Numerics.Elementary_Functions;
   use Math3D;
   use Road_Network;

   Max_Cars     : constant := 400;      --  room for dense traffic
   Limit        : Natural := 180;      --  vehicles around you (setting)
   Spawn_Near   : constant := 60.0;    --  spawn ring around the player (m)
   Spawn_Far    : constant := 250.0;
   Retire_Far   : constant := 320.0;
   Car_Length   : constant := 4.6;

   type Vehicle_Kind is (Car_Kind, Scooter, Motorbike, Deux_Chevaux, DS);

   type Agent is record
      Kind     : Vehicle_Kind := Car_Kind;
      Lean     : Float := 0.0;      --  two-wheelers lean into turns
      Active   : Boolean := False;
      Cur      : Link;              --  current segment: Pos -> Pos + Dir
      T        : Float := 0.0;      --  metres along the segment
      Speed    : Float := 0.0;
      Lane     : Float := 0.0;      --  offset to the right of the centre line
      Lane_Pick : Natural := 0;     --  the lane it likes, counted from the right
      Next     : Link;
      Has_Next : Boolean := False;
      X, Z     : Float := 0.0;      --  smoothed position for drawing
      Heading  : Float := 0.0;
      Color    : Vec3 := (0.5, 0.5, 0.5);
      Stuck    : Float := 0.0;
      Ghost    : Float := 0.0;      --  ignore others for a moment (deadlocks)
      Waiting  : Boolean := False;  --  stopped at a red light
      Jammed   : Float := 0.0;      --  seconds without real progress
   end record;

   Agents : array (1 .. Max_Cars) of Agent;

   function Four_Wheels (K : Vehicle_Kind) return Boolean is
     (K in Car_Kind | Deux_Chevaux | DS);

   --  the colours the 2CV and the DS came in
   Vintage : constant array (0 .. 5) of Vec3 :=
     ((0.55, 0.57, 0.58), (0.80, 0.74, 0.58), (0.45, 0.08, 0.10),
      (0.42, 0.58, 0.72), (0.90, 0.88, 0.80), (0.10, 0.10, 0.11));

   type Float_Pair is array (1 .. 2) of Float;
   Gen    : Ada.Numerics.Float_Random.Generator;
   Primed : Boolean := False;

   Palette : constant array (0 .. 11) of Vec3 :=
     ((0.08, 0.08, 0.09), (0.85, 0.85, 0.84), (0.55, 0.57, 0.60),
      (0.30, 0.31, 0.33), (0.70, 0.71, 0.72), (0.10, 0.16, 0.32),
      (0.45, 0.06, 0.06), (0.13, 0.20, 0.15), (0.92, 0.92, 0.90),
      (0.20, 0.22, 0.25), (0.60, 0.50, 0.38), (0.15, 0.30, 0.50));

   function Rnd return Float is (Ada.Numerics.Float_Random.Random (Gen));


   function Nearest (X, Z : Float) return Float is
      Best : Float := Float'Last;
   begin
      for A of Agents loop
         if A.Active then
            Best := Float'Min (Best, (A.X - X) ** 2 + (A.Z - Z) ** 2);
         end if;
      end loop;
      return (if Best = Float'Last then Best else Sqrt (Best));
   end Nearest;

   function Nearby (X, Z : Float) return Source_List is
      List : Source_List;
      Dist : array (Source_List'Range) of Float := (others => Float'Last);
   begin
      for I in Agents'Range loop
         declare
            A : Agent renames Agents (I);
            D : Float;
         begin
            if A.Active then
               D := (A.X - X) ** 2 + (A.Z - Z) ** 2;
               if D < 120.0 ** 2 and then D < Dist (Dist'Last) then
                  --  insert sorted
                  declare
                     J : Integer := Dist'Last;
                  begin
                     while J > Dist'First and then Dist (J - 1) > D loop
                        Dist (J) := Dist (J - 1);
                        List (J) := List (J - 1);
                        J := J - 1;
                     end loop;
                     Dist (J) := D;
                     List (J) := (Id => I, X => A.X, Z => A.Z, Speed => A.Speed,
                                  Heading => A.Heading,
                                  --  a 2CV's flat twin sounds like a motorbike
                                  Kind => (case A.Kind is
                                             when Scooter => 1,
                                             when Motorbike | Deux_Chevaux => 2,
                                             when others => 0));
                  end;
               end if;
            end if;
         end;
      end loop;
      return List;
   end Nearby;

   Walker_On   : Boolean := False;
   Walker_X, Walker_Z : Float := 0.0;

   procedure Set_Walker (On : Boolean; X, Z : Float) is
   begin
      Walker_On := On;
      Walker_X := X;
      Walker_Z := Z;
   end Set_Walker;

   procedure Clear_Corridor (A, B : Vec3; Half_Width : Float) is
      D  : constant Vec3 := B - A;
      L2 : constant Float := Float'Max (1.0, D.X * D.X + D.Z * D.Z);
   begin
      for Ag of Agents loop
         if Ag.Active then
            declare
               T  : constant Float := Float'Max (0.0, Float'Min (1.0,
                      ((Ag.X - A.X) * D.X + (Ag.Z - A.Z) * D.Z) / L2));
               PX : constant Float := A.X + T * D.X;
               PZ : constant Float := A.Z + T * D.Z;
            begin
               if (Ag.X - PX) ** 2 + (Ag.Z - PZ) ** 2 < Half_Width ** 2 then
                  Ag.Active := False;
               end if;
            end;
         end if;
      end loop;
   end Clear_Corridor;

   procedure Set_Density (Factor : Float) is
   begin
      Limit := Natural (Float'Max (0.0, Float'Min (Float (Max_Cars), 180.0 * Factor)));
   end Set_Density;

   procedure Reset is
   begin
      for A of Agents loop
         A.Active := False;
      end loop;
   end Reset;

   function Count return Natural is
      N : Natural := 0;
   begin
      for A of Agents loop
         if A.Active then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Count;


   ---------------------------------------------------------------------------
   --  Driving
   ---------------------------------------------------------------------------

   --  Lanes in our direction of travel on a way
   function Lanes_Our_Way (W : Way) return Positive is
     (if W.Oneway /= 0 then W.Lanes else Positive'Max (1, W.Lanes / 2));

   --  The offset (to the right of the centre line) of lane Index, counted
   --  from the right; on a two-way street our half is the right half
   function Lane_Offset (W : Way; Index : Natural) return Float is
      N : constant Positive := Lanes_Our_Way (W);
      I : constant Natural := Natural'Min (Index, N - 1);
   begin
      if W.Oneway = 0 then
         declare
            Half : constant Float := W.Width / 2.0;
            Lane : constant Float := Half / Float (N);
         begin
            return Half - (Float (I) + 0.5) * Lane;
         end;
      else
         return W.Width / 2.0 - (Float (I) + 0.5) * W.Width / Float (N);
      end if;
   end Lane_Offset;

   --  Most drivers keep to the right; some like the middle or the left
   function Pick_Lane return Natural is
      R : constant Float := Rnd;
   begin
      return (if R < 0.6 then 0 elsif R < 0.88 then 1 else 2);
   end Pick_Lane;

   --  Where an agent wants to be across the road: its own lane, or the
   --  lane for the turn coming up
   function Lane_Goal (A : Agent; W : Way; Left_Of_Segment : Float) return Float is
      Index : Natural := A.Lane_Pick;
      Two_Wheels_Right : constant Float := (if Four_Wheels (A.Kind) then 0.0 else 0.7);
   begin
      if A.Has_Next and then Left_Of_Segment < 45.0 and then A.Next.W /= A.Cur.W then
         declare
            D    : constant Vec3 := Direction (A.Cur);
            N    : constant Vec3 := Direction (A.Next);
            Turn : constant Float := D.X * N.Z - D.Z * N.X;   --  > 0: to the right
         begin
            if Turn > 0.35 then
               Index := 0;                                     --  right turn
            elsif Turn < -0.35 then
               Index := Lanes_Our_Way (W) - 1;                 --  left turn
            end if;
         end;
      end if;
      return Lane_Offset (W, Index) + Two_Wheels_Right;
   end Lane_Goal;


   --  Pick where to go at the end of the current segment
   procedure Choose_Next (A : in out Agent) is
      End_Pos  : constant Natural := A.Cur.Pos + A.Cur.Dir;
      End_Node : constant Natural := Node_Index (A.Cur.W, End_Pos);
      D        : constant Vec3 := Direction (A.Cur);
      Total    : Float := 0.0;
      Back     : Link;
      Has_Back : Boolean := False;
   begin
      A.Has_Next := False;
      for L of Links (End_Node) loop
         if L.W = A.Cur.W and then L.Dir = -A.Cur.Dir then
            Back := L;
            Has_Back := True;
         else
            --  prefer going straight on, but keep every option possible
            Total := Total + 0.3 + Float'Max (0.0, Dot (D, Direction (L)));
         end if;
      end loop;
      if Total > 0.0 then
         declare
            Pick : Float := Rnd * Total;
         begin
            for L of Links (End_Node) loop
               if not (L.W = A.Cur.W and then L.Dir = -A.Cur.Dir) then
                  Pick := Pick - (0.3 + Float'Max (0.0, Dot (D, Direction (L))));
                  if Pick <= 0.0 or else not A.Has_Next then
                     A.Next := L;
                     A.Has_Next := True;
                  end if;
                  exit when Pick <= 0.0;
               end if;
            end loop;
         end;
      elsif Has_Back then
         A.Next := Back;      --  dead end: turn around
         A.Has_Next := True;
      end if;
   end Choose_Next;

   function Target_Point (A : Agent) return Vec3 is
      P, Q : Node;
      Len  : Float;
      D    : Vec3;
   begin
      Segment (A.Cur, P, Q, Len);
      D := Direction (A.Cur);
      return (P.X + D.X * A.T - D.Z * A.Lane, 0.0, P.Z + D.Z * A.T + D.X * A.Lane);
   end Target_Point;


   procedure Spawn (A : in out Agent; Focus_X, Focus_Z, Focus_Heading : Float;
                    Near : Float) is
   begin
      for Attempt in 1 .. 30 loop
         declare
            W, Seg : Natural;
            Got : Boolean;
            L   : Link;
            P, Q : Node;
            Len : Float;
            Ok  : Boolean := True;
         begin
            Pick_Segment (Focus_X, Focus_Z, Near, Spawn_Far, Rnd, Rnd, Rnd, Got, W, Seg);
            --  wide roads are busier: take narrow ones only half the time
            if Got and then (Ways (W).Width >= 9.0 or else Rnd < 0.5) then
               if Ways (W).Oneway > 0 or else (Ways (W).Oneway = 0 and then Rnd < 0.5) then
                  L := (W, Seg, 1);
               else
                  L := (W, Seg + 1, -1);
               end if;
               Segment (L, P, Q, Len);
               declare
                  DX : constant Float := (P.X + Q.X) / 2.0 - Focus_X;
                  DZ : constant Float := (P.Z + Q.Z) / 2.0 - Focus_Z;
                  D  : constant Float := Sqrt (DX * DX + DZ * DZ);
               begin
                  if Len < 4.0 or else D < Near or else D > Spawn_Far then
                     Ok := False;
                  elsif Near > 20.0 and then D < 160.0
                    and then (DX * Sin (Focus_Heading) - DZ * Cos (Focus_Heading)) / D > 0.6
                  then
                     Ok := False;   --  would pop up right in front of the driver
                  end if;
               end;
               if Ok then
                  for O of Agents loop
                     if O.Active and then (O.X - (P.X + Q.X) / 2.0) ** 2
                       + (O.Z - (P.Z + Q.Z) / 2.0) ** 2 < 15.0 ** 2
                     then
                        Ok := False;
                     end if;
                  end loop;
               end if;
               if Ok then
                  declare
                     R : constant Float := Rnd;
                     K : constant Vehicle_Kind :=
                       (if R < 0.12 then Scooter elsif R < 0.2 then Motorbike
                        elsif R < 0.23 then Deux_Chevaux elsif R < 0.245 then DS
                        else Car_Kind);
                  begin
                     A := (Active => True, Kind => K, Cur => L, T => Len / 2.0,
                           Speed => 6.0,
                           Lane_Pick => Pick_Lane,
                           Color => (if K in Deux_Chevaux | DS
                                     then Vintage (Natural (Float'Floor (Rnd * 5.99)))
                                     else Palette (Natural (Float'Floor (Rnd * 11.99)))),
                           others => <>);
                  end;
                  Choose_Next (A);
                  A.Lane := Lane_Goal (A, Ways (W), Len);
                  declare
                     P0 : constant Vec3 := Target_Point (A);
                     D  : constant Vec3 := Direction (A.Cur);
                  begin
                     A.X := P0.X;
                     A.Z := P0.Z;
                     A.Heading := Arctan (D.X, -D.Z);
                  end;
                  return;
               end if;
            end if;
         end;
      end loop;
   end Spawn;

   function Angle_Diff (A, B : Float) return Float is
      D : Float := A - B;
   begin
      while D > Ada.Numerics.Pi loop
         D := D - 2.0 * Ada.Numerics.Pi;
      end loop;
      while D < -Ada.Numerics.Pi loop
         D := D + 2.0 * Ada.Numerics.Pi;
      end loop;
      return D;
   end Angle_Diff;

   procedure Drive (I : Positive; Dt, Time : Float; Player : Car.State) is
      A      : Agent renames Agents (I);
      P, Q   : Node;
      Len    : Float;
      W      : constant Way := Ways (A.Cur.W);
      Base   : constant Float := (if W.Width >= 9.0 then 13.0 else 8.5);
      Cruise : constant Float := (case A.Kind is
                                    when Car_Kind | DS => Base,
                                    when Deux_Chevaux => Base * 0.85,
                                    when Scooter   => Float'Min (Base, 11.0),
                                    when Motorbike => Base * 1.15);
      Accel  : constant Float := (case A.Kind is
                                    when Car_Kind | DS => 2.8,
                                    when Deux_Chevaux => 1.8,
                                    when Scooter   => 3.2,
                                    when Motorbike => 4.8);
      Width  : constant Float := (if Four_Wheels (A.Kind) then 2.0 else 1.1);
      Old_Heading : constant Float := A.Heading;
      Target : Float := Cruise;
      D      : constant Vec3 := Direction (A.Cur);
      Me     : constant Vec3 := (A.X, 0.0, A.Z);
   begin
      Segment (A.Cur, P, Q, Len);

      --  Slow down before a turn
      if A.Has_Next then
         declare
            Turn   : constant Float := Dot (D, Direction (A.Next));
            V_Turn : constant Float := 3.5 + (Cruise - 3.5) * Float'Max (0.0, Turn) ** 3;
            Left   : constant Float := Len - A.T;
         begin
            if Left < 25.0 then
               Target := Float'Min (Target, V_Turn + Left / 25.0 * (Cruise - V_Turn));
            end if;
         end;
      else
         Target := Float'Min (Target, (Len - A.T) * 0.5);
      end if;

      --  Stop for red (and for amber when there is room to stop)
      A.Waiting := False;
      declare
         End_Node : constant Node := Point (A.Cur.W, A.Cur.Pos + A.Cur.Dir);
         Left     : constant Float := Len - A.T;
      begin
         if End_Node.Signal >= 0.0 and then Left > 1.0 then
            declare
               State : constant Light := Signal_State (End_Node.Signal, D.X, D.Z, Time);
            begin
               if State = Red
                 or else (State = Amber and then Left > 3.0 + A.Speed * A.Speed / 10.0)
               then
                  Target := Float'Min (Target, Float'Max (0.0, (Left - 3.0) * 0.7));
                  A.Waiting := True;
               end if;
            end;
         end if;
      end;

      --  Keep the distance to whatever is in front
      if A.Ghost <= 0.0 then
         declare
            procedure Obstacle (OX, OZ, Length : Float) is
               RX  : constant Float := OX - Me.X;
               RZ  : constant Float := OZ - Me.Z;
               Fwd : constant Float := RX * D.X + RZ * D.Z;
               Lat : constant Float := abs (RX * D.Z - RZ * D.X);
            begin
               if Fwd > 0.5 and then Fwd < 30.0 and then Lat < Width then
                  Target := Float'Min
                    (Target, Float'Max (0.0, (Fwd - 0.5 * (Length + (if Four_Wheels (A.Kind)
                                                                     then Car_Length else 2.2))
                                              - 1.2) * 0.8));
               end if;
            end Obstacle;
         begin
            for J in Agents'Range loop
               if J /= I and then Agents (J).Active then
                  Obstacle (Agents (J).X, Agents (J).Z,
                            (if Four_Wheels (Agents (J).Kind) then Car_Length else 2.2));
               end if;
            end loop;
            Obstacle (Player.X, Player.Z, Car_Length);
            if Walker_On then
               Obstacle (Walker_X, Walker_Z, 1.0);
            end if;
         end;
      else
         A.Ghost := A.Ghost - Dt;
      end if;

      if A.Speed < Target then
         A.Speed := Float'Min (Target, A.Speed + Accel * Dt);
      else
         A.Speed := Float'Max (Target, A.Speed - 8.0 * Dt);
      end if;

      if A.Speed < 0.3 and then not A.Waiting then
         A.Stuck := A.Stuck + Dt;
         A.Jammed := A.Jammed + Dt;
         if A.Stuck > 7.0 then
            A.Ghost := 2.5;
            A.Stuck := 0.0;
         end if;
         --  hopelessly stuck (gridlock): leave the game, a new car will
         --  come from elsewhere
         if A.Jammed > 30.0 then
            A.Active := False;
            return;
         end if;
      else
         A.Stuck := 0.0;
         if A.Speed > 2.0 then
            A.Jammed := 0.0;
         end if;
      end if;

      --  Advance along the network
      A.T := A.T + A.Speed * Dt;
      while A.T >= Len loop
         if not A.Has_Next then
            A.Active := False;
            return;
         end if;
         A.T := A.T - Len;
         --  a U-turn at a dead end lands in the other half at once
         if A.Next.W = A.Cur.W and then A.Next.Dir /= A.Cur.Dir then
            A.Lane := Lane_Goal (A, W, 999.0);
         end if;
         A.Cur := A.Next;
         Choose_Next (A);
         Segment (A.Cur, P, Q, Len);
      end loop;

      --  Drift towards the lane we want: a lane change takes a few seconds
      --  (but a new street of another width is taken up quickly)
      declare
         Goal : constant Float := Lane_Goal (A, Ways (A.Cur.W), Len - A.T);
         Rate : constant Float := (if abs (Goal - A.Lane) > 4.0 then 4.0 else 1.1);
      begin
         if A.Lane < Goal then
            A.Lane := Float'Min (Goal, A.Lane + Rate * Dt);
         else
            A.Lane := Float'Max (Goal, A.Lane - Rate * Dt);
         end if;
      end;

      --  Smoothed position and heading for drawing
      declare
         Goal : constant Vec3 := Target_Point (A);
         DN   : constant Vec3 := Direction (A.Cur);
         K    : constant Float := 1.0 - Exp (-Dt * 6.0);
         H    : constant Float := Arctan (DN.X, -DN.Z);
         MX   : constant Float := Goal.X - A.X;
         MZ   : constant Float := Goal.Z - A.Z;
      begin
         A.X := A.X + MX * K;
         A.Z := A.Z + MZ * K;
         --  Face the way we actually move, falling back to the road
         if MX * MX + MZ * MZ > 0.04 then
            A.Heading := A.Heading + Angle_Diff (Arctan (MX, -MZ), A.Heading) * K;
         else
            A.Heading := A.Heading + Angle_Diff (H, A.Heading) * K;
         end if;
         --  lean into the turn: more with speed and turn rate
         if not Four_Wheels (A.Kind) and then Dt > 0.0 then
            declare
               Yaw_Rate : constant Float := Angle_Diff (A.Heading, Old_Heading) / Dt;
               Want     : constant Float :=
                 Float'Max (-0.6, Float'Min (0.6, Yaw_Rate * A.Speed * 0.1));
            begin
               A.Lean := A.Lean + (Want - A.Lean) * (1.0 - Exp (-Dt * 5.0));
            end;
         end if;
      end;
   end Drive;

   procedure Update (Dt, Time : Float; Focus_X, Focus_Z, Focus_Heading : Float;
                     Player : Car.State)
   is
      Spawned : Natural := 0;
   begin
      if not Loaded then
         return;
      end if;
      if not Primed then
         Ada.Numerics.Float_Random.Reset (Gen, 2026);
      end if;
      for I in Agents'Range loop
         if Agents (I).Active then
            Drive (I, Dt, Time, Player);
         end if;
         declare
            A : Agent renames Agents (I);
         begin
            if A.Active and then
              (A.X - Focus_X) ** 2 + (A.Z - Focus_Z) ** 2 > Retire_Far ** 2
            then
               A.Active := False;
            end if;
         end;
      end loop;
      for I in Agents'Range loop
         if I > Limit then
            Agents (I).Active := False;
         end if;
      end loop;
      for A of Agents (1 .. Limit) loop
         if not A.Active and then (not Primed or else Spawned < 2) then
            Spawn (A, Focus_X, Focus_Z, Focus_Heading, (if Primed then Spawn_Near else 12.0));
            Spawned := Spawned + 1;
         end if;
      end loop;
      Primed := True;
   end Update;

   procedure Collide_Player (Player : in out Car.State) is
      Offsets : constant array (1 .. 2) of Float := (1.15, -1.15);
   begin
      if not Loaded then
         return;
      end if;
      for A of Agents loop
         if A.Active and then (A.X - Player.X) ** 2 + (A.Z - Player.Z) ** 2 < 36.0 then
            for PO of Offsets loop
               for AO of Offsets loop
                  declare
                     Reach : constant Float := (if Four_Wheels (A.Kind) then 2.0 else 1.6);
                     Off   : constant Float := (if Four_Wheels (A.Kind) then AO else 0.4 * AO);
                     PX : constant Float := Player.X + Sin (Player.Heading) * PO;
                     PZ : constant Float := Player.Z - Cos (Player.Heading) * PO;
                     AX : constant Float := A.X + Sin (A.Heading) * Off;
                     AZ : constant Float := A.Z - Cos (A.Heading) * Off;
                     DX : constant Float := PX - AX;
                     DZ : constant Float := PZ - AZ;
                     D  : constant Float := Sqrt (DX * DX + DZ * DZ);
                  begin
                     if D < Reach and then D > 0.001 then
                        Player.X := Player.X + DX / D * (Reach - D);
                        Player.Z := Player.Z + DZ / D * (Reach - D);
                        declare
                           VN : constant Float :=
                             (Sin (Player.Heading) * DX - Cos (Player.Heading) * DZ) / D
                             * Player.Speed;
                        begin
                           if VN < 0.0 then
                              Player.Speed := Player.Speed * 0.6;
                              Player.Bumped := True;
                              Player.Hit_NX := DX / D;
                              Player.Hit_NZ := DZ / D;
                           end if;
                        end;
                        A.Speed := 0.0;
                     end if;
                  end;
               end loop;
            end loop;
         end if;
      end loop;
   end Collide_Player;

   ---------------------------------------------------------------------------
   --  Two-wheelers with their riders (front is -Z, like the car)
   ---------------------------------------------------------------------------

   Scooter_Mesh, Motorbike_Mesh : Meshes.Mesh;

   procedure Create_Meshes is
      use Meshes;
      procedure Rider (Seat_Y, Seat_Z, Lean_Forward, Bar_Y, Bar_Z : Float) is
      begin
         --  thighs, body, helmet with visor, arms to the handlebar
         Box (-0.17, 0.17, Seat_Y, Seat_Y + 0.17, Seat_Z - 0.45, Seat_Z + 0.1, Mat_Tyre);
         Box (-0.2, 0.2, Seat_Y + 0.15, Seat_Y + 0.72, Seat_Z - 0.05 - Lean_Forward,
              Seat_Z + 0.25, Mat_Tyre, Top_Inset_X => 0.03, Top_Inset_Front => 0.0);
         Box (-0.14, 0.14, Seat_Y + 0.72, Seat_Y + 1.02, Seat_Z - 0.17 - Lean_Forward,
              Seat_Z + 0.13 - Lean_Forward, Mat_Paint, Top_Inset_X => 0.03,
              Top_Inset_Front => 0.04, Top_Inset_Back => 0.04);
         Box (-0.11, 0.11, Seat_Y + 0.8, Seat_Y + 0.92, Seat_Z - 0.19 - Lean_Forward,
              Seat_Z - 0.16 - Lean_Forward, Mat_Glass);
         for Side of Float_Pair'(-1.0, 1.0) loop
            Box (Side * 0.27 - 0.05, Side * 0.27 + 0.05, Bar_Y, Seat_Y + 0.62,
                 Bar_Z, Seat_Z - Lean_Forward + 0.05, Mat_Tyre);
         end loop;
      end Rider;
   begin
      --  Scooter (Vespa-like)
      Start;
      Box (-0.05, 0.05, 0.0, 0.46, -0.85, -0.39, Mat_Tyre);          --  wheels
      Box (-0.06, 0.06, 0.0, 0.46, 0.4, 0.86, Mat_Tyre);
      Box (-0.18, 0.18, 0.22, 0.34, -0.55, 0.3, Mat_Paint);           --  floorboard
      Box (-0.22, 0.22, 0.3, 0.78, 0.1, 0.85, Mat_Paint,
           Top_Inset_X => 0.04, Top_Inset_Back => 0.15);               --  rear body
      Box (-0.21, 0.21, 0.3, 1.0, -0.66, -0.52, Mat_Paint,
           Top_Inset_X => 0.05);                                       --  leg shield
      Box (-0.04, 0.04, 0.95, 1.12, -0.62, -0.55, Mat_Tyre);          --  steering
      Box (-0.34, 0.34, 1.08, 1.14, -0.6, -0.54, Mat_Tyre);           --  handlebar
      Box (-0.07, 0.07, 1.0, 1.1, -0.68, -0.62, Mat_Headlight);
      Box (-0.06, 0.06, 0.62, 0.7, 0.85, 0.88, Mat_Taillight);
      Box (-0.17, 0.17, 0.78, 0.86, 0.05, 0.65, Mat_Tyre);            --  seat
      Box (-0.14, 0.14, 0.34, 0.86, -0.3, -0.12, Mat_Tyre);           --  lower legs
      Rider (0.86, 0.45, 0.05, 1.08, -0.57);
      Finish (Scooter_Mesh);

      --  Motorbike
      Start;
      Box (-0.07, 0.07, 0.0, 0.64, -1.07, -0.43, Mat_Tyre);         --  wheels
      Box (-0.08, 0.08, 0.0, 0.64, 0.42, 1.06, Mat_Tyre);
      Box (-0.2, 0.2, 0.3, 0.7, -0.35, 0.25, Mat_Tyre,
           Top_Inset_X => 0.03);                                      --  engine
      Box (-0.19, 0.19, 0.7, 0.98, -0.45, 0.05, Mat_Paint,
           Top_Inset_X => 0.05, Top_Inset_Front => 0.08);             --  tank
      Box (-0.15, 0.15, 0.82, 0.93, 0.05, 0.62, Mat_Tyre);           --  seat
      Box (-0.11, 0.11, 0.74, 0.86, 0.6, 0.95, Mat_Paint);           --  tail
      Box (-0.05, 0.05, 0.35, 1.02, -0.8, -0.7, Mat_Tyre);           --  fork
      Box (-0.38, 0.38, 1.0, 1.06, -0.6, -0.54, Mat_Tyre);           --  handlebar
      Box (-0.09, 0.09, 0.85, 0.99, -0.86, -0.78, Mat_Headlight);
      Box (-0.06, 0.06, 0.8, 0.87, 0.95, 0.98, Mat_Taillight);
      Box (-0.24, 0.24, 0.3, 0.9, 0.05, 0.2, Mat_Tyre);              --  lower legs
      Rider (0.93, 0.4, 0.25, 1.0, -0.57);
      Finish (Motorbike_Mesh);
   end Create_Meshes;

   procedure Draw (Model_Loc, Color_Loc : GL.GLint) is
      use type GL.GLint;
   begin
      for A of Agents loop
         if A.Active then
            Shaders.Set (Model_Loc, Car.Model_Matrix (Car.On_Ground (A.X, A.Z, A.Heading))
                         * Rotation_Z (-A.Lean));
            if Color_Loc >= 0 then
               Shaders.Set (Color_Loc, A.Color);
            end if;
            case A.Kind is
               when Car_Kind  => Car.Draw_Model (Car.Modern);
               when Deux_Chevaux => Car.Draw_Model (Car.Deux_Chevaux);
               when DS        => Car.Draw_Model (Car.DS);
               when Scooter   => Meshes.Draw (Scooter_Mesh);
               when Motorbike => Meshes.Draw (Motorbike_Mesh);
            end case;
         end if;
      end loop;
   end Draw;

end Traffic;
