#!/bin/sh
# Dérive: open-world Paris in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# Download the ground heights for the map area from IGN (RGE ALTI, the
# bare earth without buildings; Licence Ouverte 2.0) as 32-bit floats.
#
# usage: download_terrain.sh SOUTH WEST NORTH EAST [WIDTH HEIGHT]

VERSION=$(sed -n 's/.*Number : constant String := "\(.*\)";/\1/p' "$(dirname "$0")/../src/common/version.ads")
set -e
S=$1; W=$2; N=$3; E=$4
COLS=${5:-2000}; ROWS=${6:-1100}
DIR=data/elevation
mkdir -p "$DIR"
URL="https://data.geopf.fr/wms-r/wms?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap"
URL="$URL&LAYERS=ELEVATION.ELEVATIONGRIDCOVERAGE.HIGHRES&STYLES=&CRS=EPSG:4326"
URL="$URL&BBOX=$S,$W,$N,$E&WIDTH=$COLS&HEIGHT=$ROWS&FORMAT=image/x-bil;bits=32"

echo "Downloading ground heights ($COLS x $ROWS) from IGN"
curl -sS -f --retry 3 -A "derive-game/$VERSION" -o "$DIR/paris.bil.part" "$URL"
SIZE=$(wc -c < "$DIR/paris.bil.part")
if [ "$SIZE" -ne $((COLS * ROWS * 4)) ]; then
    echo "Unexpected answer from IGN ($SIZE bytes); the ground stays flat" >&2
    rm -f "$DIR/paris.bil.part"
    exit 1
fi
mv "$DIR/paris.bil.part" "$DIR/paris.bil"
echo "$S $W $N $E $COLS $ROWS" > "$DIR/paris.txt"
