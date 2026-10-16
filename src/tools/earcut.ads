--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT AND ISC
--
--  This is a port of earcut (https://github.com/mapbox/earcut):
--
--  ISC License
--
--  Copyright (c) 2016, Mapbox
--
--  Permission to use, copy, modify, and/or distribute this software for any
--  purpose with or without fee is hereby granted, provided that the above
--  copyright notice and this permission notice appear in all copies.
--
--  THE SOFTWARE IS PROVIDED "AS IS" AND ISC DISCLAIMS ALL WARRANTIES WITH
--  REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
--  AND FITNESS. IN NO EVENT SHALL ISC BE LIABLE FOR ANY SPECIAL, DIRECT,
--  INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
--  LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE
--  OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
--  PERFORMANCE OF THIS SOFTWARE.
--
--  Polygon triangulation with holes by ear clipping.
--  A port of the core of Mapbox's earcut algorithm (ISC licence),
--  without the z-order hashing (our polygons are small).

with Ada.Containers.Vectors;

package Earcut is

   type Point is record
      X, Y : Long_Float;
   end record;

   type Point_Array is array (Natural range <>) of Point;
   type Natural_Array is array (Positive range <>) of Natural;

   package Index_Vectors is new Ada.Containers.Vectors (Natural, Natural);

   procedure Triangulate
     (Coords      : Point_Array;
      Hole_Starts : Natural_Array;
      Triangles   : out Index_Vectors.Vector);
   --  Coords holds the outer ring followed by the hole rings (rings are
   --  open: the first point is not repeated).  Hole_Starts gives the index
   --  in Coords where each hole begins.  Triangles receives index triples
   --  into Coords.

end Earcut;
