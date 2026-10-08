# Porting notes: Remnants of Naezith

A record of how this port was made, what was measured, and every approach that failed, so the next port (or the next person) does not walk the same dead ends.

## 1. Survey

| Item | Finding |
|--|--|
| Store | Steam app 590590. Linux build in depots 590591 and 590593. |
| Engine | Custom C++ on SFML 2.5. Desktop OpenGL (legacy profile) through libX11. |
| Binary | `naezith`, x86_64 ELF, dynamically linked. Tested build MD5 `f18add699bbc6c73a8521438139ac147`. |
| Bundled libraries | SFML 2.5, OpenAL, sndio, plus old `libm.so.6` and `libstdc++.so.6` |
| Steam | Links `libsteam_api.so` and stops on an error screen ("STEAM API Init failed") without it |
| Memory | About 189 MB peak RSS at 1920x1080 and at handheld resolutions |

The game has no ARM build and no source release, so the route is the one used by other native x86_64 Linux ports such as Papers, Please: run the binary under box64, inside Westonpack for X11 and OpenGL on GLES.

## 2. Pieces

### box64

Cross compiled from source (v0.4.4, dynarec on) in Ubuntu 20.04 so it needs glibc 2.29 at most and runs on every current CFW. Ubuntu 20.04's CMake 3.16 is too old for box64 (3.19 or newer), so the build uses a portable CMake. See `build/build.sh`.

### x86_64 libraries

box64 wraps the common native libraries but the game's SFML audio module needs Ogg, Vorbis, VorbisEnc, VorbisFile and FLAC, and something in the chain wants libbsd. These come as unmodified Ubuntu 20.04 amd64 packages (`build/debs/`) and ship in `box64/box64-x86_64-linux-gnu/` (the folder name merged box64 ports use), with their copyright files in `licenses/`. Measured on the device without them: box64 wraps libbsd, FLAC, Ogg, Vorbis, VorbisFile and OpenAL with the native libraries whenever the firmware has them (Knulli does), and prefers those over the bundled copies. libstdc++, libgcc_s and VorbisEnc are never wrapped, so those three are required; the other five are fallbacks for firmwares without native copies.

### Steam stub

`port/naezith/steamstub/steamstub.c` implements the 19 flat Steam API functions the binary imports:

* `SteamAPI_Init`, `SteamAPI_IsSteamRunning` return true; `SteamAPI_RestartAppIfNecessary` returns false.
* `SteamInternal_CreateInterface` and the accessor functions return a generic dummy interface: a valid object whose virtual methods all return 0. The game then sees no logged on user and switches to its own offline mode ("OFFLINE MODE: can't submit scores"); title, menu and levels were checked on the device. Any ownership query would answer false.
* `SteamInternal_ContextInit` calls the game's context initializer exactly once and returns the game's own context storage.

The stub contains no ownership or license checks and the game has no DRM to bypass; it only replaces the client library so the game can start without the Steam client. Using the game's own `libsteam_api.so` with a `steam_appid.txt` instead was tested and does not work: the game prints "STEAM API Init failed" and exits. The approach matches binarycounter's merged stubs for Papers, Please and Osmos, and `steamstub/readme.txt` explains it in the same way.

### Launcher

`port/Remnants of Naezith.sh` follows the standard PortMaster structure:

1. Checks that the game binary is present and warns on an unknown MD5 (other versions may work).
2. Renames `lib/libm.so.6`, `lib/libstdc++.so.6` and `lib/libsteam_api.so` to `*.disabled`. The first two are older than the device's and break symbol resolution (the game's own `naezith.sh` drops them too); the third is replaced by the stub.
3. Mounts `weston_pkg_0.2` and starts `westonwrap.sh headless noop kiosk crusty_glx_gl4es` with box64 and the game, with `BOX64_LD_LIBRARY_PATH` set to the stub first, then the game's libraries, then the bundled x86 libraries, and `BOX64_LD_PRELOAD` set to the stub.
4. gptokeyb2 only supplies the PortMaster exit hotkey (Select + Start); the game reads the controller itself.

## 3. Testing approach

All testing so far happened on an x86_64 PC, set up to resemble a handheld as closely as possible:

* The game's x86_64 binary runs natively with **gl4es in GLES 2.0 mode** (`LIBGL_ES=2 LIBGL_GL=21`), which is the graphics path the device uses.
* A **rootful Xwayland** server at the handheld's resolution stands in for Weston.
* A **virtual Xbox pad** created with uinput (`tests/vpad.py`) drives the game from a step script and takes screenshots and recordings.
* The game runs inside **bubblewrap** with an empty `/dev/input` except for the virtual pad, so the pad is joystick 0, as on a handheld (see failure 5 below).
* `tests/launchertest.sh` runs the real launcher against a mock PortMaster install, to check the file handling and the library and stub wiring.

## 4. What failed and why

1. **Bundled libm and libstdc++.** The game failed with GLIBC symbol version errors. The bundled copies are older than the system's; removing them (as the game's own launcher does) fixed it.
2. **Stub returning null or zeroed interfaces.** The first stub returned a zeroed object from `SteamInternal_CreateInterface`. The game's context setup calls virtual methods on `ISteamClient` and crashed on the null vtable. Fixed with a generic dummy vtable. Its methods first returned further dummy objects; they now return 0, which the game handles (offline mode), so no query can be answered with a misleading "yes".
3. **Stub clearing the context storage.** `SteamInternal_ContextInit` first cleared 512 bytes of the context struct before calling the initializer. The struct lives in the game's `.bss` and is only about 128 bytes, so this corrupted `std::cout` and later output crashed. Found by mapping the crash address against the real PIE base (0x555555400000). Fix: never write to the context storage; only call the game's init callback once and return the storage.
4. **Renaming the real `libsteam_api.so` without a replacement on the search path.** The game could not load at all. The stub directory now comes first in `BOX64_LD_LIBRARY_PATH` and the stub is preloaded.
5. **A phantom joystick.** On the test PC a mouse driver exposes a `js0` device that took joystick slot 0, so the virtual pad's input was ignored. The tests now run the game in bubblewrap with only the virtual pad in `/dev/input`. On handhelds the built in controls are the first joystick, so this only affected testing.
6. **Unverified metadata.** An early draft of the package listed the wrong developer, release date and description, and described controls that had not been verified (a hook button). All metadata now comes from the Steam store API, and the README only lists controls that were observed in testing.
7. **Test harness races.** Starting the game before a fresh Xwayland server accepted connections, or running two harnesses on the same display number, gave black or missing screenshots. The harnesses now wait for the server and take a display number from `DISP`.

## 5. Screen sizes

Tested at the common PortMaster resolutions by entering the first level and opening the pause menu (`tests/resolutions.sh`):

| Resolution | Shape | Result |
|--|--|--|
| 640x480 | 4:3 | Fills the screen. On the level map the zone name overlaps the mode title. |
| 480x320 | 3:2 | Fills the screen. Small menu text (pause menu items, hints) is about 4 px tall. |
| 720x720 | 1:1 | Level HUD and pause menu fine. The red offline notice is cut off at the right edge. |
| 854x480 | 16:9 | Clean |
| 1280x720 | 16:9 | Clean |
| 1920x1152 | 5:3 | Clean |

The game scales its whole interface with the window height and has no interface scale setting, so text size relative to the screen cannot be changed from outside the game. The overlaps come from the game laying out its menus for widescreen.

## 6. On the device

Tested on an Anbernic RG35XX H (Allwinner H700, Mali-G31 with the libmali fbdev driver, 1 GB) with Knulli. It runs at about 37 fps in levels and 60 in menus (presented frames, counted from framebuffer page flips), with sound, and uses about 595 MB RSS, steady over several minutes with about 180 MB still available. On Mali the GPU uses system RAM, so this includes textures, which the PC figure (190 MB) does not.

The controller reaches the game by printed label: the device's key codes are non standard, but through the kernel joystick driver they arrive in Xbox order (A, B, Y, X, L1, R1, Select, Start as buttons 0 to 7), which is what the game expects.

What failed on the device and why:

1. **Missing x86_64 C++ runtime.** box64 stopped with "Error loading needed lib libstdc++.so.6" (and libgcc_s.so.1). The launcher sets the game's own old copies aside; on the PC the system's newer ones filled in. box64 ships x86_64 builds of both in its `x64lib` folder, which the port now bundles.
2. **BadMatch on X_CreateColormap.** Crusty, Westonpack's GLX layer, returns its `glXGetConfig` answer as the function result instead of writing it to the output parameter (seen in its disassembly; its source is not public). SFML 2.5 checks `GLX_DOUBLEBUFFER` through that parameter, which it never initializes, so it rejected every visual and called `XCreateColormap` with no visual, which the X server refuses. A preload replacing `glXGetConfig` does nothing, because SFML looks up glX functions with `dlsym`. `glxfix` instead replaces `XCreateColormap` and substitutes the default visual. The window is then created with the parent's visual, which is valid, and crusty renders regardless.
3. **Westonpack's plain gl4es mode** (gl4es's own GLX) avoids crusty but cannot create an EGL display on X11 with the Mali fbdev driver ("Unable to initialize EGL").
4. **filesystem_error on replays/import.** The game aborts when its empty `replays/import` or `screenshots` folders are missing. The launcher now creates them.
5. **No sound** is the known effect of westonwrap replacing `XDG_RUNTIME_DIR`; the launcher passes the real one to the game.
6. **gptokeyb2 with a gptokeyb 1 config.** The launcher now uses gptokeyb, and gptokeyb2 only on muOS, where gptokeyb is known to be unresponsive.
7. **Test tooling on the device.** `fbgrab` shows plain white for GL output, so screenshots come from a raw `/dev/fb0` dump. gl4es's `LIBGL_FPS` and crusty's `CRUSTY_FPS` do not count these frames, but the framebuffer pan register changes once per presented frame. Injected button presses must use the device's own key codes (an injector using standard gamepad codes pressed the wrong buttons, which made the exit hotkey look broken).

### View height marker

The launcher sets View Height 720 once on 480 line screens and leaves the player's later choice alone. Its marker (`.view_height_set`) used to sit in the port folder while the setting lives in `gamedata/data/user/settings.cfg`, so a fresh port folder with the player's copied game data reset their choice to 720. The marker now sits next to the settings; a marker from an older release still counts.

## 7. Still to do

* Test on other devices: ROCKNIX with Panfrost, muOS, ArkOS, and screens other than 640x480.
* If it runs slowly, the game's own settings (`fps_cap`, `render_parallax_layers`, `render_rgb_split`, `vsync` in `data/user/settings.cfg`) are the first things to try.
* Confirm on ROCKNIX with Panfrost.
