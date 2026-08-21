# ⚡ High-Performance SOCKS5 Matrix

基于 **Gost (单 IP 极简版)** 与 **3proxy (多 IP 严格「源进源出」版)** 打造的高性能、轻量化、安全加固 SOCKS5 代理运维管理系统。

---

## 🌟 方案总览与脚本选型

本项目提供两种生产级部署方案，均已实现安全加固与全自动化运维：

| 方案模式 | 适用场景 | 核心引擎 | 快捷命令 | 核心优势 |
| :--- | :--- | :--- | :--- | :--- |
| **方案 1：单 IP 加固版** (`s5_secured.sh`) | 单网卡单公网 IP 的标准服务器 | **Gost 官方核心** | `S5` | 原生直连官方 Releases，强制 SHA256 哈希校验，高强度随机密码 |
| **方案 2：多 IP「源进源出」版** (`s5_multi_ip.sh`) | 拥有 2 个或多个公网 IP 的服务器 | **3proxy 极速内核** | `S5M` | 自动扫描多 IP，精准绑定入口与出口 IP（进出一致），自动配置内核策略路由与 `rp_filter` |

---

## 🚀 一键在线安装

### 方案 1：单 IP 服务器标准加固安装
```bash
curl -fsSL https://raw.githubusercontent.com/4kercc/socks5-manager/main/s5_secured.sh -o /tmp/s5.sh && bash /tmp/s5.sh
```

### 方案 2：多 IP 服务器【源进源出】专属安装
```bash
curl -fsSL https://raw.githubusercontent.com/4kercc/socks5-manager/main/s5_multi_ip.sh -o /tmp/s5m.sh && bash /tmp/s5m.sh
```

> **提示**：安装交互均支持**一路直接按回车（Enter）**，系统将自动识别 IP 并配置安全随机端口、随机用户名与 16 位高强度复杂随机密码。

---

## 🌐 多 IP「源进源出」核心原理说明

在 Linux 多 IP 服务器环境下，如果代理程序不显式绑定本地出站 IP，Linux 内核会默认使用系统主网卡（Primary IP）的默认网关将流量发出，导致**客户端不管连入哪个 IP，访问外部网站时看到的都是主 IP**。

**本项目的解决方案**：
1. **应用层 (3proxy)**：针对每个检测到的 IP，单独声明 `internal <IP>`（入站监听）与 `external <IP>`（出站发起绑定），确保从该 IP 建立的 TCP/UDP 连接仅从该 IP 发起。
2. **内核层 (Linux Policy Routing)**：自动将 `/proc/sys/net/ipv4/conf/*/rp_filter` 设置为 `2`（宽松反向路径过滤），并为跨网卡/跨网关 IP 配置 `ip rule from <IP> table` 策略路由，保证响应包原路返回。

---

## 🖥️ 管理控制台

### 1. 单 IP 控制台 (`S5`)
终端输入 **`S5`** 即可打开单 IP 管理面板：
```text
   [1]  查看连接凭证与链接信息
   [2]  启动 / 平滑重启代理服务
   [3]  停止 / 安全终止代理服务
   [4]  切换系统开机自启策略
   [5]  重新配置参数并重新部署
   [6]  查看系统运行日志与诊断
   [7]  执行本地端口与隧道测试
   [8]  检查官方仓库更新与热刷
   [9]  完全卸载并清理系统环境
   [10] 退出控制面板
```

### 2. 多 IP「源进源出」控制台 (`S5M`)
终端输入 **`S5M`** 即可打开多 IP 管理面板，支持一键检测所有 IP 出口是否与入口 100% 匹配，并可实时汇总查看各节点的流量消耗：
```text
   [1]  查看多 IP 节点连接凭证 (展示各IP对应的SOCKS5链接)
   [2]  一键全节点「源进源出」出口测试 (验证出口IP是否与入口一致)
   [3]  查看各节点与全局流量消耗统计 (实时汇总各IP上传/下载流量)
   [4]  启动 / 重启 3proxy 代理服务
   [5]  停止 3proxy 代理服务
   [6]  重新配置参数与多 IP 列表
   [7]  彻底卸载并清理系统环境
   [8]  退出控制面板
```

---

## 📁 系统文件结构

```text
# 方案 1 (Gost):
/etc/socks5_gost.conf              # 配置文件 (chmod 600)
/usr/local/bin/gost                # Gost 核心
/usr/local/bin/S5                  # 快捷启动命令

# 方案 2 (3proxy 多 IP):
/etc/3proxy/3proxy.cfg             # 3proxy 主配置文件 (chmod 600)
/etc/3proxy/3proxy_meta.conf       # 多 IP 元数据
/etc/sysctl.d/99-3proxy-network.conf # 内核策略路由配置
/usr/local/bin/3proxy              # 3proxy 核心
/usr/local/bin/S5M                 # 快捷启动命令
```

---

## 💡 客户端连接示例

以多 IP 服务器拥有 `1.1.1.1` 与 `2.2.2.2` 两个 IP、端口 `1080` 为例：
- **连接 1.1.1.1:1080** ➡️ 访问外部目标网站，目标网站识别到的访客 IP **必定为 1.1.1.1**。
- **连接 2.2.2.2:1080** ➡️ 访问外部目标网站，目标网站识别到的访客 IP **必定为 2.2.2.2**。

---

## 🗑️ 卸载

在控制台分别选择卸载选项，脚本会自动停止守护进程、清理防火墙规则并删除所有配置文件与二进制文件。
