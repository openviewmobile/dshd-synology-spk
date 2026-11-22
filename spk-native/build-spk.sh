#!/usr/bin/env bash
# Build the native (no Docker) DSHD DSM 7 SPK.
#
# The runtime directory is produced by scripts/build-native-runtime.sh and is
# deliberately not committed. Build output: dist/dshd-<version>.spk.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/../dist}"
ARCH="${ARCH:-x86_64}"
RUNTIME_DIR="${RUNTIME_DIR:-$HERE/package/runtime}"
if [ -d "$RUNTIME_DIR" ]; then
  RUNTIME_DIR="$(cd "$RUNTIME_DIR" && pwd)"
fi
PNG_SIZE="$HERE/tools/png-size.py"
TMP=""
cleanup() { [ -n "$TMP" ] && rm -rf "$TMP"; }
trap cleanup EXIT
info() { sed -n "s/^${1}=\"\\(.*\\)\"$/\\1/p" "$HERE/INFO" | head -n 1; }
die() { printf 'build-spk-native: %s\n' "$*" >&2; exit 1; }

TMP="$(mktemp -d)"
[ -f "$HERE/INFO" ] || die "missing INFO"
PKG_NAME="$(info package)"; VERSION="$(info version)"
[ -n "$PKG_NAME" ] && [ -n "$VERSION" ] || die "INFO: empty package/version"
[[ "$PKG_NAME" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid package id"
[[ "$VERSION" =~ ^[0-9][0-9A-Za-z._-]*$ ]] || die "invalid version"
required=("$RUNTIME_DIR/node" "$RUNTIME_DIR/node_modules/@deepseek-ai/dsh/lib/bin.js"
  package/config.env.example package/port_conf/dshd.sc
  conf/privilege conf/resource scripts/start-stop-status scripts/token scripts/dshd
  scripts/installer scripts/postinst scripts/preinst scripts/preuninst
  scripts/preupgrade scripts/postupgrade
  WIZARD_UIFILES/install_uifile WIZARD_UIFILES/install_uifile_chs
  WIZARD_UIFILES/install_uifile_cht PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG)
for rel in "${required[@]}"; do
  case "$rel" in /*) path="$rel" ;; *) path="$HERE/$rel" ;; esac
  [ -e "$path" ] || die "missing $path (run scripts/build-native-runtime.sh)"
done
[ -x "$RUNTIME_DIR/node" ] || die "runtime node is not executable"
[ "$(python3 "$PNG_SIZE" "$HERE/PACKAGE_ICON.PNG")" = "72x72" ] || die "PACKAGE_ICON.PNG must be 72x72"
[ "$(python3 "$PNG_SIZE" "$HERE/PACKAGE_ICON_256.PNG")" = "256x256" ] || die "PACKAGE_ICON_256.PNG must be 256x256"
for f in conf/privilege conf/resource; do python3 -m json.tool "$HERE/$f" >/dev/null || die "invalid $f"; done
for f in install_uifile install_uifile_chs install_uifile_cht; do python3 -m json.tool "$HERE/WIZARD_UIFILES/$f" >/dev/null || die "invalid wizard $f"; done
for f in start-stop-status token dshd installer postinst preinst preuninst preupgrade postupgrade; do sh -n "$HERE/scripts/$f" || die "syntax error in scripts/$f"; done
grep -q 'docker-project' "$HERE/conf/resource" && die "native resource must not contain docker-project" || true

mkdir -p "$OUT" "$TMP/conf" "$TMP/scripts"
cp "$HERE/INFO" "$HERE/PACKAGE_ICON.PNG" "$HERE/PACKAGE_ICON_256.PNG" "$TMP/"
cp "$HERE/conf/privilege" "$HERE/conf/resource" "$TMP/conf/"
cp "$HERE"/scripts/* "$TMP/scripts/"
mkdir -p "$TMP/package"
for entry in "$HERE/package"/*; do
  [ -e "$entry" ] || continue
  base=${entry##*/}
  case "$base" in runtime|runtime-*) continue ;; esac
  cp -R "$entry" "$TMP/package/"
done
cp -R "$RUNTIME_DIR" "$TMP/package/runtime"
cp -R "$HERE/WIZARD_UIFILES" "$TMP/WIZARD_UIFILES"
find "$TMP" \( -name '.DS_Store' -o -name '._*' \) -delete 2>/dev/null || true
chmod 0755 "$TMP/scripts/"* "$TMP/package/runtime/node" "$TMP"/package/bin/* 2>/dev/null || true
sed -i.bak "s/^arch=.*/arch=\"$ARCH\"/" "$TMP/INFO"; rm -f "$TMP/INFO.bak"
chmod 0644 "$TMP/INFO" "$TMP"/PACKAGE_ICON*.PNG "$TMP"/conf/* "$TMP"/WIZARD_UIFILES/*
find "$TMP/package" -type d -exec chmod 0755 {} +
find "$TMP/package" -type f ! -path '*/runtime/node' ! -path '*/bin/*' -exec chmod 0644 {} +
( cd "$TMP/package" && COPYFILE_DISABLE=1 tar -czf "$TMP/package.tgz" . )
rm -rf "$TMP/package"
SUFFIX=""
[ "$ARCH" = "x86_64" ] || SUFFIX="-$ARCH"
SPK="$OUT/$PKG_NAME-$VERSION$SUFFIX.spk"
rm -f "$SPK"
( cd "$TMP" && COPYFILE_DISABLE=1 tar -cf "$SPK" INFO package.tgz conf scripts WIZARD_UIFILES PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG )
printf '%s\n' "$SPK"
