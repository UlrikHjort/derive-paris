--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Calendar;
with Ada.Calendar.Arithmetic;
with Ada.Calendar.Formatting;
with Ada.Containers.Vectors;
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces;

with Almanac;
with Arc_Top;
with Figures;
with Geo;
with Math3D;
with Meshes;
with Road_Network;
with Shaders;
with Terrain;

package body Scenes is

   use Math3D;
   use Ada.Numerics.Elementary_Functions;
   use Ada.Strings.Unbounded;

   Pi : constant := Ada.Numerics.Pi;

   type Float_List is array (Positive range <>) of Float;

   --  Materials (world.frag)
   Mat_Planks : constant := 60.0;
   Mat_Glow   : constant := 61.0;
   Mat_Snow   : constant := 39.0;
   Mat_Fir    : constant := 37.0;
   Mat_Light  : constant := 38.0;
   Mat_Wood   : constant := 13.0;
   Mat_Iron   : constant := 26.0;
   Mat_White  : constant := 53.0;
   Mat_Green  : constant := 56.0;
   Mat_Poster : constant := 55.0;
   Mat_Ice    : constant := 62.0;
   Mat_Show   : constant := 63.0;
   Mat_Awning : constant := 65.0;
   Mat_Books  : constant := 66.0;
   Mat_Lamp   : constant := 50.0;   --  in the colour of uExtraColor
   Mat_Marble : constant := 45.0;
   Wares : constant Float_List := (40.0, 46.0, 48.0, 37.0, 45.0, 38.0);

   Skins : constant array (0 .. 3) of Vec3 :=
     ((0.86, 0.68, 0.56), (0.76, 0.57, 0.44), (0.58, 0.40, 0.29), (0.40, 0.27, 0.19));
   Coats : constant array (0 .. 7) of Vec3 :=
     ((0.55, 0.08, 0.1), (0.12, 0.15, 0.3), (0.2, 0.2, 0.22), (0.45, 0.3, 0.18),
      (0.15, 0.32, 0.2), (0.75, 0.7, 0.62), (0.35, 0.12, 0.35), (0.8, 0.55, 0.15));

   function Hash (A, B : Float) return Float is
      V : constant Float := Sin (A * 12.9898 + B * 78.233) * 43758.5453;
   begin
      return V - Float'Floor (V);
   end Hash;

   ---------------------------------------------------------------------------
   --  The data
   ---------------------------------------------------------------------------

   type Kind_Type is (Huts, Rink, Stalls, Boxes, Show, Glow, Crowd_Kind, Unknown);

   package Text_Vectors is new Ada.Containers.Vectors (Positive, Unbounded_String);
   package Vec_Vectors is new Ada.Containers.Vectors (Positive, Vec3);

   type Solid is record
      X, Z, R : Float;
   end record;
   package Solid_Vectors is new Ada.Containers.Vectors (Positive, Solid);

   type Scene is record
      Kind     : Kind_Type := Unknown;
      Whens    : Text_Vectors.Vector;
      H0, H1   : Float := 0.0;
      Open0, Open1 : Float := 0.0;
      Points   : Vec_Vectors.Vector;     --  local x, ground y, z
      Tags     : Text_Vectors.Vector;    --  what each point is
      Streets  : Text_Vectors.Vector;
      Heights  : Vec_Vectors.Vector;     --  extra numbers per point (x)
      Mesh, Mesh2 : Meshes.Mesh;
      Built    : Boolean := False;
      Centre   : Vec3 := (0.0, 0.0, 0.0);
      Reach    : Float := 80.0;
      Solids   : Solid_Vectors.Vector;
      Say      : Unbounded_String;       --  shown when the countdown is over
      On       : Boolean := False;       --  happening now
      Late     : Boolean := False;       --  ... carried over from yesterday
   end record;

   package Scene_Vectors is new Ada.Containers.Vectors (Positive, Scene);
   All_Scenes : Scene_Vectors.Vector;

   Override : Character := 'a';
   Clock    : Float := 0.0;
   Hour_Now : Float := 12.0;
   Rate_Now : Float := 1.0 / 60.0;

   procedure Set_Override (Huts : Character) is
   begin
      Override := Huts;
   end Set_Override;

   function Local (Lat, Lon : Long_Float) return Vec3 is
      X, Z : Long_Float;
   begin
      Geo.To_Local (Lat, Lon, X, Z);
      return (Float (X), 0.0, Float (Z));
   end Local;

   function On_Ground (P : Vec3) return Vec3 is ((P.X, Terrain.Height (P.X, P.Z), P.Z));

   procedure Load is
      use type Interfaces.Unsigned_8;
      Key  : constant String := "derive-paris";
      F    : Ada.Text_IO.File_Type;
      Cur  : Scene;
      Have : Boolean := False;
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
      --  the words of a line
      function Word (L : String; N : Positive) return String is
         Count : Natural := 0;
         I     : Natural := L'First;
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
      function Num (L : String; N : Positive) return Long_Float is (Long_Float'Value (Word (L, N)));
      procedure Finish is
      begin
         if Have and then Cur.Kind /= Unknown then
            All_Scenes.Append (Cur);
         end if;
         Cur := (others => <>);
      end Finish;
   begin
      All_Scenes.Clear;
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, "data/scenes.dat");
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            Raw : constant String := Ada.Text_IO.Get_Line (F);
         begin
            if Raw'Length > 0 and then Raw (Raw'First) = '[' then
               Finish;
               Have := True;
            elsif Raw'Length > 1 then
               declare
                  L : constant String := Plain (Raw);
                  W : constant String := Word (L, 1);
                  Rest : constant String :=
                    (if L'Length > W'Length then L (L'First + W'Length + 1 .. L'Last) else "");
               begin
                  if W = "kind" then
                     declare
                        K : constant String := Word (L, 2);
                     begin
                        Cur.Kind := (if K = "huts" then Huts elsif K = "rink" then Rink
                                     elsif K = "stalls" then Stalls elsif K = "boxes" then Boxes
                                     elsif K = "show" then Show elsif K = "glow" then Glow
                                     elsif K = "crowd" then Crowd_Kind else Unknown);
                     end;
                  elsif W = "when" then
                     Cur.Whens.Append (To_Unbounded_String (Rest));
                  elsif W = "hours" then
                     Cur.H0 := Float (Num (L, 2));
                     Cur.H1 := Float (Num (L, 3));
                  elsif W = "open" then
                     Cur.Open0 := Float (Num (L, 2));
                     Cur.Open1 := Float (Num (L, 3));
                  elsif W = "say" then
                     Cur.Say := To_Unbounded_String (Rest);
                  elsif W = "street" then
                     Cur.Streets.Append (To_Unbounded_String (Rest));
                  elsif W = "at" or else W = "ring" or else W = "columns" or else W = "sphere"
                    or else W = "screens"
                  then
                     Cur.Points.Append (Local (Num (L, 2), Num (L, 3)));
                     Cur.Tags.Append (To_Unbounded_String (W));
                  elsif W = "along" or else W = "line" or else W = "crowd" or else W = "facade" then
                     Cur.Points.Append (Local (Num (L, 2), Num (L, 3)));
                     Cur.Tags.Append (To_Unbounded_String (W));
                     Cur.Points.Append (Local (Num (L, 4), Num (L, 5)));
                     Cur.Tags.Append (To_Unbounded_String (W & "_end"));
                     Cur.Heights.Append (Vec3'((if Word (L, 6) /= "" then Float (Num (L, 6)) else 0.0), 0.0, 0.0));
                  end if;
               end;
            end if;
         end;
      end loop;
      Finish;
      Ada.Text_IO.Close (F);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
   end Load;

   ---------------------------------------------------------------------------
   --  When
   ---------------------------------------------------------------------------

   --  Does one "when" line hold on this day?
   function Holds (Rule : String; Y, M, D : Integer; Dow : Positive) return Boolean is
      Tokens : array (1 .. 20) of Unbounded_String;
      N      : Natural := 0;
      I      : Positive := 1;
      function MM_DD (S : String) return Integer is
        (Integer'Value (S (S'First .. S'First + 1)) * 100 + Integer'Value (S (S'First + 3 .. S'First + 4)));
      Today : constant Integer := M * 100 + D;
   begin
      declare
         S : constant String := Rule & " ";
         Start : Natural := S'First;
      begin
         for K in S'Range loop
            if S (K) = ' ' then
               if K > Start and then N < Tokens'Last then
                  N := N + 1;
                  Tokens (N) := To_Unbounded_String (S (Start .. K - 1));
               end if;
               Start := K + 1;
            end if;
         end loop;
      end;
      while I <= N loop
         declare
            T : constant String := To_String (Tokens (I));
         begin
            if T = "every" then
               I := I + 1;
            elsif T = "advent" then
               if Override = 'n' then
                  return False;
               elsif Override /= 'y' then
                  declare
                     Eve  : constant Ada.Calendar.Time := Ada.Calendar.Time_Of (Y, 12, 24, 43_200.0);
                     Back : constant Integer :=
                       (Ada.Calendar.Formatting.Day_Name'Pos (Ada.Calendar.Formatting.Day_Of_Week (Eve)) + 1) mod 7;
                     First : constant Integer := 24 - Back - 21;
                  begin
                     if not ((M = 1 and then D <= 6) or else (M = 12 and then D >= First)
                             or else (M = 11 and then D - 30 >= First))
                     then
                        return False;
                     end if;
                  end;
               end if;
               I := I + 1;
            elsif T = "date" then
               if Today /= MM_DD (To_String (Tokens (I + 1))) then
                  return False;
               end if;
               I := I + 2;
            elsif T = "from" then
               declare
                  A : constant Integer := MM_DD (To_String (Tokens (I + 1)));
                  B : constant Integer := MM_DD (To_String (Tokens (I + 3)));
               begin
                  if (if A <= B then Today < A or else Today > B else Today < A and then Today > B) then
                     return False;
                  end if;
               end;
               I := I + 4;
            elsif T = "months" or else T = "weekday" then
               declare
                  Hit : Boolean := False;
                  J   : Positive := I + 1;
               begin
                  while J <= N and then To_String (Tokens (J)) (1) in '0' .. '9' loop
                     if Integer'Value (To_String (Tokens (J))) = (if T = "months" then M else Dow) then
                        Hit := True;
                     end if;
                     J := J + 1;
                  end loop;
                  if not Hit then
                     return False;
                  end if;
                  I := J;
               end;
            elsif T = "first_saturday" then
               if M /= Integer'Value (To_String (Tokens (I + 1))) or else Dow /= 6 or else D > 7 then
                  return False;
               end if;
               I := I + 2;
            else
               I := I + 1;
            end if;
         end;
      end loop;
      return True;
   end Holds;

   function Day_Holds (S : Scene; T : Ada.Calendar.Time) return Boolean is
      Y  : constant Integer := Ada.Calendar.Year (T);
      M  : constant Integer := Ada.Calendar.Month (T);
      D  : constant Integer := Ada.Calendar.Day (T);
      Dw : constant Positive :=
        Ada.Calendar.Formatting.Day_Name'Pos (Ada.Calendar.Formatting.Day_Of_Week (T)) + 1;
   begin
      for W of S.Whens loop
         if Holds (To_String (W), Y, M, D, Dw) then
            return True;
         end if;
      end loop;
      return False;
   end Day_Holds;

   procedure Decide (S : in out Scene; Hour : Float) is
      Today : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (Almanac.Year, Almanac.Month, Almanac.Day, 43_200.0);
      Yesterday : constant Ada.Calendar.Time := Ada.Calendar.Arithmetic."-" (Today, 1);
   begin
      S.Late := False;
      if Day_Holds (S, Today) and then Hour >= S.H0 and then Hour < Float'Min (24.0, S.H1) then
         S.On := True;
      elsif S.H1 > 24.0 and then Hour + 24.0 < S.H1 and then Day_Holds (S, Yesterday) then
         S.On := True;
         S.Late := True;
      else
         S.On := False;
      end if;
   end Decide;

   ---------------------------------------------------------------------------
   --  Shapes
   ---------------------------------------------------------------------------

   --  A quad with the corners put in order for the normal it should have;
   --  for a triangle the doubled corner goes in the middle (B = C)
   procedure Face (A, B, C, D, N : Vec3; Mat : Float) is
   begin
      if Dot (Cross (B - A, D - A), N) >= 0.0 then
         Meshes.Quad (A, B, C, D, Mat);
      else
         Meshes.Quad (D, C, B, A, Mat);
      end if;
   end Face;

   --  A box in a frame: U across, V back
   procedure Box (O, U, V : Vec3; X0, X1, Y0, Y1, Z0, Z1 : Float; Mat : Float) is
      Up : constant Vec3 := (0.0, 1.0, 0.0);
      function K (X, Y, Z : Float) return Vec3 is (O + X * U + Vec3'(0.0, Y, 0.0) + Z * V);
   begin
      Face (K (X0, Y0, Z0), K (X1, Y0, Z0), K (X1, Y1, Z0), K (X0, Y1, Z0), (-1.0) * V, Mat);
      Face (K (X0, Y0, Z1), K (X1, Y0, Z1), K (X1, Y1, Z1), K (X0, Y1, Z1), V, Mat);
      Face (K (X0, Y0, Z0), K (X0, Y0, Z1), K (X0, Y1, Z1), K (X0, Y1, Z0), (-1.0) * U, Mat);
      Face (K (X1, Y0, Z0), K (X1, Y0, Z1), K (X1, Y1, Z1), K (X1, Y1, Z0), U, Mat);
      Face (K (X0, Y1, Z0), K (X1, Y1, Z0), K (X1, Y1, Z1), K (X0, Y1, Z1), Up, Mat);
   end Box;

   procedure Cube (P : Vec3; S : Float; Mat : Float) is
   begin
      Meshes.Box (P.X - S, P.X + S, P.Y - S, P.Y + S, P.Z - S, P.Z + S, Mat);
   end Cube;

   procedure Pole (P : Vec3; H : Float; Mat : Float := Mat_Iron) is
   begin
      Meshes.Box (P.X - 0.05, P.X + 0.05, P.Y, P.Y + H, P.Z - 0.05, P.Z + 0.05, Mat);
   end Pole;

   --  Cones of a tree, its lights and its star
   procedure Tree (C : Vec3) is
      procedure Cone (R, Y0, Y1 : Float) is
         Segs : constant := 18;
         Apex : constant Vec3 := C + Vec3'(0.0, Y1, 0.0);
      begin
         for I in 0 .. Segs - 1 loop
            declare
               A0 : constant Float := 2.0 * Pi * Float (I) / Float (Segs);
               A1 : constant Float := 2.0 * Pi * Float (I + 1) / Float (Segs);
               P0 : constant Vec3 := C + Vec3'(R * Cos (A0), Y0, R * Sin (A0));
               P1 : constant Vec3 := C + Vec3'(R * Cos (A1), Y0, R * Sin (A1));
            begin
               Face (P0, Apex, Apex, P1, Vec3'(Cos (0.5 * (A0 + A1)), 0.4, Sin (0.5 * (A0 + A1))), Mat_Fir);
               Face (P0, C + Vec3'(0.0, Y0, 0.0), C + Vec3'(0.0, Y0, 0.0), P1, (0.0, -1.0, 0.0), Mat_Fir);
            end;
         end loop;
      end Cone;
   begin
      Meshes.Box (C.X - 0.2, C.X + 0.2, C.Y, C.Y + 1.5, C.Z - 0.2, C.Z + 0.2, Mat_Wood);
      Cone (3.2, 1.2, 6.0);
      Cone (2.5, 4.0, 8.5);
      Cone (1.7, 6.6, 10.8);
      for L in 0 .. 70 loop
         declare
            T : constant Float := Float (L) / 70.0;
            R : constant Float := 3.0 * (1.0 - T) + 0.25;
            A : constant Float := 2.0 * Pi * 5.0 * T;
         begin
            Cube (C + Vec3'(R * Cos (A), 1.5 + 9.0 * T, R * Sin (A)), 0.06, Mat_Light);
         end;
      end loop;
      Meshes.Box (C.X - 0.3, C.X + 0.3, C.Y + 10.7, C.Y + 11.4, C.Z - 0.08, C.Z + 0.08, Mat_Light);
      Meshes.Box (C.X - 0.08, C.X + 0.08, C.Y + 10.7, C.Y + 11.4, C.Z - 0.3, C.Z + 0.3, Mat_Light);
   end Tree;

   --  A wooden hut, its open front facing -V
   procedure Hut (O, U, V : Vec3; Index : Natural; Solids : in out Solid_Vectors.Vector) is
      W  : constant Float := 1.6;
      D  : constant Float := 2.2;
      H  : constant Float := 2.3;
      Rf : constant Float := 3.4;
      Up : constant Vec3 := (0.0, 1.0, 0.0);
      function K (X, Y, Z : Float) return Vec3 is (O + X * U + Vec3'(0.0, Y, 0.0) + Z * V);
   begin
      Box (O, U, V, -W, W, 0.0, H, D - 0.12, D, Mat_Planks);
      Box (O, U, V, -W, -W + 0.12, 0.0, H, 0.0, D, Mat_Planks);
      Box (O, U, V, W - 0.12, W, 0.0, H, 0.0, D, Mat_Planks);
      Box (O, U, V, -W, W, 0.0, 0.95, 0.0, 0.12, Mat_Planks);
      Face (K (-W + 0.12, 0.95, D - 0.13), K (W - 0.12, 0.95, D - 0.13),
            K (W - 0.12, H, D - 0.13), K (-W + 0.12, H, D - 0.13), (-1.0) * V, Mat_Glow);
      Face (K (-W + 0.12, H - 0.01, 0.12), K (W - 0.12, H - 0.01, 0.12),
            K (W - 0.12, H - 0.01, D - 0.12), K (-W + 0.12, H - 0.01, D - 0.12), (-1.0) * Up, Mat_Glow);
      for Shelf in 0 .. 1 loop
         declare
            Y : constant Float := 1.25 + 0.5 * Float (Shelf);
         begin
            Box (O, U, V, -W + 0.15, W - 0.15, Y - 0.03, Y, D - 0.5, D - 0.13, Mat_Wood);
            for K2 in 0 .. 6 loop
               declare
                  X : constant Float := -W + 0.35 + Float (K2) * (2.0 * W - 0.7) / 6.0;
                  S : constant Float := 0.07 + 0.03 * Float ((K2 + Index) mod 3);
               begin
                  Box (O, U, V, X - S, X + S, Y, Y + 2.0 * S, D - 0.4, D - 0.4 + 2.0 * S,
                       Wares (1 + (Index * 3 + K2 + Shelf) mod Wares'Length));
               end;
            end loop;
         end;
      end loop;
      Box (O, U, V, -W - 0.05, W + 0.05, 0.95, 1.0, -0.25, 0.3, Mat_Wood);
      for K2 in 0 .. 3 loop
         declare
            X : constant Float := -W + 0.5 + Float (K2) * (2.0 * W - 1.0) / 3.0;
         begin
            Box (O, U, V, X - 0.1, X + 0.1, 1.0, 1.12, -0.1, 0.1, Wares (1 + (Index + K2 * 2) mod Wares'Length));
         end;
      end loop;
      Face (K (-W, H, 0.0), K (-W, Rf, D / 2.0), K (-W, Rf, D / 2.0), K (-W, H, D), (-1.0) * U, Mat_Planks);
      Face (K (W, H, 0.0), K (W, Rf, D / 2.0), K (W, Rf, D / 2.0), K (W, H, D), U, Mat_Planks);
      for Side in 0 .. 1 loop
         declare
            Z_Eave : constant Float := (if Side = 0 then -0.6 else D + 0.25);
            Y_Eave : constant Float := H - (if Side = 0 then 0.55 else 0.2);
            Out_N  : constant Vec3 := Normalize ((if Side = 0 then (-1.0) else 1.0) * V + 0.9 * Up);
         begin
            Face (K (-W - 0.25, Y_Eave, Z_Eave), K (W + 0.25, Y_Eave, Z_Eave),
                  K (W + 0.25, Rf, D / 2.0), K (-W - 0.25, Rf, D / 2.0), Out_N, Mat_Wood);
            Face (K (-W - 0.25, Y_Eave + 0.08, Z_Eave), K (W + 0.25, Y_Eave + 0.08, Z_Eave),
                  K (W + 0.25, Rf + 0.08, D / 2.0), K (-W - 0.25, Rf + 0.08, D / 2.0), Out_N, Mat_Snow);
         end;
      end loop;
      for L in 0 .. 12 loop
         declare
            X   : constant Float := -W - 0.2 + Float (L) * (2.0 * W + 0.4) / 12.0;
            Sag : constant Float := 0.12 * Sin (Pi * Float (L mod 6) / 6.0);
         begin
            Cube (K (X, H - 0.62 - Sag, -0.58), 0.035, Mat_Light);
         end;
      end loop;
      declare
         M : constant Vec3 := K (0.0, 0.0, D / 2.0);
      begin
         Solids.Append ((M.X, M.Z, 1.9));
      end;
   end Hut;

   ---------------------------------------------------------------------------
   --  Building each kind
   ---------------------------------------------------------------------------

   Ring_R    : constant := 13.0;
   Ring_Huts : constant := 11;

   procedure Build_Huts (S : in out Scene) is
      C : constant Vec3 := On_Ground (S.Points (1));
   begin
      S.Centre := C;
      Meshes.Start;
      for I in 0 .. Ring_Huts - 1 loop
         if I /= 2 then   --  a gap to walk in
            declare
               A : constant Float := 2.0 * Pi * Float (I) / Float (Ring_Huts) + Pi / 2.0;
               V : constant Vec3 := (Cos (A), 0.0, Sin (A));
               U : constant Vec3 := (-Sin (A), 0.0, Cos (A));
            begin
               Hut (On_Ground (C + Ring_R * V), U, V, I, S.Solids);
            end;
         end if;
      end loop;
      Tree (C);
      S.Solids.Append ((C.X, C.Z, 3.0));
      for I in 0 .. Ring_Huts - 1 loop
         declare
            A : constant Float := 2.0 * Pi * (Float (I) + 0.5) / Float (Ring_Huts) + Pi / 2.0;
            P : constant Vec3 := On_Ground (C + (Ring_R - 1.2) * Vec3'(Cos (A), 0.0, Sin (A)));
         begin
            Pole (P, 2.6);
            Meshes.Box (P.X - 0.15, P.X + 0.15, P.Y + 2.6, P.Y + 2.95, P.Z - 0.15, P.Z + 0.15, Mat_Glow);
         end;
      end loop;
      Meshes.Finish (S.Mesh);
   end Build_Huts;

   --  The skating surface: R_Long x R_Wide, its long side along "along"
   R_Long : constant := 17.0;
   R_Wide : constant := 8.5;

   function Rink_Axis (S : Scene) return Vec3 is
      A : constant Vec3 := S.Points (2);
      B : constant Vec3 := S.Points (3);
   begin
      return Normalize (B - A);
   end Rink_Axis;

   procedure Build_Rink (S : in out Scene) is
      C  : constant Vec3 := On_Ground (S.Points (1));
      U  : constant Vec3 := Rink_Axis (S);
      V  : constant Vec3 := (-U.Z, 0.0, U.X);
      Up : constant Vec3 := (0.0, 1.0, 0.0);
      Y  : constant Float := C.Y + 0.08;
      function P (A, B : Float) return Vec3 is (Vec3'(C.X, Y, C.Z) + A * U + B * V);
   begin
      S.Centre := C;
      Meshes.Start;
      Face (P (-R_Long, -R_Wide), P (R_Long, -R_Wide), P (R_Long, R_Wide), P (-R_Long, R_Wide), Up, Mat_Ice);
      --  the boards round it, with a gap on one long side
      for Side in 0 .. 3 loop
         declare
            A0, B0, A1, B1 : Float;
            N : Vec3;
         begin
            case Side is
               when 0 => A0 := -R_Long; B0 := -R_Wide; A1 := R_Long; B1 := -R_Wide; N := (-1.0) * V;
               when 1 => A0 := R_Long; B0 := -R_Wide; A1 := R_Long; B1 := R_Wide; N := U;
               when 2 => A0 := R_Long; B0 := R_Wide; A1 := 1.5; B1 := R_Wide; N := V;
               when others => A0 := -R_Long; B0 := R_Wide; A1 := -R_Long; B1 := -R_Wide; N := (-1.0) * U;
            end case;
            Face (P (A0, B0), P (A1, B1), P (A1, B1) + Vec3'(0.0, 1.05, 0.0), P (A0, B0) + Vec3'(0.0, 1.05, 0.0),
                  N, Mat_White);
            Face (P (A0, B0), P (A1, B1), P (A1, B1) + Vec3'(0.0, 1.05, 0.0), P (A0, B0) + Vec3'(0.0, 1.05, 0.0),
                  (-1.0) * N, Mat_White);
            Face (P (A0, B0) + Vec3'(0.0, 1.05, 0.0), P (A1, B1) + Vec3'(0.0, 1.05, 0.0),
                  P (A1, B1) + Vec3'(0.0, 1.05, 0.0) + 0.12 * N, P (A0, B0) + Vec3'(0.0, 1.05, 0.0) + 0.12 * N,
                  Up, Mat_Wood);
            declare
               L : constant Float := Length (P (A1, B1) - P (A0, B0));
               K : Float := 0.0;
            begin
               while K <= L loop
                  declare
                     Q : constant Vec3 := P (A0, B0) + (K / Float'Max (L, 0.01)) * (P (A1, B1) - P (A0, B0));
                  begin
                     S.Solids.Append ((Q.X, Q.Z, 0.5));
                  end;
                  K := K + 1.5;
               end loop;
            end;
         end;
      end loop;
      Face (P (-R_Long, R_Wide), P (-1.5, R_Wide), P (-1.5, R_Wide) + Vec3'(0.0, 1.05, 0.0),
            P (-R_Long, R_Wide) + Vec3'(0.0, 1.05, 0.0), V, Mat_White);
      Face (P (-R_Long, R_Wide), P (-1.5, R_Wide), P (-1.5, R_Wide) + Vec3'(0.0, 1.05, 0.0),
            P (-R_Long, R_Wide) + Vec3'(0.0, 1.05, 0.0), (-1.0) * V, Mat_White);
      --  masts at the corners with strings of lights across
      declare
         Corners : constant array (1 .. 4) of Vec3 :=
           (P (-R_Long - 0.6, -R_Wide - 0.6), P (R_Long + 0.6, -R_Wide - 0.6),
            P (R_Long + 0.6, R_Wide + 0.6), P (-R_Long - 0.6, R_Wide + 0.6));
      begin
         for Q of Corners loop
            Pole (Q - Vec3'(0.0, 0.08, 0.0), 6.0);
         end loop;
         for Pair in 1 .. 4 loop
            declare
               A : constant Vec3 := Corners (Pair) + Vec3'(0.0, 5.9, 0.0);
               B : constant Vec3 := Corners (if Pair = 4 then 1 else Pair + 1) + Vec3'(0.0, 5.9, 0.0);
               Q : constant Vec3 := Corners ((Pair + 1) mod 4 + 1) + Vec3'(0.0, 5.9, 0.0);
            begin
               for L in 0 .. 40 loop
                  declare
                     T : constant Float := Float (L) / 40.0;
                  begin
                     Cube (A + T * (B - A) - Vec3'(0.0, 1.2 * Sin (Pi * T), 0.0), 0.05, Mat_Light);
                     if Pair <= 2 then   --  and across, corner to corner
                        Cube (A + T * (Q - A) - Vec3'(0.0, 1.8 * Sin (Pi * T), 0.0), 0.05, Mat_Light);
                     end if;
                  end;
               end loop;
            end;
         end loop;
      end;
      Meshes.Finish (S.Mesh);
   end Build_Rink;

   --  Two rows of stalls along a line, an aisle between them
   procedure Build_Stalls (S : in out Scene) is
      A : constant Vec3 := S.Points (1);
      B : constant Vec3 := S.Points (2);
      L : constant Float := Length (B - A);
      D : constant Vec3 := Normalize (B - A);
      N : constant Vec3 := (-D.Z, 0.0, D.X);
      T : Float := 3.0;
      K : Natural := 0;
   begin
      S.Centre := On_Ground (0.5 * (A + B));
      S.Reach := L / 2.0 + 40.0;
      Meshes.Start;
      while T < L - 3.0 loop
         for Side of Float_List'(-1.0, 1.0) loop
            declare
               O : constant Vec3 := On_Ground (A + T * D + (Side * 2.3) * N);
               U : constant Vec3 := D;
               V : constant Vec3 := Side * N;   --  away from the aisle
               Kind : constant Natural := Natural (Float'Floor (Hash (T, Side) * 4.99));
               function Q (X, Y, Z : Float) return Vec3 is (O + X * U + Vec3'(0.0, Y, 0.0) + Z * V);
            begin
               for PX of Float_List'(-1.5, 1.5) loop
                  for PZ of Float_List'(0.0, 2.2) loop
                     Pole (Q (PX, 0.0, PZ), (if PZ = 0.0 then 2.4 else 2.9));
                  end loop;
               end loop;
               --  the awning, sloping down towards the aisle
               Meshes.Quad_UV (Q (-1.6, 2.35, -0.3), Q (1.6, 2.35, -0.3), Q (1.6, 2.95, 2.3), Q (-1.6, 2.95, 2.3),
                               Normalize ((-1.0) * V + Vec3'(0.0, 4.0, 0.0)), Mat_Awning,
                               Float (Natural (Float'Floor (Hash (T, 3.0) * 7.99))));
               --  the table and what is on it
               Box (O, U, V, -1.45, 1.45, 0.82, 0.88, 0.1, 1.1, Mat_Wood);
               for TX of Float_List'(-1.3, 1.3) loop
                  Box (O, U, V, TX - 0.04, TX + 0.04, 0.0, 0.82, 0.15, 1.05, Mat_Wood);
               end loop;
               case Kind is
                  when 0 | 1 =>   --  fruit and vegetables in crates
                     for CX in 0 .. 4 loop
                        for CZ in 0 .. 1 loop
                           declare
                              X0 : constant Float := -1.4 + 0.57 * Float (CX);
                              Z0 : constant Float := 0.15 + 0.48 * Float (CZ);
                           begin
                              Box (O, U, V, X0, X0 + 0.52, 0.88, 0.98, Z0, Z0 + 0.44, Mat_Wood);
                              Box (O, U, V, X0 + 0.04, X0 + 0.48, 0.98, 1.06, Z0 + 0.04, Z0 + 0.4,
                                   Wares (1 + (CX * 2 + CZ + K) mod 4));
                           end;
                        end loop;
                     end loop;
                  when 2 =>       --  fish on ice
                     Box (O, U, V, -1.4, 1.4, 0.88, 0.96, 0.15, 1.05, Mat_Ice);
                     for F in 0 .. 9 loop
                        declare
                           X0 : constant Float := -1.25 + 0.27 * Float (F);
                        begin
                           Box (O, U, V, X0, X0 + 0.11, 0.96, 1.0, 0.25, 0.85, Mat_Marble);
                        end;
                     end loop;
                  when 3 =>       --  cheeses
                     for F in 0 .. 5 loop
                        declare
                           X0 : constant Float := -1.3 + 0.45 * Float (F);
                        begin
                           Box (O, U, V, X0, X0 + 0.36, 0.88, 1.0 + 0.04 * Float (F mod 2), 0.3, 0.75, 48.0);
                        end;
                     end loop;
                  when others =>  --  flowers in buckets
                     for F in 0 .. 7 loop
                        declare
                           X0 : constant Float := -1.35 + 0.36 * Float (F);
                        begin
                           Box (O, U, V, X0, X0 + 0.26, 0.88, 1.1, 0.3, 0.6, Mat_Iron);
                           Box (O, U, V, X0 - 0.03, X0 + 0.29, 1.1, 1.35, 0.27, 0.63,
                                (if F mod 3 = 0 then 46.0 elsif F mod 3 = 1 then 55.0 else 40.0));
                        end;
                     end loop;
               end case;
               declare
                  M : constant Vec3 := Q (0.0, 0.0, 0.6);
               begin
                  S.Solids.Append ((M.X, M.Z, 1.6));
               end;
            end;
         end loop;
         T := T + 4.2;
         K := K + 1;
      end loop;
      Meshes.Finish (S.Mesh);
   end Build_Stalls;

   --  Green boxes on the lower side of the named streets: Mesh shut, Mesh2
   --  open with the lid up
   type Spot is record
      O, U, V : Vec3;
      Seed    : Float;
   end record;
   package Spot_Vectors is new Ada.Containers.Vectors (Positive, Spot);

   procedure One_Box (P : Spot; Open : Boolean) is
      O : Vec3 renames P.O;
      U : Vec3 renames P.U;
      V : Vec3 renames P.V;
      Up : constant Vec3 := (0.0, 1.0, 0.0);
      function Q (X, Y, Z : Float) return Vec3 is (O + X * U + Vec3'(0.0, Y, 0.0) + Z * V);
   begin
      for LX of Float_List'(-0.9, 0.9) loop
         Box (O, U, V, LX - 0.03, LX + 0.03, 0.0, 0.9, 0.3, 0.36, Mat_Iron);
      end loop;
      Box (O, U, V, -1.0, 1.0, 0.9, 1.45, 0.0, 0.7, Mat_Green);
      if Open then
         Meshes.Quad_UV (Q (-0.95, 1.46, 0.05), Q (0.95, 1.46, 0.05), Q (0.95, 1.46, 0.65), Q (-0.95, 1.46, 0.65),
                         Up, Mat_Books, P.Seed);
         Box (O, U, V, -1.0, 1.0, 1.45, 2.3, 0.68, 0.74, Mat_Green);
         Meshes.Quad_UV (Q (-0.9, 1.55, 0.67), Q (-0.02, 1.55, 0.67), Q (-0.02, 2.22, 0.67), Q (-0.9, 2.22, 0.67),
                         (-1.0) * V, Mat_Poster, P.Seed);
         Meshes.Quad_UV (Q (0.05, 1.55, 0.67), Q (0.9, 1.55, 0.67), Q (0.9, 2.22, 0.67), Q (0.05, 2.22, 0.67),
                         (-1.0) * V, Mat_Books, P.Seed + 1.0);
      else
         Box (O, U, V, -1.03, 1.03, 1.45, 1.52, -0.03, 0.73, Mat_Green);
      end if;
   end One_Box;

   Box_Spots : Spot_Vectors.Vector;

   --  Not on (or right by) any carriageway: side streets, the end of a
   --  bridge, a junction
   function Clear_Of_Roads (P : Vec3) return Boolean is
      Clear : Boolean := True;
      procedure Visit (AX, AZ, BX, BZ, Width : Float; Named : Boolean) is
         pragma Unreferenced (Named);
         EX : constant Float := BX - AX;
         EZ : constant Float := BZ - AZ;
         T  : constant Float := Float'Max (0.0, Float'Min (1.0,
           ((P.X - AX) * EX + (P.Z - AZ) * EZ) / Float'Max (0.0001, EX * EX + EZ * EZ)));
      begin
         if Sqrt ((AX + T * EX - P.X) ** 2 + (AZ + T * EZ - P.Z) ** 2) < Width / 2.0 + 1.6 then
            Clear := False;
         end if;
      end Visit;
      procedure Near is new Road_Network.For_Segments_Near (Visit);
   begin
      Near (P.X, P.Z, 20.0);
      return Clear;
   end Clear_Of_Roads;

   procedure Build_Boxes (S : in out Scene) is
      use Road_Network;
      Sum : Vec3 := (0.0, 0.0, 0.0);
   begin
      Box_Spots.Clear;
      if Ways /= null then
         for W in Ways'Range loop
            declare
               Name   : constant String := To_String (Ways (W).Name);
               Wanted : Boolean := False;
            begin
               for St of S.Streets loop
                  if To_String (St) = Name then
                     Wanted := True;
                  end if;
               end loop;
               if Wanted then
                  for Pos in 0 .. Ways (W).Count - 2 loop
                     declare
                        A  : constant Node := Point (W, Pos);
                        B  : constant Node := Point (W, Pos + 1);
                        L  : constant Float := Sqrt ((B.X - A.X) ** 2 + (B.Z - A.Z) ** 2);
                        D  : constant Vec3 := (if L > 0.01 then (1.0 / L) * Vec3'(B.X - A.X, 0.0, B.Z - A.Z)
                                              else Vec3'(1.0, 0.0, 0.0));
                        N  : constant Vec3 := (-D.Z, 0.0, D.X);
                        MX : constant Float := 0.5 * (A.X + B.X);
                        MZ : constant Float := 0.5 * (A.Z + B.Z);
                        H1 : constant Float := Terrain.Height (MX + 35.0 * N.X, MZ + 35.0 * N.Z);
                        H2 : constant Float := Terrain.Height (MX - 35.0 * N.X, MZ - 35.0 * N.Z);
                        Side : constant Float := (if H1 < H2 then 1.0 else -1.0);   --  the lower side
                        Off  : constant Float := Ways (W).Width / 2.0 + 3.1;
                        T    : Float := 2.0;
                        G    : Natural := 0;
                     begin
                        if L > 6.0 and then abs (H1 - H2) > 0.5 then
                           while T < L - 2.0 loop
                              if G mod 5 /= 4 then   --  a gap now and then
                                 declare
                                    R : constant Vec3 := Vec3'(A.X, 0.0, A.Z) + T * D;
                                    P : constant Vec3 := On_Ground (R + (Side * Off) * N);
                                 begin
                                    --  a quay has land on one side; a bridge has water on both
                                    if Float'Max (H1, H2) > -0.8 and then Clear_Of_Roads (P) then
                                       Box_Spots.Append ((P, D, Side * N, Float (Natural (Box_Spots.Length) mod 97) * 3.1));
                                       Sum := Sum + P;
                                    end if;
                                 end;
                              end if;
                              T := T + 2.3;
                              G := G + 1;
                           end loop;
                        end if;
                     end;
                  end loop;
               end if;
            end;
         end loop;
      end if;
      if Box_Spots.Is_Empty then
         return;
      end if;
      S.Centre := (1.0 / Float (Box_Spots.Length)) * Sum;
      S.Reach := 2500.0;
      for Open in Boolean loop
         Meshes.Start;
         for P of Box_Spots loop
            One_Box (P, Open);
         end loop;
         if Open then
            Meshes.Finish (S.Mesh2);
         else
            Meshes.Finish (S.Mesh);
         end if;
      end loop;
      for P of Box_Spots loop
         declare
            M : constant Vec3 := P.O + 0.35 * P.V;
         begin
            S.Solids.Append ((M.X, M.Z, 0.9));
         end;
      end loop;
   end Build_Boxes;

   --  Moving light over facades: a quad a little in front of each (facing
   --  the west), the seed picks the patterns
   procedure Build_Show (S : in out Scene) is
      Sum : Vec3 := (0.0, 0.0, 0.0);
      K   : Natural := 0;
   begin
      Meshes.Start;
      for I in S.Points.First_Index .. S.Points.Last_Index loop
         if To_String (S.Tags (I)) = "facade" then
            K := K + 1;
            declare
               A  : constant Vec3 := On_Ground (S.Points (I));
               B  : constant Vec3 := On_Ground (S.Points (I + 1));
               H  : constant Float := S.Heights (K).X;
               D  : constant Vec3 := Normalize (B - A);
               N0 : constant Vec3 := (-D.Z, 0.0, D.X);
               N  : constant Vec3 := (if N0.X > 0.0 then (-1.0) * N0 else N0);
               Y0 : constant Float := Float'Min (A.Y, B.Y) + 2.5;
               P0 : constant Vec3 := Vec3'(A.X, Y0, A.Z) + 0.8 * N;
               P1 : constant Vec3 := Vec3'(B.X, Y0, B.Z) + 0.8 * N;
            begin
               Meshes.Quad_UV (P0, P1, P1 + Vec3'(0.0, H, 0.0), P0 + Vec3'(0.0, H, 0.0), N, Mat_Show,
                               Float (K * 2));
               Sum := Sum + 0.5 * (A + B) + 35.0 * N;
            end;
         end if;
      end loop;
      Meshes.Finish (S.Mesh);
      if K > 0 then
         S.Centre := (1.0 / Float (K)) * Sum;
      end if;
      S.Reach := 300.0;
   end Build_Show;

   --  Glowing things: a ring, a field of columns, a sphere, screens
   procedure Build_Night (S : in out Scene) is
   begin
      S.Reach := 2500.0;
      Meshes.Start;
      for I in S.Points.First_Index .. S.Points.Last_Index loop
         declare
            T : constant String := To_String (S.Tags (I));
            C : constant Vec3 := On_Ground (S.Points (I));
         begin
            if T = "screens" then
               for K in 0 .. 3 loop
                  declare
                     O : constant Vec3 := C + Vec3'((if K mod 2 = 0 then -2.6 else 2.6), 0.0, -24.0 + 16.0 * Float (K));
                  begin
                     Pole (O + Vec3'(-2.6, 0.0, 0.0), 6.5);
                     Pole (O + Vec3'(2.6, 0.0, 0.0), 6.5);
                     Meshes.Quad_UV (O + Vec3'(-2.5, 2.5, 0.0), O + Vec3'(2.5, 2.5, 0.0),
                                     O + Vec3'(2.5, 6.3, 0.0), O + Vec3'(-2.5, 6.3, 0.0),
                                     (0.0, 0.0, 1.0), Mat_Show, 100.0 + Float (K) * 5.0);
                     Meshes.Quad_UV (O + Vec3'(2.5, 2.5, -0.02), O + Vec3'(-2.5, 2.5, -0.02),
                                     O + Vec3'(-2.5, 6.3, -0.02), O + Vec3'(2.5, 6.3, -0.02),
                                     (0.0, 0.0, -1.0), Mat_Show, 103.0 + Float (K) * 5.0);
                  end;
               end loop;
            end if;
         end;
      end loop;
      Meshes.Finish (S.Mesh);
      --  the ring, the columns and the sphere are drawn one by one, in
      --  changing colours (Draw)
      declare
         Sum : Vec3 := (0.0, 0.0, 0.0);
      begin
         for P of S.Points loop
            Sum := Sum + P;
         end loop;
         S.Centre := (1.0 / Float (Natural'Max (1, Natural (S.Points.Length)))) * Sum;
      end;
   end Build_Night;

   Ring_Mesh, Column_Mesh, Sphere_Mesh : Meshes.Mesh;
   Shapes_Built : Boolean := False;

   procedure Build_Shapes is
      Segs : constant := 40;
   begin
      --  a ring standing up, 6 m across the middle of its tube
      Meshes.Start;
      for I in 0 .. Segs - 1 loop
         for J in 0 .. 9 loop
            declare
               function P (A_I, B_J : Integer) return Vec3 is
                  A : constant Float := 2.0 * Pi * Float (A_I) / Float (Segs);
                  B : constant Float := 2.0 * Pi * Float (B_J) / 10.0;
                  R : constant Float := 6.0 + 0.45 * Cos (B);
               begin
                  return (R * Cos (A), 7.0 + R * Sin (A), 0.45 * Sin (B));
               end P;
               A : constant Float := 2.0 * Pi * (Float (I) + 0.5) / Float (Segs);
               Mid : constant Vec3 := (6.0 * Cos (A), 7.0 + 6.0 * Sin (A), 0.0);
            begin
               Face (P (I, J), P (I + 1, J), P (I + 1, J + 1), P (I, J + 1),
                     0.25 * (P (I, J) + P (I + 1, J) + P (I + 1, J + 1) + P (I, J + 1)) - Mid, Mat_Lamp);
            end;
         end loop;
      end loop;
      Meshes.Finish (Ring_Mesh);
      Meshes.Start;
      Meshes.Box (-0.14, 0.14, 0.0, 6.0, -0.14, 0.14, Mat_Lamp);
      Meshes.Finish (Column_Mesh);
      Meshes.Start;
      declare
         R : constant Float := 4.0;
         function P (I, J : Integer) return Vec3 is
            Phi : constant Float := 2.0 * Pi * Float (I) / 24.0;
            Th  : constant Float := Pi * Float (J) / 12.0;
         begin
            return (R * Sin (Th) * Cos (Phi), 5.5 - R * Cos (Th), R * Sin (Th) * Sin (Phi));
         end P;
      begin
         for J in 0 .. 11 loop
            for I in 0 .. 23 loop
               Face (P (I, J), P (I, J + 1), P (I + 1, J + 1), P (I + 1, J),
                     0.25 * (P (I, J) + P (I, J + 1) + P (I + 1, J + 1) + P (I + 1, J)) - Vec3'(0.0, 5.5, 0.0),
                     Mat_Lamp);
            end loop;
         end loop;
      end;
      Meshes.Finish (Sphere_Mesh);
      Shapes_Built := True;
   end Build_Shapes;

   --  A crowd along a line, and light on the face of the arch at its end
   procedure Build_Crowd (S : in out Scene) is
      A : constant Vec3 := On_Ground (S.Points (1));
      B : constant Vec3 := On_Ground (S.Points (2));
   begin
      S.Centre := 0.5 * (A + B);
      S.Reach := Length (B - A) / 2.0 + 60.0;
      Meshes.Start;
      if Arc_Top.Known then
         declare
            AX, AZ, BX, BZ, NX, NZ : Float;
         begin
            Arc_Top.Front (AX, AZ, BX, BZ, NX, NZ);
            declare
               Y0 : constant Float := Terrain.Height ((AX + BX) / 2.0, (AZ + BZ) / 2.0) + 1.0;
               H  : constant Float := Arc_Top.Roof_Y - Y0 - 0.5;
               P0 : constant Vec3 := (AX, Y0, AZ);
               P1 : constant Vec3 := (BX, Y0, BZ);
            begin
               Meshes.Quad_UV (P0, P1, P1 + Vec3'(0.0, H, 0.0), P0 + Vec3'(0.0, H, 0.0), (NX, 0.0, NZ),
                               Mat_Show, 1.0);
            end;
         end;
      end if;
      Meshes.Finish (S.Mesh);
   end Build_Crowd;

   procedure Build (S : in out Scene) is
   begin
      case S.Kind is
         when Huts   => Build_Huts (S);
         when Rink   => Build_Rink (S);
         when Stalls => Build_Stalls (S);
         when Boxes  => Build_Boxes (S);
         when Show   => Build_Show (S);
         when Glow =>
            if not Shapes_Built then
               Build_Shapes;
            end if;
            Build_Night (S);
         when Crowd_Kind => Build_Crowd (S);
         when Unknown => null;
      end case;
      S.Built := True;
   end Build;

   procedure Create is
   begin
      for I in All_Scenes.First_Index .. All_Scenes.Last_Index loop
         declare
            S : Scene := All_Scenes (I);
         begin
            Build (S);
            All_Scenes.Replace_Element (I, S);
         end;
      end loop;
   end Create;

   procedure Update (Dt, Hour, Rate : Float) is
   begin
      Clock := Clock + Dt;
      Hour_Now := Hour;
      Rate_Now := Rate;
      for I in All_Scenes.First_Index .. All_Scenes.Last_Index loop
         declare
            S : Scene := All_Scenes (I);
         begin
            Decide (S, Hour);
            All_Scenes.Replace_Element (I, S);
         end;
      end loop;
   end Update;

   function Crowd (X, Z : Float) return Float is
      Best : Float := 0.0;
   begin
      for S of All_Scenes loop
         if S.On then
            declare
               Level : constant Float :=
                 (case S.Kind is
                     when Huts => 0.45, when Rink => 0.35, when Stalls => 0.5,
                     when Show => 0.4, when Glow => 0.45, when Crowd_Kind => 0.9,
                     when others => 0.0);
               D : constant Float := Sqrt ((X - S.Centre.X) ** 2 + (Z - S.Centre.Z) ** 2);
            begin
               Best := Float'Max (Best, Level * Float'Max (0.0, 1.0 - D / S.Reach));
            end;
         end if;
      end loop;
      return Best;
   end Crowd;

   --  Seconds (real) to midnight, and since it
   function To_Midnight return Float is ((24.0 - Hour_Now) / Float'Max (Rate_Now, 1.0E-6));
   function Since_Midnight return Float is (Hour_Now / Float'Max (Rate_Now, 1.0E-6));

   function Counting (S : Scene) return Boolean is
     (S.Kind = Crowd_Kind and then S.On and then not S.Late and then To_Midnight <= 10.0);
   function Cheering (S : Scene) return Boolean is
     (S.Kind = Crowd_Kind and then S.On and then S.Late and then Since_Midnight < 90.0);

   function Banner return String is
   begin
      for S of All_Scenes loop
         if Counting (S) then
            return Ada.Strings.Fixed.Trim
              (Integer'Image (Integer'Max (1, Integer (Float'Ceiling (To_Midnight)))), Ada.Strings.Left);
         elsif Cheering (S) and then Since_Midnight < 8.0 then
            return To_String (S.Say);
         end if;
      end loop;
      return "";
   end Banner;

   function Hue (T : Float) return Vec3 is
     ((0.5 + 0.5 * Cos (2.0 * Pi * T), 0.5 + 0.5 * Cos (2.0 * Pi * (T - 0.333)),
       0.5 + 0.5 * Cos (2.0 * Pi * (T - 0.667))));

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint; Cam_X, Cam_Z : Float) is
      Cam : constant Vec3 := (Cam_X, 0.0, Cam_Z);

      function Near (P : Vec3; R : Float := 160.0) return Boolean is
        ((P.X - Cam.X) ** 2 + (P.Z - Cam.Z) ** 2 < R * R);

      procedure Person (P : Vec3; Face : Float; K : Natural; Stride : Float := 0.0;
                        Arm : Float := 0.0) is
      begin
         if Near (P) then
            Figures.Person
              (Translation (On_Ground (P)) * Rotation_Y (-Face),
               Coats (K mod 8), Skins ((K * 3) mod 4), (0.14, 0.14, 0.17),
               Stride => Stride,
               Hat => (if K mod 5 = 1 then Figures.Cap else Figures.None),
               Hat_Colour => (0.6, 0.1, 0.1), Arm_Up => Arm);
         end if;
      end Person;

      --  facing along a direction in the ground plane
      function Facing (D : Vec3) return Float is (Arctan (D.X, -D.Z));

      procedure People (S : Scene) is
      begin
         Figures.Set_Locations ((Model, Paint, Skin, Legs));
         case S.Kind is
            when Huts =>
               for K in 0 .. 27 loop
                  declare
                     Dir   : constant Float := (if K mod 2 = 0 then 1.0 else -1.0);
                     Still : constant Boolean := K mod 4 = 3;
                     R     : constant Float := (if Still then Ring_R - 0.95 else 6.5 + 2.8 * Float (K mod 3));
                     A     : constant Float :=
                       (if Still then 2.0 * Pi * Float (K / 4 mod Ring_Huts) / Float (Ring_Huts) + Pi / 2.0 + 0.2
                        else 2.0 * Pi * Float (K) / 28.0 + Dir * (0.07 + 0.012 * Float (K mod 5)) * Clock);
                     Out_V : constant Vec3 := (Cos (A), 0.0, Sin (A));
                     Tang  : constant Vec3 := Dir * Vec3'(-Sin (A), 0.0, Cos (A));
                  begin
                     Person (S.Centre + R * Out_V, Facing (if Still then Out_V else Tang), K,
                             Stride => (if Still then 0.0 else 0.35 * Sin (Clock * 4.5 + Float (K))),
                             Arm => (if K mod 3 = 0 then -1.2 else 0.0));
                  end;
               end loop;
            when Rink =>
               declare
                  U : constant Vec3 := Rink_Axis (S);
                  V : constant Vec3 := (-U.Z, 0.0, U.X);
               begin
                  for K in 0 .. 21 loop
                     declare
                        Lane : constant Float := 0.55 + 0.35 * Float (K mod 3) / 2.0;
                        A    : constant Float := 2.0 * Pi * Float (K) / 22.0 + (0.12 + 0.02 * Float (K mod 4)) * Clock;
                        P    : constant Vec3 := S.Centre + (R_Long * 0.82 * Lane * Cos (A)) * U
                                                + (R_Wide * 0.8 * Lane * Sin (A)) * V + Vec3'(0.0, 0.08, 0.0);
                        T    : constant Vec3 := (-R_Long * Sin (A)) * U + (R_Wide * Cos (A)) * V;
                     begin
                        if Near (P) then
                           Figures.Person
                             (Translation (P) * Rotation_Y (-Facing (T)) * Rotation_Z (-0.12),
                              Coats (K mod 8), Skins ((K * 3) mod 4), (0.1, 0.1, 0.14),
                              Stride => 0.45 * Sin (Clock * 2.2 + Float (K)),
                              Hat => (if K mod 3 = 0 then Figures.Cap else Figures.None),
                              Hat_Colour => Coats ((K + 3) mod 8),
                              Arm_Up => (if K mod 4 = 0 then -0.7 else 0.0));
                        end if;
                     end;
                  end loop;
                  for K in 0 .. 9 loop
                     Person (S.Centre + (-R_Long + 3.4 * Float (K) + 1.0) * U - (R_Wide + 0.9) * V,
                             Facing (V), K + 3);
                  end loop;
               end;
            when Stalls =>
               declare
                  A : constant Vec3 := S.Points (1);
                  B : constant Vec3 := S.Points (2);
                  L : constant Float := Length (B - A);
                  D : constant Vec3 := Normalize (B - A);
                  N : constant Vec3 := (-D.Z, 0.0, D.X);
                  T : Float := 3.0;
                  K : Natural := 0;
               begin
                  while T < L - 3.0 loop
                     for Side of Float_List'(-1.0, 1.0) loop
                        if (K + (if Side > 0.0 then 1 else 0)) mod 2 = 0 then   --  the stallholder
                           Person (A + T * D + (Side * 4.0) * N, Facing ((-Side) * N), K * 3 + 1);
                        end if;
                     end loop;
                     T := T + 4.2;
                     K := K + 1;
                  end loop;
                  for K2 in 0 .. 59 loop   --  shoppers up and down the aisle
                     declare
                        Dir  : constant Float := (if K2 mod 2 = 0 then 1.0 else -1.0);
                        U0   : constant Float := L * Float (K2) / 60.0;
                        Pos  : constant Float := U0 + Dir * 0.9 * Clock;
                        W    : constant Float := Pos - L * Float'Floor (Pos / L);
                        Stop : constant Boolean := K2 mod 5 = 2;
                     begin
                        Person (A + (if Stop then U0 else W) * D + (0.9 * Float (K2 mod 3 - 1)) * N,
                                (if Stop then Facing (Dir * N) else Facing (Dir * D)),
                                K2 + 2,
                                Stride => (if Stop then 0.0 else 0.35 * Sin (Clock * 4.5 + Float (K2))));
                     end;
                  end loop;
               end;
            when Boxes =>
               if Hour_Now >= S.Open0 and then Hour_Now < S.Open1 then
                  for I in Box_Spots.First_Index .. Box_Spots.Last_Index loop
                     declare
                        P : Spot renames Box_Spots (I);
                     begin
                        if I mod 8 = 3 then
                           Person (P.O - 0.9 * P.V + 1.3 * P.U, Facing ((-1.0) * P.V), I);
                        elsif I mod 11 = 5 then   --  someone browsing
                           Person (P.O - 0.7 * P.V, Facing (P.V), I + 1);
                        end if;
                     end;
                  end loop;
               end if;
            when Show =>
               for K in 0 .. 39 loop
                  Person (S.Centre + Vec3'(-14.0 + 28.0 * Hash (Float (K), 1.0), 0.0,
                                           -10.0 + 20.0 * Hash (Float (K), 2.0)),
                          Facing (Vec3'(1.0, 0.0, 0.0)) + 0.4 * (Hash (Float (K), 3.0) - 0.5), K,
                          Arm => (if K mod 6 = 0 then -2.2 else 0.0));   --  a phone held up
               end loop;
            when Glow =>
               for P0 of S.Points loop
                  for K in 0 .. 13 loop
                     declare
                        A : constant Float := 2.0 * Pi * Float (K) / 14.0
                          + 0.05 * Clock * (if K mod 2 = 0 then 1.0 else -1.0);
                        R : constant Float := 9.0 + 3.0 * Hash (Float (K), P0.X);
                        P : constant Vec3 := P0 + R * Vec3'(Cos (A), 0.0, Sin (A));
                     begin
                        Person (P, Facing (P0 - P), K + 3,
                                Arm => (if K mod 5 = 0 then -2.2 else 0.0));
                     end;
                  end loop;
               end loop;
            when Crowd_Kind =>
               declare
                  A : constant Vec3 := S.Points (1);
                  B : constant Vec3 := S.Points (2);
                  L : constant Float := Length (B - A);
                  D : constant Vec3 := Normalize (B - A);
                  N : constant Vec3 := (-D.Z, 0.0, D.X);
                  Wave : constant Boolean := Counting (S) or else Cheering (S);
               begin
                  for K in 0 .. 239 loop
                     declare
                        T : constant Float := 25.0 + (L - 25.0) * Hash (Float (K), 7.0) ** 1.6;
                        X : constant Float := -30.0 + 60.0 * Hash (Float (K), 8.0);
                     begin
                        Person (A + T * D + X * N, Facing ((-1.0) * D) + 0.5 * (Hash (Float (K), 9.0) - 0.5), K,
                                Arm => (if Wave and then K mod 2 = 0
                                        then -2.4 + 0.5 * Sin (Clock * 8.0 + Float (K)) else 0.0));
                     end;
                  end loop;
               end;
            when Unknown =>
               null;
         end case;
      end People;
   begin
      for S of All_Scenes loop
         if S.On and then S.Built
           and then (S.Centre.X - Cam_X) ** 2 + (S.Centre.Z - Cam_Z) ** 2 < (S.Reach + 500.0) ** 2
         then
            Shaders.Set (Model, Identity);
            if S.Kind = Boxes and then Hour_Now >= S.Open0 and then Hour_Now < S.Open1 then
               Meshes.Draw (S.Mesh2);
            else
               Meshes.Draw (S.Mesh);
            end if;
            if S.Kind = Glow and then Shapes_Built then
               for I in S.Points.First_Index .. S.Points.Last_Index loop
                  declare
                     T : constant String := To_String (S.Tags (I));
                     C : constant Vec3 := On_Ground (S.Points (I));
                  begin
                     if T = "ring" then
                        Shaders.Set (Skin, Hue (0.05 * Clock));
                        Shaders.Set (Model, Translation (C) * Rotation_Y (0.2 * Clock));
                        Meshes.Draw (Ring_Mesh);
                     elsif T = "sphere" then
                        Shaders.Set (Skin, (0.9 + 0.1 * Sin (Clock * 0.7)) * Vec3'(1.0, 0.95, 0.82));
                        Shaders.Set (Model, Translation (C));
                        Meshes.Draw (Sphere_Mesh);
                     elsif T = "columns" then
                        for GX in -3 .. 3 loop
                           for GZ in -3 .. 3 loop
                              Shaders.Set (Skin, Hue (0.1 * Clock + 0.06 * Float (GX + GZ)));
                              Shaders.Set (Model, Translation (On_Ground (C + Vec3'(3.2 * Float (GX), 0.0, 3.2 * Float (GZ))))
                                                  * Translation ((0.0, 2.0 + 2.0 * Sin (Clock + 0.5 * Float (GX * GZ)), 0.0)));
                              Meshes.Draw (Column_Mesh);
                           end loop;
                        end loop;
                     end if;
                  end;
               end loop;
            end if;
            People (S);
         end if;
      end loop;
   end Draw;

   procedure Collide (S : in out Car.State) is
      F : constant Vec3 := Car.Forward (S);
   begin
      for Sc of All_Scenes loop
         if Sc.On and then (Sc.Centre.X - S.X) ** 2 + (Sc.Centre.Z - S.Z) ** 2 < (Sc.Reach + 20.0) ** 2 then
            for O of Sc.Solids loop
               declare
                  EX : constant Float := S.X - O.X;
                  EZ : constant Float := S.Z - O.Z;
                  D  : constant Float := Sqrt (EX * EX + EZ * EZ);
                  R  : constant Float := O.R + 1.2;
               begin
                  if D < R and then D > 0.001 then
                     S.X := S.X + EX / D * (R - D);
                     S.Z := S.Z + EZ / D * (R - D);
                     if (F.X * EX + F.Z * EZ) * S.Speed < 0.0 then
                        S.Speed := S.Speed * 0.4;
                     end if;
                     S.Bumped := True;
                     S.Hit_NX := EX / D;
                     S.Hit_NZ := EZ / D;
                  end if;
               end;
            end loop;
         end if;
      end loop;
   end Collide;

end Scenes;
