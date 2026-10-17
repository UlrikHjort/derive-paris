--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;
with System.Storage_Elements;

with Almanac;
with Geo;
with GL;
with Shaders;
with Sound;

package body Sky_Life is

   use GL;
   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Pi : constant := Ada.Numerics.Pi;

   Gen : Ada.Numerics.Float_Random.Generator;
   function Rnd return Float is (Ada.Numerics.Float_Random.Random (Gen));
   function Sym return Float is (2.0 * Rnd - 1.0);

   Program : GLuint := 0;
   U_View_Proj, U_Scale : GLint;
   VAO, VBO : aliased GLuint := 0;

   Floats : constant := 8;   --  x y z  r g b a  size
   Max_Points : constant := 9000;
   Data : array (0 .. Max_Points * Floats - 1) of aliased Float := (others => 0.0);
   Count : Natural := 0;

   procedure Put (P : Vec3; C : Vec3; A, Size : Float) is
   begin
      if Count < Max_Points then
         Data (Count * Floats .. Count * Floats + 7) := (P.X, P.Y, P.Z, C.X, C.Y, C.Z, A, Size);
         Count := Count + 1;
      end if;
   end Put;

   ---------------------------------------------------------------------------
   --  Aeroplanes
   ---------------------------------------------------------------------------

   type Aeroplane is record
      Active : Boolean := False;
      Pos, Vel : Vec3 := (0.0, 0.0, 0.0);
      Phase  : Float := 0.0;
   end record;
   Planes : array (1 .. 5) of Aeroplane;
   Clock  : Float := 0.0;

   procedure Spawn_Plane (P : in out Aeroplane; Near : Vec3) is
      A  : constant Float := 2.0 * Pi * Rnd;
      R  : constant Float := 7000.0;
      Start  : constant Vec3 := (Near.X + R * Cos (A), 1300.0 + 2200.0 * Rnd, Near.Z + R * Sin (A));
      Target : constant Vec3 := (Near.X + 3000.0 * Sym, Start.Y, Near.Z + 3000.0 * Sym);
   begin
      P := (Active => True, Pos => Start,
            Vel => (70.0 + 45.0 * Rnd) * Normalize (Target - Start),
            Phase => 5.0 * Rnd);
   end Spawn_Plane;

   ---------------------------------------------------------------------------
   --  Fireworks
   ---------------------------------------------------------------------------

   type Spark_Kind is (Rocket, Trail, Star, Glitter);
   type Spark is record
      Kind     : Spark_Kind := Star;
      Alive    : Boolean := False;
      Pos, Vel : Vec3 := (0.0, 0.0, 0.0);
      Colour   : Vec3 := (1.0, 1.0, 1.0);
      Age, Life : Float := 0.0;
      Drag     : Float := 1.0;
      Shell    : Integer := 0;   --  rockets: what they burst into
   end record;
   Sparks : array (1 .. 7000) of Spark;
   Next_Spark : Positive := 1;

   procedure Add (S : Spark) is
   begin
      Sparks (Next_Spark) := S;
      Next_Spark := (if Next_Spark = Sparks'Last then 1 else Next_Spark + 1);
   end Add;

   Palette : constant array (1 .. 7) of Vec3 :=
     ((1.0, 0.25, 0.2), (0.3, 1.0, 0.35), (1.0, 0.75, 0.3), (0.35, 0.55, 1.0),
      (1.0, 1.0, 1.0), (0.85, 0.35, 1.0), (1.0, 0.5, 0.15));
   --  bleu, blanc, rouge for the 14th of July
   Tricolore : constant array (1 .. 3) of Vec3 :=
     ((0.25, 0.4, 1.0), (1.0, 1.0, 1.0), (1.0, 0.2, 0.2));

   Show_On     : Boolean := False;
   Show_Centre : Vec3;
   Show_Big    : Boolean := False;
   Show_Left   : Float := 0.0;     --  seconds
   Next_Launch : Float := 0.0;
   Ear         : Vec3 := (0.0, 0.0, 0.0);
   French      : Boolean := False; --  tricolour shells

   function Show_Running return Boolean is (Show_On);

   Dust_Due : Float := 0.0;

   procedure Magic_Dust (Where : Vec3; Dt : Float) is
   begin
      Dust_Due := Dust_Due + 18.0 * Dt;
      while Dust_Due >= 1.0 loop
         Dust_Due := Dust_Due - 1.0;
         Add ((Kind => Trail, Alive => True,
               Pos => Where + Vec3'(0.6 * Sym, 0.3 * Sym, 0.6 * Sym),
               Vel => (0.3 * Sym, -0.3 - 0.3 * Rnd, 0.3 * Sym),
               Colour => (if Rnd < 0.7 then Vec3'(0.9, 0.7, 0.3) else Vec3'(0.9, 0.9, 0.8)),
               Age => 0.0, Life => 0.8 + 0.8 * Rnd, Drag => 1.5, Shell => 0));
      end loop;
   end Magic_Dust;

   procedure Start_Show (Centre : Vec3; Big : Boolean) is
   begin
      Show_On := True;
      Show_Centre := Centre;
      Show_Big := Big;
      Show_Left := (if Big then 240.0 else 75.0);
      Next_Launch := 0.5;
   end Start_Show;

   --  The bang reaches you later the further away you are
   procedure Bang (P : Vec3; Big : Boolean) is
      D : constant Float := Length (P - Ear);
   begin
      Sound.Boom (Delay_S => D / 343.0, Loudness => Float'Min (1.0, 400.0 / (D + 150.0)),
                  Big => Big);
   end Bang;

   procedure Burst (P : Vec3; Shell : Integer) is
      Kind  : constant Integer := Shell mod 4;   --  peony, ring, willow, glitter
      N     : constant Natural := (if Show_Big then 220 else 120);
      Speed : constant Float := (if Show_Big then 60.0 else 38.0) * (0.8 + 0.4 * Rnd);
      C1    : constant Vec3 :=
        (if French then Tricolore (1 + Shell / 4 mod 3) else Palette (1 + Shell / 4 mod 7));
      C2    : constant Vec3 :=
        (if French then Tricolore (1 + (Shell / 4 + 1) mod 3) else Palette (1 + (Shell / 4 + 3) mod 7));
      Ring_Axis : constant Vec3 := Normalize ((Sym, 0.6 + Rnd, Sym));
   begin
      for I in 1 .. N loop
         declare
            --  a random direction on a sphere
            Z  : constant Float := Sym;
            A  : constant Float := 2.0 * Pi * Rnd;
            R  : constant Float := Sqrt (Float'Max (0.0, 1.0 - Z * Z));
            D  : Vec3 := (R * Cos (A), Z, R * Sin (A));
            V  : Float := Speed * (0.85 + 0.15 * Rnd);
         begin
            if Kind = 1 then
               --  a ring: directions flattened onto a plane
               D := Normalize (D - Dot (D, Ring_Axis) * Ring_Axis);
            end if;
            if Kind = 2 then
               V := V * 0.7;
            end if;
            Add ((Kind   => (if Kind = 3 then Glitter else Star),
                  Alive  => True, Pos => P, Vel => V * D,
                  Colour => (if Kind = 2 then Vec3'(1.0, 0.7, 0.3)
                             elsif I mod 2 = 0 then C1 else C2),
                  Age    => 0.0,
                  Life   => (if Kind = 2 then 3.5 else 1.8) + 0.8 * Rnd,
                  Drag   => (if Kind = 2 then 1.6 else 1.1),
                  Shell  => 0));
         end;
      end loop;
      Bang (P, Show_Big);
   end Burst;

   procedure Launch is
      Base : constant Vec3 :=
        Show_Centre + Vec3'((if Show_Big then 120.0 else 15.0) * Sym, 0.0,
                            (if Show_Big then 120.0 else 15.0) * Sym);
   begin
      Add ((Kind => Rocket, Alive => True,
            Pos => Base + Vec3'(0.0, 2.0, 0.0),
            Vel => ((if Show_Big then 12.0 else 5.0) * Sym,
                    (if Show_Big then 58.0 else 36.0) + 14.0 * Rnd,
                    (if Show_Big then 12.0 else 5.0) * Sym),
            Colour => (1.0, 0.75, 0.4), Age => 0.0, Life => 8.0, Drag => 0.05,
            Shell => Integer (Rnd * 1000.0)));
   end Launch;

   --  Shows that the calendar brings, and the odd surprise
   Last_Hour   : Float := -1.0;
   Night_Rolled : Boolean := False;
   Surprise_At : Float := -1.0;

   procedure Schedule (Hour, Night : Float; Near : Vec3) is
      function Crossed (H : Float) return Boolean is
        (Last_Hour >= 0.0 and then Last_Hour < H and then Hour >= H
         and then Hour - Last_Hour < 1.0);
      X, Z : Long_Float;
   begin
      if not Show_On then
         --  the 14th of July: at the Eiffel Tower at eleven
         if Almanac.Bastille_Day and then Crossed (23.0) then
            Geo.To_Local (48.85826, 2.29450, X, Z);
            French := True;
            Start_Show ((Float (X), 0.0, Float (Z)), Big => True);
         --  New Year: at the Arc de Triomphe at midnight
         elsif Almanac.Month = 1 and then Almanac.Day = 1 and then Hour < 0.5
           and then Last_Hour > 23.0
         then
            Geo.To_Local (48.87378, 2.29504, X, Z);
            French := False;
            Start_Show ((Float (X), 0.0, Float (Z)), Big => True);
         end if;
      end if;
      --  once a night there may be a small show somewhere: a wedding, a
      --  birthday, a football victory
      if Hour > 12.0 and then Hour < 21.0 then
         Night_Rolled := False;
      elsif Hour >= 21.0 and then not Night_Rolled then
         Night_Rolled := True;
         Surprise_At := (if Rnd < 0.35 then 22.0 + 2.5 * Rnd else -1.0);
         if Surprise_At >= 24.0 then
            Surprise_At := Surprise_At - 24.0;
         end if;
      end if;
      if Surprise_At >= 0.0 and then Night > 0.6 and then not Show_On
        and then Crossed (Surprise_At)
      then
         declare
            A : constant Float := 2.0 * Pi * Rnd;
            D : constant Float := 500.0 + 1800.0 * Rnd;
         begin
            French := False;
            Start_Show ((Near.X + D * Cos (A), 0.0, Near.Z + D * Sin (A)), Big => False);
            Surprise_At := -1.0;
         end;
      end if;
      Last_Hour := Hour;
   end Schedule;

   procedure Create is
   begin
      Program := Shaders.Load_Program ("shaders/sparks.vert", "shaders/sparks.frag");
      U_View_Proj := Shaders.Location (Program, "uViewProj");
      U_Scale := Shaders.Location (Program, "uPointScale");
      glGenVertexArrays (1, VAO'Address);
      glBindVertexArray (VAO);
      glGenBuffers (1, VBO'Address);
      glBindBuffer (GL_ARRAY_BUFFER, VBO);
      glBufferData (GL_ARRAY_BUFFER, GLsizeiptr (Data'Length * 4), System.Null_Address,
                    GL_DYNAMIC_DRAW);
      glVertexAttribPointer (0, 3, GL_FLOAT, GL_FALSE, 32,
                             System.Storage_Elements.To_Address (0));
      glEnableVertexAttribArray (0);
      glVertexAttribPointer (1, 4, GL_FLOAT, GL_FALSE, 32,
                             System.Storage_Elements.To_Address (12));
      glEnableVertexAttribArray (1);
      glVertexAttribPointer (2, 1, GL_FLOAT, GL_FALSE, 32,
                             System.Storage_Elements.To_Address (28));
      glEnableVertexAttribArray (2);
      glBindVertexArray (0);
      Ada.Numerics.Float_Random.Reset (Gen);
   end Create;

   Started : Boolean := False;

   procedure Update (Dt, Hour, Night : Float; Listener : Vec3) is
   begin
      if not Started then
         --  some already on their way
         Started := True;
         for I in 1 .. 3 loop
            Spawn_Plane (Planes (I), Listener);
            Planes (I).Pos := Planes (I).Pos + (3000.0 + 6000.0 * Rnd) / Length (Planes (I).Vel)
              * Planes (I).Vel;
         end loop;
      end if;
      Clock := Clock + Dt;
      Ear := Listener;

      --  aeroplanes: a few at a time, always somewhere
      for P of Planes loop
         if not P.Active then
            if Rnd < Dt / 20.0 then
               Spawn_Plane (P, Listener);
            end if;
         else
            P.Pos := P.Pos + Dt * P.Vel;
            if (P.Pos.X - Listener.X) ** 2 + (P.Pos.Z - Listener.Z) ** 2 > 7600.0 ** 2 then
               P.Active := False;
            end if;
         end if;
      end loop;

      Schedule (Hour, Night, Listener);
      if Show_On then
         Show_Left := Show_Left - Dt;
         Next_Launch := Next_Launch - Dt;
         if Next_Launch <= 0.0 and then Show_Left > 4.0 then
            Launch;
            --  the finale: many at once
            Next_Launch := (if Show_Left < 25.0 and then Show_Big then 0.12 + 0.2 * Rnd
                            elsif Show_Big then 0.4 + 1.2 * Rnd else 1.0 + 2.5 * Rnd);
         end if;
         if Show_Left <= 0.0 then
            Show_On := False;
         end if;
      end if;

      for S of Sparks loop
         if S.Alive then
            S.Age := S.Age + Dt;
            S.Pos := S.Pos + Dt * S.Vel;
            S.Vel := (1.0 - S.Drag * Dt) * S.Vel + Vec3'(0.0, -9.8 * Dt * (if S.Kind = Rocket then 1.0 else 0.35), 0.0);
            case S.Kind is
               when Rocket =>
                  --  a fizzing tail on the way up, then the burst
                  if Rnd < 0.7 then
                     Add ((Kind => Trail, Alive => True, Pos => S.Pos,
                           Vel => (2.0 * Sym, -3.0, 2.0 * Sym), Colour => (1.0, 0.7, 0.35),
                           Age => 0.0, Life => 0.4 + 0.3 * Rnd, Drag => 2.0, Shell => 0));
                  end if;
                  if S.Vel.Y < 8.0 then
                     S.Alive := False;
                     Burst (S.Pos, S.Shell);
                  end if;
               when others =>
                  if S.Age >= S.Life then
                     S.Alive := False;
                  end if;
            end case;
         end if;
      end loop;
   end Update;

   procedure Draw (VP : Mat4; Pixels_Per_Metre, Night : Float) is
   begin
      Count := 0;
      if Night > 0.3 then
         for P of Planes loop
            if P.Active then
               declare
                  T     : constant Float := Clock + P.Phase;
                  Dir   : constant Vec3 := Normalize (P.Vel);
                  Right : constant Vec3 := Normalize (Cross (Dir, (0.0, 1.0, 0.0)));
                  Strobe : constant Boolean :=
                    T - 1.3 * Float'Floor (T / 1.3) < 0.05
                    or else (T - 1.3 * Float'Floor (T / 1.3) in 0.15 .. 0.2);
                  Beacon : constant Boolean := T - Float'Floor (T) < 0.12;
               begin
                  Put (P.Pos - 17.0 * Right, (1.0, 0.15, 0.1), 0.7, 6.0);   --  left: red
                  Put (P.Pos + 17.0 * Right, (0.2, 1.0, 0.3), 0.7, 6.0);    --  right: green
                  if Strobe then
                     Put (P.Pos - 17.0 * Right, (1.0, 1.0, 1.0), 2.0, 14.0);
                     Put (P.Pos + 17.0 * Right, (1.0, 1.0, 1.0), 2.0, 14.0);
                  end if;
                  if Beacon then
                     Put (P.Pos + Vec3'(0.0, 3.0, 0.0), (1.0, 0.1, 0.05), 1.4, 10.0);
                  end if;
               end;
            end if;
         end loop;
      end if;
      for S of Sparks loop
         if S.Alive then
            declare
               F : constant Float := S.Age / S.Life;
               A : Float;
            begin
               case S.Kind is
                  when Rocket => A := 1.2;
                  when Trail => A := 0.8 * (1.0 - F);
                  when Star => A := 1.6 * (1.0 - F * F);
                  when Glitter =>
                     A := (if Rnd < 0.5 then 2.0 else 0.15) * (1.0 - F);
               end case;
               Put (S.Pos, S.Colour, A,
                    (case S.Kind is when Rocket => 2.5, when Trail => 1.5,
                                    when others => (if Show_Big then 6.0 else 4.0)));
            end;
         end if;
      end loop;
      if Count = 0 then
         return;
      end if;
      glUseProgram (Program);
      glBindBuffer (GL_ARRAY_BUFFER, VBO);
      glBufferSubData (GL_ARRAY_BUFFER, 0, GLsizeiptr (Count * Floats * 4), Data'Address);
      Shaders.Set (U_View_Proj, VP);
      Shaders.Set (U_Scale, Pixels_Per_Metre);
      glEnable (GL_PROGRAM_POINT_SIZE);
      glEnable (GL_BLEND);
      glBlendFunc (GL_ONE, GL_ONE);
      glDepthMask (GL_FALSE);
      glBindVertexArray (VAO);
      glDrawArrays (GL_POINTS, 0, GLsizei (Count));
      glBindVertexArray (0);
      glDepthMask (GL_TRUE);
      glDisable (GL_BLEND);
      glDisable (GL_PROGRAM_POINT_SIZE);
   end Draw;

end Sky_Life;
