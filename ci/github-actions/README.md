# GitHub Actions definitions

These are reference copies of the workflows that are active under
`.github/workflows/`. The live definitions are:

- `.github/workflows/check.yml` — static checks on push and pull request.
- `.github/workflows/build-and-release.yml` — manual x86_64 / armv8 build that
  attaches SPKs to the release.

To update a workflow, edit both the live file and this reference copy, or remove
this directory if the duplicate source becomes hard to maintain.

`check.yml` runs static checks, shell syntax, JSON validity, and the English-docs
guard. `build-spk.yml` builds one selected architecture manually. `build-and-release.yml`
builds both x86_64 and armv8 SPKs and can attach them to the v0.4.0 release.
