#!/bin/sh
# Dérive: open-world Paris in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# A quick test of the converter: the Place Saint-Sulpice (a small piece of
# OpenStreetMap, tests/saint-sulpice.osm, © OpenStreetMap contributors,
# ODbL) into tiles, checking that the city's tiles, its roads and its
# addresses come out.  Needs no download.  `make test` runs it.

set -eu
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

./bin/osm2tiles chunk tests/saint-sulpice.osm "$OUT" -7 -6 1 2 > "$OUT/log.txt" 2>&1 || {
    cat "$OUT/log.txt"; echo "FAILED: the converter stopped"; exit 1; }

fail () { cat "$OUT/log.txt"; echo "FAILED: $1"; exit 1; }
TILES=$(ls "$OUT"/t_*.bin 2>/dev/null | wc -l)
[ "$TILES" -eq 4 ] || fail "expected 4 tiles, got $TILES"
[ -s "$OUT/roads_-7_1.bin" ] || fail "no road network"
grep -q "Saint-Sulpice" "$OUT"/addresses_*.txt || fail "no addresses on the Place Saint-Sulpice"
grep -q "street lamps" "$OUT/log.txt" || fail "no street lamps"
echo "OK: $TILES tiles, roads and addresses for the Place Saint-Sulpice"
