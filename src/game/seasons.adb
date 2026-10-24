--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Environment_Variables;
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;

with Ada.Containers.Vectors;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Almanac;
with Geo;
with Meshes;
with River;
with Road_Network;
with Shaders;
with Terrain;

package body Seasons is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   function Env (Name : String) return String is
     (if Ada.Environment_Variables.Exists (Name) then Ada.Environment_Variables.Value (Name) else "");

   Mist_Now, Heat_Now, Flood_Now : Float := 0.0;
   Water_Y : Float := 0.0;    --  the river's level near the camera
   Rise_Day : Integer := -1;   --  the day the sunrise was found for
   Sunrise : Float := 7.0;

   function Mist return Float is (Mist_Now);
   function Heat return Float is (Heat_Now);
   function Flood return Float is (Flood_Now);

   function Smooth (A, B, X : Float) return Float is
      T : constant Float := Float'Max (0.0, Float'Min (1.0, (X - A) / (B - A)));
   begin
      return T * T * (3.0 - 2.0 * T);
   end Smooth;

   ---------------------------------------------------------------------------
   --  The lower quays in a flood: the roads down by the water ("Port de
   --  ...", the Voie Georges-Pompidou, the "Berges") close, with barriers
   --  where the streets above lead down to them

   type Barrier is record
      X, Z   : Float;     --  across the road here
      DX, DZ : Float;     --  along the road, into the closed part
      Half   : Float;     --  half the road's width
   end record;
   package Barrier_Vectors is new Ada.Containers.Vectors (Positive, Barrier);
   Barriers : Barrier_Vectors.Vector;

   type Bool_Array is array (Natural range <>) of Boolean;
   type Bool_Access is access Bool_Array;
   Low_Way : Bool_Access;          --  the ways closed for the flood
   Quays_Closed : Boolean := False;
   Pending_News : Ada.Strings.Unbounded.Unbounded_String;

   function News return String is
      N : constant String := Ada.Strings.Unbounded.To_String (Pending_News);
   begin
      Pending_News := Ada.Strings.Unbounded.Null_Unbounded_String;
      return N;
   end News;

   function Down_By_The_Water (W : Natural) return Boolean is
      use Road_Network;
      Name : constant String := Ada.Strings.Unbounded.To_String (Ways (W).Name);
      function Starts (P : String) return Boolean is
        (Name'Length >= P'Length and then Name (Name'First .. Name'First + P'Length - 1) = P);
   begin
      if not (Starts ("Port ") or else Starts ("Voie Georges") or else Starts ("Berge")
              or else Starts ("Promenade") or else Ada.Strings.Fixed.Index (Name, "berges") > 0)
      then
         return False;
      end if;
      --  and by the Seine (not a "Promenade" anywhere in town)
      declare
         P : constant Node := Point (W, Ways (W).Count / 2);
         X, Z, DX, DZ : Float;
      begin
         River.At_Distance (River.Distance_Of (P.X, P.Z), X, Z, DX, DZ);
         return (P.X - X) ** 2 + (P.Z - Z) ** 2 < 140.0 ** 2;
      end;
   end Down_By_The_Water;

   procedure Close_Quays is
      use Road_Network;
   begin
               end;
            end if;
         end loop;
      end if;
      Low_Way := new Bool_Array (Ways'Range);
      for W in Ways'Range loop
         Low_Way (W) := Ways (W).Count >= 2 and then Down_By_The_Water (W);
      end loop;
      Barriers.Clear;
      for W in Ways'Range loop
         if Low_Way (W) then
            for Pos in 0 .. Ways (W).Count - 2 loop
               Close (W, Pos);
            end loop;
            --  a barrier at each end that meets a street still open
            for End_Pos of Int_Array'(0, Ways (W).Count - 1) loop
               declare
                  N : constant Natural := Node_Index (W, End_Pos);
                  Open_Way : Boolean := False;
               begin
                  for L of Walk_Links (N) loop
                     if not Low_Way (L.W) then
                        Open_Way := True;
                     end if;
                  end loop;
                  if Open_Way then
                     declare
                        A : constant Node := Point (W, End_Pos);
                        B : constant Node := Point (W, (if End_Pos = 0 then 1 else End_Pos - 1));
                        L : constant Float := Float'Max (0.01, Sqrt ((B.X - A.X) ** 2 + (B.Z - A.Z) ** 2));
                        DX : constant Float := (B.X - A.X) / L;
                        DZ : constant Float := (B.Z - A.Z) / L;
                        In_By : constant Float := Float'Min (5.0, L / 2.0);
                     begin
                        Barriers.Append ((A.X + In_By * DX, A.Z + In_By * DZ, DX, DZ, Ways (W).Width / 2.0 + 0.5));
                     end;
                  end if;
               end;
            end loop;
         end if;
      end loop;
      declare
         N : Natural := 0;
      begin
         for W in Ways'Range loop
            if Low_Way (W) then
               N := N + 1;
            end if;
         end loop;
         Ada.Text_IO.Put_Line ("Closed for the flood:" & Natural'Image (N) & " ways,"
                               & Natural'Image (Natural (Barriers.Length)) & " barriers");
      end;
      Quays_Closed := True;
      Pending_News := Ada.Strings.Unbounded.To_Unbounded_String
        ("Crue de la Seine : the lower quays are closed");
   end Close_Quays;

   procedure Open_Quays is
      use Road_Network;
   begin
      for W in Ways'Range loop
         if Low_Way (W) then
            for Pos in 0 .. Ways (W).Count - 2 loop
               Reopen (W, Pos);
            end loop;
         end if;
      end loop;
      Barriers.Clear;
      Quays_Closed := False;
      Pending_News := Ada.Strings.Unbounded.To_Unbounded_String
        ("The Seine goes down: the lower quays are open again");
   end Open_Quays;

   procedure Update (Dt, Hour, Rain : Float; Cam : Vec3) is
      Want_Mist, Want_Heat : Float;
      Today : constant Integer := Almanac.Month * 31 + Almanac.Day;
   begin
      if Today /= Rise_Day then
         Rise_Day := Today;
         Sunrise := 3.0;
         while Sunrise < 10.0 and then Almanac.Sun (Sunrise).Y < 0.0 loop
            Sunrise := Sunrise + 1.0 / 30.0;
         end loop;
      end if;

      --  the mist gathers in the small hours, lies thickest at dawn, and
      --  lifts as the sun warms the river
      Want_Mist := (if Env ("PARIS_MIST") /= "" or else Almanac.Misty_Morning then 1.0 else 0.0)
        * Smooth (1.5, 4.0, Hour) * (1.0 - Smooth (Sunrise + 0.75, Sunrise + 2.75, Hour))
        * (1.0 - Float'Min (1.0, 2.0 * Rain));
      if Env ("PARIS_MIST") /= "" then
         Want_Mist := Float'Max (Want_Mist, 1.0 - Float'Min (1.0, 2.0 * Rain));
      end if;

      --  the heat: the hot weeks, most days, the afternoon, no rain
      Want_Heat := (if Env ("PARIS_HEAT") /= "" then 1.0
                    else Almanac.Summer_Heat * (if (Today * 31 + 7) mod 10 < 7 then 1.0 else 0.3)
                         * Smooth (11.0, 14.0, Hour) * (1.0 - Smooth (18.5, 20.5, Hour)))
        * (1.0 - Float'Min (1.0, 3.0 * Rain));

      --  (slowly: a change of weather or a jump in the clock eases in)
      Mist_Now := Mist_Now + (Want_Mist - Mist_Now) * Float'Min (1.0, Dt * 0.3);
      Heat_Now := Heat_Now + (Want_Heat - Heat_Now) * Float'Min (1.0, Dt * 0.3);

      Flood_Now := (if Env ("PARIS_FLOOD") /= "" then Float'Value (Env ("PARIS_FLOOD")) else Almanac.Flood_Rise);

      if Road_Network.Loaded then
         if not Quays_Closed and then Flood_Now > 1.0 then
            Close_Quays;
         elsif Quays_Closed and then Flood_Now < 0.8 then
            Open_Quays;
         end if;
      end if;

      --  the water's level where the camera is, for the mist
      if River.Points >= 2 then
         declare
            X, Z, DX, DZ : Float;
         begin
            River.At_Distance (River.Distance_Of (Cam.X, Cam.Z), X, Z, DX, DZ);
            Water_Y := Terrain.Height (X, Z) - River.Depth + Flood_Now;
         end;
      end if;
   exception
      when Constraint_Error => null;   --  a bad PARIS_FLOOD
   end Update;

   procedure Set_Uniforms (Mist, Mist_Y, Heat, Blossom, Petals, Flood, Seine, Seine_N : GL.GLint) is
      use type GL.GLint;
      N : constant Natural := Natural'Min (64, River.Points);
      P : array (0 .. 127) of GL.GLfloat := (others => 0.0);
   begin
      Shaders.Set (Mist, Mist_Now);
      Shaders.Set (Mist_Y, Water_Y);
      Shaders.Set (Heat, Heat_Now);
      Shaders.Set (Blossom, Almanac.Blossom);
      Shaders.Set (Petals, Almanac.Petals);
      Shaders.Set (Flood, Flood_Now);
      if Flood_Now > 0.0 and then Seine >= 0 then
         for I in 1 .. N loop
            declare
               X, Z : Float;
            begin
               River.Point_At (I, X, Z);
               P (2 * (I - 1)) := GL.GLfloat (X);
               P (2 * (I - 1) + 1) := GL.GLfloat (Z);
            end;
         end loop;
         GL.glUniform2fv (Seine, GL.GLsizei (N), P'Address);
         Shaders.Set (Seine_N, Integer (N));
      else
         Shaders.Set (Seine_N, Integer'(0));
      end if;
   end Set_Uniforms;

   ---------------------------------------------------------------------------
   --  The Zouave of the Pont de l'Alma (Georges Diebolt, 1856), on the
   --  upstream face of the pier by the right bank: Parisians read the
   --  floods on him, at his feet, his knees, in 1910 his shoulders

   Zouave_Lat : constant := 48.863800;
   Zouave_Lon : constant := 2.302040;
   Feet_Above : constant := 3.0;   --  his feet over the usual level of the river

   Statue, Sheet, Fence : Meshes.Mesh;
   Built : Boolean := False;
   ZX, ZZ, ZY : Float := 0.0;

   procedure Build is
      use Meshes;
      Stone : constant := 90.0;
      Water : constant := 6.0;
      X, Z : Long_Float;
   begin
      Geo.To_Local (Zouave_Lat, Zouave_Lon, X, Z);
      ZX := Float (X);
      ZZ := Float (Z);
      ZY := Terrain.Height (ZX, ZZ) - River.Depth + Feet_Above;

      --  front is -Z; some 5 m tall, on a ledge of the pier
      Start;
      Box (-1.3, 1.3, -Feet_Above - 2.0, 0.0, -1.1, 1.4, Stone);            --  the pier's ledge
      Box (-0.62, -0.12, 0.0, 0.55, -0.45, 0.35, Stone);                    --  gaiters and feet
      Box (0.12, 0.62, 0.0, 0.55, -0.45, 0.35, Stone);
      Box (-0.8, 0.8, 0.5, 2.55, -0.55, 0.55, Stone,
           Top_Inset_X => 0.12, Top_Inset_Front => 0.1, Top_Inset_Back => 0.1);   --  the baggy saroual
      Box (-0.68, 0.68, 2.5, 2.85, -0.45, 0.45, Stone);                     --  the sash
      Box (-0.7, 0.7, 2.85, 4.15, -0.42, 0.4, Stone,
           Top_Inset_X => 0.08, Top_Inset_Front => 0.05);                   --  the short jacket
      Box (-0.95, -0.7, 2.55, 4.05, -0.25, 0.25, Stone, Top_Inset_X => 0.03);  --  arms
      Box (0.7, 0.95, 2.55, 4.05, -0.25, 0.25, Stone, Top_Inset_X => 0.03);
      Box (-0.3, 0.3, 4.1, 4.3, -0.25, 0.25, Stone);                        --  neck
      Box (-0.3, 0.3, 4.3, 4.85, -0.32, 0.28, Stone);                       --  head
      Box (-0.26, 0.26, 4.05, 4.5, -0.42, -0.3, Stone, Top_Inset_X => 0.05);   --  the beard
      Box (-0.32, 0.32, 4.8, 5.15, -0.3, 0.28, Stone, Top_Inset_X => 0.03,
           Top_Inset_Front => 0.03, Top_Inset_Back => 0.03);                --  the chéchia
      Box (0.18, 0.3, 4.6, 5.0, 0.2, 0.32, Stone);                          --  its tassel
      Finish (Statue);

      --  the flood over the lower quays: a sheet of water across the
      --  river's bed along its middle line, at the usual level (the vertex
      --  shader lifts it, as all the river's water)
      Start;
      declare
         Half : constant Float := 70.0;
         Across : constant := 7;              --  strips across, to follow the ground
         Len  : constant Float := River.Length;
         Step : constant Float := 15.0;
         S    : Float := 0.0;
         PX, PZ, PDX, PDZ : Float;
         --  a point across the river (K = 0 .. Across), at the water's level
         --  there (like the tiles' water: so far below the ground)
         function Across_At (X, Z, DX, DZ : Float; K : Natural) return Vec3 is
            Off : constant Float := Half * (2.0 * Float (K) / Float (Across) - 1.0);
            QX  : constant Float := X - Off * DZ;
            QZ  : constant Float := Z + Off * DX;
         begin
            return (QX, Terrain.Height (QX, QZ) - River.Depth - 0.03, QZ);
         end Across_At;
      begin
         River.At_Distance (0.0, PX, PZ, PDX, PDZ);
         while S < Len loop
            declare
               S2 : constant Float := Float'Min (Len, S + Step);
               X, Z, DX, DZ : Float;
            begin
               River.At_Distance (S2, X, Z, DX, DZ);
               for K in 0 .. Across - 1 loop
                  declare
                     A : constant Vec3 := Across_At (PX, PZ, PDX, PDZ, K);
                     B : constant Vec3 := Across_At (PX, PZ, PDX, PDZ, K + 1);
                     C : constant Vec3 := Across_At (X, Z, DX, DZ, K + 1);
                     D : constant Vec3 := Across_At (X, Z, DX, DZ, K);
                  begin
                     Quad (A, B, C, D, Water);
                     Quad (D, C, B, A, Water);
                  end;
               end loop;
               PX := X;
               PZ := Z;
               PDX := DX;
               PDZ := DZ;
               S := S2;
            end;
         end loop;
      end;
      Finish (Sheet);

      --  a barrier one metre either side of the middle (scaled to the
      --  road): feet, and a panel striped red and white
      Start;
      for K in 0 .. 9 loop
         declare
            X0 : constant Float := -1.0 + 0.2 * Float (K);
         begin
            Box (X0, X0 + 0.2, 0.55, 1.0, -0.03, 0.03, (if K mod 2 = 0 then 86.0 else 80.0));
         end;
      end loop;
      Box (-1.0, -0.96, 0.0, 0.55, -0.03, 0.03, 80.0);
      Box (0.96, 1.0, 0.0, 0.55, -0.03, 0.03, 80.0);
      Box (-1.0, 1.0, 0.0, 0.05, -0.25, 0.25, 17.0);
      Finish (Fence);
      Built := True;
   end Build;

   procedure Draw (Model, Paint : GL.GLint; Cam : Vec3) is
      pragma Unreferenced (Paint);
   begin
      if River.Points < 2 then
         return;
      end if;
      if not Built then
         Build;
      end if;
      if (Cam.X - ZX) ** 2 + (Cam.Z - ZZ) ** 2 < 900.0 ** 2 then
         Shaders.Set (Model, Translation ((ZX, ZY, ZZ)) * Rotation_Y (-Ada.Numerics.Pi / 2.0));   --  facing upstream
         Meshes.Draw (Statue);
      end if;
      if Flood_Now > 0.3 then
         --  (the world program lifts it with the rest of the Seine's water)
         Shaders.Set (Model, Identity);
         Meshes.Draw (Sheet);
      end if;
      --  the barriers: red and white panels on feet across the road
      for B of Barriers loop
         if (B.X - Cam.X) ** 2 + (B.Z - Cam.Z) ** 2 < 400.0 ** 2 then
            declare
               Y : constant Float := Terrain.Height (B.X, B.Z);
            begin
               Shaders.Set (Model, Translation ((B.X, Y, B.Z)) * Rotation_Y (-Arctan (B.DX, -B.DZ))
                            * Scale_XYZ (B.Half, 1.0, 1.0));
               Meshes.Draw (Fence);
            end;
         end if;
      end loop;
      Shaders.Set (Model, Identity);
   end Draw;

   procedure Collide (S : in out Car.State) is
   begin
      for B of Barriers loop
         if (B.X - S.X) ** 2 + (B.Z - S.Z) ** 2 < (B.Half + 3.0) ** 2 then
            declare
               --  across the road (along X of the fence) and along it
               U : constant Float := (S.X - B.X) * (-B.DZ) + (S.Z - B.Z) * B.DX;
               V : constant Float := (S.X - B.X) * B.DX + (S.Z - B.Z) * B.DZ;
            begin
               if abs U < B.Half and then abs V < 1.6 then
                  declare
                     Out_By : constant Float := (if V >= 0.0 then 1.6 - V else -1.6 - V);
                  begin
                     S.X := S.X + Out_By * B.DX;
                     S.Z := S.Z + Out_By * B.DZ;
                     S.Speed := S.Speed * 0.3;
                     S.Bumped := True;
                  end;
               end if;
            end;
         end if;
      end loop;
   end Collide;

end Seasons;
