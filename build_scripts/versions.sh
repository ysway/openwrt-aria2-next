#!/bin/bash
# Dependency versions — sourced from aria2-next upstream.
# Keep this file aligned with aria2-next/packaging/dependencies.env. This repo
# uses the OpenWrt/Linux subset of the maintained release baseline.

ZLIB_VERSION="1.3.2"
ZLIB_ARCHIVE="zlib-1.3.2.tar.gz"
ZLIB_URL="https://github.com/madler/zlib/releases/download/v1.3.2/zlib-1.3.2.tar.gz"
ZLIB_SHA256="bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16"

LIBSSH2_VERSION="1.11.1"
LIBSSH2_ARCHIVE="libssh2-1.11.1.tar.bz2"
LIBSSH2_URL="https://github.com/libssh2/libssh2/releases/download/libssh2-1.11.1/libssh2-1.11.1.tar.bz2"
LIBSSH2_SHA256="8ddbd698403a2c3a9987df48f2940c6f6a9bddce28d37eb201938dd7755646f0"

CURL_VERSION="8.20.0"
CURL_ARCHIVE="curl-8.20.0.tar.xz"
CURL_URL="https://curl.se/download/curl-8.20.0.tar.xz"
CURL_SHA256="63fe2dc148ba0ceae89922ef838f7e5c946272c2e78b7c59fab4b79d3ce2b896"

BOOST_VERSION="1.91.0"
BOOST_VERSION_UNDERSCORE="1_91_0"
BOOST_ARCHIVE="boost_1_91_0.tar.bz2"
BOOST_URL="https://archives.boost.io/release/1.91.0/source/boost_1_91_0.tar.bz2"
BOOST_SHA256="de5e6b0e4913395c6bdfa90537febd9028ea4c0735d2cdb0cd9b45d5f51264f5"

SPDLOG_VERSION="1.17.0"
SPDLOG_ARCHIVE="spdlog-1.17.0.tar.gz"
SPDLOG_URL="https://github.com/gabime/spdlog/archive/refs/tags/v1.17.0.tar.gz"
SPDLOG_SHA256="d8862955c6d74e5846b3f580b1605d2428b11d97a410d86e2fb13e857cd3a744"

LIBTORRENT_VERSION="2.0.12"
LIBTORRENT_ARCHIVE="libtorrent-rasterbar-2.0.12.tar.gz"
LIBTORRENT_URL="https://github.com/arvidn/libtorrent/releases/download/v2.0.12/libtorrent-rasterbar-2.0.12.tar.gz"
LIBTORRENT_SHA256="25b898d02e02e43ee9a8ea5480c20007f129091b5754d0283f94e4d51d11a19e"

OPENSSL_VERSION="3.5.6"
OPENSSL_SERIES="3.5"
OPENSSL_ARCHIVE="openssl-3.5.6.tar.gz"
OPENSSL_URL="https://github.com/openssl/openssl/releases/download/openssl-3.5.6/openssl-3.5.6.tar.gz"
OPENSSL_SHA256="deae7c80cba99c4b4f940ecadb3c3338b13cb77418409238e57d7f31f2a3b736"
