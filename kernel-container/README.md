#拉取gki源码
repo init \                                                                                                                         ─╯
  -u https://android.googlesource.com/kernel/manifest \
  -b common-android13-5.15 \
  --depth=1
  
#同步源码
repo sync -j$(nproc) --no-tags

#编译命令
LTO=thin BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh -j$(nproc)

#789补丁优先
https://github.com/ravindu644/Droidspaces-OSS/tree/main/Documentation/resources/kernel-patches/GKI/below-kernel-6.12
#NTSYNC内核补丁
git clone https://github.com/Goldzxcbug/Droidspaces_Kernel_patch

#root sukisu-ultra只需要打50补丁
curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash -s v4.1.3

#sufs
git clone https://gitlab.com/simonpunk/susfs4ksu -b *

# 1) 给 KernelSU 部分的补丁
cp susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch $KERNEL_REPO/KernelSU/

# 2) 给 common 内核部分的补丁（注意内核版本号要对上！）
cp susfs4ksu/kernel_patches/50_add_susfs_in_kernel-<kernel_version>.patch $KERNEL_REPO/common/
# 例：6.1 → 50_add_susfs_in_gki-android14-6.1.patch

# 3) 替换/新增的源码文件
cp susfs4ksu/kernel_patches/fs/* $KERNEL_REPO/common/fs/
cp susfs4ksu/kernel_patches/include/linux/* $KERNEL_REPO/common/include/linux/

# 先打 KSU 侧
cd $KERNEL_REPO/KernelSU
patch -p1 < 10_enable_susfs_for_ksu.patch

# 再打内核侧
cd $KERNEL_REPO/common
patch -p1 < 50_add_susfs_in_kernel-<kernel_version>.patch

# 两种方式任选：menuconfig / 直接改 defconfig
# 必须：
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y

# 可选特性（按需开）：
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
# ...其余见 $KernelSU_repo/kernel/Kconfig
cd common
ARCH=arm64 scripts/config \
    --enable CONFIG_KSU \
    --enable CONFIG_KSU_SUSFS \
    --enable CONFIG_KSU_SUSFS_SUS_PATH \
    --enable CONFIG_KSU_SUSFS_SUS_MOUNT \
    --enable CONFIG_KSU_SUSFS_TRY_UMOUNT \
    --enable CONFIG_KSU_MANUAL_HOOK \
    --enable CONFIG_KALLSYMS \
    --enable CONFIG_KALLSYMS_ALL \
    --enable CONFIG_KPM
