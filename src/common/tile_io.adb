with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Unchecked_Deallocation;

package body Tile_IO is

   use Ada.Streams.Stream_IO;
   use Interfaces;

   Magic : constant String := "PTL4";

   procedure Free_Floats is new Ada.Unchecked_Deallocation
     (Float_Array, Float_Array_Access);
   procedure Free_Indices is new Ada.Unchecked_Deallocation
     (Index_Array, Index_Array_Access);

   function Image (I : Integer) return String is
     (Ada.Strings.Fixed.Trim (Integer'Image (I), Ada.Strings.Both));

   function File_Name (Dir : String; IX, IZ : Integer) return String is
     (Dir & "/t_" & Image (IX) & "_" & Image (IZ) & ".bin");

   procedure Write (Dir : String; T : Tile_Data) is
      F : File_Type;
      S : Stream_Access;
   begin
      Create (F, Out_File, File_Name (Dir, T.IX, T.IZ));
      S := Stream (F);
      String'Write (S, Magic);
      Integer_32'Write (S, Integer_32 (T.IX));
      Integer_32'Write (S, Integer_32 (T.IZ));
      Integer_32'Write (S, Integer_32 (T.Vertices'Length));
      Float_Array'Write (S, T.Vertices.all);
      for G in Group_Id loop
         Integer_32'Write (S, Integer_32 (T.Indices (G)'Length));
         Index_Array'Write (S, T.Indices (G).all);
      end loop;
      Integer_32'Write (S, Integer_32 (T.Edges'Length));
      Float_Array'Write (S, T.Edges.all);
      Integer_32'Write (S, Integer_32 (T.Lights'Length));
      Float_Array'Write (S, T.Lights.all);
      Integer_32'Write (S, Integer_32 (T.Roads'Length));
      Float_Array'Write (S, T.Roads.all);
      Close (F);
   end Write;

   procedure Read
     (Dir : String; IX, IZ : Integer; T : out Tile_Data; Found : out Boolean)
   is
      Name : constant String := File_Name (Dir, IX, IZ);
      F    : File_Type;
      S    : Stream_Access;
      M    : String (1 .. 4);
      N    : Integer_32;
   begin
      Found := False;
      if not Ada.Directories.Exists (Name) then
         return;
      end if;
      Open (F, In_File, Name);
      S := Stream (F);
      String'Read (S, M);
      if M /= Magic then
         Close (F);
         return;
      end if;
      Integer_32'Read (S, N);
      T.IX := Integer (N);
      Integer_32'Read (S, N);
      T.IZ := Integer (N);
      Integer_32'Read (S, N);
      T.Vertices := new Float_Array (0 .. Integer (N) - 1);
      Float_Array'Read (S, T.Vertices.all);
      for G in Group_Id loop
         Integer_32'Read (S, N);
         T.Indices (G) := new Index_Array (0 .. Integer (N) - 1);
         Index_Array'Read (S, T.Indices (G).all);
      end loop;
      Integer_32'Read (S, N);
      T.Edges := new Float_Array (0 .. Integer (N) - 1);
      Float_Array'Read (S, T.Edges.all);
      Integer_32'Read (S, N);
      T.Lights := new Float_Array (0 .. Integer (N) - 1);
      Float_Array'Read (S, T.Lights.all);
      Integer_32'Read (S, N);
      T.Roads := new Float_Array (0 .. Integer (N) - 1);
      Float_Array'Read (S, T.Roads.all);
      Close (F);
      Found := True;
   end Read;

   procedure Free (T : in out Tile_Data) is
   begin
      Free_Floats (T.Vertices);
      Free_Floats (T.Edges);
      Free_Floats (T.Lights);
      Free_Floats (T.Roads);
      for G in Group_Id loop
         Free_Indices (T.Indices (G));
      end loop;
   end Free;

end Tile_IO;
