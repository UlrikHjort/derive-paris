with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Streams.Stream_IO;
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces.C;
with System;

with Gdk.Event;
with Gdk.Frame_Clock;
with Gdk.Types;
with Glib;
with Gtk.Css_Provider;
with Gtk.Label;
with Gtk.Main;
with Gtk.Overlay;
with Gtk.Style_Context;
with Gtk.Style_Provider;
with Gtk.Widget;
with Gtk.Window;

with Car;
with Geo;
with GL;
with GL_Area;
with Math3D;
with Pedestrians;
with Plane;
with Rain;
with Road_Network;
with Shaders;
with Traffic;
with World;

package body Game is

   use GL;
   use Math3D;
   use Ada.Numerics.Elementary_Functions;
   use type Glib.Gint64;
   use type Interfaces.C.unsigned;
   use type Interfaces.C.int;
   use type Gdk.Types.Gdk_Key_Type;
   use type Gdk.Event.Gdk_Event_Mask;

   --  Start and home (H, R): Rue Bonaparte at the corner of Place
   --  Saint-Sulpice, facing north towards Saint-Germain-des-Pres (the
   --  street is one-way north)
   Spawn_Lat     : constant Long_Float := 48.85190;
   Spawn_Lon     : constant Long_Float := 2.333020;
   Spawn_Heading : constant Float := 8.0 * Ada.Numerics.Pi / 180.0;

   Shadow_Size   : constant := 4096;
   Shadow_Extent : constant := 260.0;   --  half-size of the shadow box (m)
   Samples       : constant := 4;

   Car_Color    : constant Vec3 := (0.62, 0.07, 0.06);
   Plane_Color  : constant Vec3 := (0.90, 0.90, 0.88);
   Fog_Base     : constant := 0.0013;
   Fog_Density  : Float := Fog_Base;

   --  Weather: P toggles rain; the streets dry slowly afterwards
   Rain_Target  : Float := 0.0;
   Rain_Amount  : Float := 0.0;
   Wetness      : Float := 0.0;

   --  Time of day (hours) and the lighting derived from it
   Hour         : Float := 18.0;
   Clock_Rate   : constant := 1.0 / 60.0;   --  game hours per second
   Sun_Dir      : Vec3 := Normalize ((-0.55, 0.62, 0.50));   --  sun or moon
   Sun_Color    : Vec3 := (3.0, 2.75, 2.35);
   Sky_Zenith   : Vec3 := (0.30, 0.50, 0.82);
   Sky_Horizon  : Vec3 := (0.78, 0.84, 0.91);
   Amb_Sky      : Vec3 := (0.26, 0.33, 0.46);
   Amb_Ground   : Vec3 := (0.11, 0.09, 0.06);
   Night        : Float := 0.0;

   Window  : Gtk.Window.Gtk_Window;
   Area    : GL_Area.Gtk_GL_Area;
   Hud     : Gtk.Label.Gtk_Label;
   Sign    : Gtk.Label.Gtk_Label;      --  street name, like a Paris plaque

   Show_Street  : Boolean := True;     --  N toggles
   Announce       : Ada.Strings.Unbounded.Unbounded_String;   --  shown on the
   Announce_Timer : Float := 0.0;                             --  plaque briefly

   --  Teleport destinations, keys 1 .. 9 and 0
   type Place is record
      Name     : Ada.Strings.Unbounded.Unbounded_String;
      Lat, Lon : Long_Float;
   end record;

   function "+" (S : String) return Ada.Strings.Unbounded.Unbounded_String
     renames Ada.Strings.Unbounded.To_Unbounded_String;

   Places : constant array (0 .. 9) of Place :=
     ((+"Bastille", 48.85320, 2.36910),
      (+"Saint-Sulpice", 48.85190, 2.33302),
      (+"Notre-Dame", 48.85395, 2.34860),
      (+"Louvre", 48.86180, 2.33600),
      (+"Tour Eiffel", 48.85930, 2.29560),
      (+"Arc de Triomphe", 48.87290, 2.29880),
      (+"Sacré-Cœur", 48.88690, 2.34180),
      (+"Panthéon", 48.84660, 2.34400),
      (+"Concorde", 48.86560, 2.32120),
      (+"Opéra", 48.87060, 2.33200));
   Street_Timer : Float := 0.0;
   Street_Shown : Ada.Strings.Unbounded.Unbounded_String;

   Drone_Back : Float := 45.0;
   Drone_Up   : Float := 38.0;

   type Mode_Kind is (Driving, Flying);
   Mode     : Mode_Kind := Driving;

   Player   : Car.State;
   Aircraft : Plane.State;
   Drone    : Boolean := False;
   Zoom     : Float := 1.0;      --  camera distance factor (wheel, +/-)
   Fixed_Camera : Boolean := False;  --  PARIS_CAM: a still camera for screenshots

   --  Keys held down; mapped to car or plane controls each tick
   type Key_State is record
      Up, Down, Left, Right, W, S, A, D, Space : Boolean := False;
   end record;
   Keys : Key_State;
   Cam_Pos  : Vec3 := (0.0, 0.0, 0.0);
   Cam_Look : Vec3 := (0.0, 0.0, 0.0);
   Time     : Float := 0.0;
   Last_Frame : Glib.Gint64 := 0;
   Hud_Timer  : Float := 0.0;
   Fps_Frames : Natural := 0;
   Fps        : Float := 0.0;
   Ready      : Boolean := False;

   --  GL objects
   World_Prog, Sky_Prog, Shadow_Prog : GLuint := 0;
   Empty_VAO     : aliased GLuint := 0;
   MSAA_FBO      : aliased GLuint := 0;
   MSAA_Color    : aliased GLuint := 0;
   MSAA_Depth    : aliased GLuint := 0;
   MSAA_W, MSAA_H : Integer := 0;
   Shadow_FBO    : aliased GLuint := 0;
   Shadow_Tex    : aliased GLuint := 0;

   type World_Uniforms is record
      View_Proj, Model, Shadow_Matrix, Cam_Pos, Sun_Dir, Sun_Color,
      Sky_Zenith, Sky_Horizon, Fog_Density, Time, Car_Color,
      Shadow_Map, Shadows, Amb_Sky, Amb_Ground, Night, Lights, Light_Count,
      Head_Pos, Head_Dir, Head_On, Extra_Color, Extra_Color2, Wet : GLint;
   end record;
   WU : World_Uniforms;

   Sky_Inv_VP, Sky_Cam, Sky_Sun, Sky_Zen, Sky_Hor, Sky_Night, Sky_Clouds : GLint;
   Sh_Light_VP, Sh_Model : GLint;

   function Index_Of (S : String; C : Character; From : Positive) return Natural is
   begin
      for I in From .. S'Last loop
         if S (I) = C then
            return I;
         end if;
      end loop;
      return S'Last + 1;
   end Index_Of;

   procedure Reset_Car is
      X, Z    : Long_Float;
      Lat     : Long_Float := Spawn_Lat;
      Lon     : Long_Float := Spawn_Lon;
      Heading : Float := Spawn_Heading;
   begin
      if Ada.Environment_Variables.Exists ("PARIS_SPAWN") then
         declare
            S  : constant String := Ada.Environment_Variables.Value ("PARIS_SPAWN");
            P1 : constant Natural := Index_Of (S, ' ', S'First);
            P2 : constant Natural := Index_Of (S, ' ', P1 + 1);
         begin
            Lat := Long_Float'Value (S (S'First .. P1 - 1));
            Lon := Long_Float'Value (S (P1 + 1 .. P2 - 1));
            Heading := Float'Value (S (P2 + 1 .. S'Last)) * Ada.Numerics.Pi / 180.0;
         end;
      end if;
      if Ada.Environment_Variables.Exists ("PARIS_TIME") then
         Hour := Float'Value (Ada.Environment_Variables.Value ("PARIS_TIME"));
      end if;
      if Ada.Environment_Variables.Exists ("PARIS_RAIN") then
         Rain_Target := 1.0;
         Rain_Amount := 1.0;
         Wetness := 1.0;
      end if;
      if Ada.Environment_Variables.Exists ("PARIS_ZOOM") then
         Zoom := Float'Value (Ada.Environment_Variables.Value ("PARIS_ZOOM"));
      end if;
      Drone := Ada.Environment_Variables.Exists ("PARIS_DRONE");
      if Drone and then Ada.Environment_Variables.Value ("PARIS_DRONE") /= "1" then
         declare
            S : constant String := Ada.Environment_Variables.Value ("PARIS_DRONE");
            P : constant Natural := Index_Of (S, ' ', S'First);
         begin
            Drone_Back := Float'Value (S (S'First .. P - 1));
            Drone_Up := Float'Value (S (P + 1 .. S'Last));
         end;
      end if;
      Geo.To_Local (Lat, Lon, X, Z);
      Player := (X => Float (X), Z => Float (Z), Heading => Heading,
                 others => <>);
      Mode := Driving;
      if Ada.Environment_Variables.Exists ("PARIS_FLY") then
         Mode := Flying;
         Plane.Start (Aircraft, Player.X, Player.Z, Heading);
         if Ada.Environment_Variables.Value ("PARIS_FLY") /= "1" then
            Aircraft.Pos.Y := Float'Value (Ada.Environment_Variables.Value ("PARIS_FLY"));
         end if;
      end if;
      World.Set_Radius ((if Mode = Flying then 4 else 3));
      Cam_Pos := (Player.X, 0.0, Player.Z) - (if Drone then Drone_Back else 8.5) * Car.Forward (Player)
        + (0.0, (if Drone then Drone_Up else 3.2), 0.0);
      Cam_Look := (Player.X, 1.2, Player.Z) + (if Drone then 6.0 else 3.0) * Car.Forward (Player);
      --  PARIS_CAM="lat lon height heading_deg pitch_deg_down"
      if Ada.Environment_Variables.Exists ("PARIS_CAM") then
         declare
            S  : constant String := Ada.Environment_Variables.Value ("PARIS_CAM") & " ";
            Fields : array (1 .. 5) of Long_Float := (others => 0.0);
            First  : Positive := S'First;
            K      : Natural := 0;
            CX, CZ : Long_Float;
         begin
            for I in S'Range loop
               if S (I) = ' ' then
                  if I > First and then K < 5 then
                     K := K + 1;
                     Fields (K) := Long_Float'Value (S (First .. I - 1));
                  end if;
                  First := I + 1;
               end if;
            end loop;
            Geo.To_Local (Fields (1), Fields (2), CX, CZ);
            declare
               H : constant Float := Float (Fields (4)) * Ada.Numerics.Pi / 180.0;
               P : constant Float := Float (Fields (5)) * Ada.Numerics.Pi / 180.0;
            begin
               Cam_Pos := (Float (CX), Float (Fields (3)), Float (CZ));
               Cam_Look := Cam_Pos + 100.0 * Vec3'(Sin (H) * Cos (P), -Sin (P), -Cos (H) * Cos (P));
               Player.X := Float (CX);
               Player.Z := Float (CZ);
               Player.Heading := H;
               Fixed_Camera := True;
            end;
         end;
      end if;
   end Reset_Car;

   ---------------------------------------------------------------------------
   --  GL setup
   ---------------------------------------------------------------------------

   --  PARIS_PROFILE=1: GPU time per pass via timer queries (stalls!)
   type Pass is (P_Shadow, P_Solid, P_Ground, P_Resolve);
   Queries   : array (Pass) of aliased GLuint := (others => 0);
   Gpu_Total : array (Pass) of Long_Float := (others => 0.0);
   Profiling : Boolean := False;
   Dt_Hist   : array (0 .. 10) of Natural := (others => 0);   --  4 ms buckets
   type Cpu_Part is (C_Physics, C_Traffic, C_Lights, C_World);
   Cpu_Total : array (Cpu_Part) of Duration := (others => 0.0);

   function Clock_Now return Ada.Real_Time.Time renames Ada.Real_Time.Clock;
   procedure Add (P : Cpu_Part; Since : Ada.Real_Time.Time) is
      use type Ada.Real_Time.Time;
   begin
      Cpu_Total (P) := Cpu_Total (P) + Ada.Real_Time.To_Duration (Clock_Now - Since);
   end Add;

   procedure Begin_Pass (P : Pass) is
   begin
      if Profiling then
         if Queries (P) = 0 then
            glGenQueries (1, Queries (P)'Address);
         end if;
         glBeginQuery (GL_TIME_ELAPSED, Queries (P));
      end if;
   end Begin_Pass;

   procedure End_Pass (P : Pass) is
      Ns : aliased Interfaces.Unsigned_64 := 0;
   begin
      if Profiling then
         glEndQuery (GL_TIME_ELAPSED);
         glGetQueryObjectui64v (Queries (P), GL_QUERY_RESULT, Ns'Address);
         Gpu_Total (P) := Gpu_Total (P) + Long_Float (Ns) / 1.0E6;
      end if;
   end End_Pass;

   procedure Create_Shadow_Map is
      Border : aliased constant GLfloat_Array (0 .. 3) := (others => 1.0);
   begin
      glGenTextures (1, Shadow_Tex'Address);
      glBindTexture (GL_TEXTURE_2D, Shadow_Tex);
      glTexImage2D (GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT24, Shadow_Size, Shadow_Size,
                    0, GL_DEPTH_COMPONENT, GL_FLOAT, System.Null_Address);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_BORDER);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_BORDER);
      glTexParameterfv (GL_TEXTURE_2D, GL_TEXTURE_BORDER_COLOR, Border'Address);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_COMPARE_MODE, GL_COMPARE_REF_TO_TEXTURE);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_COMPARE_FUNC, GL_LEQUAL);
      glGenFramebuffers (1, Shadow_FBO'Address);
      glBindFramebuffer (GL_FRAMEBUFFER, Shadow_FBO);
      glFramebufferTexture2D (GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D,
                              Shadow_Tex, 0);
      glDrawBuffer (GL_NONE);
      glReadBuffer (GL_NONE);
   end Create_Shadow_Map;

   procedure Ensure_MSAA (W, H : Integer) is
   begin
      if W = MSAA_W and then H = MSAA_H then
         return;
      end if;
      if MSAA_FBO /= 0 then
         glDeleteFramebuffers (1, MSAA_FBO'Address);
         glDeleteRenderbuffers (1, MSAA_Color'Address);
         glDeleteRenderbuffers (1, MSAA_Depth'Address);
      end if;
      glGenFramebuffers (1, MSAA_FBO'Address);
      glBindFramebuffer (GL_FRAMEBUFFER, MSAA_FBO);
      glGenRenderbuffers (1, MSAA_Color'Address);
      glBindRenderbuffer (GL_RENDERBUFFER, MSAA_Color);
      glRenderbufferStorageMultisample (GL_RENDERBUFFER, Samples, GL_RGBA8,
                                        GLsizei (W), GLsizei (H));
      glFramebufferRenderbuffer (GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                 GL_RENDERBUFFER, MSAA_Color);
      glGenRenderbuffers (1, MSAA_Depth'Address);
      glBindRenderbuffer (GL_RENDERBUFFER, MSAA_Depth);
      glRenderbufferStorageMultisample (GL_RENDERBUFFER, Samples, GL_DEPTH24_STENCIL8,
                                        GLsizei (W), GLsizei (H));
      glFramebufferRenderbuffer (GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT,
                                 GL_RENDERBUFFER, MSAA_Depth);
      if glCheckFramebufferStatus (GL_FRAMEBUFFER) /= GL_FRAMEBUFFER_COMPLETE then
         Ada.Text_IO.Put_Line ("MSAA framebuffer incomplete");
      end if;
      MSAA_W := W;
      MSAA_H := H;
   end Ensure_MSAA;

   procedure Realize (Widget, Data : System.Address) with Convention => C;
   procedure Realize (Widget, Data : System.Address) is
      pragma Unreferenced (Widget, Data);
      use Shaders;
   begin
      Area.Make_Current;
      if Area.Error_Message /= "" then
         Ada.Text_IO.Put_Line ("GL error: " & Area.Error_Message);
         return;
      end if;

      World_Prog := Load_Program ("shaders/world.vert", "shaders/world.frag");
      Sky_Prog := Load_Program ("shaders/sky.vert", "shaders/sky.frag");
      Shadow_Prog := Load_Program ("shaders/shadow.vert", "shaders/shadow.frag");

      WU := (View_Proj     => Location (World_Prog, "uViewProj"),
             Model         => Location (World_Prog, "uModel"),
             Shadow_Matrix => Location (World_Prog, "uShadowMatrix"),
             Cam_Pos       => Location (World_Prog, "uCamPos"),
             Sun_Dir       => Location (World_Prog, "uSunDir"),
             Sun_Color     => Location (World_Prog, "uSunColor"),
             Sky_Zenith    => Location (World_Prog, "uSkyZenith"),
             Sky_Horizon   => Location (World_Prog, "uSkyHorizon"),
             Fog_Density   => Location (World_Prog, "uFogDensity"),
             Time          => Location (World_Prog, "uTime"),
             Car_Color     => Location (World_Prog, "uCarColor"),
             Shadow_Map    => Location (World_Prog, "uShadowMap"),
             Shadows       => Location (World_Prog, "uShadows"),
             Amb_Sky       => Location (World_Prog, "uAmbSky"),
             Amb_Ground    => Location (World_Prog, "uAmbGround"),
             Night         => Location (World_Prog, "uNight"),
             Lights        => Location (World_Prog, "uLights"),
             Light_Count   => Location (World_Prog, "uLightCount"),
             Head_Pos      => Location (World_Prog, "uHeadPos"),
             Head_Dir      => Location (World_Prog, "uHeadDir"),
             Head_On       => Location (World_Prog, "uHeadOn"),
             Extra_Color   => Location (World_Prog, "uExtraColor"),
             Extra_Color2  => Location (World_Prog, "uExtraColor2"),
             Wet           => Location (World_Prog, "uWet"));
      Sky_Inv_VP := Location (Sky_Prog, "uInvViewProj");
      Sky_Cam := Location (Sky_Prog, "uCamPos");
      Sky_Sun := Location (Sky_Prog, "uSunDir");
      Sky_Zen := Location (Sky_Prog, "uSkyZenith");
      Sky_Hor := Location (Sky_Prog, "uSkyHorizon");
      Sky_Night := Location (Sky_Prog, "uNight");
      Sky_Clouds := Location (Sky_Prog, "uClouds");
      Sh_Light_VP := Location (Shadow_Prog, "uLightViewProj");
      Sh_Model := Location (Shadow_Prog, "uModel");

      glGenVertexArrays (1, Empty_VAO'Address);
      Create_Shadow_Map;
      Car.Create_Mesh;
      Plane.Create_Mesh;
      Pedestrians.Create_Mesh;
      Rain.Create;

      Profiling := Ada.Environment_Variables.Exists ("PARIS_PROFILE");
      declare
         Dir : constant String :=
           (if Ada.Environment_Variables.Exists ("PARIS_TILES")
            then Ada.Environment_Variables.Value ("PARIS_TILES") else "tiles");
      begin
         World.Init (Dir);
         Road_Network.Load (Dir);
      end;
      Reset_Car;
      World.Load_All_Near (Player.X, Player.Z);
      Ready := True;
   exception
      when E : others =>
         Ada.Text_IO.Put_Line ("Initialisation failed: "
                               & Ada.Exceptions.Exception_Message (E));
         Gtk.Main.Main_Quit;
   end Realize;

   ---------------------------------------------------------------------------
   --  Rendering
   ---------------------------------------------------------------------------

   --  Where the action is: the car, or the plane in flight
   function Focus return Vec3 is
     (if Mode = Flying then Aircraft.Pos else (Player.X, 0.0, Player.Z));

   function Focus_Heading return Float is
     (if Mode = Flying then Aircraft.Heading else Player.Heading);

   function Focus_Forward return Vec3 is
     (Sin (Focus_Heading), 0.0, -Cos (Focus_Heading));

   function Smoothstep (E0, E1, X : Float) return Float is
      T : constant Float := Float'Max (0.0, Float'Min (1.0, (X - E0) / (E1 - E0)));
   begin
      return T * T * (3.0 - 2.0 * T);
   end Smoothstep;

   function Mix (A, B : Vec3; T : Float) return Vec3 renames Lerp;

   function To_Linear (C : Vec3) return Vec3 is
     (C.X ** 2.2, C.Y ** 2.2, C.Z ** 2.2);

   --  Sun path (a Paris summer day: sunrise about 6:00, sunset about
   --  22:00), sky colours and ambient light for the current hour
   procedure Compute_Lighting is
      A    : constant Float := (Hour - 6.0) / 16.0 * Ada.Numerics.Pi;
      Sun  : constant Vec3 := Normalize ((Cos (A), Sin (A) * 0.95, 0.35 + 0.25 * Sin (A)));
      Moon : constant Vec3 := Normalize ((0.45, 0.75, -0.40));
      Day  : constant Float := Smoothstep (-0.10, 0.18, Sun.Y);
      Low  : constant Float := 1.0 - Smoothstep (0.02, 0.38, Sun.Y);
      Day_Zen : constant Vec3 := Mix ((0.30, 0.50, 0.82), (0.24, 0.33, 0.58), Low);
      Day_Hor : constant Vec3 := Mix ((0.78, 0.84, 0.91), (0.96, 0.64, 0.42), Low);
   begin
      Night := 1.0 - Smoothstep (-0.12, 0.10, Sun.Y);
      Sky_Zenith := Mix ((0.010, 0.016, 0.045), Day_Zen, Day);
      Sky_Horizon := Mix ((0.075, 0.068, 0.085), Day_Hor, Day);
      if Sun.Y > -0.03 then
         Sun_Dir := Sun;
         Sun_Color := Smoothstep (-0.03, 0.12, Sun.Y)
           * Mix ((2.6, 1.3, 0.6), (3.0, 2.75, 2.35), Smoothstep (0.0, 0.45, Sun.Y));
      else
         Sun_Dir := Moon;
         Sun_Color := Smoothstep (-0.03, -0.2, Sun.Y) * Vec3'(0.07, 0.09, 0.16);
      end if;
      Amb_Sky := Mix ((0.010, 0.013, 0.026), Mix (Vec3'(0.26, 0.33, 0.46), 0.55 * To_Linear (Day_Hor), Low * 0.5), Day);
      Amb_Ground := Mix ((0.020, 0.015, 0.011), (0.11, 0.09, 0.06), Day);

      --  Overcast when it rains: weak sun, grey sky, softer and hazier
      if Rain_Amount > 0.0 then
         declare
            R : constant Float := Rain_Amount;
            function Grey (C : Vec3; Tint : Vec3) return Vec3 is
              ((0.3 * C.X + 0.55 * C.Y + 0.15 * C.Z) * Tint);
         begin
            Sun_Color := (1.0 - 0.8 * R) * Sun_Color;
            Sky_Zenith := Mix (Sky_Zenith, 0.75 * Grey (Sky_Zenith, (0.95, 0.98, 1.05)), R);
            Sky_Horizon := Mix (Sky_Horizon, 0.85 * Grey (Sky_Horizon, (0.97, 0.99, 1.03)), R);
            Amb_Sky := Mix (Amb_Sky, 1.1 * Grey (Amb_Sky, (0.95, 1.0, 1.08)), R);
         end;
      end if;
      Fog_Density := Fog_Base * (1.0 + 2.5 * Rain_Amount);
   end Compute_Lighting;

   function Light_View_Proj return Mat4 is
      Center : constant Vec3 :=
        (Focus.X + 120.0 * Focus_Forward.X * (if Mode = Flying then 1.0 else 0.0), 0.0,
         Focus.Z + 120.0 * Focus_Forward.Z * (if Mode = Flying then 1.0 else 0.0));
      View   : constant Mat4 :=
        Look_At (Center + 600.0 * Sun_Dir, Center, (0.0, 1.0, 0.0));
      Proj   : constant Mat4 :=
        Ortho (-Shadow_Extent, Shadow_Extent, -Shadow_Extent, Shadow_Extent,
               1.0, 1400.0);
      VP     : Mat4 := Proj * View;
      Half   : constant Float := Float (Shadow_Size) / 2.0;
   begin
      --  Snap the shadow box to whole texels so shadows do not shimmer
      for I in 12 .. 13 loop
         VP (I) := Float'Rounding (VP (I) * Half) / Half;
      end loop;
      return VP;
   end Light_View_Proj;

   --  Debug aid: PARIS_SHOT=<file.ppm> saves frame PARIS_SHOT_FRAME (default
   --  90) and quits.  PARIS_SPAWN="lat lon heading_degrees", PARIS_DRONE=1
   --  (or "back up") and PARIS_TIME=<hour> choose the view; PARIS_PROFILE=1
   --  adds GPU/CPU timings to the report.
   Frame_Number : Natural := 0;


   function Env (Name : String; Default : String := "") return String is
     (if Ada.Environment_Variables.Exists (Name)
      then Ada.Environment_Variables.Value (Name) else Default);

   procedure Save_Screenshot (Name : String; W, H : Integer) is
      use Ada.Streams.Stream_IO;
      type Pixel_Array is array (Natural range <>) of Interfaces.Unsigned_8;
      Pixels : Pixel_Array (0 .. W * H * 4 - 1);
      F      : File_Type;
      Header : constant String := "P6" & ASCII.LF & Integer'Image (W)
        & Integer'Image (H) & ASCII.LF & "255" & ASCII.LF;
      Row    : Pixel_Array (0 .. W * 3 - 1);
   begin
      glReadPixels (0, 0, GLsizei (W), GLsizei (H), GL_RGBA, GL_UNSIGNED_BYTE,
                    Pixels'Address);
      Create (F, Out_File, Name);
      String'Write (Stream (F), Header);
      for Y in reverse 0 .. H - 1 loop
         for X in 0 .. W - 1 loop
            for C in 0 .. 2 loop
               Row (X * 3 + C) := Pixels ((Y * W + X) * 4 + C);
            end loop;
         end loop;
         Pixel_Array'Write (Stream (F), Row);
      end loop;
      Close (F);
   end Save_Screenshot;

   function Render (Area_Ptr, Context, Data : System.Address) return Glib.Gboolean
     with Convention => C;
   function Render (Area_Ptr, Context, Data : System.Address) return Glib.Gboolean
   is
      pragma Unreferenced (Area_Ptr, Context, Data);
      use Shaders;
      Target   : aliased GLint := 0;
      Viewport : aliased GLint_Array (0 .. 3) := (others => 0);
      W, H     : Integer;
   begin
      if not Ready then
         return 1;
      end if;
      glGetIntegerv (GL_FRAMEBUFFER_BINDING, Target'Address);
      glGetIntegerv (GL_VIEWPORT, Viewport'Address);
      W := Integer (Viewport (2));
      H := Integer (Viewport (3));
      if W <= 0 or else H <= 0 then
         return 1;
      end if;

      declare
         T0 : constant Ada.Real_Time.Time := Clock_Now;
      begin
         --  In flight, stream ahead of the plane
         World.Update (Focus.X + (if Mode = Flying then 150.0 * Focus_Forward.X else 0.0),
                       Focus.Z + (if Mode = Flying then 150.0 * Focus_Forward.Z else 0.0));
         Add (C_World, T0);
      end;

      declare
         Proj : constant Mat4 :=
           Perspective (1.05, Float (W) / Float (H), 0.3, 3000.0);
         View : constant Mat4 := Look_At (Cam_Pos, Cam_Look, (0.0, 1.0, 0.0));
         VP   : constant Mat4 := Proj * View;
         LVP  : constant Mat4 := Light_View_Proj;
         Car_M : constant Mat4 := Car.Model_Matrix (Player);
      begin
         --  Shadow pass
         Begin_Pass (P_Shadow);
         glBindFramebuffer (GL_FRAMEBUFFER, Shadow_FBO);
         glViewport (0, 0, Shadow_Size, Shadow_Size);
         glEnable (GL_DEPTH_TEST);
         glDepthFunc (GL_LESS);
         glDepthMask (GL_TRUE);
         glClear (GL_DEPTH_BUFFER_BIT);
         glUseProgram (Shadow_Prog);
         Set (Sh_Light_VP, LVP);
         Set (Sh_Model, Identity);
         World.Cull_To (LVP);
         World.Draw_Solid;
         Set (Sh_Model, Car_M);
         Car.Draw;
         Traffic.Draw (Sh_Model, GLint (-1));
         Pedestrians.Draw (Sh_Model, -1, -1, -1, Cam_Pos.X, Cam_Pos.Z, 50.0);
         if Mode = Flying then
            Plane.Draw (Aircraft, Sh_Model);
         end if;
         End_Pass (P_Shadow);
         Begin_Pass (P_Solid);

         --  Main pass into the multisampled framebuffer
         Ensure_MSAA (W, H);
         glBindFramebuffer (GL_FRAMEBUFFER, MSAA_FBO);
         glViewport (0, 0, GLsizei (W), GLsizei (H));
         glClear (GL_DEPTH_BUFFER_BIT + GL_STENCIL_BUFFER_BIT);

         glDisable (GL_DEPTH_TEST);
         glUseProgram (Sky_Prog);
         Set (Sky_Inv_VP, Inverse (VP));
         Set (Sky_Cam, Cam_Pos);
         Set (Sky_Sun, Sun_Dir);
         Set (Sky_Zen, Sky_Zenith);
         Set (Sky_Hor, Sky_Horizon);
         Set (Sky_Night, Night);
         Set (Sky_Clouds, Rain_Amount);
         glBindVertexArray (Empty_VAO);
         glDrawArrays (GL_TRIANGLES, 0, 3);

         glEnable (GL_DEPTH_TEST);
         glUseProgram (World_Prog);
         Set (WU.View_Proj, VP);
         Set (WU.Model, Identity);
         Set (WU.Shadow_Matrix, LVP);
         Set (WU.Cam_Pos, Cam_Pos);
         Set (WU.Sun_Dir, Sun_Dir);
         Set (WU.Sun_Color, Sun_Color);
         Set (WU.Sky_Zenith, Sky_Zenith);
         Set (WU.Sky_Horizon, Sky_Horizon);
         Set (WU.Fog_Density, Fog_Density);
         Set (WU.Wet, Wetness);
         Set (WU.Time, Time);
         Set (WU.Car_Color, Car_Color);
         Set (WU.Shadow_Map, 0);
         Set (WU.Shadows, 1);
         Set (WU.Amb_Sky, Amb_Sky);
         Set (WU.Amb_Ground, Amb_Ground);
         Set (WU.Night, Night);
         declare
            Lights : aliased World.Light_Data;
            N      : Natural;
            Fwd    : constant Vec3 := Car.Forward (Player);
            T0     : constant Ada.Real_Time.Time := Clock_Now;
            Ahead  : constant Float := (if Mode = Flying then 60.0 else 15.0);
         begin
            World.Nearest_Lights (Focus.X + Ahead * Focus_Forward.X,
                                  Focus.Z + Ahead * Focus_Forward.Z, Lights, N);
            Add (C_Lights, T0);
            Set (WU.Light_Count, N);
            if N > 0 then
               glUniform4fv (WU.Lights, GLsizei (N), Lights'Address);
            end if;
            Set (WU.Head_Pos, Vec3'(Player.X, 0.75, Player.Z) + 2.2 * Fwd);
            Set (WU.Head_Dir, Normalize (Fwd + (0.0, -0.06, 0.0)));
            Set (WU.Head_On, (if Mode = Driving then Smoothstep (0.2, 0.6, Night) else 0.0));
         end;
         glActiveTexture (GL_TEXTURE0);
         glBindTexture (GL_TEXTURE_2D, Shadow_Tex);

         --  Solids first, then the ground only where nothing covers it.
         --  Alpha to coverage makes the lattice (alpha < 1) see-through.
         glDepthFunc (GL_LESS);
         World.Cull_To (VP);
         glEnable (GL_SAMPLE_ALPHA_TO_COVERAGE);
         World.Draw_Solid;
         glDisable (GL_SAMPLE_ALPHA_TO_COVERAGE);
         Set (WU.Model, Car_M);
         Set (WU.Car_Color, Car_Color);
         Car.Draw;
         Traffic.Draw (WU.Model, WU.Car_Color);
         Pedestrians.Draw (WU.Model, WU.Car_Color, WU.Extra_Color, WU.Extra_Color2,
                           Cam_Pos.X, Cam_Pos.Z, 130.0);
         if Mode = Flying then
            Set (WU.Car_Color, Plane_Color);
            Plane.Draw (Aircraft, WU.Model);
         end if;
         Set (WU.Model, Identity);
         End_Pass (P_Solid);
         Begin_Pass (P_Ground);
         World.Draw_Ground;
         Rain.Draw (VP, Cam_Pos, Time, Rain_Amount,
                    Mix (Vec3'(0.30, 0.32, 0.36), Vec3'(0.75, 0.78, 0.82), 1.0 - Night));
         End_Pass (P_Ground);
         Begin_Pass (P_Resolve);

         --  Resolve into GTK's framebuffer
         glBindFramebuffer (GL_READ_FRAMEBUFFER, MSAA_FBO);
         glBindFramebuffer (GL_DRAW_FRAMEBUFFER, GLuint (Target));
         glBlitFramebuffer (0, 0, GLint (W), GLint (H), 0, 0, GLint (W), GLint (H),
                            GL_COLOR_BUFFER_BIT, GL_NEAREST);
         glBindFramebuffer (GL_FRAMEBUFFER, GLuint (Target));
         End_Pass (P_Resolve);
      end;
      Fps_Frames := Fps_Frames + 1;
      Frame_Number := Frame_Number + 1;
      if Env ("PARIS_SHOT") /= ""
        and then Frame_Number = Integer'Value (Env ("PARIS_SHOT_FRAME", "90"))
      then
         Save_Screenshot (Env ("PARIS_SHOT"), W, H);
         Ada.Text_IO.Put_Line
           ("frames:" & Natural'Image (Frame_Number) & "  avg fps:"
            & Integer'Image (Integer (Float (Frame_Number) / Time))
            & "  car at" & Integer'Image (Integer (Player.X))
            & Integer'Image (Integer (Player.Z))
            & "  speed" & Integer'Image (Integer (Player.Speed * 3.6))
            & "  traffic" & Natural'Image (Traffic.Count)
            & "  people" & Natural'Image (Pedestrians.Count)
            & (if Mode = Flying then
                 "  plane at" & Integer'Image (Integer (Aircraft.Pos.X))
                 & Integer'Image (Integer (Aircraft.Pos.Y))
                 & Integer'Image (Integer (Aircraft.Pos.Z))
                 & (if Aircraft.Crashed > 0.0 then " CRASHED" else "")
               else ""));
         if Profiling then
            Ada.Text_IO.Put ("  frame times:");
            for B in Dt_Hist'Range loop
               Ada.Text_IO.Put (Integer'Image (B * 4) & "ms:" & Natural'Image (Dt_Hist (B)));
            end loop;
            Ada.Text_IO.New_Line;
            for C in Cpu_Part loop
               Ada.Text_IO.Put
                 ("  cpu " & Cpu_Part'Image (C) & ":"
                  & Integer'Image (Integer (Float (Cpu_Total (C)) * 1.0E6
                                           / Float (Frame_Number))) & " us");
            end loop;
            Ada.Text_IO.New_Line;
            for P in Pass loop
               Ada.Text_IO.Put_Line
                 ("  gpu " & Pass'Image (P) & ":"
                  & Integer'Image (Integer (1000.0 * Gpu_Total (P) / Long_Float (Frame_Number)))
                  & " us/frame");
            end loop;
         end if;
         Gtk.Main.Main_Quit;
      end if;
      return 1;
   end Render;

   ---------------------------------------------------------------------------
   --  Simulation tick
   ---------------------------------------------------------------------------

   Min_Zoom : constant := 0.35;
   Max_Zoom : constant := 8.0;

   procedure Zoom_By (Factor : Float) is
   begin
      Zoom := Float'Max (Min_Zoom, Float'Min (Max_Zoom, Zoom * Factor));
   end Zoom_By;

   procedure Update_Camera (Dt : Float) is
      Desired, Look : Vec3;
      K : constant Float := 1.0 - Exp (-Dt * (if Mode = Flying then 8.0 else 6.0));
   begin
      if Fixed_Camera then
         return;
      end if;
      if Mode = Flying then
         --  Behind and a little above the plane, following its heading
         --  (and half its pitch, so loops stay readable)
         declare
            H  : constant Float := Aircraft.Heading;
            P  : constant Float := 0.5 * Aircraft.Pitch;
            Bk : constant Vec3 := (Sin (H) * Cos (P), Sin (P), -Cos (H) * Cos (P));
         begin
            Desired := Aircraft.Pos - (16.0 * Zoom) * Bk + (0.0, 4.0 * Zoom, 0.0);
            Look := Aircraft.Pos + 10.0 * Plane.Forward (Aircraft);
         end;
      else
         declare
            Fwd     : constant Vec3 := Car.Forward (Player);
            Car_Pos : constant Vec3 := (Player.X, 0.0, Player.Z);
            Back    : constant Float := Zoom * (if Drone then Drone_Back else 8.5);
            Up      : constant Float := Zoom * (if Drone then Drone_Up else 3.2);
         begin
            Desired := Car_Pos - Back * Fwd + (0.0, Up, 0.0);
            Look := Car_Pos + (0.0, 1.2, 0.0) + (if Drone then 6.0 else 3.0) * Fwd;
         end;
      end if;
      Cam_Pos := Lerp (Cam_Pos, Desired, K);
      Cam_Look := Lerp (Cam_Look, Look, 1.0 - Exp (-Dt * 12.0));
      if Cam_Pos.Y < 1.0 then
         Cam_Pos.Y := 1.0;
      end if;
   end Update_Camera;

   --  Jump to a place: the car onto the nearest road, the plane above it
   procedure Teleport (P : Place) is
      X, Z : Long_Float;
      Found : Boolean;
      RX, RZ, H : Float;
   begin
      Geo.To_Local (P.Lat, P.Lon, X, Z);
      if Mode = Flying then
         Plane.Start (Aircraft, Float (X), Float (Z), Aircraft.Heading);
      else
         Road_Network.Nearest_Road (Float (X), Float (Z), Found, RX, RZ, H);
         if not Found then
            RX := Float (X);
            RZ := Float (Z);
            H := Player.Heading;
         end if;
         Player := (X => RX, Z => RZ, Heading => H, others => <>);
         Cam_Pos := (RX, 6.0, RZ) - 10.0 * Car.Forward (Player);
         Cam_Look := (RX, 1.2, RZ);
      end if;
      World.Load_All_Near (Focus.X, Focus.Z);
      Announce := P.Name;
      Announce_Timer := 3.0;
      Street_Timer := 1.0;   --  refresh the plaque now
   end Teleport;

   --  F: take off from the car, or land: the car goes to the nearest road
   --  below the plane
   procedure Toggle_Flight is
   begin
      if Mode = Driving then
         Mode := Flying;
         Plane.Start (Aircraft, Player.X, Player.Z, Player.Heading);
         World.Set_Radius (4);
      else
         declare
            Found : Boolean;
            X, Z, H : Float;
         begin
            Road_Network.Nearest_Road (Aircraft.Pos.X, Aircraft.Pos.Z, Found, X, Z, H);
            if Found then
               Player := (X => X, Z => Z, Heading => H, others => <>);
            end if;
         end;
         Mode := Driving;
         World.Set_Radius (3);
         Cam_Pos := (Player.X, 30.0, Player.Z) - 20.0 * Car.Forward (Player);
      end if;
   end Toggle_Flight;

   function Clock_Image return String is
      Minutes : constant Natural := Natural (Float'Floor (Hour * 60.0)) mod (24 * 60);
      HH      : constant String := Natural'Image (Minutes / 60);
      MM      : constant String := Natural'Image (100 + Minutes mod 60);
   begin
      return HH (2 .. HH'Last) & ":" & MM (3 .. 4);
   end Clock_Image;

   function Tick
     (Widget      : not null access Gtk.Widget.Gtk_Widget_Record'Class;
      Frame_Clock : not null access Gdk.Frame_Clock.Gdk_Frame_Clock_Record'Class)
      return Boolean
   is
      pragma Unreferenced (Widget);
      Now : constant Glib.Gint64 := Frame_Clock.Get_Frame_Time;
      Dt  : Float;
      Steps : Positive;
   begin
      if Last_Frame = 0 then
         Last_Frame := Now;
      end if;
      Dt := Float'Min (0.1, Float (Now - Last_Frame) / 1.0E6);
      declare
         B : constant Natural := Natural'Min (10, Natural (Float'Floor (Dt * 250.0)));
      begin
         Dt_Hist (B) := Dt_Hist (B) + 1;
      end;
      Last_Frame := Now;
      Time := Time + Dt;

      if Ready and then Env ("PARIS_AUTODRIVE") /= "" then
         Keys.W := True;
      end if;

      --  Weather changes over about ten seconds; streets dry in a minute
      if Rain_Amount < Rain_Target then
         Rain_Amount := Float'Min (Rain_Target, Rain_Amount + Dt / 10.0);
      else
         Rain_Amount := Float'Max (Rain_Target, Rain_Amount - Dt / 10.0);
      end if;
      if Wetness < Rain_Amount then
         Wetness := Float'Min (Rain_Amount, Wetness + Dt / 15.0);
      else
         Wetness := Float'Max (Rain_Amount, Wetness - Dt / 60.0);
      end if;
      Hour := Hour + Dt * Clock_Rate;
      if Hour >= 24.0 then
         Hour := Hour - 24.0;
      end if;
      Compute_Lighting;

      if Ready then
         declare
            T0 : Ada.Real_Time.Time := Clock_Now;
         begin
            Steps := Positive'Max (1, Integer (Float'Ceiling (Dt / 0.008)));
            if Mode = Driving then
               declare
                  Input : constant Car.Controls :=
                    (Throttle  => Keys.Up or else Keys.W,
                     Brake     => Keys.Down or else Keys.S,
                     Left      => Keys.Left or else Keys.A,
                     Right     => Keys.Right or else Keys.D,
                     Handbrake => Keys.Space);
               begin
                  for I in 1 .. Steps loop
                     Car.Update (Player, Input, Dt / Float (Steps));
                     Traffic.Collide_Player (Player);
                  end loop;
               end;
            else
               declare
                  Input : constant Plane.Controls :=
                    (Throttle_Up   => Keys.W,
                     Throttle_Down => Keys.S,
                     Nose_Down     => Keys.Up,
                     Nose_Up       => Keys.Down,
                     Roll_Left     => Keys.Left or else Keys.A,
                     Roll_Right    => Keys.Right or else Keys.D);
               begin
                  for I in 1 .. Steps loop
                     Plane.Update (Aircraft, Input, Dt / Float (Steps));
                  end loop;
               end;
            end if;
            Add (C_Physics, T0);
            T0 := Clock_Now;
            Traffic.Update (Dt, Time, Focus.X, Focus.Z, Focus_Heading, Player);
            Pedestrians.Update (Dt, Focus.X, Focus.Z, Focus_Heading, Player);
            Add (C_Traffic, T0);
         end;
         Update_Camera (Dt);
      end if;

      Hud_Timer := Hud_Timer + Dt;
      if Hud_Timer >= 0.5 then
         Fps := Float (Fps_Frames) / Hud_Timer;
         Fps_Frames := 0;
         Hud_Timer := 0.0;
         Hud.Set_Markup
           ("<span font_family='monospace' foreground='white' background='#00000088'> "
            & (if Mode = Driving then
                 Integer'Image (Integer (abs Player.Speed * 3.6)) & " km/h   "
               elsif Aircraft.Crashed > 0.0 then
                 " CRASH!   "
               else
                 Integer'Image (Integer (Aircraft.Speed * 3.6)) & " km/h"
                 & Integer'Image (Integer (Aircraft.Pos.Y)) & " m  throttle"
                 & Integer'Image (Integer (Aircraft.Throttle * 100.0)) & "%   ")
            & Integer'Image (Integer (Fps)) & " fps   "
            & Clock_Image & (if Rain_Target > 0.0 then " rain" else "")
            & "   cars" & Natural'Image (Traffic.Count)
            & "  people" & Natural'Image (Pedestrians.Count) & ASCII.LF & " "
            & (if Mode = Driving then
                 "[arrows/WASD] drive  [space] handbrake  [C] camera"
               else
                 "[W/S] throttle  [up/down] nose down/up  [left/right] bank")
            & "  [wheel/+/-] zoom  [F] "
            & (if Mode = Driving then "fly" else "land and drive")
            & "  [T] +1 hour  [P] rain  [N] street names  [1-0] places  [H] home  [R] reset </span>");
      end if;

      --  Street name sign: a few times a second, and only touch the label
      --  when the text changes (a GTK relayout costs frame time)
      Street_Timer := Street_Timer + Dt;
      if Ready and then Street_Timer >= 0.3 then
         Street_Timer := 0.0;
         Announce_Timer := Announce_Timer - 0.3;
         declare
            use Ada.Strings.Unbounded;
            Name : constant String :=
              (if Announce_Timer > 0.0 then To_String (Announce)
               elsif not Show_Street then ""
               elsif Mode = Flying then
                 (if Aircraft.Pos.Y < 150.0
                  then Road_Network.Street_At (Aircraft.Pos.X, Aircraft.Pos.Z, 40.0) else "")
               else Road_Network.Street_At (Player.X, Player.Z));
         begin
            if Name /= To_String (Street_Shown) then
               Street_Shown := To_Unbounded_String (Name);
               if Name = "" then
                  Sign.Hide;
               else
                  Sign.Set_Text (Name);
                  Sign.Show;
               end if;
            end if;
         end;
      end if;

      Area.Queue_Render;
      return True;
   end Tick;

   ---------------------------------------------------------------------------
   --  Input
   ---------------------------------------------------------------------------

   procedure Set_Key (Key : Gdk.Types.Gdk_Key_Type; Down : Boolean) is
      K : Gdk.Types.Gdk_Key_Type := Key;
   begin
      if K in 16#41# .. 16#5A# then   --  upper case letters
         K := K + 16#20#;
      end if;
      case K is
         when 16#FF52# => Keys.Up := Down;
         when 16#FF54# => Keys.Down := Down;
         when 16#FF51# => Keys.Left := Down;
         when 16#FF53# => Keys.Right := Down;
         when 16#77#   => Keys.W := Down;
         when 16#73#   => Keys.S := Down;
         when 16#61#   => Keys.A := Down;
         when 16#64#   => Keys.D := Down;
         when 16#20#   => Keys.Space := Down;
         when 16#66# =>                                       --  f
            if Down then
               Toggle_Flight;
            end if;
         when 16#30# .. 16#39# =>                             --  0 .. 9
            if Down then
               Teleport (Places (Integer (K) - 16#30#));
            end if;
         when 16#68# =>                                       --  h: home
            if Down then
               Teleport (Places (1));
            end if;
         when 16#6E# =>                                       --  n
            if Down then
               Show_Street := not Show_Street;
            end if;
         when 16#70# =>                                       --  p
            if Down then
               Rain_Target := (if Rain_Target > 0.0 then 0.0 else 1.0);
            end if;
         when 16#2B# | 16#3D# | 16#FFAB# | 16#FF55# =>        --  + = keypad+ PgUp
            if Down then
               Zoom_By (1.0 / 1.25);
            end if;
         when 16#2D# | 16#FFAD# | 16#FF56# =>                 --  - keypad- PgDn
            if Down then
               Zoom_By (1.25);
            end if;
         when 16#63# =>                                       --  c
            if Down then
               Drone := not Drone;
            end if;
         when 16#74# =>                                       --  t
            if Down then
               Hour := Hour + 1.0;
               if Hour >= 24.0 then
                  Hour := Hour - 24.0;
               end if;
            end if;
         when 16#72# =>                                       --  r
            if Down then
               if Mode = Flying then
                  Plane.Start (Aircraft, Aircraft.Pos.X, Aircraft.Pos.Z, Aircraft.Heading);
               else
                  Reset_Car;
               end if;
            end if;
         when 16#FF1B# =>                                     --  Escape
            if Down then
               Gtk.Main.Main_Quit;
            end if;
         when others => null;
      end case;
   end Set_Key;

   function Key_Press
     (Self : access Gtk.Widget.Gtk_Widget_Record'Class;
      Event : Gdk.Event.Gdk_Event_Key) return Boolean
   is
      pragma Unreferenced (Self);
   begin
      Set_Key (Event.Keyval, True);
      return True;
   end Key_Press;

   function Key_Release
     (Self : access Gtk.Widget.Gtk_Widget_Record'Class;
      Event : Gdk.Event.Gdk_Event_Key) return Boolean
   is
      pragma Unreferenced (Self);
   begin
      Set_Key (Event.Keyval, False);
      return True;
   end Key_Release;

   --  Mouse wheel: zoom the camera in and out
   function Scroll
     (Self  : access Gtk.Widget.Gtk_Widget_Record'Class;
      Event : Gdk.Event.Gdk_Event_Scroll) return Boolean
   is
      pragma Unreferenced (Self);
      use Gdk.Event;
   begin
      case Event.Direction is
         when Scroll_Up => Zoom_By (1.0 / 1.15);
         when Scroll_Down => Zoom_By (1.15);
         when Scroll_Smooth => Zoom_By (1.15 ** Float (Event.Delta_Y));
         when others => null;
      end case;
      return True;
   end Scroll;

   procedure On_Destroy (Self : access Gtk.Widget.Gtk_Widget_Record'Class) is
      pragma Unreferenced (Self);
   begin
      Gtk.Main.Main_Quit;
   end On_Destroy;

   ---------------------------------------------------------------------------

   procedure Run is
      Overlay : Gtk.Overlay.Gtk_Overlay;
      Credit  : Gtk.Label.Gtk_Label;
      Id      : Glib.Guint;
   begin
      Gtk.Main.Init;

      Gtk.Window.Gtk_New (Window);
      Window.Set_Title ("Paris");
      Window.Set_Default_Size (1600, 900);
      Window.On_Destroy (On_Destroy'Access);
      Window.On_Key_Press_Event (Key_Press'Access);
      Window.On_Key_Release_Event (Key_Release'Access);
      Window.Add_Events (Gdk.Event.Scroll_Mask or Gdk.Event.Smooth_Scroll_Mask);
      Window.On_Scroll_Event (Scroll'Access);

      Gtk.Overlay.Gtk_New (Overlay);
      Window.Add (Overlay);

      GL_Area.Gtk_New (Area);
      Area.Set_Required_Version (3, 3);
      Area.Set_Has_Depth_Buffer (False);
      Area.On_Realize (Realize'Access);
      Area.On_Render (Render'Access);
      Overlay.Add (Area);

      Gtk.Label.Gtk_New (Hud);
      Hud.Set_Halign (Gtk.Widget.Align_Start);
      Hud.Set_Valign (Gtk.Widget.Align_End);
      Hud.Set_Margin_Start (10);
      Hud.Set_Margin_Bottom (10);
      Overlay.Add_Overlay (Hud);

      --  Street name plaque, top centre: enamel blue, white letters, green frame
      Gtk.Label.Gtk_New (Sign);
      Sign.Set_Halign (Gtk.Widget.Align_Center);
      Sign.Set_Valign (Gtk.Widget.Align_Start);
      Sign.Set_Margin_Top (14);
      Sign.Set_No_Show_All (True);
      declare
         Css   : Gtk.Css_Provider.Gtk_Css_Provider;
         Dummy : Boolean;
      begin
         Gtk.Css_Provider.Gtk_New (Css);
         Dummy := Css.Load_From_Data
           (".street-sign { background-color: #1d3b72; color: #ffffff;"
            & " font-family: sans-serif; font-weight: bold; font-size: 22px;"
            & " padding: 6px 22px; border: 3px solid #f2f2f2; border-radius: 6px;"
            & " box-shadow: 0 0 0 3px #2f6b45, 0 3px 8px rgba(0,0,0,0.5); }",
            null);
         Gtk.Style_Context.Get_Style_Context (Sign).Add_Provider
           (Gtk.Css_Provider."+" (Css), Gtk.Style_Provider.Priority_Application);
         Gtk.Style_Context.Get_Style_Context (Sign).Add_Class ("street-sign");
      end;
      Overlay.Add_Overlay (Sign);

      Gtk.Label.Gtk_New (Credit);
      Credit.Set_Markup
        ("<span size='small' foreground='white' background='#00000088'>"
         & " Map data &#169; OpenStreetMap contributors (ODbL) </span>");
      Credit.Set_Halign (Gtk.Widget.Align_End);
      Credit.Set_Valign (Gtk.Widget.Align_End);
      Credit.Set_Margin_End (10);
      Credit.Set_Margin_Bottom (10);
      Overlay.Add_Overlay (Credit);

      Id := Area.Add_Tick_Callback (Tick'Access);
      pragma Unreferenced (Id);

      Window.Show_All;
      Gtk.Main.Main;
   end Run;

end Game;
