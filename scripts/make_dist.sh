#!/bin/sh
# Dérive: open-world Paris in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# The prebuilt download: dist/derive-<version>-linux-x86_64.tar.gz with
# the game and the converter, the Ada libraries they need that are not
# usually installed (GtkAda and the GNAT runtime), the shaders, the data,
# the scripts to build the city, and two launchers: ./city (small or all)
# and ./derive.  Needs a built game (make tools game).  The release
# workflow runs this when a version is tagged.

set -eu
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*Number : constant String := "\(.*\)";/\1/p' src/common/version.ads)
NAME=derive-$VERSION-linux-x86_64
OUT=dist/$NAME
rm -rf "$OUT" "dist/$NAME.tar.gz"
mkdir -p "$OUT/bin" "$OUT/lib"

cp bin/derive bin/osm2tiles "$OUT/bin/"

# the Ada libraries, by the names the programs ask for
for P in bin/derive bin/osm2tiles; do
    ldd "$P" | awk '/libgtkada|libgnat|libgnarl/ {print $1, $3}'
done | sort -u | while read -r SONAME FILE; do
    cp -L "$FILE" "$OUT/lib/$SONAME"
done

# what the repository holds of shaders, data, scripts and the fixed tiles
git ls-files shaders data scripts tiles LICENSE CHANGELOG.md README.md \
    | grep -v '^data/home/' | while read -r F; do
    mkdir -p "$OUT/$(dirname "$F")"
    cp "$F" "$OUT/$F"
done
cp -r data/home "$OUT/data/"

cat > "$OUT/derive" <<'LAUNCH'
#!/bin/sh
# Start Dérive (the Ada libraries it brings are in lib/)
D=$(cd "$(dirname "$0")" && pwd)
cd "$D"
if ! ls tiles/t_*.bin >/dev/null 2>&1; then
    echo "No city built yet: first run  ./city small  (the centre, a few minutes)"
    echo "or  ./city all  (all of Paris, a few hundred MB)."
fi
LD_LIBRARY_PATH="$D/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" exec "$D/bin/derive" "$@"
LAUNCH

cat > "$OUT/city" <<'LAUNCH'
#!/bin/sh
# Build the city:  ./city small  (the centre)  or  ./city all  (all of Paris)
D=$(cd "$(dirname "$0")" && pwd)
cd "$D"
command -v curl >/dev/null 2>&1 || { echo "Needs curl, to download the map data (e.g. sudo apt install curl)"; exit 1; }
LD_LIBRARY_PATH="$D/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
exec ./scripts/city.sh "${1:-small}"
LAUNCH
chmod +x "$OUT/derive" "$OUT/city"

cat > "$OUT/README-FIRST.txt" <<TXT
Dérive $VERSION for Linux (x86_64): an open-world Paris in Ada
https://github.com/UlrikHjort/derive-paris

It needs GTK 3, libepoxy (OpenGL), PulseAudio's library, zlib and curl,
and a graphics card with OpenGL 3.3.  On Debian, Ubuntu and Mint:

    sudo apt install libgtk-3-0 libepoxy0 libpulse0 zlib1g curl

(Fedora: gtk3 libepoxy pulseaudio-libs zlib curl; Arch: gtk3 libepoxy
libpulse zlib curl.)

Then build the city once, and play:

    ./city small     the centre of Paris, 4 x 4 km (a few minutes), or
    ./city all       all of Paris (a few hundred MB, much longer)
    ./derive

F1 shows the keys, F2 the games.  The map data is downloaded from
OpenStreetMap (© OpenStreetMap contributors, ODbL) and the ground heights
from IGN (Licence Ouverte 2.0).  The code is under the MIT License
(LICENSE); see README.md for everything else.
TXT

tar -C dist -czf "dist/$NAME.tar.gz" "$NAME"
echo "dist/$NAME.tar.gz ($(du -h "dist/$NAME.tar.gz" | cut -f1))"
