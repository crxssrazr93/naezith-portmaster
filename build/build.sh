#!/bin/bash
# Builds everything the port ships that is not game data, inside build/Dockerfile:
#   box64 (aarch64, dynarec on)          -> port/naezith/box64/box64
#   libsteam_api.so stub (x86_64)        -> port/naezith/steamstub/libsteam_api.so
#   glxfix preload (x86_64)              -> port/naezith/glxfix/libglxfix.so
#   x86_64 audio libraries (Ubuntu 20.04) -> port/naezith/box64/box64-x86_64-linux-gnu/ (from build/debs)
#   box64's x86_64 libstdc++ and libgcc_s -> port/naezith/box64/box64-x86_64-linux-gnu/ (from box64's x64lib)
# Usage: build/build.sh [box64 git tag]
set -e
TAG="${1:-v0.4.4}"
R="$(cd "$(dirname "$0")/.." && pwd)"
docker build -q -t naezith-portmaster-build "$R/build" >/dev/null
mkdir -p "$R/build/src"
[ -d "$R/build/src/box64" ] || git clone -q --depth 1 --branch "$TAG" https://github.com/ptitSeb/box64.git "$R/build/src/box64"
docker run --rm -v "$R:/repo" naezith-portmaster-build bash -c '
  set -e
  cd /repo/build/src/box64 && mkdir -p build-aarch64 && cd build-aarch64
  cmake .. -DARM_DYNAREC=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc -DCMAKE_ASM_COMPILER=aarch64-linux-gnu-gcc \
    -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64 >/dev/null
  make -j"$(nproc)" >/dev/null
  aarch64-linux-gnu-strip -o /repo/port/naezith/box64/box64 box64
  gcc -shared -fPIC -O2 -o /repo/port/naezith/steamstub/libsteam_api.so /repo/port/naezith/steamstub/steamstub.c
  gcc -shared -fPIC -O2 -o /repo/port/naezith/glxfix/libglxfix.so /repo/port/naezith/glxfix/glxfix.c -ldl
  cp /repo/build/src/box64/x64lib/libstdc++.so.6 /repo/build/src/box64/x64lib/libgcc_s.so.1 /repo/port/naezith/box64/box64-x86_64-linux-gnu/
  cd /tmp && for d in /repo/build/debs/*.deb; do dpkg-deb -x "$d" x; done
  cp -L x/usr/lib/x86_64-linux-gnu/*.so.* /repo/port/naezith/box64/box64-x86_64-linux-gnu/ 2>/dev/null || true
'
ls -la "$R/port/naezith/box64/box64" "$R/port/naezith/steamstub/libsteam_api.so" "$R/port/naezith/glxfix/libglxfix.so"
