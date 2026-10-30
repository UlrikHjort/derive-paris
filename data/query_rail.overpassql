// Overpass query for the railways of the game area: the tracks, the trams'
// rails and the platforms.  {{bbox}} is replaced by scripts/download_rail.sh.
[out:xml][timeout:300][maxsize:536870912];
(
  way["railway"~"^(rail|light_rail|tram|platform)$"]({{bbox}});
);
(._;>;);
out body;
