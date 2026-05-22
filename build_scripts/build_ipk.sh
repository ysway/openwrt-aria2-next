#!/bin/bash
# Build an .ipk package for the static aria2-next build.
#
# This creates an OpenWrt-compatible .ipk as a gzip-compressed tarball
# containing debian-binary, data.tar.gz, and control.tar.gz. The structure
# matches OpenWrt's ipkg-build script (see /builder/scripts/ipkg-build inside
# the SDK image) so the result is installable with opkg on target devices.
#
# The default package name is `aria2-next-static`. It installs `/usr/bin/aria2-next`
# and `/etc/init.d/aria2-next`, so it can coexist with the official OpenWrt
# `aria2` package unless callers explicitly set Conflicts/Replaces overrides.
# Override via PKG_NAME_OVERRIDE / PKG_RELEASE_OVERRIDE / PKG_CONFLICTS_OVERRIDE
# / PKG_REPLACES_OVERRIDE / PKG_PROVIDES_OVERRIDE to generate variants.
#
# Usage:
#   bash build_ipk.sh <platform> <binary_path> <output_dir>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/versions.sh"

PLATFORM="${1:?Usage: build_ipk.sh <platform> <binary_path> <output_dir>}"
BINARY="${2:?Binary path required}"
OUTPUT_DIR_INPUT="${3:?Output directory required}"

ensure_dir "$OUTPUT_DIR_INPUT"
OUTPUT_DIR="$(cd "$OUTPUT_DIR_INPUT" && pwd)"

if [ ! -f "$BINARY" ]; then
    log_fatal "Binary not found: $BINARY"
fi

ARIA2_VERSION="$(get_aria2_version)"
PKG_NAME="${PKG_NAME_OVERRIDE:-$PKG_BASE_NAME}"
PKG_RELEASE="${PKG_RELEASE_OVERRIDE:-1}"
PKG_VERSION="${ARIA2_VERSION}-${PKG_RELEASE}"
PKG_ARCH="$PLATFORM"
PKG_CONFLICTS="${PKG_CONFLICTS_OVERRIDE:-}"
PKG_REPLACES="${PKG_REPLACES_OVERRIDE:-}"
PKG_PROVIDES="${PKG_PROVIDES_OVERRIDE:-}"

WORKDIR="$(mktemp -d)"

trap 'rm -rf "$WORKDIR"' EXIT

# ── package staging directory ───────────────────────────────────────────────
PKG_DIR="$WORKDIR/pkg"
DATA_DIR="$PKG_DIR"
mkdir -p "$DATA_DIR/usr/bin"
mkdir -p "$DATA_DIR/etc/init.d"
mkdir -p "$DATA_DIR/etc/config"
mkdir -p "$DATA_DIR/usr/share/doc/$PKG_NAME"
mkdir -p "$PKG_DIR/CONTROL"

cp "$BINARY" "$DATA_DIR/usr/bin/$BINARY_NAME"
chmod 755 "$DATA_DIR/usr/bin/$BINARY_NAME"

# Install init script and config if available
PACKAGE_FILES="$PACKAGE_FILES_DIR"
if [ -f "$PACKAGE_FILES/aria2-next.init" ]; then
    cp "$PACKAGE_FILES/aria2-next.init" "$DATA_DIR/etc/init.d/aria2-next"
    chmod 755 "$DATA_DIR/etc/init.d/aria2-next"
fi
if [ -f "$PACKAGE_FILES/aria2-next.conf" ]; then
    cp "$PACKAGE_FILES/aria2-next.conf" "$DATA_DIR/etc/config/aria2-next"
fi

# BUILDINFO
if [ -f "$OUTPUT_DIR/BUILDINFO" ]; then
    cp "$OUTPUT_DIR/BUILDINFO" "$DATA_DIR/usr/share/doc/$PKG_NAME/BUILDINFO"
fi

cd "$DATA_DIR"
tar --format=gnu --numeric-owner --sort=name -cpf - --mtime='@0' \
    --exclude='./CONTROL' . | gzip -n - > "$WORKDIR/data.tar.gz"

# ── control.tar.gz ──────────────────────────────────────────────────────────
CTRL_DIR="$PKG_DIR/CONTROL"

INSTALLED_SIZE=$(gzip -cd "$WORKDIR/data.tar.gz" | wc -c | awk '{print $1}')

cat > "$CTRL_DIR/control" <<EOF
Package: $PKG_NAME
Version: $PKG_VERSION
Architecture: $PKG_ARCH
Maintainer: openwrt-aria2-next
Description: aria2-next download utility (statically linked)
 A maintained aria2-compatible download utility with ED2K, BitTorrent,
 Metalink, and HTTP/HTTPS/FTP/SFTP support. This package ships a
 statically linked aria2-next binary with OpenSSL, libssh2, c-ares,
 expat, sqlite3, and zlib embedded.
Installed-Size: $INSTALLED_SIZE
Section: net
Priority: optional
EOF

if [ -n "$PKG_CONFLICTS" ]; then
    echo "Conflicts: $PKG_CONFLICTS" >> "$CTRL_DIR/control"
fi

if [ -n "$PKG_REPLACES" ]; then
    echo "Replaces: $PKG_REPLACES" >> "$CTRL_DIR/control"
fi

if [ -n "$PKG_PROVIDES" ]; then
    echo "Provides: $PKG_PROVIDES" >> "$CTRL_DIR/control"
fi

# conffiles
cat > "$CTRL_DIR/conffiles" <<EOF
/etc/config/aria2-next
EOF

# Install postinst/prerm scripts (mirrors USERID:=aria2=6800:aria2=6800
# from the official OpenWrt aria2 Makefile, plus enable/disable hooks).
for hook in postinst prerm; do
    if [ -f "$PACKAGE_FILES/$hook" ]; then
        cp "$PACKAGE_FILES/$hook" "$CTRL_DIR/$hook"
        chmod 755 "$CTRL_DIR/$hook"
    fi
done

cd "$CTRL_DIR"
# Match OpenWrt's ipkg-build layout and metadata normalization.
tar --format=gnu --numeric-owner --sort=name -cf - --mtime='@0' . | \
    gzip -n - > "$WORKDIR/control.tar.gz"

# ── Assemble .ipk ──────────────────────────────────────────────────────────
echo "2.0" > "$WORKDIR/debian-binary"

IPK_FILE="$OUTPUT_DIR/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.ipk"

cd "$WORKDIR"
tar --format=gnu --numeric-owner --sort=name -cf - --mtime='@0' \
    ./debian-binary ./data.tar.gz ./control.tar.gz | gzip -n - > "$IPK_FILE"

log_info "Built: $IPK_FILE"
echo "IPK_FILE=$IPK_FILE"
