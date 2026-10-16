with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;

with Math3D;
with Road_Network;
with Shaders;

package body Traffic is

   use Ada.Numerics.Elementary_Functions;
   use Math3D;
   use Road_Network;

   Max_Cars     : constant := 180;
   Spawn_Near   : constant := 60.0;    --  spawn ring around the player (m)
   Spawn_Far    : constant := 250.0;
   Retire_Far   : constant := 320.0;
   Car_Length   : constant := 4.6;

   type Agent is record
      Active   : Boolean := False;
      Cur      : Link;              --  current segment: Pos -> Pos + Dir
      T        : Float := 0.0;      --  metres along the segment
      Speed    : Float := 0.0;
      Lane     : Float := 0.0;      --  offset to the right of the centre line
      Next     : Link;
      Has_Next : Boolean := False;
      X, Z     : Float := 0.0;      --  smoothed position for drawing
      Heading  : Float := 0.0;
      Color    : Vec3 := (0.5, 0.5, 0.5);
      Stuck    : Float := 0.0;
      Ghost    : Float := 0.0;      --  ignore others for a moment (deadlocks)
      Waiting  : Boolean := False;  --  stopped at a red light
   end record;

   Agents : array (1 .. Max_Cars) of Agent;
   Gen    : Ada.Numerics.Float_Random.Generator;
   Primed : Boolean := False;

   Palette : constant array (0 .. 11) of Vec3 :=
     ((0.08, 0.08, 0.09), (0.85, 0.85, 0.84), (0.55, 0.57, 0.60),
      (0.30, 0.31, 0.33), (0.70, 0.71, 0.72), (0.10, 0.16, 0.32),
      (0.45, 0.06, 0.06), (0.13, 0.20, 0.15), (0.92, 0.92, 0.90),
      (0.20, 0.22, 0.25), (0.60, 0.50, 0.38), (0.15, 0.30, 0.50));

   function Rnd return Float is (Ada.Numerics.Float_Random.Random (Gen));


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

   function Lane_For (W : Way) return Float is
   begin
      if W.Oneway = 0 then
         --  rightmost lane of our half
         return W.Width / 2.0 - W.Width / Float (2 * Positive'Max (2, W.Lanes));
      elsif W.Lanes = 1 then
         return 0.0;
      else
         declare
            K : constant Natural :=
              Natural'Min (W.Lanes - 1, Natural (Float'Floor (Rnd * Float (W.Lanes))));
         begin
            return -W.Width / 2.0 + (Float (K) + 0.5) * W.Width / Float (W.Lanes);
         end;
      end if;
   end Lane_For;


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
            W   : constant Natural := Pick_Way (Rnd);
            Seg : Natural;
            L   : Link;
            P, Q : Node;
            Len : Float;
            Ok  : Boolean := True;
         begin
            if Ways (W).Count >= 2 then
               Seg := Natural'Min (Ways (W).Count - 2,
                                   Natural (Float'Floor (Rnd * Float (Ways (W).Count - 1))));
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
                  A := (Active => True, Cur => L, T => Len / 2.0,
                        Speed => 6.0, Lane => Lane_For (Ways (W)),
                        Color => Palette (Natural (Float'Floor (Rnd * 11.99))),
                        others => <>);
                  Choose_Next (A);
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
      Cruise : constant Float := (if W.Width >= 9.0 then 13.0 else 8.5);
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
            procedure Obstacle (OX, OZ : Float) is
               RX  : constant Float := OX - Me.X;
               RZ  : constant Float := OZ - Me.Z;
               Fwd : constant Float := RX * D.X + RZ * D.Z;
               Lat : constant Float := abs (RX * D.Z - RZ * D.X);
            begin
               if Fwd > 0.5 and then Fwd < 30.0 and then Lat < 2.0 then
                  Target := Float'Min (Target, Float'Max (0.0, (Fwd - Car_Length - 1.5) * 0.8));
               end if;
            end Obstacle;
         begin
            for J in Agents'Range loop
               if J /= I and then Agents (J).Active then
                  Obstacle (Agents (J).X, Agents (J).Z);
               end if;
            end loop;
            Obstacle (Player.X, Player.Z);
         end;
      else
         A.Ghost := A.Ghost - Dt;
      end if;

      if A.Speed < Target then
         A.Speed := Float'Min (Target, A.Speed + 2.8 * Dt);
      else
         A.Speed := Float'Max (Target, A.Speed - 8.0 * Dt);
      end if;

      if A.Speed < 0.3 and then not A.Waiting then
         A.Stuck := A.Stuck + Dt;
         if A.Stuck > 7.0 then
            A.Ghost := 2.5;
            A.Stuck := 0.0;
         end if;
      else
         A.Stuck := 0.0;
      end if;

      --  Advance along the network
      A.T := A.T + A.Speed * Dt;
      while A.T >= Len loop
         if not A.Has_Next then
            A.Active := False;
            return;
         end if;
         A.T := A.T - Len;
         if A.Next.W /= A.Cur.W then
            A.Lane := Lane_For (Ways (A.Next.W));
         elsif A.Next.Dir /= A.Cur.Dir then
            A.Lane := Lane_For (W);
         end if;
         A.Cur := A.Next;
         Choose_Next (A);
         Segment (A.Cur, P, Q, Len);
      end loop;

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
      for A of Agents loop
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
                     PX : constant Float := Player.X + Sin (Player.Heading) * PO;
                     PZ : constant Float := Player.Z - Cos (Player.Heading) * PO;
                     AX : constant Float := A.X + Sin (A.Heading) * AO;
                     AZ : constant Float := A.Z - Cos (A.Heading) * AO;
                     DX : constant Float := PX - AX;
                     DZ : constant Float := PZ - AZ;
                     D  : constant Float := Sqrt (DX * DX + DZ * DZ);
                  begin
                     if D < 2.0 and then D > 0.001 then
                        Player.X := Player.X + DX / D * (2.0 - D);
                        Player.Z := Player.Z + DZ / D * (2.0 - D);
                        declare
                           VN : constant Float :=
                             (Sin (Player.Heading) * DX - Cos (Player.Heading) * DZ) / D
                             * Player.Speed;
                        begin
                           if VN < 0.0 then
                              Player.Speed := Player.Speed * 0.6;
                              Player.Bumped := True;
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

   procedure Draw (Model_Loc, Color_Loc : GL.GLint) is
      use type GL.GLint;
   begin
      for A of Agents loop
         if A.Active then
            Shaders.Set (Model_Loc, Car.Model_Matrix
                           ((X => A.X, Z => A.Z, Heading => A.Heading, others => <>)));
            if Color_Loc >= 0 then
               Shaders.Set (Color_Loc, A.Color);
            end if;
            Car.Draw;
         end if;
      end loop;
   end Draw;

end Traffic;
