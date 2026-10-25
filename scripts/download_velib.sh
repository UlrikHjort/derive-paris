#!/bin/sh
# Dérive: open-world Paris in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# The bicycle-hire stations (Vélib') of the game area from OpenStreetMap,
# into data/velib.txt (lat lon per line).  One small Overpass request.
#
#   scripts/download_velib.sh [south west north east]

VERSION=$(sed -n 's/.*Number : constant String := "\(.*\)";/\1/p' "$(dirname "$0")/../src/common/version.ads")
set -eu
cd "$(dirname "$0")/.."
BBOX="${1:-48.8150},${2:-2.2240},${3:-48.9030},${4:-2.4700}"
OUT=data/velib.txt
TMP=$(mktemp)
curl -s -A "derive-game/$VERSION (OpenStreetMap city game)" --data-urlencode \
  "data=[out:csv(::lat,::lon;false;' ')][timeout:120];node[amenity=bicycle_rental]($BBOX);out;" \
  https://overpass-api.de/api/interpreter > "$TMP"
N=$(grep -c '^[0-9]' "$TMP" || true)
if [ "$N" -lt 10 ]; then
    echo "Overpass gave $N stations; data/velib.txt is left as it was" >&2
    rm -f "$TMP"
    exit 1
fi
{
    echo "# Bicycle-hire stations (Vélib') in Paris, from OpenStreetMap"
    echo "# (© OpenStreetMap contributors, ODbL): latitude longitude"
    grep '^[0-9]' "$TMP"
} > "$OUT"
rm -f "$TMP"
echo "$N stations in $OUT"
