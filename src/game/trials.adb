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
with Math3D;
with Meshes;
with Shaders;
with Road_Network;
with Sound;
with Terrain;

package body Trials is

   use Ada.Strings.Unbounded;
   use Ada.Numerics.Elementary_Functions;

   Pi : constant := Ada.Numerics.Pi;

   type Point is record
      X, Z : Float := 0.0;
      H    : Float := 0.0;   --  the road's heading there (once on the road)
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

   Reach : constant := 18.0;     --  how near a point counts as passed
   Road_Points : Point_Vectors.Vector;   --  the run's points, put on the road
   Me_X, Me_Z, Last_X, Last_Z : Float := 0.0;
   Arrow_M, Arch_M : Meshes.Mesh;
   Built : Boolean := False;

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
         return (Float (X), Float (Z), 0.0);
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
      --  the points on the road itself, where the GPS takes you
      Road_Points.Clear;
      for P of T.Points loop
         declare
            Ok : Boolean;
            PX, PZ, PH : Float;
         begin
            Road_Network.Nearest_Road (P.X, P.Z, Ok, PX, PZ, PH);
            Road_Points.Append ((if Ok then (PX, PZ, PH) else P));
         end;
      end loop;
      Me_X := RX;
      Me_Z := RZ;
      Last_X := RX;
      Last_Z := RZ;
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
            Last_X := Me_X;
            Last_Z := Me_Z;
            Me_X := Player.X;
            Me_Z := Player.Z;
            declare
               P : constant Point := Road_Points (Next_Pt);
               --  the nearest the car came to it on this step
               DX : constant Float := Me_X - Last_X;
               DZ : constant Float := Me_Z - Last_Z;
               L2 : constant Float := DX * DX + DZ * DZ;
               U  : constant Float :=
                 (if L2 > 1.0E-6 then Float'Max (0.0, Float'Min (1.0, ((P.X - Last_X) * DX + (P.Z - Last_Z) * DZ) / L2))
                  else 0.0);
               Near2 : constant Float := (Last_X + U * DX - P.X) ** 2 + (Last_Z + U * DZ - P.Z) ** 2;
            begin
               if Near2 < Reach ** 2 then
                  if Next_Pt = Natural (Road_Points.Length) then
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
            P : constant Point := Road_Points (Next_Pt);
         begin
            X := P.X;
            Z := P.Z;
            Name := To_Unbounded_String
              (if Next_Pt = Natural (T.Points.Length) then "Finish"
               else "Checkpoint" & Natural'Image (Next_Pt));
         end;
      end if;
   end Goal;

   procedure Draw (Model, Skin : GL.GLint; Time : Float) is
      use Math3D;
   begin
      if Current not in Countdown | Running then
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
         --  the finish: two posts and a chequered banner across the road,
         --  24 m wide, along X (turned to the road where it is drawn)
         Meshes.Start;
         for S in -1 .. 1 loop
            if S /= 0 then
               Meshes.Box (Float (S) * 12.0 - 0.15, Float (S) * 12.0 + 0.15, 0.0, 5.6, -0.15, 0.15, 26.0);
            end if;
         end loop;
         for Col in 0 .. 47 loop
            for Row in 0 .. 1 loop
               Meshes.Box (-12.0 + 0.5 * Float (Col), -11.5 + 0.5 * Float (Col),
                           4.6 + 0.5 * Float (Row), 5.1 + 0.5 * Float (Row), -0.06, 0.06,
                           (if (Col + Row) mod 2 = 0 then 39.0 else 17.0));
            end loop;
         end loop;
         Meshes.Finish (Arch_M);
         Built := True;
      end if;
      declare
         N : constant Natural := Natural (Road_Points.Length);
         F : constant Point := Road_Points (N);
         P : constant Point := Road_Points (Next_Pt);
         D : constant Float := Sqrt ((P.X - Me_X) ** 2 + (P.Z - Me_Z) ** 2);
         S : constant Float := 1.0 + Float'Min (3.0, D / 120.0);
      begin
         Shaders.Set (Model, Translation ((F.X, Terrain.Height (F.X, F.Z), F.Z)) * Rotation_Y (-F.H));
         Meshes.Draw (Arch_M);
         Shaders.Set (Skin, (if Next_Pt = N then Vec3'(1.0, 0.85, 0.2) else Vec3'(0.2, 1.0, 0.35)));
         Shaders.Set (Model, Translation ((P.X, Terrain.Height (P.X, P.Z) + 4.0 + 0.3 * Sin (Time * 2.5)
                                           + 7.0 * (S - 1.0), P.Z))
                      * Rotation_Y (Time * 1.5) * Scale (S));
         Meshes.Draw (Arrow_M);
      end;
   end Draw;

   function Hud_Text return String is
   begin
      if Current not in Countdown | Running then
         return "";
      end if;
      declare
         T : Trial renames All_Trials (Which);
         N : constant Natural := Natural (T.Points.Length);
         P : constant Point := Road_Points (Next_Pt);
         D : constant Natural := Natural (Sqrt ((P.X - Me_X) ** 2 + (P.Z - Me_Z) ** 2));
      begin
         return "<span font_family='monospace' background='#000000a0' foreground='white'>  "
           & "<b>" & To_String (T.Name) & "</b>   "
           & (if Current = Countdown then "get ready"
              else Time_Image (Time) & "   " & (if Next_Pt = N then "finish"
                                                else "checkpoint" & Natural'Image (Next_Pt) & " of"
                                                     & Natural'Image (N - 1))
                   & Natural'Image (D) & " m")
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
