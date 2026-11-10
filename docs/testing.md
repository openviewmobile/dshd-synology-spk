# Synology 测试

## Compose 镜像

```bash
# arm64 本机
docker build --platform linux/arm64 -t dshd-synology:test .
docker run --rm -p 127.0.0.1:3080:3080 dshd-synology:test
curl -i http://127.0.0.1:3080/    # 401
```

已验证的链路：

- 无 cookie `GET /` → 401；
- token URL → 303 + HttpOnly cookie；
- 认证后 `GET /` → 200，UI HTML 约 40 KB；
- arm64 与 amd64 镜像均构建并运行（amd64 用 digest 拉取 + QEMU）。

## SPK 结构

```bash
scripts/check-spk.sh
```

脚本构建两个变体，并检查 `INFO`、`package.tgz`、`docker-compose.yml` 路径：

```text
== dshd-0.1.0.spk
structure OK
== dshd-docker-project-0.1.0.spk
structure OK
```

## 未验证

- DSM 真机安装/启动/停止/升级/卸载；
- Container Manager `docker-project` worker 版本与 compose 路径解释；
- DSM 反向代理 TLS/WebSocket；
- 首启 token/URL 交付；
- 权限、端口、资源限制。

真机验证前不要把 SPK 作为发布包。
