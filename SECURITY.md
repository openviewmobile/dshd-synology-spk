# Security policy

## Supported versions

| Version | Supported |
|---|---|
| 0.4.x native | Yes |
| 0.3.x Docker (legacy) | Best effort |
| 0.2.x and earlier | No |

## Report a vulnerability

Please **do not** open a public GitHub issue for a vulnerability.

Use GitHub's private **Report a vulnerability** flow in the Security tab, or email
the maintainers listed in the repository profile. Include:

- affected version and architecture;
- DSM version and whether it is a VM or real hardware;
- a minimal reproduction;
- impact and any known workaround;
- whether the issue affects the package, the bundled dsh runtime, or both.

We will acknowledge reports as soon as possible and coordinate disclosure after a
fix is available. Please allow time for a release before publishing details.

## Threat model and known boundaries

DSHD Native is a **local-only** package:

- dsh binds to `127.0.0.1` by default; the package does not configure a public
  listener or router port forwarding.
- The dsh process runs as the unprivileged package user `dshd`.
- Data directories are `0700` (home) and `0750` (workspace); the token file and
  logs are `0600`.
- The token URL is a bearer credential. Treat it like a password.
- The native package has no container isolation. If you expose the UI through a
  reverse proxy, configure HTTPS and authentication at the proxy, and set
  `DSH_PUBLIC_URL` / `DSH_TRUSTED_HOST` to the exact public origin.
- Do not put secrets in bug reports, screenshots, `config.env` examples, or logs.
- The bundled runtime is an upstream release; report upstream vulnerabilities to
  the relevant project as well when appropriate.

## Package signing

The community SPKs are currently unsigned. DSM will warn about third-party
packages. Verify the SHA-256 checksum from the release page before installing, or
build the package yourself from source.
