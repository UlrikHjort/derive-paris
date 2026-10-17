--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Float_Random;
with System.Storage_Elements;

with GL;
with Shaders;

package body Rain is

   use GL;

   Drops : constant := 7000;

   Program : GLuint := 0;
   VAO, VBO : aliased GLuint := 0;
   U_View_Proj, U_Cam, U_Time, U_Amount, U_Color, U_Snow, U_Scale : GLint;

   procedure Create is
      Gen  : Ada.Numerics.Float_Random.Generator;
      Data : array (0 .. Drops * 8 - 1) of aliased Float;
   begin
      Program := Shaders.Load_Program ("shaders/rain.vert", "shaders/rain.frag");
      U_View_Proj := Shaders.Location (Program, "uViewProj");
      U_Cam := Shaders.Location (Program, "uCamPos");
      U_Time := Shaders.Location (Program, "uTime");
      U_Amount := Shaders.Location (Program, "uAmount");
      U_Color := Shaders.Location (Program, "uColor");
      U_Snow := Shaders.Location (Program, "uSnow");
      U_Scale := Shaders.Location (Program, "uPointScale");

      Ada.Numerics.Float_Random.Reset (Gen, 42);
      for D in 0 .. Drops - 1 loop
         declare
            X : constant Float := Ada.Numerics.Float_Random.Random (Gen);
            Y : constant Float := Ada.Numerics.Float_Random.Random (Gen);
            Z : constant Float := Ada.Numerics.Float_Random.Random (Gen);
         begin
            Data (D * 8 .. D * 8 + 7) := (X, Y, Z, 0.0, X, Y, Z, 1.0);
         end;
      end loop;
      glGenVertexArrays (1, VAO'Address);
      glBindVertexArray (VAO);
      glGenBuffers (1, VBO'Address);
      glBindBuffer (GL_ARRAY_BUFFER, VBO);
      glBufferData (GL_ARRAY_BUFFER, GLsizeiptr (Data'Length * 4), Data'Address,
                    GL_STATIC_DRAW);
      glVertexAttribPointer (0, 4, GL_FLOAT, GL_FALSE, 16,
                             System.Storage_Elements.To_Address (0));
      glEnableVertexAttribArray (0);
      glBindVertexArray (0);
   end Create;

   procedure Draw (VP : Math3D.Mat4; Cam : Math3D.Vec3;
                   Time, Amount : Float; Snow : Boolean; Pixels_Per_Metre : Float;
                   Color : Math3D.Vec3)
   is
   begin
      if Amount <= 0.01 then
         return;
      end if;
      glUseProgram (Program);
      Shaders.Set (U_View_Proj, VP);
      Shaders.Set (U_Cam, Cam);
      Shaders.Set (U_Time, Time);
      Shaders.Set (U_Amount, Amount);
      Shaders.Set (U_Color, (if Snow then Math3D."*" (0.3 + 0.7 * Color.X / 0.75,
                                                       Math3D.Vec3'(0.9, 0.92, 0.95))
                             else Color));
      Shaders.Set (U_Snow, (if Snow then 1 else 0));
      Shaders.Set (U_Scale, Pixels_Per_Metre);
      glEnable (GL_BLEND);
      glBlendFunc (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
      glDepthMask (GL_FALSE);
      glBindVertexArray (VAO);
      if Snow then
         glEnable (GL_PROGRAM_POINT_SIZE);
         glDrawArrays (GL_POINTS, 0, GLsizei (Drops * 2));
         glDisable (GL_PROGRAM_POINT_SIZE);
      else
         glDrawArrays (GL_LINES, 0, GLsizei (Drops * 2));
      end if;
      glBindVertexArray (0);
      glDepthMask (GL_TRUE);
      glDisable (GL_BLEND);
   end Draw;

   procedure Draw_Leaves (VP : Math3D.Mat4; Cam : Math3D.Vec3;
                          Time, Amount, Pixels_Per_Metre, Light : Float) is
   begin
      if Amount <= 0.005 then
         return;
      end if;
      glUseProgram (Program);
      Shaders.Set (U_View_Proj, VP);
      Shaders.Set (U_Cam, Cam);
      Shaders.Set (U_Time, Time);
      Shaders.Set (U_Amount, Amount);
      Shaders.Set (U_Color, Math3D.Vec3'(Light, Light, Light));
      Shaders.Set (U_Snow, 2);
      Shaders.Set (U_Scale, Pixels_Per_Metre);
      glEnable (GL_BLEND);
      glBlendFunc (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
      glEnable (GL_PROGRAM_POINT_SIZE);
      glBindVertexArray (VAO);
      glDrawArrays (GL_POINTS, 0, GLsizei (Drops * 2));
      glBindVertexArray (0);
      glDisable (GL_PROGRAM_POINT_SIZE);
      glDisable (GL_BLEND);
   end Draw_Leaves;

end Rain;
