# ZRAM LZ4KD 增强移植到 GKI 6.12（android16-6.12）

## 结论先行

Deemoxzj/GKI_KernelSU_SUSFS 仓库的 zram 增强 = **LZ4 1.10 NEON 加速 + 华为 LZ4KD/LZ4K 算法**，通过 `build.yml` 的「文件覆盖 + perl 正则改写 + patch」三步注入。移植到 6.12 的**唯一硬伤**是：SukiSU_patch 只提供 5.10/5.15/6.1/6.6 的补丁，而 **6.12 的 zram 子系统已重构为 backend（zcomp_ops）架构**，6.6 的 `lz4kd.patch` 有 3 个 hunk 打不上。

本包提供了 6.12 专用的 backend 适配层，把华为编解码器直接接到 6.12 的 `zcomp_ops` 上，绕过不兼容的旧 crypto/zcomp 补丁。

## 实证：6.6 补丁在 6.12 源码上的表现（patch --dry-run）

| 文件 | 结果 | 说明 |
|---|---|---|
| lib/Kconfig | ✅ 可打（offset -1） | 定义 LZ4K/LZ4KD COMPRESS/DECOMPRESS |
| lib/Makefile | ✅ 可打（offset -9） | 编译 lz4k/ lz4kd/ 库 |
| crypto/Kconfig | ✅ 可打（offset -33） | 定义 CRYPTO_LZ4K/LZ4KD |
| kernel/module/main.c | ✅ 可打（offset +424） | 模块黑名单处理（与算法无关） |
| crypto/Makefile | ⚠️ 仅行号偏移 | 已重生成 `08-crypto-makefile.patch` |
| drivers/block/zram/Kconfig | ❌ 架构变了 | 已重写为 `01~04` |
| drivers/block/zram/zcomp.c | ❌ backend 架构重写 | 已重写为 `06~07` |

## 本包内容

```
port612/
├── README-移植指南.md         本文件
├── zram_backends/
│   ├── backend_lz4kd.c/.h     核心：华为 LZ4KD 接到 6.12 zcomp_ops
│   └── backend_lz4k.c/.h      附加：oplus LZ4K backend（有额外 include 要求）
└── patches/
    ├── 01-zram-kconfig-backend.patch       新增 ZRAM_BACKEND_LZ4K/LZ4KD
    ├── 02-zram-kconfig-forcelzo.patch      force_lzo 条件纳入新 backend
    ├── 03-zram-kconfig-defcomp-choice.patch 默认压缩选项增加 lz4k/lz4kd
    ├── 04-zram-kconfig-defcomp-string.patch ZRAM_DEF_COMP 字符串映射
    ├── 05-zram-makefile.patch              zram.o 增加两个 backend 目标
    ├── 06-zcomp-include.patch              zcomp.c 增加头文件
    ├── 07-zcomp-backends.patch             backends[] 数组注册两个 backend
    ├── 08-crypto-makefile.patch            crypto 层编译 lz4k.o/lz4kd.o
    └── legacy_6.6_*.patch                  6.6 原补丁拆分（lib/crypto/module 部分可直接用）
```

**验证状态**：7 个 zram 补丁 + crypto/Makefile 补丁已在真实的 `android16-6.12` 源码副本上 `patch -p1` 依次真实应用，全部 rc=0，最终 Kconfig/Makefile/zcomp.c 内容核对无误。注意这是**补丁应用验证，不是编译验证**——我无法在此环境编译完整内核。

## 集成到仓库的具体做法

在 `build.yml` 的「配置 ZRAM LZ4 补丁栈」（原 L1183）里，`use_zram` 且 `kernel_version == 6.12` 时改用本流程：

```bash
# 1) 保留原有：本仓 LZ4 1.10 覆盖 + NEON 改写（这部分与内核版本无关，照旧）
rm -f lib/lz4/lz4_compress.c lib/lz4/lz4_decompress.c lib/lz4/lz4defs.h lib/lz4/lz4hc_compress.c
cp -r $ZZH_PATCHES/zram/lz4/* ./lib/lz4/
cp -r $ZZH_PATCHES/zram/include/linux/* ./include/linux/
bash $ZZH_PATCHES/zram/apply_lz4_neon.sh

# 2) 保留原有：华为 lz4k 库源码 + 头文件（提供编解码实现）
cp -r $SUKISU_PATCHES/other/zram/lz4k/include/linux/* ./include/linux/
cp -r $SUKISU_PATCHES/other/zram/lz4k/lib/* ./lib/
cp -r $SUKISU_PATCHES/other/zram/lz4k/crypto/* ./crypto/

# 3) 【6.12 专用】跳过 6.6 的 lz4kd.patch / lz4k_oplus.patch，改打适配补丁
if [ "$KERNEL_VER" = "6.12" ]; then
  # lib / crypto / module 部分沿用 6.6 原补丁（实测可打）
  patch -p1 < "$PORT/legacy_6.6_lib_Kconfig.patch"
  patch -p1 < "$PORT/legacy_6.6_lib_Makefile.patch"
  patch -p1 < "$PORT/legacy_6.6_crypto_Kconfig.patch"
  patch -p1 < "$PORT/legacy_6.6_kernel_module_main.c.patch"
  patch -p1 < "$PORT/08-crypto-makefile.patch"

  # zram 子系统用 6.12 backend 适配补丁
  for p in "$PORT"/0[1-7]-*.patch; do patch -p1 < "$p"; done

  # 拷贝 backend 源码进内核 zram 目录
  cp "$PORT/../zram_backends/backend_lz4kd.c" "$PORT/../zram_backends/backend_lz4kd.h" drivers/block/zram/
  # 如启用 lz4k backend，还需：
  #   cp backend_lz4k.c/.h drivers/block/zram/
  #   并在 drivers/block/zram/Makefile 加 ccflags-y += -I$(srctree)/lib/lz4k_oplus
else
  # 原有逻辑：cp lz4k_oplus + patch 6.6 补丁
  ...
fi
```

配置片段 `config/zram.config` 追加项需相应调整：6.12 用的是 `CONFIG_ZRAM_BACKEND_LZ4KD=y` + `CONFIG_ZRAM_DEF_COMP_LZ4KD=y`（不再是 `CONFIG_ZRAM_DEF_COMP_LZ4KD` 单独生效），`CONFIG_CRYPTO_LZ4KD=y` 仍需要以编译 crypto/lz4kd.o。

## 必须知道的坑与限制

1. **没有编译验证**：后端适配层是按 6.12 `zcomp_ops` 结构和华为编解码 API 签名写的，补丁应用已验证，但未做真实内核编译。首次构建请留意 `backend_lz4kd.c` 的编译报错。
2. **`lz4kd_encode_state_bytes_min()` 符号**：lib/lz4kd/Makefile 带 `-DLZ4K_DELTA`，该函数的非 delta 版被 `#if !defined(LZ4K_DELTA)` 排除；delta 版在 `lz4kd_encode_delta.c`。若链接报未定义，改 backend 里用固定 `PAGE_SIZE*2` 或直接调 delta 版函数。
3. **oplus lz4k backend**：`backend_lz4k.c` include 的 `lz4k.h` 在 `lib/lz4k_oplus/`，不在 `include/linux/`。默认算法是 lz4kd，可先不启用 lz4k backend；要启用需按文件内注释加 include 路径。
4. **NEON 改写脚本**：`apply_lz4_neon.sh` 用正则匹配 `crypto/lz4.c` 等文件里的 `LZ4_decompress_safe()` 调用。6.12 若写法不同，脚本会 exit 1（好事，不会静默漏打），需按实际代码调整正则。
5. **crypto 老 API 仍在**：已确认 6.12 保留 `coa_compress`/`crypto_comp_compress`/`CRYPTO_ALG_TYPE_COMPRESS`，华为 crypto/lz4kd.c 能编译。**不需要**改内核 crypto 核心。
6. **CONFIG_CRYPTO_DELTA 未定义**：6.12 无 `CRYPTO_ALG_EXT_PROP_DELTA`/`coa_compress_delta` 扩展，lz4kd.c 里的 `#ifdef CONFIG_CRYPTO_DELTA` 分支会被跳过，走普通 compress 路径——这与 6.6 行为一致，不影响可用性（只是没有 delta 加速）。
7. **`lz4kds`/SDDC 不在此列**：那是 whitewhale 一加内核的原创实现，与 SukiSU/本仓的 LZ4KD 是两套东西，源码不在公开分支，无法移植。

## 建议的推进顺序

1. 先把 `backend_lz4kd.c` 和 7 个 zram 补丁合入仓库，只启用 lz4kd（不启 lz4k oplus）。
2. 用 `use_zram=true, kernel_version=6.12` 跑一次完整构建。
3. 若编译报错，优先看 `backend_lz4kd.c` 和 `lz4kd_encode_state_bytes_min` 符号问题。
4. 编过后刷机验证 `/sys/block/zram0/comp_algorithm` 里有 `lz4kd` 且能设为默认。
