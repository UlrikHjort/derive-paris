--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The Seine's channel, for the plane: between the quay walls it may fly
--  down to just above the water (and so under the bridges).  From the
--  middle line in data/seine.txt.

package River is

   function In_Channel (X, Z : Float) return Boolean;

   function Length return Float;
   --  Of the middle line, from Austerlitz (0) down to Bir-Hakeim

   procedure At_Distance (S : Float; X, Z, DX, DZ : out Float);
   --  The point that far along the middle line, and the way downstream

   function Distance_Of (X, Z : Float) return Float;
   --  How far along the middle line the point nearest (X, Z) is
   --  Over the water, well clear of the quay walls

   Depth : constant := 6.0;
   --  How far below the street the water lies there

   Deck_Under : constant := 1.4;
   --  How far below the street a bridge's underside is

   Lowest : constant := 0.5;
   --  How low over the water the plane may fly

   Clear : constant := 0.5;
   --  How far it must keep below a bridge's underside

   function Gap_Top return Float is (Depth - Deck_Under - Clear);
   --  Above the water: fly between Lowest and this to pass under a bridge

end River;
