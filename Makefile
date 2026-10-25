# Dérive: open-world Paris in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# Derive -- an open-world city game in Ada/GtkAda, Paris from OpenStreetMap
#
#   make            check what is needed, build converter and game
#   make check      only check that the tools and libraries are installed
#   make tiles      download (missing) OSM chunks and generate tiles/
#   make tiles-small  only the centre (4 x 4 km from the Invalides to the
#                   Hôtel de Ville, Montparnasse to the Louvre): quicker,
#                   to try it out; "make tiles" later reuses its downloads
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
# The centre only, where the game starts: four of the 2 x 2 km chunks of
# BBOX exactly, so that a later "make tiles" keeps what it downloaded
SMALL := 48.8322 2.3047 48.8675 2.3587

all: check tools game

check:
	@./scripts/check_deps.sh

# (every target checks first what is needed: a missing library is then
# named, with the command to install it, rather than a compiler error)
tools: check
	gprbuild -p -P tools.gpr -j0

game: check
	gprbuild -p -P derive.gpr -j0

tiles: check tools
	./scripts/build_city.sh $(BBOX)

tiles-small: check tools
	./scripts/build_city.sh $(SMALL)

run: game
	@ls tiles/t_*.bin >/dev/null 2>&1 || { \
	  echo "No city built yet: run 'make tiles' (all of Paris, a few hundred MB)"; \
	  echo "or 'make tiles-small' (only the centre, quicker) first."; exit 1; }
	./bin/derive

download: tools
	rm -rf data/osm/chunks data/elevation
	./scripts/build_city.sh $(BBOX)

clean:
	gprclean -P tools.gpr
	gprclean -P derive.gpr

.PHONY: all check tools game tiles tiles-small run download clean
