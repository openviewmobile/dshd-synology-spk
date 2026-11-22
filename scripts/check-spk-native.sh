#!/usr/bin/env bash
# Static checks for the native DSHD package (no Docker / Container Manager).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPK="$ROOT/spk-native"
fail() { printf 'check-spk-native: %s\n' "$*" >&2; exit 1; }
[ -f "$SPK/INFO" ] || fail "missing spk-native/INFO"
grep -q '^package="dshd"$' "$SPK/INFO" || fail "package id must be dshd"
grep -q '^arch="x86_64"$' "$SPK/INFO" || fail "native runtime is x86_64"
grep -Rqi 'docker\|container manager' "$SPK/conf/resource" && fail "native resource must not reference Docker"
[ -f "$SPK/conf/privilege" ] || fail "missing privilege"
for f in "$SPK"/scripts/{start-stop-status,token,dshd,installer,postinst,preinst,preuninst,preupgrade,postupgrade}; do
  [ -f "$f" ] || fail "missing $f"
  sh -n "$f" || fail "syntax error in $f"
done
for f in "$SPK"/WIZARD_UIFILES/install_uifile*; do python3 -m json.tool "$f" >/dev/null || fail "invalid $f"; done
python3 -m json.tool "$SPK/conf/resource" >/dev/null || fail "invalid resource"
python3 -m json.tool "$SPK/conf/privilege" >/dev/null || fail "invalid privilege"
[ -x "$SPK/build-spk.sh" ] || fail "build-spk.sh not executable"
printf 'check-spk-native: ok\n'
