--  Minimal binding to zlib's one-shot compress/uncompress.

with Ada.Streams;

package Zlib is

   Zlib_Error : exception;

   function Compress (Data : Ada.Streams.Stream_Element_Array)
     return Ada.Streams.Stream_Element_Array;

   function Uncompress (Data : Ada.Streams.Stream_Element_Array;
                        Size : Ada.Streams.Stream_Element_Offset)
     return Ada.Streams.Stream_Element_Array;
   --  Size: the length of the original data

end Zlib;
