with Ada.Containers.Generic_Array_Sort;

package body Earcut is

   Null_Node : constant := 0;

   type Node_Rec is record
      I       : Natural;
      X, Y    : Long_Float;
      Prev    : Natural := Null_Node;
      Next    : Natural := Null_Node;
      Steiner : Boolean := False;
   end record;

   package Node_Vectors is new Ada.Containers.Vectors (Positive, Node_Rec);

   procedure Triangulate
     (Coords      : Point_Array;
      Hole_Starts : Natural_Array;
      Triangles   : out Index_Vectors.Vector)
   is
      Pool : Node_Vectors.Vector;

      function X (N : Positive) return Long_Float is (Pool (N).X);
      function Y (N : Positive) return Long_Float is (Pool (N).Y);
      function Nx (N : Positive) return Positive is (Pool (N).Next);
      function Pv (N : Positive) return Positive is (Pool (N).Prev);

      procedure Set_Next (N, V : Positive) is
      begin
         Pool (N).Next := V;
      end Set_Next;

      procedure Set_Prev (N, V : Positive) is
      begin
         Pool (N).Prev := V;
      end Set_Prev;

      function Area (P, Q, R : Positive) return Long_Float is
        ((Y (Q) - Y (P)) * (X (R) - X (Q)) - (X (Q) - X (P)) * (Y (R) - Y (Q)));

      function Equals (A, B : Positive) return Boolean is
        (X (A) = X (B) and then Y (A) = Y (B));

      function Insert_Node
        (I : Natural; Px, Py : Long_Float; Last : Natural) return Positive
      is
         P : Positive;
      begin
         Pool.Append ((I => I, X => Px, Y => Py, others => <>));
         P := Pool.Last_Index;
         if Last = Null_Node then
            Set_Prev (P, P);
            Set_Next (P, P);
         else
            Set_Next (P, Nx (Last));
            Set_Prev (P, Last);
            Set_Prev (Nx (Last), P);
            Set_Next (Last, P);
         end if;
         return P;
      end Insert_Node;

      procedure Remove_Node (P : Positive) is
      begin
         Set_Prev (Nx (P), Pv (P));
         Set_Next (Pv (P), Nx (P));
      end Remove_Node;

      function Signed_Area (From, To : Natural) return Long_Float is
         Sum : Long_Float := 0.0;
         J   : Natural := To;
      begin
         for I in From .. To loop
            Sum := Sum + (Coords (J).X - Coords (I).X)
                       * (Coords (I).Y + Coords (J).Y);
            J := I;
         end loop;
         return Sum;
      end Signed_Area;

      function Linked_List
        (From, To : Natural; Clockwise : Boolean) return Natural
      is
         Last : Natural := Null_Node;
      begin
         if Clockwise = (Signed_Area (From, To) > 0.0) then
            for I in From .. To loop
               Last := Insert_Node (I, Coords (I).X, Coords (I).Y, Last);
            end loop;
         else
            for I in reverse From .. To loop
               Last := Insert_Node (I, Coords (I).X, Coords (I).Y, Last);
            end loop;
         end if;
         if Last /= Null_Node and then Equals (Last, Nx (Last)) then
            Remove_Node (Last);
            Last := Nx (Last);
         end if;
         return Last;
      end Linked_List;

      function Filter_Points (Start : Natural; Stop : Natural := Null_Node)
        return Natural
      is
         P, E  : Natural;
         Again : Boolean;
      begin
         if Start = Null_Node then
            return Start;
         end if;
         E := (if Stop = Null_Node then Start else Stop);
         P := Start;
         loop
            Again := False;
            if not Pool (P).Steiner
              and then (Equals (P, Nx (P)) or else Area (Pv (P), P, Nx (P)) = 0.0)
            then
               Remove_Node (P);
               P := Pv (P);
               E := P;
               exit when P = Nx (P);
               Again := True;
            else
               P := Nx (P);
            end if;
            exit when not Again and then P = E;
         end loop;
         return E;
      end Filter_Points;

      function Point_In_Triangle
        (Ax, Ay, Bx, By, Cx, Cy, Px, Py : Long_Float) return Boolean is
        ((Cx - Px) * (Ay - Py) >= (Ax - Px) * (Cy - Py)
         and then (Ax - Px) * (By - Py) >= (Bx - Px) * (Ay - Py)
         and then (Bx - Px) * (Cy - Py) >= (Cx - Px) * (By - Py));

      function Is_Ear (Ear : Positive) return Boolean is
         A : constant Positive := Pv (Ear);
         B : constant Positive := Ear;
         C : constant Positive := Nx (Ear);
         P : Positive;
         X0, X1, Y0, Y1 : Long_Float;
      begin
         if Area (A, B, C) >= 0.0 then
            return False;
         end if;
         X0 := Long_Float'Min (X (A), Long_Float'Min (X (B), X (C)));
         X1 := Long_Float'Max (X (A), Long_Float'Max (X (B), X (C)));
         Y0 := Long_Float'Min (Y (A), Long_Float'Min (Y (B), Y (C)));
         Y1 := Long_Float'Max (Y (A), Long_Float'Max (Y (B), Y (C)));
         P := Nx (C);
         while P /= A loop
            if X (P) >= X0 and then X (P) <= X1
              and then Y (P) >= Y0 and then Y (P) <= Y1
              and then Point_In_Triangle
                (X (A), Y (A), X (B), Y (B), X (C), Y (C), X (P), Y (P))
              and then Area (Pv (P), P, Nx (P)) >= 0.0
            then
               return False;
            end if;
            P := Nx (P);
         end loop;
         return True;
      end Is_Ear;

      function Sign (V : Long_Float) return Integer is
        (if V > 0.0 then 1 elsif V < 0.0 then -1 else 0);

      function On_Segment (P, Q, R : Positive) return Boolean is
        (X (Q) <= Long_Float'Max (X (P), X (R))
         and then X (Q) >= Long_Float'Min (X (P), X (R))
         and then Y (Q) <= Long_Float'Max (Y (P), Y (R))
         and then Y (Q) >= Long_Float'Min (Y (P), Y (R)));

      function Intersects (P1, Q1, P2, Q2 : Positive) return Boolean is
         O1 : constant Integer := Sign (Area (P1, Q1, P2));
         O2 : constant Integer := Sign (Area (P1, Q1, Q2));
         O3 : constant Integer := Sign (Area (P2, Q2, P1));
         O4 : constant Integer := Sign (Area (P2, Q2, Q1));
      begin
         return (O1 /= O2 and then O3 /= O4)
           or else (O1 = 0 and then On_Segment (P1, P2, Q1))
           or else (O2 = 0 and then On_Segment (P1, Q2, Q1))
           or else (O3 = 0 and then On_Segment (P2, P1, Q2))
           or else (O4 = 0 and then On_Segment (P2, Q1, Q2));
      end Intersects;

      function Locally_Inside (A, B : Positive) return Boolean is
        (if Area (Pv (A), A, Nx (A)) < 0.0 then
            Area (A, B, Nx (A)) >= 0.0 and then Area (A, Pv (A), B) >= 0.0
         else
            Area (A, B, Pv (A)) < 0.0 or else Area (A, Nx (A), B) < 0.0);

      function Intersects_Polygon (A, B : Positive) return Boolean is
         P : Positive := A;
      begin
         loop
            if Pool (P).I /= Pool (A).I and then Pool (Nx (P)).I /= Pool (A).I
              and then Pool (P).I /= Pool (B).I
              and then Pool (Nx (P)).I /= Pool (B).I
              and then Intersects (P, Nx (P), A, B)
            then
               return True;
            end if;
            P := Nx (P);
            exit when P = A;
         end loop;
         return False;
      end Intersects_Polygon;

      function Middle_Inside (A, B : Positive) return Boolean is
         P      : Positive := A;
         Inside : Boolean := False;
         Px     : constant Long_Float := (X (A) + X (B)) / 2.0;
         Py     : constant Long_Float := (Y (A) + Y (B)) / 2.0;
      begin
         loop
            if (Y (P) > Py) /= (Y (Nx (P)) > Py)
              and then Y (Nx (P)) /= Y (P)
              and then Px < (X (Nx (P)) - X (P)) * (Py - Y (P))
                            / (Y (Nx (P)) - Y (P)) + X (P)
            then
               Inside := not Inside;
            end if;
            P := Nx (P);
            exit when P = A;
         end loop;
         return Inside;
      end Middle_Inside;

      function Is_Valid_Diagonal (A, B : Positive) return Boolean is
        (Pool (Nx (A)).I /= Pool (B).I and then Pool (Pv (A)).I /= Pool (B).I
         and then not Intersects_Polygon (A, B)
         and then
           ((Locally_Inside (A, B) and then Locally_Inside (B, A)
             and then Middle_Inside (A, B)
             and then (Area (Pv (A), A, Pv (B)) /= 0.0
                       or else Area (A, Pv (B), B) /= 0.0))
            or else (Equals (A, B) and then Area (Pv (A), A, Nx (A)) > 0.0
                     and then Area (Pv (B), B, Nx (B)) > 0.0)));

      function Split_Polygon (A, B : Positive) return Positive is
         A2, B2 : Positive;
         An     : constant Positive := Nx (A);
         Bp     : constant Positive := Pv (B);
         Copy_A : constant Node_Rec := Pool (A);
         Copy_B : constant Node_Rec := Pool (B);
      begin
         Pool.Append ((I => Copy_A.I, X => Copy_A.X, Y => Copy_A.Y, others => <>));
         A2 := Pool.Last_Index;
         Pool.Append ((I => Copy_B.I, X => Copy_B.X, Y => Copy_B.Y, others => <>));
         B2 := Pool.Last_Index;
         Set_Next (A, B);
         Set_Prev (B, A);
         Set_Next (A2, An);
         Set_Prev (An, A2);
         Set_Next (B2, A2);
         Set_Prev (A2, B2);
         Set_Next (Bp, B2);
         Set_Prev (B2, Bp);
         return B2;
      end Split_Polygon;

      procedure Emit (A, B, C : Positive) is
      begin
         Triangles.Append (Pool (A).I);
         Triangles.Append (Pool (B).I);
         Triangles.Append (Pool (C).I);
      end Emit;

      function Cure_Local_Intersections (Start_In : Positive) return Natural
      is
         Start : Positive := Start_In;
         P     : Positive := Start;
         A, B  : Positive;
      begin
         loop
            A := Pv (P);
            B := Nx (Nx (P));
            if not Equals (A, B) and then Intersects (A, P, Nx (P), B)
              and then Locally_Inside (A, B) and then Locally_Inside (B, A)
            then
               Emit (A, P, B);
               Remove_Node (P);
               Remove_Node (Nx (P));
               P := B;
               Start := B;
            end if;
            P := Nx (P);
            exit when P = Start;
         end loop;
         return Filter_Points (P);
      end Cure_Local_Intersections;

      procedure Earcut_Linked (Ear_In : Natural; Pass : Natural);

      procedure Split_Earcut (Start : Positive) is
         A : Positive := Start;
         B, C : Positive;
         Fa, Fc : Natural;
      begin
         loop
            B := Nx (Nx (A));
            while B /= Pv (A) loop
               if Pool (A).I /= Pool (B).I and then Is_Valid_Diagonal (A, B)
               then
                  C := Split_Polygon (A, B);
                  Fa := Filter_Points (A, Nx (A));
                  Fc := Filter_Points (C, Nx (C));
                  Earcut_Linked (Fa, 0);
                  Earcut_Linked (Fc, 0);
                  return;
               end if;
               B := Nx (B);
            end loop;
            A := Nx (A);
            exit when A = Start;
         end loop;
      end Split_Earcut;

      procedure Earcut_Linked (Ear_In : Natural; Pass : Natural) is
         Ear        : Natural := Ear_In;
         Stop       : Natural;
         Prev, Next : Positive;
      begin
         if Ear = Null_Node then
            return;
         end if;
         Stop := Ear;
         while Pv (Ear) /= Nx (Ear) loop
            Prev := Pv (Ear);
            Next := Nx (Ear);
            if Is_Ear (Ear) then
               Emit (Prev, Ear, Next);
               Remove_Node (Ear);
               Ear := Nx (Next);
               Stop := Nx (Next);
            else
               Ear := Next;
               if Ear = Stop then
                  case Pass is
                     when 0 =>
                        Earcut_Linked (Filter_Points (Ear), 1);
                     when 1 =>
                        Ear := Cure_Local_Intersections (Filter_Points (Ear));
                        Earcut_Linked (Ear, 2);
                     when others =>
                        Split_Earcut (Ear);
                  end case;
                  exit;
               end if;
            end if;
         end loop;
      end Earcut_Linked;

      function Get_Leftmost (Start : Positive) return Positive is
         P        : Positive := Start;
         Leftmost : Positive := Start;
      begin
         loop
            if X (P) < X (Leftmost)
              or else (X (P) = X (Leftmost) and then Y (P) < Y (Leftmost))
            then
               Leftmost := P;
            end if;
            P := Nx (P);
            exit when P = Start;
         end loop;
         return Leftmost;
      end Get_Leftmost;

      function Sector_Contains_Sector (M, P : Positive) return Boolean is
        (Area (Pv (M), M, Pv (P)) < 0.0 and then Area (Nx (P), M, Nx (M)) < 0.0);

      function Find_Hole_Bridge (Hole, Outer_Node : Positive) return Natural is
         P       : Positive := Outer_Node;
         Hx      : constant Long_Float := X (Hole);
         Hy      : constant Long_Float := Y (Hole);
         Qx      : Long_Float := Long_Float'First;
         M       : Natural := Null_Node;
         Stop    : Positive;
         Mx, My  : Long_Float;
         Tan_Min : Long_Float := Long_Float'Last;
         Tan, Ix : Long_Float;
      begin
         loop
            if Hy <= Y (P) and then Hy >= Y (Nx (P)) and then Y (Nx (P)) /= Y (P)
            then
               Ix := X (P) + (Hy - Y (P)) * (X (Nx (P)) - X (P))
                             / (Y (Nx (P)) - Y (P));
               if Ix <= Hx and then Ix > Qx then
                  Qx := Ix;
                  M := (if X (P) < X (Nx (P)) then P else Nx (P));
                  if Ix = Hx then
                     return M;
                  end if;
               end if;
            end if;
            P := Nx (P);
            exit when P = Outer_Node;
         end loop;

         if M = Null_Node then
            return Null_Node;
         end if;

         Stop := M;
         Mx := X (M);
         My := Y (M);
         P := M;
         loop
            if Hx >= X (P) and then X (P) >= Mx and then Hx /= X (P)
              and then Point_In_Triangle
                ((if Hy < My then Hx else Qx), Hy, Mx, My,
                 (if Hy < My then Qx else Hx), Hy, X (P), Y (P))
            then
               Tan := abs (Hy - Y (P)) / (Hx - X (P));
               if Locally_Inside (P, Hole)
                 and then (Tan < Tan_Min
                           or else (Tan = Tan_Min
                                    and then (X (P) > X (M)
                                              or else (X (P) = X (M)
                                                       and then Sector_Contains_Sector (M, P)))))
               then
                  M := P;
                  Tan_Min := Tan;
               end if;
            end if;
            P := Nx (P);
            exit when P = Stop;
         end loop;
         return M;
      end Find_Hole_Bridge;

      function Eliminate_Hole (Hole, Outer_Node : Positive) return Positive is
         Bridge, Bridge_Reverse : Natural;
         Dummy : Natural;
      begin
         Bridge := Find_Hole_Bridge (Hole, Outer_Node);
         if Bridge = Null_Node then
            return Outer_Node;
         end if;
         Bridge_Reverse := Split_Polygon (Bridge, Hole);
         Dummy := Filter_Points (Bridge_Reverse, Nx (Bridge_Reverse));
         return Filter_Points (Bridge, Nx (Bridge));
      end Eliminate_Hole;

      Outer_Len  : constant Natural :=
        (if Hole_Starts'Length > 0 then Hole_Starts (Hole_Starts'First)
         else Coords'Length);
      Outer_Node : Natural;
   begin
      Triangles.Clear;
      if Outer_Len < 3 then
         return;
      end if;
      Outer_Node := Linked_List (0, Outer_Len - 1, True);
      if Outer_Node = Null_Node or else Nx (Outer_Node) = Pv (Outer_Node) then
         return;
      end if;

      if Hole_Starts'Length > 0 then
         declare
            type Hole_Array is array (Positive range <>) of Positive;
            Queue : Hole_Array (1 .. Hole_Starts'Length);
            Count : Natural := 0;
            function Less (A, B : Positive) return Boolean is (X (A) < X (B));
            procedure Sort is new Ada.Containers.Generic_Array_Sort
              (Positive, Positive, Hole_Array, Less);
         begin
            for H in Hole_Starts'Range loop
               declare
                  From : constant Natural := Hole_Starts (H);
                  To   : constant Natural :=
                    (if H < Hole_Starts'Last then Hole_Starts (H + 1) - 1
                     else Coords'Length - 1);
                  L    : Natural;
               begin
                  if To - From >= 2 then
                     L := Linked_List (From, To, False);
                     if L /= Null_Node then
                        if L = Nx (L) then
                           Pool (L).Steiner := True;
                        end if;
                        Count := Count + 1;
                        Queue (Count) := Get_Leftmost (L);
                     end if;
                  end if;
               end;
            end loop;
            Sort (Queue (1 .. Count));
            for I in 1 .. Count loop
               Outer_Node := Eliminate_Hole (Queue (I), Outer_Node);
            end loop;
         end;
      end if;

      Earcut_Linked (Outer_Node, 0);
   end Triangulate;

end Earcut;
