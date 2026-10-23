#!/bin/sh
# Dérive: open-world Paris in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# Small looping GIFs of the game for the README (docs/gifs): each scene is
# a short recording (PARIS_RECORD) with the game's test switches, made
# small with ffmpeg (its own palette, 480 px wide, 12 frames a second).
#
#   scripts/make_gifs.sh            all of them
#   scripts/make_gifs.sh fly rain   just these
#
# The game opens its window for each; leave it be while it records.
# Needs ffmpeg and a built game (make game, make tiles).

set -e
cd "$(dirname "$0")/.."
OUT=docs/gifs
mkdir -p "$OUT"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# A quiet home of its own, so your settings, photos and videos are not touched
mkdir -p "$WORK/home"
printf 'volume = 0\ntraffic = 1.0\npedestrians = 1.0\ncompass = no\nstreet_names = no\n' > "$WORK/home/.deriverc"

# record NAME SECONDS [VAR=value ...]
record () {
    name=$1; secs=$2; shift 2
    echo "== $name"
    rm -rf "$WORK/home/Videos"
    mkdir -p "$WORK/home/Videos"
    env HOME="$WORK/home" PARIS_NOWHEEL=1 PARIS_RECORD="$secs" "$@" \
        timeout $((secs + 90)) ./bin/derive > "$WORK/$name.log" 2>&1 || true
    # the picture is put into its file a moment after the game has gone
    for i in 1 2 3 4 5 6 7 8 9 10; do
        mp4=$(ls "$WORK"/home/Videos/Derive/*.mp4 2>/dev/null | head -n 1)
        [ -n "$mp4" ] && break
        sleep 1
    done
    if [ -z "$mp4" ]; then
        echo "   no video:"; tail -n 5 "$WORK/$name.log"; return
    fi
    sleep 1
    # drop the first second (the scene settling), make it small, loop it
    ffmpeg -loglevel error -y -ss 1 -i "$mp4" \
        -vf "fps=12,scale=480:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
        -loop 0 "$OUT/$name.gif"
    echo "   $OUT/$name.gif ($(du -k "$OUT/$name.gif" | cut -f1) kB)"
}

ALL="$*"
pick () { [ -z "$ALL" ] && return 0; for w in $ALL; do [ "$w" = "$1" ] && return 0; done; return 1; }

# Up the Champs-Élysées towards the Arc de Triomphe, in the late sun
pick champs && record champs 7 PARIS_SPAWN="48.871941 2.300946 296" PARIS_TIME=17.3 PARIS_AUTODRIVE=1
# Flying past the Eiffel Tower
pick fly && record fly 8 PARIS_SPAWN="48.85200 2.28300 50" PARIS_FLY=110 PARIS_TIME=16
# The Eiffel Tower sparkling on the hour, from the Trocadéro
pick sparkle && record sparkle 6 PARIS_CAM="48.86180 2.28800 12 150 -6" PARIS_TIME=21.0
# Drop the clutch: smoke and skid marks
pick burnout && record burnout 7 PARIS_BURNOUT=1 PARIS_TIME=15
# A market morning in the Rue d'Aligre (a Tuesday)
pick market && record market 6 PARIS_DATE=2026-10-27 PARIS_TIME=10 PARIS_CAM="48.848650 2.377850 4 30 10"
