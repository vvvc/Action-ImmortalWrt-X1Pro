#!/bin/bash
# DIY Part 1: X1 Pro device setup
# 原则：最小化侵入，只 patch 不改写上游文件
# 幂等设计：重复运行不会重复追加条目
# 参考 TR3000：第三方包直接 clone 到 package/，不用 feeds
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
OPENWRT="$WORKSPACE/openwrt"

echo "=== DIY Part 1: X1 Pro setup ==="

# 1. Clone third-party packages into package/ (参照 TR3000)
#    直接 clone 避免 feeds 分支/index 问题
#    注意：diy-part1.sh 已 clone 过这些包，这里跳过已存在的
mkdir -p "$OPENWRT/package"
clone_if_missing() {
  local url="$1" dest="$2"
  if [ ! -d "$dest" ]; then
    git clone --depth=1 "$url" "$dest"
    echo "  → cloned $(basename "$dest")"
  else
    echo "  → $(basename "$dest") already exists, skipping"
  fi
}
clone_if_missing https://github.com/eamonxg/luci-theme-aurora "$OPENWRT/package/luci-theme-aurora"
clone_if_missing https://github.com/eamonxg/luci-app-aurora-config "$OPENWRT/package/luci-app-aurora-config"
clone_if_missing https://github.com/timsaya/luci-app-bandix "$OPENWRT/package/luci-app-bandix"
clone_if_missing https://github.com/timsaya/openwrt-bandix "$OPENWRT/package/openwrt-bandix"
echo "  → aurora packages cloned"

# 1b. Fix bandix Makefile: 将 zoneinfo-all 替换为本地 x1pro-zoneinfo
BANDIX_MK="$OPENWRT/package/openwrt-bandix/openwrt-bandix/Makefile"
if [ -f "$BANDIX_MK" ]; then
  if grep -q 'zoneinfo-all' "$BANDIX_MK"; then
    sed -i 's/zoneinfo-all/x1pro-zoneinfo/g' "$BANDIX_MK"
    echo "  → bandix Makefile: zoneinfo-all → x1pro-zoneinfo"
  else
    echo "  → bandix Makefile: already using x1pro-zoneinfo or no zoneinfo dep"
  fi
fi

# 1c. 更新 .config: 旧配置的 zoneinfo-all → x1pro-zoneinfo（避免 kconfig 递归冲突）
if [ -f "$OPENWRT/.config" ]; then
  if grep -q 'CONFIG_PACKAGE_zoneinfo-all' "$OPENWRT/.config"; then
    sed -i 's/CONFIG_PACKAGE_zoneinfo-all=y/CONFIG_PACKAGE_x1pro-zoneinfo=y/' "$OPENWRT/.config"
    # 清理所有多余 zoneinfo 包（仅保留 asia + core + simple）
    for pkg in zoneinfo-africa zoneinfo-america zoneinfo-atlantic \
               zoneinfo-australia-nz zoneinfo-europe zoneinfo-indian \
               zoneinfo-pacific zoneinfo-poles; do
      sed -i "/CONFIG_PACKAGE_${pkg}=y/d" "$OPENWRT/.config"
    done
    echo "  → .config: zoneinfo-all → x1pro-zoneinfo, redundant zones removed"
  else
    echo "  → .config: already updated or no zoneinfo-all entry"
  fi
fi

# 1d. 创建 x1pro-zoneinfo 本地 metapackage（bandix 依赖它）
#    注意：命名需与 feeds 现有包区分，使用 x1pro- 前缀避免 kconfig 递归冲突
mkdir -p "$OPENWRT/package/x1pro-zoneinfo"
cat > "$OPENWRT/package/x1pro-zoneinfo/Makefile" << 'MAKEFILE_EOF'
include $(TOPDIR)/rules.mk

PKG_NAME:=x1pro-zoneinfo
PKG_VERSION:=1
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/x1pro-zoneinfo
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Asia timezones (metapackage for X1Pro)
  DEPENDS:= \
	+zoneinfo-core \
	+zoneinfo-simple \
	+zoneinfo-asia
  PKGARCH:=all
endef

define Package/x1pro-zoneinfo/description
  Meta-package that depends on Asia zoneinfo sets (X1Pro build)
endef

define Build/Configure
endef
define Build/Compile
endef

define Package/x1pro-zoneinfo/install
	$(INSTALL_DIR) $(1)
endef

$(eval $(call BuildPackage,x1pro-zoneinfo))
MAKEFILE_EOF
echo "  → x1pro-zoneinfo metapackage created"



# 6. [注释] Patch 02_network — MAC 设置修复
# 上游 mediatek_setup_macs() 已通过 mtd_get_mac_binary Factory 0xe000 读取 MAC，
# 不再需要本地注入。待编译验证后确认删除。
#NETWORK_FILE="$OPENWRT/target/linux/mediatek/filogic/base-files/etc/board.d/02_network"
#if [ -f "$NETWORK_FILE" ]; then
#  if ! grep -q "X1 Pro MAC fix" "$NETWORK_FILE"; then
#    awk -v marker='X1 Pro MAC fix' '
#/^exit 0$/ && !done {
#    print "# " marker ": read MAC from Factory partition offset 0xe000"
#    print "# eth0 (WAN) = base MAC, eth1 (LAN) = base MAC + 1"
#    print "case $board in"
#    print "oray,x1pro-v1|oray,x1pro-v1-ubootmod)"
#    print "\t_x1_wan=$(mtd_get_mac_binary Factory 0xe000)"
#    print "\tif [ -n \"$_x1_wan\" ]; then"
#    print "\t\tip link set eth0 address \"$_x1_wan\" 2>/dev/null"
#    print "\t\tip link set eth1 address \"$(macaddr_add \"$_x1_wan\" 1)\" 2>/dev/null"
#    print "\tfi"
#    print "\t;;"
#    print "esac"
#    print ""
#    print "exit 0"
#    done=1
#    next
#}
#{ print }
#' "$NETWORK_FILE" > "${NETWORK_FILE}.tmp" && mv "${NETWORK_FILE}.tmp" "$NETWORK_FILE"
#    echo "  → 02_network MAC fix patched (inline awk)"
#  else
#    echo "  → 02_network MAC fix already present (skipping)"
#  fi
#fi

echo "=== DIY Part 1 done ==="
