#!/bin/bash
# PORTMASTER: naezith.zip, Remnants of Naezith.sh

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt

[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"

get_controls

GAMEDIR=/$directory/ports/naezith
DATADIR=$GAMEDIR/gamedata
BINARY="naezith"
KNOWN_MD5="f18add699bbc6c73a8521438139ac147"

cd "$GAMEDIR"

# the previous run's log is kept as log.prev.txt
mv -f "$GAMEDIR/log.txt" "$GAMEDIR/log.prev.txt" 2>/dev/null
# tee gets a relative path: gptokeyb's exit hotkey runs pkill -f naezith, which matches every
# command line containing the word, and a tee writing to .../naezith/log.txt died with the game,
# ending the log and then the launcher (AmberELEC reports that exit as an error)
> "$GAMEDIR/log.txt" && exec > >(tee log.txt) 2>&1
# Device, system and memory details for bug reports (tools/portlog.sh)
# The files a bug report needs; named in log.txt and on screen only when something fails
export PORT_REPORT_FILES="ports/naezith/log.txt"
source "$GAMEDIR/tools/portlog.sh"
port_header "Remnants of Naezith launcher"

if [ ! -f "$DATADIR/$BINARY" ]; then
  pm_message "Game files missing. Copy the Linux Steam build of Remnants of Naezith into ports/naezith/gamedata (see README)."
  sleep 5
  exit 1
fi

if [ "$(md5sum "$DATADIR/$BINARY" | cut -d' ' -f1)" != "$KNOWN_MD5" ]; then
  port_log "WARNING: unknown game version (md5 $(md5sum "$DATADIR/$BINARY" | cut -c1-32)), this port was tested with the 22.03.2024 Linux build"
else
  port_log "game version: 22.03.2024 Linux build (md5 matches)"
fi

# Tidy up gamedata: the bundled libm and libstdc++ break on newer systems (the game's own
# launcher drops them too), and Steam is replaced by steamstub/ (see steamstub/readme.txt).
for lib in libm.so.6 libstdc++.so.6 libsteam_api.so; do
  [ -f "$DATADIR/lib/$lib" ] && mv "$DATADIR/lib/$lib" "$DATADIR/lib/$lib.disabled"
done
find "$DATADIR" -maxdepth 1 -name "*.sh" -delete
$ESUDO chmod a+x "$DATADIR/$BINARY" "$GAMEDIR/box64/box64"

# Mount Weston runtime
weston_dir=/tmp/weston
$ESUDO mkdir -p "${weston_dir}"
weston_runtime="weston_pkg_0.2"
if [ ! -f "$controlfolder/libs/${weston_runtime}.squashfs" ]; then
  if [ ! -f "$controlfolder/harbourmaster" ]; then
    pm_message "This port requires the latest PortMaster to run, please go to https://portmaster.games/ for more info."
    sleep 5
    exit 1
  fi
  $ESUDO $controlfolder/harbourmaster --quiet --no-check runtime_check "${weston_runtime}.squashfs"
fi
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
  $ESUDO umount "${weston_dir}"
fi
$ESUDO mount "$controlfolder/libs/${weston_runtime}.squashfs" "${weston_dir}"
port_mounted "$weston_runtime" "$weston_dir/westonwrap.sh"

# rocknix mode on rocknix panfrost/freedreno; libmali not supported
if [[ "$CFW_NAME" = "ROCKNIX" ]]; then
  export rocknix_mode=1
fi

# The game reads the controller natively (SFML joystick); gptokeyb only provides the exit hotkey.
# Two pad layouts the game cannot read, seen on the RG552 under AmberELEC; the first joystick's
# capability bitmaps decide, and gptokeyb covers them with the game's keyboard controls:
# - no hat axes: the D-pad sends buttons, but the game reads the D-pad from the hat only, so the
#   D-pad is mapped to the arrow keys (move and menus)
# - no BTN_START: Start is a later button and the game's Pause (button 7) lands on R2, so Start is
#   mapped to Escape (Pause in game, Back in menus)
gptk="$GAMEDIR/naezith.gptk"
pad_map=""
for ev in /sys/class/input/event*/device; do
  [ -d "$ev/js0" ] || continue
  abs="$(awk '{ print $NF }' "$ev/capabilities/abs" 2>/dev/null)"
  if [ $(( 0x${abs:-0} & 0x10000 )) -eq 0 ]; then
    pad_map+='s/^up = .*/up = up/;s/^down = .*/down = down/;s/^left = .*/left = left/;s/^right = .*/right = right/;'
    port_log "the pad has no hat axes, so the D-pad is mapped to the arrow keys"
  fi
  # BTN_START is 0x13b: bit 59 of the fifth 64 bit word, counted from the end of the bitmap
  keys=($(cat "$ev/capabilities/key" 2>/dev/null))
  word=0
  [ ${#keys[@]} -ge 5 ] && word="${keys[${#keys[@]} - 5]}"
  if [ $(( (0x$word >> 59) & 1 )) -eq 0 ]; then
    pad_map+='s/^start = .*/start = esc/;'
    port_log "the pad has no BTN_START, so Start is mapped to Escape"
  fi
  break
done
if [ -n "$pad_map" ]; then
  sed "$pad_map" "$gptk" > "$GAMEDIR/naezith.pad.gptk"
  gptk="$GAMEDIR/naezith.pad.gptk"
fi
# gptokeyb1 is unresponsive on muOS, where gptokeyb2 is used instead (as in the Dicey Dungeons port)
if [ "$CFW_NAME" = "muOS" ] && [ -n "$GPTOKEYB2" ]; then
  $GPTOKEYB2 "$BINARY" -c "$gptk" &
else
  $GPTOKEYB "$BINARY" -c "$gptk" &
fi
pm_platform_helper "$GAMEDIR/box64/box64"

cd "$DATADIR"
# The game aborts when these folders are missing (they ship empty in the depot)
mkdir -p "$DATADIR/replays/import" "$DATADIR/screenshots"

# The game's View Height (Settings, Graphics) defaults to 1080, which leaves the level and its text
# tiny on 480 line screens. Set 720 once; a value chosen in the game later is kept. The marker sits
# next to the settings (older releases kept it in the port folder), so it travels with them.
if [ "${DISPLAY_HEIGHT:-480}" -le 480 ] && [ ! -f "$DATADIR/data/user/.view_height_set" ] &&
   [ ! -f "$GAMEDIR/.view_height_set" ]; then
  cfg="$DATADIR/data/user/settings.cfg"
  if [ -f "$cfg" ]; then
    sed -i 's/"default_view_height": *[0-9.]*/"default_view_height": 720.0/' "$cfg"
  else
    mkdir -p "$(dirname "$cfg")"
    printf '{\n    "settings": {\n        "default_view_height": 720.0\n    }\n}\n' > "$cfg"
  fi
  touch "$DATADIR/data/user/.view_height_set"
fi

# The leaderboards are offline on handhelds, and the game says so in large red text on the title
# screen in every language; blank those two strings (tip from a tester).
for lang in "$DATADIR"/data/lang/*.json; do
  grep -qE '"offline_mode(_warning)?": *"[^"]' "$lang" &&
    sed -i -E 's/("offline_mode(_warning)?": *)"[^"]*"/\1""/' "$lang"
done

# glxfix works around crusty answering SFML's visual queries wrongly (see glxfix/glxfix.c).
# westonwrap replaces XDG_RUNTIME_DIR; pass the real one on so OpenAL can reach PipeWire for sound.
REAL_XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# box64's settings go to westonwrap as VAR=value arguments, which it puts on the game's command
# line: westonwrap sources PortMaster's control files first, and on ROCKNIX the game then started
# with the firmware's BOX64_LD_LIBRARY_PATH (/usr/share/box64/lib) instead of the port's, so box64
# could not find the game's libraries. BOX64_LOG=1 names a library that fails to load.
port_log "starting the game"
$ESUDO $weston_dir/westonwrap.sh headless noop kiosk crusty_glx_gl4es \
  BOX64_LOG=1 BOX64_SHOWSEGV=1 BOX64_SHOWBT=1 \
  BOX64_LD_LIBRARY_PATH="$GAMEDIR/steamstub:$DATADIR/lib:$GAMEDIR/box64/box64-x86_64-linux-gnu" \
  BOX64_LD_PRELOAD="$GAMEDIR/steamstub/libsteam_api.so:$GAMEDIR/glxfix/libglxfix.so" \
  XDG_RUNTIME_DIR="$REAL_XDG_RUNTIME_DIR" $GAMEDIR/box64/box64 ./$BINARY

# Clean up after ourselves
port_exit
$ESUDO $weston_dir/westonwrap.sh cleanup
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
  $ESUDO umount "${weston_dir}"
fi
pm_finish
