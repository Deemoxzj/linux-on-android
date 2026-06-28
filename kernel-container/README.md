#拉取gki源码
repo init \                                                                                                                         ─╯
  -u https://android.googlesource.com/kernel/manifest \
  -b common-android13-5.15 \
  --depth=1
  
#同步源码
repo sync -j$(nproc) --no-tags

编译命令
LTO=thin BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh -j$(nproc)

#NTSYNC内核补丁
git clone https://github.com/Goldzxcbug/Droidspaces_Kernel_patch

#root sukisu
curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash -s v4.1.3

#sufs
git clone https://gitlab.com/simonpunk/susfs4ksu

#defconfig
CONFIG_PID_NS=y
CONFIG_IP_VS=y
CONFIG_MODULE_FORCE_LOAD=y
CONFIG_SYSVIPC=y
CONFIG_POSIX_MQUEUE=y
CONFIG_CGROUP_DEVICE=y
CONFIG_USER_NS=y
CONFIG_BRIDGE_NETFILTER=y
CONFIG_NETFILTER_XT_TARGET_CHECKSUM=y
CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y
CONFIG_NETFILTER_XT_MATCH_IPVS=y
CONFIG_IP6_NF_NAT=y
CONFIG_IP6_NF_TARGET_MASQUERADE=y
CONFIG_BT_HCIVHCI=y
CONFIG_DEVTMPFS=y
CONFIG_NULL_TTY=y
#
CONFIG_FHANDLE=y
CONFIG_UNIX_DIAG=y
CONFIG_PACKET_DIAG=y
CONFIG_NETLINK_DIAG=y
CONFIG_MACVLAN=y
CONFIG_LOCALVERSION="-Deemo-SkSU-NTS"
CONFIG_NTSYNC=y
#eBPF
#CONFIG_FTRACE_SYSCALLS=y
#CONFIG_FUNCTION_TRACER=y
#CONFIG_FUNCTION_GRAPH_TRACER=y
#CONFIG_STACK_TRACER=y
#CONFIG_DYNAMIC_FTRACE=y

#test
CONFIG_IPC_NS=y
# UFW support
CONFIG_NETFILTER_XT_TARGET_REJECT=y
CONFIG_NETFILTER_XT_TARGET_LOG=y
CONFIG_NETFILTER_XT_MATCH_RECENT=y
# Fail2ban support
CONFIG_IP_SET=y
CONFIG_IP_SET_HASH_IP=y
CONFIG_IP_SET_HASH_NET=y
CONFIG_NETFILTER_XT_SET=y
# Enable xattr support on tmpfs
# (required for NixOS setcap wrappers in /run/wrappers)
CONFIG_TMPFS_XATTR=y
#KPM
CONFIG_KPM=y
CONFIG_SECURITY=y
CONFIG_SECURITYFS=y
CONFIG_SECURITY_LANDLOCK=y
