--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Version;

separate (Game)
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
     & "  Shift+H          make this your home (asks first)" & LF
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
     & "  F5               settings" & LF
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
     & "  Esc otherwise    quit the game (asks first)" & LF & LF
     & "<span foreground='#8890a0'>  Dérive " & Version.Number & "</span>"
     & "</span>";
end Help_Text;
