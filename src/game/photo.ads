--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Photos (F12): the game's picture as a PNG in ~/Pictures/Derive.  The
--  picture is copied at once; the PNG is written in the background so
--  the game does not stutter.

package Photo is

   procedure Take (Width, Height : Natural);
   --  Copy the picture in the bound framebuffer (after a frame is drawn)

   procedure Take_As (Width, Height : Natural; File_Name : String; Max_Width : Positive);
   --  The same, into that file and made smaller (for the postcards); it
   --  does not change the message

   function Message return String;
   --  Where the last photo went, or why there was none

end Photo;
