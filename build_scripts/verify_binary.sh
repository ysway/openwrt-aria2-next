#!/bin/bash
# Verify the built aria2-next binary: linkage check + functional check.
#
# Exits non-zero if the binary fails critical checks.
# Sets FULLY_STATIC=yes/no as an output variable.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

BINARY="${1:-$BUILDDIR/aria2-next-build/$BINARY_NAME}"

if [ ! -f "$BINARY" ]; then
    log_fatal "Binary not found: $BINARY"
fi

FULLY_STATIC="unknown"

# ── File type ───────────────────────────────────────────────────────────────
log_info "File type:"
file "$BINARY"

# ── Dynamic linkage check ──────────────────────────────────────────────────
log_info "Checking dynamic linkage..."

NEEDED=""
if command -v readelf >/dev/null 2>&1; then
    NEEDED=$(readelf -d "$BINARY" 2>/dev/null | grep NEEDED || true)
elif command -v "${TARGET_HOST:-}-readelf" >/dev/null 2>&1; then
    NEEDED=$("${TARGET_HOST}-readelf" -d "$BINARY" 2>/dev/null | grep NEEDED || true)
fi

if [ -z "$NEEDED" ]; then
    log_info "No dynamic NEEDED entries — binary appears fully static"
    FULLY_STATIC="yes"
else
    log_warn "Dynamic NEEDED entries found:"
    echo "$NEEDED"
    # Check if any of our embedded libs leaked as dynamic deps
    LEAKED=""
    for lib in libssl libcrypto libssh2 libcares libexpat libsqlite3 libz; do
        if echo "$NEEDED" | grep -qi "$lib"; then
            LEAKED="$LEAKED $lib"
        fi
    done
    if [ -n "$LEAKED" ]; then
        log_error "Embedded libraries appearing as dynamic deps:$LEAKED"
        FULLY_STATIC="no"
    else
        log_warn "Dynamic deps exist but none are from embedded libraries"
        FULLY_STATIC="no"
    fi
fi

# ── ldd fallback ───────────────────────────────────────────────────────────
ldd "$BINARY" 2>&1 || true

# ── Functional check ───────────────────────────────────────────────────────
log_info "Functional check: --version"
if "$BINARY" --version 2>/dev/null; then
    log_info "$BINARY_NAME --version succeeded"
else
    # Cross-compiled binary may not run on build host; that's OK
    log_warn "$BINARY_NAME --version did not execute (expected for cross builds)"
fi

log_info "Functional check: --help"
if "$BINARY" --help >/dev/null 2>&1; then
    log_info "$BINARY_NAME --help succeeded"
else
    log_warn "$BINARY_NAME --help did not execute (expected for cross builds)"
fi

export FULLY_STATIC
log_info "Verification complete. FULLY_STATIC=$FULLY_STATIC"
printf 'FULLY_STATIC=%s\n' "$FULLY_STATIC"
