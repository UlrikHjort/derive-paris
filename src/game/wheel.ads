--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Racing wheel (Logitech G29 with pedals and H-shifter) read directly
--  from the Linux event device, with force feedback.  Without a wheel
--  everything here is a no-op and the keyboard drives as before.

package Wheel is

   type Gear_Position is range -1 .. 6;   --  -1 reverse, 0 neutral

   type Input is record
      Steering : Float := 0.0;   --  -1 full lock left .. 1 full lock right
      Throttle : Float := 0.0;   --  pedals 0 (released) .. 1 (floored)
      Brake    : Float := 0.0;
      Clutch   : Float := 0.0;
      Shifter  : Gear_Position := 0;
      Hat_X, Hat_Y : Integer := 0;   --  d-pad, -1 .. 1 (Y: -1 up)
   end record;

   type Button is
     (Cross, Square, Circle, Triangle, Paddle_Right, Paddle_Left, R2, L2,
      Share, Options, R3, L3, Plus, Minus, Dial_Right, Dial_Left, Enter, PS,
      Pad_Up, Pad_Down, Pad_Left, Pad_Right);

   procedure Open;
   --  Look for a wheel under /dev/input/by-id; quietly nothing if none

   function Present return Boolean;

   procedure Poll;
   --  Read what the wheel sent since the last call (once per frame).
   --  A wheel plugged in later is found within a few seconds.

   function State return Input;

   function Next_Press (B : out Button) return Boolean;
   --  Buttons pressed since the last Poll, one at a time

   function Held (B : Button) return Boolean;

   procedure Set_Gain (G : Float);
   --  Overall force feedback strength 0 .. 1

   procedure Set_Force (Level : Float);
   --  Constant force on the rim, -1 .. 1, positive turns the wheel right

end Wheel;
