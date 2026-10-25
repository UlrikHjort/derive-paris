--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
separate (Game)
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
