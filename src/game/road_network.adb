with Ada.Directories;
with Ada.Numerics.Elementary_Functions;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Interfaces;

package body Road_Network is

   use Ada.Numerics.Elementary_Functions;

   type Real_Array is array (Natural range <>) of Float;
   type Real_Array_Access is access Real_Array;

   Cumulative : Real_Array_Access;   --  running total of way lengths

   procedure Load (File_Name : String) is
      use Ada.Streams.Stream_IO;
      use Interfaces;
      F     : File_Type;
      S     : Stream_Access;
      Magic : String (1 .. 4);
      N     : Integer_32;
   begin
      if not Ada.Directories.Exists (File_Name) then
         Ada.Text_IO.Put_Line ("No road network (" & File_Name & "): no traffic");
         return;
      end if;
      Open (F, In_File, File_Name);
      S := Stream (F);
      String'Read (S, Magic);
      if Magic /= "PRD3" then
         Ada.Text_IO.Put_Line (File_Name & ": old format, run make tiles");
         Close (F);
         return;
      end if;
      Integer_32'Read (S, N);
      Nodes := new Node_Array (0 .. Integer (N) - 1);
      for P of Nodes.all loop
         Float'Read (S, P.X);
         Float'Read (S, P.Z);
         Float'Read (S, P.Signal);
      end loop;
      Integer_32'Read (S, N);
      Ways := new Way_Array (0 .. Integer (N) - 1);

      declare
         package Int_Vectors is new Ada.Containers.Vectors (Natural, Natural);
         All_Nodes : Int_Vectors.Vector;
         V         : Integer_32;
         Width     : Float;
         One, Ln, Cnt : Integer_32;
      begin
         for W of Ways.all loop
            Integer_32'Read (S, One);
            Integer_32'Read (S, Ln);
            Float'Read (S, Width);
            Integer_32'Read (S, Cnt);
            W := (Oneway => Integer (One), Lanes => Positive'Max (1, Integer (Ln)),
                  Width => Width, First => Natural (All_Nodes.Length),
                  Count => Natural (Cnt), Name => <>);
            for K in 1 .. Cnt loop
               Integer_32'Read (S, V);
               All_Nodes.Append (Natural (V));
            end loop;
            Integer_32'Read (S, V);
            declare
               Name : String (1 .. Natural (V));
            begin
               String'Read (S, Name);
               W.Name := Ada.Strings.Unbounded.To_Unbounded_String (Name);
            end;
         end loop;
         Way_Nodes := new Int_Array (0 .. Natural (All_Nodes.Length) - 1);
         for I in Way_Nodes'Range loop
            Way_Nodes (I) := All_Nodes (I);
         end loop;
      end;
      Close (F);

      Links := new Link_Table (Nodes'Range);
      Walk_Links := new Link_Table (Nodes'Range);
      for W in Ways'Range loop
         for Pos in 0 .. Ways (W).Count - 1 loop
            if Pos + 1 < Ways (W).Count then
               Walk_Links (Node_Index (W, Pos)).Append ((W, Pos, 1));
               if Ways (W).Oneway >= 0 then
                  Links (Node_Index (W, Pos)).Append ((W, Pos, 1));
               end if;
            end if;
            if Pos > 0 then
               Walk_Links (Node_Index (W, Pos)).Append ((W, Pos, -1));
               if Ways (W).Oneway <= 0 then
                  Links (Node_Index (W, Pos)).Append ((W, Pos, -1));
               end if;
            end if;
         end loop;
      end loop;

      Cumulative := new Real_Array (Ways'Range);
      declare
         Sum : Float := 0.0;
      begin
         for W in Ways'Range loop
            for Pos in 0 .. Ways (W).Count - 2 loop
               declare
                  A : constant Node := Point (W, Pos);
                  B : constant Node := Point (W, Pos + 1);
               begin
                  Sum := Sum + Sqrt ((B.X - A.X) ** 2 + (B.Z - A.Z) ** 2)
                    * (if Ways (W).Width >= 9.0 then 2.0 else 1.0);
               end;
            end loop;
            Cumulative (W) := Sum;
         end loop;
      end;
      Ada.Text_IO.Put_Line ("Road network:" & Nodes'Length'Image & " nodes,"
                            & Ways'Length'Image & " ways");
   end Load;

   procedure Segment (L : Link; A, B : out Node; Len : out Float) is
   begin
      A := Point (L.W, L.Pos);
      B := Point (L.W, L.Pos + L.Dir);
      Len := Sqrt ((B.X - A.X) ** 2 + (B.Z - A.Z) ** 2);
   end Segment;

   function Direction (L : Link) return Math3D.Vec3 is
      A, B : Node;
      Len  : Float;
   begin
      Segment (L, A, B, Len);
      if Len < 0.001 then
         return (0.0, 0.0, -1.0);
      end if;
      return ((B.X - A.X) / Len, 0.0, (B.Z - A.Z) / Len);
   end Direction;

   function Pick_Way (R : Float) return Natural is
      Target : constant Float := R * Cumulative (Cumulative'Last);
      Lo     : Natural := Cumulative'First;
      Hi     : Natural := Cumulative'Last;
   begin
      while Lo < Hi loop
         declare
            Mid : constant Natural := (Lo + Hi) / 2;
         begin
            if Cumulative (Mid) < Target then
               Lo := Mid + 1;
            else
               Hi := Mid;
            end if;
         end;
      end loop;
      return Lo;
   end Pick_Way;

   procedure Nearest_Road
     (X, Z : Float; Found : out Boolean; PX, PZ, Heading : out Float)
   is
      Best : Float := Float'Last;
   begin
      Found := False;
      PX := X;
      PZ := Z;
      Heading := 0.0;
      if not Loaded then
         return;
      end if;
      for W in Ways'Range loop
         for Pos in 0 .. Ways (W).Count - 2 loop
            declare
               A  : constant Node := Point (W, Pos);
               B  : constant Node := Point (W, Pos + 1);
               EX : constant Float := B.X - A.X;
               EZ : constant Float := B.Z - A.Z;
               L2 : constant Float := EX * EX + EZ * EZ;
               T  : Float := 0.0;
               QX, QZ, D : Float;
            begin
               if L2 > 1.0E-6 then
                  T := Float'Max (0.0, Float'Min (1.0, ((X - A.X) * EX + (Z - A.Z) * EZ) / L2));
                  QX := A.X + T * EX;
                  QZ := A.Z + T * EZ;
                  D := (QX - X) ** 2 + (QZ - Z) ** 2;
                  if D < Best then
                     Best := D;
                     Found := True;
                     PX := QX;
                     PZ := QZ;
                     Heading := (if Ways (W).Oneway < 0 then Arctan (-EX, EZ)
                                 else Arctan (EX, -EZ));
                  end if;
               end if;
            end;
         end loop;
      end loop;
   end Nearest_Road;

   function Street_At (X, Z : Float; Max_Distance : Float := 14.0) return String is
      Best : Float := Max_Distance * Max_Distance;
      Way_Found : Integer := -1;
   begin
      if not Loaded then
         return "";
      end if;
      for W in Ways'Range loop
         if Ada.Strings.Unbounded.Length (Ways (W).Name) > 0 then
            for Pos in 0 .. Ways (W).Count - 2 loop
               declare
                  A  : constant Node := Point (W, Pos);
                  B  : constant Node := Point (W, Pos + 1);
                  EX : constant Float := B.X - A.X;
                  EZ : constant Float := B.Z - A.Z;
                  L2 : constant Float := EX * EX + EZ * EZ;
                  T  : Float := 0.0;
                  D  : Float;
               begin
                  if abs (A.X - X) < 400.0 and then abs (A.Z - Z) < 400.0 then
                     if L2 > 1.0E-6 then
                        T := Float'Max (0.0, Float'Min
                               (1.0, ((X - A.X) * EX + (Z - A.Z) * EZ) / L2));
                     end if;
                     D := (A.X + T * EX - X) ** 2 + (A.Z + T * EZ - Z) ** 2;
                     if D < Best then
                        Best := D;
                        Way_Found := W;
                     end if;
                  end if;
               end;
            end loop;
         end if;
      end loop;
      return (if Way_Found < 0 then ""
              else Ada.Strings.Unbounded.To_String (Ways (Way_Found).Name));
   end Street_At;

   function Signal_State (Offset, Dir_X, Dir_Z, Time : Float) return Light is
      Phase : constant Float :=
        Time + Offset - Signal_Cycle * Float'Floor ((Time + Offset) / Signal_Cycle);
   begin
      if abs Dir_X >= abs Dir_Z then          --  east-west movement
         return (if Phase < 13.0 then Green elsif Phase < 16.0 then Amber else Red);
      else                                    --  north-south movement
         return (if Phase < 16.0 then Red elsif Phase < 29.0 then Green else Amber);
      end if;
   end Signal_State;

end Road_Network;
