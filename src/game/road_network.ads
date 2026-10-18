--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The drivable road graph (tiles/roads.bin, written by osm2tiles), shared
--  by the traffic and the pedestrians, and the traffic-light timing that
--  the shader uses too.

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

with Math3D;

package Road_Network is

   type Node is record
      X, Z   : Float;
      Signal : Float := -1.0;   --  traffic-light phase offset (s), -1 = none
   end record;

   type Node_Array is array (Natural range <>) of Node;
   type Node_Array_Access is access Node_Array;

   type Way is record
      Oneway : Integer;      --  0 both ways, 1 along, -1 against node order
      Lanes  : Positive;
      Width  : Float;
      First  : Natural;      --  into Way_Nodes
      Count  : Natural;
      Name   : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Way_Array is array (Natural range <>) of Way;
   type Way_Array_Access is access Way_Array;

   type Int_Array is array (Natural range <>) of Natural;
   type Int_Array_Access is access Int_Array;

   --  A way to leave a node: along way W from its point Pos in direction Dir
   type Link is record
      W   : Natural := 0;
      Pos : Natural := 0;
      Dir : Integer := 1;
   end record;

   package Link_Vectors is new Ada.Containers.Vectors (Positive, Link);
   type Link_Table is array (Natural range <>) of Link_Vectors.Vector;
   type Link_Table_Access is access Link_Table;

   Nodes      : Node_Array_Access;
   Ways       : Way_Array_Access;
   Way_Nodes  : Int_Array_Access;
   Links      : Link_Table_Access;   --  directions cars may take
   Walk_Links : Link_Table_Access;   --  every direction (pedestrians)

   procedure Load (Dir : String);
   --  Read and merge every roads*.bin in Dir (one per converted chunk)

   function Loaded return Boolean is (Ways /= null and then Ways'Length > 0);

   function Point (W : Natural; Pos : Natural) return Node is
     (Nodes (Way_Nodes (Ways (W).First + Pos)));

   function Node_Index (W : Natural; Pos : Natural) return Natural is
     (Way_Nodes (Ways (W).First + Pos));

   procedure Segment (L : Link; A, B : out Node; Len : out Float);
   function Direction (L : Link) return Math3D.Vec3;

   procedure Pick_Segment
     (X, Z, Near, Far : Float; R1, R2, R3 : Float;
      Found : out Boolean; W, Pos : out Natural);
   --  A random road segment roughly between Near and Far metres from
   --  (X, Z); R1 .. R3 are uniform random numbers in [0, 1)

   procedure Nearest_Road
     (X, Z : Float; Found : out Boolean; PX, PZ, Heading : out Float);
   --  The closest point on the network, with the heading along the road
   --  (in an allowed driving direction)

   function Street_At (X, Z : Float; Max_Distance : Float := 14.0) return String;
   --  Name of the nearest named street within Max_Distance, "" if none

   --  Routing ---------------------------------------------------------------

   type Route_Point is record
      X, Z : Float;
      Way  : Natural;   --  the way driven from this point to the next
   end record;

   package Route_Vectors is new Ada.Containers.Vectors (Natural, Route_Point);

   procedure Find_Route
     (From_X, From_Z, Heading, To_X, To_Z : Float;
      Route : out Route_Vectors.Vector; Found : out Boolean;
      Any_Way : Boolean := False);
   --  Shortest drivable route (one-way streets respected), starting in the
   --  direction of Heading if possible.  Route starts at the car.  Any_Way:
   --  one-way streets both ways (the streets closed for a race)

   generic
      with procedure Visit (AX, AZ, BX, BZ, Width : Float; Named : Boolean);
   procedure For_Segments_Near (X, Z, Radius : Float);
   --  Every road segment near (X, Z), for drawing the minimap

   type Light is (Green, Amber, Red);

   Signal_Cycle : constant := 32.0;   --  seconds; matches world.frag

   function Signal_State (Offset, Dir_X, Dir_Z, Time : Float) return Light;
   --  State of a light for traffic moving along (Dir_X, Dir_Z).  East-west
   --  and north-south movements alternate.

end Road_Network;
