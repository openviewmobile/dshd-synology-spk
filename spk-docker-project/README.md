# docker-project SPK variant（实验，未在 DSM 验证）

这是路线 D 的 worker 化候选包：SPK 不再执行 `docker compose`，而是通过
`conf/resource` 的 `docker-project` 让 Container Manager 创建/启动项目。

- `INFO`: `startable="no"`（生命周期交给 worker）；
- `conf/resource`: `docker-project.projects = [{name: dshd, path: compose}]`；
- `package/compose/docker-compose.yml`: 与主 scaffold 同构；
- `conf/privilege`: 默认 `package`，worker 以 Container Manager 权限运行。

```bash
./spk-docker-project/build-spk.sh
```

**未验证**：worker 的最低 Container Manager 版本、compose 路径解释、镜像预载、
项目注册/升级/卸载、端口和反代。当前只作为研究用候选，不能发布。
