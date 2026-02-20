# OpenWrt 本地设备一键安装说明

适用场景：你准备在本地 OpenWrt 设备上做 `MickeyMagicHouse` 基础能力联调测试。

## 1) 没有 GitHub 直连时怎么安装？

可以，`wget` 只是其中一种方式，不是唯一方式。

### 方式 A：OpenWrt 能访问 GitHub（直接 wget）

```sh
wget -O /tmp/openwrt-oneclick-install.sh \
  https://raw.githubusercontent.com/<your-org>/<your-repo>/<your-branch>/scripts/openwrt-oneclick-install.sh
chmod +x /tmp/openwrt-oneclick-install.sh
sh /tmp/openwrt-oneclick-install.sh
```

### 方式 B：OpenWrt 不能访问 GitHub（推荐用 scp 从你电脑传过去）

先在你的电脑执行（在仓库根目录）：

```sh
scp scripts/openwrt-oneclick-install.sh root@<openwrt-ip>:/tmp/
```

再在 OpenWrt 设备执行：

```sh
chmod +x /tmp/openwrt-oneclick-install.sh
sh /tmp/openwrt-oneclick-install.sh
```

## 2) 脚本执行逻辑（先依赖，后安装）

脚本会严格按以下顺序执行：

1. 检查是否为 `root`、是否为 OpenWrt 环境。
2. `opkg update` 刷新软件源。
3. 先安装基础依赖（如 `ca-bundle`、`wget-ssl`、`curl`、`nftables`、`kmod-tun` 等）。
4. 校验关键依赖是否安装成功，失败则终止。
5. 再安装功能组件（`mwan3`、`pbr`、`sing-box`、`docker` 等）。
6. 自动启用可用服务（`dockerd`、`pbr`、`mwan3`）。

## 3) 常见问题

### Q1: 依赖包安装失败
通常是当前软件源缺包或架构不匹配。先确认：

- 设备架构是否对应软件源
- 软件源是否可访问
- 固件版本是否支持目标包

### Q2: 设备空间不足
先清理缓存或扩容，再重试安装。

### Q3: 安装后 Web 页面没看到功能
建议重启后再检查，并确认 LuCI 对应 app 包已安装。

## 4) 建议

首次安装完成后执行：

```sh
reboot
```

重启后再开始配置多出口、PBR 与 sing-box 规则。
