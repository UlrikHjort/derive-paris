--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Calendar.Time_Zones;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Real_Time;
with Ada.Strings.Fixed;
with Ada.Strings.Maps;
with Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;
with Ada.Text_IO;
with GNAT.OS_Lib;
with Interfaces.C;
with System;

with GL;
with Sound;

package body Recorder is

   use Ada.Strings.Unbounded;
   use type System.Address;
   use type Interfaces.C.size_t;
   use type Ada.Real_Time.Time;
   use type GNAT.OS_Lib.String_Access;

   Rate : constant := 30;   --  frames per second

   function Popen (Command, Mode : Interfaces.C.char_array) return System.Address
     with Import, Convention => C, External_Name => "popen";
   function Pclose (Stream : System.Address) return Interfaces.C.int
     with Import, Convention => C, External_Name => "pclose";
   function Fwrite (Data : System.Address; Size, N : Interfaces.C.size_t;
                    Stream : System.Address) return Interfaces.C.size_t
     with Import, Convention => C, External_Name => "fwrite";

   --  If ffmpeg dies, a write must fail instead of killing the game
   function Signal (Sig : Interfaces.C.int; Handler : System.Address) return System.Address
     with Import, Convention => C, External_Name => "signal";
   SIGPIPE : constant := 13;
   SIG_IGN : constant System.Address := System'To_Address (1);

   type Byte_Array is array (Natural range <>) of Interfaces.Unsigned_8;
   type Byte_Access is access Byte_Array;

   Pipe     : System.Address := System.Null_Address;
   Pixels   : Byte_Access;
   Rec_W, Rec_H : Natural := 0;
   Started  : Ada.Real_Time.Time;
   Written  : Natural := 0;
   Base     : Unbounded_String;   --  output file without extension
   With_Sound : Boolean := False;
   Note     : Unbounded_String;

   function Q (S : String) return String is ("'" & S & "'");

   function Active return Boolean is (Pipe /= System.Null_Address);

   function Seconds return Natural is
     (if Active then Natural (Ada.Real_Time.To_Duration (Ada.Real_Time.Clock - Started))
      else 0);

   function Message return String is (To_String (Note));

   function Folder return String is
      Home   : constant String := Ada.Environment_Variables.Value ("HOME", ".");
      Videos : constant String := Home & "/Videos";
   begin
      return (if Ada.Directories.Exists (Videos) then Videos & "/Derive" else Home & "/Derive videos");
   end Folder;

   procedure Start (Width, Height : Natural) is
      Now  : constant String := Ada.Calendar.Formatting.Image
        (Ada.Calendar.Clock, Time_Zone => Ada.Calendar.Time_Zones.UTC_Time_Offset);
      Stamp : String := Now (Now'First .. Now'First + 18);   --  YYYY-MM-DD HH:MM:SS
      Ignored : System.Address;
      pragma Unreferenced (Ignored);
   begin
      if Active then
         return;
      end if;
      Ignored := Signal (SIGPIPE, SIG_IGN);
      if GNAT.OS_Lib.Locate_Exec_On_Path ("ffmpeg") = null then
         Note := To_Unbounded_String ("Recording needs ffmpeg (sudo apt install ffmpeg)");
         return;
      end if;
      Ada.Strings.Fixed.Translate (Stamp, Ada.Strings.Maps.To_Mapping (" :", "_-"));
      begin
         Ada.Directories.Create_Path (Folder);
      exception
         when others =>
            Note := To_Unbounded_String ("Could not make " & Folder);
            return;
      end;
      Base := To_Unbounded_String (Folder & "/derive_" & Stamp);
      --  the encoder wants even sizes
      Rec_W := Width - Width mod 2;
      Rec_H := Height - Height mod 2;
      Pixels := new Byte_Array (0 .. Rec_W * Rec_H * 4 - 1);
      declare
         Cmd : constant String :=
           "ffmpeg -loglevel error -y -f rawvideo -pix_fmt rgba -video_size"
           & Natural'Image (Rec_W) & "x" & Ada.Strings.Fixed.Trim (Natural'Image (Rec_H), Ada.Strings.Left)
           & " -framerate" & Natural'Image (Rate) & " -i - -vf vflip"
           & " -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p "
           & Q (To_String (Base) & ".video.mkv");
      begin
         Pipe := Popen (Interfaces.C.To_C (Cmd), Interfaces.C.To_C ("w"));
      end;
      if Pipe = System.Null_Address then
         Note := To_Unbounded_String ("Could not start ffmpeg");
         return;
      end if;
      With_Sound := Sound.Playing;
      if With_Sound then
         Sound.Start_Capture (To_String (Base) & ".audio.raw");
      end if;
      Started := Ada.Real_Time.Clock;
      Written := 0;
      Note := To_Unbounded_String ("Recording to " & To_String (Base) & ".mp4");
      Ada.Text_IO.Put_Line (To_String (Note));
   end Start;

   procedure Frame (Width, Height : Natural) is
      use GL;
      Due : Integer;
      N   : Interfaces.C.size_t;
   begin
      if not Active then
         return;
      end if;
      if Width - Width mod 2 /= Rec_W or else Height - Height mod 2 /= Rec_H then
         Stop;   --  the window changed size
         return;
      end if;
      --  keep the video in step with the clock (and the sound): repeat a
      --  frame when the game is slower than 30 fps, skip when faster
      Due := Integer (Float'Floor (Float (Ada.Real_Time.To_Duration
                                           (Ada.Real_Time.Clock - Started)) * Float (Rate)))
        + 1 - Written;
      if Due <= 0 then
         return;
      end if;
      glReadPixels (0, 0, GLsizei (Rec_W), GLsizei (Rec_H), GL_RGBA, GL_UNSIGNED_BYTE,
                    Pixels.all'Address);
      for I in 1 .. Integer'Min (Due, 15) loop
         N := Fwrite (Pixels.all'Address, 1, Pixels'Length, Pipe);
         if N /= Pixels'Length then
            Note := To_Unbounded_String ("Recording stopped: ffmpeg failed");
            Stop;
            return;
         end if;
      end loop;
      Written := Written + Due;
   end Frame;

   procedure Free is new Ada.Unchecked_Deallocation (Byte_Array, Byte_Access);

   procedure Stop is
      R : Interfaces.C.int;
      B : constant String := To_String (Base);
   begin
      if not Active then
         return;
      end if;
      R := Pclose (Pipe);   --  the encoder finishes
      pragma Unreferenced (R);
      Pipe := System.Null_Address;
      Free (Pixels);
      if With_Sound then
         Sound.Stop_Capture;
      end if;
      --  put picture and sound together in the background
      declare
         Cmd : constant String :=
           (if With_Sound then
              "ffmpeg -loglevel error -y -i " & Q (B & ".video.mkv")
              & " -f s16le -ar 44100 -ac 2 -i " & Q (B & ".audio.raw")
              & " -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart "
              & Q (B & ".mp4") & " && rm -f " & Q (B & ".video.mkv") & " " & Q (B & ".audio.raw")
            else
              "ffmpeg -loglevel error -y -i " & Q (B & ".video.mkv")
              & " -c copy -movflags +faststart " & Q (B & ".mp4")
              & " && rm -f " & Q (B & ".video.mkv"));
         Args : GNAT.OS_Lib.Argument_List :=
           (new String'("-c"), new String'(Cmd));
         Pid  : GNAT.OS_Lib.Process_Id;
         pragma Unreferenced (Pid);
      begin
         Pid := GNAT.OS_Lib.Non_Blocking_Spawn ("/bin/sh", Args);
         for A of Args loop
            GNAT.OS_Lib.Free (A);
         end loop;
      end;
      Note := To_Unbounded_String ("Video saved: " & B & ".mp4");
      Ada.Text_IO.Put_Line (To_String (Note));
   end Stop;

end Recorder;
