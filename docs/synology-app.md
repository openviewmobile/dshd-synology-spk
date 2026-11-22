# Synology DSM App Packaging: Putting dsh on a NAS

- Status: research (2026-11-08), not a scope decision.
- Goal: run the dsh kernel on a Synology NAS, with the Web UI reachable from a browser on the LAN; no cloud/relay involved.
- See [ADR-0007](adr/0007-local-only-scope.md) for the related product decision; cross-platform architecture and the release matrix are not maintained in this repository.
- Conclusion: **For the MVP, use Container Manager + Compose + a prebuilt multi-arch image + the DSM reverse proxy; for GA, wrap a Docker project in an SPK package; only start a native SPK effort when "Docker must not be used" is a hard requirement.**

---

## 1. Drawing the Boundary First: Is a NAS "Local" or "Remote"?

ADR-0007 classifies "a browser connecting to a Host on another machine" as remote, hence no Web. The NAS approach must first make the definition explicit:

| Form | Kernel location | Browser location | Counts as local |
|---|---|---|---|
| NAS + LAN browser | On the NAS itself | Same LAN | **Propose counting as the "LAN device edition"**, not Web/SaaS |
| NAS + public port mapping | On the NAS itself | Any network | Remote, outside product scope |
| NAS + QuickConnect/relay | On the NAS itself | Any network | Remote, and dsh does not support that path |

Recommend defining the NAS as a **single-user, LAN-only, relay-free local device SKU**; remote access is the user's own VPN/Tailscale and is not a product commitment. This requires product to add an explanatory note to ADR-0007, otherwise it conflicts with "no Web".

---

## 2. dsh's Hard Constraints (these determine architecture, not preferences)

| Fact | Impact |
|---|---|
| `dsh --profile web` defaults to `127.0.0.1:3080` and prints a URL with a one-time token at startup | First start must have a way to get the URL into the user's hands |
| `--host` accepts only a **concrete local IP** and rejects `0.0.0.0` | In a container you cannot simply "listen on all interfaces + map ports" |
| Host/Origin fence: the bound IP is accepted; any other authority must be `--trusted-host` | The reverse proxy must preserve/rewrite Host and add the domain to the trust list |
| `--public-url` only "announces", it does not grant trust | Must be paired with `--trusted-host` |
| The startup token is exchanged for a signed HttpOnly cookie; the token only appears on stdout/in the URL | The token must never be written into the image, docs, or model context |
| `--tls-cert/--tls-key` are available, but there is no ACME and no self-signed fallback | On a NAS it is better to terminate TLS at DSM |
| The tool surface needs bash, filesystem, ripgrep, pnpm, optionally Python/Office | The container image cannot be pure distroless |
| Native modules include `node-pty`, `koffi`, `node:sqlite`, etc. | Must be built/verified per arch; Alpine/musl is high risk |

The startup invocation dsh officially recommends for containers is:

```sh
dsh --profile web --no-open \
  --host "$(hostname -i | awk '{print $1}')" \
  --public-url https://dsh.example.com \
  --trusted-host dsh.example.com
```

`hostname -i` gets the container IP (e.g. `172.18.0.2`), not `127.0.0.1`. This is the precondition for "port mapping + reverse proxy" to work.

---

## 3. DSM Platform Facts (as of DSM 7.2.2)

| Fact | Evidence | Impact on the plan |
|---|---|---|
| SPK layout is fixed: `INFO`, `package.tgz`, `scripts/`, `conf/`, icons; `WIZARD_UIFILES` v2 since 7.2.2 | Developer Guide | A native package must follow this layout |
| DSM 7 enforces privilege dropping: `run-as: package` by default, scripts run as the package user | Privilege docs | Cannot be root by default; ports/files/services are all restricted |
| Package directories `target/var/etc/tmp/home` live on the volume by default (except `install_type=system`) | FHS docs | Put data in `var/home` or a shared folder, never on the system disk |
| DSM 7 **no longer requires GPG signing** (the signing mechanism exists only in DSM 6.x) | Sign Package docs | Third parties can ship a plain tar SPK; manual install shows a source warning |
| Container Manager ships both `x86_64` and `armv8` SPKs (24.0.2-1707) | Synology Archive | x86_64 is universal; ARM only on some models |
| Supported models include ARM units such as DS223/DS124/DS223j | Official Applied Models | Cannot assume "ARM never has Docker" |
| Package Center's Node.js tops out at **v22.23.4**, no v24 | Synology Archive | A native SPK must bundle Node 24 |
| Two reverse proxy paths: the DSM login portal reverse proxy; Web Station's `reverse_proxy` service type | Developer Guide Web Service | Web Station is not the only entry point; a single container need not depend on it |
| `docker-project` worker since ContainerManager >= 1432 (DSM 7.2.1) | Developer Guide | Minimum version gate for the hybrid SPK |
| Docker worker ports limited to 1025–65535 | Developer Guide | Cannot use 80/443 |
| A package must register a `.sc` port file for the firewall to list the app | Port docs | Without registration there is no firewall app entry |
| Review requirements: non-root, offline installable, no AppArmor denials, no leftovers, no port conflicts | Publication Review | dsh's native shell/tool surface will collide with these checks |

Assumptions that need on-site verification: Container Manager's dockerd runs as root with **no rootless mode**; Docker publishes ports by writing iptables directly, so **the DSM firewall cannot serve as a security boundary for container ports**; DSM 7's systemd is used only for DSM itself and for `pkg-*.service`.

---

## 4. Four Candidates

### A. Container Manager / Docker Compose (recommended MVP)

Prebuild `linux/amd64` + `linux/arm64` images, create a Compose project in Container Manager, terminate TLS at the DSM reverse proxy, and persist data in volumes.

- Pros: Node 24 comes straight from the official image; multi-arch; resource limits/logging/restart policies are built in; upgrading = changing the tag; decoupled from DSM.
- Cons: requires a model that supports Container Manager; the first-start token must be read from the logs; UID/shared-folder permissions need manual alignment; pulling images from inside China may be blocked.

### B. Native DSM SPK (Phase 3, not the first choice)

`package.tgz` bundles Node 24 + dsh + dependencies + pnpm, `start-stop-status` launches the process, and it runs as the package user.

- Pros: the best install experience in Package Center; no Docker dependency; can use a DSM desktop icon.
- Cons: separate build per arch; Node 24 must be bundled; native modules need cross-compilation; AppArmor/review risk; large package; you must build the upgrade chain yourself.

### C. DSM Web Station Reverse Proxy (not a standalone option)

Web Station can register a `reverse_proxy` service, but for a "single Docker app" it is a **network-layer component**, not a packaging option. The available entry points are Container Manager's Project → Web Portal (if that version offers it), or Control Panel → Login Portal → Advanced → Reverse Proxy. Both are DSM's built-in nginx; Web Station is only needed when you want the reverse proxy registered as a "Web service" along with the SPK.

### D. Hybrid: SPK Shell + Docker Runtime (recommended GA)

The SPK handles Package Center installation, icons, ports, permissions, and reverse-proxy registration; the actual kernel lives in a container started by the `docker-project` worker.

- Pros: keeps A's Node 24/multi-arch/isolation while gaining one-click install and upgrade from Package Center.
- Cons: still depends on Container Manager; the SPK must handle offline install/image preloading; review is more complex; requires DSM 7.2.1+.

---

## 5. Decision Matrix

Scores 1–5, weights total 100; C is not scored separately (it is a component).

| Dimension | Weight | A Docker | B Native SPK | D Hybrid |
|---|---:|---:|---:|---:|
| Install experience | 15 | 3 | 5 | 5 |
| Update/rollback | 10 | 4 | 4 | 4 |
| Auth/TLS | 15 | 4 | 4 | 4 |
| Persistence/workspace | 10 | 5 | 4 | 5 |
| Resource isolation/limits | 8 | 4 | 3 | 4 |
| Node 24 availability | 10 | 5 | 2 | 5 |
| Native modules | 8 | 4 | 2 | 4 |
| GUI/first start | 10 | 3 | 4 | 4 |
| Licensing/compliance | 4 | 4 | 4 | 4 |
| Support burden | 5 | 3 | 2 | 3 |
| Model coverage | 5 | 4 | 4 | 4 |
| **Weighted score** | 100 | **3.90** | **3.61** | **4.30** |

Reading: **D scores highest, but it is a superset of A** — without A's image/Compose/reverse proxy there is no D, so the path is A → D. B is dragged down by Node 24, native modules, and support burden, and only makes sense when "the customer explicitly rejects Docker". A's low "GUI/first start" score comes mainly from token delivery, not technical infeasibility; this is the product gap most worth closing first.

---

## 6. MVP: Container Manager + Compose + Reverse Proxy

### 6.1 Topology

```
LAN Browser
  │ HTTPS 443 (dsh.example.com)
  ▼
DSM nginx (login portal reverse proxy / Container Manager Web Portal)
  │ HTTP 127.0.0.1:3080  (bound to loopback only)
  ▼
dsh container (bridge network, container IP 172.x:3080)
  ├─ /data/dsh      ← /volume1/docker/dshd/home
  └─ /workspace     ← /volume1/dsh-workspace
```

dsh binds the container IP, **not** `0.0.0.0`; the container port is published only to `127.0.0.1:3080`; the reverse proxy passes `Host: dsh.example.com` to dsh, so `--trusted-host` must include it; TLS terminates at DSM, dsh sees an HTTP upstream, and the cookie carries no `Secure` — the backend must therefore bind only to loopback. Recommended repository layout: `deploy/synology/{compose.yaml,.env.example,Dockerfile,entrypoint.sh,dsm/,spk/}`.

### 6.2 Dockerfile sketch

```dockerfile
FROM node:24-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash ca-certificates git ripgrep tini python3 util-linux \
    && rm -rf /var/lib/apt/lists/*
RUN npm i -g @deepseek-ai/dsh@0.2.1-rc.5 pnpm
COPY entrypoint.sh /usr/local/bin/
ENV DSH_HOME=/data/dsh NODE_ENV=production
WORKDIR /workspace
ENTRYPOINT ["/usr/sbin/tini","--","/usr/local/bin/entrypoint.sh"]
```

Do not use Alpine: the prebuilds for `node-pty`/`koffi` are mostly glibc-based, and musl usually requires building from source. For production builds, separate a build stage and precompile the native modules into the image; if the target arch has no prebuild, install `build-essential python3` during the build stage.

### 6.3 entrypoint sketch

```sh
#!/bin/sh
set -eu
: "${DSH_HOME:=/data/dsh}"
: "${DSH_PUBLIC_URL:?}" "${DSH_TRUSTED_HOST:?}"
mkdir -p "$DSH_HOME" /workspace

# Fix permissions then drop privileges when started as root; PUID/PGID map to the DSM user/group
if [ "$(id -u)" = "0" ]; then
  chown -R "${PUID:-1026}:${PGID:-100}" "$DSH_HOME" /workspace
  exec setpriv --reuid="${PUID:-1026}" --regid="${PGID:-100}" --init-groups "$0" "$@"
fi

exec dsh --profile web --no-open --host "$(hostname -i | awk '{print $1}')" \
  --port 3080 --public-url "$DSH_PUBLIC_URL" --trusted-host "$DSH_TRUSTED_HOST"
```

### 6.4 compose sketch

```yaml
name: dshd
services:
  dsh:
    image: ghcr.io/<org>/dshd:0.1.0
    restart: unless-stopped
    ports: ["127.0.0.1:3080:3080"]
    volumes: ["./home:/data/dsh", "/volume1/dsh-workspace:/workspace"]
    environment:
      DSH_HOME: /data/dsh
      DSH_PUBLIC_URL: https://dsh.example.com
      DSH_TRUSTED_HOST: dsh.example.com
      DEEPSEEK_API_KEY: ${DEEPSEEK_API_KEY:?}
      PUID: "1026"
      PGID: "100"
      TZ: Asia/Shanghai
    mem_limit: 4g
    cpus: 2.0
```

Put `.env` in the same directory as the compose file; whether Container Manager passes `.env` through must be tested on the target version. Health checks must hit the container IP (`http://$(hostname -i | awk '{print $1}'):3080/`); hitting `127.0.0.1` will fail.

### 6.5 DSM installation steps (x86_64 first)

1. Install **Container Manager** from Package Center; if the model does not support it, this plan does not apply.
2. Control Panel → Shared Folder: create `dsh-workspace` and give the DSM user who will actually use dsh read/write permission.
3. In File Station create `/docker/dshd` and upload `compose.yaml` and `.env`; Container Manager → Project → Create → select that directory → Start.
4. Open the container logs and find `dsh web: https://dsh.example.com/?token=...`; open it once in a browser to exchange the token for a cookie.
5. Control Panel → Login Portal → Advanced → Reverse Proxy: source HTTPS `dsh.example.com:443`, destination HTTP `127.0.0.1:3080`; bind the certificate, enable HSTS, and confirm that WebSocket upgrade headers are passed through.
6. Security → Firewall: allow only LAN to 443; do not allow 3080. Do not configure port forwarding on the router; for remote access use VPN/Tailscale, which is out of product scope.

If Container Manager offers Project → Web Portal, you can skip step 5 and create an HTTPS portal for container port 3080 directly; underneath it is still DSM nginx reverse proxying.

### 6.6 The Real Boundaries of Auth and TLS

- The dsh token is the **only identity**; a DSM login is not a dsh login, and the reverse proxy adds no authentication by default.
- Additional gates can only come from VPN/Tailscale, firewall IP allowlists, or custom nginx basic auth (the DSM UI is limited).
- The token appears in container logs, browser history, and diagnostic bundles; restrict Container Manager permissions to the admin group and state clearly that "logs contain secrets".
- When proxying to an HTTP upstream the cookie has no `Secure`; that is acceptable, but 3080 must then never be exposed to the LAN.
- Do not use the subpath `/dsh/`: dsh supports `--public-url` + prefix-stripping proxies, but DSM's built-in reverse proxy does not guarantee prefix stripping. A dedicated domain is the most robust option.
- `dsh.example.com` must be resolvable on the LAN; without public port 80, Let's Encrypt is unavailable, so use a private CA or import a certificate.

### 6.7 Persistence, Permissions, Resources

- `home/`: profiles, sessions, credentials, logs — must be backed up; credentials should be encrypted.
- `workspace/`: user files, code repositories — must be backed up (Hyper Backup/snapshots); `cache/` is optional.
- **UID mapping**: the first regular user on DSM is usually 1026, and group `users` is 100; align the container via `PUID/PGID`, otherwise File Station will show "unknown user/cannot edit".
- Do not run as root long-term; files written by root will be uneditable by DSM users.
- Node baseline is about 300–600 MB; agent builds/tests may reach 2–4 GB. Start with 2 vCPU / 4 GB; models with 2 GB of RAM OOM easily.
- ARM (RTD1619B) works, but compilation/indexing is noticeably slow; for heavy work prefer x86_64 Plus models. Image + node_modules is about 1–2 GB, so reserve 20 GB.

- Updates: use immutable versions for image tags (add a digest in production), back up `home/` → change the tag → `docker compose pull && up -d`; keep the old tag for rollback. dsh is pinned inside the image; do not run `npm update` inside the container.

---

## 7. Native SPK (Phase 3)

### 7.1 Package Structure

```text
dshd.spk
├── INFO
├── package.tgz          # node24/, dsh/, node_modules/, pnpm/, bin/
├── scripts/  preinst postinst preuninst postuninst preupgrade postupgrade start-stop-status
├── conf/     privilege  resource  systemd/pkg-dshd.service
├── WIZARD_UIFILES/install_uifile
├── PACKAGE_ICON.PNG (64x64)  PACKAGE_ICON_256.PNG (256x256)
└── LICENSE
```

### 7.2 INFO Essentials

```ini
package="dshd"
version="0.1.0-0001"
os_min_ver="7.2-64570"
arch="x86_64"                 # the other build uses armv8; do not mix them
displayname="DSHD"
displayname_chs="DSHD"
description="Local dsh agent for Synology NAS"
maintainer="..."  maintainer_url="https://..."  support_url="https://..."
dsmuidir="ui"  dsmappname="com.example.dshd"
checkport="yes"  startable="yes"
```

- `arch` is `x86_64` or `armv8`; the official guidance explicitly discourages stuffing multi-platform binaries into a single SPK.
- Use `adminport` with caution: Package Center's "Open" can only assemble `protocol://NAS_IP:port/path`, so the Host header is not `dsh.example.com` and will be rejected with 403 by the Host fence, and it cannot carry the startup token. The desktop icon should point to a launcher page.

### 7.3 Lifecycle and Permissions

- `start-stop-status` is the only reliable lifecycle entry; prefer `conf/systemd/pkg-dshd.service` + `synosystemctl`, with `nohup` + a PID file as the fallback.
- Package scripts run as the `package` user; binding 80/443 needs root/capability, so give up on that and use 3080 + a reverse proxy.
- Create the workspace as a shared folder via the `data-share` resource (uninstall does not delete it), or let the user pick an existing shared folder; the latter requires handling ACLs.
- Register ports with `.sc` and reference them in `port-config` under `conf/resource`, otherwise the app will not appear in the firewall.
- When a reverse proxy is needed, use the `webservice` `reverse_proxy` type, but that introduces a Web Station dependency; it is simpler to have the user create one manually in the login portal.

### 7.4 Node 24 and Native Modules

- Package Center has no Node 24, so the SPK must bundle the official `linux-x64`/`linux-arm64` binaries (about 100 MB per arch).
- Must verify that DSM 7.2's glibc/OpenSSL can satisfy Node 24; the official binaries depend on glibc, so test model by model.
- `node-pty` and `koffi` must be built per arch inside the DSM Toolkit chroot, or you must confirm the prebuild ABI matches; this is the single biggest source of schedule risk for a native SPK.
- Whether to bundle pnpm, ripgrep, Python, and Office is a trade-off; every addition increases package size and review surface.

### 7.5 Publishing and Review

- DSM 7 does not require GPG signing; third parties can install manually, but a source warning is shown.
- The official Package Center requires a developer account, acceptance of the distribution agreement, and passing checks for non-root, offline install, Security Advisor, AppArmor denials, port registration, and uninstall leftovers.
- dsh's core capability is "execute arbitrary shell/read and write the workspace", which is inherently in tension with DSM's security review; **listing officially is high risk, so design for manual SPK/GitHub distribution first**.
- A third-party package source/auto-update requires maintaining your own JSON feed; otherwise users can only download new SPKs manually.

### 7.6 Hybrid D: The SPK Is Only an Installer

`conf/resource` uses `docker-project`:

```json
{
  "docker-project": {
    "preload-image": "dshd-image.tar.gz",
    "projects": [{ "name": "dshd", "path": "compose" }]
  }
}
```

- The SPK handles: dependency checks (Container Manager), shared folders, ports, icons, reverse proxy, upgrade scripts; the container handles Node 24, dsh, native modules, isolation.
- Cost: an offline install must preload a 1–2 GB image; without preloading, the first start must pull from the network, which conflicts with the review requirement of "no abnormal network activity during installation".
- Recommended only after A's image/reverse proxy have been validated.

---

## 8. Clearly Infeasible / High Risk

1. **`dsh web --host 0.0.0.0` does not work**: upstream explicitly rejects wildcard addresses; you must bind a concrete IP.
2. **Publishing 3080 directly to the LAN/public internet**: the Host/Origin fence, token leakage, and Docker bypassing the DSM firewall — all three are unacceptable.
3. **Rootless containers**: Container Manager has no rootless mode; containers are root by default, and only `user:` can drop privileges.
4. **A native SPK running a root daemon / binding 80, 443**: DSM 7 forces the package user and systemd only recognizes `pkg-*` units; non-root cannot bind low ports, so use 3080/8443 + a reverse proxy.
5. **A package writing outside FHS paths**: permissions/AppArmor will block it; the workspace must go through a shared folder or volume.
6. **Expecting Package Center to provide Node 24**: the current maximum is v22; you can only bundle it or containerize.
7. **armv7/older ARM models**: no Container Manager and no official Node 24 armv7 binary; unsupported.
8. **Listing on Package Center without review**: requires a developer agreement and security review; dsh's shell surface is a hard blocker.
9. **Using QuickConnect to reverse-proxy a custom domain**: QuickConnect is not a general-purpose reverse proxy; remote access can only be VPN/DDNS + port forwarding (and is outside local scope).
10. **One Host shared by multiple users / DSM login as SSO**: dsh is a single-user kernel and has no built-in DSM SSO; multi-user means one container per user, and SSO means building your own launcher.
11. **Subpath reverse proxying without prefix stripping**: dsh will 404/403; use a dedicated domain, or write your own rewrite.
12. **Directly reaching ghcr.io/Docker Hub from mainland China**: frequently fails; use a registry mirror, a private registry, or offline tar import.

---

## 9. Open Questions

1. Target model matrix: start with x86_64, or must we cover ARM units like the DS223/DS124?
2. Can Container Manager be a hard prerequisite? If customers reject Docker, is B worth 3 months of investment?
3. How do we hand the first-start token to non-technical users: change dsh to add a token file/one-time launcher, or accept "copy it from the logs"?
4. Is single-user sufficient? For multi-user, do we need one container per user?
5. Who owns workspace location and the UID/ACL strategy? Should the MVP bundle Python/Office (the image grows to 2–3 GB)?
6. Distribution in mainland China: where to host images, whether to provide an offline package, whether to run a registry mirror; official Package Center or GitHub/manual SPK?
7. Does ARM performance satisfy "a usable agent"? Compile/index tasks need real measurement.
8. Are cookies still valid after a container restart (is the signing key persisted)? If not, a new token must be fetched on every restart.
9. Should credentials in `home/` be additionally encrypted? DSM snapshots/Hyper Backup will copy them.
10. Who tracks changes to DSM 7.3's packaging/container policies?

---

## 10. Next Experiments

| # | Experiment | Effort | Exit criterion |
|---|---|---|---|
| E1 | Build amd64/arm64 images, run Node 24 + dsh + native modules | 3 days | Both arches can run `dsh web`, bash/rg, node-pty, sqlite |
| E2 | DSM reverse proxy: HTTPS, WebSocket, Host/Origin, cookies | 2 days | Browser can chat, WS stays up, no 403 |
| E3 | First-start token: log extraction + cookie persistence + launcher prototype | 3 days | Non-technical user reaches the UI in 3 steps |
| E4 | UID/ACL matrix: PUID/PGID, shared folders, File Station | 2 days | Users can edit workspace files in File Station |
| E5 | Resource limits: 2 GB/4 GB, OOM, heavy tasks | 2 days | NAS not dragged down, OOM produces readable logs |
| E6 | SPK hello-world: package user, ports, data-share, icon | 5 days | Installs/starts/uninstalls on a DSM 7.2 VM |
| E7 | SPK bundling Node 24 + dsh, verify AppArmor | 5 days | Can start the Host; record all denials |
| E8 | Hybrid D: SPK + docker-project + reverse proxy | 5 days | UI opens directly after one-click install |
| E9 | Upgrade/rollback/backup restore | 2 days | Old version can be rolled back, no data loss |

Recommended order: E1 → E2 → E3 → E4/E5 in parallel → then decide on E6–E8. **If E1/E2 fail, none of the later SPK work is worth doing.**

---

## 11. Sources

- [Synology Package Developer Guide (DSM 7.2.2)](https://help.synology.com/developer-guide/): [SPK structure](https://help.synology.com/developer-guide/synology_package/introduction.html), [INFO required fields](https://help.synology.com/developer-guide/synology_package/INFO_necessary_fields.html)/[optional fields](https://help.synology.com/developer-guide/synology_package/INFO_optional_fields.html), [lifecycle scripts](https://help.synology.com/developer-guide/synology_package/scripts.html)
- [Privilege (DSM 7 privilege dropping)](https://help.synology.com/developer-guide/privilege/preface.html) / [Package FHS](https://help.synology.com/developer-guide/integrate_dsm/fhs.html) / [Port registration](https://help.synology.com/developer-guide/integrate_dsm/ports.html)
- [Docker worker](https://help.synology.com/developer-guide/resource_acquisition/docker.html) / [Docker Project worker](https://help.synology.com/developer-guide/resource_acquisition/docker-project.html) / [Web Service (reverse_proxy)](https://help.synology.com/developer-guide/resource_acquisition/web_service.html) / [Data Share](https://help.synology.com/developer-guide/resource_acquisition/data_share.html)
- [Platform/architecture mapping](https://help.synology.com/developer-guide/appendix/platarchs.html) / [Publication review checklist](https://help.synology.com/developer-guide/appendix/publication_review.html) / [DSM 7 no longer requires signing](https://help.synology.com/developer-guide/toolkit/sign_package.html)
- [Container Manager product page](https://www.synology.com/en-global/dsm/feature/container-manager)
- [Container Manager 24.0.2-1707 (armv8/x86_64 SPK)](https://archive.synology.com/download/Package/ContainerManager/24.0.2-1707)
- [Node.js v22.23.4-1011 (latest available Node package)](https://archive.synology.com/download/Package/Node.js_v22/22.23.4-1011)
- [dsh Web App deployment notes](https://github.com/deepseek-ai/deepseek-harness/tree/master/packages/bundle/web-app)

## Prototype Validation (2026-11-08)

The Compose prototype in [this project](../) has landed:

- Image: `node:24-bookworm-slim` + dsh 0.2.2-rc.1 + pnpm + ripgrep, non-root user;
- Inside the container, `dsh web --host <bridge-ip> --port 3080 --no-open`, working around dsh's rejection of `0.0.0.0`;
- Compose publishes only `127.0.0.1:3080`, for the DSM reverse proxy;
- Measured on local arm64 Docker: the container starts, `GET /` without a cookie returns 401, after exchanging the token for a cookie 303→200, and the UI HTML is about 40 KB.

2026-11-08 addendum: both arm64 and amd64 images have been built in Docker; amd64 pulls
`node:24-bookworm-slim-amd64` by digest via the DaoCloud mirror, and inside the container `dsh web` returns 401 unauthenticated, 303 for the token, and 200 after auth (see
[`evidence/amd64-image.txt`](../evidence/amd64-image.txt)).
Still unverified: Container Manager on a real DSM, DSM reverse proxy TLS/WebSocket, DSM firewall, first-start token delivery. The next step is E4/E5 (UID/ACL, resource limits) and a minimal SPK shell.

## 2026-11-09: SPK Scaffold (superseded by the 2026-11-10 implementation)

Added the minimal shell in [`spk/`](../spk/):
`INFO`, `package.tgz`, `conf/privilege`, `start-stop-status`; `start/stop` calls
`docker compose up/down`. The SPK tar structure and script syntax were verified on the host, but it has **not been installed on a real DSM**.

## 2026-11-10: SPK 0.2.0 Implementation

`spk/` has been upgraded from the scaffold to a buildable DSM 7.2 package (still **unverified on a real DSM**):

- `INFO` 0.2.0, with fields filled in; real 72/256 icons;
- `conf/privilege` defaults to package, with only the 5 lifecycle scripts as root;
- `start-stop-status` locates Docker/Compose, initializes directories, runs `compose up -d`,
  polls logs to extract the token into `/var/packages/dshd/var/token-url.txt`, and fails startup when there is no token;
- `scripts/token`, `installer`, `postinst`, `preuninst`;
- `conf/resource` port registration + `port_conf/dshd.sc`;
- Compose parameterized (image tag/port/data path/public URL), no `example.com` by default;
- `scripts/check-spk.sh` locally validates structure/INFO/icons/Compose/scripts, and smoke-tests
  start/stop and the token with a fake Docker CLI; `make all` passes.

Still unverified: DSM real-machine install/start/stop/upgrade/uninstall, Container Manager's Compose paths and parameters, the port UI, reverse proxy TLS/WebSocket, token log format, ACL/UID. See
[`docs/spk.md`](spk.md) and [`docs/testing.md`](testing.md).
