with Interfaces.C;
with System;

package body Zlib is

   use Ada.Streams;
   use Interfaces.C;

   function Compress_Bound (Source_Len : unsigned_long) return unsigned_long
     with Import, Convention => C, External_Name => "compressBound";

   function Compress2 (Dest : System.Address; Dest_Len : access unsigned_long;
                       Source : System.Address; Source_Len : unsigned_long;
                       Level : int) return int
     with Import, Convention => C, External_Name => "compress2";

   function Uncompress_C (Dest : System.Address; Dest_Len : access unsigned_long;
                          Source : System.Address; Source_Len : unsigned_long)
                          return int
     with Import, Convention => C, External_Name => "uncompress";

   function Compress (Data : Stream_Element_Array) return Stream_Element_Array is
      Bound  : constant unsigned_long := Compress_Bound (Data'Length);
      Result : Stream_Element_Array (1 .. Stream_Element_Offset (Bound));
      Len    : aliased unsigned_long := Bound;
   begin
      if Compress2 (Result'Address, Len'Access, Data'Address, Data'Length, 6) /= 0 then
         raise Zlib_Error with "compress2 failed";
      end if;
      return Result (1 .. Stream_Element_Offset (Len));
   end Compress;

   function Uncompress (Data : Stream_Element_Array; Size : Stream_Element_Offset)
     return Stream_Element_Array
   is
      Result : Stream_Element_Array (1 .. Size);
      Len    : aliased unsigned_long := unsigned_long (Size);
   begin
      if Uncompress_C (Result'Address, Len'Access, Data'Address, Data'Length) /= 0
        or else Stream_Element_Offset (Len) /= Size
      then
         raise Zlib_Error with "uncompress failed";
      end if;
      return Result;
   end Uncompress;

end Zlib;
