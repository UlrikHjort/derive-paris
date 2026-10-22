--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Birds by day: flocks wheeling over the rooftops, gulls gliding along
--  the Seine, and sparrows hopping on the pavements that flutter up when
--  you come close.

with GL;
with Math3D;

package Birds is

   procedure Update (Dt : Float; Focus : Math3D.Vec3; Hour : Float; Near : Math3D.Vec3);
   --  Focus: where the camera is about; Near: you (the car or on foot)

   procedure Draw (Model, Paint : GL.GLint; Cam : Math3D.Vec3);

end Birds;
