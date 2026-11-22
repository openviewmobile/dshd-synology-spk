#!/usr/bin/env bash
# Export a locally built image to dist/ for Container Manager's "Import image".
#
#   scripts/export-image.sh                     # tag from spk/INFO
#   DSHD_IMAGE=dshd-synology:amd64 scripts/export-image.sh
#
# On the NAS:
#   docker load < dshd-image-0.3.0-amd64.tar.gz
# or Container Manager -> Image -> Add -> From file.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n 's/^version="\(.*\)"$/\1/p' "$ROOT/spk/INFO" | head -n 1)"
TAG="${DSHD_IMAGE:-dshd-synology:$VERSION}"
ARCH="$(docker image inspect -f '{{.Architecture}}' "$TAG" 2>/dev/null || true)"
[ -n "$ARCH" ] || { echo "image $TAG is not present" >&2; exit 1; }
OUT="$ROOT/dist/dshd-image-$VERSION-$ARCH.tar.gz"
mkdir -p "$ROOT/dist"
printf 'exporting %s (%s) -> %s\n' "$TAG" "$ARCH" "$OUT"
docker save "$TAG" | gzip -c > "$OUT"
( cd "$ROOT/dist" && shasum -a 256 "$(basename "$OUT")" > "$(basename "$OUT").sha256" 2>/dev/null ||
  sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256" )
cat "$OUT.sha256"
