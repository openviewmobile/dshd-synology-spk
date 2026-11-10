# DSHD for Synology DSM（SPK 独立项目）

本目录是一个可单独复制、构建和验证的 Synology DSM 项目：以 Container Manager +
Docker Compose 运行 headless dsh，并尝试用 DSM 7 SPK 包一层。包含 Compose 原型、
两个 SPK scaffold 和结构校验脚本。

> SPK 包目前是**未在 DSM 真机验证**的 scaffold；正式包仍需 Container Manager 的
> `docker-project` worker、端口/权限、反向代理和首启 token 交付。

## 目录

```
Dockerfile / entrypoint.sh   headless dsh 镜像原型
docker-compose.yml           Compose 运行方式
spk/                         普通 SPK scaffold（docker compose 启停）
spk-docker-project/          docker-project worker 候选
scripts/check-spk.sh         构建两个变体并检查 SPK 成员结构
docs/                        设计与研究记录
evidence/                    arm64/amd64 镜像与反代证据
dist/                        本地 SPK 产物（gitignore）
```


完整设计、SPK 与测试文档见 [docs/](docs/README.md)。这是
[研究文档](docs/synology-app.md) 的 **A→D 路线**里 E1/E2 的最小可运行原型：
Container Manager + Compose + headless dsh 镜像 + DSM 反向代理。

## 前提

- DSM 7.2+，Container Manager（Docker）已安装；
- NAS 能访问 Docker Hub/国内镜像源，或已导入镜像；
- 不要求 SSH；以下都在 Container Manager 项目界面操作。

## 组成

- [Dockerfile](Dockerfile)：可参数化基础镜像 + dsh 0.2.2-rc.1 + pnpm + ripgrep；默认用 npm 国内镜像与阿里云 Debian 源；
- [entrypoint.sh](entrypoint.sh)：读取容器 bridge IP 作为 `--host`（dsh 不接受 `0.0.0.0`），端口 3080；
- [docker-compose.yml](docker-compose.yml)：持久化 `/home/dsh`，只把 3080 发布到 NAS loopback；`DSH_PUBLIC_URL` / `DSH_TRUSTED_HOST` 必须与反代域名一致；
- [entrypoint.sh](entrypoint.sh)：把 `--public-url` 和 `--trusted-host` 传给 dsh，token 打印成浏览器可直接打开的 HTTPS URL；
- DSM 反向代理：`https://dsh.example.com` → `http://127.0.0.1:3080`，开启 WebSocket。

## 部署

1. 把本目录上传到 NAS（如 `/volume1/docker/dshd`）；
2. Container Manager → 项目 → 新增 → 选择该目录的 `docker-compose.yml`；
3. 构建并启动；打开容器日志，找到：

   ```
   dsh web: http://<container-ip>:3080/?token=...
   ```

   该 token 是一次性登录凭据，复制完整 URL。
4. DSM → 控制面板 → 登录门户 → 反向代理 → 新增：
   - 来源：HTTPS，`dsh.example.com`，443；
   - 目的地：HTTP，`127.0.0.1`，3080；
   - 自定义标题 → WebSocket。
5. 浏览器打开 `https://dsh.example.com/?token=...`；token 换 cookie 后即可使用。

## 验证

```bash
# NAS 上（SSH 可选）
curl -I http://127.0.0.1:3080/
# 无 cookie 应为 401；带日志里的 token URL 应 303 → 200

docker logs dshd 2>&1 | tail -20
```

## 本机反代语义验证（2026-11-08）

```bash
docker run -d --name dshd-test -p 127.0.0.1:13080:3080 \
  -e DSH_PUBLIC_URL=https://dsh.example.com \
  -e DSH_TRUSTED_HOST=dsh.example.com dshd-synology:test
docker logs dshd-test
# dsh web: https://dsh.example.com/?token=...
# 用 Host: dsh.example.com 请求 token，返回 303，未认证请求 401
```

记录见 [evidence/reverse-proxy.txt](evidence/reverse-proxy.txt)。这补上了原原型只绑容器 IP、但反代 Host 不在 dsh 信任列表里的缺口。

## amd64 镜像验证（2026-11-08）

在 arm64 Mac 上用 Docker QEMU 构建并运行了 x86_64 镜像，基础镜像通过 DaoCloud 镜像源按 amd64 digest 拉取：

```bash
docker pull --platform linux/amd64 docker.m.daocloud.io/library/node@sha256:c0a93797ee78814ae6d32fcca2561fdbbe423149c3f5389aad32d86e9fd85bd4
docker tag docker.m.daocloud.io/library/node@sha256:c0a93797ee78814ae6d32fcca2561fdbbe423149c3f5389aad32d86e9fd85bd4 node:24-bookworm-slim-amd64
docker build --platform linux/amd64 \
  --build-arg NODE_IMAGE=node:24-bookworm-slim-amd64 \
  --build-arg NPM_REGISTRY=https://registry.npmmirror.com \
  --build-arg APT_MIRROR=http://mirrors.aliyun.com \
  -t dshd-synology:amd64 .
```

容器启动后：未认证 `401`，token `303` + HttpOnly cookie，认证后 `200`（40 KB UI）。
记录见 [evidence/amd64-image.txt](evidence/amd64-image.txt)。这说明 x86_64 NAS 已有可构建镜像路径；
仍需 DSM 真机验证 Container Manager 项目、DSM 反代 TLS/WS 和升级。

## 已知限制

- **首启 token 交付**是最大 UX 缺口：普通用户不会看容器日志。D 阶段用 SPK 包一层，在 DSM 套件里展示 token/打开 UI；或加一次性 bootstrap 页面。
- dsh 只接受具体本地地址；不要改成 `0.0.0.0`。
- DSM 反向代理要允许 WebSocket，否则 UI 会显示连接断开。
- 容器端口发布到 `127.0.0.1` 可绕过 DSM 防火墙规则；如果改成 `0.0.0.0`，必须同时用 DSM 防火墙限制来源。
- 多用户/鉴权不在 MVP：一个容器一个 dsh home；token 泄露等于会话泄露。
- 多架构：arm64 与 amd64 均已在本机 Docker 构建；x86_64 NAS 用上面的 amd64 命令，不能直接搬 arm64 镜像。
- 最终 SPK 仍建议包 Docker（D 阶段），不要先做原生 SPK；原生方案受 DSM Node 版本和原生模块限制。

### 本机 arm64 验证（可选）

```bash
docker build --platform linux/arm64 -t dshd-synology:test .
docker run --rm -p 127.0.0.1:3080:3080 dshd-synology:test
# 另开终端
curl -i http://127.0.0.1:3080/    # 401
```

## SPK 最小外壳（scaffold）

[spk/](spk/) 提供 DSM 7 普通 SPK 结构：`INFO` + `package.tgz` + `conf/privilege` +
`start-stop-status`，用 `docker compose` 启停同一 Compose 原型。构建：

```bash
spk/build-spk.sh
```

这是**未在 DSM 真机验证**的 scaffold；正式包仍需 Container Manager 的
`docker-project` worker、端口/权限、反代和首启 token 交付。

## docker-project 候选

[spk-docker-project/](spk-docker-project/) 是不执行 Docker CLI、改用
`conf/resource` 的 `docker-project` worker 的候选包，`startable="no"`。
构建：

```bash
spk-docker-project/build-spk.sh
```

同样**未在 DSM 验证**；worker 版本、compose 路径、镜像预载和升级仍需真机确认。

## 结构检查

```bash
scripts/check-spk.sh
```

构建主 scaffold 与 docker-project 候选包，并验证 SPK 成员、`package.tgz` 和 compose 路径。
这只能证明打包结构正确，不能替代 DSM 安装验证。
