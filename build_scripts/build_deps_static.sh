#!/bin/bash
# Build all static dependencies inside the OpenWrt SDK container.
#
# Expects:
#   - SDK toolchain on PATH (CC, CXX, AR, RANLIB set or discoverable)
#   - TARGET_HOST, TARGET_PROCESSOR, OPENSSL_TARGET, EXTRA_CFLAGS set
#     (via target-map.sh)
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

if [ -z "${TARGET_HOST:-}" ]; then
    log_fatal "TARGET_HOST is not set; source target-map.sh and call resolve_target first"
fi
TARGET_PROCESSOR="${TARGET_PROCESSOR:-${TARGET_HOST%%-*}}"

SRC_DIR="$SOURCE_CACHE_DIR"
VENDOR_DIR="$ARIA2_SRC/third_party"
ensure_dir "$SRC_DIR" "$PREFIX"

for vendored_dependency in nghttp2 curl libtorrent boost gpac ffmpeg; do
    if [ ! -d "$VENDOR_DIR/$vendored_dependency" ]; then
        log_fatal "Vendored dependency source is missing: $VENDOR_DIR/$vendored_dependency"
    fi
done

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
    -DCMAKE_SYSTEM_PROCESSOR="$TARGET_PROCESSOR"
    -DCMAKE_INSTALL_LIBDIR=lib
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
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
download_source "$ZLIB_URL" "$SRC_DIR/$ZLIB_ARCHIVE" "$ZLIB_SHA256"
download_source "$EXPAT_URL" "$SRC_DIR/$EXPAT_ARCHIVE" "$EXPAT_SHA256"
download_source "$SQLITE_URL" "$SRC_DIR/$SQLITE_ARCHIVE" "$SQLITE_SHA256"
download_source "$OPENSSL_URL" "$SRC_DIR/$OPENSSL_ARCHIVE" "$OPENSSL_SHA256"
download_source "$LIBSSH2_URL" "$SRC_DIR/$LIBSSH2_ARCHIVE" "$LIBSSH2_SHA256"

# ── zlib ────────────────────────────────────────────────────────────────────
log_info "Building zlib ${ZLIB_VERSION}"
cd "$BUILDDIR"
rm -rf "zlib-${ZLIB_VERSION}"
extract_source "$SRC_DIR/$ZLIB_ARCHIVE" "$BUILDDIR"
cd "zlib-${ZLIB_VERSION}"
CHOST="$TARGET_HOST" AR="$TARGET_AR" RANLIB="$TARGET_RANLIB" CFLAGS="$COMMON_CFLAGS" \
    ./configure --prefix="$PREFIX" --static
make -j"$NPROC" libz.a
make install

# ── FFmpeg ──────────────────────────────────────────────────────────────────
log_info "Building vendored FFmpeg ${FFMPEG_VERSION}"
cd "$BUILDDIR"
rm -rf build/ffmpeg-release
mkdir -p build/ffmpeg-release
cd build/ffmpeg-release
"$VENDOR_DIR/ffmpeg/configure" \
    --prefix="$PREFIX" \
    --cc="${TARGET_HOST}-gcc" \
    --cxx="${TARGET_HOST}-g++" \
    --ar="$TARGET_AR" \
    --ranlib="$TARGET_RANLIB" \
    --nm="$TARGET_NM" \
    --strip="${TARGET_HOST}-strip" \
    --enable-cross-compile \
    --target-os=linux \
    --arch="$TARGET_PROCESSOR" \
    --extra-cflags="$COMMON_CFLAGS" \
    --extra-ldflags="$COMMON_LINK_FLAGS $EXTRA_LIBS_STRING" \
    --enable-pic \
    --enable-static \
    --disable-shared \
    --disable-autodetect \
    --disable-everything \
    --disable-programs \
    --disable-doc \
    --disable-network \
    --disable-x86asm \
    --disable-version-tracking \
    --disable-avdevice \
    --disable-avfilter \
    --disable-swscale \
    --enable-avformat \
    --enable-avcodec \
    --enable-avutil \
    --enable-protocol=file \
    --enable-demuxer=mov,mpegts,aac,ac3,eac3,mp3,flac,ogg,matroska,webvtt,flv,avi,asf,mpegps,mpegvideo,srt,ass \
    --enable-muxer=mp4,matroska,webvtt \
    --enable-parser=aac,aac_latm,ac3,h264,hevc,av1,vp9,opus,vorbis,flac,mpegaudio \
    --enable-decoder=aac,aac_latm,ac3,eac3,mp3,flac,opus,vorbis \
    --enable-bsf=aac_adtstoasc,extract_extradata
make -j"$NPROC"
make install-libs install-headers

# ── GPAC ────────────────────────────────────────────────────────────────────
log_info "Building vendored GPAC ${GPAC_VERSION}"
cd "$BUILDDIR"
rm -rf build/gpac-release build/gpac-source
# GPAC's revision helper updates a generated header in its source tree. Build
# from a writable copy because upstream verification mounts the checkout
# read-only.
cp -a "$VENDOR_DIR/gpac" build/gpac-source
mkdir -p build/gpac-release
cd build/gpac-release
GPAC_SOURCE_DIR="$BUILDDIR/build/gpac-source"
GPAC_CPU="$TARGET_PROCESSOR"
GPAC_CFLAGS="$COMMON_CFLAGS -fPIC -DPIC"
case "$TARGET_PROCESSOR" in
    mips|mips64)
        GPAC_CPU=mips
        ;;
    mipsel|mips64el|riscv64|loongarch64)
        # GPAC treats "mips" as big-endian and has no native names for the
        # other little-endian OpenWrt targets. Its generic C path is portable.
        GPAC_CPU=unknown
        ;;
esac
GPAC_AR="$(basename "$TARGET_AR")"
GPAC_AR="${GPAC_AR#"${TARGET_HOST}-"}"
GPAC_RANLIB="$(basename "$TARGET_RANLIB")"
GPAC_RANLIB="${GPAC_RANLIB#"${TARGET_HOST}-"}"
GPAC_DISABLED_PACKAGES=(
    ssl opensvc openhevc platinum freetype jpeg openjpeg png mad a52 xvid
    faad ffmpeg freenect vorbis theora nghttp2 ngtcp2 nghttp3 oss dvb4linux
    alsa pulseaudio jack directfb hid lzma tinygl vtb ogg sdl caption
    mpeghdec libcaca curl
)
GPAC_PACKAGE_ARGS=()
for gpac_package in "${GPAC_DISABLED_PACKAGES[@]}"; do
    GPAC_PACKAGE_ARGS+=("--disable-$gpac_package")
done
CC=gcc \
CXX=g++ \
AR="$GPAC_AR" \
RANLIB="$GPAC_RANLIB" \
STRIP=strip \
"$GPAC_SOURCE_DIR/configure" \
    --prefix="$PREFIX" \
    --cross-prefix="${TARGET_HOST}-" \
    --target-os=linux \
    --cpu="$GPAC_CPU" \
    --extra-cflags="$GPAC_CFLAGS" \
    --extra-ldflags="$COMMON_LINK_FLAGS $EXTRA_LIBS_STRING" \
    --static-build \
    --disable-all \
    --disable-x11 \
    --disable-rmtws \
    --enable-dashin \
    --enable-parsers \
    --enable-vtt \
    --enable-ttxt \
    --enable-import \
    --enable-txtin \
    --enable-isoff \
    --enable-isoff-write \
    --enable-isoff-frag \
    --enable-threads \
    --enable-network \
    --enable-net-cap \
    --enable-log \
    --use-zlib="$PREFIX" \
    "${GPAC_PACKAGE_ARGS[@]}"

# GPAC's CPU table predates several OpenWrt 64-bit target names. Keep its
# generated ABI header accurate when the generic C path is selected.
case "$TARGET_PROCESSOR" in
    x86_64|aarch64|mips64|mips64el|riscv64|loongarch64)
        if ! grep -qx '#define GPAC_64_BITS' config.h; then
            sed -i '/^#endif.*_GF_CONFIG_H_/i #define GPAC_64_BITS' config.h
            grep -qx '#define GPAC_64_BITS' config.h || \
                log_fatal "Could not mark GPAC as a 64-bit build"
        fi
        ;;
esac

# GPAC enables SSE2 whenever the compiler accepts the flag, even when the SDK
# targets Pentium MMX/Pentium 4. Preserve the OpenWrt toolchain's CPU policy.
if [ "$TARGET_PROCESSOR" = "i486" ]; then
    sed -i 's/ -msse2//g' config.mak
    if grep -q -- '-msse2' config.mak; then
        log_fatal "Could not remove GPAC's unconditional SSE2 flag"
    fi
fi

case "$TARGET_PROCESSOR" in
    mips|mips64)
        grep -qx '#define GPAC_BIG_ENDIAN' config.h || \
            log_fatal "GPAC did not configure a big-endian MIPS build"
        ;;
    mipsel|mips64el)
        if grep -qx '#define GPAC_BIG_ENDIAN' config.h; then
            log_fatal "GPAC incorrectly configured little-endian MIPS as big-endian"
        fi
        ;;
esac

make -C src -j"$NPROC" lib
cmake \
    -DSOURCE="$GPAC_SOURCE_DIR" \
    -DBINARY="$BUILDDIR/build/gpac-release" \
    -DPREFIX="$PREFIX" \
    -P "$ARIA2_SRC/cmake/scripts/InstallGpac.cmake"

# ── expat ───────────────────────────────────────────────────────────────────
log_info "Building expat ${EXPAT_VERSION}"
cd "$BUILDDIR"
rm -rf "expat-${EXPAT_VERSION}"
extract_source "$SRC_DIR/$EXPAT_ARCHIVE" "$BUILDDIR"
cd "expat-${EXPAT_VERSION}"
CHOST="$TARGET_HOST" CC="${TARGET_HOST}-gcc" AR="$TARGET_AR" RANLIB="$TARGET_RANLIB" \
    CFLAGS="$COMMON_CFLAGS" LDFLAGS="$COMMON_LINK_FLAGS $EXTRA_LIBS_STRING" \
    ./configure --host="$TARGET_HOST" --prefix="$PREFIX" --disable-shared --enable-static \
    --without-tests --without-examples --without-xmlwf --without-docbook
make -j"$NPROC"
make install

# ── SQLite ──────────────────────────────────────────────────────────────────
log_info "Building SQLite ${SQLITE_VERSION}"
cd "$BUILDDIR"
rm -rf "sqlite-autoconf-${SQLITE_AUTOCONF_VERSION}"
extract_source "$SRC_DIR/$SQLITE_ARCHIVE" "$BUILDDIR"
cd "sqlite-autoconf-${SQLITE_AUTOCONF_VERSION}"
CHOST="$TARGET_HOST" CC="${TARGET_HOST}-gcc" AR="$TARGET_AR" RANLIB="$TARGET_RANLIB" \
    CFLAGS="$COMMON_CFLAGS" CPPFLAGS="-I$PREFIX/include" \
    LDFLAGS="$COMMON_LINK_FLAGS $EXTRA_LIBS_STRING" \
    ./configure --host="$TARGET_HOST" --prefix="$PREFIX" --disable-shared --enable-static \
    --disable-readline
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
    no-ssl3 no-dtls no-comp no-sctp no-srp
    --cross-compile-prefix="${TARGET_HOST}-"
    --prefix="$PREFIX"
    --libdir=lib
    -O2
    -ffunction-sections -fdata-sections -fno-asynchronous-unwind-tables -flto=auto
)
PATH="$OPENSSL_TOOL_WRAPPER_DIR:$PATH" AR=ar RANLIB=ranlib NM=nm \
./Configure "${openssl_configure_args[@]}"
if ! PATH="$OPENSSL_TOOL_WRAPPER_DIR:$PATH" make -j"$NPROC"; then
    log_warn "OpenSSL build failed; retrying once in case its generated Makefile was refreshed"
    PATH="$OPENSSL_TOOL_WRAPPER_DIR:$PATH" make -j"$NPROC"
fi
PATH="$OPENSSL_TOOL_WRAPPER_DIR:$PATH" make install_sw

# ── libssh2 ────────────────────────────────────────────────────────────────
log_info "Building libssh2 ${LIBSSH2_VERSION}"
cd "$BUILDDIR"
rm -rf "libssh2-${LIBSSH2_VERSION}" build/libssh2-release
extract_source "$SRC_DIR/$LIBSSH2_ARCHIVE" "$BUILDDIR"
cmake -S "libssh2-${LIBSSH2_VERSION}" -B build/libssh2-release \
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
cmake --build build/libssh2-release -j"$NPROC"
cmake --install build/libssh2-release

# ── nghttp2 ────────────────────────────────────────────────────────────────────
log_info "Building vendored nghttp2 ${NGHTTP2_VERSION}"
cd "$BUILDDIR"
rm -rf build/nghttp2-release
cmake -S "$VENDOR_DIR/nghttp2" -B build/nghttp2-release \
    "${COMMON_CMAKE_ARGS[@]}" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_MODULE_LINKER_FLAGS="$COMMON_LINK_FLAGS" \
    -DCMAKE_SHARED_LINKER_FLAGS="$COMMON_LINK_FLAGS" \
    -DENABLE_LIB_ONLY=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_STATIC_LIBS=ON \
    -DBUILD_TESTING=OFF \
    -DCMAKE_DISABLE_FIND_PACKAGE_OpenSSL=TRUE \
    -DCMAKE_DISABLE_FIND_PACKAGE_Libngtcp2=TRUE \
    -DCMAKE_DISABLE_FIND_PACKAGE_Libnghttp3=TRUE \
    -DCMAKE_DISABLE_FIND_PACKAGE_Systemd=TRUE \
    -DCMAKE_DISABLE_FIND_PACKAGE_Jansson=TRUE \
    -DCMAKE_DISABLE_FIND_PACKAGE_Libevent=TRUE \
    -DCMAKE_DISABLE_FIND_PACKAGE_LibXml2=TRUE \
    -DCMAKE_DISABLE_FIND_PACKAGE_Jemalloc=TRUE \
    -DCMAKE_C_FLAGS="$COMMON_CFLAGS" \
    -DCMAKE_CXX_FLAGS="$COMMON_CXXFLAGS" \
    -DCMAKE_EXE_LINKER_FLAGS="$COMMON_LINK_FLAGS"
cmake --build build/nghttp2-release -j"$NPROC"
cmake --install build/nghttp2-release

# ── curl ───────────────────────────────────────────────────────────────────────
log_info "Building vendored curl ${CURL_VERSION}"
cd "$BUILDDIR"
rm -rf build/curl-release
cmake -S "$VENDOR_DIR/curl" -B build/curl-release \
    "${COMMON_CMAKE_ARGS[@]}" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_MODULE_LINKER_FLAGS="$COMMON_LINK_FLAGS" \
    -DCMAKE_SHARED_LINKER_FLAGS="$COMMON_LINK_FLAGS" \
    -DBUILD_CURL_EXE=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_STATIC_LIBS=ON \
    -DBUILD_TESTING=OFF \
    -DCMAKE_DISABLE_FIND_PACKAGE_Perl=TRUE \
    -DCURL_DISABLE_INSTALL=OFF \
    -DCURL_USE_PKGCONFIG=OFF \
    -DCURL_USE_CMAKECONFIG=OFF \
    -DENABLE_ARES=OFF \
    -DENABLE_THREADED_RESOLVER=ON \
    -DCURL_USE_LIBSSH2=ON \
    -DLIBSSH2_USE_STATIC_LIBS=ON \
    -DLIBSSH2_INCLUDE_DIR="$PREFIX/include" \
    -DLIBSSH2_LIBRARY="$PREFIX/lib/libssh2.a" \
    -DUSE_NGHTTP2=ON \
    -DNGHTTP2_USE_STATIC_LIBS=ON \
    -DNGHTTP2_INCLUDE_DIR="$PREFIX/include" \
    -DNGHTTP2_LIBRARY="$PREFIX/lib/libnghttp2.a" \
    -DCURL_ZLIB=ON \
    -DZLIB_ROOT="$PREFIX" \
    -DZLIB_USE_STATIC_LIBS=ON \
    -DZLIB_INCLUDE_DIR="$PREFIX/include" \
    -DZLIB_LIBRARY="$PREFIX/lib/libz.a" \
    -DCURL_BROTLI=OFF \
    -DCURL_ZSTD=OFF \
    -DUSE_LIBIDN2=OFF \
    -DCURL_DISABLE_ALTSVC=ON \
    -DCURL_DISABLE_AWS=ON \
    -DCURL_DISABLE_DICT=ON \
    -DCURL_DISABLE_DOH=ON \
    -DCURL_DISABLE_FILE=ON \
    -DCURL_DISABLE_FTP=ON \
    -DCURL_DISABLE_GOPHER=ON \
    -DCURL_DISABLE_HSTS=ON \
    -DCURL_DISABLE_IMAP=ON \
    -DCURL_DISABLE_IPFS=ON \
    -DCURL_DISABLE_LDAP=ON \
    -DCURL_DISABLE_LDAPS=ON \
    -DCURL_DISABLE_MQTT=ON \
    -DCURL_DISABLE_NETRC=OFF \
    -DCURL_DISABLE_POP3=ON \
    -DCURL_DISABLE_RTSP=ON \
    -DCURL_DISABLE_SMTP=ON \
    -DCURL_DISABLE_TELNET=ON \
    -DCURL_DISABLE_TFTP=ON \
    -DCURL_DISABLE_WEBSOCKETS=ON \
    -DCURL_USE_LIBPSL=OFF \
    -DCURL_USE_GSSAPI=OFF \
    -DCURL_USE_OPENSSL=ON \
    -DOPENSSL_ROOT_DIR="$PREFIX" \
    -DOPENSSL_USE_STATIC_LIBS=ON \
    -DOPENSSL_INCLUDE_DIR="$PREFIX/include" \
    -DOPENSSL_CRYPTO_LIBRARY="$PREFIX/lib/libcrypto.a" \
    -DOPENSSL_SSL_LIBRARY="$PREFIX/lib/libssl.a" \
    -DCMAKE_C_FLAGS="$COMMON_CFLAGS" \
    -DCMAKE_EXE_LINKER_FLAGS="$COMMON_LINK_FLAGS"
cmake --build build/curl-release -j"$NPROC"
cmake --install build/curl-release

# ── libtorrent-rasterbar ──────────────────────────────────────────────────
log_info "Building vendored libtorrent-rasterbar ${LIBTORRENT_VERSION}"
cd "$BUILDDIR"
rm -rf build/libtorrent-rasterbar-release
cmake -S "$VENDOR_DIR/libtorrent" -B build/libtorrent-rasterbar-release \
    "${COMMON_CMAKE_ARGS[@]}" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_MODULE_LINKER_FLAGS="$COMMON_LINK_FLAGS" \
    -DCMAKE_SHARED_LINKER_FLAGS="$COMMON_LINK_FLAGS" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBoost_INCLUDE_DIR="$VENDOR_DIR/boost" \
    -DBoost_NO_BOOST_CMAKE=ON \
    -DOPENSSL_ROOT_DIR="$PREFIX" \
    -DOPENSSL_USE_STATIC_LIBS=ON \
    -DOPENSSL_INCLUDE_DIR="$PREFIX/include" \
    -DOPENSSL_CRYPTO_LIBRARY="$PREFIX/lib/libcrypto.a" \
    -DOPENSSL_SSL_LIBRARY="$PREFIX/lib/libssl.a" \
    -Dbuild_tests=OFF \
    -Dbuild_examples=OFF \
    -Dbuild_tools=OFF \
    -Dpython-bindings=OFF \
    -Ddeprecated-functions=OFF \
    -Dextensions=ON \
    -Dmutable-torrents=ON \
    -Dstreaming=ON \
    -Di2p=OFF \
    -Dwebtorrent=OFF \
    -Dlogging=OFF \
    -Dencryption=ON \
    -Ddht=ON \
    -DCMAKE_C_FLAGS="$COMMON_CFLAGS" \
    -DCMAKE_CXX_FLAGS="$COMMON_CXXFLAGS" \
    -DCMAKE_EXE_LINKER_FLAGS="$COMMON_LINK_FLAGS"
cmake --build build/libtorrent-rasterbar-release -j"$NPROC"
cmake --install build/libtorrent-rasterbar-release

log_info "All static dependencies built successfully in $PREFIX"
