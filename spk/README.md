# DSM 7 SPK scaffold（未在真机验证）

这是「SPK 外壳 + Docker 运行时」的最小包结构，对应研究文档的路线 D：

- `INFO`：DSM 7.2+，`x86_64`/`armv8`，`startable=yes`；
- `conf/privilege`：默认 `package`，仅 `start`/`stop`/`status` 以 root 运行
  （与官方 SPK 的 `ctrl-script` 模式一致）；正式发布应改用 `docker-project` worker；
- `scripts/start-stop-status`：`start` 调 `docker compose up -d`，`stop` 调 `down`；
- `package/docker-compose.yml`：与 `docker-compose.yml` 同构，镜像
  需预先导入 NAS（`docker load`），并把 `dshd-synology:latest` 换成实际 tag；
- `build-spk.sh`：生成普通 tar SPK（DSM 7 不要求 GPG）。

```bash
./spk/build-spk.sh
# output: dist/dshd-0.1.0.spk
```

**未验证**：SPK 安装/升级/卸载、Container Manager 的 `docker compose` 路径、`run-as`
权限、DSM 反代 TLS/WebSocket、首启 token 展示。真机验证前不要作为发布包。
