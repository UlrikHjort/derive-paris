# Paris

An open-world driving (and flying) game in Ada and GtkAda.  The 3D city of
Paris (inside the Périphérique, plus the Bois de Boulogne, Vincennes and a
corner of La Défense) is generated from OpenStreetMap data: buildings with their
real outlines, heights and roofs, streets with markings and traffic
lights, the Seine with its quays and bridges, trees, street lamps, traffic
and pedestrians, day and night, and rain.

## Building

Needs GNAT with gprbuild, GtkAda (GTK 3), libepoxy, zlib, PulseAudio
(libpulse-simple), curl and an OpenGL 3.3 graphics card.

    make            # build the converter (bin/osm2tiles) and the game (bin/paris)
    make tiles      # download the OSM data if needed, build tiles/
    make run        # play

The OSM data (`data/osm/`) and the generated tiles are not in the
repository; `make tiles` recreates them.  The map area (`BBOX` in the
Makefile) is split into 2 x 2 km chunks which are downloaded one after the
other from the Overpass API (`scripts/build_city.sh`, query in
`data/query.overpassql`) and converted in parallel.  An interrupted
download simply continues where it stopped when run again; `make download`
fetches everything fresh.  Change `BBOX` to build a smaller or larger area.

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
| G | compass, position (lat/lon, heading, altitude) and minimap |
| Shift + 1 .. 0 | GPS: navigate to that place (route through the real streets, turn-by-turn with street names) |
| X | stop navigating |
| J | clear the traffic around you (new cars arrive gradually) |
| M | sound on/off |
| 1 .. 9, 0 | jump to Saint-Sulpice, Notre-Dame, Louvre, Tour Eiffel, Arc de Triomphe, Sacré-Cœur, Panthéon, Concorde, Opéra, Bastille |
| H | home: Place Saint-Sulpice (also where the game starts) |
| R | reset |

## Settings

`~/.adadriverc` holds settings as `name = value` lines (`#` starts a
comment); the game writes a commented starter file on its first run.
So far: `traffic`, `pedestrians` (1.0 = normal), `volume` (0 .. 1),
`start_hour`, `time_speed` (game minutes per real second), `compass` and
`street_names` (yes/no).

## How it works

- `src/tools`: `osm2tiles` reads the OSM extract and writes 250 m tiles
  (meshes, collision edges, lamps, road strips) and the road network.
- `src/game`: the GtkAda game; tiles are streamed around the player.
- `shaders`: facades, windows, roofs, water and lighting are drawn
  procedurally in GLSL, there are no textures.

Debug options for screenshots: `PARIS_SHOT=file.ppm`, `PARIS_SPAWN`,
`PARIS_CAM`, `PARIS_DRONE`, `PARIS_FLY`, `PARIS_TIME`, `PARIS_RAIN`,
`PARIS_ZOOM`, `PARIS_TILES`, `PARIS_TELEPORT`, `PARIS_WAV`, `PARIS_COMPASS_PNG`, `PARIS_NAV`, `PARIS_MAP_PNG`, `PARIS_PROFILE` (see `src/game/game.adb`).

Map data © OpenStreetMap contributors, available under the Open Database
License (ODbL).
