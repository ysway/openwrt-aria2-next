#!/bin/bash
# Dependency versions — sourced from aria2-next upstream.
# Keep in sync with aria2-next/packaging/dependencies.env, which is the
# authoritative baseline for maintained release packaging.

ZLIB_VERSION="1.3.2"
EXPAT_VERSION="2.8.1"
SQLITE_VERSION="3.53.1"
SQLITE_AUTOCONF_VERSION="3530100"
SQLITE_YEAR="2026"
CARES_VERSION="1.34.6"
LIBSSH2_VERSION="1.11.1"
OPENSSL_VERSION="3.5.6"

# aria2-next source is inside the submodule; version is extracted at build time
# from aria2-next/CMakeLists.txt.

# Download URLs
ZLIB_URL="https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.gz"
EXPAT_URL="https://github.com/libexpat/libexpat/releases/download/R_$(echo $EXPAT_VERSION | tr . _)/expat-${EXPAT_VERSION}.tar.bz2"
SQLITE_URL="https://www.sqlite.org/${SQLITE_YEAR}/sqlite-autoconf-${SQLITE_AUTOCONF_VERSION}.tar.gz"
CARES_URL="https://github.com/c-ares/c-ares/releases/download/v${CARES_VERSION}/c-ares-${CARES_VERSION}.tar.gz"
LIBSSH2_URL="https://github.com/libssh2/libssh2/releases/download/libssh2-${LIBSSH2_VERSION}/libssh2-${LIBSSH2_VERSION}.tar.bz2"
OPENSSL_URL="https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz"
