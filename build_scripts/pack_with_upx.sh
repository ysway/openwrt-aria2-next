#!/bin/bash
# Compress aria2-next with UPX if the target supports it.
#
# Uses the UPX_SKIP variable (set by target-map.sh) to decide whether to skip.
# Always keeps a backup; restores on failure.
#
# Usage:
#   bash pack_with_upx.sh /path/to/aria2-next

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

BINARY="${1:-$BUILDDIR/aria2-next-build/$BINARY_NAME}"

if [ ! -f "$BINARY" ]; then
    log_fatal "Binary not found: $BINARY"
fi

# Check skip list
if [ "${UPX_SKIP:-no}" = "yes" ]; then
    log_info "UPX skipped for this target (UPX_SKIP=yes)"
    echo "UPX_APPLIED=no"
    exit 0
fi

# Ensure UPX is available
if ! command -v upx >/dev/null 2>&1; then
    log_warn "UPX not found on PATH; skipping compression"
    echo "UPX_APPLIED=no"
    exit 0
fi

BACKUP="${BINARY}.uncompressed"
cp "$BINARY" "$BACKUP"

ORIGINAL_SIZE=$(stat -c%s "$BINARY" 2>/dev/null || stat -f%z "$BINARY")
log_info "Original size: $ORIGINAL_SIZE bytes"

# Attempt UPX compression
log_info "Running UPX on $BINARY"
if ! upx --best --lzma "$BINARY"; then
    log_warn "UPX compression failed; restoring original"
    mv "$BACKUP" "$BINARY"
    echo "UPX_APPLIED=no"
    exit 0
fi

PACKED_SIZE=$(stat -c%s "$BINARY" 2>/dev/null || stat -f%z "$BINARY")
log_info "Packed size: $PACKED_SIZE bytes (was $ORIGINAL_SIZE)"

# Integrity test
log_info "Running UPX integrity test"
if ! upx -t "$BINARY"; then
    log_warn "UPX integrity test failed; restoring original"
    mv "$BACKUP" "$BINARY"
    echo "UPX_APPLIED=no"
    exit 0
fi

# Functional test (may fail on cross builds — that's fine)
if "$BINARY" --version >/dev/null 2>&1; then
    log_info "Packed binary passes --version check"
else
    log_warn "Packed binary --version check failed or not runnable (cross build)"
    # For cross builds we trust the UPX integrity test
fi

log_info "UPX compression succeeded"
echo "UPX_APPLIED=yes"
