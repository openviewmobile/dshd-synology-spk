# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
semantic versioning for package releases.

## [0.4.0] - 2026-11-10

### Added

- Native DSM 7.2 package (`spk-native/`): bundled Node 24 + `@deepseek-ai/dsh`
  runtime, no Docker or Container Manager dependency.
- x86_64 and armv8 build targets.
- Package Center install wizard for dsh home, workspace, port, public URL, and
  trusted host.
- `dshd` CLI with `status`, `token`, `logs`, `doctor`, `restart`, `config`, and
  `version`.
- Default-workspace fix using a `workspace-controller.documentsDirectory` overlay
  and a stable symlink.
- Native runtime `TMPDIR=/dev/shm/dshd` workaround for DSM's `mmap(PROT_EXEC)`
  restrictions.
- Subpath reverse-proxy guidance (`location ^~`) and WebSocket verification.
- GitHub release, contribution, security, and CI materials.
- Hyperframes + three.js promotional video project.

### Changed

- Recommended package is now the native implementation. The Docker package is
  retained as `spk/` for legacy/historical use.
- Documentation is written in English.

### Fixed

- `--patch` must follow the `web` profile command; ordering now matches the dsh
  launcher contract.
- Workspace overlay is mode `0644` so the package user can read it even when the
  package was started by root during an upgrade.
- Stale root-owned runtime files no longer block a package-user start.
- Reboot auto-start is verified on VirtualDSM.

### Known limitations

- Real DSM hardware and ARM DSM boot are not yet verified.
- A real model chat turn requires a DeepSeek API key and was not part of acceptance.
- The final Apply click in the Package Center wizard was not completed on QEMU TCG;
  installation was completed with `synopkg install`.
- Community SPKs are unsigned.

## [0.3.0] - 2026-11-09

### Added

- DSM 7 SPK using Container Manager's `docker-project` worker.
- Token extraction, port registration, reverse-proxy guidance, and lifecycle
  scripts.
- VirtualDSM UI/worker investigation and evidence.

### Known limitations

- Container Manager worker install/upgrade is unreliable on VirtualDSM without
  KVM; see `docs/testing.md`.

## [0.2.0] - 2026-11-08

### Added

- Initial SPK shell, icon generation, Docker Compose packaging, and local checks.
