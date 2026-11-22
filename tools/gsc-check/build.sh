#!/bin/sh
# Linux syntax/link check for H1 GSC with the repo's gsc-tool (no game needed).
# Build:  tools/gsc-check/build.sh            -> tools/gsc-check/gsct
# Check:  tools/gsc-check/gsct <file.gsc> <include root, e.g. COD-GSC-Source/H1-GSC>
set -e
G="$(cd "$(dirname "$0")/../../deps/gsc-tool" && pwd)"
OUT="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
ls "$G"/src/gsc/*.cpp "$G"/src/gsc/common/*.cpp "$G"/src/gsc/engine/h1*.cpp "$G"/src/utils/*.cpp "$G"/deps/fmt/src/format.cc "$OUT/main.cpp" |
  xargs -P "$(nproc)" -I{} sh -c 'g++ -std=c++20 -O1 -w -fpermissive -I"'"$G"'/include" -I"'"$G"'/deps/fmt/include" -include "'"$G"'/include/xsk/stdinc.hpp" -c "{}" -o "'"$TMP"'/$(echo "{}" | md5sum | cut -c1-12).o"'
g++ "$TMP"/*.o -lz -o "$OUT/gsct"
rm -rf "$TMP"
echo "built $OUT/gsct"
