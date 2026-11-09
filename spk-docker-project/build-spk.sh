#!/usr/bin/env bash
# Build the experimental docker-project SPK wrapper. Run from this directory.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/../dist}"
mkdir -p "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$HERE/INFO" "$TMP/INFO"
cp -a "$HERE/conf" "$TMP/conf"
cp -a "$HERE/package" "$TMP/package"
tar -czf "$TMP/package.tgz" -C "$TMP" package
rm -rf "$TMP/package"
( cd "$TMP" && tar -cf "$OUT/dshd-docker-project-0.1.0.spk" INFO package.tgz conf )
echo "$OUT/dshd-docker-project-0.1.0.spk"
