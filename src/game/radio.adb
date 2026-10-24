--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with Almanac;
with Era;
with Seasons;
with Sound;

package body Radio is

   use Ada.Strings.Unbounded;

   Is_On     : Boolean := False;
   Bulletin  : Unbounded_String;
   Show_Time : Float := 0.0;
   Last_Hour : Integer := -1;

   function On return Boolean is (Is_On);

   function Img (N : Integer) return String is
     (Ada.Strings.Fixed.Trim (Integer'Image (N), Ada.Strings.Left));

   --  "7 h 05"
   function Time_Fr (H : Float) return String is
      M  : constant Natural := Natural (Float'Floor (H * 60.0)) mod (24 * 60);
      S2 : constant String := Natural'Image (100 + M mod 60);
   begin
      return Img (M / 60) & " h " & S2 (S2'Last - 1 .. S2'Last);
   end Time_Fr;

   --  "1,40"
   function Metres_Fr (M : Float) return String is
      C  : constant Natural := Natural (Float'Rounding (Float'Max (0.0, M) * 100.0));
      S2 : constant String := Natural'Image (100 + C mod 100);
   begin
      return Img (C / 100) & "," & S2 (S2'Last - 1 .. S2'Last);
   end Metres_Fr;

   function Metres_En (M : Float) return String is
      F : String := Metres_Fr (M);
   begin
      for C of F loop
         if C = ',' then
            C := '.';
         end if;
      end loop;
      return F;
   end Metres_En;

   function Sun_Crossing (From, To : Float) return Float is
      Step : constant Float := (if To > From then 1.0 / 30.0 else -1.0 / 30.0);
      H : Float := From;
   begin
      while (if Step > 0.0 then H < To else H > To) and then Almanac.Sun (H).Y < 0.0 loop
         H := H + Step;
      end loop;
      return H;
   end Sun_Crossing;

   --  How warm Paris is: the month's mean, cooler at dawn and warmer in
   --  the afternoon, less in the rain, more in a heat wave
   function Temperature (F : Facts) return Integer is
      Mean : constant array (1 .. 12) of Float :=
        (5.0, 6.0, 9.0, 12.0, 16.0, 19.0, 21.5, 21.0, 17.5, 13.0, 8.5, 5.5);
      Day_Swing : constant Float :=
        (if F.Hour < 6.0 then -4.0
         elsif F.Hour < 15.0 then -4.0 + 8.0 * (F.Hour - 6.0) / 9.0
         else 4.0 - 8.0 * (F.Hour - 15.0) / 15.0);
   begin
      return Integer (Mean (Almanac.Month) + Day_Swing * (1.0 - 0.6 * F.Rain)
                      - 2.5 * F.Rain - 3.0 * F.Snow + 7.0 * Seasons.Heat);
   end Temperature;

   procedure Compose (F : Facts) is
      LF : constant String := (1 => ASCII.LF);
      T  : Unbounded_String;
      procedure Line (Fr, En : String) is
      begin
         Append (T, LF & "  " & Fr & "   <i><span foreground='#c8cdd8'>" & En & "</span></i>  ");
      end Line;
      Deg : constant Integer := Temperature (F);
      Flood : constant Float := Seasons.Flood;
   begin
      T := To_Unbounded_String
        ("<span font_family='sans' foreground='white'><b>  &#x266B; Radio Dérive"
         & (if Era.In_1973 then ", 1973" else "") & "  </b>");
      Line ("Il est " & Time_Fr (F.Hour) & ".", "It is " & Time_Fr (F.Hour) & ".");

      --  the weather
      if F.Storm then
         Line ("Orages sur Paris, restez prudents.", "Thunderstorms over Paris, take care.");
      elsif F.Snow > 0.2 then
         Line ("Il neige sur la capitale.", "It is snowing on the capital.");
      elsif F.Rain > 0.2 then
         Line ("Pluie sur Paris, chaussées glissantes.", "Rain over Paris, slippery roads.");
      elsif Seasons.Mist > 0.3 then
         Line ("Brouillard sur la Seine ce matin.", "Mist on the Seine this morning.");
      elsif Seasons.Heat > 0.4 then
         Line ("Canicule : buvez de l'eau, restez à l'ombre.", "Heat wave: drink water, stay in the shade.");
      elsif F.Hour >= 21.0 or else F.Hour < 6.0 then
         Line ("Nuit claire sur Paris.", "A clear night over Paris.");
      else
         Line ("Beau temps sur Paris.", "Fine weather over Paris.");
      end if;
      Line ("Il fait " & Img (Deg) & (if abs Deg = 1 then " degré." else " degrés."),
            Img (Deg) & " °C.");

      --  the river
      if Flood > 1.0 then
         Line ("Crue de la Seine : " & Metres_Fr (1.4 + Flood) & " m à Austerlitz, voies sur berges fermées"
               & (if Flood > 2.5 then ", navigation interrompue." else "."),
               "The Seine in flood: " & Metres_En (1.4 + Flood) & " m at Austerlitz, lower quays closed"
               & (if Flood > 2.5 then ", no boats." else "."));
      else
         Line ("La Seine à Austerlitz : " & Metres_Fr (1.4 + Flood) & " m.",
               "The Seine at Austerlitz: " & Metres_En (1.4 + Flood) & " m.");
      end if;

      --  the traffic
      if F.Traffic > 1.3 then
         Line ("Circulation dense, bouchons sur le périphérique.", "Heavy traffic, jams on the ring road.");
      elsif F.Traffic < 0.4 then
         Line ("Circulation fluide.", "The roads are clear.");
      end if;
      if F.Closed > 0 then
         Line (Img (F.Closed) & (if F.Closed = 1 then " rue fermée" else " rues fermées")
               & " : travaux, accidents.",
               Img (F.Closed) & (if F.Closed = 1 then " street" else " streets") & " closed: works, accidents.");
      end if;
      if Almanac.Saturday and then F.Hour >= 12.0 and then F.Hour < 18.0 then
         Line ("Manifestation cet après-midi sur les boulevards.", "A demonstration this afternoon on the boulevards.");
      end if;
      --  the sun
      if F.Hour < 11.0 then
         Line ("Lever du soleil à " & Time_Fr (Sun_Crossing (3.0, 11.0)) & ".",
               "Sunrise at " & Time_Fr (Sun_Crossing (3.0, 11.0)) & ".");
      elsif F.Hour >= 15.0 and then F.Hour < 22.0 then
         Line ("Coucher du soleil à " & Time_Fr (Sun_Crossing (23.0, 15.0)) & ".",
               "Sunset at " & Time_Fr (Sun_Crossing (23.0, 15.0)) & ".");
      end if;
      Append (T, "</span>");
      Bulletin := T;
      Show_Time := 14.0;
      Sound.Effect (Sound.Chime, 0.8, 0.0);
   end Compose;

   procedure Toggle (F : Facts) is
   begin
      Is_On := not Is_On;
      if Is_On then
         Last_Hour := Integer (Float'Floor (F.Hour));
         Compose (F);
      else
         Show_Time := 0.0;
      end if;
   end Toggle;

   procedure Update (Dt : Float; F : Facts) is
      H : constant Integer := Integer (Float'Floor (F.Hour));
   begin
      Show_Time := Float'Max (0.0, Show_Time - Dt);
      if Is_On and then H /= Last_Hour then
         Last_Hour := H;
         Compose (F);
      end if;
   end Update;

   function Text return String is
     (if Show_Time > 0.0 then To_String (Bulletin) else "");

end Radio;
