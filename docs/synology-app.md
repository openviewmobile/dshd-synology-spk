# Synology DSM 应用化：把 dsh 装进 NAS

- 状态：研究（2026-11-08），不是范围决策。
- 目标：让 dsh 内核跑在 Synology NAS 上，LAN 内浏览器访问 Web UI；不引入云端/中继。
- 相关产品决策见 [ADR-0007](adr/0007-local-only-scope.md)；跨端架构与发布矩阵不随本仓库维护。
- 结论：**MVP 用 Container Manager + Compose + 预构建多架构镜像 + DSM 反向代理；GA 用 SPK 包一层 Docker 项目；原生 SPK 只在“必须无 Docker”时立项。**

---

## 1. 先划边界：NAS 属于“本地”还是“远程”？

ADR-0007 把“浏览器连另一台机器的 Host”判为远程，因此不做 Web。NAS 方案必须先把定义说清：

| 形态 | 内核位置 | 浏览器位置 | 是否算本地 |
|---|---|---|---|
| NAS + LAN 浏览器 | NAS 本机 | 同一 LAN | **建议算“LAN 设备版”**，不是 Web/SaaS |
| NAS + 公网端口映射 | NAS 本机 | 任意网络 | 远程，超出产品范围 |
| NAS + QuickConnect/中继 | NAS 本机 | 任意网络 | 远程，且 dsh 不支持该链路 |

建议把 NAS 定义为**单用户、LAN 内、无中继的本地设备 SKU**；远程访问由用户自建 VPN/Tailscale，不属于产品承诺。这需要产品在 ADR-0007 上补一条解释，否则会和“不做 Web”冲突。

---

## 2. dsh 的硬约束（决定架构，不是偏好）

| 事实 | 影响 |
|---|---|
| `dsh --profile web` 默认 `127.0.0.1:3080`，启动打印带一次性 token 的 URL | 首启必须有办法把 URL 交到用户手里 |
| `--host` 只接受**具体本机 IP**，拒绝 `0.0.0.0` | 容器里不能简单“监听所有网卡 + 端口映射” |
| Host/Origin 栅栏：接受绑定 IP；其他 authority 必须 `--trusted-host` | 反代必须保留/改写 Host，且把域名加入信任 |
| `--public-url` 只负责“公告”，不授予信任 | 必须同时配 `--trusted-host` |
| 启动 token 换签名 HttpOnly cookie；token 只在 stdout/URL | 不能把 token 写进镜像、文档或模型上下文 |
| `--tls-cert/--tls-key` 可用，但无 ACME、无自签兜底 | NAS 上更适合由 DSM 终止 TLS |
| 工具面需要 bash、文件系统、ripgrep、pnpm、可选 Python/Office | 容器镜像不能是纯 distroless |
| 原生模块含 `node-pty`、`koffi`、`node:sqlite` 等 | 必须按 arch 构建/验证，Alpine/musl 风险高 |

容器场景下 dsh 官方建议的启动方式就是：

```sh
dsh --profile web --no-open \
  --host "$(hostname -i | awk '{print $1}')" \
  --public-url https://dsh.example.com \
  --trusted-host dsh.example.com
```

`hostname -i` 拿到容器 IP（如 `172.18.0.2`），不是 `127.0.0.1`。这是“端口映射 + 反代”能成立的前提。

---

## 3. DSM 平台事实（截至 DSM 7.2.2）

| 事实 | 证据 | 对方案的影响 |
|---|---|---|
| SPK 结构固定：`INFO`、`package.tgz`、`scripts/`、`conf/`、图标；7.2.2 起有 `WIZARD_UIFILES` v2 | 开发者指南 | 原生包必须按此布局 |
| DSM 7 强制降权：默认 `run-as: package`，脚本以包用户运行 | Privilege 文档 | 不能默认 root；端口/文件/服务都受限 |
| 包目录 `target/var/etc/tmp/home` 默认在卷上（`install_type=system` 除外） | FHS 文档 | 数据放 `var/home` 或共享文件夹，不写系统盘 |
| DSM 7 **不再要求 GPG 签名**（签名机制仅 DSM 6.x） | Sign Package 文档 | 第三方可发普通 tar SPK；手动安装提示来源 |
| Container Manager 同时提供 `x86_64` 与 `armv8` SPK（24.0.2-1707） | Synology Archive | x86_64 全面；ARM 仅部分机型 |
| 适用机型含 DS223/DS124/DS223j 等 ARM 机型 | 官方 Applied Models | 不能假设“ARM 一定没有 Docker” |
| Package Center 的 Node.js 最高为 **v22.23.4**，没有 v24 | Synology Archive | 原生 SPK 必须自带 Node 24 |
| 反代两条路：DSM 登录门户反代；Web Station 的 `reverse_proxy` 服务类型 | 开发者指南 Web Service | Web Station 不是唯一入口，单容器不必依赖它 |
| `docker-project` worker 自 ContainerManager >= 1432（DSM 7.2.1） | 开发者指南 | 混合 SPK 的最低版本门槛 |
| Docker worker 端口限制 1025–65535 | 开发者指南 | 不能占 80/443 |
| 包需注册 `.sc` 端口文件，防火墙才会列出应用 | Port 文档 | 不注册就没有防火墙应用条目 |
| 审核要求：非 root、可离线安装、无 AppArmor deny、无残留、端口不冲突 | Publication Review | 原生 dsh 的 shell/工具面会撞上这些检查 |

需现场核实的假设：Container Manager 的 dockerd 以 root 运行，**没有 rootless 模式**；Docker 发布端口通常直接写 iptables，**不能把 DSM 防火墙当容器端口的安全边界**；DSM 7 的 systemd 只用于 DSM 自身与 `pkg-*.service`。

---

## 4. 四种候选

### A. Container Manager / Docker Compose（推荐 MVP）

预构建 `linux/amd64` + `linux/arm64` 镜像，Container Manager 建 Compose 项目，DSM 反代终止 TLS，数据卷持久化。

- 优点：Node 24 直接来自官方镜像；多架构；资源限制/日志/重启策略现成；升级=换 tag；与 DSM 解耦。
- 缺点：要求机型支持 Container Manager；首启 token 要从日志取；UID/共享文件夹权限要手工对齐；国内拉镜像可能受阻。

### B. 原生 DSM SPK（Phase 3，非首选）

`package.tgz` 内置 Node 24 + dsh + 依赖 + pnpm，`start-stop-status` 起进程，包用户运行。

- 优点：Package Center 安装体验最好；无 Docker 依赖；可用 DSM 桌面图标。
- 缺点：每个 arch 单独构建；Node 24 要自带；原生模块要交叉编译；AppArmor/审核风险；包体积大；升级链要自己做。

### C. DSM Web Station 反向代理（不是独立方案）

Web Station 能注册 `reverse_proxy` 服务，但对“单个 Docker 应用”来说它是**网络层组件**，不是打包方案。可用入口是 Container Manager 的 Project → Web Portal（若该版本提供），或控制面板 → 登录门户 → 高级 → 反向代理。两者都是 DSM 内置 nginx；Web Station 只在你要把反代作为“Web 服务”随 SPK 注册时才需要。

### D. 混合：SPK 外壳 + Docker 运行时（推荐 GA）

SPK 负责 Package Center 安装、图标、端口、权限、反代注册；实际内核放在容器里，由 `docker-project` worker 启动。

- 优点：保留 A 的 Node 24/多架构/隔离，同时拿到 Package Center 的一键安装与升级。
- 缺点：仍依赖 Container Manager；SPK 要处理离线安装/镜像预载；审核更复杂；需要 DSM 7.2.1+。

---

## 5. 决策矩阵

评分 1–5，权重合计 100；C 不单独评分（它是组件）。

| 维度 | 权重 | A Docker | B 原生 SPK | D 混合 |
|---|---:|---:|---:|---:|
| 安装体验 | 15 | 3 | 5 | 5 |
| 更新/回滚 | 10 | 4 | 4 | 4 |
| 认证/TLS | 15 | 4 | 4 | 4 |
| 持久化/工作区 | 10 | 5 | 4 | 5 |
| 资源隔离/限制 | 8 | 4 | 3 | 4 |
| Node 24 可得性 | 10 | 5 | 2 | 5 |
| 原生模块 | 8 | 4 | 2 | 4 |
| GUI/首启 | 10 | 3 | 4 | 4 |
| 许可/合规 | 4 | 4 | 4 | 4 |
| 支持负担 | 5 | 3 | 2 | 3 |
| 机型覆盖 | 5 | 4 | 4 | 4 |
| **加权分** | 100 | **3.90** | **3.61** | **4.30** |

读法：**D 分数最高，但它是 A 的超集**——没有 A 的镜像/Compose/反代，就没有 D，所以路线是 A → D。B 被 Node 24、原生模块、支持负担拖低，只在“客户明确拒绝 Docker”时才有意义。A 的“GUI/首启”低分主要来自 token 交付，不是技术不可行，这是最值得先补的产品缺口。

---

## 6. MVP：Container Manager + Compose + 反代

### 6.1 拓扑

```
LAN Browser
  │ HTTPS 443 (dsh.example.com)
  ▼
DSM nginx（登录门户反代 / Container Manager Web Portal）
  │ HTTP 127.0.0.1:3080  （只绑定 loopback）
  ▼
dsh 容器（bridge 网络，容器 IP 172.x:3080）
  ├─ /data/dsh      ← /volume1/docker/dshd/home
  └─ /workspace     ← /volume1/dsh-workspace
```

dsh 绑定容器 IP，**不是** `0.0.0.0`；容器端口只发布到 `127.0.0.1:3080`；反代把 `Host: dsh.example.com` 传给 dsh，所以 `--trusted-host` 必须包含它；TLS 在 DSM 终止，dsh 看到 HTTP 上游，cookie 不带 `Secure`——后端必须只绑 loopback。仓库建议布局：`deploy/synology/{compose.yaml,.env.example,Dockerfile,entrypoint.sh,dsm/,spk/}`。

### 6.2 Dockerfile 草图

```dockerfile
FROM node:24-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash ca-certificates git ripgrep tini python3 util-linux \
    && rm -rf /var/lib/apt/lists/*
RUN npm i -g @deepseek-ai/dsh@0.2.1-rc.5 pnpm
COPY entrypoint.sh /usr/local/bin/
ENV DSH_HOME=/data/dsh NODE_ENV=production
WORKDIR /workspace
ENTRYPOINT ["/usr/sbin/tini","--","/usr/local/bin/entrypoint.sh"]
```

不要用 Alpine：`node-pty`/`koffi` 的 prebuild 以 glibc 为主，musl 往往要自编。生产构建建议分离 build stage，并把原生模块预编译到镜像里；若目标 arch 没有 prebuild，在 build 阶段装 `build-essential python3`。

### 6.3 entrypoint 草图

```sh
#!/bin/sh
set -eu
: "${DSH_HOME:=/data/dsh}"
: "${DSH_PUBLIC_URL:?}" "${DSH_TRUSTED_HOST:?}"
mkdir -p "$DSH_HOME" /workspace

# root 启动时修权限再降权；PUID/PGID 对应 DSM 用户/组
if [ "$(id -u)" = "0" ]; then
  chown -R "${PUID:-1026}:${PGID:-100}" "$DSH_HOME" /workspace
  exec setpriv --reuid="${PUID:-1026}" --regid="${PGID:-100}" --init-groups "$0" "$@"
fi

exec dsh --profile web --no-open --host "$(hostname -i | awk '{print $1}')" \
  --port 3080 --public-url "$DSH_PUBLIC_URL" --trusted-host "$DSH_TRUSTED_HOST"
```

### 6.4 compose 草图

```yaml
name: dshd
services:
  dsh:
    image: ghcr.io/<org>/dshd:0.1.0
    restart: unless-stopped
    ports: ["127.0.0.1:3080:3080"]
    volumes: ["./home:/data/dsh", "/volume1/dsh-workspace:/workspace"]
    environment:
      DSH_HOME: /data/dsh
      DSH_PUBLIC_URL: https://dsh.example.com
      DSH_TRUSTED_HOST: dsh.example.com
      DEEPSEEK_API_KEY: ${DEEPSEEK_API_KEY:?}
      PUID: "1026"
      PGID: "100"
      TZ: Asia/Shanghai
    mem_limit: 4g
    cpus: 2.0
```

`.env` 放 compose 同目录；Container Manager 是否透传 `.env` 需在目标版本实测。健康检查要打容器 IP（`http://$(hostname -i | awk '{print $1}'):3080/`），打 `127.0.0.1` 会失败。

### 6.5 DSM 安装步骤（x86_64 先行）

1. Package Center 安装 **Container Manager**；机型不支持则本方案不成立。
2. 控制面板 → 共享文件夹：建 `dsh-workspace`，给实际使用 dsh 的 DSM 用户读写权限。
3. File Station 建 `/docker/dshd`，上传 `compose.yaml` 与 `.env`；Container Manager → 项目 → 新建 → 选择该目录 → 启动。
4. 打开容器日志，找到 `dsh web: https://dsh.example.com/?token=...`；浏览器打开一次，token 换成 cookie。
5. 控制面板 → 登录门户 → 高级 → 反向代理：来源 HTTPS `dsh.example.com:443`，目的地 HTTP `127.0.0.1:3080`；绑定证书、开 HSTS、确认 WebSocket 升级头透传。
6. 安全性 → 防火墙：只放行 LAN 到 443；不要放行 3080。路由器不做端口映射；远程用 VPN/Tailscale，不纳入产品。

若 Container Manager 带 Project → Web Portal，可跳过第 5 步，直接为容器端口 3080 建 HTTPS 门户；本质仍是 DSM nginx 反代。

### 6.6 认证与 TLS 的真实边界

- dsh token 是**唯一身份**；DSM 登录不等于 dsh 登录，反代默认不加认证。
- 额外门禁只能靠 VPN/Tailscale、防火墙 IP 白名单，或自定义 nginx basic auth（DSM UI 能力有限）。
- token 会出现在容器日志、浏览器历史、诊断包；Container Manager 权限限制在 admin 组，并明确“日志含密钥”。
- 反代到 HTTP 上游时 cookie 无 `Secure`；可接受，但不能再把 3080 暴露到 LAN。
- 不要用子路径 `/dsh/`：dsh 支持 `--public-url` + 去前缀代理，但 DSM 内置反代不保证剥前缀。用独立域名最稳。
- `dsh.example.com` 必须在 LAN 内可解析；没有公网 80 时 Let's Encrypt 不可用，改用私有 CA 或导入证书。

### 6.7 持久化、权限、资源

- `home/`：profiles、sessions、credentials、日志，必须备份，credentials 建议加密。
- `workspace/`：用户文件、代码库，必须备份（Hyper Backup/快照）；`cache/` 可选。
- **UID 映射**：DSM 首个普通用户通常是 1026，`users` 组 100；容器用 `PUID/PGID` 对齐，否则 File Station 会出现“未知用户/无法编辑”。
- 不要以 root 长期运行；root 写出的文件会让 DSM 用户无法改。
- Node 基线约 300–600 MB；agent 构建/测试可能 2–4 GB。建议 2 vCPU / 4 GB 起；2 GB 内存的机型易 OOM。
- ARM（RTD1619B）能跑，但编译/索引明显慢；重活建议 x86_64 Plus 机型。镜像 + node_modules 约 1–2 GB，预留 20 GB。

- 更新：镜像 tag 用不可变版本（生产再加 digest），备份 `home/` → 改 tag → `docker compose pull && up -d`；保留旧 tag 回滚。dsh 固定在镜像内，不要在容器里 `npm update`。

---

## 7. 原生 SPK（Phase 3）

### 7.1 包结构

```text
dshd.spk
├── INFO
├── package.tgz          # node24/、dsh/、node_modules/、pnpm/、bin/
├── scripts/  preinst postinst preuninst postuninst preupgrade postupgrade start-stop-status
├── conf/     privilege  resource  systemd/pkg-dshd.service
├── WIZARD_UIFILES/install_uifile
├── PACKAGE_ICON.PNG（64x64）  PACKAGE_ICON_256.PNG（256x256）
└── LICENSE
```

### 7.2 INFO 要点

```ini
package="dshd"
version="0.1.0-0001"
os_min_ver="7.2-64570"
arch="x86_64"                 # 另一份构建用 armv8；不要混装
displayname="DSHD"
displayname_chs="DSHD"
description="Local dsh agent for Synology NAS"
maintainer="..."  maintainer_url="https://..."  support_url="https://..."
dsmuidir="ui"  dsmappname="com.example.dshd"
checkport="yes"  startable="yes"
```

- `arch` 取 `x86_64` 或 `armv8`；官方明确不建议把多平台二进制塞进一个 SPK。
- `adminport` 慎用：Package Center 的“打开”只能拼 `protocol://NAS_IP:port/path`，Host 头不是 `dsh.example.com`，会被 Host 栅栏 403，而且无法携带启动 token。桌面图标应指向 launcher 页面。

### 7.3 生命周期与权限

- `start-stop-status` 是唯一可靠的生命周期入口；优先 `conf/systemd/pkg-dshd.service` + `synosystemctl`，退路是 `nohup` + PID 文件。
- 包脚本以 `package` 用户运行；绑定 80/443 需要 root/capability，直接放弃，用 3080 + 反代。
- 工作区用 `data-share` 资源建共享文件夹（卸载不删除），或让用户选已有共享文件夹；后者要处理 ACL。
- 端口用 `.sc` 注册并在 `conf/resource` 的 `port-config` 引用，否则防火墙里看不到应用。
- 需要反代时用 `webservice` 的 `reverse_proxy` 类型，但会引入 Web Station 依赖；更简单的是让用户用登录门户手工建。

### 7.4 Node 24 与原生模块

- Package Center 没有 Node 24，SPK 必须自带官方 `linux-x64`/`linux-arm64` 二进制（约 100 MB/arch）。
- 需验证 DSM 7.2 的 glibc/OpenSSL 能满足 Node 24；官方二进制依赖 glibc，逐机型测。
- `node-pty`、`koffi` 要在 DSM Toolkit chroot 里按 arch 构建，或确认 prebuild ABI 匹配；这是原生 SPK 最大的工期来源。
- pnpm、ripgrep、Python、Office 是否内置要取舍；每加一项，包体和审核面都增加。

### 7.5 发布与审核

- DSM 7 不需要 GPG 签名；第三方可手动安装，但会提示来源。
- 官方 Package Center 需申请开发者账号、接受分发协议，并通过非 root、离线安装、Security Advisor、AppArmor deny、端口注册、卸载残留等检查。
- dsh 的核心能力就是“执行任意 shell/读写工作区”，与 DSM 的安全审核天然紧张；**官方上架风险高，先按手动 SPK/GitHub 分发设计**。
- 第三方包源/自动更新要自己维护 JSON feed；否则用户只能手动下载新 SPK。

### 7.6 混合 D：SPK 只做安装器

`conf/resource` 用 `docker-project`：

```json
{
  "docker-project": {
    "preload-image": "dshd-image.tar.gz",
    "projects": [{ "name": "dshd", "path": "compose" }]
  }
}
```

- SPK 负责：依赖检查（Container Manager）、共享文件夹、端口、图标、反代、升级脚本；容器负责 Node 24、dsh、原生模块、隔离。
- 代价：离线安装要预载 1–2 GB 镜像；不预载则首次启动要联网拉取，和“安装期无异常网络活动”的审核要求冲突。
- 建议在 A 验证完镜像/反代后再做。

---

## 8. 明确不可行 / 高风险

1. **`dsh web --host 0.0.0.0` 不可用**：上游明确拒绝通配地址；必须绑定具体 IP。
2. **直接把 3080 发布到 LAN/公网**：Host/Origin 栅栏、token 泄露、Docker 绕过 DSM 防火墙，三条都不可接受。
3. **Rootless 容器**：Container Manager 没有 rootless 模式；容器默认 root，只有 `user:` 能降权。
4. **原生 SPK 装 root 守护进程 / 绑 80、443**：DSM 7 强制包用户，systemd 只认 `pkg-*` 单元；非 root 不能绑低端口，用 3080/8443 + 反代。
5. **包写 FHS 之外的路径**：权限/AppArmor 会拦；工作区必须走共享文件夹或卷。
6. **指望 Package Center 提供 Node 24**：当前最高 v22；只能自带或容器化。
7. **armv7/老 ARM 机型**：没有 Container Manager，也没有 Node 24 官方 armv7 二进制；不支持。
8. **无审核直接上架 Package Center**：需要开发者协议与安全审核；dsh 的 shell 面是硬伤。
9. **QuickConnect 反代自定义域名**：QuickConnect 不是通用反代；远程只能 VPN/DDNS + 端口映射（且超出本地范围）。
10. **一个 Host 多用户共用 / DSM 登录当 SSO**：dsh 是单用户内核，也没有内置 DSM SSO；多用户要一用户一容器，SSO 要自研 launcher。
11. **子路径反代不剥前缀**：dsh 会 404/403；用独立域名，或自己写 rewrite。
12. **国内网络直连 ghcr.io/Docker Hub**：经常失败；需镜像加速、私有 registry 或离线 tar 导入。

---

## 9. 开放问题

1. 目标机型矩阵：先 x86_64，还是必须覆盖 DS223/DS124 这类 ARM？
2. Container Manager 能否作为硬前提？如果客户拒绝 Docker，是否值得为 B 投 3 个月？
3. 首启 token 怎么交给非技术用户：改 dsh 增加 token 文件/一次性 launcher，还是接受“从日志复制”？
4. 单用户是否够？多用户是否要一用户一容器？
5. 工作区位置与 UID/ACL 策略谁负责？MVP 是否内置 Python/Office（镜像会涨到 2–3 GB）？
6. 国内分发：镜像放哪、是否提供离线包、是否做 registry 镜像；官方 Package Center 还是 GitHub/手动 SPK？
7. ARM 性能是否满足“可用的 agent”？需要实测编译/索引任务。
8. 容器重启后 cookie 是否仍有效（签名密钥是否持久化）？若失效，每次重启都要重新取 token。
9. `home/` 里的 credentials 是否要额外加密？DSM 快照/Hyper Backup 会复制它。
10. DSM 7.3 的包/容器策略变化由谁跟踪？

---

## 10. 下一步实验

| # | 实验 | 工期 | 出口标准 |
|---|---|---|---|
| E1 | 构建 amd64/arm64 镜像，跑 Node 24 + dsh + 原生模块 | 3 天 | 两架构都能 `dsh web`、bash/rg、node-pty、sqlite |
| E2 | DSM 反代：HTTPS、WebSocket、Host/Origin、cookie | 2 天 | 浏览器可聊天，WS 不断，无 403 |
| E3 | 首启 token：日志提取 + cookie 持久化 + launcher 原型 | 3 天 | 非技术用户 3 步内进入 UI |
| E4 | UID/ACL 矩阵：PUID/PGID、共享文件夹、File Station | 2 天 | 用户能在 File Station 编辑工作区文件 |
| E5 | 资源限制：2 GB/4 GB、OOM、重任务 | 2 天 | 不拖垮 NAS，OOM 有可读日志 |
| E6 | SPK hello-world：包用户、端口、data-share、图标 | 5 天 | DSM 7.2 虚拟机可安装/启动/卸载 |
| E7 | SPK 内置 Node 24 + dsh，验证 AppArmor | 5 天 | 能起 Host；记录所有 deny |
| E8 | 混合 D：SPK + docker-project + 反代 | 5 天 | 一键安装后可直接打开 UI |
| E9 | 升级/回滚/备份恢复 | 2 天 | 旧版本可回滚，数据不丢 |

建议顺序：E1 → E2 → E3 → E4/E5 并行 → 再决定 E6–E8。**E1/E2 不通过，后面的 SPK 都不用做。**

---

## 11. 来源

- [Synology Package Developer Guide（DSM 7.2.2）](https://help.synology.com/developer-guide/)：[SPK 结构](https://help.synology.com/developer-guide/synology_package/introduction.html)、[INFO 必填](https://help.synology.com/developer-guide/synology_package/INFO_necessary_fields.html)/[可选](https://help.synology.com/developer-guide/synology_package/INFO_optional_fields.html)、[生命周期脚本](https://help.synology.com/developer-guide/synology_package/scripts.html)
- [Privilege（DSM 7 降权）](https://help.synology.com/developer-guide/privilege/preface.html) / [包 FHS](https://help.synology.com/developer-guide/integrate_dsm/fhs.html) / [端口注册](https://help.synology.com/developer-guide/integrate_dsm/ports.html)
- [Docker worker](https://help.synology.com/developer-guide/resource_acquisition/docker.html) / [Docker Project worker](https://help.synology.com/developer-guide/resource_acquisition/docker-project.html) / [Web Service（reverse_proxy）](https://help.synology.com/developer-guide/resource_acquisition/web_service.html) / [Data Share](https://help.synology.com/developer-guide/resource_acquisition/data_share.html)
- [平台/架构映射](https://help.synology.com/developer-guide/appendix/platarchs.html) / [上架审核清单](https://help.synology.com/developer-guide/appendix/publication_review.html) / [DSM 7 不再需要签名](https://help.synology.com/developer-guide/toolkit/sign_package.html)
- [Container Manager 产品页](https://www.synology.com/en-global/dsm/feature/container-manager)
- [Container Manager 24.0.2-1707（armv8/x86_64 SPK）](https://archive.synology.com/download/Package/ContainerManager/24.0.2-1707)
- [Node.js v22.23.4-1011（最新可用 Node 包）](https://archive.synology.com/download/Package/Node.js_v22/22.23.4-1011)
- [dsh Web App 部署说明](https://github.com/deepseek-ai/deepseek-harness/tree/master/packages/bundle/web-app)

## 原型验证（2026-11-08）

已落地 [本项目](../) 的 Compose 原型：

- 镜像：`node:24-bookworm-slim` + dsh 0.2.2-rc.1 + pnpm + ripgrep，非 root 用户；
- 容器内 `dsh web --host <bridge-ip> --port 3080 --no-open`，规避 dsh 拒绝 `0.0.0.0`；
- Compose 只发布 `127.0.0.1:3080`，给 DSM 反代使用；
- 本机 arm64 Docker 实测：容器启动、`GET /` 无 cookie 返回 401、token 换 cookie 后 303→200，UI HTML 约 40 KB。

2026-11-08 补充：arm64 与 amd64 镜像均已在 Docker 构建；amd64 用 DaoCloud 镜像源按 digest 拉取
`node:24-bookworm-slim-amd64`，容器内 `dsh web` 未认证 401、token 303、认证后 200（见
[`evidence/amd64-image.txt`](../evidence/amd64-image.txt)）。
仍未验证：DSM 真机 Container Manager、DSM 反代 TLS/WebSocket、DSM 防火墙、首启 token 交付。下一步是 E4/E5（UID/ACL、资源限制）与 SPK 最小外壳。

## 2026-11-09：SPK scaffold

已加入 [`spk/`](../spk/) 最小外壳：
`INFO`、`package.tgz`、`conf/privilege`、`start-stop-status`，`start/stop` 调
`docker compose up/down`。已在主机验证 SPK tar 结构与脚本语法，但**未在 DSM 真机安装**，
因此仍不能视为可发布包。下一步是把 `run-as: root` 改为 `docker-project` worker，
并用真机验证端口、反代、升级和 token 交付。
