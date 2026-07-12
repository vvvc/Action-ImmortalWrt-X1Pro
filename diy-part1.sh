#!/bin/bash
# DIY Part 1: X1 Pro device setup
# 原则：最小化侵入，只 patch 不改写上游文件
# 幂等设计：重复运行不会重复追加条目
# 说明：aurora 主题通过 git clone 引入（eamonxg 第三方包）
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
OPENWRT="$WORKSPACE/openwrt"

echo "=== DIY Part 1: X1 Pro setup ==="

mkdir -p "$OPENWRT/package"

# 1. Clone third-party packages (aurora theme + app)
git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora "$OPENWRT/package/luci-theme-aurora"
git clone --depth=1 https://github.com/eamonxg/luci-app-aurora-config "$OPENWRT/package/luci-app-aurora-config"
echo "  → Third-party packages (aurora) cloned"

# 2. Copy DTS files
DTS_DIR="$OPENWRT/target/linux/mediatek/files/arch/arm64/boot/dts/mediatek/"
mkdir -p "$DTS_DIR"

for f in mt7981b-oray-x1pro-v1.dtsi mt7981b-oray-x1pro-v1.dts mt7981b-oray-x1pro-v1-ubootmod.dts; do
  if [ -f "$WORKSPACE/$f" ]; then
    cp "$WORKSPACE/$f" "$DTS_DIR"
    echo "  → $f"
  fi
done

# 3. Patch filogic.mk
if [ -f "$WORKSPACE/filogic.mk" ]; then
  cp "$WORKSPACE/filogic.mk" "$OPENWRT/target/linux/mediatek/filogic.mk"
  echo "  → filogic.mk patched"
fi

# 4. Patch upstream 02_network — X1 Pro 接口定义（幂等）
#    X1 Pro: eth1=LAN, eth0=WAN（与 TR3000 相同）
NETWORK_FILE="$OPENWRT/target/linux/mediatek/filogic/base-files/etc/board.d/02_network"
if [ -f "$NETWORK_FILE" ]; then
  if ! grep -q "oray,x1pro-v1|\\\\" "$NETWORK_FILE"; then
    python3 -c '
import sys
f = sys.argv[1]
with open(f) as fh:
    content = fh.read()
old = "\tcudy,tr3000-v1-ubootmod|\\\n"
new = old + "\toray,x1pro-v1|\\\n\toray,x1pro-v1-ubootmod|\\\n"
content = content.replace(old, new, 1)
with open(f, "w") as fh:
    fh.write(content)
' "$NETWORK_FILE"
    echo "  → 02_network patched (X1 Pro interfaces added)"
  else
    echo "  → 02_network already has X1 Pro entries (skipping)"
  fi
else
  echo "  ⚠ 02_network not found at $NETWORK_FILE"
fi

# 5. Patch platform.sh — sysupgrade 支持（幂等）
PLATFORM_FILE="$OPENWRT/target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh"
if [ -f "$PLATFORM_FILE" ]; then
  if ! grep -q "oray,x1pro-v1-ubootmod|\\\\" "$PLATFORM_FILE"; then
    python3 -c '
import sys
f = sys.argv[1]
with open(f) as fh:
    content = fh.read()
old = "\tcudy,wbr3000uax-v1-ubootmod|\\\n"
new = old + "\toray,x1pro-v1-ubootmod|\\\n"
content = content.replace(old, new, 1)
with open(f, "w") as fh:
    fh.write(content)
' "$PLATFORM_FILE"
    echo "  → platform.sh patched"
  else
    echo "  → platform.sh already has X1 Pro entry (skipping)"
  fi
fi

# 6. Patch 02_network — MAC 地址修复（从 Factory 分区读取）
#    根据实际硬件数据，MAC 地址存储在 Factory 分区偏移 0xe000 处
#    eth0 (WAN): 偏移 0xe000, eth1 (LAN): 偏移 0xe000 + 1
if [ -f "$NETWORK_FILE" ]; then
  if ! grep -q "X1 Pro MAC fix" "$NETWORK_FILE"; then
    python3 - << 'PYEOF' "$NETWORK_FILE"
import sys
f = open(sys.argv[1])
content = f.read()
f.close()
old = 'exit 0'
new = """
# X1 Pro MAC fix: read MAC from Factory partition offset 0xe000
# eth0 (WAN) = base MAC, eth1 (LAN) = base MAC + 1
case $board in
oray,x1pro-v1|oray,x1pro-v1-ubootmod)
\t_x1_wan=$(mtd_get_mac_binary Factory 0xe000)
\tif [ -n "$_x1_wan" ]; then
\t\tip link set eth0 address "$_x1_wan" 2>/dev/null
\t\tip link set eth1 address "$(macaddr_add "$_x1_wan" 1)" 2>/dev/null
\tfi
\t;;
esac

exit 0"""
content = content.replace(old, new, 1)
with open(sys.argv[1], 'w') as fh:
    fh.write(content)
PYEOF
    echo "  → 02_network MAC fix patched (Factory 0xe000)"
  else
    echo "  → 02_network MAC fix already present (skipping)"
  fi
fi

echo "=== DIY Part 1 done ==="

# 7. 移除 MT7915 warp_proxy 代码（X1 Pro 使用 MT7976CN，不需要 MT7915）
#    原因：padavanonly 仓库缺少 mt7915_cr.h，导致 warp_proxy 编译失败
WARP_CHIPS="$OPENWRT/package/mtk/drivers/mt_wifi/src/mt_wifi/embedded/plug_in/warp_proxy/chips"
WARP_MAKE="$OPENWRT/package/mtk/drivers/mt_wifi/src/mt_wifi/embedded/plug_in/warp_proxy/Makefile"
if [ -d "$WARP_CHIPS" ]; then
    rm -f "$WARP_CHIPS/warp_wifi_mt7915.c"
    rm -f "$WARP_CHIPS/warp_wifi_mt7915.h"
    echo "  → Removed MT7915 warp_proxy source files"
fi
# 从 Makefile 中移除 MT7915 编译选项
if [ -f "$WARP_MAKE" ]; then
    sed -i '' -e '/CONFIG_CHIP_MT7915/,+2d' "$WARP_MAKE" 2>/dev/null || \
    sed -i '/CONFIG_CHIP_MT7915/,+2d' "$WARP_MAKE" 2>/dev/null || true
    echo "  → Removed MT7915 from warp_proxy Makefile"
fi
