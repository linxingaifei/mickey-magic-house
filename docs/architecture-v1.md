# 米奇妙妙屋 系统架构 V1.0

## 一、项目定位

商业可控多出口智能网关系统  
基于 OpenWrt 23.05 深度定制

## 二、核心架构

PPPoE 接入 → PBR 第一层分流 → 多出口  
sing-box 执行第二层源IP绑定分流

## 三、出口支持

- 多 WAN
- L2TP Client
- OpenVPN Client
- sing-box TUN
- Docker 扩展

## 四、存储结构

- Ext4 可扩容 Root
- Docker 独立数据目录
- SATA / NVMe / VirtIO 支持

## 五、未来规划

V1：基础多出口系统  
V2：Web 控制平台  
V3：商业授权模块  
V4：云控中心
