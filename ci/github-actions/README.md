# GitHub Actions definitions

These workflow definitions are kept here because the first publication token did
not include GitHub's `workflow` OAuth scope. To activate them:

```bash
mkdir -p .github/workflows
cp ci/github-actions/*.yml .github/workflows/
git add .github/workflows
git commit -m "ci: enable checks and SPK build workflows"
git push
```

The push account must have the `workflow` scope:

```bash
gh auth refresh -h github.com -s workflow
```

`check.yml` runs static checks, shell syntax, JSON validity, and the English-docs
guard. `build-spk.yml` builds x86_64/armv8 SPKs manually with Docker and QEMU.
