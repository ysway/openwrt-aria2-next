#!/bin/bash
# Entrypoint script for building aria2-next inside the OpenWrt SDK container.
#
# This script is executed via:
#   docker run --rm --user root \
#     -v "$(pwd)/repo:/work/repo:z" \
#     -v "$(pwd)/output:/work/output:z" \
#     -e OPENWRT_SDK_VERSION=... \
#     -e BUILD_VERSION=... \
#     ghcr.io/openwrt/sdk:<platform>-V<version> \
#     bash /work/repo/build_scripts/build_in_sdk.sh <platform>
#
# Expects:
#   /work/repo    - mounted repo with aria2-next submodule
#   /work/output  - mounted output directory for artifacts
#   /builder      - SDK_HOME (pre-existing in the SDK container image)

set -euo pipefail

PLATFORM="${1:?Usage: build_in_sdk.sh <platform>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

log_info "=== Building aria2-next for $PLATFORM ==="

if command -v git >/dev/null 2>&1; then
    git config --global --add safe.directory "$REPO_ROOT"
    git config --global --add safe.directory "$ARIA2_SRC"
fi

# ── Install host build tools ───────────────────────────────────────────────
log_info "Installing host build tools..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
    pkg-config curl file bzip2 xz-utils upx-ucl ca-certificates binutils \
    make perl python3 python3-pip

export PIP_DISABLE_PIP_VERSION_CHECK=1
python3 -m pip install \
    "${CMAKE_PIP_SPEC:-cmake>=3.25,<4}" \
    "${NINJA_PIP_SPEC:-ninja>=1.11}"

# ── Set up SDK toolchain ──────────────────────────────────────────────────
SDK_HOME="${SDK_HOME:-/builder}"
TOOLCHAIN_DIR=$(find "$SDK_HOME"/staging_dir -maxdepth 1 -name 'toolchain-*' -type d | head -1)
if [ -z "$TOOLCHAIN_DIR" ]; then
    log_fatal "Could not find SDK toolchain directory in $SDK_HOME/staging_dir/"
fi
export PATH="$TOOLCHAIN_DIR/bin:$PATH"
export STAGING_DIR="$SDK_HOME/staging_dir"
log_info "Toolchain: $TOOLCHAIN_DIR"

# ── Resolve target mapping ─────────────────────────────────────────────────
source "$SCRIPT_DIR/target-map.sh"
resolve_target "$PLATFORM"

# Auto-detect TARGET_HOST from SDK toolchain if possible
DETECTED_HOST=$(auto_detect_target_host "$TOOLCHAIN_DIR")
if [ -n "$DETECTED_HOST" ]; then
    if [ "$DETECTED_HOST" != "$TARGET_HOST" ]; then
        log_info "Auto-detected host triple: $DETECTED_HOST (overriding mapped: $TARGET_HOST)"
        TARGET_HOST="$DETECTED_HOST"
        export TARGET_HOST
    fi
fi
log_info "Target: HOST=$TARGET_HOST SSL=$OPENSSL_TARGET UPX_SKIP=$UPX_SKIP"

# ── Build static dependencies ──────────────────────────────────────────────
export PREFIX=/work/static-prefix
export BUILDDIR=/work/build
mkdir -p "$PREFIX" "$BUILDDIR"

log_info "Building static dependencies..."
bash "$SCRIPT_DIR/build_deps_static.sh"

# ── Build aria2-next ───────────────────────────────────────────────────────
log_info "Building aria2-next..."
BUILD_LOG="/tmp/aria2-next-build.log"
bash "$SCRIPT_DIR/build_static_aria2.sh" 2>&1 | tee "$BUILD_LOG"

BINARY=$(awk -F= '/^BINARY=/{value=$2} END{print value}' "$BUILD_LOG")
BINARY="${BINARY:-$BUILDDIR/aria2-next-build/$BINARY_NAME}"

# ── Verify binary ──────────────────────────────────────────────────────────
log_info "Verifying binary..."
VERIFY_LOG="/tmp/verify.log"
bash "$SCRIPT_DIR/verify_binary.sh" "$BINARY" 2>&1 | tee "$VERIFY_LOG"

FULLY_STATIC=$(awk -F= '/^FULLY_STATIC=/{value=$2} END{print value}' "$VERIFY_LOG")
export FULLY_STATIC="${FULLY_STATIC:-unknown}"

# ── Compress with UPX ──────────────────────────────────────────────────────
log_info "UPX compression..."
UPX_OUTPUT=$(bash "$SCRIPT_DIR/pack_with_upx.sh" "$BINARY" 2>&1)
echo "$UPX_OUTPUT"
UPX_APPLIED=$(printf '%s\n' "$UPX_OUTPUT" | awk -F= '/^UPX_APPLIED=/{value=$2} END{print value}')
export UPX_APPLIED="${UPX_APPLIED:-no}"

# ── Collect artifacts ──────────────────────────────────────────────────────
OUTPUT_DIR="/work/output/$PLATFORM"
mkdir -p "$OUTPUT_DIR"

export OPENWRT_SDK_VERSION="${OPENWRT_SDK_VERSION:-unknown}"
export BUILD_VERSION="${BUILD_VERSION:-dev}"

log_info "Collecting artifacts..."
bash "$SCRIPT_DIR/collect_artifacts.sh" "$PLATFORM" "$BINARY" "$OUTPUT_DIR"

# ── Build .ipk package ────────────────────────────────────────────────────
log_info "Building .ipk package..."
bash "$SCRIPT_DIR/build_ipk.sh" "$PLATFORM" "$BINARY" "$OUTPUT_DIR"

# ── Build .apk package when apk-tools 3 is available ─────────────────────
BUILD_APK_MODE="${BUILD_APK:-auto}"
if is_truthy "$BUILD_APK_MODE" ||
    { [ "$BUILD_APK_MODE" = "auto" ] && [ -x /builder/staging_dir/host/bin/apk ]; }; then
    log_info "Building .apk package..."
    bash "$SCRIPT_DIR/build_apk.sh" "$PLATFORM" "$BINARY" "$OUTPUT_DIR"
elif [ "$BUILD_APK_MODE" = "auto" ]; then
    log_info "Skipping .apk package: apk-tools 3 is not available in this SDK"
else
    log_info "Skipping .apk package: BUILD_APK=$BUILD_APK_MODE"
fi

log_info "=== Build complete for $PLATFORM ==="
ls -la "$OUTPUT_DIR/"
