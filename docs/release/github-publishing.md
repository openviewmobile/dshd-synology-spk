# Publishing DSHD on GitHub

This is the release checklist for the public repository and the `v0.4.0` release.
It covers repository metadata, legal/security material, release assets, CI, and
the YouTube launch. Repository URLs are set to `openviewmobile/dshd-synology-spk`.

## 0. Launch readiness

Prepared in this repository:

- English README, docs, community files, MIT license, third-party notices, and
  package license texts.
- x86_64/armv8 SPKs (0.4.0), verified SHA-256 checksums, release notes, and
  acceptance screenshots.
- GitHub issue forms, PR template, static-check CI, and manual SPK build CI.
- 50-second launch video, YouTube thumbnail, SRT captions, upload metadata, and
  1280×640 social preview.
- `scripts/prepare-release.sh` assembles `release/0.4.0/` and verifies checksums.

Still needed from the maintainer:

1. ~~The GitHub owner/repository name.~~ Resolved: `openviewmobile/dshd-synology-spk`.
2. Confirmation of the copyright holder in `LICENSE` (currently “DSHD project
   contributors”).
3. A GitHub account with Actions and release permissions, then the actual push,
   tag, and upload — none of which this working copy can perform without
   credentials.
4. A YouTube channel/upload and the final public video URL.
5. Optional but recommended before claiming full acceptance: boot the armv8 SPK
   on ARM DSM, complete the Package Center wizard Apply, and test a real model
   chat with a valid API key.

## 1. Repository metadata

- [ ] Repository name: `dshd-synology-spk` (or `dshd-native`).
- [ ] Description: **"Run DeepSeek Harness natively on Synology DSM 7.2 — no Docker."**
- [ ] Website: YouTube video or documentation URL (optional).
- [ ] Topics: `synology`, `dsm`, `spk`, `deepseek`, `ai-agent`, `self-hosted`,
  `nas`, `armv8`, `x86-64`.
- [ ] Social preview image: `docs/social-preview.png` (1280×640).
- [ ] README screenshot renders correctly on GitHub (relative paths).
- [ ] About section uses the one-line pitch; no unverified claims.
- [ ] Default branch is `main`.
- [ ] Discussions enabled (recommended for installation help).
- [ ] Wiki disabled unless it will be maintained.

## 2. Legal and community files

- [x] `LICENSE` — MIT (confirm the copyright holder before release).
- [x] `THIRD_PARTY_NOTICES.md` — Node.js, dsh, and npm dependency inventory.
- [x] `licenses/NODE-LICENSE.txt` and `licenses/DSH-LICENSE.txt`.
- [x] `CONTRIBUTING.md`.
- [x] `SECURITY.md`.
- [x] `CODE_OF_CONDUCT.md`.
- [x] Issue forms and pull-request template.
- [x] Repository URLs point to `openviewmobile/dshd-synology-spk`.
- [ ] Enable private vulnerability reporting in **Settings → Security**.
- [ ] Enable secret scanning and Dependabot alerts.
- [ ] Confirm that the MIT license is compatible with your intended distribution;
  the bundled dsh is MIT, Node.js uses its own permissive license.

## 3. Repository hygiene

- [ ] `git status` contains only intended source/docs; no `dist/`, runtime, logs,
  `.env`, or test data.
- [ ] `git grep -nE 'token=|api[_-]?key|password|DshdTest|dshdadmin'` reviewed;
  screenshots and docs contain no live credentials.
- [ ] Run a secret scanner (e.g. `gitleaks detect --source .` or GitHub secret
  scanning) across the full history, not just the working tree.
- [ ] Remove the temporary `/etc/nginx` test config from any published instructions;
  only the documented reverse-proxy snippet remains.
- [ ] Confirm `.gitignore` excludes `dist/`, runtimes, `.env`, and OS metadata.
- [ ] Add a `CITATION.cff` only if you want an academic citation; not required.

## 4. CI and automation

- [x] Active `.github/workflows/check.yml` — static checks, shell syntax, JSON
  validity, and the English-docs guard.
- [x] Active `.github/workflows/build-and-release.yml` — GitHub-hosted x86_64 /
  armv8 builds that attach SPKs to the release.
- [x] `main` branch protection requires the `static` check and blocks force pushes
  and deletions.
- [ ] Run the `checks` workflow on the first push; add the badge to README if
  desired.
- [ ] Run `build SPK` manually once for each architecture and verify the artifact
  checksum is reproducible enough for release.
- [ ] Protect `main`: require the `checks` workflow and one review.
- [ ] Do not add Docker Hub or npm credentials; the build uses public sources.

## 5. Release assets for `v0.4.0`

Create a tag and GitHub Release:

```bash
git tag -a v0.4.0 -m "DSHD Native 0.4.0"
git push origin main --tags
```

Release title: **DSHD Native 0.4.0 — DeepSeek Harness on DSM without Docker**

Assets:

| Asset | Required | Notes |
|---|---|---|
| `dshd-0.4.0.spk` | Yes | x86_64 package |
| `dshd-0.4.0-armv8.spk` | Yes | armv8 package; state untested on ARM DSM |
| `SHA256SUMS-0.4.0.txt` | Yes | checksums for both SPKs |
| `release-notes-0.4.0.md` | Yes | paste into release body |
| `package-center-branded.png` | Recommended | branded Package Center preview |
| `acceptance-native-web-main.png` | Recommended | UI preview |
| `DSHD-Native-YouTube-thumbnail.png` | Optional | YouTube thumbnail |
| Source code (zip/tar) | Automatic | GitHub-generated |

Use the release body from `docs/release/release-notes-0.4.0.md`. Mark it as the
latest release. Do not attach the 1 GB runtime directories.

## 6. Release body checklist

- [ ] Clear one-line pitch and hero screenshot.
- [ ] Compatibility table (DSM 7.2+, x86_64/armv8).
- [ ] Install steps and token command.
- [ ] SHA-256 checksums.
- [ ] Verification status and known limitations (unsigned, ARM untested, real model
  chat untested).
- [ ] Upgrade/uninstall data-retention behavior.
- [ ] Link to `docs/testing.md`, `SECURITY.md`, and the YouTube video.
- [ ] No claim that the package is Synology-certified or signed.

## 7. Marketing launch kit

- [x] YouTube video rendered from `promo-video/` (1920×1080, 50 s, H.264/AAC).
- [x] YouTube thumbnail 1280×720, high contrast, readable at small size.
- [x] Captions/SRT prepared (`promo-video/DSHD-Native-Promo.srt`).
- [x] Title, description, tags, chapters, and pinned comment prepared from
  `promo-video/youtube-metadata.md`.
- [ ] Upload the video and paste the real URL into the README and release body.
- [ ] End screen and pinned comment point to the GitHub release, not a fake URL.
- [ ] Short vertical clip (9:16) for Shorts/Reddit/X, optional but recommended.
- [ ] Reddit posts: r/synology, r/selfhosted, r/LocalLLaMA (follow each community's
  self-promotion rules).
- [ ] Synology community forum post with install caveats.
- [ ] Do not spam; disclose that you maintain the project.

## 8. Post-release

- [ ] Verify the downloaded SPK checksum from a machine that is not the build host.
- [ ] Install the release artifact on a clean VirtualDSM once more.
- [ ] Create a `v0.4.1` milestone for fixes found after launch.
- [ ] Watch issues for install failures and pin a troubleshooting comment.
- [ ] Add the YouTube link and GitHub release link to README once live.
- [ ] Archive or label the legacy Docker package clearly; avoid recommending it for
  new installs.

## 9. One-command artifact preparation

From a clean checkout with the runtimes built:

```bash
./scripts/prepare-release.sh 0.4.0
```

The script copies both SPKs, checksums, release notes, acceptance screenshots,
the social preview, the YouTube thumbnail, captions, and the normalized MP4 into
`release/0.4.0/`, then verifies both SPK SHA-256 checksums. `release/` is
gitignored; upload its contents to the GitHub Release. The SPKs are large;
GitHub's release asset limit is 2 GB per file, so 213 MB is fine.
