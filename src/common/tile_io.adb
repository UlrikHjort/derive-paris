with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Unchecked_Deallocation;

with Zlib;

package body Tile_IO is

   use Ada.Streams;
   use Ada.Streams.Stream_IO;
   use Interfaces;

   Magic : constant String := "PTL5";

   procedure Free_Floats is new Ada.Unchecked_Deallocation
     (Float_Array, Float_Array_Access);
   procedure Free_Indices is new Ada.Unchecked_Deallocation
     (Index_Array, Index_Array_Access);

   function Image (I : Integer) return String is
     (Ada.Strings.Fixed.Trim (Integer'Image (I), Ada.Strings.Both));

   function File_Name (Dir : String; IX, IZ : Integer) return String is
     (Dir & "/t_" & Image (IX) & "_" & Image (IZ) & ".bin");

   --  Tiles are written into memory first and stored zlib-compressed:
   --  "PTL5", raw size, compressed size, compressed bytes.

   type Byte_Buffer is access Stream_Element_Array;
   procedure Free_Buffer is new Ada.Unchecked_Deallocation
     (Stream_Element_Array, Byte_Buffer);

   type Memory_Stream is new Root_Stream_Type with record
      Data : Byte_Buffer;
      Last : Stream_Element_Offset := 0;    --  write position / read position
   end record;

   overriding procedure Read
     (S : in out Memory_Stream; Item : out Stream_Element_Array;
      Last : out Stream_Element_Offset);
   overriding procedure Write
     (S : in out Memory_Stream; Item : Stream_Element_Array);

   overriding procedure Read
     (S : in out Memory_Stream; Item : out Stream_Element_Array;
      Last : out Stream_Element_Offset)
   is
      N : constant Stream_Element_Offset :=
        Stream_Element_Offset'Min (Item'Length, S.Data'Last - S.Last);
   begin
      Item (Item'First .. Item'First + N - 1) := S.Data (S.Last + 1 .. S.Last + N);
      S.Last := S.Last + N;
      Last := Item'First + N - 1;
   end Read;

   overriding procedure Write
     (S : in out Memory_Stream; Item : Stream_Element_Array)
   is
   begin
      if S.Data = null then
         S.Data := new Stream_Element_Array (1 .. 1_048_576);
      end if;
      if S.Last + Item'Length > S.Data'Last then
         declare
            Bigger : constant Byte_Buffer := new Stream_Element_Array
              (1 .. Stream_Element_Offset'Max (2 * S.Data'Last, S.Last + Item'Length));
         begin
            Bigger (1 .. S.Last) := S.Data (1 .. S.Last);
            Free_Buffer (S.Data);
            S.Data := Bigger;
         end;
      end if;
      S.Data (S.Last + 1 .. S.Last + Item'Length) := Item;
      S.Last := S.Last + Item'Length;
   end Write;

   procedure Write (Dir : String; T : Tile_Data) is
      M : aliased Memory_Stream;
      S : constant access Root_Stream_Type'Class := M'Access;
      F : File_Type;
   begin
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
      declare
         Packed : constant Stream_Element_Array := Zlib.Compress (M.Data (1 .. M.Last));
      begin
         Create (F, Out_File, File_Name (Dir, T.IX, T.IZ));
         String'Write (Stream (F), Magic);
         Integer_32'Write (Stream (F), Integer_32 (M.Last));
         Integer_32'Write (Stream (F), Integer_32 (Packed'Length));
         Write (F, Packed);
         Close (F);
      end;
      Free_Buffer (M.Data);
   end Write;

   procedure Read
     (Dir : String; IX, IZ : Integer; T : out Tile_Data; Found : out Boolean)
   is
      Name : constant String := File_Name (Dir, IX, IZ);
      F    : File_Type;
      M    : aliased Memory_Stream;
      S    : constant access Root_Stream_Type'Class := M'Access;
      Mg   : String (1 .. 4);
      Raw, Size, N : Integer_32;
   begin
      Found := False;
      if not Ada.Directories.Exists (Name) then
         return;
      end if;
      Open (F, In_File, Name);
      String'Read (Stream (F), Mg);
      if Mg /= Magic then
         Close (F);
         return;
      end if;
      Integer_32'Read (Stream (F), Raw);
      Integer_32'Read (Stream (F), Size);
      declare
         Packed : Stream_Element_Array (1 .. Stream_Element_Offset (Size));
         Last   : Stream_Element_Offset;
      begin
         Read (F, Packed, Last);
         Close (F);
         M.Data := new Stream_Element_Array'
           (Zlib.Uncompress (Packed, Stream_Element_Offset (Raw)));
      end;

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
      Free_Buffer (M.Data);
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
