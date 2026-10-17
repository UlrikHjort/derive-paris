--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;
with System.Storage_Elements;

with GL;
with Shaders;

package body Tyre_Effects is

   use GL;
   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Program : GLuint := 0;
   U_View_Proj, U_Cam, U_Scale, U_Points, U_Color : GLint;

   --  Vertex: x, y, z, alpha, size
   Floats : constant := 5;

   --  Skid marks: a ring of quads (two triangles each)
   Max_Marks  : constant := 6000;
   Mark_Data  : array (0 .. Max_Marks * 6 * Floats - 1) of aliased Float := (others => 0.0);
   Next_Mark  : Natural := 0;
   Mark_Count : Natural := 0;
   Dirty_From, Dirty_To : Integer := -1;   --  marks to upload
   Mark_VAO, Mark_VBO : aliased GLuint := 0;

   --  Four tracks: rear left, rear right, front left, front right
   type Track is record
      Active : Boolean := False;
      Last   : Vec3 := (0.0, 0.0, 0.0);
   end record;
   Tracks : array (1 .. 4) of Track;

   --  Smoke puffs
   Max_Puffs : constant := 500;
   type Puff is record
      Pos, Vel : Vec3 := (0.0, 0.0, 0.0);
      Age, Life : Float := 0.0;
      Size     : Float := 0.0;
      Thick    : Float := 0.0;
   end record;
   Puffs     : array (1 .. Max_Puffs) of Puff;
   Next_Puff : Positive := 1;
   Puff_Data : array (0 .. Max_Puffs * Floats - 1) of aliased Float;
   Puff_VAO, Puff_VBO : aliased GLuint := 0;
   Smoke_Due : Float := 0.0;
   Gen       : Ada.Numerics.Float_Random.Generator;

   function Rnd return Float is (Ada.Numerics.Float_Random.Random (Gen) * 2.0 - 1.0);

   procedure Make_Buffer (VAO, VBO : access GLuint; Bytes : Natural) is
      Stride : constant GLsizei := GLsizei (Floats * 4);
   begin
      glGenVertexArrays (1, VAO.all'Address);
      glBindVertexArray (VAO.all);
      glGenBuffers (1, VBO.all'Address);
      glBindBuffer (GL_ARRAY_BUFFER, VBO.all);
      glBufferData (GL_ARRAY_BUFFER, GLsizeiptr (Bytes), System.Null_Address, GL_DYNAMIC_DRAW);
      glVertexAttribPointer (0, 3, GL_FLOAT, GL_FALSE, Stride,
                             System.Storage_Elements.To_Address (0));
      glEnableVertexAttribArray (0);
      glVertexAttribPointer (1, 2, GL_FLOAT, GL_FALSE, Stride,
                             System.Storage_Elements.To_Address (12));
      glEnableVertexAttribArray (1);
      glBindVertexArray (0);
   end Make_Buffer;

   procedure Create is
   begin
      Program := Shaders.Load_Program ("shaders/effects.vert", "shaders/effects.frag");
      U_View_Proj := Shaders.Location (Program, "uViewProj");
      U_Cam := Shaders.Location (Program, "uCamPos");
      U_Scale := Shaders.Location (Program, "uPointScale");
      U_Points := Shaders.Location (Program, "uPoints");
      U_Color := Shaders.Location (Program, "uColor");
      Make_Buffer (Mark_VAO'Access, Mark_VBO'Access, Mark_Data'Length * 4);
      Make_Buffer (Puff_VAO'Access, Puff_VBO'Access, Puff_Data'Length * 4);
      Ada.Numerics.Float_Random.Reset (Gen, 7);
   end Create;

   procedure Add_Mark (A, B : Vec3; Alpha : Float) is
      DX : constant Float := B.X - A.X;
      DZ : constant Float := B.Z - A.Z;
      L  : constant Float := Float'Max (0.001, Sqrt (DX * DX + DZ * DZ));
      PX : constant Float := -DZ / L * 0.11;
      PZ : constant Float := DX / L * 0.11;
      Y  : constant Float := A.Y + 0.025;
      Base : constant Natural := Next_Mark * 6 * Floats;
      procedure Put (I : Natural; X, Z : Float) is
      begin
         Mark_Data (Base + I * Floats .. Base + I * Floats + 4) := (X, Y, Z, Alpha, 0.0);
      end Put;
   begin
      Put (0, A.X - PX, A.Z - PZ);
      Put (1, A.X + PX, A.Z + PZ);
      Put (2, B.X + PX, B.Z + PZ);
      Put (3, A.X - PX, A.Z - PZ);
      Put (4, B.X + PX, B.Z + PZ);
      Put (5, B.X - PX, B.Z - PZ);
      if Dirty_From < 0 or else Next_Mark < Dirty_From then
         Dirty_From := Next_Mark;
      end if;
      Dirty_To := Integer'Max (Dirty_To, Next_Mark);
      Next_Mark := (Next_Mark + 1) mod Max_Marks;
      Mark_Count := Natural'Min (Max_Marks, Mark_Count + 1);
   end Add_Mark;

   procedure Update (S : Car.State; Wet : Float; Dt : Float) is
      Spinning : constant Boolean := S.Spin > 1.0;
      Sliding  : constant Boolean := S.Skid > 0.3 and then abs S.Speed > 2.0;
      Strength : constant Float :=
        Float'Min (1.0, Float'Max (S.Skid, S.Spin / 5.0)) * (1.0 - 0.6 * Wet);
   begin
      for I in Tracks'Range loop
         declare
            T    : Track renames Tracks (I);
            Rear : constant Boolean := I <= 2;
            P    : constant Vec3 :=
              (if Rear then Car.Rear_Wheel (S, I = 2) else Car.Front_Wheel (S, I = 4));
            On   : constant Boolean := Sliding or else (Rear and then Spinning);
         begin
            if not On then
               T.Active := False;
            elsif not T.Active then
               T.Active := True;
               T.Last := P;
            elsif (P.X - T.Last.X) ** 2 + (P.Z - T.Last.Z) ** 2 > 0.3 ** 2 then
               Add_Mark (T.Last, P, 0.2 + 0.45 * Strength);
               T.Last := P;
            end if;
         end;
      end loop;

      --  Smoke from spinning rear tyres, a little from sliding ones
      declare
         Rate : constant Float :=
           (if Spinning then 25.0 + 12.0 * S.Spin elsif Sliding then 12.0 * S.Skid else 0.0)
           * (1.0 - 0.8 * Wet);
      begin
         Smoke_Due := Smoke_Due + Rate * Dt;
         while Smoke_Due >= 1.0 loop
            Smoke_Due := Smoke_Due - 1.0;
            declare
               P : constant Vec3 := Car.Rear_Wheel (S, Rnd > 0.0);
            begin
               Puffs (Next_Puff) :=
                 (Pos   => (P.X + 0.2 * Rnd, P.Y + 0.3, P.Z + 0.2 * Rnd),
                  Vel   => (0.8 * Rnd - 0.3 * Sin (S.Heading) * S.Speed,
                            0.5 + 0.3 * Rnd,
                            0.8 * Rnd + 0.3 * Cos (S.Heading) * S.Speed),
                  Age   => 0.0,
                  Life  => 2.5 + 1.5 * Rnd,
                  Size  => 0.45 + 0.15 * Rnd,
                  Thick => (if Spinning then 0.35 else 0.2));
               Next_Puff := (if Next_Puff = Max_Puffs then 1 else Next_Puff + 1);
            end;
         end loop;
      end;
      for P of Puffs loop
         if P.Age < P.Life then
            P.Age := P.Age + Dt;
            P.Pos := P.Pos + Dt * P.Vel;
            P.Vel := (P.Vel.X * (1.0 - 1.5 * Dt), P.Vel.Y * (1.0 - 0.6 * Dt) + 0.15 * Dt,
                      P.Vel.Z * (1.0 - 1.5 * Dt));
            P.Size := P.Size + 1.2 * Dt;   --  spreads out
         end if;
      end loop;
   end Update;

   procedure Draw_Marks (VP : Mat4; Cam : Vec3) is
   begin
      if Mark_Count = 0 then
         return;
      end if;
      glUseProgram (Program);
      if Dirty_From >= 0 then
         glBindBuffer (GL_ARRAY_BUFFER, Mark_VBO);
         glBufferSubData (GL_ARRAY_BUFFER, GLintptr (Dirty_From * 6 * Floats * 4),
                          GLsizeiptr ((Dirty_To - Dirty_From + 1) * 6 * Floats * 4),
                          Mark_Data (Dirty_From * 6 * Floats)'Address);
         Dirty_From := -1;
         Dirty_To := -1;
      end if;
      Shaders.Set (U_View_Proj, VP);
      Shaders.Set (U_Cam, Cam);
      Shaders.Set (U_Points, 0);
      Shaders.Set (U_Color, Vec3'(0.025, 0.025, 0.03));
      glEnable (GL_BLEND);
      glBlendFunc (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
      glDepthMask (GL_FALSE);
      glDepthFunc (GL_LEQUAL);
      glEnable (GL_POLYGON_OFFSET_FILL);
      glPolygonOffset (GLfloat (-2.0), GLfloat (-2.0));
      glBindVertexArray (Mark_VAO);
      glDrawArrays (GL_TRIANGLES, 0, GLsizei (Mark_Count * 6));
      glBindVertexArray (0);
      glDisable (GL_POLYGON_OFFSET_FILL);
      glDepthFunc (GL_LESS);
      glDepthMask (GL_TRUE);
      glDisable (GL_BLEND);
   end Draw_Marks;

   procedure Draw_Smoke (VP : Mat4; Cam : Vec3; Pixels_Per_Metre : Float; Light : Float) is
      N : Natural := 0;
   begin
      for P of Puffs loop
         if P.Age < P.Life then
            declare
               Fade : constant Float := P.Age / P.Life;
               A    : constant Float :=
                 P.Thick * Float'Min (1.0, P.Age * 8.0) * (1.0 - Fade) * (1.0 - Fade);
            begin
               Puff_Data (N * Floats .. N * Floats + 4) :=
                 (P.Pos.X, P.Pos.Y, P.Pos.Z, A, P.Size);
               N := N + 1;
            end;
         end if;
      end loop;
      if N = 0 then
         return;
      end if;
      glUseProgram (Program);
      glBindBuffer (GL_ARRAY_BUFFER, Puff_VBO);
      glBufferSubData (GL_ARRAY_BUFFER, 0, GLsizeiptr (N * Floats * 4), Puff_Data'Address);
      Shaders.Set (U_View_Proj, VP);
      Shaders.Set (U_Cam, Cam);
      Shaders.Set (U_Points, 1);
      Shaders.Set (U_Scale, Pixels_Per_Metre);
      Shaders.Set (U_Color, (0.25 + 0.65 * Light) * Vec3'(1.0, 1.0, 1.0));
      glEnable (GL_PROGRAM_POINT_SIZE);
      glEnable (GL_BLEND);
      glBlendFunc (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
      glDepthMask (GL_FALSE);
      glBindVertexArray (Puff_VAO);
      glDrawArrays (GL_POINTS, 0, GLsizei (N));
      glBindVertexArray (0);
      glDepthMask (GL_TRUE);
      glDisable (GL_BLEND);
      glDisable (GL_PROGRAM_POINT_SIZE);
   end Draw_Smoke;

end Tyre_Effects;
