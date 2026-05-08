include $(TOPDIR)/rules.mk

MIHOMO_PACKAGE_VERSION:=$(if $(MIHOMO_PACKAGE_VERSION),$(MIHOMO_PACKAGE_VERSION),0.0.0)
MIHOMO_PACKAGE_RELEASE:=$(if $(MIHOMO_PACKAGE_RELEASE),$(MIHOMO_PACKAGE_RELEASE),1)

PKG_NAME:=mihomo
PKG_VERSION:=$(MIHOMO_PACKAGE_VERSION)
PKG_RELEASE:=$(MIHOMO_PACKAGE_RELEASE)

PKG_LICENSE:=GPL-3.0
PKG_MAINTAINER:=luci-app-mihomo project

PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/mihomo
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Mihomo wrapper service (UCI + procd init.d)
  PKGARCH:=$(PKGARCH)
  DEPENDS:=+wget +gzip
endef

define Package/mihomo/description
 Wrapper for mihomo on OpenWrt: UCI shim + procd init script + auto-install helper
 (/usr/sbin/mihomo-install-binary) that downloads the official mihomo binary from
 https://github.com/MetaCubeX/mihomo/releases when the binary is missing.
 Existing binaries are left untouched. Geo data files are NOT bundled.
endef

define Build/Compile
endef

define Package/mihomo/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ../../files/etc/init.d/mihomo $(1)/etc/init.d/mihomo

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ../../files/etc/config/mihomo $(1)/etc/config/mihomo

	$(INSTALL_DIR) $(1)/etc/mihomo
	$(INSTALL_CONF) ../../files/etc/mihomo/config.yaml $(1)/etc/mihomo/config.yaml

	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ../../files/usr/sbin/mihomo-install-binary $(1)/usr/sbin/mihomo-install-binary
endef

define Package/mihomo/conffiles
/etc/config/mihomo
/etc/mihomo/config.yaml
endef

define Package/mihomo/postinst
#!/bin/sh
set -eu

[ -n "$${IPKG_INSTROOT:-}" ] && exit 0

initd="/etc/init.d/mihomo"

if [ -x "$${initd}" ]; then
  "$${initd}" enable >/dev/null 2>&1 || true
  # Restart is best-effort; init.d will auto-install binary if missing
  "$${initd}" restart >/dev/null 2>&1 || true
fi

exit 0
endef

define Package/mihomo/prerm
#!/bin/sh
set -eu

[ -n "$${IPKG_INSTROOT:-}" ] && exit 0

action="$${1:-}"
initd="/etc/init.d/mihomo"

if [ -x "$${initd}" ]; then
  "$${initd}" stop >/dev/null 2>&1 || true

  case "$${action}" in
    remove|purge|deconfigure)
      "$${initd}" disable >/dev/null 2>&1 || true
      ;;
  esac
fi

exit 0
endef

define Package/mihomo/postrm
#!/bin/sh
set -eu

[ -n "$${IPKG_INSTROOT:-}" ] && exit 0

action="$${1:-}"

case "$${action}" in
  remove|purge|deconfigure)
    rm -f /var/run/mihomo.pid /var/run/mihomo.yaml

    if [ ! -e /etc/mihomo/config.yaml ]; then
      rmdir /etc/mihomo >/dev/null 2>&1 || true
    fi
    ;;
esac

exit 0
endef

$(eval $(call BuildPackage,mihomo))
