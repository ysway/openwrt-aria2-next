#!/bin/bash
# Collect build artifacts and generate BUILDINFO for a single target.
#
# Usage:
#   bash collect_artifacts.sh <platform> <binary_path> <output_dir>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/versions.sh"

PLATFORM="${1:?Usage: collect_artifacts.sh <platform> <binary_path> <output_dir>}"
BINARY="${2:?Binary path required}"
OUTPUT_DIR="${3:?Output directory required}"

ensure_dir "$OUTPUT_DIR"

ARIA2_VERSION="$(get_aria2_version)"
SUBMODULE_COMMIT="$(get_submodule_commit)"
SDK_VERSION="${OPENWRT_SDK_VERSION:-unknown}"
BUILD_VERSION="${BUILD_VERSION:-dev}"
FULLY_STATIC="${FULLY_STATIC:-unknown}"
UPX_APPLIED="${UPX_APPLIED:-no}"

# Copy binary
cp "$BINARY" "$OUTPUT_DIR/$BINARY_NAME"

# Generate BUILDINFO
cat > "$OUTPUT_DIR/BUILDINFO" <<EOF
project_build_version: $BUILD_VERSION
openwrt_target: $PLATFORM
sdk_version: $SDK_VERSION
submodule_commit: $SUBMODULE_COMMIT
aria2_version: $ARIA2_VERSION
expat_version: $EXPAT_VERSION
sqlite_version: $SQLITE_VERSION
cares_version: $CARES_VERSION
openssl_version: $OPENSSL_VERSION
zlib_version: $ZLIB_VERSION
libssh2_version: $LIBSSH2_VERSION
upx_applied: $UPX_APPLIED
fully_static: $FULLY_STATIC
build_date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

log_info "Artifacts collected in $OUTPUT_DIR"
log_info "BUILDINFO:"
cat "$OUTPUT_DIR/BUILDINFO"
