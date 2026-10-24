--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Synthesised sound: engine (car or plane), tyres and wind, and the city
--  around you (distant traffic, passing cars, horns, birds, rain, church
--  bells striking the hours).  Mixed in a background task and played
--  through PulseAudio; without a sound server the game is simply silent.

package Sound is

   type Mode_Kind is (Driving, Flying, Visiting, Walking);

   --  A vehicle nearby, as heard by the listener
   type Voice is record
      Id     : Natural := 0;     --  0: silent; the same vehicle keeps its Id
      Dist   : Float := 100.0;   --  metres
      Pan    : Float := 0.0;     --  -1 left .. 1 right
      Radial : Float := 0.0;     --  m/s, > 0 moving away (Doppler)
      Speed  : Float := 0.0;     --  m/s
      Kind   : Natural := 0;     --  0 car, 1 scooter, 2 motorbike
   end record;
   type Voice_List is array (1 .. 8) of Voice;

   type Params is record
      Mode     : Mode_Kind := Driving;
      Rpm      : Float := 850.0;   --  engine revolutions per minute
      Load     : Float := 0.0;     --  throttle 0 .. 1
      Speed    : Float := 0.0;     --  m/s
      Altitude : Float := 0.0;     --  m above the street (ear height)
      Rain     : Float := 0.0;     --  0 .. 1
      Night    : Float := 0.0;     --  0 .. 1
      Traffic  : Float := 0.0;     --  0 .. 1, how close the nearest car is
      Horn     : Boolean := False; --  the player's horn
      Engine_Off : Boolean := False;   --  a wrecked car
      Two_Stroke : Boolean := False;   --  on the scooter: its buzz, not the car's hum
      Bike     : Boolean := False;   --  on a Vélib': the freewheel ticking, a bell for a horn
      Squeal   : Float := 0.0;     --  0 .. 1: tyres sliding or spinning
      Church   : Float := 0.0;     --  0 .. 1: how near Saint-Sulpice is
      Jingle   : Float := 0.0;     --  0 .. 1: sleigh bells going by
      Jingle_Pan : Float := 0.0;
      Jets     : Float := 0.0;     --  0 .. 1: jets roaring over
      Crowd    : Float := 0.0;     --  0 .. 1: a cheering crowd
      Busker   : Natural := 0;     --  a street musician's tune (0: none)
      Busker_Level, Busker_Pan : Float := 0.0;
      Alien    : Float := 0.0;     --  0 .. 1: the UFO's whine
      Alien_Pan : Float := 0.0;
      Voices   : Voice_List;       --  the traffic around you
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

   procedure Peal (Seconds : Float);
   --  Saint-Sulpice rings all its bells (swinging, out of step)

   function Pealing return Boolean;

   procedure Boom (Delay_S, Loudness : Float; Big : Boolean);
   --  A firework bursting: heard Delay_S seconds from now (sound is slow)

   procedure Thunder (Delay_S, Loudness : Float; Close : Boolean);
   --  Thunder after a lightning strike (sound travels 343 m a second)

   procedure Wooo (Loudness, Pan : Float);
   --  A ghost going by

   procedure Ho_Ho (Loudness, Pan : Float);
   --  Father Christmas laughs

   type Effect_Kind is (Meow, Flutter, Thud, Organ, Beep, Go_Beep, Chime);
   procedure Effect (Kind : Effect_Kind; Loudness, Pan : Float);
   --  Little one-off sounds: a cat, pigeons taking off, a snowball on the
   --  car, the Phantom's organ

   procedure Shutter;
   --  A camera click (a photo was taken)

   procedure Start_Capture (File_Name : String);
   --  Also write what is played to a raw file (16 bit stereo, 44.1 kHz)

   procedure Stop_Capture;
   --  Close that file (waits for the mixer, a few milliseconds)

   function Playing return Boolean;
   --  A sound server was found and sound is being played

   procedure Toggle_Mute;
   function Muted return Boolean;

end Sound;
