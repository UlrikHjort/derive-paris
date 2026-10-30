--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions;

with Meshes;
with Shaders;

package body Figures is

   use Math3D;

   Mat_Fur : constant := 39.0;
   Mat_Wood : constant := 13.0;
   Mat_Gold : constant := 38.0;

   L : Locations;

   Torso, Leg_L, Leg_R, Arm_R, Kepi_M, Helmet_M, Cap_M,
   Guitar_M, Accordion_M, Drum_M, Violin_M,
   Bike_M, Rider_M, Crank_M, Cat_Body, Cat_Tail, Bird_Body, Wing_L, Wing_R,
   Ball_M, Sitting_M : Meshes.Mesh;

   Hip : constant := 0.9;

   procedure Create is
      use Meshes;
   begin
      --  body without the right arm (it can be raised); front is -Z
      Start;
      Box (-0.2, 0.2, 0.9, 1.45, -0.12, 0.12, Mat_Cloth, Top_Inset_X => 0.03);
      Box (-0.27, -0.2, 0.86, 1.42, -0.07, 0.07, Mat_Cloth);
      Box (-0.05, 0.05, 1.45, 1.52, -0.05, 0.05, Mat_Skin);
      Box (-0.1, 0.1, 1.5, 1.73, -0.11, 0.1, Mat_Skin);
      Box (-0.105, 0.105, 1.66, 1.77, -0.08, 0.115, Mat_Tyre);
      Finish (Torso);
      Start;
      Box (0.2, 0.27, -0.56, 0.0, -0.07, 0.07, Mat_Cloth);   --  hangs from the shoulder
      Finish (Arm_R);
      Start;
      Box (-0.18, -0.02, 0.08, Hip, -0.08, 0.08, Mat_Trousers);
      Box (-0.18, -0.02, 0.0, 0.08, -0.15, 0.08, Mat_Tyre);
      Finish (Leg_L);
      Start;
      Box (0.02, 0.18, 0.08, Hip, -0.08, 0.08, Mat_Trousers);
      Box (0.02, 0.18, 0.0, 0.08, -0.15, 0.08, Mat_Tyre);
      Finish (Leg_R);
      --  hats (in the hat colour: drawn as paint)
      Start;
      Box (-0.11, 0.11, 1.7, 1.86, -0.12, 0.11, Mat_Paint);
      Box (-0.12, 0.12, 1.69, 1.72, -0.18, 0.12, Mat_Tyre);   --  peak
      Finish (Kepi_M);
      Start;
      Box (-0.14, 0.14, 1.66, 1.86, -0.15, 0.14, Mat_Paint, Top_Inset_X => 0.05,
           Top_Inset_Front => 0.05, Top_Inset_Back => 0.05);
      Finish (Helmet_M);
      Start;
      Box (-0.115, 0.115, 1.7, 1.8, -0.12, 0.12, Mat_Paint);
      Box (-0.1, 0.1, 1.7, 1.73, -0.25, -0.1, Mat_Paint);
      Finish (Cap_M);
      --  instruments, held in front
      Start;
      Box (-0.25, 0.1, 0.95, 1.2, -0.22, -0.14, Mat_Wood);     --  body of the guitar
      Box (0.1, 0.5, 1.12, 1.17, -0.2, -0.16, Mat_Tyre);       --  neck
      Finish (Guitar_M);
      Start;
      Box (-0.22, 0.22, 0.95, 1.3, -0.3, -0.12, Mat_Paint);    --  bellows (red)
      Box (-0.24, -0.18, 0.93, 1.32, -0.32, -0.1, Mat_Tyre);
      Box (0.18, 0.24, 0.93, 1.32, -0.32, -0.1, Mat_Fur);      --  keys
      Finish (Accordion_M);
      Start;
      Box (-0.22, 0.22, 0.75, 1.05, -0.45, -0.15, Mat_Paint);
      Box (-0.23, 0.23, 1.04, 1.07, -0.46, -0.14, Mat_Fur);
      Finish (Drum_M);
      Start;
      Box (-0.06, 0.06, 1.3, 1.42, -0.3, -0.05, Mat_Wood);
      Box (0.02, 0.4, 1.38, 1.4, -0.35, -0.33, Mat_Fur);       --  bow
      Finish (Violin_M);
      --  a racing bike and its rider, bent low over the bars
      Start;
      Box (-0.02, 0.02, 0.0, 0.68, -0.95, -0.3, Mat_Tyre);     --  wheels
      Box (-0.02, 0.02, 0.0, 0.68, 0.25, 0.9, Mat_Tyre);
      Box (-0.025, 0.025, 0.35, 0.85, -0.62, 0.55, Mat_Paint); --  frame (paint)
      Box (-0.22, 0.22, 0.95, 0.98, -0.72, -0.62, Mat_Tyre);   --  handlebar
      Finish (Bike_M);
      Start;
      Box (-0.17, 0.17, 0.85, 1.25, -0.45, 0.4, Mat_Cloth,
           Top_Inset_Front => 0.25);                            --  back, bent over
      Box (-0.1, 0.1, 1.08, 1.32, -0.72, -0.48, Mat_Skin);     --  head
      Box (-0.12, 0.12, 1.24, 1.36, -0.75, -0.45, Mat_Paint);  --  helmet
      Box (-0.22, -0.16, 0.95, 1.15, -0.7, -0.2, Mat_Cloth);   --  arms
      Box (0.16, 0.22, 0.95, 1.15, -0.7, -0.2, Mat_Cloth);
      Finish (Rider_M);
      Start;
      Box (-0.16, -0.05, 0.3, 0.85, -0.06, 0.06, Mat_Skin);    --  legs, turning
      Box (0.05, 0.16, 0.3, 0.85, -0.06, 0.06, Mat_Skin);
      Finish (Crank_M);
      --  a cat: body, head with ears, legs; the tail separately
      Start;
      Box (-0.08, 0.08, 0.12, 0.27, -0.2, 0.2, Mat_Tyre);
      Box (-0.07, 0.07, 0.22, 0.36, -0.33, -0.18, Mat_Tyre);
      Box (-0.065, -0.03, 0.36, 0.42, -0.3, -0.25, Mat_Tyre);
      Box (0.03, 0.065, 0.36, 0.42, -0.3, -0.25, Mat_Tyre);
      Box (-0.05, -0.02, 0.3, 0.32, -0.335, -0.33, Mat_Gold);  --  eyes
      Box (0.02, 0.05, 0.3, 0.32, -0.335, -0.33, Mat_Gold);
      Box (-0.07, -0.03, 0.0, 0.14, -0.17, -0.13, Mat_Tyre);
      Box (0.03, 0.07, 0.0, 0.14, -0.17, -0.13, Mat_Tyre);
      Box (-0.07, -0.03, 0.0, 0.14, 0.13, 0.17, Mat_Tyre);
      Box (0.03, 0.07, 0.0, 0.14, 0.13, 0.17, Mat_Tyre);
      Finish (Cat_Body);
      Start;
      Box (-0.02, 0.02, 0.2, 0.5, 0.18, 0.22, Mat_Tyre);
      Finish (Cat_Tail);
      --  a pigeon (grey, from the white fur material darkened: use plaster
      --  grey via the stone of the curbs)
      Start;
      Box (-0.06, 0.06, 0.05, 0.17, -0.12, 0.14, 2.0);
      Box (-0.04, 0.04, 0.15, 0.25, -0.2, -0.1, 2.0);
      Box (-0.01, 0.01, 0.18, 0.2, -0.24, -0.2, Mat_Gold);     --  beak
      Box (-0.02, 0.02, 0.0, 0.05, -0.02, 0.02, Mat_Taillight); --  red feet
      Finish (Bird_Body);
      Start;
      Box (-0.28, -0.04, 0.13, 0.15, -0.08, 0.1, 2.0);
      Finish (Wing_L);
      Start;
      Box (0.04, 0.28, 0.13, 0.15, -0.08, 0.1, 2.0);
      Finish (Wing_R);
      Start;
      Box (-1.0, 1.0, -1.0, 1.0, -1.0, 1.0, Mat_Fur);
      Finish (Ball_M);
      --  a pigeon on the ground, wings folded: slate grey (the paint), a
      --  darker tail, the neck a little green
      Start;
      Box (-0.055, 0.055, 0.05, 0.15, -0.1, 0.12, Mat_Paint, Top_Inset_X => 0.01);
      Box (-0.065, 0.065, 0.08, 0.15, -0.04, 0.15, Mat_Paint);                   --  the folded wings
      Box (-0.035, 0.035, 0.08, 0.11, 0.12, 0.22, Mat_Tyre);                     --  tail
      Box (-0.035, 0.035, 0.13, 0.21, -0.15, -0.08, Mat_Paint);                  --  neck
      Box (-0.03, 0.03, 0.19, 0.25, -0.2, -0.12, Mat_Paint);                     --  head
      Box (-0.008, 0.008, 0.21, 0.225, -0.235, -0.2, Mat_Gold);                  --  beak
      Box (-0.025, 0.025, 0.0, 0.05, -0.02, 0.02, Mat_Taillight);                --  red feet
      Finish (Sitting_M);
   end Create;

   procedure Set_Locations (Loc : Locations) is
   begin
      L := Loc;
   end Set_Locations;

   procedure Colours (Cloth, Skin, Legs : Vec3) is
   begin
      if L.Cloth >= 0 then
         Shaders.Set (L.Cloth, Cloth);
         Shaders.Set (L.Skin, Skin);
         Shaders.Set (L.Legs, Legs);
      end if;
   end Colours;

   procedure Person (M : Mat4; Cloth, Skin, Legs : Vec3;
                     Stride : Float := 0.0; Hat : Hat_Kind := None;
                     Hat_Colour : Vec3 := (1.0, 1.0, 1.0);
                     Prop : Prop_Kind := Nothing; Arm_Up : Float := 0.0) is
   begin
      Colours (Cloth, Skin, Legs);
      Shaders.Set (L.Model, M);
      Meshes.Draw (Torso);
      Shaders.Set (L.Model, M * Translation ((0.0, Hip, 0.0)) * Rotation_X (Stride)
                   * Translation ((0.0, -Hip, 0.0)));
      Meshes.Draw (Leg_L);
      Shaders.Set (L.Model, M * Translation ((0.0, Hip, 0.0)) * Rotation_X (-Stride)
                   * Translation ((0.0, -Hip, 0.0)));
      Meshes.Draw (Leg_R);
      Shaders.Set (L.Model, M * Translation ((0.0, 1.42, 0.0))
                   * Rotation_X (Arm_Up + (if Arm_Up = 0.0 then -0.5 * Stride else 0.0)));
      Meshes.Draw (Arm_R);
      if Prop /= Nothing then
         Colours ((0.75, 0.08, 0.08), Skin, Legs);
         Shaders.Set (L.Model, M);
         case Prop is
            when Guitar => Meshes.Draw (Guitar_M);
            when Accordion => Meshes.Draw (Accordion_M);
            when Drum => Meshes.Draw (Drum_M);
            when Violin => Meshes.Draw (Violin_M);
            when Nothing => null;
         end case;
      end if;
      if Hat /= None then
         Colours (Hat_Colour, Skin, Legs);
         Shaders.Set (L.Model, M);
         case Hat is
            when Kepi => Meshes.Draw (Kepi_M);
            when Helmet => Meshes.Draw (Helmet_M);
            when Cap => Meshes.Draw (Cap_M);
            when None => null;
         end case;
      end if;
   end Person;

   procedure Seated (M : Mat4; Cloth, Skin, Legs : Vec3; Seat, Lean : Float) is
      Out_To : constant Float :=
        Ada.Numerics.Elementary_Functions.Arccos (Float'Min (1.0, Seat / Hip));
      At_Hip : constant Mat4 := M * Translation ((0.0, Seat, 0.05));
      Body_M : constant Mat4 := At_Hip * Rotation_X (Lean) * Translation ((0.0, -Hip, 0.0));
   begin
      Colours (Cloth, Skin, Legs);
      Shaders.Set (L.Model, Body_M);
      Meshes.Draw (Torso);
      Shaders.Set (L.Model, Body_M * Translation ((0.0, 1.42, 0.0)) * Rotation_X (0.7));
      Meshes.Draw (Arm_R);
      Shaders.Set (L.Model, At_Hip * Rotation_X (Out_To) * Translation ((0.0, -Hip, 0.0)));
      Meshes.Draw (Leg_L);
      Shaders.Set (L.Model, At_Hip * Rotation_X (Out_To + 0.06) * Translation ((0.0, -Hip, 0.0)));
      Meshes.Draw (Leg_R);
   end Seated;

   procedure Cyclist (M : Mat4; Jersey, Skin : Vec3; Pedal : Float) is
   begin
      Colours (Jersey, Skin, Skin);
      Shaders.Set (L.Model, M);
      Meshes.Draw (Bike_M);
      Meshes.Draw (Rider_M);
      Shaders.Set (L.Model, M * Translation ((0.0, 0.58, 0.05)) * Rotation_X (Pedal)
                   * Translation ((0.0, -0.58, -0.05)));
      Meshes.Draw (Crank_M);
   end Cyclist;

   procedure Cat (M : Mat4; Walk : Float; Sitting : Boolean) is
   begin
      Shaders.Set (L.Model, (if Sitting then M * Rotation_X (0.45) else M)
                   * Translation ((0.0, 0.03 * abs Walk, 0.0)));
      Meshes.Draw (Cat_Body);
      Shaders.Set (L.Model, M * Translation ((0.0, 0.25, 0.2)) * Rotation_Z (0.4 * Walk)
                   * Translation ((0.0, -0.25, -0.2)));
      Meshes.Draw (Cat_Tail);
   end Cat;

   procedure Pigeon_On_Ground (M : Mat4; Peck : Float) is
   begin
      --  the head goes down to peck: the whole bird tips forward a little
      Shaders.Set (L.Model, M * Translation ((0.0, 0.05, 0.0)) * Rotation_X (-Peck)
                   * Translation ((0.0, -0.05, 0.0)));
      Meshes.Draw (Sitting_M);
   end Pigeon_On_Ground;

   procedure Pigeon (M : Mat4; Flap : Float) is
   begin
      Shaders.Set (L.Model, M);
      Meshes.Draw (Bird_Body);
      Shaders.Set (L.Model, M * Translation ((-0.04, 0.14, 0.0)) * Rotation_Z (Flap)
                   * Translation ((0.04, -0.14, 0.0)));
      Meshes.Draw (Wing_L);
      Shaders.Set (L.Model, M * Translation ((0.04, 0.14, 0.0)) * Rotation_Z (-Flap)
                   * Translation ((-0.04, -0.14, 0.0)));
      Meshes.Draw (Wing_R);
   end Pigeon;

   procedure Ball (Where : Vec3; Radius : Float) is
      M : Mat4 := Translation (Where);
   begin
      M (0) := Radius;
      M (5) := Radius;
      M (10) := Radius;
      Shaders.Set (L.Model, M);
      Meshes.Draw (Ball_M);
   end Ball;

end Figures;
