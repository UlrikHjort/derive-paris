--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The morning round: before the city wakes, the baker's scooter with a
--  crate of warm baguettes, and the cafés, hotels and restaurants around
--  the bakery (data/bakeries.txt; the customers are at real house numbers,
--  different every morning) waiting for their bread before they open.
--  Stop at the door to hand it over; on time they tip, late they grumble,
--  and every knock breaks a baguette.  The dawn comes up as you ride (the
--  clock runs at a quarter of its pace); the best morning of each bakery
--  is kept in ~/.derive_rounds.

with Ada.Strings.Unbounded;

with Car;
with GL;

package Rounds is

   type Phase_Kind is (Off, Loading, Riding, Done);

   procedure Load;
   function Count return Natural;
   function Name (I : Positive) return String;
   function Best (I : Positive) return Float;   --  euros in tips, 0: none yet

   procedure Start (I : Positive; Player : out Car.State; Hour : in out Float);
   --  On the scooter at the bakery's door, a little before sunrise
   procedure Again (Player : out Car.State; Hour : in out Float);
   procedure Stop;

   function Phase return Phase_Kind;
   function Active return Boolean;      --  not Off
   function Holding return Boolean;     --  the crate is being loaded: wait
   function Clock_Pace return Float;
   --  Game hours a second while riding (0: the clock's usual pace)

   procedure Impact (Loss : Float);
   --  The scooter lost this much speed (m/s) in a knock this step

   procedure Update (Dt : Float; Player : Car.State; Hour : Float);

   procedure Goal (Serial : out Natural; X, Z : out Float;
                   Name : out Ada.Strings.Unbounded.Unbounded_String);
   --  The GPS goes to the customer who opens first

   procedure Draw (Model, Paint, Skin, Legs : GL.GLint; Time : Float);
   --  The baker at the door, the customers waiting with an arrow above

   function Hud_Text return String;      --  the round and the next customer (markup)
   function Banner return String;
   function Panel_Text return String;    --  the morning's account, when Done

end Rounds;
