--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
separate (Game)
procedure Toggle_Walk is
   Side_X : constant Float := -Cos (Player.Heading);   --  the driver's side (left)
   Side_Z : constant Float := -Sin (Player.Heading);
   procedure Say (Text : String; Seconds : Float) is
   begin
      Announce := Ada.Strings.Unbounded.To_Unbounded_String (Text);
      Announce_Timer := Seconds;
      Street_Timer := 1.0;
   end Say;
begin
   if not Walking and then Boating then
      --  out of the boat: only at the landing, where it is tied up
      if not Motorboat.Near_Landing (Player) then
         Say ("Bring the boat back to the landing by the Pont de l'Alma (Q there)", 3.0);
         return;
      end if;
      if abs Player.Speed > 1.5 then
         Say ("Slow down first", 1.5);
         return;
      end if;
      Motorboat.Hire_Point (Walk_X, Walk_Z);
      Walk_Z := Walk_Z - 1.6;   --  (beside the mark, not on it)
      Walk_Yaw := Player.Heading;
      Walk_Pitch := 0.0;
      Walking := True;
      Capture_Mouse (True);
      Boating := False;
      Player := Parked;
      Car.Set_Player_Model (Usual_Model);
      Say ("The boat is tied up.  Q: back to the car", 3.0);
      return;
   end if;
   if not Walking and then Riding_Velib then
      --  off the Vélib': only at a station, where it locks into a dock
      declare
         Found : Boolean;
         BX, BZ, BH : Float;
      begin
         Street_Life.Nearest_Velib (Player.X, Player.Z, 14.0, Found, BX, BZ, BH);
         if not Found then
            Say ("Leave the Vélib' at a station (Q there)", 2.5);
            return;
         end if;
         if abs Player.Speed > 1.5 then
            Say ("Stop first", 1.5);
            return;
         end if;
         Walking := True;
         Walk_X := Player.X + 1.0 * Side_X;
         Walk_Z := Player.Z + 1.0 * Side_Z;
         Walk_Yaw := Player.Heading;
         Walk_Pitch := 0.0;
         Capture_Mouse (True);
         Riding_Velib := False;
         Player := Parked;
         Car.Set_Player_Model (Usual_Model);
         Say ("The Vélib' is back in its dock.  Q: back to the car", 3.0);
         return;
      end;
   end if;
   if not Walking then
      if Mode /= Driving or else Visiting then
         return;
      end if;
      if abs Player.Speed > 2.0 then
         Announce := Ada.Strings.Unbounded.To_Unbounded_String ("Stop the car first");
         Announce_Timer := 1.5;
         Street_Timer := 1.0;
         return;
      end if;
      Walking := True;
      Walk_X := Player.X + 1.6 * Side_X;
      Walk_Z := Player.Z + 1.6 * Side_Z;
      Walk_Yaw := Player.Heading;
      Walk_Pitch := 0.0;
      Capture_Mouse (True);
      Announce := Ada.Strings.Unbounded.To_Unbounded_String
        ("On foot: mouse to look, W/A/S/D to walk, Shift to run, Q to drive on");
      Announce_Timer := 4.0;
      Street_Timer := 1.0;
   elsif In_Museum then
      Leave_Museum;
   elsif In_Hall_B then
      Leave_Hall_B;
   elsif In_Room then
      Leave_Room;
   elsif On_Tower then
      Go_Down;
   elsif On_Arc then
      Down_The_Arc;
   elsif On_Boat then
      On_Boat := False;
      Boats.Ashore (Walk_X, Walk_Z);
      Walk_Pitch := 0.0;
      Announce := Ada.Strings.Unbounded.To_Unbounded_String ("Ashore");
      Announce_Timer := 2.0;
      Street_Timer := 1.0;
   else
      --  by a Vélib' station: take a bike (the car stays where it is)
      declare
         Found : Boolean;
         BX, BZ, BH : Float;
      begin
         Street_Life.Nearest_Velib (Walk_X, Walk_Z, 10.0, Found, BX, BZ, BH);
         if Found and then Mode = Driving then
            if Cos (BH - Walk_Yaw) < 0.0 then
               BH := BH + Ada.Numerics.Pi;   --  the way you face
            end if;
            Parked := Player;
            Player := Car.On_Ground (BX, BZ, BH);
            Player.Ground := Terrain.Height (BX, BZ);
            Car.Set_Player_Model (Car.Velib);
            Riding_Velib := True;
            Walking := False;
            Capture_Mouse (False);
            Traffic.Set_Walker (False, 0.0, 0.0);
            Cam_Pos := (Player.X, 4.0 + Player.Ground, Player.Z) - 6.0 * Car.Forward (Player);
            Cam_Look := (Player.X, 1.2 + Player.Ground, Player.Z);
            Say ("On a Vélib'!  Ride to another station and Q there to leave it", 4.0);
            return;
         end if;
      end;
      declare
         DX : constant Float := Player.X - Walk_X;
         DZ : constant Float := Player.Z - Walk_Z;
         D  : constant Float := Sqrt (DX * DX + DZ * DZ);
      begin
         Walking := False;
         Capture_Mouse (False);
         Traffic.Set_Walker (False, 0.0, 0.0);
         if D >= 6.0 then
            --  far from the car: back to it at once
            Pending_Load := True;
            Cam_Pos := (Player.X, 6.0 + Player.Ground, Player.Z) - 10.0 * Car.Forward (Player);
            Cam_Look := (Player.X, 1.2 + Player.Ground, Player.Z);
            Announce := Ada.Strings.Unbounded.To_Unbounded_String
              ("Back to the car (" & Ada.Strings.Fixed.Trim (Natural'Image (Natural (D)), Ada.Strings.Left)
               & " m away)");
            Announce_Timer := 2.0;
            Street_Timer := 1.0;
         end if;
      end;
   end if;
end Toggle_Walk;
