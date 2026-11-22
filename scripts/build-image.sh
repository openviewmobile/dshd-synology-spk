#!/usr/bin/env bash
# Build the headless dsh image used by the SPK and the standalone Compose file.
#
#   scripts/build-image.sh                       # host platform, tag from INFO
#   PLATFORM=linux/amd64 scripts/build-image.sh  # x86_64 NAS
#   PLATFORM=linux/arm64 scripts/build-image.sh  # armv8 NAS
#
# Set NODE_IMAGE / NPM_REGISTRY / APT_MIRROR to override the defaults.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n 's/^version="\(.*\)"$/\1/p' "$ROOT/spk/INFO" | head -n 1)"
TAG="${DSHD_IMAGE:-dshd-synology:$VERSION}"
PLATFORM="${PLATFORM:-}"

args=(build -t "$TAG" -f "$ROOT/Dockerfile")
if [ -n "$PLATFORM" ]; then
  args+=(--platform "$PLATFORM")
fi
if [ -n "${NODE_IMAGE:-}" ]; then
  args+=(--build-arg "NODE_IMAGE=$NODE_IMAGE")
fi
if [ -n "${NPM_REGISTRY:-}" ]; then
  args+=(--build-arg "NPM_REGISTRY=$NPM_REGISTRY")
fi
if [ -n "${APT_MIRROR:-}" ]; then
  args+=(--build-arg "APT_MIRROR=$APT_MIRROR")
fi
args+=("$ROOT")

printf 'building %s%s\n' "$TAG" "${PLATFORM:+ for $PLATFORM}"
docker "${args[@]}"
docker image inspect -f '{{.RepoTags}} {{.Architecture}}/{{.Os}}' "$TAG"
