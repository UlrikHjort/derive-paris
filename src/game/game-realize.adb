--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
separate (Game)
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
   Hud_Layer.Create;
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

   Profiling := Ada.Environment_Variables.Exists ("PARIS_PROFILE")
     and then Ada.Environment_Variables.Value ("PARIS_PROFILE") /= "cpu";
   Profiling_Cpu := Ada.Environment_Variables.Exists ("PARIS_PROFILE");
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
   if not City_Built then
      --  a fresh checkout: say how to build the city
      Ada.Text_IO.Put_Line ("No city built yet: quit, and run ""make tiles"" (all of Paris)"
                            & " or ""make tiles-small"" (only the centre, quicker)");
      Announce := Ada.Strings.Unbounded.To_Unbounded_String
        ("No city yet: quit and run  make tiles  (all of Paris) or  make tiles-small  (the centre)");
      Announce_Timer := 1.0E9;
      Street_Timer := 1.0;
   end if;
   Ready := True;
exception
   when E : others =>
      Ada.Text_IO.Put_Line ("Initialisation failed: "
                            & Ada.Exceptions.Exception_Message (E));
      Gtk.Main.Main_Quit;
end Realize;
