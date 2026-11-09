#!/usr/bin/env bash
# Build a plain (unsigned) DSM 7 SPK scaffold. Run from this directory.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/../dist}"
mkdir -p "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$HERE/INFO" "$TMP/INFO"
cp -a "$HERE/conf" "$HERE/scripts" "$TMP/"
cp -a "$HERE/package" "$TMP/package"
tar -czf "$TMP/package.tgz" -C "$TMP" package
rm -rf "$TMP/package"
chmod 755 "$TMP/scripts/start-stop-status"
( cd "$TMP" && tar -cf "$OUT/dshd-0.1.0.spk" INFO package.tgz conf scripts )
echo "$OUT/dshd-0.1.0.spk"
