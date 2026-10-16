// Overpass query for the game area.  {{bbox}} is replaced by
// scripts/download_osm.sh with "south,west,north,east" from the Makefile.
[out:xml][timeout:600][maxsize:1073741824];
(
  wr["building"]({{bbox}});
  wr["building:part"]({{bbox}});
  way["highway"]({{bbox}});
  way["area:highway"]({{bbox}});
  wr["natural"]({{bbox}});
  wr["waterway"]({{bbox}});
  wr["water"]({{bbox}});
  wr["leisure"]({{bbox}});
  wr["landuse"]({{bbox}});
  wr["amenity"="parking"]({{bbox}});
  wr["place"="square"]({{bbox}});
  wr["man_made"="bridge"]({{bbox}});
  node["natural"="tree"]({{bbox}});
  node["highway"~"^(crossing|street_lamp|traffic_signals)$"]({{bbox}});
);
(._;>;);
out body;
