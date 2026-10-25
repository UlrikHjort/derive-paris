--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
separate (Game)
procedure Update_Walk (Dt : Float) is
   Speed : constant Float := (if Keys.Shift then 4.2 else 1.5);
   Fwd_X : constant Float := Sin (Walk_Yaw);
   Fwd_Z : constant Float := -Cos (Walk_Yaw);
   DX, DZ : Float := 0.0;
   Turn  : constant Float := 1.8 * Dt;
begin
   --  in the funicular: carried up (or down), off at the other end
   if On_Funicular then
      if Funicular.Arrived then
         On_Funicular := False;
         Funicular.Alight (Walk_X, Walk_Z);
         Announce := Ada.Strings.Unbounded.To_Unbounded_String
           ((if Walk_Z < -3200.0 then "The Sacré-Cœur, at the top of Montmartre"
             else "Place Suzanne-Valadon, at the foot of the hill"));
         Announce_Timer := 3.0;
         Street_Timer := 1.0;
      else
         Funicular.Ride_Eye (Walk_X, Walk_Z, Cabin_Floor);
         return;
      end if;
   end if;
   if not In_Museum and then not In_Hall_B and then not In_Room and then not On_Tower
     and then not On_Arc and then not On_Boat and then Funicular.At_Station (Walk_X, Walk_Z)
   then
      Funicular.Board (Walk_X, Walk_Z);
      On_Funicular := True;
      Funicular.Ride_Eye (Walk_X, Walk_Z, Cabin_Floor);
      Traffic.Set_Walker (False, 0.0, 0.0);
      Announce := Ada.Strings.Unbounded.To_Unbounded_String
        ("Aboard the Funiculaire de Montmartre: the doors close, and off it goes");
      Announce_Timer := 4.0;
      Street_Timer := 1.0;
      return;
   end if;
   --  on a boat: carried along (the mouse looks round)
   if On_Boat then
      declare
         Heading : Float;
      begin
         Boats.Ride_Eye (Walk_X, Walk_Z, Boat_Deck, Heading);
      end;
      return;
   end if;
   if not In_Museum and then not In_Hall_B and then not In_Room and then not On_Tower
     and then not On_Arc and then On_A_Decal
   then
      return;
   end if;
   --  the yellow mark by the landing: a motorboat of your own
   if not In_Museum and then not In_Hall_B and then not In_Room and then not On_Tower
     and then not On_Arc and then Mode = Driving and then Motorboat.At_Hire (Walk_X, Walk_Z)
   then
      Parked := Player;
      Motorboat.Launch (Player);
      Car.Set_Player_Model (Car.Vedette);
      Boating := True;
      Walking := False;
      Capture_Mouse (False);
      Traffic.Set_Walker (False, 0.0, 0.0);
      Cam_Pos := (Player.X, 4.0 + Player.Ground, Player.Z) - 9.0 * Car.Forward (Player);
      Cam_Look := (Player.X, 1.0 + Player.Ground, Player.Z);
      Announce := Ada.Strings.Unbounded.To_Unbounded_String
        ("A motorboat of your own: the Seine is yours.  Back here and Q to tie up");
      Announce_Timer := 5.0;
      Street_Timer := 1.0;
      return;
   end if;
   --  the bateaux-mouches' landing: aboard
   if not In_Museum and then not In_Hall_B and then not In_Room and then not On_Tower
     and then not On_Arc and then Boats.At_Landing (Walk_X, Walk_Z)
   then
      declare
         Heading : Float;
      begin
         Boats.Board;
         if Boats.Riding then
            On_Boat := True;
            Boats.Ride_Eye (Walk_X, Walk_Z, Boat_Deck, Heading);
            Walk_Yaw := Heading;
            Walk_Pitch := 0.0;
            Traffic.Set_Walker (False, 0.0, 0.0);
            Announce := Ada.Strings.Unbounded.To_Unbounded_String
              ("Aboard a bateau-mouche: down the Seine to the Eiffel Tower and back (Q: ashore)");
            Announce_Timer := 5.0;
            Street_Timer := 1.0;
         end if;
      end;
      return;
   end if;
   if In_Room then
      Rooms.Update (Dt, Walk_X, Walk_Z);
      Rooms.Keep_Inside (Walk_X, Walk_Z);   --  (the metro: into the car when it leaves)
      if Rooms.At_Exit (Walk_X, Walk_Z) then
         Leave_Room;
         return;
      end if;
   elsif not In_Museum and then not In_Hall_B and then not On_Tower and then not On_Arc
     and then Ufo.In_Beam (Walk_X, Walk_Z)
   then
      Enter_Room (Rooms.Room_C);
      return;
   elsif not In_Museum and then not In_Hall_B and then not On_Tower and then not On_Arc
     and then Street_Life.At_Entrance (Walk_X, Walk_Z)
   then
      Enter_Room (Rooms.Room_Metro);   --  down into the metro
      return;
   end if;
   --  the arrows turn too, for those without a mouse
   if Keys.Left then
      Walk_Yaw := Walk_Yaw - Turn;
   elsif Keys.Right then
      Walk_Yaw := Walk_Yaw + Turn;
   end if;
   if Keys.Page_Up then
      Walk_Pitch := Float'Min (1.4, Walk_Pitch + Turn);
   elsif Keys.Page_Down then
      Walk_Pitch := Float'Max (-1.4, Walk_Pitch - Turn);
   end if;
   if Keys.W or else Keys.Up then
      DX := DX + Fwd_X;
      DZ := DZ + Fwd_Z;
   elsif Keys.S or else Keys.Down then
      DX := DX - Fwd_X;
      DZ := DZ - Fwd_Z;
   end if;
   if Keys.A then
      DX := DX + Fwd_Z;
      DZ := DZ - Fwd_X;
   elsif Keys.D then
      DX := DX - Fwd_Z;
      DZ := DZ + Fwd_X;
   end if;
   if DX /= 0.0 or else DZ /= 0.0 then
      declare
         L : constant Float := Sqrt (DX * DX + DZ * DZ);
         Hit : Boolean;
         NX, NZ : Float;
      begin
         Walk_X := Walk_X + DX / L * Speed * Dt;
         Walk_Z := Walk_Z + DZ / L * Speed * Dt;
         if On_Tower then
            Tower.Keep_On_Deck (Walk_X, Walk_Z);
            Walk_Step := Walk_Step + Dt * Speed * 4.2;
            return;
         end if;
         if On_Arc then
            Arc_Top.Keep_On_Roof (Walk_X, Walk_Z);
            Walk_Step := Walk_Step + Dt * Speed * 4.2;
            return;
         end if;
         if In_Room then
            Rooms.Keep_Inside (Walk_X, Walk_Z);
            Walk_Step := Walk_Step + Dt * Speed * 4.2;
            return;
         end if;
         if In_Hall_B then
            Hall_B.Keep_Inside (Walk_X, Walk_Z);
            Walk_Step := Walk_Step + Dt * Speed * 4.2;
            if Hall_B.At_Exit (Walk_X, Walk_Z) then
               Leave_Hall_B;
            end if;
            return;
         end if;
         if In_Museum then
            Museum.Keep_Inside (Walk_X, Walk_Z);
            Walk_Step := Walk_Step + Dt * Speed * 4.2;
            if Museum.At_Exit (Walk_X, Walk_Z) then
               Leave_Museum;
            end if;
            return;
         end if;
         --  walls, and the parked car
         World.Collide (Walk_X, Walk_Z, 0.35, Hit, NX, NZ);
         if Museum.Touching_Pyramid (Walk_X, Walk_Z) then
            Enter_Museum;
            return;
         end if;
         if Hall_B.Touching_Entrance (Walk_X, Walk_Z) then
            Enter_Hall_B;
            return;
         end if;
         if Tower.Under (Walk_X, Walk_Z) then
            Go_Up;
            return;
         end if;
         if Arc_Top.Under (Walk_X, Walk_Z) then
            Up_The_Arc;
            return;
         end if;
         declare
            CX : constant Float := Walk_X - Player.X;
            CZ : constant Float := Walk_Z - Player.Z;
            CD : constant Float := Sqrt (CX * CX + CZ * CZ);
         begin
            if CD < 1.6 and then CD > 0.01 then
               Walk_X := Player.X + CX / CD * 1.6;
               Walk_Z := Player.Z + CZ / CD * 1.6;
            end if;
         end;
         Walk_Step := Walk_Step + Dt * Speed * 4.2;
      end;
   end if;
   Traffic.Set_Walker (True, Walk_X, Walk_Z);
end Update_Walk;
