#!/bin/sh
# Dérive: open-world Paris in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# Download and convert a whole city area in 2 km chunks.
#
#   scripts/build_city.sh <south> <west> <north> <east>
#
# The area is split into chunks by "osm2tiles plan".  Each chunk is
# downloaded from Overpass into data/osm/chunks/ (one request at a time,
# with pauses, only when the file is missing).  A chunk that fails is
# retried in a second round; whatever could be downloaded is converted, so
# running the script again later fills in the gaps.  The tiles are built
# in tiles.new/ and swapped in when complete, so the game never sees a
# half-built directory.  Set JOBS for the number of parallel conversions.

set -u

if [ $# -ne 4 ]; then
    echo "usage: $0 <south> <west> <north> <east>" >&2
    exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
CHUNKS=data/osm/chunks
JOBS=${JOBS:-6}
mkdir -p "$CHUNKS"

# The ground heights (once); without them the city is built flat
if [ ! -s data/elevation/paris.bil ]; then
    ./scripts/download_terrain.sh "$1" "$2" "$3" "$4" || true
fi

PLAN=$(./bin/osm2tiles plan "$1" "$2" "$3" "$4") || exit 1
TOTAL=$(echo "$PLAN" | wc -l)
echo "$TOTAL chunks"

download_missing () {
    echo "$PLAN" | while read -r TX0 TX1 TZ0 TZ1 S W NO E; do
        FILE=$CHUNKS/c_${TX0}_${TZ0}.osm
        if [ ! -s "$FILE" ]; then
            echo "chunk $TX0 $TZ0"
            ./scripts/download_osm.sh "$FILE" "$S" "$W" "$NO" "$E" \
                || echo "  chunk $TX0 $TZ0 failed, will retry"
            sleep 10
        fi
    done
}

missing () {
    echo "$PLAN" | while read -r TX0 TX1 TZ0 TZ1 REST; do
        [ -s "$CHUNKS/c_${TX0}_${TZ0}.osm" ] || echo "$TX0 $TZ0"
    done
}

# 1. Download, in two rounds
download_missing
if [ -n "$(missing)" ]; then
    echo "Retrying failed chunks in a minute..."
    sleep 60
    download_missing
fi
MISSING=$(missing)

# 2. Convert every chunk we have, in parallel, into tiles.new/
rm -rf tiles.new
mkdir -p tiles.new
echo "$PLAN" | while read -r TX0 TX1 TZ0 TZ1 REST; do
    if [ -s "$CHUNKS/c_${TX0}_${TZ0}.osm" ]; then
        echo "$TX0 $TX1 $TZ0 $TZ1"
    fi
done | xargs -P "$JOBS" -L 1 sh -c '
    ./bin/osm2tiles chunk data/osm/chunks/c_$0_$2.osm tiles.new $0 $1 $2 $3 \
        > tiles.new/.log_$0_$2.txt 2>&1 \
    && echo "converted chunk $0 $2" \
    || echo "chunk $0 $2 FAILED, see tiles.new/.log_$0_$2.txt"'

# 3. Swap in the new tiles
rm -rf tiles.old
[ -d tiles ] && mv tiles tiles.old
mv tiles.new tiles
rm -rf tiles.old

echo "Done: $(ls tiles/t_*.bin | wc -l) tiles, $(du -sh tiles | cut -f1)"
if [ -n "$MISSING" ]; then
    echo "Some chunks could not be downloaded (Overpass busy):"
    echo "$MISSING"
    echo "Run the same command again later to fill them in."
    exit 1
fi
