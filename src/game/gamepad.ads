--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  A game controller (an Xbox-style pad, a PlayStation pad, the Steam
--  Controller through Steam Input or the kernel's hid-steam driver), read
--  straight from the Linux event device like the wheel.  Any device with
--  the gamepad's south button counts; a wheel does not.  Its buttons come
--  out as the wheel's, so the menus answer them the same way.

with Wheel;

package Gamepad is

   type Input is record
      Left_X, Left_Y   : Float := 0.0;   --  -1 .. 1, Y: -1 pushed forward
      Right_X, Right_Y : Float := 0.0;
      Left_Trigger, Right_Trigger : Float := 0.0;   --  0 .. 1
   end record;

   procedure Open;
   --  Look for a pad under /dev/input; quietly nothing if none

   procedure Poll;
   --  Once per frame; a pad plugged in later is found within a few seconds

   function Present return Boolean;
   function State return Input;

   function Touched return Boolean;
   --  A stick or a trigger is away from rest

   --  A south, B east, X square, Y triangle, LB / RB paddles, back share,
   --  start options, guide PS, the stick buttons L3 / R3, the d-pad
   function Next_Press (B : out Wheel.Button) return Boolean;
   function Held (B : Wheel.Button) return Boolean;

end Gamepad;
