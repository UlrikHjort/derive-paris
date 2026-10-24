--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Streams.Stream_IO;
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Ada.Unchecked_Conversion;
with Interfaces.C;
with System;

with Cairo;
with Cairo.Image_Surface;
with Cairo.Png;
with Cairo.Surface;
with Gdk;
with Gdk.Event;
with Gdk.Frame_Clock;
with Gdk.Types;
with Glib;
with Gtk.Css_Provider;
with Gtk.Enums;
with Gtk.Label;
with Gtk.Main;
with Gtk.Overlay;
with Gtk.Style_Context;
with Gtk.Style_Provider;
with Gtk.Widget;
with Gtk.Window;

with Beacon;
with Almanac;
with Car;
with Compass;
with Config;
with Geo;
with Halloween;
with Instruments;
with Landscape;
with GL;
with GL_Area;
with Math3D;
with Museum;
with Navigation;
with Night_Bus;
with Pedestrians;
with Photo;
with Plane;
with Race;
with Radio;
with Taxi;
with Arc_Top;
with Hall_B;
with Decals;
with Scenes;
with Seasons;
with Birds;
with Stravinsky;
with Addresses;
with Extras;
with Moulin;
with Rooms;
with Postcards;
with Closures;
with Stunts;
with Rounds;
with Trials;
with Boats;
with Era;
with Altimeter;
with River;
with Gdk.Keyval;
with Gtkada.Bindings;
with Glib.Unicode;
with Street_Life;
with Limit_Sign;
with Rain;
with Recorder;
with Road_Network;
with Saved_Places;
with Shaders;
with Sky_Life;
with Sleigh;
with Sound;
with Storm;
with Terrain;
with Surprises;
with Tower;
with Traffic;
with Tyre_Effects;
with Ufo;
with Wheel;
with World;
with Xmas;

package body Game is

   use GL;
   use Math3D;
   use Ada.Numerics.Elementary_Functions;
   use type Glib.Gint64;
   use type Glib.Guint;
   use type Interfaces.C.unsigned;
   use type Interfaces.C.int;
   use type Gdk.Types.Gdk_Key_Type;
   use type Gdk.Event.Gdk_Event_Mask;

   --  Start and home (H, R): Rue Bonaparte at the corner of Place
   --  Saint-Sulpice, facing north towards Saint-Germain-des-Pres (the
   --  street is one-way north)
   --  Home: Rue Bonaparte by the Place Saint-Sulpice, or "home = lat lon
   --  heading" in ~/.deriverc (Shift+H sets it to where you are)
   Spawn_Lat     : Long_Float := 48.85190;
   Spawn_Lon     : Long_Float := 2.333020;
   Spawn_Heading : Float := 8.0 * Ada.Numerics.Pi / 180.0;
   Spawn_Name    : Ada.Strings.Unbounded.Unbounded_String :=
     Ada.Strings.Unbounded.To_Unbounded_String ("Rue Bonaparte");

   procedure Read_Home is
      S : constant String := Config.Get ("home", "") & " ";
      Field : array (1 .. 3) of Long_Float := (0.0, 0.0, 8.0);
      K     : Natural := 0;
      First : Positive := S'First;
   begin
      if S'Length < 5 then
         return;
      end if;
      for I in S'Range loop
         if S (I) = ' ' then
            if I > First and then K < 3 then
               K := K + 1;
               Field (K) := Long_Float'Value (S (First .. I - 1));
            end if;
            First := I + 1;
         end if;
      end loop;
      if K >= 2 then
         Spawn_Lat := Field (1);
         Spawn_Lon := Field (2);
         Spawn_Heading := Float (Field (3)) * Ada.Numerics.Pi / 180.0;
         Spawn_Name := Ada.Strings.Unbounded.To_Unbounded_String ("Home");
      end if;
   exception
      when Constraint_Error => null;   --  a bad line: the default home
   end Read_Home;

   Shadow_Size   : constant := 4096;
   Shadow_Extent : constant := 260.0;   --  half-size of the shadow box (m)
   Samples       : constant := 4;

   Car_Color    : constant Vec3 := (0.62, 0.07, 0.06);
   Taxi_Black   : constant Vec3 := (0.04, 0.04, 0.05);   --  your car on a taxi shift
   Plane_Color  : constant Vec3 := (0.90, 0.90, 0.88);
   Fog_Base     : constant := 0.0013;
   Fog_Density  : Float := Fog_Base;

   --  Weather: P toggles rain; the streets dry slowly afterwards
   Rain_Target  : Float := 0.0;
   Rain_Amount  : Float := 0.0;
   Wetness      : Float := 0.0;
   Snow_Target  : Float := 0.0;   --  snowing (P cycles dry, rain, snow)
   Snow_Amount  : Float := 0.0;
   Snow_Cover   : Float := 0.0;   --  snow lying on the ground and roofs
   Storm_On     : Boolean := False;   --  thunder and lightning with the rain
   Storm_Auto   : Float := 0.0;       --  seconds left of a storm that came by itself
   Storm_Rolled : Integer := -1;      --  the day a summer storm was decided on
   Storm_At     : Float := -1.0;
   Dice         : Ada.Numerics.Float_Random.Generator;
   function Chance return Float is (Ada.Numerics.Float_Random.Random (Dice));

   --  Christmas decorations: in the season, or as ~/.deriverc says
   Xmas_Setting : Character := 'a';   --  a(uto), y(es), n(o)
   function Christmas return Boolean is
     (Xmas_Setting = 'y' or else (Xmas_Setting = 'a' and then Almanac.Christmas));

   Spooky_Setting : Character := 'a';
   function Spooky return Boolean is
     (Spooky_Setting = 'y' or else (Spooky_Setting = 'a' and then Almanac.Halloween));

   --  Time of day (hours) and the lighting derived from it
   Hour         : Float := 18.0;
   Clock_Rate   : Float := 1.0 / 60.0;      --  game hours per second
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
   Overlay : Gtk.Overlay.Gtk_Overlay;   --  the 3D view with everything on top
   Help    : Gtk.Label.Gtk_Label;   --  the keys, shown with F1
   Start_Recording : Boolean := False;   --  F9 pressed
   Take_Photo      : Boolean := False;   --  F12 pressed
   Place_List : Gtk.Label.Gtk_Label;   --  saved places, shown with O
   List_Open  : Boolean := False;
   List_Sel   : Positive := 1;
   Game_Menu  : Gtk.Label.Gtk_Label;   --  F2: the games
   Menu_Open  : Boolean := False;
   Menu_Sel   : Positive := 1;
   Race_Hud   : Gtk.Label.Gtk_Label;   --  lap, position, time
   Radio_Box  : Gtk.Label.Gtk_Label;   --  the radio's news
   Radio_Shown : Ada.Strings.Unbounded.Unbounded_String;
   Race_Banner : Gtk.Label.Gtk_Label;  --  3, 2, 1, GO!
   Race_Shown : Ada.Strings.Unbounded.Unbounded_String;
   Banner_Shown : Ada.Strings.Unbounded.Unbounded_String;
   Results_Shown : Ada.Strings.Unbounded.Unbounded_String;
   Results_Up : Boolean := False;     --  shown (once) after the finish
   Results_Open : Boolean := False;   --  and still on the screen
   Taxi_Goal    : Natural := 0;       --  the taxi goal the GPS has
   Trial_Goal   : Natural := Natural'Last;   --  the time trial goal the GPS has
   Round_Goal   : Natural := Natural'Last;   --  the morning round's, likewise
   Bus_Goal     : Natural := Natural'Last;   --  and the night bus's
   Riding_Velib : Boolean := False;          --  on a Vélib', the car parked
   Parked       : Car.State;                 --  where the car was left meanwhile

   --  The player's own car: as chosen in ~/.deriverc, or a DS in 1973
   function Usual_Model return Car.Model_Kind is
      M : constant String := Config.Get ("car", "modern");
   begin
      return (if Era.In_1973 then Car.DS
              elsif M = "2cv" then Car.Deux_Chevaux elsif M = "ds" then Car.DS elsif M = "r4" then Car.R4
              else Car.Modern);
   end Usual_Model;
   Panel_Shown  : Ada.Strings.Unbounded.Unbounded_String;   --  the taxi's ride panel
   Gate_X, Gate_Z : Float := 0.0;      --  where the GPS points
   Sign    : Gtk.Label.Gtk_Label;      --  street name, like a Paris plaque

   Show_Street  : Boolean := True;     --  N toggles
   Show_Compass : Boolean := True;     --  G toggles compass and position
   Compass_Widget : Gtk.Widget.Gtk_Widget;
   Panel          : Gtk.Widget.Gtk_Widget;   --  instruments (I)
   Show_Panel     : Boolean := True;
   Last_Hour    : Integer := -1;       --  church bells strike the hours
   Announce       : Ada.Strings.Unbounded.Unbounded_String;   --  shown on the
   Manual_Gearbox : Boolean := True;    --  with a wheel and H-shifter
   Need_Clutch    : Boolean := True;
   Steer_Gain     : Float := 1.0;       --  wheel sensitivity
   Steer_Centre   : Float := 0.0;       --  degrees, if the wheel is off centre
   Force_Time     : Float := 0.0;       --  for the force feedback
   Last_Steering  : Float := 0.0;
   Jolt           : Float := 0.0;       --  kerb or crash kick, decays
   Jolt_Time      : Float := 0.0;
   Jolt_Side      : Float := 0.0;       --  crash: > 0 hit on the right
   Jolt_Length    : Float := 0.25;
   Scrape         : Float := 0.0;       --  rubbing along a wall, decays
   Announce_Timer : Float := 0.0;                             --  plaque briefly
   Pending_Load   : Boolean := False;
   --  Load the tiles around the focus at the next frame.  GL objects can
   --  only be made in the render callback, where the context is current.

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

   --  On foot (Q): first person, the mouse looks all round
   Walking    : Boolean := False;
   Walk_X, Walk_Z : Float := 0.0;
   Walk_Yaw   : Float := 0.0;
   Walk_Pitch : Float := 0.0;
   Walk_Step  : Float := 0.0;      --  the bob of the steps
   Captured   : Boolean := False;  --  the mouse turns the head
   In_Museum  : Boolean := False;  --  inside the Louvre (through the Pyramid)
   In_Hall_B : Boolean := False;   --  in hall B
   In_Room   : Boolean := False;   --  in one of the rooms (Rooms)
   Caption    : Gtk.Label.Gtk_Label;   --  the label of the work you look at
   Confirm    : Gtk.Label.Gtk_Label;   --  "Go home?"
   Confirm_Open : Boolean := False;
   Search_Box  : Gtk.Label.Gtk_Label;   --  F3: find an address
   Search_Open : Boolean := False;
   Search_Text : Ada.Strings.Unbounded.Unbounded_String;
   Search_Sel  : Positive := 1;
   Search_Hits : Addresses.Result_Array;
   Search_N    : Natural := 0;
   Caption_Shown : Ada.Strings.Unbounded.Unbounded_String;
   On_Tower   : Boolean := False;  --  on top of the Eiffel Tower
   On_Arc     : Boolean := False;  --  on the roof of the Arc de Triomphe
   On_Boat    : Boolean := False;  --  on a bateau-mouche's upper deck
   Boat_Deck  : Float := 0.0;

   Player   : Car.State;
   Aircraft : Plane.State;
   Drone    : Boolean := False;
   Zoom     : Float := 1.0;      --  camera distance factor (wheel, +/-)
   Fixed_Camera : Boolean := False;  --  PARIS_CAM: a still camera for screenshots
   Snap_Frames  : Natural := 0;      --  a bought postcard: the camera before the work
   Snap_Eye, Snap_Look : Vec3 := (0.0, 0.0, 0.0);
   Snap_Name, Snap_Text : Ada.Strings.Unbounded.Unbounded_String;

   type Float_List is array (1 .. 16) of Float;

   --  Home (V): standing in the top-floor apartment at 76 rue Bonaparte.
   --  The converter writes its position to tiles/home.txt.
   type Home_Info is record
      Known          : Boolean := False;
      Origin         : Vec3 := (0.0, 0.0, 0.0);   --  facade, inner end
      Along, Inward  : Vec3 := (0.0, 0.0, 0.0);
      Length, Depth  : Float := 0.0;
      Floor_Y        : Float := 0.0;
      Windows        : Natural := 0;
      Kitchen_S      : Float := -1.0;    --  kitchen window, apartment coordinates
      Kitchen_D      : Float := 0.0;
      Window_S       : Float_List := (others => 0.0);   --  centres, apartment coordinates
   end record;
   Home      : Home_Info;
   Visiting  : Boolean := False;
   Eye_S, Eye_D : Float := 0.0;      --  position in the apartment (m)
   Eye_Yaw   : Float := 0.0;
   Eye_Pitch : Float := 0.0;
   Dragging  : Boolean := False;     --  mouse look: left button held
   Drag_X, Drag_Y : Float := 0.0;

   --  Keys held down; mapped to car or plane controls each tick
   type Key_State is record
      Up, Down, Left, Right, W, S, A, D, Space : Boolean := False;
      Page_Up, Page_Down : Boolean := False;
      B : Boolean := False;   --  horn
      Shift : Boolean := False;   --  run (on foot)
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
      Head_Pos, Head_Dir, Head_On, Extra_Color, Extra_Color2, Wet,
      Tower_Lights, Sparkle, Snow_Cover, Xmas_On, Autumn, Bare, Litter, Trash, Gallery,
      Mist, Mist_Y, Heat, Blossom, Petals, Flood, Seine, Seine_N : GLint;
   end record;
   WU : World_Uniforms;

   Sky_Era : GLint := -1;
   Sh_Erase, Sh_Erase_B, Sh_Erase_N : GLint := -1;
   W_Erase, W_Erase_B, W_Erase_N, W_Era : GLint := -1;
   Sky_Inv_VP, Sky_Cam, Sky_Sun, Sky_Zen, Sky_Hor, Sky_Night, Sky_Clouds,
   Sky_Sun_True, Sky_Moon, Sky_Moon_Age : GLint;
   Sun_True : Vec3 := (0.0, 1.0, 0.0);    --  the sun, also at night
   Moon_Dir : Vec3 := (0.0, 1.0, 0.0);
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
         if Ada.Environment_Variables.Value ("PARIS_RAIN") = "storm" then
            Storm_On := True;
         end if;
         if Ada.Environment_Variables.Value ("PARIS_RAIN") = "snow" then
            Snow_Target := 1.0;
            Snow_Amount := 1.0;
            Snow_Cover := 1.0;
         else
            Rain_Target := 1.0;
            Rain_Amount := 1.0;
            Wetness := 1.0;
         end if;
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
      Cam_Pos := (Player.X, Terrain.Height (Player.X, Player.Z), Player.Z)
        - (if Drone then Drone_Back else 8.5) * Car.Forward (Player)
        + (0.0, (if Drone then Drone_Up else 3.2), 0.0);
      Cam_Look := (Player.X, 1.2 + Terrain.Height (Player.X, Player.Z), Player.Z)
        + (if Drone then 6.0 else 3.0) * Car.Forward (Player);
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
               --  the height is above the ground there
               Cam_Pos := (Float (CX), Float (Fields (3)) + Terrain.Height (Float (CX), Float (CZ)),
                           Float (CZ));
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

   procedure Load_Home (File_Name : String) is
      F : Ada.Text_IO.File_Type;
   begin
      if not Ada.Directories.Exists (File_Name) then
         return;
      end if;
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, File_Name);
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            Line : constant String := Ada.Text_IO.Get_Line (F);
            V    : array (1 .. 9) of Float := (others => 0.0);
            K    : Natural := 0;
            First : Natural := 0;
         begin
            if Line'Length > 8 and then Line (Line'First .. Line'First + 7) = "kitchen " then
               declare
                  Rest  : constant String := Line (Line'First + 8 .. Line'Last);
                  Space : Natural := Rest'First;
               begin
                  while Space <= Rest'Last and then Rest (Space) = ' ' loop
                     Space := Space + 1;
                  end loop;
                  while Space <= Rest'Last and then Rest (Space) /= ' ' loop
                     Space := Space + 1;
                  end loop;
                  Home.Kitchen_S := Float'Value (Rest (Rest'First .. Space - 1));
                  Home.Kitchen_D := Float'Value (Rest (Space .. Rest'Last));
               end;
            elsif Line'Length > 7 and then Line (Line'First .. Line'First + 6) = "windows" then
               --  "windows s1 s2 ... origin s0": centres relative to the facade
               declare
                  Words : array (1 .. 20) of Float := (others => 0.0);
                  N     : Natural := 0;
                  Start : Natural := 0;
                  Text  : constant String := Line (Line'First + 7 .. Line'Last) & " ";
               begin
                  for I in Text'Range loop
                     if Text (I) = ' ' then
                        if Start > 0 and then N < Words'Last then
                           if Text (Start .. I - 1) /= "origin" then
                              N := N + 1;
                              Words (N) := Float'Value (Text (Start .. I - 1));
                           end if;
                        end if;
                        Start := 0;
                     elsif Start = 0 then
                        Start := I;
                     end if;
                  end loop;
                  --  the last number is the origin of the apartment frame
                  Home.Windows := Natural'Min (Float_List'Last, Natural'Max (0, N - 1));
                  for K in 1 .. Home.Windows loop
                     Home.Window_S (K) := Words (K) - Words (N);
                  end loop;
               end;
            elsif Line'Length > 0 and then Line (Line'First) /= '#' then
               for I in Line'First .. Line'Last + 1 loop
                  if I > Line'Last or else Line (I) = ' ' then
                     if First > 0 and then K < V'Last then
                        K := K + 1;
                        V (K) := Float'Value (Line (First .. I - 1));
                     end if;
                     First := 0;
                  elsif First = 0 then
                     First := I;
                  end if;
               end loop;
               if K = 9 then
                  Home := (Known  => True,
                           Origin => (V (1), 0.0, V (2)),
                           Along  => (V (3), 0.0, V (4)),
                           Inward => (V (5), 0.0, V (6)),
                           Length => V (7), Depth => V (8), Floor_Y => V (9),
                           Windows => Home.Windows, Window_S => Home.Window_S,
                           Kitchen_S => Home.Kitchen_S, Kitchen_D => Home.Kitchen_D);
               end if;
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (F);
   exception
      when others =>
         Ada.Text_IO.Put_Line ("Could not read " & File_Name);
         Home.Known := False;
   end Load_Home;

   --  skyline_*.txt from osm2tiles: "ix iz name" per landmark tile
   procedure Load_Skyline (Dir : String) is
      use Ada.Directories;
      Search : Search_Type;
      Item   : Directory_Entry_Type;
      Count  : Natural := 0;
   begin
      if not Exists (Dir) then
         return;
      end if;
      Start_Search (Search, Dir, "skyline_*.txt", (Ordinary_File => True, others => False));
      while More_Entries (Search) loop
         Get_Next_Entry (Search, Item);
         declare
            F : Ada.Text_IO.File_Type;
         begin
            Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Full_Name (Item));
            while not Ada.Text_IO.End_Of_File (F) loop
               declare
                  Line : constant String := Ada.Text_IO.Get_Line (F) & " ";
                  P1   : Natural := Line'First;
                  P2   : Natural;
               begin
                  while Line (P1) = ' ' loop
                     P1 := P1 + 1;
                  end loop;
                  P2 := Index_Of (Line, ' ', P1);
                  declare
                     IX : constant Integer := Integer'Value (Line (P1 .. P2 - 1));
                     P3 : Natural := P2;
                     P4 : Natural;
                  begin
                     while Line (P3) = ' ' loop
                        P3 := P3 + 1;
                     end loop;
                     P4 := Index_Of (Line, ' ', P3);
                     World.Pin_Tile (IX, Integer'Value (Line (P3 .. P4 - 1)));
                     Count := Count + 1;
                  end;
               exception
                  when Constraint_Error => null;   --  empty or malformed line
               end;
            end loop;
            Ada.Text_IO.Close (F);
         end;
      end loop;
      End_Search (Search);
      Ada.Text_IO.Put_Line ("Skyline landmarks:" & Count'Image);
   end Load_Skyline;

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
             Tower_Lights  => Location (World_Prog, "uTowerLights"),
             Sparkle       => Location (World_Prog, "uSparkle"),
             Snow_Cover    => Location (World_Prog, "uSnowCover"),
             Xmas_On       => Location (World_Prog, "uXmas"),
             Autumn        => Location (World_Prog, "uAutumn"),
             Bare          => Location (World_Prog, "uBare"),
             Litter        => Location (World_Prog, "uLitter"),
             Trash         => Location (World_Prog, "uTrash"),
             Gallery       => Location (World_Prog, "uGallery"),
             Lights        => Location (World_Prog, "uLights"),
             Light_Count   => Location (World_Prog, "uLightCount"),
             Head_Pos      => Location (World_Prog, "uHeadPos"),
             Head_Dir      => Location (World_Prog, "uHeadDir"),
             Head_On       => Location (World_Prog, "uHeadOn"),
             Extra_Color   => Location (World_Prog, "uExtraColor"),
             Extra_Color2  => Location (World_Prog, "uExtraColor2"),
             Wet           => Location (World_Prog, "uWet"),
             Mist          => Location (World_Prog, "uMist"),
             Mist_Y        => Location (World_Prog, "uMistY"),
             Heat          => Location (World_Prog, "uHeat"),
             Blossom       => Location (World_Prog, "uBlossom"),
             Petals        => Location (World_Prog, "uPetals"),
             Flood         => Location (World_Prog, "uFlood"),
             Seine         => Location (World_Prog, "uSeine"),
             Seine_N       => Location (World_Prog, "uSeineN"));
      Sky_Inv_VP := Location (Sky_Prog, "uInvViewProj");
      Sky_Cam := Location (Sky_Prog, "uCamPos");
      Sky_Era := Location (Sky_Prog, "uEra");
      W_Erase := Location (World_Prog, "uErase");
      W_Erase_B := Location (World_Prog, "uEraseB");
      W_Erase_N := Location (World_Prog, "uEraseN");
      W_Era := Location (World_Prog, "uEra");
      Sh_Erase := Location (Shadow_Prog, "uErase");
      Sh_Erase_B := Location (Shadow_Prog, "uEraseB");
      Sh_Erase_N := Location (Shadow_Prog, "uEraseN");
      Sky_Sun := Location (Sky_Prog, "uSunDir");
      Sky_Sun_True := Location (Sky_Prog, "uSunTrue");
      Sky_Moon := Location (Sky_Prog, "uMoonDir");
      Sky_Moon_Age := Location (Sky_Prog, "uMoonAge");
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
      Traffic.Create_Meshes;
      Pedestrians.Create_Mesh;
      Rain.Create;
      Tyre_Effects.Create;
      Landscape.Create;
      Museum.Create;
      Beacon.Create;
      Storm.Create;
      Sky_Life.Create;
      Xmas.Create;
      Sleigh.Create_Mesh;
      Halloween.Create_Mesh;
      Ufo.Create_Mesh;
      Surprises.Create;

      Profiling := Ada.Environment_Variables.Exists ("PARIS_PROFILE");
      declare
         Dir : constant String :=
           (if Ada.Environment_Variables.Exists ("PARIS_TILES")
            then Ada.Environment_Variables.Value ("PARIS_TILES") else "tiles");
      begin
         World.Init (Dir);
         Road_Network.Load (Dir);
         Load_Home (Dir & "/home.txt");
         Tower.Load (Dir & "/eiffel.txt");
         Arc_Top.Load (Dir & "/arc.txt");
         Scenes.Load;
         Postcards.Load;
         Trials.Load;
         Rounds.Load;
         Night_Bus.Load;
         Addresses.Load (Dir);
         Scenes.Set_Override (Xmas_Setting);
         Scenes.Create;
         Stravinsky.Create;
         Tower.Create;     --  their railings, now that we know where they are
         Arc_Top.Create;
         --  decals
         declare
            P : constant Vec3 := Museum.Pyramid;
            X, Z : Float;
         begin
            Decals.Set (Decals.Decal_A, P.X - 32.0, P.Z);
            if Tower.Known then
               Tower.Centre (X, Z);
               Decals.Set (Decals.Decal_B, X, Z);
            end if;
            if Arc_Top.Known then
               Arc_Top.Centre (X, Z);
               Decals.Set (Decals.Decal_C, X, Z);
            end if;
            Hall_B.Mark_Point (X, Z);
            Decals.Set (Decals.Decal_D, X, Z);
            declare
               Found : Boolean;
               Marks : constant array (Rooms.Room_A .. Rooms.Room_D) of Decals.Decal_Kind :=
                 (Decals.Decal_F, Decals.Decal_G, Decals.Decal_E, Decals.Decal_H);
            begin
               for K in Marks'Range loop
                  Rooms.Mark (K, X, Z, Found);
                  if Found then
                     Decals.Set (Marks (K), X, Z);
                  end if;
               end loop;
            end;
            if Home.Known then
               Decals.Set (Decals.Decal_E,
                          Home.Origin.X + Home.Length / 2.0 * Home.Along.X - 2.2 * Home.Inward.X,
                          Home.Origin.Z + Home.Length / 2.0 * Home.Along.Z - 2.2 * Home.Inward.Z);
            end if;
         end;
         if Home.Known and then Home.Windows > 0 then
            --  a cat walks the railings of the balconies
            declare
               Lo : Float := Home.Window_S (1);
               Hi : Float := Home.Window_S (1);
            begin
               for K in 1 .. Home.Windows loop
                  Lo := Float'Min (Lo, Home.Window_S (K));
                  Hi := Float'Max (Hi, Home.Window_S (K));
               end loop;
               Surprises.Set_Balcony (Home.Origin, Home.Along, (-1.0) * Home.Inward,
                                      Lo - 0.8, Hi + 0.8, Home.Floor_Y);
            end;
         end if;
         Load_Skyline (Dir);
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

   --  The morning after a fête (the 14th of July, the Fête de la Musique,
   --  the New Year): paper and cans everywhere, swept away by noon
   function Party_Morning return Boolean is
     ((Almanac.Month = 7 and then Almanac.Day = 15) or else (Almanac.Month = 6 and then Almanac.Day = 22)
      or else (Almanac.Month = 1 and then Almanac.Day = 1));
   function Trash_Now return Float is
     (if Party_Morning then Float'Max (0.0, Float'Min (1.0, (12.0 - Hour) / 6.0)) else 0.0);

   --  How many of the people about are sweeping the streets
   function Sweeper_Share return Float is
     (if Party_Morning and then Hour >= 5.5 and then Hour < 13.0 then 0.14
      elsif Hour >= 6.0 and then Hour < 11.0 then 0.025 else 0.0);

   function Eye_Position return Vec3 is
     (Home.Origin + Eye_S * Home.Along + Eye_D * Home.Inward
      + (0.0, Home.Floor_Y + 1.6, 0.0));

   function Walk_Eye return Vec3 is
     ((Walk_X, (if In_Museum then Museum.Floor_Y
                elsif In_Hall_B then Hall_B.Floor_Y
                elsif In_Room then Rooms.Floor_Y
                elsif On_Tower then Tower.Top_Floor_Y
                elsif On_Arc then Arc_Top.Roof_Y
                elsif On_Boat then Boat_Deck
                else Terrain.Height (Walk_X, Walk_Z))
               + 1.65 + 0.03 * abs Sin (Walk_Step), Walk_Z));

   --  Where the action is: the car, the plane in flight, or home
   function Focus return Vec3 is
     (if Visiting then (Eye_Position.X, 0.0, Eye_Position.Z)
      elsif Walking then (Walk_X, Terrain.Height (Walk_X, Walk_Z), Walk_Z)
      elsif Mode = Flying then Aircraft.Pos else (Player.X, Player.Ground, Player.Z));

   function Focus_Heading return Float is
     (if Walking then Walk_Yaw elsif Mode = Flying then Aircraft.Heading else Player.Heading);

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
      Sun  : constant Vec3 := Almanac.Sun (Hour);
      Moon : constant Vec3 := Almanac.Moon (Hour);
      --  how much of the moon is lit: full moon nights are brighter
      Lit  : constant Float := 0.5 - 0.5 * Cos (2.0 * Ada.Numerics.Pi * Almanac.Moon_Age);
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
      elsif Moon.Y > 0.05 then
         Sun_Dir := Moon;
         Sun_Color := Smoothstep (-0.03, -0.2, Sun.Y) * Smoothstep (0.05, 0.2, Moon.Y)
           * (0.3 + 0.7 * Lit) * Vec3'(0.07, 0.09, 0.16);
      else
         --  no moon: only the glow of the city
         Sun_Dir := Normalize ((0.2, 1.0, 0.1));
         Sun_Color := Smoothstep (-0.03, -0.2, Sun.Y) * Vec3'(0.015, 0.018, 0.03);
      end if;
      Sun_True := Sun;
      Moon_Dir := Moon;
      Amb_Sky := Mix ((0.010, 0.013, 0.026), Mix (Vec3'(0.26, 0.33, 0.46), 0.55 * To_Linear (Day_Hor), Low * 0.5), Day);
      Amb_Ground := Mix ((0.020, 0.015, 0.011), (0.11, 0.09, 0.06), Day);

      --  Overcast when it rains: weak sun, grey sky, softer and hazier
      if Rain_Amount > 0.0 or else Snow_Amount > 0.0 then
         declare
            R : constant Float := Float'Max (Rain_Amount, Snow_Amount);
            function Grey (C : Vec3; Tint : Vec3) return Vec3 is
              ((0.3 * C.X + 0.55 * C.Y + 0.15 * C.Z) * Tint);
         begin
            Sun_Color := (1.0 - 0.8 * R) * Sun_Color;
            Sky_Zenith := Mix (Sky_Zenith, 0.75 * Grey (Sky_Zenith, (0.95, 0.98, 1.05)), R);
            Sky_Horizon := Mix (Sky_Horizon, 0.85 * Grey (Sky_Horizon, (0.97, 0.99, 1.03)), R);
            Amb_Sky := Mix (Amb_Sky, 1.1 * Grey (Amb_Sky, (0.95, 1.0, 1.08)), R);
         end;
      end if;
      --  lightning lights up the sky and the whole city for a moment
      declare
         F : constant Float := Storm.Flash;
      begin
         if F > 0.0 then
            Sky_Zenith := Sky_Zenith + F * Vec3'(0.55, 0.57, 0.7);
            Sky_Horizon := Sky_Horizon + F * Vec3'(0.6, 0.6, 0.7);
            Amb_Sky := Amb_Sky + F * Vec3'(0.45, 0.47, 0.6);
         end if;
      end;
      Fog_Density := Fog_Base * (if Visiting or else On_Tower or else On_Arc then 0.4 else 1.0) * (1.0 + 2.5 * Rain_Amount + 3.5 * Snow_Amount);
   end Compute_Lighting;

   function Light_View_Proj return Mat4 is
      Center : constant Vec3 :=
        (Focus.X + 120.0 * Focus_Forward.X * (if Mode = Flying then 1.0 else 0.0),
         Terrain.Height (Focus.X, Focus.Z),
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

   --  PARIS_SHOT_PNG=<file.png>: the frame as it is on screen, with the
   --  info line, compass, minimap and signs drawn on top (for the README)
   procedure Save_Composite (Name : String; W, H : Integer) is
      use Cairo;
      type Byte_Array is array (Natural range <>) of Interfaces.Unsigned_8;
      Pixels  : Byte_Array (0 .. W * H * 4 - 1);
      Surface : constant Cairo_Surface := Cairo.Image_Surface.Create
        (Cairo.Image_Surface.Cairo_Format_RGB24, Glib.Gint (W), Glib.Gint (H));
      Stride  : constant Natural := Natural (Cairo.Image_Surface.Get_Stride (Surface));
      Out_Px  : Byte_Array (0 .. Stride * H - 1)
        with Import, Address => Cairo.Image_Surface.Get_Data_Generic (Surface);
      Cr      : Cairo_Context;
      Status  : Cairo_Status;
      use Gtk.Widget.Widget_List;
      Children : Glist := Overlay.Get_Children;
      Item     : Glist := Children;
   begin
      glReadPixels (0, 0, GLsizei (W), GLsizei (H), GL_RGBA, GL_UNSIGNED_BYTE, Pixels'Address);
      Cairo.Surface.Flush (Surface);
      for Y in 0 .. H - 1 loop
         for X in 0 .. W - 1 loop
            declare
               S : constant Natural := ((H - 1 - Y) * W + X) * 4;
               D : constant Natural := Y * Stride + X * 4;
            begin
               Out_Px (D) := Pixels (S + 2);
               Out_Px (D + 1) := Pixels (S + 1);
               Out_Px (D + 2) := Pixels (S);
               Out_Px (D + 3) := 255;
            end;
         end loop;
      end loop;
      Cairo.Surface.Mark_Dirty (Surface);
      Cr := Create (Surface);
      while Item /= Null_List loop
         declare
            Child : constant Gtk.Widget.Gtk_Widget := Get_Data (Item);
            X, Y  : Glib.Gint;
            Ok    : Boolean;
         begin
            if Gtk.Widget."/=" (Child, Gtk.Widget.Gtk_Widget (Area)) and then Child.Get_Mapped then
               Child.Translate_Coordinates (Area, 0, 0, X, Y, Ok);
               Save (Cr);
               Translate (Cr, Glib.Gdouble (X), Glib.Gdouble (Y));
               Child.Draw (Cr);
               Restore (Cr);
            end if;
         end;
         Item := Next (Item);
      end loop;
      Free (Children);
      Destroy (Cr);
      Status := Cairo.Png.Write_To_Png (Surface, Name);
      pragma Unreferenced (Status);
      Surface_Destroy (Surface);
   end Save_Composite;

   --  For testing: a label as a picture
   procedure Save_Label_Png (L : Gtk.Label.Gtk_Label; File_Name : String) is
      use Cairo;
      Surface : constant Cairo_Surface := Cairo.Image_Surface.Create
        (Cairo.Image_Surface.Cairo_Format_ARGB32,
         L.Get_Allocated_Width, L.Get_Allocated_Height);
      Cr      : constant Cairo_Context := Create (Surface);
      Status  : Cairo_Status;
   begin
      L.Draw (Cr);
      Status := Cairo.Png.Write_To_Png (Surface, File_Name);
      pragma Unreferenced (Status);
      Destroy (Cr);
      Surface_Destroy (Surface);
   end Save_Label_Png;

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

      if Pending_Load then
         World.Load_All_Near (Focus.X, Focus.Z);
         Pending_Load := False;
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
           Perspective (1.05, Float (W) / Float (H), 0.3, 9000.0);
         View : constant Mat4 := Look_At (Cam_Pos, Cam_Look, (0.0, 1.0, 0.0));
         VP   : constant Mat4 := Proj * View;
         LVP  : constant Mat4 := Light_View_Proj;
         Car_M : constant Mat4 := Car.Model_Matrix (Player)
           * (if Car."=" (Car.Player_Model, Car.Scooter) or else Car."=" (Car.Player_Model, Car.Velib)
              then Rotation_Z (-Car.Lean (Player)) else Identity);
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
         Era.Set_Shadow_Uniforms (Sh_Erase, Sh_Erase_B, Sh_Erase_N);
         World.Draw_Solid;
         Set (Sh_Erase_N, Integer'(0));
         Set (Sh_Model, Car_M);
         Car.Draw;
         if Riding_Velib then
            Set (Sh_Model, Car.Model_Matrix (Parked));
            Car.Draw_Model (Usual_Model);
         end if;
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
         Set (Sky_Era, (if Era.In_1973 then 1.0 else 0.0));
         Set (Sky_Sun, Sun_Dir);
         Set (Sky_Zen, Sky_Zenith);
         Set (Sky_Hor, Sky_Horizon);
         Set (Sky_Night, Night);
         Set (Sky_Clouds, Float'Max (Rain_Amount, Snow_Amount));
         Set (Sky_Sun_True, Sun_True);
         Set (Sky_Moon, Moon_Dir);
         Set (Sky_Moon_Age, Almanac.Moon_Age);
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
         Set (WU.Snow_Cover, Snow_Cover);
         Set (WU.Xmas_On, (if Christmas then 1.0 else 0.0));
         Set (WU.Autumn, Almanac.Autumn_Colour);
         Set (WU.Bare, Almanac.Bare);
         Set (WU.Litter, Almanac.Leaf_Litter * (1.0 - Snow_Cover));
         Set (WU.Trash, Trash_Now);
         Seasons.Set_Uniforms (WU.Mist, WU.Mist_Y, WU.Heat, WU.Blossom, WU.Petals, WU.Flood,
                               WU.Seine, WU.Seine_N);
         if In_Museum or else In_Hall_B or else In_Room then
            Set (WU.Mist, 0.0);   --  (indoors, and the metro deep under the river's level)
            Set (WU.Heat, 0.0);
         end if;
         Set (WU.Time, Time);
         Set (WU.Car_Color, Car_Color);
         Set (WU.Shadow_Map, 0);
         Set (WU.Shadows, 1);
         Set (WU.Amb_Sky, Amb_Sky);
         Set (WU.Amb_Ground, Amb_Ground);
         Set (WU.Night, Night);
         Set (WU.Tower_Lights, (if Beacon.Lights_On (Hour, Night) then Night else 0.0));
         Set (WU.Sparkle, Beacon.Sparkle (Hour, Night));
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
            --  a UFO nearby makes the street lamps flicker
            if Ufo.Nearness > 0.15 then
               for I in 0 .. N - 1 loop
                  if Sin (Time * 37.0 + Float (I) * 5.1) + Sin (Time * 23.0 + Float (I) * 2.3)
                    > 2.0 - 2.5 * Ufo.Nearness
                  then
                     Lights (4 * I + 3) := 0.1;
                  end if;
               end loop;
            end if;
            if N > 0 then
               glUniform4fv (WU.Lights, GLsizei (N), Lights'Address);
            end if;
            Set (WU.Head_Pos, Vec3'(Player.X, Player.Ground + 0.75, Player.Z) + 2.2 * Fwd);
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
         Era.Set_Uniforms (W_Erase, W_Erase_B, W_Erase_N, W_Era);
         World.Draw_Solid;
         Set (W_Erase_N, Integer'(0));   --  (only the city's tiles are left out)
         Era.Draw (WU.Model, WU.Car_Color, Cam_Pos);
         Street_Life.Draw (WU.Model, WU.Car_Color, Cam_Pos);   --  benches, bins, posters, tags, papers
         Scenes.Draw (WU.Model, WU.Car_Color, WU.Extra_Color, WU.Extra_Color2, Cam_Pos.X, Cam_Pos.Z);
         if not Era.In_1973 then
            Stravinsky.Draw (WU.Model, WU.Car_Color, Cam_Pos);   --  (from 1983)
         end if;
         Moulin.Draw (WU.Model, WU.Car_Color, Cam_Pos);
         Set (WU.Car_Color, Car_Color);
         if Walking and then not In_Museum and then not In_Hall_B and then not In_Room
           and then not On_Tower and then not On_Arc
         then
            Decals.Draw (WU.Model, WU.Extra_Color, Walk_X, Walk_Z);
         end if;
         glDisable (GL_SAMPLE_ALPHA_TO_COVERAGE);
         Set (WU.Model, Identity);   --  (what was drawn before may have moved it)
         Landscape.Draw;   --  the hills beyond the loaded tiles
         Set (WU.Model, Car_M);
         Set (WU.Car_Color, (if Taxi.Active then Taxi_Black
                             elsif Night_Bus.Active then Vec3'(0.08, 0.13, 0.32) else Car_Color));
         if Riding_Velib then
            Set (WU.Extra_Color, Vec3'(0.8, 0.62, 0.5));     --  your face
            Set (WU.Extra_Color2, Vec3'(0.15, 0.17, 0.25));  --  your jeans
            Set (WU.Car_Color, Vec3'(0.55, 0.38, 0.22));     --  your jacket
         end if;
         Car.Draw;
         if Riding_Velib then
            Set (WU.Model, Car.Model_Matrix (Parked));
            Set (WU.Car_Color, Car_Color);
            Car.Draw_Model (Usual_Model);
         end if;
         Traffic.Draw (WU.Model, WU.Car_Color);
         if not In_Museum and then not In_Hall_B and then not In_Room then
            Birds.Draw (WU.Model, WU.Car_Color, Cam_Pos);
            Extras.Draw (WU.Model, WU.Car_Color, WU.Extra_Color, WU.Extra_Color2, Cam_Pos);
            Boats.Draw (WU.Model, WU.Car_Color, WU.Extra_Color, WU.Extra_Color2, Cam_Pos, Night);
            Seasons.Draw (WU.Model, WU.Car_Color, Cam_Pos);
            Closures.Draw (WU.Model, WU.Car_Color, WU.Extra_Color, WU.Extra_Color2, WU.Extra_Color, Cam_Pos, Time);
            Set (WU.Car_Color, Car_Color);
         end if;
         Race.Draw (WU.Model, WU.Car_Color, WU.Extra_Color, WU.Extra_Color2, Cam_Pos);
         if Mode = Driving and then not Visiting then
            Taxi.Draw (WU.Model, WU.Car_Color, WU.Extra_Color, WU.Extra_Color2, Player, Time);
            Trials.Draw (WU.Model, WU.Extra_Color, Time);
            Rounds.Draw (WU.Model, WU.Car_Color, WU.Extra_Color, WU.Extra_Color2, Time);
            Night_Bus.Draw (WU.Model, WU.Car_Color, WU.Extra_Color, WU.Extra_Color2, Time);
         end if;
         Set (WU.Car_Color, Car_Color);
         if Christmas then
            Set (WU.Model, Identity);
            Xmas.Draw;
         end if;

         Sleigh.Draw (WU.Model, WU.Car_Color, WU.Extra_Color);
         Halloween.Draw (WU.Model);
         Ufo.Draw (WU.Model, WU.Car_Color);
         if On_Tower or else On_Arc then
            glEnable (GL_SAMPLE_ALPHA_TO_COVERAGE);   --  see through the railing
            if On_Tower then
               Tower.Draw (WU.Model);
            else
               Arc_Top.Draw (WU.Model);
            end if;
            glDisable (GL_SAMPLE_ALPHA_TO_COVERAGE);
         end if;
         if In_Hall_B then
            Hall_B.Draw (WU.Model, WU.Car_Color, WU.Extra_Color, WU.Extra_Color2, WU.Gallery);
         end if;
         if In_Room then
            Rooms.Draw (WU.Model, WU.Car_Color, WU.Extra_Color, WU.Extra_Color2, WU.Gallery);
            Set (WU.Car_Color, Car_Color);
         end if;
         if In_Museum then
            Museum.Draw (WU.Model, WU.Car_Color, WU.Extra_Color, WU.Extra_Color2, WU.Gallery);
            Set (WU.Car_Color, Car_Color);
         end if;
         Surprises.Draw (WU.Model, WU.Car_Color, WU.Extra_Color, WU.Extra_Color2);
         Set (WU.Model, Identity);
         Set (WU.Car_Color, Car_Color);
         Set (WU.Model, Identity);
         Pedestrians.Draw (WU.Model, WU.Car_Color, WU.Extra_Color, WU.Extra_Color2,
                           Cam_Pos.X, Cam_Pos.Z, 130.0);
         if Mode = Flying then
            Set (WU.Car_Color, Plane_Color);
            Plane.Draw (Aircraft, WU.Model);
         end if;
         Set (WU.Model, Identity);
         End_Pass (P_Solid);
         Begin_Pass (P_Ground);
         Set (WU.Flood, 0.0);   --  (the river's hole at street level stays put)
         World.Draw_Ground;
         Tyre_Effects.Draw_Marks (VP, Cam_Pos);
         Beacon.Draw (VP, Cam_Pos, Time, Hour, Night, Rain_Amount);
         Storm.Draw (VP, Cam_Pos);
         Ufo.Draw_Beam (VP, Cam_Pos);
         Surprises.Draw_Lights (VP, Cam_Pos);
         Boats.Draw_Lights (VP, Cam_Pos, Night);
         Sky_Life.Draw (VP, Float (H) / (2.0 * Tan (0.525)), Night);
         Rain.Draw (VP, Cam_Pos, Time, (if In_Museum or else In_Hall_B or else In_Room then 0.0 else Float'Max (Rain_Amount, Snow_Amount)),
                    Snow_Amount > Rain_Amount, Float (H) / (2.0 * Tan (0.525)),
                    Mix (Vec3'(0.30, 0.32, 0.36), Vec3'(0.75, 0.78, 0.82), 1.0 - Night));
         if (Mode = Driving or else Visiting or else Walking)
           and then not In_Museum and then not In_Hall_B and then not In_Room
           and then not On_Tower and then not On_Arc
         then
            Rain.Draw_Leaves (VP, Cam_Pos, Time, Almanac.Leaves_Falling * (1.0 - Snow_Amount),
                              Float (H) / (2.0 * Tan (0.525)), 0.15 + 0.85 * (1.0 - Night));
         end if;
         Tyre_Effects.Draw_Smoke (VP, Cam_Pos, Float (H) / (2.0 * Tan (0.525)), 1.0 - Night);
         End_Pass (P_Ground);
         Begin_Pass (P_Resolve);

         --  Resolve into GTK's framebuffer
         glBindFramebuffer (GL_READ_FRAMEBUFFER, MSAA_FBO);
         glBindFramebuffer (GL_DRAW_FRAMEBUFFER, GLuint (Target));
         glBlitFramebuffer (0, 0, GLint (W), GLint (H), 0, 0, GLint (W), GLint (H),
                            GL_COLOR_BUFFER_BIT, GL_NEAREST);
         glBindFramebuffer (GL_FRAMEBUFFER, GLuint (Target));
         if Start_Recording then
            Start_Recording := False;
            Recorder.Start (Natural (W), Natural (H));
            Announce := Ada.Strings.Unbounded.To_Unbounded_String (Recorder.Message);
            Announce_Timer := 3.0;
            Street_Timer := 1.0;
         end if;
         Recorder.Frame (Natural (W), Natural (H));
         if Postcards.Want_Picture then
            Postcards.Take_Picture (Natural (W), Natural (H));
         end if;
         if Take_Photo then
            Take_Photo := False;
            Photo.Take (Natural (W), Natural (H));
            Sound.Shutter;
            Announce := Ada.Strings.Unbounded.To_Unbounded_String (Photo.Message);
            Announce_Timer := 3.0;
            Street_Timer := 1.0;
         end if;
         End_Pass (P_Resolve);
      end;
      Fps_Frames := Fps_Frames + 1;
      Frame_Number := Frame_Number + 1;
      if Env ("PARIS_SHOT") /= ""
        and then Frame_Number = Integer'Value (Env ("PARIS_SHOT_FRAME", "90"))
      then
         Save_Screenshot (Env ("PARIS_SHOT"), W, H);
         if Env ("PARIS_SHOT_PNG") /= "" then
            Save_Composite (Env ("PARIS_SHOT_PNG"), W, H);
         end if;
         if Env ("PARIS_COMPASS_PNG") /= "" then
            Compass.Save_Png (Env ("PARIS_COMPASS_PNG"));
         end if;
         if Env ("PARIS_HELP_PNG") /= "" then
            Save_Label_Png (Help, Env ("PARIS_HELP_PNG"));
         end if;
         if Env ("PARIS_PANEL_PNG") /= "" then
            Instruments.Save_Png (Env ("PARIS_PANEL_PNG"));
         end if;
         if Env ("PARIS_LIST_PNG") /= "" then
            Save_Label_Png (Place_List, Env ("PARIS_LIST_PNG"));
         end if;
         if Env ("PARIS_MAP_PNG") /= "" then
            Navigation.Save_Png (Env ("PARIS_MAP_PNG"));
            Ada.Text_IO.Put_Line ("navigation: " & Navigation.Current_Text);
         end if;
         Ada.Text_IO.Put_Line
           ("frames:" & Natural'Image (Frame_Number) & "  avg fps:"
            & Integer'Image (Integer (Float (Frame_Number) / Time))
            & "  car at" & Integer'Image (Integer (Player.X))
            & Integer'Image (Integer (Player.Z))
            & "  speed" & Integer'Image (Integer (Player.Speed * 3.6))
            & "  traffic" & Natural'Image (Traffic.Count)
            & "  people" & Natural'Image (Pedestrians.Count)
            & (if Visiting then
                 "  visiting at s" & Integer'Image (Integer (Eye_S * 10.0))
                 & " d" & Integer'Image (Integer (Eye_D * 10.0)) & " (dm)"
               else "")
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
      --  a postcard being printed: for a few frames, right before the work
      if Snap_Frames > 0 then
         Cam_Pos := Snap_Eye;
         Cam_Look := Snap_Look;
         Snap_Frames := Snap_Frames - 1;
         Hall_B.Snapping := Snap_Frames > 0;
         if Snap_Frames = 1 then
            Postcards.Buy (Ada.Strings.Unbounded.To_String (Snap_Name),
                           Ada.Strings.Unbounded.To_String (Snap_Text));
         end if;
         return;
      end if;
      --  PARIS_ORBIT="angle distance height": look at the car from there
      --  (testing; angle in degrees from straight ahead, clockwise)
      if Env ("PARIS_ORBIT") /= "" and then Mode = Driving then
         declare
            S  : constant String := Env ("PARIS_ORBIT") & " ";
            P1 : constant Natural := Index_Of (S, ' ', S'First);
            P2 : constant Natural := Index_Of (S, ' ', P1 + 1);
            A  : constant Float := Player.Heading
              + Float'Value (S (S'First .. P1 - 1)) * Ada.Numerics.Pi / 180.0;
            D  : constant Float := Float'Value (S (P1 + 1 .. P2 - 1));
            H  : constant Float := Float'Value (S (P2 + 1 .. S'Last - 1));
         begin
            Cam_Pos := (Player.X + D * Sin (A), H + Player.Ground, Player.Z - D * Cos (A));
            Cam_Look := (Player.X, 0.8 + Player.Ground, Player.Z);
            return;
         end;
      end if;
      if Visiting then
         Cam_Pos := Eye_Position;
         Cam_Look := Cam_Pos + Vec3'(Sin (Eye_Yaw) * Cos (Eye_Pitch), Sin (Eye_Pitch),
                                     -Cos (Eye_Yaw) * Cos (Eye_Pitch));
         return;
      end if;
      if Walking then
         Cam_Pos := Walk_Eye;
         Cam_Look := Cam_Pos + Vec3'(Sin (Walk_Yaw) * Cos (Walk_Pitch), Sin (Walk_Pitch),
                                     -Cos (Walk_Yaw) * Cos (Walk_Pitch));
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
            Car_Pos : constant Vec3 := (Player.X, Player.Ground, Player.Z);
            Bus     : constant Boolean := Car."=" (Car.Player_Model, Car.Bus);
            Back    : constant Float := Zoom * (if Drone then Drone_Back elsif Bus then 17.0 else 8.5);
            Up      : constant Float := Zoom * (if Drone then Drone_Up elsif Bus then 6.0 else 3.2);
         begin
            Desired := Car_Pos - Back * Fwd + (0.0, Up, 0.0);
            Look := Car_Pos + (0.0, 1.2, 0.0) + (if Drone then 6.0 else 3.0) * Fwd;
         end;
      end if;
      Cam_Pos := Lerp (Cam_Pos, Desired, K);
      Cam_Look := Lerp (Cam_Look, Look, 1.0 - Exp (-Dt * 12.0));
      --  a wall between the car and the camera (a narrow street, turning
      --  by a building): the camera comes in to this side of it, and up a
      --  little when that is close, to look down on the car; it eases back
      --  out once the view is clear
      if Mode = Driving then
         declare
            Target : constant Vec3 := (Player.X, Player.Ground + 1.6, Player.Z);
            Span   : constant Float := Length (Cam_Pos - Target);
            Free   : constant Float := World.Ray_Free (Target, Cam_Pos);
         begin
            if Free < 1.0 and then Span > 0.5 then
               declare
                  D : constant Float := Float'Max (1.5, Free * Span - 0.7);
               begin
                  Cam_Pos := Target + (D / Span) * (Cam_Pos - Target);
                  Cam_Pos.Y := Cam_Pos.Y + Float'Max (0.0, 6.0 - D) * 0.5;
               end;
            end if;
         end;
      end if;
      --  never below the ground (hills, the plane low over Montmartre)
      declare
         G : constant Float := Terrain.Height (Cam_Pos.X, Cam_Pos.Z) + 1.0;
      begin
         if Cam_Pos.Y < G then
            Cam_Pos.Y := G;
         end if;
      end;
   end Update_Camera;

   --  Jump to a place: the car onto the nearest road, the plane above it
   procedure End_Race;
   --  Back to the city from a race (below, with the games menu)

   procedure Go_Home_Now;
   procedure Save_Home_Here;
   --  (below, after Teleport)

   procedure Teleport (P : Place) is
      X, Z : Long_Float;
      Found : Boolean;
      RX, RZ, H : Float;
   begin
      if Race.Active then
         End_Race;
      end if;
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
         Player.Ground := Terrain.Height (RX, RZ);
         Cam_Pos := (RX, 6.0 + Player.Ground, RZ) - 10.0 * Car.Forward (Player);
         Cam_Look := (RX, 1.2 + Player.Ground, RZ);
      end if;
      Pending_Load := True;
      Announce := P.Name;
      Announce_Timer := 3.0;
      Street_Timer := 1.0;   --  refresh the plaque now
   end Teleport;


   Welcomed : Boolean := False;

   --  V: go home to the apartment window, or back to the car
   procedure Go_Home;
   --  Up to the window (below)

   procedure Toggle_Visit is
   begin
      if Visiting then
         Visiting := False;
         World.Set_Radius (3);
         Pending_Load := True;
      --  a hidden place: only from close by, with the car (nearly) stopped
      elsif Home.Known and then Mode = Driving and then abs Player.Speed < 3.0
        and then (Player.X - (Home.Origin.X + Home.Length / 2.0 * Home.Along.X)) ** 2
                 + (Player.Z - (Home.Origin.Z + Home.Length / 2.0 * Home.Along.Z)) ** 2
                 < 150.0 ** 2
      then
         Go_Home;
      end if;
      if not Visiting then
         Announce_Timer := 0.0;
         Street_Timer := 1.0;
      end if;
   end Toggle_Visit;

   procedure Go_Home is
   begin
      if not Home.Known then
         return;
      end if;
      begin
         Visiting := True;
         --  the first time home, by day, the bells of Saint-Sulpice ring
         if not Welcomed and then Hour > 8.0 and then Hour < 21.0 and then not Sound.Pealing then
            Welcomed := True;
            Sound.Peal (120.0);
         end if;
         Eye_S := Home.Length / 2.0;
         --  the window nearest the middle of the facade
         for K in 1 .. Home.Windows loop
            if abs (Home.Window_S (K) - Home.Length / 2.0) < abs (Eye_S - Home.Length / 2.0)
              or else K = 1
            then
               Eye_S := Home.Window_S (K);
            end if;
         end loop;
         Eye_D := 0.9;
         --  look out of the window, slightly down onto the square
         Eye_Yaw := Arctan (-Home.Inward.X, Home.Inward.Z);
         Eye_Pitch := -0.12;
         --  from up here you see far: the Pantheon is 1.1 km away
         World.Set_Radius (6);
         Pending_Load := True;
         Announce := Ada.Strings.Unbounded.To_Unbounded_String ("76, rue Bonaparte");
         Announce_Timer := 1.0E9;
         Street_Timer := 1.0;
      end;
   end Go_Home;

   --  K: to the kitchen window, looking out into the courtyard
   procedure Go_To_Kitchen is
   begin
      if Visiting and then Home.Kitchen_S >= 0.0 then
         Eye_S := Home.Kitchen_S;
         Eye_D := Home.Kitchen_D - 0.45;
         Eye_Yaw := Arctan (Home.Inward.X, -Home.Inward.Z);
         Eye_Pitch := 0.0;
      end if;
   end Go_To_Kitchen;

   --  Looking around and walking in the apartment
   ---------------------------------------------------------------------------
   --  On foot
   ---------------------------------------------------------------------------

   --  The mouse: a hidden pointer that is put back in the middle of the
   --  window after every move, so the head turns as far as you like
   function Gdk_Cursor_New_For_Display (Display : System.Address; Kind : Interfaces.C.int)
     return System.Address
     with Import, Convention => C, External_Name => "gdk_cursor_new_for_display";
   function Gdk_Window_Get_Display (W : System.Address) return System.Address
     with Import, Convention => C, External_Name => "gdk_window_get_display";
   function Gdk_Window_Get_Screen (W : System.Address) return System.Address
     with Import, Convention => C, External_Name => "gdk_window_get_screen";
   procedure Gdk_Window_Set_Cursor (W, Cursor : System.Address)
     with Import, Convention => C, External_Name => "gdk_window_set_cursor";
   procedure Gdk_Window_Get_Origin (W : System.Address; X, Y : out Interfaces.C.int)
     with Import, Convention => C, External_Name => "gdk_window_get_origin";
   procedure Gdk_Device_Warp (D, Screen : System.Address; X, Y : Interfaces.C.int)
     with Import, Convention => C, External_Name => "gdk_device_warp";
   function To_Address is new Ada.Unchecked_Conversion (Gdk.Gdk_Window, System.Address);
   use type System.Address;

   procedure Capture_Mouse (On : Boolean) is
      W : constant System.Address := To_Address (Window.Get_Window);
      Blank : constant Interfaces.C.int := -2;   --  GDK_BLANK_CURSOR
   begin
      Captured := On;
      if W = System.Null_Address then
         return;
      end if;
      Gdk_Window_Set_Cursor
        (W, (if On then Gdk_Cursor_New_For_Display (Gdk_Window_Get_Display (W), Blank)
             else System.Null_Address));
   end Capture_Mouse;

   --  H, after "yes": straight to the home, exactly as you start the game
   --  R: the car back on the nearest street, stopped, facing the way it
   --  was going (stuck against a wall, on a pavement, in the river...)
   procedure Back_On_The_Road is
      Found : Boolean;
      RX, RZ, H : Float;
   begin
      Road_Network.Nearest_Road (Player.X, Player.Z, Found, RX, RZ, H);
      if not Found then
         return;
      end if;
      --  the road's direction that is nearer to the car's
      if Cos (H - Player.Heading) < 0.0 then
         H := H + Ada.Numerics.Pi;
      end if;
      Player := (X => RX, Z => RZ, Heading => H, others => <>);
      Player.Ground := Terrain.Height (RX, RZ);
      Announce := Ada.Strings.Unbounded.To_Unbounded_String ("Back on the road");
      Announce_Timer := 1.5;
      Street_Timer := 1.0;
   end Back_On_The_Road;

   procedure Go_Home_Now is
      X, Z : Long_Float;
   begin
      if Race.Active then
         End_Race;
      end if;
      if Walking then
         Walking := False;
         Capture_Mouse (False);
         Traffic.Set_Walker (False, 0.0, 0.0);
      end if;
      Geo.To_Local (Spawn_Lat, Spawn_Lon, X, Z);
      if Mode = Flying then
         Plane.Start (Aircraft, Float (X), Float (Z), Spawn_Heading);
      else
         Player := (X => Float (X), Z => Float (Z), Heading => Spawn_Heading, others => <>);
         Player.Ground := Terrain.Height (Player.X, Player.Z);
         Cam_Pos := (Player.X, 6.0 + Player.Ground, Player.Z) - 10.0 * Car.Forward (Player);
         Cam_Look := (Player.X, 1.2 + Player.Ground, Player.Z);
      end if;
      Pending_Load := True;
      Announce := Spawn_Name;
      Announce_Timer := 3.0;
      Street_Timer := 1.0;
   end Go_Home_Now;

   --  Shift+H: home is where the car is now (into ~/.deriverc)
   procedure Save_Home_Here is
      Lat, Lon : Long_Float;
      function Img (V : Long_Float) return String is
         S : constant String := Long_Long_Integer'Image (Long_Long_Integer (abs V * 1.0E6));
         W : constant String := S (S'First + 1 .. S'Last);
      begin
         return (if V < 0.0 then "-" else "") & W (W'First .. W'Last - 6) & "." & W (W'Last - 5 .. W'Last);
      end Img;
      Deg : constant Integer :=
        Integer (Player.Heading * 180.0 / Ada.Numerics.Pi) mod 360;
   begin
      if Mode /= Driving or else Visiting or else Walking then
         Announce := Ada.Strings.Unbounded.To_Unbounded_String ("Park the car where home should be");
      else
         Geo.To_Lat_Lon (Long_Float (Player.X), Long_Float (Player.Z), Lat, Lon);
         Spawn_Lat := Lat;
         Spawn_Lon := Lon;
         Spawn_Heading := Float (Deg) * Ada.Numerics.Pi / 180.0;
         Spawn_Name := Ada.Strings.Unbounded.To_Unbounded_String ("Home");
         Config.Set ("home", Img (Lat) & " " & Img (Lon) & Integer'Image (Deg));
         Announce := Ada.Strings.Unbounded.To_Unbounded_String ("Home is here now (H takes you back)");
      end if;
      Announce_Timer := 3.0;
      Street_Timer := 1.0;
   end Save_Home_Here;

   procedure Enter_Museum is
   begin
      In_Museum := True;
      Museum.Entrance (Walk_X, Walk_Z, Walk_Yaw);
      Walk_Pitch := 0.05;
      Traffic.Set_Walker (False, 0.0, 0.0);
      Announce := Ada.Strings.Unbounded.To_Unbounded_String ("Musée du Louvre");
      Announce_Timer := 3.0;
      Street_Timer := 1.0;
   end Enter_Museum;

   procedure Leave_Museum is
   begin
      In_Museum := False;
      Museum.Way_Out (Walk_X, Walk_Z, Walk_Yaw);
      Walk_Pitch := 0.1;
      Announce := Ada.Strings.Unbounded.To_Unbounded_String ("Cour Napoléon");
      Announce_Timer := 2.0;
      Street_Timer := 1.0;
   end Leave_Museum;

   procedure Enter_Hall_B is
   begin
      Hall_B.New_Exhibition;
      In_Hall_B := True;
      Hall_B.Entrance (Walk_X, Walk_Z, Walk_Yaw);
      Walk_Pitch := 0.0;
      Traffic.Set_Walker (False, 0.0, 0.0);
      Announce := Ada.Strings.Unbounded.To_Unbounded_String (Hall_B.Artist & ": " & Hall_B.Title);
      Announce_Timer := 5.0;
      Street_Timer := 1.0;
   end Enter_Hall_B;

   procedure Leave_Hall_B is
   begin
      In_Hall_B := False;
      Hall_B.Way_Out (Walk_X, Walk_Z, Walk_Yaw);
      Walk_Pitch := 0.15;
      Announce := Ada.Strings.Unbounded.To_Unbounded_String (Hall_B.Exit_Name);
      Announce_Timer := 2.0;
      Street_Timer := 1.0;
   end Leave_Hall_B;

   procedure Enter_Room (K : Rooms.Room_Kind) is
   begin
      Rooms.Enter (K, Walk_X, Walk_Z, Walk_Yaw);
      In_Room := True;
      Rooms.Entrance (Walk_X, Walk_Z, Walk_Yaw);
      Walk_Pitch := 0.0;
      Traffic.Set_Walker (False, 0.0, 0.0);
      Announce := Ada.Strings.Unbounded.To_Unbounded_String (Rooms.Arrival);
      Announce_Timer := 4.0;
      Street_Timer := 1.0;
   end Enter_Room;

   procedure Leave_Room is
   begin
      In_Room := False;
      Rooms.Way_Out (Walk_X, Walk_Z, Walk_Yaw);
      Walk_Pitch := 0.1;
      Announce := Ada.Strings.Unbounded.To_Unbounded_String (Rooms.Leaving);
      Announce_Timer := 3.0;
      Street_Timer := 1.0;
   end Leave_Room;

   procedure Go_Up is
   begin
      On_Tower := True;
      Tower.Arrival (Walk_X, Walk_Z, Walk_Yaw);
      Walk_Pitch := -0.15;
      Traffic.Set_Walker (False, 0.0, 0.0);
      World.Set_Radius (5);   --  you see far from up here
      Announce := Ada.Strings.Unbounded.To_Unbounded_String ("Tour Eiffel, 3e étage");
      Announce_Timer := 3.0;
      Street_Timer := 1.0;
   end Go_Up;

   procedure Go_Down is
   begin
      On_Tower := False;
      Tower.Ground (Walk_X, Walk_Z, Walk_Yaw);
      Walk_Pitch := 0.0;
      World.Set_Radius (3);
      Announce := Ada.Strings.Unbounded.To_Unbounded_String ("Champ-de-Mars");
      Announce_Timer := 2.0;
      Street_Timer := 1.0;
   end Go_Down;

   procedure Up_The_Arc is
   begin
      On_Arc := True;
      Arc_Top.Arrival (Walk_X, Walk_Z, Walk_Yaw);
      Walk_Pitch := -0.08;
      Traffic.Set_Walker (False, 0.0, 0.0);
      World.Set_Radius (4);   --  you see far from up here
      Announce := Ada.Strings.Unbounded.To_Unbounded_String ("Arc de Triomphe, la terrasse");
      Announce_Timer := 3.0;
      Street_Timer := 1.0;
   end Up_The_Arc;

   procedure Down_The_Arc is
   begin
      On_Arc := False;
      Arc_Top.Ground (Walk_X, Walk_Z, Walk_Yaw);
      Walk_Pitch := 0.15;   --  looking up at it
      World.Set_Radius (3);
      Announce := Ada.Strings.Unbounded.To_Unbounded_String ("Place Charles-de-Gaulle");
      Announce_Timer := 2.0;
      Street_Timer := 1.0;
   end Down_The_Arc;

   procedure Toggle_Walk is
      Side_X : constant Float := -Cos (Player.Heading);   --  the driver's side (left)
      Side_Z : constant Float := -Sin (Player.Heading);
      procedure Say (Text : String; Seconds : Float) is
      begin
         Announce := Ada.Strings.Unbounded.To_Unbounded_String (Text);
         Announce_Timer := Seconds;
         Street_Timer := 1.0;
      end Say;
   begin
      if not Walking and then Riding_Velib then
         --  off the Vélib': only at a station, where it locks into a dock
         declare
            Found : Boolean;
            BX, BZ, BH : Float;
         begin
            Street_Life.Nearest_Velib (Player.X, Player.Z, 14.0, Found, BX, BZ, BH);
            if not Found then
               Say ("Leave the Vélib' at a station (Q there)", 2.5);
               return;
            end if;
            if abs Player.Speed > 1.5 then
               Say ("Stop first", 1.5);
               return;
            end if;
            Walking := True;
            Walk_X := Player.X + 1.0 * Side_X;
            Walk_Z := Player.Z + 1.0 * Side_Z;
            Walk_Yaw := Player.Heading;
            Walk_Pitch := 0.0;
            Capture_Mouse (True);
            Riding_Velib := False;
            Player := Parked;
            Car.Set_Player_Model (Usual_Model);
            Say ("The Vélib' is back in its dock.  Q: back to the car", 3.0);
            return;
         end;
      end if;
      if not Walking then
         if Mode /= Driving or else Visiting then
            return;
         end if;
         if abs Player.Speed > 2.0 then
            Announce := Ada.Strings.Unbounded.To_Unbounded_String ("Stop the car first");
            Announce_Timer := 1.5;
            Street_Timer := 1.0;
            return;
         end if;
         Walking := True;
         Walk_X := Player.X + 1.6 * Side_X;
         Walk_Z := Player.Z + 1.6 * Side_Z;
         Walk_Yaw := Player.Heading;
         Walk_Pitch := 0.0;
         Capture_Mouse (True);
         Announce := Ada.Strings.Unbounded.To_Unbounded_String
           ("On foot: mouse to look, W/A/S/D to walk, Shift to run, Q to drive on");
         Announce_Timer := 4.0;
         Street_Timer := 1.0;
      elsif In_Museum then
         Leave_Museum;
      elsif In_Hall_B then
         Leave_Hall_B;
      elsif In_Room then
         Leave_Room;
      elsif On_Tower then
         Go_Down;
      elsif On_Arc then
         Down_The_Arc;
      elsif On_Boat then
         On_Boat := False;
         Boats.Ashore (Walk_X, Walk_Z);
         Walk_Pitch := 0.0;
         Announce := Ada.Strings.Unbounded.To_Unbounded_String ("Ashore");
         Announce_Timer := 2.0;
         Street_Timer := 1.0;
      else
         --  by a Vélib' station: take a bike (the car stays where it is)
         declare
            Found : Boolean;
            BX, BZ, BH : Float;
         begin
            Street_Life.Nearest_Velib (Walk_X, Walk_Z, 10.0, Found, BX, BZ, BH);
            if Found and then Mode = Driving then
               if Cos (BH - Walk_Yaw) < 0.0 then
                  BH := BH + Ada.Numerics.Pi;   --  the way you face
               end if;
               Parked := Player;
               Player := Car.On_Ground (BX, BZ, BH);
               Player.Ground := Terrain.Height (BX, BZ);
               Car.Set_Player_Model (Car.Velib);
               Riding_Velib := True;
               Walking := False;
               Capture_Mouse (False);
               Traffic.Set_Walker (False, 0.0, 0.0);
               Cam_Pos := (Player.X, 4.0 + Player.Ground, Player.Z) - 6.0 * Car.Forward (Player);
               Cam_Look := (Player.X, 1.2 + Player.Ground, Player.Z);
               Say ("On a Vélib'!  Ride to another station and Q there to leave it", 4.0);
               return;
            end if;
         end;
         declare
            DX : constant Float := Player.X - Walk_X;
            DZ : constant Float := Player.Z - Walk_Z;
            D  : constant Float := Sqrt (DX * DX + DZ * DZ);
         begin
            Walking := False;
            Capture_Mouse (False);
            Traffic.Set_Walker (False, 0.0, 0.0);
            if D >= 6.0 then
               --  far from the car: back to it at once
               Pending_Load := True;
               Cam_Pos := (Player.X, 6.0 + Player.Ground, Player.Z) - 10.0 * Car.Forward (Player);
               Cam_Look := (Player.X, 1.2 + Player.Ground, Player.Z);
               Announce := Ada.Strings.Unbounded.To_Unbounded_String
                 ("Back to the car (" & Ada.Strings.Fixed.Trim (Natural'Image (Natural (D)), Ada.Strings.Left)
                  & " m away)");
               Announce_Timer := 2.0;
               Street_Timer := 1.0;
            end if;
         end;
      end if;
   end Toggle_Walk;

   function On_A_Decal return Boolean is
      K : Decals.Decal_Kind;
   begin
      if not Decals.Standing_On (Walk_X, Walk_Z, K) then
         return False;
      end if;
      case K is
         when Decals.Decal_A => Enter_Museum;
         when Decals.Decal_B => Go_Up;
         when Decals.Decal_C => Up_The_Arc;
         when Decals.Decal_D =>
            if Era.In_1973 then
               return False;   --  no Pompidou yet
            end if;
            Enter_Hall_B;
         when Decals.Decal_F => Enter_Room (Rooms.Room_A);
         when Decals.Decal_G => Enter_Room (Rooms.Room_B);
         when Decals.Decal_H => Enter_Room (Rooms.Room_D);
         when Decals.Decal_E =>
            Walking := False;
            Capture_Mouse (False);
            Traffic.Set_Walker (False, 0.0, 0.0);
            Go_Home;
      end case;
      return True;
   end On_A_Decal;

   procedure Update_Walk (Dt : Float) is
      Speed : constant Float := (if Keys.Shift then 4.2 else 1.5);
      Fwd_X : constant Float := Sin (Walk_Yaw);
      Fwd_Z : constant Float := -Cos (Walk_Yaw);
      DX, DZ : Float := 0.0;
      Turn  : constant Float := 1.8 * Dt;
   begin
      --  on a boat: carried along (the mouse looks round)
      if On_Boat then
         declare
            Heading : Float;
         begin
            Boats.Ride_Eye (Walk_X, Walk_Z, Boat_Deck, Heading);
         end;
         return;
      end if;
      if not In_Museum and then not In_Hall_B and then not In_Room and then not On_Tower
        and then not On_Arc and then On_A_Decal
      then
         return;
      end if;
      --  the bateaux-mouches' landing: aboard
      if not In_Museum and then not In_Hall_B and then not In_Room and then not On_Tower
        and then not On_Arc and then Boats.At_Landing (Walk_X, Walk_Z)
      then
         declare
            Heading : Float;
         begin
            Boats.Board;
            if Boats.Riding then
               On_Boat := True;
               Boats.Ride_Eye (Walk_X, Walk_Z, Boat_Deck, Heading);
               Walk_Yaw := Heading;
               Walk_Pitch := 0.0;
               Traffic.Set_Walker (False, 0.0, 0.0);
               Announce := Ada.Strings.Unbounded.To_Unbounded_String
                 ("Aboard a bateau-mouche: down the Seine to the Eiffel Tower and back (Q: ashore)");
               Announce_Timer := 5.0;
               Street_Timer := 1.0;
            end if;
         end;
         return;
      end if;
      if In_Room then
         Rooms.Update (Dt, Walk_X, Walk_Z);
         Rooms.Keep_Inside (Walk_X, Walk_Z);   --  (the metro: into the car when it leaves)
         if Rooms.At_Exit (Walk_X, Walk_Z) then
            Leave_Room;
            return;
         end if;
      elsif not In_Museum and then not In_Hall_B and then not On_Tower and then not On_Arc
        and then Ufo.In_Beam (Walk_X, Walk_Z)
      then
         Enter_Room (Rooms.Room_C);
         return;
      elsif not In_Museum and then not In_Hall_B and then not On_Tower and then not On_Arc
        and then Street_Life.At_Entrance (Walk_X, Walk_Z)
      then
         Enter_Room (Rooms.Room_Metro);   --  down into the metro
         return;
      end if;
      --  the arrows turn too, for those without a mouse
      if Keys.Left then
         Walk_Yaw := Walk_Yaw - Turn;
      elsif Keys.Right then
         Walk_Yaw := Walk_Yaw + Turn;
      end if;
      if Keys.Page_Up then
         Walk_Pitch := Float'Min (1.4, Walk_Pitch + Turn);
      elsif Keys.Page_Down then
         Walk_Pitch := Float'Max (-1.4, Walk_Pitch - Turn);
      end if;
      if Keys.W or else Keys.Up then
         DX := DX + Fwd_X;
         DZ := DZ + Fwd_Z;
      elsif Keys.S or else Keys.Down then
         DX := DX - Fwd_X;
         DZ := DZ - Fwd_Z;
      end if;
      if Keys.A then
         DX := DX + Fwd_Z;
         DZ := DZ - Fwd_X;
      elsif Keys.D then
         DX := DX - Fwd_Z;
         DZ := DZ + Fwd_X;
      end if;
      if DX /= 0.0 or else DZ /= 0.0 then
         declare
            L : constant Float := Sqrt (DX * DX + DZ * DZ);
            Hit : Boolean;
            NX, NZ : Float;
         begin
            Walk_X := Walk_X + DX / L * Speed * Dt;
            Walk_Z := Walk_Z + DZ / L * Speed * Dt;
            if On_Tower then
               Tower.Keep_On_Deck (Walk_X, Walk_Z);
               Walk_Step := Walk_Step + Dt * Speed * 4.2;
               return;
            end if;
            if On_Arc then
               Arc_Top.Keep_On_Roof (Walk_X, Walk_Z);
               Walk_Step := Walk_Step + Dt * Speed * 4.2;
               return;
            end if;
            if In_Room then
               Rooms.Keep_Inside (Walk_X, Walk_Z);
               Walk_Step := Walk_Step + Dt * Speed * 4.2;
               return;
            end if;
            if In_Hall_B then
               Hall_B.Keep_Inside (Walk_X, Walk_Z);
               Walk_Step := Walk_Step + Dt * Speed * 4.2;
               if Hall_B.At_Exit (Walk_X, Walk_Z) then
                  Leave_Hall_B;
               end if;
               return;
            end if;
            if In_Museum then
               Museum.Keep_Inside (Walk_X, Walk_Z);
               Walk_Step := Walk_Step + Dt * Speed * 4.2;
               if Museum.At_Exit (Walk_X, Walk_Z) then
                  Leave_Museum;
               end if;
               return;
            end if;
            --  walls, and the parked car
            World.Collide (Walk_X, Walk_Z, 0.35, Hit, NX, NZ);
            if Museum.Touching_Pyramid (Walk_X, Walk_Z) then
               Enter_Museum;
               return;
            end if;
            if Hall_B.Touching_Entrance (Walk_X, Walk_Z) then
               Enter_Hall_B;
               return;
            end if;
            if Tower.Under (Walk_X, Walk_Z) then
               Go_Up;
               return;
            end if;
            if Arc_Top.Under (Walk_X, Walk_Z) then
               Up_The_Arc;
               return;
            end if;
            declare
               CX : constant Float := Walk_X - Player.X;
               CZ : constant Float := Walk_Z - Player.Z;
               CD : constant Float := Sqrt (CX * CX + CZ * CZ);
            begin
               if CD < 1.6 and then CD > 0.01 then
                  Walk_X := Player.X + CX / CD * 1.6;
                  Walk_Z := Player.Z + CZ / CD * 1.6;
               end if;
            end;
            Walk_Step := Walk_Step + Dt * Speed * 4.2;
         end;
      end if;
      Traffic.Set_Walker (True, Walk_X, Walk_Z);
   end Update_Walk;

   procedure Update_Visit (Dt : Float) is
      Turn  : constant Float := 1.6 * Dt;
      Walk  : constant Float := 1.4 * Dt;
      Fwd_X : constant Float := Sin (Eye_Yaw);
      Fwd_Z : constant Float := -Cos (Eye_Yaw);
      DX, DZ : Float := 0.0;
   begin
      --  arrows: walk and turn; A/D step sideways; PgUp/PgDn and the
      --  mouse (drag) look up and down
      if Keys.Left then
         Eye_Yaw := Eye_Yaw - Turn;
      elsif Keys.Right then
         Eye_Yaw := Eye_Yaw + Turn;
      end if;
      if Keys.Page_Up then
         Eye_Pitch := Float'Min (1.2, Eye_Pitch + Turn);
      elsif Keys.Page_Down then
         Eye_Pitch := Float'Max (-1.2, Eye_Pitch - Turn);
      end if;
      if Keys.W or else Keys.Up then
         DX := DX + Fwd_X * Walk;
         DZ := DZ + Fwd_Z * Walk;
      elsif Keys.S or else Keys.Down then
         DX := DX - Fwd_X * Walk;
         DZ := DZ - Fwd_Z * Walk;
      end if;
      if Keys.A then
         DX := DX + Fwd_Z * Walk;
         DZ := DZ - Fwd_X * Walk;
      elsif Keys.D then
         DX := DX - Fwd_Z * Walk;
         DZ := DZ + Fwd_X * Walk;
      end if;
      --  move in apartment coordinates and stay inside the walls
      declare
         function At_Window (S : Float) return Boolean is
         begin
            for K in 1 .. Home.Windows loop
               if abs (S - Home.Window_S (K)) < 0.45 then
                  return True;
               end if;
            end loop;
            return False;
         end At_Window;
         New_S : Float := Float'Max (0.3, Float'Min (Home.Length - 0.3,
                   Eye_S + DX * Home.Along.X + DZ * Home.Along.Z));
         New_D : constant Float := Eye_D + DX * Home.Inward.X + DZ * Home.Inward.Z;
      begin
         --  out on a balcony you stay in front of its window
         if Eye_D < 0.25 and then not At_Window (New_S) then
            New_S := Eye_S;
         end if;
         Eye_S := New_S;
         --  through a French window you can step out onto the balcony, and
         --  at the kitchen window you can lean out
         Eye_D := Float'Max ((if At_Window (New_S) then -0.75 else 0.25),
                             Float'Min ((if Home.Kitchen_S >= 0.0
                                           and then abs (New_S - Home.Kitchen_S) < 0.45
                                         then Home.Kitchen_D + 0.6
                                         else Home.Depth - 0.3),
                                        New_D));
      end;
   end Update_Visit;

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
         Player.Ground := Terrain.Height (Player.X, Player.Z);
         Cam_Pos := (Player.X, 30.0 + Player.Ground, Player.Z) - 20.0 * Car.Forward (Player);
      end if;
   end Toggle_Flight;

   function Clock_Image return String is
      Minutes : constant Natural := Natural (Float'Floor (Hour * 60.0)) mod (24 * 60);
      HH      : constant String := Natural'Image (Minutes / 60);
      MM      : constant String := Natural'Image (100 + Minutes mod 60);
   begin
      return HH (2 .. HH'Last) & ":" & MM (3 .. 4);
   end Clock_Image;

   procedure Set_Key (Key : Gdk.Types.Gdk_Key_Type; Down : Boolean);
   procedure Open_Search;
   procedure Refresh_Search;
   procedure Close_Search;
   --  (below, by Key_Press)

   --  F1: the keys for what you are doing now
   function Help_Text return String is
      LF : constant String := (1 => ASCII.LF);
      function Head (S : String) return String is
        ("<b><span foreground='#ffd27a'>" & S & "</span></b>" & LF);
   begin
      return "<span font_family='monospace'>"
        & (if Visiting then
             Head ("Walking")
             & "  arrows, W/S      walk and turn" & LF
             & "  A / D            step aside" & LF
             & "  PgUp/PgDn, drag  look up and down" & LF
             & "  K                kitchen window" & LF
             & "  V                back to the car" & LF & LF
           elsif Walking and then On_Tower then
             Head ("On top of the Eiffel Tower")
             & "  mouse            look all round" & LF
             & "  W / S, A / D     walk round the platform" & LF
             & "  Q                the lift down" & LF & LF
           elsif Walking and then On_Boat then
             Head ("Aboard a bateau-mouche")
             & "  mouse            look all round" & LF
             & "  Q                ashore, on the quay beside it" & LF & LF
           elsif Walking and then On_Arc then
             Head ("On the Arc de Triomphe")
             & "  mouse            look all round" & LF
             & "  W / S, A / D     walk round the roof" & LF
             & "  Q                the stairs down" & LF & LF
           elsif Walking and then In_Room then
             Head (Rooms.Heading)
             & "  mouse            look all round" & LF
             & "  W / S, A / D     walk, step aside" & LF
             & "  Q                out" & LF & LF
           elsif Walking and then In_Hall_B then
             Head (Hall_B.Heading)
             & "  mouse            look all round" & LF
             & "  W / S, A / D     walk, step aside" & LF
             & "  stand before a work to read its label" & LF
             & "  the SORTIE door  out (or Q)" & LF & LF
           elsif Walking and then In_Museum then
             Head ("In the Louvre")
             & "  mouse            look all round" & LF
             & "  W / S, A / D     walk, step aside" & LF
             & "  Shift            run (not really allowed)" & LF
             & "  the SORTIE door  out to the Cour Napoléon (or Q)" & LF & LF
           elsif Walking then
             Head ("On foot")
             & "  mouse            look all round" & LF
             & "  W / S, up/down   walk forwards / back" & LF
             & "  A / D            step aside" & LF
             & "  left / right     turn" & LF
             & "  Shift            run" & LF
             & "  Esc              free the mouse (click to look again)" & LF
             & "  Q                back into the car (from anywhere)" & LF & LF
           elsif Mode = Driving then
             Head ("Driving")
             & "  arrows / WASD    drive" & LF
             & "  space            handbrake" & LF
             & "  B                horn" & LF
             & "  C                chase or drone camera" & LF
             & "  mouse wheel, +/-  zoom" & LF
             & "  F                take off in the plane" & LF
             & "  Q                get out and walk" & LF
             & "  E                gearbox: manual or automatic" & LF
             & "  I                instruments (gear, revs, speed)" & LF
             & "  R                back on the road, here" & LF & LF
           else
             Head ("Flying")
             & "  W / S            throttle" & LF
             & "  up / down        nose down / up" & LF
             & "  left / right     bank" & LF
             & "  mouse wheel, +/-  zoom" & LF
             & "  F                land and drive" & LF
             & "  R                restart the plane" & LF & LF)
        & Head ("Paris")
        & "  1 .. 0           go to Saint-Sulpice, Notre-Dame, Louvre," & LF
        & "                   Tour Eiffel, Arc de Triomphe, Sacré-Cœur," & LF
        & "                   Panthéon, Concorde, Opéra, Bastille" & LF
        & "  H                home (asks first)" & LF
        & "  Shift+H          make this your home" & LF
        & "  Shift + 1 .. 0   navigate there (GPS)" & LF
        & "  X                stop navigating" & LF
        & "  L                save this place" & LF
        & "  O                saved places (GPS, go there)" & LF
        & "  G                compass, position and minimap" & LF
        & "  N                street names" & LF
        & "  J                clear the traffic around you" & LF & LF
        & Head ("Time and weather")
        & "  T                one hour later" & LF
        & "  U                Paris in 1973, or today" & LF
        & "  Z                the radio: the news on the hour" & LF
        & "  P                weather: rain, storm, snow, dry" & LF
        & "  M                sound on / off" & LF
        & "  F2               games: racing, taxi, time trials, the morning round" & LF
        & "  F3               find an address (GPS)" & LF
        & "  F4               your postcards" & LF
        & "  Y / Shift+Y      one day later / earlier" & LF
        & "  F9               record a video (again: stop)" & LF
        & "  F12              take a photo" & LF
        & (if Wheel.Present and then not Visiting then
             LF & Head ("Racing wheel")
             & "  X button         handbrake" & LF
             & "  red dial button  horn" & LF
             & "  red dial, + / -  zoom" & LF
             & "  square           camera" & LF
             & "  triangle         compass and minimap" & LF
             & "  circle           street names" & LF
             & "  R2 / L2          one hour later / weather" & LF
             & "  share / options  clear traffic / sound" & LF
             & "  PS               home" & LF
             & "  L3               stop navigating" & LF
             & "  d-pad right/left save place / saved places" & LF
           else "")
        & LF & "  F1 or Esc        close" & LF
        & "  Esc otherwise    quit the game"
        & "</span>";
   end Help_Text;

   ---------------------------------------------------------------------------
   --  Saved places: L saves where you are, O lists them for the GPS
   ---------------------------------------------------------------------------

   procedure Show_Markers is
      X, Z : Long_Float;
   begin
      Navigation.Clear_Markers;
      for I in 1 .. Saved_Places.Count loop
         Geo.To_Local (Saved_Places.Lat (I), Saved_Places.Lon (I), X, Z);
         Navigation.Add_Marker (Float (X), Float (Z));
      end loop;
   end Show_Markers;

   function Escape (S : String) return String is
      use Ada.Strings.Unbounded;
      R : Unbounded_String;
   begin
      for C of S loop
         case C is
            when '&' => Append (R, "&amp;");
            when '<' => Append (R, "&lt;");
            when '>' => Append (R, "&gt;");
            when others => Append (R, C);
         end case;
      end loop;
      return To_String (R);
   end Escape;

   procedure Refresh_List is
      use Ada.Strings.Unbounded;
      LF : constant String := (1 => ASCII.LF);
      T  : Unbounded_String :=
        To_Unbounded_String ("<span font_family='monospace'>"
                             & "<b><span foreground='#ffd27a'>Saved places</span></b>" & LF & LF);
      N  : constant Natural := Saved_Places.Count;
   begin
      if N = 0 then
         Append (T, "  Nothing saved yet." & LF
                 & "  Press L (or d-pad right on the wheel)" & LF
                 & "  to save the place where you are." & LF);
      else
         List_Sel := Positive'Min (List_Sel, N);
         for I in 1 .. N loop
            declare
               Num  : constant String := Natural'Image (I);
               Line : constant String :=
                 (if Num'Length < 3 then " " else "") & Num & "  " & Escape (Saved_Places.Name (I));
            begin
               if I = List_Sel then
                  Append (T, "<span background='#3a6fd8'>" & Line & "  </span>" & LF);
               else
                  Append (T, Line & LF);
               end if;
            end;
         end loop;
      end if;
      Append (T, LF & "<span foreground='#aab'>"
              & "  up/down  choose      Enter    navigate (GPS)" & LF
              & "  Space    go there    Delete   forget it" & LF
              & "  O / Esc  close" & LF
              & (if Wheel.Present then
                   "  wheel: d-pad choose, X navigate, square go, circle close" & LF
                 else "")
              & "  (names can be changed in ~/.derive_places)</span></span>");
      Place_List.Set_Markup (To_String (T));
   end Refresh_List;

   procedure Save_Here is
      Where : constant Vec3 :=
        (if Visiting then Eye_Position
         elsif Mode = Flying then Aircraft.Pos else (Player.X, Player.Ground, Player.Z));
      Lat, Lon : Long_Float;
      Street : constant String := Road_Network.Street_At (Where.X, Where.Z, 40.0);
      Count  : Natural := 0;
   begin
      Geo.To_Lat_Lon (Long_Float (Where.X), Long_Float (Where.Z), Lat, Lon);
      for I in 1 .. Saved_Places.Count loop
         if Street /= "" and then Saved_Places.Name (I)'Length >= Street'Length
           and then Saved_Places.Name (I) (Saved_Places.Name (I)'First
                                           .. Saved_Places.Name (I)'First + Street'Length - 1)
                    = Street
         then
            Count := Count + 1;
         end if;
      end loop;
      declare
         Name : constant String :=
           (if Street = "" then "Place" & Natural'Image (Saved_Places.Count + 1)
            elsif Count = 0 then Street
            else Street & " (" & Natural'Image (Count + 1) (2 .. Natural'Image (Count + 1)'Last) & ")");
      begin
         Saved_Places.Add (Name, Lat, Lon);
         Announce := Ada.Strings.Unbounded.To_Unbounded_String ("Saved: " & Name);
      end;
      Announce_Timer := 2.0;
      Street_Timer := 1.0;
      Show_Markers;
      if List_Open then
         Refresh_List;
      end if;
   end Save_Here;

   procedure Toggle_List is
   begin
      List_Open := not List_Open;
      if List_Open then
         Help.Hide;
         Refresh_List;
         Place_List.Show;
      else
         Place_List.Hide;
      end if;
   end Toggle_List;

   procedure Go_To_Saved (I : Positive; Jump : Boolean) is
      X, Z : Long_Float;
   begin
      if I > Saved_Places.Count then
         return;
      end if;
      if Jump then
         if not Visiting then
            Teleport ((Ada.Strings.Unbounded.To_Unbounded_String (Saved_Places.Name (I)),
                       Saved_Places.Lat (I), Saved_Places.Lon (I)));
         end if;
      else
         Geo.To_Local (Saved_Places.Lat (I), Saved_Places.Lon (I), X, Z);
         Navigation.Set_Destination (Saved_Places.Name (I), Float (X), Float (Z));
         if not Show_Compass then
            Set_Key (16#67#, True);   --  show the minimap
         end if;
      end if;
      Toggle_List;
   end Go_To_Saved;

   --  Keys while the list is open; True when the key was used
   function List_Key (K : Gdk.Types.Gdk_Key_Type) return Boolean is
      N : constant Natural := Saved_Places.Count;
   begin
      case K is
         when 16#FF52# | 16#77# =>                            --  up, w
            if List_Sel > 1 then
               List_Sel := List_Sel - 1;
            end if;
         when 16#FF54# | 16#73# =>                            --  down, s
            if List_Sel < N then
               List_Sel := List_Sel + 1;
            end if;
         when 16#FF0D# | 16#FF8D# =>                          --  Enter
            Go_To_Saved (List_Sel, Jump => False);
            return True;
         when 16#20# =>                                       --  space
            Go_To_Saved (List_Sel, Jump => True);
            return True;
         when 16#31# .. 16#39# =>                             --  1 .. 9
            Go_To_Saved (Positive (K - 16#30#), Jump => False);
            return True;
         when 16#FFFF# | 16#FF08# =>                          --  Delete, Backspace
            if N > 0 then
               Saved_Places.Remove (List_Sel);
               Show_Markers;
            end if;
         when 16#6F# | 16#FF1B# =>                            --  o, Escape
            Toggle_List;
            return True;
         when 16#6C# =>                                       --  l
            Save_Here;
         when others =>
            return False;
      end case;
      Refresh_List;
      return True;
   end List_Key;

   ---------------------------------------------------------------------------
   --  F2: the games.  For now street races: ready-made tracks, a random
   --  one around you, and a track editor
   ---------------------------------------------------------------------------


   --  The games menu: the games at the top, each with its own menu below
   type Menu_Level is (Games, Racing, Tracks, Taxi_Menu, Trials_Menu, Rounds_Menu, Bus_Menu);
   Level : Menu_Level := Games;
   type Menu_Item is
     (Go_Racing, Go_Taxi, Go_Trials, Go_Rounds, Go_Bus, Go_Free, Race_Again, Leave_Race, Street_Race, Random_Race,
      Make_Track, Save_Track, Drop_Track, Start_Shift, Stop_Shift, Up);
   type Item_Array is array (1 .. 8) of Menu_Item;

   procedure List_Items (L : out Item_Array; N : out Natural) is
      procedure Add (I : Menu_Item) is
      begin
         N := N + 1;
         L (N) := I;
      end Add;
   begin
      N := 0;
      L := (others => Up);
      case Level is
         when Games =>
            Add (Go_Racing);
            Add (Go_Taxi);
            Add (Go_Trials);
            Add (Go_Rounds);
            Add (Go_Bus);
            Add (Go_Free);
         when Taxi_Menu =>
            if Taxi.Active then
               Add (Stop_Shift);
            else
               Add (Start_Shift);
            end if;
            Add (Up);
         when Racing =>
            if Race.Active then
               Add (Race_Again);
               Add (Leave_Race);
            end if;
            Add (Street_Race);
            Add (Random_Race);
            if Race.Editing then
               Add (Save_Track);
               Add (Drop_Track);
            else
               Add (Make_Track);
            end if;
            Add (Up);
         when Tracks | Trials_Menu | Rounds_Menu | Bus_Menu =>
            null;   --  the tracks, runs or bakeries themselves (see Menu_Items)
      end case;
   end List_Items;

   function Menu_Items return Natural is
      L : Item_Array;
      N : Natural;
   begin
      if Level = Tracks then
         return Race.Track_Count + 1;
      elsif Level = Trials_Menu then
         return Trials.Count + 1;
      elsif Level = Rounds_Menu then
         return Rounds.Count + 1;
      elsif Level = Bus_Menu then
         return Night_Bus.Count + 1;
      end if;
      List_Items (L, N);
      return N;
   end Menu_Items;

   function Item_At (I : Positive) return Menu_Item is
      L : Item_Array;
      N : Natural;
   begin
      List_Items (L, N);
      return L (Positive'Min (I, Positive'Max (1, N)));
   end Item_At;

   procedure Refresh_Menu is
      use Ada.Strings.Unbounded;
      use type Race.Phase_Kind;
      LF : constant String := (1 => ASCII.LF);
      T  : Unbounded_String :=
        To_Unbounded_String ("<span font_family='monospace'><b><span foreground='#ffd27a'>"
                             & (case Level is
                                  when Games  => "Games",
                                  when Racing => "Street racing",
                                  when Tracks => "Street racing: choose a track",
                                  when Taxi_Menu => "Taxi",
                                  when Trials_Menu => "Time trials: through Paris against the clock",
                                  when Rounds_Menu => "The morning round: bread before the cafés open",
                                  when Bus_Menu => "The night bus: a line after midnight")
                             & "</span></b>" & LF & LF
                             & (if Level = Tracks then
                                  "  Laps:  &lt; " & (if Race.Laps_Setting = 0 then "as the track suits"
                                                      else Ada.Strings.Fixed.Trim
                                                        (Natural'Image (Race.Laps_Setting), Ada.Strings.Left))
                                  & " &gt;   (left/right)" & LF & LF
                                else ""));
      procedure Line (I : Positive; Text : String) is
         Num : constant String := Natural'Image (I);
         L   : constant String := (if Num'Length < 3 then " " else "") & Num & "  " & Text;
      begin
         if I = Menu_Sel then
            Append (T, "<span background='#3a6fd8'>" & L & "  </span>" & LF);
         else
            Append (T, L & LF);
         end if;
      end Line;
   begin
      Menu_Sel := Positive'Min (Menu_Sel, Menu_Items);
      if Level = Tracks then
         for I in 1 .. Race.Track_Count loop
            Line (I, Escape (Race.Track_Name (I)));
         end loop;
         Line (Race.Track_Count + 1, "back");
      elsif Level = Trials_Menu then
         for I in 1 .. Trials.Count loop
            Line (I, Escape (Trials.Name (I))
                  & (if Trials.Best (I) > 0.0
                     then "  <span foreground='#9fd4a8'>(best" & Natural'Image (Natural (Trials.Best (I) / 60.0))
                          & ":" & Ada.Strings.Fixed.Tail (Ada.Strings.Fixed.Trim
                            (Natural'Image (Natural (Float'Floor (Trials.Best (I))) mod 60), Ada.Strings.Left), 2, '0')
                          & ")</span>"
                     else ""));
         end loop;
         Line (Trials.Count + 1, "back");
      elsif Level = Rounds_Menu then
         for I in 1 .. Rounds.Count loop
            Line (I, Escape (Rounds.Name (I))
                  & (if Rounds.Best (I) > 0.0
                     then "  <span foreground='#9fd4a8'>(best" & Natural'Image (Natural (Float'Floor (Rounds.Best (I))))
                          & " € in tips)</span>"
                     else ""));
         end loop;
         Line (Rounds.Count + 1, "back");
      elsif Level = Bus_Menu then
         for I in 1 .. Night_Bus.Count loop
            Line (I, Escape (Night_Bus.Name (I))
                  & (if Night_Bus.Best (I) > 0
                     then "  <span foreground='#9fd4a8'>(best " & (1 .. Night_Bus.Best (I) => '*') & ")</span>"
                     else ""));
         end loop;
         Line (Night_Bus.Count + 1, "back");
      else
         for I in 1 .. Menu_Items loop
            Line (I, (case Item_At (I) is
                        when Go_Racing    => "Street racing  &gt;",
                        when Go_Taxi      => "Taxi  &gt;",
                        when Go_Trials    => "Time trials  &gt;",
                        when Go_Rounds    => "The morning round  &gt;",
                        when Go_Bus       => "The night bus  &gt;",
                        when Start_Shift  => "Start a shift",
                        when Stop_Shift   => "End the shift",
                        when Go_Free      =>
                          (if Race.Active then "Back to the city (leave the race)"
                           elsif Trials.Active then "Back to the city (leave the run)"
                           elsif Rounds.Active then "Back to the city (leave the round)"
                           elsif Night_Bus.Active then "Back to the city (leave the bus)"
                           elsif Taxi.Active then "Back to the city (end the shift)"
                           elsif Race.Editing then "Back to the city (drop the track)"
                           else "Free driving"),
                        when Race_Again   => "Race again",
                        when Leave_Race   =>
                          (if Race.Phase = Race.Finished then "Back to the city"
                           else "Give up the race"),
                        when Street_Race  => "Race on a track  &gt;",
                        when Random_Race  => "Random race around here",
                        when Make_Track   => "Make a track",
                        when Save_Track   =>
                          "Save the track (" & Ada.Strings.Fixed.Trim
                            (Natural'Image (Race.Edit_Points), Ada.Strings.Left) & " checkpoints)",
                        when Drop_Track   => "Throw the track away",
                        when Up           => "back"));
         end loop;
      end if;
      Append (T, LF & "<span foreground='#aab'>"
              & "  up/down  choose    Enter  select" & LF
              & "  Backspace  back    F2 / Esc  close"
              & (if Wheel.Present then LF & "  wheel: d-pad choose, X select, circle close" else "")
              & "</span></span>");
      Game_Menu.Set_Markup (To_String (T));
   end Refresh_Menu;

   procedure Toggle_Menu is
   begin
      Menu_Open := not Menu_Open;
      Results_Open := False;   --  the menu takes the results' place
      if Menu_Open then
         Help.Hide;
         if List_Open then
            Toggle_List;
         end if;
         --  in a race (or making a track) straight to its own menu
         Level := (if Race.Active or else Race.Editing then Racing
                   elsif Taxi.Active then Taxi_Menu
                   elsif Trials.Active then Trials_Menu
                   elsif Rounds.Active then Rounds_Menu
                   elsif Night_Bus.Active then Bus_Menu else Games);
         Menu_Sel := 1;
         Refresh_Menu;
         Game_Menu.Show;
      else
         Game_Menu.Hide;
      end if;
   end Toggle_Menu;

   --  Up a level (or close at the top)
   procedure Menu_Back is
   begin
      case Level is
         when Games  => Toggle_Menu;
         when Racing => Level := Games;
         when Tracks => Level := Racing;
         when Taxi_Menu => Level := Games;
         when Trials_Menu => Level := Games;
         when Rounds_Menu => Level := Games;
         when Bus_Menu => Level := Games;
      end case;
      Menu_Sel := 1;
      if Menu_Open then
         Refresh_Menu;
      end if;
   end Menu_Back;

   procedure Say (Text : String; Seconds : Float := 3.0) is
   begin
      Announce := Ada.Strings.Unbounded.To_Unbounded_String (Text);
      Announce_Timer := Seconds;
      Street_Timer := 1.0;
   end Say;

   --  Back to the city: the race (or the editor) away, the traffic back
   procedure End_Race is
   begin
      if Night_Bus.Active then
         Night_Bus.Stop;
         Navigation.Clear;
         Bus_Goal := Natural'Last;
         Car.Set_Player_Model (Usual_Model);
      end if;
      if Rounds.Active then
         Rounds.Stop;
         Navigation.Clear;
         Round_Goal := Natural'Last;
         Car.Set_Player_Model (Usual_Model);
      end if;
      if Trials.Active then
         Trials.Stop;
         Navigation.Clear;
         Trial_Goal := Natural'Last;
      end if;
      if Race.Active then
         Race.Stop;
         Traffic.Set_Density (Config.Get ("traffic", 1.0));
         Navigation.Clear;
      end if;
      Results_Up := False;
      Results_Open := False;
      Race_Shown := Ada.Strings.Unbounded.Null_Unbounded_String;
      Banner_Shown := Ada.Strings.Unbounded.Null_Unbounded_String;
      Results_Shown := Ada.Strings.Unbounded.Null_Unbounded_String;
      Race_Hud.Hide;
      Race_Banner.Hide;
      if Game_Menu.Get_Visible and then not Menu_Open then
         Game_Menu.Hide;
      end if;
   end End_Race;

   --  Back to free driving from the taxi
   procedure End_Taxi is
   begin
      if Taxi.Active then
         Taxi.Close;
         Navigation.Clear;
         Race_Shown := Ada.Strings.Unbounded.Null_Unbounded_String;
         Race_Hud.Hide;
         Race_Banner.Hide;
         Limit_Sign.Set (0, False, 0.0);
         if Game_Menu.Get_Visible and then not Menu_Open then
            Game_Menu.Hide;
         end if;
      end if;
   end End_Taxi;

   procedure Begin_Taxi is
   begin
      if Visiting or else Walking or else Riding_Velib or else Mode /= Driving then
         Say ("Get back in the car first");
         return;
      end if;
      End_Race;
      Race.Edit_Cancel;
      Trials.Stop;
      Taxi.Start_Shift (Player);
      Taxi_Goal := 0;
      Panel_Shown := Ada.Strings.Unbounded.Null_Unbounded_String;
      if not Show_Compass then
         Set_Key (16#67#, True);   --  the minimap, for the way to the fares
      end if;
      Race_Hud.Show;
   end Begin_Taxi;

   procedure Begin_Race (Track : Natural) is
      Ok : Boolean;
   begin
      if Visiting or else Walking or else Riding_Velib or else Mode /= Driving then
         Say ("Get back in the car first");
         return;
      end if;
      End_Race;
      Race.Edit_Cancel;
      End_Taxi;
      if Track = 0 then
         Race.Start_Random (Player.X, Player.Z, Player, Ok);
      else
         Race.Start (Track, Player, Ok);
      end if;
      if not Ok then
         Say ((if Track = 0 then "No good track around here, try somewhere else"
               else "This track cannot be driven"));
         return;
      end if;
      --  no traffic, only the racers
      Traffic.Set_Density (0.0);
      Traffic.Reset;
      Player.Ground := Terrain.Height (Player.X, Player.Z);
      Cam_Pos := (Player.X, 6.0 + Player.Ground, Player.Z) - 10.0 * Car.Forward (Player);
      Cam_Look := (Player.X, 1.2 + Player.Ground, Player.Z);
      Pending_Load := True;
      Gate_X := 0.0;
      Gate_Z := 0.0;
      if not Show_Compass then
         Set_Key (16#67#, True);   --  the minimap, for the way to the gates
      end if;
      Race_Hud.Show;
   end Begin_Race;

   procedure Begin_Again is
      Ok : Boolean;
   begin
      if Visiting or else Walking or else Riding_Velib or else Mode /= Driving then
         Say ("Get back in the car first");
         return;
      end if;
      Race.Restart (Player, Ok);
      if not Ok then
         return;
      end if;
      Results_Up := False;
      Results_Open := False;
      Results_Shown := Ada.Strings.Unbounded.Null_Unbounded_String;
      Banner_Shown := Ada.Strings.Unbounded.Null_Unbounded_String;
      Player.Ground := Terrain.Height (Player.X, Player.Z);
      Cam_Pos := (Player.X, 6.0 + Player.Ground, Player.Z) - 10.0 * Car.Forward (Player);
      Cam_Look := (Player.X, 1.2 + Player.Ground, Player.Z);
      Pending_Load := True;
      Gate_X := 0.0;
      Gate_Z := 0.0;
      Race_Hud.Show;
   end Begin_Again;

   procedure Begin_Trial (I : Natural) is
   begin
      if Visiting or else Walking or else Riding_Velib or else Mode /= Driving then
         Say ("Get back in the car first");
         return;
      end if;
      End_Race;
      Race.Edit_Cancel;
      End_Taxi;
      if I = 0 then
         Trials.Again (Player, Hour);
      else
         Trials.Start (I, Player, Hour);
      end if;
      Cam_Pos := (Player.X, 6.0 + Player.Ground, Player.Z) - 10.0 * Car.Forward (Player);
      Cam_Look := (Player.X, 1.2 + Player.Ground, Player.Z);
      Pending_Load := True;
      Trial_Goal := Natural'Last;
      Panel_Shown := Ada.Strings.Unbounded.Null_Unbounded_String;
      if not Show_Compass then
         Set_Key (16#67#, True);   --  the minimap, for the way
      end if;
      Race_Hud.Show;
   end Begin_Trial;

   --  The morning round: on the baker's scooter at the bakery's door
   procedure Begin_Round (I : Natural) is
   begin
      if Visiting or else Walking or else Riding_Velib or else Mode /= Driving then
         Say ("Get back in the car first");
         return;
      end if;
      if I /= 0 then
         End_Race;
      end if;
      Race.Edit_Cancel;
      End_Taxi;
      Trials.Stop;
      if I = 0 then
         Rounds.Again (Player, Hour);
      else
         Rounds.Start (I, Player, Hour);
      end if;
      Car.Set_Player_Model (Car.Scooter);
      Cam_Pos := (Player.X, 6.0 + Player.Ground, Player.Z) - 10.0 * Car.Forward (Player);
      Cam_Look := (Player.X, 1.2 + Player.Ground, Player.Z);
      Pending_Load := True;
      Round_Goal := Natural'Last;
      Panel_Shown := Ada.Strings.Unbounded.Null_Unbounded_String;
      if not Show_Compass then
         Set_Key (16#67#, True);   --  the minimap, for the way
      end if;
      Race_Hud.Show;
   end Begin_Round;

   --  The night bus: at the wheel of a twelve-metre bus, after midnight
   procedure Begin_Bus (I : Natural) is
   begin
      if Visiting or else Walking or else Riding_Velib or else Mode /= Driving then
         Say ("Get back in the car first");
         return;
      end if;
      if I /= 0 then
         End_Race;
      end if;
      Race.Edit_Cancel;
      End_Taxi;
      Trials.Stop;
      if I = 0 then
         Night_Bus.Again (Player, Hour);
      else
         Night_Bus.Start (I, Player, Hour);
      end if;
      Car.Set_Player_Model (Car.Bus);
      Cam_Pos := (Player.X, 8.0 + Player.Ground, Player.Z) - 18.0 * Car.Forward (Player);
      Cam_Look := (Player.X, 1.2 + Player.Ground, Player.Z);
      Pending_Load := True;
      Bus_Goal := Natural'Last;
      Panel_Shown := Ada.Strings.Unbounded.Null_Unbounded_String;
      if not Show_Compass then
         Set_Key (16#67#, True);
      end if;
      Race_Hud.Show;
   end Begin_Bus;

   procedure Menu_Choose is
   begin
      if Level = Bus_Menu then
         if Menu_Sel > Night_Bus.Count then
            Menu_Back;
         else
            Toggle_Menu;
            Begin_Bus (Menu_Sel);
         end if;
         return;
      end if;
      if Level = Rounds_Menu then
         if Menu_Sel > Rounds.Count then
            Menu_Back;
         else
            Toggle_Menu;
            Begin_Round (Menu_Sel);
         end if;
         return;
      end if;
      if Level = Trials_Menu then
         if Menu_Sel > Trials.Count then
            Menu_Back;
         else
            Toggle_Menu;
            Begin_Trial (Menu_Sel);
         end if;
         return;
      end if;
      if Level = Tracks then
         if Menu_Sel > Race.Track_Count then
            Menu_Back;
         else
            Toggle_Menu;
            Begin_Race (Menu_Sel);
         end if;
         return;
      end if;
      case Item_At (Menu_Sel) is
         when Go_Racing =>
            Level := Racing;
            Menu_Sel := 1;
            Refresh_Menu;
         when Go_Taxi =>
            Level := Taxi_Menu;
            Menu_Sel := 1;
            Refresh_Menu;
         when Go_Trials =>
            Level := Trials_Menu;
            Menu_Sel := 1;
            Refresh_Menu;
         when Go_Rounds =>
            Level := Rounds_Menu;
            Menu_Sel := 1;
            Refresh_Menu;
         when Go_Bus =>
            Level := Bus_Menu;
            Menu_Sel := 1;
            Refresh_Menu;
         when Start_Shift =>
            Toggle_Menu;
            Begin_Taxi;
         when Stop_Shift =>
            Toggle_Menu;
            Taxi.End_Shift;
         when Go_Free =>
            Toggle_Menu;
            End_Race;
            Race.Edit_Cancel;
            End_Taxi;
         when Race_Again =>
            Toggle_Menu;
            Begin_Again;
         when Leave_Race =>
            Toggle_Menu;
            End_Race;
         when Street_Race =>
            Race.Load_Saved;
            Level := Tracks;
            Menu_Sel := 1;
            Refresh_Menu;
         when Random_Race =>
            Toggle_Menu;
            Begin_Race (0);
         when Make_Track =>
            Toggle_Menu;
            End_Race;
            Race.Edit_Start;
            Say ("Track editor: drive, and press Enter at each checkpoint", 6.0);
         when Save_Track =>
            declare
               Name : Ada.Strings.Unbounded.Unbounded_String;
            begin
               Race.Edit_Save (Name);
               Toggle_Menu;
               if Ada.Strings.Unbounded.Length (Name) = 0 then
                  Say ("A track needs at least two checkpoints");
               else
                  Say ("Saved as """ & Ada.Strings.Unbounded.To_String (Name)
                       & """ (F2, Street racing, Race on a track)", 4.0);
               end if;
            end;
         when Drop_Track =>
            Race.Edit_Cancel;
            Toggle_Menu;
         when Up =>
            Menu_Back;
      end case;
   end Menu_Choose;

   --  Keys while the menu is open; True when the key was used
   function Menu_Key (K : Gdk.Types.Gdk_Key_Type) return Boolean is
   begin
      case K is
         when 16#FF52# | 16#77# =>                            --  up, w
            if Menu_Sel > 1 then
               Menu_Sel := Menu_Sel - 1;
            end if;
         when 16#FF54# | 16#73# =>                            --  down, s
            if Menu_Sel < Menu_Items then
               Menu_Sel := Menu_Sel + 1;
            end if;
         when 16#FF0D# | 16#FF8D# | 16#20# =>                 --  Enter, space
            Menu_Choose;
            return True;
         when 16#31# .. 16#39# =>                             --  1 .. 9
            if Natural (K - 16#30#) <= Menu_Items then
               Menu_Sel := Positive (K - 16#30#);
               Menu_Choose;
            end if;
            return True;
         when 16#FF08# =>                                     --  Backspace
            Menu_Back;
            return True;
         when 16#FF51# | 16#61# =>                            --  left, a
            if Level = Tracks then
               Race.Set_Laps (if Race.Laps_Setting = 0 then 5 else Race.Laps_Setting - 1);
            else
               Menu_Back;
               return True;
            end if;
         when 16#FF53# | 16#64# =>                            --  right, d
            if Level = Tracks then
               Race.Set_Laps (if Race.Laps_Setting = 5 then 0 else Race.Laps_Setting + 1);
            else
               return True;
            end if;
         when 16#FFBF# | 16#FF1B# =>                          --  F2, Escape
            Toggle_Menu;
            return True;
         when others =>
            return False;
      end case;
      Refresh_Menu;
      return True;
   end Menu_Key;

   --  Each frame: the race's labels and the GPS to the next gate
   procedure Race_Overlays is
      use Ada.Strings.Unbounded;
      use type Race.Phase_Kind;
      X, Z : Float;
   begin
      if Race.Editing then
         declare
            T : constant String :=
              "<span font_family='sans' weight='bold' foreground='white' background='#000000a0'>"
              & "  Track editor: " & Ada.Strings.Fixed.Trim (Natural'Image (Race.Edit_Points), Ada.Strings.Left)
              & " checkpoints   Enter: drop one here   Backspace: undo   F2: save  </span>";
         begin
            if To_String (Race_Shown) /= T then
               Race_Shown := To_Unbounded_String (T);
               Race_Hud.Set_Markup (T);
               Race_Hud.Show;
            end if;
         end;
         return;
      elsif not Race.Active then
         if Race_Hud.Get_Visible and then Length (Race_Shown) > 0 and then not Taxi.Active then
            Race_Shown := Null_Unbounded_String;
            Race_Hud.Hide;
         end if;
         return;
      end if;
      declare
         T : constant String := Race.Hud_Text;
         W : constant String := Race.Warning;
         B : constant String := (if Race.Banner /= "" then Race.Banner
                                 elsif W /= "" then "!" & W else "");
      begin
         if To_String (Race_Shown) /= T then
            Race_Shown := To_Unbounded_String (T);
            Race_Hud.Set_Markup (T);
         end if;
         if To_String (Banner_Shown) /= B then
            Banner_Shown := To_Unbounded_String (B);
            if B = "" then
               Race_Banner.Hide;
            else
               if B (B'First) = '!' then
                  --  a warning: "!TITLE|what to do"
                  declare
                     Bar : constant Natural := Ada.Strings.Fixed.Index (B, "|");
                  begin
                     Race_Banner.Set_Markup
                       ("<span font_family='sans' background='#a01818d8' foreground='white'>"
                        & "<span weight='heavy' size='36000'>  " & B (B'First + 1 .. Bar - 1)
                        & "  </span>" & ASCII.LF & "<span size='18000'>  " & B (Bar + 1 .. B'Last)
                        & "  </span></span>");
                  end;
               else
                  Race_Banner.Set_Markup
                    ("<span font_family='sans' weight='heavy' size='72000' foreground='"
                     & (if B = "GO!" then "#5cff7a" else "#ffd27a") & "'>" & B & "</span>");
               end if;
               Race_Banner.Show;
            end if;
         end if;
      end;
      if Race.Next_Gate (X, Z) then
         if abs (X - Gate_X) + abs (Z - Gate_Z) > 1.0 then
            Gate_X := X;
            Gate_Z := Z;
            declare
               Way : Road_Network.Route_Vectors.Vector;
            begin
               Race.Route_To_Gate (Player.X, Player.Z, Way);
               Navigation.Follow ("Next checkpoint", Way);
            end;
         end if;
      end if;
      if Race.Phase = Race.Finished then
         if not Results_Up then
            Navigation.Clear;
         end if;
         --  the results once the FINISHED banner has been seen
         if not Results_Up and then Race.Seconds_Since_Finish >= 3.0 and then not Menu_Open then
            Results_Up := True;
            Results_Open := True;
            Results_Shown := Null_Unbounded_String;
            Game_Menu.Show;
         end if;
         --  the others come in one by one
         if Results_Open then
            declare
               R : constant String := Race.Results_Text;
            begin
               if To_String (Results_Shown) /= R then
                  Results_Shown := To_Unbounded_String (R);
                  Game_Menu.Set_Markup (R);
               end if;
            end;
         end if;
      end if;
   end Race_Overlays;

   --  Each frame in a taxi shift: the HUD, a fine, the ride's panel, the
   --  GPS and the speed limit sign
   --  The time trial: its line at the top, the countdown, the result, the GPS
   procedure Trial_Overlays is
      use Ada.Strings.Unbounded;
      use type Trials.Phase_Kind;
   begin
      if not Trials.Active then
         return;
      end if;
      declare
         T : constant String := Trials.Hud_Text;
         B : constant String := Trials.Banner;
         P : constant String := Trials.Panel_Text;
      begin
         if To_String (Race_Shown) /= T then
            Race_Shown := To_Unbounded_String (T);
            if T = "" then
               Race_Hud.Hide;
            else
               Race_Hud.Set_Markup (T);
               Race_Hud.Show;
            end if;
         end if;
         if To_String (Banner_Shown) /= B then
            Banner_Shown := To_Unbounded_String (B);
            if B = "" then
               Race_Banner.Hide;
            else
               Race_Banner.Set_Markup ("<span font_family='sans' weight='heavy' size='60000' foreground='#ffd27a'>"
                                       & B & "</span>");
               Race_Banner.Show;
            end if;
         end if;
         if not Menu_Open and then To_String (Panel_Shown) /= P then
            Panel_Shown := To_Unbounded_String (P);
            if P = "" then
               Game_Menu.Hide;
            else
               Game_Menu.Set_Markup (P);
               Game_Menu.Show;
            end if;
         end if;
      end;
      declare
         Serial : Natural;
         X, Z   : Float;
         Name   : Unbounded_String;
      begin
         Trials.Goal (Serial, X, Z, Name);
         if Serial /= Trial_Goal then
            Trial_Goal := Serial;
            if Length (Name) = 0 then
               Navigation.Clear;
            else
               Navigation.Set_Destination (To_String (Name), X, Z);
            end if;
         end if;
      end;
   end Trial_Overlays;

   --  The morning round: the same, its line, the account, the GPS
   procedure Round_Overlays is
      use Ada.Strings.Unbounded;
         begin
      if not Rounds.Active then
         return;
      end if;
      declare
         T : constant String := Rounds.Hud_Text;
         B : constant String := Rounds.Banner;
         P : constant String := Rounds.Panel_Text;
      begin
         if To_String (Race_Shown) /= T then
            Race_Shown := To_Unbounded_String (T);
            if T = "" then
               Race_Hud.Hide;
            else
               Race_Hud.Set_Markup (T);
               Race_Hud.Show;
            end if;
         end if;
         if To_String (Banner_Shown) /= B then
            Banner_Shown := To_Unbounded_String (B);
            if B = "" then
               Race_Banner.Hide;
            else
               Race_Banner.Set_Markup ("<span font_family='sans' weight='heavy' size='60000' foreground='#ffd27a'>"
                                       & B & "</span>");
               Race_Banner.Show;
            end if;
         end if;
         if not Menu_Open and then To_String (Panel_Shown) /= P then
            Panel_Shown := To_Unbounded_String (P);
            if P = "" then
               Game_Menu.Hide;
            else
               Game_Menu.Set_Markup (P);
               Game_Menu.Show;
            end if;
         end if;
      end;
      declare
         Serial : Natural;
         X, Z   : Float;
         Name   : Unbounded_String;
      begin
         Rounds.Goal (Serial, X, Z, Name);
         if Serial /= Round_Goal then
            Round_Goal := Serial;
            if Length (Name) = 0 then
               Navigation.Clear;
            else
               Navigation.Set_Destination (To_String (Name), X, Z);
            end if;
         end if;
      end;
   end Round_Overlays;

   --  The night bus: likewise
   procedure Bus_Overlays is
      use Ada.Strings.Unbounded;
         begin
      if not Night_Bus.Active then
         return;
      end if;
      declare
         T : constant String := Night_Bus.Hud_Text;
         B : constant String := Night_Bus.Banner;
         P : constant String := Night_Bus.Panel_Text;
      begin
         if To_String (Race_Shown) /= T then
            Race_Shown := To_Unbounded_String (T);
            if T = "" then
               Race_Hud.Hide;
            else
               Race_Hud.Set_Markup (T);
               Race_Hud.Show;
            end if;
         end if;
         if To_String (Banner_Shown) /= B then
            Banner_Shown := To_Unbounded_String (B);
            if B = "" then
               Race_Banner.Hide;
            else
               Race_Banner.Set_Markup ("<span font_family='sans' weight='heavy' size='60000' foreground='#ffd27a'>"
                                       & B & "</span>");
               Race_Banner.Show;
            end if;
         end if;
         if not Menu_Open and then To_String (Panel_Shown) /= P then
            Panel_Shown := To_Unbounded_String (P);
            if P = "" then
               Game_Menu.Hide;
            else
               Game_Menu.Set_Markup (P);
               Game_Menu.Show;
            end if;
         end if;
      end;
      declare
         Serial : Natural;
         X, Z   : Float;
         Name   : Unbounded_String;
      begin
         Night_Bus.Goal (Serial, X, Z, Name);
         if Serial /= Bus_Goal then
            Bus_Goal := Serial;
            if Length (Name) = 0 then
               Navigation.Clear;
            else
               Navigation.Set_Destination (To_String (Name), X, Z);
            end if;
         end if;
      end;
   end Bus_Overlays;

   procedure Taxi_Overlays is
      use Ada.Strings.Unbounded;
   begin
      if not Taxi.Active then
         return;
      end if;
      declare
         T : constant String := Taxi.Hud_Text;
         W : constant String := Taxi.Warning;
         P : constant String := Taxi.Panel_Text;
      begin
         if To_String (Race_Shown) /= T then
            Race_Shown := To_Unbounded_String (T);
            if T = "" then
               Race_Hud.Hide;
            else
               Race_Hud.Set_Markup (T);
               Race_Hud.Show;
            end if;
         end if;
         if To_String (Banner_Shown) /= W then
            Banner_Shown := To_Unbounded_String (W);
            if W = "" then
               Race_Banner.Hide;
            else
               declare
                  Bar : constant Natural := Ada.Strings.Fixed.Index (W, "|");
               begin
                  Race_Banner.Set_Markup
                    ("<span font_family='sans' background='#a01818d8' foreground='white'>"
                     & "<span weight='heavy' size='30000'>  " & W (W'First + 1 .. Bar - 1)
                     & "  </span>" & ASCII.LF & "<span size='16000'>  " & W (Bar + 1 .. W'Last)
                     & "  </span></span>");
                  Race_Banner.Show;
               end;
            end if;
         end if;
         if not Menu_Open and then To_String (Panel_Shown) /= P then
            Panel_Shown := To_Unbounded_String (P);
            if P = "" then
               Game_Menu.Hide;
            else
               Game_Menu.Set_Markup (P);
               Game_Menu.Show;
            end if;
         end if;
      end;
      declare
         Serial : Natural;
         X, Z   : Float;
         Name   : Unbounded_String;
      begin
         Taxi.Goal (Serial, X, Z, Name);
         if Serial /= Taxi_Goal then
            Taxi_Goal := Serial;
            if Length (Name) = 0 then
               Navigation.Clear;
            else
               Navigation.Set_Destination (To_String (Name), X, Z);
            end if;
         end if;
      end;
      Limit_Sign.Set ((if Mode = Driving and then not Visiting and then not Walking
                       then Taxi.Limit else 0), Taxi.Over_Limit, Time);
   end Taxi_Overlays;

   --  Big text from the scenes in the middle of the screen
   procedure Scene_Overlays is
      use Ada.Strings.Unbounded;
   begin
      if Race.Active or else Taxi.Active or else Trials.Active or else Rounds.Active
        or else Night_Bus.Active
      then
         return;
      end if;
      declare
         B : constant String := Scenes.Banner;
      begin
         if To_String (Banner_Shown) /= B then
            Banner_Shown := To_Unbounded_String (B);
            if B = "" then
               Race_Banner.Hide;
            else
               Race_Banner.Set_Markup
                 ("<span font_family='sans' weight='heavy' size='72000' foreground='#ffd27a'>" & B & "</span>");
               Race_Banner.Show;
            end if;
         end if;
      end;
   end Scene_Overlays;

   --  Racing wheel buttons do what the keys do
   procedure Wheel_Buttons is
      B : Wheel.Button;
      procedure Tap (Key : Gdk.Types.Gdk_Key_Type) is
      begin
         Set_Key (Key, True);
         Set_Key (Key, False);
      end Tap;
   begin
      while Wheel.Next_Press (B) loop
         if Confirm_Open then
            case B is
               when Wheel.Cross  => Tap (16#FF0D#);
               when Wheel.Circle => Tap (16#FF1B#);
               when others => null;
            end case;
            goto Next;
         end if;
         if not Menu_Open and then Taxi.Panel_Text /= "" then
            case B is
               when Wheel.Cross  => Tap (16#FF0D#);   --  next fare
               when Wheel.Circle => Tap (16#FF1B#);   --  end the shift
               when others => null;
            end case;
            goto Next;
         end if;
         if Menu_Open then
            case B is
               when Wheel.Pad_Up   => Tap (16#FF52#);
               when Wheel.Pad_Down => Tap (16#FF54#);
               when Wheel.Cross    => Tap (16#FF0D#);
               when Wheel.Pad_Left => Tap (16#FF08#);   --  back
               when Wheel.Circle   => Tap (16#FFBF#);
               when others => null;
            end case;
            goto Next;
         end if;
         if List_Open then
            case B is
               when Wheel.Pad_Up   => Tap (16#FF52#);
               when Wheel.Pad_Down => Tap (16#FF54#);
               when Wheel.Cross    => Tap (16#FF0D#);
               when Wheel.Square   => Tap (16#20#);
               when Wheel.Circle | Wheel.Pad_Left => Tap (16#6F#);
               when Wheel.Pad_Right => Tap (16#6C#);
               when others => null;
            end case;
            goto Next;
         end if;
         case B is
            when Wheel.Pad_Right => Tap (16#6C#);   --  l: save this place
            when Wheel.Pad_Left  => Tap (16#6F#);   --  o: saved places
            when Wheel.Square   => Tap (16#63#);    --  c: camera
            when Wheel.Triangle => Tap (16#67#);    --  g: compass and map
            when Wheel.Circle   => Tap (16#6E#);    --  n: street names
            when Wheel.R2       => Tap (16#74#);    --  t: one hour later
            when Wheel.L2       => Tap (16#70#);    --  p: rain
            when Wheel.Share    => Tap (16#6A#);    --  j: clear traffic
            when Wheel.Options  => Tap (16#6D#);    --  m: sound
            when Wheel.PS       => Tap (16#68#);    --  h: home
            when Wheel.L3       => Tap (16#78#);    --  x: stop navigating
            when Wheel.Plus | Wheel.Dial_Right => Zoom_By (1.0 / 1.15);
            when Wheel.Minus | Wheel.Dial_Left => Zoom_By (1.15);
            when others => null;
         end case;
         <<Next>>
      end loop;
   end Wheel_Buttons;

   --  Force feedback: the front wheels pull back to the centre more the
   --  faster you go, the rim is damped, and kerbs and crashes kick
   procedure Wheel_Force (Dt : Float) is
      use Ada.Numerics.Elementary_Functions;
      In_Car : constant Boolean := Mode = Driving and then not Visiting;
      Steer  : constant Float := Wheel.State.Steering;
      Rate   : constant Float := (Steer - Last_Steering) / Float'Max (Dt, 0.001);
      V      : constant Float := abs Player.Speed;
      F      : Float;
   begin
      Last_Steering := Steer;
      Force_Time := Force_Time + Dt;
      if not In_Car then
         --  A light spring, so the wheel stays put in the air
         Wheel.Set_Force (-0.25 * Steer);
         return;
      end if;
      F := -(0.12 + 0.55 * Float'Min (1.0, V / 18.0)) * Steer * 2.2;
      F := F - 0.02 * Rate;                                    --  damping
      --  Off the road (pavement, cobbles) the rim shivers
      if not Player.On_Road and then V > 1.0 then
         F := F + 0.06 * Float'Min (1.0, V / 10.0) * Sin (Force_Time * 70.0);
      end if;
      --  a badly damaged car shakes in the hands
      if Race.Shake > 0.0 and then V > 2.0 then
         F := F + Race.Shake * Float'Min (1.0, V / 15.0)
           * (Sin (Force_Time * 31.0) + 0.5 * Sin (Force_Time * 53.0));
      end if;
      if Jolt_Time > 0.0 then
         declare
            Since : constant Float := Jolt_Length - Jolt_Time;   --  seconds since the hit
            Fade  : constant Float := Jolt_Time / Jolt_Length;
         begin
            --  first a push to the side that was hit, then it shakes out
            if Since < 0.07 then
               F := F + Jolt * Jolt_Side;
            end if;
            F := F + Jolt * (1.0 - 0.5 * abs Jolt_Side) * Sin (Since * 45.0 * Ada.Numerics.Pi / 3.0) * Fade;
         end;
         Jolt_Time := Float'Max (0.0, Jolt_Time - Dt);
      end if;
      --  rubbing along a wall: a fine rumble
      if Scrape > 0.01 then
         F := F + 0.07 * Scrape * Sin (Force_Time * 95.0);
         Scrape := Float'Max (0.0, Scrape - 6.0 * Dt);
      end if;
      Wheel.Set_Force (Float'Max (-0.9, Float'Min (0.9, F)));
   end Wheel_Force;

   --  The vehicles around the listener, for the sound: distance, side
   --  and how fast they come closer or move away
   function Hear_Traffic (X, Z, Ear_Y, Head : Float) return Sound.Voice_List is
      Near : constant Traffic.Source_List := Traffic.Nearby (X, Z);
      List : Sound.Voice_List;
      --  the listener's own movement
      LV   : constant Float := (if Mode = Driving and then not Visiting then Player.Speed else 0.0);
      LVX  : constant Float := Sin (Player.Heading) * LV;
      LVZ  : constant Float := -Cos (Player.Heading) * LV;
   begin
      for I in Near'Range loop
         if Near (I).Id /= 0 then
            declare
               N  : Traffic.Sound_Source renames Near (I);
               DX : constant Float := N.X - X;
               DZ : constant Float := N.Z - Z;
               DH : constant Float := Float'Max (0.5, Sqrt (DX * DX + DZ * DZ));
               D  : constant Float := Sqrt (DH * DH + (Ear_Y - 0.8) ** 2);
               VX : constant Float := Sin (N.Heading) * N.Speed - LVX;
               VZ : constant Float := -Cos (N.Heading) * N.Speed - LVZ;
            begin
               List (I) := (Id => N.Id, Dist => D,
                            Pan => (DX * Cos (Head) + DZ * Sin (Head)) / DH,
                            Radial => (VX * DX + VZ * DZ) / D,
                            Speed => N.Speed, Kind => N.Kind);
            end;
         end if;
      end loop;
      return List;
   end Hear_Traffic;

   --  Saint-Sulpice: how loud its bells are where you are
   function Church_Near return Float is
      SX, SZ : Long_Float;
      Where  : constant Vec3 := (if Visiting then Eye_Position else Focus);
   begin
      Geo.To_Local (48.85100, 2.33480, SX, SZ);
      --  close by they are loud; a few streets away much softer
      return 1.0 / (1.0 + (Sqrt ((Where.X - Float (SX)) ** 2 + (Where.Z - Float (SZ)) ** 2)
                           / 150.0) ** 1.6);
   end Church_Near;

   Last_Clock : Float := -1.0;
   --  a wedding on some Saturdays
   Wedding : constant Boolean := Integer (Ada.Calendar.Seconds (Ada.Calendar.Clock)) mod 2 = 0;

   --  Compass, position read-out and sound, once per frame
   procedure Update_Senses is
      Look  : constant Vec3 := Cam_Look - Cam_Pos;
      Head  : constant Float := Arctan (Look.X, -Look.Z);
      Where : constant Vec3 := (if Visiting then Eye_Position elsif Walking then Walk_Eye else Focus);
      Lat, Lon : Long_Float;
      Ear_Y : constant Float :=
        (if Visiting then Home.Floor_Y + 1.6 - Terrain.Height (Home.Origin.X, Home.Origin.Z)
         elsif Mode = Flying then Aircraft.Pos.Y - Terrain.Height (Aircraft.Pos.X, Aircraft.Pos.Z)
         else 1.2);
   begin
      Geo.To_Lat_Lon (Long_Float (Where.X), Long_Float (Where.Z), Lat, Lon);
      --  PARIS_TRACE=1: where you are, twice a second, on the terminal
      if Frame_Number mod 30 = 0 and then Env ("PARIS_TRACE") /= "" then
         declare
            function Six (V : Long_Float) return String is
              (Ada.Strings.Fixed.Trim (Integer'Image (Integer (Long_Float'Floor (V))), Ada.Strings.Left) & "."
               & Ada.Strings.Fixed.Tail (Ada.Strings.Fixed.Trim
                   (Integer'Image (Integer ((V - Long_Float'Floor (V)) * 1.0E6)), Ada.Strings.Left), 6, '0'));
         begin
            Ada.Text_IO.Put_Line ("at " & Six (Lat) & " " & Six (Lon) & "  heading"
                                  & Integer'Image (Integer (Head * 180.0 / Ada.Numerics.Pi) mod 360)
                                  & "  frame" & Integer'Image (Frame_Number));
            Ada.Text_IO.Flush;
         end;
      end if;
      Sleigh.Set_Listener_Heading (Head);
      Ufo.Set_Listener_Heading (Head);
      if Show_Compass then
         Compass.Update (Head + Ufo.Nearness * Ufo.Nearness * 25.0 * Sin (Time * 1.7)
                                * Sin (Time * 0.6 + 1.0), Lat, Lon, (if Mode = Flying and then not Visiting
                                           then Aircraft.Pos.Y else -1.0));
      end if;
      Navigation.Update (Where.X, Where.Z,
                         (if Visiting or else Walking or else Mode = Flying then Head else Player.Heading),
                         1.0 / 60.0, Route_Allowed => Mode = Driving and then not Visiting);

      Sound.Set
        ((Mode     => (if Visiting then Sound.Visiting elsif Walking then Sound.Walking
                       elsif Mode = Flying then Sound.Flying else Sound.Driving),
          Rpm      => Player.Rpm,
          Load     => (if Mode = Flying then Aircraft.Throttle
                       elsif Race.Misfiring then 0.0
                       elsif Keys.Up or else Keys.W then 1.0
                       elsif Wheel.Present then Float'Max (0.15, Wheel.State.Throttle)
                       else 0.15),
          Speed    => (if Mode = Flying then Aircraft.Speed else abs Player.Speed),
          Altitude => (if In_Museum or else In_Hall_B or else In_Room then 400.0 elsif On_Tower then 280.0
                       elsif On_Arc then 50.0 else Ear_Y),
          Rain     => Rain_Amount,
          Night    => Night,
          Traffic  => Float'Max (0.0, 1.0 - Traffic.Nearest (Where.X, Where.Z) / 60.0),
          Horn     => Keys.B or else Wheel.Held (Wheel.Enter)
                      or else (Env ("PARIS_BELL") /= "" and then Frame_Number mod 150 < 5),   --  (testing)
          Engine_Off => Mode = Driving and then not Visiting and then (Race.Wrecked or else Riding_Velib),
          Two_Stroke => Car."=" (Car.Player_Model, Car.Scooter),
          Bike     => Riding_Velib,
          Church   => Church_Near,
          Jingle   => Sleigh.Jingle,
          Jets     => Surprises.Jets,
          Crowd    => (if In_Museum or else In_Hall_B or else In_Room then 0.1
                       else Float'Max (Float'Max (Float'Max (Surprises.Crowd, Race.Crowd),
                                                  Sky_Life.Crowd (Where)),
                                       Scenes.Crowd (Where.X, Where.Z))),   --  the murmur of visitors
          Busker   => Surprises.Busker,
          Busker_Level => Surprises.Busker_Level,
          Busker_Pan => Surprises.Busker_Pan,
          Alien    => Ufo.Nearness,
          Alien_Pan => Ufo.Pan,
          Jingle_Pan => Sleigh.Pan,
          Squeal   => (if Mode = Driving and then not Visiting
                       then Float'Min (1.0, Float'Max (Player.Skid * Float'Min (1.0, abs Player.Speed / 6.0),
                                                       Player.Spin / 4.0))
                            * (1.0 - 0.7 * Wetness)
                       else 0.0),
          Voices   => Hear_Traffic (Where.X, Where.Z, Ear_Y, Head)));

      --  The hour strikes (from Saint-Sulpice, louder the nearer you are),
      --  and on the days for it all the bells ring out
      declare
         H : constant Integer := Integer (Float'Floor (Hour));
         function Crossed (T : Float) return Boolean is
           (Last_Clock >= 0.0 and then Last_Clock < T and then Hour >= T
            and then Hour - Last_Clock < 1.0);
      begin
         if Last_Hour >= 0 and then H /= Last_Hour and then Night < 0.9
           and then not Sound.Pealing
         then
            Sound.Bells ((if H mod 12 = 0 then 12 else H mod 12), Church_Near);
         end if;
         if not Sound.Pealing then
            if (Almanac.Sunday and then Crossed (10.75))            --  before Sunday mass
              or else (Almanac.Easter_Sunday and then Crossed (11.9))
              or else (Almanac.Christmas_Eve and then Crossed (23.7))  --  midnight mass
              or else (Almanac.Month = 1 and then Almanac.Day = 1 and then Last_Clock > 23.0
                       and then Hour < 0.5)                         --  New Year
              or else (Almanac.Saturday and then Crossed (15.5) and then Wedding)
            then
               Sound.Peal (240.0);
            end if;
         end if;
         Last_Hour := H;
         Last_Clock := Hour;
      end;
   end Update_Senses;

   --  Errors are said on the terminal and kept in ~/.derive.log (the
   --  first few of a session), for when the game runs without a terminal
   Errors_Logged : Natural := 0;

   procedure Log_Error (Where : String; E : Ada.Exceptions.Exception_Occurrence) is
      F : Ada.Text_IO.File_Type;
      Name : constant String := Env ("HOME") & "/.derive.log";
   begin
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error,
                            Where & ": " & Ada.Exceptions.Exception_Information (E));
      if Errors_Logged >= 20 then
         return;
      end if;
      Errors_Logged := Errors_Logged + 1;
      begin
         Ada.Text_IO.Open (F, Ada.Text_IO.Append_File, Name);
      exception
         when Ada.Text_IO.Name_Error =>
            Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Name);
      end;
      Ada.Text_IO.Put_Line (F, Ada.Calendar.Formatting.Image (Ada.Calendar.Clock) & "  " & Where & ": "
                            & Ada.Exceptions.Exception_Information (E));
      Ada.Text_IO.Close (F);
   exception
      when others => null;   --  no log then
   end Log_Error;

   procedure Callback_Failed (E : Ada.Exceptions.Exception_Occurrence) is
   begin
      Log_Error ("Error in a callback", E);
   end Callback_Failed;

   Density_Wait : Float := 0.0;


   --  How busy the streets are at this hour, against normal
   --  How busy the streets are through the day: empty in the small hours,
   --  slowly waking from five, the rush hours on weekdays; on Saturdays and
   --  more so on Sundays the morning stays quiet till late
   function Traffic_Factor (H : Float) return Float is
      Weekday : constant Boolean := not Almanac.Saturday and then not Almanac.Sunday;
      type Point is record
         Hour, Level : Float;
      end record;
      type Curve is array (Positive range <>) of Point;
      Week : constant Curve :=
        ((0.0, 0.4), (2.0, 0.25), (4.5, 0.15), (5.5, 0.25), (6.5, 0.45), (7.5, 0.9), (8.0, 1.5),
         (9.0, 1.6), (9.75, 1.0), (16.5, 1.05), (17.5, 1.6), (19.0, 1.5), (20.0, 1.0), (22.0, 0.75),
         (24.0, 0.4));
      Weekend : constant Curve :=
        ((0.0, 0.6), (3.0, 0.4), (5.0, 0.2), (7.0, 0.2), (9.0, 0.45), (11.0, 0.85), (13.0, 1.0),
         (19.0, 1.0), (22.0, 0.85), (24.0, 0.6));
      function Along (C : Curve) return Float is
      begin
         for I in C'First .. C'Last - 1 loop
            if H >= C (I).Hour and then H < C (I + 1).Hour then
               return C (I).Level + (C (I + 1).Level - C (I).Level)
                 * (H - C (I).Hour) / (C (I + 1).Hour - C (I).Hour);
            end if;
         end loop;
         return C (C'Last).Level;
      end Along;
   begin
      return (if Weekday then Along (Week)
              elsif Almanac.Sunday then 0.85 * Along (Weekend)
              else Along (Weekend));
   end Traffic_Factor;

   function Radio_Facts return Radio.Facts is
     ((Hour    => Hour,
       Rain    => Rain_Amount,
       Snow    => Snow_Amount,
       Storm   => Storm_On and then Rain_Amount > 0.5,
       Closed  => Closures.Count,
       Traffic => Traffic_Factor (Hour)));

   Tick_Failed : Natural := 0;   --  errors in frames told about

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

      if Ready and then Frame_Number = 2 and then Env ("PARIS_VISIT") /= "" and then not Visiting then
         Toggle_Visit;
         if Env ("PARIS_KITCHEN") /= "" then
            Go_To_Kitchen;
            Eye_Pitch := Float'Value (Env ("PARIS_KITCHEN")) * Ada.Numerics.Pi / 180.0;
         end if;
         if Env ("PARIS_VISIT_D") /= "" then
            Eye_D := Float'Value (Env ("PARIS_VISIT_D"));
         end if;
         if Env ("PARIS_VISIT") /= "1" then
            Eye_Yaw := Eye_Yaw + Float'Value (Env ("PARIS_VISIT")) * Ada.Numerics.Pi / 180.0;
         end if;
      end if;
      --  PARIS_ALBUM=<frame>: open the postcard album then (testing)
      if Env ("PARIS_ALBUM") /= "" and then Frame_Number = Integer'Value (Env ("PARIS_ALBUM")) then
         Postcards.Toggle_Album;
      end if;
      if Frame_Number = 2 and then Env ("PARIS_HELP_PNG") /= "" then
         Set_Key (16#FFBE#, True);
      end if;
      if Ready and then Frame_Number = 40 and then Env ("PARIS_PHOTO") /= "" then
         Take_Photo := True;
      end if;
      if Ready and then Frame_Number = 20 and then Env ("PARIS_LIST_PNG") /= "" then
         Set_Key (16#6C#, True);    --  save here
         Set_Key (16#6F#, True);    --  open the list
         Set_Key (16#FF54#, True);  --  choose the next one
         Set_Key (16#FF54#, False);
      end if;
      if Ready and then Frame_Number = 3 and then Env ("PARIS_NAV") /= "" then
         declare
            P : constant Place := Places (Integer'Value (Env ("PARIS_NAV")));
            X, Z : Long_Float;
         begin
            Geo.To_Local (P.Lat, P.Lon, X, Z);
            Navigation.Set_Destination (Ada.Strings.Unbounded.To_String (P.Name),
                                        Float (X), Float (Z));
         end;
      end if;
      if Ready and then Frame_Number = 30 and then Env ("PARIS_TELEPORT") /= "" then
         Teleport (Places (Integer'Value (Env ("PARIS_TELEPORT"))));
      end if;
      --  PARIS_TOGGLE_FLIGHT=<frame>: press F then (testing)
      if Ready and then Env ("PARIS_TOGGLE_FLIGHT") /= ""
        and then (Frame_Number = Integer'Value (Env ("PARIS_TOGGLE_FLIGHT"))
                  or else Frame_Number = Integer'Value (Env ("PARIS_TOGGLE_BACK", "-1")))
      then
         Set_Key (16#66#, True);
         Set_Key (16#66#, False);
      end if;
      if Ready and then Frame_Number = 30 and then Env ("PARIS_WALK") /= "" then
         Toggle_Walk;
         Walk_Yaw := Walk_Yaw + Float'Value (Env ("PARIS_WALK")) * Ada.Numerics.Pi / 180.0;
         Walk_Pitch := -Float'Value (Env ("PARIS_WALK_PITCH", "0")) * Ada.Numerics.Pi / 180.0;
      end if;
      --  PARIS_ARC=yaw: on the roof of the Arc de Triomphe (testing)
      if Ready and then Frame_Number = 30 and then Env ("PARIS_ARC") /= "" then
         if not Walking then
            Toggle_Walk;
         end if;
         Up_The_Arc;
         Walk_Yaw := Walk_Yaw + Float'Value (Env ("PARIS_ARC")) * Ada.Numerics.Pi / 180.0;
      end if;
      --  PARIS_TOWER=yaw: on top of the Eiffel Tower (testing)
      if Ready and then Frame_Number = 30 and then Env ("PARIS_TOWER") /= "" then
         if not Walking then
            Toggle_Walk;
         end if;
         Go_Up;
         Walk_Yaw := Walk_Yaw + Float'Value (Env ("PARIS_TOWER")) * Ada.Numerics.Pi / 180.0;
      end if;
      --  PARIS_ROOM="k x z yaw" (k: A, B, C or D): in a room, x z from its entrance (testing)
      if Ready and then Frame_Number = 30 and then Env ("PARIS_ROOM") /= "" then
         if not Walking then
            Toggle_Walk;
         end if;
         declare
            S  : constant String := Env ("PARIS_ROOM") & " 0 0 0 ";
            P0 : constant Natural := Index_Of (S, ' ', S'First);
            P1 : constant Natural := Index_Of (S, ' ', P0 + 1);
            P2 : constant Natural := Index_Of (S, ' ', P1 + 1);
            P3 : constant Natural := Index_Of (S, ' ', P2 + 1);
         begin
            Enter_Room (Rooms.Room_Kind'Value ("Room_" & S (S'First .. P0 - 1)));
            Walk_X := Walk_X + Float'Value (S (P0 + 1 .. P1 - 1));
            Walk_Z := Walk_Z + Float'Value (S (P1 + 1 .. P2 - 1));
            Walk_Yaw := Walk_Yaw + Float'Value (S (P2 + 1 .. P3 - 1)) * Ada.Numerics.Pi / 180.0;
         end;
      end if;
      --  PARIS_HALL="x z yaw": in hall B (testing)
      if Ready and then Frame_Number = 30 and then Env ("PARIS_HALL") /= "" then
         if not Walking then
            Toggle_Walk;
         end if;
         Enter_Hall_B;
         declare
            S  : constant String := Env ("PARIS_HALL") & " ";
            P1 : constant Natural := Index_Of (S, ' ', S'First);
            P2 : constant Natural := Index_Of (S, ' ', P1 + 1);
            EX, EZ, EY : Float;
         begin
            Hall_B.Entrance (EX, EZ, EY);
            Walk_X := EX - 3.0 + Float'Value (S (S'First .. P1 - 1));
            Walk_Z := EZ + Float'Value (S (P1 + 1 .. P2 - 1));
            Walk_Yaw := Float'Value (S (P2 + 1 .. S'Last - 1)) * Ada.Numerics.Pi / 180.0;
         end;
      end if;
      --  PARIS_LOUVRE="x z yaw": stand in the gallery (testing)
      if Ready and then Frame_Number = 30 and then Env ("PARIS_LOUVRE") /= "" then
         if not Walking then
            Toggle_Walk;
         end if;
         Enter_Museum;
         declare
            S  : constant String := Env ("PARIS_LOUVRE") & " ";
            P1 : constant Natural := Index_Of (S, ' ', S'First);
            P2 : constant Natural := Index_Of (S, ' ', P1 + 1);
            EX, EZ, EY : Float;
         begin
            Museum.Entrance (EX, EZ, EY);
            Walk_X := EX - 3.0 + Float'Value (S (S'First .. P1 - 1));
            Walk_Z := EZ + Float'Value (S (P1 + 1 .. P2 - 1));
            Walk_Yaw := Float'Value (S (P2 + 1 .. S'Last - 1)) * Ada.Numerics.Pi / 180.0;
         end;
      end if;
      --  PARIS_MENU=1|racing|tracks: the games menu open (testing)
      if Ready and then Frame_Number = 20 and then Env ("PARIS_MENU") /= "" then
         Set_Key (16#FFBF#, True);
         if Env ("PARIS_MENU") /= "1" then
            Set_Key (16#FF0D#, True);   --  Street racing
         end if;
         if Env ("PARIS_MENU") = "tracks" then
            Set_Key (16#FF0D#, True);   --  Race on a track
         end if;
      end if;
      --  PARIS_METRO=1: down the nearest metro entrance; PARIS_METRO_GO=n:
      --  then n stations down the list and aboard (testing)
      if Ready and then Frame_Number = 30 and then Env ("PARIS_METRO") /= "" then
         if not Walking then
            Toggle_Walk;
         end if;
         Enter_Room (Rooms.Room_Metro);
      end if;
      if Ready and then Frame_Number = 60 and then Env ("PARIS_METRO_GO") /= "" then
         for I in 1 .. Natural'Value (Env ("PARIS_METRO_GO")) loop
            Set_Key (16#FF54#, True);
         end loop;
         Set_Key (16#FF0D#, True);
      end if;
      --  PARIS_BOAT=1: aboard a bateau-mouche at the Pont de l'Alma (testing)
      if Ready and then Frame_Number = 30 and then Env ("PARIS_BOAT") /= "" then
         if not Walking then
            Toggle_Walk;
         end if;
         Boats.Landing (Walk_X, Walk_Z);
         Walk_Z := Walk_Z + 1.5;
      end if;
      --  PARIS_TRIAL=n: start that time trial; PARIS_TRIAL_AUTO=1: jump to
      --  each checkpoint in turn (testing)
      if Ready and then Frame_Number = 30 and then Env ("PARIS_TRIAL") /= "" then
         Begin_Trial (Natural'Value (Env ("PARIS_TRIAL")));
      end if;
      if Ready and then Env ("PARIS_TRIAL_AUTO") /= "" and then Frame_Number mod 100 = 0
        and then Trials."=" (Trials.Phase, Trials.Running)
      then
         declare
            Serial : Natural;
            X, Z   : Float;
            Name   : Ada.Strings.Unbounded.Unbounded_String;
         begin
            Trials.Goal (Serial, X, Z, Name);
            Player := (X => X, Z => Z, Heading => Player.Heading, others => <>);
            Player.Ground := Terrain.Height (X, Z);
         end;
      end if;
      --  PARIS_VELIB=1: on foot to the nearest Vélib' station, and a bike
      --  from it (testing)
      if Ready and then Frame_Number = 40 and then Env ("PARIS_VELIB") /= "" then
         declare
            Found : Boolean;
            BX, BZ, BH : Float;
         begin
            Street_Life.Nearest_Velib (Player.X, Player.Z, 3000.0, Found, BX, BZ, BH);
            if Found then
               Player.Speed := 0.0;
               if not Walking then
                  Toggle_Walk;
               end if;
               Walk_X := BX;
               Walk_Z := BZ;
               Walk_Yaw := BH;
               Toggle_Walk;
            end if;
         end;
      end if;
      --  PARIS_BUS=n: drive that night bus line; PARIS_BUS_AUTO=1: to each
      --  stop in turn (testing)
      if Ready and then Frame_Number = 30 and then Env ("PARIS_BUS") /= "" then
         Begin_Bus (Natural'Value (Env ("PARIS_BUS")));
      end if;
      if Ready and then Env ("PARIS_BUS_AUTO") /= "" and then Frame_Number mod 150 = 0
        and then Night_Bus."=" (Night_Bus.Phase, Night_Bus.Driving)
      then
         declare
            Serial : Natural;
            X, Z   : Float;
            Name   : Ada.Strings.Unbounded.Unbounded_String;
            Found  : Boolean;
            RX, RZ, RH : Float;
         begin
            Night_Bus.Goal (Serial, X, Z, Name);
            Road_Network.Nearest_Road (X, Z, Found, RX, RZ, RH);
            Player := Car.On_Ground (X, Z, (if Found then RH else Player.Heading));
            Player.Ground := Terrain.Height (X, Z);
         end;
      end if;
      --  PARIS_BUY=n: in the hall, n postcards bought at the shop (testing)
      if Ready and then In_Hall_B and then Env ("PARIS_BUY") /= "" and then Frame_Number >= 60
        and then Frame_Number mod 20 = 0 and then Frame_Number < 60 + 20 * Natural'Value (Env ("PARIS_BUY"))
      then
         Hall_B.Next_Card (Snap_Name, Snap_Text, Snap_Eye, Snap_Look);
         Snap_Frames := 4;
         Hall_B.Snapping := True;
      end if;
      --  PARIS_RADIO=1: the radio on (testing)
      if Ready and then Frame_Number = 30 and then Env ("PARIS_RADIO") /= "" then
         Radio.Toggle (Radio_Facts);
      end if;
      --  PARIS_ROUND=n: the morning round from that bakery; PARIS_ROUND_AUTO=1:
      --  to each door in turn, 30 m short of it first (testing)
      if Ready and then Frame_Number = 30 and then Env ("PARIS_ROUND") /= "" then
         Begin_Round (Natural'Value (Env ("PARIS_ROUND")));
      end if;
      if Ready and then Env ("PARIS_ROUND_AUTO") /= "" and then Frame_Number mod 100 = 0
        and then Rounds."=" (Rounds.Phase, Rounds.Riding)
      then
         declare
            Serial : Natural;
            X, Z   : Float;
            Name   : Ada.Strings.Unbounded.Unbounded_String;
            Found  : Boolean;
            RX, RZ, RH : Float;
            Short  : constant Float := (if Frame_Number mod 200 = 0 then 30.0 else 0.0);
         begin
            Rounds.Goal (Serial, X, Z, Name);
            Road_Network.Nearest_Road (X, Z, Found, RX, RZ, RH);
            if not Found then
               RH := Player.Heading;
            end if;
            X := X - Short * Sin (RH);
            Z := Z + Short * Cos (RH);
            Player := Car.On_Ground (X, Z, RH);
            Player.Ground := Terrain.Height (X, Z);
         end;
      end if;
      --  PARIS_TAXI_AUTO=1: jump to each fare and destination in turn (testing)
      if Ready and then Env ("PARIS_TAXI_AUTO") /= "" and then Frame_Number mod 150 = 0 then
         declare
            use type Taxi.Phase_Kind;
            Serial : Natural;
            X, Z   : Float;
            Name   : Ada.Strings.Unbounded.Unbounded_String;
         begin
            Taxi.Goal (Serial, X, Z, Name);
            if Taxi.Phase = Taxi.Paid then
               Set_Key (16#FF0D#, True);
            elsif Ada.Strings.Unbounded.Length (Name) > 0 then
               Player := (X => X, Z => Z, Heading => Player.Heading, others => <>);
               Player.Ground := Terrain.Height (X, Z);
            end if;
         end;
      end if;
      --  PARIS_DECAL=A..E: on foot a few steps from it (testing)
      if Ready and then Frame_Number = 30 and then Env ("PARIS_DECAL") /= "" then
         declare
            K : constant Decals.Decal_Kind := Decals.Decal_Kind'Value ("Decal_" & Env ("PARIS_DECAL"));
            X, Z : Float;
            D : constant Float := Float'Value (Env ("PARIS_DECAL_D", "3.0"));
         begin
            Decals.Position (K, X, Z);
            if not Walking then
               Toggle_Walk;
            end if;
            Walk_X := X + D * 0.6;
            Walk_Z := Z + D * 0.8;
            Walk_Yaw := Arctan (X - Walk_X, -(Z - Walk_Z));
            Walk_Pitch := -0.45;
         end;
      end if;
      --  PARIS_SEARCH="76 rue bonaparte": the address box with that typed (testing)
      if Ready and then Frame_Number = 40 and then Env ("PARIS_SEARCH") /= "" then
         Open_Search;
         Search_Text := Ada.Strings.Unbounded.To_Unbounded_String (Env ("PARIS_SEARCH"));
         Refresh_Search;
         for I in 1 .. Search_N loop
            Ada.Text_IO.Put_Line ("search: " & Search_Hits (I).Label (1 .. Search_Hits (I).Last)
                                  & Integer (Search_Hits (I).X)'Image & Integer (Search_Hits (I).Z)'Image);
         end loop;
         if Env ("PARIS_SEARCH_GO") /= "" and then Search_N > 0 then
            Navigation.Set_Destination (Search_Hits (1).Label (1 .. Search_Hits (1).Last),
                                        Search_Hits (1).X, Search_Hits (1).Z);
            Close_Search;
            Ada.Text_IO.Put_Line ("search: destination set");
         end if;
      end if;
      --  PARIS_HEADING=<degrees>: turn the car that way (testing)
      if Ready and then Frame_Number = 30 and then Env ("PARIS_HEADING") /= "" then
         Player.Heading := Float'Value (Env ("PARIS_HEADING")) * Ada.Numerics.Pi / 180.0;
      end if;
      --  PARIS_TAXI=1: start a taxi shift (testing)
      if Ready and then Frame_Number = 30 and then Env ("PARIS_TAXI") /= "" then
         Begin_Taxi;
      end if;
      --  PARIS_RACE=<track>: on the grid at once (0: a random track; testing)
      if Ready and then Frame_Number = 30 and then Env ("PARIS_RACE") /= "" then
         if Env ("PARIS_RACE_LAPS") /= "" then
            Race.Set_Laps (Natural'Value (Env ("PARIS_RACE_LAPS")));
         end if;
         Begin_Race (Natural'Value (Env ("PARIS_RACE")));
      end if;
      if Ready and then Frame_Number = 30 and then Env ("PARIS_PEAL") /= "" then
         Sound.Peal (Float'Value (Env ("PARIS_PEAL")));
      end if;
      if Ready and then Env ("PARIS_AUTODRIVE") /= "" then
         Keys.W := True;
      end if;
      --  PARIS_RECORD=<seconds>: record a video from frame 30 (testing)
      if Ready and then Env ("PARIS_RECORD") /= "" then
         if Frame_Number = 30 then
            Start_Recording := True;
         elsif Recorder.Active and then Recorder.Seconds >= Integer'Value (Env ("PARIS_RECORD")) then
            Recorder.Stop;
            Gtk.Main.Main_Quit;
         end if;
      end if;
      --  PARIS_BURNOUT: throttle against the brake, let go, swerve (testing)
      if Ready and then Env ("PARIS_BURNOUT") /= "" then
         Keys.W := Frame_Number in 21 .. 200;
         Keys.S := Frame_Number in 21 .. 80;
         Keys.Left := Frame_Number in 110 .. 150;
      end if;

      --  Weather changes over about ten seconds; streets dry in a minute
      if Rain_Amount < Rain_Target then
         Rain_Amount := Float'Min (Rain_Target, Rain_Amount + Dt / 10.0);
      else
         Rain_Amount := Float'Max (Rain_Target, Rain_Amount - Dt / 10.0);
      end if;
      if Snow_Amount < Snow_Target then
         Snow_Amount := Float'Min (Snow_Target, Snow_Amount + Dt / 10.0);
      else
         Snow_Amount := Float'Max (Snow_Target, Snow_Amount - Dt / 10.0);
      end if;
      --  snow settles in a minute and a half, and melts slowly
      if Snow_Amount > 0.05 then
         Snow_Cover := Float'Min (1.0, Snow_Cover + Snow_Amount * Dt / 90.0);
      else
         Snow_Cover := Float'Max (0.0, Snow_Cover - Dt / (if Rain_Amount > 0.1 then 60.0 else 400.0));
      end if;
      if Wetness < Rain_Amount then
         Wetness := Float'Min (Rain_Amount, Wetness + Dt / 15.0);
      else
         Wetness := Float'Max (Rain_Amount, Wetness - Dt / 60.0);
      end if;
      --  (the morning round: the dawn comes up slowly)
      Seasons.Update (Dt, Hour, Rain_Amount, Cam_Pos);
      Radio.Update (Dt, Radio_Facts);
      declare
         use Ada.Strings.Unbounded;
         T : constant String := Radio.Text;
      begin
         if To_String (Radio_Shown) /= T then
            Radio_Shown := To_Unbounded_String (T);
            if T = "" then
               Radio_Box.Hide;
            else
               Radio_Box.Set_Markup ("<span background='#101828d8'>" & T & (1 => ASCII.LF) & "</span>");
               Radio_Box.Show;
            end if;
         end if;
      end;
      declare
         N : constant String := Seasons.News;
      begin
         if N /= "" then
            Say (N, 5.0);
         end if;
      end;
      Hour := Hour + Dt * (if Rounds.Clock_Pace > 0.0 then Rounds.Clock_Pace
                           elsif Night_Bus.Clock_Pace > 0.0 then Night_Bus.Clock_Pace else Clock_Rate);
      if Hour >= 24.0 then
         Hour := Hour - 24.0;
         Almanac.Next_Day;
      end if;
      Compute_Lighting;

      Wheel.Poll;
      Wheel_Buttons;

      if Ready then
         declare
            T0 : Ada.Real_Time.Time := Clock_Now;
         begin
            Steps := Positive'Max (1, Integer (Float'Ceiling (Dt / 0.008)));
            if Visiting or else Walking then
               if Visiting then
                  Update_Visit (Dt);
               else
                  Update_Walk (Dt);
               end if;
               for I in 1 .. Steps loop
                  Car.Update (Player, (Handbrake => True, others => <>), Dt / Float (Steps));
               end loop;
            elsif Mode = Driving then
               declare
                  W     : constant Wheel.Input := Wheel.State;
                  Analog : constant Boolean := Wheel.Present;
                  Input : constant Car.Controls :=
                    (Throttle  => Keys.Up or else Keys.W,
                     Brake     => Keys.Down or else Keys.S,
                     Left      => Keys.Left or else Keys.A,
                     Right     => Keys.Right or else Keys.D,
                     Handbrake => Keys.Space or else Wheel.Held (Wheel.Cross),
                     Analog         => Analog,
                     Throttle_Pedal =>
                       Float'Max (W.Throttle, (if Keys.Up or else Keys.W then 1.0 else 0.0)),
                     Brake_Pedal    =>
                       Float'Max (W.Brake, (if Keys.Down or else Keys.S then 1.0 else 0.0)),
                     Clutch_Pedal   => W.Clutch,
                     Steering       =>
                       Float'Max (-1.0, Float'Min (1.0,
                         (W.Steering - Steer_Centre / 450.0) * Steer_Gain)),
                     Manual         => Analog and then Manual_Gearbox,
                     Gear           => Integer (W.Shifter),
                     Need_Clutch    => Need_Clutch,
                     Wet            => Wetness,
                     Snow           => Snow_Cover,
                     Power          => Race.Power,
                     Pull           => Race.Steer_Pull);
                  Was_Grinding : constant Boolean := Player.Grinding;
                  Was_Gear     : constant Integer := Player.Gear;
                  --  on the grid: rev all you like, but the handbrake is on
                  Held  : Car.Controls := Input;
               begin
                  Held.Handbrake := True;
                  for I in 1 .. Steps loop
                     declare
                        Before : constant Float := abs Player.Speed;
                        Loss   : Float;
                     begin
                        Car.Update (Player, (if Race.Frozen then Held else Input), Dt / Float (Steps));
                        Traffic.Collide_Player (Player);
                        Street_Life.Collide (Player);
                        Scenes.Collide (Player);
                        Closures.Collide (Player);
                        Seasons.Collide (Player);
                        Loss := Before - abs Player.Speed;
                        if Player.Bumped and then Loss > 0.0 then
                           Race.Impact (Loss);   --  damage, in a race
                           Taxi.Impact (Loss);   --  an upset passenger
                           Rounds.Impact (Loss); --  a baguette broken
                           Night_Bus.Impact (Loss);
                        end if;
                        if Player.Kerb_Jolt /= 0.0 then
                           Jolt := Player.Kerb_Jolt;
                           Jolt_Side := 0.0;
                           Jolt_Time := 0.25;
                           Jolt_Length := 0.25;
                        elsif Player.Bumped and then Loss > 0.6 and then Jolt_Time < 0.1 then
                           --  a crash: the harder, the bigger the kick (gently
                           --  capped), and the wheel is pushed towards the side
                           --  that hit
                           Jolt := Float'Min (0.5, 0.12 + Loss / 14.0);
                           Jolt_Side := -(Player.Hit_NX * Cos (Player.Heading)
                                          + Player.Hit_NZ * Sin (Player.Heading));
                           Jolt_Time := 0.35;
                           Jolt_Length := 0.35;
                        elsif Player.Bumped and then Before > 1.0 then
                           Scrape := Float'Min (1.0, Before / 8.0);
                        end if;
                     end;
                  end loop;
                  Tyre_Effects.Update (Player, Wetness, Dt);
                  if Player.Grinding and then not Was_Grinding then
                     Announce := Ada.Strings.Unbounded.To_Unbounded_String
                       ("Krrrk! Clutch down to change gear");
                     Announce_Timer := 1.5;
                     Street_Timer := 1.0;
                  elsif Player.Gear /= Was_Gear and then Announce_Timer > 0.0
                    and then Ada.Strings.Unbounded.Index (Announce, "Krrrk") = 1
                  then
                     Announce_Timer := 0.0;
                  end if;
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
                     declare
                        Before : constant Vec3 := Aircraft.Pos;
                     begin
                        Plane.Update (Aircraft, Input, Dt / Float (Steps));
                        Stunts.Update (Before, Aircraft.Pos, Flying => Aircraft.Crashed <= 0.0);
                     end;
                  end loop;
               end;
               declare
                  News : constant String := Stunts.News;
               begin
                  if News /= "" then
                     Announce := Ada.Strings.Unbounded.To_Unbounded_String (News);
                     Announce_Timer := 4.0;
                     Street_Timer := 1.0;
                  end if;
               end;
            end if;
            if Mode /= Flying then
               Stunts.Update (Vec3'(0.0, 0.0, 0.0), Vec3'(0.0, 0.0, 0.0), Flying => False);
            end if;
            Race.Update (Dt, Player);
            Taxi.Update (Dt, Player, Hour, Almanac.Sunday, Rain_Amount);
            Trials.Update (Dt, Player);
            Rounds.Update (Dt, Player, Hour);
            Night_Bus.Update (Dt, Player, Hour);
            if Trials.Holding or else Rounds.Holding or else Night_Bus.Holding then
               Player.Speed := 0.0;   --  the countdown: wait for it
            end if;
            --  the traffic: rush hour on weekdays, quiet late at night
            Density_Wait := Density_Wait - Dt;
            if Density_Wait <= 0.0 and then not Race.Active then
               Density_Wait := 5.0;
               Traffic.Set_Density (Config.Get ("traffic", 1.0) * Traffic_Factor (Hour));
            end if;
            Hall_B.Update (Dt);
            --  the label of the work you stand before
            declare
               use Ada.Strings.Unbounded;
               T : constant String :=
                 (if In_Hall_B and then Walking then Hall_B.Caption (Walk_X, Walk_Z, Walk_Yaw)
                  elsif In_Room and then Walking then Rooms.Status else "");
            begin
               if T /= To_String (Caption_Shown) then
                  Caption_Shown := To_Unbounded_String (T);
                  if T = "" then
                     Caption.Hide;
                  else
                     Caption.Set_Markup (T);
                     Caption.Show;
                  end if;
               end if;
            end;
            Add (C_Physics, T0);
            T0 := Clock_Now;
            Closures.Update (Dt, Hour, Almanac.Saturday, Focus.X, Focus.Z, Focus_Heading);
            Traffic.Update (Dt, Time, Focus.X, Focus.Z, Focus_Heading, Player);
            Street_Life.Update (Dt, Focus.X, Focus.Z);
            Birds.Update (Dt, Focus, Hour,
                          (if Walking then Vec3'(Walk_X, 0.0, Walk_Z) else Vec3'(Player.X, 0.0, Player.Z)));
            Scenes.Update (Dt, Hour, Clock_Rate);
            Postcards.Update (Cam_Pos, Cam_Look,
                              Allowed => not (In_Museum or else In_Hall_B or else In_Room or else Visiting
                                              or else On_Tower or else On_Arc or else Fixed_Camera));
            declare
               News : constant String := Postcards.News;
            begin
               if News /= "" then
                  Announce := Ada.Strings.Unbounded.To_Unbounded_String (News);
                  Announce_Timer := 5.0;
                  Street_Timer := 1.0;
               end if;
            end;
            Stravinsky.Update (Dt);
            Boats.Update (Dt);
            Moulin.Update (Dt);
            Extras.Update (Dt, Hour, Night,
                           (if Walking then Vec3'(Walk_X, 0.0, Walk_Z) else Vec3'(Player.X, 0.0, Player.Z)));
            Pedestrians.Set_Sweepers ((if Env ("PARIS_SWEEPERS") /= "" then 0.5 else Sweeper_Share));
            Pedestrians.Update (Dt, Focus.X, Focus.Z, Focus_Heading, Player);
            Add (C_Traffic, T0);
         end;
         Update_Camera (Dt);
         Race_Overlays;
         Taxi_Overlays;
         Trial_Overlays;
         Round_Overlays;
         Bus_Overlays;
         --  the altimeter: height above the ground, or the water of the Seine
         declare
            Wet : constant Boolean := River.In_Channel (Aircraft.Pos.X, Aircraft.Pos.Z);
            Below : constant Float := Terrain.Height (Aircraft.Pos.X, Aircraft.Pos.Z)
              - (if Wet then River.Depth else 0.0);
         begin
            Altimeter.Set (Mode = Flying and then not Visiting and then Aircraft.Crashed <= 0.0,
                           Aircraft.Pos.Y - Below, Aircraft.Speed * Sin (Aircraft.Pitch), Wet);
         end;
         Scene_Overlays;
      end if;

      Hud_Timer := Hud_Timer + Dt;
      if Hud_Timer >= 0.5 then
         Fps := Float (Fps_Frames) / Hud_Timer;
         Fps_Frames := 0;
         Hud_Timer := 0.0;
         Hud.Set_Markup
           ("<span font_family='monospace' foreground='white' background='#00000088'> "
            & (if Recorder.Active then
                 "<span foreground='#ff4040'>● REC"
                 & Natural'Image (Recorder.Seconds / 60) & ":"
                 & Natural'Image (100 + Recorder.Seconds mod 60) (3 .. 4) & "</span>   "
               else "")
            & (if Walking then " on foot   "
               elsif Mode = Driving and then Show_Panel and then not Visiting then ""
               elsif Mode = Driving then
                 Integer'Image (Integer (abs Player.Speed * 3.6)) & " km/h  "
                 & (case Player.Gear is
                      when -1 => "R ", when 0 => "N ",
                      when others =>
                        (if Wheel.Present and then Manual_Gearbox then " " else "D")
                        & Integer'Image (Player.Gear) (2 .. 2))
                 & Integer'Image (Integer (Player.Rpm / 100.0) * 100) & " rpm   "
               elsif Aircraft.Crashed > 0.0 then
                 " CRASH!   "
               else
                 Integer'Image (Integer (Aircraft.Speed * 3.6)) & " km/h"
                 & Integer'Image (Integer (Aircraft.Pos.Y)) & " m  throttle"
                 & Integer'Image (Integer (Aircraft.Throttle * 100.0)) & "%   ")
            & Integer'Image (Integer (Fps)) & " fps   "
            & Clock_Image & "  " & Almanac.Image
            & (if Storm_On then " storm" elsif Rain_Target > 0.0 then " rain"
               elsif Snow_Target > 0.0 then " snow" else "")
            & "   cars" & Natural'Image (Traffic.Count)
            & "  people" & Natural'Image (Pedestrians.Count)
            & "   F1 keys </span>");
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
               elsif not Show_Street or else In_Museum or else In_Hall_B or else In_Room then ""
               elsif On_Arc then "Arc de Triomphe"
               elsif On_Tower then "Tour Eiffel"
               elsif Walking then Road_Network.Street_At (Walk_X, Walk_Z)
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

      --  The instrument panel, in the car
      declare
         Want : constant Boolean := Ready and then Show_Panel and then Mode = Driving
           and then not Visiting and then not Walking;
      begin
         if Want /= Panel.Get_Visible then
            Panel.Set_Visible (Want);
         end if;
         if Want then
            Instruments.Update
              ((Gear     => Player.Gear,
                Manual   => Wheel.Present and then Manual_Gearbox,
                Grinding => Player.Grinding,
                Lever    => Integer (Wheel.State.Shifter),
                Rpm      => Player.Rpm,
                Kmh      => abs Player.Speed * 3.6,
                Pedals   => Wheel.Present,
                Clutch   => Wheel.State.Clutch,
                Brake    => Wheel.State.Brake,
                Throttle => Wheel.State.Throttle));
         end if;
      end;

      if Ready then
         Sky_Life.Update (Dt, Hour, Night, Cam_Pos);
         --  summer: now and then an afternoon or evening thunderstorm
         if Almanac.Month in 5 .. 9 and then Almanac.Day /= Storm_Rolled and then Hour >= 12.0 then
            Storm_Rolled := Almanac.Day;
            Storm_At := (if Chance < 0.25 then 15.0 + 7.0 * Chance else -1.0);
         end if;
         if Storm_At > 0.0 and then Hour >= Storm_At and then Hour < Storm_At + 0.5
           and then Rain_Target = 0.0 and then Snow_Target = 0.0
         then
            Storm_At := -1.0;
            Storm_On := True;
            Rain_Target := 1.0;
            Storm_Auto := 200.0 + 150.0 * Chance;
         end if;
         if Storm_Auto > 0.0 then
            Storm_Auto := Storm_Auto - Dt;
            if Storm_Auto <= 0.0 then
               --  it passes over
               Storm_On := False;
               Rain_Target := 0.0;
            end if;
         end if;
         Storm.Update (Dt, Storm_On and then Rain_Amount > 0.5, Cam_Pos);
         Ufo.Update (Dt, Hour, Night, Cam_Pos);
         declare
            Look : constant Vec3 := Cam_Look - Cam_Pos;
         begin
            Surprises.Update
              ((Dt => Dt, Hour => Hour, Night => Night, Rain => Rain_Amount,
                Snow => Snow_Cover, Listener => Cam_Pos, Heading => Arctan (Look.X, -Look.Z),
                Car_Pos => (Player.X, Player.Ground, Player.Z), Car_Speed => abs Player.Speed,
                Driving => Mode = Driving and then not Visiting, Visiting => Visiting));
         end;
         if Frame_Number = 100 and then Env ("PARIS_SURPRISE") /= "" then
            Ada.Text_IO.Put_Line (Surprises.Report);
         end if;
         if Frame_Number = 30 and then Env ("PARIS_SURPRISE") /= "" then
            declare
               L : constant String := Env ("PARIS_SURPRISE") & ",";
               First : Positive := L'First;
            begin
               for I in L'Range loop
                  if L (I) = ',' then
                     Surprises.Force (L (First .. I - 1));
                     First := I + 1;
                  end if;
               end loop;
            end;
         end if;
         if Frame_Number = 30 and then Env ("PARIS_UFO") /= "" then
            Ufo.Visit (Cam_Pos);
         end if;
         if Frame_Number = 40 and then Env ("PARIS_STRIKE") /= "" then
            declare
               Look  : constant Vec3 := Cam_Look - Cam_Pos;
               Ahead : constant Vec3 := Normalize (Vec3'(Look.X, 0.0, Look.Z));
            begin
               Storm.Strike_At ((Cam_Pos.X, 0.0, Cam_Pos.Z) + Float'Value (Env ("PARIS_STRIKE")) * Ahead,
                                Cam_Pos);
            end;
         end if;
         Pedestrians.Set_Santas (Christmas, (if Env ("PARIS_SANTA") = "walkers" then 1.0 else 0.035));
         Sleigh.Update (Dt, Christmas, Cam_Pos);
         declare
            Look : constant Vec3 := Cam_Look - Cam_Pos;
         begin
            Halloween.Update (Dt, Spooky, Night, Cam_Pos, (Player.X, Player.Ground, Player.Z),
                              Arctan (Look.X, -Look.Z));
         end;
         if Frame_Number = 40 and then Env ("PARIS_GHOST") /= "" then
            Halloween.Ghost_Here (Cam_Look + (if Env ("PARIS_GHOST") = "near" then 0.0 else 6.0)
                                  * Normalize (Cam_Look - Cam_Pos) + Vec3'(0.0, 1.5, 0.0));
         end if;
         if Sleigh.Visible then
            Sky_Life.Magic_Dust (Sleigh.Dust_Point, Dt);
         end if;
         if Frame_Number = 30 and then Env ("PARIS_SANTA") /= "" then
            if Env ("PARIS_SANTA") = "near" then
               --  across the view, 45 m ahead, from the left
               Sleigh.Start_At (Vec3'(Cam_Look.X, Cam_Pos.Y + 4.0, Cam_Look.Z)
                                + 45.0 * Normalize (Cam_Look - Cam_Pos)
                                - 70.0 * Normalize (Cross (Cam_Look - Cam_Pos, (0.0, 1.0, 0.0))),
                                Arctan (Cam_Look.X - Cam_Pos.X, -(Cam_Look.Z - Cam_Pos.Z))
                                + Ada.Numerics.Pi / 2.0);
            else
               Sleigh.Start_Flight (Cam_Pos, Down_The_Street => True);
            end if;
         end if;
         if Sleigh.Ho_Ho_Now then
            Sound.Ho_Ho (Float'Min (1.0, Sleigh.Jingle * 1.5), Sleigh.Pan);
         end if;
         --  a Santa on the pavement says hello when you drive by
         if Mode = Driving and then not Visiting then
            declare
               Found  : Boolean;
               SX, SZ : Float;
            begin
               Pedestrians.Santa_Near (Player.X, Player.Z, Found, SX, SZ);
               if Found then
                  Sound.Ho_Ho (0.8, ((SX - Player.X) * Cos (Player.Heading)
                                     + (SZ - Player.Z) * Sin (Player.Heading)) / 9.0);
               end if;
            end;
         end if;
         if Frame_Number = 30 and then Env ("PARIS_FIREWORKS") /= "" then
            Sky_Life.Start_Show (Vec3'(Player.X, 0.0, Player.Z) + 500.0 * Car.Forward (Player),
                                 Big => Env ("PARIS_FIREWORKS") = "big");
         end if;
         Update_Senses;
         if Wheel.Present then
            Wheel_Force (Dt);
         end if;
      end if;

      Area.Queue_Render;
      return True;
   exception
      --  something went wrong in one frame: say so (once), and go on with
      --  the next rather than stopping the game
      when E : others =>
         if Tick_Failed < 5 then
            Tick_Failed := Tick_Failed + 1;
            Log_Error ("Error in a frame (" & Clock_Image & (if Mode = Flying then ", flying" else "") & ")", E);
         end if;
         Area.Queue_Render;
         return True;
   end Tick;

   ---------------------------------------------------------------------------
   --  Input
   ---------------------------------------------------------------------------

   --  Paris in 1973 or today: the cars and the street are made again
   procedure Set_Year (In_1973 : Boolean) is
   begin
      Era.Set (In_1973);
      if not Rounds.Active then
         Car.Set_Player_Model (Usual_Model);
      end if;
      Traffic.Reset;
      Street_Life.Clear;
      Say ((if In_1973 then "Paris, 1973" else "Paris, today"), 3.0);
   end Set_Year;

   procedure Set_Key (Key : Gdk.Types.Gdk_Key_Type; Down : Boolean) is
      K : Gdk.Types.Gdk_Key_Type := Key;
   begin
      if K in 16#41# .. 16#5A# then   --  upper case letters
         K := K + 16#20#;
      end if;
      if Confirm_Open and then Down then
         Confirm_Open := False;
         Confirm.Hide;
         if K = 16#FF0D# or else K = 16#FF8D# or else K = 16#68# or else K = 16#79# then
            Go_Home_Now;
         end if;
         return;
      end if;
      if List_Open and then Down and then List_Key (K) then
         return;
      end if;
      if Postcards.Album_Open and then Down and then Postcards.Album_Key (Natural (K)) then
         return;
      end if;
      if In_Room and then Walking and then Down and then Rooms.Key (Natural (K)) then
         return;   --  (the metro: choosing a station)
      end if;
      if Menu_Open and then Down and then Menu_Key (K) then
         return;
      end if;
      --  in the hall's shop: Enter buys a postcard of one of the works
      if Down and then In_Hall_B and then Walking and then (K = 16#FF0D# or else K = 16#FF8D#)
        and then Hall_B.At_Shop (Walk_X, Walk_Z, Walk_Yaw)
      then
         Hall_B.Next_Card (Snap_Name, Snap_Text, Snap_Eye, Snap_Look);
         Snap_Frames := 4;
         Hall_B.Snapping := True;
         return;
      end if;
      --  after the night bus: the line again, or back to the city
      if Down and then not Menu_Open and then Night_Bus."=" (Night_Bus.Phase, Night_Bus.Done)
        and then (K = 16#FF0D# or else K = 16#FF8D# or else K = 16#FF1B#)
      then
         if K = 16#FF1B# then
            End_Race;
         else
            Begin_Bus (0);
         end if;
         return;
      end if;
      --  after the morning round: another morning, or back to the city
      if Down and then not Menu_Open and then Rounds."=" (Rounds.Phase, Rounds.Done)
        and then (K = 16#FF0D# or else K = 16#FF8D# or else K = 16#FF1B#)
      then
         if K = 16#FF1B# then
            End_Race;
         else
            Begin_Round (0);
         end if;
         return;
      end if;
      --  after a time trial: again, or back to the city
      if Down and then not Menu_Open and then Trials."=" (Trials.Phase, Trials.Done)
        and then (K = 16#FF0D# or else K = 16#FF8D# or else K = 16#FF1B#)
      then
         if K = 16#FF1B# then
            End_Race;
         else
            Begin_Trial (0);
         end if;
         return;
      end if;
      --  after a taxi ride: on to the next fare, or end the shift
      if Down and then not Menu_Open
        and then (K = 16#FF0D# or else K = 16#FF8D# or else K = 16#FF1B#)
      then
         declare
            use type Taxi.Phase_Kind;
         begin
            if Taxi.Phase = Taxi.Paid then
               if K = 16#FF1B# then
                  Taxi.End_Shift;
               else
                  Taxi.Next_Fare (Player);
               end if;
               return;
            elsif Taxi.Phase = Taxi.Summary then
               End_Taxi;
               return;
            end if;
         end;
      end if;
      --  the track editor: Enter drops a checkpoint, Backspace takes it back
      if Race.Editing and then Down and then not Walking and then Mode = Driving then
         if K = 16#FF0D# or else K = 16#FF8D# then
            declare
               Ok : Boolean;
            begin
               Race.Edit_Drop (Player.X, Player.Z, Ok);
               if Ok then
                  Say ("Checkpoint" & Natural'Image (Race.Edit_Points), 1.5);
               else
                  Say ("Too close to the last checkpoint", 1.5);
               end if;
            end;
            return;
         elsif K = 16#FF08# then
            Race.Edit_Undo;
            Say ("Checkpoint taken back", 1.5);
            return;
         end if;
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
         when 16#62#   => Keys.B := Down;                     --  b: horn
         when 16#FFE1# | 16#FFE2# => Keys.Shift := Down;      --  shift: run
         when 16#71# =>                                       --  q: on foot
            if Down then
               Toggle_Walk;
            end if;
         when 16#69# =>                                       --  i: instruments
            if Down then
               Show_Panel := not Show_Panel;
            end if;
         when 16#6C# =>                                       --  l: save place
            if Down then
               Save_Here;
            end if;
         when 16#6F# =>                                       --  o: saved places
            if Down then
               Toggle_List;
            end if;
         when 16#65# =>                                       --  e: gearbox
            if Down then
               Manual_Gearbox := not Manual_Gearbox;
               Announce := Ada.Strings.Unbounded.To_Unbounded_String
                 ((if not Wheel.Present then "Gearbox: automatic (manual needs the wheel)"
                   elsif Manual_Gearbox then "Gearbox: manual" else "Gearbox: automatic"));
               Announce_Timer := 1.5;
               Street_Timer := 1.0;
            end if;
         when 16#66# =>                                       --  f
            if Down and then not Visiting then
               Toggle_Flight;
            end if;
         when 16#6B# =>                                       --  k
            if Down then
               Go_To_Kitchen;
            end if;
         when 16#76# =>                                       --  v
            if Down then
               Toggle_Visit;
            end if;
         when 16#30# .. 16#39# =>                             --  0 .. 9
            if Down and then not Visiting then
               Teleport (Places (Integer (K) - 16#30#));
            end if;
         when 16#68# =>                                       --  h: home (asks first)
            if Down and then not Visiting then
               Confirm_Open := True;
               Confirm.Set_Markup
                 ("<span font_family='sans' size='large'><b>Go home?</b>  "
                  & Ada.Strings.Unbounded.To_String (Spawn_Name) & "</span>" & ASCII.LF
                  & "<span foreground='#aab'>Enter or H: yes      Esc: no"
                  & (if Wheel.Present then ASCII.LF & "wheel: X yes, circle no" else "")
                  & "</span>");
               Confirm.Show;
            end if;
         when 16#67# =>                                       --  g
            if Down then
               Show_Compass := not Show_Compass;
               if Show_Compass then
                  Compass_Widget.Show_All;
               else
                  Compass_Widget.Hide;
               end if;
               Navigation.Show (Show_Compass);
            end if;
         when 16#6D# =>                                       --  m
            if Down then
               Sound.Toggle_Mute;
            end if;
         when 16#6A# =>                                       --  j: clear traffic jams
            if Down then
               Traffic.Reset;
               Announce := Ada.Strings.Unbounded.To_Unbounded_String ("Traffic cleared");
               Announce_Timer := 1.5;
               Street_Timer := 1.0;
            end if;
         when 16#78# =>                                       --  x: stop navigating
            if Down then
               Navigation.Clear;
            end if;
         when 16#6E# =>                                       --  n
            if Down then
               Show_Street := not Show_Street;
            end if;
         when 16#70# =>                                       --  p
            if Down then
               --  dry, rain, storm, snow, dry
               Storm_Auto := 0.0;
               if Rain_Target > 0.0 and then not Storm_On then
                  Storm_On := True;
               elsif Rain_Target > 0.0 then
                  Storm_On := False;
                  Rain_Target := 0.0;
                  Snow_Target := 1.0;
               elsif Snow_Target > 0.0 then
                  Snow_Target := 0.0;
               else
                  Rain_Target := 1.0;
               end if;
            end if;
         when 16#FF55# =>                                     --  PgUp
            Keys.Page_Up := Down;
            if Down and then not Visiting then
               Zoom_By (1.0 / 1.25);
            end if;
         when 16#FF56# =>                                     --  PgDn
            Keys.Page_Down := Down;
            if Down and then not Visiting then
               Zoom_By (1.25);
            end if;
         when 16#2B# | 16#3D# | 16#FFAB# =>                   --  + = keypad+
            if Down then
               Zoom_By (1.0 / 1.25);
            end if;
         when 16#2D# | 16#FFAD# =>                            --  - keypad-
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
                  Almanac.Next_Day;
               end if;
            end if;
         when 16#72# =>                                       --  r
            if Down then
               if Mode = Flying then
                  Plane.Start (Aircraft, Aircraft.Pos.X, Aircraft.Pos.Z, Aircraft.Heading);
               elsif not Visiting and then not Race.Active then
                  Back_On_The_Road;
               end if;
            end if;
         when 16#FFC9# =>                                     --  F12: photo
            if Down then
               Take_Photo := True;
            end if;
         when 16#FFC6# =>                                     --  F9: record
            if Down then
               if Recorder.Active then
                  Recorder.Stop;
                  Announce := Ada.Strings.Unbounded.To_Unbounded_String (Recorder.Message);
                  Announce_Timer := 4.0;
                  Street_Timer := 1.0;
               else
                  Start_Recording := True;   --  at the next frame, its size
               end if;
            end if;
         when 16#7A# =>                                       --  z: the radio
            if Down then
               Radio.Toggle (Radio_Facts);
               if not Radio.On then
                  Say ("Radio off", 1.5);
               end if;
            end if;
         when 16#75# =>                                       --  u: Paris in 1973, or today
            if Down then
               Set_Year (not Era.In_1973);
            end if;
         when 16#79# =>                                       --  y: one day later
            if Down then
               Almanac.Next_Day;
               Say (Almanac.Image & Integer'Image (Almanac.Year), 1.5);
            end if;
         when 16#FFC1# =>                                     --  F4: the postcards
            if Down then
               Help.Hide;
               Postcards.Toggle_Album;
            end if;
         when 16#FFC0# =>                                     --  F3: find an address
            if Down then
               Open_Search;
            end if;
         when 16#FFBE# =>                                     --  F1: keys
            if Down then
               if Help.Get_Visible then
                  Help.Hide;
               else
                  if List_Open then
                     Toggle_List;
                  end if;
                  Help.Set_Markup (Help_Text);
                  Help.Show;
               end if;
            end if;
         when 16#FFBF# =>                                     --  F2: games
            if Down then
               Toggle_Menu;   --  (over the results, if they are up)
            end if;
         when 16#FF1B# =>                                     --  Escape
            if Down then
               if Results_Open then
                  --  the results away; the race stays (F2 for the menu)
                  Results_Open := False;
                  Game_Menu.Hide;
               elsif (Race.Active or else Taxi.Active) and then not (Walking and then Captured) then
                  Toggle_Menu;   --  not out of the game by mistake
               elsif Walking and then Captured then
                  Capture_Mouse (False);   --  the mouse back (click to look again)
               elsif Help.Get_Visible then
                  Help.Hide;
               else
                  Gtk.Main.Main_Quit;
               end if;
            end if;
         when others => null;
      end case;
   end Set_Key;

   ---------------------------------------------------------------------------
   --  F3: type a street (and a number), Enter sets the GPS
   ---------------------------------------------------------------------------

   procedure Refresh_Search is
      use Ada.Strings.Unbounded;
      LF : constant String := (1 => ASCII.LF);
      T  : Unbounded_String;
      Here_X : constant Float := (if Walking then Walk_X else Player.X);
      Here_Z : constant Float := (if Walking then Walk_Z else Player.Z);
   begin
      Addresses.Search (To_String (Search_Text), Here_X, Here_Z, Search_Hits, Search_N);
      Search_Sel := Positive'Max (1, Positive'Min (Search_Sel, Natural'Max (1, Search_N)));
      Append (T, "<span font_family='sans'><b><span foreground='#ffd27a'>Find an address</span></b>"
              & LF & "<span size='large' background='#ffffff22'> " & Escape (To_String (Search_Text))
              & "&#x2502; </span>" & LF);
      if Length (Search_Text) > 0 and then Search_N = 0 then
         Append (T, LF & "<span foreground='#aab'>  nothing found</span>");
      end if;
      for I in 1 .. Search_N loop
         declare
            L : constant String := Escape (Search_Hits (I).Label (1 .. Search_Hits (I).Last));
         begin
            Append (T, LF & (if I = Search_Sel then "<span background='#3a6fd8'> " & L & " </span>" else " " & L));
         end;
      end loop;
      Append (T, LF & LF & "<span foreground='#aab' size='small'>street name and number, in any order"
              & LF & "up/down: choose    Enter: GPS there    Esc: close</span></span>");
      Search_Box.Set_Markup (To_String (T));
   end Refresh_Search;

   procedure Open_Search is
   begin
      Search_Open := True;
      Search_Sel := 1;
      Help.Hide;
      Refresh_Search;
      Search_Box.Show;
   end Open_Search;

   procedure Close_Search is
   begin
      Search_Open := False;
      Search_Box.Hide;
   end Close_Search;

   --  A key while the box is open (always used)
   procedure Search_Key (Event : Gdk.Event.Gdk_Event_Key) is
      use Ada.Strings.Unbounded;
      K : constant Gdk.Types.Gdk_Key_Type := Event.Keyval;
   begin
      case K is
         when 16#FF1B# | 16#FFC0# =>                          --  Escape, F3
            Close_Search;
            return;
         when 16#FF0D# | 16#FF8D# =>                          --  Enter
            if Search_N > 0 then
               declare
                  H : constant Addresses.Result := Search_Hits (Search_Sel);
               begin
                  Navigation.Set_Destination (H.Label (1 .. H.Last), H.X, H.Z);
                  if not Show_Compass then
                     Set_Key (16#67#, True);   --  the minimap
                  end if;
               end;
               Close_Search;
            end if;
            return;
         when 16#FF52# =>                                     --  up
            if Search_Sel > 1 then
               Search_Sel := Search_Sel - 1;
            end if;
         when 16#FF54# =>                                     --  down
            if Search_Sel < Search_N then
               Search_Sel := Search_Sel + 1;
            end if;
         when 16#FF08# =>                                     --  Backspace: one character
            declare
               S : constant String := To_String (Search_Text);
               L : Natural := S'Last;
            begin
               if L >= S'First then
                  --  back over the continuation bytes of a UTF-8 character
                  while L > S'First and then Character'Pos (S (L)) in 16#80# .. 16#BF# loop
                     L := L - 1;
                  end loop;
                  Search_Text := To_Unbounded_String (S (S'First .. L - 1));
               end if;
            end;
            Search_Sel := 1;
         when others =>
            declare
               C : constant Glib.Gunichar := Gdk.Keyval.To_Unicode (K);
            begin
               if Glib.">=" (C, 32) and then Length (Search_Text) < 60 then
                  declare
                     Buf  : String (1 .. 6);
                     Last : Natural;
                  begin
                     Glib.Unicode.Unichar_To_UTF8 (C, Buf, Last);
                     Append (Search_Text, Buf (1 .. Last));
                     Search_Sel := 1;
                  end;
               else
                  return;
               end if;
            end;
      end case;
      Refresh_Search;
   end Search_Key;

   function Key_Press
     (Self : access Gtk.Widget.Gtk_Widget_Record'Class;
      Event : Gdk.Event.Gdk_Event_Key) return Boolean
   is
      pragma Unreferenced (Self);
      use type Gdk.Types.Gdk_Modifier_Type;
   begin
      if Search_Open then
         Search_Key (Event);
         return True;
      end if;
      --  Shift + 1 .. 0 (the digit row, whatever the keyboard layout):
      --  navigate to that place
      if (Event.State and Gdk.Types.Shift_Mask) /= 0
        and then Event.Hardware_Keycode in 10 .. 19
      then
         declare
            P : constant Place := Places ((Integer (Event.Hardware_Keycode) - 9) mod 10);
            X, Z : Long_Float;
         begin
            Geo.To_Local (P.Lat, P.Lon, X, Z);
            Navigation.Set_Destination (Ada.Strings.Unbounded.To_String (P.Name),
                                        Float (X), Float (Z));
         end;
         return True;
      end if;
      --  Shift + Y: one day earlier
      if (Event.State and Gdk.Types.Shift_Mask) /= 0
        and then (Event.Keyval = 16#59# or else Event.Keyval = 16#79#)
      then
         Almanac.Previous_Day;
         Say (Almanac.Image & Integer'Image (Almanac.Year), 1.5);
         return True;
      end if;
      --  Shift + H: home is here
      if (Event.State and Gdk.Types.Shift_Mask) /= 0
        and then (Event.Keyval = 16#48# or else Event.Keyval = 16#68#)
      then
         Save_Home_Here;
         return True;
      end if;
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

   --  Mouse: drag with the left button to look around in the apartment
   function Button_Press
     (Self  : access Gtk.Widget.Gtk_Widget_Record'Class;
      Event : Gdk.Event.Gdk_Event_Button) return Boolean
   is
      pragma Unreferenced (Self);
   begin
      if Walking and then not Captured then
         Capture_Mouse (True);
      end if;
      if Event.Button = 1 then
         Dragging := True;
         Drag_X := Float (Event.X);
         Drag_Y := Float (Event.Y);
      end if;
      return True;
   end Button_Press;

   function Button_Release
     (Self  : access Gtk.Widget.Gtk_Widget_Record'Class;
      Event : Gdk.Event.Gdk_Event_Button) return Boolean
   is
      pragma Unreferenced (Self);
   begin
      if Event.Button = 1 then
         Dragging := False;
      end if;
      return True;
   end Button_Release;

   function Motion
     (Self  : access Gtk.Widget.Gtk_Widget_Record'Class;
      Event : Gdk.Event.Gdk_Event_Motion) return Boolean
   is
      pragma Unreferenced (Self);
      X : constant Float := Float (Event.X);
      Y : constant Float := Float (Event.Y);
   begin
      if Dragging and then Visiting then
         Eye_Yaw := Eye_Yaw - (X - Drag_X) * 0.004;
         Eye_Pitch := Float'Max (-1.2, Float'Min (1.2, Eye_Pitch + (Y - Drag_Y) * 0.004));
      end if;
      if Walking and then Captured then
         declare
            W  : constant System.Address := To_Address (Event.Window);
            OX, OY : Interfaces.C.int;
            CX : constant Float := Float (Area.Get_Allocated_Width) / 2.0;
            CY : constant Float := Float (Area.Get_Allocated_Height) / 2.0;
         begin
            if abs (X - CX) > 0.5 or else abs (Y - CY) > 0.5 then
               Walk_Yaw := Walk_Yaw + (X - CX) * 0.0025;
               Walk_Pitch := Float'Max (-1.4, Float'Min (1.4, Walk_Pitch - (Y - CY) * 0.0025));
               if W /= System.Null_Address and then Event.Device /= System.Null_Address then
                  Gdk_Window_Get_Origin (W, OX, OY);
                  Gdk_Device_Warp (Event.Device, Gdk_Window_Get_Screen (W),
                                   OX + Interfaces.C.int (CX), OY + Interfaces.C.int (CY));
               end if;
            end if;
         end;
      end if;
      Drag_X := X;
      Drag_Y := Y;
      return True;
   end Motion;

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
      Credit  : Gtk.Label.Gtk_Label;
      Id      : Glib.Guint;
   begin
      Gtk.Main.Init;
      Gtkada.Bindings.Set_On_Exception (Callback_Failed'Access);
      Config.Load;
      Read_Home;
      Terrain.Load;
      Hour := Config.Get ("start_hour", 18.0);
      declare
         D : constant String := Config.Get ("date", "today");
      begin
         if D'Length = 10 and then D (D'First + 4) = '-' then
            Almanac.Set_Date (Integer'Value (D (D'First .. D'First + 3)),
                              Integer'Value (D (D'First + 5 .. D'First + 6)),
                              Integer'Value (D (D'First + 8 .. D'First + 9)));
         end if;
      exception
         when Constraint_Error =>
            Ada.Text_IO.Put_Line ("~/.deriverc: date should look like 2026-12-24");
      end;
      if Env ("PARIS_DATE") /= "" then
         declare
            D : constant String := Env ("PARIS_DATE");
         begin
            Almanac.Set_Date (Integer'Value (D (D'First .. D'First + 3)),
                              Integer'Value (D (D'First + 5 .. D'First + 6)),
                              Integer'Value (D (D'First + 8 .. D'First + 9)));
         end;
      end if;
      Clock_Rate := Config.Get ("time_speed", 1.0) / 60.0;
      Show_Compass := Config.Get ("compass", True);
      Show_Street := Config.Get ("street_names", True);
      Show_Panel := Config.Get ("instruments", True);
      declare
         M : constant String := Config.Get ("car", "modern");
      begin
         Car.Set_Player_Model ((if M = "2cv" then Car.Deux_Chevaux elsif M = "ds" then Car.DS
                                elsif M = "r4" then Car.R4 else Car.Modern));
         if Config.Get ("era", "today") = "1973" or else Env ("PARIS_1973") /= "" then
            Era.Set (True);
            Car.Set_Player_Model (Car.DS);
         end if;
      end;
      declare
         X : constant String := Config.Get ("christmas", "auto");
      begin
         Xmas_Setting := (if X = "yes" then 'y' elsif X = "no" then 'n' else 'a');
      end;
      declare
         X : constant String := Config.Get ("halloween", "auto");
      begin
         Spooky_Setting := (if X = "yes" then 'y' elsif X = "no" then 'n' else 'a');
      end;
      Traffic.Set_Density (Config.Get ("traffic", 1.0));
      Pedestrians.Set_Density (Config.Get ("pedestrians", 1.0));
      Pedestrians.Set_Keep_Out (Race.On_Course'Access);
      Sound.Set_Volume (Config.Get ("volume", 0.8));
      Saved_Places.Load;
      Ada.Numerics.Float_Random.Reset (Dice);
      Pedestrians.Set_Santas (Christmas, (if Env ("PARIS_SANTA") = "walkers" then 1.0 else 0.035));
      Show_Markers;
      Manual_Gearbox := Config.Get ("manual_gearbox", True);
      Need_Clutch := Config.Get ("clutch", True);
      Steer_Gain := Config.Get ("steering", 1.0);
      Steer_Centre := Config.Get ("wheel_centre", 0.0);
      Wheel.Set_Gain (Config.Get ("force_feedback", 0.6));
      if Env ("PARIS_NOWHEEL") = "" then
         Wheel.Open;
      end if;

      Gtk.Window.Gtk_New (Window);
      Window.Set_Title ("Dérive");
      Window.Set_Default_Size (1600, 900);
      Window.On_Destroy (On_Destroy'Access);
      Window.On_Key_Press_Event (Key_Press'Access);
      Window.On_Key_Release_Event (Key_Release'Access);
      Window.Add_Events (Gdk.Event.Scroll_Mask or Gdk.Event.Smooth_Scroll_Mask
                         or Gdk.Event.Button_Press_Mask or Gdk.Event.Button_Release_Mask
                         or Gdk.Event.Button_Motion_Mask);
      Window.On_Scroll_Event (Scroll'Access);
      Window.On_Button_Press_Event (Button_Press'Access);
      Window.On_Button_Release_Event (Button_Release'Access);
      Window.On_Motion_Notify_Event (Motion'Access);

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

      Gtk.Label.Gtk_New (Help);
      Help.Set_Halign (Gtk.Widget.Align_Center);
      Help.Set_Valign (Gtk.Widget.Align_Center);
      Help.Set_No_Show_All (True);
      Overlay.Add_Overlay (Help);

      Gtk.Label.Gtk_New (Place_List);
      Place_List.Set_Halign (Gtk.Widget.Align_Center);
      Place_List.Set_Valign (Gtk.Widget.Align_Center);
      Place_List.Set_No_Show_All (True);
      Overlay.Add_Overlay (Place_List);

      Gtk.Label.Gtk_New (Search_Box);
      Search_Box.Set_Halign (Gtk.Widget.Align_Center);
      Search_Box.Set_Valign (Gtk.Widget.Align_Start);
      Search_Box.Set_Margin_Top (80);
      Search_Box.Set_No_Show_All (True);
      Overlay.Add_Overlay (Search_Box);
      Overlay.Add_Overlay (Postcards.Album);

      Gtk.Label.Gtk_New (Confirm);
      Confirm.Set_Halign (Gtk.Widget.Align_Center);
      Confirm.Set_Valign (Gtk.Widget.Align_Center);
      Confirm.Set_No_Show_All (True);
      Overlay.Add_Overlay (Confirm);

      Gtk.Label.Gtk_New (Caption);
      Caption.Set_Halign (Gtk.Widget.Align_Center);
      Caption.Set_Valign (Gtk.Widget.Align_End);
      Caption.Set_Margin_Bottom (60);
      Caption.Set_Justify (Gtk.Enums.Justify_Center);
      Caption.Set_No_Show_All (True);
      Overlay.Add_Overlay (Caption);

      Gtk.Label.Gtk_New (Game_Menu);
      Game_Menu.Set_Halign (Gtk.Widget.Align_Center);
      Game_Menu.Set_Valign (Gtk.Widget.Align_Center);
      Game_Menu.Set_No_Show_All (True);
      Overlay.Add_Overlay (Game_Menu);

      Gtk.Label.Gtk_New (Race_Hud);
      Race_Hud.Set_Halign (Gtk.Widget.Align_Center);
      Race_Hud.Set_Valign (Gtk.Widget.Align_Start);
      Race_Hud.Set_Margin_Top (70);
      Race_Hud.Set_No_Show_All (True);
      Overlay.Add_Overlay (Race_Hud);

      Gtk.Label.Gtk_New (Radio_Box);
      Radio_Box.Set_Halign (Gtk.Widget.Align_Center);
      Radio_Box.Set_Valign (Gtk.Widget.Align_End);
      Radio_Box.Set_Margin_Bottom (60);
      Radio_Box.Set_No_Show_All (True);
      Overlay.Add_Overlay (Radio_Box);

      Gtk.Label.Gtk_New (Race_Banner);
      Race_Banner.Set_Halign (Gtk.Widget.Align_Center);
      Race_Banner.Set_Valign (Gtk.Widget.Align_Start);   --  above the car
      Race_Banner.Set_Margin_Top (120);
      Race_Banner.Set_Justify (Gtk.Enums.Justify_Center);
      Race_Banner.Set_No_Show_All (True);
      Overlay.Add_Overlay (Race_Banner);

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
            & " box-shadow: 0 0 0 3px #2f6b45, 0 3px 8px rgba(0,0,0,0.5); }"
            & ".caption { background-color: rgba(250,250,248,0.94); color: #1a1a1a;"
            & " font-size: 15px; padding: 10px 20px; border-radius: 2px;"
            & " border-left: 4px solid #d97757; }"
            & ".help { background-color: rgba(10,14,24,0.88); color: #f2f2f2;"
            & " font-size: 15px; padding: 18px 26px; border-radius: 10px;"
            & " border: 1px solid rgba(255,255,255,0.25); }",
            null);
         Gtk.Style_Context.Get_Style_Context (Help).Add_Provider
           (Gtk.Css_Provider."+" (Css), Gtk.Style_Provider.Priority_Application);
         Gtk.Style_Context.Get_Style_Context (Help).Add_Class ("help");
         Gtk.Style_Context.Get_Style_Context (Place_List).Add_Provider
           (Gtk.Css_Provider."+" (Css), Gtk.Style_Provider.Priority_Application);
         Gtk.Style_Context.Get_Style_Context (Place_List).Add_Class ("help");
         Gtk.Style_Context.Get_Style_Context (Game_Menu).Add_Provider
           (Gtk.Css_Provider."+" (Css), Gtk.Style_Provider.Priority_Application);
         Gtk.Style_Context.Get_Style_Context (Game_Menu).Add_Class ("help");
         Gtk.Style_Context.Get_Style_Context (Caption).Add_Provider
           (Gtk.Css_Provider."+" (Css), Gtk.Style_Provider.Priority_Application);
         Gtk.Style_Context.Get_Style_Context (Caption).Add_Class ("caption");
         Gtk.Style_Context.Get_Style_Context (Confirm).Add_Provider
           (Gtk.Css_Provider."+" (Css), Gtk.Style_Provider.Priority_Application);
         Gtk.Style_Context.Get_Style_Context (Confirm).Add_Class ("help");
         Gtk.Style_Context.Get_Style_Context (Search_Box).Add_Provider
           (Gtk.Css_Provider."+" (Css), Gtk.Style_Provider.Priority_Application);
         Gtk.Style_Context.Get_Style_Context (Search_Box).Add_Class ("help");
         Gtk.Style_Context.Get_Style_Context (Postcards.Album).Add_Provider
           (Gtk.Css_Provider."+" (Css), Gtk.Style_Provider.Priority_Application);
         Gtk.Style_Context.Get_Style_Context (Postcards.Album).Add_Class ("help");
         Gtk.Style_Context.Get_Style_Context (Sign).Add_Provider
           (Gtk.Css_Provider."+" (Css), Gtk.Style_Provider.Priority_Application);
         Gtk.Style_Context.Get_Style_Context (Sign).Add_Class ("street-sign");
      end;
      Overlay.Add_Overlay (Sign);

      declare
         Sign_W : constant Gtk.Widget.Gtk_Widget := Limit_Sign.Create;
      begin
         Sign_W.Set_Halign (Gtk.Widget.Align_Start);
         Sign_W.Set_Valign (Gtk.Widget.Align_End);
         Sign_W.Set_Margin_Start (272);
         Sign_W.Set_Margin_Bottom (40);
         Overlay.Add_Overlay (Sign_W);
      end;

      declare
         Alt_W : constant Gtk.Widget.Gtk_Widget := Altimeter.Create;
      begin
         Alt_W.Set_Halign (Gtk.Widget.Align_Start);
         Alt_W.Set_Valign (Gtk.Widget.Align_Center);
         Alt_W.Set_Margin_Start (12);
         Overlay.Add_Overlay (Alt_W);
      end;

      Panel := Instruments.Create;
      Panel.Set_No_Show_All (True);
      Overlay.Add_Overlay (Panel);
      Compass_Widget := Compass.Create;
      Overlay.Add_Overlay (Compass_Widget);
      Overlay.Add_Overlay (Navigation.Create_Minimap);
      Overlay.Add_Overlay (Navigation.Create_Instructions);

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
      if not Show_Compass then
         Compass_Widget.Hide;
         Navigation.Show (False);
      end if;
      --  no sound when making screenshots, unless asked for
      if Env ("PARIS_SHOT") = "" or else Env ("PARIS_SOUND") /= "" then
         Sound.Start;
      end if;
      Gtk.Main.Main;
      Race.Stop;
      Recorder.Stop;   --  quitting while recording keeps the video
      Sound.Stop;
   end Run;

end Game;
