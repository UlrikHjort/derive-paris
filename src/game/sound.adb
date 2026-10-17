--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Environment_Variables;
with Ada.Numerics;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Ada.Numerics.Elementary_Functions;
with Interfaces;
with Interfaces.C;
with Interfaces.C.Strings;
with System;

package body Sound is

   use Ada.Numerics.Elementary_Functions;
   use Interfaces;
   use type C.int;

   type Sample_Array is array (Natural range <>) of aliased Integer_16
     with Convention => C;

   Rate   : constant := 44_100;
   Frames : constant := 1024;            --  per write, about 23 ms
   Two_Pi : constant := 2.0 * Ada.Numerics.Pi;

   ---------------------------------------------------------------------------
   --  PulseAudio simple API
   ---------------------------------------------------------------------------

   type Sample_Spec is record
      Format   : C.int;
      Rate     : Unsigned_32;
      Channels : Unsigned_8;
   end record
     with Convention => C;

   type Buffer_Attr is record
      Max_Length, T_Length, Pre_Buf, Min_Req, Frag_Size : Unsigned_32;
   end record
     with Convention => C;

   PA_Stream_Playback : constant C.int := 1;
   PA_Sample_S16LE    : constant C.int := 3;

   function PA_New
     (Server : C.Strings.chars_ptr; Name : C.Strings.chars_ptr; Dir : C.int;
      Dev : C.Strings.chars_ptr; Stream_Name : C.Strings.chars_ptr;
      Spec : access Sample_Spec; Map : System.Address; Attr : access Buffer_Attr;
      Error : access C.int) return System.Address
     with Import, Convention => C, External_Name => "pa_simple_new";

   function PA_Write (S : System.Address; Data : System.Address; Bytes : C.size_t;
                      Error : access C.int) return C.int
     with Import, Convention => C, External_Name => "pa_simple_write";

   procedure PA_Free (S : System.Address)
     with Import, Convention => C, External_Name => "pa_simple_free";

   ---------------------------------------------------------------------------
   type Effect_List is array (1 .. 8) of Effect_Kind;
   type Effect_Values is array (1 .. 8) of Float;

   --  Shared state between the game and the mixer
   ---------------------------------------------------------------------------

   protected Shared is
      procedure Put (P : Params);
      function Get return Params;
      procedure Ring (Strikes : Positive; Loudness : Float);
      procedure Take_Bells (Strikes : out Natural; Loudness : out Float);
      procedure Request_Stop;
      function Stopping return Boolean;
      procedure Flip_Mute;
      function Is_Muted return Boolean;
      procedure Put_Volume (V : Float);
      procedure Set_Capture (Name : String);
      function Capture_Name return String;
      procedure Set_Capture_Open (Open : Boolean);
      function Capture_Open return Boolean;
      procedure Set_Playing;
      procedure Click;
      procedure Put_Effect (K : Effect_Kind; Loud, Pan : Float);
      procedure Take_Effect (Any : out Boolean; K : out Effect_Kind; Loud, Pan : out Float);
      procedure Put_Laugh (Loudness, Pan : Float);
      procedure Put_Wooo (Loudness, Pan : Float);
      procedure Put_Thunder (Delay_S, Loudness : Float; Close : Boolean);
      procedure Take_Thunder (Any : out Boolean; Delay_S, Loudness : out Float;
                              Close : out Boolean);
      procedure Take_Wooo (Any : out Boolean; Loudness, Pan : out Float);
      procedure Take_Laugh (Any : out Boolean; Loudness, Pan : out Float);
      procedure Put_Peal (Seconds : Float);
      procedure Take_Peal (Seconds : out Float);
      procedure Set_Pealing (On : Boolean);
      function Is_Pealing return Boolean;
      procedure Put_Boom (Delay_S, Loudness : Float; Big : Boolean);
      procedure Take_Boom (Any : out Boolean; Delay_S, Loudness : out Float; Big : out Boolean);
      procedure Take_Click (Any : out Boolean);
      function Is_Playing return Boolean;
      function Volume return Float;
   private
      Current   : Params;
      Bell_Count : Natural := 0;
      Bell_Loud  : Float := 0.0;
      Stop_Flag : Boolean := False;
      Mute      : Boolean := False;
      Cap_Name  : Ada.Strings.Unbounded.Unbounded_String;
      Cap_Open  : Boolean := False;
      Play_On   : Boolean := False;
      Clicks    : Natural := 0;
      Effects   : Effect_List := (others => Meow);
      Effect_Loud, Effect_Pan : Effect_Values := (others => 0.0);
      Effect_Count : Natural := 0;
      Laugh_Ask : Boolean := False;
      Wooo_Ask  : Boolean := False;
      Thunder_Ask : Boolean := False;
      Thunder_Delay, Thunder_Loud : Float := 0.0;
      Thunder_Close : Boolean := False;
      Wooo_Loud, Wooo_Pan : Float := 0.0;
      Laugh_Loud, Laugh_Pan : Float := 0.0;
      Peal_Ask  : Float := 0.0;
      Peal_On   : Boolean := False;
      Boom_Wait : Boolean := False;
      Boom_Delay, Boom_Loud : Float := 0.0;
      Boom_Big  : Boolean := False;
      Master    : Float := 0.8;
   end Shared;

   protected body Shared is
      procedure Put (P : Params) is
      begin
         Current := P;
      end Put;
      function Get return Params is (Current);
      procedure Ring (Strikes : Positive; Loudness : Float) is
      begin
         Bell_Count := Strikes;
         Bell_Loud := Loudness;
      end Ring;
      procedure Take_Bells (Strikes : out Natural; Loudness : out Float) is
      begin
         Strikes := Bell_Count;
         Loudness := Bell_Loud;
         Bell_Count := 0;
      end Take_Bells;
      procedure Request_Stop is
      begin
         Stop_Flag := True;
      end Request_Stop;
      function Stopping return Boolean is (Stop_Flag);
      procedure Flip_Mute is
      begin
         Mute := not Mute;
      end Flip_Mute;
      function Is_Muted return Boolean is (Mute);
      procedure Set_Capture (Name : String) is
      begin
         Cap_Name := Ada.Strings.Unbounded.To_Unbounded_String (Name);
      end Set_Capture;
      function Capture_Name return String is (Ada.Strings.Unbounded.To_String (Cap_Name));
      procedure Set_Capture_Open (Open : Boolean) is
      begin
         Cap_Open := Open;
      end Set_Capture_Open;
      function Capture_Open return Boolean is (Cap_Open);
      procedure Set_Playing is
      begin
         Play_On := True;
      end Set_Playing;
      function Is_Playing return Boolean is (Play_On);
      procedure Put_Boom (Delay_S, Loudness : Float; Big : Boolean) is
      begin
         Boom_Wait := True;
         Boom_Delay := Delay_S;
         Boom_Loud := Float'Max (Boom_Loud, Loudness);
         Boom_Big := Big;
      end Put_Boom;
      procedure Take_Boom (Any : out Boolean; Delay_S, Loudness : out Float; Big : out Boolean) is
      begin
         Any := Boom_Wait;
         Delay_S := Boom_Delay;
         Loudness := Boom_Loud;
         Big := Boom_Big;
         Boom_Wait := False;
         Boom_Loud := 0.0;
      end Take_Boom;
      procedure Put_Peal (Seconds : Float) is
      begin
         Peal_Ask := Seconds;
         Peal_On := True;
      end Put_Peal;
      procedure Take_Peal (Seconds : out Float) is
      begin
         Seconds := Peal_Ask;
         Peal_Ask := 0.0;
      end Take_Peal;
      procedure Set_Pealing (On : Boolean) is
      begin
         Peal_On := On;
      end Set_Pealing;
      function Is_Pealing return Boolean is (Peal_On);
      procedure Put_Thunder (Delay_S, Loudness : Float; Close : Boolean) is
      begin
         Thunder_Ask := True;
         Thunder_Delay := Delay_S;
         Thunder_Loud := Loudness;
         Thunder_Close := Close;
      end Put_Thunder;
      procedure Take_Thunder (Any : out Boolean; Delay_S, Loudness : out Float;
                              Close : out Boolean) is
      begin
         Any := Thunder_Ask;
         Delay_S := Thunder_Delay;
         Loudness := Thunder_Loud;
         Close := Thunder_Close;
         Thunder_Ask := False;
      end Take_Thunder;
      procedure Put_Wooo (Loudness, Pan : Float) is
      begin
         Wooo_Ask := True;
         Wooo_Loud := Loudness;
         Wooo_Pan := Pan;
      end Put_Wooo;
      procedure Take_Wooo (Any : out Boolean; Loudness, Pan : out Float) is
      begin
         Any := Wooo_Ask;
         Loudness := Wooo_Loud;
         Pan := Wooo_Pan;
         Wooo_Ask := False;
      end Take_Wooo;
      procedure Put_Laugh (Loudness, Pan : Float) is
      begin
         Laugh_Ask := True;
         Laugh_Loud := Loudness;
         Laugh_Pan := Pan;
      end Put_Laugh;
      procedure Take_Laugh (Any : out Boolean; Loudness, Pan : out Float) is
      begin
         Any := Laugh_Ask;
         Loudness := Laugh_Loud;
         Pan := Laugh_Pan;
         Laugh_Ask := False;
      end Take_Laugh;
      procedure Put_Effect (K : Effect_Kind; Loud, Pan : Float) is
      begin
         if Effect_Count < Effects'Last then
            Effect_Count := Effect_Count + 1;
            Effects (Effect_Count) := K;
            Effect_Loud (Effect_Count) := Loud;
            Effect_Pan (Effect_Count) := Pan;
         end if;
      end Put_Effect;
      procedure Take_Effect (Any : out Boolean; K : out Effect_Kind; Loud, Pan : out Float) is
      begin
         Any := Effect_Count > 0;
         if Any then
            K := Effects (Effect_Count);
            Loud := Effect_Loud (Effect_Count);
            Pan := Effect_Pan (Effect_Count);
            Effect_Count := Effect_Count - 1;
         else
            K := Meow;
            Loud := 0.0;
            Pan := 0.0;
         end if;
      end Take_Effect;
      procedure Click is
      begin
         Clicks := Clicks + 1;
      end Click;
      procedure Take_Click (Any : out Boolean) is
      begin
         Any := Clicks > 0;
         Clicks := 0;
      end Take_Click;
      procedure Put_Volume (V : Float) is
      begin
         Master := Float'Max (0.0, Float'Min (1.0, V));
      end Put_Volume;
      function Volume return Float is (Master);
   end Shared;

   procedure Set (P : Params) is
   begin
      Shared.Put (P);
   end Set;

   procedure Bells (Strikes : Positive; Loudness : Float) is
   begin
      Shared.Ring (Strikes, Loudness);
   end Bells;

   procedure Set_Volume (V : Float) is
   begin
      Shared.Put_Volume (V);
   end Set_Volume;

   procedure Toggle_Mute is
   begin
      Shared.Flip_Mute;
   end Toggle_Mute;

   function Muted return Boolean is (Shared.Is_Muted);

   ---------------------------------------------------------------------------
   --  Synthesis
   ---------------------------------------------------------------------------

   --  Fast white noise
   Seed : Unsigned_32 := 22_222;
   function Noise return Float is
   begin
      Seed := Seed * 1_664_525 + 1_013_904_223;
      return Float (Seed) / 2147483648.0 - 1.0;
   end Noise;

   function Uniform return Float is (0.5 * (Noise + 1.0));

   --  One-pole low-pass filter state
   type Lowpass is record
      Y : Float := 0.0;
   end record;

   function Step (F : in out Lowpass; X, Cutoff : Float) return Float is
      A : constant Float := 1.0 - Exp (-Two_Pi * Cutoff / Float (Rate));
   begin
      F.Y := F.Y + A * (X - F.Y);
      return F.Y;
   end Step;

   --  A sound event with an envelope: passing car, horn, bird, bell stroke
   type Event_Kind is (None, Passing, Horn, Bird, Bell, Click, Boom, Crackle, Jingle, Laugh, Ghost, Thunder,
                       Cat, Wings, Snowball, Pipe, Note);

   type Event is record
      Kind     : Event_Kind := None;
      T, Dur   : Float := 0.0;      --  seconds
      Volume   : Float := 0.0;
      Pan      : Float := 0.0;      --  -1 left .. 1 right
      Freq     : Float := 0.0;
      Phase    : Float := 0.0;
      Filter   : Lowpass;
      --  passing cars: closest distance (m), speed (m/s), direction
      Near     : Float := 8.0;
      Speed    : Float := 10.0;
      Dir      : Float := 1.0;
      Filter2, Filter3 : Lowpass;
      --  two resonators (a voice's formants)
      R1a, R1b, R2a, R2b : Float := 0.0;
   end record;

   --  A two-pole resonance at F Hz, bandwidth B Hz, scaled so that a
   --  tone at F comes out about as loud as it went in
   function Resonate (X : Float; F, B : Float; Y1, Y2 : in out Float) return Float is
      R  : constant Float := Exp (-Ada.Numerics.Pi * B / Float (Rate));
      W  : constant Float := Two_Pi * F / Float (Rate);
      A1 : constant Float := 2.0 * R * Cos (W);
      Y  : constant Float := (1.0 - R) * 2.0 * Sin (W) * X + A1 * Y1 - R * R * Y2;
   begin
      Y2 := Y1;
      Y1 := Y;
      return Y;
   end Resonate;

   Events : array (1 .. 48) of Event;

   procedure Add (E : Event) is
   begin
      for Slot of Events loop
         if Slot.Kind = None then
            Slot := E;
            return;
         end if;
      end loop;
   end Add;

   Bell_Partials : constant array (1 .. 6) of Float := (0.5, 1.0, 1.19, 1.5, 2.0, 2.66);

   --  One sample of an event (stereo)
   procedure Play (E : in out Event; L, R : in out Float) is
      Dt  : constant Float := 1.0 / Float (Rate);
      Env : Float;
      S   : Float := 0.0;
   begin
      E.T := E.T + Dt;
      if E.T >= E.Dur then
         E.Kind := None;
         return;
      end if;
      case E.Kind is
         when Passing =>
            --  a car driving past: X is its position along the street,
            --  loudness follows the distance, the engine note drops as it
            --  passes (Doppler) and the sound moves from one side to the other
            declare
               X      : constant Float := E.Speed * (E.T - 0.5 * E.Dur);
               R      : constant Float := Sqrt (E.Near * E.Near + X * X);
               Radial : constant Float := E.Speed * X / R;   --  > 0: going away
               Shift  : constant Float := 343.0 / (343.0 + Radial);
               Tyres  : Float;
               Hum    : Float;
            begin
               Env := (E.Near / R) ** 1.6;
               E.Pan := E.Dir * X / R;
               --  tyre hiss: band of noise, brighter when close
               Tyres := Step (E.Filter, Noise, 900.0 + 900.0 * Env);
               Tyres := Tyres - Step (E.Filter2, Tyres, 180.0);
               E.Phase := E.Phase + E.Freq * Shift / Float (Rate);
               E.Phase := E.Phase - Float'Floor (E.Phase);
               if E.Freq > 90.0 then
                  --  a scooter: thin, buzzing two-stroke whine
                  Hum := (if E.Phase < 0.3 then 1.0 else -0.43);
                  Hum := Step (E.Filter3, Hum, 900.0);
                  S := 1.2 * Tyres + 0.9 * Hum;
               else
                  Hum := Sin (Two_Pi * E.Phase) + 0.35 * Sin (2.0 * Two_Pi * E.Phase);
                  Hum := Step (E.Filter3, Hum, 200.0);
                  S := 2.6 * Tyres + 0.5 * Hum;
               end if;
            end;
         when Horn =>
            Env := (if E.T < 0.03 then E.T / 0.03 else 1.0);
            E.Phase := E.Phase + E.Freq * Dt;
            S := (if E.Phase - Float'Floor (E.Phase) < 0.5 then 1.0 else -1.0)
              + (if 1.26 * E.Phase - Float'Floor (1.26 * E.Phase) < 0.5 then 1.0 else -1.0);
            S := Step (E.Filter, 0.5 * S, 1200.0);
         when Bird =>
            --  a quick chirp sweeping upwards
            Env := Sin (Ada.Numerics.Pi * E.T / E.Dur);
            E.Phase := E.Phase + (E.Freq * (1.0 + 0.6 * E.T / E.Dur)) * Dt;
            S := Sin (Two_Pi * E.Phase);
         when Bell =>
            Env := 1.0;
            --  big (low) bells ring on longer than small ones; the hum
            --  under the note is quieter and fades with it, so the tail
            --  stays clear instead of sinking into a drone
            for K in Bell_Partials'Range loop
               S := S + Sin (Two_Pi * E.Freq * Bell_Partials (K) * E.T)
                 * Exp (-E.T * (0.35 + 0.45 * Float (Integer'Max (K, 2)))
                        * Float'Max (0.6, E.Freq / 440.0))
                 * (if K = 1 then 0.35 else 1.0 / Float (K - 1));
            end loop;
            S := S * (if E.T < 0.005 then E.T / 0.005 else 1.0);
         when Boom =>
            --  a deep thump that rolls away
            Env := Exp (-E.T * (if E.Freq > 0.0 then 5.0 else 9.0))
              * (if E.T < 0.004 then E.T / 0.004 else 1.0);
            S := Step (E.Filter2, Step (E.Filter, Noise, 160.0), 120.0) * 6.0;
         when Crackle =>
            --  glittering pops after a big burst
            Env := (1.0 - E.T / E.Dur);
            S := (if Uniform < 0.004 then 3.0 * Noise else 0.0);
            S := S - Step (E.Filter, S, 1500.0);
         when Jingle =>
            --  a little sleigh bell: bright, inharmonic, quickly gone
            Env := Exp (-E.T * 22.0);
            S := Sin (Two_Pi * E.Freq * E.T) + 0.6 * Sin (Two_Pi * E.Freq * 1.47 * E.T)
              + 0.4 * Sin (Two_Pi * E.Freq * 2.09 * E.T);
         when Laugh =>
            --  "Ho, ho, ho!": three deep 'o' sounds, each with a breathy h
            declare
               N     : constant Float := Float'Floor (E.T / 0.42);
               Local : constant Float := E.T - N * 0.42;
               Pitch : constant Float := 118.0 - 9.0 * N - 25.0 * Local;
               Src   : Float;
            begin
               if Local > 0.3 or else N > 2.0 then
                  Env := 0.0;
                  S := 0.0;
               else
                  Env := Float'Min (1.0, Local / 0.03) * (1.0 - Local / 0.3) ** 0.5;
                  E.Phase := E.Phase + Pitch / Float (Rate);
                  E.Phase := E.Phase - Float'Floor (E.Phase);
                  Src := (if Local < 0.05 then 0.6 * Noise else 2.0 * E.Phase - 1.0 + 0.1 * Noise);
                  S := 2.2 * Resonate (Src, 470.0, 90.0, E.R1a, E.R1b)
                    + 1.3 * Resonate (Src, 820.0, 110.0, E.R2a, E.R2b);
               end if;
            end;
         when Cat =>
            --  "mi-aow": rising then falling, the vowel opening from i to a
            declare
               F     : constant Float := E.T / E.Dur;
               Pitch : constant Float := 520.0 + 260.0 * Sin (Ada.Numerics.Pi * F) - 120.0 * F;
               F1    : constant Float := 500.0 + 500.0 * Sin (Ada.Numerics.Pi * Float'Min (1.0, F * 1.3));
               Src   : Float;
            begin
               Env := Sin (Ada.Numerics.Pi * F) ** 0.7;
               E.Phase := E.Phase + Pitch / Float (Rate);
               E.Phase := E.Phase - Float'Floor (E.Phase);
               Src := 2.0 * E.Phase - 1.0;
               S := 1.6 * Resonate (Src, F1, 150.0, E.R1a, E.R1b)
                 + 0.9 * Resonate (Src, 2.2 * F1, 220.0, E.R2a, E.R2b);
            end;
         when Wings =>
            --  a flock clattering up: bursts of noise at the wing beat
            Env := Exp (-E.T * 2.2) * (0.5 + 0.5 * Sin (Two_Pi * 13.0 * E.T + 3.0 * Noise));
            S := Noise - Step (E.Filter, Noise, 600.0);
            S := Step (E.Filter2, S, 4000.0) * 1.5;
         when Snowball =>
            --  a soft thump on the car
            Env := Exp (-E.T * 18.0);
            S := Step (E.Filter2, Step (E.Filter, Noise, 500.0), 300.0) * 10.0;
         when Pipe =>
            --  one organ pipe: a stack of octaves and fifths, a slow speech
            Env := Float'Min (1.0, E.T / 0.04) * Float'Min (1.0, (E.Dur - E.T) / 0.15);
            S := Sin (Two_Pi * E.Freq * E.T) + 0.6 * Sin (Two_Pi * E.Freq * 2.0 * E.T)
              + 0.45 * Sin (Two_Pi * E.Freq * 0.5 * E.T) + 0.3 * Sin (Two_Pi * E.Freq * 3.0 * E.T)
              + 0.25 * Sin (Two_Pi * E.Freq * 4.0 * E.T) + 0.15 * Sin (Two_Pi * E.Freq * 6.0 * E.T);
         when Note =>
            --  a busker's note; Speed tells the instrument
            declare
               Vib : constant Float := 1.0 + (if E.Speed = 3.0 then 0.006 * Sin (Two_Pi * 5.5 * E.T)
                                              else 0.002 * Sin (Two_Pi * 6.0 * E.T));
               Ph  : Float;
            begin
               E.Phase := E.Phase + E.Freq * Vib / Float (Rate);
               E.Phase := E.Phase - Float'Floor (E.Phase);
               Ph := E.Phase;
               if E.Speed = 1.0 then        --  accordion: two reeds, a little apart
                  Env := Float'Min (1.0, E.T / 0.03) * Float'Min (1.0, (E.Dur - E.T) / 0.05);
                  S := (if Ph < 0.3 then 1.0 else -0.43)
                    + (if Ph * 1.004 - Float'Floor (Ph * 1.004) < 0.3 then 1.0 else -0.43);
                  S := Step (E.Filter, 0.5 * S, 2500.0);
               elsif E.Speed = 2.0 then     --  guitar: plucked
                  Env := Exp (-E.T * 3.5) * Float'Min (1.0, E.T / 0.003);
                  S := Sin (Two_Pi * Ph) + 0.5 * Sin (2.0 * Two_Pi * Ph) * Exp (-E.T * 3.0)
                    + 0.3 * Sin (3.0 * Two_Pi * Ph) * Exp (-E.T * 6.0);
               elsif E.Speed = 3.0 then     --  violin: bowed
                  Env := Float'Min (1.0, E.T / 0.08) * Float'Min (1.0, (E.Dur - E.T) / 0.08);
                  S := Step (E.Filter, 2.0 * Ph - 1.0, 3000.0);
               else                          --  drum
                  Env := Exp (-E.T * (if E.Freq > 100.0 then 25.0 else 10.0));
                  S := (if E.Freq > 100.0 then Noise
                        else Sin (Two_Pi * (60.0 - 30.0 * E.T) * E.T) * 1.5);
               end if;
            end;
         when Thunder =>
            --  a crack if it was close, then a deep rumble rolling on and
            --  swelling as the sound comes back from further along the bolt
            declare
               Roll : constant Float :=
                 0.55 + 4.0 * abs Step (E.Filter3, Noise, 2.5);
               Rumble : constant Float :=
                 Step (E.Filter2, Step (E.Filter, Noise, 180.0), 110.0) * 40.0;
            begin
               Env := Float'Min (1.0, E.T / (if E.Freq > 0.0 then 0.02 else 0.35))
                 * Exp (-E.T * 0.55);
               S := Rumble * Roll;
               if E.Freq > 0.0 and then E.T < 0.4 then
                  S := S + 1.8 * Noise * Exp (-E.T * 14.0);   --  the crack
               end if;
            end;
         when Ghost =>
            --  "wooooo": a hollow voice rising and falling, wavering
            declare
               F : constant Float := E.T / E.Dur;
               Pitch : constant Float :=
                 (260.0 + 160.0 * Sin (Ada.Numerics.Pi * F) - 60.0 * F)
                 * (1.0 + 0.03 * Sin (Two_Pi * 5.5 * E.T));
               Src : Float;
            begin
               Env := Sin (Ada.Numerics.Pi * F) ** 2;
               E.Phase := E.Phase + Pitch / Float (Rate);
               E.Phase := E.Phase - Float'Floor (E.Phase);
               Src := Sin (Two_Pi * E.Phase) + 0.3 * Sin (2.0 * Two_Pi * E.Phase) + 0.15 * Noise;
               S := 2.5 * Resonate (Src, 380.0, 120.0, E.R1a, E.R1b) + 0.5 * Src;
            end;
         when Click =>
            --  a shutter: a short bright tick
            Env := Exp (-E.T * 160.0);
            S := Step (E.Filter, Noise, 4000.0) - Step (E.Filter2, Noise, 800.0) * 0.5;
         when None =>
            return;
      end case;
      S := S * Env * E.Volume;
      L := L + S * (1.0 - 0.6 * E.Pan);
      R := R + S * (1.0 + 0.6 * E.Pan);
   end Play;

   ---------------------------------------------------------------------------
   --  Reverb for the bells: the stone of the church and the houses on the
   --  square (four combs and two all-passes, a little different left and
   --  right)
   ---------------------------------------------------------------------------

   type Buffer is array (Natural range <>) of Float;
   type Comb is record
      Data   : Buffer (0 .. 4095) := (others => 0.0);
      Length : Positive;
      Pos    : Natural := 0;
      Damp   : Float := 0.0;
   end record;
   type Comb_Set is array (1 .. 4) of Comb;

   Combs_L : Comb_Set :=
     ((Length => 3437, others => <>), (Length => 3571, others => <>),
      (Length => 3299, others => <>), (Length => 3137, others => <>));
   Combs_R : Comb_Set :=
     ((Length => 3469, others => <>), (Length => 3613, others => <>),
      (Length => 3331, others => <>), (Length => 3181, others => <>));
   Passes_L : Comb_Set :=
     ((Length => 556, others => <>), (Length => 441, others => <>),
      (Length => 341, others => <>), (Length => 225, others => <>));
   Passes_R : Comb_Set :=
     ((Length => 579, others => <>), (Length => 464, others => <>),
      (Length => 364, others => <>), (Length => 248, others => <>));

   Reverb_Hp : Lowpass;

   function Reverb (X : Float; Combs, Passes : in out Comb_Set) return Float is
      Y : Float := 0.0;
      A : Float;
   begin
      for C of Combs loop
         declare
            Out_S : constant Float := C.Data (C.Pos);
         begin
            --  a long tail, the highs dying first
            C.Damp := Out_S * 0.55 + C.Damp * 0.45;
            C.Data (C.Pos) := X + C.Damp * 0.88;
            C.Pos := (C.Pos + 1) mod C.Length;
            Y := Y + Out_S;
         end;
      end loop;
      Y := Y * 0.25;
      for P of Passes (1 .. 2) loop
         A := P.Data (P.Pos);
         P.Data (P.Pos) := Y + A * 0.5;
         P.Pos := (P.Pos + 1) mod P.Length;
         Y := A - Y * 0.5;
      end loop;
      return Y;
   end Reverb;

   --  Continuous sounds
   Engine_Phase, Prop_Phase : Float := 0.0;
   type Hum_Phases is array (1 .. 4) of Float;
   Hum_Freq  : constant Hum_Phases := (47.0, 61.3, 83.1, 104.7);
   Hum_Gain  : constant Hum_Phases := (1.0, 1.0, 0.7, 0.5);
   Hum_Phase : Hum_Phases := (others => 0.0);
   Rpm_Now                  : Float := 850.0;
   Rumble, Road, Wind, Rain_F, Engine_Tone, Engine_Grit : Lowpass;
   Engine_Tone2, Road2, Wind2, Rumble2 : Lowpass;   --  second stages: softer roll-off
   Wobble   : Float := 0.0;                --  slow random drift of the revs
   Wobble_F : Lowpass;
   Rain_Hp                  : Lowpass;
   Next_Horn, Next_Bird : Float := 1.0;
   Alien_Level, Alien_Time, Alien_Phase1, Alien_Phase2 : Float := 0.0;
   Jingle_Clock : Float := 0.0;
   Bell_Wait                : Float := 0.0;
   Bells_Left               : Natural := 0;
   Bell_Volume              : Float := 0.0;

   --  A full peal: the bells swing, each at its own pace, and strike on
   --  every swing, harder one way than the other.  They start one after
   --  the other and stop the same way.
   Peal_Left  : Float := 0.0;
   Peal_Pitch : constant array (1 .. 4) of Float := (165.0, 196.0, 220.0, 262.0);
   Peal_Swing : constant array (1 .. 4) of Float := (2.5, 2.05, 1.75, 1.5);
   Peal_Next  : array (1 .. 4) of Float := (others => 0.0);
   Peal_Side  : array (1 .. 4) of Boolean := (others => False);

   ---------------------------------------------------------------------------
   --  The traffic around you: every nearby vehicle has its own engine,
   --  placed where it is, with Doppler; cars waiting at a light idle
   ---------------------------------------------------------------------------

   type Voice_State is record
      Id        : Natural := 0;
      Live      : Boolean := False;
      Gain, Pan, Shift, Rpm : Float := 0.0;
      T_Gain, T_Pan, T_Shift, T_Rpm, T_Bright, T_Tyres : Float := 0.0;
      Tyres_Now : Float := 0.0;
      Bright    : Float := 300.0;
      Kind      : Natural := 0;
      Char      : Float := 1.0;   --  each engine sounds a little different
      Phase     : Float := 0.0;
      F1, F2, T1, T2 : Lowpass;
   end record;

   Slots : array (Voice_List'Range) of Voice_State;

   function Traffic_Rpm (Kind : Natural; Speed : Float) return Float is
      Kmh : constant Float := Speed * 3.6;
      Low : Float := 0.0;
      Tops : constant array (1 .. 4) of Float :=
        (if Kind = 2 then (30.0, 55.0, 80.0, 110.0) else (18.0, 35.0, 52.0, 72.0));
   begin
      if Kind = 1 then   --  scooter: automatic, revs rise and stay
         return (if Kmh < 3.0 then 1900.0 else Float'Min (7600.0, 4200.0 + Kmh * 110.0));
      end if;
      if Kmh < 3.0 then
         return (if Kind = 2 then 1100.0 else 780.0);
      end if;
      for G in Tops'Range loop
         if Kmh < Tops (G) or else G = Tops'Last then
            return 1100.0 + Float'Min (1.0, (Kmh - Low) / (Tops (G) - Low))
              * (if Kind = 2 then 3800.0 else 2100.0);
         end if;
         Low := Tops (G);
      end loop;
      return 800.0;
   end Traffic_Rpm;

   procedure Match_Voices (List : Voice_List) is
      Wanted : array (Slots'Range) of Boolean := (others => False);
   begin
      --  vehicles already heard keep their slot
      for S of Slots loop
         S.Live := False;
      end loop;
      for I in List'Range loop
         if List (I).Id /= 0 then
            for J in Slots'Range loop
               if Slots (J).Id = List (I).Id then
                  Slots (J).Live := True;
                  Wanted (I) := True;
                  exit;
               end if;
            end loop;
         end if;
      end loop;
      --  new ones take a free slot and fade in
      for I in List'Range loop
         if List (I).Id /= 0 and then not Wanted (I) then
            for J in Slots'Range loop
               if not Slots (J).Live and then Slots (J).Gain < 0.0005 then
                  Slots (J) := (Id => List (I).Id, Live => True, Kind => List (I).Kind,
                                Char => 0.88 + 0.24 * Float ((List (I).Id * 7919) mod 101) / 100.0,
                                Pan => List (I).Pan, Shift => 1.0,
                                Rpm => Traffic_Rpm (List (I).Kind, List (I).Speed),
                                others => <>);
                  exit;
               end if;
            end loop;
         end if;
      end loop;
      --  targets
      for S of Slots loop
         S.T_Gain := 0.0;
         if S.Live then
            for V of List loop
               if V.Id = S.Id then
                  declare
                     Moving : constant Float := Float'Min (1.0, V.Speed / 8.0);
                  begin
                     S.T_Gain := (case S.Kind is
                                    when 1 => 0.22, when 2 => 0.55, when others => 0.30)
                       * (0.55 + 0.45 * Moving) / (V.Dist + 3.0);
                     S.T_Tyres := 0.5 * Float'Min (1.0, (V.Speed / 14.0) ** 2) / (V.Dist + 3.0);
                     S.T_Pan := V.Pan;
                     S.T_Shift := 343.0 / (343.0 + V.Radial);
                     S.T_Rpm := Traffic_Rpm (S.Kind, V.Speed) * S.Char;
                     --  far away the sound gets duller
                     S.T_Bright := 1.0 / (1.0 + V.Dist / 35.0);
                  end;
               end if;
            end loop;
         end if;
      end loop;
   end Match_Voices;

   --  One sample of all traffic voices
   procedure Play_Voices (L, R : in out Float) is
      K : constant Float := 0.0006;   --  parameter smoothing per sample
   begin
      for S of Slots loop
         if S.Live or else S.Gain > 0.00005 then
            S.Gain := S.Gain + (S.T_Gain - S.Gain) * K;
            S.Pan := S.Pan + (S.T_Pan - S.Pan) * K;
            S.Shift := S.Shift + (S.T_Shift - S.Shift) * K;
            S.Rpm := S.Rpm + (S.T_Rpm - S.Rpm) * K * 0.5;
            S.Bright := S.Bright + (S.T_Bright - S.Bright) * K;
            S.Tyres_Now := S.Tyres_Now + (S.T_Tyres - S.Tyres_Now) * K;
            declare
               F0 : constant Float :=
                 S.Rpm / (if S.Kind = 0 then 30.0 else 60.0) * S.Shift;
               Ph : Float;
               E  : Float;
               T  : Float;
            begin
               S.Phase := S.Phase + F0 / Float (Rate);
               S.Phase := S.Phase - Float'Floor (S.Phase);
               Ph := Two_Pi * S.Phase;
               case S.Kind is
                  when 1 =>   --  scooter: buzzing two-stroke
                     E := (if S.Phase < 0.25 then 1.0 else -0.33) + 0.3 * Noise;
                     E := Step (S.F1, E, 300.0 + 1200.0 * S.Bright);
                  when 2 =>   --  motorbike: deep, uneven pulses
                     E := (if S.Phase < 0.15 then 1.0 else -0.18)
                       + 0.6 * Sin (0.5 * Ph) + 0.2 * Noise;
                     E := Step (S.F1, E, 150.0 + 500.0 * S.Bright);
                  when others =>
                     E := Sin (Ph) + 0.5 * Sin (2.0 * Ph + 0.7) + 0.25 * Sin (3.0 * Ph + 1.9)
                       + 0.3 * Sin (0.5 * Ph) + 0.25 * Noise;
                     E := Step (S.F1, E, 90.0 + F0 * 1.5 + 250.0 * S.Bright);
               end case;
               E := Step (S.F2, E, 200.0 + F0 * 2.0 + 900.0 * S.Bright);
               --  tyres: a soft, dark rush
               T := Step (S.T1, Noise, 250.0 + 500.0 * S.Bright);
               T := T - Step (S.T2, T, 120.0);
               E := E * S.Gain + T * S.Tyres_Now;
               L := L + E * (1.0 - 0.7 * S.Pan);
               R := R + E * (1.0 + 0.7 * S.Pan);
            end;
         end if;
      end loop;
   end Play_Voices;

   --  The player's horn: two tones like a French car
   Horn_Phase1, Horn_Phase2, Horn_Level : Float := 0.0;
   Horn_F1, Horn_F2 : Lowpass;

   --  Tyre squeal: a wavering high tone with a rough edge
   Squeal_Level, Squeal_Phase : Float := 0.0;
   Squeal_Drift, Squeal_Hp, Squeal_Lp : Lowpass;

   --  Leaves the sound alone up to 0.6, then bends smoothly towards 1
   function Limit (X : Float) return Float is
     (if abs X <= 0.6 then X
      else (if X > 0.0 then 1.0 else -1.0) * (0.6 + 0.4 * Tanh ((abs X - 0.6) / 0.4)));

   Octaves : constant array (1 .. 2) of Float := (0.5, 1.0);

   ---------------------------------------------------------------------------
   --  Street musicians (Fête de la Musique): old French tunes, each on its
   --  own instrument.  Notes as (semitones from middle C, beats); a rest
   --  is -99.
   ---------------------------------------------------------------------------

   type Tune_Note is record
      Pitch : Integer;
      Beats : Float;
   end record;
   type Tune_Notes is array (Positive range <>) of Tune_Note;

   --  Frère Jacques (accordion)
   Jacques : constant Tune_Notes :=
     ((0, 1.0), (2, 1.0), (4, 1.0), (0, 1.0), (0, 1.0), (2, 1.0), (4, 1.0), (0, 1.0),
      (4, 1.0), (5, 1.0), (7, 2.0), (4, 1.0), (5, 1.0), (7, 2.0),
      (7, 0.5), (9, 0.5), (7, 0.5), (5, 0.5), (4, 1.0), (0, 1.0),
      (7, 0.5), (9, 0.5), (7, 0.5), (5, 0.5), (4, 1.0), (0, 1.0),
      (0, 1.0), (-5, 1.0), (0, 2.0), (0, 1.0), (-5, 1.0), (0, 2.0), (-99, 2.0));
   --  Au clair de la lune (guitar)
   Lune : constant Tune_Notes :=
     ((0, 1.0), (0, 1.0), (0, 1.0), (2, 1.0), (4, 2.0), (2, 2.0),
      (0, 1.0), (4, 1.0), (2, 1.0), (2, 1.0), (0, 4.0),
      (0, 1.0), (0, 1.0), (0, 1.0), (2, 1.0), (4, 2.0), (2, 2.0),
      (0, 1.0), (4, 1.0), (2, 1.0), (2, 1.0), (0, 4.0), (-99, 2.0));
   --  Sur le pont d'Avignon (violin)
   Avignon : constant Tune_Notes :=
     ((0, 1.0), (0, 1.0), (0, 2.0), (2, 1.0), (2, 1.0), (2, 2.0),
      (4, 1.0), (5, 1.0), (7, 1.0), (0, 1.0), (-1, 1.0), (-5, 1.0), (0, 2.0),
      (0, 1.0), (0, 1.0), (0, 2.0), (2, 1.0), (2, 1.0), (2, 2.0),
      (4, 1.0), (5, 1.0), (7, 1.0), (0, 1.0), (-1, 1.0), (-5, 1.0), (0, 2.0), (-99, 2.0));
   --  La Marseillaise, the first lines (accordion)
   Marseillaise : constant Tune_Notes :=
     ((-5, 0.75), (-5, 0.25), (-5, 1.0), (0, 1.0), (0, 1.0), (2, 1.0), (2, 1.0),
      (7, 1.5), (4, 0.5), (0, 0.75), (0, 0.25), (4, 0.75), (0, 0.25), (-3, 1.0),
      (5, 2.0), (2, 0.75), (-1, 0.25), (0, 3.0), (-99, 1.0),
      (0, 0.75), (2, 0.25), (4, 1.0), (4, 1.0), (4, 1.0), (5, 0.75), (4, 0.25),
      (4, 1.0), (2, 1.0), (-99, 1.0), (2, 0.75), (4, 0.25), (5, 1.0), (5, 1.0),
      (5, 1.0), (7, 0.75), (5, 0.25), (4, 3.0), (-99, 2.0));
   --  a drummer: kick and snare
   Drums : constant Tune_Notes :=
     ((-24, 1.0), (24, 1.0), (-24, 0.5), (-24, 0.5), (24, 1.0),
      (-24, 1.0), (24, 0.5), (24, 0.5), (-24, 0.5), (-24, 0.5), (24, 1.0));

   Busker_Playing : Natural := 0;
   Busker_Step    : Positive := 1;
   Busker_Wait    : Float := 0.0;

   procedure Play_Busker (P : Params; Dt : Float) is
      Tempo : constant Float := (case P.Busker is when 2 => 0.55, when 3 => 0.4,
                                                  when 5 => 0.3, when others => 0.42);
      Instrument : constant Float := (case P.Busker is when 2 => 2.0, when 3 => 3.0,
                                                       when 5 => 4.0, when others => 1.0);
      function Get (I : Positive) return Tune_Note is
        (case P.Busker is
            when 1 => Jacques (I), when 2 => Lune (I), when 3 => Avignon (I),
            when 4 => Marseillaise (I), when others => Drums (I));
      function Last return Positive is
        (case P.Busker is
            when 1 => Jacques'Last, when 2 => Lune'Last, when 3 => Avignon'Last,
            when 4 => Marseillaise'Last, when others => Drums'Last);
   begin
      if P.Busker = 0 or else P.Busker_Level < 0.01 then
         Busker_Playing := 0;
         return;
      end if;
      if P.Busker /= Busker_Playing then
         Busker_Playing := P.Busker;
         Busker_Step := 1;
         Busker_Wait := 0.0;
      end if;
      Busker_Wait := Busker_Wait - Dt;
      while Busker_Wait <= 0.0 loop
         declare
            N : constant Tune_Note := Get (Busker_Step);
            Len : constant Float := N.Beats * Tempo;
         begin
            if N.Pitch /= -99 then
               Add ((Kind => Note, Dur => Float'Max (0.12, Len * 0.92), T => Busker_Wait,
                     Volume => 0.16 * P.Busker_Level, Pan => 0.7 * P.Busker_Pan,
                     Freq => 261.63 * 2.0 ** (Float (N.Pitch) / 12.0),
                     Speed => Instrument, others => <>));
            end if;
            Busker_Wait := Busker_Wait + Len;
            Busker_Step := (if Busker_Step >= Last then 1 else Busker_Step + 1);
         end;
      end loop;
   end Play_Busker;

   --  a crowd cheering, and jets roaring over
   Crowd_F1, Crowd_F2, Crowd_Swell, Jet_F1, Jet_F2 : Lowpass;

   procedure Mix (Buffer : out Sample_Array) is
      P     : constant Params := Shared.Get;
      Dt    : constant Float := Float (Frames) / Float (Rate);
      Ear   : constant Float := Float'Max (0.0, P.Altitude);
      --  the city gets quieter and duller as you go up
      City  : constant Float := 1.0 / (1.0 + Ear / 60.0);
      Day   : constant Float := 1.0 - P.Night;
      Inside : constant Boolean := P.Mode = Visiting;
      Gain   : constant Float := Shared.Volume / 0.8;
   begin
      --  Schedule events for this buffer
      Match_Voices (P.Voices);
      declare
         Any  : Boolean;
         Wait, Loud : Float;
         Big  : Boolean;
      begin
         Shared.Take_Boom (Any, Wait, Loud, Big);
         if Any then
            Add ((Kind => Boom, Dur => 1.2, T => -Wait, Volume => 0.5 * Loud,
                  Freq => (if Big then 1.0 else 0.0), Pan => 0.4 * Noise, others => <>));
            if Big then
               Add ((Kind => Crackle, Dur => 1.5, T => -Wait - 0.4, Volume => 0.25 * Loud,
                     Pan => 0.4 * Noise, others => <>));
            end if;
         end if;
      end;
      declare
         Any : Boolean;
      begin
         Shared.Take_Click (Any);
         if Any then
            Add ((Kind => Click, Dur => 0.06, Volume => 0.5, others => <>));
            Add ((Kind => Click, Dur => 0.06, T => -0.11, Volume => 0.35, others => <>));
         end if;
      end;
      declare
         Any  : Boolean;
         K    : Effect_Kind;
         Loud, Where : Float;
      begin
         loop
            Shared.Take_Effect (Any, K, Loud, Where);
            exit when not Any;
            case K is
               when Meow =>
                  Add ((Kind => Cat, Dur => 0.75, Volume => 0.12 * Loud, Pan => 0.7 * Where,
                        others => <>));
               when Flutter =>
                  Add ((Kind => Wings, Dur => 1.3, Volume => 0.25 * Loud, Pan => 0.7 * Where,
                        others => <>));
               when Thud =>
                  Add ((Kind => Snowball, Dur => 0.3, Volume => 0.5 * Loud, Pan => 0.5 * Where,
                        others => <>));
               when Organ =>
                  --  the opening of Bach's Toccata in D minor, in octaves
                  declare
                     type Step_Rec is record
                        At_T, Hz, Len : Float;
                     end record;
                     Phrase : constant array (1 .. 11) of Step_Rec :=
                       ((0.0, 440.0, 0.13), (0.13, 392.0, 0.13), (0.26, 440.0, 1.3),
                        (1.9, 392.0, 0.13), (2.03, 349.2, 0.13), (2.16, 329.6, 0.13),
                        (2.29, 293.7, 0.13), (2.42, 277.2, 0.55), (3.0, 293.7, 2.6),
                        (3.0, 220.0, 2.6), (3.0, 174.6, 2.6));
                  begin
                     for N of Phrase loop
                        for Octave of Octaves loop
                           Add ((Kind => Pipe, Dur => N.Len, T => -N.At_T,
                                 Volume => 0.035 * Loud, Freq => N.Hz * Octave,
                                 Pan => 0.4 * Where, others => <>));
                        end loop;
                     end loop;
                  end;
            end case;
         end loop;
      end;

      Play_Busker (P, Dt);

      --  sleigh bells: shaken in the rhythm of the reindeer's gallop
      if P.Jingle > 0.01 then
         declare
            Gallop : constant Float := 0.5 + 0.5 * Sin (Jingle_Clock * 2.0 * Ada.Numerics.Pi * 2.2);
         begin
            Jingle_Clock := Jingle_Clock + Dt;
            for K in 1 .. Natural (Float'Floor (Dt * 45.0 * Gallop + Uniform)) loop
               Add ((Kind => Jingle, Dur => 0.25, T => -Dt * Uniform,
                     Volume => 0.05 * P.Jingle * (0.4 + 0.6 * Uniform),
                     Pan => 0.7 * P.Jingle_Pan, Freq => 2300.0 + 1100.0 * Uniform,
                     others => <>));
            end loop;
         end;
      end if;
      declare
         Any : Boolean;
         Loud, Where : Float;
      begin
         Shared.Take_Laugh (Any, Loud, Where);
         if Any then
            Add ((Kind => Laugh, Dur => 1.3, Volume => 0.18 * Loud, Pan => 0.7 * Where,
                  others => <>));
         end if;
         declare
            Wait  : Float;
            Close : Boolean;
         begin
            Shared.Take_Thunder (Any, Wait, Loud, Close);
            if Any then
               Add ((Kind => Thunder, Dur => 9.0, T => -Wait, Volume => 0.3 * Loud,
                     Freq => (if Close then 1.0 else 0.0), Pan => 0.3 * Noise, others => <>));
            end if;
         end;
         Shared.Take_Wooo (Any, Loud, Where);
         if Any then
            Add ((Kind => Ghost, Dur => 2.4, Volume => 0.05 * Loud, Pan => 0.7 * Where,
                  others => <>));
         end if;
      end;
      Next_Horn := Next_Horn - Dt;
      if Next_Horn <= 0.0 then
         Add ((Kind => Horn, Dur => 0.25 + 0.5 * Uniform,
               Volume => (0.015 + 0.04 * Uniform) * City, Pan => Noise,
               Freq => 330.0 + 120.0 * Uniform, others => <>));
         Next_Horn := (20.0 + 60.0 * Uniform) * (1.0 + 3.0 * P.Night);
      end if;
      Next_Bird := Next_Bird - Dt;
      if Next_Bird <= 0.0 then
         if Day > 0.5 and then P.Rain < 0.3 then
            for K in 1 .. 1 + Natural (Float'Floor (3.0 * Uniform)) loop
               Add ((Kind => Bird, Dur => 0.06 + 0.08 * Uniform,
                     T => -0.12 * Float (K - 1),
                     Volume => 0.02 + 0.025 * Uniform, Pan => Noise,
                     Freq => 2600.0 + 2200.0 * Uniform, others => <>));
            end loop;
         end if;
         Next_Bird := 1.0 + 5.0 * Uniform;
      end if;
      declare
         Strikes : Natural;
         Loud    : Float;
      begin
         Shared.Take_Bells (Strikes, Loud);
         if Strikes > 0 then
            Bells_Left := Strikes;
            Bell_Volume := Loud;
            Bell_Wait := 0.0;
         end if;
      end;
      declare
         Ask : Float;
      begin
         Shared.Take_Peal (Ask);
         if Ask > 0.0 then
            Peal_Left := Ask;
            for B in Peal_Next'Range loop
               Peal_Next (B) := 2.5 * Float (Peal_Next'Last - B);   --  small bells first
            end loop;
         end if;
      end;
      if Peal_Left > 0.0 then
         Peal_Left := Peal_Left - Dt;
         for B in Peal_Next'Range loop
            Peal_Next (B) := Peal_Next (B) - Dt;
            --  the bells stop one by one at the end, the big one last
            if Peal_Next (B) <= 0.0
              and then Peal_Left > 2.0 * Float (Peal_Next'Last - B)
            then
               Peal_Side (B) := not Peal_Side (B);
               Add ((Kind => Bell, Dur => 9.0,
                     Volume => P.Church * (0.05 + 0.019 * Float (5 - B))
                               * (if Peal_Side (B) then 1.0 else 0.7),
                     Pan => 0.3 - 0.15 * Float (B), Freq => Peal_Pitch (B), others => <>));
               Peal_Next (B) := Peal_Swing (B) * (0.97 + 0.06 * Uniform);
            end if;
         end loop;
         if Peal_Left <= 0.0 then
            Shared.Set_Pealing (False);
         end if;
      end if;
      if Bells_Left > 0 then
         Bell_Wait := Bell_Wait - Dt;
         if Bell_Wait <= 0.0 then
            Add ((Kind => Bell, Dur => 9.0, Volume => 0.19 * Bell_Volume,
                  Pan => 0.2, Freq => 294.0, others => <>));
            Bells_Left := Bells_Left - 1;
            Bell_Wait := 2.4;
         end if;
      end if;

      for I in 0 .. Frames - 1 loop
         declare
            L, R : Float := 0.0;
            S    : Float;
         begin
            --  Distant traffic: a steady low murmur of many engines far
            --  away, no swell
            S := Step (Rumble2, Step (Rumble, Noise, 110.0), 110.0) * 0.32;
            for K in Hum_Phase'Range loop
               Hum_Phase (K) := Hum_Phase (K) + Hum_Freq (K) / Float (Rate);
               Hum_Phase (K) := Hum_Phase (K) - Float'Floor (Hum_Phase (K));
               S := S + 0.012 * Hum_Gain (K) * Sin (Two_Pi * Hum_Phase (K));
            end loop;
            S := S * City * (0.35 + 0.65 * Day);
            L := L + S;
            R := R + S;
            if P.Rain > 0.01 then
               declare
                  N : constant Float := Noise;
                  H : constant Float := N - Step (Rain_Hp, N, 900.0);
               begin
                  S := Step (Rain_F, H, 6000.0) * 0.16 * P.Rain * (if Inside then 0.5 else 1.0);
                  L := L + S * (0.9 + 0.2 * Noise);
                  R := R + S * (0.9 + 0.2 * Noise);
               end;
            end if;

            case P.Mode is
               when Driving =>
                  --  Engine: a four-cylinder fires twice per revolution
                  --  Engine as heard from inside the car: a soft, low hum
                  --  whose revs drift a little, never a bright buzz
                  Rpm_Now := Rpm_Now + (P.Rpm - Rpm_Now) * 0.0004;
                  Wobble := Step (Wobble_F, Noise, 0.7);
                  declare
                     F0 : constant Float := Rpm_Now / 60.0 * 2.0 * (1.0 + 2.5 * Wobble);
                     Ph : Float;
                     E  : Float;
                  begin
                     Engine_Phase := Engine_Phase + F0 / Float (Rate);
                     Engine_Phase := Engine_Phase - Float'Floor (Engine_Phase);
                     Ph := Two_Pi * Engine_Phase;
                     E := Sin (Ph) + 0.4 * Sin (2.0 * Ph + 0.4) + 0.15 * Sin (3.0 * Ph + 1.3)
                       + 0.35 * Sin (0.5 * Ph);
                     E := E + Step (Engine_Grit, Noise, 120.0 + F0 * 1.2) * (0.5 + 0.8 * P.Load);
                     E := Step (Engine_Tone, E, 160.0 + 260.0 * P.Load + F0 * 1.2);
                     E := Step (Engine_Tone2, E, 220.0 + 300.0 * P.Load + F0 * 1.2);
                     S := E * (0.06 + 0.06 * P.Load);
                     L := L + S;
                     R := R + S;
                  end;
                  --  tyres on the road and wind, muffled by the car body
                  S := Step (Road2, Step (Road, Noise, 260.0), 260.0) * 1.6
                    * Float'Min (1.0, P.Speed / 25.0);
                  L := L + S;
                  R := R + S;
                  S := Step (Wind2, Step (Wind, Noise, 900.0), 900.0) * 0.07 * (P.Speed / 40.0) ** 2;
                  L := L + S;
                  R := R + S;
               when Flying =>
                  --  propeller blades and engine
                  declare
                     F0 : constant Float := 55.0 + 60.0 * P.Load;
                     Ph : Float;
                  begin
                     Prop_Phase := Prop_Phase + F0 / Float (Rate);
                     Prop_Phase := Prop_Phase - Float'Floor (Prop_Phase);
                     Ph := Two_Pi * Prop_Phase;
                     S := (Sin (Ph) + 0.7 * Sin (2.0 * Ph) + 0.5 * Sin (3.0 * Ph)
                           + 0.35 * Sin (5.0 * Ph)) * 0.06 * (0.6 + 0.6 * P.Load);
                     S := S + Step (Engine_Grit, Noise, 600.0) * 0.18;
                     L := L + S;
                     R := R + S;
                  end;
                  S := Step (Wind, Noise, 1500.0) * 0.5 * Float'Min (1.0, P.Speed / 50.0);
                  L := L + S;
                  R := R + S;
               when Visiting =>
                  null;
            end case;

            Play_Voices (L, R);

            if P.Crowd > 0.01 then
               declare
                  Swell : constant Float := 0.6 + 2.5 * abs Step (Crowd_Swell, Noise, 1.5);
                  N     : constant Float := Noise;
               begin
                  S := Step (Crowd_F2, N - Step (Crowd_F1, N, 450.0), 2600.0)
                    * 0.35 * P.Crowd * Swell;
                  L := L + S * (0.9 + 0.2 * Noise);
                  R := R + S * (0.9 + 0.2 * Noise);
               end;
            end if;
            if P.Jets > 0.01 then
               S := (Step (Jet_F1, Noise, 1400.0) * 1.2 + Step (Jet_F2, Noise, 120.0) * 2.5)
                 * 0.5 * P.Jets;
               L := L + S;
               R := R + S;
            end if;

            --  the UFO: an eerie, wavering whine over a deep throb
            Alien_Level := Alien_Level + (P.Alien - Alien_Level) * 0.0005;
            if Alien_Level > 0.001 then
               Alien_Time := Alien_Time + 1.0 / Float (Rate);
               declare
                  F : constant Float := 640.0 + 90.0 * Sin (Two_Pi * 5.5 * Alien_Time)
                    + 40.0 * Sin (Two_Pi * 0.3 * Alien_Time);
               begin
                  Alien_Phase1 := Alien_Phase1 + F / Float (Rate);
                  Alien_Phase1 := Alien_Phase1 - Float'Floor (Alien_Phase1);
                  Alien_Phase2 := Alien_Phase2 + 62.0 / Float (Rate);
                  Alien_Phase2 := Alien_Phase2 - Float'Floor (Alien_Phase2);
                  S := (0.5 * Sin (Two_Pi * Alien_Phase1)
                        + 0.25 * Sin (Two_Pi * 1.501 * Alien_Phase1)
                        + 0.7 * Sin (Two_Pi * Alien_Phase2) * (0.6 + 0.4 * Sin (Two_Pi * 2.0 * Alien_Time)))
                    * 0.08 * Alien_Level;
                  L := L + S * (1.0 - 0.6 * P.Alien_Pan);
                  R := R + S * (1.0 + 0.6 * P.Alien_Pan);
               end;
            end if;

            Horn_Level := Horn_Level
              + ((if P.Horn and then P.Mode = Driving then 1.0 else 0.0) - Horn_Level) * 0.004;
            if Horn_Level > 0.001 then
               Horn_Phase1 := Horn_Phase1 + 415.0 / Float (Rate);
               Horn_Phase1 := Horn_Phase1 - Float'Floor (Horn_Phase1);
               Horn_Phase2 := Horn_Phase2 + 523.0 / Float (Rate);
               Horn_Phase2 := Horn_Phase2 - Float'Floor (Horn_Phase2);
               S := (if Horn_Phase1 < 0.5 then 1.0 else -1.0)
                 + (if Horn_Phase2 < 0.5 then 1.0 else -1.0);
               S := Step (Horn_F2, Step (Horn_F1, S, 2200.0), 3000.0) * 0.09 * Horn_Level;
               L := L + S;
               R := R + S;
            end if;

            Squeal_Level := Squeal_Level + (P.Squeal - Squeal_Level) * 0.002;
            if Squeal_Level > 0.001 then
               declare
                  Drift : constant Float := Step (Squeal_Drift, Noise, 6.0);
                  N     : constant Float := Noise;
                  Band  : Float;
               begin
                  Squeal_Phase := Squeal_Phase
                    + (1050.0 + 220.0 * Squeal_Level + 2500.0 * Drift) / Float (Rate);
                  Squeal_Phase := Squeal_Phase - Float'Floor (Squeal_Phase);
                  Band := Step (Squeal_Lp, N, 3500.0);
                  Band := Band - Step (Squeal_Hp, Band, 1200.0);
                  S := (Sin (Two_Pi * Squeal_Phase) * 0.6
                        + 0.25 * Sin (2.0 * Two_Pi * Squeal_Phase) + 1.6 * Band)
                    * 0.10 * Squeal_Level;
                  L := L + S;
                  R := R + S;
               end;
            end if;

            declare
               BL, BR : Float := 0.0;   --  the bells, before the reverb
            begin
               for E of Events loop
                  if E.Kind /= None then
                     if E.T < 0.0 then
                        E.T := E.T + 1.0 / Float (Rate);   --  delayed start
                     elsif E.Kind in Bell | Ghost | Pipe then
                        Play (E, BL, BR);
                     else
                        Play (E, L, R);
                     end if;
                  end if;
               end loop;
               --  only the bright part goes into the reverb: the deep
               --  tones would make it muddy
               declare
                  Mono   : constant Float := 0.5 * (BL + BR);
                  Bright : constant Float := Mono - Step (Reverb_Hp, Mono, 300.0);
               begin
                  L := L + 0.75 * BL + 0.9 * Reverb (Bright, Combs_L, Passes_L);
                  R := R + 0.75 * BR + 0.9 * Reverb (Bright, Combs_R, Passes_R);
               end;
            end;

            --  limit only the real peaks (clean below that) and convert
            L := 0.8 * Gain * Limit (L);
            R := 0.8 * Gain * Limit (R);
            Buffer (2 * I) := Integer_16 (L * 32000.0);
            Buffer (2 * I + 1) := Integer_16 (R * 32000.0);
         end;
      end loop;
   end Mix;

   ---------------------------------------------------------------------------

   task Mixer is
      entry Begin_Mixing;
   end Mixer;

   task body Mixer is
      Spec   : aliased Sample_Spec := (PA_Sample_S16LE, Rate, 2);
      Attr   : aliased Buffer_Attr :=
        (Max_Length => Unsigned_32'Last,
         T_Length   => Unsigned_32 (Frames * 4 * 3),   --  about 70 ms latency
         Pre_Buf    => Unsigned_32'Last,
         Min_Req    => Unsigned_32'Last,
         Frag_Size  => Unsigned_32'Last);
      Err    : aliased C.int := 0;
      Stream : System.Address;
      Buffer : aliased Sample_Array (0 .. 2 * Frames - 1);
      Silent : constant Sample_Array (0 .. 2 * Frames - 1) := (others => 0);
      Name   : C.Strings.chars_ptr := C.Strings.New_String ("Paris");
      SName  : C.Strings.chars_ptr := C.Strings.New_String ("game sound");
      use type System.Address;
   begin
      select
         accept Begin_Mixing;
      or
         terminate;
      end select;
      if Ada.Environment_Variables.Exists ("PARIS_WAV") then
         Stream := System.Null_Address;
      else
         Stream := PA_New (C.Strings.Null_Ptr, Name, PA_Stream_Playback, C.Strings.Null_Ptr,
                           SName, Spec'Access, System.Null_Address, Attr'Access, Err'Access);
      end if;
      C.Strings.Free (Name);
      C.Strings.Free (SName);
      --  PARIS_WAV=<file>: write the sound to a WAV file instead (testing)
      if Ada.Environment_Variables.Exists ("PARIS_WAV") then
         declare
            use Ada.Streams.Stream_IO;
            F : File_Type;
            Total : Natural := 0;
         begin
            Create (F, Out_File, Ada.Environment_Variables.Value ("PARIS_WAV"));
            String'Write (Ada.Streams.Stream_IO.Stream (F), "RIFF");
            Unsigned_32'Write (Ada.Streams.Stream_IO.Stream (F), 36 + 4 * Rate * 30);
            String'Write (Ada.Streams.Stream_IO.Stream (F), "WAVEfmt ");
            Unsigned_32'Write (Ada.Streams.Stream_IO.Stream (F), 16);
            Unsigned_16'Write (Ada.Streams.Stream_IO.Stream (F), 1);
            Unsigned_16'Write (Ada.Streams.Stream_IO.Stream (F), 2);
            Unsigned_32'Write (Ada.Streams.Stream_IO.Stream (F), Rate);
            Unsigned_32'Write (Ada.Streams.Stream_IO.Stream (F), Rate * 4);
            Unsigned_16'Write (Ada.Streams.Stream_IO.Stream (F), 4);
            Unsigned_16'Write (Ada.Streams.Stream_IO.Stream (F), 16);
            String'Write (Ada.Streams.Stream_IO.Stream (F), "data");
            Unsigned_32'Write (Ada.Streams.Stream_IO.Stream (F), 4 * Rate * 30);
            while not Shared.Stopping and then Total < Rate * 30 loop
               Mix (Buffer);
               Sample_Array'Write (Ada.Streams.Stream_IO.Stream (F), Buffer);
               Total := Total + Frames;
               delay Duration (Float (Frames) / Float (Rate));
            end loop;
            Close (F);
         end;
      else
      --  without a sound server we simply stay silent
      if Stream /= System.Null_Address then
         Shared.Set_Playing;
      end if;
      declare
         use Ada.Streams.Stream_IO;
         Cap : File_Type;
      begin
         while Stream /= System.Null_Address and then not Shared.Stopping loop
            Mix (Buffer);
            if Shared.Is_Muted then
               Buffer := Silent;
            end if;
            --  recording a video: keep a copy of the sound
            declare
               Name : constant String := Shared.Capture_Name;
            begin
               if Name /= "" and then not Is_Open (Cap) then
                  begin
                     Create (Cap, Out_File, Name);
                     Shared.Set_Capture_Open (True);
                  exception
                     when others => Shared.Set_Capture ("");
                  end;
               elsif Name = "" and then Is_Open (Cap) then
                  Close (Cap);
                  Shared.Set_Capture_Open (False);
               end if;
               if Is_Open (Cap) then
                  Sample_Array'Write (Ada.Streams.Stream_IO.Stream (Cap), Buffer);
               end if;
            end;
            exit when PA_Write (Stream, Buffer'Address, C.size_t (Buffer'Length * 2),
                                Err'Access) < 0;
         end loop;
         if Is_Open (Cap) then
            Close (Cap);
            Shared.Set_Capture_Open (False);
         end if;
      end;
      end if;
      if Stream /= System.Null_Address then
         PA_Free (Stream);
      end if;
   end Mixer;

   Started : Boolean := False;

   procedure Start is
   begin
      if not Started then
         Started := True;
         Mixer.Begin_Mixing;
      end if;
   end Start;

   procedure Stop is
   begin
      Shared.Request_Stop;
   end Stop;

   procedure Start_Capture (File_Name : String) is
   begin
      Shared.Set_Capture (File_Name);
   end Start_Capture;

   procedure Stop_Capture is
   begin
      Shared.Set_Capture ("");
      for I in 1 .. 50 loop
         exit when not Shared.Capture_Open;
         delay 0.01;
      end loop;
   end Stop_Capture;

   function Playing return Boolean is (Shared.Is_Playing);

   procedure Peal (Seconds : Float) is
   begin
      Shared.Put_Peal (Seconds);
   end Peal;

   function Pealing return Boolean is (Shared.Is_Pealing);

   procedure Boom (Delay_S, Loudness : Float; Big : Boolean) is
   begin
      Shared.Put_Boom (Delay_S, Loudness, Big);
   end Boom;

   procedure Thunder (Delay_S, Loudness : Float; Close : Boolean) is
   begin
      Shared.Put_Thunder (Delay_S, Loudness, Close);
   end Thunder;

   procedure Wooo (Loudness, Pan : Float) is
   begin
      Shared.Put_Wooo (Loudness, Pan);
   end Wooo;

   procedure Ho_Ho (Loudness, Pan : Float) is
   begin
      Shared.Put_Laugh (Loudness, Pan);
   end Ho_Ho;

   procedure Effect (Kind : Effect_Kind; Loudness, Pan : Float) is
   begin
      Shared.Put_Effect (Kind, Loudness, Pan);
   end Effect;

   procedure Shutter is
   begin
      Shared.Click;
   end Shutter;

end Sound;
