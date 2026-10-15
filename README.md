# openwrt-aria2-next

[![Build aria2-next](https://github.com/ysway/openwrt-aria2-next/actions/workflows/build-aria2.yml/badge.svg)](https://github.com/ysway/openwrt-aria2-next/actions/workflows/build-aria2.yml)
[![Package feed](https://img.shields.io/badge/feed-GitHub%20Pages-0969da)](https://ysway.github.io/openwrt-aria2-next/)
[![License: MIT](https://img.shields.io/badge/Infrastructure-MIT-blue.svg)](LICENSE)

Statically linked [aria2-next](https://github.com/AnInsomniacy/aria2-next) builds for [OpenWrt](https://openwrt.org/), compiled inside official OpenWrt SDK containers and published as OPKG, APK, and raw binary artifacts across 31 target architectures.

This repository owns the OpenWrt build, packaging, service integration, release, and package-feed layers. The downloader source remains in the `aria2-next/` git submodule.

## Features

- **Self-contained binaries** — target libraries are linked statically to avoid firmware package dependency conflicts
- **Broad protocol support** — HTTP(S), SFTP, BitTorrent, Metalink 4, native HLS/MPEG-DASH media downloads, JSON-RPC over HTTP/WebSocket, XML-RPC over HTTP, and ED2K
- **OpenSSL backend** — HTTPS support with static OpenSSL, plus asynchronous DNS through Boost.Asio and curl, including optional DNS-over-HTTPS for curl transfers
- **31 OpenWrt target architectures** — built with official OpenWrt SDK Docker images
- **Dual package format** — `.ipk` for OPKG-based OpenWrt and standalone `.apk` for APK-based OpenWrt
- **OpenWrt service integration** — procd init script and UCI configuration based on OpenWrt's official `net/aria2` model
- **UPX compression with a safety net** — optional, verified after packing, and skipped on known-sensitive targets
- **Auditable releases** — raw binaries, `BUILDINFO`, per-file hashes on the feed, and release `SHA256SUMS`
- **Automated upstream tracking** — the sync workflow follows stable tagged `aria2-next` releases after x86_64 verification

## Supported Architectures

<details>
<summary>All 31 target platforms</summary>

| Architecture | Platforms | UPX | Default SDK |
|:---|:---|:---:|:---:|
| **AArch64** | `aarch64_cortex-a53`, `aarch64_cortex-a72`, `aarch64_cortex-a76`, `aarch64_generic` | Yes | 25.12.5 |
| **ARM** | `arm_arm1176jzf-s_vfp`, `arm_arm926ej-s`, `arm_cortex-a15_neon-vfpv4`, `arm_cortex-a5_vfpv4`, `arm_cortex-a7`, `arm_cortex-a7_neon-vfpv4`, `arm_cortex-a7_vfpv4`, `arm_cortex-a8_vfpv3`, `arm_cortex-a9`, `arm_cortex-a9_neon`, `arm_cortex-a9_vfpv3-d16`, `arm_fa526`, `arm_xscale` | Yes | 25.12.5 |
| **x86** | `i386_pentium-mmx`, `i386_pentium4` | Yes | 25.12.5 |
| **x86_64** | `x86_64` | Yes | 25.12.5 |
| **MIPS** | `mips_24kc`, `mips_mips32` | Yes | 25.12.5 |
| **MIPS-EL** | `mipsel_24kc`, `mipsel_24kc_24kf`, `mipsel_74kc`, `mipsel_mips32` | Yes | 25.12.5 |
| **MIPS64** | `mips64_mips64r2`, `mips64_octeonplus` | No | 25.12.5 |
| **MIPS64-EL** | `mips64el_mips64r2` | No | 25.12.5 |
| **RISC-V 64** | `riscv64_generic` | No | 25.12.5 |
| **LoongArch64** | `loongarch64_generic` | No | 25.12.5 |

</details>

### Check your architecture

For OPKG-based OpenWrt:

```sh
opkg print-architecture | awk 'NF==3 && $3~/^[0-9]+$/ {print $2}' | tail -1
```

For APK-based OpenWrt:

```sh
cat /etc/apk/arch
```

Use the package-manager architecture, not just `uname -m`; OpenWrt target names include CPU tuning and ABI details.

## Installation

### Option 1: Quick installer

The installer detects OPKG versus APK, resolves the latest release, selects the matching architecture, and verifies `SHA256SUMS` when the release provides it.

```sh
wget -O- https://raw.githubusercontent.com/ysway/openwrt-aria2-next/master/setup.sh | sh
```

For an auditable install, download `setup.sh`, inspect it, then run it. Optional overrides include:

```sh
ARIA2_RELEASE_TAG=v3.0.4 ARIA2_ARCH=x86_64 sh setup.sh
ARIA2_INSTALL_MODE=raw sh setup.sh
ARIA2_REPO=owner/fork sh setup.sh
```

`ARIA2_INSTALL_MODE` accepts `auto`, `opkg`, `apk`, or `raw`.

### Option 2: Download an IPK from Releases

Use this on OPKG-based OpenWrt:

```sh
VERSION=3.0.4
TAG="v${VERSION}"
ARCH=x86_64

wget "https://github.com/ysway/openwrt-aria2-next/releases/download/${TAG}/aria2-next-static_${VERSION}_${ARCH}.ipk"
opkg install "aria2-next-static_${VERSION}_${ARCH}.ipk"
```

Replace the example version and architecture with values from the [latest release](https://github.com/ysway/openwrt-aria2-next/releases/latest).

### Option 3: Download an APK from Releases

Use this on APK-based OpenWrt:

```sh
VERSION=3.0.4
TAG="v${VERSION}"
ARCH=x86_64

wget "https://github.com/ysway/openwrt-aria2-next/releases/download/${TAG}/aria2-next-static_${VERSION}_${ARCH}.apk"
apk add --allow-untrusted "aria2-next-static_${VERSION}_${ARCH}.apk"
```

The package is currently published as a standalone unsigned APK rather than through a signed APK repository, so `--allow-untrusted` is required.

### Option 4: Use the OPKG feed

The [GitHub Pages feed](https://ysway.github.io/openwrt-aria2-next/) publishes a directory and OPKG index for each architecture:

```sh
ARCH=$(opkg print-architecture | awk 'NF==3 && $3~/^[0-9]+$/ {print $2}' | tail -1)
echo "src/gz aria2-next-static https://ysway.github.io/openwrt-aria2-next/${ARCH}" >> /etc/opkg/customfeeds.conf

opkg update
opkg install aria2-next-static
```

The site root is a landing page. The architecture suffix is required in the feed URL.

### Option 5: Install the raw binary

```sh
VERSION=3.0.4
TAG="v${VERSION}"
ARCH=x86_64

wget -O /usr/bin/aria2-next \
  "https://github.com/ysway/openwrt-aria2-next/releases/download/${TAG}/aria2-next_${VERSION}_${ARCH}"
chmod 0755 /usr/bin/aria2-next
/usr/bin/aria2-next --version
```

The raw binary does not install the procd service, UCI configuration, system user, or package-manager metadata.

## Configuration

The package installs a disabled-by-default service. Create a writable download directory, configure an RPC secret, then enable it:

```sh
mkdir -p /mnt/data/downloads
chown aria2:aria2 /mnt/data/downloads

uci set aria2-next.main.enabled='1'
uci set aria2-next.main.dir='/mnt/data/downloads'
uci set aria2-next.main.rpc_auth_method='token'
uci set aria2-next.main.rpc_secret='replace-with-a-long-random-secret'
uci commit aria2-next

service aria2-next enable
service aria2-next start
```

Useful paths:

| Path | Purpose |
|:---|:---|
| `/usr/bin/aria2-next` | Static downloader binary |
| `/etc/init.d/aria2-next` | procd service |
| `/etc/config/aria2-next` | UCI configuration |
| `/var/etc/aria2-next` | Rendered runtime config, session, and per-instance engine state by default |
| `/mnt/sda1/aria2-next` | Download directory in the packaged sample config |

The UCI section type remains `config aria2` to match OpenWrt's official schema. Existing `/etc/config/aria2` files can usually be reused by copying them to `/etc/config/aria2-next`. The service also accepts the older `download_dir` and `dht_enable` keys. aria2-next 2.6 removed RPC username/password authentication; configurations using `rpc_user`, `rpc_passwd`, or `rpc_auth_method='user_pass'` must migrate to `rpc_auth_method='token'` with a non-empty `rpc_secret`. The service fails closed instead of starting those legacy configurations without authentication.

### Upgrading to aria2-next 3

Upstream 3.0 replaces the legacy engine with a Boost.Asio-based core while retaining the `aria2-next` executable, aria2-style configuration/session files, and JSON-RPC methods. This repository keeps its OpenWrt package names, installation paths, and static build model.

XML-RPC over HTTP at `/rpc` was restored in 3.0.2 and shares JSON-RPC's token authentication. JSONP, Metalink 3, and the libaria2 C++ API remain unavailable. Built-in RPC TLS was removed: the service rejects enabled `rpc_secure` and RPC certificate/key settings, including equivalent `extra_settings` and bare `rpc-secure` flags, so an old HTTPS configuration cannot silently start as plaintext HTTP. Use a TLS reverse proxy when encrypted remote RPC is needed, and retain the RPC token secret.

For a reverse proxy running on the same device, set UCI `rpc_listen_all='false'` to bind RPC to loopback. HTTPS downloads still verify certificates using the target's CA trust material under `/etc/ssl`; `ca_certificate` or `SSL_CERT_FILE` can select a CA bundle explicitly. Static linking does not bundle a CA store.

| UCI setting | Version 3 behavior |
|:---|:---|
| `state_save_interval` | Resume checkpoint interval in seconds, at least `1`; upstream default is `10` |
| `auto_save_interval` | Legacy alias for `state_save_interval`; `0` is no longer valid |
| `detach_share_only` | Lets seeding tasks stop counting toward concurrent downloads; `bt_detach_seed_only` remains a service alias |
| `bt_peer_id_prefix` | BitTorrent peer ID prefix; `peer_id_prefix` remains a service alias |
| `disk_cache` | Retired upstream and ignored; it does not limit version 3 memory use |

Before upgrading, stop the service and back up `/etc/config/aria2-next` and the configured `config_dir`, including session files and each `state.<instance>` directory. Keep the same download paths and state directories: version 3 retains the version 2.8 stream, ED2K, media, and BitTorrent state layouts. Original aria2 `.aria2` control files are not imported.

The default `/var/etc/aria2-next` directory is normally volatile on OpenWrt. For recovery across device reboots, place `config_dir` on writable persistent storage, mounted before starting the service. For a new instance, for example:

```sh
mkdir -p /mnt/data/aria2-next-state
chown aria2:aria2 /mnt/data/aria2-next-state
uci set aria2-next.main.config_dir='/mnt/data/aria2-next-state'
uci commit aria2-next
```

When moving an existing instance, stop it and copy the complete old `config_dir` to the new location before changing the setting.

### Changes in 3.0.4

Upstream restores `thunder://` links wherever a URI is accepted, including `aria2.probe`. The new `aria2.moveDownload` RPC method moves an unfinished task's files to another directory, pausing a running task for the move and resuming it afterward.

For the packaged service, move destinations must be writable by the service user and accessible inside its procd jail. The configured download directory is mounted read-write; the RPC method does not grant access to other storage paths.

Optional `incomplete-suffix` gives unfinished HTTP/SFTP files a suffix such as `.part`; its default is empty. `auto-file-renaming-style=parentheses` selects browser-style numbered filenames instead of the default `dot` style, and `download-result=default|full|hide` controls the results table printed on exit. These options can use the existing `list extra_settings` interface; the package does not override their upstream defaults. For example, add `list extra_settings 'incomplete-suffix=.part'` to a `config aria2` section if desired.

File allocation was corrected in 3.0.3: `none` and `trunc` create sparse files, while `prealloc` and `falloc` reserve disk space before downloading. The packaged `file_allocation='none'` profile is retained; allow for the disk-space and startup-work differences before selecting preallocation on a router.

### Tuning for small routers

Version 3 defaults to five concurrent downloads and up to 16 connections per HTTP download. Media and BitTorrent also use worker threads and buffers; static linking and UPX do not bound runtime memory. A conservative starting point is:

```sh
uci set aria2-next.main.max_concurrent_downloads='1'
uci set aria2-next.main.split='2'
uci set aria2-next.main.max_connection_per_server='2'
uci commit aria2-next
service aria2-next restart
```

Adjust these values for the device and workload. Additional supported version 3 options can be supplied through `list extra_settings`; consult the pinned upstream [option reference](aria2-next/docs/options.md).

## Feed Notes

- The GitHub Pages site provides OPKG `Packages` and `Packages.gz` metadata.
- APK artifacts are browsable on the site and in Releases, but the site is not a signed APK repository.
- Every architecture directory includes the package artifacts, raw binary, `BUILDINFO`, and hashes shown in the package table.
- Feed generation is implemented by `build_scripts/gen_feed.sh` and `build_scripts/render_feed_index.sh`, so it can be tested outside GitHub Actions.
- Forks must enable GitHub Pages for the `feed` branch if they want to publish the generated site.

## How It Works

### Build and release flow

```text
sync-upstream.yml (daily or manual)
  └─ Select the newest stable aria2-next SemVer tag
  └─ Parse and reconcile the dependency manifest as untrusted data
  └─ Build x86_64, run upstream tests, and exercise BitTorrent over RPC
  └─ Revalidate the exact tag/SHA in a fresh write job and update the submodule
  └─ Dispatch build-aria2.yml
       │
       ▼
prepare job
  └─ Validate the requested platform list
  └─ Read one version and timestamp for the whole run
       │
       ▼
build matrix (up to 31 targets)
  └─ Pull official OpenWrt SDK image
  └─ Restore dependency/download cache
  └─ Build verified static dependencies
  └─ Build only the aria2-next executable target by default
  └─ Verify static linkage and runnable targets' protocol/service behavior
  └─ Optional UPX → IPK + APK v3 → upload
       │
       ▼
artifact assembly job
  └─ Collect each target's already verified packages and binary
       │
       ├─► deploy job: regenerate the feed branch and website
       └─► release job: publish IPK, APK, binary, and SHA256SUMS assets
```

Scheduled upstream builds publish automatically only after the isolated x86_64 candidate build, upstream test suite, and BitTorrent RPC startup/shutdown check pass. The verification job has read-only repository permission; a separate short write job recreates the data-only manifest change, rejects unexpected staged paths or a moved tag/default branch, and then commits. When no matching full-matrix run remains active, the next scheduled run retries a missing or failed build for the exact default-branch commit, so a transient dispatch failure cannot leave the release/feed permanently stale. Manual build-workflow runs are safe previews by default: they upload Actions artifacts but do not replace the feed or release unless the `publish` input is explicitly enabled. Partial target selections cannot be published because that would erase architectures from the regenerated feed.

### Static dependencies

Dependency versions in [`build_scripts/versions.sh`](build_scripts/versions.sh) track the upstream [`aria2-next/packaging/dependencies.env`](aria2-next/packaging/dependencies.env) baseline. The manifest explicitly classifies dependencies as downloaded, vendored, or upstream-only. Vendored version labels can follow a new submodule tag automatically; downloaded versions stop synchronization until their internally consistent archive, HTTPS URL, and SHA-256 tuple is reviewed. Added or removed dependency fields also stop for a build-graph review. The upstream manifest is parsed strictly as data and is never sourced by the write-enabled workflow. Exact pins are kept in `versions.sh` and recorded in each artifact's `BUILDINFO`, avoiding a second hard-coded version list in this document.

| Library | Source policy | Purpose |
|:---|:---|:---|
| zlib | Downloaded, SHA-256 pinned | Compression |
| expat | Downloaded, SHA-256 pinned | XML and Metalink parsing |
| SQLite | Downloaded, SHA-256 pinned | Cookie and session-related storage |
| OpenSSL | Downloaded, SHA-256 pinned | TLS and cryptography |
| libssh2 | Downloaded, SHA-256 pinned | SFTP |
| curl | Vendored by the submodule | HTTP(S) and SFTP transfer engine |
| nghttp2 | Vendored by the submodule | HTTP/2 framing for curl |
| Boost | Vendored by the submodule | Asio networking, Beast HTTP/WebSocket RPC, JSON, and libtorrent headers |
| spdlog | Vendored by the submodule | Header-only logging |
| libtorrent-rasterbar | Vendored by the submodule | BitTorrent engine |
| GPAC | Vendored by the submodule | Native HLS and MPEG-DASH client |
| FFmpeg | Vendored by the submodule | Media demuxing, stream probing, and remuxing |

DNS is asynchronous: aria2-next's core uses the Boost.Asio system resolver, while curl uses its threaded resolver. The build also enables curl's DNS-over-HTTPS support; setting upstream `dns-over-https` uses that resolver for curl transfers, while other lookups continue to use the system resolver.

The engine and libtorrent are both compiled as C++20. Keeping their Boost.Asio configuration consistent avoids an ABI mismatch that can crash a BitTorrent session on startup. Version 3 uses Boost.Beast/JSON for RPC and no longer needs wslay. Its required dependency stack is supplied through `ARIA2_DEPENDENCY_ROOT` and `ARIA2_BOOST_ROOT`, with the upstream superbuild disabled because this project builds the static dependencies itself.

The build checks upstream's actual `src/disk/File.cc` with the target C++ compiler before configuring CMake. If plain compilation fails but adding `<utility>` succeeds, it applies a C++-only `-include utility` compatibility flag for the missing `std::exchange` header. Upstream 3.0.4 includes that header, so it builds without the flag. Unrelated compile failures stop the build. This source-based check replaces the version-specific workaround that missed the 3.0.3 sync failure and leaves the pinned downloader source unchanged.

The cross-build keeps whole-program LTO for aria2-next and its other static dependencies, but deliberately compiles FFmpeg without LTO. FFmpeg uses per-object ISA flags for runtime SIMD dispatch; preserving those object boundaries prevents cross-GCC from rejecting optional instructions such as NEON during the final link. Generic MIPS builds also disable incorrect Loongson/MMI autodetection. The build validates GPAC's generated ABI width against the target compiler and supplies FFmpeg's missing RISC-V syscall include when building against musl SDK headers.

FTP was removed upstream in aria2-next 2.6.0. BitTorrent encryption is provided by libtorrent. The local dependency profile uses OpenSSL and does not add alternative TLS, allocator, or event-loop libraries.

## Local Development

### Prerequisites

- Docker
- Git with submodule support
- Bash for the repository validation helpers

Clone and initialize the upstream source:

```sh
git clone --recurse-submodules https://github.com/ysway/openwrt-aria2-next.git
cd openwrt-aria2-next
```

### Build one target with Docker

```sh
PLATFORM=x86_64
SDK_VERSION=25.12.5
mkdir -p output .cache/sources .cache/pip

docker run --rm --user root \
  -v "$PWD:/work/repo:z" \
  -v "$PWD/output:/work/output:z" \
  -e PLATFORM="$PLATFORM" \
  -e OPENWRT_SDK_VERSION="$SDK_VERSION" \
  -e BUILD_VERSION=local \
  -e SOURCE_CACHE_DIR=/work/repo/.cache/sources \
  -e PIP_CACHE_DIR=/work/repo/.cache/pip \
  -e ARIA2_BUILD_TESTS=no \
  -e UPX_ENABLED=yes \
  "ghcr.io/openwrt/sdk:${PLATFORM}-V${SDK_VERSION}" \
  bash /work/repo/build_scripts/build_in_sdk.sh "$PLATFORM"
```

Output is written to `output/<platform>/`:

- `aria2-next`
- `aria2-next-static_<version>-1_<platform>.ipk`
- `BUILDINFO`

The 25.12.5 SDK contains both `ipkg-build` and apk-tools 3, so the local build
creates the IPK and APK v3 packages in the same target job. The release workflow
renames package files to globally unique asset names without changing their
internal versions.

### Build options

| Variable or workflow input | Default | Effect |
|:---|:---|:---|
| `NPROC` | detected CPU count | Limits parallel Make/Ninja work |
| `ARIA2_BUILD_TESTS` / `build_tests` | `no` | Runs target-compiler compatibility tests and compiles `aria2_tests`; that executable is not runnable for most cross targets |
| `UPX_ENABLED` / `upx` | `yes` | Enables compression where the target safety map permits it |
| `BUILD_APK` | `auto` | Builds APK v3 when apk-tools 3 is available; CI enables it explicitly with the 25.12.5 SDK |
| `SOURCE_CACHE_DIR` | `/work/build/src` | Reuses verified dependency archives |
| `PIP_CACHE_DIR` | pip default | Reuses CMake/Ninja wheels |
| `CMAKE_PIP_SPEC` | `cmake>=3.25,<4` | Overrides the container-side CMake package constraint |
| `NINJA_PIP_SPEC` | `ninja>=1.11` | Overrides the container-side Ninja package constraint |
| `platforms` | `all` | Manual workflow target selection; accepts a comma-separated allow-listed set |
| `sdk_version` | target default | Manual workflow SDK override |
| `publish` | `false` | Allows a complete manual matrix to update the feed and release |

Release builds configure upstream with `BUILD_TESTING=OFF` and request the `aria2-next` target explicitly. Setting `ARIA2_BUILD_TESTS=yes` runs the compiler compatibility regressions and enables and compiles `aria2_tests`; most cross-target executables still require target hardware or emulation to run.

### Build scripts overview

| Script | Purpose |
|:---|:---|
| `build_in_sdk.sh` | Container entrypoint and full target pipeline |
| `common.sh` | Shared variables, verified downloads, and helper functions |
| `versions.sh` | Dependency policy, versions, URLs, and hashes |
| `sync_dependency_manifest.sh` | Safe upstream manifest reconciliation |
| `test_dependency_manifest.sh` | Dependency policy regression tests |
| `cxx_compat.sh` | Target-compiler preflight for the upstream disk implementation's standard header |
| `test_cxx_compat.sh` | C++ compatibility probe regression tests |
| `target-map.sh` | Platform to compiler/OpenSSL/UPX mapping |
| `build_deps_static.sh` | Static dependency build |
| `build_static_aria2.sh` | aria2-next CMake configuration and selected-target build |
| `verify_binary.sh` | Static-link and executable smoke verification |
| `test_binary_runtime.py` | Native HTTP/gzip, HTTPS trust, DoH, authenticated JSON/XML-RPC, WebSocket, and BitTorrent regression |
| `pack_with_upx.sh` | Optional compression with rollback and integrity testing |
| `collect_artifacts.sh` | Raw binary and `BUILDINFO` generation |
| `build_ipk.sh` | Reproducible OpenWrt IPK assembly |
| `build_apk.sh` | Standalone OpenWrt APK assembly |
| `build_apk_artifacts.sh` | Batch APK v3 packaging for downloaded matrix artifacts |
| `ci_matrix.sh` | Manual/automated platform selection validation |
| `gen_feed.sh` | Per-architecture OPKG metadata generation |
| `render_feed_index.sh` | Feed website architecture table rendering |
| `test_aria2_init.sh` | procd/UCI service smoke harness |

### Verification helpers

Fast checks:

```sh
bash -n build_scripts/*.sh
sh -n setup.sh \
  package/aria2-next-static/files/aria2-next.init \
  package/aria2-next-static/files/postinst \
  package/aria2-next-static/files/prerm
sh build_scripts/test_aria2_init.sh
bash build_scripts/test_dependency_manifest.sh
bash build_scripts/test_cxx_compat.sh
```

Runnable SDK targets also execute `test_binary_runtime.py` and validate the service's generated configurations with the built binary. The protocol fixture uses loopback HTTP/HTTPS servers and requires Python 3 plus an `openssl` command; both are installed by the SDK entrypoint. Cross-target builds retain static-link checks and need hardware or emulation for runtime coverage.

A package/feed layout check can use a dummy executable:

```sh
work_dir=$(mktemp -d)
printf '#!/bin/sh\necho aria2-next dummy\n' > "$work_dir/aria2-next"
chmod +x "$work_dir/aria2-next"

bash build_scripts/build_ipk.sh x86_64 "$work_dir/aria2-next" "$work_dir/artifacts"
cp -r feed_template "$work_dir/feed"
bash build_scripts/gen_feed.sh "$work_dir/artifacts" "$work_dir/feed/x86_64"
bash build_scripts/render_feed_index.sh "$work_dir/feed" test "local build"
```

APK v3 must be built and verified with OpenWrt's apk-tools 3:

```sh
docker run --rm --user root \
  -v "$PWD:/work/repo:ro" \
  -v "$work_dir/artifacts:/work/artifacts" \
  "ghcr.io/openwrt/sdk:x86_64-V25.12.5" \
  bash /work/repo/build_scripts/build_apk.sh \
    x86_64 /work/artifacts/aria2-next /work/artifacts
```

Run one end-to-end SDK build after changing compiler flags, dependencies, target mapping, or the container pipeline.

## Repository Structure

```text
openwrt-aria2-next/
├── .github/workflows/
│   ├── sync-upstream.yml       # Tagged upstream release tracking
│   └── build-aria2.yml         # Matrix build, feed deployment, and release
├── aria2-next/                 # Git submodule: upstream downloader source
├── build_scripts/              # Build, verification, packaging, and feed helpers
├── package/aria2-next-static/  # OpenWrt package, procd service, and UCI config
├── feed_template/              # GitHub Pages site template and styles
├── setup.sh                    # OpenWrt release installer
└── LICENSE                     # Infrastructure license
```

## Design Decisions

- **Static over dynamic:** the package is intended for devices where installing a compatible dependency closure is inconvenient or impossible.
- **Upstream source stays upstream:** downloader changes belong in `aria2-next`; this repository focuses on OpenWrt integration.
- **CMake and Ninja:** `aria2-next` supports CMake as its maintained build system, so removed Autotools machinery is not restored.
- **OpenSSL only:** one TLS backend keeps the static closure and feature behavior predictable.
- **Target-only release builds:** cross-built unit tests are opt-in; static linkage and package/service checks remain mandatory here.
- **UPX with rollback:** packing is skipped for known-sensitive architectures, and a failed integrity check restores the original binary.
- **Verified source archives:** cached downloads are accepted only when they match the pinned SHA-256 value.
- **Reproducible package metadata:** IPK archives normalize ordering, ownership, timestamps, and gzip metadata.
- **Native APK v3 tooling:** OpenWrt 25.12 packages are built and verified by apk-tools 3 rather than by approximating its binary format.
- **`docker run` from the runner:** official SDK containers are selected per matrix target without relying on a dynamic Actions `container:` expression.
- **Separate package identity:** `aria2-next-static` and `/usr/bin/aria2-next` can coexist with OpenWrt's official `aria2` package.

## Contributing

1. Fork the repository and initialize its submodule.
2. Keep downloader-source changes in the upstream `aria2-next` repository.
3. Run the smallest relevant verification set from above.
4. Use a one-target Docker build for build-system or dependency changes.
5. Submit a pull request describing affected OpenWrt versions and architectures.

When changing dependencies, classify the version field in `build_scripts/versions.sh`. Downloaded sources also require a reviewed archive, URL, and SHA-256 tuple; structural additions or removals require adapting the build graph before synchronization can continue. When changing package names, paths, workflow inputs, or artifacts, update this README and the feed template in the same change.

## Acknowledgements

- **[aria2](https://github.com/aria2/aria2)** — the original multi-protocol downloader and ecosystem
- **[aria2-next](https://github.com/AnInsomniacy/aria2-next)** — maintained source used by this packaging repository
- **[OpenWrt](https://openwrt.org/)** — SDK images, package conventions, procd, and the reference aria2 service model
- **[GuNanOvO/openwrt-tailscale](https://github.com/GuNanOvO/openwrt-tailscale)** — inspiration for the OpenWrt SDK container and feed workflow pattern

## License

The build scripts, CI configuration, feed template, and packaging infrastructure in this repository are licensed under the [MIT License](LICENSE).

The produced `aria2-next` binaries are licensed under GPL-2.0-or-later, following the upstream source and its included `COPYING` file. Bundled dependencies retain their respective licenses.
