--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--

with Ada.Environment_Variables;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;
with Ada.Strings.Fixed;

with Config;
with Figures;
with Geo;
with Math3D;
with Meshes;
with Road_Network;
with Shaders;
with Sound;
with Terrain;

package body Taxi is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;
   use Ada.Strings.Unbounded;

   subtype UString is Unbounded_String;
   function "+" (S : String) return UString renames To_Unbounded_String;

   Gen    : Ada.Numerics.Float_Random.Generator;
   Seeded : Boolean := False;
   function Rnd return Float is (Ada.Numerics.Float_Random.Random (Gen));

   function Test (Name : String) return Boolean is
     (Ada.Environment_Variables.Exists (Name));

   LF : constant String := (1 => ASCII.LF);

   ---------------------------------------------------------------------------
   --  Where people want to go
   ---------------------------------------------------------------------------

   type Place is record
      Name     : UString;
      Lat, Lon : Long_Float;
   end record;

   Places : constant array (Positive range <>) of Place :=
     ((+"Gare du Nord", 48.88090, 2.35530),
      (+"Gare de l'Est", 48.87680, 2.35920),
      (+"Gare de Lyon", 48.84430, 2.37430),
      (+"Gare Montparnasse", 48.84140, 2.32030),
      (+"Gare Saint-Lazare", 48.87630, 2.32530),
      (+"Gare d'Austerlitz", 48.84240, 2.36530),
      (+"the Opéra Garnier", 48.87190, 2.33160),
      (+"the Musée d'Orsay", 48.86000, 2.32660),
      (+"the Louvre", 48.86200, 2.33600),
      (+"the Centre Pompidou", 48.86060, 2.35220),
      (+"the Hôtel de Ville", 48.85660, 2.35220),
      (+"Place de la Bastille", 48.85320, 2.36910),
      (+"Place des Vosges", 48.85560, 2.36550),
      (+"the Trocadéro", 48.86250, 2.28780),
      (+"the Eiffel Tower", 48.85840, 2.29450),
      (+"Les Invalides", 48.85660, 2.31260),
      (+"the Arc de Triomphe", 48.87380, 2.29500),
      (+"the Galeries Lafayette", 48.87380, 2.33200),
      (+"the Moulin Rouge", 48.88410, 2.33220),
      (+"the Sacré-Cœur", 48.88670, 2.34310),
      (+"the Panthéon", 48.84620, 2.34640),
      (+"the Jardin du Luxembourg", 48.84840, 2.33650),
      (+"the Café de Flore", 48.85410, 2.33260),
      (+"the Hôtel Ritz", 48.86810, 2.32900),
      (+"the Hôtel George V", 48.86880, 2.30050),
      (+"Le Bon Marché", 48.85100, 2.32430),
      (+"Place d'Italie", 48.83120, 2.35560),
      (+"the Buttes-Chaumont", 48.88090, 2.38280),
      (+"Père-Lachaise", 48.86140, 2.39340),
      (+"the Accor Arena in Bercy", 48.83860, 2.37860),
      (+"the Bibliothèque nationale", 48.83370, 2.37590),
      (+"the Canal Saint-Martin", 48.87180, 2.36400),
      (+"Place de la République", 48.86740, 2.36360),
      (+"the Parc Monceau", 48.87940, 2.30910),
      (+"the rue Mouffetard", 48.84220, 2.34970),
      (+"the Jardin des Plantes", 48.84400, 2.35940),
      (+"the Palais des Congrès", 48.87850, 2.28300),
      (+"Place de Clichy", 48.88350, 2.32740),
      (+"Saint-Germain-des-Prés", 48.85390, 2.33380),
      (+"the Champs-Élysées", 48.86980, 2.30750));

   ---------------------------------------------------------------------------
   --  Who rides with you
   ---------------------------------------------------------------------------

   type Kind is (Business, Elderly, Tourist, Party);

   type Name_List is array (Positive range <>) of UString;
   Business_Names : constant Name_List :=
     (+"M. Lefèvre", +"Mme Laurent", +"M. Garnier", +"Mme Rousseau", +"M. Bertrand", +"Mme Chevalier");
   Elderly_Names : constant Name_List :=
     (+"Mme Dubois", +"M. Mercier", +"Mme Fontaine", +"M. Girard", +"Mme Lemaire");
   Tourist_Names : constant Name_List :=
     (+"Mr Smith", +"Frau Weber", +"Signora Rossi", +"Mr Tanaka", +"Mrs Johnson", +"Señor García");
   Party_Names : constant Name_List :=
     (+"Léa and Hugo", +"Camille", +"Théo and friends", +"Manon", +"Jules and Inès");

   function Pick (L : Name_List) return UString is
     (L (L'First + Natural'Min (L'Length - 1, Natural (Float'Floor (Rnd * Float (L'Length))))));

   --  How much they tip when happy, and how much a knock upsets them
   Tip_Rate  : constant array (Kind) of Float := (0.25, 0.20, 0.12, 0.30);
   Knock_Fuss : constant array (Kind) of Float := (0.8, 1.8, 1.0, 0.5);

   ---------------------------------------------------------------------------
   --  The state of the shift and the ride
   ---------------------------------------------------------------------------

   Current : Phase_Kind := Off;
   Me_X, Me_Z : Float := 0.0;

   --  the fare
   Who        : UString;
   Who_Kind   : Kind := Business;
   Waiting    : Boolean := False;   --  someone at the kerb (else still looking)
   Look_Wait  : Float := 0.0;
   Fare_X, Fare_Z, Fare_Face : Float := 0.0;
   Pick_X, Pick_Z : Float := 0.0;   --  the road beside them
   Fare_Shirt, Fare_Skin, Fare_Legs : Vec3 := (0.5, 0.5, 0.5);
   Dest_Name  : UString;
   Dest_X, Dest_Z : Float := 0.0;

   --  the GPS
   Goal_Serial : Natural := 0;
   Goal_X, Goal_Z : Float := 0.0;
   Goal_Name : UString;

   --  the ride
   Elapsed, Allowed, Bonus_Max, Driven : Float := 0.0;
   Mood       : Float := 1.0;
   Per_Km     : Float := 1.32;
   Tariff     : Character := 'A';
   Ride_Fines : Float := 0.0;
   Pending, Pending_Time : Float := 0.0;   --  a knock going on
   Slow_Time  : Float := 0.0;

   --  the last ride, for the panel
   Last_Meter, Last_Tip, Last_Bonus, Last_Fines, Last_Mood : Float := 0.0;
   Last_Late  : Boolean := False;
   Last_Dest  : UString;

   --  the shift
   Total, Sum_Meter, Sum_Tips, Sum_Bonus, Sum_Fines, Km, Best, Shift_Time : Float := 0.0;
   Rides : Natural := 0;

   --  what the passenger says
   Said_Fr, Said_En : UString;
   Said_Time, Complain_Wait : Float := 0.0;

   --  the speed limit
   Here_Limit : Natural := 0;
   Too_Fast   : Boolean := False;
   Limit_Wait : Float := 0.0;

   --  the police: a car by the road and an officer with a speed gun
   type Check is record
      On       : Boolean := False;
      CX, CZ, H : Float := 0.0;      --  the car, parked along the road
      OX, OZ, Face : Float := 0.0;   --  the officer
      Seen     : Boolean := False;   --  you came close
      Done     : Boolean := False;   --  already stopped you
      Life     : Float := 0.0;
   end record;
   Police     : Check;
   Next_Check : Float := 0.0;
   Warn       : UString;
   Warn_Time  : Float := 0.0;

   Lamp_Mesh, Bar_Mesh : Meshes.Mesh;
   Built : Boolean := False;

   function Phase return Phase_Kind is (Current);
   function Active return Boolean is (Current /= Off);
   function Limit return Natural is (if Current = Off then 0 else Here_Limit);
   function Over_Limit return Boolean is (Current /= Off and then Too_Fast);

   function Money (V : Float) return String is
      Cents : constant Integer := Integer (V * 100.0);
      Whole : constant String := Integer'Image (abs Cents / 100);
      Frac  : constant String := Integer'Image (100 + abs Cents mod 100);
   begin
      return (if Cents < 0 then "-" else "") & Whole (Whole'First + 1 .. Whole'Last)
        & "." & Frac (Frac'Last - 1 .. Frac'Last) & " €";
   end Money;

   function Kmh (Player : Car.State) return Float is (abs Player.Speed * 3.6);

   procedure Say (Fr, En : String) is
   begin
      Said_Fr := +Fr;
      Said_En := +En;
      Said_Time := 4.5;
   end Say;

   procedure Set_Goal (X, Z : Float; Name : String) is
   begin
      Goal_X := X;
      Goal_Z := Z;
      Goal_Name := +Name;
      Goal_Serial := Goal_Serial + 1;
   end Set_Goal;

   procedure Goal (Serial : out Natural; X, Z : out Float; Name : out UString) is
   begin
      Serial := (if Current = Off then 0 else Goal_Serial);
      X := Goal_X;
      Z := Goal_Z;
      Name := Goal_Name;
   end Goal;

   ---------------------------------------------------------------------------
   --  A new fare
   ---------------------------------------------------------------------------

   procedure Look_For_Fare (Hour : Float) is
      use Road_Network;
      Near : constant Float := (if Test ("PARIS_TAXI_NEAR") then 25.0 else 300.0);
      Far  : constant Float := (if Test ("PARIS_TAXI_NEAR") then 60.0 else 800.0);
   begin
      Waiting := False;
      for Attempt in 1 .. 30 loop
         declare
            Found  : Boolean;
            W, Pos : Natural;
         begin
            Pick_Segment (Me_X, Me_Z, Near, Far, Rnd, Rnd, Rnd, Found, W, Pos);
            if Found then
               declare
                  A : constant Node := Point (W, Pos);
                  B : constant Node := Point (W, Pos + 1);
                  L : constant Float := Sqrt ((B.X - A.X) ** 2 + (B.Z - A.Z) ** 2);
               begin
                  if L > 8.0 then
                     declare
                        T    : constant Float := 0.2 + 0.6 * Rnd;
                        DX   : constant Float := (B.X - A.X) / L;
                        DZ   : constant Float := (B.Z - A.Z) / L;
                        Side : constant Float := (if Rnd < 0.5 then -1.0 else 1.0);
                        Off  : constant Float := Ways (W).Width / 2.0 + 1.3;
                        Night : constant Boolean := Hour >= 22.0 or else Hour < 5.0;
                        R    : constant Float := Rnd;
                     begin
                        Pick_X := A.X + T * (B.X - A.X);
                        Pick_Z := A.Z + T * (B.Z - A.Z);
                        Fare_X := Pick_X + Side * Off * (-DZ);
                        Fare_Z := Pick_Z + Side * Off * DX;
                        --  facing the street
                        Fare_Face := Arctan (Side * DZ, Side * DX);
                        Who_Kind := (if Night and then R < 0.45 then Party
                                     elsif R < 0.35 then Business
                                     elsif R < 0.6 then Elderly
                                     elsif R < 0.9 or else not Night then Tourist
                                     else Party);
                        case Who_Kind is
                           when Business =>
                              Who := Pick (Business_Names);
                              Fare_Shirt := (0.16, 0.17, 0.22);
                              Fare_Legs := (0.14, 0.15, 0.19);
                           when Elderly =>
                              Who := Pick (Elderly_Names);
                              Fare_Shirt := (0.62, 0.55, 0.45);
                              Fare_Legs := (0.35, 0.33, 0.32);
                           when Tourist =>
                              Who := Pick (Tourist_Names);
                              Fare_Shirt := (if Rnd < 0.5 then (0.95, 0.55, 0.15) else (0.2, 0.65, 0.85));
                              Fare_Legs := (0.75, 0.68, 0.5);
                           when Party =>
                              Who := Pick (Party_Names);
                              Fare_Shirt := (if Rnd < 0.5 then (0.85, 0.1, 0.45) else (0.55, 0.2, 0.85));
                              Fare_Legs := (0.08, 0.08, 0.1);
                        end case;
                        Fare_Skin := (case Natural (Float'Floor (Rnd * 3.99)) is
                                   when 0 => (0.86, 0.68, 0.56), when 1 => (0.76, 0.57, 0.44),
                                   when 2 => (0.58, 0.40, 0.29), when others => (0.40, 0.27, 0.19));
                     end;
                     --  where to: somewhere 1.2 to 4.5 km away
                     declare
                        Lo : constant Float := (if Test ("PARIS_TAXI_NEAR") then 500.0 else 1200.0);
                        Hi : constant Float := (if Test ("PARIS_TAXI_NEAR") then 1200.0 else 4500.0);
                        Chosen : Natural := 0;
                        Seen   : Natural := 0;
                     begin
                        for I in Places'Range loop
                           declare
                              X, Z : Long_Float;
                              D : Float;
                           begin
                              Geo.To_Local (Places (I).Lat, Places (I).Lon, X, Z);
                              D := Sqrt ((Float (X) - Fare_X) ** 2 + (Float (Z) - Fare_Z) ** 2);
                              if D >= Lo and then D <= Hi then
                                 Seen := Seen + 1;
                                 if Rnd < 1.0 / Float (Seen) then   --  one at random
                                    Chosen := I;
                                 end if;
                              end if;
                           end;
                        end loop;
                        if Chosen = 0 then
                           Chosen := Places'First + Natural (Float'Floor (Rnd * Float (Places'Length - 1)));
                        end if;
                        declare
                           X, Z : Long_Float;
                           Found2 : Boolean;
                           RX, RZ, RH : Float;
                        begin
                           Geo.To_Local (Places (Chosen).Lat, Places (Chosen).Lon, X, Z);
                           Nearest_Road (Float (X), Float (Z), Found2, RX, RZ, RH);
                           Dest_X := (if Found2 then RX else Float (X));
                           Dest_Z := (if Found2 then RZ else Float (Z));
                           Dest_Name := Places (Chosen).Name;
                        end;
                     end;
                     Waiting := True;
                     Set_Goal (Pick_X, Pick_Z, "Pick up " & To_String (Who));
                     return;
                  end if;
               end;
            end if;
         end;
      end loop;
      Look_Wait := 1.0;   --  nobody this time: look again in a moment
   end Look_For_Fare;

   ---------------------------------------------------------------------------

   procedure Start_Shift (Player : Car.State) is
   begin
      if not Seeded then
         Ada.Numerics.Float_Random.Reset (Gen);
         Seeded := True;
      end if;
      Total := 0.0;
      Sum_Meter := 0.0;
      Sum_Tips := 0.0;
      Sum_Bonus := 0.0;
      Sum_Fines := 0.0;
      Km := 0.0;
      Best := 0.0;
      Shift_Time := 0.0;
      Rides := 0;
      Police.On := False;
      Warn_Time := 0.0;
      Said_Time := 0.0;
      Next_Check := (if Test ("PARIS_TAXI_POLICE") then 3.0
                     else (90.0 + 210.0 * Rnd) / Float'Max (0.05, Config.Get ("taxi_police", 1.0)));
      Me_X := Player.X;
      Me_Z := Player.Z;
      Current := Finding;
      Waiting := False;
      Look_Wait := 0.0;
   end Start_Shift;

   procedure Next_Fare (Player : Car.State) is
   begin
      if Current = Paid then
         Me_X := Player.X;
         Me_Z := Player.Z;
         Current := Finding;
         Waiting := False;
         Look_Wait := 0.0;
      end if;
   end Next_Fare;

   procedure End_Shift is
   begin
      if Current /= Off then
         Current := Summary;
         Police.On := False;
         Goal_Name := Null_Unbounded_String;
         Goal_Serial := Goal_Serial + 1;
      end if;
   end End_Shift;

   procedure Close is
   begin
      Current := Off;
      Police.On := False;
      Goal_Serial := Goal_Serial + 1;
   end Close;

   procedure Impact (Loss : Float) is
   begin
      if Current /= Carrying then
         return;
      end if;
      if Pending_Time <= 0.0 then
         Pending_Time := 0.12;
      end if;
      Pending := Pending + Loss;
   end Impact;

   function Bonus_Now return Float is
     (Bonus_Max * Float'Max (0.0, 1.0 - Elapsed / Float'Max (1.0, Allowed)));

   function Meter_Now return Float is
     (Float'Max (7.30, 4.40 + Driven / 1000.0 * Per_Km));

   procedure Board (Player : Car.State; Hour : Float; Sunday : Boolean) is
      Route : Road_Network.Route_Vectors.Vector;
      Found : Boolean;
      L     : Float := 0.0;
   begin
      Road_Network.Find_Route (Player.X, Player.Z, Player.Heading, Dest_X, Dest_Z, Route, Found);
      if Found then
         for K in Route.First_Index + 1 .. Route.Last_Index loop
            L := L + Sqrt ((Route (K).X - Route (K - 1).X) ** 2 + (Route (K).Z - Route (K - 1).Z) ** 2);
         end loop;
      else
         L := 1.4 * Sqrt ((Dest_X - Player.X) ** 2 + (Dest_Z - Player.Z) ** 2);
      end if;
      --  time at about 23 km/h (Paris, lights, traffic), and a bonus that
      --  melts away over that time
      Allowed := L / 6.5 + 30.0;
      Bonus_Max := 3.0 + L / 250.0;
      Elapsed := 0.0;
      Driven := 0.0;
      Mood := 1.0;
      Ride_Fines := 0.0;
      Pending := 0.0;
      Pending_Time := 0.0;
      Slow_Time := 0.0;
      Complain_Wait := 8.0;
      --  tarif A in the daytime on weekdays, B in the evening, at night
      --  and on Sundays
      if not Sunday and then Hour >= 10.0 and then Hour < 17.0 then
         Tariff := 'A';
         Per_Km := 1.32;
      else
         Tariff := 'B';
         Per_Km := 1.65;
      end if;
      Current := Carrying;
      Waiting := False;
      Set_Goal (Dest_X, Dest_Z, To_String (Dest_Name));
      Sound.Effect (Sound.Thud, 0.35, 0.0);   --  the door
      declare
         Where : constant String := To_String (Dest_Name);
         --  "the Louvre" -> "Le Louvre" is too much French; the name will do
      begin
         case Who_Kind is
            when Tourist =>
               Say ("Hello! Er... " & Where & ", please?", "(a tourist: they speak English)");
            when Party =>
               Say ("Salut ! " & Where & ", et vite !", "Hi! " & Where & ", and quickly!");
            when Business =>
               Say ("Bonjour. " & Where & ", je suis pressé.", "Hello. " & Where & ", I'm in a hurry.");
            when Elderly =>
               Say ("Bonjour, jeune homme. " & Where & ", s'il vous plaît.",
                    "Hello, young man. " & Where & ", please.");
         end case;
      end;
   end Board;

   procedure Pay is
      Late : constant Boolean := Elapsed > Allowed + 30.0;
      Tip  : Float := (if Mood < 0.25 then 0.0 else Meter_Now * Tip_Rate (Who_Kind) * Mood);
      Ride : Float;
   begin
      if Who_Kind = Business and then Late then
         Tip := 0.0;
      end if;
      Last_Meter := Meter_Now;
      Last_Tip := Tip;
      Last_Bonus := Bonus_Now;
      Last_Fines := Ride_Fines;
      Last_Mood := Mood;
      Last_Late := Late;
      Last_Dest := Dest_Name;
      Ride := Last_Meter + Last_Tip + Last_Bonus;
      Total := Total + Ride;
      Sum_Meter := Sum_Meter + Last_Meter;
      Sum_Tips := Sum_Tips + Last_Tip;
      Sum_Bonus := Sum_Bonus + Last_Bonus;
      Km := Km + Driven / 1000.0;
      Best := Float'Max (Best, Ride - Ride_Fines);
      Rides := Rides + 1;
      if Mood >= 0.5 then
         Say ("Merci beaucoup, bonne journée !", "Thank you very much, have a nice day!");
      elsif Mood >= 0.25 then
         Say ("Merci.", "Thanks.");
      else
         Say ("Enfin ! Plus jamais.", "At last! Never again.");
      end if;
      Sound.Effect (Sound.Go_Beep, 0.6, 0.0);
      Current := Paid;
      Goal_Name := Null_Unbounded_String;
      Goal_Serial := Goal_Serial + 1;
   end Pay;

   ---------------------------------------------------------------------------
   --  The police
   ---------------------------------------------------------------------------

   procedure Place_Police (Player : Car.State) is
      F : constant Vec3 := Car.Forward (Player);
      Ahead : constant Float := 170.0 + 60.0 * Rnd;
      Found : Boolean;
      RX, RZ, RH : Float;
   begin
      Road_Network.Nearest_Road (Player.X + Ahead * F.X, Player.Z + Ahead * F.Z, Found, RX, RZ, RH);
      if not Found or else (RX - Player.X) ** 2 + (RZ - Player.Z) ** 2 < 110.0 ** 2 then
         Next_Check := 2.0;   --  not here: try again in a moment
         return;
      end if;
      declare
         RF : constant Vec3 := (Sin (RH), 0.0, -Cos (RH));   --  along the road
         RR : constant Vec3 := (Cos (RH), 0.0, Sin (RH));    --  to its right
         Side : constant Float := (if Rnd < 0.5 then 1.0 else -1.0);
         Look : Vec3;
      begin
         Police := (On => True, Seen => False, Done => False, Life => 0.0,
                    CX => RX + Side * 3.6 * RR.X, CZ => RZ + Side * 3.6 * RR.Z,
                    H => (if Side > 0.0 then RH else RH + Ada.Numerics.Pi),
                    OX => RX + Side * 5.4 * RR.X - 2.5 * RF.X,
                    OZ => RZ + Side * 5.4 * RR.Z - 2.5 * RF.Z,
                    Face => 0.0);
         --  the officer faces the street and the oncoming cars
         Look := Normalize ((-Side) * RR - 0.6 * (Side * RF));
         Police.Face := Arctan (Look.X, -Look.Z);
      end;
      Next_Check := (300.0 + 300.0 * Rnd) / Float'Max (0.05, Config.Get ("taxi_police", 1.0));
   end Place_Police;

   procedure Fine (Player : Car.State) is
      Speed  : constant Natural := Natural (Kmh (Player));
      Excess : constant Integer := Speed - Here_Limit;
      Amount : constant Float :=
        (if Excess <= 20 then 45.0 elsif Excess <= 40 then 135.0 else 375.0)
        * Config.Get ("taxi_fines", 1.0);
      Img    : constant String := Ada.Strings.Fixed.Trim (Natural'Image (Speed), Ada.Strings.Left);
      Lim    : constant String := Ada.Strings.Fixed.Trim (Natural'Image (Here_Limit), Ada.Strings.Left);
   begin
      Total := Total - Amount;
      Sum_Fines := Sum_Fines + Amount;
      if Current = Carrying then
         Ride_Fines := Ride_Fines + Amount;
         if Who_Kind = Elderly then
            Mood := Mood - 0.3;
         end if;
         Say ((if Who_Kind = Party then "Ha ha ! La police !" else "Oh là là... la police !"),
              "Oh dear... the police!");
      end if;
      Warn := +("!CONTRÔLE DE VITESSE|" & Img & " km/h where " & Lim & " is allowed: a fine of "
                & Money (Amount));
      Warn_Time := 6.0;
      Sound.Effect (Sound.Go_Beep, 1.0, 0.0);
   end Fine;

   function Warning return String is
     (if Current /= Off and then Warn_Time > 0.0 then To_String (Warn) else "");

   ---------------------------------------------------------------------------

   procedure Update (Dt : Float; Player : Car.State; Hour : Float; Sunday : Boolean) is
   begin
      if Current = Off then
         return;
      end if;
      Me_X := Player.X;
      Me_Z := Player.Z;
      Said_Time := Float'Max (0.0, Said_Time - Dt);
      Warn_Time := Float'Max (0.0, Warn_Time - Dt);
      Complain_Wait := Float'Max (0.0, Complain_Wait - Dt);
      if Current = Summary then
         return;
      end if;
      Shift_Time := Shift_Time + Dt;

      --  the speed limit of the street here
      Limit_Wait := Limit_Wait - Dt;
      if Limit_Wait <= 0.0 then
         Limit_Wait := 0.2;
         Here_Limit := Road_Network.Limit_At (Player.X, Player.Z, Player.Heading);
      end if;
      Too_Fast := Here_Limit > 0 and then Kmh (Player) > Float (Here_Limit) + 2.0;

      case Current is
         when Finding =>
            if not Waiting then
               Look_Wait := Look_Wait - Dt;
               if Look_Wait <= 0.0 then
                  Look_For_Fare (Hour);
               end if;
            elsif (Player.X - Fare_X) ** 2 + (Player.Z - Fare_Z) ** 2 < 9.0 ** 2
              and then abs Player.Speed < 1.5
            then
               Board (Player, Hour, Sunday);
            end if;

         when Carrying =>
            Elapsed := Elapsed + Dt;
            Driven := Driven + abs Player.Speed * Dt;
            --  a knock is over: how did they take it?
            if Pending_Time > 0.0 then
               Pending_Time := Pending_Time - Dt;
               if Pending_Time <= 0.0 then
                  if Pending > 1.5 then
                     Mood := Mood - Float'Min (0.5, Pending / 12.0 * Knock_Fuss (Who_Kind));
                     Say ("Aïe ! Attention !", "Ouch! Careful!");
                     Complain_Wait := 6.0;
                  end if;
                  Pending := 0.0;
               end if;
            end if;
            declare
               Over : constant Boolean :=
                 Here_Limit > 0 and then Kmh (Player) > Float (Here_Limit) + 5.0;
            begin
               case Who_Kind is
                  when Elderly =>
                     if Over then
                        Mood := Mood - 0.05 * Dt;
                        if Complain_Wait = 0.0 then
                           Say ("Doucement, jeune homme !", "Gently, young man!");
                           Complain_Wait := 9.0;
                        end if;
                     end if;
                  when Tourist =>
                     if Over then
                        Mood := Mood - 0.015 * Dt;
                     end if;
                  when Business =>
                     if Elapsed > Allowed then
                        Mood := Mood - 0.03 * Dt;
                     end if;
                     Slow_Time := (if abs Player.Speed < 5.0 then Slow_Time + Dt else 0.0);
                     if Complain_Wait = 0.0 and then Bonus_Now < 0.5 * Bonus_Max
                       and then Slow_Time > 4.0
                     then
                        Say ("Plus vite, je suis pressé !", "Faster, I'm in a hurry!");
                        Complain_Wait := 12.0;
                     end if;
                  when Party =>
                     if Over then
                        Mood := Float'Min (1.0, Mood + 0.02 * Dt);
                        if Complain_Wait = 0.0 then
                           Say ("Plus vite ! Plus vite !", "Faster! Faster!");
                           Complain_Wait := 15.0;
                        end if;
                     end if;
               end case;
            end;
            Mood := Float'Max (0.0, Float'Min (1.0, Mood));
            --  there: stop near the place
            if (Player.X - Dest_X) ** 2 + (Player.Z - Dest_Z) ** 2 < 20.0 ** 2
              and then abs Player.Speed < 2.0
            then
               Pay;
            end if;

         when others =>
            null;
      end case;

      --  the police: now and then a check somewhere ahead of you
      if Current in Finding | Carrying then
         if Police.On then
            declare
               D2 : constant Float := (Player.X - Police.OX) ** 2 + (Player.Z - Police.OZ) ** 2;
            begin
               Police.Life := Police.Life + Dt;
               if D2 < 80.0 ** 2 then
                  Police.Seen := True;
               end if;
               if not Police.Done and then D2 < 30.0 ** 2 and then Here_Limit > 0
                 and then Kmh (Player) > Float (Here_Limit) + 5.0
               then
                  Police.Done := True;
                  Fine (Player);
               end if;
               if (Police.Seen and then D2 > 250.0 ** 2) or else Police.Life > 240.0 then
                  Police.On := False;
               end if;
            end;
         else
            Next_Check := Next_Check - Dt;
            if Next_Check <= 0.0 then
               Place_Police (Player);
            end if;
         end if;
      end if;
   end Update;

   ---------------------------------------------------------------------------
   --  On the screen
   ---------------------------------------------------------------------------

   function Hud_Text return String is
      Light : constant String :=
        (if Current = Carrying then "<span foreground='#ff5040'>&#x25CF; occupé</span>"
         else "<span foreground='#5cff7a'>&#x25CF; libre</span>");
      Line : UString;
   begin
      if Current not in Finding | Carrying then
         return "";
      end if;
      if Current = Finding then
         if Waiting then
            Append (Line, "   " & To_String (Who) & " is waiting, "
                    & Ada.Strings.Fixed.Trim
                      (Integer'Image (Integer (Sqrt ((Fare_X - Me_X) ** 2 + (Fare_Z - Me_Z) ** 2))),
                       Ada.Strings.Left) & " m away");
         else
            Append (Line, "   looking for a fare...");
         end if;
      else
         Append (Line, "   to " & To_String (Dest_Name)
                 & "   meter " & Money (Meter_Now) & " (tarif " & Tariff & ")"
                 & "   bonus " & Money (Bonus_Now));
      end if;
      return "<span font_family='sans' weight='bold' foreground='white' background='#000000a0'>"
        & "  TAXI  " & Light & To_String (Line) & "   shift " & Money (Total) & "  </span>"
        & (if Said_Time > 0.0 and then Current = Carrying then
             LF & "<span font_family='sans' foreground='white' background='#000000a0'>  &#x201C;"
             & To_String (Said_Fr) & "&#x201D;  <i>" & To_String (Said_En) & "</i>  </span>"
           else "");
   end Hud_Text;

   function Panel_Text return String is
      function Row (Label : String; V : Float; Note : String := "") return String is
         M : constant String := Money (V);
      begin
         return "  " & Label & (1 .. Natural'Max (1, 12 - Label'Length) => ' ')
           & (1 .. Natural'Max (0, 10 - M'Length + 1) => ' ') & M
           & (if Note /= "" then "  " & Note else "") & LF;
      end Row;
   begin
      if Current = Paid then
         return "<span font_family='monospace'><b><span foreground='#ffd27a'>Ride done: "
           & To_String (Last_Dest) & "</span></b>" & LF & LF
           & Row ("Meter", Last_Meter)
           & Row ("Tip", Last_Tip,
                  (if Last_Tip = 0.0 and then Last_Late then "(late)"
                   elsif Last_Mood >= 0.8 then "(delighted)"
                   elsif Last_Mood >= 0.5 then "(pleased)"
                   elsif Last_Mood >= 0.25 then "(not happy)" else "(furious)"))
           & Row ("Bonus", Last_Bonus)
           & (if Last_Fines > 0.0 then Row ("Fines", -Last_Fines) else "")
           & LF
           & Row ("This ride", Last_Meter + Last_Tip + Last_Bonus - Last_Fines)
           & Row ("Shift", Total)
           & LF & "<span foreground='#aab'>  Enter: next fare    Esc: end the shift</span></span>";
      elsif Current = Summary then
         return "<span font_family='monospace'><b><span foreground='#ffd27a'>The shift is over</span></b>"
           & LF & LF
           & "  Rides" & (1 .. 7 => ' ') & Natural'Image (Rides) & LF
           & "  With passengers" & Natural'Image (Natural (Km * 10.0) / 10) & "."
           & Ada.Strings.Fixed.Trim (Natural'Image (Natural (Km * 10.0) mod 10), Ada.Strings.Left) & " km"
           & LF & "  On the road " & Natural'Image (Natural (Shift_Time / 60.0)) & " min" & LF & LF
           & Row ("Meter", Sum_Meter)
           & Row ("Tips", Sum_Tips)
           & Row ("Bonus", Sum_Bonus)
           & Row ("Fines", -Sum_Fines)
           & LF
           & Row ("Earned", Total)
           & Row ("Best ride", Best)
           & LF & "<span foreground='#aab'>  Enter or Esc: back to the city</span></span>";
      end if;
      return "";
   end Panel_Text;

   ---------------------------------------------------------------------------

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint; Player : Car.State; Time : Float) is
   begin
      if Current = Off then
         return;
      end if;
      if not Built then
         Meshes.Start;
         Meshes.Box (-0.3, 0.3, 1.42, 1.58, -0.12, 0.12, 50.0);   --  the TAXI sign
         Meshes.Finish (Lamp_Mesh);
         Meshes.Start;
         Meshes.Box (-0.6, 0.6, 1.42, 1.55, -0.16, 0.16, 50.0);   --  a light bar
         Meshes.Finish (Bar_Mesh);
         Built := True;
      end if;

      --  the sign on your roof: green free, red taken
      if Current /= Summary then
         Shaders.Set (Skin, (if Current = Carrying then Vec3'(1.0, 0.12, 0.08)
                             else Vec3'(0.2, 1.0, 0.35)));
         Shaders.Set (Model, Car.Model_Matrix (Player));
         Meshes.Draw (Lamp_Mesh);
      end if;

      --  the police car, its lights going, and the officer
      if Police.On then
         Shaders.Set (Paint, Vec3'(0.93, 0.93, 0.95));
         Shaders.Set (Model, Car.Model_Matrix (Car.On_Ground (Police.CX, Police.CZ, Police.H)));
         Car.Draw_Model (Car.Modern);
         Shaders.Set (Skin, (if Time - Float'Floor (Time) < 0.5 then Vec3'(0.15, 0.35, 1.0)
                             else Vec3'(0.04, 0.07, 0.3)));
         Meshes.Draw (Bar_Mesh);
      end if;

      Figures.Set_Locations ((Model, Paint, Skin, Legs));
      if Police.On then
         Figures.Person
           (Translation ((Police.OX, Terrain.Height (Police.OX, Police.OZ), Police.OZ))
            * Rotation_Y (-Police.Face),
            (0.1, 0.13, 0.28), (0.8, 0.62, 0.5), (0.08, 0.1, 0.22),
            Hat => Figures.Kepi, Hat_Colour => (0.1, 0.12, 0.3), Arm_Up => -1.5);
      end if;
      --  the fare, waving
      if Current = Finding and then Waiting then
         Figures.Person
           (Translation ((Fare_X, Terrain.Height (Fare_X, Fare_Z), Fare_Z)) * Rotation_Y (-Fare_Face),
            Fare_Shirt, Fare_Skin, Fare_Legs, Arm_Up => -2.5 + 0.35 * Sin (Time * 7.0));
      end if;
   end Draw;

end Taxi;
