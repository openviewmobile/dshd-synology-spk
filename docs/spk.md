# DSM 7 SPK 实现（0.2.0）

> **范围**：`spk/` 是主实现；`spk-docker-project/` 是实验变体。
> **验证状态**：本地结构/脚本/Docker Compose 渲染检查通过；**没有 DSM 真机测试**。
> 文中标注“未验证”的条目不能当作已工作。

## 1. 目标与边界

在 DSM 7.2+ 的 Container Manager 上运行 headless dsh 容器，SPK 负责：

- Package Center 安装/升级/卸载；
- 套件启停与 `status`；
- Docker/Compose 定位、数据目录初始化；
- 首启 token URL 提取到稳定文件，并提供 `token` 命令；
- 端口注册（防火墙界面可识别）；
- 卸载时只清理运行态，不默认删除用户数据。

SPK **不**把 Node/dsh 装进 DSM 系统 Node；运行时仍在容器里。原生 Node 方案受
DSM Node 版本（当前最高 v22）和原生模块限制，不作为首选。

## 2. 包结构

```text
dshd-0.2.0.spk (tar)
├── INFO
├── PACKAGE_ICON.PNG                 72x72，RGBA
├── PACKAGE_ICON_256.PNG             256x256，RGBA
├── package.tgz
│   └── package/
│       ├── docker-compose.yml       参数化 Compose
│       ├── config.env.example       运行时配置模板
│       └── port_conf/dshd.sc        端口注册文件
├── conf/
│   ├── privilege                    package 默认 + ctrl-script root
│   ├── resource                     port-config
│   └── resource.webservice.example.json  候选，不打包
└── scripts/
    ├── start-stop-status
    ├── token
    ├── installer                    postinst/preuninst 共用实现
    ├── postinst
    └── preuninst
```

`package.tgz` 解包到 `/var/packages/dshd/target`，因此路径为
`/var/packages/dshd/target/package/docker-compose.yml`。SPK 根目录的
`scripts/` 安装到 `/var/packages/dshd/scripts/`。

### 2.1 INFO

关键字段：

```ini
package="dshd"
version="0.2.0"
displayname="DSHD"
description="DeepSeek Harness (dsh) web agent ..."
maintainer="DSHD project"
distributor="DSHD project"
support_center="no"
arch="x86_64 armv8"
os_min_ver="7.2-64570"
startable="yes"
ctl_stop="yes"
support_conf_folder="yes"
category="productivity"
checkport="yes"
```

说明：

- `arch` 同时列 `x86_64 armv8`。包本身只含脚本/compose，不含原生二进制，镜像
  另行按 arch 构建/导入，因此一个 SPK 可覆盖两类机型；**这不等于镜像可跨 arch**。
- `support_conf_folder` 在 DSM 6+ 已废弃，但按项目要求保留为 `yes`，避免旧
  Package Center 兼容性回归。
- `version="0.2.0"` 是项目要求；官方文档建议 `feature-build`（如
  `0.2.0-0001`）形式。DSM 7.2 是否接受纯三段版本**未验证**。
- `support_center="no"`：没有 Synology Support Center 集成。
- `category="productivity"` 的值未在真机 Package Center 校验。

### 2.2 图标

由 [spk/tools/gen-icons.py](../spk/tools/gen-icons.py) 用纯 Python 标准库生成
（4x 超采样后 box filter），不依赖 Pillow/ImageMagick。设计是深色圆角终端卡片 +
青色提示符 + 绿色光标 + 层叠 NAS/容器意象。

```bash
make icons
# 重新生成 72x72 / 256x256，并同步 spk-docker-project/
```

构建脚本和 `scripts/check-spk.sh` 会解析 PNG IHDR 校验尺寸。

## 3. 权限模型

`conf/privilege`：

```json
{
  "defaults": { "run-as": "package" },
  "ctrl-script": [
    { "action": "postinst",  "run-as": "root" },
    { "action": "preuninst", "run-as": "root" },
    { "action": "start",     "run-as": "root" },
    { "action": "stop",      "run-as": "root" },
    { "action": "status",    "run-as": "root" }
  ]
}
```

### 为什么需要 root

Container Manager 的 Docker socket（通常是 `/var/run/docker.sock`）归 root 所有，
`docker compose` 需要访问它。可选方案：

| 方案 | 授权范围 | 持久性 | 结论 |
|---|---|---|---|
| `ctrl-script` 以 root 跑 start/stop/status | 仅 5 个控制脚本 | 短生命周期 | **采用** |
| 包用户加入 `docker` 组 | 等价 root（可挂载宿主 `/`） | 持久 | 拒绝 |
| 每个动作 `sudo` | DSM 脚本环境不保证可用 | — | 不可靠 |
| `docker-project` worker | 交给 Container Manager | 持久 worker | 实验变体 |

取舍：root 控制脚本仍是高权限面。为缩小风险：

- 只有 `postinst`/`preuninst`/`start`/`stop`/`status` 提权，包内其他文件以
  `package` 运行；
- `start-stop-status` **不 source** `config.env`，而是按 `KEY=value` 解析白名单
  键并校验类型/绝对路径，避免包用户通过可写配置注入 root 命令；
- 脚本不执行用户提供的命令，只调用固定路径的 `docker compose`；
- 不把 `docker` 组授予包用户。

`postinst` 需要 root 来在包目录外创建数据目录和 `/usr/local/bin/dshd-token`
链接；`preuninst` 需要 root 停止 Compose 项目并移除该链接。

> 未验证：DSM 7.2 是否接受 `ctrl-script` 中的 `postinst`/`preuninst` root 条目；
> 官方文档列出这些 action，但真机行为未测。

## 4. 生命周期

### 4.1 `scripts/start-stop-status`

DSM 调用参数：`start`、`stop`、`status`、`prestart`、`prestop`。`prestart`/
`prestop` 直接返回 0。

`start` 流程：

1. 读取/创建 `/var/packages/dshd/var/config.env`；
2. 解析并校验配置；
3. 定位 Docker（候选顺序）：
   - `$DSHD_DOCKER`
   - `/usr/local/bin/docker`
   - `/usr/bin/docker`
   - `/var/packages/ContainerManager/target/usr/bin/docker`
   - `command -v docker`
4. 验证 `docker compose version`；失败则找 `docker-compose` 可执行文件；
5. 创建 `$DSHD_DATA_DIR/home`、`$DSHD_WORKSPACE_DIR`，root 运行时把顶层目录
   chown 到 `DSHD_PUID:DSHD_PGID`（默认 1001:1001，不递归）；
6. 若容器已在运行：重新从日志提取最新 token（不信任可能过期的 token 文件）；
7. 检查本地镜像存在（`docker image inspect`）；缺失则失败，避免 Compose
   静默拉取意外 tag；
8. `docker compose up -d --remove-orphans`；
9. 轮询容器 ID/运行状态和日志，等待形如
   `dsh web: https://host/?token=...` 的 URL；
10. 写入 `token-url.txt`（0600）和 `status`（0600），返回 0。

**token 缺失时返回 1，不伪造成功。** 容器保留用于诊断；`status` 仍会显示运行中。

`stop`：

- `docker compose down --remove-orphans`（不删 bind mount 数据）；
- 删除 `token-url.txt` 和 `status`，写 `state=stopped`；
- 若 Docker 已不可用（关机阶段），只清理本地运行态并返回 0，避免阻塞关机。

`status`：容器运行返回 0，否则返回 3（DSM 约定）。Docker 不可用也返回 3。

### 4.2 `scripts/token`

```bash
sudo /var/packages/dshd/scripts/token
sudo dshd-token        # postinst 尝试创建的链接
```

读取 `/var/packages/dshd/var/token-url.txt` 并输出到 stdout。文件 0600 root，
非 root 用户会收到用 `sudo` 的提示。URL 含 bearer credential，按密码处理。

### 4.3 `scripts/installer`

`postinst` → `installer init`：

- 创建 `var/`；
- 首次复制 `config.env.example` → `config.env`，已存在则保留；
- 创建数据/工作区目录，按 `DSHD_PUID/PGID` 设置顶层 owner；
- 尝试 `ln -sfn ... /usr/local/bin/dshd-token`（失败不阻塞安装）。

`preuninst`：

1. 以 best-effort 执行 `start-stop-status stop`（Docker 不可用或配置损坏时忽略
   失败），确保卸载后不会留下容器；
2. 调用 `installer cleanup`：删除 token/status/temp 文件和指向本包的
   `/usr/local/bin/dshd-token` 链接；
3. **保留** `config.env`、dsh home、workspace。

## 5. 配置与 Compose

`config.env` 位于 `/var/packages/dshd/var/config.env`，由 `start-stop-status`
以 `--env-file` 传给 Compose。模板见
[spk/package/config.env.example](../spk/package/config.env.example)。

数据/工作区目录必须是绝对路径，位于 `/volume*` 或包 var 目录下，且不能含 `..`。
这避免被篡改的配置让 root 脚本在 `/etc` 等系统路径创建目录或 chown；配置解析本身也
不执行 shell。

`package/docker-compose.yml` 的关键点：

```yaml
name: dshd-spk
services:
  dshd:
    image: ${DSHD_IMAGE:-dshd-synology:0.2.0}
    container_name: dshd-spk
    init: true
    restart: unless-stopped
    ports:
      - "127.0.0.1:${DSHD_PORT:-3080}:3080"
    volumes:
      - ${DSHD_DATA_DIR:-/volume1/docker/dshd}/home:/home/dsh
      - ${DSHD_WORKSPACE_DIR:-/volume1/dshd-workspace}:/workspace
    environment:
      DSH_BIND_HOST: ""
      DSH_PUBLIC_URL: ${DSH_PUBLIC_URL:-http://127.0.0.1:3080}
      DSH_TRUSTED_HOST: ${DSH_TRUSTED_HOST:-127.0.0.1}
```

- 默认值全部 loopback，不含 `example.com`；
- Compose 只发布到 `127.0.0.1`，TLS 由 DSM 反代终止；
- `DSH_BIND_HOST` 留空，容器 entrypoint 用 bridge IP 绑定（dsh 拒绝 `0.0.0.0`）；
- `DSH_PUBLIC_URL`/`DSH_TRUSTED_HOST` 必须与反代域名一致；
- 数据目录为 bind mount，卸载不删除。

`docker compose config` 在本地检查中会渲染此文件并断言镜像 tag、loopback 端口、
公开 URL 和无 `example.com`。

## 6. 端口注册

`conf/resource`：

```json
{
  "port-config": {
    "protocol-file": "port_conf/dshd.sc"
  }
}
```

`package/port_conf/dshd.sc`：

```ini
[dshd_web]
title="DSHD"
desc="DSHD web UI (loopback only; expose it through a reverse proxy)"
port_forward="no"
dst.ports="3080/tcp"
```

官方 Port 文档的示例把 `.sc` 放在 target-relative 路径（如
`port_conf/xxdns.sc`），因此文件放在 `package.tgz` 的 `package/port_conf/`。
`port_forward="no"` 表示不在路由器端口转发列表推荐，但仍应在防火墙 UI 显示应用。

> 未验证：DSM 7.2 的防火墙/端口转发界面是否正确读取该 `protocol-file` 路径，
> 以及 `checkport="yes"` 对 3080 的冲突检查行为。

## 7. 反向代理 / Web Service（候选，未启用）

### 7.1 推荐：DSM 控制面板手工反代

控制面板 → 登录门户 → 高级 → 反向代理：

- 来源 `https://<domain>:443`，绑定 DSM 证书；
- 目的地 `http://127.0.0.1:3080`；
- 自定义标题启用 WebSocket；
- `config.env` 的 `DSH_PUBLIC_URL` / `DSH_TRUSTED_HOST` 指向同一域名。

这是当前文档推荐路径，因为 DSM 内置 nginx 由控制面板管理，不依赖 WebStation。

### 7.2 候选：`webservice` worker

[spk/conf/resource.webservice.example.json](../spk/conf/resource.webservice.example.json)
给出一个完整的 `webservice` 资源候选：

```json
{
  "webservice": {
    "services": [{
      "service": "dshd",
      "display_name": "DSHD",
      "support_alias": true,
      "support_server": false,
      "type": "reverse_proxy",
      "proxy_target": "http://127.0.0.1:3080",
      "proxy_headers": [
        { "name": "Host", "value": "$host" },
        { "name": "Upgrade", "value": "$http_upgrade" },
        { "name": "Connection", "value": "$connection_upgrade" }
      ],
      "proxy_http_version": 1,
      "connect_timeout": 60,
      "read_timeout": 3600,
      "send_timeout": 3600
    }],
    "portals": [{
      "service": "dshd", "name": "DSHD", "type": "alias", "alias": "dshd"
    }],
    "pkg_dir_prepare": []
  }
}
```

字段依据官方 Web Service（DSM 7.0+）文档；`pkg_dir_prepare` 在该 worker 中是
required 数组，因此给空数组。**没有放进活动 `conf/resource`**，因为：

- `webservice` worker 由 WebStation 提供，SPK 未声明/验证该依赖；
- alias portal 的实际主机名、TLS 证书、Host 头转发与 dsh 的 Host/Origin 栅栏
  未在真机确认；
- dsh 的 token URL 必须与公开 origin 一致，portal 生成的地址未必匹配。

合并前必须真机验证，并确保 `DSH_TRUSTED_HOST` 与实际访问域名一致。

## 8. 构建、安装、升级、卸载

### 构建

```bash
./spk/build-spk.sh
# dist/dshd-0.2.0.spk
```

构建脚本会：

- 解析 `INFO`，校验 `package`/`version` 格式和必填键；
- 检查全部必需文件、图标尺寸、JSON、`.sc`、脚本语法；
- 拒绝 `package/` 或默认配置中出现 `example.com`；
- 生成 `package.tgz`（成员以 `package/` 为根）和 SPK 根成员。

`spk-docker-project/build-spk.sh` 生成
`dist/dshd-docker-project-0.2.0.spk`，仅用于实验。

### 安装前

1. DSM 7.2+，Container Manager 已安装并启动；
2. 镜像已导入：`docker image inspect dshd-synology:0.2.0`；
3. 数据/工作区父目录存在或可创建；
4. 若走反代，域名已解析且证书已绑定。

### 安装

Package Center → 手动安装 → `dist/dshd-0.2.0.spk`；或：

```bash
sudo synopkg install /volume1/.../dshd-0.2.0.spk
sudo synopkg start dshd
sudo /var/packages/dshd/scripts/token
```

### 升级

DSM 顺序（文档）：stop old → preupgrade new → preuninst old → postuninst old →
preinst new → postinst new → postupgrade new → start new。

本包没有 `preupgrade`/`postupgrade`；`postinst` 保留已有 `config.env`，因此升级
不会覆盖用户配置。新增配置键由 `start-stop-status` 的内置默认值兜底。数据目录
不变。

> 未验证：升级时 `preuninst` 是否在 old target 仍存在时运行、配置保留、回滚。

### 卸载

`preuninst` 只清 token/status/链接，保留配置与数据。彻底删除：

```bash
sudo rm -rf /volume1/docker/dshd /volume1/dshd-workspace
```

> 未验证：DSM 是否在 uninstall 后自动删除 `/var/packages/dshd/var`（即使删除，
> 数据目录仍保留）；Package Center 的“删除套件设置”行为。

## 9. 未验证清单

**没有 DSM 真机测试。** 至少需要确认：

- [ ] Package Center 接受 SPK（tar 格式、INFO 字段、纯三段版本）。
- [ ] `ctrl-script` 的 postinst/preuninst/start/stop/status root 身份生效。
- [ ] Container Manager 的 `docker`/Compose v2 路径与 `--env-file`、
      `--no-log-prefix`、`--remove-orphans` 兼容。
- [ ] `image inspect` 预检查不会误伤已导入镜像。
- [ ] token 日志格式、提取、权限、`sudo dshd-token`。
- [ ] 端口注册在防火墙 UI 可见；`port_forward="no"` 行为正确。
- [ ] 反代 TLS/WebSocket/Host/Origin/cookie 链路。
- [ ] `webservice` 候选（如启用）。
- [ ] 数据目录 1001:1001 与 DSM 用户/ACL/File Station。
- [ ] 图标显示、`/usr/local/bin` 链接策略。
- [ ] 升级/回滚/卸载残留/资源限制/日志轮转。
- [ ] `spk-docker-project` 的 worker 版本、compose 路径、镜像预载。

## 10. 参考

- Synology Package Developer Guide：SPK 结构、INFO、scripts、privilege、Port、
  Web Service、Docker Project。
- [spk/tools/gen-icons.py](../spk/tools/gen-icons.py)、
  [spk/build-spk.sh](../spk/build-spk.sh)、
  [scripts/check-spk.sh](../scripts/check-spk.sh)。
