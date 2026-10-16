#!/bin/sh
# Dérive: open-world Paris in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# Download the OpenStreetMap extract for the game area from the Overpass API.
#
#   scripts/download_osm.sh <output.osm> <south> <west> <north> <east>
#
# The query is data/query.overpassql with {{bbox}} filled in.  The main
# Overpass server is tried first, then a mirror, a few times each.  The
# result is only kept when it is a complete OSM file.

set -eu

if [ $# -ne 5 ]; then
    echo "usage: $0 <output.osm> <south> <west> <north> <east>" >&2
    exit 2
fi

OUT=$1
BBOX="$2,$3,$4,$5"
DIR=$(dirname "$0")/..
QUERY_TEMPLATE=$DIR/data/query.overpassql
SERVERS="https://overpass-api.de/api/interpreter https://overpass.kumi.systems/api/interpreter"
AGENT="derive-game/0.4 (OpenStreetMap city game)"

mkdir -p "$(dirname "$OUT")"
TMP=$(mktemp "${OUT}.XXXXXX")
QUERY=$(mktemp)
trap 'rm -f "$TMP" "$QUERY"' EXIT

grep -v '^//' "$QUERY_TEMPLATE" | sed "s/{{bbox}}/$BBOX/g" > "$QUERY"

for attempt in 1 2 3 4 5; do
    for server in $SERVERS; do
        echo "Downloading $BBOX from $server (attempt $attempt)..."
        if curl -sS --fail --compressed -A "$AGENT" \
                --data-urlencode "data@$QUERY" "$server" -o "$TMP"; then
            # Overpass reports timeouts and memory errors inside a 200 reply
            if tail -c 100 "$TMP" | grep -q '</osm>' \
               && ! grep -q '<remark>' "$TMP"; then
                mv "$TMP" "$OUT"
                trap 'rm -f "$QUERY"' EXIT
                echo "Saved $OUT ($(du -h "$OUT" | cut -f1))"
                exit 0
            fi
            echo "  incomplete answer, retrying" >&2
        fi
    done
    sleep $((attempt * 30))
done

echo "Download failed; the Overpass servers may be busy, try again later." >&2
exit 1
