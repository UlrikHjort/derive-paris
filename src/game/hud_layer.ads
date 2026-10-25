--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The panels (street sign, compass, minimap, speedometer, menus...) are
--  GTK widgets laid out in an offscreen window; their picture is drawn
--  here over the 3D view, in OpenGL.  (Left on top of the GL area, GTK 3
--  would read the whole 3D picture back from the graphics card every
--  frame to blend them in, which halved the frame rate.)

with System;

package Hud_Layer is

   procedure Create;
   --  (GL context current)

   procedure Draw (Data : System.Address; Width, Height, Stride : Natural;
                   X0, Y0, X1, Y1 : Natural);
   --  The picture (cairo's ARGB32: premultiplied, B G R A in memory, rows
   --  of Stride bytes from the top); only the part X0 .. X1 - 1, Y0 .. Y1 - 1
   --  changed (none when empty), the whole when the size is new

end Hud_Layer;
