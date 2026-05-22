# openwrt-aria2-next Agent Notes

This file is a compact handoff for future agents working on `openwrt-aria2-next`.

## Current Goal

Build and publish static `aria2-next` packages for OpenWrt using official OpenWrt SDK Docker images.

## Upstream Facts

- Upstream repository: `https://github.com/AnInsomniacy/aria2-next.git`
- Local submodule path: `aria2-next/`
- Current version extracted from `aria2-next/CMakeLists.txt`
- Build system: CMake 3.25+ with Ninja
- Produced executable: `aria2-next`
- Dependency baseline: `aria2-next/packaging/dependencies.env`

Important dependency pins at migration time:

| Dependency | Version |
| --- | --- |
| zlib | 1.3.2 |
| expat | 2.8.1 |
| SQLite | 3.53.1 / autoconf 3530100 |
| c-ares | 1.34.6 |
| libssh2 | 1.11.1 |
| OpenSSL | 3.5.6 |

## OpenWrt Packaging Surface

- Package name: `aria2-next-static`
- Binary: `/usr/bin/aria2-next`
- Service: `/etc/init.d/aria2-next`
- Config: `/etc/config/aria2-next`
- Package source: `package/aria2-next-static/`
- UCI section type: keep `config aria2` for compatibility with OpenWrt's official aria2 config schema
- Default runtime config directory: `/var/etc/aria2-next`
- Default sample download directory: `/mnt/sda1/aria2-next`

The service is adapted from official OpenWrt `net/aria2`. OpenWrt 24.10 and 25.12 had byte-identical aria2 init/config sources when this migration was done.

## Build Model

Use host Docker to run official SDK containers. Do not use GitHub Actions `container:` for the build job.

Default SDKs:

- IPK: `ghcr.io/openwrt/sdk:<platform>-V24.10.4`
- APK: `ghcr.io/openwrt/sdk:<platform>-V25.12.0`

Local one-target build pattern:

```sh
PLATFORM=x86_64
SDK_VERSION=24.10.4
docker run --rm --user root \
  -v "$PWD:/work/repo:z" \
  -v "$PWD/output:/work/output:z" \
  -e PLATFORM="$PLATFORM" \
  -e OPENWRT_SDK_VERSION="$SDK_VERSION" \
  -e BUILD_VERSION="local" \
  "ghcr.io/openwrt/sdk:${PLATFORM}-V${SDK_VERSION}" \
  bash /work/repo/build_scripts/build_in_sdk.sh "$PLATFORM"
```

## Static Build Notes

- Dependencies are built in `build_scripts/build_deps_static.sh`.
- `build_scripts/build_static_aria2.sh` configures aria2-next with CMake/Ninja.
- Preserve OpenSSL `gcc-ar`, `gcc-ranlib`, and `gcc-nm` wrappers for LTO.
- Preserve OpenSSL RC4 support because aria2 uses ARC4 for BitTorrent MSE.
- The CMake build enables OpenSSL, zlib, expat, c-ares, SQLite, and libssh2, and disables GnuTLS, libxml2, libuv, jemalloc, and tcmalloc.

## Package Format Lessons

Correct OpenWrt IPK format is a gzip-compressed tar archive containing:

```text
./debian-binary
./data.tar.gz
./control.tar.gz
```

Do not use Debian `ar` format for these custom OpenWrt IPKs; it previously caused `Malformed package file` and opkg crashes on target devices.

## Validation Commands

Run these before handing work back:

```sh
bash -n build_scripts/*.sh
sh -n package/aria2-next-static/files/aria2-next.init \
  package/aria2-next-static/files/postinst \
  package/aria2-next-static/files/prerm
sh build_scripts/test_aria2_init.sh
```

Also inspect generated packages when packaging logic changes:

```sh
tmpdir=$(mktemp -d)
printf '#!/bin/sh\necho aria2-next dummy\n' > "$tmpdir/aria2-next"
chmod +x "$tmpdir/aria2-next"
bash build_scripts/build_ipk.sh x86_64 "$tmpdir/aria2-next" "$tmpdir/out"
bash build_scripts/build_apk.sh x86_64 "$tmpdir/aria2-next" "$tmpdir/out"
```

For end-to-end confidence, run one Docker SDK build, preferably `x86_64` first.

## Known Migration Rules

- Replace old `aria2-builder` references with `aria2-next`.
- Replace old `aria2-static` package references with `aria2-next-static`.
- Replace old raw binary asset `aria2c` with `aria2-next`.
- Keep service config compatibility with official OpenWrt aria2 where practical.
- Do not introduce a conflict with the official `aria2` package unless a future task explicitly requests it.
