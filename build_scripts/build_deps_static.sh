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
COMMON_CXXFLAGS="$COMMON_CFLAGS"
COMMON_LINK_FLAGS="-L$PREFIX/lib -Wl,--gc-sections -flto=auto"
EXTRA_LIBS_ARRAY=()
EXTRA_LIBS_STRING=""

if [ -n "${EXTRA_LIBS:-}" ]; then
    read -r -a extra_libs_raw <<< "$EXTRA_LIBS"
    mapfile -t EXTRA_LIBS_ARRAY < <(resolve_extra_libs "${TARGET_HOST}-gcc" "${extra_libs_raw[@]}")
    EXTRA_LIBS_STRING="${EXTRA_LIBS_ARRAY[*]}"
fi

resolve_target_binutils

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

COMMON_CMAKE_ARGS=(
    -G Ninja
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_SYSTEM_NAME=Linux
    -DCMAKE_C_COMPILER="${TARGET_HOST}-gcc"
    -DCMAKE_CXX_COMPILER="${TARGET_HOST}-g++"
    -DCMAKE_AR="$TARGET_AR"
    -DCMAKE_RANLIB="$TARGET_RANLIB"
    -DCMAKE_NM="$TARGET_NM"
    -DCMAKE_STRIP="${TARGET_HOST}-strip"
    -DCMAKE_FIND_ROOT_PATH="$CMAKE_FIND_ROOT_PATH"
    -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY
    -DCMAKE_PREFIX_PATH="$PREFIX"
    -DCMAKE_INCLUDE_PATH="$CMAKE_INCLUDE_PATH"
    -DCMAKE_LIBRARY_PATH="$CMAKE_LIBRARY_PATH"
    -DCMAKE_C_STANDARD_LIBRARIES="$EXTRA_LIBS_STRING"
    -DCMAKE_CXX_STANDARD_LIBRARIES="$EXTRA_LIBS_STRING"
)

# ── Download all sources ────────────────────────────────────────────────────
log_info "Downloading dependency sources..."
download_source "$ZLIB_URL" "$SRC_DIR/$ZLIB_ARCHIVE"
download_source "$OPENSSL_URL" "$SRC_DIR/$OPENSSL_ARCHIVE"
download_source "$LIBSSH2_URL" "$SRC_DIR/$LIBSSH2_ARCHIVE"
download_source "$CURL_URL" "$SRC_DIR/$CURL_ARCHIVE"
download_source "$BOOST_URL" "$SRC_DIR/$BOOST_ARCHIVE"
download_source "$SPDLOG_URL" "$SRC_DIR/$SPDLOG_ARCHIVE"
download_source "$LIBTORRENT_URL" "$SRC_DIR/$LIBTORRENT_ARCHIVE"

# ── zlib ────────────────────────────────────────────────────────────────────
log_info "Building zlib ${ZLIB_VERSION}"
cd "$BUILDDIR"
rm -rf "zlib-${ZLIB_VERSION}"
extract_source "$SRC_DIR/$ZLIB_ARCHIVE" "$BUILDDIR"
cd "zlib-${ZLIB_VERSION}"
CHOST="$TARGET_HOST" AR="$TARGET_AR" RANLIB="$TARGET_RANLIB" CFLAGS="$COMMON_CFLAGS" \
    ./configure --prefix="$PREFIX" --static
make -j"$NPROC"
make install

# ── OpenSSL ─────────────────────────────────────────────────────────────────
log_info "Building OpenSSL ${OPENSSL_VERSION}"
cd "$BUILDDIR"
rm -rf "openssl-${OPENSSL_VERSION}"
extract_source "$SRC_DIR/$OPENSSL_ARCHIVE" "$BUILDDIR"
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
rm -rf "libssh2-${LIBSSH2_VERSION}" build/libssh2-for-curl-release
extract_source "$SRC_DIR/$LIBSSH2_ARCHIVE" "$BUILDDIR"
cmake -S "libssh2-${LIBSSH2_VERSION}" -B build/libssh2-for-curl-release \
    "${COMMON_CMAKE_ARGS[@]}" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_MODULE_LINKER_FLAGS="$COMMON_LINK_FLAGS" \
    -DCMAKE_SHARED_LINKER_FLAGS="$COMMON_LINK_FLAGS" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_STATIC_LIBS=ON \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_TESTING=OFF \
    -DCRYPTO_BACKEND=OpenSSL \
    -DENABLE_ZLIB_COMPRESSION=ON \
    -DOPENSSL_USE_STATIC_LIBS=ON \
    -DOPENSSL_ROOT_DIR="$PREFIX" \
    -DOPENSSL_INCLUDE_DIR="$PREFIX/include" \
    -DOPENSSL_SSL_LIBRARY="$PREFIX/lib/libssl.a" \
    -DOPENSSL_CRYPTO_LIBRARY="$PREFIX/lib/libcrypto.a" \
    -DZLIB_USE_STATIC_LIBS=ON \
    -DZLIB_ROOT="$PREFIX" \
    -DZLIB_INCLUDE_DIR="$PREFIX/include" \
    -DZLIB_LIBRARY="$PREFIX/lib/libz.a" \
    -DCMAKE_C_FLAGS="$COMMON_CFLAGS" \
    -DCMAKE_EXE_LINKER_FLAGS="$COMMON_LINK_FLAGS"
cmake --build build/libssh2-for-curl-release -j"$NPROC"
cmake --install build/libssh2-for-curl-release

# ── curl ───────────────────────────────────────────────────────────────────
log_info "Building curl ${CURL_VERSION}"
cd "$BUILDDIR"
rm -rf "curl-${CURL_VERSION}" build/curl-release
extract_source "$SRC_DIR/$CURL_ARCHIVE" "$BUILDDIR"
cmake -S "curl-${CURL_VERSION}" -B build/curl-release \
    "${COMMON_CMAKE_ARGS[@]}" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_MODULE_LINKER_FLAGS="$COMMON_LINK_FLAGS" \
    -DCMAKE_SHARED_LINKER_FLAGS="$COMMON_LINK_FLAGS" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_STATIC_LIBS=ON \
    -DBUILD_CURL_EXE=OFF \
    -DBUILD_TESTING=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_LIBCURL_DOCS=OFF \
    -DBUILD_MISC_DOCS=OFF \
    -DCURL_USE_PKGCONFIG=OFF \
    -DCURL_USE_OPENSSL=ON \
    -DENABLE_THREADED_RESOLVER=ON \
    -DOPENSSL_USE_STATIC_LIBS=ON \
    -DOPENSSL_ROOT_DIR="$PREFIX" \
    -DOPENSSL_INCLUDE_DIR="$PREFIX/include" \
    -DOPENSSL_SSL_LIBRARY="$PREFIX/lib/libssl.a" \
    -DOPENSSL_CRYPTO_LIBRARY="$PREFIX/lib/libcrypto.a" \
    -DCURL_ZLIB=ON \
    -DZLIB_USE_STATIC_LIBS=ON \
    -DZLIB_ROOT="$PREFIX" \
    -DZLIB_INCLUDE_DIR="$PREFIX/include" \
    -DZLIB_LIBRARY="$PREFIX/lib/libz.a" \
    -DCURL_USE_LIBSSH2=ON \
    -DLibssh2_ROOT="$PREFIX" \
    -DUSE_NGHTTP2=OFF \
    -DUSE_NGTCP2=OFF \
    -DUSE_NGHTTP3=OFF \
    -DUSE_QUICHE=OFF \
    -DUSE_LIBIDN2=OFF \
    -DCURL_USE_LIBPSL=OFF \
    -DCURL_BROTLI=OFF \
    -DCURL_ZSTD=OFF \
    -DCURL_ENABLE_NTLM=OFF \
    -DCURL_ENABLE_SMB=OFF \
    -DCURL_DISABLE_AWS=ON \
    -DCURL_DISABLE_DOH=ON \
    -DCURL_DISABLE_FILE=ON \
    -DCURL_DISABLE_IPFS=ON \
    -DCURL_DISABLE_LDAP=ON \
    -DCURL_DISABLE_LDAPS=ON \
    -DCURL_DISABLE_DICT=ON \
    -DCURL_DISABLE_GOPHER=ON \
    -DCURL_DISABLE_IMAP=ON \
    -DCURL_DISABLE_MQTT=ON \
    -DCURL_DISABLE_POP3=ON \
    -DCURL_DISABLE_RTSP=ON \
    -DCURL_DISABLE_SMTP=ON \
    -DCURL_DISABLE_TELNET=ON \
    -DCURL_DISABLE_TFTP=ON \
    -DCURL_DISABLE_WEBSOCKETS=ON \
    -DCURL_CA_BUNDLE=auto \
    -DCURL_CA_PATH=auto \
    -DCURL_CA_FALLBACK=ON \
    -DCMAKE_C_FLAGS="$COMMON_CFLAGS" \
    -DCMAKE_EXE_LINKER_FLAGS="$COMMON_LINK_FLAGS"
cmake --build build/curl-release -j"$NPROC"
cmake --install build/curl-release

# ── Boost headers ──────────────────────────────────────────────────────────
log_info "Installing Boost headers ${BOOST_VERSION}"
cd "$BUILDDIR"
rm -rf "boost_${BOOST_VERSION_UNDERSCORE}"
extract_source "$SRC_DIR/$BOOST_ARCHIVE" "$BUILDDIR"
rm -rf "$PREFIX/include/boost"
cp -R "boost_${BOOST_VERSION_UNDERSCORE}/boost" "$PREFIX/include/"

# ── spdlog headers ───────────────────────────────────────────────────────────
log_info "Installing spdlog ${SPDLOG_VERSION}"
cd "$BUILDDIR"
rm -rf "spdlog-${SPDLOG_VERSION}"
extract_source "$SRC_DIR/$SPDLOG_ARCHIVE" "$BUILDDIR"
rm -rf "$PREFIX/include/spdlog"
cp -R "spdlog-${SPDLOG_VERSION}/include/spdlog" "$PREFIX/include/"

# ── libtorrent-rasterbar ───────────────────────────────────────────────────
log_info "Building libtorrent-rasterbar ${LIBTORRENT_VERSION}"
cd "$BUILDDIR"
rm -rf "libtorrent-rasterbar-${LIBTORRENT_VERSION}" build/libtorrent-rasterbar-release
extract_source "$SRC_DIR/$LIBTORRENT_ARCHIVE" "$BUILDDIR"
cmake -S "libtorrent-rasterbar-${LIBTORRENT_VERSION}" -B build/libtorrent-rasterbar-release \
    "${COMMON_CMAKE_ARGS[@]}" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DBUILD_SHARED_LIBS=OFF \
    -Dbuild_tests=OFF \
    -Dbuild_examples=OFF \
    -Dbuild_tools=OFF \
    -Dpython-bindings=OFF \
    -Dpython-egg-info=OFF \
    -Dgnutls=OFF \
    -Dencryption=ON \
    -Ddht=ON \
    -DOPENSSL_USE_STATIC_LIBS=ON \
    -DOPENSSL_ROOT_DIR="$PREFIX" \
    -DOPENSSL_INCLUDE_DIR="$PREFIX/include" \
    -DOPENSSL_SSL_LIBRARY="$PREFIX/lib/libssl.a" \
    -DOPENSSL_CRYPTO_LIBRARY="$PREFIX/lib/libcrypto.a" \
    -DBoost_NO_BOOST_CMAKE=ON \
    -DBoost_INCLUDE_DIR="$PREFIX/include" \
    -DCMAKE_C_FLAGS="$COMMON_CFLAGS" \
    -DCMAKE_CXX_FLAGS="$COMMON_CXXFLAGS" \
    -DCMAKE_EXE_LINKER_FLAGS="$COMMON_LINK_FLAGS"
cmake --build build/libtorrent-rasterbar-release -j"$NPROC"
cmake --install build/libtorrent-rasterbar-release

log_info "All static dependencies built successfully in $PREFIX"
