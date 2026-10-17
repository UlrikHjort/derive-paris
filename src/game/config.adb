--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Characters.Handling;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Strings.Hash;
with Ada.Text_IO;

package body Config is

   package Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (String, String, Ada.Strings.Hash, "=");

   Values : Maps.Map;

   Starter : constant String :=
     "# ~/.deriverc -- settings for Derive (open-world Paris, in Ada)" & ASCII.LF
     & "# name = value; lines starting with # are comments." & ASCII.LF
     & "# Delete a line (or this file) to get the default back." & ASCII.LF
     & ASCII.LF
     & "# Traffic: 1.0 is normal Paris (180 vehicles around you), 0 is empty" & ASCII.LF
     & "# streets, 2.0 is rush hour." & ASCII.LF
     & "traffic = 1.0" & ASCII.LF
     & ASCII.LF
     & "# Pedestrians: 1.0 is normal (160 people around you)." & ASCII.LF
     & "pedestrians = 1.0" & ASCII.LF
     & ASCII.LF
     & "# Sound volume, 0 .. 1 (M mutes in the game)." & ASCII.LF
     & "volume = 0.8" & ASCII.LF
     & ASCII.LF
     & "# Time of day at the start (hours, 0 .. 24) and how fast time passes" & ASCII.LF
     & "# (game minutes per real second; 0 stops the clock)." & ASCII.LF
     & "start_hour = 18.0" & ASCII.LF
     & "# The date: today, or a day like 2026-12-24 (the season, the moon," & ASCII.LF
     & "# and what Paris celebrates)." & ASCII.LF
     & "date = today" & ASCII.LF
     & "# Christmas decorations: auto (December to Epiphany), yes or no." & ASCII.LF
     & "christmas = auto" & ASCII.LF
     & "time_speed = 1.0" & ASCII.LF
     & ASCII.LF
     & "# Shown at the start: compass and minimap, street name plaque," & ASCII.LF
     & "# instrument panel (gear, revs, speed)." & ASCII.LF
     & "compass = yes" & ASCII.LF
     & "street_names = yes" & ASCII.LF
     & "instruments = yes" & ASCII.LF
     & ASCII.LF
     & "# Racing wheel (Logitech G29, found by itself when plugged in):" & ASCII.LF
     & "# drive with the H-shifter and clutch (no: automatic), whether a gear" & ASCII.LF
     & "# only goes in with the clutch down, force feedback strength 0 .. 1." & ASCII.LF
     & "manual_gearbox = yes" & ASCII.LF
     & "clutch = yes" & ASCII.LF
     & "force_feedback = 0.6" & ASCII.LF
     & "# Steering sensitivity (1.0: 900 degrees lock to lock like a real car," & ASCII.LF
     & "# 1.5: quicker) and a correction if the car does not run straight with" & ASCII.LF
     & "# the wheel centred (degrees, + if the car pulls to the right)." & ASCII.LF
     & "steering = 1.0" & ASCII.LF
     & "wheel_centre = 0.0" & ASCII.LF;

   function File_Name return String is
     (Ada.Environment_Variables.Value ("HOME", ".") & "/.deriverc");

   --  The game was called differently before: take an old file over
   function Old_File_Name return String is
     (Ada.Environment_Variables.Value ("HOME", ".") & "/.adadriverc");

   procedure Load is
      use Ada.Strings.Fixed;
      F : Ada.Text_IO.File_Type;
   begin
      if not Ada.Directories.Exists (File_Name)
        and then Ada.Directories.Exists (Old_File_Name)
      then
         begin
            Ada.Directories.Rename (Old_File_Name, File_Name);
            Ada.Text_IO.Put_Line ("Moved " & Old_File_Name & " to " & File_Name);
         exception
            when others => null;
         end;
      end if;
      if not Ada.Directories.Exists (File_Name) then
         begin
            Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, File_Name);
            Ada.Text_IO.Put (F, Starter);
            Ada.Text_IO.Close (F);
            Ada.Text_IO.Put_Line ("Wrote default settings to " & File_Name);
         exception
            when others => return;
         end;
      end if;
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, File_Name);
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            Line : constant String := Trim (Ada.Text_IO.Get_Line (F), Ada.Strings.Both);
            Eq   : constant Natural := Index (Line, "=");
         begin
            if Line'Length > 0 and then Line (Line'First) /= '#' and then Eq > 0 then
               declare
                  Hash : constant Natural := Index (Line, "#");
                  Last : constant Natural := (if Hash > Eq then Hash - 1 else Line'Last);
               begin
                  Values.Include
                    (Ada.Characters.Handling.To_Lower
                       (Trim (Line (Line'First .. Eq - 1), Ada.Strings.Both)),
                     Trim (Line (Eq + 1 .. Last), Ada.Strings.Both));
               end;
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (F);
   exception
      when others =>
         Ada.Text_IO.Put_Line ("Could not read " & File_Name);
   end Load;

   function Get (Name : String; Default : Float) return Float is
   begin
      if Values.Contains (Name) then
         return Float'Value (Values.Element (Name));
      end if;
      return Default;
   exception
      when Constraint_Error =>
         Ada.Text_IO.Put_Line (File_Name & ": bad number for " & Name);
         return Default;
   end Get;

   function Get (Name : String; Default : Boolean) return Boolean is
   begin
      if Values.Contains (Name) then
         declare
            V : constant String := Ada.Characters.Handling.To_Lower (Values.Element (Name));
         begin
            return V = "yes" or else V = "true" or else V = "on" or else V = "1";
         end;
      end if;
      return Default;
   end Get;

   function Get (Name : String; Default : String) return String is
     (if Values.Contains (Name) then Values.Element (Name) else Default);

end Config;
