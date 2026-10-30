#!/bin/sh
# Builds a minimal, size-optimised, FULLY STATIC Node.js for linux-x64 musl (Alpine).
# Fully static = no runtime dependency on the host's musl/libstdc++, so one binary
# runs on any Alpine version. Runs inside an alpine container as root.
# Mounts: /in/node-v$NODE_VERSION.tar.xz (source, read-only), /out (result).
# Based on nodejs/unofficial-builds recipes/musl (MIT), plus --fully-static and the
# same minimal feature flags as the glibc bases.
set -eu
V=${NODE_VERSION:?set NODE_VERSION}
OPT=${OPT:-Os}
JOBS=${JOBS:-$(nproc)}
case "$OPT" in Os|O2) ;; *) echo "OPT must be Os or O2" >&2; exit 1 ;; esac

apk add --no-cache bash binutils-gold g++ gcc libgcc linux-headers make python3 xz file

# Node 22 needs GCC >= 12.2
gv=$(gcc -dumpfullversion)
echo "Alpine $(cat /etc/alpine-release), gcc $gv, $(ld --version | head -1)"
if [ "$(printf '12.2.0\n%s\n' "$gv" | sort -V | head -1)" != "12.2.0" ]; then
  echo "gcc $gv is older than 12.2" >&2; exit 1
fi

mkdir -p /work && cd /work
tar -xf /in/node-v$V.tar.xz
cd node-v$V

export CFLAGS="-g0 -$OPT" CXXFLAGS="-g0 -$OPT"
python3 configure.py --fully-static \
  --without-node-options --without-intl --without-inspector \
  --without-amaro --without-sqlite --without-node-code-cache --enable-lto
echo "make start $(date -u)"
make -j"$JOBS"
echo "make done $(date -u)"

BIN=node-v$V-minimal-linux-x64-musl
cp out/Release/node /out/$BIN
strip /out/$BIN
file /out/$BIN
file /out/$BIN | grep -q 'statically linked' || { echo "binary is not statically linked" >&2; exit 1; }
/out/$BIN -p "process.version + ' ' + process.arch + ' intl=' + typeof Intl"
echo "BUILD OK $BIN opt=-$OPT size=$(stat -c %s /out/$BIN)"
