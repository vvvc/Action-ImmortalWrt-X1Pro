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

# 1b. Fix bandix Makefile: 将 zoneinfo-all 改为 zoneinfo-asia（.config 已启用）
BANDIX_MK="$OPENWRT/package/openwrt-bandix/openwrt-bandix/Makefile"
if [ -f "$BANDIX_MK" ]; then
  if grep -q 'zoneinfo-all' "$BANDIX_MK"; then
    sed -i 's/zoneinfo-all/zoneinfo-asia/g' "$BANDIX_MK"
    echo "  → bandix Makefile: zoneinfo-all → zoneinfo-asia"
  else
    echo "  → bandix Makefile: already updated or no zoneinfo dep"
  fi
fi



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
