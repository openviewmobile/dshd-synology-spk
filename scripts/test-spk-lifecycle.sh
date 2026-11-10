#!/usr/bin/env bash
# Local smoke test for spk/scripts/start-stop-status using a fake Docker CLI.
#
# This validates the control flow (image check, compose up/down, token
# extraction, status file, failure without a token) without DSM or a real
# container. It does NOT validate Container Manager's actual Docker paths.
set -euo pipefail

SPK="${1:?usage: test-spk-lifecycle.sh /path/to/dshd.spk}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/spk" "$TMP/target" "$TMP/var" "$TMP/data" "$TMP/work" "$TMP/state" "$TMP/bin"
tar -xf "$SPK" -C "$TMP/spk"
tar -xzf "$TMP/spk/package.tgz" -C "$TMP/target"

[ -f "$TMP/target/package/docker-compose.yml" ] || {
  echo "lifecycle: package.tgz extraction failed" >&2
  exit 1
}

FAKE="$TMP/bin/docker"
cat > "$FAKE" <<'FAKE_DOCKER'
#!/bin/sh
set -u
state="${FAKE_DOCKER_STATE:?}"
mode="${FAKE_DOCKER_MODE:-ok}"
case "$*" in
  "compose version"*)
    echo "Docker Compose version v2.29.0"
    ;;
  *"compose"*" up -d"*)
    mkdir -p "$state"
    : > "$state/up"
    echo "compose up"
    ;;
  *"compose"*" ps -q dshd"*)
    [ -f "$state/up" ] && echo "fake-container-id"
    ;;
  *"compose"*" logs"*)
    if [ "$mode" = "notoken" ]; then
      echo "dshd-1 | dsh web: starting without a token"
    else
      echo "dshd-1 | dsh web: http://127.0.0.1:3080/?token=smokeTOKEN123"
    fi
    ;;
  *"compose"*" down"*)
    rm -f "$state/up"
    echo "compose down"
    ;;
  "inspect -f {{.State.Running}} fake-container-id"*)
    if [ -f "$state/up" ]; then echo "true"; else echo "false"; fi
    ;;
  "image inspect "*)
    ;;
  *)
    echo "fake docker: unhandled arguments: $*" >&2
    exit 99
    ;;
esac
FAKE_DOCKER
chmod 0755 "$FAKE"

cat > "$TMP/var/config.env" <<EOF
DSHD_IMAGE=dshd-synology:0.2.0
DSHD_PORT=3080
DSHD_DATA_DIR=$TMP/var/data
DSHD_WORKSPACE_DIR=$TMP/var/work
DSH_PUBLIC_URL=http://127.0.0.1:3080
DSH_TRUSTED_HOST=127.0.0.1
DSHD_PUID=$(id -u)
DSHD_PGID=$(id -g)
DSHD_START_TIMEOUT=4
EOF

export SYNOPKG_PKGDEST="$TMP/target"
export SYNOPKG_PKGVAR="$TMP/var"
export DSHD_DOCKER="$FAKE"
export FAKE_DOCKER_STATE="$TMP/state"
export FAKE_DOCKER_MODE="ok"

CTL="$TMP/spk/scripts/start-stop-status"

"$CTL" start >"$TMP/start.log" 2>&1 || {
  cat "$TMP/start.log" >&2
  echo "lifecycle: start failed" >&2
  exit 1
}
[ "$(cat "$TMP/var/token-url.txt")" = "http://127.0.0.1:3080/?token=smokeTOKEN123" ] || {
  echo "lifecycle: unexpected token file contents" >&2
  exit 1
}
grep -q '^state=running' "$TMP/var/status" || {
  echo "lifecycle: status file is not running" >&2
  exit 1
}
"$CTL" status || {
  echo "lifecycle: status action did not report running" >&2
  exit 1
}

"$CTL" stop >"$TMP/stop.log" 2>&1 || {
  cat "$TMP/stop.log" >&2
  echo "lifecycle: stop failed" >&2
  exit 1
}
[ ! -e "$TMP/var/token-url.txt" ] || {
  echo "lifecycle: token file was not removed on stop" >&2
  exit 1
}
grep -q '^state=stopped' "$TMP/var/status" || {
  echo "lifecycle: status file is not stopped" >&2
  exit 1
}
set +e
"$CTL" status
code=$?
set -e
[ "$code" -eq 3 ] || {
  echo "lifecycle: stopped status should exit 3, got $code" >&2
  exit 1
}

# Token command: happy path and missing file path.
DSHD_TOKEN_FILE="$TMP/var/token-url.txt" "$TMP/spk/scripts/token" >/dev/null 2>&1 && {
  echo "lifecycle: token command should fail when no token exists" >&2
  exit 1
}
printf '%s\n' "http://127.0.0.1:3080/?token=smokeTOKEN123" > "$TMP/token-test.txt"
out="$(DSHD_TOKEN_FILE="$TMP/token-test.txt" "$TMP/spk/scripts/token")"
[ "$out" = "http://127.0.0.1:3080/?token=smokeTOKEN123" ] || {
  echo "lifecycle: token command output mismatch" >&2
  exit 1
}

# Start must fail (and not write a token) when the log has no token line.
export FAKE_DOCKER_MODE="notoken"
: > "$TMP/state/up"
set +e
"$CTL" start >"$TMP/notoken.log" 2>&1
code=$?
set -e
[ "$code" -ne 0 ] || {
  echo "lifecycle: start should fail without a token" >&2
  exit 1
}
[ ! -e "$TMP/var/token-url.txt" ] || {
  echo "lifecycle: token file must not be fabricated" >&2
  exit 1
}
grep -q '^state=failed' "$TMP/var/status" || {
  echo "lifecycle: missing-token status should be failed" >&2
  exit 1
}


# Installer init/cleanup: seed config, create data dirs, install/remove the
# convenience link, and prove user data/config survive cleanup.
INST_ROOT="$TMP/pkgroot"
INST_VAR="$TMP/install-var"
INST_DATA="$INST_VAR/data"
INST_WORK="$INST_VAR/work"
mkdir -p "$INST_ROOT" "$INST_VAR"
cp -R "$TMP/target" "$INST_ROOT/target"
cp -R "$TMP/spk/scripts" "$INST_ROOT/scripts"
python3 - "$INST_ROOT/target/package/config.env.example" \
  "$INST_DATA" "$INST_WORK" <<'PY'
import sys
path, data, work = sys.argv[1:4]
text = open(path).read()
text = text.replace("DSHD_DATA_DIR=/volume1/docker/dshd", f"DSHD_DATA_DIR={data}")
text = text.replace("DSHD_WORKSPACE_DIR=/volume1/dshd-workspace", f"DSHD_WORKSPACE_DIR={work}")
open(path, "w").write(text)
PY

SYNOPKG_PKGDEST="$INST_ROOT/target" SYNOPKG_PKGVAR="$INST_VAR" \
  DSHD_TOKEN_LINK="$TMP/install-dshd-token" \
  "$INST_ROOT/scripts/installer" init >"$TMP/installer-init.log" 2>&1 || {
  cat "$TMP/installer-init.log" >&2
  echo "lifecycle: installer init failed" >&2
  exit 1
}
[ -f "$INST_VAR/config.env" ] && [ -d "$INST_DATA/home" ] && [ -d "$INST_WORK" ] || {
  echo "lifecycle: installer init did not create config/data dirs" >&2
  exit 1
}
[ -L "$TMP/install-dshd-token" ] || {
  echo "lifecycle: installer did not create the token link" >&2
  exit 1
}
printf 'token\n' > "$INST_VAR/token-url.txt"
printf 'state=running\n' > "$INST_VAR/status"
SYNOPKG_PKGDEST="$INST_ROOT/target" SYNOPKG_PKGVAR="$INST_VAR" \
  DSHD_TOKEN_LINK="$TMP/install-dshd-token" \
  "$INST_ROOT/scripts/installer" cleanup >"$TMP/installer-cleanup.log" 2>&1 || {
  cat "$TMP/installer-cleanup.log" >&2
  echo "lifecycle: installer cleanup failed" >&2
  exit 1
}
[ ! -e "$INST_VAR/token-url.txt" ] && [ ! -e "$INST_VAR/status" ] && \
  [ ! -e "$TMP/install-dshd-token" ] || {
  echo "lifecycle: installer cleanup left runtime state/link behind" >&2
  exit 1
}
[ -f "$INST_VAR/config.env" ] && [ -d "$INST_DATA/home" ] && [ -d "$INST_WORK" ] || {
  echo "lifecycle: installer cleanup deleted user data/config" >&2
  exit 1
}

# Stop must still succeed and clean runtime state if Docker is already gone
# (typical during NAS shutdown), but must not claim a running status.
DSHD_DOCKER="$TMP/bin/no-such-docker" "$CTL" stop >"$TMP/stop-nodocker.log" 2>&1 || {
  cat "$TMP/stop-nodocker.log" >&2
  echo "lifecycle: stop without docker should not fail" >&2
  exit 1
}
grep -q '^state=stopped' "$TMP/var/status" || {
  echo "lifecycle: stop without docker did not write stopped status" >&2
  exit 1
}
set +e
DSHD_DOCKER="$TMP/bin/no-such-docker" "$CTL" status >/dev/null 2>&1
code=$?
set -e
[ "$code" -eq 3 ] || {
  echo "lifecycle: status without docker should exit 3, got $code" >&2
  exit 1
}

# Data directories outside /volume (or the package var) must be rejected before
# root creates/chowns anything.
cp "$TMP/var/config.env" "$TMP/var/config.env.bak"
awk '/^DSHD_DATA_DIR=/{print "DSHD_DATA_DIR=/etc"; next} {print}' \
  "$TMP/var/config.env.bak" > "$TMP/var/config.env"
set +e
"$CTL" start >"$TMP/badpath.log" 2>&1
code=$?
set -e
[ "$code" -ne 0 ] || {
  echo "lifecycle: start must reject a data dir outside /volume" >&2
  exit 1
}
mv "$TMP/var/config.env.bak" "$TMP/var/config.env"

echo "lifecycle smoke OK"
