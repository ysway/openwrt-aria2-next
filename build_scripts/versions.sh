#!/bin/bash
# Dependency versions — sourced from aria2-next upstream.
# Keep this file aligned with aria2-next/packaging/dependencies.env. This repo
# uses the OpenWrt/Linux subset of the maintained release baseline.

ZLIB_VERSION="1.3.2"
ZLIB_ARCHIVE="zlib-${ZLIB_VERSION}.tar.gz"
ZLIB_URL="https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/${ZLIB_ARCHIVE}"
ZLIB_SHA256="bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16"

LIBSSH2_VERSION="1.11.1"
LIBSSH2_ARCHIVE="libssh2-${LIBSSH2_VERSION}.tar.bz2"
LIBSSH2_URL="https://github.com/libssh2/libssh2/releases/download/libssh2-${LIBSSH2_VERSION}/${LIBSSH2_ARCHIVE}"
LIBSSH2_SHA256="8ddbd698403a2c3a9987df48f2940c6f6a9bddce28d37eb201938dd7755646f0"

CURL_VERSION="8.20.0"
CURL_ARCHIVE="curl-${CURL_VERSION}.tar.xz"
CURL_URL="https://curl.se/download/${CURL_ARCHIVE}"
CURL_SHA256="63fe2dc148ba0ceae89922ef838f7e5c946272c2e78b7c59fab4b79d3ce2b896"

BOOST_VERSION="1.91.0"
BOOST_VERSION_UNDERSCORE="1_91_0"
BOOST_ARCHIVE="boost_${BOOST_VERSION_UNDERSCORE}.tar.bz2"
BOOST_URL="https://archives.boost.io/release/${BOOST_VERSION}/source/${BOOST_ARCHIVE}"
BOOST_SHA256="de5e6b0e4913395c6bdfa90537febd9028ea4c0735d2cdb0cd9b45d5f51264f5"

LIBTORRENT_VERSION="2.0.12"
LIBTORRENT_ARCHIVE="libtorrent-rasterbar-${LIBTORRENT_VERSION}.tar.gz"
LIBTORRENT_URL="https://github.com/arvidn/libtorrent/releases/download/v${LIBTORRENT_VERSION}/${LIBTORRENT_ARCHIVE}"
LIBTORRENT_SHA256="25b898d02e02e43ee9a8ea5480c20007f129091b5754d0283f94e4d51d11a19e"

OPENSSL_VERSION="3.5.6"
OPENSSL_SERIES="3.5"
OPENSSL_ARCHIVE="openssl-${OPENSSL_VERSION}.tar.gz"
OPENSSL_URL="https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/${OPENSSL_ARCHIVE}"
OPENSSL_SHA256="deae7c80cba99c4b4f940ecadb3c3338b13cb77418409238e57d7f31f2a3b736"
