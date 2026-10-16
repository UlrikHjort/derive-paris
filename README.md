# Paris

An open-world driving (and flying) game in Ada and GtkAda.  The 3D city of
central Paris is generated from OpenStreetMap data: buildings with their
real outlines, heights and roofs, streets with markings and traffic
lights, the Seine with its quays and bridges, trees, street lamps, traffic
and pedestrians, day and night, and rain.

## Building

Needs GNAT with gprbuild, GtkAda (GTK 3), libepoxy, curl and an OpenGL 3.3
graphics card.

    make            # build the converter (bin/osm2tiles) and the game (bin/paris)
    make tiles      # download the OSM extract (~50 MB) if needed, build tiles/
    make run        # play

The OSM data (`data/osm/`) and the generated tiles are not in the
repository; `make tiles` recreates them.  `make download` fetches fresh
OSM data.  The map area is the `BBOX` in the Makefile, the download query
is `data/query.overpassql`.

## Controls

| Key | |
|---|---|
| arrows / WASD | drive |
| space | handbrake |
| C | chase or drone camera |
| mouse wheel, + / - | zoom |
| F | take off in a plane / land and drive again |
| W / S, arrows (in the air) | throttle, pitch (up = nose down) and bank |
| T | one hour later |
| P | rain |
| N | street names |
| R | reset |

## How it works

- `src/tools`: `osm2tiles` reads the OSM extract and writes 250 m tiles
  (meshes, collision edges, lamps, road strips) and the road network.
- `src/game`: the GtkAda game; tiles are streamed around the player.
- `shaders`: facades, windows, roofs, water and lighting are drawn
  procedurally in GLSL, there are no textures.

Debug options for screenshots: `PARIS_SHOT=file.ppm`, `PARIS_SPAWN`,
`PARIS_CAM`, `PARIS_DRONE`, `PARIS_FLY`, `PARIS_TIME`, `PARIS_RAIN`,
`PARIS_ZOOM`, `PARIS_PROFILE` (see `src/game/game.adb`).

Map data © OpenStreetMap contributors, available under the Open Database
License (ODbL).
