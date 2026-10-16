with Ada.Numerics.Elementary_Functions;

with Meshes;
with World;

package body Car is

   use Ada.Numerics.Elementary_Functions;
   use Math3D;

   type Float_Array is array (Positive range <>) of Float;

   Wheel_Base    : constant := 2.6;
   Max_Steer     : constant := 0.55;
   Engine_Accel  : constant := 7.0;    --  m/s^2
   Brake_Decel   : constant := 14.0;
   Reverse_Accel : constant := 4.0;
   Max_Speed     : constant := 38.0;   --  ~137 km/h
   Max_Reverse   : constant := 8.0;
   Body_Radius   : constant := 1.0;    --  collision circles along the car
   Circle_Offset : constant := 1.15;

   function Forward (S : State) return Vec3 is
     ((Sin (S.Heading), 0.0, -Cos (S.Heading)));

   function Model_Matrix (S : State) return Mat4 is
     (Translation ((S.X, S.Lift, S.Z)) * Rotation_Y (-S.Heading));

   Kerb_Height : constant := 0.14;

   procedure Approach (V : in out Float; Target, Rate : Float) is
   begin
      if V < Target then
         V := Float'Min (Target, V + Rate);
      else
         V := Float'Max (Target, V - Rate);
      end if;
   end Approach;

   procedure Update (S : in out State; C : Controls; Dt : Float) is
      Was_On_Road  : constant Boolean := S.On_Road;
      Steer_Target : Float := 0.0;
      Speed_Factor : constant Float := 1.0 + abs S.Speed / 10.0;
   begin
      --  Longitudinal
      if C.Throttle then
         if S.Speed < -0.1 then
            S.Speed := S.Speed + Brake_Decel * Dt;
         else
            S.Speed := S.Speed + Engine_Accel * (1.0 - S.Speed / Max_Speed) * Dt;
         end if;
      elsif C.Brake then
         if S.Speed > 0.1 then
            S.Speed := S.Speed - Brake_Decel * Dt;
         else
            S.Speed := Float'Max (-Max_Reverse, S.Speed - Reverse_Accel * Dt);
         end if;
      else
         Approach (S.Speed, 0.0, 1.5 * Dt);   --  rolling resistance
      end if;
      if C.Handbrake then
         Approach (S.Speed, 0.0, 9.0 * Dt);
      end if;
      S.Speed := S.Speed - S.Speed * abs S.Speed * 0.0006 * Dt;  --  air drag

      --  Steering: less lock at speed, returns to centre when released
      if C.Left then
         Steer_Target := -Max_Steer / Speed_Factor;
      elsif C.Right then
         Steer_Target := Max_Steer / Speed_Factor;
      end if;
      Approach (S.Steer, Steer_Target, 2.5 * Dt);

      --  Bicycle model
      S.Heading := S.Heading + S.Speed / Wheel_Base * Tan (S.Steer) * Dt
        * (if C.Handbrake then 1.4 else 1.0);
      S.X := S.X + Sin (S.Heading) * S.Speed * Dt;
      S.Z := S.Z - Cos (S.Heading) * S.Speed * Dt;

      --  Collision: two circles (front and rear) pushed out of edges
      S.Bumped := False;
      for Offset of Float_Array'(Circle_Offset, -Circle_Offset) loop
         declare
            FX : constant Float := Sin (S.Heading) * Offset;
            FZ : constant Float := -Cos (S.Heading) * Offset;
            CX : Float := S.X + FX;
            CZ : Float := S.Z + FZ;
            Hit : Boolean;
            NX, NZ : Float;
         begin
            World.Collide (CX, CZ, Body_Radius, Hit, NX, NZ);
            if Hit then
               S.X := CX - FX;
               S.Z := CZ - FZ;
               S.Bumped := True;
               --  Remove the velocity component going into the wall
               declare
                  VX : constant Float := Sin (S.Heading) * S.Speed;
                  VZ : constant Float := -Cos (S.Heading) * S.Speed;
                  VN : constant Float := VX * NX + VZ * NZ;
               begin
                  if VN < 0.0 then
                     S.Speed := S.Speed * (1.0 - 0.9 * abs VN / Float'Max (abs S.Speed, 0.01));
                  end if;
               end;
            end if;
         end;
      end loop;

      --  Kerbs: the body rides 14 cm higher on the sidewalk; climbing the
      --  kerb at speed gives a jolt and costs some speed
      S.On_Road := World.On_Road (S.X, S.Z);
      if Was_On_Road and then not S.On_Road and then abs S.Speed > 2.0 then
         S.Lift_Speed := S.Lift_Speed + 0.9 + 0.04 * abs S.Speed;
         S.Speed := S.Speed * 0.88;
      elsif not Was_On_Road and then S.On_Road and then abs S.Speed > 2.0 then
         S.Lift_Speed := S.Lift_Speed - 0.4;
      end if;
      declare
         Target : constant Float := (if S.On_Road then 0.0 else Kerb_Height);
      begin
         S.Lift_Speed := S.Lift_Speed + ((Target - S.Lift) * 260.0 - S.Lift_Speed * 16.0) * Dt;
         S.Lift := S.Lift + S.Lift_Speed * Dt;
         if S.Lift < 0.0 then
            S.Lift := 0.0;
            S.Lift_Speed := 0.0;
         end if;
      end;
   end Update;

   ---------------------------------------------------------------------------
   --  Mesh
   ---------------------------------------------------------------------------

   Body_Mesh : Meshes.Mesh;

   procedure Create_Mesh is
      use Meshes;
   begin
      Start;
      --  Body (front is -Z)
      Box (-0.88, 0.88, 0.32, 0.95, -2.15, 2.1, Mat_Paint,
           Top_Inset_X => 0.03, Top_Inset_Front => 0.1, Top_Inset_Back => 0.05);
      --  Cabin with glass sides
      Box (-0.80, 0.80, 0.95, 1.42, -0.9, 1.15, Mat_Paint,
           Top_Inset_X => 0.12, Top_Inset_Front => 0.55, Top_Inset_Back => 0.3,
           Side_Mat => Mat_Glass);
      --  Wheels
      for WX of Float_Array'(-0.82, 0.82) loop
         for WZ of Float_Array'(-1.35, 1.3) loop
            Box (WX - 0.14, WX + 0.14, 0.0, 0.66, WZ - 0.33, WZ + 0.33, Mat_Tyre);
         end loop;
      end loop;
      --  Lights
      Box (-0.78, -0.45, 0.68, 0.82, -2.17, -2.1, Mat_Headlight);
      Box (0.45, 0.78, 0.68, 0.82, -2.17, -2.1, Mat_Headlight);
      Box (-0.82, -0.5, 0.72, 0.86, 2.06, 2.12, Mat_Taillight);
      Box (0.5, 0.82, 0.72, 0.86, 2.06, 2.12, Mat_Taillight);
      Finish (Body_Mesh);
   end Create_Mesh;

   procedure Draw is
   begin
      Meshes.Draw (Body_Mesh);
   end Draw;

end Car;
