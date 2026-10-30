#!/usr/bin/env bash
# Builds a minimal Node.js for macOS on the runner's own architecture (arm64 on
# macos-15, x64 on macos-15-intel). Run from the folder holding node-v$NODE_VERSION/.
# Output: out/node-v$NODE_VERSION-minimal-darwin-<arm64|x64>
set -euo pipefail
V=${NODE_VERSION:?set NODE_VERSION}
OPT=${OPT:-Os}
[[ "$OPT" =~ ^(Os|O2)$ ]] || { echo "OPT must be Os or O2" >&2; exit 1; }
case "$(uname -m)" in arm64) ARCH=arm64 ;; x86_64) ARCH=x64 ;; *) echo "unsupported arch $(uname -m)" >&2; exit 1 ;; esac

OUT=$PWD/out
mkdir -p "$OUT"
cd "node-v$V"

export CFLAGS="-g0 -$OPT" CXXFLAGS="-g0 -$OPT"
# postject adds a Mach-O load command (152 B); without spare header space it
# shifts __DATA and the x64 SEA crashes at startup (SIGBUS).
export LDFLAGS="-Wl,-headerpad,0x4000"

# Same minimal runtime as the other bases: no ICU, no inspector, NODE_OPTIONS
# ignored, no bundled TS tooling / SQLite / built-in code cache.
./configure --without-node-options --without-intl --without-inspector \
  --without-amaro --without-sqlite --without-node-code-cache
echo "make start $(date -u)"
make -j"$(sysctl -n hw.ncpu)"
echo "make done $(date -u)"

BIN=node-v$V-minimal-darwin-$ARCH
cp out/Release/node "$OUT/$BIN"
strip -x "$OUT/$BIN"
# strip breaks the linker's ad-hoc signature, and macOS won't run unsigned arm64.
codesign --force --sign - "$OUT/$BIN"
"$OUT/$BIN" -p "process.version + ' ' + process.arch + ' intl=' + typeof Intl"
echo "BUILD OK $BIN opt=-$OPT size=$(stat -f %z "$OUT/$BIN")"
