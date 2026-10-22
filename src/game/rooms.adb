--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces;

with Figures;
with Geo;
with Math3D;
with Meshes;
with Shaders;
with Sound;
with Terrain;

package body Rooms is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;
   use Ada.Strings.Unbounded;

   Pi : constant := Ada.Numerics.Pi;

   type Float_List is array (Positive range <>) of Float;

   --  Materials (world.frag)
   Mat_Stone  : constant := 29.0;
   Mat_Marble : constant := 45.0;
   Mat_Wood   : constant := 13.0;
   Mat_Parquet : constant := 35.0;
   Mat_Red    : constant := 46.0;   --  red damask
   Mat_Gilt   : constant := 48.0;
   Mat_Paint  : constant := 54.0;   --  glossy, in uCarColor
   Mat_Canvas : constant := 51.0;
   Mat_Bones  : constant := 77.0;
   Mat_Brass  : constant := 78.0;
   Mat_Flame  : constant := 79.0;
   Mat_Amber  : constant := 76.0;
   Mat_Dark   : constant := 70.0;
   Mat_Lamp   : constant := 50.0;   --  in uExtraColor
   Mat_Ground : constant := 29.0;   --  stone
   Mat_Exit   : constant := 49.0;
   Mat_Iron_Stand : constant := 17.0;

   Gen : Ada.Numerics.Float_Random.Generator;
   Seeded : Boolean := False;
   function Rnd return Float is (Ada.Numerics.Float_Random.Random (Gen));

   ---------------------------------------------------------------------------
   --  The words and places (data/rooms.dat)

   type Room_Data is record
      At_Lat, At_Lon : Long_Float := 0.0;
      Has_Out : Boolean := False;
      Out_Lat, Out_Lon : Long_Float := 0.0;
      Out_Yaw : Float := 0.0;
      Has_Mark : Boolean := False;
      Mark_Lat, Mark_Lon : Long_Float := 0.0;
      Arrive, Leave, Head, Note : Unbounded_String;
   end record;
   Data : array (Room_Kind) of Room_Data;
   Loaded : Boolean := False;

   procedure Load is
      use type Interfaces.Unsigned_8;
      Key : constant String := "derive-paris";
      F   : Ada.Text_IO.File_Type;
      Cur : Integer := -1;
      function Plain (Hex : String) return String is
         R : String (1 .. Hex'Length / 2);
      begin
         for I in R'Range loop
            R (I) := Character'Val
              (Interfaces.Unsigned_8'Value ("16#" & Hex (Hex'First + 2 * (I - 1) .. Hex'First + 2 * I - 1) & "#")
               xor Interfaces.Unsigned_8 (Character'Pos (Key (Key'First + (I - 1) mod Key'Length))));
         end loop;
         return R;
      end Plain;
      function Word (L : String; N : Positive) return String is
         Count : Natural := 0;
         I : Natural := L'First;
      begin
         while I <= L'Last loop
            while I <= L'Last and then L (I) = ' ' loop
               I := I + 1;
            end loop;
            exit when I > L'Last;
            declare
               J : Natural := I;
            begin
               while J <= L'Last and then L (J) /= ' ' loop
                  J := J + 1;
               end loop;
               Count := Count + 1;
               if Count = N then
                  return L (I .. J - 1);
               end if;
               I := J;
            end;
         end loop;
         return "";
      end Word;
   begin
      Loaded := True;
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, "data/rooms.dat");
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            Raw : constant String := Ada.Text_IO.Get_Line (F);
         begin
            if Raw'Length > 0 and then Raw (Raw'First) = '[' then
               Cur := Cur + 1;
            elsif Raw'Length > 1 and then Cur in 0 .. 3 then
               declare
                  L : constant String := Plain (Raw);
                  W : constant String := Word (L, 1);
                  Rest : constant String := (if L'Length > W'Length then L (L'First + W'Length + 1 .. L'Last) else "");
                  D : Room_Data renames Data (Room_Kind'Val (Cur));
               begin
                  if W = "at" then
                     D.At_Lat := Long_Float'Value (Word (L, 2));
                     D.At_Lon := Long_Float'Value (Word (L, 3));
                  elsif W = "out" then
                     D.Has_Out := True;
                     D.Out_Lat := Long_Float'Value (Word (L, 2));
                     D.Out_Lon := Long_Float'Value (Word (L, 3));
                     D.Out_Yaw := Float'Value (Word (L, 4)) * Pi / 180.0;
                  elsif W = "mark" then
                     D.Has_Mark := True;
                     D.Mark_Lat := Long_Float'Value (Word (L, 2));
                     D.Mark_Lon := Long_Float'Value (Word (L, 3));
                  elsif W = "arrive" then
                     D.Arrive := To_Unbounded_String (Rest);
                  elsif W = "leave" then
                     D.Leave := To_Unbounded_String (Rest);
                  elsif W = "head" then
                     D.Head := To_Unbounded_String (Rest);
                  elsif W = "note" then
                     D.Note := To_Unbounded_String (Rest);
                  end if;
               exception
                  when Constraint_Error => null;
               end;
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (F);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
   end Load;

   ---------------------------------------------------------------------------
   --  State

   Kind   : Room_Kind := Room_A;
   Origin : Vec3 := (0.0, 0.0, 0.0);   --  the door, at floor level; the room runs along +X
   Back_X, Back_Z, Back_Yaw : Float := 0.0;
   Clock  : Float := 0.0;
   Inside_Time : Float := 0.0;
   Hall   : Meshes.Mesh;
   Built  : Boolean := False;
   Need_Build : Boolean := False;   --  (done in Draw, where GL is ready)
   Me_X, Me_Z : Float := 0.0;

   function Current return Room_Kind is (Kind);

   procedure Mark (K : Room_Kind; X, Z : out Float; Found : out Boolean) is
      LX, LZ : Long_Float;
   begin
      if not Loaded then
         Load;
      end if;
      Found := Data (K).Has_Mark;
      Geo.To_Local (Data (K).Mark_Lat, Data (K).Mark_Lon, LX, LZ);
      X := Float (LX);
      Z := Float (LZ);
   end Mark;
   function Floor_Y return Float is (Origin.Y);
   function G (X, Y, Z : Float) return Vec3 is (Origin + Vec3'(X, Y, Z));

   --  the size of each room: along X from the door, across Z
   function Length_Of return Float is
     (case Kind is when Room_A => 64.0, when Room_B => 24.0, when Room_C => 14.0, when Room_D => 33.0);
   function Half_W return Float is
     (case Kind is when Room_A => 14.0, when Room_B => 10.0, when Room_C => 7.0, when Room_D => 16.5);

   ---------------------------------------------------------------------------
   --  Shapes

   procedure Face (A, B, C, D, N : Vec3; Mat : Float) is
   begin
      if Dot (Cross (B - A, D - A), N) >= 0.0 then
         Meshes.Quad (A, B, C, D, Mat);
      else
         Meshes.Quad (D, C, B, A, Mat);
      end if;
   end Face;

   procedure Box (X0, X1, Y0, Y1, Z0, Z1 : Float; Mat : Float) is
   begin
      Meshes.Box (Origin.X + X0, Origin.X + X1, Origin.Y + Y0, Origin.Y + Y1,
                  Origin.Z + Z0, Origin.Z + Z1, Mat);
   end Box;

   --  a room's shell: floor, walls, ceiling
   procedure Shell (Floor_Mat, Wall_Mat, Ceiling_Mat : Float; H : Float) is
      L : constant Float := Length_Of;
      W : constant Float := Half_W;
   begin
      Meshes.Quad_UV (G (0.0, 0.0, -W), G (L, 0.0, -W), G (L, 0.0, W), G (0.0, 0.0, W),
                      (0.0, 1.0, 0.0), Floor_Mat, 0.0, L / 2.0, W);
      Face (G (0.0, H, -W), G (L, H, -W), G (L, H, W), G (0.0, H, W), (0.0, -1.0, 0.0), Ceiling_Mat);
      Face (G (0.0, 0.0, -W), G (L, 0.0, -W), G (L, H, -W), G (0.0, H, -W), (0.0, 0.0, 1.0), Wall_Mat);
      Face (G (0.0, 0.0, W), G (L, 0.0, W), G (L, H, W), G (0.0, H, W), (0.0, 0.0, -1.0), Wall_Mat);
      Face (G (0.0, 0.0, -W), G (0.0, 0.0, W), G (0.0, H, W), G (0.0, H, -W), (1.0, 0.0, 0.0), Wall_Mat);
      Face (G (L, 0.0, -W), G (L, 0.0, W), G (L, H, W), G (L, H, -W), (-1.0, 0.0, 0.0), Wall_Mat);
   end Shell;

   procedure Door is
   begin
      Face (G (0.03, 0.0, -1.2), G (0.03, 0.0, 1.2), G (0.03, 2.8, 1.2), G (0.03, 2.8, -1.2),
            (1.0, 0.0, 0.0), Mat_Wood);
      Box (0.03, 0.12, 3.0, 3.45, -0.8, 0.8, Mat_Exit);
   end Door;

   procedure Flame (P : Vec3; S : Float := 0.05) is
   begin
      Meshes.Box (P.X - 0.6 * S, P.X + 0.6 * S, P.Y, P.Y + 2.0 * S, P.Z - 0.6 * S, P.Z + 0.6 * S, Mat_Flame);
   end Flame;

   procedure Candle (P : Vec3) is
   begin
      Meshes.Box (P.X - 0.025, P.X + 0.025, P.Y, P.Y + 0.25, P.Z - 0.025, P.Z + 0.025, Mat_Marble);
      Flame (P + Vec3'(0.0, 0.25, 0.0), 0.025);
   end Candle;

   ---------------------------------------------------------------------------
   --  A: a great church

   procedure Build_A is
      H : constant Float := 24.0;
   begin
      Shell (Mat_Marble, Mat_Stone, Mat_Stone, H);
      --  a barrel vault over the nave
      for K in 0 .. 11 loop
         declare
            A0 : constant Float := Pi * Float (K) / 12.0;
            A1 : constant Float := Pi * Float (K + 1) / 12.0;
            function V (A : Float; X : Float) return Vec3 is (G (X, 16.0 + 7.0 * Sin (A), -7.0 * Cos (A)));
         begin
            Face (V (A0, 0.0), V (A1, 0.0), V (A1, 64.0), V (A0, 64.0),
                  (0.0, -Sin (0.5 * (A0 + A1)), Cos (0.5 * (A0 + A1))), Mat_Stone);
         end;
      end loop;
      Face (G (0.0, 12.0, -14.0), G (64.0, 12.0, -14.0), G (64.0, 12.0, -7.0), G (0.0, 12.0, -7.0), (0.0, -1.0, 0.0), Mat_Stone);
      Face (G (0.0, 12.0, 14.0), G (64.0, 12.0, 14.0), G (64.0, 12.0, 7.0), G (0.0, 12.0, 7.0), (0.0, -1.0, 0.0), Mat_Stone);
      --  the arcades: piers on both sides, a cornice above
      for K in 1 .. 9 loop
         declare
            X : constant Float := 6.0 * Float (K);
         begin
            for Side of Float_List'(-1.0, 1.0) loop
               Box (X - 0.7, X + 0.7, 0.0, 16.0, Side * 7.0 - 0.7, Side * 7.0 + 0.7, Mat_Stone);
            end loop;
         end;
      end loop;
      for Side of Float_List'(-1.0, 1.0) loop
         Box (3.0, 58.0, 15.4, 16.2, Side * 7.0 - 1.0, Side * 7.0 + 1.0, Mat_Stone);
      end loop;
      --  pews on both sides of the middle
      for R in 0 .. 12 loop
         declare
            X : constant Float := 10.0 + 2.6 * Float (R);
         begin
            for Side of Float_List'(-1.0, 1.0) loop
               Box (X, X + 0.45, 0.42, 0.48, Side * 1.3, Side * 6.0, Mat_Wood);
               Box (X + 0.4, X + 0.48, 0.48, 0.95, Side * 1.3, Side * 6.0, Mat_Wood);
               Box (X + 0.05, X + 0.1, 0.0, 0.42, Side * 1.4, Side * 1.5, Mat_Wood);
               Box (X + 0.05, X + 0.1, 0.0, 0.42, Side * 5.8, Side * 5.9, Mat_Wood);
            end loop;
         end;
      end loop;
      --  the choir: steps, the altar, candles and a gilded cross
      Box (54.0, 64.0, 0.0, 0.3, -7.0, 7.0, Mat_Marble);
      Box (55.0, 64.0, 0.3, 0.6, -6.0, 6.0, Mat_Marble);
      Box (59.0, 61.0, 0.6, 1.6, -2.0, 2.0, Mat_Marble);
      for K in -2 .. 2 loop
         Candle (G (60.0, 1.6, 0.6 * Float (K)));
      end loop;
      Box (60.0, 60.2, 1.6, 4.6, -0.12, 0.12, Mat_Gilt);
      Box (60.0, 60.2, 3.6, 3.85, -0.8, 0.8, Mat_Gilt);
      --  the brass meridian across the floor, and up the white obelisk
      Box (40.0, 40.08, 0.005, 0.02, -13.0, 13.0, Mat_Brass);
      Box (39.4, 40.6, 0.0, 10.0, 12.2, 13.4, Mat_Marble);
      Box (39.7, 40.3, 10.0, 11.0, 12.5, 13.1, Mat_Marble);
      Box (40.0, 40.08, 0.02, 10.0, 12.16, 12.2, Mat_Brass);
      --  the organ over the door: a gallery and a case of pipes
      Box (0.0, 4.0, 9.0, 10.0, -9.0, 9.0, Mat_Wood);
      Box (0.0, 1.6, 10.0, 21.0, -8.5, 8.5, Mat_Wood);
      for K in 0 .. 33 loop
         declare
            Z : constant Float := -8.0 + 16.0 * Float (K) / 33.0;
            Ht : constant Float := 4.0 + 4.5 * abs Sin (Float (K) * 0.28) + 2.5 * Float (if K mod 6 = 0 then 1 else 0);
         begin
            Box (1.65, 1.95, 11.0, 11.0 + Ht, Z - 0.17, Z + 0.17, Mat_Brass);
         end;
      end loop;
      --  candle stands along the aisles, and paintings in the chapels
      for K in 0 .. 3 loop
         declare
            X : constant Float := 12.0 + 12.0 * Float (K);
         begin
            for Side of Float_List'(-1.0, 1.0) loop
               Box (X - 0.8, X + 0.8, 0.0, 1.0, Side * 11.5 - 0.4, Side * 11.5 + 0.4, Mat_Iron_Stand);
               for J in 0 .. 9 loop
                  Candle (G (X - 0.7 + 0.15 * Float (J), 1.0, Side * 11.5 + 0.2 * Float (J mod 2) - 0.1));
               end loop;
               --  a dark old painting
               declare
                  ZW : constant Float := Side * 13.95;
                  N  : constant Vec3 := (0.0, 0.0, -Side);
               begin
                  Meshes.Quad_UV (G (X - 2.2, 3.0, ZW), G (X + 2.2, 3.0, ZW), G (X + 2.2, 8.5, ZW), G (X - 2.2, 8.5, ZW),
                                  N, Mat_Canvas, Float (7 + 16 * 5 + 128 * (K * 2 + (if Side > 0.0 then 1 else 0)) + 640));
               end;
            end loop;
         end;
      end loop;
      Door;
   end Build_A;

   ---------------------------------------------------------------------------
   --  B: a cabaret, 1890

   procedure Build_B is
      H : constant Float := 7.0;
   begin
      Shell (Mat_Parquet, Mat_Red, Mat_Dark, H);
      --  the stage at the far end, curtains either side
      Box (17.0, 24.0, 0.0, 1.0, -8.0, 8.0, Mat_Wood);
      for Side of Float_List'(-1.0, 1.0) loop
         Box (17.0, 17.6, 1.0, 7.0, Side * 8.0 - Side * 1.6, Side * 8.0, Mat_Red);
      end loop;
      Box (17.0, 17.6, 6.0, 7.0, -8.0, 8.0, Mat_Red);
      --  footlights
      for K in 0 .. 15 loop
         Box (17.05, 17.2, 1.0, 1.12, -7.5 + Float (K), -7.4 + Float (K), Mat_Amber);
      end loop;
      --  round tables with a red-shaded lamp
      for TX in 0 .. 2 loop
         for TZ in -2 .. 2 loop
            if not (TX = 0 and then TZ = -2) then   --  where the painter works
               declare
                  X : constant Float := 4.0 + 4.0 * Float (TX);
                  Z : constant Float := 3.3 * Float (TZ);
               begin
                  Box (X - 0.05, X + 0.05, 0.0, 0.72, Z - 0.05, Z + 0.05, Mat_Wood);
                  Box (X - 0.45, X + 0.45, 0.72, 0.76, Z - 0.45, Z + 0.45, Mat_Marble);
                  Box (X - 0.12, X + 0.12, 0.76, 1.0, Z - 0.12, Z + 0.12, Mat_Amber);
               end;
            end if;
         end loop;
      end loop;
      --  the easel, and the canvas on it
      Box (3.0, 3.06, 0.0, 1.9, -7.4, -7.34, Mat_Wood);
      Box (3.0, 3.06, 0.0, 1.9, -6.46, -6.4, Mat_Wood);
      Box (3.12, 3.18, 0.0, 1.7, -6.93, -6.87, Mat_Wood);
      Meshes.Quad_UV (G (3.04, 0.95, -7.45), G (3.04, 0.95, -6.35), G (3.04, 1.85, -6.35), G (3.04, 1.85, -7.45),
                      (-1.0, 0.0, 0.0), Mat_Canvas, Float (1 + 16 * 1 + 128 * 9));
      --  gas lamps on the walls
      for K in 0 .. 3 loop
         for Side of Float_List'(-1.0, 1.0) loop
            Box (2.5 + 4.0 * Float (K), 2.8 + 4.0 * Float (K), 3.2, 3.6, Side * 9.85, Side * 9.6, Mat_Amber);
         end loop;
      end loop;
      Door;
   end Build_B;

   ---------------------------------------------------------------------------
   --  C: a round room of panels and lights

   procedure Build_C is
      R : constant Float := 6.5;
      C : constant Vec3 := G (7.0, 0.0, 0.0);
   begin
      for K in 0 .. 23 loop
         declare
            A0 : constant Float := 2.0 * Pi * Float (K) / 24.0;
            A1 : constant Float := 2.0 * Pi * Float (K + 1) / 24.0;
            function P (A, Rad, Y : Float) return Vec3 is (C + Vec3'(Rad * Cos (A), Y, Rad * Sin (A)));
            Mid : constant Float := 0.5 * (A0 + A1);
         begin
            Face (P (A0, R, 0.0), P (A1, R, 0.0), P (A1, R - 1.0, 4.0), P (A0, R - 1.0, 4.0),
                  (-Cos (Mid), 0.2, -Sin (Mid)), Mat_Paint);
            Face (C + Vec3'(0.0, 0.0, 0.0), P (A0, R, 0.0), P (A1, R, 0.0), P (A1, R, 0.0), (0.0, 1.0, 0.0), Mat_Paint);
            Face (C + Vec3'(0.0, 4.0, 0.0), P (A0, R - 1.0, 4.0), P (A1, R - 1.0, 4.0), P (A1, R - 1.0, 4.0),
                  (0.0, -1.0, 0.0), Mat_Paint);
            --  a window strip, dark, with stars
            Face (P (A0, R - 0.42, 2.3), P (A1, R - 0.42, 2.3), P (A1, R - 0.6, 3.0), P (A0, R - 0.6, 3.0),
                  (-Cos (Mid), 0.0, -Sin (Mid)), Mat_Dark);
            if K mod 2 = 0 then
               Flame (P (Mid, R - 0.55, 2.65), 0.015);
            end if;
            --  panels with lights, all round
            Box (C.X - Origin.X + (R - 1.2) * Cos (Mid) - 0.4, C.X - Origin.X + (R - 1.2) * Cos (Mid) + 0.4, 0.0, 1.0,
                 (R - 1.2) * Sin (Mid) - 0.4, (R - 1.2) * Sin (Mid) + 0.4, Mat_Paint);
            for J in 0 .. 2 loop
               Meshes.Box (P (Mid, R - 1.62, 1.0).X - 0.06, P (Mid, R - 1.62, 1.0).X + 0.06, Origin.Y + 1.0, Origin.Y + 1.06,
                           P (Mid, R - 1.62, 1.0).Z - 0.06 + 0.2 * Float (J - 1) * Cos (Mid),
                           P (Mid, R - 1.62, 1.0).Z + 0.06 + 0.2 * Float (J - 1) * Cos (Mid), Mat_Lamp);
            end loop;
         end;
      end loop;
      --  the column of light in the middle
      Meshes.Box (C.X - 0.12, C.X + 0.12, C.Y, C.Y + 4.0, C.Z - 0.12, C.Z + 0.12, Mat_Lamp);
      Meshes.Box (C.X - 0.6, C.X + 0.6, C.Y, C.Y + 0.9, C.Z - 0.6, C.Z + 0.6, Mat_Paint);
   end Build_C;

   ---------------------------------------------------------------------------
   --  D: a maze of tunnels lined with bones, six coins to find

   N_Cells : constant := 11;
   Cell    : constant := 3.0;
   type Walls_Of is record
      East, South : Boolean := True;   --  a wall on that side of the cell
   end record;
   Maze : array (0 .. N_Cells - 1, 0 .. N_Cells - 1) of Walls_Of;
   type Coin is record
      P : Vec3;
      Got : Boolean := False;
   end record;
   Coins : array (1 .. 6) of Coin;
   Found_Coins : Natural := 0;
   Start_Time, Done_Time : Float := 0.0;
   Coin_M : Meshes.Mesh;
   Coin_Built : Boolean := False;

   --  the tunnels run from the door (X 0) along +X; cell (I, J) has its
   --  corner at X = 3 I, Z = 3 J - 16.5
   function Cell_X (I : Integer) return Float is (Cell * Float (I));
   function Cell_Z (J : Integer) return Float is (Cell * Float (J) - 16.5);

   procedure Carve is
      type Seen_Array is array (0 .. N_Cells - 1, 0 .. N_Cells - 1) of Boolean;
      Seen : Seen_Array := (others => (others => False));
      type Pair is record
         I, J : Integer;
      end record;
      type Pairs is array (Positive range <>) of Pair;
      Steps : constant Pairs := ((1, 0), (-1, 0), (0, 1), (0, -1));
      Stack : array (1 .. N_Cells * N_Cells) of Pair;
      Top   : Natural := 0;
      Dead  : array (1 .. 64) of Pair;
      N_Dead : Natural := 0;
   begin
      Maze := (others => (others => (True, True)));
      Seen (0, N_Cells / 2) := True;
      Top := 1;
      Stack (1) := (0, N_Cells / 2);
      while Top > 0 loop
         declare
            P : constant Pair := Stack (Top);
            Opts : Pairs (1 .. 4);
            N : Natural := 0;
         begin
            for D of Steps loop
               declare
                  Q : constant Pair := (P.I + D.I, P.J + D.J);
               begin
                  if Q.I in 0 .. N_Cells - 1 and then Q.J in 0 .. N_Cells - 1 and then not Seen (Q.I, Q.J) then
                     N := N + 1;
                     Opts (N) := Q;
                  end if;
               end;
            end loop;
            if N = 0 then
               --  a dead end (not the start): a place for a coin
               if N_Dead < Dead'Last and then not (P.I = 0 and then P.J = N_Cells / 2) then
                  declare
                     Walls : Natural := 0;
                  begin
                     if Maze (P.I, P.J).East then Walls := Walls + 1; end if;
                     if Maze (P.I, P.J).South then Walls := Walls + 1; end if;
                     if P.I = 0 or else Maze (P.I - 1, P.J).East then Walls := Walls + 1; end if;
                     if P.J = 0 or else Maze (P.I, P.J - 1).South then Walls := Walls + 1; end if;
                     if Walls = 3 then
                        N_Dead := N_Dead + 1;
                        Dead (N_Dead) := P;
                     end if;
                  end;
               end if;
               Top := Top - 1;
            else
               declare
                  Q : constant Pair := Opts (1 + Natural (Float'Floor (Rnd * Float (N) * 0.999)));
               begin
                  if Q.I > P.I then Maze (P.I, P.J).East := False;
                  elsif Q.I < P.I then Maze (Q.I, Q.J).East := False;
                  elsif Q.J > P.J then Maze (P.I, P.J).South := False;
                  else Maze (Q.I, Q.J).South := False;
                  end if;
                  Seen (Q.I, Q.J) := True;
                  Top := Top + 1;
                  Stack (Top) := Q;
               end;
            end if;
         end;
      end loop;
      --  the first step is always a way on
      Maze (0, N_Cells / 2).East := False;
      --  coins in six dead ends (or anywhere far, if there are too few)
      for K in Coins'Range loop
         declare
            P : constant Pair := (if K <= N_Dead then Dead (1 + (K * 7) mod N_Dead)
                                  else (N_Cells - 1 - K, K + 1));
         begin
            Coins (K) := (G (Cell_X (P.I) + Cell / 2.0, 0.9, Cell_Z (P.J) + Cell / 2.0) + Vec3'(0.0, 0.3, 0.0), False);
         end;
      end loop;
      Found_Coins := 0;
   end Carve;

   procedure Build_Coin is
   begin
      Meshes.Start;
      for K in 0 .. 11 loop
         declare
            A0 : constant Float := 2.0 * Pi * Float (K) / 12.0;
            A1 : constant Float := 2.0 * Pi * Float (K + 1) / 12.0;
            P0 : constant Vec3 := (0.18 * Cos (A0), 0.18 * Sin (A0), 0.0);
            P1 : constant Vec3 := (0.18 * Cos (A1), 0.18 * Sin (A1), 0.0);
         begin
            for S of Float_List'(-1.0, 1.0) loop
               Face (Vec3'(0.0, 0.0, 0.015 * S), P0 + Vec3'(0.0, 0.0, 0.015 * S), P1 + Vec3'(0.0, 0.0, 0.015 * S),
                     P1 + Vec3'(0.0, 0.0, 0.015 * S), (0.0, 0.0, S), Mat_Brass);
            end loop;
            Face (P0 + Vec3'(0.0, 0.0, -0.015), P1 + Vec3'(0.0, 0.0, -0.015), P1 + Vec3'(0.0, 0.0, 0.015),
                  P0 + Vec3'(0.0, 0.0, 0.015), (Cos (A0 + Pi / 12.0), Sin (A0 + Pi / 12.0), 0.0), Mat_Brass);
         end;
      end loop;
      Meshes.Finish (Coin_M);
      Coin_Built := True;
   end Build_Coin;

   procedure Build_D is
      H : constant Float := 2.3;
      procedure Wall (X0, Z0, X1, Z1 : Float) is
         A : constant Vec3 := G (X0, 0.0, Z0);
         B : constant Vec3 := G (X1, 0.0, Z1);
         D : constant Vec3 := Normalize (B - A);
         N : constant Vec3 := (-D.Z, 0.0, D.X);
         T : constant Float := 0.3;
      begin
         for S of Float_List'(-1.0, 1.0) loop
            Face (A + (S * T) * N, B + (S * T) * N, B + (S * T) * N + Vec3'(0.0, H, 0.0),
                  A + (S * T) * N + Vec3'(0.0, H, 0.0), S * N, Mat_Bones);
         end loop;
      end Wall;
      W : constant Float := Cell * Float (N_Cells);
   begin
      Meshes.Quad_UV (G (0.0, 0.0, -16.5), G (W, 0.0, -16.5), G (W, 0.0, 16.5), G (0.0, 0.0, 16.5),
                      (0.0, 1.0, 0.0), Mat_Ground, 0.0, W / 3.0, 11.0);
      Face (G (0.0, H, -16.5), G (W, H, -16.5), G (W, H, 16.5), G (0.0, H, 16.5), (0.0, -1.0, 0.0), Mat_Stone);
      --  the outer walls and the walls between the cells
      Wall (0.0, -16.5, W, -16.5);
      Wall (0.0, 16.5, W, 16.5);
      Wall (0.0, -16.5, 0.0, 16.5);
      Wall (W, -16.5, W, 16.5);
      for I in 0 .. N_Cells - 1 loop
         for J in 0 .. N_Cells - 1 loop
            if Maze (I, J).East and then I < N_Cells - 1 then
               Wall (Cell_X (I + 1), Cell_Z (J), Cell_X (I + 1), Cell_Z (J + 1));
            end if;
            if Maze (I, J).South and then J < N_Cells - 1 then
               Wall (Cell_X (I), Cell_Z (J + 1), Cell_X (I + 1), Cell_Z (J + 1));
            end if;
            --  now and then a torch on a wall
            if (I * 7 + J * 3) mod 9 = 0 then
               Flame (G (Cell_X (I) + 1.5, 1.7, Cell_Z (J) + 0.32), 0.06);
            end if;
         end loop;
      end loop;
      --  the way out at the far end: a lit opening (the door marks it)
      Face (G (W - 0.05, 0.0, Cell_Z (N_Cells / 2) + 0.4), G (W - 0.05, 0.0, Cell_Z (N_Cells / 2) + 2.6),
            G (W - 0.05, 2.0, Cell_Z (N_Cells / 2) + 2.6), G (W - 0.05, 2.0, Cell_Z (N_Cells / 2) + 0.4),
            (-1.0, 0.0, 0.0), Mat_Wood);
      Box (W - 0.12, W - 0.03, 2.05, 2.25, Cell_Z (N_Cells / 2) + 0.9, Cell_Z (N_Cells / 2) + 2.1, Mat_Exit);
   end Build_D;

   ---------------------------------------------------------------------------

   procedure Enter (K : Room_Kind; From_X, From_Z, From_Yaw : Float) is
      X, Z : Long_Float;
   begin
      if not Seeded then
         Ada.Numerics.Float_Random.Reset (Gen);
         Seeded := True;
      end if;
      if not Loaded then
         Load;
      end if;
      Kind := K;
      Back_X := From_X;
      Back_Z := From_Z;
      Back_Yaw := From_Yaw;
      Geo.To_Local (Data (K).At_Lat, Data (K).At_Lon, X, Z);
      Origin := (Float (X), Terrain.Height (Float (X), Float (Z)) - (if K = Room_D then 70.0 else 50.0), Float (Z));
      Need_Build := True;
      Carve;
      Inside_Time := 0.0;
      Start_Time := Clock;
      Done_Time := 0.0;
      if K = Room_A then
         Sound.Effect (Sound.Organ, 1.4, 0.0);
      end if;
   end Enter;

   procedure Entrance (X, Z, Yaw : out Float) is
   begin
      case Kind is
         when Room_C =>
            X := Origin.X + 3.0;
            Z := Origin.Z;
         when Room_D =>
            X := Origin.X + 1.5;
            Z := Origin.Z + Cell_Z (N_Cells / 2) + 1.5;
         when others =>
            X := Origin.X + 3.0;
            Z := Origin.Z;
      end case;
      Yaw := Pi / 2.0;   --  east, into the room
   end Entrance;

   procedure Way_Out (X, Z, Yaw : out Float) is
      D : Room_Data renames Data (Kind);
      LX, LZ : Long_Float;
   begin
      if D.Has_Out then
         Geo.To_Local (D.Out_Lat, D.Out_Lon, LX, LZ);
         X := Float (LX);
         Z := Float (LZ);
         Yaw := D.Out_Yaw;
      else
         X := Back_X;
         Z := Back_Z;
         Yaw := Back_Yaw;
      end if;
   end Way_Out;

   procedure Keep_Inside (X, Z : in out Float) is
      LX : Float := X - Origin.X;
      LZ : Float := Z - Origin.Z;
      M  : constant Float := 0.4;
   begin
      case Kind is
         when Room_C =>
            declare
               DX : constant Float := LX - 7.0;
               D  : constant Float := Sqrt (DX * DX + LZ * LZ);
            begin
               if D > 5.0 then
                  LX := 7.0 + DX * 5.0 / D;
                  LZ := LZ * 5.0 / D;
               elsif D < 0.8 and then D > 0.01 then
                  LX := 7.0 + DX * 0.8 / D;
                  LZ := LZ * 0.8 / D;
               end if;
            end;
         when Room_D =>
            declare
               I : constant Integer := Integer'Max (0, Integer'Min (N_Cells - 1, Integer (Float'Floor (LX / Cell))));
               J : constant Integer := Integer'Max (0, Integer'Min (N_Cells - 1, Integer (Float'Floor ((LZ + 16.5) / Cell))));
               U : Float := LX - Cell_X (I);
               V : Float := LZ - Cell_Z (J);
            begin
               if (I = 0 or else Maze (I - 1, J).East) and then U < M then U := M; end if;
               if (I = N_Cells - 1 or else Maze (I, J).East) and then U > Cell - M then U := Cell - M; end if;
               if (J = 0 or else Maze (I, J - 1).South) and then V < M then V := M; end if;
               if (J = N_Cells - 1 or else Maze (I, J).South) and then V > Cell - M then V := Cell - M; end if;
               LX := Cell_X (I) + U;
               LZ := Cell_Z (J) + V;
            end;
         when others =>
            LX := Float'Max (M, Float'Min (Length_Of - M, LX));
            LZ := Float'Max (-Half_W + M, Float'Min (Half_W - M, LZ));
            if Kind = Room_A and then LX > 54.0 then
               LX := 54.0;   --  not up into the choir
            elsif Kind = Room_B and then LX > 16.6 then
               LX := 16.6;   --  not onto the stage
            end if;
      end case;
      X := Origin.X + LX;
      Z := Origin.Z + LZ;
   end Keep_Inside;

   function At_Exit (X, Z : Float) return Boolean is
      LX : constant Float := X - Origin.X;
      LZ : constant Float := Z - Origin.Z;
   begin
      case Kind is
         when Room_C =>
            return Inside_Time > 12.0;
         when Room_D =>
            return Found_Coins = Coins'Length and then LX > Cell_X (N_Cells) - 1.0
              and then abs (LZ - (Cell_Z (N_Cells / 2) + 1.5)) < 1.2;
         when others =>
            return LX < 1.2 and then abs LZ < 1.6;
      end case;
   end At_Exit;

   function Light return Float is
     (case Kind is when Room_C => 2.0, when Room_D => 3.0, when others => 1.0);

   procedure Update (Dt : Float; X, Z : Float) is
   begin
      Clock := Clock + Dt;
      Inside_Time := Inside_Time + Dt;
      Me_X := X;
      Me_Z := Z;
      if Kind = Room_D then
         for C of Coins loop
            if not C.Got and then (C.P.X - X) ** 2 + (C.P.Z - Z) ** 2 < 0.9 ** 2 then
               C.Got := True;
               Found_Coins := Found_Coins + 1;
               Sound.Effect (Sound.Beep, 0.7, 0.0);
               if Found_Coins = Coins'Length then
                  Done_Time := Clock - Start_Time;
                  Sound.Effect (Sound.Go_Beep, 0.8, 0.0);
               end if;
            end if;
         end loop;
      end if;
   end Update;

   function Time_Image (T : Float) return String is
      S : constant Natural := Natural (Float'Floor (T));
      SS : constant String := Natural'Image (100 + S mod 60);
   begin
      return Ada.Strings.Fixed.Trim (Natural'Image (S / 60), Ada.Strings.Left) & ":" & SS (SS'Last - 1 .. SS'Last);
   end Time_Image;

   function Status return String is
   begin
      case Kind is
         when Room_D =>
            return "<span font_family='sans' weight='bold'>" & To_String (Data (Kind).Note) & "  "
              & Ada.Strings.Fixed.Trim (Natural'Image (Found_Coins), Ada.Strings.Left) & "/6    "
              & Time_Image (if Found_Coins = Coins'Length then Done_Time else Clock - Start_Time)
              & (if Found_Coins = Coins'Length then "    the way out is open, at the far end" else "")
              & "</span>";
         when Room_B =>
            if (Me_X - (Origin.X + 3.0)) ** 2 + (Me_Z - (Origin.Z - 6.9)) ** 2 < 3.5 ** 2 then
               return "<span font_family='serif' size='large'><i>" & To_String (Data (Kind).Note) & "</i></span>";
            end if;
            return "";
         when Room_A =>
            if abs (Me_X - (Origin.X + 40.0)) < 3.0 then
               return "<span font_family='serif' size='large'><i>" & To_String (Data (Kind).Note) & "</i></span>";
            end if;
            return "";
         when Room_C =>
            return "";
      end case;
   end Status;

   function Heading return String is (To_String (Data (Kind).Head));
   function Arrival return String is (To_String (Data (Kind).Arrive));
   function Leaving return String is (To_String (Data (Kind).Leave));

   procedure Draw (Model, Paint, Skin, Legs, Gallery : GL.GLint) is
      Skins : constant array (0 .. 3) of Vec3 :=
        ((0.86, 0.68, 0.56), (0.76, 0.57, 0.44), (0.58, 0.40, 0.29), (0.40, 0.27, 0.19));
      Coats : constant array (0 .. 5) of Vec3 :=
        ((0.1, 0.1, 0.12), (0.35, 0.25, 0.2), (0.2, 0.22, 0.35), (0.5, 0.1, 0.1), (0.3, 0.3, 0.3), (0.15, 0.25, 0.15));
   begin
      if Need_Build then
         Need_Build := False;
         if Built then
            Meshes.Free (Hall);
         end if;
         if Kind = Room_D and then not Coin_Built then
            Build_Coin;
         end if;
         Meshes.Start;
         case Kind is
            when Room_A => Build_A;
            when Room_B => Build_B;
            when Room_C => Build_C;
            when Room_D => Build_D;
         end case;
         Meshes.Finish (Hall);
         Built := True;
      end if;
      if not Built then
         return;
      end if;
      Shaders.Set (Gallery, Light);
      Shaders.Set (Model, Identity);
      Shaders.Set (Paint, (if Kind = Room_C then Vec3'(0.36, 0.40, 0.44) else Vec3'(0.6, 0.6, 0.62)));
      Shaders.Set (Skin, (if Kind = Room_C
                          then (0.8 + 0.2 * Sin (Clock * 3.0)) * Vec3'(0.35, 1.0, 0.8)
                          else Vec3'(1.0, 0.8, 0.5)));
      Meshes.Draw (Hall);
      Figures.Set_Locations ((Model, Paint, Skin, Legs));
      case Kind is
         when Room_A =>
            --  a few people sitting or standing quietly
            for K in 0 .. 7 loop
               declare
                  X : constant Float := 12.0 + 3.6 * Float (K);
                  Z : constant Float := (if K mod 2 = 0 then -3.0 else 4.0);
               begin
                  Figures.Person (Translation (G (X, 0.0, Z)) * Rotation_Y (-Pi / 2.0),
                                  Coats (K mod 6), Skins (K mod 4), (0.12, 0.12, 0.15));
               end;
            end loop;
         when Room_B =>
            --  the dancers, kicking high in a line
            for K in 0 .. 5 loop
               declare
                  Kick : constant Float := 1.1 * Sin (Clock * 7.0 + Float (K) * Pi);
               begin
                  Figures.Person (Translation (G (20.0, 1.0, -5.0 + 2.0 * Float (K))) * Rotation_Y (Pi / 2.0),
                                  (if K mod 2 = 0 then Vec3'(0.95, 0.95, 0.92) else Vec3'(0.85, 0.1, 0.12)),
                                  Skins (K mod 2), (0.95, 0.9, 0.9),
                                  Stride => Kick, Arm_Up => -2.0 - 0.3 * Sin (Clock * 7.0));
               end;
            end loop;
            --  people at the tables, watching
            for K in 0 .. 9 loop
               declare
                  X : constant Float := 4.0 + 4.0 * Float (K mod 3) - 0.8;
                  Z : constant Float := 3.3 * Float (K mod 5 - 2) + 0.6;
               begin
                  Figures.Person (Translation (G (X, 0.0, Z)) * Rotation_Y (-Pi / 2.0),
                                  Coats (K mod 6), Skins ((K * 3) mod 4), (0.1, 0.1, 0.12),
                                  Hat => (if K mod 3 = 0 then Figures.Cap else Figures.None),
                                  Hat_Colour => (0.08, 0.08, 0.08));
               end;
            end loop;
            --  the painter: small, a bowler hat, at his easel
            Figures.Person (Translation (G (2.0, 0.0, -6.9)) * Rotation_Y (-Pi / 2.0) * Scale (0.82),
                            (0.12, 0.12, 0.14), Skins (0), (0.15, 0.12, 0.1),
                            Hat => Figures.Cap, Hat_Colour => (0.05, 0.05, 0.05),
                            Arm_Up => -1.2 + 0.25 * Sin (Clock * 2.3));
         when Room_C =>
            --  three small green crew, their heads big
            for K in 0 .. 2 loop
               declare
                  A : constant Float := 2.0 * Pi * Float (K) / 3.0 + 0.3 * Sin (Clock * 0.4);
                  P : constant Vec3 := G (7.0 + 3.8 * Cos (A), 0.0, 3.8 * Sin (A));
               begin
                  Figures.Person (Translation (P) * Rotation_Y (-A - Pi / 2.0 + 0.4 * Sin (Clock + Float (K)))
                                  * Scale (0.75),
                                  (0.75, 0.78, 0.82), (0.45, 0.85, 0.4), (0.75, 0.78, 0.82),
                                  Arm_Up => (if K = 1 then -1.6 + 0.3 * Sin (Clock * 4.0) else 0.0));
               end;
            end loop;
         when Room_D =>
            --  the coins, turning, until found
            if Coin_Built then
               for C of Coins loop
                  if not C.Got then
                     Shaders.Set (Model, Translation (C.P + Vec3'(0.0, 0.05 * Sin (Clock * 2.0), 0.0))
                                         * Rotation_Y (Clock * 2.0));
                     Meshes.Draw (Coin_M);
                  end if;
               end loop;
            end if;
      end case;
      Shaders.Set (Gallery, 0.0);
      Shaders.Set (Model, Identity);
   end Draw;

end Rooms;
