--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
separate (Game)
procedure Update_Camera (Dt : Float) is
   Desired, Look : Vec3;
   K : constant Float := 1.0 - Exp (-Dt * (if Mode = Flying then 8.0 else 6.0));
begin
   if Fixed_Camera then
      return;
   end if;
   --  a postcard being printed: for a few frames, right before the work
   if Snap_Frames > 0 then
      Cam_Pos := Snap_Eye;
      Cam_Look := Snap_Look;
      Snap_Frames := Snap_Frames - 1;
      Hall_B.Snapping := Snap_Frames > 0;
      if Snap_Frames = 1 then
         Postcards.Buy (Ada.Strings.Unbounded.To_String (Snap_Name),
                        Ada.Strings.Unbounded.To_String (Snap_Text));
      end if;
      return;
   end if;
   --  PARIS_ORBIT="angle distance height": look at the car from there
   --  (testing; angle in degrees from straight ahead, clockwise)
   if Env ("PARIS_ORBIT") /= "" and then Mode = Driving then
      declare
         S  : constant String := Env ("PARIS_ORBIT") & " ";
         P1 : constant Natural := Index_Of (S, ' ', S'First);
         P2 : constant Natural := Index_Of (S, ' ', P1 + 1);
         A  : constant Float := Player.Heading
           + Float'Value (S (S'First .. P1 - 1)) * Ada.Numerics.Pi / 180.0;
         D  : constant Float := Float'Value (S (P1 + 1 .. P2 - 1));
         H  : constant Float := Float'Value (S (P2 + 1 .. S'Last - 1));
      begin
         Cam_Pos := (Player.X + D * Sin (A), H + Player.Ground, Player.Z - D * Cos (A));
         Cam_Look := (Player.X, 0.8 + Player.Ground, Player.Z);
         return;
      end;
   end if;
   if Visiting then
      Cam_Pos := Eye_Position;
      Cam_Look := Cam_Pos + Vec3'(Sin (Eye_Yaw) * Cos (Eye_Pitch), Sin (Eye_Pitch),
                                  -Cos (Eye_Yaw) * Cos (Eye_Pitch));
      return;
   end if;
   if Walking then
      Cam_Pos := Walk_Eye;
      Cam_Look := Cam_Pos + Vec3'(Sin (Walk_Yaw) * Cos (Walk_Pitch), Sin (Walk_Pitch),
                                  -Cos (Walk_Yaw) * Cos (Walk_Pitch));
      return;
   end if;
   if Mode = Flying then
      --  Behind and a little above the plane, following its heading
      --  (and half its pitch, so loops stay readable)
      declare
         H  : constant Float := Aircraft.Heading;
         P  : constant Float := 0.5 * Aircraft.Pitch;
         Bk : constant Vec3 := (Sin (H) * Cos (P), Sin (P), -Cos (H) * Cos (P));
      begin
         Desired := Aircraft.Pos - (16.0 * Zoom) * Bk + (0.0, 4.0 * Zoom, 0.0);
         Look := Aircraft.Pos + 10.0 * Plane.Forward (Aircraft);
      end;
   else
      declare
         Fwd     : constant Vec3 := Car.Forward (Player);
         Car_Pos : constant Vec3 := (Player.X, Player.Ground, Player.Z);
         Bus     : constant Boolean := Car."=" (Car.Player_Model, Car.Bus);
         Back    : constant Float := Zoom * (if Drone then Drone_Back elsif Bus then 17.0 else 8.5);
         Up      : constant Float := Zoom * (if Drone then Drone_Up elsif Bus then 6.0 else 3.2);
      begin
         Desired := Car_Pos - Back * Fwd + (0.0, Up, 0.0);
         Look := Car_Pos + (0.0, 1.2, 0.0) + (if Drone then 6.0 else 3.0) * Fwd;
      end;
   end if;
   Cam_Pos := Lerp (Cam_Pos, Desired, K);
   Cam_Look := Lerp (Cam_Look, Look, 1.0 - Exp (-Dt * 12.0));
   --  a wall between the car and the camera (a narrow street, turning
   --  by a building): the camera comes in to this side of it, and up a
   --  little when that is close, to look down on the car; it eases back
   --  out once the view is clear
   if Mode = Driving then
      declare
         Target : constant Vec3 := (Player.X, Player.Ground + 1.6, Player.Z);
         Span   : constant Float := Length (Cam_Pos - Target);
         Free   : constant Float := World.Ray_Free (Target, Cam_Pos);
      begin
         if Free < 1.0 and then Span > 0.5 then
            declare
               D : constant Float := Float'Max (1.5, Free * Span - 0.7);
            begin
               Cam_Pos := Target + (D / Span) * (Cam_Pos - Target);
               Cam_Pos.Y := Cam_Pos.Y + Float'Max (0.0, 6.0 - D) * 0.5;
            end;
         end if;
      end;
   end if;
   --  never below the ground (hills, the plane low over Montmartre)
   declare
      G : constant Float := Terrain.Height (Cam_Pos.X, Cam_Pos.Z) + 1.0;
   begin
      if Cam_Pos.Y < G then
         Cam_Pos.Y := G;
      end if;
   end;
end Update_Camera;
