# DeepSeek Harness (SPK 0.4.0, no Docker)

Runs headless dsh on DSM 7.2 as **a regular package-user process**, without Docker, Container
Manager, or the `docker-project` worker. Suitable when you want to avoid Docker-in-Docker, or when
Container Manager is not available on the NAS.

## Architecture

```text
Package Center
  └─ /var/packages/dshd/scripts/start-stop-status
       └─ dshd user → target/runtime/node
            └─ dsh web --patch <workspace overlay> --host 127.0.0.1 --port 3080
                 ├─ home:      /volume1/@appdata/dshd/native/home
                 ├─ workspace: /volume1/@appdata/dshd/native/workspace
                 └─ token:     /var/packages/dshd/var/token-url.txt (0600)
```

Key points:

- `target/runtime` bundles the official Node 24 + `@deepseek-ai/dsh`; it does not depend on DSM's
  Node/npm and does not download from the internet.
- Listens only on `127.0.0.1:3080`; external publication must be handled by the DSM reverse proxy.
- Runs as the package user `dshd` (not root); data directories are 0700, the token is 0600.
- **DSM's `/volume1` and `/tmp` do not allow `mmap(PROT_EXEC)` for native addons**,
  so `TMPDIR` is fixed to `/dev/shm/dshd` (tmpfs, executable, readable only by the package user);
  otherwise `require_builtin.node` reports `failed to map segment from shared object`.
- `docker-project` is not used, so install/upgrade/uninstall no longer pass through the Container Manager
  worker; `synopkg install/start/stop` also works on VirtualDSM without KVM.
- The first dsh run creates the default workspace at `<Documents>/deepseek-harness/default-workspace`.
  DSM has no `xdg-user-dir`, so the start script:
  1. writes a read-only overlay `var/dshd-workspace.patch.yml` that points
     `workspace-controller.documentsDirectory` at the package home;
  2. symlinks `deepseek-harness/default-workspace` under the package home to
     `DSHD_WORKSPACE_DIR`.
  This way the Web UI can use the default workspace immediately on first open, avoiding
  "Unable to create default workspace".

## Build

Docker is required only at **build time** to extract a reproducible Node + dsh runtime from the image:

```bash
# 1. Generate spk-native/package/runtime (about 1 GB, gitignored)
scripts/build-native-runtime.sh

# 2. Generate dist/dshd-0.4.0.spk (about 213 MB)
spk-native/build-spk.sh

# Static checks
scripts/check-spk-native.sh
```

armv8 uses the same set of scripts, with its runtime kept separately in `package/runtime-armv8`; INFO's
`arch` is written by a build parameter and does not overwrite the x86_64 package:

```bash
make native-armv8-runtime   # linux/arm64 image + extract the runtime
make native-armv8-spk       # dist/dshd-0.4.0-armv8.spk
```

Note: the armv8 package has been verified for ELF architecture and SPK structure on the build machine (Apple Silicon), but has not yet passed boot acceptance on a real ARM Synology or VM.

## Installation

```bash
sudo synopkg install /volume1/docker/dshd-0.4.0.spk
sudo synopkg start dshd
sudo /usr/local/bin/dshd-token
```

You can also install manually from Package Center; the install wizard only asks for:

- dsh home (under `/volume`, default `/volume1/@appdata/dshd/native/home`)
- Workspace (default `/volume1/@appdata/dshd/native/workspace`)
- Loopback port (1025–65535, default 3080)
- Public access URL, Trusted Host

> Custom data directories must already exist and be writable by `dshd`. The installer runs as the package user and cannot
> create directories under the `/volume1` root; the default `@appdata/dshd/native` is created automatically.
> When migrating from the Docker edition, if the old data is owned by uid 1001, run
> `chown -R dshd:dshd <dir>` as root before pointing the wizard at it.

## Configuration and operations

```bash
sudo vi /var/packages/dshd/var/config.env
sudo synopkg restart dshd        # or dshd restart

/usr/local/bin/dshd status
/usr/local/bin/dshd doctor       # node/runtime/directories/port/token preflight
/usr/local/bin/dshd logs 200
/usr/local/bin/dshd-token
```

| Variable | Default | Description |
|---|---|---|
| `DSHD_DATA_DIR` | `/volume1/@appdata/dshd/native/home` | dsh home |
| `DSHD_WORKSPACE_DIR` | `/volume1/@appdata/dshd/native/workspace` | agent workspace |
| `DSHD_PORT` | `3080` | listens on 127.0.0.1 only |
| `DSH_PUBLIC_URL` | `http://127.0.0.1:3080` | token URL / Web GUI origin |
| `DSH_TRUSTED_HOST` | `127.0.0.1` | dsh Host/Origin validation |
| `DSHD_START_TIMEOUT` | `300` | seconds to wait for the token |

Logs: `/var/packages/dshd/var/log/dsh.log`.
PID: `/var/packages/dshd/var/dshd.pid`.
Upgrade/uninstall preserves `var/config.env`, home, and workspace; only volatile files such as token/PID are removed.

## Reverse proxy

Control Panel → Login Portal → Advanced → Reverse Proxy:

- Source: HTTPS, `dsh.example.net`, 443
- Destination: HTTP, `127.0.0.1`, `3080`
- Custom headers: enable WebSocket

When publishing at the root path:

```ini
DSH_PUBLIC_URL=https://dsh.example.net
DSH_TRUSTED_HOST=dsh.example.net
```

If publishing under a **subpath**, for example `https://nas.example/dshd/`, DSM's bundled
nginx has a server-level regex location for static assets; `^~` is required so that the whole subpath is handed to the
reverse proxy, otherwise `/assets/*.js` is intercepted by DSM's 404 page first:

```nginx
location = /dshd { return 301 /dshd/; }
location ^~ /dshd/ {
    proxy_pass http://127.0.0.1:3080/;
    proxy_http_version 1.1;
    proxy_set_header Host $http_host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_buffering off;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
}
```

Corresponding configuration:

```ini
DSH_PUBLIC_URL=https://nas.example/dshd/
DSH_TRUSTED_HOST=nas.example
```

Do not map 3080 to the router or the LAN.

## Limitations

- No container isolation; the security boundary is the `dshd` package user, 0700 data directories, and loopback-only listening.
- First startup takes about 90–120 seconds on a QEMU TCG VirtualDSM; real hardware is usually faster.
- `/dev/shm` must exist and be executable; this is a prerequisite for loading native addons on DSM.
- The runtime is about 1 GB (SPK about 213 MB); separate x86_64 and armv8 packages are provided, and an upgrade package
  replaces the runtime but not user data.
- `usr-local-linker` creates `/usr/local/bin/dshd*` only during installation; if missing, use
  `/var/packages/dshd/target/bin/dshd` directly.
