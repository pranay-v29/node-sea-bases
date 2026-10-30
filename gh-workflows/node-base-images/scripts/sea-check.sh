#!/usr/bin/env bash
# Checks a minimal Node base before it is used for BrowserStackLocal:
#   - it is the expected Node version and ignores NODE_OPTIONS
#   - it works as a single executable (SEA): inject a test app with postject the
#     same way build_scripts/ does, then run it
#   - Linux: after injection the program headers sit where kernels < 5.18 (and
#     qemu/Rosetta) look for them: the address computed from the first PT_LOAD
#     must be where they are really mapped, else ld.so aborts at startup
#   - macOS: the base has room for postject's extra Mach-O load command
# Usage: sea-check.sh <base> [copy-of-test-sea]   (needs npx; Git Bash on Windows)
set -euo pipefail
BASE=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
SAVE=${2:-}
case "$SAVE" in ""|/*) ;; *) SAVE=$PWD/$SAVE ;; esac
FUSE=NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2
fail() { echo "sea-check: $*" >&2; exit 1; }

OS=$(uname -s)
EXT=""
case "$OS" in MINGW*|MSYS*|CYGWIN*) EXT=.exe ;; esac

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cd "$W"

v=$("$BASE" -p process.version)
echo "base: $v $("$BASE" -p process.arch)"
if [ -n "${NODE_VERSION:-}" ] && [ "$v" != "v$NODE_VERSION" ]; then
  fail "base is $v, expected v$NODE_VERSION"
fi

echo 'require("fs").writeFileSync("honoured", "x")' > inject.js
NODE_OPTIONS="--require ./inject.js" "$BASE" -e 0
[ ! -e honoured ] || fail "NODE_OPTIONS was honoured"

echo 'console.log("sea ok " + process.version + " " + process.arch)' > app.js
echo '{ "main": "app.js", "output": "sea-prep.blob", "disableExperimentalSEAWarning": true, "useCodeCache": false, "useSnapshot": false, "execArgv": [], "execArgvExtension": "none" }' > sea-config.json
"$BASE" --experimental-sea-config sea-config.json

SEA=sea$EXT
cp "$BASE" "$SEA"
chmod u+w "$SEA"
extra=()
if [ "$OS" = Darwin ]; then
  sizeofcmds=$(otool -h "$SEA" | awk 'NR==4{print $7}')
  text_off=$(otool -l "$SEA" | awk '/sectname __text/{f=1} f&&/offset/{print $2; exit}')
  free=$((text_off - 32 - sizeofcmds))
  echo "Mach-O header space: $free B free"
  [ "$free" -ge 152 ] || fail "only $free B of Mach-O header space (need 152): link with -Wl,-headerpad,0x4000"
  codesign --remove-signature "$SEA"
  extra=(--macho-segment-name NODE_SEA)
fi
npx -y postject@1.0.0-alpha.6 "$SEA" NODE_SEA_BLOB sea-prep.blob --sentinel-fuse "$FUSE" ${extra[@]+"${extra[@]}"}
grep -q -a "$FUSE:1" "$SEA" || fail "postject did not inject the blob"

if [ "$OS" = Linux ]; then
  phoff=$(readelf -hW "$SEA" | awk '/Start of program headers/{print $5}')
  loads=$(readelf -lW "$SEA" | awk '$1 == "LOAD" {print $2, $3, $5}')
  read -r off0 va0 _ <<< "$(echo "$loads" | head -1)"
  expect=$(( va0 - off0 + phoff ))
  mapped=""
  while read -r off va fsz; do
    if [ $(( phoff >= off && phoff < off + fsz )) = 1 ]; then mapped=$(( va + phoff - off )); break; fi
  done <<< "$loads"
  [ -n "$mapped" ] || fail "program headers are not inside any PT_LOAD"
  printf 'program headers mapped at 0x%x, kernels < 5.18 look at 0x%x\n' "$mapped" "$expect"
  if [ "$mapped" -ne "$expect" ]; then
    readelf -lW "$SEA" >&2
    fail "program headers misplaced: the SEA would crash in ld.so on kernels < 5.18"
  fi
fi
if [ "$OS" = Darwin ]; then
  codesign --sign - "$SEA"
fi

out=$("./$SEA")
echo "$out"
[ "${out#sea ok}" != "$out" ] || fail "SEA did not run the injected app"
if [ -n "$SAVE" ]; then
  cp "$SEA" "$SAVE"
fi
echo "sea-check passed"
