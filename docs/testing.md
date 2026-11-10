# Synology 测试

## 0. 结论

- 本地可验证：SPK 打包结构、INFO、图标、package.tgz、Compose 渲染、脚本语法、
  启停/token 控制流（假 Docker CLI）。
- **不可本地替代**：DSM 真机安装/启动/停止/升级/卸载、Container Manager 的
  Docker 路径与 Compose 版本、端口注册 UI、DSM 反代 TLS/WebSocket、ACL。
- 目前**没有进行任何 DSM 硬件测试**。

## 1. 全量本地检查

```bash
make all
# 先构建 dist/ 下的两个变体，再运行 scripts/check-spk.sh 做检查
```

预期检查段输出（2026-11-10，macOS，Docker 29.9.2 / Compose v5.6.1；`make all` 前面还会打印两个构建路径）：

```text
== dshd-0.2.0.spk
  ok: dshd-0.2.0.spk: SPK members
  ok: dshd-0.2.0.spk: INFO keys/values
  ok: dshd-0.2.0.spk: icon dimensions
  ok: dshd-0.2.0.spk: scripts executable and shell syntax
  ok: dshd-0.2.0.spk: JSON config and port registration
  ok: dshd-0.2.0.spk: package.tgz contents
  ok: dshd-0.2.0.spk: docker compose config
structure OK
== dshd-docker-project-0.2.0.spk
  ok: dshd-docker-project-0.2.0.spk: icon dimensions
structure OK
== lifecycle smoke (fake Docker CLI)
lifecycle smoke OK
all SPK checks OK
```

### 检查项明细

| 检查 | 实现 |
|---|---|
| SPK tar 成员 | `INFO`、`package.tgz`、`conf/privilege`、`conf/resource`、5 个 scripts、两个图标；禁止 `package/` 出现在 SPK 根 |
| INFO | 必填键非空；`package=dshd`、`version=0.2.0`、`arch="x86_64 armv8"`、`os_min_ver=7.2-*`、`startable/ctl_stop/support_conf_folder=yes`、`support_center=no` |
| 图标 | 解析 PNG IHDR：72x72 与 256x256 |
| package.tgz | 含 `package/docker-compose.yml`、`package/config.env.example`、`package/port_conf/dshd.sc`；无 `.DS_Store` |
| JSON | `conf/privilege`、`conf/resource` 可解析；privilege 为 package 默认、5 个 action root；resource 引用 `port_conf/dshd.sc` |
| 端口文件 | `[dshd_web]`、`dst.ports="3080/tcp"` |
| 脚本 | 5 个脚本可执行且 `sh -n` 通过 |
| Compose | 变量参数化；默认无 `example.com`；`docker compose --env-file ... config` 渲染成功；断言 image tag、`host_ip: 127.0.0.1`、`DSH_PUBLIC_URL` |
| 生命周期 | 假 Docker CLI 跑 start/status/stop/token，并验证无 token 时 start 非零退出 |

如果本机没有 Docker/Compose，Compose 渲染会打印 `WARN` 并跳过；其他检查仍会执行。
这不是完整验证，CI/发布前应在有 Docker 的环境跑。

## 2. 生命周期冒烟（假 Docker）

```bash
scripts/test-spk-lifecycle.sh dist/dshd-0.2.0.spk
# lifecycle smoke OK
```

做法：

1. 解包 SPK 和 `package.tgz` 到临时目录；
2. 写一个只实现本包所需子命令的假 `docker`：
   `compose version`、`compose up/down/ps/logs`、`inspect`、`image inspect`；
3. 用临时 `config.env`（数据目录、4 秒超时）运行
   `SYNOPKG_PKGDEST=... SYNOPKG_PKGVAR=... DSHD_DOCKER=<fake> start`；
4. 断言：

   - `token-url.txt` 内容等于假日志里的 URL；
   - `status` 文件 `state=running`，`status` 动作返回 0；
   - `stop` 后 token 文件删除、`state=stopped`、`status` 返回 3；
   - token 命令在无文件时失败、有文件时输出 URL；
   - 假日志没有 token 时 `start` 返回非 0、**不生成 token 文件**、状态 `failed`。

**局限**：假 Docker 不验证真实 Compose 参数解析、真实 dsh 日志格式、Docker
socket 权限、容器网络、镜像内容。它只证明脚本控制流和失败语义。

## 3. Compose 渲染

```bash
docker compose \
  --env-file spk/package/config.env.example \
  -f spk/package/docker-compose.yml \
  config
```

应看到：

- `image: dshd-synology:0.2.0`；
- `host_ip: 127.0.0.1`、`published: "3080"`；
- `DSH_PUBLIC_URL: http://127.0.0.1:3080`；
- 两个 bind mount：`/volume1/docker/dshd/home`、`/volume1/dshd-workspace`；
- 没有 `example.com`。

`name: dshd-spk` 需要 Compose v2；Container Manager 的实际版本未验证。

## 4. 镜像层验证（已有，2026-11-08）

这些是容器原型验证，不是 SPK 验证：

```bash
# arm64
docker build --platform linux/arm64 -t dshd-synology:test .
docker run --rm -p 127.0.0.1:3080:3080 dshd-synology:test
curl -i http://127.0.0.1:3080/    # 401
```

已记录：

- 无 cookie `GET /` → 401；
- token URL → 303 + HttpOnly cookie；
- 认证后 `GET /` → 200，UI HTML 约 40 KB；
- arm64 与 amd64 均构建/运行（amd64 用 digest 拉取 + QEMU）。

证据：[evidence/amd64-image.txt](../evidence/amd64-image.txt)、
[evidence/reverse-proxy.txt](../evidence/reverse-proxy.txt)。

## 5. DSM 真机检查清单

> 尚未执行。按顺序做，任何一步失败都记录 Package Center / `/var/log/messages` /
> `docker compose logs`。

### 5.1 安装前

```bash
# SSH 到 NAS
docker version
docker compose version
docker image inspect dshd-synology:0.2.0 >/dev/null && echo image-present
ls -ld /volume1/docker /volume1
```

- [ ] DSM 7.2+，Container Manager 已启动；
- [ ] 镜像已导入且 architecture 匹配（x86_64 / armv8）；
- [ ] 3080 未被占用（`ss -ltnp | grep 3080` 或 `netstat`）；
- [ ] 数据目录父卷空间足够。

### 5.2 安装

- [ ] Package Center 手动安装 `dshd-0.2.0.spk`，无“损坏/不兼容”；
- [ ] 图标/名称/描述正确；
- [ ] `/var/packages/dshd/target/package/docker-compose.yml` 存在；
- [ ] `/var/packages/dshd/var/config.env` 由模板创建；
- [ ] `/usr/local/bin/dshd-token` 链接存在或日志说明跳过。

### 5.3 首次启动

```bash
sudo synopkg start dshd
sudo /var/packages/dshd/scripts/token
cat /var/packages/dshd/var/status
```

- [ ] start 返回 0；
- [ ] `token-url.txt` 出现，权限 0600；
- [ ] token URL 的 scheme/host 与 `DSH_PUBLIC_URL` 一致；
- [ ] `status` 返回 0；
- [ ] `docker compose ... logs dshd` 有 `dsh web:` 行；
- [ ] **故障注入**：把 `config.env` 的 `DSHD_IMAGE` 改成不存在的 tag，start
      必须失败且不创建 token；
- [ ] **故障注入**：临时让日志无 token（例如改镜像/入口）时 start 返回非 0。

### 5.4 访问与反代

- [ ] 本机 `curl -I http://127.0.0.1:3080/` 返回 401；
- [ ] token URL 首次访问 303 + cookie，随后 200；
- [ ] DSM 反代 HTTPS 打开 UI，WebSocket 不断；
- [ ] `DSH_TRUSTED_HOST` 不匹配时返回 403（预期栅栏）；
- [ ] 3080 未暴露到 LAN/公网。

### 5.5 停止/重启/升级/卸载

- [ ] `synopkg stop dshd` 后容器消失、token/status 清理、数据保留；
- [ ] NAS 重启后套件自动启动，token 重新生成；
- [ ] 升级到新版本：`config.env` 与 home/workspace 保留；
- [ ] 卸载：`preuninst` 只清 token/status/链接；数据目录保留；
- [ ] 重新安装后配置/数据可复用；
- [ ] Package Center 无残留错误，`/var/log/messages` 无 AppArmor deny。

### 5.6 权限/ACL

- [ ] File Station 能看到数据目录，UID 1001 显示符合预期；
- [ ] 实际 DSM 用户能读写 workspace；
- [ ] 包用户无法读取 `token-url.txt`（0600 root）；
- [ ] `sudo dshd-token` 可用，普通用户不可用。

## 6. 未验证 / 风险

- DSM 真机安装/启动/停止/升级/卸载；
- `INFO` 纯三段版本、`category`、图标显示；
- `ctrl-script` 的 postinst/preuninst root；
- Container Manager Docker/Compose 路径、`--env-file`、`--no-log-prefix`、
  `--remove-orphans`、`name:`；
- 端口注册 `.sc` 路径/UI；
- Web Service `reverse_proxy` 候选（未启用）；
- 首启 dsh 日志格式与 token 提取；
- ACL/UID、资源限制、日志轮转；
- `spk-docker-project` worker 行为。

真机验证通过前不要把 SPK 作为发布包。
