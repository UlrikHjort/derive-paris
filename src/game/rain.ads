--  Falling rain: streaks in a box that travels with the camera.

with Math3D;

package Rain is

   procedure Create;
   --  Build the program and the drop buffer (GL context current)

   procedure Draw (VP : Math3D.Mat4; Cam : Math3D.Vec3;
                   Time, Amount : Float; Color : Math3D.Vec3);
   --  Amount 0 .. 1; draws nothing when it is 0

end Rain;
