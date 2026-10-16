with Ada.Environment_Variables;
with Ada.Numerics;
with Ada.Streams.Stream_IO;
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
   private
      Current   : Params;
      Bell_Count : Natural := 0;
      Bell_Loud  : Float := 0.0;
      Stop_Flag : Boolean := False;
      Mute      : Boolean := False;
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
   end Shared;

   procedure Set (P : Params) is
   begin
      Shared.Put (P);
   end Set;

   procedure Bells (Strikes : Positive; Loudness : Float) is
   begin
      Shared.Ring (Strikes, Loudness);
   end Bells;

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
   type Event_Kind is (None, Passing, Horn, Bird, Bell);

   type Event is record
      Kind     : Event_Kind := None;
      T, Dur   : Float := 0.0;      --  seconds
      Volume   : Float := 0.0;
      Pan      : Float := 0.0;      --  -1 left .. 1 right
      Freq     : Float := 0.0;
      Phase    : Float := 0.0;
      Filter   : Lowpass;
   end record;

   Events : array (1 .. 24) of Event;

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
            --  tyre and engine noise swelling and fading as a car goes by
            Env := Sin (Ada.Numerics.Pi * E.T / E.Dur) ** 3;
            S := Step (E.Filter, Noise, 500.0 + 900.0 * Env) * 2.2;
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
            for K in Bell_Partials'Range loop
               S := S + Sin (Two_Pi * E.Freq * Bell_Partials (K) * E.T)
                 * Exp (-E.T * (0.35 + 0.45 * Float (K))) / Float (K);
            end loop;
            S := S * (if E.T < 0.005 then E.T / 0.005 else 1.0);
         when None =>
            return;
      end case;
      S := S * Env * E.Volume;
      L := L + S * (1.0 - 0.6 * E.Pan);
      R := R + S * (1.0 + 0.6 * E.Pan);
   end Play;

   --  Continuous sounds
   Engine_Phase, Prop_Phase : Float := 0.0;
   Rpm_Now                  : Float := 850.0;
   Rumble, Road, Wind, Rain_F, Engine_Tone, Engine_Grit : Lowpass;
   Rain_Hp                  : Lowpass;
   Next_Pass, Next_Horn, Next_Bird : Float := 1.0;
   Bell_Wait                : Float := 0.0;
   Bells_Left               : Natural := 0;
   Bell_Volume              : Float := 0.0;

   procedure Mix (Buffer : out Sample_Array) is
      P     : constant Params := Shared.Get;
      Dt    : constant Float := Float (Frames) / Float (Rate);
      Ear   : constant Float := Float'Max (0.0, P.Altitude);
      --  the city gets quieter and duller as you go up
      City  : constant Float := 1.0 / (1.0 + Ear / 60.0);
      Day   : constant Float := 1.0 - P.Night;
      Inside : constant Boolean := P.Mode = Visiting;
   begin
      --  Schedule events for this buffer
      Next_Pass := Next_Pass - Dt;
      if Next_Pass <= 0.0 then
         Add ((Kind => Passing, Dur => 2.5 + 3.0 * Uniform,
               Volume => (0.05 + 0.08 * Uniform) * City * (0.4 + 0.6 * Day),
               Pan => Noise, others => <>));
         Next_Pass := (1.5 + 5.0 * Uniform) * (1.0 + 2.0 * P.Night) / (0.5 + P.Traffic);
      end if;
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
      if Bells_Left > 0 then
         Bell_Wait := Bell_Wait - Dt;
         if Bell_Wait <= 0.0 then
            Add ((Kind => Bell, Dur => 6.0, Volume => 0.22 * Bell_Volume,
                  Pan => 0.2, Freq => 440.0, others => <>));
            Bells_Left := Bells_Left - 1;
            Bell_Wait := 2.4;
         end if;
      end if;

      for I in 0 .. Frames - 1 loop
         declare
            L, R : Float := 0.0;
            S    : Float;
         begin
            --  Distant traffic rumble and rain
            S := Step (Rumble, Noise, 120.0) * 0.9 * City * (0.35 + 0.65 * Day);
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
                  Rpm_Now := Rpm_Now + (P.Rpm - Rpm_Now) * 0.0006;
                  declare
                     F0 : constant Float := Rpm_Now / 60.0 * 2.0;
                     Ph : Float;
                     E  : Float;
                  begin
                     Engine_Phase := Engine_Phase + F0 / Float (Rate);
                     Engine_Phase := Engine_Phase - Float'Floor (Engine_Phase);
                     Ph := Two_Pi * Engine_Phase;
                     E := Sin (Ph) + 0.6 * Sin (2.0 * Ph + 0.4) + 0.4 * Sin (3.0 * Ph + 1.3)
                       + 0.25 * Sin (4.0 * Ph + 2.1) + 0.15 * Sin (0.5 * Ph);
                     E := E + Step (Engine_Grit, Noise, 300.0 + F0 * 4.0) * (1.5 + 3.0 * P.Load);
                     E := Step (Engine_Tone, E, 250.0 + 900.0 * P.Load + F0 * 2.0);
                     S := E * (0.07 + 0.11 * P.Load);
                     L := L + S;
                     R := R + S;
                  end;
                  --  tyres on the road and wind
                  S := Step (Road, Noise, 400.0) * 1.4 * Float'Min (1.0, P.Speed / 25.0);
                  L := L + S;
                  R := R + S;
                  S := Step (Wind, Noise, 2500.0) * 0.08 * (P.Speed / 40.0) ** 2;
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

            for E of Events loop
               if E.Kind /= None then
                  if E.T < 0.0 then
                     E.T := E.T + 1.0 / Float (Rate);   --  delayed start
                  else
                     Play (E, L, R);
                  end if;
               end if;
            end loop;

            --  soft clip and convert
            L := 0.8 * L / (1.0 + abs L);
            R := 0.8 * R / (1.0 + abs R);
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
      while Stream /= System.Null_Address and then not Shared.Stopping loop
         Mix (Buffer);
         if Shared.Is_Muted then
            Buffer := Silent;
         end if;
         exit when PA_Write (Stream, Buffer'Address, C.size_t (Buffer'Length * 2),
                             Err'Access) < 0;
      end loop;
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

end Sound;
