#!/bin/bash
# Build all static dependencies inside the OpenWrt SDK container.
#
# Expects:
#   - SDK toolchain on PATH (CC, CXX, AR, RANLIB set or discoverable)
#   - TARGET_HOST, OPENSSL_TARGET, EXTRA_CFLAGS set (via target-map.sh)
#   - PREFIX set (via common.sh)
#   - versions.sh sourced
#
# Usage:
#   source build_scripts/common.sh
#   source build_scripts/versions.sh
#   source build_scripts/target-map.sh
#   resolve_target "$PLATFORM"
#   bash build_scripts/build_deps_static.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/versions.sh"

SRC_DIR="$BUILDDIR/src"
ensure_dir "$SRC_DIR" "$PREFIX"

# Section-splitting lets the linker drop unused functions/data from static
# archives via --gc-sections. -fno-asynchronous-unwind-tables trims .eh_frame
# without affecting C++ exception handling (synchronous tables are kept).
# -flto=auto is paired with gcc-ar/gcc-ranlib when available so static
# archives keep the LTO plugin metadata intact across the build.
COMMON_CFLAGS="-O2 -ffunction-sections -fdata-sections -fno-asynchronous-unwind-tables -flto=auto ${EXTRA_CFLAGS:-}"
EXTRA_LIBS_ARRAY=()
EXTRA_LIBS_STRING=""

if [ -n "${EXTRA_LIBS:-}" ]; then
    read -r -a extra_libs_raw <<< "$EXTRA_LIBS"
    mapfile -t EXTRA_LIBS_ARRAY < <(resolve_extra_libs "${TARGET_HOST}-gcc" "${extra_libs_raw[@]}")
    EXTRA_LIBS_STRING="${EXTRA_LIBS_ARRAY[*]}"
fi

resolve_target_binutils

# ── Download all sources ────────────────────────────────────────────────────
log_info "Downloading dependency sources..."
download_source "$ZLIB_URL"    "$SRC_DIR/zlib-${ZLIB_VERSION}.tar.gz"
download_source "$EXPAT_URL"   "$SRC_DIR/expat-${EXPAT_VERSION}.tar.bz2"
download_source "$SQLITE_URL"  "$SRC_DIR/sqlite-autoconf-${SQLITE_AUTOCONF_VERSION}.tar.gz"
download_source "$CARES_URL"   "$SRC_DIR/c-ares-${CARES_VERSION}.tar.gz"
download_source "$LIBSSH2_URL" "$SRC_DIR/libssh2-${LIBSSH2_VERSION}.tar.bz2"
download_source "$OPENSSL_URL" "$SRC_DIR/openssl-${OPENSSL_VERSION}.tar.gz"

# ── zlib ────────────────────────────────────────────────────────────────────
log_info "Building zlib ${ZLIB_VERSION}"
cd "$BUILDDIR"
rm -rf "zlib-${ZLIB_VERSION}"
extract_source "$SRC_DIR/zlib-${ZLIB_VERSION}.tar.gz" "$BUILDDIR"
cd "zlib-${ZLIB_VERSION}"
CHOST="$TARGET_HOST" AR="$TARGET_AR" RANLIB="$TARGET_RANLIB" CFLAGS="$COMMON_CFLAGS" \
    ./configure --prefix="$PREFIX" --static
make -j"$NPROC"
make install

# ── expat ───────────────────────────────────────────────────────────────────
log_info "Building expat ${EXPAT_VERSION}"
cd "$BUILDDIR"
rm -rf "expat-${EXPAT_VERSION}"
extract_source "$SRC_DIR/expat-${EXPAT_VERSION}.tar.bz2" "$BUILDDIR"
cd "expat-${EXPAT_VERSION}"
AR="$TARGET_AR" RANLIB="$TARGET_RANLIB" NM="$TARGET_NM" \
./configure --host="$TARGET_HOST" --prefix="$PREFIX" \
    --disable-shared --enable-static \
    CFLAGS="$COMMON_CFLAGS"
make -j"$NPROC"
make install

# ── SQLite ──────────────────────────────────────────────────────────────────
log_info "Building SQLite ${SQLITE_VERSION}"
cd "$BUILDDIR"
rm -rf "sqlite-autoconf-${SQLITE_AUTOCONF_VERSION}"
extract_source "$SRC_DIR/sqlite-autoconf-${SQLITE_AUTOCONF_VERSION}.tar.gz" "$BUILDDIR"
cd "sqlite-autoconf-${SQLITE_AUTOCONF_VERSION}"
AR="$TARGET_AR" RANLIB="$TARGET_RANLIB" NM="$TARGET_NM" \
./configure --host="$TARGET_HOST" --prefix="$PREFIX" \
    --disable-shared --enable-static \
    CFLAGS="$COMMON_CFLAGS"
make -j"$NPROC"
make install

# ── c-ares ──────────────────────────────────────────────────────────────────
log_info "Building c-ares ${CARES_VERSION}"
cd "$BUILDDIR"
rm -rf "c-ares-${CARES_VERSION}"
extract_source "$SRC_DIR/c-ares-${CARES_VERSION}.tar.gz" "$BUILDDIR"
cd "c-ares-${CARES_VERSION}"
AR="$TARGET_AR" RANLIB="$TARGET_RANLIB" NM="$TARGET_NM" \
./configure --host="$TARGET_HOST" --prefix="$PREFIX" \
    --disable-shared --enable-static \
    CFLAGS="$COMMON_CFLAGS"
make -j"$NPROC"
make install

# ── OpenSSL ─────────────────────────────────────────────────────────────────
log_info "Building OpenSSL ${OPENSSL_VERSION}"
cd "$BUILDDIR"
rm -rf "openssl-${OPENSSL_VERSION}"
extract_source "$SRC_DIR/openssl-${OPENSSL_VERSION}.tar.gz" "$BUILDDIR"
cd "openssl-${OPENSSL_VERSION}"
OPENSSL_TOOL_WRAPPER_DIR="$BUILDDIR/openssl-tool-wrappers"
rm -rf "$OPENSSL_TOOL_WRAPPER_DIR"
mkdir -p "$OPENSSL_TOOL_WRAPPER_DIR"
for openssl_tool in ar ranlib nm; do
    case "$openssl_tool" in
        ar) tool_command="$TARGET_AR" ;;
        ranlib) tool_command="$TARGET_RANLIB" ;;
        nm) tool_command="$TARGET_NM" ;;
    esac

    tool_path="$(command -v "$tool_command")"
    cat > "$OPENSSL_TOOL_WRAPPER_DIR/${TARGET_HOST}-${openssl_tool}" <<EOF
#!/bin/sh
exec "$tool_path" "\$@"
EOF
    chmod 755 "$OPENSSL_TOOL_WRAPPER_DIR/${TARGET_HOST}-${openssl_tool}"
done
openssl_configure_args=(
    "$OPENSSL_TARGET"
    no-shared
    no-module
    no-apps
    no-tests
    # Keep trims to protocol/features aria2 disables or never exposes.
    # RC4 must stay enabled because aria2 uses OpenSSL's ARC4 for BitTorrent MSE.
    no-ssl3 no-dtls no-comp no-sctp no-srp
    --cross-compile-prefix="${TARGET_HOST}-"
    --prefix="$PREFIX"
    --libdir=lib
    -O2
    -ffunction-sections -fdata-sections -fno-asynchronous-unwind-tables -flto=auto
)
PATH="$OPENSSL_TOOL_WRAPPER_DIR:$PATH" AR=ar RANLIB=ranlib NM=nm \
./Configure "${openssl_configure_args[@]}"
PATH="$OPENSSL_TOOL_WRAPPER_DIR:$PATH" make -j"$NPROC"
PATH="$OPENSSL_TOOL_WRAPPER_DIR:$PATH" make install_sw

# ── libssh2 ────────────────────────────────────────────────────────────────
log_info "Building libssh2 ${LIBSSH2_VERSION}"
cd "$BUILDDIR"
rm -rf "libssh2-${LIBSSH2_VERSION}"
extract_source "$SRC_DIR/libssh2-${LIBSSH2_VERSION}.tar.bz2" "$BUILDDIR"
cd "libssh2-${LIBSSH2_VERSION}"
AR="$TARGET_AR" RANLIB="$TARGET_RANLIB" NM="$TARGET_NM" \
./configure --host="$TARGET_HOST" --prefix="$PREFIX" \
    --disable-shared --enable-static \
    --disable-tests --disable-examples-build \
    --with-crypto=openssl --with-libssl-prefix="$PREFIX" \
    CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib" \
    CFLAGS="$COMMON_CFLAGS" \
    LIBS="$EXTRA_LIBS_STRING" \
    PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
make -j"$NPROC"
make install

log_info "All static dependencies built successfully in $PREFIX"
