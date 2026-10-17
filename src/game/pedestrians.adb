--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;

with Math3D;
with Meshes;
with Road_Network;
with Shaders;

package body Pedestrians is

   use Ada.Numerics.Elementary_Functions;
   use Math3D;
   use Road_Network;

   Max_Walkers : constant := 400;
   Limit       : Natural := 160;
   Spawn_Near  : constant := 30.0;
   Spawn_Far   : constant := 150.0;
   Retire_Far  : constant := 190.0;
   Hip         : constant := 0.92;

   type Walker is record
      Active  : Boolean := False;
      Cur     : Link;
      T       : Float := 0.0;
      Side    : Float := 1.0;          --  +1 right of the way, -1 left
      Offset  : Float := 5.0;          --  from the centre line
      Speed   : Float := 1.3;
      X, Z    : Float := 0.0;
      Heading : Float := 0.0;
      Phase   : Float := 0.0;          --  walk cycle
      Dodge_X, Dodge_Z : Float := 0.0; --  stepping aside for the car
      Shirt, Skin, Legs : Vec3 := (0.5, 0.5, 0.5);
      Santa   : Boolean := False;
      Greeted : Boolean := False;
   end record;

   Santas_On : Boolean := False;
   Mat_Fur   : constant := 39.0;   --  white fur trim and beard

   Walkers : array (1 .. Max_Walkers) of Walker;
   Gen     : Ada.Numerics.Float_Random.Generator;
   Primed  : Boolean := False;

   Body_Mesh, Left_Leg, Right_Leg, Santa_Mesh : Meshes.Mesh;

   Santa_Share : Float := 0.035;

   procedure Set_Santas (On : Boolean; Share : Float := 0.035) is
   begin
      Santas_On := On;
      Santa_Share := Share;
   end Set_Santas;

   Shirts : constant array (0 .. 9) of Vec3 :=
     ((0.10, 0.10, 0.12), (0.80, 0.80, 0.78), (0.18, 0.22, 0.40), (0.50, 0.12, 0.12),
      (0.35, 0.33, 0.30), (0.62, 0.52, 0.36), (0.15, 0.30, 0.22), (0.70, 0.62, 0.20),
      (0.25, 0.25, 0.28), (0.55, 0.30, 0.45));
   Skins : constant array (0 .. 4) of Vec3 :=
     ((0.86, 0.68, 0.56), (0.76, 0.57, 0.44), (0.58, 0.40, 0.29),
      (0.40, 0.27, 0.19), (0.92, 0.76, 0.64));
   Trousers : constant array (0 .. 4) of Vec3 :=
     ((0.10, 0.12, 0.20), (0.08, 0.08, 0.09), (0.30, 0.28, 0.25),
      (0.20, 0.27, 0.40), (0.45, 0.40, 0.32));

   function Rnd return Float is (Ada.Numerics.Float_Random.Random (Gen));

   procedure Set_Density (Factor : Float) is
   begin
      Limit := Natural (Float'Max (0.0, Float'Min (Float (Max_Walkers), 160.0 * Factor)));
   end Set_Density;

   function Count return Natural is
      N : Natural := 0;
   begin
      for I in Walkers'Range loop
         if I > Limit then
            Walkers (I).Active := False;
         end if;
      end loop;
      for W of Walkers (1 .. Limit) loop
         if W.Active then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Count;

   procedure Create_Mesh is
      use Meshes;
   begin
      Start;
      Box (-0.2, 0.2, 0.9, 1.45, -0.12, 0.12, Mat_Cloth, Top_Inset_X => 0.03);
      Box (-0.27, -0.2, 0.86, 1.42, -0.07, 0.07, Mat_Cloth);
      Box (0.2, 0.27, 0.86, 1.42, -0.07, 0.07, Mat_Cloth);
      Box (-0.05, 0.05, 1.45, 1.52, -0.05, 0.05, Mat_Skin);
      Box (-0.1, 0.1, 1.5, 1.73, -0.11, 0.1, Mat_Skin);
      Box (-0.105, 0.105, 1.66, 1.77, -0.08, 0.115, Mat_Tyre);   --  hair
      Finish (Body_Mesh);
      --  Father Christmas: the same body in red, with a beard, a belt and a
      --  hat with a pompom (front is -Z)
      Start;
      Box (-0.2, 0.2, 0.9, 1.45, -0.12, 0.12, Mat_Cloth, Top_Inset_X => 0.03);
      Box (-0.27, -0.2, 0.86, 1.42, -0.07, 0.07, Mat_Cloth);
      Box (0.2, 0.27, 0.86, 1.42, -0.07, 0.07, Mat_Cloth);
      Box (-0.205, 0.205, 0.86, 0.94, -0.125, 0.125, Mat_Fur);       --  hem
      Box (-0.21, 0.21, 1.02, 1.08, -0.13, 0.13, Mat_Tyre);          --  belt
      Box (-0.05, 0.05, 1.45, 1.52, -0.05, 0.05, Mat_Skin);
      Box (-0.1, 0.1, 1.5, 1.73, -0.11, 0.1, Mat_Skin);
      Box (-0.11, 0.11, 1.38, 1.62, -0.15, -0.08, Mat_Fur);          --  beard
      Box (-0.115, 0.115, 1.71, 1.78, -0.125, 0.12, Mat_Fur);        --  hat brim
      Box (-0.1, 0.1, 1.78, 1.92, -0.09, 0.11, Mat_Cloth,
           Top_Inset_X => 0.06, Top_Inset_Front => 0.08, Top_Inset_Back => 0.02);
      Box (-0.04, 0.04, 1.88, 1.96, 0.06, 0.14, Mat_Fur);            --  pompom
      Finish (Santa_Mesh);
      for Side in 0 .. 1 loop
         declare
            X0 : constant Float := (if Side = 0 then -0.18 else 0.02);
         begin
            Start;
            Box (X0, X0 + 0.16, 0.08, Hip, -0.08, 0.08, Mat_Trousers);
            Box (X0, X0 + 0.16, 0.0, 0.08, -0.15, 0.08, Mat_Tyre);
            if Side = 0 then
               Finish (Left_Leg);
            else
               Finish (Right_Leg);
            end if;
         end;
      end loop;
   end Create_Mesh;

   function Place (W : Walker) return Vec3 is
      P, Q : Node;
      Len  : Float;
      D    : constant Vec3 := Direction (W.Cur);
   begin
      Segment (W.Cur, P, Q, Len);
      return (P.X + D.X * W.T - D.Z * W.Side * W.Offset + W.Dodge_X, 0.0,
              P.Z + D.Z * W.T + D.X * W.Side * W.Offset + W.Dodge_Z);
   end Place;

   procedure Choose_Next (W : in out Walker) is
      End_Node : constant Natural := Node_Index (W.Cur.W, W.Cur.Pos + W.Cur.Dir);
      Options  : Natural := 0;
      Pick     : Natural;
   begin
      for L of Walk_Links (End_Node) loop
         if not (L.W = W.Cur.W and then L.Dir = -W.Cur.Dir) then
            Options := Options + 1;
         end if;
      end loop;
      if Options = 0 then
         --  dead end: turn round, staying on the same sidewalk
         W.Cur := (W.Cur.W, W.Cur.Pos + W.Cur.Dir, -W.Cur.Dir);
         W.Side := -W.Side;
         return;
      end if;
      Pick := Natural'Min (Options - 1, Natural (Float'Floor (Rnd * Float (Options))));
      for L of Walk_Links (End_Node) loop
         if not (L.W = W.Cur.W and then L.Dir = -W.Cur.Dir) then
            if Pick = 0 then
               if L.W /= W.Cur.W then
                  W.Offset := Ways (L.W).Width / 2.0 + 1.2 + 0.6 * Rnd;
               end if;
               W.Cur := L;
               return;
            end if;
            Pick := Pick - 1;
         end if;
      end loop;
   end Choose_Next;

   procedure Spawn (W : in out Walker; Focus_X, Focus_Z, Focus_Heading, Near : Float) is
   begin
      for Attempt in 1 .. 20 loop
         declare
            Way_I, Seg : Natural;
            Got   : Boolean;
            P, Q  : Node;
            Len   : Float;
         begin
            Pick_Segment (Focus_X, Focus_Z, Near, Spawn_Far, Rnd, Rnd, Rnd, Got, Way_I, Seg);
            if Got then
               declare
                  L  : constant Link :=
                    (if Rnd < 0.5 then (Way_I, Seg, 1) else (Way_I, Seg + 1, -1));
               begin
                  Segment (L, P, Q, Len);
                  declare
                     DX : constant Float := (P.X + Q.X) / 2.0 - Focus_X;
                     DZ : constant Float := (P.Z + Q.Z) / 2.0 - Focus_Z;
                     D  : constant Float := Sqrt (DX * DX + DZ * DZ);
                  begin
                     if Len > 3.0 and then D >= Near and then D <= Spawn_Far
                       and then not (Near > 20.0 and then D < 90.0
                                     and then (DX * Sin (Focus_Heading)
                                               - DZ * Cos (Focus_Heading)) / D > 0.5)
                     then
                        W := (Active => True, Cur => L, T => Rnd * Len,
                              Side => (if Rnd < 0.5 then 1.0 else -1.0),
                              Offset => Ways (Way_I).Width / 2.0 + 1.2 + 0.6 * Rnd,
                              Speed => 1.1 + 0.5 * Rnd,
                              Phase => 6.3 * Rnd,
                              Shirt => Shirts (Natural (Float'Floor (Rnd * 9.99))),
                              Skin => Skins (Natural (Float'Floor (Rnd * 4.99))),
                              Legs => Trousers (Natural (Float'Floor (Rnd * 4.99))),
                              others => <>);
                        if Santas_On and then Rnd < Santa_Share then
                           W.Santa := True;
                           W.Shirt := (0.72, 0.06, 0.06);
                           W.Legs := (0.62, 0.05, 0.05);
                           W.Skin := (0.92, 0.74, 0.62);
                           W.Speed := 0.9 + 0.3 * Rnd;   --  in no hurry
                        end if;
                        declare
                           Pos : constant Vec3 := Place (W);
                           Dir : constant Vec3 := Direction (W.Cur);
                        begin
                           W.X := Pos.X;
                           W.Z := Pos.Z;
                           W.Heading := Arctan (Dir.X, -Dir.Z);
                        end;
                        return;
                     end if;
                  end;
               end;
            end if;
         end;
      end loop;
   end Spawn;

   procedure Walk (W : in out Walker; Dt : Float; Player : Car.State) is
      P, Q : Node;
      Len  : Float;
   begin
      Segment (W.Cur, P, Q, Len);
      W.T := W.T + W.Speed * Dt;
      while W.T >= Len loop
         W.T := W.T - Len;
         Choose_Next (W);
         Segment (W.Cur, P, Q, Len);
      end loop;
      W.Phase := W.Phase + Dt * W.Speed * 4.2;

      --  Step aside when the car comes close; drift back afterwards
      declare
         AX : constant Float := W.X - Player.X;
         AZ : constant Float := W.Z - Player.Z;
         D  : constant Float := Sqrt (AX * AX + AZ * AZ);
      begin
         if D < 4.0 and then D > 0.01 and then abs Player.Speed > 0.5 then
            W.Dodge_X := W.Dodge_X + AX / D * 5.0 * Dt;
            W.Dodge_Z := W.Dodge_Z + AZ / D * 5.0 * Dt;
         else
            W.Dodge_X := W.Dodge_X * (1.0 - 0.5 * Dt);
            W.Dodge_Z := W.Dodge_Z * (1.0 - 0.5 * Dt);
         end if;
      end;

      declare
         Goal : constant Vec3 := Place (W);
         K    : constant Float := 1.0 - Exp (-Dt * 4.0);
         MX   : constant Float := Goal.X - W.X;
         MZ   : constant Float := Goal.Z - W.Z;
         Want : Float;
         Diff : Float;
      begin
         W.X := W.X + MX * K;
         W.Z := W.Z + MZ * K;
         if MX * MX + MZ * MZ > 0.0004 then
            Want := Arctan (MX, -MZ);
            Diff := Want - W.Heading;
            while Diff > Ada.Numerics.Pi loop
               Diff := Diff - 2.0 * Ada.Numerics.Pi;
            end loop;
            while Diff < -Ada.Numerics.Pi loop
               Diff := Diff + 2.0 * Ada.Numerics.Pi;
            end loop;
            W.Heading := W.Heading + Diff * K;
         end if;
      end;
   end Walk;

   procedure Update (Dt : Float; Focus_X, Focus_Z, Focus_Heading : Float;
                     Player : Car.State)
   is
      Spawned : Natural := 0;
   begin
      if not Loaded then
         return;
      end if;
      if not Primed then
         Ada.Numerics.Float_Random.Reset (Gen, 1789);
      end if;
      for I in Walkers'Range loop
         if I > Limit then
            Walkers (I).Active := False;
         end if;
      end loop;
      for W of Walkers (1 .. Limit) loop
         if W.Active then
            Walk (W, Dt, Player);
            if (W.X - Focus_X) ** 2 + (W.Z - Focus_Z) ** 2 > Retire_Far ** 2 then
               W.Active := False;
            end if;
         elsif not Primed or else Spawned < 3 then
            Spawn (W, Focus_X, Focus_Z, Focus_Heading, (if Primed then Spawn_Near else 5.0));
            Spawned := Spawned + 1;
         end if;
      end loop;
      Primed := True;
   end Update;

   procedure Draw (Model_Loc, Cloth_Loc, Skin_Loc, Legs_Loc : GL.GLint;
                   Near_X, Near_Z : Float; Max_Distance : Float)
   is
      use type GL.GLint;
   begin
      for W of Walkers loop
         if W.Active
           and then (W.X - Near_X) ** 2 + (W.Z - Near_Z) ** 2 < Max_Distance ** 2
         then
            declare
               Bob   : constant Float := 0.025 * abs Sin (W.Phase);
               M     : constant Mat4 :=
                 Translation ((W.X, Bob, W.Z)) * Rotation_Y (-W.Heading);
               Swing : constant Float := 0.45 * Sin (W.Phase);
            begin
               if Cloth_Loc >= 0 then
                  Shaders.Set (Cloth_Loc, W.Shirt);
                  Shaders.Set (Skin_Loc, W.Skin);
                  Shaders.Set (Legs_Loc, W.Legs);
               end if;
               Shaders.Set (Model_Loc, M);
               Meshes.Draw ((if W.Santa then Santa_Mesh else Body_Mesh));
               Shaders.Set (Model_Loc, M * Translation ((0.0, Hip, 0.0))
                            * Rotation_X (Swing) * Translation ((0.0, -Hip, 0.0)));
               Meshes.Draw (Left_Leg);
               Shaders.Set (Model_Loc, M * Translation ((0.0, Hip, 0.0))
                            * Rotation_X (-Swing) * Translation ((0.0, -Hip, 0.0)));
               Meshes.Draw (Right_Leg);
            end;
         end if;
      end loop;
   end Draw;

   procedure Santa_Near (X, Z : Float; Found : out Boolean; SX, SZ : out Float) is
   begin
      Found := False;
      SX := 0.0;
      SZ := 0.0;
      for W of Walkers loop
         if W.Active and then W.Santa and then not W.Greeted
           and then (W.X - X) ** 2 + (W.Z - Z) ** 2 < 9.0 ** 2
         then
            W.Greeted := True;
            Found := True;
            SX := W.X;
            SZ := W.Z;
            return;
         end if;
      end loop;
   end Santa_Near;

end Pedestrians;
