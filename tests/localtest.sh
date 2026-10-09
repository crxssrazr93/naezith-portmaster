#!/bin/bash
# Device-like test on an x86_64 Linux PC: the game's own x86_64 binary with gl4es (GLES 2.0
# backend, like the handheld), the Steam stub, a an offscreen Xvfb server (no window on the desktop) at a handheld resolution and
# a scripted virtual gamepad (tests/vpad.py). The game runs inside bwrap with only the virtual
# pad visible under /dev/input, so it is joystick 0 as on a handheld.
#
# Usage: tests/localtest.sh <WxH> "<vpad script>" [tag]
# Env:   GAME_DIR  Linux Steam build of the game (default: port/naezith/gamedata)
#        GL4ES_LIB directory holding gl4es' libGL.so.1 for x86_64 (build: github.com/ptitSeb/gl4es)
#        DISP      X display number for the test server (default 5)
# Output: tests/out/<tag>/ with screenshots, recordings and game.log; prints peak RSS.
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"
RES="${1:-640x480}"; SCRIPT="$2"; TAG="${3:-run}"; D="${DISP:-5}"
GAME_DIR="${GAME_DIR:-$R/port/naezith/gamedata}"
: "${GL4ES_LIB:?set GL4ES_LIB to a directory with gl4es libGL.so.1}"
OUT="$R/tests/out/$TAG"; mkdir -p "$OUT"; rm -f "$OUT"/*.png "$OUT"/*.mp4
# the game's bundled libraries minus the ones the port drops (see the launcher)
LIBS="$R/tests/out/lib"; rm -rf "$LIBS"; mkdir -p "$LIBS"
for f in "$GAME_DIR"/lib/*; do case "$(basename "$f")" in libm.so.6|libstdc++.so.6|libsteam_api.so) ;; *) ln -s "$f" "$LIBS/";; esac; done
while [ -e "/tmp/.X$D-lock" ]; do sleep 0.5; done
unset WAYLAND_DISPLAY; export SDL_VIDEODRIVER=x11 XDG_RUNTIME_DIR=/tmp/xdg-offscreen; mkdir -p -m 700 /tmp/xdg-offscreen; Xvfb :$D -screen 0 "$RES"x24 -nolisten tcp >/dev/null 2>&1 & XPID=$!
for i in $(seq 40); do DISPLAY=:$D xdpyinfo >/dev/null 2>&1 && break; sleep 0.5; done
DISPLAY=:$D xdpyinfo >/dev/null 2>&1 || { echo "offscreen X server :$D did not start"; kill $XPID 2>/dev/null; exit 1; }
before=$(ls /dev/input/)
REC_CMD="ffmpeg -y -loglevel error -f x11grab -framerate 30 -video_size $RES -i :$D -c:v libx264 -preset ultrafast $OUT/{name}.mp4" \
SHOT_CMD="DISPLAY=:$D import -window root $OUT/{name}.png 2>/dev/null" \
  python3 "$R/tests/vpad.py" "wait 2; $SCRIPT" & VPID=$!
sleep 2
new=$(comm -13 <(echo "$before" | sort) <(ls /dev/input/ | sort))
binds=(); for n in $new; do binds+=(--dev-bind "/dev/input/$n" "/dev/input/$n"); done
cd "$GAME_DIR"
DISPLAY=:$D LIBGL_ES=2 LIBGL_GL=21 \
LD_LIBRARY_PATH="$R/port/naezith/steamstub:$GL4ES_LIB:$LIBS" \
  bwrap --die-with-parent --dev-bind / / --tmpfs /dev/input "${binds[@]}" ./naezith > "$OUT/game.log" 2>&1 & GPID=$!
wait $VPID
GAME=$(pgrep -P $GPID naezith || echo $GPID)
PEAK=$(awk '/VmHWM/{print int($2/1024)}' /proc/$GAME/status 2>/dev/null)
ALIVE=$(kill -0 $GPID 2>/dev/null && echo yes || echo no)
kill $GAME 2>/dev/null; wait $GPID 2>/dev/null; kill $XPID 2>/dev/null; wait $XPID 2>/dev/null
echo "alive=$ALIVE peakRSS=${PEAK}MB files: $(ls "$OUT" | grep -E 'png|mp4' | tr '\n' ' ')"
