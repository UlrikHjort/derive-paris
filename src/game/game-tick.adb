--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
separate (Game)
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
   --  PARIS_MOTORBOAT=1: on foot to the yellow mark by the landing: the
   --  motorboat (testing)
   if Ready and then Frame_Number = 40 and then Env ("PARIS_MOTORBOAT") /= "" then
      Player.Speed := 0.0;
      if not Walking then
         Toggle_Walk;
      end if;
      Motorboat.Hire_Point (Walk_X, Walk_Z);
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
   --  PARIS_SEARCH="12 rue de rivoli": the address box with that typed (testing)
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
                     if Boating then
                        Motorboat.Step (Player, Input, Dt / Float (Steps));
                     else
                        Car.Update (Player, (if Race.Frozen then Held else Input), Dt / Float (Steps));
                        Traffic.Collide_Player (Player);
                        Street_Life.Collide (Player);
                        Scenes.Collide (Player);
                        Closures.Collide (Player);
                        Seasons.Collide (Player);
                     end if;
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
         Traffic.Set_Snow (Snow_Cover);
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
         Boats.Update (Dt, Cam_Pos);
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
