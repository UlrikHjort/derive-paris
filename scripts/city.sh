#!/bin/sh
# Dérive: open-world Paris in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# Build the city: download the map data and the ground heights for an
# area of Paris and make the game's tiles of it.
#
#   scripts/city.sh small   the centre, 4 x 4 km from the Invalides to the
#                           Hôtel de Ville, Montparnasse to the Louvre (a
#                           few minutes; four of the chunks of "all", so
#                           building all of Paris later keeps them)
#   scripts/city.sh all     all of Paris inside the Périphérique, with the
#                           Bois de Boulogne, Vincennes and a corner of La
#                           Défense (a few hundred MB, much longer)
#
# (make tiles and make tiles-small run this; so does ./city in the
# prebuilt download)

set -eu
cd "$(dirname "$0")/.."

case "${1:-}" in
    small) exec ./scripts/build_city.sh 48.8322 2.3047 48.8675 2.3587 ;;
    all)   exec ./scripts/build_city.sh 48.8150 2.2240 48.9030 2.4700 ;;
    *)     echo "usage: $0 small | all" >&2; exit 2 ;;
esac
