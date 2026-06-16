#!/bin/bash
# Dependency versions — sourced from aria2-next upstream.
# Keep this file aligned with aria2-next/packaging/dependencies.env. This repo
# uses the OpenWrt/Linux subset of the maintained release baseline.

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

CARES_VERSION="1.34.5"
CARES_TAG="v1.34.5"
CARES_ARCHIVE="c-ares-1.34.5.tar.gz"
CARES_URL="https://github.com/c-ares/c-ares/releases/download/v1.34.5/c-ares-1.34.5.tar.gz"
CARES_SHA256="7d935790e9af081c25c495fd13c2cfcda4792983418e96358ef6e7320ee06346"

LIBSSH2_VERSION="1.11.1"
LIBSSH2_ARCHIVE="libssh2-1.11.1.tar.bz2"
LIBSSH2_URL="https://github.com/libssh2/libssh2/releases/download/libssh2-1.11.1/libssh2-1.11.1.tar.bz2"
LIBSSH2_SHA256="8ddbd698403a2c3a9987df48f2940c6f6a9bddce28d37eb201938dd7755646f0"

OPENSSL_VERSION="3.5.6"
OPENSSL_SERIES="3.5"
OPENSSL_ARCHIVE="openssl-3.5.6.tar.gz"
OPENSSL_URL="https://github.com/openssl/openssl/releases/download/openssl-3.5.6/openssl-3.5.6.tar.gz"
OPENSSL_SHA256="deae7c80cba99c4b4f940ecadb3c3338b13cb77418409238e57d7f31f2a3b736"
