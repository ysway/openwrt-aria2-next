#!/bin/bash
# Common helper functions and variables for all build scripts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default static prefix inside SDK container
PREFIX="${PREFIX:-/work/static-prefix}"
BUILDDIR="${BUILDDIR:-/work/build}"
SOURCE_CACHE_DIR="${SOURCE_CACHE_DIR:-$BUILDDIR/src}"
UPSTREAM_SUBMODULE="${UPSTREAM_SUBMODULE:-aria2-next}"
BINARY_NAME="${BINARY_NAME:-aria2-next}"
PKG_BASE_NAME="${PKG_BASE_NAME:-aria2-next-static}"
PACKAGE_FILES_DIR="${PACKAGE_FILES_DIR:-$REPO_ROOT/package/$PKG_BASE_NAME/files}"
ARIA2_SRC="${REPO_ROOT}/${UPSTREAM_SUBMODULE}"
NPROC="${NPROC:-$(nproc 2>/dev/null || echo 4)}"

export PREFIX BUILDDIR SOURCE_CACHE_DIR UPSTREAM_SUBMODULE BINARY_NAME PKG_BASE_NAME PACKAGE_FILES_DIR ARIA2_SRC NPROC

log_info()  { echo "==> $*"; }
log_warn()  { echo "WARNING: $*" >&2; }
log_error() { echo "ERROR: $*" >&2; }
log_fatal() { log_error "$@"; exit 1; }

is_truthy() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

resolve_tool_command() {
    local preferred="${1:?preferred tool required}"
    local fallback="${2:-}"
    local resolved_path

    if command -v "$preferred" >/dev/null 2>&1; then
        resolved_path="$(command -v "$preferred")"
        printf '%s' "$resolved_path"
    elif [ -n "$fallback" ] && command -v "$fallback" >/dev/null 2>&1; then
        resolved_path="$(command -v "$fallback")"
        printf '%s' "$resolved_path"
    else
        printf '%s' "$preferred"
    fi
}

resolve_target_binutils() {
    if [ -z "${TARGET_HOST:-}" ]; then
        log_fatal "TARGET_HOST is not set; cannot resolve binutils"
    fi

    TARGET_AR="$(resolve_tool_command "${TARGET_HOST}-gcc-ar" "${TARGET_HOST}-ar")"
    TARGET_RANLIB="$(resolve_tool_command "${TARGET_HOST}-gcc-ranlib" "${TARGET_HOST}-ranlib")"
    TARGET_NM="$(resolve_tool_command "${TARGET_HOST}-gcc-nm" "${TARGET_HOST}-nm")"

    export TARGET_AR TARGET_RANLIB TARGET_NM
}

resolve_extra_libs() {
    local compiler="${1:?compiler required}"
    shift || true

    local item archive
    for item in "$@"; do
        case "$item" in
            -latomic)
                archive="$($compiler -print-file-name=libatomic.a 2>/dev/null || true)"
                if [ -n "$archive" ] && [ "$archive" != "libatomic.a" ] && [ -f "$archive" ]; then
                    printf '%s\n' "$archive"
                else
                    printf '%s\n' "$item"
                fi
                ;;
            *)
                printf '%s\n' "$item"
                ;;
        esac
    done
}

ensure_dir() {
    mkdir -p "$@"
}

download_source() {
    local url="$1" dest="$2" expected_sha256="${3:-}"
    local actual_sha256 temp_file

    if [ -f "$dest" ]; then
        if [ -z "$expected_sha256" ]; then
            log_info "Already downloaded: $dest"
            return 0
        fi

        actual_sha256=$(sha256sum "$dest" | awk '{print $1}')
        if [ "$actual_sha256" = "$expected_sha256" ]; then
            log_info "Using verified cached source: $dest"
            return 0
        fi

        log_warn "Cached source checksum mismatch; downloading a clean copy: $dest"
    fi

    ensure_dir "$(dirname "$dest")"
    temp_file="${dest}.part.$$"
    rm -f "$temp_file"

    log_info "Downloading $url"
    if ! curl --fail --location --show-error --silent \
        --retry 5 --retry-delay 2 --connect-timeout 15 \
        --output "$temp_file" "$url"; then
        rm -f "$temp_file"
        log_fatal "Failed to download source: $url"
    fi

    if [ -n "$expected_sha256" ]; then
        actual_sha256=$(sha256sum "$temp_file" | awk '{print $1}')
        if [ "$actual_sha256" != "$expected_sha256" ]; then
            rm -f "$temp_file"
            log_fatal "Checksum mismatch for $url (expected $expected_sha256, got $actual_sha256)"
        fi
    fi

    mv "$temp_file" "$dest"
}

extract_source() {
    local archive="$1" dest_dir="$2"
    ensure_dir "$dest_dir"
    case "$archive" in
        *.tar.gz)  tar xf "$archive" -C "$dest_dir" ;;
        *.tar.bz2) tar xf "$archive" -C "$dest_dir" ;;
        *.tar.xz)  tar xf "$archive" -C "$dest_dir" ;;
        *) log_fatal "Unknown archive format: $archive" ;;
    esac
}

get_aria2_version() {
    local ver
    if [ -f "$ARIA2_SRC/CMakeLists.txt" ]; then
        ver=$(sed -n 's/^[[:space:]]*VERSION[[:space:]]\+\([0-9][0-9.]*\).*/\1/p' "$ARIA2_SRC/CMakeLists.txt" | head -1)
    elif [ -f "$ARIA2_SRC/configure.ac" ]; then
        ver=$(grep '^AC_INIT' "$ARIA2_SRC/configure.ac" | sed -n 's/.*\[\([0-9][0-9.]*\)\].*/\1/p')
    else
        ver=""
    fi
    if [ -z "$ver" ]; then
        ver="unknown"
    fi
    echo "$ver"
}

get_submodule_commit() {
    git -C "$ARIA2_SRC" rev-parse HEAD 2>/dev/null || \
        git -C "$REPO_ROOT" rev-parse --verify "HEAD:$UPSTREAM_SUBMODULE" 2>/dev/null || \
        echo "unknown"
}
