#!/usr/bin/env python3
# Dérive: open-world Paris in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# Scramble a text file for the game: section lines ("[name]") are kept,
# every other line is XORed with a short key and written as hex.  Not
# secret, just not readable at a glance.
#
#   scripts/scramble.py data/gallery.txt data/gallery.dat
import sys

KEY = b"derive-paris"

def scramble(line):
    data = line.encode("utf-8")
    return "".join("%02x" % (b ^ KEY[i % len(KEY)]) for i, b in enumerate(data))

with open(sys.argv[1], encoding="utf-8") as src, open(sys.argv[2], "w", encoding="ascii") as out:
    for raw in src:
        line = raw.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        out.write((line if line.startswith("[") else scramble(line)) + "\n")
