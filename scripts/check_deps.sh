#!/bin/sh
# Dérive: open-world Paris in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# Check that everything needed to build and run Dérive is installed.
# Says what is missing and how to install it, and (when run from a
# terminal) offers to install it.  Exit status 1 when something needed is
# missing.  `make` runs this first; `make check` runs it on its own.

MISSING=""        # what is needed and missing (our own names)
OPTIONAL=""       # what would be nice

have () { command -v "$1" >/dev/null 2>&1; }
need () { MISSING="$MISSING $1"; }

# --- the Ada compiler and its build tool -----------------------------------
have gnatmake && have gnatls || need gnat
have gprbuild || need gprbuild

# --- GtkAda: the gtkada project file where gprbuild looks -------------------
gtkada_found () {
    for D in $(echo "$GPR_PROJECT_PATH" | tr ':' ' ') \
             $(gnatls -v 2>/dev/null | sed -n '/Project Search Path/,/^$/p' | tail -n +2); do
        [ -f "$D/gtkada.gpr" ] && return 0
    done
    return 1
}
if have gnatls; then
    gtkada_found || need gtkada
else
    need gtkada
fi

# --- C libraries (with their headers) ---------------------------------------
if have pkg-config; then
    pkg-config --exists gtk+-3.0        || need gtk3
    pkg-config --exists epoxy           || need epoxy
    pkg-config --exists zlib            || need zlib
    pkg-config --exists libpulse-simple || need pulse
else
    need pkgconfig
fi

# --- programs ---------------------------------------------------------------
have curl   || need curl
have ffmpeg || OPTIONAL="$OPTIONAL ffmpeg"

if [ -z "$MISSING" ] && [ -z "$OPTIONAL" ]; then
    echo "All needed tools and libraries are installed."
    exit 0
fi

# --- the package names on this system ---------------------------------------
if have apt-get; then
    PM="sudo apt-get install"
    GTKADA=$(apt-cache search --names-only '^libgtkada[0-9.]*-dev$' 2>/dev/null \
             | awk '{print $1}' | sort -V | tail -1)
    pkg () { case $1 in
        gnat) echo gnat ;; gprbuild) echo gprbuild ;; gtkada) echo "${GTKADA:-libgtkada-dev}" ;;
        gtk3) echo libgtk-3-dev ;; epoxy) echo libepoxy-dev ;; zlib) echo zlib1g-dev ;;
        pulse) echo libpulse-dev ;; pkgconfig) echo pkg-config ;; curl) echo curl ;;
        ffmpeg) echo ffmpeg ;; esac; }
elif have dnf; then
    PM="sudo dnf install"
    pkg () { case $1 in
        gnat) echo gcc-gnat ;; gprbuild) echo gprbuild ;; gtkada) echo gtkada-devel ;;
        gtk3) echo gtk3-devel ;; epoxy) echo libepoxy-devel ;; zlib) echo zlib-devel ;;
        pulse) echo pulseaudio-libs-devel ;; pkgconfig) echo pkgconf ;; curl) echo curl ;;
        ffmpeg) echo ffmpeg-free ;; esac; }
elif have pacman; then
    PM="sudo pacman -S"
    pkg () { case $1 in
        gnat) echo gcc-ada ;; gprbuild) echo gprbuild ;; gtkada) echo "gtkada (from the AUR)" ;;
        gtk3) echo gtk3 ;; epoxy) echo libepoxy ;; zlib) echo zlib ;;
        pulse) echo libpulse ;; pkgconfig) echo pkgconf ;; curl) echo curl ;;
        ffmpeg) echo ffmpeg ;; esac; }
elif have zypper; then
    PM="sudo zypper install"
    pkg () { case $1 in
        gnat) echo gcc-ada ;; gprbuild) echo gprbuild ;; gtkada) echo gtkada-devel ;;
        gtk3) echo gtk3-devel ;; epoxy) echo libepoxy-devel ;; zlib) echo zlib-devel ;;
        pulse) echo libpulse-devel ;; pkgconfig) echo pkg-config ;; curl) echo curl ;;
        ffmpeg) echo ffmpeg ;; esac; }
else
    PM=""
    pkg () { echo "$1"; }
fi

describe () { case $1 in
    gnat) echo "GNAT, the Ada compiler" ;; gprbuild) echo "gprbuild, the Ada build tool" ;;
    gtkada) echo "GtkAda, the Ada binding to GTK 3" ;; gtk3) echo "GTK 3 (development files)" ;;
    epoxy) echo "libepoxy, for OpenGL" ;; zlib) echo "zlib, for the compressed tiles" ;;
    pulse) echo "PulseAudio's libpulse-simple, for the sound" ;;
    pkgconfig) echo "pkg-config, to find the libraries" ;;
    curl) echo "curl, to download the map data and the ground heights" ;;
    ffmpeg) echo "ffmpeg, to record videos with F9 (optional)" ;; esac; }

PACKAGES=""
if [ -n "$MISSING" ]; then
    echo "Dérive needs these, which are not installed:"
    for M in $MISSING; do
        echo "  - $(describe "$M")"
        PACKAGES="$PACKAGES $(pkg "$M")"
    done
fi
if [ -n "$OPTIONAL" ]; then
    echo "Optional, not installed:"
    for M in $OPTIONAL; do
        echo "  - $(describe "$M")"
    done
fi
ALL="$PACKAGES"
for M in $OPTIONAL; do ALL="$ALL $(pkg "$M")"; done

if [ -z "$PM" ]; then
    echo "Install them with your system's package manager:$ALL"
    [ -n "$MISSING" ] && exit 1 || exit 0
fi

echo "To install:  $PM$ALL"
case "$ALL" in *AUR*) echo "(GtkAda is in the AUR on Arch, e.g. with yay -S gtkada)" ;; esac

# Offer to install, only when someone is there to answer
if [ -t 0 ] && [ -t 1 ]; then
    printf "Install now? [y/N] "
    read -r ANSWER
    case "$ANSWER" in
        y|Y|yes|Yes)
            # shellcheck disable=SC2086
            $PM $(echo "$ALL" | sed 's/(from the AUR)//; s/ gtkada / /') && exec "$0"
            ;;
    esac
fi
[ -n "$MISSING" ] && exit 1 || exit 0
