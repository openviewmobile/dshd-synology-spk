#!/usr/bin/env bash
# Build the experimental docker-project SPK wrapper. Run from this directory.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/../dist}"

die() { printf 'build-spk(docker-project): %s\n' "$*" >&2; exit 1; }

info() {
  local key="$1"
  sed -n "s/^${key}=\"\\(.*\\)\"$/\\1/p" "$HERE/INFO" | head -n 1
}
VERSION="$(info version)"
[ -n "$VERSION" ] || die "INFO: version is empty"
[ "$(info package)" = "dshd" ] || die "INFO: package must be dshd"

for rel in \
  INFO PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG \
  conf/privilege conf/resource \
  package/compose/docker-compose.yml package/compose/.env.example
do
  [ -f "$HERE/$rel" ] || die "missing required file: $rel"
done

python3 -m json.tool "$HERE/conf/privilege" >/dev/null ||
  die "conf/privilege is not valid JSON"
python3 -m json.tool "$HERE/conf/resource" >/dev/null ||
  die "conf/resource is not valid JSON"
if grep -RIn 'example\.com' "$HERE/package" >/dev/null 2>&1; then
  die "example.com must not appear in packaged defaults"
fi

mkdir -p "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$HERE/INFO" "$HERE/PACKAGE_ICON.PNG" "$HERE/PACKAGE_ICON_256.PNG" "$TMP/"
cp -R "$HERE/conf" "$TMP/conf"
cp -R "$HERE/package" "$TMP/package"
find "$TMP" -name '.DS_Store' -delete 2>/dev/null || true
find "$TMP/package" -type f -exec chmod 0644 {} +
find "$TMP/package" -type d -exec chmod 0755 {} +

chmod 0644 "$TMP/INFO" "$TMP"/PACKAGE_ICON*.PNG "$TMP"/conf/*
tar -czf "$TMP/package.tgz" -C "$TMP" package
rm -rf "$TMP/package"

SPK="$OUT/dshd-docker-project-$VERSION.spk"
rm -f "$SPK"
( cd "$TMP" && tar -cf "$SPK" \
    INFO package.tgz conf PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG )
printf '%s\n' "$SPK"
