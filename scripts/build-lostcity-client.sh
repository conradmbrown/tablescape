#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT/vendor/lostcity-os1"
mkdir -p build/classes
find src/main/java -name '*.java' > build/sources.txt
"$ROOT/runtime/jdk8u504-b01/bin/javac" -encoding UTF-8 -d build/classes @build/sources.txt
