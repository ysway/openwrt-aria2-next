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
- Dependency policy and trusted download metadata: `build_scripts/versions.sh`

Dependency inventory (read exact pins from `build_scripts/versions.sh` and
artifact `BUILDINFO` files):

| Dependency | Source policy |
| --- | --- |
| zlib | Downloaded, SHA-256 pinned |
| expat | Downloaded, SHA-256 pinned |
| SQLite | Downloaded, SHA-256 pinned |
| libssh2 | Downloaded, SHA-256 pinned |
| OpenSSL | Downloaded, SHA-256 pinned |
| curl | Vendored by the submodule |
| nghttp2 | Vendored by the submodule |
| Boost | Vendored by the submodule |
| spdlog | Vendored by the submodule |
| wslay | Vendored by the submodule |
| libtorrent-rasterbar | Vendored by the submodule |

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

Default SDK:

- IPK + APK: `ghcr.io/openwrt/sdk:<platform>-V25.12.5`
- Legacy `riscv64_riscv64` IPK: `ghcr.io/openwrt/sdk:riscv64_riscv64-V24.10.7`
- Legacy `mips_4kec` IPK: `ghcr.io/openwrt/sdk:mips_4kec-V24.10.7`

Local one-target build pattern:

```sh
PLATFORM=x86_64
SDK_VERSION=25.12.5
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
- Release builds request the `aria2-next` target explicitly. Set
  `ARIA2_BUILD_TESTS=yes` only when the cross-built test executable is needed.
- Downloaded dependency archives are accepted only after matching the SHA-256
  values in `build_scripts/versions.sh`; the remaining dependencies use sources
  vendored by the pinned aria2-next submodule.
- `sync_dependency_manifest.sh` parses the external upstream manifest as data,
  updates vendored version labels, and fails closed for downloaded-version or
  structural dependency changes. Keep its policy regression test passing.
- `sync-upstream.yml` verifies the candidate in a read-only x86_64 build job,
  then recreates only the gitlink/manifest diff in a fresh write job. Keep tag
  and commit outputs in environment variables rather than interpolating them
  into shell or JavaScript source. Its build-status reconciliation retries a
  missing or failed full-matrix dispatch for the exact default-branch SHA.
- Preserve OpenSSL `gcc-ar`, `gcc-ranlib`, and `gcc-nm` wrappers for LTO.
- The CMake build enables OpenSSL, zlib, expat, SQLite3, libssh2, curl,
  nghttp2, libtorrent, BitTorrent, Metalink, XML-RPC, and WebSocket support.
  Vendored Boost provides the core Boost.Asio system resolver and libtorrent
  headers; vendored spdlog and wslay provide logging and WebSocket framing.
  curl uses its threaded resolver, so DNS remains asynchronous throughout.
- The local OpenWrt profile explicitly disables GnuTLS, nettle, GMP, libgcrypt, libuv, libxml2, jemalloc, and tcmalloc.

## Package Format Lessons

Correct OpenWrt IPK format is a gzip-compressed tar archive containing:

```text
./debian-binary
./data.tar.gz
./control.tar.gz
```

Do not use Debian `ar` format for these custom OpenWrt IPKs; it previously caused `Malformed package file` and opkg crashes on target devices.

OpenWrt 25.12 uses APK v3. Build it with the SDK's apk-tools 3 `mkpkg`
command through `build_scripts/build_apk.sh`; do not restore the older
concatenated-gzip APK v2 implementation. Verify output with `apk verify
--allow-untrusted`.

## Validation Commands

Run these before handing work back:

```sh
bash -n build_scripts/*.sh
sh -n package/aria2-next-static/files/aria2-next.init \
  package/aria2-next-static/files/postinst \
  package/aria2-next-static/files/prerm
sh build_scripts/test_aria2_init.sh
bash build_scripts/test_dependency_manifest.sh
bash build_scripts/ci_matrix.sh x86_64,aarch64_cortex-a53
```

Also inspect generated packages when packaging logic changes:

```sh
tmpdir=$(mktemp -d)
printf '#!/bin/sh\necho aria2-next dummy\n' > "$tmpdir/aria2-next"
chmod +x "$tmpdir/aria2-next"
bash build_scripts/build_ipk.sh x86_64 "$tmpdir/aria2-next" "$tmpdir/out"
```

Run APK checks inside an OpenWrt 25.12 SDK so apk-tools 3 is available. For
end-to-end confidence, run one Docker SDK build, preferably `x86_64` first.

Previously validated `v2.4.1` SDK builds: `x86_64`, `arm_cortex-a9`, and
`i386_pentium-mmx` on `24.10.4`. Revalidate with the current SDK defaults after
changing toolchain-sensitive logic.

## Known Migration Rules

- Replace old `aria2-builder` references with `aria2-next`.
- Replace old `aria2-static` package references with `aria2-next-static`.
- Replace old raw binary asset `aria2c` with `aria2-next`.
- Keep service config compatibility with official OpenWrt aria2 where practical.
- Do not introduce a conflict with the official `aria2` package unless a future task explicitly requests it.
