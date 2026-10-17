--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Calendar.Time_Zones;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Strings.Maps;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada.Unchecked_Deallocation;
with Interfaces;
with System;

with Cairo;
with Cairo.Image_Surface;
with Cairo.Png;
with Cairo.Surface;
with Glib;

with GL;

package body Photo is

   use Ada.Strings.Unbounded;
   use Interfaces;

   type Byte_Array is array (Natural range <>) of Unsigned_8;
   type Byte_Access is access Byte_Array;
   procedure Free is new Ada.Unchecked_Deallocation (Byte_Array, Byte_Access);

   protected Status is
      procedure Set (S : String);
      function Get return String;
      procedure Set_Busy (B : Boolean);
      function Busy return Boolean;
   private
      Text : Unbounded_String;
      Working : Boolean := False;
   end Status;

   protected body Status is
      procedure Set (S : String) is
      begin
         Text := To_Unbounded_String (S);
      end Set;
      function Get return String is (To_String (Text));
      procedure Set_Busy (B : Boolean) is
      begin
         Working := B;
      end Set_Busy;
      function Busy return Boolean is (Working);
   end Status;

   function Message return String is (Status.Get);

   --  Writes one PNG at a time
   task Writer is
      entry Write (Pixels : Byte_Access; W, H : Natural; Name : String);
   end Writer;

   task body Writer is
      P    : Byte_Access;
      PW, PH : Natural := 0;
      File : Unbounded_String;
   begin
      loop
         select
            accept Write (Pixels : Byte_Access; W, H : Natural; Name : String) do
               P := Pixels;
               PW := W;
               PH := H;
               File := To_Unbounded_String (Name);
            end Write;
         or
            terminate;
         end select;
         declare
            use Cairo;
            Surface : constant Cairo_Surface := Cairo.Image_Surface.Create
              (Cairo.Image_Surface.Cairo_Format_RGB24, Glib.Gint (PW), Glib.Gint (PH));
            Stride  : constant Natural :=
              Natural (Cairo.Image_Surface.Get_Stride (Surface));
            Data    : constant System.Address := Cairo.Image_Surface.Get_Data_Generic (Surface);
            Out_Px  : Byte_Array (0 .. Stride * PH - 1) with Import, Address => Data;
            Result  : Cairo_Status;
         begin
            Cairo.Surface.Flush (Surface);
            for Y in 0 .. PH - 1 loop
               declare
                  Src : constant Natural := (PH - 1 - Y) * PW * 4;   --  GL rows go up
                  Dst : constant Natural := Y * Stride;
               begin
                  for X in 0 .. PW - 1 loop
                     --  cairo: 32-bit xRGB, little endian bytes B G R x
                     Out_Px (Dst + X * 4)     := P (Src + X * 4 + 2);
                     Out_Px (Dst + X * 4 + 1) := P (Src + X * 4 + 1);
                     Out_Px (Dst + X * 4 + 2) := P (Src + X * 4);
                     Out_Px (Dst + X * 4 + 3) := 255;
                  end loop;
               end;
            end loop;
            Cairo.Surface.Mark_Dirty (Surface);
            Result := Cairo.Png.Write_To_Png (Surface, To_String (File));
            Cairo.Surface.Destroy (Surface);
            if Result = Cairo_Status_Success then
               Status.Set ("Photo saved: " & To_String (File));
            else
               Status.Set ("Could not save " & To_String (File));
            end if;
            Ada.Text_IO.Put_Line (Status.Get);
         end;
         Free (P);
         Status.Set_Busy (False);
      end loop;
   end Writer;

   function Folder return String is
      Home     : constant String := Ada.Environment_Variables.Value ("HOME", ".");
      Pictures : constant String := Home & "/Pictures";
   begin
      return (if Ada.Directories.Exists (Pictures) then Pictures & "/Derive"
              else Home & "/Derive photos");
   end Folder;

   procedure Take (Width, Height : Natural) is
      Now   : constant String := Ada.Calendar.Formatting.Image
        (Ada.Calendar.Clock, Time_Zone => Ada.Calendar.Time_Zones.UTC_Time_Offset);
      Stamp : String := Now (Now'First .. Now'First + 18);
      P     : Byte_Access;
   begin
      if Status.Busy then
         Status.Set ("Still saving the last photo");
         return;
      end if;
      begin
         Ada.Directories.Create_Path (Folder);
      exception
         when others =>
            Status.Set ("Could not make " & Folder);
            return;
      end;
      Ada.Strings.Fixed.Translate (Stamp, Ada.Strings.Maps.To_Mapping (" :", "_-"));
      declare
         Base : constant String := Folder & "/derive_" & Stamp;
         Name : Unbounded_String := To_Unbounded_String (Base & ".png");
         N    : Positive := 2;
      begin
         while Ada.Directories.Exists (To_String (Name)) loop
            Name := To_Unbounded_String
              (Base & "_" & Ada.Strings.Fixed.Trim (Positive'Image (N), Ada.Strings.Left) & ".png");
            N := N + 1;
         end loop;
         P := new Byte_Array (0 .. Width * Height * 4 - 1);
         GL.glReadPixels (0, 0, GL.GLsizei (Width), GL.GLsizei (Height), GL.GL_RGBA,
                          GL.GL_UNSIGNED_BYTE, P.all'Address);
         Status.Set_Busy (True);
         Status.Set ("Photo saved: " & To_String (Name));
         Writer.Write (P, Width, Height, To_String (Name));
      end;
   end Take;

end Photo;
