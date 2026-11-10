# docker-project SPK 变体（实验，未在 DSM 验证）

这是路线 D 的 worker 化候选包：SPK 不再执行 `docker compose`，而是通过
`conf/resource` 的 `docker-project` 让 Container Manager 创建/启动项目。

- `INFO`：`startable="no"`、`ctl_stop="no"`，版本 0.2.0；生命周期交给 worker；
- `conf/resource`：`docker-project.projects = [{name: dshd, path: compose}]`；
- `conf/privilege`：默认 `package`；不执行 Docker CLI；
- `package/compose/docker-compose.yml`：与主包同构的参数化 Compose；
- `package/compose/.env.example`：复制为同目录 `.env` 后按站点修改；
- `PACKAGE_ICON*.PNG`：与主包相同的生成图标；
- `build-spk.sh`：校验 INFO/JSON/默认值后生成
  `dist/dshd-docker-project-0.2.0.spk`。

```bash
./spk-docker-project/build-spk.sh
scripts/check-spk.sh    # 同时检查主包与该变体的结构
```

```bash
cp /var/packages/dshd/target/package/compose/.env.example \
   /var/packages/dshd/target/package/compose/.env
# 编辑 .env：DSHD_IMAGE / DSH_PUBLIC_URL / DSH_TRUSTED_HOST ...
```

**未验证**：worker 的最低 Container Manager 版本、`docker-project` 字段与 compose
路径解释、`.env` 是否被 worker 读取、镜像预载、项目注册/升级/卸载、端口和反代。
当前只作为研究用候选，不能发布；主包 `spk/` 才是当前实现。
