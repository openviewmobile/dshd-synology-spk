#!/usr/bin/env bash
# End-to-end SPK test against a real Docker daemon and a real dsh image.
#
# This is deliberately NOT part of `make check`: it starts a container, binds a
# loopback port, and takes roughly a minute. It exercises the parts a fake
# Docker CLI cannot: compose interpolation, bind mounts, container startup,
# token extraction from real dsh logs, cookie exchange, the Host/Origin fence,
# and stop/cleanup.
#
#   DSHD_TEST_IMAGE=dshd-synology:test scripts/test-spk-docker.sh dist/dshd-0.3.0.spk
#
# Requirements: Docker + Compose v2 on the host, and the image present locally.
set -euo pipefail

SPK="${1:?usage: test-spk-docker.sh /path/to/dshd.spk}"
IMAGE="${DSHD_TEST_IMAGE:-dshd-synology:test}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'cleanup' EXIT

cleanup() {
  if [ -f "$TMP/var/config.env" ]; then
    SYNOPKG_PKGDEST="$TMP/target" SYNOPKG_PKGVAR="$TMP/var" \
      "$TMP/spk/scripts/start-stop-status" stop >/dev/null 2>&1 || true
  fi
  docker rm -f "dshd-dshd-1" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
fail() { printf 'e2e: %s\n' "$*" >&2; exit 1; }
pass() { printf '  ok: %s\n' "$*"; }

command -v docker >/dev/null 2>&1 || fail "docker not found"
docker compose version >/dev/null 2>&1 || fail "docker compose v2 not found"
docker image inspect "$IMAGE" >/dev/null 2>&1 || fail "image $IMAGE is not present"
[ -z "$(docker ps -q -f name=^/dshd-dshd-1\$)" ] ||
  fail "a container named dshd-dshd-1 is already running; stop it first"

mkdir -p "$TMP/spk" "$TMP/target" "$TMP/var" "$TMP/bin"
tar -xf "$SPK" -C "$TMP/spk"
tar -xzf "$TMP/spk/package.tgz" -C "$TMP/target"
# Mirrors /var/packages/dshd: INFO + scripts live next to target/.
cp "$TMP/spk/INFO" "$TMP/INFO"
cp -R "$TMP/spk/scripts" "$TMP/scripts"

# Ask the kernel for a free loopback port.
PORT=$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)

cat > "$TMP/var/config.env" <<EOF
DSHD_IMAGE=$IMAGE
DSHD_ALLOW_PULL=no
DSHD_PORT=$PORT
DSHD_DATA_DIR=$TMP/var/data
DSHD_WORKSPACE_DIR=$TMP/var/work
DSH_PUBLIC_URL=http://127.0.0.1:$PORT
DSH_TRUSTED_HOST=127.0.0.1
DSHD_PUID=1001
DSHD_PGID=1001
DSHD_START_TIMEOUT=90
DSHD_MIN_FREE_MB=1
DSHD_ALLOW_EMULATION=yes
DSHD_MEM_LIMIT=2g
DSHD_CPUS=2.0
DSHD_PIDS_LIMIT=512
DSHD_LOG_MAX_SIZE=5m
DSHD_LOG_MAX_FILE=2
EOF

export SYNOPKG_PKGDEST="$TMP/target"
export SYNOPKG_PKGVAR="$TMP/var"
export DSHD_TOKEN_LINK="$TMP/bin/dshd-token"
export DSHD_CLI_LINK="$TMP/bin/dshd"

# The image runs uid 1001. On Docker Desktop bind mounts preserve the host
# uid, so make the test directories writable for the container user.
"$TMP/spk/scripts/installer" init >"$TMP/install.log" 2>&1 ||
  { cat "$TMP/install.log" >&2; fail "installer init failed"; }
chmod -R 0777 "$TMP/var/data" "$TMP/var/work" 2>/dev/null || true

"$TMP/spk/scripts/start-stop-status" start >"$TMP/start.log" 2>&1 ||
  { cat "$TMP/start.log" >&2; docker logs dshd-dshd-1 2>&1 | tail -40 >&2 || true; fail "start failed"; }
[ -s "$TMP/var/token-url.txt" ] || fail "token file is missing"
TOKEN_URL=$(cat "$TMP/var/token-url.txt")
case "$TOKEN_URL" in
  "http://127.0.0.1:$PORT/?token="*) ;;
  *) fail "unexpected token URL: $TOKEN_URL" ;;
esac
pass "real container start and token extraction"

code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/")
[ "$code" = "401" ] || fail "unauthenticated request returned $code, expected 401"
pass "unauthenticated request is 401"

jar="$TMP/cookies.txt"
code=$(curl -s -c "$jar" -o /dev/null -w '%{http_code}' "$TOKEN_URL")
[ "$code" = "303" ] || fail "token exchange returned $code, expected 303"
pass "token exchange redirects and sets a cookie"

code=$(curl -s -b "$jar" -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/")
[ "$code" = "200" ] || fail "authenticated request returned $code, expected 200"
pass "authenticated UI is 200"

"$TMP/bin/dshd" status >"$TMP/cli-status.out" 2>&1 || true
grep -q '^state=running' "$TMP/cli-status.out" ||
  { cat "$TMP/cli-status.out" >&2; fail "dshd status does not report running"; }
pass "dshd status"

# Restart with a reverse-proxy-style public origin and verify the Host fence.
"$TMP/spk/scripts/start-stop-status" stop >"$TMP/stop.log" 2>&1 ||
  { cat "$TMP/stop.log" >&2; fail "stop failed"; }
grep -q '^state=stopped' "$TMP/var/status" || fail "stop did not write stopped status"

sed -i.bak \
  -e "s#^DSH_PUBLIC_URL=.*#DSH_PUBLIC_URL=http://dsh.example.net:$PORT#" \
  -e 's#^DSH_TRUSTED_HOST=.*#DSH_TRUSTED_HOST=dsh.example.net#' \
  "$TMP/var/config.env"
rm -f "$TMP/var/config.env.bak"

"$TMP/spk/scripts/start-stop-status" start >"$TMP/start-proxy.log" 2>&1 ||
  { cat "$TMP/start-proxy.log" >&2; fail "reverse-proxy-configured start failed"; }
TOKEN_URL=$(cat "$TMP/var/token-url.txt")
case "$TOKEN_URL" in
  "http://dsh.example.net:$PORT/?token="*) ;;
  *) fail "public URL was not used in the token link: $TOKEN_URL" ;;
esac
query=${TOKEN_URL#*\?}
code=$(curl -s -H 'Host: dsh.example.net' -o /dev/null -w '%{http_code}' \
  "http://127.0.0.1:$PORT/?$query")
[ "$code" = "303" ] || fail "Host/Origin-fenced token exchange returned $code, expected 303"
pass "reverse-proxy Host fence accepts the configured public origin"


"$TMP/spk/scripts/start-stop-status" stop >"$TMP/stop2.log" 2>&1 ||
  { cat "$TMP/stop2.log" >&2; fail "second stop failed"; }
[ -z "$(docker ps -q -f name=^/dshd-dshd-1\$)" ] || fail "container still running after stop"
[ ! -e "$TMP/var/token-url.txt" ] || fail "token file was not removed on stop"
pass "stop removes the container and token"

"$TMP/spk/scripts/installer" cleanup >"$TMP/cleanup.log" 2>&1 ||
  { cat "$TMP/cleanup.log" >&2; fail "installer cleanup failed"; }
[ -f "$TMP/var/config.env" ] || fail "uninstall deleted config.env"
[ -d "$TMP/var/data/home" ] || fail "uninstall deleted user data"
pass "uninstall keeps config and user data"

echo "real Docker e2e OK (image $IMAGE, port $PORT)"
