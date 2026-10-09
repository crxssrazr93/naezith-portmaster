#!/bin/bash
# Runs the real launcher (port/Remnants of Naezith.sh) on an x86_64 PC against a mock
# PortMaster install: control.txt, mount/umount (symlinks), westonwrap.sh (an offscreen Xvfb server (no window on the desktop)
# with gl4es) and box64 (runs the x86_64 binary natively, mapping BOX64_LD_* to LD_*).
# Checks the launcher's file handling, library setup and Steam stub wiring.
#
# Usage: tests/launchertest.sh "<vpad script>" [tag]
# Env:   GAME_DIR, GL4ES_LIB, DISP as for tests/localtest.sh
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$1"; TAG="${2:-launcher}"; D="${DISP:-5}"
GAME_DIR="${GAME_DIR:-$R/port/naezith/gamedata}"
: "${GL4ES_LIB:?set GL4ES_LIB to a directory with gl4es libGL.so.1}"
ROOT="$R/tests/out/mockroot"; OUT="$R/tests/out/$TAG"; mkdir -p "$OUT"; rm -f "$OUT"/*.mp4 "$OUT"/*.png
rm -rf "$ROOT"; mkdir -p "$ROOT/ports" "$ROOT/PortMaster/libs" "$ROOT/bin" "$ROOT/weston"
cp -r "$R/port/." "$ROOT/ports/"
cp -r "$GAME_DIR/." "$ROOT/ports/naezith/gamedata/"
touch "$ROOT/PortMaster/libs/weston_pkg_0.2.squashfs"
cat > "$ROOT/PortMaster/control.txt" <<EOC
directory="${ROOT#/}"; ESUDO=""; GPTOKEYB="true"; GPTOKEYB2="true"; CFW_NAME="mock"; PM_CAN_MOUNT="Y"
DISPLAY_WIDTH=640; DISPLAY_HEIGHT=480
get_controls() { :; }; pm_message() { echo "PM_MESSAGE: \$*"; }; pm_finish() { echo PM_FINISH; }; pm_platform_helper() { :; }
EOC
printf '#!/bin/bash\nrmdir "$2" 2>/dev/null; rm -f "$2"; ln -s "%s" "$2"\n' "$ROOT/weston" > "$ROOT/bin/mount"
printf '#!/bin/bash\n[ -L "$1" ] && rm -f "$1"; exit 0\n' > "$ROOT/bin/umount"
cat > "$ROOT/weston/westonwrap.sh" <<EOW
#!/bin/bash
[ "\$1" = cleanup ] && { echo WESTON_CLEANUP; exit 0; }
echo "WESTONWRAP args: \$1 \$2 \$3 \$4"; shift 4
unset WAYLAND_DISPLAY; Xvfb :$D -screen 0 640x480x24 -nolisten tcp >/dev/null 2>&1 & XP=\$!
for i in \$(seq 40); do DISPLAY=:$D xdpyinfo >/dev/null 2>&1 && break; sleep 0.5; done
DISPLAY=:$D LIBGL_ES=2 LIBGL_GL=21 LD_LIBRARY_PATH="$GL4ES_LIB" env "\$@"   # args after the mode are VAR=value pairs, then the command
kill \$XP; wait \$XP
EOW
# mock box64: run the x86_64 binary directly with the library setup box64 would get
mv "$ROOT/ports/naezith/box64/box64" "$ROOT/ports/naezith/box64/box64.real" 2>/dev/null || true
cat > "$ROOT/ports/naezith/box64/box64" <<'EOB'
#!/bin/bash
echo "BOX64 mock: LD_LIBRARY_PATH=$BOX64_LD_LIBRARY_PATH PRELOAD=$BOX64_LD_PRELOAD cmd=$*"
LD_LIBRARY_PATH="$BOX64_LD_LIBRARY_PATH:$LD_LIBRARY_PATH" LD_PRELOAD="$BOX64_LD_PRELOAD" exec "$@"
EOB
chmod +x "$ROOT"/bin/* "$ROOT/weston/westonwrap.sh" "$ROOT/ports/naezith/box64/box64"
REC_CMD="ffmpeg -y -loglevel error -f x11grab -framerate 30 -video_size 640x480 -i :$D -c:v libx264 -preset ultrafast $OUT/{name}.mp4" \
SHOT_CMD="DISPLAY=:$D import -window root $OUT/{name}.png 2>/dev/null" python3 "$R/tests/vpad.py" "$SCRIPT" > /dev/null & VP=$!
( export PATH="$ROOT/bin:$PATH" XDG_DATA_HOME="$ROOT/xdg"; mkdir -p "$ROOT/xdg"; ln -sfn "$ROOT/PortMaster" "$ROOT/xdg/PortMaster"
  timeout 180 bash "$ROOT/ports/Remnants of Naezith.sh" ) > "$OUT/launcher.out" 2>&1 & LP=$!
wait $VP
for p in $(pgrep -f "[g]amedata/naezith$|^\./[n]aezith$"); do kill $p; done; wait $LP
echo "--- launcher output"; grep -vE "^LIBGL|Enabling Core" "$OUT/launcher.out" | head -30
echo "--- gamedata/lib after run"; ls "$ROOT/ports/naezith/gamedata/lib" | tr '\n' ' '; echo
