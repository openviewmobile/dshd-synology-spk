# DSHD SPK 包（0.2.0，未在 DSM 真机验证）

这是「SPK 外壳 + Docker 运行时」的主实现，对应研究文档路线 D：

- `INFO`：DSM 7.2+，`x86_64`/`armv8`，`startable=yes`，`ctl_stop=yes`；
- `conf/privilege`：默认 `package`，仅 `postinst`/`preuninst`/`start`/`stop`/
  `status` 以 root 运行（Docker socket 需要；详见
  [../docs/spk.md](../docs/spk.md#3-权限模型)）；
- `conf/resource`：通过 `port_conf/dshd.sc` 注册 3080/tcp；
- `scripts/start-stop-status`：定位 Docker/Compose、创建数据目录、`compose up -d`、
  轮询日志、写 token/status；`stop` 执行 `down`；`status` 检查容器；
- `scripts/token`：输出首启 token URL；
- `scripts/installer` + `postinst`/`preuninst`：初始化配置/目录，卸载时只清运行态；
- `package/docker-compose.yml`：参数化镜像 tag、端口、数据路径、公开 URL；
- `package/config.env.example`：运行时配置模板；
- `PACKAGE_ICON.PNG` / `PACKAGE_ICON_256.PNG`：由 `tools/gen-icons.py` 生成；
- `build-spk.sh`：生成普通 tar SPK（DSM 7 不要求 GPG），带完整性校验。

## 构建与检查

```bash
./spk/build-spk.sh
# dist/dshd-0.2.0.spk

../scripts/check-spk.sh
# 或仓库根目录：scripts/check-spk.sh
```

构建脚本会校验 INFO 必填键、图标尺寸、JSON、`.sc`、脚本语法和必需文件；缺文件
直接失败。

重新生成图标：

```bash
make icons
# 或 python3 spk/tools/gen-icons.py && cp ... spk-docker-project/
```

## 安装后

```bash
sudo vi /var/packages/dshd/var/config.env
sudo synopkg start dshd
sudo /var/packages/dshd/scripts/token    # 或 sudo dshd-token
cat /var/packages/dshd/var/status
```

- `DSHD_IMAGE` 必须已在 NAS 本地（`docker image inspect` 可查）；包不会自动拉取；
- `DSH_PUBLIC_URL` / `DSH_TRUSTED_HOST` 与反代域名一致；
- token 文件 `/var/packages/dshd/var/token-url.txt`，0600 root；
- token 缺失时 start 返回失败，容器保留用于诊断；
- 数据：`/volume1/docker/dshd` 与 `/volume1/dshd-workspace`（可配置）。

## 权限取舍

Docker socket 由 root 拥有。把包用户加入 `docker` 组等于持久 root 权限；本包选择
只对 5 个控制脚本提权，并让 `start-stop-status` 以白名单方式解析 `config.env`
（不 source、不 eval），降低配置注入风险。`docker-project` 变体可以避免 Docker
CLI，但仍是实验。

## 反向代理

推荐 DSM 控制面板 → 登录门户 → 高级 → 反向代理，目的地
`http://127.0.0.1:3080`，启用 WebSocket。`conf/resource.webservice.example.json`
是 Web Service worker 候选，**未启用、未验证**；不要直接合并到
`conf/resource`，除非在真机确认 WebStation 依赖、alias portal 域名和 Host 头。

## 未验证

SPK 安装/升级/卸载、`ctrl-script` root、Container Manager 的 Docker/Compose
路径与参数、端口注册 UI、反代 TLS/WebSocket、token 日志格式、ACL/UID、图标显示、
`/usr/local/bin` 链接策略。**真机验证前不要作为发布包。** 完整清单见
[../docs/spk.md](../docs/spk.md#9-未验证清单)。
