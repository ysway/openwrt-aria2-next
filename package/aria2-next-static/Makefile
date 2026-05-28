include $(TOPDIR)/rules.mk

PKG_NAME:=aria2-next-static
PKG_RELEASE:=1

# Version is determined at build time from the aria2-next submodule
PKG_VERSION:=$(shell sed -n 's/^[[:space:]]*VERSION[[:space:]]\+\([0-9][0-9.]*\).*/\1/p' $(CURDIR)/../../aria2-next/CMakeLists.txt 2>/dev/null | head -1)
ifeq ($(PKG_VERSION),)
  PKG_VERSION:=0.0.0
endif

PKG_MAINTAINER:=openwrt-aria2-next
PKG_LICENSE:=GPL-2.0-or-later
PKG_LICENSE_FILES:=COPYING
PKG_CPE_ID:=cpe:/a:aria2_project:aria2

# Mirrors the official net/aria2 Makefile flags so any in-tree rebuild
# benefits from the same size/optimization treatment.
PKG_BUILD_FLAGS:=gc-sections lto
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/aria2-next-static
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=File Transfer
  TITLE:=aria2-next download utility (static build)
  URL:=https://github.com/AnInsomniacy/aria2-next
  DEPENDS:=
  # Same uid/gid as the official net/aria2 package so file ownership
  # transfers cleanly between the two packages.
  USERID:=aria2=6800:aria2=6800
endef

define Package/aria2-next-static/description
  aria2-next is a maintained aria2-compatible multi-protocol download
  utility operated via command line. It supports HTTP/HTTPS, FTP, SFTP,
  ED2K, BitTorrent, and Metalink.

  This package ships a statically linked binary with libcurl,
  libtorrent-rasterbar, Boost headers, OpenSSL, libssh2, and zlib
  embedded. No external library dependencies are required at runtime.
endef

define Package/aria2-next-static/conffiles
/etc/config/aria2-next
endef

# The actual binary is pre-built by the CI pipeline; this Makefile is
# kept as a packaging reference and for in-tree (buildroot) reuse.
define Build/Compile
	@echo "aria2-next-static: binary is pre-built"
endef

define Package/aria2-next-static/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/aria2-next $(1)/usr/bin/aria2-next

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/aria2-next.init $(1)/etc/init.d/aria2-next

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/aria2-next.conf $(1)/etc/config/aria2-next
endef

$(eval $(call BuildPackage,aria2-next-static))
