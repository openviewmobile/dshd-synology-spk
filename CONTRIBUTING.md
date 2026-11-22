# Contributing to DSHD for Synology DSM

Thanks for helping improve DSHD. This repository contains DSM package tooling,
documentation, and acceptance evidence. Please keep changes focused and include
enough context for a reviewer to reproduce them.

## Before you start

- Read [README.md](README.md), [SECURITY.md](SECURITY.md), and the relevant package
  README (`spk-native/README.md` for 0.4.x, `spk/README.md` for the legacy Docker
  package).
- For security issues, do **not** open a public issue. Follow [SECURITY.md](SECURITY.md).
- Never commit real NAS credentials, API keys, token URLs, DSM serial numbers, or
  private screenshots. Test with a disposable VM.

## Development setup

Requirements:

- Python 3.11+
- Bash and standard Unix tools
- Docker (only for building the native runtime and the legacy image)
- Node.js 22+ (only for repository tooling and the Hyperframes promo project)
- FFmpeg (for the promo video)

Useful checks:

```bash
make native-check        # static checks for the native package
make check               # legacy SPK structure + lifecycle checks
scripts/check-spk-native.sh
python3 -m json.tool spk-native/conf/resource >/dev/null
```

Build a native SPK:

```bash
make native-runtime
make native-spk
```

Build the armv8 package:

```bash
make native-armv8-runtime
make native-armv8-spk
```

The built runtimes are large and intentionally ignored by Git. Do not commit
`spk-native/package/runtime*` or `dist/`.

## Pull requests

- Describe the problem, the change, and the verification performed.
- Include the DSM version, architecture, and whether the test was on real hardware
  or VirtualDSM.
- Keep documentation and code in **English**. The package UI may contain localized
  strings, but repository docs and comments should be English.
- If you change package behavior, update the relevant README and, when applicable,
  add a note to `docs/testing.md` with reproducible evidence.
- Do not mix large generated artifacts into a code PR. Attach checksums or a release
  link instead.

## Commit style

Use a short imperative subject, optionally with a scope:

```text
fix(native): keep the workspace overlay readable by the package user
docs: translate the acceptance record to English
feat(video): add the Hyperframes promo composition
```

## Tests and evidence

For native package changes, at minimum:

```bash
make native-check
sh -n spk-native/scripts/*
```

For lifecycle changes, test install, start, stop, restart, and uninstall in a
disposable DSM VM. Remove tokens and credentials from logs before attaching them.
For UI changes, include a screenshot or a short screen recording.

## License

By contributing, you agree that your contribution is licensed under the repository's
MIT license (see [LICENSE](LICENSE)).
