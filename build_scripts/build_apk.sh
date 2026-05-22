#!/bin/bash
# Build an .apk package for aria2-next-static (OpenWrt 25.12+ APK format).
#
# APK v2 format: concatenation of gzipped tar segments:
#   1. Control segment: .PKGINFO (and optional scripts)
#   2. Data segment: actual installed files
# Unsigned packages omit the signature segment.
#
# Usage:
#   bash build_apk.sh <platform> <binary_path> <output_dir>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/versions.sh"

PLATFORM="${1:?Usage: build_apk.sh <platform> <binary_path> <output_dir>}"
BINARY="${2:?Binary path required}"
OUTPUT_DIR="${3:?Output directory required}"

if [ ! -f "$BINARY" ]; then
    log_fatal "Binary not found: $BINARY"
fi

ARIA2_VERSION="$(get_aria2_version)"
PKG_NAME="$PKG_BASE_NAME"
PKG_VERSION="${ARIA2_VERSION}-r1"
PKG_ARCH="$PLATFORM"
WORKDIR="$(mktemp -d)"

trap 'rm -rf "$WORKDIR"' EXIT

# ── Data directory ──────────────────────────────────────────────────────────
DATA_DIR="$WORKDIR/data"
mkdir -p "$DATA_DIR/usr/bin"
mkdir -p "$DATA_DIR/etc/init.d"
mkdir -p "$DATA_DIR/etc/config"
mkdir -p "$DATA_DIR/usr/share/doc/$PKG_NAME"

cp "$BINARY" "$DATA_DIR/usr/bin/$BINARY_NAME"
chmod 755 "$DATA_DIR/usr/bin/$BINARY_NAME"

PACKAGE_FILES="$PACKAGE_FILES_DIR"
if [ -f "$PACKAGE_FILES/aria2-next.init" ]; then
    cp "$PACKAGE_FILES/aria2-next.init" "$DATA_DIR/etc/init.d/aria2-next"
    chmod 755 "$DATA_DIR/etc/init.d/aria2-next"
fi
if [ -f "$PACKAGE_FILES/aria2-next.conf" ]; then
    cp "$PACKAGE_FILES/aria2-next.conf" "$DATA_DIR/etc/config/aria2-next"
fi

if [ -f "$OUTPUT_DIR/BUILDINFO" ]; then
    cp "$OUTPUT_DIR/BUILDINFO" "$DATA_DIR/usr/share/doc/$PKG_NAME/BUILDINFO"
fi

INSTALLED_SIZE=$(du -sk "$DATA_DIR" | awk '{print $1}')
INSTALLED_SIZE=$((INSTALLED_SIZE * 1024))

# ── .PKGINFO ───────────────────────────────────────────────────────────────
cat > "$WORKDIR/.PKGINFO" <<EOF
pkgname = $PKG_NAME
pkgver = $PKG_VERSION
pkgdesc = aria2-next download utility (statically linked)
url = https://github.com/AnInsomniacy/aria2-next
size = $INSTALLED_SIZE
arch = $PKG_ARCH
license = GPL-2.0-or-later
origin = $PKG_NAME
maintainer = openwrt-aria2-next
backup = etc/config/aria2-next
EOF

if [ -f "$PACKAGE_FILES/postinst" ]; then
    cp "$PACKAGE_FILES/postinst" "$WORKDIR/.post-install"
    chmod 755 "$WORKDIR/.post-install"
fi
if [ -f "$PACKAGE_FILES/prerm" ]; then
    cp "$PACKAGE_FILES/prerm" "$WORKDIR/.pre-deinstall"
    chmod 755 "$WORKDIR/.pre-deinstall"
fi

# ── Build control segment ──────────────────────────────────────────────────
control_files=(.PKGINFO)
[ -f "$WORKDIR/.post-install" ] && control_files+=(.post-install)
[ -f "$WORKDIR/.pre-deinstall" ] && control_files+=(.pre-deinstall)
tar -czf "$WORKDIR/control.tar.gz" -C "$WORKDIR" "${control_files[@]}"

# ── Build data segment ─────────────────────────────────────────────────────
tar -czf "$WORKDIR/data.tar.gz" -C "$DATA_DIR" .

# ── Concatenate into .apk ─────────────────────────────────────────────────
ensure_dir "$OUTPUT_DIR"
APK_FILE="$OUTPUT_DIR/${PKG_NAME}-${ARIA2_VERSION}-r1.apk"

cat "$WORKDIR/control.tar.gz" "$WORKDIR/data.tar.gz" > "$APK_FILE"

log_info "Built: $APK_FILE"
echo "APK_FILE=$APK_FILE"
