# OpenWrt SOCKS5 + V2Ray 一对一转发一键脚本

这个目录提供一个可直接在 OpenWrt 执行的安装脚本：

- 一键安装 xray-core + Web 管理面板
- 支持 SOCKS5 节点一键导入 / 删除 / 更新 / 选择
- 支持内网地址一对一转发规则管理
- 提供“虎额节电”模式开关（平衡/性能/节电）
- Web UI 使用粉紫色主题

## 一键安装

```sh
chmod +x install.sh
./install.sh
```

安装成功后访问：

```text
http://<OpenWrt-LAN-IP>/mickey-v2ray/
```

## 数据文件

- 节点库：`/etc/mickey-v2ray/nodes.json`
- 转发规则：`/etc/mickey-v2ray/forward-rules.json`
- 状态：`/etc/mickey-v2ray/state.json`
- xray 配置：`/etc/mickey-v2ray/xray-config.json`

## 注意

1. 本脚本默认使用 `xray-core` 的 SOCKS outbound。
2. 转发规则使用 dokodemo-door 入站实现 TCP/UDP 代理转发。
3. 建议配合防火墙策略限制访问来源，避免误暴露。
