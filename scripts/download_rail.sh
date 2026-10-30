#!/bin/sh
# Dérive: open-world Paris in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# Download the railways of the game area, once, into data/osm/rail.osm.  The
# city's chunks don't hold them; osm2tiles adds this file to every chunk.
#
#   scripts/download_rail.sh <south> <west> <north> <east>
set -eu
DIR=$(dirname "$0")/..
[ -s "$DIR/data/osm/rail.osm" ] && exit 0
QUERY_TEMPLATE=$DIR/data/query_rail.overpassql \
    "$DIR/scripts/download_osm.sh" "$DIR/data/osm/rail.osm" "$1" "$2" "$3" "$4"
