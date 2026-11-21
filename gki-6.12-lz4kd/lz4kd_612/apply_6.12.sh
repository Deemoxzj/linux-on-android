#!/bin/bash
# =============================================================================
# apply_6.12.sh — 在 GKI 6.12 内核源码树中注入 LZ4KD zram 增强
# =============================================================================
# 由 build-lz4kd.yml 在内核源码 common/ 目录（KERNEL_ROOT/common）调用。
#
# 前置条件（由 build 工作流已完成）：
#   - 内核源码已 repo sync，当前目录 = <KERNEL_ROOT>/common
#   - SukiSU_patch 已 clone 到 $SUKISU_PATCHES
#   - 本脚本所在目录 = $LZ4KD_PATCH_ROOT（含 patches/ 与 backends/）
#
# 设计原则：只新增文件 + 用 patch 打 supplement，不改任何上游脚本逻辑。
# =============================================================================
set -euo pipefail

PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$PATCH_DIR/.." && pwd)"   # 仓库根目录
SUKISU_PATCHES="${SUKISU_PATCHES:?SUKISU_PATCHES 未设置}"
FAILED=0

echo "=== [lz4kd-6.12] 注入开始 ==="
echo "  补丁目录 : $PATCH_DIR"
echo "  SukiSU   : $SUKISU_PATCHES"
echo "  内核目录 : $PWD"

# ---------------------------------------------------------------------------
# 1) 保留原逻辑：本仓 LZ4 1.10 全量源码 + ARM64 NEON 加速
#    （这段与内核版本无关，等价于原 build.yml 的 ZRAM 补丁栈前半段）
# ---------------------------------------------------------------------------
echo "--- [1/5] LZ4 1.10 源码覆盖 + NEON 改写 ---"
rm -f lib/lz4/lz4_compress.c lib/lz4/lz4_decompress.c lib/lz4/lz4defs.h lib/lz4/lz4hc_compress.c
cp -r "$REPO_ROOT/zram/lz4/"* ./lib/lz4/ 2>/dev/null || {
  echo "::warning::本仓 zram/lz4 目录未找到，跳过 LZ4 1.10 覆盖（将用内核自带 LZ4）"
}
cp -r "$REPO_ROOT/zram/include/linux/"* ./include/linux/ 2>/dev/null || true
if [ -f "$REPO_ROOT/zram/apply_lz4_neon.sh" ]; then
  bash "$REPO_ROOT/zram/apply_lz4_neon.sh" || echo "::warning::NEON 改写未完全成功"
fi

# ---------------------------------------------------------------------------
# 2) 华为 LZ4KD 编解码库 + 头文件（提供底层实现，无版本差异，直接 cp）
# ---------------------------------------------------------------------------
echo "--- [2/5] 华为 LZ4KD 库源码 + crypto 适配层 ---"
cp -r "$SUKISU_PATCHES/other/zram/lz4k/include/linux/"* ./include/linux/
cp -r "$SUKISU_PATCHES/other/zram/lz4k/lib/"* ./lib/
# crypto/Makefile 补丁引用了 obj-$(CONFIG_CRYPTO_LZ4K/LZ4KD) += lz4k.o/lz4kd.o，
# 必须把对应的 C 源文件也拷进 crypto/，否则报 "No rule to make target 'crypto/lz4k.o'"
cp -r "$SUKISU_PATCHES/other/zram/lz4k/crypto/"* ./crypto/

# ---------------------------------------------------------------------------
# 3) 打 crypto/lib/module 补丁（6.6 原补丁，实测 6.12 可打）
# ---------------------------------------------------------------------------
echo "--- [3/5] crypto / lib / module 补丁 ---"
apply_patch() {
  local p="$1"
  if [ ! -f "$p" ]; then echo "::error::补丁不存在: $p"; FAILED=$((FAILED+1)); return 1; fi
  if patch -p1 --forward < "$p"; then
    echo "  OK: $(basename "$p")"
  else
    echo "::warning::补丁未应用（可能已打）: $(basename "$p")"
  fi
}
for p in \
  legacy_6.6_lib_Kconfig.patch \
  legacy_6.6_lib_Makefile.patch \
  legacy_6.6_crypto_Kconfig.patch \
  legacy_6.6_kernel_module_main.c.patch \
  08-crypto-makefile.patch; do
  apply_patch "$PATCH_DIR/patches/$p" || true
done

# ---------------------------------------------------------------------------
# 4) 打 6.12 zram backend 适配补丁（本包核心，已 dry-run 验证）
# ---------------------------------------------------------------------------
echo "--- [4/5] 6.12 zram backend 适配补丁 ---"
for p in "$PATCH_DIR"/patches/0[1-7]-*.patch; do
  apply_patch "$p" || true
done

# ---------------------------------------------------------------------------
# 5) 拷贝 backend 适配层源码到内核 zram 目录
# ---------------------------------------------------------------------------
echo "--- [5/5] 拷贝 backend_lz4kd 源码 ---"
cp "$PATCH_DIR/backends/backend_lz4kd.c" "$PATCH_DIR/backends/backend_lz4kd.h" ./drivers/block/zram/

# 校验关键结果，避免静默失败
echo "--- 结果校验 ---"
if ! grep -q 'backend_lz4kd' drivers/block/zram/Makefile; then
  echo "::error::backend_lz4kd 未进入 Makefile"; FAILED=$((FAILED+1))
fi
if ! grep -q '&backend_lz4kd' drivers/block/zram/zcomp.c; then
  echo "::error::backend_lz4kd 未注册到 zcomp.c"; FAILED=$((FAILED+1))
fi
if ! grep -q '^config LZ4KD_COMPRESS' lib/Kconfig; then
  echo "::error::LZ4KD_COMPRESS 未定义"; FAILED=$((FAILED+1))
fi

echo "=== [lz4kd-6.12] 注入完成，失败项: $FAILED ==="
exit $FAILED
