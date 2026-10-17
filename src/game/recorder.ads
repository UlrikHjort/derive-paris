--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Video recording (F9): the game's picture and sound into an MP4 in
--  ~/Videos/Derive, encoded by ffmpeg.

package Recorder is

   procedure Start (Width, Height : Natural);
   procedure Stop;
   function Active return Boolean;

   procedure Frame (Width, Height : Natural);
   --  After a frame is drawn, with the finished picture in the bound
   --  framebuffer: hand it to the encoder (30 frames per second)

   function Seconds return Natural;
   --  How long the recording has run

   function Message return String;
   --  What happened, for the screen: where the video goes, or an error

end Recorder;
