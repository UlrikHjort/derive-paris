# Dérive: open-world Paris in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# Derive -- an open-world city game in Ada/GtkAda, Paris from OpenStreetMap
#
#   make            build converter and game
#   make tiles      download (missing) OSM chunks and generate tiles/
#   make run        start the game
#   make download   fetch all OSM chunks again (Overpass API)
#
# The OSM data and the generated tiles are not kept in git: a fresh
# checkout only needs "make tiles".  For all of Paris that downloads about
# 50 chunks of 2 x 2 km (several hundred MB, takes a while; an interrupted
# run continues where it stopped) and converts them in parallel.

# All of Paris inside the Peripherique, plus the Bois de Boulogne and
# Vincennes and a bit of La Defense: south west north east
BBOX  := 48.8150 2.2240 48.9030 2.4700

all: tools game

tools:
	gprbuild -p -P tools.gpr -j0

game:
	gprbuild -p -P derive.gpr -j0

tiles: tools
	./scripts/build_city.sh $(BBOX)

run: game
	./bin/derive

download: tools
	rm -rf data/osm/chunks data/elevation
	./scripts/build_city.sh $(BBOX)

clean:
	gprclean -P tools.gpr
	gprclean -P derive.gpr

.PHONY: all tools game tiles run download clean
