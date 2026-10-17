--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with System.Storage_Elements;

with Geo;
with GL;
with Terrain;
with Shaders;

package body Beacon is

   use GL;
   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   --  The lantern on top of the tower
   Tower_Lat : constant := 48.858222;
   Tower_Lon : constant := 2.294500;
   Lamp_Y    : constant := 292.0;

   Beams     : constant := 4;
   Beam_Length : constant := 3500.0;   --  metres
   Turn_Time : constant := 24.0;     --  seconds per turn

   Program : GLuint := 0;
   U_View_Proj, U_Color, U_Strength : GLint;
   VAO, VBO : aliased GLuint := 0;
   Data : array (0 .. Beams * 6 * 5 - 1) of aliased Float := (others => 0.0);
   Lamp : Vec3;

   procedure Create is
      X, Z : Long_Float;
   begin
      Program := Shaders.Load_Program ("shaders/beam.vert", "shaders/beam.frag");
      U_View_Proj := Shaders.Location (Program, "uViewProj");
      U_Color := Shaders.Location (Program, "uColor");
      U_Strength := Shaders.Location (Program, "uStrength");
      Geo.To_Local (Tower_Lat, Tower_Lon, X, Z);
      Lamp := (Float (X), Lamp_Y + Terrain.Height (Float (X), Float (Z)), Float (Z));
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
   end Create;

   function Lights_On (Hour, Night : Float) return Boolean is
     (Night > 0.55 and then (Hour >= 12.0 and then Hour < 23.75));

   function Sparkle (Hour, Night : Float) return Float is
      Minute : constant Float := (Hour - Float'Floor (Hour)) * 60.0;
   begin
      if not Lights_On (Hour, Night) or else Minute >= 5.0 then
         return 0.0;
      end if;
      --  switch on and off over a few seconds
      return Float'Min (1.0, Float'Min (Minute, 5.0 - Minute) * 20.0);
   end Sparkle;

   procedure Draw (VP : Mat4; Cam : Vec3; Time, Hour, Night, Rain : Float) is
      Angle0 : constant Float := Time * 2.0 * Ada.Numerics.Pi / Turn_Time;
      N : Natural := 0;
   begin
      if not Lights_On (Hour, Night) then
         return;
      end if;
      for B in 0 .. Beams - 1 loop
         declare
            A   : constant Float := Angle0 + Float (B) * Ada.Numerics.Pi / 2.0;
            Dir : constant Vec3 := Normalize ((Cos (A), -0.012, Sin (A)));
            Far : constant Vec3 := Lamp + Beam_Length * Dir;
            --  turned towards the camera, wider further out
            Side : Vec3 := Cross (Dir, Lamp - Cam);
            procedure Put (P : Vec3; Along, Across : Float) is
            begin
               Data (N * 5 .. N * 5 + 4) := (P.X, P.Y, P.Z, Along, Across);
               N := N + 1;
            end Put;
         begin
            if Length (Side) < 0.001 then
               Side := (0.0, 1.0, 0.0);
            end if;
            Side := Normalize (Side);
            Put (Lamp - 2.0 * Side, 0.0, -1.0);
            Put (Lamp + 2.0 * Side, 0.0, 1.0);
            Put (Far + 220.0 * Side, 1.0, 1.0);
            Put (Lamp - 2.0 * Side, 0.0, -1.0);
            Put (Far + 220.0 * Side, 1.0, 1.0);
            Put (Far - 220.0 * Side, 1.0, -1.0);
         end;
      end loop;
      glUseProgram (Program);
      glBindBuffer (GL_ARRAY_BUFFER, VBO);
      glBufferSubData (GL_ARRAY_BUFFER, 0, GLsizeiptr (N * 5 * 4), Data'Address);
      Shaders.Set (U_View_Proj, VP);
      Shaders.Set (U_Color, Vec3'(1.0, 0.93, 0.78));
      --  stronger in the rain: more for the light to scatter on
      Shaders.Set (U_Strength, 0.45 * Night * (1.0 + 1.2 * Rain));
      glEnable (GL_BLEND);
      glBlendFunc (GL_ONE, GL_ONE);
      glDepthMask (GL_FALSE);
      glBindVertexArray (VAO);
      glDrawArrays (GL_TRIANGLES, 0, GLsizei (N));
      glBindVertexArray (0);
      glDepthMask (GL_TRUE);
      glDisable (GL_BLEND);
   end Draw;

   procedure Draw_Shaft (VP : Mat4; Cam, From, To : Vec3;
                         Width_From, Width_To : Float; Color : Vec3;
                         Strength : Float) is
      Dir  : constant Vec3 := To - From;
      Side : Vec3 := Cross (Dir, From - Cam);
      N    : Natural := 0;
      procedure Put (P : Vec3; Along, Across : Float) is
      begin
         Data (N * 5 .. N * 5 + 4) := (P.X, P.Y, P.Z, Along, Across);
         N := N + 1;
      end Put;
   begin
      if Length (Side) < 0.001 then
         Side := (1.0, 0.0, 0.0);
      end if;
      Side := Normalize (Side);
      Put (From - Width_From * Side, 0.0, -1.0);
      Put (From + Width_From * Side, 0.0, 1.0);
      Put (To + Width_To * Side, 1.0, 1.0);
      Put (From - Width_From * Side, 0.0, -1.0);
      Put (To + Width_To * Side, 1.0, 1.0);
      Put (To - Width_To * Side, 1.0, -1.0);
      glUseProgram (Program);
      glBindBuffer (GL_ARRAY_BUFFER, VBO);
      glBufferSubData (GL_ARRAY_BUFFER, 0, GLsizeiptr (N * 5 * 4), Data'Address);
      Shaders.Set (U_View_Proj, VP);
      Shaders.Set (U_Color, Color);
      Shaders.Set (U_Strength, Strength);
      glEnable (GL_BLEND);
      glBlendFunc (GL_ONE, GL_ONE);
      glDepthMask (GL_FALSE);
      glBindVertexArray (VAO);
      glDrawArrays (GL_TRIANGLES, 0, GLsizei (N));
      glBindVertexArray (0);
      glDepthMask (GL_TRUE);
      glDisable (GL_BLEND);
   end Draw_Shaft;

end Beacon;
