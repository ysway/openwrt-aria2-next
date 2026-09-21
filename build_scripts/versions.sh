#!/bin/bash
# Dependency versions align with the aria2-next upstream baseline. Download
# URLs and SHA-256 hashes are maintained here because upstream vendors its
# dependency sources and no longer publishes that metadata in dependencies.env.

# Version changes in this group require a reviewed archive, URL, and checksum.
DOWNLOADED_VERSION_VARS=(
    ZLIB_VERSION
    EXPAT_VERSION
    SQLITE_VERSION
    LIBSSH2_VERSION
    OPENSSL_VERSION
)

# These sources are fixed by the aria2-next gitlink, so sync-upstream may update
# their descriptive version labels without introducing a new download.
VENDORED_VERSION_VARS=(
    CURL_VERSION
    NGHTTP2_VERSION
    BOOST_VERSION
    LIBTORRENT_VERSION
    GPAC_VERSION
    FFMPEG_VERSION
    SPDLOG_VERSION
    WSLAY_VERSION
)

# These fields describe test or non-OpenWrt toolchains and are classified only
# so a newly introduced release dependency cannot pass unnoticed.
IGNORED_UPSTREAM_VERSION_VARS=(
    DOCTEST_VERSION
    ANDROID_NDK_VERSION
    LLVM_MINGW_VERSION
)

ZLIB_VERSION="1.3.2"
ZLIB_ARCHIVE="zlib-1.3.2.tar.gz"
ZLIB_URL="https://github.com/madler/zlib/releases/download/v1.3.2/zlib-1.3.2.tar.gz"
ZLIB_SHA256="bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16"

EXPAT_VERSION="2.8.1"
EXPAT_TAG="R_2_8_1"
EXPAT_ARCHIVE="expat-2.8.1.tar.bz2"
EXPAT_URL="https://github.com/libexpat/libexpat/releases/download/R_2_8_1/expat-2.8.1.tar.bz2"
EXPAT_SHA256="f5833dd2e1cd7739ec9182804a1a29c4f0cc7c2f26b633d3a2188b7766a88ecb"

SQLITE_AUTOCONF_VERSION="3530100"
SQLITE_VERSION="3.53.1"
SQLITE_YEAR="2026"
SQLITE_ARCHIVE="sqlite-autoconf-3530100.tar.gz"
SQLITE_URL="https://www.sqlite.org/2026/sqlite-autoconf-3530100.tar.gz"
SQLITE_SHA256="83e6b2020a034e9a7ad4a72feea59e1ad52f162e09cbd26735a3ffb98359fc4f"

LIBSSH2_VERSION="1.11.1"
LIBSSH2_ARCHIVE="libssh2-1.11.1.tar.bz2"
LIBSSH2_URL="https://github.com/libssh2/libssh2/releases/download/libssh2-1.11.1/libssh2-1.11.1.tar.bz2"
LIBSSH2_SHA256="8ddbd698403a2c3a9987df48f2940c6f6a9bddce28d37eb201938dd7755646f0"

CURL_VERSION="8.21.0"
NGHTTP2_VERSION="1.70.0"
BOOST_VERSION="1.91.0"
LIBTORRENT_VERSION="2.1.1"
GPAC_VERSION="26.07.0"
FFMPEG_VERSION="8.1.2"
SPDLOG_VERSION="1.17.0"
WSLAY_VERSION="1.1.1"

OPENSSL_VERSION="3.5.6"
OPENSSL_SERIES="3.5"
OPENSSL_ARCHIVE="openssl-3.5.6.tar.gz"
OPENSSL_URL="https://github.com/openssl/openssl/releases/download/openssl-3.5.6/openssl-3.5.6.tar.gz"
OPENSSL_SHA256="deae7c80cba99c4b4f940ecadb3c3338b13cb77418409238e57d7f31f2a3b736"
