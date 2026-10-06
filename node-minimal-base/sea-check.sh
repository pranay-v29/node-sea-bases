#!/usr/bin/env bash
# SEA check for a minimal linux base: inject a tiny app with postject (as the
# BrowserStackLocal build does), check the program headers, run it.
# Usage: sea-check.sh <base> <out-sea-binary>
#
# postject moves the program-header table. Kernels < 5.18 (and qemu/Rosetta)
# compute its address as first PT_LOAD (p_vaddr - p_offset) + e_phoff; if
# PT_PHDR is elsewhere, the SEA aborts in ld.so on those systems
# (rtld.c: _dl_rtld_map.l_libname), even though it runs on the CI kernel.
set -euo pipefail
BASE=$(realpath "$1")
OUT=$(realpath -m "$2")
FUSE=NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2

W=$(mktemp -d)
cd "$W"
echo 'console.log("sea ok " + process.version + " " + process.arch)' > app.js
echo '{ "main": "app.js", "output": "sea-prep.blob", "disableExperimentalSEAWarning": true, "useCodeCache": false, "useSnapshot": false }' > sea-config.json
"$BASE" --experimental-sea-config sea-config.json
cp "$BASE" sea
chmod u+w sea
npx -y postject@1.0.0-alpha.6 sea NODE_SEA_BLOB sea-prep.blob --sentinel-fuse "$FUSE"
grep -q -a "$FUSE:1" sea || { echo "postject did not inject the blob" >&2; exit 1; }

phoff=$(readelf -hW sea | awk '/Start of program headers/{print $5}')
read -r off va < <(readelf -lW sea | awk '$1 == "LOAD" {print $2, $3; exit}')
phdr=$(readelf -lW sea | awk '$1 == "PHDR" {print $3}')
expect=$(( va - off + phoff ))
printf 'PT_PHDR %s, address computed by kernels < 5.18: 0x%x\n' "$phdr" "$expect"
if [ $(( phdr )) -ne "$expect" ]; then
  readelf -lW sea >&2
  echo "PT_PHDR misplaced: the SEA would crash in ld.so on kernels < 5.18" >&2
  exit 1
fi

./sea
cp sea "$OUT"
