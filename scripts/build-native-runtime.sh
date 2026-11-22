#!/usr/bin/env bash
# Extract a self-contained Node + dsh runtime from the existing build image
# into spk-native/package/runtime. The resulting SPK runs dsh natively; Docker
# is only used here, at build time, to produce a reproducible runtime.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${TARGET:-$ROOT/spk-native/package/runtime}"
IMAGE="${DSHD_IMAGE:-dshd-synology:amd64}"
PLATFORM="${PLATFORM:-linux/amd64}"

docker image inspect "$IMAGE" >/dev/null 2>&1 || {
  printf 'building image %s for %s\n' "$IMAGE" "$PLATFORM" >&2
  PLATFORM="$PLATFORM" DSHD_IMAGE="$IMAGE" "$ROOT/scripts/build-image.sh"
}
CID=$(docker create --platform "$PLATFORM" --entrypoint /bin/sh "$IMAGE" -c 'sleep 1')
trap 'docker rm -f "$CID" >/dev/null 2>&1 || true' EXIT
rm -rf "$TARGET"
mkdir -p "$TARGET"
docker cp "$CID:/usr/local/bin/node" "$TARGET/node"
docker cp "$CID:/usr/local/lib/node_modules" "$TARGET/node_modules"
# npm/pnpm/corepack are build-time only and are not needed by dsh web.
rm -rf "$TARGET/node_modules/npm" "$TARGET/node_modules/pnpm" "$TARGET/node_modules/corepack"
# AppleDouble/xattr sidecars from a previous host extraction are not runtime data.
find "$TARGET" \( -name '._*' -o -name '.DS_Store' \) -delete 2>/dev/null || true
chmod 0755 "$TARGET/node"
file "$TARGET/node" 2>/dev/null || true
du -sh "$TARGET"
printf 'runtime written to %s\n' "$TARGET"
