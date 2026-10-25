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
with Gdk.Rectangle;
with Gdk.Frame_Clock;
with Gdk.Types;
with Glib;
with Gtk.Css_Provider;
with Gtk.Enums;
with Gtk.Label;
with Gtk.Main;
with Gtk.Box;
with Gtk.Offscreen_Window;
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
with Funicular;
with Geo;
with Halloween;
with Instruments;
with Landscape;
with GL;
with GL_Area;
with Math3D;
with Museum;
with Motorboat;
with Hud_Layer;
with Navigation;
with Notes;
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

--  The game: the window, the world and everything in it, frame by frame.
--  The biggest pieces are in their own files (separate bodies, with all of
--  this package in view): game-tick.adb (each frame's simulation, and the
--  test switches), game-render.adb (drawing), game-set_key.adb (the keys),
--  game-run.adb and game-realize.adb (starting up), game-update_camera.adb,
--  game-update_walk.adb and game-toggle_walk.adb (on foot), and
--  game-help_text.adb, game-refresh_menu.adb and game-menu_choose.adb (F1
--  and the F2 menu).
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

   --  The graphics level (graphics = low | medium | high in ~/.deriverc):
   --  the shadow map's size, the multisampling, and the share of the
   --  window's pixels the world is drawn at (then scaled up)
   Shadow_Size   : GLsizei := 4096;
   Render_Scale  : Float := 1.0;
   Graphics_Changed : Boolean := False;   --  (the shadow map and buffers made again)
   Shadow_Extent : constant := 260.0;   --  half-size of the shadow box (m)
   Samples       : GLsizei := 4;

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
   --  The panels: laid out in an offscreen window of the 3D view's size,
   --  drawn over it in OpenGL (Draw_Hud, Hud_Layer)
   Hud_Win  : Gtk.Offscreen_Window.Gtk_Offscreen_Window;
   Hud_Over : Gtk.Overlay.Gtk_Overlay;
   Hud_Base : Gtk.Box.Gtk_Box;
   Hud_W, Hud_H : Integer := 0;
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
   Boating      : Boolean := False;          --  in the hired motorboat, the car parked
   Parked       : Car.State;                 --  where the car was left meanwhile

   --  Has the city been built (make tiles)?  A fresh checkout has none
   function City_Built return Boolean is
      use Ada.Directories;
      Search_It : Search_Type;
      Found : Boolean := False;
   begin
      Start_Search (Search_It, "tiles", "t_*.bin", (Ordinary_File => True, others => False));
      Found := More_Entries (Search_It);
      End_Search (Search_It);
      return Found;
   exception
      when others =>
         return False;
   end City_Built;

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
   Confirm_Quit : Boolean := False;   --  the box asks "quit?", not "go home?"
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
   On_Funicular : Boolean := False;  --  in a cabin of the Funiculaire de Montmartre
   Cabin_Floor  : Float := 0.0;
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

   --  Home (V): standing in a top-floor apartment on Place Saint-Sulpice.
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
   Profiling : Boolean := False;      --  GPU timer queries (PARIS_PROFILE=1)
   Profiling_Cpu : Boolean := False;  --  CPU times only, no stalls (PARIS_PROFILE=cpu)
   Dt_Hist   : array (0 .. 10) of Natural := (others => 0);   --  4 ms buckets
   type Cpu_Part is (C_Physics, C_Traffic, C_Lights, C_World, C_Tick, C_Render);
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

   --  At a lower render scale with multisampling, the samples are first
   --  resolved into this (at the scaled size), then stretched to the window
   Mid_FBO, Mid_Color : aliased GLuint := 0;
   Mid_W, Mid_H : Integer := 0;

   procedure Ensure_Mid (W, H : Integer) is
   begin
      if W = Mid_W and then H = Mid_H then
         return;
      end if;
      if Mid_FBO /= 0 then
         glDeleteFramebuffers (1, Mid_FBO'Address);
         glDeleteRenderbuffers (1, Mid_Color'Address);
      end if;
      glGenFramebuffers (1, Mid_FBO'Address);
      glBindFramebuffer (GL_FRAMEBUFFER, Mid_FBO);
      glGenRenderbuffers (1, Mid_Color'Address);
      glBindRenderbuffer (GL_RENDERBUFFER, Mid_Color);
      glRenderbufferStorageMultisample (GL_RENDERBUFFER, 0, GL_RGBA8, GLsizei (W), GLsizei (H));
      glFramebufferRenderbuffer (GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, Mid_Color);
      Mid_W := W;
      Mid_H := H;
   end Ensure_Mid;

   --  graphics = low | medium | high
   procedure Set_Graphics (Level : String) is
   begin
      if Level = "low" then
         Shadow_Size := 1024;
         Samples := 0;
         Render_Scale := 0.75;
      elsif Level = "medium" then
         Shadow_Size := 2048;
         Samples := 2;
         Render_Scale := 1.0;
      else
         Shadow_Size := 4096;
         Samples := 4;
         Render_Scale := 1.0;
      end if;
   end Set_Graphics;

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
      Notes.Say ("Skyline landmarks:" & Count'Image);
   end Load_Skyline;

   procedure Realize (Widget, Data : System.Address) with Convention => C;
   procedure Realize (Widget, Data : System.Address) is separate;

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
                elsif On_Funicular then Cabin_Floor
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

   --  The panels' picture, over the 3D view
   Hud_Surface : Cairo.Cairo_Surface := Cairo.Null_Surface;
   Surf_W, Surf_H : Integer := 0;
   --  what changed in the panels' window since the picture was last made
   --  (GTK tells: the damage event), redrawn and uploaded alone
   Dirty : Boolean := True;
   Dirty_X0, Dirty_Y0, Dirty_X1, Dirty_Y1 : Integer := 0;

   function Hud_Damaged
     (Self  : access Gtk.Widget.Gtk_Widget_Record'Class;
      Event : Gdk.Event.Gdk_Event_Expose) return Boolean
   is
      pragma Unreferenced (Self);
      A : constant Gdk.Rectangle.Gdk_Rectangle := Event.Area;
      X0 : constant Integer := Integer (A.X);
      Y0 : constant Integer := Integer (A.Y);
      X1 : constant Integer := Integer (A.X) + Integer (A.Width);
      Y1 : constant Integer := Integer (A.Y) + Integer (A.Height);
   begin
      if not Dirty then
         Dirty := True;
         Dirty_X0 := X0;
         Dirty_Y0 := Y0;
         Dirty_X1 := X1;
         Dirty_Y1 := Y1;
      else
         Dirty_X0 := Integer'Min (Dirty_X0, X0);
         Dirty_Y0 := Integer'Min (Dirty_Y0, Y0);
         Dirty_X1 := Integer'Max (Dirty_X1, X1);
         Dirty_Y1 := Integer'Max (Dirty_Y1, Y1);
      end if;
      return False;
   end Hud_Damaged;

   procedure Draw_Hud (W, H : Integer) is
      use Cairo;
      use type Gtk.Offscreen_Window.Gtk_Offscreen_Window;
      Cr : Cairo_Context;
      use Gtk.Widget.Widget_List;
      Children : Glist;
      Item     : Glist;
   begin
      if Hud_Win = null then
         return;
      end if;
      if Hud_Surface = Null_Surface or else W /= Surf_W or else H /= Surf_H then
         if Hud_Surface /= Null_Surface then
            Cairo.Surface.Destroy (Hud_Surface);
         end if;
         Hud_Surface := Cairo.Image_Surface.Create
           (Cairo.Image_Surface.Cairo_Format_ARGB32, Glib.Gint (W), Glib.Gint (H));
         Surf_W := W;
         Surf_H := H;
         Dirty := True;
         Dirty_X0 := 0;
         Dirty_Y0 := 0;
         Dirty_X1 := W;
         Dirty_Y1 := H;
      end if;
      --  lay out what changed (a label with a new text) before it is drawn
      Hud_Win.Check_Resize;
      if not Dirty then
         Hud_Layer.Draw (Cairo.Image_Surface.Get_Data_Generic (Hud_Surface), W, H,
                         Natural (Cairo.Image_Surface.Get_Stride (Hud_Surface)), 0, 0, 0, 0);
         return;
      end if;
      declare
         X0 : constant Integer := Integer'Max (0, Dirty_X0);
         Y0 : constant Integer := Integer'Max (0, Dirty_Y0);
         X1 : constant Integer := Integer'Min (W, Dirty_X1);
         Y1 : constant Integer := Integer'Min (H, Dirty_Y1);
      begin
         Dirty := False;
         Cr := Create (Hud_Surface);
         Rectangle (Cr, Glib.Gdouble (X0), Glib.Gdouble (Y0), Glib.Gdouble (X1 - X0), Glib.Gdouble (Y1 - Y0));
         Clip (Cr);
         Set_Operator (Cr, Cairo_Operator_Clear);
         Paint (Cr);
         Set_Operator (Cr, Cairo_Operator_Over);
         Children := Hud_Over.Get_Children;
         Item := Children;
         while Item /= Null_List loop
            declare
               Child : constant Gtk.Widget.Gtk_Widget := Get_Data (Item);
               X, Y  : Glib.Gint;
               Ok    : Boolean;
            begin
               if Gtk.Widget."/=" (Child, Gtk.Widget.Gtk_Widget (Hud_Base)) and then Child.Get_Mapped then
                  Child.Translate_Coordinates (Hud_Over, 0, 0, X, Y, Ok);
                  --  only those in the changed part
                  if Integer (X) < X1 and then Integer (Y) < Y1
                    and then Integer (X) + Integer (Child.Get_Allocated_Width) > X0
                    and then Integer (Y) + Integer (Child.Get_Allocated_Height) > Y0
                  then
                     Save (Cr);
                     Translate (Cr, Glib.Gdouble (X), Glib.Gdouble (Y));
                     Child.Draw (Cr);
                     Restore (Cr);
                  end if;
               end if;
            end;
            Item := Next (Item);
         end loop;
         Free (Children);
         Destroy (Cr);
         Cairo.Surface.Flush (Hud_Surface);
         Hud_Layer.Draw (Cairo.Image_Surface.Get_Data_Generic (Hud_Surface), W, H,
                         Natural (Cairo.Image_Surface.Get_Stride (Hud_Surface)), X0, Y0, X1, Y1);
      end;
   end Draw_Hud;

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
   is separate;

   ---------------------------------------------------------------------------
   --  Simulation tick
   ---------------------------------------------------------------------------

   Min_Zoom : constant := 0.35;
   Max_Zoom : constant := 8.0;

   procedure Zoom_By (Factor : Float) is
   begin
      Zoom := Float'Max (Min_Zoom, Float'Min (Max_Zoom, Zoom * Factor));
   end Zoom_By;

   procedure Update_Camera (Dt : Float) is separate;

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
         Announce := Ada.Strings.Unbounded.To_Unbounded_String ("Place Saint-Sulpice");
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

   procedure Toggle_Walk is separate;

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

   procedure Update_Walk (Dt : Float) is separate;

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
   function Help_Text return String is separate;

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
   type Menu_Level is (Games, Racing, Tracks, Taxi_Menu, Trials_Menu, Rounds_Menu, Bus_Menu, Settings_Menu);
   Level : Menu_Level := Games;
   type Menu_Item is
     (Go_Racing, Go_Taxi, Go_Trials, Go_Rounds, Go_Bus, Go_Settings, Go_Free, Race_Again, Leave_Race, Street_Race, Random_Race,
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
            Add (Go_Settings);
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
         when Tracks | Trials_Menu | Rounds_Menu | Bus_Menu | Settings_Menu =>
            null;   --  the tracks, runs or bakeries themselves (see Menu_Items)
      end case;
   end List_Items;

   type Settings_Kind is
     (S_Volume, S_Traffic, S_People, S_Graphics, S_Car, S_Time_Speed, S_Limits,
      S_Gearbox, S_Compass, S_Names);

   --  F2, Settings: what can be changed while playing (game-setting_*.adb)
   function Traffic_Factor (H : Float) return Float;
   function Setting_Count return Natural;
   function Setting_Line (I : Positive) return String;
   procedure Setting_Change (I : Positive; Step : Integer);
   --  One step to the left (-1) or right (+1); applied at once and kept
   --  in ~/.deriverc

   function Setting_Count return Natural is separate;
   function Setting_Line (I : Positive) return String is separate;
   procedure Setting_Change (I : Positive; Step : Integer) is separate;

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
      elsif Level = Settings_Menu then
         return Setting_Count + 1;
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

   procedure Refresh_Menu is separate;

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
         when Settings_Menu => Level := Games;
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
      if Visiting or else Walking or else Riding_Velib or else Boating or else Mode /= Driving then
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
      if Visiting or else Walking or else Riding_Velib or else Boating or else Mode /= Driving then
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
      if Visiting or else Walking or else Riding_Velib or else Boating or else Mode /= Driving then
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
      if Visiting or else Walking or else Riding_Velib or else Boating or else Mode /= Driving then
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
      if Visiting or else Walking or else Riding_Velib or else Boating or else Mode /= Driving then
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
      if Visiting or else Walking or else Riding_Velib or else Boating or else Mode /= Driving then
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

   procedure Menu_Choose is separate;

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
            if Level = Settings_Menu and then Menu_Sel <= Setting_Count then
               Setting_Change (Menu_Sel, -1);
            elsif Level = Tracks then
               Race.Set_Laps (if Race.Laps_Setting = 0 then 5 else Race.Laps_Setting - 1);
            else
               Menu_Back;
               return True;
            end if;
         when 16#FF53# | 16#64# =>                            --  right, d
            if Level = Settings_Menu and then Menu_Sel <= Setting_Count then
               Setting_Change (Menu_Sel, 1);
            elsif Level = Tracks then
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
          Two_Stroke => Car."=" (Car.Player_Model, Car.Scooter) or else Boating,
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
   is separate;

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

   procedure Set_Key (Key : Gdk.Types.Gdk_Key_Type; Down : Boolean) is separate;

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

   procedure Run is separate;

end Game;
