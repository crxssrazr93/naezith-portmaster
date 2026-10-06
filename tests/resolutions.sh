#!/bin/bash
# Runs tests/localtest.sh at the common PortMaster screen shapes and enters the first level,
# capturing the menu, level map, in level HUD and pause menu at each.
R="$(cd "$(dirname "$0")/.." && pwd)"
for r in 640x480 480x320 720x720 854x480 1280x720 1920x1152; do
  "$R/tests/localtest.sh" $r "wait 14; shot a_intro; press A; wait 4; shot b_menu; press A; wait 6; shot c_story; press A; wait 8; shot d_map; press A; wait 8; shot e_level; hold right 1.5; press A; wait 1; shot f_play; press START; wait 2; shot g_pause" res_$r
done
