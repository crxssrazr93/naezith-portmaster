#!/bin/bash

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

> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

if [ ! -f "$DATADIR/$BINARY" ]; then
  pm_message "Game files missing. Copy the Linux Steam build of Remnants of Naezith into ports/naezith/gamedata (see README)."
  sleep 5
  exit 1
fi

if [ "$(md5sum "$DATADIR/$BINARY" | cut -d' ' -f1)" != "$KNOWN_MD5" ]; then
  echo "Warning: unknown game version, this port was tested with the 22.03.2024 Linux build."
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

# rocknix mode on rocknix panfrost/freedreno; libmali not supported
if [[ "$CFW_NAME" = "ROCKNIX" ]]; then
  export rocknix_mode=1
fi

# The game reads the controller natively (SFML joystick); gptokeyb only provides the exit hotkey.
# gptokeyb1 is unresponsive on muOS, where gptokeyb2 is used instead (as in the Dicey Dungeons port)
if [ "$CFW_NAME" = "muOS" ] && [ -n "$GPTOKEYB2" ]; then
  $GPTOKEYB2 "$BINARY" -c "$GAMEDIR/naezith.gptk" &
else
  $GPTOKEYB "$BINARY" -c "$GAMEDIR/naezith.gptk" &
fi
pm_platform_helper "$GAMEDIR/box64/box64"

cd "$DATADIR"
# The game aborts when these folders are missing (they ship empty in the depot)
mkdir -p "$DATADIR/replays/import" "$DATADIR/screenshots"

# glxfix works around crusty answering SFML's visual queries wrongly (see glxfix/glxfix.c).
# westonwrap replaces XDG_RUNTIME_DIR; pass the real one on so OpenAL can reach PipeWire for sound.
REAL_XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

$ESUDO env \
BOX64_LD_LIBRARY_PATH="$GAMEDIR/steamstub:$DATADIR/lib:$GAMEDIR/box64/box64-x86_64-linux-gnu" \
BOX64_LD_PRELOAD="$GAMEDIR/steamstub/libsteam_api.so:$GAMEDIR/glxfix/libglxfix.so" \
$weston_dir/westonwrap.sh headless noop kiosk crusty_glx_gl4es \
XDG_RUNTIME_DIR="$REAL_XDG_RUNTIME_DIR" $GAMEDIR/box64/box64 ./$BINARY

# Clean up after ourselves
$ESUDO $weston_dir/westonwrap.sh cleanup
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
  $ESUDO umount "${weston_dir}"
fi
pm_finish
