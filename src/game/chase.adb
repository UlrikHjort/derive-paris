--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;

with Road_Network;
with Shaders;

package body Chase is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;
   use Road_Network;

   Reach     : constant := 160.0;   --  farther than this: out of reach
   Give_Up   : constant := 12.0;    --  seconds out of reach and it is gone

   On       : Boolean := False;
   Result   : Outcome := Going;
   Cur      : Link;
   T        : Float := 0.0;          --  metres along the current segment
   Speed    : Float := 0.0;
   X, Z, H  : Float := 0.0;
   Run_Left : Float := 0.0;          --  seconds until it stops
   Out_Time : Float := 0.0;
   Gap      : Float := 0.0;
   Colour   : Vec3 := (0.1, 0.1, 0.12);

   Gen : Ada.Numerics.Float_Random.Generator;
   Seeded : Boolean := False;
   function Rnd return Float is (Ada.Numerics.Float_Random.Random (Gen));

   Colours : constant array (0 .. 4) of Vec3 :=
     ((0.08, 0.08, 0.09), (0.55, 0.06, 0.06), (0.12, 0.2, 0.42), (0.7, 0.71, 0.72), (0.15, 0.3, 0.18));

   function Active return Boolean is (On);
   function State return Outcome is (Result);
   function Where return Vec3 is ((X, 0.0, Z));
   function Distance return Float is (Gap);
   function Lost_For return Float is (Out_Time);

   procedure Stop is
   begin
      On := False;
   end Stop;

   --  the next segment at the end of this one: on, rather than back; not
   --  into a closed street; now and then a turn
   procedure Choose_Next is
      End_Node : constant Natural := Node_Index (Cur.W, Cur.Pos + Cur.Dir);
      D : constant Vec3 := Direction (Cur);
      Best, Back : Link;
      Have, Have_Back : Boolean := False;
      Best_Score : Float := -1.0E9;
   begin
      for L of Links (End_Node) loop
         if L.W = Cur.W and then L.Dir = -Cur.Dir then
            Back := L;
            Have_Back := True;
         elsif not Is_Closed (L) then
            declare
               S : constant Float := Dot (D, Direction (L)) + 1.6 * Rnd   --  a turn now and then
                 + (if Ways (L.W).Width >= 9.0 then 0.3 else 0.0);           --  likes the big streets
            begin
               if S > Best_Score then
                  Best_Score := S;
                  Best := L;
                  Have := True;
               end if;
            end;
         end if;
      end loop;
      if Have then
         Cur := Best;
      elsif Have_Back then
         Cur := Back;
      end if;
      T := 0.0;
   end Choose_Next;

   procedure Start (Player : Car.State) is
      Found : Boolean := False;
      W, Seg : Natural := 0;
      HX : constant Float := Sin (Player.Heading);
      HZ : constant Float := -Cos (Player.Heading);
      Best_D : Float := Float'Last;
      Need_Ahead : Boolean := True;
      procedure Visit (VW, VS : Natural; AX, AZ, BX, BZ : Float) is
         MX : constant Float := (AX + BX) / 2.0 - Player.X;
         MZ : constant Float := (AZ + BZ) / 2.0 - Player.Z;
         Ahead : constant Float := MX * HX + MZ * HZ;
         Side  : constant Float := abs (MX * HZ - MZ * HX);
         --  best some 30 m ahead, on the street you are in; else (second
         --  try) any street close by, a little away from you
         D : constant Float :=
           (if Need_Ahead then abs (Ahead - 30.0) + 2.0 * Side
            else abs (Sqrt (MX * MX + MZ * MZ) - 25.0));
         L : constant Float := Sqrt ((BX - AX) ** 2 + (BZ - AZ) ** 2);
      begin
         if (not Need_Ahead or else (Ahead > 10.0 and then Side < 14.0))
           and then L > 3.0 and then D < Best_D and then not Is_Closed (VW, VS)
         then
            Best_D := D;
            W := VW;
            Seg := VS;
            Found := True;
         end if;
      end Visit;
      procedure Each is new For_Segment_Ids_Near (Visit);
   begin
      if not Seeded then
         Ada.Numerics.Float_Random.Reset (Gen);
         Seeded := True;
      end if;
      Each (Player.X, Player.Z, 70.0);
      if not Found then
         Need_Ahead := False;
         Each (Player.X, Player.Z, 70.0);
      end if;
      if not Found then
         return;
      end if;
      --  the way along the segment that goes away from you, where allowed
      declare
         Fwd : constant Link := (W, Seg, 1);
         Bwd : constant Link := (W, Seg + 1, -1);
         D   : constant Vec3 := Direction (Fwd);
         A   : constant Node := Point (W, Seg);
         B   : constant Node := Point (W, Seg + 1);
         MX  : constant Float := (A.X + B.X) / 2.0 - Player.X;
         MZ  : constant Float := (A.Z + B.Z) / 2.0 - Player.Z;
         Away_Fwd : constant Boolean := D.X * (MX + 5.0 * HX) + D.Z * (MZ + 5.0 * HZ) >= 0.0;
      begin
         if Ways (W).Oneway > 0 then
            Cur := Fwd;
         elsif Ways (W).Oneway < 0 then
            Cur := Bwd;
         else
            Cur := (if Away_Fwd then Fwd else Bwd);
         end if;
      end;
      T := 0.0;
      Speed := 6.0;
      Run_Left := 150.0 + 90.0 * Rnd;
      Out_Time := 0.0;
      Result := Going;
      Colour := Colours (Natural (Float'Floor (Rnd * 4.99)));
      On := True;
      Update (0.0, Player);
   end Start;

   procedure Update (Dt : Float; Player : Car.State) is
      P, Q : Node;
      Len  : Float;
   begin
      if not On then
         return;
      end if;
      Gap := Sqrt ((X - Player.X) ** 2 + (Z - Player.Z) ** 2);
      if Result = Going then
         Run_Left := Run_Left - Dt;
         if Run_Left <= 0.0 then
            Result := Stopped;
         end if;
         --  not a race: at about the limit, slower round the corners, and
         --  easing off when you fall far behind (but not waiting)
         declare
            Want : Float := Float'Min (14.0, 0.85 * Float (Ways (Cur.W).Limit) / 3.6 + 2.0);
         begin
            Segment (Cur, P, Q, Len);
            if Gap > 90.0 then
               Want := 0.7 * Want;
            elsif Gap < 15.0 then
               Want := Want + 2.0;              --  you are right behind: it hurries
            end if;
            Speed := Speed + Float'Max (-6.0 * Dt, Float'Min (3.0 * Dt, Want - Speed));
         end;
         T := T + Speed * Dt;
         Segment (Cur, P, Q, Len);
         while T > Len loop
            T := T - Len;
            declare
               Before : constant Vec3 := Direction (Cur);
            begin
               Choose_Next;
               --  a real turn: round it slowly
               if Dot (Before, Direction (Cur)) < 0.7 then
                  Speed := Float'Min (Speed, 6.0);
               end if;
            end;
            Segment (Cur, P, Q, Len);
            exit when Len < 0.01;
         end loop;
      else
         Speed := Float'Max (0.0, Speed - 5.0 * Dt);   --  pulls in and stops
         T := Float'Min (T + Speed * Dt, Float'Max (0.0, Len - 1.0));
         Segment (Cur, P, Q, Len);
      end if;
      declare
         D : constant Vec3 := Direction (Cur);
         --  keep to the right of the middle of the street
         Lane : constant Float := (if Ways (Cur.W).Oneway = 0 then Ways (Cur.W).Width / 4.0 else 0.0)
           + (if Result = Stopped then 1.0 else 0.0);
         NX : constant Float := P.X + D.X * T - D.Z * Lane;
         NZ : constant Float := P.Z + D.Z * T + D.X * Lane;
      begin
         if Dt > 0.0 then
            --  smooth the corners a little
            X := X + Float'Min (1.0, 8.0 * Dt) * (NX - X);
            Z := Z + Float'Min (1.0, 8.0 * Dt) * (NZ - Z);
            H := Arctan (D.X, -D.Z);
         else
            X := NX;
            Z := NZ;
            H := Arctan (D.X, -D.Z);
         end if;
      end;
      --  out of reach for too long: lost (not once it has stopped and you
      --  are on your way to it)
      if Gap > Reach and then Result = Going then
         Out_Time := Out_Time + Dt;
         if Out_Time > Give_Up then
            Result := Lost;
         end if;
      else
         Out_Time := Float'Max (0.0, Out_Time - 0.5 * Dt);
      end if;
   end Update;

   procedure Draw (Model, Paint : GL.GLint) is
   begin
      if not On or else Result = Lost then
         return;
      end if;
      Shaders.Set (Paint, Colour);
      Shaders.Set (Model, Car.Model_Matrix (Car.On_Ground (X, Z, H)));
      Car.Draw_Model (Car.Modern);
   end Draw;

end Chase;
