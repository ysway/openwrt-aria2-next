#!/bin/bash
# Build an OpenWrt APK v3 package for aria2-next-static (OpenWrt 25.12+).
#
# APK v3 is an ADB-based format and must be produced by apk-tools 3. Hand-built
# concatenated gzip streams are APK v2 and are rejected by OpenWrt 25.12.
#
# Usage:
#   bash build_apk.sh <platform> <binary_path> <output_dir>
#
# APK_TOOL may override the apk-tools 3 executable. Inside an OpenWrt 25.12 SDK
# image the host tool is normally /builder/staging_dir/host/bin/apk.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PLATFORM="${1:?Usage: build_apk.sh <platform> <binary_path> <output_dir>}"
BINARY="${2:?Binary path required}"
OUTPUT_DIR_INPUT="${3:?Output directory required}"

if [ ! -f "$BINARY" ]; then
    log_fatal "Binary not found: $BINARY"
fi

ensure_dir "$OUTPUT_DIR_INPUT"
OUTPUT_DIR="$(cd "$OUTPUT_DIR_INPUT" && pwd)"

resolve_apk_tool() {
    if [ -n "${APK_TOOL:-}" ] && [ -x "$APK_TOOL" ]; then
        printf '%s\n' "$APK_TOOL"
    elif [ -x /builder/staging_dir/host/bin/apk ]; then
        printf '%s\n' /builder/staging_dir/host/bin/apk
    elif command -v apk >/dev/null 2>&1; then
        command -v apk
    else
        return 1
    fi
}

if ! APK_TOOL_PATH="$(resolve_apk_tool)"; then
    log_fatal "apk-tools 3 is required to build OpenWrt 25.12 APK packages"
fi

APK_VERSION_OUTPUT="$("$APK_TOOL_PATH" --version 2>&1)"
case "$APK_VERSION_OUTPUT" in
    "apk-tools 3."*) ;;
    *) log_fatal "apk-tools 3 is required; found: $APK_VERSION_OUTPUT" ;;
esac

ARIA2_VERSION="$(get_aria2_version)"
PKG_NAME="$PKG_BASE_NAME"
PKG_VERSION="${ARIA2_VERSION}-r1"
PKG_ARCH="$PLATFORM"
WORK_DIR="$(mktemp -d)"
DATA_DIR="$WORK_DIR/data"
APK_FILE="$OUTPUT_DIR/${PKG_NAME}-${PKG_VERSION}.apk"

trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p \
    "$DATA_DIR/usr/bin" \
    "$DATA_DIR/etc/init.d" \
    "$DATA_DIR/etc/config" \
    "$DATA_DIR/usr/share/doc/$PKG_NAME" \
    "$DATA_DIR/lib/apk/packages"

cp "$BINARY" "$DATA_DIR/usr/bin/$BINARY_NAME"
chmod 0755 "$DATA_DIR/usr/bin/$BINARY_NAME"

PACKAGE_FILES="$PACKAGE_FILES_DIR"
if [ -f "$PACKAGE_FILES/aria2-next.init" ]; then
    cp "$PACKAGE_FILES/aria2-next.init" "$DATA_DIR/etc/init.d/aria2-next"
    chmod 0755 "$DATA_DIR/etc/init.d/aria2-next"
fi
if [ -f "$PACKAGE_FILES/aria2-next.conf" ]; then
    cp "$PACKAGE_FILES/aria2-next.conf" "$DATA_DIR/etc/config/aria2-next"
    chmod 0644 "$DATA_DIR/etc/config/aria2-next"
fi
if [ -f "$OUTPUT_DIR/BUILDINFO" ]; then
    cp "$OUTPUT_DIR/BUILDINFO" "$DATA_DIR/usr/share/doc/$PKG_NAME/BUILDINFO"
    chmod 0644 "$DATA_DIR/usr/share/doc/$PKG_NAME/BUILDINFO"
fi

# OpenWrt records file ownership, conffiles, and persistent service users under
# /lib/apk/packages. Match package-pack.mk so direct packages behave like
# packages produced by the OpenWrt buildroot.
(
    cd "$DATA_DIR"
    find . \( -type f -o -type l \)
) | sed 's#^\./#/#' | sort > "$DATA_DIR/lib/apk/packages/$PKG_NAME.list"

printf 'aria2=6800:aria2=6800\n' > "$DATA_DIR/lib/apk/packages/$PKG_NAME.rusers"
printf '/etc/config/aria2-next\n' > "$DATA_DIR/lib/apk/packages/$PKG_NAME.conffiles"

CONFIG_SHA256="$(sha256sum "$DATA_DIR/etc/config/aria2-next" | awk '{print $1}')"
printf '/etc/config/aria2-next %s\n' "$CONFIG_SHA256" \
    > "$DATA_DIR/lib/apk/packages/$PKG_NAME.conffiles_static"

MKPKG_ARGS=(
    mkpkg
    --info "name:$PKG_NAME"
    --info "version:$PKG_VERSION"
    --info "description:aria2-next download utility (statically linked)"
    --info "arch:$PKG_ARCH"
    --info "license:GPL-2.0-or-later"
    --info "origin:$PKG_NAME"
    --info "url:https://github.com/AnInsomniacy/aria2-next"
    --info "maintainer:openwrt-aria2-next"
    --info "depends:"
    --files "$DATA_DIR"
    --output "$APK_FILE"
)

if [ -f "$PACKAGE_FILES/postinst" ]; then
    MKPKG_ARGS+=(--script "post-install:$PACKAGE_FILES/postinst")
    MKPKG_ARGS+=(--script "post-upgrade:$PACKAGE_FILES/postinst")
fi
if [ -f "$PACKAGE_FILES/prerm" ]; then
    MKPKG_ARGS+=(--script "pre-deinstall:$PACKAGE_FILES/prerm")
fi

# Normalize staged mtimes. BUILDINFO still captures the real build timestamp,
# while the APK container itself stays reproducible for identical inputs.
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"
case "$SOURCE_DATE_EPOCH" in
    *[!0-9]*) log_fatal "SOURCE_DATE_EPOCH must be a non-negative integer" ;;
esac
find "$DATA_DIR" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +

"$APK_TOOL_PATH" "${MKPKG_ARGS[@]}"
"$APK_TOOL_PATH" verify --allow-untrusted "$APK_FILE"

log_info "Built and verified APK v3: $APK_FILE"
echo "APK_FILE=$APK_FILE"
