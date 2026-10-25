--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
separate (Game)
function Setting_Line (I : Positive) return String is
   K : constant Settings_Kind := Settings_Kind'Val (I - 1);
   function Pct (V : Float) return String is
     (Ada.Strings.Fixed.Trim (Integer'Image (Integer (V * 100.0)), Ada.Strings.Left) & " %");
   function Row (Name, Value : String) return String is
     (Name & (1 .. Natural'Max (1, 20 - Name'Length) => ' ') & "&lt; " & Value & " &gt;");
begin
   return
     (case K is
         when S_Volume     => Row ("Volume", Pct (Config.Get ("volume", 0.8))),
         when S_Traffic    => Row ("Traffic", Pct (Config.Get ("traffic", 1.0))),
         when S_People     => Row ("People", Pct (Config.Get ("pedestrians", 1.0))),
         when S_Graphics   => Row ("Graphics", Config.Get ("graphics", "high")),
         when S_Car        => Row ("Your car", Config.Get ("car", "modern")),
         when S_Time_Speed =>
           Row ("Time", Ada.Strings.Fixed.Trim (Integer'Image (Integer (Config.Get ("time_speed", 1.0) * 60.0)),
                                               Ada.Strings.Left) & " s a game hour"),
         when S_Limits     => Row ("Speed limits", Config.Get ("speed_limits", "game")),
         when S_Gearbox    =>
           Row ("Gearbox (wheel)", (if Manual_Gearbox then "manual" else "automatic")),
         when S_Compass    => Row ("Compass and map", (if Show_Compass then "yes" else "no")),
         when S_Names      => Row ("Street names", (if Show_Street then "yes" else "no")));
end Setting_Line;
