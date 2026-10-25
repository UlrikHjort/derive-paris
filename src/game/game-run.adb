--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
separate (Game)
procedure Run is
   Credit  : Gtk.Label.Gtk_Label;
   Id      : Glib.Guint;
begin
   Gtk.Main.Init;
   Gtkada.Bindings.Set_On_Exception (Callback_Failed'Access);
   Config.Load;
   Set_Graphics (Config.Get ("graphics", "high"));
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

   --  the panels' own window, offscreen (see Draw_Hud)
   Gtk.Offscreen_Window.Gtk_New (Hud_Win);
   Gtk.Overlay.Gtk_New (Hud_Over);
   Gtk.Box.Gtk_New_Hbox (Hud_Base);
   Hud_Base.Set_Size_Request (1600, 900);
   Hud_Over.Add (Hud_Base);
   Hud_Win.Add (Hud_Over);
   Hud_Win.On_Damage_Event (Hud_Damaged'Access);

   Gtk.Label.Gtk_New (Hud);
   Hud.Set_Halign (Gtk.Widget.Align_Start);
   Hud.Set_Valign (Gtk.Widget.Align_End);
   Hud.Set_Margin_Start (10);
   Hud.Set_Margin_Bottom (10);
   Hud_Over.Add_Overlay (Hud);

   Gtk.Label.Gtk_New (Help);
   Help.Set_Halign (Gtk.Widget.Align_Center);
   Help.Set_Valign (Gtk.Widget.Align_Center);
   Help.Set_No_Show_All (True);
   Hud_Over.Add_Overlay (Help);

   Gtk.Label.Gtk_New (Place_List);
   Place_List.Set_Halign (Gtk.Widget.Align_Center);
   Place_List.Set_Valign (Gtk.Widget.Align_Center);
   Place_List.Set_No_Show_All (True);
   Hud_Over.Add_Overlay (Place_List);

   Gtk.Label.Gtk_New (Search_Box);
   Search_Box.Set_Halign (Gtk.Widget.Align_Center);
   Search_Box.Set_Valign (Gtk.Widget.Align_Start);
   Search_Box.Set_Margin_Top (80);
   Search_Box.Set_No_Show_All (True);
   Hud_Over.Add_Overlay (Search_Box);
   Hud_Over.Add_Overlay (Postcards.Album);

   Gtk.Label.Gtk_New (Confirm);
   Confirm.Set_Halign (Gtk.Widget.Align_Center);
   Confirm.Set_Valign (Gtk.Widget.Align_Center);
   Confirm.Set_No_Show_All (True);
   Hud_Over.Add_Overlay (Confirm);

   Gtk.Label.Gtk_New (Caption);
   Caption.Set_Halign (Gtk.Widget.Align_Center);
   Caption.Set_Valign (Gtk.Widget.Align_End);
   Caption.Set_Margin_Bottom (60);
   Caption.Set_Justify (Gtk.Enums.Justify_Center);
   Caption.Set_No_Show_All (True);
   Hud_Over.Add_Overlay (Caption);

   Gtk.Label.Gtk_New (Game_Menu);
   Game_Menu.Set_Halign (Gtk.Widget.Align_Center);
   Game_Menu.Set_Valign (Gtk.Widget.Align_Center);
   Game_Menu.Set_No_Show_All (True);
   Hud_Over.Add_Overlay (Game_Menu);

   Gtk.Label.Gtk_New (Race_Hud);
   Race_Hud.Set_Halign (Gtk.Widget.Align_Center);
   Race_Hud.Set_Valign (Gtk.Widget.Align_Start);
   Race_Hud.Set_Margin_Top (70);
   Race_Hud.Set_No_Show_All (True);
   Hud_Over.Add_Overlay (Race_Hud);

   Gtk.Label.Gtk_New (Radio_Box);
   Radio_Box.Set_Halign (Gtk.Widget.Align_Center);
   Radio_Box.Set_Valign (Gtk.Widget.Align_End);
   Radio_Box.Set_Margin_Bottom (60);
   Radio_Box.Set_No_Show_All (True);
   Hud_Over.Add_Overlay (Radio_Box);

   Gtk.Label.Gtk_New (Race_Banner);
   Race_Banner.Set_Halign (Gtk.Widget.Align_Center);
   Race_Banner.Set_Valign (Gtk.Widget.Align_Start);   --  above the car
   Race_Banner.Set_Margin_Top (120);
   Race_Banner.Set_Justify (Gtk.Enums.Justify_Center);
   Race_Banner.Set_No_Show_All (True);
   Hud_Over.Add_Overlay (Race_Banner);

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
   Hud_Over.Add_Overlay (Sign);

   declare
      Sign_W : constant Gtk.Widget.Gtk_Widget := Limit_Sign.Create;
   begin
      Sign_W.Set_Halign (Gtk.Widget.Align_Start);
      Sign_W.Set_Valign (Gtk.Widget.Align_End);
      Sign_W.Set_Margin_Start (272);
      Sign_W.Set_Margin_Bottom (40);
      Hud_Over.Add_Overlay (Sign_W);
   end;

   declare
      Alt_W : constant Gtk.Widget.Gtk_Widget := Altimeter.Create;
   begin
      Alt_W.Set_Halign (Gtk.Widget.Align_Start);
      Alt_W.Set_Valign (Gtk.Widget.Align_Center);
      Alt_W.Set_Margin_Start (12);
      Hud_Over.Add_Overlay (Alt_W);
   end;

   Panel := Instruments.Create;
   Panel.Set_No_Show_All (True);
   Hud_Over.Add_Overlay (Panel);
   Compass_Widget := Compass.Create;
   Hud_Over.Add_Overlay (Compass_Widget);
   Hud_Over.Add_Overlay (Navigation.Create_Minimap);
   Hud_Over.Add_Overlay (Navigation.Create_Instructions);

   Gtk.Label.Gtk_New (Credit);
   Credit.Set_Markup
     ("<span size='small' foreground='white' background='#00000088'>"
      & " Map data &#169; OpenStreetMap contributors (ODbL) </span>");
   Credit.Set_Halign (Gtk.Widget.Align_End);
   Credit.Set_Valign (Gtk.Widget.Align_End);
   Credit.Set_Margin_End (10);
   Credit.Set_Margin_Bottom (10);
   Hud_Over.Add_Overlay (Credit);

   Id := Area.Add_Tick_Callback (Tick'Access);
   pragma Unreferenced (Id);

   Window.Show_All;
   Hud_Win.Show_All;
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
