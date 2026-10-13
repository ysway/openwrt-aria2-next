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
VERIFY_FAILED=0

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
    for lib in \
        libssl libcrypto libssh2 libexpat libsqlite3 libz \
        libcurl libnghttp2 libtorrent-rasterbar libgpac \
        libavformat libavcodec libswresample libavutil; do
        if echo "$NEEDED" | grep -qi "$lib"; then
            LEAKED="$LEAKED $lib"
        fi
    done
    if [ -n "$LEAKED" ]; then
        log_error "Embedded libraries appearing as dynamic deps:$LEAKED"
    else
        log_error "Dynamic dependencies found in an artifact promised to be fully static"
    fi
    FULLY_STATIC="no"
    VERIFY_FAILED=1
fi

# ── ldd fallback ───────────────────────────────────────────────────────────
ldd "$BINARY" 2>&1 || true

# ── Functional check ───────────────────────────────────────────────────────
NATIVE_TARGET=no
case "$(uname -m):${TARGET_PROCESSOR:-unknown}" in
    x86_64:x86_64|x86_64:i386|x86_64:i486|i?86:i?86|aarch64:aarch64|arm*:arm|riscv64:riscv64|loongarch64:loongarch64)
        NATIVE_TARGET=yes
        ;;
esac
BINARY_RUNS=no
log_info "Functional check: --version"
if "$BINARY" --no-conf --version; then
    BINARY_RUNS=yes
    log_info "$BINARY_NAME --version succeeded"
elif [ "$NATIVE_TARGET" = yes ]; then
    log_fatal "$BINARY_NAME --version failed on a native target"
else
    # Cross-compiled binary may not run on build host; that's OK
    log_warn "$BINARY_NAME --version did not execute (expected for cross builds)"
fi

log_info "Functional check: --help"
if "$BINARY" --no-conf --help >/dev/null 2>&1; then
    log_info "$BINARY_NAME --help succeeded"
elif [ "$BINARY_RUNS" = yes ]; then
    log_fatal "$BINARY_NAME --help failed on a runnable target"
else
    log_warn "$BINARY_NAME --help did not execute (expected for cross builds)"
fi

if [ "$BINARY_RUNS" = yes ]; then
    log_info "Checking native HTTP/TLS, DNS-over-HTTPS, RPC, and BitTorrent behavior..."
    python3 "$SCRIPT_DIR/test_binary_runtime.py" "$BINARY"
    ARIA2_TEST_BINARY="$BINARY" sh "$SCRIPT_DIR/test_aria2_init.sh"
else
    log_info "Native runtime checks require target hardware or emulation"
fi

export FULLY_STATIC
log_info "Verification complete. FULLY_STATIC=$FULLY_STATIC"
printf 'FULLY_STATIC=%s\n' "$FULLY_STATIC"

if [ "$VERIFY_FAILED" -ne 0 ]; then
    log_fatal "Static linkage verification failed"
fi
