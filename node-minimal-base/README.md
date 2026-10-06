# Minimal Node.js base — linux-x64, glibc ≥ 2.17

Builds a small Node.js binary for embedding an app as a Node single executable (SEA).
Workflow: `.github/workflows/node-minimal-base.yml` (push to this branch, or run it manually
with a `node_version`). Output: a run artifact with the stripped binary, a `.gz`, and `SHA256SUMS`.

## What it builds
- Official Node.js source from nodejs.org, SHA-256 checked against `SHASUMS256.txt`.
- Configure: `--without-node-options --without-intl --without-inspector --without-amaro
  --without-sqlite --without-node-code-cache --enable-lto`, `CFLAGS=CXXFLAGS="-g0 -Os"`, then `strip`.
- Toolchain: CentOS 7 (glibc 2.17) + GCC 15, from
  [nodejs/unofficial-builds](https://github.com/nodejs/unofficial-builds) `recipes/centos7-toolchain`
  (MIT), with the same glibc-2.17 source patches. libstdc++/libgcc are linked statically.

## Checks in the workflow
- Fails if the binary needs any glibc symbol newer than `GLIBC_2.17`, or links the GCC 15 runtime.
- Runs the binary in a stock `centos:7` container (glibc 2.17).

## Notes
- The toolchain image (GCC 15 from source, ~1 h) is cached between runs with the GitHub Actions cache.
- For release use, build from an organisation-controlled repository and compare checksums;
  this branch is for producing and measuring the base.
