# openwrt-aria2-next Agent Notes

This file is a compact handoff for future agents working on `openwrt-aria2-next`.

## Current Goal

Build and publish static `aria2-next` packages for OpenWrt using official OpenWrt SDK Docker images.

Keep downloader implementation in the pinned upstream submodule. This repository owns OpenWrt integration, verified static dependency builds, package/service behavior, releases, and the feed; do not fork the engine to reproduce removed upstream features.

## Upstream Facts

- Upstream repository: `https://github.com/AnInsomniacy/aria2-next.git`
- Local submodule path: `aria2-next/`
- Current version extracted from `aria2-next/CMakeLists.txt`
- Build system: CMake 3.25+ with Ninja
- Language baseline: C11/C++20, including libtorrent
- Produced executable: `aria2-next`
- Test executable and CTest name: `aria2_tests`
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
| libtorrent-rasterbar | Vendored by the submodule |
| GPAC | Vendored by the submodule |
| FFmpeg | Vendored by the submodule |

## OpenWrt Packaging Surface

- Package name: `aria2-next-static`
- Binary: `/usr/bin/aria2-next`
- Service: `/etc/init.d/aria2-next`
- Config: `/etc/config/aria2-next`
- Package source: `package/aria2-next-static/`
- UCI section type: keep `config aria2` for compatibility with OpenWrt's official aria2 config schema
- Default runtime config directory: `/var/etc/aria2-next`
- Default sample download directory: `/mnt/sda1/aria2-next`
- Target matrix: 31 architectures, validated by `build_scripts/ci_matrix.sh`

The service is adapted from official OpenWrt `net/aria2`. OpenWrt 24.10 and 25.12 had byte-identical aria2 init/config sources when this migration was done.

## Build Model

Use host Docker to run official SDK containers. Do not use GitHub Actions `container:` for the build job.

Default SDK:

- IPK + APK: `ghcr.io/openwrt/sdk:<platform>-V25.12.5`

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
  `ARIA2_BUILD_TESTS=yes` to run the compiler compatibility regressions and
  compile the cross-built test executable.
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
- Keep OpenSSL's runtime trust directory at `/etc/ssl`; curl uses its default
  trust fallback rather than build-host paths. The target still needs CA data.
- Compile the engine and libtorrent with C++20 so their Boost.Asio feature
  definitions and layouts agree. Validate BitTorrent startup through RPC on
  runnable native builds; successful linking and unit tests alone can miss
  this ABI problem. `verify_binary.sh` runs `test_binary_runtime.py` for
  HTTP/gzip, HTTPS trust, DoH, authenticated JSON/XML-RPC, WebSocket, and BitTorrent,
  then validates the generated service configurations with that binary.
- Keep FFmpeg itself out of LTO. Its runtime-dispatch objects carry different
  ISA flags, and cross-GCC can otherwise reject optional instructions such as
  NEON during the final generic-target link. Generic MIPS builds separately
  disable incorrect Loongson CPU-extension and MMI autodetection.
- Derive GPAC's 32/64-bit ABI from the target compiler rather than target-name
  guesses. On RISC-V, keep the forced `asm/unistd.h` include that backports
  FFmpeg's musl fix and exposes the `riscv_hwprobe` syscall number.
- Version 3 requires the OpenSSL, zlib, expat, SQLite3, curl/libssh2/nghttp2,
  libtorrent, GPAC, and FFmpeg stack. Disable `ARIA2_SUPERBUILD` and supply
  `ARIA2_DEPENDENCY_ROOT` and `ARIA2_BOOST_ROOT` for our prebuilt libraries;
  do not pass removed legacy feature switches that CMake merely ignores.
- `cxx_compat.sh` preflights the actual upstream `src/disk/File.cc` with the
  target C++ compiler. Use the C++-only `-include utility` workaround only when
  plain compilation fails and that include makes it succeed; unrelated errors
  must fail the build. Keep `test_cxx_compat.sh` passing. Do not gate the fix by
  a version string, dirty the upstream gitlink, or add the header to C flags.
  Upstream 3.0.4 includes `<utility>`, so its plain compile should pass and
  the compatibility flag should be absent.
- Vendored Boost supplies Asio networking, Beast HTTP/WebSocket RPC, JSON,
  and libtorrent headers; spdlog supplies logging. wslay was removed upstream.
  curl uses its threaded resolver, and its DNS-over-HTTPS support is enabled
  for the optional upstream `dns-over-https` setting. Other lookups use the
  system resolver.
- The local dependency profile keeps OpenSSL as its TLS backend and does not
  add alternative TLS, allocator, or event-loop libraries.

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
bash build_scripts/test_cxx_compat.sh
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

Revalidate with the current SDK defaults after changing toolchain-sensitive
logic. For a major upstream change, run the native x86_64 unit suite and
BitTorrent RPC startup/shutdown check, then representative cross-target builds.

## Known Migration Rules

- Replace old `aria2-builder` references with `aria2-next`.
- Replace old `aria2-static` package references with `aria2-next-static`.
- Replace old raw binary asset `aria2c` with `aria2-next`.
- Keep service config compatibility with official OpenWrt aria2 where practical.
- Do not introduce a conflict with the official `aria2` package unless a future task explicitly requests it.
- Version 3 supports JSON-RPC over HTTP/WebSocket and, since 3.0.2, XML-RPC at
  `/rpc` with the same token authentication. JSONP, Metalink 3, and libaria2
  remain unavailable. Built-in RPC TLS was removed. Reject RPC TLS options in
  UCI and `extra_settings`, including bare `rpc-secure` flags accepted by the
  newer parser, so an old secure configuration cannot start plaintext;
  recommend a TLS reverse proxy with the existing token secret.
- Version 3.0.4 restores `thunder://` URI handling and adds `aria2.moveDownload`
  for moving unfinished downloads. Destinations must remain accessible in the
  procd jail and writable by the service user; do not broaden mounts implicitly.
  Keep `incomplete-suffix` optional and empty
  by default. `auto-file-renaming-style` and `download-result` can be supplied
  through existing `extra_settings`; do not impose new package defaults.
- Since 3.0.3, `file-allocation=none` and `trunc` are sparse, while `prealloc`
  and `falloc` reserve space before downloading. Retain the sample's `none`
  profile and account for preallocation work and storage use on small routers.
- Use UCI `state_save_interval` (minimum 1 second); `auto_save_interval` remains
  an alias, but 0 is invalid. Map `bt_detach_seed_only` to `detach_share_only`
  and `peer_id_prefix` to `bt_peer_id_prefix`. `disk_cache` is retired upstream
  and must not be described as a version 3 memory limit.
- Keep the version 2.8 session and `state.<instance>` directories during an
  upgrade: stream, ED2K, media, and BitTorrent state layouts are retained.
  Original aria2 `.aria2` control files are not imported. Back up UCI and the
  complete `config_dir` while the service is stopped.
- `/var/etc/aria2-next` is normally volatile. Document a writable persistent
  `config_dir` for reboot recovery and copy existing state before relocating
  it. For smaller routers, tune concurrent downloads and per-download
  connections; static linking and UPX do not impose a runtime memory limit.
