--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
separate (Game)
function Render (Area_Ptr, Context, Data : System.Address) return Glib.Gboolean
is
   pragma Unreferenced (Area_Ptr, Context, Data);
   use Shaders;
   Target   : aliased GLint := 0;
   Viewport : aliased GLint_Array (0 .. 3) := (others => 0);
   W, H     : Integer;
   RW, RH   : Integer;   --  the world is drawn at this size (the render scale)
   Started  : constant Ada.Real_Time.Time := Clock_Now;
begin
   if not Ready then
      return 1;
   end if;
   glGetIntegerv (GL_FRAMEBUFFER_BINDING, Target'Address);
   glGetIntegerv (GL_VIEWPORT, Viewport'Address);
   W := Integer (Viewport (2));
   H := Integer (Viewport (3));
   --  the graphics level changed (F2, Settings): the shadow map and the
   --  buffers made again at their new sizes
   if Graphics_Changed then
      Graphics_Changed := False;
      glDeleteFramebuffers (1, Shadow_FBO'Address);
      glDeleteTextures (1, Shadow_Tex'Address);
      Create_Shadow_Map;
      MSAA_W := 0;
      Mid_W := 0;
   end if;
   RW := Integer'Max (1, Integer (Float (W) * Render_Scale));
   RH := Integer'Max (1, Integer (Float (H) * Render_Scale));
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
      Ensure_MSAA (RW, RH);
      glBindFramebuffer (GL_FRAMEBUFFER, MSAA_FBO);
      glViewport (0, 0, GLsizei (RW), GLsizei (RH));
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
         Funicular.Draw (WU.Model, WU.Car_Color, Cam_Pos);
         Balloon.Draw (WU.Model, WU.Car_Color, Cam_Pos);
         Set (WU.Car_Color, Car_Color);
         Vitrines.Draw (WU.Model, WU.Car_Color, WU.Extra_Color, WU.Extra_Color2, Cam_Pos, Hour, Time);
         Match.Draw (WU.Model, WU.Car_Color, WU.Extra_Color, WU.Extra_Color2, Cam_Pos, Time);
         Tertre.Draw (WU.Model, WU.Car_Color, WU.Extra_Color, WU.Extra_Color2, Cam_Pos, Hour, Rain_Amount, Time);
         Set (WU.Car_Color, Car_Color);
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
      glUseProgram (Shadow_Prog);
      Set (Sh_Light_VP, VP);
      Set (Sh_Model, Identity);
      Set (Sh_Erase_N, Integer'(0));
      World.Draw_Ground_Depth;
      glUseProgram (World_Prog);
      World.Draw_Ground;
      Tyre_Effects.Draw_Marks (VP, Cam_Pos);
      Beacon.Draw (VP, Cam_Pos, Time, Hour, Night, Rain_Amount);
      Storm.Draw (VP, Cam_Pos);
      Ufo.Draw_Beam (VP, Cam_Pos);
      Surprises.Draw_Lights (VP, Cam_Pos);
      Boats.Draw_Lights (VP, Cam_Pos, Night);
      Sky_Life.Draw (VP, Float (RH) / (2.0 * Tan (0.525)), Night);
      Rain.Draw (VP, Cam_Pos, Time, (if In_Museum or else In_Hall_B or else In_Room then 0.0 else Float'Max (Rain_Amount, Snow_Amount)),
                 Snow_Amount > Rain_Amount, Float (RH) / (2.0 * Tan (0.525)),
                 Mix (Vec3'(0.30, 0.32, 0.36), Vec3'(0.75, 0.78, 0.82), 1.0 - Night));
      if (Mode = Driving or else Visiting or else Walking)
        and then not In_Museum and then not In_Hall_B and then not In_Room
        and then not On_Tower and then not On_Arc
      then
         Rain.Draw_Leaves (VP, Cam_Pos, Time, Almanac.Leaves_Falling * (1.0 - Snow_Amount),
                           Float (RH) / (2.0 * Tan (0.525)), 0.15 + 0.85 * (1.0 - Night));
      end if;
      Tyre_Effects.Draw_Smoke (VP, Cam_Pos, Float (RH) / (2.0 * Tan (0.525)), 1.0 - Night);
      End_Pass (P_Ground);
      Begin_Pass (P_Resolve);

      --  Resolve into GTK's framebuffer
      if RW = W and then RH = H then
         glBindFramebuffer (GL_READ_FRAMEBUFFER, MSAA_FBO);
         glBindFramebuffer (GL_DRAW_FRAMEBUFFER, GLuint (Target));
         glBlitFramebuffer (0, 0, GLint (W), GLint (H), 0, 0, GLint (W), GLint (H),
                            GL_COLOR_BUFFER_BIT, GL_NEAREST);
      else
         --  drawn smaller: (resolve the samples, then) stretch to the window
         if Samples > 1 then
            Ensure_Mid (RW, RH);
            glBindFramebuffer (GL_READ_FRAMEBUFFER, MSAA_FBO);
            glBindFramebuffer (GL_DRAW_FRAMEBUFFER, Mid_FBO);
            glBlitFramebuffer (0, 0, GLint (RW), GLint (RH), 0, 0, GLint (RW), GLint (RH),
                               GL_COLOR_BUFFER_BIT, GL_NEAREST);
            glBindFramebuffer (GL_READ_FRAMEBUFFER, Mid_FBO);
         else
            glBindFramebuffer (GL_READ_FRAMEBUFFER, MSAA_FBO);
         end if;
         glBindFramebuffer (GL_DRAW_FRAMEBUFFER, GLuint (Target));
         glBlitFramebuffer (0, 0, GLint (RW), GLint (RH), 0, 0, GLint (W), GLint (H),
                            GL_COLOR_BUFFER_BIT, GL_LINEAR);
      end if;
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
      --  the panels, after the photos, films and postcards (which show
      --  the city only) and before a screenshot
      glViewport (0, 0, GLsizei (W), GLsizei (H));
      Draw_Hud (W, H);
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
      if Profiling_Cpu then
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
   Add (C_Render, Started);
   return 1;
end Render;
