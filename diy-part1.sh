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

# 6. Patch 02_network — MAC 设置修复（幂等）
#    内核 DSA 驱动通过 nvmem 读取 eth0/eth1 MAC 失败（返回全 FF），
#    导致 eth0/eth1 显示全 FF。用 bdinfo 读取的正确 MAC 覆盖。
#    wan_mac/lan_mac 在 mediatek_setup_macs 中已设置，退出前用 ip link 覆盖。
if [ -f "$NETWORK_FILE" ]; then
  if ! grep -q "X1 Pro MAC fix" "$NETWORK_FILE"; then
    python3 -c "
import sys
f = sys.argv[1]
with open(f) as fh:
    content = fh.read()
old = 'exit 0'
new = '''
# X1 Pro MAC fix: kernel DSA driver fails to read MAC via nvmem for eth0/eth1,
# resulting in all-Fs. Override with the correct MAC already read from bdinfo.
case $board in
oray,x1pro-v1|oray,x1pro-v1-ubootmod)
\tip link set eth0 address \"$wan_mac\" 2>/dev/null
\tip link set eth1 address \"$lan_mac\" 2>/dev/null
\t;;
esac

exit 0'''
content = content.replace(old, new, 1)
with open(f, 'w') as fh:
    fh.write(content)
" "$NETWORK_FILE"
    echo "  → 02_network MAC fix patched"
  else
    echo "  → 02_network MAC fix already present (skipping)"
  fi
fi

echo "=== DIY Part 1 done ==="
