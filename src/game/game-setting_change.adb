--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
separate (Game)
procedure Setting_Change (I : Positive; Step : Integer) is
   K : constant Settings_Kind := Settings_Kind'Val (I - 1);

   --  the next of a list of choices, one way or the other, round
   function Next (Now : String; Choices : String) return String is
      type Bounds is array (1 .. 8) of Natural;
      Starts, Ends : Bounds := (others => 0);
      N : Natural := 0;
      First : Positive := Choices'First;
      Here : Natural := 0;
   begin
      for C in Choices'First .. Choices'Last + 1 loop
         if C > Choices'Last or else Choices (C) = ' ' then
            N := N + 1;
            Starts (N) := First;
            Ends (N) := C - 1;
            if Choices (First .. C - 1) = Now then
               Here := N;
            end if;
            First := C + 1;
         end if;
      end loop;
      Here := (if Here = 0 then 1 else (Here - 1 + Step + N) mod N + 1);
      return Choices (Starts (Here) .. Ends (Here));
   end Next;

   function Img (V : Float) return String is
      S : constant String := Float'Image (Float'Rounding (V * 100.0) / 100.0);
   begin
      return Ada.Strings.Fixed.Trim (S (S'First .. Ada.Strings.Fixed.Index (S, "E") - 1), Ada.Strings.Both);
   end Img;

   function Stepped (Name : String; Default, Lo, Hi, By : Float) return Float is
      V : constant Float := Float'Max (Lo, Float'Min (Hi, Config.Get (Name, Default) + Float (Step) * By));
   begin
      Config.Set (Name, Img (V));
      return V;
   end Stepped;
begin
   case K is
      when S_Volume =>
         Sound.Set_Volume (Stepped ("volume", 0.8, 0.0, 1.0, 0.1));
      when S_Traffic =>
         Traffic.Set_Density (Stepped ("traffic", 1.0, 0.0, 2.0, 0.25) * Traffic_Factor (Hour));
      when S_People =>
         Pedestrians.Set_Density (Stepped ("pedestrians", 1.0, 0.0, 2.0, 0.25));
      when S_Graphics =>
         Config.Set ("graphics", Next (Config.Get ("graphics", "high"), "low medium high"));
         Set_Graphics (Config.Get ("graphics", "high"));
         Graphics_Changed := True;
      when S_Car =>
         Config.Set ("car", Next (Config.Get ("car", "modern"), "modern 2cv ds r4"));
         if Car."=" (Car.Player_Model, Car.Modern) or else Car."=" (Car.Player_Model, Car.Deux_Chevaux)
           or else Car."=" (Car.Player_Model, Car.DS) or else Car."=" (Car.Player_Model, Car.R4)
         then
            Car.Set_Player_Model (Usual_Model);   --  (not while on the scooter, the bus...)
         end if;
      when S_Time_Speed =>
         Config.Set ("time_speed", Next (Config.Get ("time_speed", "1.0"), "0.25 0.5 1.0 2.0 5.0"));
         Clock_Rate := Config.Get ("time_speed", 1.0) / 60.0;
      when S_Limits =>
         Config.Set ("speed_limits", Next (Config.Get ("speed_limits", "game"), "game real"));
      when S_Gearbox =>
         Manual_Gearbox := not Manual_Gearbox;
         Config.Set ("manual_gearbox", (if Manual_Gearbox then "yes" else "no"));
      when S_Compass =>
         Set_Key (16#67#, True);
         Config.Set ("compass", (if Show_Compass then "yes" else "no"));
      when S_Names =>
         Show_Street := not Show_Street;
         Config.Set ("street_names", (if Show_Street then "yes" else "no"));
   end case;
end Setting_Change;
