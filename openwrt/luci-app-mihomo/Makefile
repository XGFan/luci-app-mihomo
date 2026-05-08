include $(TOPDIR)/rules.mk

MIHOMO_PACKAGE_VERSION:=$(if $(MIHOMO_PACKAGE_VERSION),$(MIHOMO_PACKAGE_VERSION),0.0.0)
MIHOMO_PACKAGE_RELEASE:=$(if $(MIHOMO_PACKAGE_RELEASE),$(MIHOMO_PACKAGE_RELEASE),1)

PKG_NAME:=luci-app-mihomo
PKG_VERSION:=$(MIHOMO_PACKAGE_VERSION)
PKG_RELEASE:=$(MIHOMO_PACKAGE_RELEASE)

PKG_LICENSE:=GPL-3.0
PKG_MAINTAINER:=luci-app-mihomo project

PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-mihomo
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Mihomo LuCI shell entry
  PKGARCH:=$(PKGARCH)
  DEPENDS:=+luci-base +rpcd
endef

define Package/luci-app-mihomo/description
 Lightweight LuCI shell that wraps the mihomo external dashboard in an iframe.
 Reads UCI (/etc/config/mihomo) for controller_port and ui_path.
endef

define Build/Compile
endef

define Package/luci-app-mihomo/install
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/mihomo
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/mihomo/index.js $(1)/www/luci-static/resources/view/mihomo/index.js
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/mihomo.json $(1)/usr/share/luci/menu.d/mihomo.json
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-mihomo.json $(1)/usr/share/rpcd/acl.d/luci-app-mihomo.json
endef

define Package/luci-app-mihomo/postinst
#!/bin/sh

[ -n "$${IPKG_INSTROOT:-}" ] && exit 0

rm -f /tmp/luci-indexcache.*
rm -rf /tmp/luci-modulecache/
/etc/init.d/rpcd reload >/dev/null 2>&1 || true

exit 0
endef

define Package/luci-app-mihomo/postrm
#!/bin/sh

[ -n "$${IPKG_INSTROOT:-}" ] && exit 0

rm -f /tmp/luci-indexcache.*
rm -rf /tmp/luci-modulecache/
/etc/init.d/rpcd reload >/dev/null 2>&1 || true

exit 0
endef

$(eval $(call BuildPackage,luci-app-mihomo))
