--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Minimal OpenGL 3.3 core binding.
--
--  GTK already uses libepoxy for GL dispatch, so we bind to epoxy's
--  global function pointers (epoxy_glXxx); epoxy resolves them lazily
--  for the current context.

with Interfaces.C;
with Interfaces.C.Strings;
with System;

package GL is

   use Interfaces;

   subtype GLenum is C.unsigned;
   subtype GLbitfield is C.unsigned;
   subtype GLuint is C.unsigned;
   subtype GLint is C.int;
   subtype GLsizei is C.int;
   subtype GLfloat is C.C_float;
   subtype GLboolean is C.unsigned_char;
   subtype GLsizeiptr is C.ptrdiff_t;
   subtype GLintptr is C.ptrdiff_t;

   GL_FALSE : constant GLboolean := 0;
   GL_TRUE  : constant GLboolean := 1;

   GL_DEPTH_BUFFER_BIT   : constant := 16#0100#;
   GL_COLOR_BUFFER_BIT   : constant := 16#4000#;

   GL_TRIANGLES          : constant := 16#0004#;
   GL_LINES              : constant := 16#0001#;

   GL_NEVER              : constant := 16#0200#;
   GL_LESS               : constant := 16#0201#;
   GL_LEQUAL             : constant := 16#0203#;
   GL_ALWAYS             : constant := 16#0207#;
   GL_NOTEQUAL           : constant := 16#0205#;
   GL_TIME_ELAPSED       : constant := 16#88BF#;
   GL_QUERY_RESULT       : constant := 16#8866#;
   GL_STENCIL_TEST       : constant := 16#0B90#;
   GL_SAMPLE_ALPHA_TO_COVERAGE : constant := 16#809E#;
   GL_STENCIL_BUFFER_BIT : constant := 16#0400#;
   GL_KEEP               : constant := 16#1E00#;
   GL_REPLACE            : constant := 16#1E01#;

   GL_CULL_FACE          : constant := 16#0B44#;
   GL_DEPTH_TEST         : constant := 16#0B71#;
   GL_BLEND              : constant := 16#0BE2#;
   GL_VIEWPORT           : constant := 16#0BA2#;
   GL_POLYGON_OFFSET_FILL : constant := 16#8037#;
   GL_MULTISAMPLE        : constant := 16#809D#;
   GL_FRAMEBUFFER_SRGB   : constant := 16#8DB9#;

   GL_FRONT              : constant := 16#0404#;
   GL_BACK               : constant := 16#0405#;
   GL_CW                 : constant := 16#0900#;
   GL_CCW                : constant := 16#0901#;

   GL_SRC_ALPHA          : constant := 16#0302#;
   GL_ONE_MINUS_SRC_ALPHA : constant := 16#0303#;

   GL_UNSIGNED_BYTE      : constant := 16#1401#;
   GL_UNSIGNED_INT       : constant := 16#1405#;
   GL_FLOAT              : constant := 16#1406#;

   GL_ARRAY_BUFFER       : constant := 16#8892#;
   GL_ELEMENT_ARRAY_BUFFER : constant := 16#8893#;
   GL_STATIC_DRAW        : constant := 16#88E4#;
   GL_DYNAMIC_DRAW       : constant := 16#88E8#;

   GL_FRAGMENT_SHADER    : constant := 16#8B30#;
   GL_VERTEX_SHADER      : constant := 16#8B31#;
   GL_COMPILE_STATUS     : constant := 16#8B81#;
   GL_LINK_STATUS        : constant := 16#8B82#;
   GL_INFO_LOG_LENGTH    : constant := 16#8B84#;

   GL_TEXTURE_2D         : constant := 16#0DE1#;
   GL_TEXTURE0           : constant := 16#84C0#;
   GL_TEXTURE_MAG_FILTER : constant := 16#2800#;
   GL_TEXTURE_MIN_FILTER : constant := 16#2801#;
   GL_TEXTURE_WRAP_S     : constant := 16#2802#;
   GL_TEXTURE_WRAP_T     : constant := 16#2803#;
   GL_LINEAR             : constant := 16#2601#;
   GL_NEAREST            : constant := 16#2600#;
   GL_CLAMP_TO_EDGE      : constant := 16#812F#;
   GL_CLAMP_TO_BORDER    : constant := 16#812D#;
   GL_TEXTURE_BORDER_COLOR : constant := 16#1004#;
   GL_TEXTURE_COMPARE_MODE : constant := 16#884C#;
   GL_TEXTURE_COMPARE_FUNC : constant := 16#884D#;
   GL_COMPARE_REF_TO_TEXTURE : constant := 16#884E#;
   GL_DEPTH_COMPONENT    : constant := 16#1902#;
   GL_DEPTH_COMPONENT24  : constant := 16#81A6#;
   GL_DEPTH_COMPONENT32F : constant := 16#8CAC#;
   GL_RGBA8              : constant := 16#8058#;
   GL_RGBA16F            : constant := 16#881A#;
   GL_RGBA               : constant := 16#1908#;
   GL_DEPTH24_STENCIL8   : constant := 16#88F0#;

   GL_FRAMEBUFFER        : constant := 16#8D40#;
   GL_READ_FRAMEBUFFER   : constant := 16#8CA8#;
   GL_DRAW_FRAMEBUFFER   : constant := 16#8CA9#;
   GL_RENDERBUFFER       : constant := 16#8D41#;
   GL_FRAMEBUFFER_BINDING : constant := 16#8CA6#;
   GL_COLOR_ATTACHMENT0  : constant := 16#8CE0#;
   GL_DEPTH_ATTACHMENT   : constant := 16#8D00#;
   GL_DEPTH_STENCIL_ATTACHMENT : constant := 16#821A#;
   GL_FRAMEBUFFER_COMPLETE : constant := 16#8CD5#;
   GL_NONE               : constant := 0;

   type GLint_Array is array (Natural range <>) of aliased GLint;
   type GLfloat_Array is array (Natural range <>) of aliased GLfloat;

   --  Function pointer types ---------------------------------------------

   type P_Enum is access procedure (A : GLenum) with Convention => C;
   type P_Bitfield is access procedure (A : GLbitfield) with Convention => C;
   type P_4F is access procedure (A, B, C, D : GLfloat) with Convention => C;
   type P_2F is access procedure (A, B : GLfloat) with Convention => C;
   type P_Bool is access procedure (A : GLboolean) with Convention => C;
   type P_4I is access procedure (A, B, C, D : GLint) with Convention => C;
   type P_Enum_Ptr is access procedure (A : GLenum; P : System.Address)
     with Convention => C;
   type P_Gen is access procedure (N : GLsizei; Ids : System.Address)
     with Convention => C;
   type P_Uint is access procedure (A : GLuint) with Convention => C;
   type P_Enum_Uint is access procedure (A : GLenum; B : GLuint)
     with Convention => C;
   type P_Enum_2 is access procedure (A, B : GLenum) with Convention => C;
   type P_Buffer_Data is access procedure
     (Target : GLenum; Size : GLsizeiptr; Data : System.Address; Usage : GLenum)
     with Convention => C;
   type P_Attrib_Pointer is access procedure
     (Index : GLuint; Size : GLint; Kind : GLenum; Normalized : GLboolean;
      Stride : GLsizei; Offset : System.Address)
     with Convention => C;
   type F_Create_Shader is access function (Kind : GLenum) return GLuint
     with Convention => C;
   type F_Create is access function return GLuint with Convention => C;
   type P_Shader_Source is access procedure
     (Shader : GLuint; Count : GLsizei; Strings : System.Address;
      Lengths : System.Address)
     with Convention => C;
   type P_Get_Iv is access procedure
     (Obj : GLuint; Pname : GLenum; Params : System.Address)
     with Convention => C;
   type P_Get_Log is access procedure
     (Obj : GLuint; Max : GLsizei; Length : System.Address;
      Log : C.Strings.chars_ptr)
     with Convention => C;
   type P_Uint_2 is access procedure (A, B : GLuint) with Convention => C;
   type F_Uniform_Loc is access function
     (Program : GLuint; Name : C.Strings.chars_ptr) return GLint
     with Convention => C;
   type P_Uniform_Matrix is access procedure
     (Loc : GLint; Count : GLsizei; Transpose : GLboolean; Value : System.Address)
     with Convention => C;
   type P_Uniform_3F is access procedure (Loc : GLint; X, Y, Z : GLfloat)
     with Convention => C;
   type P_Uniform_1F is access procedure (Loc : GLint; X : GLfloat)
     with Convention => C;
   type P_Uniform_1I is access procedure (Loc : GLint; X : GLint)
     with Convention => C;
   type P_Draw_Elements is access procedure
     (Mode : GLenum; Count : GLsizei; Kind : GLenum; Offset : System.Address)
     with Convention => C;
   type P_Draw_Arrays is access procedure
     (Mode : GLenum; First : GLint; Count : GLsizei)
     with Convention => C;
   type P_Renderbuffer_Storage_MS is access procedure
     (Target : GLenum; Samples : GLsizei; Format : GLenum;
      Width, Height : GLsizei)
     with Convention => C;
   type P_Framebuffer_Renderbuffer is access procedure
     (Target, Attachment, RB_Target : GLenum; RB : GLuint)
     with Convention => C;
   type P_Framebuffer_Texture_2D is access procedure
     (Target, Attachment, Tex_Target : GLenum; Tex : GLuint; Level : GLint)
     with Convention => C;
   type P_Blit is access procedure
     (SX0, SY0, SX1, SY1, DX0, DY0, DX1, DY1 : GLint;
      Mask : GLbitfield; Filter : GLenum)
     with Convention => C;
   type F_Check_FB is access function (Target : GLenum) return GLenum
     with Convention => C;
   type P_Tex_Image_2D is access procedure
     (Target : GLenum; Level, Internal : GLint; Width, Height : GLsizei;
      Border : GLint; Format, Kind : GLenum; Data : System.Address)
     with Convention => C;
   type P_Tex_Parameter_I is access procedure
     (Target, Pname : GLenum; Param : GLint)
     with Convention => C;
   type P_Tex_Parameter_FV is access procedure
     (Target, Pname : GLenum; Params : System.Address)
     with Convention => C;
   type P_Read_Pixels is access procedure
     (X, Y : GLint; Width, Height : GLsizei; Format, Kind : GLenum;
      Data : System.Address)
     with Convention => C;
   type P_Uniform_4F is access procedure (Loc : GLint; X, Y, Z, W : GLfloat)
     with Convention => C;

   type P_2D is access procedure (A, B : C.double)
     with Convention => C;
   type P_Stencil_Func is access procedure (Func : GLenum; Ref : GLint; Mask : GLuint)
     with Convention => C;
   type P_Enum_3 is access procedure (A, B, C : GLenum)
     with Convention => C;
   type P_Bool_4 is access procedure (R, G, B, A : GLboolean)
     with Convention => C;
   type P_Void is access procedure with Convention => C;
   type P_Get_Query_U64 is access procedure
     (Id : GLuint; Pname : GLenum; Value : System.Address)
     with Convention => C;
   type P_Uniform_FV is access procedure
     (Loc : GLint; Count : GLsizei; Values : System.Address)
     with Convention => C;

   --  Functions -----------------------------------------------------------

   glGenQueries : P_Gen
     with Import, Convention => C, External_Name => "epoxy_glGenQueries";
   glBeginQuery : P_Enum_Uint
     with Import, Convention => C, External_Name => "epoxy_glBeginQuery";
   glEndQuery : P_Enum
     with Import, Convention => C, External_Name => "epoxy_glEndQuery";
   glGetQueryObjectui64v : P_Get_Query_U64
     with Import, Convention => C, External_Name => "epoxy_glGetQueryObjectui64v";
   glFinish : P_Void
     with Import, Convention => C, External_Name => "epoxy_glFinish";
   glStencilFunc : P_Stencil_Func
     with Import, Convention => C, External_Name => "epoxy_glStencilFunc";
   glStencilOp : P_Enum_3
     with Import, Convention => C, External_Name => "epoxy_glStencilOp";
   glColorMask : P_Bool_4
     with Import, Convention => C, External_Name => "epoxy_glColorMask";
   glDepthRange : P_2D
     with Import, Convention => C, External_Name => "epoxy_glDepthRange";
   glUniform4fv : P_Uniform_FV
     with Import, Convention => C, External_Name => "epoxy_glUniform4fv";

   glClear : P_Bitfield
     with Import, Convention => C, External_Name => "epoxy_glClear";
   glClearColor : P_4F
     with Import, Convention => C, External_Name => "epoxy_glClearColor";
   glEnable : P_Enum
     with Import, Convention => C, External_Name => "epoxy_glEnable";
   glDisable : P_Enum
     with Import, Convention => C, External_Name => "epoxy_glDisable";
   glDepthFunc : P_Enum
     with Import, Convention => C, External_Name => "epoxy_glDepthFunc";
   glDepthMask : P_Bool
     with Import, Convention => C, External_Name => "epoxy_glDepthMask";
   glCullFace : P_Enum
     with Import, Convention => C, External_Name => "epoxy_glCullFace";
   glFrontFace : P_Enum
     with Import, Convention => C, External_Name => "epoxy_glFrontFace";
   glPolygonOffset : P_2F
     with Import, Convention => C, External_Name => "epoxy_glPolygonOffset";
   glBlendFunc : P_Enum_2
     with Import, Convention => C, External_Name => "epoxy_glBlendFunc";
   glViewport : P_4I
     with Import, Convention => C, External_Name => "epoxy_glViewport";
   glGetIntegerv : P_Enum_Ptr
     with Import, Convention => C, External_Name => "epoxy_glGetIntegerv";

   glGenVertexArrays : P_Gen
     with Import, Convention => C, External_Name => "epoxy_glGenVertexArrays";
   glDeleteVertexArrays : P_Gen
     with Import, Convention => C, External_Name => "epoxy_glDeleteVertexArrays";
   glBindVertexArray : P_Uint
     with Import, Convention => C, External_Name => "epoxy_glBindVertexArray";
   glGenBuffers : P_Gen
     with Import, Convention => C, External_Name => "epoxy_glGenBuffers";
   glDeleteBuffers : P_Gen
     with Import, Convention => C, External_Name => "epoxy_glDeleteBuffers";
   glBindBuffer : P_Enum_Uint
     with Import, Convention => C, External_Name => "epoxy_glBindBuffer";
   glBufferData : P_Buffer_Data
     with Import, Convention => C, External_Name => "epoxy_glBufferData";
   glVertexAttribPointer : P_Attrib_Pointer
     with Import, Convention => C, External_Name => "epoxy_glVertexAttribPointer";
   glEnableVertexAttribArray : P_Uint
     with Import, Convention => C,
          External_Name => "epoxy_glEnableVertexAttribArray";

   glCreateShader : F_Create_Shader
     with Import, Convention => C, External_Name => "epoxy_glCreateShader";
   glShaderSource : P_Shader_Source
     with Import, Convention => C, External_Name => "epoxy_glShaderSource";
   glCompileShader : P_Uint
     with Import, Convention => C, External_Name => "epoxy_glCompileShader";
   glGetShaderiv : P_Get_Iv
     with Import, Convention => C, External_Name => "epoxy_glGetShaderiv";
   glGetShaderInfoLog : P_Get_Log
     with Import, Convention => C, External_Name => "epoxy_glGetShaderInfoLog";
   glDeleteShader : P_Uint
     with Import, Convention => C, External_Name => "epoxy_glDeleteShader";
   glCreateProgram : F_Create
     with Import, Convention => C, External_Name => "epoxy_glCreateProgram";
   glAttachShader : P_Uint_2
     with Import, Convention => C, External_Name => "epoxy_glAttachShader";
   glLinkProgram : P_Uint
     with Import, Convention => C, External_Name => "epoxy_glLinkProgram";
   glGetProgramiv : P_Get_Iv
     with Import, Convention => C, External_Name => "epoxy_glGetProgramiv";
   glGetProgramInfoLog : P_Get_Log
     with Import, Convention => C, External_Name => "epoxy_glGetProgramInfoLog";
   glUseProgram : P_Uint
     with Import, Convention => C, External_Name => "epoxy_glUseProgram";
   glGetUniformLocation : F_Uniform_Loc
     with Import, Convention => C, External_Name => "epoxy_glGetUniformLocation";
   glUniformMatrix4fv : P_Uniform_Matrix
     with Import, Convention => C, External_Name => "epoxy_glUniformMatrix4fv";
   glUniform3f : P_Uniform_3F
     with Import, Convention => C, External_Name => "epoxy_glUniform3f";
   glUniform4f : P_Uniform_4F
     with Import, Convention => C, External_Name => "epoxy_glUniform4f";
   glUniform1f : P_Uniform_1F
     with Import, Convention => C, External_Name => "epoxy_glUniform1f";
   glUniform1i : P_Uniform_1I
     with Import, Convention => C, External_Name => "epoxy_glUniform1i";

   glDrawElements : P_Draw_Elements
     with Import, Convention => C, External_Name => "epoxy_glDrawElements";
   glDrawArrays : P_Draw_Arrays
     with Import, Convention => C, External_Name => "epoxy_glDrawArrays";

   glGenFramebuffers : P_Gen
     with Import, Convention => C, External_Name => "epoxy_glGenFramebuffers";
   glDeleteFramebuffers : P_Gen
     with Import, Convention => C, External_Name => "epoxy_glDeleteFramebuffers";
   glBindFramebuffer : P_Enum_Uint
     with Import, Convention => C, External_Name => "epoxy_glBindFramebuffer";
   glGenRenderbuffers : P_Gen
     with Import, Convention => C, External_Name => "epoxy_glGenRenderbuffers";
   glDeleteRenderbuffers : P_Gen
     with Import, Convention => C, External_Name => "epoxy_glDeleteRenderbuffers";
   glBindRenderbuffer : P_Enum_Uint
     with Import, Convention => C, External_Name => "epoxy_glBindRenderbuffer";
   glRenderbufferStorageMultisample : P_Renderbuffer_Storage_MS
     with Import, Convention => C,
          External_Name => "epoxy_glRenderbufferStorageMultisample";
   glFramebufferRenderbuffer : P_Framebuffer_Renderbuffer
     with Import, Convention => C,
          External_Name => "epoxy_glFramebufferRenderbuffer";
   glFramebufferTexture2D : P_Framebuffer_Texture_2D
     with Import, Convention => C,
          External_Name => "epoxy_glFramebufferTexture2D";
   glBlitFramebuffer : P_Blit
     with Import, Convention => C, External_Name => "epoxy_glBlitFramebuffer";
   glCheckFramebufferStatus : F_Check_FB
     with Import, Convention => C,
          External_Name => "epoxy_glCheckFramebufferStatus";
   glDrawBuffer : P_Enum
     with Import, Convention => C, External_Name => "epoxy_glDrawBuffer";
   glReadBuffer : P_Enum
     with Import, Convention => C, External_Name => "epoxy_glReadBuffer";

   glGenTextures : P_Gen
     with Import, Convention => C, External_Name => "epoxy_glGenTextures";
   glBindTexture : P_Enum_Uint
     with Import, Convention => C, External_Name => "epoxy_glBindTexture";
   glActiveTexture : P_Enum
     with Import, Convention => C, External_Name => "epoxy_glActiveTexture";
   glTexImage2D : P_Tex_Image_2D
     with Import, Convention => C, External_Name => "epoxy_glTexImage2D";
   glTexParameteri : P_Tex_Parameter_I
     with Import, Convention => C, External_Name => "epoxy_glTexParameteri";
   glTexParameterfv : P_Tex_Parameter_FV
     with Import, Convention => C, External_Name => "epoxy_glTexParameterfv";

   glReadPixels : P_Read_Pixels
     with Import, Convention => C, External_Name => "epoxy_glReadPixels";

end GL;
