#!/bin/sh
# MickeyMagicHouse - OpenWrt 一键安装基础组件脚本
# 用法：sh openwrt-oneclick-install.sh

set -eu

PROJECT_NAME="MickeyMagicHouse"

# 先安装依赖，再安装功能包
DEPENDENCY_PKGS="ca-bundle libustream-mbedtls uclient-fetch wget-ssl curl bash coreutils-timeout ip-full iptables-nft nftables kmod-tun"
FEATURE_PKGS="ppp ppp-mod-pppoe odhcp6c mwan3 pbr luci-app-pbr sing-box docker dockerd containerd kmod-veth kmod-bridge kmod-br-netfilter kmod-overlay kmod-cgroup2"
CRITICAL_PKGS="ca-bundle curl wget-ssl nftables"

log() {
  printf '%s %s\n' "[INFO]" "$*"
}

warn() {
  printf '%s %s\n' "[WARN]" "$*"
}

err() {
  printf '%s %s\n' "[ERR ]" "$*" >&2
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "缺少命令: $1"
    exit 1
  }
}

ensure_openwrt() {
  if [ ! -f /etc/openwrt_release ] && [ ! -f /etc/os-release ]; then
    err "当前系统看起来不是 OpenWrt，终止执行。"
    exit 1
  fi
}

ensure_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "请使用 root 执行脚本。"
    exit 1
  fi
}

install_pkg() {
  pkg="$1"
  if opkg list-installed "$pkg" >/dev/null 2>&1; then
    log "已安装: $pkg"
    return 0
  fi

  if opkg install "$pkg" >/dev/null 2>&1; then
    log "安装成功: $pkg"
    return 0
  fi

  warn "安装失败(可能源里没有): $pkg"
  return 1
}

install_pkg_group() {
  title="$1"
  pkg_list="$2"

  log "开始安装${title}..."

  group_success=0
  group_fail=0
  for pkg in $pkg_list; do
    if install_pkg "$pkg"; then
      group_success=$((group_success + 1))
      TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))
    else
      group_fail=$((group_fail + 1))
      TOTAL_FAIL=$((TOTAL_FAIL + 1))
      FAILED_PKGS="$FAILED_PKGS $pkg"
    fi
  done

  log "${title}安装完成：成功 ${group_success}，失败 ${group_fail}"
}

check_critical_packages() {
  missing=""
  for pkg in $CRITICAL_PKGS; do
    if ! opkg list-installed "$pkg" >/dev/null 2>&1; then
      missing="$missing $pkg"
    fi
  done

  if [ -n "$missing" ]; then
    err "关键依赖未安装成功:${missing}"
    err "请检查软件源可用性后重试。"
    exit 1
  fi
}

enable_service_if_exists() {
  svc="$1"
  if [ -x "/etc/init.d/$svc" ]; then
    /etc/init.d/"$svc" enable || true
    /etc/init.d/"$svc" start || true
    log "已启用服务: $svc"
  else
    warn "服务不存在，跳过: $svc"
  fi
}

main() {
  ensure_root
  ensure_openwrt
  need_cmd opkg

  TOTAL_SUCCESS=0
  TOTAL_FAIL=0
  FAILED_PKGS=""

  log "开始执行 $PROJECT_NAME OpenWrt 一键安装"
  log "刷新软件源..."
  if ! opkg update >/dev/null 2>&1; then
    err "opkg update 失败，请检查网络或软件源配置"
    exit 1
  fi

  install_pkg_group "基础依赖" "$DEPENDENCY_PKGS"
  check_critical_packages
  install_pkg_group "功能组件" "$FEATURE_PKGS"

  log "配置并启动关键服务..."
  enable_service_if_exists dockerd
  enable_service_if_exists pbr
  enable_service_if_exists mwan3

  log "安装完成：成功 $TOTAL_SUCCESS，失败 $TOTAL_FAIL"
  if [ "$TOTAL_FAIL" -gt 0 ]; then
    warn "失败包列表:${FAILED_PKGS}"
    warn "有部分包安装失败，通常是当前软件源不包含对应包；可切换到支持仓库后重试。"
  fi

  log "建议重启设备后再进行联调测试: reboot"
}

main "$@"
