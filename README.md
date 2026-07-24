# openwrt-aria2-next

[![Build aria2-next](https://github.com/ysway/openwrt-aria2-next/actions/workflows/build-aria2.yml/badge.svg)](https://github.com/ysway/openwrt-aria2-next/actions/workflows/build-aria2.yml)
[![Package feed](https://img.shields.io/badge/feed-GitHub%20Pages-0969da)](https://ysway.github.io/openwrt-aria2-next/)
[![License: MIT](https://img.shields.io/badge/Infrastructure-MIT-blue.svg)](LICENSE)

Statically linked [aria2-next](https://github.com/AnInsomniacy/aria2-next) builds for [OpenWrt](https://openwrt.org/), compiled inside official OpenWrt SDK containers and published as OPKG, APK, and raw binary artifacts across 33 target architectures.

This repository owns the OpenWrt build, packaging, service integration, release, and package-feed layers. The downloader source remains in the `aria2-next/` git submodule.

## Features

- **Self-contained binaries** — target libraries are linked statically to avoid firmware package dependency conflicts
- **Broad protocol support** — HTTP(S), FTP, SFTP, BitTorrent, Metalink, XML-RPC, WebSocket RPC, and ED2K
- **OpenSSL backend** — TLS support with static OpenSSL, plus c-ares async DNS
- **33 OpenWrt target architectures** — built with official OpenWrt SDK Docker images
- **Dual package format** — `.ipk` for OPKG-based OpenWrt and standalone `.apk` for APK-based OpenWrt
- **OpenWrt service integration** — procd init script and UCI configuration based on OpenWrt's official `net/aria2` model
- **UPX compression with a safety net** — optional, verified after packing, and skipped on known-sensitive targets
- **Auditable releases** — raw binaries, `BUILDINFO`, per-file hashes on the feed, and release `SHA256SUMS`
- **Automated upstream tracking** — the sync workflow follows tagged `aria2-next` releases

## Supported Architectures

<details>
<summary>All 33 target platforms</summary>

| Architecture | Platforms | UPX | Default SDK |
|:---|:---|:---:|:---:|
| **AArch64** | `aarch64_cortex-a53`, `aarch64_cortex-a72`, `aarch64_cortex-a76`, `aarch64_generic` | Yes | 24.10.7 |
| **ARM** | `arm_arm1176jzf-s_vfp`, `arm_arm926ej-s`, `arm_cortex-a15_neon-vfpv4`, `arm_cortex-a5_vfpv4`, `arm_cortex-a7`, `arm_cortex-a7_neon-vfpv4`, `arm_cortex-a7_vfpv4`, `arm_cortex-a8_vfpv3`, `arm_cortex-a9`, `arm_cortex-a9_neon`, `arm_cortex-a9_vfpv3-d16`, `arm_fa526`, `arm_xscale` | Yes | 24.10.7 |
| **x86** | `i386_pentium-mmx`, `i386_pentium4` | Yes | 24.10.7 |
| **x86_64** | `x86_64` | Yes | 24.10.7 |
| **MIPS** | `mips_24kc`, `mips_4kec`, `mips_mips32` | Yes | 24.10.7 |
| **MIPS-EL** | `mipsel_24kc`, `mipsel_24kc_24kf`, `mipsel_74kc`, `mipsel_mips32` | Yes | 24.10.7 |
| **MIPS64** | `mips64_mips64r2`, `mips64_octeonplus` | No | 24.10.7 |
| **MIPS64-EL** | `mips64el_mips64r2` | No | 24.10.7 |
| **RISC-V 64** | `riscv64_riscv64` | No | 24.10.7 |
| **RISC-V 64** | `riscv64_generic` | No | 25.12.5 |
| **LoongArch64** | `loongarch64_generic` | No | 24.10.7 |

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
ARIA2_RELEASE_TAG=v2.5.2 ARIA2_ARCH=x86_64 sh setup.sh
ARIA2_INSTALL_MODE=raw sh setup.sh
ARIA2_REPO=owner/fork sh setup.sh
```

`ARIA2_INSTALL_MODE` accepts `auto`, `opkg`, `apk`, or `raw`.

### Option 2: Download an IPK from Releases

Use this on OPKG-based OpenWrt:

```sh
VERSION=2.5.2
TAG="v${VERSION}"
ARCH=x86_64

wget "https://github.com/ysway/openwrt-aria2-next/releases/download/${TAG}/aria2-next-static_${VERSION}_${ARCH}.ipk"
opkg install "aria2-next-static_${VERSION}_${ARCH}.ipk"
```

Replace the example version and architecture with values from the [latest release](https://github.com/ysway/openwrt-aria2-next/releases/latest).

### Option 3: Download an APK from Releases

Use this on APK-based OpenWrt:

```sh
VERSION=2.5.2
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
VERSION=2.5.2
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
| `/var/etc/aria2-next` | Rendered runtime config, session, and DHT state by default |
| `/mnt/sda1/aria2-next` | Download directory in the packaged sample config |

The UCI section type remains `config aria2` to match OpenWrt's official schema. Existing `/etc/config/aria2` files can usually be reused by copying them to `/etc/config/aria2-next`. The service also accepts the older `download_dir` and `dht_enable` keys.

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
  └─ Find the newest aria2-next v* tag
  └─ Update the submodule and dependency pins
  └─ Dispatch build-aria2.yml
       │
       ▼
prepare job
  └─ Validate the requested platform list
  └─ Read one version and timestamp for the whole run
       │
       ▼
build matrix (up to 33 targets)
  └─ Pull official OpenWrt SDK image
  └─ Restore dependency/download cache
  └─ Build verified static dependencies
  └─ Build only the aria2-next executable target by default
  └─ Verify static linkage → optional UPX → IPK → upload
       │
       ▼
APK packaging job
  └─ Use OpenWrt 25.12 apk-tools 3 to build and verify APK v3
       │
       ├─► deploy job: regenerate the feed branch and website
       └─► release job: publish IPK, APK, binary, and SHA256SUMS assets
```

Scheduled upstream builds publish automatically. Manual workflow runs are safe previews by default: they upload Actions artifacts but do not replace the feed or release unless the `publish` input is explicitly enabled. Partial target selections cannot be published because that would erase architectures from the regenerated feed.

### Static dependencies

Versions, URLs, and SHA-256 hashes are pinned in [`build_scripts/versions.sh`](build_scripts/versions.sh) and track the upstream [`aria2-next/packaging/dependencies.env`](aria2-next/packaging/dependencies.env) baseline.

| Library | Version | Purpose |
|:---|:---|:---|
| zlib | 1.3.2 | Compression |
| expat | 2.8.1 | XML and Metalink parsing |
| SQLite | 3.53.1 | Cookie and session-related storage |
| c-ares | 1.34.5 | Async DNS |
| OpenSSL | 3.5.6 | TLS and cryptography |
| libssh2 | 1.11.1 | SFTP |

Builds keep the OpenSSL ARC4 implementation because aria2's BitTorrent MSE path still depends on it. Unused GnuTLS, nettle, GMP, libgcrypt, libuv, libxml2, jemalloc, and tcmalloc paths are disabled.

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
SDK_VERSION=24.10.7
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

When the selected SDK contains apk-tools 3, the local build also creates
`aria2-next-static-<version>-r1.apk`. The CI workflow packages all targets in a
separate OpenWrt 25.12 SDK job so APK v3 output is consistent even when the
binary was built with a 24.10 SDK. The release workflow then renames package
files to globally unique asset names without changing their internal versions.

### Build options

| Variable or workflow input | Default | Effect |
|:---|:---|:---|
| `NPROC` | detected CPU count | Limits parallel Make/Ninja work |
| `ARIA2_BUILD_TESTS` / `build_tests` | `no` | Also compiles `aria2_tests`; it is not runnable for most cross targets |
| `UPX_ENABLED` / `upx` | `yes` | Enables compression where the target safety map permits it |
| `BUILD_APK` | `auto` | Builds APK v3 when apk-tools 3 is available; CI defers this to its packaging job |
| `SOURCE_CACHE_DIR` | `/work/build/src` | Reuses verified dependency archives |
| `PIP_CACHE_DIR` | pip default | Reuses CMake/Ninja wheels |
| `CMAKE_PIP_SPEC` | `cmake>=3.25,<4` | Overrides the container-side CMake package constraint |
| `NINJA_PIP_SPEC` | `ninja>=1.11` | Overrides the container-side Ninja package constraint |
| `platforms` | `all` | Manual workflow target selection; accepts a comma-separated allow-listed set |
| `sdk_version` | target default | Manual workflow SDK override |
| `publish` | `false` | Allows a complete manual matrix to update the feed and release |

The upstream CMake project currently defines its test target unconditionally. Release builds therefore request the `aria2-next` target explicitly; using CMake's default `all` target would compile a large test executable 33 times without running it.

### Build scripts overview

| Script | Purpose |
|:---|:---|
| `build_in_sdk.sh` | Container entrypoint and full target pipeline |
| `common.sh` | Shared variables, verified downloads, and helper functions |
| `versions.sh` | Dependency versions, URLs, and hashes |
| `target-map.sh` | Platform to compiler/OpenSSL/UPX mapping |
| `build_deps_static.sh` | Static dependency build |
| `build_static_aria2.sh` | aria2-next CMake configuration and selected-target build |
| `verify_binary.sh` | Static-link and executable smoke verification |
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
```

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

When changing dependency versions, update the upstream dependency baseline first and keep `build_scripts/versions.sh` synchronized. When changing package names, paths, workflow inputs, or artifacts, update this README and the feed template in the same change.

## Acknowledgements

- **[aria2](https://github.com/aria2/aria2)** — the original multi-protocol downloader and ecosystem
- **[aria2-next](https://github.com/AnInsomniacy/aria2-next)** — maintained source used by this packaging repository
- **[OpenWrt](https://openwrt.org/)** — SDK images, package conventions, procd, and the reference aria2 service model
- **[GuNanOvO/openwrt-tailscale](https://github.com/GuNanOvO/openwrt-tailscale)** — inspiration for the OpenWrt SDK container and feed workflow pattern

## License

The build scripts, CI configuration, feed template, and packaging infrastructure in this repository are licensed under the [MIT License](LICENSE).

The produced `aria2-next` binaries are licensed under GPL-2.0-or-later, following the upstream source and its included `COPYING` file. Bundled dependencies retain their respective licenses.
