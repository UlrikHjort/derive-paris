# Contributing to Dérive

Thank you for looking!  Dérive is a hobby project: an open-world Paris
in Ada, written entirely by prompting an AI (see the README).  Issues
and pull requests are welcome: bugs, places in Paris that look wrong,
ideas for things to do in the city, and code.

## Building

See the README's Quick start: `make` checks what is needed and builds,
`make tiles-small` builds the centre of Paris, `make run` plays.
`make test` converts a small piece of Paris (no download) and is what
the GitHub build runs.

## Reporting a bug

Please say:
- what you did and what you saw (a screenshot, F12, helps a lot),
- where in Paris, the coordinates in the top right corner,
- the date and time in the game (bottom line),
- your Linux, graphics card, and the version (`./bin/derive` prints it
  first; it is also at the bottom of F1),
- anything in `~/.derive.log`, where the game writes its errors.

## Trying things out: the test switches

The game takes environment variables that put you somewhere, at some
time, doing something, and take a screenshot.  They are how every
change here is checked.  The most useful:

| Variable | What it does |
|---|---|
| `PARIS_SHOT=f.ppm PARIS_SHOT_FRAME=90` | save that frame and quit (`PARIS_SHOT_PNG=f.png` as well: with the panels) |
| `PARIS_CAM="lat lon height heading pitch_down"` | a still camera there |
| `PARIS_SPAWN="lat lon heading"` | the car there |
| `PARIS_TIME=21.5`, `PARIS_DATE=2026-12-24` | the hour and the day |
| `PARIS_RAIN=1` / `storm` / `snow` | the weather |
| `PARIS_MIST=1`, `PARIS_HEAT=1`, `PARIS_FLOOD=3` | the seasons' weather |
| `PARIS_FLY=110` | in the plane, at that height |
| `PARIS_WALK=1` | on foot |
| `PARIS_AUTODRIVE=1` | the car drives itself down the road |
| `PARIS_ORBIT="angle distance height"` | look at the car from there |
| `PARIS_TAXI=1`, `PARIS_TAXI_AUTO=1` | a taxi shift, jumping from fare to fare |
| `PARIS_TRIAL=n`, `PARIS_ROUND=n`, `PARIS_BUS=n` | start that time trial, morning round, bus line |
| `PARIS_RECORD=8` | record 8 seconds of video |
| `PARIS_PROFILE=cpu` | print where the frame's time goes |
| `PARIS_NOWHEEL=1` | ignore a racing wheel |

Run with your own `HOME` (say `HOME=/tmp/derive-test`) to keep your own
settings and photos out of it, and with `volume = 0` in that home's
`.deriverc` to keep it quiet.

## The code

- `src/game/`: the game.  `game.adb` holds the window and the state;
  its biggest parts are separate files (`game-tick.adb` each frame,
  `game-render.adb` the drawing, `game-set_key.adb` the keys).  Each
  feature has its own package (`taxi`, `rounds`, `night_bus`, `boats`,
  `seasons`, `radio`...).
- `src/tools/`: `osm2tiles`, which turns OpenStreetMap data into tiles.
- `shaders/`: GLSL 3.30; `world.frag` holds the materials.
- `data/`: small hand-made data (landmarks, postcards, bakeries, bus
  lines...), easy to add to.

The style: Ada 2012, three spaces, `--` comments in plain English that
say why, names spelled out.  Keep a feature in its own package where you
can, and add a test switch for it.

## Pull requests

Small and focused is best: one feature or one fix.  The GitHub build
must pass.  If it changes what you see, a before/after screenshot in the
pull request helps a lot.
