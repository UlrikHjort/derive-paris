--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Loading GLSL programs from files and setting uniforms.

with GL;
with Math3D;

package Shaders is

   Shader_Error : exception;

   function Load_Program (Vertex_File, Fragment_File : String) return GL.GLuint;
   --  Compile and link; raises Shader_Error with the info log on failure.

   function Location (Program : GL.GLuint; Name : String) return GL.GLint;

   procedure Set (Loc : GL.GLint; M : Math3D.Mat4);
   procedure Set (Loc : GL.GLint; V : Math3D.Vec3);
   procedure Set (Loc : GL.GLint; F : Float);
   procedure Set (Loc : GL.GLint; I : Integer);

end Shaders;
