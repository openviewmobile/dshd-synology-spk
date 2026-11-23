# GitHub Actions definitions

These workflow definitions are kept here because the first publication token did
not include GitHub's `workflow` OAuth scope. To activate them:

```bash
mkdir -p .github/workflows
cp ci/github-actions/build-spk.yml ci/github-actions/build-and-release.yml .github/workflows/
git add .github/workflows
git commit -m "ci: enable checks and SPK build workflows"
git push
```

The push account must have the `workflow` scope:

```bash
gh auth refresh -h github.com -s workflow
```

`check.yml` runs static checks, shell syntax, JSON validity, and the English-docs
guard. `build-spk.yml` builds one selected architecture manually. `build-and-release.yml`
builds both x86_64 and armv8 SPKs and can attach them to the v0.4.0 release.
