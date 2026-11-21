# GKI 6.12 ZRAM LZ4KD 增强移植备份

> 本目录是 `Deemoxzj/GKI_KernelSU_SUSFS` 仓库 6.12 内核 ZRAM LZ4KD 增强方案的**完整备份**。
> 目的是：即使主仓库被上游覆盖或误删，也能从这里完整恢复。

## 状态：✅ 已实机验证成功并开机

- 验证运行：`https://github.com/Deemoxzj/GKI_KernelSU_SUSFS/actions/runs/44886591167`（conclusion: success）
- 用户反馈：**已成功开机**。
- 验证配置：Android 16 / 内核 6.12.69 / BakaSU / 禁用 SUSFS / droidspaces=on / ZRAM(LZ4KD) + BBG + Re-Kernel + NoMount + 网络增强 + NTSync 全开。
- 来源基准：主仓库 `dev` 分支 commit `4cbb812d13906bf8313d35b3f5738752ce378682`（含全部 4 轮编译修复）。

## 这是什么

GKI 6.12 的 zram 子系统已从旧的字符串数组重构为 `zcomp_ops` backend 架构，SukiSU_patch 提供的 5.10~6.6 `lz4kd.patch` 无法直接套用（zram Kconfig 与 zcomp.c 两个 hunk 失败）。本方案用一层 `backend_lz4kd` 适配层，把华为 LZ4KD 编解码器直接接到 6.12 的 `zcomp_ops` 上，绕过不兼容的旧补丁。

注意：这是 **LZ4KD**（华为算法），不是 whitewhale 一加内核那个闭源的 **LZ4KDS/SDDC**（跨页去重），两者是不同东西。

## 目录内容

```
gki-6.12-lz4kd/
├── README.md                       本说明
├── 部署说明.md                     零侵入集成 + 同步上游的完整操作手册
├── workflows/
│   ├── kernel-a16-6-12-lz4kd.yml   入口工作流（带 Run 按钮与参数）
│   └── build-lz4kd.yml             定制 build（复制自主仓库 build.yml，仅改 zram 步骤）
└── lz4kd_612/
    ├── README.md                   技术说明与风险
    ├── apply_6.12.sh               补丁注入脚本（含 4 轮修复后的最终版）
    ├── backends/
    │   ├── backend_lz4kd.c/.h      zcomp_ops backend 适配层
    ├── patches/
    │   ├── 01~08-*.patch           6.12 专用 zram/crypto 适配补丁
    │   └── legacy_6.6_*.patch      从 6.6 原补丁拆出、6.12 仍可复用的部分
    └── .gitattributes              强制脚本/补丁 LF（防 CRLF 破坏）
```

## 恢复方法

若主仓库 `GKI_KernelSU_SUSFS` 的 LZ4KD 相关文件丢失，从本目录恢复：

```bash
# 在主仓库根目录执行
mkdir -p lz4kd_612 .github/workflows
cp -r <本目录>/lz4kd_612/. ./lz4kd_612/
cp <本目录>/workflows/*.yml .github/workflows/
git add lz4kd_612 .github/workflows/build-lz4kd.yml .github/workflows/kernel-a16-6-12-lz4kd.yml
git commit -m "restore: LZ4KD 6.12 方案（从 linux-on-android 备份恢复）"
git push
```

恢复后按 `部署说明.md` 触发「内核构建 - Android 16 (6.12) [LZ4KD 定制]」即可。

## 四轮编译修复记录（供排障参考）

| 轮次 | 报错 | 修复 |
|---|---|---|
| 1 | `CONFIG_CRYPTO_LZ4K_OPLUS: actual '', expected 'y'` | 6.12 定制块删除该 config 行 |
| 2 | `No rule to make target 'crypto/lz4k.o'` | apply 脚本补拷 `lz4k/crypto/*` |
| 3 | `fatal error: 'backend_lz4k.h' file not found` | 06 补丁去掉 lz4k 的无条件 include |
| 4 | `Unable to find zram.ko / zsmalloc.ko` | 6.12 定制块从 modules.bzl 删这两个模块条目 |

每一轮的错误与修复都已固化在本目录的最终版文件里，无需重新踩坑。
