#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
mkdir -p "$ROOT/runtime"
cd "$ROOT/runtime"
nodefile=node-v24.21.0-linux-x64.tar.xz
javafile=OpenJDK8U-jdk_x64_linux_hotspot_8u504b01.tar.gz
if [ ! -f "$nodefile" ]; then curl -fL "https://nodejs.org/dist/v24.21.0/$nodefile" -o "$nodefile"; fi
if [ ! -f "$javafile" ]; then curl -fL "https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u504-b01/$javafile" -o "$javafile"; fi
printf '%s  %s\n' fd8e59d5a511510f6a298afb548f18c7d2b1be404d8b4a27d94fbe49f56cb2d6 "$nodefile" 9c70e102f527ac674ac2fe9c7d47b9a04e2d19842ba5ab8e9b33f368bbadfaea "$javafile" | sha256sum -c -
[ -d node-v24.21.0-linux-x64 ] || tar -xf "$nodefile"
[ -d jdk8u504-b01 ] || tar -xf "$javafile"
