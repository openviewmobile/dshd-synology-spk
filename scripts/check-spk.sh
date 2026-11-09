#!/usr/bin/env bash
# Build both SPK variants and validate their member layout without DSM.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$ROOT/spk/build-spk.sh" "$TMP" >/dev/null
"$ROOT/spk-docker-project/build-spk.sh" "$TMP" >/dev/null

for spk in "$TMP"/*.spk; do
  echo "== $(basename "$spk")"
  tar -tf "$spk" | grep -q '^INFO$'
  tar -tf "$spk" | grep -q '^package.tgz$'
  mkdir -p "$TMP/x"
  rm -rf "$TMP/x"/*
  tar -xf "$spk" -C "$TMP/x"
  test -f "$TMP/x/INFO"
  tar -tzf "$TMP/x/package.tgz" | grep -q 'docker-compose.yml'
  echo "structure OK"
done
