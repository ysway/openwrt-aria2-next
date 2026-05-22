#!/bin/sh
# Quick installer for the static aria2-next build on OpenWrt.
#
# Usage:
#   wget -O- https://raw.githubusercontent.com/ysway/openwrt-aria2-next/master/setup.sh | sh
#
# Or download and run:
#   sh setup.sh

set -eu

REPO="ysway/openwrt-aria2-next"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
DOWNLOAD_BASE="https://github.com/${REPO}/releases/download"
TMPDIR="$(mktemp -d /tmp/aria2-next.XXXXXX)"

cleanup() {
    rm -rf "$TMPDIR"
}

trap cleanup EXIT INT TERM

detect_arch() {
    if command -v apk >/dev/null 2>&1 && [ -f /etc/apk/arch ]; then
        cat /etc/apk/arch
        return
    fi

    if command -v opkg >/dev/null 2>&1; then
        opkg print-architecture 2>/dev/null \
            | awk 'NF==3 && $3~/^[0-9]+$/ {print $2}' \
            | tail -1
        return
    fi

    arch="$(uname -m)"
    case "$arch" in
        x86_64)        echo "x86_64" ;;
        aarch64)       echo "aarch64_generic" ;;
        armv7*|armv6*) echo "arm_cortex-a7" ;;
        mips)          echo "mips_24kc" ;;
        mipsel)        echo "mipsel_24kc" ;;
        riscv64)       echo "riscv64_generic" ;;
        loongarch64)   echo "loongarch64_generic" ;;
        i?86)          echo "i386_pentium4" ;;
        *)
            echo "ERROR: Unsupported architecture: $arch" >&2
            exit 1
            ;;
    esac
}

get_latest_tag() {
    wget -qO- "$API_URL" \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -n 1
}

download_asset() {
    asset_name="$1"
    destination="$2"
    asset_url="${DOWNLOAD_BASE}/${LATEST_TAG}/${asset_name}"

    echo "Downloading ${asset_name}..."
    wget -q -O "$destination" "$asset_url"
}

install_with_opkg() {
    asset_name="aria2-next-static_${VERSION}_${ARCH}.ipk"
    pkg_path="$TMPDIR/$asset_name"

    download_asset "$asset_name" "$pkg_path"
    echo "Installing ${asset_name} with opkg..."
    opkg install "$pkg_path"
}

install_with_apk() {
    asset_name="aria2-next-static_${VERSION}_${ARCH}.apk"
    pkg_path="$TMPDIR/$asset_name"

    download_asset "$asset_name" "$pkg_path"
    echo "Installing ${asset_name} with apk..."
    apk add --allow-untrusted "$pkg_path"
}

install_raw_binary() {
    asset_name="aria2-next_${VERSION}_${ARCH}"
    binary_path="$TMPDIR/$asset_name"

    download_asset "$asset_name" "$binary_path"
    echo "Installing raw binary fallback..."
    install -m 0755 "$binary_path" /usr/bin/aria2-next
}

version_from_tag() {
    tag="$1"
    case "$tag" in
        v*)
            echo "${tag#v}"
            ;;
        aria2-next-*)
            version="${tag#aria2-next-}"
            case "$version" in
                *-????????????) echo "${version%-????????????}" ;;
                *) echo "$version" ;;
            esac
            ;;
        *)
            echo "$tag"
            ;;
    esac
}

LATEST_TAG="$(get_latest_tag)"
if [ -z "$LATEST_TAG" ]; then
    echo "ERROR: Could not determine the latest release tag from ${API_URL}" >&2
    exit 1
fi

VERSION="$(version_from_tag "$LATEST_TAG")"
ARCH="$(detect_arch)"

echo "Latest release: $LATEST_TAG"
echo "Detected architecture: $ARCH"

if command -v apk >/dev/null 2>&1 && [ -f /etc/apk/arch ]; then
    install_with_apk
elif command -v opkg >/dev/null 2>&1; then
    install_with_opkg
else
    install_raw_binary
fi

if /usr/bin/aria2-next --version >/dev/null 2>&1; then
    echo "aria2-next installed successfully"
    /usr/bin/aria2-next --version | head -1
else
    echo "WARNING: aria2-next installed but could not be verified" >&2
fi
