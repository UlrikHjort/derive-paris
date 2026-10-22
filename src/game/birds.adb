--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Containers.Vectors;
with Ada.Environment_Variables;
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;
with Ada.Text_IO;

with Geo;
with Meshes;
with Road_Network;
with Shaders;
with Sound;
with Terrain;

package body Birds is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Pi : constant := Ada.Numerics.Pi;
   Mat_Feather : constant := 30.0;   --  matt, in uCarColor

   Gen : Ada.Numerics.Float_Random.Generator;
   Seeded : Boolean := False;
   function Rnd return Float is (Ada.Numerics.Float_Random.Random (Gen));

   Clock : Float := 0.0;
   Day   : Boolean := True;

   ---------------------------------------------------------------------------
   --  The bird: a body along -Z, wings hinged at its sides

   Body_M, Wing_L, Wing_R : Meshes.Mesh;
   Built : Boolean := False;

   procedure Build is
   begin
      Meshes.Start;
      Meshes.Box (-0.05, 0.05, -0.05, 0.05, -0.14, 0.12, Mat_Feather);      --  body
      Meshes.Box (-0.035, 0.035, -0.01, 0.06, -0.21, -0.14, Mat_Feather);   --  head
      Meshes.Box (-0.04, 0.04, -0.02, 0.0, 0.12, 0.22, Mat_Feather);        --  tail
      Meshes.Finish (Body_M);
      Meshes.Start;
      Meshes.Box (-0.34, -0.05, 0.0, 0.012, -0.09, 0.07, Mat_Feather);
      Meshes.Finish (Wing_L);
      Meshes.Start;
      Meshes.Box (0.05, 0.34, 0.0, 0.012, -0.09, 0.07, Mat_Feather);
      Meshes.Finish (Wing_R);
      Built := True;
   end Build;

   procedure Bird (Model : GL.GLint; P : Vec3; Yaw, Bank, Size, Flap : Float) is
      M : constant Mat4 := Translation (P) * Rotation_Y (-Yaw) * Rotation_Z (Bank) * Scale (Size);
   begin
      Shaders.Set (Model, M);
      Meshes.Draw (Body_M);
      Shaders.Set (Model, M * Translation ((-0.05, 0.0, 0.0)) * Rotation_Z (Flap) * Translation ((0.05, 0.0, 0.0)));
      Meshes.Draw (Wing_L);
      Shaders.Set (Model, M * Translation ((0.05, 0.0, 0.0)) * Rotation_Z (-Flap) * Translation ((-0.05, 0.0, 0.0)));
      Meshes.Draw (Wing_R);
   end Bird;

   function Heading (D : Vec3) return Float is (Arctan (D.X, -D.Z));

   ---------------------------------------------------------------------------
   --  Flocks over the rooftops

   type Flock is record
      Anchor : Vec3 := (0.0, 0.0, 0.0);
      Radius, Height, Speed, Phase : Float := 0.0;
      Size   : Natural := 0;
      Set    : Boolean := False;
   end record;
   Flocks : array (1 .. 3) of Flock;

   function Flock_Point (F : Flock; T : Float) return Vec3 is
     (F.Anchor + Vec3'(F.Radius * Cos (F.Speed * T + F.Phase),
                       F.Height + 6.0 * Sin (0.27 * T + F.Phase),
                       0.7 * F.Radius * Sin (F.Speed * T + F.Phase)));

   ---------------------------------------------------------------------------
   --  Gulls along the river

   package Vec_Vectors is new Ada.Containers.Vectors (Positive, Vec3);
   River : Vec_Vectors.Vector;
   River_Read : Boolean := False;

   procedure Read_River is
      use Ada.Text_IO;
      F : File_Type;
      package F_IO is new Ada.Text_IO.Float_IO (Long_Float);
   begin
      River_Read := True;
      Open (F, In_File, "data/seine.txt");
      while not End_Of_File (F) loop
         declare
            Line : constant String := Get_Line (F);
         begin
            if Line'Length > 5 and then Line (Line'First) /= '#' then
               declare
                  Lat, Lon : Long_Float;
                  Last : Positive;
                  X, Z : Long_Float;
               begin
                  F_IO.Get (Line, Lat, Last);
                  F_IO.Get (Line (Last + 1 .. Line'Last), Lon, Last);
                  Geo.To_Local (Lat, Lon, X, Z);
                  River.Append ((Float (X), 0.0, Float (Z)));
               end;
            end if;
         end;
      end loop;
      Close (F);
   exception
      when others =>
         if Is_Open (F) then
            Close (F);
         end if;
   end Read_River;

   type Gull is record
      Seg    : Natural := 0;     --  along the river: segment and how far into it
      T      : Float := 0.0;
      Dir    : Float := 1.0;     --  downstream or up
      Side, Height, Speed, Phase : Float := 0.0;
      P, Last : Vec3 := (0.0, 0.0, 0.0);
   end record;
   Gulls : array (1 .. 9) of Gull;

   ---------------------------------------------------------------------------
   --  Sparrows on the pavement

   type Sparrow is record
      P, V  : Vec3 := (0.0, 0.0, 0.0);
      Yaw   : Float := 0.0;
      Hop   : Float := 0.0;     --  time to the next hop
      Up    : Float := 0.0;     --  > 0: flying off
   end record;
   type Sparrow_Array is array (1 .. 6) of Sparrow;
   type Group is record
      Birds : Sparrow_Array;
      Home  : Vec3 := (0.0, 0.0, 0.0);
      Set   : Boolean := False;
      Fled  : Boolean := False;
   end record;
   Groups : array (1 .. 5) of Group;

   procedure Place_Group (G : in out Group; Focus : Vec3) is
      Found : Boolean;
      W, Pos : Natural;
   begin
      G.Set := False;
      if Ada.Environment_Variables.Exists ("PARIS_SPARROWS") then   --  close by (testing)
         Road_Network.Pick_Segment (Focus.X, Focus.Z, 2.0, 14.0, Rnd, Rnd, Rnd, Found, W, Pos);
      else
         Road_Network.Pick_Segment (Focus.X, Focus.Z, 20.0, 110.0, Rnd, Rnd, Rnd, Found, W, Pos);
      end if;
      if not Found then
         return;
      end if;
      declare
         A : constant Road_Network.Node := Road_Network.Point (W, Pos);
         B : constant Road_Network.Node := Road_Network.Point (W, Pos + 1);
         L : constant Float := Float'Max (0.1, Sqrt ((B.X - A.X) ** 2 + (B.Z - A.Z) ** 2));
         T : constant Float := Rnd;
         S : constant Float := (if Rnd < 0.5 then -1.0 else 1.0);
         Off : constant Float := Road_Network.Ways (W).Width / 2.0 + 1.4 + 1.2 * Rnd;
         X : constant Float := A.X + T * (B.X - A.X) - S * Off * (B.Z - A.Z) / L;
         Z : constant Float := A.Z + T * (B.Z - A.Z) + S * Off * (B.X - A.X) / L;
      begin
         G.Home := (X, Terrain.Height (X, Z), Z);
         for Bd of G.Birds loop
            Bd := (P => G.Home + Vec3'(1.6 * (Rnd - 0.5), 0.0, 1.6 * (Rnd - 0.5)),
                   V => (0.0, 0.0, 0.0), Yaw => 2.0 * Pi * Rnd, Hop => Rnd, Up => 0.0);
         end loop;
         G.Set := True;
         G.Fled := False;
      end;
   end Place_Group;

   ---------------------------------------------------------------------------

   procedure Update (Dt : Float; Focus : Vec3; Hour : Float; Near : Vec3) is
   begin
      if not Seeded then
         Ada.Numerics.Float_Random.Reset (Gen);
         Seeded := True;
      end if;
      if not River_Read then
         Read_River;
      end if;
      Clock := Clock + Dt;
      Day := Hour > 6.5 and then Hour < 20.5;

      --  flocks: anchored near you, moved on when you are far
      for F of Flocks loop
         if not F.Set or else (F.Anchor.X - Focus.X) ** 2 + (F.Anchor.Z - Focus.Z) ** 2 > 600.0 ** 2 then
            declare
               A : constant Float := 2.0 * Pi * Rnd;
               D : constant Float := 150.0 + 250.0 * Rnd;
               X : constant Float := Focus.X + D * Cos (A);
               Z : constant Float := Focus.Z + D * Sin (A);
            begin
               F := (Anchor => (X, Terrain.Height (X, Z), Z), Radius => 50.0 + 70.0 * Rnd,
                     Height => 35.0 + 35.0 * Rnd, Speed => (0.06 + 0.05 * Rnd) * (if Rnd < 0.5 then -1.0 else 1.0),
                     Phase => 2.0 * Pi * Rnd, Size => 7 + Natural (8.0 * Rnd), Set => True);
            end;
            if Ada.Environment_Variables.Exists ("PARIS_FLOCK") then   --  close by (testing)
               F.Anchor := Focus + Vec3'(0.0, Terrain.Height (Focus.X, Focus.Z), -40.0);
               F.Radius := 20.0;
               F.Height := 14.0;
            end if;
         end if;
      end loop;

      --  gulls: glide along the river near you
      if Natural (River.Length) >= 2 then
         for G of Gulls loop
            if G.Seg = 0 or else (G.P.X - Focus.X) ** 2 + (G.P.Z - Focus.Z) ** 2 > 700.0 ** 2 then
               --  start near the closest bit of river
               declare
                  Best : Natural := 1;
                  BD   : Float := Float'Last;
               begin
                  for I in River.First_Index .. River.Last_Index - 1 loop
                     declare
                        D : constant Float := (River (I).X - Focus.X) ** 2 + (River (I).Z - Focus.Z) ** 2;
                     begin
                        if D < BD then
                           BD := D;
                           Best := I;
                        end if;
                     end;
                  end loop;
                  G := (Seg => Integer'Max (1, Integer'Min (River.Last_Index - 1,
                                                          Best + Integer (2.0 * (Rnd - 0.5)))),
                        T => Rnd, Dir => (if Rnd < 0.5 then -1.0 else 1.0),
                        Side => 30.0 * (Rnd - 0.5), Height => 8.0 + 14.0 * Rnd,
                        Speed => 6.0 + 4.0 * Rnd, Phase => 2.0 * Pi * Rnd, others => <>);
               end;
            end if;
            declare
               A : constant Vec3 := River (G.Seg);
               B : constant Vec3 := River (G.Seg + 1);
               L : constant Float := Float'Max (1.0, Length (B - A));
               D : constant Vec3 := (1.0 / L) * (B - A);
               N : constant Vec3 := (-D.Z, 0.0, D.X);
               W : constant Float := G.Side + 12.0 * Sin (0.2 * Clock + G.Phase);
               P : Vec3;
            begin
               G.T := G.T + G.Dir * G.Speed * Dt / L;
               if G.T > 1.0 then
                  if G.Seg + 1 < River.Last_Index then
                     G.Seg := G.Seg + 1;
                     G.T := 0.0;
                  else
                     G.Dir := -1.0;
                     G.T := 1.0;
                  end if;
               elsif G.T < 0.0 then
                  if G.Seg > River.First_Index then
                     G.Seg := G.Seg - 1;
                     G.T := 1.0;
                  else
                     G.Dir := 1.0;
                     G.T := 0.0;
                  end if;
               end if;
               P := A + G.T * (B - A) + W * N;
               P.Y := Terrain.Height (P.X, P.Z) + G.Height + 3.0 * Sin (0.33 * Clock + G.Phase);
               G.Last := G.P;
               G.P := P;
            end;
         end loop;
      end if;

      --  sparrows: hop about, and are off when you come near
      for G of Groups loop
         if not G.Set or else (G.Home.X - Focus.X) ** 2 + (G.Home.Z - Focus.Z) ** 2 > 160.0 ** 2
           or else (G.Fled and then G.Birds (1).Up > 4.0)
         then
            Place_Group (G, Focus);
         end if;
         if G.Set then
            if not G.Fled and then (Near.X - G.Home.X) ** 2 + (Near.Z - G.Home.Z) ** 2 < 6.5 ** 2 then
               G.Fled := True;
               Sound.Effect (Sound.Flutter, 0.5, 0.0);
               for Bd of G.Birds loop
                  declare
                     Away : constant Vec3 := Normalize (Bd.P - Near + Vec3'(0.01, 0.0, 0.0));
                  begin
                     Bd.V := Vec3'(5.0 * Away.X + 2.0 * (Rnd - 0.5), 3.0 + 2.0 * Rnd,
                                   5.0 * Away.Z + 2.0 * (Rnd - 0.5));
                     Bd.Yaw := Heading (Bd.V);
                     Bd.Up := 0.01;
                  end;
               end loop;
            end if;
            for Bd of G.Birds loop
               if Bd.Up > 0.0 then
                  Bd.Up := Bd.Up + Dt;
                  Bd.V.Y := Bd.V.Y + 1.5 * Dt;
                  Bd.P := Bd.P + Dt * Bd.V;
               else
                  Bd.Hop := Bd.Hop - Dt;
                  if Bd.Hop <= 0.0 then
                     Bd.Hop := 0.3 + 1.5 * Rnd;
                     Bd.Yaw := Bd.Yaw + 1.5 * (Rnd - 0.5);
                     declare
                        Step : constant Vec3 := 0.18 * Vec3'(Sin (Bd.Yaw), 0.0, -Cos (Bd.Yaw));
                        Q    : Vec3 := Bd.P + Step;
                     begin
                        if (Q.X - G.Home.X) ** 2 + (Q.Z - G.Home.Z) ** 2 > 1.4 ** 2 then
                           Bd.Yaw := Heading (G.Home - Bd.P);   --  back towards the others
                           Q := Bd.P;
                        end if;
                        Bd.P := (Q.X, Terrain.Height (Q.X, Q.Z), Q.Z);
                     end;
                  end if;
               end if;
            end loop;
         end if;
      end loop;
   end Update;

   procedure Draw (Model, Paint : GL.GLint; Cam : Vec3) is
      function Near (P : Vec3; R : Float) return Boolean is
        ((P.X - Cam.X) ** 2 + (P.Z - Cam.Z) ** 2 < R * R);
   begin
      if not Day then
         return;
      end if;
      if not Built then
         Build;
      end if;
      --  flocks: dark, flapping in bursts
      Shaders.Set (Paint, Vec3'(0.16, 0.16, 0.18));
      for F of Flocks loop
         if F.Set and then Near (F.Anchor, 900.0) then
            for K in 1 .. F.Size loop
               declare
                  Lag : constant Float := 0.9 * Float (K);
                  T   : constant Float := Clock - Lag / (abs F.Speed * F.Radius + 1.0) * 6.0;
                  P   : constant Vec3 := Flock_Point (F, T) + Vec3'(2.5 * Sin (Float (K) * 2.1 + Clock * 0.4),
                                                                   1.5 * Sin (Float (K) * 1.3), 2.5 * Cos (Float (K) * 3.7));
                  Ahead : constant Vec3 := Flock_Point (F, T + 0.5) - Flock_Point (F, T);
                  Beat  : constant Float := (if Sin (Clock * 0.7 + Float (K)) > -0.3
                                             then 0.6 * Sin (Clock * 14.0 + Float (K)) else 0.15);
               begin
                  Bird (Model, P, Heading (Ahead), -0.4 * Float'Copy_Sign (1.0, F.Speed), 1.5, Beat);
               end;
            end loop;
         end if;
      end loop;
      --  gulls: white, gliding, a slow beat now and then
      Shaders.Set (Paint, Vec3'(0.93, 0.93, 0.92));
      for G of Gulls loop
         if G.Seg > 0 and then Near (G.P, 700.0) then
            declare
               V : constant Vec3 := G.P - G.Last;
            begin
               Bird (Model, G.P, Heading (V), 0.15 * Sin (0.4 * Clock + G.Phase), 2.6,
                     (if Sin (0.5 * Clock + G.Phase) > 0.6 then 0.45 * Sin (Clock * 5.0) else 0.1));
            end;
         end if;
      end loop;
      --  sparrows: small and brown
      Shaders.Set (Paint, Vec3'(0.42, 0.3, 0.2));
      for G of Groups loop
         if G.Set and then Near (G.Home, 90.0) then
            for Bd of G.Birds loop
               Bird (Model, Bd.P + Vec3'(0.0, 0.05, 0.0),
                     Bd.Yaw, 0.0, 0.62, (if Bd.Up > 0.0 then 0.7 * Sin (Clock * 30.0) else 0.0));
            end loop;
         end if;
      end loop;
   end Draw;

end Birds;
