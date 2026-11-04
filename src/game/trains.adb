--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;
with Ada.Text_IO;

with Meshes;
with Shaders;
with Sound;

package body Trains is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;

   Pi : constant := Ada.Numerics.Pi;

   Step : constant := 4.0;          --  metres between the points of a line
   Max_Points : constant := 2500;
   Top_Speed  : constant := 22.0;   --  m/s, out in the city
   Yard_Speed : constant := 8.0;    --  near the station
   Yard       : constant := 600.0;  --  metres of it
   Accel      : constant := 0.6;
   Brake      : constant := 0.8;
   Gap        : constant := 0.8;    --  between two cars

   type Point_Array is array (1 .. Max_Points) of Vec3;
   type Kind_Type is (TGV, Suburban);

   type Phase_Type is (Waiting, Out_Bound, Away, In_Bound);

   type Train is record
      Kind   : Kind_Type := TGV;
      Pts    : Point_Array;
      N      : Natural := 0;
      Front  : Float := 0.0;       --  along the line, metres from the station
      Dir    : Float := 1.0;       --  +1 going out, -1 coming in
      Speed  : Float := 0.0;
      Phase  : Phase_Type := Waiting;
      Timer  : Float := 0.0;
   end record;

   Max_Trains : constant := 6;
   All_Trains : array (1 .. Max_Trains) of Train;
   Count : Natural := 0;

   Gen : Ada.Numerics.Float_Random.Generator;
   function Rnd return Float is (Ada.Numerics.Float_Random.Random (Gen));

   --  the cars, front to back: their length, and the end cars' noses
   type Car_Kind is (Power, Coach, Double_End, Double);
   function Car_Length (K : Car_Kind) return Float is
     (case K is when Power => 22.0, when Coach => 18.7, when Double_End | Double => 24.0);
   type Make_Up is array (Positive range <>) of Car_Kind;
   TGV_Cars : constant Make_Up := (Power, Coach, Coach, Coach, Coach, Coach, Coach, Coach, Coach, Power);
   Sub_Cars : constant Make_Up := (Double_End, Double, Double, Double, Double, Double_End);

   function Cars (T : Train) return Make_Up is
     (if T.Kind = TGV then TGV_Cars else Sub_Cars);

   function Train_Length (T : Train) return Float is
      L : Float := 0.0;
   begin
      for C of Cars (T) loop
         L := L + Car_Length (C) + Gap;
      end loop;
      return L;
   end Train_Length;

   function Line_Length (T : Train) return Float is (Float (T.N - 1) * Step);

   --  The point S metres along the line (beyond its ends: straight on)
   function At_Distance (T : Train; S : Float) return Vec3 is
   begin
      if T.N < 2 then
         return (0.0, 0.0, 0.0);
      elsif S <= 0.0 then
         return T.Pts (1) + (S / Step) * (T.Pts (2) - T.Pts (1));
      elsif S >= Line_Length (T) then
         return T.Pts (T.N) + ((S - Line_Length (T)) / Step) * (T.Pts (T.N) - T.Pts (T.N - 1));
      end if;
      declare
         F : constant Float := S / Step;
         I : constant Positive := Natural (Float'Floor (F)) + 1;
         R : constant Float := F - Float'Floor (F);
      begin
         return T.Pts (I) + R * (T.Pts (Positive'Min (T.N, I + 1)) - T.Pts (I));
      end;
   end At_Distance;

   procedure Load (Dir : String) is
      use Ada.Directories;
      Search : Search_Type;
      E      : Directory_Entry_Type;
   begin
      Ada.Numerics.Float_Random.Reset (Gen);
      if not Exists (Dir) then
         return;
      end if;
      Start_Search (Search, Dir, "train_*.txt");
      while More_Entries (Search) and then Count < Max_Trains loop
         Get_Next_Entry (Search, E);
         declare
            F : Ada.Text_IO.File_Type;
            T : Train;
         begin
            Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Full_Name (E));
            declare
               Head : constant String := Ada.Text_IO.Get_Line (F);
            begin
               T.Kind := (if Head'Length >= 8 and then Head (Head'First + 5 .. Head'First + 7) = "rer"
                          then Suburban else TGV);
            end;
            while not Ada.Text_IO.End_Of_File (F) and then T.N < Max_Points loop
               declare
                  L : constant String := Ada.Text_IO.Get_Line (F);
                  V : array (1 .. 3) of Float := (others => 0.0);
                  K : Natural := 0;
                  First : Positive := L'First;
               begin
                  for I in L'First .. L'Last + 1 loop
                     if I > L'Last or else L (I) = ' ' then
                        if I > First and then K < 3 then
                           K := K + 1;
                           V (K) := Float'Value (L (First .. I - 1));
                        end if;
                        First := I + 1;
                     end if;
                  end loop;
                  if K = 3 then
                     T.N := T.N + 1;
                     T.Pts (T.N) := (V (1), V (2), V (3));
                  end if;
               end;
            end loop;
            Ada.Text_IO.Close (F);
            if T.N > 50 then
               --  each somewhere along its round, so they are not all in
               T.Phase := Waiting;
               T.Front := Train_Length (T) + 5.0;
               T.Dir := 1.0;
               T.Timer := 20.0 + 160.0 * Rnd;
               Count := Count + 1;
               All_Trains (Count) := T;
            end if;
         exception
            when others =>
               if Ada.Text_IO.Is_Open (F) then
                  Ada.Text_IO.Close (F);
               end if;
         end;
      end loop;
      End_Search (Search);
   end Load;

   Ticks : Natural := 0;

   procedure Update (Dt : Float; Listener : Vec3) is
   begin
      Ticks := Ticks + 1;
      if Ticks mod 120 = 1 and then Ada.Environment_Variables.Exists ("PARIS_TRAINS") then
         for T of All_Trains (1 .. Count) loop
            Ada.Text_IO.Put_Line ("train " & T.Phase'Image & " front" & Integer (T.Front)'Image
              & " of" & Integer (Line_Length (T))'Image & " v" & Integer (T.Speed)'Image
              & " at" & Integer (At_Distance (T, T.Front).X)'Image & Integer (At_Distance (T, T.Front).Y)'Image
              & Integer (At_Distance (T, T.Front).Z)'Image);
         end loop;
      end if;
      for T of All_Trains (1 .. Count) loop
         case T.Phase is
            when Waiting =>
               T.Timer := T.Timer - Dt;
               if T.Timer <= 0.0 then
                  T.Phase := Out_Bound;
                  T.Dir := 1.0;
                  T.Speed := 0.0;
                  declare
                     D : constant Float := Length (At_Distance (T, T.Front) - Listener);
                  begin
                     if D < 400.0 then
                        Sound.Effect (Sound.Foghorn, Float'Min (1.0, 60.0 / (D + 20.0)), 0.0);
                     end if;
                  end;
               end if;
            when Out_Bound =>
               declare
                  Limit : constant Float := (if T.Front < Yard + Train_Length (T) then Yard_Speed else Top_Speed);
               begin
                  T.Speed := Float'Min (Limit, T.Speed + Accel * Dt);
                  T.Front := T.Front + T.Speed * Dt;
                  if T.Front - Train_Length (T) > Line_Length (T) + 20.0 then
                     T.Phase := Away;
                     T.Timer := 30.0 + 90.0 * Rnd;
                  end if;
               end;
            when Away =>
               T.Timer := T.Timer - Dt;
               if T.Timer <= 0.0 then
                  T.Phase := In_Bound;
                  T.Dir := -1.0;
                  T.Front := Line_Length (T) + 20.0;
                  T.Speed := Top_Speed;
               end if;
            when In_Bound =>
               declare
                  Left  : constant Float := Float'Max (0.0, T.Front - 5.0);
                  Limit : constant Float :=
                    Float'Min ((if T.Front < Yard then Yard_Speed else Top_Speed), Sqrt (2.0 * Brake * Left) + 0.3);
               begin
                  if T.Speed > Limit then
                     T.Speed := Float'Max (Limit, T.Speed - Brake * Dt);
                  else
                     T.Speed := Float'Min (Limit, T.Speed + Accel * Dt);
                  end if;
                  T.Front := T.Front - T.Speed * Dt;
                  if Left < 0.3 then
                     --  in at the platform; out again later, the other end first
                     T.Phase := Waiting;
                     T.Front := T.Front + Train_Length (T);
                     T.Timer := 60.0 + 60.0 * Rnd;
                  end if;
               end;
         end case;
      end loop;
   end Update;

   ---------------------------------------------------------------------------
   --  The cars: front -Z, the rails at Y = 0

   Built : Boolean := False;
   Car_Mesh : array (Boolean, Car_Kind) of Meshes.Mesh;   --  (True: lit windows)

   procedure Build is
      use Meshes;
      Mat_Stripe : constant := Mat_Skin;       --  in Stripe
      Mat_Roof   : constant := Mat_Trousers;   --  in Roof
   begin
      for Lit in Boolean loop
      for K in Car_Kind loop
         declare
            Mat_Glass : constant Float := (if Lit then 76.0 else Meshes.Mat_Glass);   --  amber, lit
            H  : constant Float := Car_Length (K) / 2.0;
            Up : constant Float := (if K in Double_End | Double then 4.4 else 3.8);
            Nose : constant Float := (case K is when Power => 7.0, when Double_End => 1.2, when others => 0.0);
         begin
            Start;
            --  the bogies, dark under the body
            Box (-1.2, 1.2, 0.0, 0.95, -H + 1.5, -H + 4.5, Mat_Tyre);
            Box (-1.2, 1.2, 0.0, 0.95, H - 4.5, H - 1.5, Mat_Tyre);
            Box (-1.0, 1.0, 0.5, 0.95, -H + 0.3, H - 0.3, Mat_Tyre);
            --  the body, its nose sloping down at the front
            Box (-1.45, 1.45, 0.95, Up, -H, H, Mat_Paint, Top_Inset_X => 0.15, Top_Inset_Front => Nose);
            Box (-1.47, 1.47, 1.45, 1.75, -H + (if Nose > 0.0 then 0.6 else 0.3), H - 0.3, Mat_Stripe);
            --  the windows
            if K = Power then
               Box (-1.1, 1.1, Up - 0.95, Up - 0.25, -H + Nose - 0.2, -H + Nose + 0.6, Mat_Glass);
            else
               Box (-1.48, 1.48, 2.25, 2.95, -H + 1.6, H - 1.6, Mat_Glass);
               if K in Double_End | Double then
                  Box (-1.48, 1.48, 3.35, 3.95, -H + 2.5, H - 2.5, Mat_Glass);
               end if;
               if K = Double_End then
                  Box (-1.2, 1.2, 2.4, 3.6, -H - 0.02, -H + 0.2, Mat_Glass);
               end if;
            end if;
            Box (-1.25, 1.25, Up, Up + 0.2, -H + Nose + 0.3, H - 0.4, Mat_Roof);
            --  the lights at the ends: white ahead, red behind (the shader
            --  lights one or the other the way the car faces)
            if K in Power | Double_End then
               Box (-1.1, -0.7, 1.15, 1.45, -H - 0.03, -H + 0.1, Mat_Headlight);
               Box (0.7, 1.1, 1.15, 1.45, -H - 0.03, -H + 0.1, Mat_Headlight);
               Box (-1.1, -0.8, 1.15, 1.4, H - 0.1, H + 0.03, Mat_Taillight);
               Box (0.8, 1.1, 1.15, 1.4, H - 0.1, H + 0.03, Mat_Taillight);
            end if;
            Finish (Car_Mesh (Lit, K));
         end;
      end loop;
      end loop;
      Built := True;
   end Build;

   procedure Draw (Model, Paint, Stripe, Roof : GL.GLint; Cam : Vec3;
                   Night : Float := 0.0) is
   begin
      if Count = 0 then
         return;
      end if;
      if not Built then
         Build;
      end if;
      for T of All_Trains (1 .. Count) loop
         if T.Phase /= Away
           and then Length (At_Distance (T, T.Front) - Cam) < 2500.0 + Train_Length (T)
         then
            Shaders.Set (Paint, (if T.Kind = TGV then Vec3'(0.92, 0.93, 0.95) else Vec3'(0.88, 0.89, 0.92)));
            Shaders.Set (Stripe, (if T.Kind = TGV then Vec3'(0.10, 0.20, 0.55) else Vec3'(0.15, 0.30, 0.62)));
            Shaders.Set (Roof, Vec3'(0.42, 0.45, 0.50));
            declare
               Along : Float := 0.0;   --  from the front, back along the train
               List  : constant Make_Up := Cars (T);
            begin
               for I in List'Range loop
                  declare
                     L  : constant Float := Car_Length (List (I));
                     --  (the front is ahead of the rest: back is against Dir)
                     F  : constant Vec3 := At_Distance (T, T.Front - T.Dir * Along);
                     B  : constant Vec3 := At_Distance (T, T.Front - T.Dir * (Along + L));
                     D  : constant Vec3 := F - B;
                     DL : constant Float := Float'Max (0.01, Sqrt (D.X * D.X + D.Z * D.Z));
                     Heading : constant Float := Arctan (D.X, -D.Z);
                     Pitch   : constant Float := Arctan (D.Y, DL);
                     --  the last car of a TGV is a power car turned round
                     Turn : constant Boolean := I = List'Last and then List (I) in Power | Double_End;
                     M : constant Mat4 :=
                       Translation (0.5 * (F + B) + Vec3'(0.0, 0.12, 0.0)) * Rotation_Y (-Heading)
                       * Rotation_X (Pitch) * (if Turn then Rotation_Y (Pi) else Identity);
                  begin
                     Shaders.Set (Model, M);
                     Meshes.Draw (Car_Mesh (Night > 0.4, List (I)));
                     Along := Along + L + Gap;
                  end;
               end loop;
            end;
         end if;
      end loop;
      Shaders.Set (Model, Identity);
   end Draw;

   procedure Leave_Now is
   begin
      for T of All_Trains (1 .. Count) loop
         if T.Phase = Waiting then
            T.Timer := 0.0;
         end if;
      end loop;
   end Leave_Now;

   procedure Push (X, Z : in out Float; Feet : Float) is
   begin
      for T of All_Trains (1 .. Count) loop
         if T.Phase in Out_Bound | In_Bound and then T.Speed > 0.1 then
            declare
               Along : Float := 0.0;
            begin
               for C of Cars (T) loop
                  declare
                     L : constant Float := Car_Length (C);
                     F : constant Vec3 := At_Distance (T, T.Front - T.Dir * Along);
                     B : constant Vec3 := At_Distance (T, T.Front - T.Dir * (Along + L));
                     DX : constant Float := F.X - B.X;
                     DZ : constant Float := F.Z - B.Z;
                     DL : constant Float := Float'Max (0.01, Sqrt (DX * DX + DZ * DZ));
                     --  across the car, and along it from its middle
                     Side : constant Float := ((X - B.X) * DZ - (Z - B.Z) * DX) / DL;
                     On   : constant Float := ((X - B.X) * DX + (Z - B.Z) * DZ) / DL;
                  begin
                     if abs Side < 2.1 and then On > -0.5 and then On < DL + 0.5
                       and then abs (Feet - 0.5 * (F.Y + B.Y)) < 3.0
                     then
                        declare
                           Out_By : constant Float := (if Side >= 0.0 then 2.1 - Side else -2.1 - Side);
                        begin
                           X := X + Out_By * DZ / DL;
                           Z := Z - Out_By * DX / DL;
                        end;
                     end if;
                     Along := Along + L + Gap;
                  end;
               end loop;
            end;
         end if;
      end loop;
   end Push;

end Trains;
