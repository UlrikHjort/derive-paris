--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with GL; use GL;
with Shaders;

package body Hud_Layer is

   Program : GLuint := 0;
   Tex     : aliased GLuint := 0;
   VAO     : aliased GLuint := 0;
   U_Hud   : GLint := GLint (-1);
   Tex_W, Tex_H : Natural := 0;

   procedure Create is
   begin
      Program := Shaders.Load_Program ("shaders/hud.vert", "shaders/hud.frag");
      U_Hud := Shaders.Location (Program, "uHud");
      glGenTextures (1, Tex'Address);
      glBindTexture (GL_TEXTURE_2D, Tex);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
      glGenVertexArrays (1, VAO'Address);
   end Create;

   procedure Draw (Data : System.Address; Width, Height, Stride : Natural;
                   X0, Y0, X1, Y1 : Natural) is
      use type GLuint;
   begin
      if Program = 0 or else Width = 0 or else Height = 0 then
         return;
      end if;
      glActiveTexture (GL_TEXTURE0);
      glBindTexture (GL_TEXTURE_2D, Tex);
      glPixelStorei (GL_UNPACK_ROW_LENGTH, GLint (Stride / 4));
      if Width /= Tex_W or else Height /= Tex_H then
         glTexImage2D (GL_TEXTURE_2D, 0, GL_RGBA8, GLsizei (Width), GLsizei (Height), 0,
                       GL_BGRA, GL_UNSIGNED_BYTE, Data);
         Tex_W := Width;
         Tex_H := Height;
      elsif X1 > X0 and then Y1 > Y0 then
         glPixelStorei (GL_UNPACK_SKIP_PIXELS, GLint (X0));
         glPixelStorei (GL_UNPACK_SKIP_ROWS, GLint (Y0));
         glTexSubImage2D (GL_TEXTURE_2D, 0, GLint (X0), GLint (Y0), GLsizei (X1 - X0), GLsizei (Y1 - Y0),
                          GL_BGRA, GL_UNSIGNED_BYTE, Data);
         glPixelStorei (GL_UNPACK_SKIP_PIXELS, 0);
         glPixelStorei (GL_UNPACK_SKIP_ROWS, 0);
      end if;
      glPixelStorei (GL_UNPACK_ROW_LENGTH, 0);
      glDisable (GL_DEPTH_TEST);
      glEnable (GL_BLEND);
      glBlendFunc (GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
      glUseProgram (Program);
      Shaders.Set (U_Hud, Integer'(0));
      glBindVertexArray (VAO);
      glDrawArrays (GL_TRIANGLES, 0, 3);
      glBindVertexArray (0);
      glDisable (GL_BLEND);
   end Draw;

end Hud_Layer;
