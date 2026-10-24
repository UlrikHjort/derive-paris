--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Containers.Vectors;
with Ada.Environment_Variables;
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Strings.Fixed;
with Ada.Text_IO;

with Geo;
with Road_Network;
with Sound;
with Terrain;

package body Trials is

   use Ada.Strings.Unbounded;
   use Ada.Numerics.Elementary_Functions;

   Pi : constant := Ada.Numerics.Pi;

   type Point is record
      X, Z : Float := 0.0;
   end record;
   package Point_Vectors is new Ada.Containers.Vectors (Positive, Point);

   type Trial is record
      Name   : Unbounded_String;
      Hour   : Float := -1.0;
      Start  : Point;
      Points : Point_Vectors.Vector;   --  the vias, then the finish
      Best   : Float := 0.0;
   end record;
   package Trial_Vectors is new Ada.Containers.Vectors (Positive, Trial);
   All_Trials : Trial_Vectors.Vector;

   Current  : Phase_Kind := Off;
   Which    : Natural := 0;
   Next_Pt  : Positive := 1;     --  the point to reach next
   Clock    : Float := 0.0;      --  the countdown, then the time
   Time     : Float := 0.0;
   Last_Beep : Integer := 4;
   New_Best : Boolean := False;
   Old_Best : Float := 0.0;
   Serial   : Natural := 0;

   Reach : constant := 25.0;     --  how near a point counts as passed

   function File return String is
     (Ada.Environment_Variables.Value ("HOME", ".") & "/.derive_trials");

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
               for T of All_Trials loop
                  if To_String (T.Name) = L (Tab + 1 .. L'Last) then
                     T.Best := Float'Value (L (L'First .. Tab - 1));
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
      Ada.Text_IO.Put_Line (F, "# Dérive: your best time trials (seconds <tab> run)");
      for T of All_Trials loop
         if T.Best > 0.0 then
            Ada.Text_IO.Put_Line (F, Ada.Strings.Fixed.Trim (Float'Image (T.Best), Ada.Strings.Left)
                                  & ASCII.HT & To_String (T.Name));
         end if;
      end loop;
      Ada.Text_IO.Close (F);
   exception
      when others => null;
   end Write_Best;

   procedure Load is
      F   : Ada.Text_IO.File_Type;
      Cur : Trial;
      Have : Boolean := False;
      procedure Finish is
      begin
         if Have and then Length (Cur.Name) > 0 and then not Cur.Points.Is_Empty then
            All_Trials.Append (Cur);
         end if;
         Cur := (others => <>);
      end Finish;
      function Local (S : String) return Point is
         Sp : constant Natural := Ada.Strings.Fixed.Index (S, " ");
         X, Z : Long_Float;
      begin
         Geo.To_Local (Long_Float'Value (S (S'First .. Sp - 1)), Long_Float'Value (S (Sp + 1 .. S'Last)), X, Z);
         return (Float (X), Float (Z));
      end Local;
   begin
      All_Trials.Clear;
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, "data/trials.txt");
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            L  : constant String := Ada.Text_IO.Get_Line (F);
            Sp : constant Natural := Ada.Strings.Fixed.Index (L, " ");
            W  : constant String := (if Sp > 0 then L (L'First .. Sp - 1) else L);
            R  : constant String := (if Sp > 0 then Ada.Strings.Fixed.Trim (L (Sp + 1 .. L'Last), Ada.Strings.Both)
                                     else "");
         begin
            if L'Length = 0 or else L (L'First) = '#' then
               null;
            elsif L (L'First) = '[' then
               Finish;
               Have := True;
            elsif W = "name" then
               Cur.Name := To_Unbounded_String (R);
            elsif W = "hour" then
               Cur.Hour := Float'Value (R);
            elsif W = "start" then
               Cur.Start := Local (R);
            elsif W = "via" or else W = "finish" then
               Cur.Points.Append (Local (R));
            end if;
         exception
            when Constraint_Error => null;
         end;
      end loop;
      Finish;
      Ada.Text_IO.Close (F);
      Read_Best;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
   end Load;

   function Count return Natural is (Natural (All_Trials.Length));
   function Name (I : Positive) return String is (To_String (All_Trials (I).Name));
   function Best (I : Positive) return Float is (All_Trials (I).Best);
   function Phase return Phase_Kind is (Current);
   function Active return Boolean is (Current /= Off);
   function Holding return Boolean is (Current = Countdown);

   function Time_Image (T : Float) return String is
      Tenths : constant Natural := Natural (Float'Floor (T * 10.0));
      Secs   : constant Natural := Tenths / 10;
      S2     : constant String := Natural'Image (100 + Secs mod 60);
   begin
      return Ada.Strings.Fixed.Trim (Natural'Image (Secs / 60), Ada.Strings.Left) & ":"
        & S2 (S2'Last - 1 .. S2'Last) & "." & Ada.Strings.Fixed.Trim (Natural'Image (Tenths mod 10), Ada.Strings.Left);
   end Time_Image;

   ---------------------------------------------------------------------------

   procedure Begin_It (Player : out Car.State; Hour : in out Float) is
      T : Trial renames All_Trials (Which);
      Found : Boolean;
      RX, RZ, RH : Float;
      First : constant Point := T.Points.First_Element;
      Want  : constant Float := Arctan (First.X - T.Start.X, -(First.Z - T.Start.Z));
   begin
      Road_Network.Nearest_Road (T.Start.X, T.Start.Z, Found, RX, RZ, RH);
      if not Found then
         RX := T.Start.X;
         RZ := T.Start.Z;
         RH := Want;
      elsif Cos (RH - Want) < 0.0 then
         RH := RH + Pi;   --  the road's way that goes towards the first point
      end if;
      Player := Car.On_Ground (RX, RZ, RH);
      Player.Ground := Terrain.Height (RX, RZ);
      if T.Hour >= 0.0 then
         Hour := T.Hour;
      end if;
      Next_Pt := 1;
      Clock := 3.0;
      Time := 0.0;
      Last_Beep := 4;
      New_Best := False;
      Current := Countdown;
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

   procedure Update (Dt : Float; Player : Car.State) is
   begin
      case Current is
         when Off | Done =>
            null;
         when Countdown =>
            Clock := Clock - Dt;
            if Integer (Float'Ceiling (Clock)) < Last_Beep then
               Last_Beep := Integer (Float'Ceiling (Clock));
               if Last_Beep > 0 then
                  Sound.Effect (Sound.Beep, 0.8, 0.0);
               end if;
            end if;
            if Clock <= 0.0 then
               Current := Running;
               Sound.Effect (Sound.Go_Beep, 0.9, 0.0);
            end if;
         when Running =>
            Time := Time + Dt;
            declare
               P : constant Point := All_Trials (Which).Points (Next_Pt);
            begin
               if (Player.X - P.X) ** 2 + (Player.Z - P.Z) ** 2 < Reach ** 2 then
                  if Next_Pt = Natural (All_Trials (Which).Points.Length) then
                     --  the finish
                     Current := Done;
                     Sound.Effect (Sound.Go_Beep, 0.9, 0.0);
                     Old_Best := All_Trials (Which).Best;
                     if Old_Best = 0.0 or else Time < Old_Best then
                        All_Trials (Which).Best := Time;
                        New_Best := True;
                        Write_Best;
                     end if;
                  else
                     Next_Pt := Next_Pt + 1;
                     Sound.Effect (Sound.Beep, 0.6, 0.0);
                  end if;
                  Serial := Serial + 1;
               end if;
            end;
      end case;
   end Update;

   procedure Goal (Serial : out Natural; X, Z : out Float; Name : out Unbounded_String) is
   begin
      Serial := Trials.Serial;
      X := 0.0;
      Z := 0.0;
      Name := Null_Unbounded_String;
      if Current in Countdown | Running then
         declare
            T : Trial renames All_Trials (Which);
            P : constant Point := T.Points (Next_Pt);
         begin
            X := P.X;
            Z := P.Z;
            Name := To_Unbounded_String
              (if Next_Pt = Natural (T.Points.Length) then "Finish"
               else "Checkpoint" & Natural'Image (Next_Pt));
         end;
      end if;
   end Goal;

   function Hud_Text return String is
   begin
      if Current not in Countdown | Running then
         return "";
      end if;
      declare
         T : Trial renames All_Trials (Which);
         N : constant Natural := Natural (T.Points.Length);
      begin
         return "<span font_family='monospace' background='#000000a0' foreground='white'>  "
           & "<b>" & To_String (T.Name) & "</b>   "
           & (if Current = Countdown then "get ready"
              else Time_Image (Time) & "   " & (if Next_Pt = N then "to the finish"
                                                else "checkpoint" & Natural'Image (Next_Pt) & " of"
                                                     & Natural'Image (N - 1)))
           & (if T.Best > 0.0 then "   best " & Time_Image (T.Best) else "")
           & "  </span>";
      end;
   end Hud_Text;

   function Banner return String is
   begin
      if Current = Countdown then
         return Ada.Strings.Fixed.Trim (Integer'Image (Integer (Float'Ceiling (Clock))), Ada.Strings.Left);
      elsif Current = Running and then Time < 1.0 then
         return "GO!";
      end if;
      return "";
   end Banner;

   function Panel_Text return String is
      LF : constant String := (1 => ASCII.LF);
   begin
      if Current /= Done then
         return "";
      end if;
      return "<span font_family='monospace'><b><span foreground='#ffd27a'>"
        & To_String (All_Trials (Which).Name) & "</span></b>" & LF & LF
        & "  Your time   " & Time_Image (Time) & LF
        & (if New_Best then
             "  <b><span foreground='#7fe08a'>Best time!</span></b>"
             & (if Old_Best > 0.0 then "  (was " & Time_Image (Old_Best) & ")" else "") & LF
           else "  Best        " & Time_Image (All_Trials (Which).Best) & LF)
        & LF & "<span foreground='#aab'>  Enter: again    Esc: back to the city</span></span>";
   end Panel_Text;

end Trials;
