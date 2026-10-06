#!/usr/bin/env bash
# Builds a minimal Node.js for linux (x64 or arm64, from uname -m) that runs on glibc >= 2.17
# (CentOS/RHEL 7, Amazon Linux 2 and newer). Runs inside the toolchain image.
# Mounts: /in/node-v$NODE_VERSION.tar.xz (source, read-only), /out (result).
# The glibc-2.17 patches and checks come from nodejs/unofficial-builds
# recipes/centos7-toolchain/run.sh (MIT, commit c41adbe).
set -euo pipefail
V=${NODE_VERSION:?set NODE_VERSION}
JOBS=${JOBS:-$(nproc)}
OPT=${OPT:-Os}   # compiler optimisation level: Os (size) or O2 (speed)
[[ "$OPT" =~ ^(Os|O2)$ ]] || { echo "OPT must be Os or O2" >&2; exit 1; }

case "$(uname -m)" in x86_64) ARCH=x64 ;; aarch64) ARCH=arm64 ;; *) echo "unsupported arch $(uname -m)" >&2; exit 1 ;; esac

mkdir -p /work && cd /work
tar -xf /in/node-v$V.tar.xz
cd node-v$V

# --- glibc 2.17 patches (unofficial-builds) ---------------------------------
# c-ares must not use sys/random.h / getrandom (glibc 2.25+)
sed -i 's/define HAVE_SYS_RANDOM_H 1/undef HAVE_SYS_RANDOM_H/g' deps/cares/config/linux/ares_config.h
sed -i 's/define HAVE_GETRANDOM 1/undef HAVE_GETRANDOM/g' deps/cares/config/linux/ares_config.h
# experimental WASM memory control needs Linux 3.17 + glibc 2.27
if [ -f deps/v8/src/d8/d8.cc ]; then
  sed -i -e 's/#if V8_TARGET_OS_LINUX/#if false/g' deps/v8/src/wasm/wasm-objects.cc deps/v8/src/d8/d8.cc
fi

# --- toolchain: GCC 15 + Python 3.13 (what unofficial-builds uses for >= v22.3)
set +u; source /opt/gcc15/enable; set -u   # also sets LDFLAGS=-static-libstdc++ -static-libgcc
export PYTHON=python3.13 CC=gcc CXX=g++
export CFLAGS="-g0 -$OPT" CXXFLAGS="-g0 -$OPT"

# Minimal runtime: no ICU, no inspector, NODE_OPTIONS ignored, no bundled TS
# tooling / SQLite / built-in code cache; link-time optimisation.
$PYTHON configure.py --without-node-options --without-intl --without-inspector \
  --without-amaro --without-sqlite --without-node-code-cache --enable-lto
echo "make start $(date -u)"
make -j"$JOBS"
echo "make done $(date -u)"

BIN=node-v$V-minimal-linux-$ARCH-glibc217
cp out/Release/node /out/$BIN
strip /out/$BIN

# --- glibc 2.17 is the product: verify (unofficial-builds checks) -------------
env -u LD_LIBRARY_PATH /out/$BIN -p "process.version + ' ' + process.arch + ' intl=' + typeof Intl"
if env -u LD_LIBRARY_PATH ldd /out/$BIN | grep /opt/gcc15; then
  echo "binary is dynamically linked against the GCC 15 runtime" >&2; exit 1
fi
maxGlibc=$(objdump -T /out/$BIN | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -uV | tail -1)
if [ "$(printf 'GLIBC_2.17\n%s\n' "$maxGlibc" | sort -V | tail -1)" != "GLIBC_2.17" ]; then
  echo "binary requires $maxGlibc, newer than the glibc 2.17 target" >&2; exit 1
fi
echo "BUILD OK $BIN opt=-$OPT size=$(stat -c %s /out/$BIN) max-glibc=$maxGlibc"
