#!/bin/bash
# Build aria2-next as a static binary using the pre-built static dependencies.
#
# Expects:
#   - SDK toolchain on PATH
#   - TARGET_HOST set
#   - PREFIX set and populated by build_deps_static.sh
#   - ARIA2_SRC pointing to the aria2-next submodule

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

if [ -z "${TARGET_HOST:-}" ]; then
    log_fatal "TARGET_HOST is not set; source target-map.sh and call resolve_target first"
fi

log_info "Building aria2-next from $ARIA2_SRC for $TARGET_HOST"

EXTRA_LIBS_ARRAY=()
EXTRA_LIBS_STRING=""
STANDARD_LIBS_ARRAY=()
STANDARD_LIBS_STRING=""

if [ -n "${EXTRA_LIBS:-}" ]; then
    read -r -a extra_libs_raw <<< "$EXTRA_LIBS"
    mapfile -t EXTRA_LIBS_ARRAY < <(resolve_extra_libs "${TARGET_HOST}-gcc" "${extra_libs_raw[@]}")
    EXTRA_LIBS_STRING="${EXTRA_LIBS_ARRAY[*]}"
fi

resolve_target_binutils

STANDARD_LIBS_ARRAY=("${EXTRA_LIBS_ARRAY[@]}")
for compiler_archive in libgcc_eh.a libgcc.a; do
    archive_path=$("${TARGET_HOST}-g++" -print-file-name="$compiler_archive" 2>/dev/null || true)
    if [ -n "$archive_path" ] && [ "$archive_path" != "$compiler_archive" ] && [ -f "$archive_path" ]; then
        STANDARD_LIBS_ARRAY+=("$archive_path")
    fi
done
STANDARD_LIBS_STRING="${STANDARD_LIBS_ARRAY[*]}"

BUILD_DIR="$BUILDDIR/aria2-next-build"
rm -rf "$BUILD_DIR"

COMMON_FLAGS="-O2 -ffunction-sections -fdata-sections -fno-asynchronous-unwind-tables -flto=auto ${EXTRA_CFLAGS:-}"
LINK_FLAGS="-L$PREFIX/lib -static -static-libgcc -static-libstdc++ -Wl,--gc-sections -flto=auto"

TARGET_LIBC_ARCHIVE=$("${TARGET_HOST}-gcc" -print-file-name=libc.a 2>/dev/null || true)
TARGET_LIB_DIR=""
TARGET_TOOLCHAIN_ROOT=""
TARGET_STAGING_ROOT=""
FIND_ROOT_PATHS=("$PREFIX")
LIBRARY_PATHS=("$PREFIX/lib")
INCLUDE_PATHS=("$PREFIX/include")

if [ -n "$TARGET_LIBC_ARCHIVE" ] && [ "$TARGET_LIBC_ARCHIVE" != "libc.a" ] && [ -f "$TARGET_LIBC_ARCHIVE" ]; then
    TARGET_LIB_DIR=$(dirname "$TARGET_LIBC_ARCHIVE")
    TARGET_TOOLCHAIN_ROOT=$(cd "$TARGET_LIB_DIR/.." && pwd)
    FIND_ROOT_PATHS+=("$TARGET_TOOLCHAIN_ROOT")
    LIBRARY_PATHS+=("$TARGET_LIB_DIR")
fi

if [ -n "${STAGING_DIR:-}" ]; then
    TARGET_STAGING_ROOT=$(find "$STAGING_DIR" -maxdepth 1 -name 'target-*' -type d | head -1)
    if [ -n "$TARGET_STAGING_ROOT" ]; then
        FIND_ROOT_PATHS+=("$TARGET_STAGING_ROOT")
        if [ -d "$TARGET_STAGING_ROOT/usr/lib" ]; then
            LIBRARY_PATHS+=("$TARGET_STAGING_ROOT/usr/lib")
        fi
        if [ -d "$TARGET_STAGING_ROOT/usr/include" ]; then
            INCLUDE_PATHS+=("$TARGET_STAGING_ROOT/usr/include")
        fi
    fi
fi

CMAKE_FIND_ROOT_PATH=$(IFS=';'; echo "${FIND_ROOT_PATHS[*]}")
CMAKE_LIBRARY_PATH=$(IFS=';'; echo "${LIBRARY_PATHS[*]}")
CMAKE_INCLUDE_PATH=$(IFS=';'; echo "${INCLUDE_PATHS[*]}")

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
unset PKG_CONFIG_SYSROOT_DIR

cmake -S "$ARIA2_SRC" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_C_COMPILER="${TARGET_HOST}-gcc" \
    -DCMAKE_CXX_COMPILER="${TARGET_HOST}-g++" \
    -DCMAKE_AR="$TARGET_AR" \
    -DCMAKE_RANLIB="$TARGET_RANLIB" \
    -DCMAKE_NM="$TARGET_NM" \
    -DCMAKE_STRIP="${TARGET_HOST}-strip" \
    -DCMAKE_FIND_ROOT_PATH="$CMAKE_FIND_ROOT_PATH" \
    -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DCMAKE_INCLUDE_PATH="$CMAKE_INCLUDE_PATH" \
    -DCMAKE_LIBRARY_PATH="$CMAKE_LIBRARY_PATH" \
    -DCMAKE_C_FLAGS="$COMMON_FLAGS" \
    -DCMAKE_CXX_FLAGS="$COMMON_FLAGS" \
    -DCMAKE_EXE_LINKER_FLAGS="$LINK_FLAGS" \
    -DCMAKE_C_STANDARD_LIBRARIES="$EXTRA_LIBS_STRING" \
    -DCMAKE_CXX_STANDARD_LIBRARIES="$STANDARD_LIBS_STRING" \
    -DARIA2_ENABLE_STATIC=ON \
    -DARIA2_RELEASE_SIZE_OPTIMIZED=ON \
    -DARIA2_RELEASE_LTO=ON \
    -DARIA2_ENABLE_SSL=ON \
    -DARIA2_ENABLE_BITTORRENT=ON \
    -DARIA2_ENABLE_WEBSOCKET=ON \
    -DARIA2_WITH_ZLIB=ON \
    -DARIA2_WITH_TCMALLOC=OFF \
    -DARIA2_WITH_JEMALLOC=OFF \
    -DBoost_NO_BOOST_CMAKE=ON \
    -DBoost_INCLUDE_DIR="$PREFIX/include" \
    -DARIA2_BASH_COMPLETION_DIR=share/bash-completion/completions

cmake --build "$BUILD_DIR" -j"$NPROC"

# Strip the binary using the cross-strip from the toolchain
"${TARGET_HOST}-strip" "$BUILD_DIR/$BINARY_NAME" 2>/dev/null || strip "$BUILD_DIR/$BINARY_NAME" 2>/dev/null || true

log_info "$BINARY_NAME built: $(file "$BUILD_DIR/$BINARY_NAME")"
printf 'BINARY=%s\n' "$BUILD_DIR/$BINARY_NAME"
