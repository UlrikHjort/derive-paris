--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Little people and animals for the surprises: soldiers, cyclists,
--  musicians, children, a cat and pigeons.  Drawn with the world program;
--  the colours go into the paint, skin and trouser uniforms.

with GL;
with Math3D;

package Figures is

   use type GL.GLint;

   type Locations is record
      Model, Cloth, Skin, Legs : GL.GLint := -1;
   end record;

   procedure Create;
   procedure Set_Locations (Loc : Locations);

   type Hat_Kind is (None, Kepi, Helmet, Cap);
   type Prop_Kind is (Nothing, Guitar, Accordion, Drum, Violin);

   procedure Person (M : Math3D.Mat4; Cloth, Skin, Legs : Math3D.Vec3;
                     Stride : Float := 0.0; Hat : Hat_Kind := None;
                     Hat_Colour : Math3D.Vec3 := (1.0, 1.0, 1.0);
                     Prop : Prop_Kind := Nothing; Arm_Up : Float := 0.0);
   --  A standing or walking figure (Stride: leg swing angle); Arm_Up raises
   --  the right arm (throwing)

   procedure Cyclist (M : Math3D.Mat4; Jersey, Skin : Math3D.Vec3; Pedal : Float);
   --  A racing cyclist on his bike, pedalling

   procedure Cat (M : Math3D.Mat4; Walk : Float; Sitting : Boolean);
   procedure Pigeon (M : Math3D.Mat4; Flap : Float);
   procedure Pigeon_On_Ground (M : Math3D.Mat4; Peck : Float);
   --  Wings folded, slate grey in the paint (Cloth); Peck tips it forward
   --  Flap: wing angle (0: folded)

   procedure Ball (Where : Math3D.Vec3; Radius : Float);
   --  A snowball

end Figures;
