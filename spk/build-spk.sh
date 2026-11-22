#!/usr/bin/env bash
# Build the DSHD DSM 7 SPK (plain tar, unsigned; DSM 7 does not require GPG).
#
# Usage: spk/build-spk.sh [OUTPUT_DIR]
# Output: <OUTPUT_DIR>/dshd-<version>.spk (default: ./dist)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/../dist}"
PNG_SIZE="$HERE/tools/png-size.py"
TMP=""

cleanup() { [ -n "$TMP" ] && rm -rf "$TMP"; }
trap cleanup EXIT

info() {
  local key="$1"
  sed -n "s/^${key}=\"\\(.*\\)\"$/\\1/p" "$HERE/INFO" | head -n 1
}

die() {
  printf 'build-spk: %s\n' "$*" >&2
  exit 1
}

# --- Validate INFO ---------------------------------------------------------
[ -f "$HERE/INFO" ] || die "missing INFO"
PKG_NAME="$(info package)"
VERSION="$(info version)"
[ -n "$PKG_NAME" ] || die "INFO: package is empty"
[ -n "$VERSION" ] || die "INFO: version is empty"
[[ "$PKG_NAME" =~ ^[A-Za-z0-9._-]+$ ]] || die "INFO: invalid package id: $PKG_NAME"
[[ "$VERSION" =~ ^[0-9][0-9A-Za-z._-]*$ ]] || die "INFO: invalid version: $VERSION"

required_keys=(
  package version displayname description maintainer distributor arch
  os_min_ver startable ctl_stop support_conf_folder category support_center
)
for key in "${required_keys[@]}"; do
  value="$(info "$key")"
  [ -n "$value" ] || die "INFO: required key '$key' is missing or empty"
done

[[ "$(info arch)" == *"x86_64"* || "$(info arch)" == *"armv8"* ]] ||
  die "INFO: arch must include x86_64 or armv8"
case "$(info os_min_ver)" in
  7.*) ;;
  *) die "INFO: os_min_ver must target DSM 7.x" ;;
esac

# --- Validate required files ----------------------------------------------
required_files=(
  package/docker-compose.yml
  package/config.env.example
  package/port_conf/dshd.sc
  conf/privilege
  conf/resource
  scripts/start-stop-status
  scripts/token
  scripts/dshd
  scripts/installer
  scripts/postinst
  scripts/preuninst
  scripts/preupgrade
  scripts/postupgrade
  WIZARD_UIFILES/install_uifile
  WIZARD_UIFILES/install_uifile_chs
  WIZARD_UIFILES/install_uifile_cht
  PACKAGE_ICON.PNG
  PACKAGE_ICON_256.PNG
)
for rel in "${required_files[@]}"; do
  [ -f "$HERE/$rel" ] || die "missing required file: spk/$rel"
done

[ -f "$PNG_SIZE" ] || die "missing icon dimension helper: spk/tools/png-size.py"

icon72="$(python3 "$PNG_SIZE" "$HERE/PACKAGE_ICON.PNG")" ||
  die "PACKAGE_ICON.PNG is not a readable PNG"
icon256="$(python3 "$PNG_SIZE" "$HERE/PACKAGE_ICON_256.PNG")" ||
  die "PACKAGE_ICON_256.PNG is not a readable PNG"
[ "$icon72" = "72x72" ] || die "PACKAGE_ICON.PNG must be 72x72, got $icon72"
[ "$icon256" = "256x256" ] || die "PACKAGE_ICON_256.PNG must be 256x256, got $icon256"

python3 -m json.tool "$HERE/conf/privilege" >/dev/null ||
  die "conf/privilege is not valid JSON"
python3 -m json.tool "$HERE/conf/resource" >/dev/null ||
  die "conf/resource is not valid JSON"
python3 -m json.tool "$HERE/conf/resource.webservice.example.json" >/dev/null ||
  die "conf/resource.webservice.example.json is not valid JSON"

for uifile in install_uifile install_uifile_chs install_uifile_cht; do
  python3 -m json.tool "$HERE/WIZARD_UIFILES/$uifile" >/dev/null ||
    die "WIZARD_UIFILES/$uifile is not valid JSON"
done

for script in start-stop-status token dshd installer postinst preuninst preupgrade postupgrade; do
  sh -n "$HERE/scripts/$script" || die "shell syntax error in scripts/$script"
done

grep -q 'port_conf/dshd.sc' "$HERE/conf/resource" ||
  die "conf/resource does not reference the port protocol file"
grep -q '3080/tcp' "$HERE/package/port_conf/dshd.sc" ||
  die "package/port_conf/dshd.sc does not register 3080/tcp"
if grep -RIn 'example\.com' "$HERE/package" "$HERE/conf/resource" >/dev/null 2>&1; then
  die "example.com must not appear in packaged defaults"
fi

# --- Stage ----------------------------------------------------------------
mkdir -p "$OUT"
TMP="$(mktemp -d)"
mkdir -p "$TMP/conf" "$TMP/scripts"

cp "$HERE/INFO" "$TMP/INFO"
cp "$HERE/PACKAGE_ICON.PNG" "$HERE/PACKAGE_ICON_256.PNG" "$TMP/"
cp "$HERE/conf/privilege" "$HERE/conf/resource" "$TMP/conf/"
cp "$HERE"/scripts/start-stop-status "$HERE"/scripts/token \
   "$HERE"/scripts/dshd "$HERE"/scripts/installer \
   "$HERE"/scripts/preinst "$HERE"/scripts/postinst "$HERE"/scripts/preuninst \
   "$HERE"/scripts/preupgrade "$HERE"/scripts/postupgrade "$TMP/scripts/"
cp -R "$HERE/package" "$TMP/package"
cp -R "$HERE/WIZARD_UIFILES" "$TMP/WIZARD_UIFILES"

find "$TMP" \( -name '.DS_Store' -o -name '._*' \) -delete 2>/dev/null || true
find "$TMP/package" -type f -exec chmod 0644 {} +
find "$TMP/package" -type d -exec chmod 0755 {} +
# The dsh container runs as uid 1001; these bind-mount roots must be writable
# before Container Manager's docker-project worker starts the container.
chmod 0777 "$TMP/package/compose/data/home" "$TMP/package/compose/data/workspace" "$TMP/package/compose/data/run"
[ -d "$TMP/package/bin" ] && find "$TMP/package/bin" -type f -exec chmod 0755 {} +
chmod 0755 "$TMP/package/compose/entrypoint.sh"
chmod 0644 "$TMP/INFO" "$TMP"/PACKAGE_ICON*.PNG "$TMP"/conf/* "$TMP"/WIZARD_UIFILES/*
chmod 0755 "$TMP"/scripts/*

# package.tgz contains the package files at its root; DSM extracts it into
# /var/packages/<name>/target. Do not add a `package/` level here.
( cd "$TMP/package" && COPYFILE_DISABLE=1 tar -czf "$TMP/package.tgz" . )
rm -rf "$TMP/package"

SPK="$OUT/$PKG_NAME-$VERSION.spk"
rm -f "$SPK"
( cd "$TMP" && COPYFILE_DISABLE=1 tar -cf "$SPK" \
    INFO package.tgz conf scripts WIZARD_UIFILES \
    PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG )

printf '%s\n' "$SPK"
