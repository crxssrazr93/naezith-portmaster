# Remnants of Naezith for PortMaster

A [PortMaster](https://portmaster.games/) port of [Remnants of Naezith](https://store.steampowered.com/app/590590/Remnants_of_Naezith/) (Tolga Ay, 2018), a grappling hook precision platformer, for Linux handhelds with ARM64 CPUs.

The port runs the game's own x86_64 Linux build. No game files are included: you supply them from your Steam copy.

| | |
|--|--|
| Status | Runs on an Anbernic RG35XX H (Knulli): about 37 fps in levels, 60 in menus, sound and controls working. |
| Tester reports | Works on an RG40XX-H (muOS) and an R36S (dArkOS), controls as expected. |
| Target | aarch64 PortMaster devices (Knulli, muOS, ROCKNIX, ArkOS and others), 1 GB RAM or more |
| Runtimes | Westonpack (`weston_pkg_0.2`), bundled box64 |
| Memory | about 600 MB on the device (box64, gl4es and the GPU share RAM), about 190 MB natively on a PC |

## For players

1. Buy the game on Steam.
2. Open the [Steam console](https://steamcommunity.com/sharedfiles/filedetails/?id=873543244) and download the Linux build:
   ```
   download_depot 590590 590591 271869356780381257
   download_depot 590590 590593 1978461534159709910
   ```
3. Merge both download folders and copy everything (the `naezith` binary plus the `lib` and `data` folders) into `ports/naezith/gamedata/` on your device.
4. Start **Remnants of Naezith** from the Ports menu.

Controls, notes and known limitations are in [port/README.md](port/README.md), the file that ships with the port.

## How it works

```
Remnants of Naezith.sh (PortMaster launcher)
  └ westonwrap.sh headless noop kiosk crusty_glx_gl4es   (Weston + Xwayland, OpenGL on GLES via gl4es)
      └ box64                                             (x86_64 to aarch64 dynamic recompiler)
          └ naezith (the game's x86_64 Linux binary, SFML 2.5)
              ├ gamedata/lib/*            the game's own SFML, OpenAL and friends (x86_64)
              ├ box64/box64-x86_64-linux-gnu/  box64's x86_64 libstdc++ and libgcc_s, libvorbisenc,
              │                                and fallbacks for Ogg, Vorbis, FLAC, libbsd
              ├ steamstub/libsteam_api.so stand in for the Steam API (x86_64)
              └ glxfix/libglxfix.so       works around Westonpack's GLX visual answers (x86_64)
```

* **box64** translates the x86_64 game and its x86_64 libraries; system libraries such as libc, libGL and libX11 are wrapped to the device's native ones.
* **Westonpack** supplies a Weston compositor with Xwayland, since the game is an X11 program, and gl4es, since the game uses desktop OpenGL and handhelds only have OpenGL ES.
* **The Steam stub** lets the game start without Steam. The game refuses to run when `SteamAPI_Init` fails (also with a `steam_appid.txt`), so the stub reports Steam as running but not logged on; the game then uses its own offline mode. Every Steam interface method returns 0, so it performs no ownership checks and bypasses no DRM (the game has none), in the same way as the merged Papers, Please and Osmos ports. See [port/naezith/steamstub/readme.txt](port/naezith/steamstub/readme.txt) and the source next to it.
* **glxfix** fixes window creation under Westonpack: its GLX layer answers SFML's visual queries in a way that leaves SFML with no visual, and the X server then rejects the window's colormap. The preload hands `XCreateColormap` the default visual in that case. Source: [port/naezith/glxfix/glxfix.c](port/naezith/glxfix/glxfix.c).
* **The launcher** moves aside the game's bundled `libm.so.6` and `libstdc++.so.6` (the game's own launcher does the same, they are older than the system's) and its real `libsteam_api.so`, mounts Westonpack and starts the game through box64.

The full story, including every approach that failed and why, is in [docs/PORTING.md](docs/PORTING.md).

## Repository layout

| Path | Contents |
|--|--|
| `port/` | Exactly what ships to `ports/` on the device |
| `build/` | Build environment (Dockerfile), `build.sh` (box64, Steam stub, x86 libraries), `package.sh` |
| `tests/` | Local test harnesses (device like runs on a PC, a mock PortMaster launcher test, a virtual gamepad) and device tools in `tests/device/` |
| `docs/` | Porting notes |

## Building

Requirements: Docker, git, zip.

```
build/build.sh      # box64 (aarch64, cross compiled against glibc 2.31), the Steam stub and glxfix
build/package.sh    # naezith.zip, ready to unzip into ports/
```

box64 is pinned to v0.4.4 (`build/build.sh v0.4.5` builds another tag). Building against Ubuntu 20.04 keeps the binary compatible with every current PortMaster CFW.

## Testing on a PC

The harnesses run the x86_64 game natively with gl4es in GLES 2.0 mode, which is close to what the device does, on a private Xwayland server at a handheld resolution, driven by a virtual gamepad.

Requirements: Xwayland, bubblewrap, ImageMagick, ffmpeg, Python 3 with `python-evdev`, write access to `/dev/uinput`, and an x86_64 build of [gl4es](https://github.com/ptitSeb/gl4es).

```
export GAME_DIR=/path/to/naezith/linux/build GL4ES_LIB=/path/to/gl4es/lib
tests/localtest.sh 640x480 "wait 14; shot menu; press A; wait 5; shot next"
tests/resolutions.sh                   # 640x480, 480x320, 720x720, 854x480, 1280x720, 1920x1152
tests/launchertest.sh "wait 20; shot started"
```

`tests/vpad.py` documents the step syntax (`wait`, `press`, `tap`, `hold`, `on`/`off`, `shot`, `rec`).

## Testing on a device

`tests/device/` drives a Knulli device over SSH (password in `~/.ssh/knulli.pass`, host in `KNULLI_HOST`): `knulli.sh` runs a command, `knulli_shot.sh` saves a screenshot from the framebuffer, `devpad.py` (copied to the device) presses the device's own buttons by their printed labels, and `fbfps.py` (on the device) counts presented frames per second. Games start and stop through EmulationStation's web API:

```
tests/device/knulli.sh 'curl -s -d "/userdata/roms/ports/Remnants of Naezith.sh" localhost:1234/launch'
tests/device/knulli.sh 'python3 /userdata/system/devpad.py "wait 30; press A; wait 3; press A"'
tests/device/knulli_shot.sh shot.png
tests/device/knulli.sh 'python3 /userdata/system/devpad.py "chord SELECT START"'
```

## Known limitations

* Online features (global rankings, score submission) are unavailable; the game runs in its own offline mode.
* The interface scales with the screen height and has no separate scale setting. On 480x320 screens the smallest menu text is hard to read. On 4:3 and square screens a few labels on the level map overlap and the offline notice is cut off at the right edge.
* ROCKNIX needs Panfrost (as for every Westonpack port).

## Credits and licenses

* Remnants of Naezith by Tolga Ay. Not affiliated; buy the game to play it.
* [box64](https://github.com/ptitSeb/box64) and [gl4es](https://github.com/ptitSeb/gl4es) by ptitSeb (MIT), [Westonpack](https://github.com/binarycounter/Westonpack) by binarycounter, the PortMaster team.
* The x86_64 audio libraries are unmodified Ubuntu 20.04 packages. box64 uses the device's native Ogg, Vorbis, FLAC and libbsd when present; the bundled copies are fallbacks for firmwares without them, except libvorbisenc, which box64 cannot wrap. All licence files are in `port/naezith/licenses/`.
* box64's `x64lib` copies of `libstdc++.so.6` and `libgcc_s.so.1` (GCC runtime library exception).
* Everything written for this port (launcher, Steam stub, glxfix, scripts, docs) is MIT licensed, see [LICENSE](LICENSE).
