# openwrt-aria2-next

Static [aria2-next](https://github.com/AnInsomniacy/aria2-next) builds for OpenWrt. The project builds `aria2-next` inside official OpenWrt SDK Docker images, packages it as `aria2-next-static`, and publishes IPK, APK, and raw binary artifacts for common OpenWrt targets.

This branch replaces the retired `aria2-builder` submodule with the maintained `aria2-next` source repository.

## What Changed

- Upstream source: `aria2-next/` git submodule from `https://github.com/AnInsomniacy/aria2-next.git`
- Upstream version source: `aria2-next/CMakeLists.txt`
- Build system: CMake 3.25+ and Ninja, not Autotools
- Installed binary: `/usr/bin/aria2-next`
- OpenWrt package: `aria2-next-static`
- Service path: `/etc/init.d/aria2-next`
- Config path: `/etc/config/aria2-next`

The UCI section type remains `config aria2` because the service is adapted from OpenWrt's official `net/aria2` init model. Existing `/etc/config/aria2` files can usually be reused by copying them to `/etc/config/aria2-next`.

## Features

- Statically linked OpenWrt binary built against the official SDK toolchain
- Native aria2-next engine with expat, SQLite, c-ares, OpenSSL, libssh2, and zlib linked statically
- ED2K, BitTorrent, Metalink, XML-RPC, Async DNS, HTTP, HTTPS, FTP, and SFTP support from aria2-next
- OPKG `.ipk` package for OpenWrt 24.10 and older
- APK `.apk` package for OpenWrt 25.12 and newer
- Raw `aria2-next` binary artifact for manual installs
- Feed branch generation for per-architecture OPKG metadata

## Dependency Baseline

Dependency versions are pinned in [build_scripts/versions.sh](build_scripts/versions.sh) and should track `aria2-next/packaging/dependencies.env`.

| Dependency | Version |
| --- | --- |
| zlib | 1.3.2 |
| expat | 2.8.1 |
| SQLite | 3.53.1 |
| c-ares | 1.34.6 |
| libssh2 | 1.11.1 |
| OpenSSL | 3.5.6 |

OpenWrt builds intentionally keep the upstream OpenSSL backend and disable the unused GnuTLS, nettle, GMP, libgcrypt, libuv, and libxml2 paths for a smaller static closure.

OpenSSL RC4 support is intentionally preserved because aria2's OpenSSL backend still uses ARC4 for BitTorrent MSE.

## Install From Release Assets

Set `VERSION`, `TAG`, and `ARCH` to match the release and target architecture. Tagged upstream releases use `TAG=v${VERSION}`.

```sh
VERSION=2.4.1
TAG=v${VERSION}
ARCH=x86_64
```

For OPKG-based OpenWrt:

```sh
wget "https://github.com/ysway/openwrt-aria2-next/releases/download/${TAG}/aria2-next-static_${VERSION}-1_${ARCH}.ipk"
opkg install "aria2-next-static_${VERSION}-1_${ARCH}.ipk"
```

For APK-based OpenWrt:

```sh
wget "https://github.com/ysway/openwrt-aria2-next/releases/download/${TAG}/aria2-next-static-${VERSION}-r1.apk"
apk add --allow-untrusted "aria2-next-static-${VERSION}-r1.apk"
```

For a raw binary install:

```sh
wget -O /usr/bin/aria2-next "https://github.com/ysway/openwrt-aria2-next/releases/download/${TAG}/aria2-next_${VERSION}_${ARCH}"
chmod +x /usr/bin/aria2-next
aria2-next --version
```

## Install From The Feed

For OpenWrt 24.10 or older, add the matching architecture feed:

```sh
ARCH=$(opkg print-architecture | awk 'NF==3 && $3~/^[0-9]+$/ {print $2}' | tail -1)
echo "src/gz aria2-next-static https://ysway.github.io/openwrt-aria2-next/${ARCH}" >> /etc/opkg/customfeeds.conf
opkg update
opkg install aria2-next-static
```

The feed branch publishes OPKG metadata only. APK packages are published as standalone release/feed files and are installed with `apk add --allow-untrusted <file>`.

## Service Setup

The package installs a disabled-by-default service. Configure a download directory before starting it.

```sh
uci set aria2-next.main.enabled='1'
uci set aria2-next.main.dir='/mnt/data/downloads'
uci commit aria2-next
service aria2-next enable
service aria2-next start
```

Useful paths:

| Path | Purpose |
| --- | --- |
| `/usr/bin/aria2-next` | Static binary |
| `/etc/init.d/aria2-next` | procd service |
| `/etc/config/aria2-next` | UCI configuration |
| `/var/etc/aria2-next` | Rendered runtime config/session state by default |
| `/mnt/sda1/aria2-next` | Default download directory in the packaged sample config |

The service also accepts legacy `download_dir` and `dht_enable` keys from older `aria2-static` configs.

## Build Locally With Docker

Initialize the submodule first:

```sh
git submodule update --init --recursive
```

Build one target with the official OpenWrt SDK Docker image:

```sh
PLATFORM=x86_64
SDK_VERSION=24.10.4
docker pull "ghcr.io/openwrt/sdk:${PLATFORM}-V${SDK_VERSION}"
docker run --rm --user root \
  -v "$PWD:/work/repo:z" \
  -v "$PWD/output:/work/output:z" \
  -e PLATFORM="$PLATFORM" \
  -e OPENWRT_SDK_VERSION="$SDK_VERSION" \
  -e BUILD_VERSION="local" \
  "ghcr.io/openwrt/sdk:${PLATFORM}-V${SDK_VERSION}" \
  bash /work/repo/build_scripts/build_in_sdk.sh "$PLATFORM"
```

Outputs are written to `output/$PLATFORM/`:

- `aria2-next`
- `aria2-next-static_<version>-1_<platform>.ipk`
- `aria2-next-static-<version>-r1.apk`
- `BUILDINFO`

Validated locally for `aria2-next` `v2.4.1` with OpenWrt SDK `24.10.4`: `x86_64`, `arm_cortex-a9`, and `i386_pentium-mmx`.

## Build Pipeline

[.github/workflows/build-aria2.yml](.github/workflows/build-aria2.yml) builds the target matrix by running `docker run` against official SDK images such as `ghcr.io/openwrt/sdk:x86_64-V24.10.4`. It does not use the GitHub Actions `container:` directive.

[.github/workflows/sync-upstream.yml](.github/workflows/sync-upstream.yml) updates the `aria2-next` submodule to the latest upstream release tag and syncs dependency versions from `aria2-next/packaging/dependencies.env`.

The default SDK versions are:

- IPK-era build: `24.10.4`
- APK-era build: `25.12.0`

## Repository Layout

```text
aria2-next/                 Git submodule for upstream source
build_scripts/              OpenWrt SDK, static dependency, package, and feed helpers
feed_template/              GitHub Pages feed UI template
package/aria2-next-static/  OpenWrt package Makefile, init script, UCI config, package hooks
install.sh                  Quick installer for release assets
```

## Verification Helpers

```sh
bash -n build_scripts/*.sh
sh -n package/aria2-next-static/files/aria2-next.init \
  package/aria2-next-static/files/postinst \
  package/aria2-next-static/files/prerm
sh build_scripts/test_aria2_init.sh
```

A focused package-layout check can be done with a dummy binary:

```sh
tmpdir=$(mktemp -d)
printf '#!/bin/sh\necho aria2-next dummy\n' > "$tmpdir/aria2-next"
chmod +x "$tmpdir/aria2-next"
bash build_scripts/build_ipk.sh x86_64 "$tmpdir/aria2-next" "$tmpdir/out"
```

## Notes For Maintainers

- Keep `aria2-next` changes in the upstream repository; this project should only package and build it for OpenWrt.
- Keep dependency pins aligned with `aria2-next/packaging/dependencies.env`.
- Keep the OpenWrt service schema compatible with official `net/aria2` configs unless a migration note is added.
- Do not rename the package back to `aria2`; `aria2-next-static` is intentionally separate from OpenWrt's official `aria2` package.
