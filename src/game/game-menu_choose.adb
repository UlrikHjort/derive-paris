--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
separate (Game)
procedure Menu_Choose is
begin
   if Level = Settings_Menu then
      if Menu_Sel > Setting_Count then
         Menu_Back;
      else
         Setting_Change (Menu_Sel, 1);   --  (Enter: the next value)
         Refresh_Menu;
      end if;
      return;
   end if;
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
      when Go_Settings =>
         Level := Settings_Menu;
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
