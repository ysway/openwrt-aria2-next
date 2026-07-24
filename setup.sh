#!/bin/sh
# Quick installer for the static aria2-next build on OpenWrt.
#
# Usage:
#   wget -O- https://raw.githubusercontent.com/ysway/openwrt-aria2-next/master/setup.sh | sh
#
# Or download and run:
#   sh setup.sh
#
# Optional environment overrides:
#   ARIA2_RELEASE_TAG=v2.5.2 ARIA2_ARCH=x86_64 sh setup.sh
#   ARIA2_INSTALL_MODE=raw sh setup.sh
#   ARIA2_REPO=owner/fork sh setup.sh

set -eu

REPO="${ARIA2_REPO:-ysway/openwrt-aria2-next}"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
DOWNLOAD_BASE="https://github.com/${REPO}/releases/download"
WORK_DIR="$(mktemp -d /tmp/aria2-next.XXXXXX)"

cleanup() {
    rm -rf "$WORK_DIR"
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
    verify_asset "$asset_name" "$destination"
}

verify_asset() {
    asset_name="$1"
    asset_path="$2"
    checksums_path="$WORK_DIR/SHA256SUMS"
    checksums_url="${DOWNLOAD_BASE}/${LATEST_TAG}/SHA256SUMS"

    if ! command -v sha256sum >/dev/null 2>&1; then
        echo "WARNING: sha256sum is unavailable; skipping download verification" >&2
        return
    fi

    if ! wget -q -O "$checksums_path" "$checksums_url"; then
        echo "WARNING: SHA256SUMS is unavailable for ${LATEST_TAG}; skipping verification" >&2
        return
    fi

    expected="$(awk -v asset="$asset_name" '$2 == asset || $2 == "*" asset { print $1; exit }' "$checksums_path")"
    if [ -z "$expected" ]; then
        echo "ERROR: ${asset_name} is missing from SHA256SUMS" >&2
        exit 1
    fi

    actual="$(sha256sum "$asset_path" | awk '{print $1}')"
    if [ "$actual" != "$expected" ]; then
        echo "ERROR: SHA-256 verification failed for ${asset_name}" >&2
        exit 1
    fi

    echo "Verified SHA-256: ${expected}"
}

install_with_opkg() {
    asset_name="aria2-next-static_${VERSION}_${ARCH}.ipk"
    pkg_path="$WORK_DIR/$asset_name"

    download_asset "$asset_name" "$pkg_path"
    echo "Installing ${asset_name} with opkg..."
    opkg install "$pkg_path"
}

install_with_apk() {
    asset_name="aria2-next-static_${VERSION}_${ARCH}.apk"
    pkg_path="$WORK_DIR/$asset_name"

    download_asset "$asset_name" "$pkg_path"
    echo "Installing ${asset_name} with apk..."
    apk add --allow-untrusted "$pkg_path"
}

install_raw_binary() {
    asset_name="aria2-next_${VERSION}_${ARCH}"
    binary_path="$WORK_DIR/$asset_name"

    download_asset "$asset_name" "$binary_path"
    echo "Installing raw binary fallback..."
    cp "$binary_path" /usr/bin/aria2-next
    chmod 0755 /usr/bin/aria2-next
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

LATEST_TAG="${ARIA2_RELEASE_TAG:-$(get_latest_tag)}"
if [ -z "$LATEST_TAG" ]; then
    echo "ERROR: Could not determine the latest release tag from ${API_URL}" >&2
    exit 1
fi

VERSION="$(version_from_tag "$LATEST_TAG")"
ARCH="${ARIA2_ARCH:-$(detect_arch)}"
INSTALL_MODE="${ARIA2_INSTALL_MODE:-auto}"

echo "Latest release: $LATEST_TAG"
echo "Detected architecture: $ARCH"

case "$INSTALL_MODE" in
    auto)
        if command -v apk >/dev/null 2>&1 && [ -f /etc/apk/arch ]; then
            install_with_apk
        elif command -v opkg >/dev/null 2>&1; then
            install_with_opkg
        else
            install_raw_binary
        fi
        ;;
    apk)
        command -v apk >/dev/null 2>&1 || {
            echo "ERROR: ARIA2_INSTALL_MODE=apk but apk is unavailable" >&2
            exit 1
        }
        install_with_apk
        ;;
    opkg)
        command -v opkg >/dev/null 2>&1 || {
            echo "ERROR: ARIA2_INSTALL_MODE=opkg but opkg is unavailable" >&2
            exit 1
        }
        install_with_opkg
        ;;
    raw)
        install_raw_binary
        ;;
    *)
        echo "ERROR: Unsupported ARIA2_INSTALL_MODE: $INSTALL_MODE" >&2
        echo "Expected one of: auto, opkg, apk, raw" >&2
        exit 1
        ;;
esac

if /usr/bin/aria2-next --version >/dev/null 2>&1; then
    echo "aria2-next installed successfully"
    /usr/bin/aria2-next --version | head -1
else
    echo "WARNING: aria2-next installed but could not be verified" >&2
fi
