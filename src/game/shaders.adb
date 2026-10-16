--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Interfaces.C.Strings;
with System;

package body Shaders is

   use GL;
   use Interfaces.C;

   function Read_File (Name : String) return String is
      use Ada.Streams.Stream_IO;
      F    : File_Type;
      Size : constant Natural := Natural (Ada.Directories.Size (Name));
      S    : String (1 .. Size);
   begin
      Open (F, In_File, Name);
      String'Read (Stream (F), S);
      Close (F);
      return S;
   end Read_File;

   function Info_Log (Obj : GLuint; Is_Program : Boolean) return String is
      Len : aliased GLint := 0;
   begin
      if Is_Program then
         glGetProgramiv (Obj, GL_INFO_LOG_LENGTH, Len'Address);
      else
         glGetShaderiv (Obj, GL_INFO_LOG_LENGTH, Len'Address);
      end if;
      if Len <= 1 then
         return "";
      end if;
      declare
         Buf : Strings.chars_ptr := Strings.New_String ((1 .. Natural (Len) => ' '));
      begin
         if Is_Program then
            glGetProgramInfoLog (Obj, Len, System.Null_Address, Buf);
         else
            glGetShaderInfoLog (Obj, Len, System.Null_Address, Buf);
         end if;
         return S : constant String := Strings.Value (Buf) do
            Strings.Free (Buf);
         end return;
      end;
   end Info_Log;

   function Compile (Kind : GLenum; File : String) return GLuint is
      Source : aliased Strings.chars_ptr := Strings.New_String (Read_File (File));
      Shader : constant GLuint := glCreateShader (Kind);
      Status : aliased GLint := 0;
   begin
      glShaderSource (Shader, 1, Source'Address, System.Null_Address);
      Strings.Free (Source);
      glCompileShader (Shader);
      glGetShaderiv (Shader, GL_COMPILE_STATUS, Status'Address);
      if Status = 0 then
         raise Shader_Error with File & ": " & Info_Log (Shader, False);
      end if;
      return Shader;
   end Compile;

   function Load_Program (Vertex_File, Fragment_File : String) return GLuint is
      VS      : constant GLuint := Compile (GL_VERTEX_SHADER, Vertex_File);
      FS      : constant GLuint := Compile (GL_FRAGMENT_SHADER, Fragment_File);
      Program : constant GLuint := glCreateProgram.all;
      Status  : aliased GLint := 0;
   begin
      glAttachShader (Program, VS);
      glAttachShader (Program, FS);
      glLinkProgram (Program);
      glGetProgramiv (Program, GL_LINK_STATUS, Status'Address);
      if Status = 0 then
         raise Shader_Error with Vertex_File & " + " & Fragment_File & ": "
           & Info_Log (Program, True);
      end if;
      glDeleteShader (VS);
      glDeleteShader (FS);
      return Program;
   end Load_Program;

   function Location (Program : GLuint; Name : String) return GLint is
      C_Name : Strings.chars_ptr := Strings.New_String (Name);
      Loc    : constant GLint := glGetUniformLocation (Program, C_Name);
   begin
      Strings.Free (C_Name);
      return Loc;
   end Location;

   procedure Set (Loc : GLint; M : Math3D.Mat4) is
   begin
      glUniformMatrix4fv (Loc, 1, GL_FALSE, M'Address);
   end Set;

   procedure Set (Loc : GLint; V : Math3D.Vec3) is
   begin
      glUniform3f (Loc, C_float (V.X), C_float (V.Y), C_float (V.Z));
   end Set;

   procedure Set (Loc : GLint; F : Float) is
   begin
      glUniform1f (Loc, C_float (F));
   end Set;

   procedure Set (Loc : GLint; I : Integer) is
   begin
      glUniform1i (Loc, GLint (I));
   end Set;

end Shaders;
