# DSM 7 SPK

## 目标形态

在 DSM 7.2+ 的 Container Manager 上跑一个 headless dsh 容器，再用原生 SPK 提供：

- 套件中心安装/卸载/启停；
- 端口注册与 DSM 反向代理；
- 首启 token/URL 交付（当前最大 UX 缺口）；
- 升级与数据保留。

SPK 只包运行时，不把 Node/dsh 直接装进 DSM 系统 Node；原生 Node 方案受 DSM Node 版本与
原生模块限制，不作为首选。

## 两个 scaffold

### `spk/`：普通 SPK + `docker compose`

- `INFO`：DSM 7.2+，`x86_64`/`armv8`，`startable=yes`；
- `conf/privilege`：默认 `package`，仅 start/stop/status 以 root 运行；
- `scripts/start-stop-status`：`start` 执行 `docker compose up -d`，`stop` 执行 `down`；
- `package/docker-compose.yml`：镜像需预先导入 NAS（`docker load`），并替换 tag；
- `build-spk.sh`：生成普通 tar SPK（DSM 7 不要求 GPG）。

构建：

```bash
./spk/build-spk.sh
# dist/dshd-0.1.0.spk
```

### `spk-docker-project/`：`docker-project` worker

- `INFO` 的 `startable="no"`，生命周期交给 Container Manager；
- `conf/resource` 声明 `docker-project.projects = [{name: dshd, path: compose}]`；
- `package/compose/docker-compose.yml` 与主 scaffold 同构；
- 不执行 Docker CLI，权限由 Container Manager 管理。

构建：

```bash
./spk-docker-project/build-spk.sh
# dist/dshd-docker-project-0.1.0.spk
```

结构检查：

```bash
scripts/check-spk.sh
# 两个包均输出 structure OK
```

## DSM 真机安装检查清单

- [ ] 在 DSM 7.2 Container Manager 中安装 SPK；
- [ ] `docker-project` worker 的最低版本/字段被接受；
- [ ] compose 路径、镜像预载和 tag 正确；
- [ ] 端口注册、DSM 反代 TLS/WebSocket 正常；
- [ ] 首启 token/URL 能在套件 UI 展示或通过一次性 bootstrap 页交付；
- [ ] 升级/卸载不丢 dsh home；
- [ ] 权限、资源限制、日志轮转。

> 当前两个包都**没有在 DSM 真机验证**，不能作为发布包。结构检查只证明 tar/INFO/
> package.tgz/compose 路径正确。
