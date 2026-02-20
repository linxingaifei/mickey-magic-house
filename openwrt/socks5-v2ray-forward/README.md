# OpenWrt SOCKS5 + V2Ray 一对一转发一键脚本

这个目录提供一个可直接在 OpenWrt 执行的安装脚本：

- 一键安装 xray-core + Web 管理面板
- 支持 SOCKS5 节点一键导入 / 删除 / 更新 / 选择
- 支持内网地址一对一转发规则管理
- 提供“虎额节电”模式开关（平衡/性能/节电）
- Web UI 使用粉紫色主题

## Web 入口在哪里？

默认安装后入口是：

```text
http://<OpenWrt-LAN-IP>/mickey-v2ray/
```

API 默认入口：

```text
http://<OpenWrt-LAN-IP>/cgi-bin/mickey-v2ray-api
```

脚本执行完成时也会打印 `Web 面板目录`、`API 入口`、`默认访问地址`。

## 一键安装

```sh
chmod +x install.sh
./install.sh
```

> 说明：无需预装 `jq`，脚本会自动通过 `opkg` 安装依赖（包括 `jq` 与 `xray-core`）。

## 可选：软件与数据/Web 分离部署

可以，支持分离。你可以把：

- **软件程序**（xray 二进制、init 服务）放在 OpenWrt 本机
- **数据目录**（节点/规则/状态/json）挂载到 Docker 卷路径
- **Web 静态文件**放到 Docker/Nginx 挂载目录
- API 可改为反向代理后的地址

示例：

```sh
APP_DIR=/mnt/docker-data/mickey-v2ray \
WEB_DIR=/mnt/docker-www/mickey-v2ray \
API_BASE=http://192.168.1.1:18080/cgi-bin/mickey-v2ray-api \
RESTART_UHTTPD=0 \
./install.sh
```

变量说明：

- `APP_DIR`：数据目录（默认 `/etc/mickey-v2ray`）
- `WEB_DIR`：Web 页面目录（默认 `/www/mickey-v2ray`）
- `CGI_SCRIPT`：API 脚本落地路径（默认 `/www/cgi-bin/mickey-v2ray-api`）
- `API_BASE`：前端请求 API 根路径（默认 `/cgi-bin/mickey-v2ray-api`）
- `RESTART_UHTTPD`：是否重启 uhttpd（默认 `1`，分离部署建议 `0`）

## 数据文件

- 节点库：`${APP_DIR}/nodes.json`
- 转发规则：`${APP_DIR}/forward-rules.json`
- 状态：`${APP_DIR}/state.json`
- xray 配置：`${APP_DIR}/xray-config.json`

## 注意

1. 本脚本默认使用 `xray-core` 的 SOCKS outbound。
2. 转发规则使用 dokodemo-door 入站实现 TCP/UDP 代理转发。
3. 建议配合防火墙策略限制访问来源，避免误暴露。
