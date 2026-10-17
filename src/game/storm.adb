--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;
with System.Storage_Elements;

with Geo;
with GL;
with Shaders;
with Sound;

package body Storm is

   use GL;
   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Gen : Ada.Numerics.Float_Random.Generator;
   function Rnd return Float is (Ada.Numerics.Float_Random.Random (Gen));
   function Sym return Float is (2.0 * Rnd - 1.0);

   Program : GLuint := 0;
   U_View_Proj, U_Cam, U_Scale, U_Points, U_Color, U_Fade : GLint;
   VAO, VBO : aliased GLuint := 0;

   --  The bolt: a main channel and a few branches, as line segments
   Max_Segs : constant := 160;
   type Segment is record
      A, B   : Vec3;
      Bright : Float;   --  the main channel 1, branches less
   end record;
   Segs  : array (1 .. Max_Segs) of Segment;
   Count : Natural := 0;

   Floats : constant := 5;
   Data : array (0 .. Max_Segs * 12 * Floats - 1) of aliased Float := (others => 0.0);

   Age       : Float := 10.0;   --  seconds since the strike
   Strokes   : Natural := 3;    --  return strokes: the bolt flickers
   Strength  : Float := 0.0;    --  flash at your place
   Next      : Float := 3.0;
   Eiffel    : Vec3;

   procedure Create is
      X, Z : Long_Float;
   begin
      Program := Shaders.Load_Program ("shaders/effects.vert", "shaders/effects.frag");
      U_View_Proj := Shaders.Location (Program, "uViewProj");
      U_Cam := Shaders.Location (Program, "uCamPos");
      U_Scale := Shaders.Location (Program, "uPointScale");
      U_Points := Shaders.Location (Program, "uPoints");
      U_Color := Shaders.Location (Program, "uColor");
      U_Fade := Shaders.Location (Program, "uFadeFar");
      glGenVertexArrays (1, VAO'Address);
      glBindVertexArray (VAO);
      glGenBuffers (1, VBO'Address);
      glBindBuffer (GL_ARRAY_BUFFER, VBO);
      glBufferData (GL_ARRAY_BUFFER, GLsizeiptr (Data'Length * 4), System.Null_Address,
                    GL_DYNAMIC_DRAW);
      glVertexAttribPointer (0, 3, GL_FLOAT, GL_FALSE, 20, System.Storage_Elements.To_Address (0));
      glEnableVertexAttribArray (0);
      glVertexAttribPointer (1, 2, GL_FLOAT, GL_FALSE, 20, System.Storage_Elements.To_Address (12));
      glEnableVertexAttribArray (1);
      glBindVertexArray (0);
      Ada.Numerics.Float_Random.Reset (Gen);
      Geo.To_Local (48.858222, 2.294500, X, Z);
      Eiffel := (Float (X), 300.0, Float (Z));
   end Create;

   --  A jagged channel from From down to To, with side branches
   procedure Channel (From, To : Vec3; Bright : Float; Depth : Natural) is
      N    : constant Positive := (if Depth = 0 then 26 else 9);
      P    : Vec3 := From;
      Span : constant Float := Length (To - From);
   begin
      for I in 1 .. N loop
         exit when Count >= Max_Segs;
         declare
            T : constant Float := Float (I) / Float (N);
            Q : Vec3 := From + T * (To - From);
         begin
            if I < N then
               Q := Q + (0.06 * Span / Float (N) * 4.0) * Vec3'(Sym, 0.3 * Sym, Sym);
            end if;
            Count := Count + 1;
            Segs (Count) := (P, Q, Bright);
            --  a branch now and then, wandering off and dying out
            if Depth = 0 and then I < N - 3 and then Rnd < 0.18 then
               Channel (Q, Q + Vec3'(Span * 0.25 * Sym, -Span * (0.12 + 0.2 * Rnd), Span * 0.25 * Sym),
                        Bright * 0.45, 1);
            end if;
            P := Q;
         end;
      end loop;
   end Channel;

   procedure Bolt (Ground, Listener : Vec3);

   procedure Strike_At (Ground, Listener : Vec3) is
   begin
      Bolt (Ground, Listener);
   end Strike_At;

   procedure Strike (Listener : Vec3; Distance : Float := -1.0) is
      D : constant Float :=
        (if Distance >= 0.0 then Distance
         elsif Rnd < 0.1 then 200.0 + 400.0 * Rnd else 700.0 + 4500.0 * Rnd);
      A : constant Float := 2.0 * Ada.Numerics.Pi * Rnd;
      Ground : Vec3 := (Listener.X + D * Cos (A), 0.0, Listener.Z + D * Sin (A));
   begin
      --  the Eiffel Tower is struck often: it is the highest point around
      if Length (Ground - Vec3'(Eiffel.X, 0.0, Eiffel.Z)) < 2500.0 and then Rnd < 0.3 then
         Ground := Eiffel;
      end if;
      Bolt (Ground, Listener);
   end Strike;

   procedure Bolt (Ground, Listener : Vec3) is
   begin
      Count := 0;
      Channel (Ground + Vec3'(300.0 * Sym, 900.0, 300.0 * Sym), Ground, 1.0, 0);
      Age := 0.0;
      Strokes := 2 + Natural (Float'Floor (3.0 * Rnd));
      declare
         R : constant Float := Length (Vec3'(Ground.X, 0.0, Ground.Z) - Vec3'(Listener.X, 0.0, Listener.Z));
      begin
         Strength := Float'Min (1.0, 1600.0 / (R + 600.0));
         Sound.Thunder (Delay_S  => R / 343.0,
                        Loudness => Float'Min (1.0, 900.0 / (R + 300.0)),
                        Close    => R < 900.0);
      end;
   end Bolt;

   --  The bolt flickers: a few strokes in a third of a second
   function Lit return Float is
   begin
      if Age > 0.08 * Float (Strokes) + 0.1 then
         return 0.0;
      end if;
      declare
         Phase : constant Float := Age / 0.08 - Float'Floor (Age / 0.08);
      begin
         return (if Phase < 0.45 then 1.0 else 0.15);
      end;
   end Lit;

   function Flash return Float is (Strength * Lit);

   procedure Update (Dt : Float; Active : Boolean; Listener : Vec3) is
   begin
      Age := Age + Dt;
      if Active then
         Next := Next - Dt;
         if Next <= 0.0 then
            Strike (Listener);
            Next := 4.0 + 12.0 * Rnd;
         end if;
      else
         Next := 2.0 + 4.0 * Rnd;
      end if;
   end Update;

   procedure Draw (VP : Mat4; Cam : Vec3) is
      L : constant Float := Lit;
      N : Natural := 0;
      procedure Put (P : Vec3; Alpha : Float) is
      begin
         Data (N * Floats .. N * Floats + 4) := (P.X, P.Y, P.Z, Alpha, 0.0);
         N := N + 1;
      end Put;
   begin
      if L <= 0.0 or else Count = 0 then
         return;
      end if;
      --  each segment as a strip turned to the camera: a bright core and a
      --  wide faint glow; wider far away, so it stays visible
      for Pass in 1 .. 2 loop
         for I in 1 .. Count loop
            declare
               S    : Segment renames Segs (I);
               Dir  : constant Vec3 := S.B - S.A;
               Mid  : constant Vec3 := 0.5 * (S.A + S.B);
               Dist : constant Float := Length (Mid - Cam);
               Side : Vec3 := Cross (Dir, Mid - Cam);
               W    : constant Float := Float'Max (1.5, Dist * 0.0012)
                 * (if Pass = 1 then 7.0 else 1.0) * (0.5 + 0.5 * S.Bright);
               A    : constant Float := L * S.Bright * (if Pass = 1 then 0.12 else 1.0);
            begin
               if Length (Side) > 0.001 then
                  Side := (W / Length (Side)) * Side;
                  Put (S.A - Side, A);
                  Put (S.A + Side, A);
                  Put (S.B + Side, A);
                  Put (S.A - Side, A);
                  Put (S.B + Side, A);
                  Put (S.B - Side, A);
               end if;
            end;
         end loop;
      end loop;
      glUseProgram (Program);
      glBindBuffer (GL_ARRAY_BUFFER, VBO);
      glBufferSubData (GL_ARRAY_BUFFER, 0, GLsizeiptr (N * Floats * 4), Data'Address);
      Shaders.Set (U_View_Proj, VP);
      Shaders.Set (U_Cam, Cam);
      Shaders.Set (U_Points, 0);
      Shaders.Set (U_Fade, 1.0E6);
      Shaders.Set (U_Scale, 1.0);
      Shaders.Set (U_Color, Vec3'(0.85, 0.88, 1.0));
      glEnable (GL_BLEND);
      glBlendFunc (GL_SRC_ALPHA, GL_ONE);
      glDepthMask (GL_FALSE);
      glBindVertexArray (VAO);
      glDrawArrays (GL_TRIANGLES, 0, GLsizei (N));
      glBindVertexArray (0);
      glDepthMask (GL_TRUE);
      glDisable (GL_BLEND);
   end Draw;

end Storm;
