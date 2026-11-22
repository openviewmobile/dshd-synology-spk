# Synology Testing

## 0.1 0.4.0 native (no Docker)

On 2026-11-10, on the same VirtualDSM (DSM 7.2, QEMU TCG, x86_64), the following was completed:

```text
synopkg install dist/dshd-0.4.0.spk   -> success
synopkg start dshd                    -> success, status=running
curl 127.0.0.1:3080                    -> 401
token URL                              -> 303
/ after cookie                         -> 200
synopkg stop                           -> token deleted, process exited
synopkg start                          -> success again
```

### Verified

- **CLI lifecycle**: `install/start/stop/restart/status/doctor/token/logs` all work;
  `node v24.22.2`, `dsh 0.2.2-rc.1`, no Docker container.
- **Package Center GUI**: Package Center shows the DSHD Native icon, 0.4.0, Running;
  click Stop → confirm → `Manually Stopped`; click Run → `Starting...` → `running`.
  See [acceptance-native-package-center.png](acceptance-native-package-center.png),
  [acceptance-native-package-stopped.png](acceptance-native-package-stopped.png).
- **Uninstall GUI**: Package Center Uninstall → confirm; the package directory is removed,
  `/volume1/@appdata/dshd` data is retained.
- **dsh Web UI**: the default workspace is created automatically; the main UI, Plugins, and Automation tasks
  all open; logo/icon/Chinese-English copy are normal. WebSocket connects successfully through the reverse proxy:
  `ws://127.0.0.1:5000/dshd-test/api/remote.mux`; the "Add API Key" settings dialog
  works. See [acceptance-native-web-main.png](acceptance-native-web-main.png),
  [acceptance-native-plugins.png](acceptance-native-plugins.png),
  [acceptance-native-automation.png](acceptance-native-automation.png),
  [acceptance-native-api-key.png](acceptance-native-api-key.png).
  The four pages under More → Settings — General, Models, Built-in plugins, Agent presets — all
  open; see
  [acceptance-native-settings.png](acceptance-native-settings.png),
  [acceptance-native-settings-models.png](acceptance-native-settings-models.png),
  [acceptance-native-more-menu.png](acceptance-native-more-menu.png).
- **First workspace fix**: DSM has no `xdg-user-dir`, so dsh originally reported
  "Unable to create default workspace"; the startup script now uses a `--patch` overlay to point
  `documentsDirectory` at the package home, and symlinks
  `<home>/deepseek-harness/default-workspace` to the configured workspace; the default
  workspace works.
- **Reverse proxy**: added a `/dshd-test/` prefix proxy in DSM nginx; `location ^~ /dshd-test/`
  must be used; with a plain `location`, DSM's static-asset regex intercepts
  `/assets/*.js` first and returns 404. With `^~`, HTML, JS/CSS, token 303,
  and authenticated 200 all pass.
- **Install wizard GUI**: Package Center Manual Install → upload SPK → third-party package Agree →
  runtime settings are shown; all five field values and defaults are correct, see 0.1.1 below.
- **Reboot auto-start**: after a DSM reboot the package automatically enters `starting`, becomes
  `running` within about 2 minutes and regenerates the token; loopback `/` returns 401.
- **Docker→native migration logic**: ran `installer init` with a temporary legacy `config.env`;
  old `/volume*/docker/*` paths were rewritten to `$PKG_VAR/native/{home,workspace}`,
  a `config.env.pre-native` backup was generated, and the directories were created.
- **armv8 package build**: built `dist/dshd-0.4.0-armv8.spk`, INFO `arch=armv8`,
  runtime is an ARM aarch64 ELF; running `node .../bin.js --version` inside an arm64 Debian container
  returns `0.2.2-rc.1`, but it has not yet been started on an ARM DSM.

### 0.1.1 Package Center install wizard

When manually installing the 213 MB `dshd-0.4.0.spk`, DSM upload/verification is slow on QEMU TCG;
after the upload completes, the third-party package disclaimer appears first (Cancel / Agree); after Agree it proceeds to
"DSHD Native runtime settings". Measured fields and defaults:

| Field | name | Value |
|---|---|---|
| dsh home | `DSHD_DATA_DIR` | `/volume1/@appdata/dshd/native/home` |
| Workspace | `DSHD_WORKSPACE_DIR` | `/volume1/@appdata/dshd/native/workspace` |
| Loopback port | `DSHD_PORT` | `3080` |
| Public URL | `DSH_PUBLIC_URL` | `http://127.0.0.1:3080` |
| Trusted host | `DSH_TRUSTED_HOST` | `127.0.0.1` |

Screenshot: [acceptance-native-install-wizard.png](acceptance-native-install-wizard.png).

### Build artifacts

| Package | Architecture | SHA-256 |
|---|---|---|
| `dist/dshd-0.4.0.spk` | x86_64 | `6faac9d152d6493359649c4cb38fcd3914cbbe9e21bd790978ba6b149c667d75` |
| `dist/dshd-0.4.0-armv8.spk` | armv8 | `4c1f9f5d93bfb75de34a4cfddaa063649167a58390261a2031d54bf58b3a5aed` |

### Not covered

- The wizard was verified only through the runtime settings page; the 213 MB package is very slow to upload/verify on QEMU TCG,
  so the final installation was completed with `synopkg install`; the wizard's final Apply step was not treated as an acceptance item.
- The armv8 package was built but not started/accepted on ARM Synology.
- 0.3.0 (Docker) → 0.4.0 (native) verified only the config/directory migration logic, not a full installation rehearsal with real Docker
  data volumes; when the old home belongs to uid 1001, root
  `chown -R dshd:dshd` is required.
- Real DSM hardware, DSM reverse proxy GUI/TLS certificates, external access.
- No model API key was configured, so end-to-end model turns for chat/tool calls were not verified; the UI correctly
  prompts Sign in / Add API Key.

## 0.2 Docker version (0.3.0) conclusions

- Locally verifiable: SPK packaging structure, INFO, icons, package.tgz, Compose rendering, script syntax,
  start/stop/token control flow (fake Docker CLI).
- **Not locally substitutable**: DSM real-machine install/start/stop/upgrade/uninstall, Container Manager's
  Docker paths and Compose version, port registration UI, DSM reverse-proxy TLS/WebSocket, ACL.
- At present **no DSM hardware testing has been performed at all**.

## 1. Full local check

```bash
make all
# Build the two variants under dist/ first, then run scripts/check-spk.sh to check them
```

Expected check-section output (2026-11-10, macOS, Docker 29.9.2 / Compose v5.6.1; `make all` also prints the two build paths before this):

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

### Check details

| Check | Implementation |
|---|---|
| SPK tar members | `INFO`, `package.tgz`, `conf/privilege`, `conf/resource`, 5 scripts, two icons; `package/` must not appear at the SPK root |
| INFO | Required keys non-empty; `package=dshd`, `version=0.2.0`, `arch="x86_64 armv8"`, `os_min_ver=7.2-*`, `startable/ctl_stop/support_conf_folder=yes`, `support_center=no` |
| Icons | Parse PNG IHDR: 72x72 and 256x256 |
| package.tgz | Contains `package/docker-compose.yml`, `package/config.env.example`, `package/port_conf/dshd.sc`; no `.DS_Store` |
| JSON | `conf/privilege`, `conf/resource` parse; privilege is the package default with 5 root actions; resource references `port_conf/dshd.sc` |
| Port file | `[dshd_web]`, `dst.ports="3080/tcp"` |
| Scripts | All 5 scripts are executable and pass `sh -n` |
| Compose | Variable-parameterized; no `example.com` by default; `docker compose --env-file ... config` renders successfully; asserts image tag, `host_ip: 127.0.0.1`, `DSH_PUBLIC_URL` |
| Lifecycle | Fake Docker CLI runs start/status/stop/token, and verifies that start exits non-zero when there is no token |

If the local machine has no Docker/Compose, Compose rendering prints `WARN` and is skipped; the other checks still run.
This is not complete verification; it should be run in a Docker-enabled environment in CI/before release.

## 2. Lifecycle smoke (fake Docker)

```bash
scripts/test-spk-lifecycle.sh dist/dshd-0.2.0.spk
# lifecycle smoke OK
```

Approach:

1. Unpack the SPK and `package.tgz` into a temporary directory;
2. Write a fake `docker` that implements only the subcommands this package needs:
   `compose version`, `compose up/down/ps/logs`, `inspect`, `image inspect`;
3. Run `SYNOPKG_PKGDEST=... SYNOPKG_PKGVAR=... DSHD_DOCKER=<fake> start` with a temporary
   `config.env` (data directory, 4-second timeout);
4. Assert:

   - the contents of `token-url.txt` equal the URL in the fake log;
   - the `status` file has `state=running`, and the `status` action returns 0;
   - after `stop`, the token file is deleted, `state=stopped`, and `status` returns 3;
   - the token command fails when the file is absent and outputs the URL when it is present;
   - when the fake log has no token, `start` returns non-zero, **does not create a token file**, and status is `failed`.

**Limitations**: the fake Docker does not verify real Compose argument parsing, real dsh log format, Docker
socket permissions, container networking, or image contents. It only proves script control flow and failure semantics.

## 3. Compose rendering

```bash
docker compose \
  --env-file spk/package/config.env.example \
  -f spk/package/docker-compose.yml \
  config
```

You should see:

- `image: dshd-synology:0.2.0`;
- `host_ip: 127.0.0.1`, `published: "3080"`;
- `DSH_PUBLIC_URL: http://127.0.0.1:3080`;
- two bind mounts: `/volume1/docker/dshd/home`, `/volume1/dshd-workspace`;
- no `example.com`.

`name: dshd-spk` requires Compose v2; the actual Container Manager version has not been verified.

## 4. Image-layer verification (existing, 2026-11-08)

These are container prototype verifications, not SPK verifications:

```bash
# arm64
docker build --platform linux/arm64 -t dshd-synology:test .
docker run --rm -p 127.0.0.1:3080:3080 dshd-synology:test
curl -i http://127.0.0.1:3080/    # 401
```

Recorded:

- unauthenticated `GET /` → 401;
- token URL → 303 + HttpOnly cookie;
- after authentication, `GET /` → 200, UI HTML about 40 KB;
- both arm64 and amd64 build/run (amd64 uses digest pull + QEMU).

Evidence: [evidence/amd64-image.txt](../evidence/amd64-image.txt),
[evidence/reverse-proxy.txt](../evidence/reverse-proxy.txt).

## 5. DSM real-machine checklist

> Not yet executed. Do the steps in order; for any failure, record Package Center / `/var/log/messages` /
> `docker compose logs`.

### 5.1 Before installation

```bash
# SSH to the NAS
docker version
docker compose version
docker image inspect dshd-synology:0.2.0 >/dev/null && echo image-present
ls -ld /volume1/docker /volume1
```

- [ ] DSM 7.2+, Container Manager started;
- [ ] Image imported and architecture matches (x86_64 / armv8);
- [ ] Port 3080 is free (`ss -ltnp | grep 3080` or `netstat`);
- [ ] The parent volume for the data directory has enough space.

### 5.2 Installation

- [ ] Package Center manual install of `dshd-0.2.0.spk`, no "corrupted/incompatible";
- [ ] Icon/name/description correct;
- [ ] `/var/packages/dshd/target/package/docker-compose.yml` exists;
- [ ] `/var/packages/dshd/var/config.env` is created from the template;
- [ ] `/usr/local/bin/dshd-token` link exists, or the log explains the skip.

### 5.3 First start

```bash
sudo synopkg start dshd
sudo /var/packages/dshd/scripts/token
cat /var/packages/dshd/var/status
```

- [ ] start returns 0;
- [ ] `token-url.txt` appears with permissions 0600;
- [ ] the token URL's scheme/host match `DSH_PUBLIC_URL`;
- [ ] `status` returns 0;
- [ ] `docker compose ... logs dshd` has a `dsh web:` line;
- [ ] **Fault injection**: change `DSHD_IMAGE` in `config.env` to a nonexistent tag; start
      must fail and must not create a token;
- [ ] **Fault injection**: temporarily make the log contain no token (e.g. change image/entrypoint); start must return non-zero.

### 5.4 Access and reverse proxy

- [ ] Local `curl -I http://127.0.0.1:3080/` returns 401;
- [ ] the token URL returns 303 + cookie on first access, then 200;
- [ ] DSM reverse-proxy HTTPS opens the UI and WebSocket stays connected;
- [ ] when `DSH_TRUSTED_HOST` does not match, 403 is returned (expected guard);
- [ ] 3080 is not exposed to LAN/public internet.

### 5.5 Stop/restart/upgrade/uninstall

- [ ] after `synopkg stop dshd`, the container is gone, token/status are cleaned up, data is retained;
- [ ] after a NAS reboot the package starts automatically and the token is regenerated;
- [ ] upgrade to a new version: `config.env` and home/workspace are retained;
- [ ] uninstall: `preuninst` clears only token/status/links; the data directory is retained;
- [ ] after reinstall, configuration/data can be reused;
- [ ] Package Center has no residual errors, `/var/log/messages` has no AppArmor deny.

### 5.6 Permissions/ACL

- [ ] File Station can see the data directory; UID 1001 displays as expected;
- [ ] a real DSM user can read/write the workspace;
- [ ] the package user cannot read `token-url.txt` (0600 root);
- [ ] `sudo dshd-token` works, while a normal user cannot use it.

## 6. Unverified / risks

- DSM real-machine install/start/stop/upgrade/uninstall;
- `INFO` pure three-part version, `category`, icon display;
- `ctrl-script` postinst/preuninst root;
- Container Manager Docker/Compose paths, `--env-file`, `--no-log-prefix`,
  `--remove-orphans`, `name:`;
- port registration `.sc` path/UI;
- Web Service `reverse_proxy` candidates (not enabled);
- first-start dsh log format and token extraction;
- ACL/UID, resource limits, log rotation;

Do not treat the SPK as a release package until real-machine verification passes.

## 0.3.0 VirtualDSM acceptance record (2026-11-10)

Environment: `vdsm/virtual-dsm` (DSM 7.2.2-72806, QEMU TCG, no KVM);
Container Manager 24.0.2-1543; image `dshd-synology:0.3.0` (amd64).

Verified:

- the container starts with `user: dsh`; the port is only `127.0.0.1:3080->3080/tcp`;
- the first-start token is written to `compose/data/run/token-url.txt`;
- unauthenticated `GET /` → **401**;
- token URL → **303** and issues an HttpOnly session cookie;
- `GET /` with the cookie → **200**.

```text
exchange=303 auth=200
127.0.0.1:3080->3080/tcp
```

Could not be completed automatically:

- `synopkg install` reports
  `failed to acquire postinst worker` during the worker stage (`compose up` timeout). Manually running the same
  `docker-compose.admin.yaml` starts normally. It was initially misdiagnosed as a TCG first-start timeout;
  later, a Docker API proxy localized it to the `compose up` stage (stop/delete immediately after create without start),
  unrelated to dsh startup time; see the supplement below for details.
- Therefore `synopkg start/stop/status`, upgrade 0.2.0→0.3.0, and uninstall cleanup have not yet formed a complete automated loop on this
  VirtualDSM; they need to be redone on native DSM or a KVM-enabled VirtualDSM
  as a follow-up.

Manual verification reproduction:

```bash
sudo docker tag dshd-synology:amd64 dshd-synology:0.3.0
sudo synopkg install /volume1/docker/dshd-test/dshd-0.3.0.spk
sudo docker compose -f /var/packages/dshd/target/compose/docker-compose.admin.yaml up -d
sleep 120
sudo cat /var/packages/dshd/target/compose/data/run/token-url.txt
```

### 0.3.0 UI/functional acceptance supplement (2026-11-10, no KVM)

Used Playwright + Chromium to log in to the DSM desktop and operate item by item; screenshots are saved in
`docs/acceptance-0.3.0/`.

| Item | Result | Evidence/conclusion |
| --- | --- | --- |
| DSM login, desktop | Pass | 1440×1000 screenshot; Package Center/Container Manager can be launched |
| Package Center manual install upload | Pass | After selecting the SPK, the third-party package confirmation page appears |
| Install wizard ENU | Pass (fixed) | Long labels previously squeezed input fields to 1 character wide; after shortening `desc`, all 6 input fields and defaults display fully, see `01-install-wizard.png` |
| Wizard validation | Pass | `/tmp` triggers "minimum length 6"; port/path validation tightened to `/volumeN/...` and 1025–65535, see `02-wizard-validation.png` |
| Install confirmation page | Pass | Shows package name, version, developer, description, and "Run after installation" |
| Install execution | **Fail (worker, needs DSM-side workaround)** | Succeeded once with "remove `container_name` + Docker API proxy rewriting stop's 304 to 204"; after removing the proxy, repair/upgrade/reinstall consistently fail at the worker stage: `fail compose up '<uuid>'` / code 276/278, see `03-install-failure.png` |
| Installed list/error state | Pass (display) | DSHD shows Error, "Please re-install…", see `04-package-center-error.png` |
| `synopkg start/status` | Partial pass | On the successful install, start returned success and the container was running; status was constantly 3 because `do_status` did not load the config — fixed; after the fix status=0 |
| CLI links | Pass | `/usr/local/bin/dshd`, `dshd-token` point to target; `dshd token` works |
| `dshd doctor` | Pass (fixed) | After adding `--project-name dshd` it recognizes `dshd-dshd-1` as running; the compose path in `dshd logs` was also fixed |
| Container port | Pass | `127.0.0.1:3080->3080/tcp`, 0.0.0.0 not published |
| token / HTTP | Pass | token URL 303, 200 after cookie; unauthenticated 401 |
| dsh Web UI | Pass (image level) | The same image renders the complete workspace in the host's `dshd-test` container, see `06-dsh-web-ui.png`; the SPK container is on the DSM internal network and was not reached directly from the host |
| Container Manager UI | Pass (UI) | Overview/Project/Container/Image/Log can be opened; manually composed projects are not registered in the DSM project list, showing "No projects created", see `05-container-manager.png` |
| Reverse proxy/firewall/WebSocket | Not passed/not done | Installation was blocked, so this step was not reached |
| Upgrade 0.2.0→0.3.0 | **Fail** | upgrade failed at `last_stage=start`; the container was only Created, not Started, and the package became broken; needs retesting on native DSM |
| Uninstall/data retention | Incomplete | Uninstall/cleanup works in the failed-install state, but "data retained after upgrade" was not verified |

Root-cause correction: the earlier judgment that "first start takes 90–120 seconds under TCG and exceeds the worker timeout" was inaccurate.
Docker API logs show the worker completes create within seconds, then calls
`POST /containers/{id}/stop` and delete, **never calling start**; for a container that is only
created and not running, Docker returns `304 Not Modified`, which the worker treats
as a `compose up` failure. One successful install (stage=`installed_and_stopped`)
occurred with "remove `container_name` + a test-only Unix socket proxy rewriting 304 to
204"; but the same configuration could not be reproduced reliably afterward, and removing the proxy immediately returned to 276/278. Therefore
it can be concluded that the problem lies in the worker's stop/state judgment for a "container not running after create",
not in the package scripts or slow dsh startup; that 304→204 proxy was only a localization tool and must not enter the release package.
After failure the worker also deletes the `dshd-synology:0.3.0` tag; before retrying it must be re-tagged,
otherwise compose will try to pull from the network (this VirtualDSM has no external network).

Conclusion: **the UI layer is usable (wizard width/validation fixed), but the VirtualDSM Container
Manager worker still cannot reliably complete the install/upgrade loop; this cannot be used to claim that all functional acceptance passed.**
The next step should be to retest the worker on native DSM 7.2 or a KVM-enabled VirtualDSM, or switch to
Container Manager's `docker` resource for a control experiment.
