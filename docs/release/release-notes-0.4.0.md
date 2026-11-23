# DeepSeek Harness 0.4.0

**Run DeepSeek Harness natively on Synology DSM 7.2 — no Docker, no Container Manager.**

## Highlights

- Native Node 24 + dsh runtime bundled in the SPK.
- Runs as the unprivileged `dshd` package user.
- Loopback-only listener (`127.0.0.1:3080`) with a `0600` bearer-token URL.
- Package Center install, start/stop, uninstall, and boot auto-start.
- DSM default-workspace fix.
- x86_64 and armv8 builds.

## Artifacts

| File | Architecture | Size | SHA-256 |
|---|---|---|---|
| `dshd-0.4.0.spk` | x86_64 | ~213 MB | `4ee8e49aedbd9e1f9f3296f9a75c7b2555fcb8d45cd1b030418a3b5e62293a2d` |
| `dshd-0.4.0-armv8.spk` | armv8 | ~215 MB | `adfc5d7b0c6418877ce86c21c396f1f9b6be53d513d5e77d315e85c1f8b9426a` |

Verify before installing:

```bash
shasum -a 256 dshd-0.4.0.spk dshd-0.4.0-armv8.spk
```

## Install

1. Download the SPK matching your NAS architecture.
2. Package Center → Manual Install → select the SPK.
3. Accept the third-party package warning.
4. Keep the wizard defaults, or choose a dsh home and workspace under `/volume*`.
5. Start **DeepSeek Harness**.
6. Run `sudo /usr/local/bin/dshd-token` and open the token URL.

## Verification

Verified on VirtualDSM DSM 7.2 (QEMU TCG, x86_64):

- CLI install/start/stop/restart/status/doctor/token/logs.
- Package Center install, stop/run, uninstall UI.
- Reboot auto-start.
- dsh Web UI, WebSocket through a subpath reverse proxy, Settings pages, default
  workspace.
- Migration logic with a legacy Docker config.
- armv8 runtime `dsh --version` in an arm64 container.

Not verified:

- Real DSM hardware, ARM DSM boot.
- A real model API chat turn.
- The wizard's final Apply click (CLI install was used).
- A full legacy Docker data-volume migration.
- DSM Control Panel reverse-proxy GUI/TLS.

## Known issues

- SPKs are unsigned; DSM will warn.
- A custom data/workspace directory must already exist and be writable by `dshd`.
- `/dev/shm` must exist and allow execution.
- The package binds loopback only; remote access requires a reverse proxy.
- The runtime adds about 1 GB on disk.

## Upgrade and uninstall

Upgrades replace the runtime but preserve `var/config.env`, dsh home, and workspace.
Uninstall preserves `/volume1/@appdata/dshd`; remove it manually if you want a full
wipe.

## Links

- Repository: https://github.com/openviewmobile/dshd-synology-spk
- Full acceptance record: `docs/testing.md`
- License: MIT
