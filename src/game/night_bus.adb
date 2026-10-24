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

with Figures;
with Geo;
with Math3D;
with Meshes;
with Road_Network;
with Shaders;
with Sound;
with Terrain;

package body Night_Bus is

   use Ada.Strings.Unbounded;
   use Ada.Numerics.Elementary_Functions;
   use Math3D;

   Gen : Ada.Numerics.Float_Random.Generator;
   function Rnd return Float is (Ada.Numerics.Float_Random.Random (Gen));

   function "+" (S : String) return Unbounded_String renames To_Unbounded_String;

   type Stop_Rec is record
      Name   : Unbounded_String;
      X, Z   : Float := 0.0;     --  where it is in the data
      RX, RZ : Float := 0.0;     --  on the road before it
      PX, PZ : Float := 0.0;     --  the pole, on the pavement
      Face   : Float := 0.0;
      Due    : Float := 0.0;     --  the hour in the timetable
      Waiting, Off_Here : Natural := 0;
      Served : Boolean := False;
      Left_At : Float := 0.0;    --  the hour the bus left
      Skipped : Boolean := False;
   end record;
   package Stop_Vectors is new Ada.Containers.Vectors (Positive, Stop_Rec);

   type Line is record
      Name  : Unbounded_String;
      Stops : Stop_Vectors.Vector;
      Best  : Natural := 0;
   end record;
   package Line_Vectors is new Ada.Containers.Vectors (Positive, Line);
   Lines : Line_Vectors.Vector;

   Current  : Phase_Kind := Off;
   Which    : Natural := 0;
   Stops    : Stop_Vectors.Vector;   --  this run's
   Next     : Positive := 1;         --  the stop to serve next
   Now      : Float := 1.0;
   Me_X, Me_Z, Me_Speed : Float := 0.0;
   On_Board : Natural := 0;
   Carried, Tickets : Natural := 0;
   Door_Time : Float := 0.0;         --  the doors open: people moving
   Boarding, Alighting : Natural := 0;
   Comfort  : Float := 1.0;          --  0 .. 1: how they found the ride
   Knock_Wait : Float := 0.0;
   Serial   : Natural := 0;
   Said     : Unbounded_String;
   Said_Time : Float := 0.0;
   New_Best : Boolean := False;
   Stars    : Natural := 0;

   Pace  : constant := 1.0 / 3600.0;  --  the clock in real time: a timetable to keep
   Reach : constant := 16.0;

   Pole_M : Meshes.Mesh;
   Built  : Boolean := False;

   function File return String is
     (Ada.Environment_Variables.Value ("HOME", ".") & "/.derive_nightbus");

   function Count return Natural is (Natural (Lines.Length));
   function Name (I : Positive) return String is (To_String (Lines (I).Name));
   function Best (I : Positive) return Natural is (Lines (I).Best);
   function Phase return Phase_Kind is (Current);
   function Active return Boolean is (Current /= Off);
   function Holding return Boolean is (Current = At_Stop);
   function Clock_Pace return Float is (if Current in Driving | At_Stop then Pace else 0.0);

   function Clock_Image (H : Float) return String is
      M  : constant Natural := Natural (Float'Floor (H * 60.0)) mod (24 * 60);
      S2 : constant String := Natural'Image (100 + M mod 60);
   begin
      return Ada.Strings.Fixed.Trim (Natural'Image (M / 60), Ada.Strings.Left) & ":" & S2 (S2'Last - 1 .. S2'Last);
   end Clock_Image;

   function Img (N : Integer) return String is
     (Ada.Strings.Fixed.Trim (Integer'Image (N), Ada.Strings.Left));

   procedure Say (S : String) is
   begin
      Said := +S;
      Said_Time := 4.5;
   end Say;

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
               for Li of Lines loop
                  if To_String (Li.Name) = L (Tab + 1 .. L'Last) then
                     Li.Best := Natural'Value (L (L'First .. Tab - 1));
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
      Ada.Text_IO.Put_Line (F, "# Dérive: your best night bus runs (stars <tab> line)");
      for Li of Lines loop
         if Li.Best > 0 then
            Ada.Text_IO.Put_Line (F, Img (Li.Best) & ASCII.HT & To_String (Li.Name));
         end if;
      end loop;
      Ada.Text_IO.Close (F);
   exception
      when others => null;
   end Write_Best;

   procedure Load is
      F   : Ada.Text_IO.File_Type;
      Cur : Line;
      procedure Finish is
      begin
         if Length (Cur.Name) > 0 and then Natural (Cur.Stops.Length) >= 2 then
            Lines.Append (Cur);
         end if;
         Cur := (others => <>);
      end Finish;
   begin
      Lines.Clear;
      Ada.Numerics.Float_Random.Reset (Gen);
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, "data/night_bus.txt");
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            L : constant String := Ada.Text_IO.Get_Line (F);
         begin
            if L'Length = 0 or else L (L'First) = '#' then
               null;
            elsif L (L'First) = '[' and then L (L'Last) = ']' then
               Finish;
               Cur.Name := +L (L'First + 1 .. L'Last - 1);
            elsif L'Length > 5 and then L (L'First .. L'First + 4) = "stop " then
               declare
                  R  : constant String := L (L'First + 5 .. L'Last);
                  S1 : constant Natural := Ada.Strings.Fixed.Index (R, " ");
                  S2 : constant Natural := Ada.Strings.Fixed.Index (R, " ", S1 + 1);
                  X, Z : Long_Float;
                  S : Stop_Rec;
               begin
                  Geo.To_Local (Long_Float'Value (R (R'First .. S1 - 1)), Long_Float'Value (R (S1 + 1 .. S2 - 1)), X, Z);
                  S.Name := +R (S2 + 1 .. R'Last);
                  S.X := Float (X);
                  S.Z := Float (Z);
                  Cur.Stops.Append (S);
               end;
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

   ---------------------------------------------------------------------------

   procedure Begin_It (Player : out Car.State; Hour : in out Float) is
      Secs : Float := 0.0;
   begin
      Stops := Lines (Which).Stops;
      --  after midnight, whatever the hour was
      if Hour > 4.5 and then Hour < 23.0 then
         Hour := 0.75;
      end if;
      Now := Hour;
      for I in Stops.First_Index .. Stops.Last_Index loop
         declare
            S : Stop_Rec renames Stops (I);
            Ok : Boolean;
         begin
            Road_Network.Kerb_Of (S.X, S.Z, Ok, S.RX, S.RZ, S.PX, S.PZ, S.Face);
            if not Ok then
               S.RX := S.X;
               S.RZ := S.Z;
               S.PX := S.X;
               S.PZ := S.Z;
            end if;
            if I > Stops.First_Index then
               declare
                  P : Stop_Rec renames Stops (I - 1);
               begin
                  --  the timetable: at some 25 km/h with the corners, and
                  --  half a minute at each stop
                  Secs := Secs + 1.35 * Sqrt ((S.RX - P.RX) ** 2 + (S.RZ - P.RZ) ** 2) / 6.5 + 25.0;
               end;
            end if;
            --  on the minute
            S.Due := Float'Ceiling ((Hour + (15.0 + Secs) * Pace) * 60.0) / 60.0;
            S.Waiting := (if I = Stops.Last_Index then 0
                          else Natural (Float'Floor (Rnd * (if I = Stops.First_Index then 7.0 else 5.0))));
            S.Served := False;
            S.Skipped := False;
         end;
      end loop;
      declare
         First : constant Stop_Rec := Stops (Stops.First_Index);
         Ok : Boolean;
         RX, RZ, RH : Float;
         To : constant Stop_Rec := Stops (Stops.First_Index + 1);
         Want : constant Float := Arctan (To.RX - First.RX, -(To.RZ - First.RZ));
      begin
         Road_Network.Nearest_Road (First.RX, First.RZ, Ok, RX, RZ, RH);
         if not Ok then
            RX := First.RX;
            RZ := First.RZ;
            RH := Want;
         elsif Cos (RH - Want) < 0.0 then
            RH := RH + Ada.Numerics.Pi;
         end if;
         --  pulled up before the first stop, a bus length short
         Player := Car.On_Ground (RX - 14.0 * Sin (RH), RZ + 14.0 * Cos (RH), RH);
         Player.Ground := Terrain.Height (Player.X, Player.Z);
      end;
      Next := Stops.First_Index;
      On_Board := 0;
      Carried := 0;
      Tickets := 0;
      Comfort := 1.0;
      New_Best := False;
      Stars := 0;
      Said := Null_Unbounded_String;
      Current := Driving;
      Serial := Serial + 1;
      Say ("Your bus, " & To_String (Lines (Which).Name) & ".  First stop: "
           & To_String (Stops (Next).Name) & ", at " & Clock_Image (Stops (Next).Due));
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

   procedure Impact (Loss : Float) is
   begin
      if Current /= Driving or else Loss < 3.0 or else Knock_Wait > 0.0 then
         return;
      end if;
      Knock_Wait := 1.0;
      Comfort := Float'Max (0.0, Comfort - Float'Min (0.3, Loss / 25.0) * (if On_Board > 0 then 1.0 else 0.3));
      if On_Board > 0 then
         Say ("Eh ! Doucement !  (Hey! Gently!)");
      end if;
   end Impact;

   procedure Finish_Run is
      On_Time, Early, Missed : Natural := 0;
   begin
      for S of Stops loop
         if S.Skipped then
            Missed := Missed + 1;
         elsif S.Left_At < S.Due - 0.5 / 60.0 then
            Early := Early + 1;
         elsif S.Left_At <= S.Due + 2.5 / 60.0 then
            On_Time := On_Time + 1;
         end if;
      end loop;
      --  stars: the timetable, nobody left behind, the comfort
      declare
         N : constant Float := Float (Natural (Stops.Length));
         Score : constant Float := 5.0 * Float (On_Time) / N - 1.5 * Float (Early) - 2.0 * Float (Missed)
           + 2.0 * Comfort - 1.0;
      begin
         Stars := Natural (Float'Max (1.0, Float'Min (5.0, Float'Rounding (Score))));
      end;
      if Stars > Lines (Which).Best then
         Lines (Which).Best := Stars;
         New_Best := True;
         Write_Best;
      end if;
      Current := Done;
      Sound.Effect (Sound.Go_Beep, 0.8, 0.0);
      Serial := Serial + 1;
   end Finish_Run;

   procedure Update (Dt : Float; Player : Car.State; Hour : Float) is
   begin
      Now := Hour;
      Me_X := Player.X;
      Me_Z := Player.Z;
      Me_Speed := abs Player.Speed;
      Said_Time := Float'Max (0.0, Said_Time - Dt);
      Knock_Wait := Float'Max (0.0, Knock_Wait - Dt);
      case Current is
         when Off | Done =>
            null;
         when Driving =>
            declare
               S : Stop_Rec renames Stops (Next);
               D2 : constant Float := (S.RX - Me_X) ** 2 + (S.RZ - Me_Z) ** 2;
            begin
               if D2 < Reach ** 2 and then Me_Speed < 1.0 then
                  --  the doors open
                  Current := At_Stop;
                  Alighting := (if Next = Stops.Last_Index then On_Board
                                else Natural'Min (On_Board, Natural (Float'Floor (Rnd * Float (On_Board + 1)))));
                  Boarding := S.Waiting;
                  Door_Time := 2.0 + 1.1 * Float (Alighting + Boarding);
                  Sound.Effect (Sound.Thud, 0.4, 0.3);
               end if;
               --  driven on past it with people waiting: a missed stop
               if Current = Driving and then Next < Stops.Last_Index then
                  declare
                     N : Stop_Rec renames Stops (Next + 1);
                  begin
                     if (N.RX - Me_X) ** 2 + (N.RZ - Me_Z) ** 2 < Reach ** 2 then
                        S.Skipped := True;
                        S.Left_At := Now;
                        if S.Waiting > 0 then
                           Comfort := Float'Max (0.0, Comfort - 0.2);
                           Say ("You drove past " & To_String (S.Name) & ": " & Img (S.Waiting)
                                & " left waiting in the night");
                        end if;
                        Next := Next + 1;
                        Serial := Serial + 1;
                     end if;
                  end;
               end if;
            end;
         when At_Stop =>
            Door_Time := Door_Time - Dt;
            declare
               S : Stop_Rec renames Stops (Next);
            begin
               if Door_Time <= 0.0 then
                  On_Board := On_Board - Alighting + Boarding;
                  Carried := Carried + Boarding;
                  Tickets := Tickets + Natural (Float'Floor (Float (Boarding) * 0.6));
                  S.Waiting := 0;
                  S.Served := True;
                  if Next = Stops.Last_Index then
                     S.Left_At := Float'Max (Now, S.Due);   --  early at the terminus is no fault
                     Say ("Terminus ! Tout le monde descend.  (Everybody off.)");
                     Finish_Run;
                  elsif Now < S.Due - 0.5 / 60.0 and then not Ada.Environment_Variables.Exists ("PARIS_BUS_AUTO") then
                     --  never leave early: the doors stay open till then
                     Door_Time := 0.5;
                     if Said_Time = 0.0 then
                        Say ("Too early: wait for " & Clock_Image (S.Due) & " (never leave a stop early)");
                     end if;
                     Boarding := 0;
                     Alighting := 0;
                  else
                     S.Left_At := Now;
                     Current := Driving;
                     Sound.Effect (Sound.Beep, 0.5, 0.3);
                     Next := Next + 1;
                     Serial := Serial + 1;
                     if Next = Stops.Last_Index then
                        Say ("Next: " & To_String (Stops (Next).Name) & ", the terminus");
                     else
                        Say ("Next stop: " & To_String (Stops (Next).Name) & " at " & Clock_Image (Stops (Next).Due));
                     end if;
                  end if;
               end if;
            end;
      end case;
   end Update;

   procedure Goal (Serial : out Natural; X, Z : out Float; Name : out Unbounded_String) is
   begin
      Serial := Night_Bus.Serial;
      X := 0.0;
      Z := 0.0;
      Name := Null_Unbounded_String;
      if Current in Driving | At_Stop then
         X := Stops (Next).RX;
         Z := Stops (Next).RZ;
         Name := Stops (Next).Name;
      end if;
   end Goal;

   ---------------------------------------------------------------------------

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint; Time : Float) is
   begin
      if Current = Off then
         return;
      end if;
      if not Built then
         --  the stop: a pole and its sign, lit (uExtraColor)
         Meshes.Start;
         Meshes.Box (-0.05, 0.05, 0.0, 2.6, -0.05, 0.05, 26.0);
         Meshes.Box (-0.3, 0.3, 2.2, 2.9, -0.04, 0.04, 50.0);
         Meshes.Finish (Pole_M);
         Built := True;
      end if;
      Figures.Set_Locations ((Model, Paint, Skin, Legs));
      for I in Stops.First_Index .. Stops.Last_Index loop
         declare
            S : Stop_Rec renames Stops (I);
         begin
            if (S.PX - Me_X) ** 2 + (S.PZ - Me_Z) ** 2 < 300.0 ** 2 then
               Shaders.Set (Skin, (if I = Next then Vec3'(0.35, 0.55, 1.0) else Vec3'(0.15, 0.25, 0.6)));
               Shaders.Set (Model, Translation ((S.PX, Terrain.Height (S.PX, S.PZ), S.PZ))
                            * Rotation_Y (-S.Face));
               Meshes.Draw (Pole_M);
               --  the people waiting (fewer as they board)
               declare
                  N : constant Natural :=
                    (if I = Next and then Current = At_Stop
                     then Natural (Float'Max (0.0, Float'Min (Float (S.Waiting),
                       (Door_Time - 2.0) / 1.1 - Float (Alighting))))
                     else S.Waiting);
               begin
                  for K in 1 .. N loop
                     declare
                        Ang : constant Float := Float (K) * 2.4 + Float (I);
                        Off_X : constant Float := 1.2 * Cos (Ang) + 0.6 * Float (K mod 3);
                        Off_Z : constant Float := 0.8 * Sin (Ang);
                        FX : constant Float := S.PX + Off_X * Cos (S.Face) - Off_Z * Sin (S.Face);
                        FZ : constant Float := S.PZ + Off_X * Sin (S.Face) + Off_Z * Cos (S.Face);
                        Seed : constant Natural := (I * 7 + K * 13) mod 6;
                     begin
                        Figures.Person
                          (Translation ((FX, Terrain.Height (FX, FZ), FZ)) * Rotation_Y (-S.Face - 0.3 * Sin (Ang)),
                           (case Seed is
                               when 0 => (0.12, 0.12, 0.14), when 1 => (0.55, 0.12, 0.2),
                               when 2 => (0.2, 0.3, 0.45), when 3 => (0.6, 0.55, 0.45),
                               when 4 => (0.25, 0.4, 0.25), when others => (0.45, 0.3, 0.55)),
                           (case Seed mod 4 is
                               when 0 => (0.86, 0.68, 0.56), when 1 => (0.76, 0.57, 0.44),
                               when 2 => (0.58, 0.40, 0.29), when others => (0.40, 0.27, 0.19)),
                           (0.12, 0.13, 0.18),
                           Arm_Up => (if I = Next and then K = 1 and then Current = Driving
                                        and then (S.PX - Me_X) ** 2 + (S.PZ - Me_Z) ** 2 < 80.0 ** 2
                                      then -2.5 + 0.35 * Sin (Time * 7.0) else 0.0));
                     end;
                  end loop;
               end;
            end if;
         end;
      end loop;
   end Draw;

   ---------------------------------------------------------------------------

   function Hud_Text return String is
   begin
      if Current not in Driving | At_Stop then
         return "";
      end if;
      declare
         S : Stop_Rec renames Stops (Next);
         D : constant Natural := Natural (Sqrt ((S.RX - Me_X) ** 2 + (S.RZ - Me_Z) ** 2));
         Late : constant Integer := Integer (Float'Floor ((Now - S.Due) * 60.0));
      begin
         return "<span font_family='sans' weight='bold' foreground='white' background='#000000a0'>  "
           & "<span foreground='#7fb2ff'>" & To_String (Lines (Which).Name) & "</span>   " & Clock_Image (Now)
           & (if Current = At_Stop then "   doors open at " & To_String (S.Name)
              else "   next: " & To_String (S.Name) & " " & Clock_Image (S.Due)
                   & (if Late > 0 then " <span foreground='#ff8a7a'>(" & Img (Late) & " min late)</span>" else "")
                   & "  " & Img (D) & " m")
           & "   on board " & Img (On_Board) & "  </span>"
           & (if Said_Time > 0.0 then (1 => ASCII.LF)
                & "<span font_family='sans' foreground='white' background='#000000a0'>  " & To_String (Said) & "  </span>"
              else "");
      end;
   end Hud_Text;

   function Banner return String is ("");

   function Panel_Text return String is
      LF : constant String := (1 => ASCII.LF);
      T  : Unbounded_String;
      function Pad (S : String; N : Natural) return String is
         Letters : Natural := 0;
      begin
         for I in S'Range loop
            if Character'Pos (S (I)) / 64 /= 2 then
               if Letters = N then
                  return S (S'First .. I - 1);
               end if;
               Letters := Letters + 1;
            end if;
         end loop;
         return S & (1 .. N - Letters => ' ');
      end Pad;
   begin
      if Current /= Done then
         return "";
      end if;
      T := +("<span font_family='monospace'><b><span foreground='#7fb2ff'>"
             & To_String (Lines (Which).Name) & "</span></b>" & LF & LF);
      for S of Stops loop
         declare
            Diff : constant Integer := Integer (Float'Rounding ((S.Left_At - S.Due) * 60.0));
         begin
            Append (T, "  " & Pad (To_String (S.Name), 24) & " " & Clock_Image (S.Due) & "  "
                    & (if S.Skipped then "<span foreground='#ff8a7a'>missed</span>"
                       elsif Diff < 0 then "<span foreground='#ff8a7a'>left early</span>"
                       elsif Diff <= 2 then "<span foreground='#7fe08a'>on time</span>"
                       else "<span foreground='#ffd27a'>" & Img (Diff) & " min late</span>") & LF);
         end;
      end loop;
      Append (T, LF & "  Passengers    " & Img (Carried) & "  (" & Img (Tickets) & " tickets sold)" & LF
              & "  Comfort       " & Img (Natural (Comfort * 100.0)) & " %" & LF
              & "  " & (1 .. Stars => '*') & (1 .. 5 - Stars => '.') & "  "
              & (if New_Best then "<b><span foreground='#7fe08a'>Best run!</span></b>" else "")
              & LF & LF & "<span foreground='#aab'>  Enter: the line again    Esc: back to the city</span></span>");
      return To_String (T);
   end Panel_Text;

end Night_Bus;
