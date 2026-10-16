#!/bin/sh
# Download and convert a whole city area in 2 km chunks.
#
#   scripts/build_city.sh <south> <west> <north> <east>
#
# The area is split into chunks by "osm2tiles plan".  Each chunk is
# downloaded from Overpass into data/osm/chunks/ (one request at a time, with
# a pause in between, and only when the file is missing, so an interrupted
# run simply continues), then all chunks are converted into tiles/ in
# parallel.  Set JOBS to change the number of parallel conversions.

set -eu

if [ $# -ne 4 ]; then
    echo "usage: $0 <south> <west> <north> <east>" >&2
    exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
CHUNKS=data/osm/chunks
JOBS=${JOBS:-6}
mkdir -p "$CHUNKS" tiles

PLAN=$(./bin/osm2tiles plan "$1" "$2" "$3" "$4")
TOTAL=$(echo "$PLAN" | wc -l)
echo "$TOTAL chunks"

# 1. Download, politely and resumably
N=0
echo "$PLAN" | while read -r TX0 TX1 TZ0 TZ1 S W NO E; do
    N=$((N + 1))
    FILE=$CHUNKS/c_${TX0}_${TZ0}.osm
    if [ -s "$FILE" ]; then
        continue
    fi
    echo "[$N/$TOTAL] chunk $TX0 $TZ0"
    ./scripts/download_osm.sh "$FILE" "$S" "$W" "$NO" "$E"
    sleep 5
done

# 2. Convert all chunks in parallel
rm -f tiles/*.bin
echo "$PLAN" | while read -r TX0 TX1 TZ0 TZ1 S W NO E; do
    echo "$TX0 $TX1 $TZ0 $TZ1"
done | xargs -P "$JOBS" -L 1 sh -c '
    ./bin/osm2tiles chunk data/osm/chunks/c_$0_$2.osm tiles $0 $1 $2 $3 \
        > tiles/.log_$0_$2.txt 2>&1 \
    && echo "converted chunk $0 $2" \
    || { echo "chunk $0 $2 FAILED, see tiles/.log_$0_$2.txt"; exit 255; }'

echo "Done: $(ls tiles/t_*.bin | wc -l) tiles, $(du -sh tiles | cut -f1)"
