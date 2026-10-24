--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Containers.Vectors;
with Ada.Environment_Variables;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;
with Ada.Strings.Fixed;
with Ada.Text_IO;

with Addresses;
with Almanac;
with Figures;
with Geo;
with Math3D;
with Meshes;
with Road_Network;
with Shaders;
with Sound;
with Terrain;

package body Rounds is

   use Ada.Strings.Unbounded;
   use Ada.Numerics.Elementary_Functions;
   use Math3D;

   Gen : Ada.Numerics.Float_Random.Generator;
   function Rnd return Float is (Ada.Numerics.Float_Random.Random (Gen));

   type Bakery is record
      Name : Unbounded_String;
      X, Z : Float := 0.0;
      Best : Float := 0.0;
   end record;
   package Bakery_Vectors is new Ada.Containers.Vectors (Positive, Bakery);
   Bakeries : Bakery_Vectors.Vector;

   --  The customers of the morning
   type Customer_Kind is (Cafe, Hotel, Restaurant, School);
   type Customer is record
      Kind      : Customer_Kind := Cafe;
      Name      : Unbounded_String;
      Address   : Unbounded_String;
      X, Z      : Float := 0.0;    --  on the road before the door
      DX, DZ    : Float := 0.0;    --  where they wait, on the pavement
      Face      : Float := 0.0;    --  towards the road
      Loaves    : Positive := 4;
      Opens     : Float := 6.5;    --  the hour they open: the bread before
      Delivered : Boolean := False;
      At_Hour   : Float := 0.0;
      Given     : Natural := 0;
      Tip       : Float := 0.0;
      Skin      : Vec3 := (0.8, 0.62, 0.5);
   end record;
   Max_Customers : constant := 6;
   Customers : array (1 .. Max_Customers) of Customer;
   N_Customers : Natural := 0;

   type Name_List is array (Positive range <>) of Unbounded_String;
   function "+" (S : String) return Unbounded_String renames To_Unbounded_String;
   Names : constant array (Customer_Kind) of access constant Name_List :=
     (Cafe => new Name_List'(+"Café des Arts", +"Le Petit Zinc", +"Bar du Marché", +"Café du Coin",
                             +"Le Rendez-vous", +"Café de la Place", +"Le Bistrot d'en face"),
      Hotel => new Name_List'(+"Hôtel du Lys", +"Hôtel Beauséjour", +"Hôtel du Square",
                              +"Hôtel des Voyageurs"),
      Restaurant => new Name_List'(+"Chez Marcel", +"Chez Paulette", +"Le Bouchon", +"La Table d'Hélène",
                                   +"Le Vieux Comptoir"),
      School => new Name_List'(+"École maternelle (the canteen)", +"Crèche des Lutins"));

   Current   : Phase_Kind := Off;
   Which     : Natural := 0;
   Load_Time : Float := 0.0;
   Now       : Float := 6.0;     --  the hour
   Start_At  : Float := 6.0;
   Me_X, Me_Z : Float := 0.0;
   Shop_X, Shop_Z, Shop_DX, Shop_DZ, Shop_Face : Float := 0.0;   --  the bakery: road, door
   Crate     : Natural := 0;     --  baguettes left in the crate
   Broken, Broken_All : Natural := 0;
   Knock_Wait : Float := 0.0;
   Tips      : Float := 0.0;
   New_Best  : Boolean := False;
   Old_Best  : Float := 0.0;
   Serial    : Natural := 0;
   Target    : Natural := 0;
   Said      : Unbounded_String;
   Said_Time : Float := 0.0;

   Pace : constant := 1.0 / 360.0;   --  a game hour in six minutes
   Reach : constant := 10.0;         --  how near the door to stop

   Arrow_M : Meshes.Mesh;
   Built   : Boolean := False;

   function File return String is
     (Ada.Environment_Variables.Value ("HOME", ".") & "/.derive_rounds");

   function Count return Natural is (Natural (Bakeries.Length));
   function Name (I : Positive) return String is (To_String (Bakeries (I).Name));
   function Best (I : Positive) return Float is (Bakeries (I).Best);
   function Phase return Phase_Kind is (Current);
   function Active return Boolean is (Current /= Off);
   function Holding return Boolean is (Current = Loading);
   function Clock_Pace return Float is (if Current in Loading | Riding then Pace else 0.0);

   function Clock_Image (H : Float) return String is
      M  : constant Natural := Natural (Float'Floor (H * 60.0)) mod (24 * 60);
      S2 : constant String := Natural'Image (100 + M mod 60);
   begin
      return Ada.Strings.Fixed.Trim (Natural'Image (M / 60), Ada.Strings.Left) & ":" & S2 (S2'Last - 1 .. S2'Last);
   end Clock_Image;

   --  S cut or padded to N letters (UTF-8: the accents take two bytes)
   function Pad (S : String; N : Natural) return String is
      Letters : Natural := 0;
   begin
      for I in S'Range loop
         if Character'Pos (S (I)) / 64 /= 2 then   --  not a continuation byte
            if Letters = N then
               return S (S'First .. I - 1);
            end if;
            Letters := Letters + 1;
         end if;
      end loop;
      return S & (1 .. N - Letters => ' ');
   end Pad;

   function Euros (E : Float) return String is
      C  : constant Natural := Natural (Float'Rounding (Float'Max (0.0, E) * 100.0));
      S2 : constant String := Natural'Image (100 + C mod 100);
   begin
      return Ada.Strings.Fixed.Trim (Natural'Image (C / 100), Ada.Strings.Left) & "." & S2 (S2'Last - 1 .. S2'Last)
        & " €";
   end Euros;

   ---------------------------------------------------------------------------

   procedure Read_Best is
      F : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, File);
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            L   : constant String := Ada.Text_IO.Get_Line (F);
            Tab : constant Natural := Ada.Strings.Fixed.Index (L, (1 => ASCII.HT));
         begin
            if Tab > 0 then
               for B of Bakeries loop
                  if To_String (B.Name) = L (Tab + 1 .. L'Last) then
                     B.Best := Float'Value (L (L'First .. Tab - 1));
                  end if;
               end loop;
            end if;
         exception
            when Constraint_Error => null;
         end;
      end loop;
      Ada.Text_IO.Close (F);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
   end Read_Best;

   procedure Write_Best is
      F : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, File);
      Ada.Text_IO.Put_Line (F, "# Dérive: your best morning rounds (euros in tips <tab> bakery)");
      for B of Bakeries loop
         if B.Best > 0.0 then
            Ada.Text_IO.Put_Line (F, Ada.Strings.Fixed.Trim (Float'Image (B.Best), Ada.Strings.Left)
                                  & ASCII.HT & To_String (B.Name));
         end if;
      end loop;
      Ada.Text_IO.Close (F);
   exception
      when others => null;
   end Write_Best;

   procedure Load is
      F : Ada.Text_IO.File_Type;
   begin
      Bakeries.Clear;
      Ada.Numerics.Float_Random.Reset (Gen);
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, "data/bakeries.txt");
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            L  : constant String := Ada.Text_IO.Get_Line (F);
            S1 : constant Natural := Ada.Strings.Fixed.Index (L, " ");
            S2 : constant Natural := (if S1 > 0 then Ada.Strings.Fixed.Index (L, " ", S1 + 1) else 0);
            X, Z : Long_Float;
         begin
            if L'Length > 0 and then L (L'First) /= '#' and then S2 > 0 then
               Geo.To_Local (Long_Float'Value (L (L'First .. S1 - 1)), Long_Float'Value (L (S1 + 1 .. S2 - 1)), X, Z);
               Bakeries.Append ((+L (S2 + 1 .. L'Last), Float (X), Float (Z), 0.0));
            end if;
         exception
            when Constraint_Error => null;
         end;
      end loop;
      Ada.Text_IO.Close (F);
      Read_Best;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
   end Load;

   ---------------------------------------------------------------------------
   --  Setting out

   --  How far from the middle of the road the pavement is, at (X, Z)
   function Kerb_Offset (X, Z : Float) return Float is
      Best_D : Float := Float'Last;
      Width  : Float := 10.0;
      procedure Visit (AX, AZ, BX, BZ, W : Float; Named : Boolean) is
         pragma Unreferenced (Named);
         DX : constant Float := BX - AX;
         DZ : constant Float := BZ - AZ;
         L2 : constant Float := Float'Max (1.0E-4, DX * DX + DZ * DZ);
         U  : constant Float := Float'Max (0.0, Float'Min (1.0, ((X - AX) * DX + (Z - AZ) * DZ) / L2));
         D  : constant Float := (AX + U * DX - X) ** 2 + (AZ + U * DZ - Z) ** 2;
      begin
         if D < Best_D then
            Best_D := D;
            Width := W;
         end if;
      end Visit;
      procedure Each is new Road_Network.For_Segments_Near (Visit);
   begin
      Each (X, Z, 20.0);
      return Width / 2.0 + 1.3;
   end Kerb_Offset;

   --  The road before a house, and the pavement on its side
   procedure Door_Of (HX, HZ : Float; Ok : out Boolean; RX, RZ, DX, DZ, Face : out Float) is
      RH : Float;
   begin
      Road_Network.Nearest_Road (HX, HZ, Ok, RX, RZ, RH);
      DX := HX;
      DZ := HZ;
      Face := 0.0;
      if Ok then
         declare
            VX : Float := HX - RX;
            VZ : Float := HZ - RZ;
            D  : constant Float := Sqrt (VX * VX + VZ * VZ);
            K  : constant Float := Kerb_Offset (RX, RZ);
         begin
            if D > 60.0 then
               Ok := False;   --  a house far back from any street
               return;
            end if;
            if D < 0.1 then
               VX := Cos (RH);   --  across the road
               VZ := Sin (RH);
            else
               VX := VX / D;
               VZ := VZ / D;
            end if;
            DX := RX + K * VX;
            DZ := RZ + K * VZ;
            Face := Arctan (-VX, VZ);   --  looking at the road
         end;
      end if;
   end Door_Of;

   function Sunrise return Float is
      H : Float := 3.0;
   begin
      while H < 10.0 and then Almanac.Sun (H).Y < 0.0 loop
         H := H + 1.0 / 60.0;
      end loop;
      return H;
   end Sunrise;

   procedure Choose_Customers is
      Taken : array (Customer_Kind) of Natural := (others => 0);
      Used_Names : array (Customer_Kind, 1 .. 8) of Boolean := (others => (others => False));
      B : Bakery renames Bakeries (Which);
   begin
      N_Customers := 0;
      for Attempt in 1 .. 200 loop
         exit when N_Customers = Max_Customers;
         declare
            Found : Boolean;
            Where : Addresses.Result;
            HX, HZ : Float;
            Label : Unbounded_String;
            Ok : Boolean;
            RX, RZ, DX, DZ, Face : Float;
         begin
            Addresses.Pick_Near (B.X, B.Z, 150.0, 700.0, Rnd, Found, Where);
            if Found then
               HX := Where.X;
               HZ := Where.Z;
               Label := +Where.Label (1 .. Where.Last);
            else
               --  without house numbers: somewhere along a street
               declare
                  W, Pos : Natural;
               begin
                  Road_Network.Pick_Segment (B.X, B.Z, 150.0, 700.0, Rnd, Rnd, Rnd, Found, W, Pos);
                  if Found then
                     HX := Road_Network.Point (W, Pos).X;
                     HZ := Road_Network.Point (W, Pos).Z;
                     Label := +Road_Network.Street_At (HX, HZ);
                  end if;
               end;
            end if;
            if Found then
               Door_Of (HX, HZ, Ok, RX, RZ, DX, DZ, Face);
               --  apart from each other, and not by the bakery
               if Ok and then (RX - Shop_X) ** 2 + (RZ - Shop_Z) ** 2 > 140.0 ** 2 then
                  for I in 1 .. N_Customers loop
                     if (RX - Customers (I).X) ** 2 + (RZ - Customers (I).Z) ** 2 < 110.0 ** 2 then
                        Ok := False;
                     end if;
                  end loop;
               end if;
               if Ok and then (RX - Shop_X) ** 2 + (RZ - Shop_Z) ** 2 > 140.0 ** 2 then
                  declare
                     R : constant Float := Rnd;
                     K : constant Customer_Kind :=
                       (if Taken (School) = 0 and then R < 0.12 then School
                        elsif R < 0.55 then Cafe elsif R < 0.8 then Hotel
                        elsif Taken (Restaurant) < 2 then Restaurant else Cafe);
                     L : constant Name_List := Names (K).all;
                     P : Positive := L'First + Natural'Min (L'Length - 1, Natural (Float'Floor (Rnd * Float (L'Length))));
                     C : Customer;
                  begin
                     for Try in 1 .. L'Length loop
                        exit when not Used_Names (K, P);
                        P := (if P = L'Last then L'First else P + 1);
                     end loop;
                     Used_Names (K, P) := True;
                     Taken (K) := Taken (K) + 1;
                     C.Kind := K;
                     C.Name := L (P);
                     C.Address := Label;
                     C.X := RX;
                     C.Z := RZ;
                     C.DX := DX;
                     C.DZ := DZ;
                     C.Face := Face;
                     C.Loaves := (case K is
                                     when Cafe       => 3 + Natural (Float'Floor (Rnd * 4.0)),
                                     when Hotel      => 6 + Natural (Float'Floor (Rnd * 5.0)),
                                     when Restaurant => 2 + Natural (Float'Floor (Rnd * 3.0)),
                                     when School     => 10 + Natural (Float'Floor (Rnd * 4.0)));
                     C.Skin := (case Natural (Float'Floor (Rnd * 3.99)) is
                                   when 0 => (0.86, 0.68, 0.56), when 1 => (0.76, 0.57, 0.44),
                                   when 2 => (0.58, 0.40, 0.29), when others => (0.40, 0.27, 0.19));
                     N_Customers := N_Customers + 1;
                     Customers (N_Customers) := C;
                  end;
               end if;
            end if;
         end;
      end loop;

      --  When they open: along the quickest way round (the nearest next),
      --  with time to spare, on the quarter hour or the five minutes
      declare
         Seen : array (1 .. Max_Customers) of Boolean := (others => False);
         PX : Float := Shop_X;
         PZ : Float := Shop_Z;
         Secs : Float := 0.0;
      begin
         for Step in 1 .. N_Customers loop
            declare
               Next : Natural := 0;
               Near : Float := Float'Last;
            begin
               for I in 1 .. N_Customers loop
                  if not Seen (I) then
                     declare
                        D : constant Float := Sqrt ((Customers (I).X - PX) ** 2 + (Customers (I).Z - PZ) ** 2);
                     begin
                        if D < Near then
                           Near := D;
                           Next := I;
                        end if;
                     end;
                  end if;
               end loop;
               Seen (Next) := True;
               Secs := Secs + Near * 1.45 / 8.5 + 10.0;   --  the streets wind; stopping
               declare
                  Due : constant Float := Start_At + (Secs * 1.35 + 30.0) * Pace;
                  Fives : constant Float := Float'Ceiling (Due * 12.0);
               begin
                  Customers (Next).Opens := Fives / 12.0;
               end;
               PX := Customers (Next).X;
               PZ := Customers (Next).Z;
            end;
         end loop;
      end;
   end Choose_Customers;

   procedure Begin_It (Player : out Car.State; Hour : in out Float) is
      B : Bakery renames Bakeries (Which);
      Ok : Boolean;
      RH : Float;
   begin
      Door_Of (B.X, B.Z, Ok, Shop_X, Shop_Z, Shop_DX, Shop_DZ, Shop_Face);
      if not Ok then
         Shop_X := B.X;
         Shop_Z := B.Z;
         Shop_DX := B.X;
         Shop_DZ := B.Z;
      end if;
      Road_Network.Nearest_Road (Shop_X, Shop_Z, Ok, Shop_X, Shop_Z, RH);
      if not Ok then
         RH := 0.0;
      end if;
      --  at the kerb by the door, a little before sunrise
      Start_At := Float'Max (4.5, Float'Min (7.25, Sunrise - 0.75));
      Hour := Start_At;
      Now := Hour;
      Choose_Customers;
      Player := Car.On_Ground (Shop_X, Shop_Z, RH);
      Player.Ground := Terrain.Height (Shop_X, Shop_Z);
      Me_X := Shop_X;
      Me_Z := Shop_Z;
      Crate := 3;   --  a few to spare
      for I in 1 .. N_Customers loop
         Crate := Crate + Customers (I).Loaves;
      end loop;
      Broken := 0;
      Broken_All := 0;
      Tips := 0.0;
      New_Best := False;
      Said := Null_Unbounded_String;
      Load_Time := 4.0;
      Current := Loading;
      Target := 0;
      Serial := Serial + 1;
   end Begin_It;

   procedure Start (I : Positive; Player : out Car.State; Hour : in out Float) is
   begin
      Which := I;
      Begin_It (Player, Hour);
   end Start;

   procedure Again (Player : out Car.State; Hour : in out Float) is
   begin
      if Which /= 0 then
         Begin_It (Player, Hour);
      end if;
   end Again;

   procedure Stop is
   begin
      Current := Off;
      Serial := Serial + 1;
   end Stop;

   ---------------------------------------------------------------------------

   procedure Say (S : String) is
   begin
      Said := +S;
      Said_Time := 5.0;
   end Say;

   procedure Impact (Loss : Float) is
   begin
      if Current /= Riding or else Loss < 4.0 or else Knock_Wait > 0.0 or else Crate = 0 then
         return;
      end if;
      declare
         N : constant Natural := Natural'Min (Crate, (if Loss > 9.0 then 2 else 1));
      begin
         Crate := Crate - N;
         Broken := Broken + N;
         Broken_All := Broken_All + N;
         Knock_Wait := 1.0;
         Say ((if N = 1 then "Crack! A baguette broke in the crate" else "Crack! Two baguettes broke"));
      end;
   end Impact;

   --  The customer who opens first, still waiting
   function First_Waiting return Natural is
      Best : Natural := 0;
   begin
      for I in 1 .. N_Customers loop
         if not Customers (I).Delivered
           and then (Best = 0 or else Customers (I).Opens < Customers (Best).Opens)
         then
            Best := I;
         end if;
      end loop;
      return Best;
   end First_Waiting;

   procedure Hand_Over (I : Positive) is
      C : Customer renames Customers (I);
      Late : constant Float := (Now - C.Opens) * 60.0;   --  minutes
      Base : constant Float := 1.0 + 0.25 * Float (C.Loaves);
   begin
      C.Delivered := True;
      C.At_Hour := Now;
      C.Given := Natural'Min (Crate, C.Loaves);
      Crate := Crate - C.Given;
      if C.Given < C.Loaves then
         C.Tip := 0.0;
         Say (To_String (C.Name) & ": ""Il en manque !"" (" & Natural'Image (C.Loaves - C.Given) & " short)");
      elsif Late <= 0.0 then
         C.Tip := Base + (if Late < -8.0 then 0.5 else 0.0);
         Say (To_String (C.Name) & ": "
              & (if Late < -8.0 then """Déjà ! Merci, c'est encore chaud.""" else """Merci, pile à l'heure !""")
              & "  +" & Euros (C.Tip));
      else
         C.Tip := Float'Max (0.0, Base - 0.25 * Late);
         Say (To_String (C.Name) & ": "
              & (if Late > 10.0 then """Enfin ! Les clients attendent depuis l'ouverture.""" else """Un peu juste...""")
              & (if C.Tip > 0.0 then "  +" & Euros (C.Tip) else ""));
      end if;
      Tips := Tips + C.Tip;
      Sound.Effect (Sound.Beep, 0.6, 0.0);
      Serial := Serial + 1;
      if First_Waiting = 0 then
         Current := Done;
         Sound.Effect (Sound.Go_Beep, 0.9, 0.0);
         Old_Best := Bakeries (Which).Best;
         if Tips > Old_Best then
            Bakeries (Which).Best := Tips;
            New_Best := True;
            Write_Best;
         end if;
      end if;
   end Hand_Over;

   procedure Update (Dt : Float; Player : Car.State; Hour : Float) is
   begin
      Now := Hour;
      Me_X := Player.X;
      Me_Z := Player.Z;
      Said_Time := Float'Max (0.0, Said_Time - Dt);
      Knock_Wait := Float'Max (0.0, Knock_Wait - Dt);
      case Current is
         when Off | Done =>
            null;
         when Loading =>
            Load_Time := Load_Time - Dt;
            if Load_Time <= 0.0 then
               Current := Riding;
               Sound.Effect (Sound.Go_Beep, 0.8, 0.0);
               Say ("The crate is full: " & Ada.Strings.Fixed.Trim (Natural'Image (Crate), Ada.Strings.Left)
                    & " baguettes, warm.  Bonne route !");
            end if;
         when Riding =>
            if abs Player.Speed < 2.5 then
               for I in 1 .. N_Customers loop
                  if not Customers (I).Delivered
                    and then ((Customers (I).DX - Me_X) ** 2 + (Customers (I).DZ - Me_Z) ** 2 < Reach ** 2
                              or else (Customers (I).X - Me_X) ** 2 + (Customers (I).Z - Me_Z) ** 2 < Reach ** 2)
                  then
                     Hand_Over (I);
                     exit;
                  end if;
               end loop;
            end if;
            if Current = Riding and then First_Waiting /= Target then
               Target := First_Waiting;
               Serial := Serial + 1;
            end if;
      end case;
   end Update;

   procedure Goal (Serial : out Natural; X, Z : out Float; Name : out Unbounded_String) is
   begin
      Serial := Rounds.Serial;
      X := 0.0;
      Z := 0.0;
      Name := Null_Unbounded_String;
      if Current in Loading | Riding then
         declare
            T : constant Natural := First_Waiting;
         begin
            if T /= 0 then
               X := Customers (T).X;
               Z := Customers (T).Z;
               Name := Customers (T).Name;
            end if;
         end;
      end if;
   end Goal;

   ---------------------------------------------------------------------------

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint; Time : Float) is
      T : constant Natural := First_Waiting;
   begin
      if Current = Off then
         return;
      end if;
      if not Built then
         --  an arrow pointing down
         Meshes.Start;
         Meshes.Box (-0.25, 0.25, 1.2, 2.8, -0.25, 0.25, 50.0);
         declare
            Tip : constant Vec3 := (0.0, 0.0, 0.0);
            C   : constant array (0 .. 3) of Vec3 :=
              ((-0.8, 1.2, -0.8), (0.8, 1.2, -0.8), (0.8, 1.2, 0.8), (-0.8, 1.2, 0.8));
         begin
            for K in 0 .. 3 loop
               Meshes.Quad (C (K), C ((K + 1) mod 4), Tip, Tip, 50.0);
               Meshes.Quad (C ((K + 1) mod 4), C (K), Tip, Tip, 50.0);
            end loop;
         end;
         Meshes.Finish (Arrow_M);
         Built := True;
      end if;

      --  an arrow over each door still waiting: gold over the next
      if Current in Loading | Riding then
         for I in 1 .. N_Customers loop
            if not Customers (I).Delivered then
               declare
                  C : Customer renames Customers (I);
                  D : constant Float := Sqrt ((C.DX - Me_X) ** 2 + (C.DZ - Me_Z) ** 2);
                  S : constant Float := (if I = T then 1.0 + Float'Min (3.0, D / 120.0) else 0.7);
               begin
                  Shaders.Set (Skin, (if I = T then Vec3'(1.0, 0.8, 0.2) else Vec3'(0.55, 0.85, 0.6)));
                  Shaders.Set (Model, Translation ((C.DX, Terrain.Height (C.DX, C.DZ) + 3.2 + 0.3 * Sin (Time * 2.5)
                                                    + 7.0 * (S - 1.0), C.DZ))
                               * Rotation_Y (Time * 1.5) * Scale (S));
                  Meshes.Draw (Arrow_M);
               end;
            end if;
         end loop;
      end if;

      Figures.Set_Locations ((Model, Paint, Skin, Legs));
      --  the baker at the door, in white, waving you off
      if (Shop_DX - Me_X) ** 2 + (Shop_DZ - Me_Z) ** 2 < 200.0 ** 2 then
         Figures.Person
           (Translation ((Shop_DX, Terrain.Height (Shop_DX, Shop_DZ), Shop_DZ)) * Rotation_Y (-Shop_Face),
            (0.93, 0.92, 0.88), (0.8, 0.62, 0.5), (0.85, 0.84, 0.8),
            Hat => Figures.Cap, Hat_Colour => (0.95, 0.95, 0.93),
            Arm_Up => (if Current = Loading then 0.0 else -2.5 + 0.35 * Sin (Time * 6.0)));
      end if;
      --  the customers at their doors: a waiter's white shirt, a hotel
      --  porter's dark coat, a cook's whites, a dinner lady's blue
      for I in 1 .. N_Customers loop
         declare
            C : Customer renames Customers (I);
            D2 : constant Float := (C.DX - Me_X) ** 2 + (C.DZ - Me_Z) ** 2;
         begin
            if D2 < 250.0 ** 2
              and then (not C.Delivered or else (Now - C.At_Hour) / Pace < 6.0)
            then
               Figures.Person
                 (Translation ((C.DX, Terrain.Height (C.DX, C.DZ), C.DZ)) * Rotation_Y (-C.Face),
                  (case C.Kind is
                      when Cafe => (0.92, 0.92, 0.9), when Hotel => (0.12, 0.14, 0.3),
                      when Restaurant => (0.95, 0.95, 0.93), when School => (0.35, 0.55, 0.8)),
                  C.Skin,
                  (case C.Kind is
                      when Cafe => (0.08, 0.08, 0.09), when Hotel => (0.1, 0.11, 0.2),
                      when Restaurant => (0.3, 0.3, 0.32), when School => (0.25, 0.25, 0.3)),
                  Hat => (if C.Kind = Hotel then Figures.Kepi else Figures.None),
                  Hat_Colour => (0.12, 0.14, 0.3),
                  Arm_Up => (if not C.Delivered and then D2 < 60.0 ** 2 then -2.5 + 0.35 * Sin (Time * 7.0)
                             else 0.0));
            end if;
         end;
      end loop;
   end Draw;

   ---------------------------------------------------------------------------

   function Hud_Text return String is
   begin
      if Current not in Loading | Riding then
         return "";
      end if;
      declare
         T : constant Natural := First_Waiting;
         Left : Natural := 0;
         Next : constant String :=
           (if T = 0 then ""
            else "   next: <b>" & To_String (Customers (T).Name) & "</b>, " & To_String (Customers (T).Address)
                 & ", opens " & Clock_Image (Customers (T).Opens)
                 & Natural'Image (Natural (Sqrt ((Customers (T).X - Me_X) ** 2 + (Customers (T).Z - Me_Z) ** 2)))
                 & " m");
      begin
         for I in 1 .. N_Customers loop
            if not Customers (I).Delivered then
               Left := Left + 1;
            end if;
         end loop;
         return "<span font_family='monospace' background='#000000a0' foreground='white'>  "
           & "<b>" & To_String (Bakeries (Which).Name) & "</b>   " & Clock_Image (Now)
           & (if Current = Loading then "   loading the crate..."
              else Next & "   " & Ada.Strings.Fixed.Trim (Natural'Image (Left), Ada.Strings.Left) & " to go")
           & "   crate" & Natural'Image (Crate) & "   tips " & Euros (Tips) & "  "
           & (if Said_Time > 0.0 then (1 => ASCII.LF) & "  " & To_String (Said) & "  " else "")
           & "</span>";
      end;
   end Hud_Text;

   function Banner return String is
   begin
      if Current = Loading then
         return "Au boulot !";
      end if;
      return "";
   end Banner;

   function Panel_Text return String is
      LF : constant String := (1 => ASCII.LF);
      T  : Unbounded_String;
   begin
      if Current /= Done then
         return "";
      end if;
      T := +("<span font_family='monospace'><b><span foreground='#ffd27a'>The morning round, "
             & To_String (Bakeries (Which).Name) & "</span></b>" & LF & LF);
      for I in 1 .. N_Customers loop
         declare
            C : Customer renames Customers (I);
            Late : constant Integer := Integer (Float'Ceiling ((C.At_Hour - C.Opens) * 60.0));
         begin
            Append (T, "  " & Pad (To_String (C.Name), 26) & " "
                    & Ada.Strings.Fixed.Tail (Natural'Image (C.Given), 3) & " at " & Clock_Image (C.At_Hour)
                    & (if C.Given < C.Loaves then "  <span foreground='#ff8a7a'>short</span>"
                       elsif Late > 0 then "  <span foreground='#ff8a7a'>" & Ada.Strings.Fixed.Trim
                         (Integer'Image (Late), Ada.Strings.Left) & " min late</span>"
                       else "  <span foreground='#7fe08a'>on time</span>")
                    & "  " & Euros (C.Tip) & LF);
         end;
      end loop;
      Append (T, LF & "  Tips          " & Euros (Tips) & LF);
      if Broken_All > 0 then
         Append (T, "  Broken        " & Ada.Strings.Fixed.Trim (Natural'Image (Broken_All), Ada.Strings.Left)
                 & (if Broken_All = 1 then " baguette" else " baguettes") & LF);
      end if;
      Append (T, (if New_Best then
                    "  <b><span foreground='#7fe08a'>Best morning!</span></b>"
                    & (if Old_Best > 0.0 then "  (was " & Euros (Old_Best) & ")" else "") & LF
                  else "  Best          " & Euros (Bakeries (Which).Best) & LF));
      Append (T, LF & "<span foreground='#aab'>  Enter: another morning    Esc: back to the city</span></span>");
      return To_String (T);
   end Panel_Text;

end Rounds;
