#!/usr/bin/env bash
# Build both SPK variants and validate everything that can be checked without
# DSM hardware: archive members, INFO, icons, package.tgz, compose rendering,
# JSON, protocol file, executable/shell syntax, and a fake-Docker lifecycle run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PNG_SIZE="$ROOT/spk/tools/png-size.py"

pass() { printf '  ok: %s\n' "$*"; }
fail() { printf '  FAIL: %s\n' "$*" >&2; exit 1; }

info_value() {
  sed -n "s/^$1=\"\\(.*\\)\"$/\\1/p" "$2" | head -n 1
}

require_member() {
  local spk="$1" member="$2"
  tar -tf "$spk" | grep -qxF "$member" ||
    fail "$(basename "$spk"): missing SPK member $member"
}

check_info() {
  local x="$1" name="$2"
  local info="$x/INFO"
  local keys=(
    package version displayname description maintainer distributor arch
    os_min_ver startable ctl_stop support_conf_folder category support_center
  )
  for key in "${keys[@]}"; do
    [ -n "$(info_value "$key" "$info")" ] ||
      fail "$name: INFO key '$key' missing or empty"
  done
  [ "$(info_value package "$info")" = "dshd" ] ||
    fail "$name: package must be dshd"
  [ "$(info_value version "$info")" = "0.3.0" ] ||
    fail "$name: version must be 0.3.0"
  [ "$(info_value startable "$info")" = "yes" ] ||
    fail "$name: startable must be yes"
  [ "$(info_value ctl_stop "$info")" = "yes" ] ||
    fail "$name: ctl_stop must be yes"
  [ "$(info_value support_conf_folder "$info")" = "yes" ] ||
    fail "$name: support_conf_folder must be yes"
  [ "$(info_value support_center "$info")" = "no" ] ||
    fail "$name: support_center must be no"
  [ "$(info_value arch "$info")" = "x86_64 armv8" ] ||
    fail "$name: arch must be x86_64 armv8"
  dep=$(info_value install_dep_packages "$info")
  [ -z "$dep" ] || [ "$dep" = "ContainerManager" ] ||
    fail "$name: unexpected dependency: $dep"
  [[ "$(info_value os_min_ver "$info")" == 7.2-* ]] ||
    fail "$name: os_min_ver must target DSM 7.2"
  pass "$name: INFO keys/values"
}

check_icons() {
  local x="$1" name="$2"
  [ "$(python3 "$PNG_SIZE" "$x/PACKAGE_ICON.PNG")" = "72x72" ] ||
    fail "$name: PACKAGE_ICON.PNG must be 72x72"
  [ "$(python3 "$PNG_SIZE" "$x/PACKAGE_ICON_256.PNG")" = "256x256" ] ||
    fail "$name: PACKAGE_ICON_256.PNG must be 256x256"
  pass "$name: icon dimensions"
}

check_scripts() {
  local x="$1" name="$2"
  local scripts=(start-stop-status token dshd installer preinst postinst preuninst preupgrade postupgrade)
  for script in "${scripts[@]}"; do
    [ -f "$x/scripts/$script" ] || fail "$name: missing scripts/$script"
    [ -x "$x/scripts/$script" ] || fail "$name: scripts/$script is not executable"
    sh -n "$x/scripts/$script" || fail "$name: shell syntax error in scripts/$script"
  done
  sh -n "$x/scripts/start-stop-status" ||
    fail "$name: start-stop-status shell syntax"
  pass "$name: scripts executable and shell syntax"
}

check_json_and_sc() {
  local x="$1" name="$2" target="$3"
  python3 -m json.tool "$x/conf/privilege" >/dev/null ||
    fail "$name: conf/privilege is not valid JSON"
  python3 -m json.tool "$x/conf/resource" >/dev/null ||
    fail "$name: conf/resource is not valid JSON"
  python3 - "$x/conf/privilege" <<'PY' || fail "$name: privilege must run as package"
import json, sys
p = json.load(open(sys.argv[1]))
assert p["defaults"]["run-as"] == "package", p
PY
  python3 - "$x/conf/resource" <<'PY' || fail "$name: resource lacks port-config"
import json, sys
r = json.load(open(sys.argv[1]))
assert r["port-config"]["protocol-file"] == "port_conf/dshd.sc", r
assert "docker-project" in r or "docker" in r, r
PY
  [ -f "$target/port_conf/dshd.sc" ] ||
    fail "$name: package.tgz missing port_conf/dshd.sc"
  grep -qx '\[dshd_web\]' "$target/port_conf/dshd.sc" ||
    fail "$name: dshd.sc missing [dshd_web] section"
  grep -q '^dst.ports="3080/tcp"' "$target/port_conf/dshd.sc" ||
    fail "$name: dshd.sc must register 3080/tcp"
  pass "$name: JSON config and port registration"
}

check_wizard() {
  local x="$1" name="$2"
  for uifile in install_uifile install_uifile_chs install_uifile_cht; do
    local f="$x/WIZARD_UIFILES/$uifile"
    [ -f "$f" ] || fail "$name: missing WIZARD_UIFILES/$uifile"
    python3 - "$f" <<'PYWIZ' || fail "$name: invalid wizard $uifile"
import json, sys
data = json.load(open(sys.argv[1]))
assert isinstance(data, list) and data, data
items = data[0]["items"][0]["subitems"]
keys = {i["key"] for i in items}
for key in ("DSHD_DATA_DIR", "DSHD_WORKSPACE_DIR", "DSHD_PORT",
            "DSHD_IMAGE", "DSH_PUBLIC_URL", "DSH_TRUSTED_HOST"):
    assert key in keys, (key, keys)
for item in items:
    assert item.get("defaultValue") is not None, item
    assert item.get("validator"), item
PYWIZ
  done
  pass "$name: install wizard JSON"
}

check_package_tgz() {
  local x="$1" name="$2"
  local tgz="$x/package.tgz"
  [ -f "$tgz" ] || fail "$name: missing package.tgz"
  local members
  members="$(tar -tzf "$tgz" | sed 's#^\./##')"
  for required in \
    docker-compose.yml \
    config.env.example \
    port_conf/dshd.sc
  do
    grep -qxF "$required" <<<"$members" ||
      fail "$name: package.tgz missing $required"
  done
  if grep -Eq '(^|/)(\.DS_Store|\._)' <<<"$members"; then
    fail "$name: package.tgz contains macOS metadata files"
  fi
  pass "$name: package.tgz contents"
}

check_compose() {
  local x="$1" name="$2"
  local compose="$x/target/docker-compose.yml"
  local envfile="$x/target/config.env.example"
  [ -f "$compose" ] || fail "$name: missing docker-compose.yml"
  [ -f "$envfile" ] || fail "$name: missing config.env.example"

  for var in DSHD_IMAGE DSHD_ALLOW_PULL DSHD_PORT DSHD_DATA_DIR \
             DSHD_WORKSPACE_DIR DSH_PUBLIC_URL DSH_TRUSTED_HOST \
             DSHD_MEM_LIMIT DSHD_CPUS DSHD_PIDS_LIMIT \
             DSHD_LOG_MAX_SIZE DSHD_LOG_MAX_FILE DSHD_MIN_FREE_MB; do
    grep -q "^${var}=" "$envfile" ||
      fail "$name: config.env.example missing $var"
  done
  grep -q '\${DSHD_IMAGE' "$compose" ||
    fail "$name: compose image is not parameterized"
  grep -q '\${DSHD_DATA_DIR' "$compose" ||
    fail "$name: compose data path is not parameterized"
  grep -q '\${DSH_PUBLIC_URL' "$compose" ||
    fail "$name: compose public URL is not parameterized"
  grep -q '127.0.0.1:\${DSHD_PORT' "$compose" ||
    fail "$name: compose must publish on 127.0.0.1"
  if grep -RIn 'example\.com' "$x/target" >/dev/null 2>&1; then
    fail "$name: packaged defaults still contain example.com"
  fi

  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    if ! docker compose --env-file "$envfile" -f "$compose" config >"$x/compose.out" 2>"$x/compose.err"; then
      cat "$x/compose.err" >&2
      fail "$name: docker compose config failed"
    fi
    grep -q 'image: dshd-synology:0.3.0' "$x/compose.out" ||
      fail "$name: rendered image tag is wrong"
    grep -q 'host_ip: 127.0.0.1' "$x/compose.out" ||
      fail "$name: rendered port is not bound to 127.0.0.1"
    grep -q 'DSH_PUBLIC_URL: http://127.0.0.1:3080' "$x/compose.out" ||
      fail "$name: rendered DSH_PUBLIC_URL is wrong"
    grep -q 'healthcheck:' "$x/compose.out" ||
      fail "$name: compose healthcheck missing"
    grep -q 'pids_limit: 512' "$x/compose.out" ||
      fail "$name: compose pids_limit missing"
    grep -q 'no-new-privileges:true' "$x/compose.out" ||
      fail "$name: compose no-new-privileges missing"
    grep -q 'max-size: 10m' "$x/compose.out" ||
      fail "$name: compose log rotation missing"
    grep -q 'cap_drop:' "$x/compose.out" ||
      fail "$name: compose cap_drop missing"
    if grep -q 'example\.com' "$x/compose.out"; then
      fail "$name: rendered compose contains example.com"
    fi
    pass "$name: docker compose config"
  else
    printf '  WARN: docker compose unavailable; skipped compose rendering\n'
  fi
}

check_main() {
  local spk="$1"
  local name
  name="$(basename "$spk")"
  echo "== $name"

  local members
  members="$(tar -tf "$spk")"
  for required in \
    INFO package.tgz conf/privilege conf/resource \
    scripts/start-stop-status scripts/token scripts/dshd scripts/installer \
    scripts/postinst scripts/preuninst scripts/preupgrade scripts/postupgrade \
    WIZARD_UIFILES/install_uifile WIZARD_UIFILES/install_uifile_chs \
    WIZARD_UIFILES/install_uifile_cht \
    PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG
  do
    require_member "$spk" "$required"
  done
  if grep -q '^package/' <<<"$members"; then
    fail "$name: package/ files must live inside package.tgz"
  fi
  pass "$name: SPK members"

  local x="$TMP/main-x"
  mkdir -p "$x"
  tar -xf "$spk" -C "$x"
  mkdir -p "$x/target"
  tar -xzf "$x/package.tgz" -C "$x/target"

  check_info "$x" "$name"
  check_icons "$x" "$name"
  check_scripts "$x" "$name"
  check_json_and_sc "$x" "$name" "$x/target"
  check_wizard "$x" "$name"
  check_package_tgz "$x" "$name"
  check_compose "$x" "$name"
  echo "structure OK"
}

mkdir -p "$TMP/main"
MAIN_SPK="$("$ROOT/spk/build-spk.sh" "$TMP/main")"

check_main "$MAIN_SPK"

echo "== lifecycle smoke (fake Docker CLI)"
bash "$ROOT/scripts/test-spk-lifecycle.sh" "$MAIN_SPK"

echo "all SPK checks OK"
