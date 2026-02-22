# OpenWrt 双层分流落地（PBR + sing-box 二次分流）

> 目标：第一层用 OpenWrt PBR 把用户流量分配到 `wan / l2tp / openvpn / sing-box-tun`；第二层在进入 `sing-box-tun` 后继续做一对一节点绑定（源 IP → 固定代理节点）。

## 1. 拓扑与分层

```text
PPPoE 用户
  └─(固定内网 IP)
      └─ OpenWrt PBR (第一层)
          ├─ 出口 A: WAN
          ├─ 出口 B: L2TP
          ├─ 出口 C: OpenVPN
          └─ 出口 D: sing-box TUN
                 └─ sing-box route/rule_set (第二层)
                     ├─ 10.0.0.11 -> 节点 node-hk-01
                     ├─ 10.0.0.12 -> 节点 node-jp-01
                     └─ 10.0.0.13 -> 节点 node-us-01
```

### 设计原则

1. **第一层只决定“是否进入 sing-box”**，不在 PBR 内处理代理节点细节。
2. **第二层只处理进入 sing-box 的流量**，按源 IP 一对一绑定到节点。
3. **出口责任清晰**：PBR 管“出口类型”，sing-box 管“节点映射”。
4. **故障隔离**：某个 sing-box 节点异常不影响 WAN/L2TP/OpenVPN 直出策略。

---

## 2. 第一层：OpenWrt PBR 规则建议

建议建立 4 组策略：

- `PBR-WAN`: 指定用户或网段直走 WAN。
- `PBR-L2TP`: 指定用户或网段走 L2TP。
- `PBR-OVPN`: 指定用户或网段走 OpenVPN。
- `PBR-SBOX`: 指定用户或网段进入 `sing-box-tun`。

示例思路（伪配置，按你的实际接口名替换）：

```text
10.0.0.11/32 -> wan
10.0.0.12/32 -> l2tp-vpn
10.0.0.13/32 -> openvpn-vpn
10.0.0.21/32 -> singbox_tun
10.0.0.22/32 -> singbox_tun
10.0.0.23/32 -> singbox_tun
```

> 重点：只有被分配到 `singbox_tun` 的 IP，才会触发第二层节点一对一。

---

## 3. 第二层：sing-box 源 IP 一对一节点绑定

下面是可复用的 `route.rules` 结构（示例）：

```json
{
  "route": {
    "rules": [
      {
        "ip_cidr": ["10.0.0.21/32"],
        "outbound": "node-hk-01"
      },
      {
        "ip_cidr": ["10.0.0.22/32"],
        "outbound": "node-jp-01"
      },
      {
        "ip_cidr": ["10.0.0.23/32"],
        "outbound": "node-us-01"
      },
      {
        "ip_cidr": ["10.0.0.0/24"],
        "outbound": "direct"
      }
    ],
    "final": "direct"
  }
}
```

### 一对一绑定要点

- 每个用户 IP 用 `/32` 精确匹配。
- 每个节点独立 outbound tag（如 `node-hk-01`）。
- 最后加兜底规则，避免未命中流量黑洞。
- 推荐在节点健康检查失败时切到备用节点（同地区）。

---

## 4. 节点与用户映射建议

建议单独维护一个映射表（可由脚本生成 sing-box 配置）：

| 用户 IP | 一级出口(PBR) | 二级节点(sing-box) | 备注 |
|---|---|---|---|
| 10.0.0.11 | WAN | - | 业务直连 |
| 10.0.0.12 | L2TP | - | 跨境低成本线路 |
| 10.0.0.13 | OpenVPN | - | 兼容旧系统 |
| 10.0.0.21 | sing-box-tun | node-hk-01 | 港区固定出口 |
| 10.0.0.22 | sing-box-tun | node-jp-01 | 日区固定出口 |
| 10.0.0.23 | sing-box-tun | node-us-01 | 美区固定出口 |

---

## 5. 运维与排障顺序

当你发现某用户“没有走到期望节点”时，按顺序查：

1. **先看 PBR 命中**：是否真的被送到了 `sing-box-tun`。
2. **再看 sing-box 规则命中**：源 IP `/32` 是否一致。
3. **再看节点连通**：对应 outbound 节点是否在线。
4. **最后看回程/NAT**：避免回程走错接口造成假性丢包。

---

## 6. 推荐实践（适配你当前需求）

- PPPoE 用户池建议固定分配，减少规则漂移。
- 以“用户 IP = 账号”方式建立静态映射，便于审计。
- sing-box 节点采用一主一备（同地区）策略，切换时不改 PBR，仅改二层映射。
- 新增用户时先加 PBR，再加 sing-box 一对一规则，最后做连通测试。

这样可以实现你说的模式：

- 第一层：`wan / l2tp / openvpn / sing-box tun` 四类分流。
- 第二层：进入 `sing-box tun` 后再按源 IP 一对一绑定节点。
