--  Synthesised sound: engine (car or plane), tyres and wind, and the city
--  around you (distant traffic, passing cars, horns, birds, rain, church
--  bells striking the hours).  Mixed in a background task and played
--  through PulseAudio; without a sound server the game is simply silent.

package Sound is

   type Mode_Kind is (Driving, Flying, Visiting);

   type Params is record
      Mode     : Mode_Kind := Driving;
      Rpm      : Float := 850.0;   --  engine revolutions per minute
      Load     : Float := 0.0;     --  throttle 0 .. 1
      Speed    : Float := 0.0;     --  m/s
      Altitude : Float := 0.0;     --  m above the street (ear height)
      Rain     : Float := 0.0;     --  0 .. 1
      Night    : Float := 0.0;     --  0 .. 1
      Traffic  : Float := 0.0;     --  0 .. 1, how close the nearest car is
   end record;

   procedure Start;
   --  Open the sound device and start mixing

   procedure Stop;
   --  Stop mixing and close the device (call before the program ends)

   procedure Set (P : Params);

   procedure Bells (Strikes : Positive; Loudness : Float);
   --  A church bell striking the hour; Loudness 0 .. 1 (distance)

   procedure Set_Volume (V : Float);
   --  Master volume 0 .. 1

   procedure Toggle_Mute;
   function Muted return Boolean;

end Sound;
