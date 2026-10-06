#!/bin/bash
# Zips port/ into naezith.zip, laid out the way PortMaster's tools/build_release.py builds it
# (metadata moved into the port folder, README.md renamed to naezith.md).
set -e
R="$(cd "$(dirname "$0")/.." && pwd)"
[ -x "$R/port/naezith/box64/box64" ] || { echo "run build/build.sh first"; exit 1; }
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp "$R/port/Remnants of Naezith.sh" "$stage/"
cp -r "$R/port/naezith" "$stage/"
rm -rf "$stage/naezith/gamedata" "$stage/naezith/log.txt" "$stage/naezith/log.prev.txt"
mkdir "$stage/naezith/gamedata"
cp "$R/port/naezith/gamedata/Put Linux game files here" "$stage/naezith/gamedata/"
cp "$R/port/port.json" "$R/port/gameinfo.xml" "$R/port/screenshot.png" "$R/port/cover.png" "$stage/naezith/"
cp "$R/port/README.md" "$stage/naezith/naezith.md"
rm -f "$R/naezith.zip"
(cd "$stage" && zip -9 -r -q -X "$R/naezith.zip" .)
ls -l "$R/naezith.zip"
