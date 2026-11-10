# DSHD for Synology DSM（SPK）

面向 DSM 7.2 的独立 Synology 包项目：用 Container Manager + Docker Compose
运行 headless dsh，再由原生 SPK 提供套件中心安装、启停、端口注册、首启 token
交付和卸载清理。

> **状态：0.2.0 已实现、可构建、通过本地结构与生命周期冒烟检查，但没有在 DSM
> 真机安装/启动/升级/卸载验证。** 详见 [未验证项](#未验证项) 与
> [docs/spk.md](docs/spk.md)。不要把它当成已发布的包。

## 目录

```
Dockerfile / entrypoint.sh       headless dsh 镜像原型
docker-compose.yml               独立 Compose 原型（开发/手工部署）
spk/                             主 SPK 包（实现版，0.2.0）
  INFO                           包元数据
  PACKAGE_ICON.PNG               72x72 图标
  PACKAGE_ICON_256.PNG           256x256 图标
  conf/                          privilege、resource、Web Service 候选
  package/                       package.tgz 内容：compose、配置模板、端口文件
  scripts/                       生命周期、token、installer
  tools/                         图标生成与 PNG 尺寸检查（不打包）
  build-spk.sh                   构建 dist/dshd-0.2.0.spk
spk-docker-project/              实验性 docker-project worker 变体
scripts/check-spk.sh             构建两个包并做本地全量检查
scripts/test-spk-lifecycle.sh    用假 Docker CLI 冒烟测试启停/token 逻辑
docs/                            设计与测试文档
evidence/                        本机验证记录
dist/                            本地 SPK 产物（gitignore）
```

## 快速开始

### 1. 构建/导入镜像

镜像 tag 默认 `dshd-synology:0.2.0`，与 SPK 的 `config.env` 一致。

```bash
# 在 x86_64 NAS 或构建机上（armv8 NAS 用 linux/arm64）
docker build --platform linux/amd64 -t dshd-synology:0.2.0 .

# 无 NAS 构建环境时：导出后导入
docker save dshd-synology:0.2.0 | gzip > dshd-image-0.2.0.tar.gz
# NAS 上（SSH）
docker load < dshd-image-0.2.0.tar.gz
```

也可以在 Container Manager → 映像 → 新增 → 从文件导入 tar/tar.gz。

### 2. 构建并检查 SPK

```bash
./spk/build-spk.sh          # 输出 dist/dshd-0.2.0.spk
scripts/check-spk.sh        # 本地结构 + 生命周期检查；应输出 all SPK checks OK
```

`make all` 会先把两个变体构建到 `dist/`，再运行 `scripts/check-spk.sh` 对全新构建做检查。

### 3. 在 DSM 安装

- **Package Center → 手动安装**：选择 `dist/dshd-0.2.0.spk`；
- 或 SSH：`sudo synopkg install /volume1/.../dshd-0.2.0.spk`。

安装后 `postinst` 会：

- 创建 `/var/packages/dshd/var/config.env`（首次安装，之后不覆盖）；
- 创建 `DSHD_DATA_DIR/home` 与 `DSHD_WORKSPACE_DIR`；
- 尝试建立 `/usr/local/bin/dshd-token` → `/var/packages/dshd/scripts/token`。

### 4. 配置公开地址

```bash
sudo vi /var/packages/dshd/var/config.env
```

至少确认镜像 tag、数据目录和访问地址：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `DSHD_IMAGE` | `dshd-synology:0.2.0` | 必须已在 NAS 本地存在；启动前会检查，缺失则失败 |
| `DSHD_PORT` | `3080` | 发布到 NAS loopback 的宿主端口 |
| `DSHD_DATA_DIR` | `/volume1/docker/dshd` | dsh home 的宿主目录，必须备份；须在 `/volume*` 或包 var 下 |
| `DSHD_WORKSPACE_DIR` | `/volume1/dshd-workspace` | `/workspace` 的宿主目录，必须备份；限制同上 |
| `DSH_PUBLIC_URL` | `http://127.0.0.1:3080` | 打印在 token URL 里的公开 origin |
| `DSH_TRUSTED_HOST` | `127.0.0.1` | dsh Host/Origin 栅栏允许的 authority |
| `DSHD_PUID` / `DSHD_PGID` | `1001` | 数据目录宿主 owner；当前镜像固定以 1001 运行 |
| `DSHD_START_TIMEOUT` | `90` | 等待 token 的秒数 |

直连（SSH 隧道）可保持 `127.0.0.1`；走 DSM 反向代理时，把 `DSH_PUBLIC_URL`
设为完整 HTTPS origin（如 `https://dsh.example.net`），`DSH_TRUSTED_HOST` 设为
同一域名（不带 scheme/端口），两者必须匹配。

### 5. 启动并取 token

Package Center 启动套件，或：

```bash
sudo synopkg start dshd
sudo /var/packages/dshd/scripts/token    # 也可是 sudo dshd-token
```

`start-stop-status` 会执行 `docker compose up -d`，轮询容器日志，找到
`dsh web: https://.../?token=...` 后写入：

```
/var/packages/dshd/var/token-url.txt   # root:root, 0600
```

**token 缺失时启动会返回失败**（不会伪造成功）；容器会保留用于诊断。检查：

```bash
sudo docker compose \
  --env-file /var/packages/dshd/var/config.env \
  -f /var/packages/dshd/target/package/docker-compose.yml \
  logs dshd
```

### 6. DSM 反向代理（推荐入口）

控制面板 → 登录门户 → 高级 → 反向代理 → 新增：

- 来源：HTTPS，`dsh.example.net`，443（使用 DSM 证书）；
- 目的地：HTTP，`127.0.0.1`，`3080`；
- 自定义标题 → **WebSocket**。

`config.env` 中设置 `DSH_PUBLIC_URL=https://dsh.example.net` 与
`DSH_TRUSTED_HOST=dsh.example.net`，重启套件。不要把 3080 暴露到 LAN/公网。

## 包结构

```text
dshd-0.2.0.spk (tar)
├── INFO
├── PACKAGE_ICON.PNG          72x72
├── PACKAGE_ICON_256.PNG      256x256
├── package.tgz
│   └── package/
│       ├── docker-compose.yml
│       ├── config.env.example
│       └── port_conf/dshd.sc
├── conf/
│   ├── privilege             package 默认；生命周期脚本 root
│   ├── resource              端口注册
│   └── resource.webservice.example.json  （不打包，候选）
└── scripts/
    ├── start-stop-status
    ├── token
    ├── installer
    ├── postinst
    └── preuninst
```

## 权限模型

- `defaults.run-as = "package"`：包文件与普通脚本默认以 `dshd` 包用户运行；
- `ctrl-script` 仅对 `postinst`、`preuninst`、`start`、`stop`、`status`
  使用 root。

原因：Container Manager 的 Docker socket 由 root 拥有。另一种做法是把包用户加入
`docker` 组，但该组等价于 root，且是**持久**授权；相比之下，把权限限制在几个
短生命周期控制脚本更小。`postinst` 需要 root 创建共享目录外的数据目录和可选
`/usr/local/bin` 链接；`preuninst` 需要 root 停止容器并移除该链接。
`start-stop-status` 解析 `config.env` 时
只按 `KEY=value` 读取并校验白名单键，**不会 source/执行**该文件，避免包用户借配置
注入 root 命令。

`spk-docker-project/` 变体不执行 Docker CLI，`startable="no"`，把生命周期交给
Container Manager 的 `docker-project` worker；它仍是实验候选，见
[spk-docker-project/README.md](spk-docker-project/README.md)。

## 端口与反向代理资源

- `conf/resource` 注册 `port-config.protocol-file = port_conf/dshd.sc`；
- `dshd.sc` 声明 `3080/tcp`，`port_forward="no"`（不应做路由器端口映射）；
- 端口注册让 DSM 防火墙界面能识别 DSHD，**不代表**已在真机验证。

DSM 7 的 Web Service `reverse_proxy` worker 需要 WebStation，且门户域名/TLS/Host
栅栏行为未在真机确认，因此没有放进活动 `conf/resource`。候选配置在
[spk/conf/resource.webservice.example.json](spk/conf/resource.webservice.example.json)，
字段依据官方 Web Service 文档；合并前必须真机验证。当前推荐路径仍是控制面板手工
反向代理。

## 卸载与数据

`preuninst` 先 best-effort 停止 Compose 项目，再删除 `token-url.txt`、`status`
和 `/usr/local/bin/dshd-token` 链接，**默认保留**：

- `/var/packages/dshd/var/config.env`（升级时复用；整包卸载后 DSM 可能删除包 var）
- `DSHD_DATA_DIR`（dsh home，始终保留）
- `DSHD_WORKSPACE_DIR`（工作区，始终保留）

彻底清除需管理员显式执行：

```bash
sudo rm -rf /volume1/docker/dshd /volume1/dshd-workspace
```

## 本地验证

```bash
make all
# 或 scripts/check-spk.sh
```

检查内容：SPK tar 成员、INFO 必填键/固定值、图标尺寸、`package.tgz` 内容、
`conf/privilege`/`resource` JSON、`.sc` 端口、脚本可执行位与 `sh -n`、
`docker compose config` 渲染、无 `example.com` 默认值，以及用假 Docker CLI 跑
start/status/stop/token 和“无 token 必须失败”的冒烟测试。

已验证（2026-11-10，本机 macOS/Docker，**非 DSM**）：

```text
== dshd-0.2.0.spk
  ... structure OK
== dshd-docker-project-0.2.0.spk
  ... structure OK
== lifecycle smoke (fake Docker CLI)
lifecycle smoke OK
all SPK checks OK
```

镜像层已有的本机验证（401 / token 303 / 认证 200、arm64 与 amd64 构建）见
[evidence/](evidence/) 与 [docs/testing.md](docs/testing.md)。

## 未验证项

**没有 DSM 硬件测试。** 以下必须在真机确认：

1. DSM 7.2 接受 `version="0.2.0"`（官方文档建议 `feature-build` 形式）。
2. Package Center 安装/升级/卸载，`ctrl-script` 的 root 身份与 `postinst`/
   `preuninst` 调用顺序。
3. Container Manager 提供的 `docker` 路径、Compose v2 插件与 `docker compose`
   子命令（脚本有候选路径与 `docker-compose` 回退，但未实测）。
4. `conf/resource` 端口注册在防火墙/端口转发 UI 中可见。
5. `conf/privilege` 的 `postinst`/`preuninst` root 条目被接受。
6. 首启日志格式、`--no-log-prefix` 兼容性、token 提取与文件权限。
7. `docker compose config` 的 `name:` 顶层字段在 Container Manager 版本中可用。
8. 数据目录 uid/gid 1001 与 DSM 用户/ACL/File Station 的实际显示和写权限。
9. 反向代理 TLS/WebSocket、Host/Origin 栅栏、cookie 行为。
10. 套件图标尺寸/显示、`/usr/local/bin/dshd-token` 链接是否符合 Package Center
    策略。
11. Web Service `reverse_proxy` 候选（未启用）。
12. 升级保留 `config.env`/数据、回滚、卸载残留检查、资源限制与日志轮转。

## 文档

- [docs/spk.md](docs/spk.md)：SPK 设计、权限、token、资源、安装/升级/卸载细节
- [docs/testing.md](docs/testing.md)：本地检查、假 Docker 冒烟、真机检查清单
- [docs/synology-app.md](docs/synology-app.md)：DSM 应用化路线研究
- [spk/README.md](spk/README.md)：包内实现与命令速查
- [spk-docker-project/README.md](spk-docker-project/README.md)：实验变体
