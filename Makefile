# Paris -- OSM city driving game in Ada/GtkAda
#
#   make            build converter and game
#   make tiles      generate tiles/ from the OSM extract (downloads it first
#                   when it is missing)
#   make run        start the game
#   make download   fetch the OSM extract again (Overpass API)
#
# The OSM data and the generated tiles are not kept in git: a fresh
# checkout only needs "make tiles" (about 50 MB download, 15 s converting).

# Central Paris: Saint-Germain, Latin Quarter, the islands, the Louvre
OSM   := data/osm/paris_centre.osm
# south west north east; the download query uses the same box
BBOX  := 48.8360 2.3150 48.8660 2.3600

all: tools game

tools:
	gprbuild -p -P tools.gpr -j0

game:
	gprbuild -p -P paris.gpr -j0

$(OSM):
	./scripts/download_osm.sh $(OSM) $(BBOX)

tiles: tools $(OSM)
	mkdir -p tiles
	rm -f tiles/*.bin tiles/roads.bin
	./bin/osm2tiles $(OSM) tiles $(BBOX)

run: game
	./bin/paris

download:
	./scripts/download_osm.sh $(OSM) $(BBOX)

clean:
	gprclean -P tools.gpr
	gprclean -P paris.gpr

.PHONY: all tools game tiles run download clean
