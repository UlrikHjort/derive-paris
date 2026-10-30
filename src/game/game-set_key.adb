--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
separate (Game)
procedure Set_Key (Key : Gdk.Types.Gdk_Key_Type; Down : Boolean) is
   K : Gdk.Types.Gdk_Key_Type := Key;
begin
   if K in 16#41# .. 16#5A# then   --  upper case letters
      K := K + 16#20#;
   end if;
   if Confirm_Open and then Down then
      Confirm_Open := False;
      Confirm.Hide;
      if Confirm_Quit then
         Confirm_Quit := False;
         if K = 16#FF0D# or else K = 16#FF8D# or else K = 16#79# then   --  Enter, y
            Gtk.Main.Main_Quit;
         end if;
      elsif Confirm_Set_Home then
         Confirm_Set_Home := False;
         if K = 16#FF0D# or else K = 16#FF8D# or else K = 16#79# then   --  Enter, y
            Save_Home_Here;
         end if;
      elsif K = 16#FF0D# or else K = 16#FF8D# or else K = 16#68# or else K = 16#79# then
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
      when 16#FFE3# => Keys.Ctrl := Down;                    --  left ctrl
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
            if Wheel_Drives then
               Manual_Gearbox := not Manual_Gearbox;
            end if;
            Announce := Ada.Strings.Unbounded.To_Unbounded_String
              ((if not Wheel_Drives then "Gearbox: automatic (manual needs the wheel)"
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
      when 16#FFC2# =>                                     --  F5: settings
         if Down then
            Open_Settings;
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
               --  not out of the game by one press too many: ask
               Confirm_Open := True;
               Confirm_Quit := True;
               Confirm.Set_Markup
                 ("<span font_family='sans' size='large'><b>Quit Dérive?</b></span>" & ASCII.LF
                  & "<span foreground='#aab'>Enter or Y: quit      Esc or N: go on playing"
                  & (if Wheel.Present then ASCII.LF & "wheel: X quit, circle go on" else "")
                  & "</span>");
               Confirm.Show;
            end if;
         end if;
      when others => null;
   end case;
end Set_Key;
