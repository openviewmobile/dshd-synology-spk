#!/usr/bin/env bash
# Assemble the GitHub release payload for the current native package version.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.4.0}"
OUT="${2:-$ROOT/release/$VERSION}"
SPK_X86="$ROOT/dist/dshd-$VERSION.spk"
SPK_ARM="$ROOT/dist/dshd-$VERSION-armv8.spk"
NOTES="$ROOT/docs/release/release-notes-$VERSION.md"
SUMS="$ROOT/docs/release/SHA256SUMS-$VERSION.txt"

[ -f "$SPK_X86" ] || { echo "missing $SPK_X86" >&2; exit 1; }
[ -f "$SPK_ARM" ] || { echo "missing $SPK_ARM" >&2; exit 1; }
[ -f "$NOTES" ] || { echo "missing $NOTES" >&2; exit 1; }
[ -f "$SUMS" ] || { echo "missing $SUMS" >&2; exit 1; }

mkdir -p "$OUT"
cp "$SPK_X86" "$SPK_ARM" "$NOTES" "$SUMS" "$OUT/"
cp "$ROOT/docs/package-center-branded.png" "$OUT/"
cp "$ROOT/docs/acceptance-native-web-main.png" "$OUT/"
cp "$ROOT/docs/social-preview.png" "$OUT/" 2>/dev/null || true
if [ -f "$ROOT/promo-video/youtube-thumbnail.png" ]; then
  cp "$ROOT/promo-video/youtube-thumbnail.png" "$OUT/DSHD-Native-YouTube-thumbnail.png"
fi
if [ -f "$ROOT/promo-video/DSHD-Native-Promo.srt" ]; then
  cp "$ROOT/promo-video/DSHD-Native-Promo.srt" "$OUT/"
fi
if [ -f "$ROOT/promo-video/youtube-metadata.md" ]; then
  cp "$ROOT/promo-video/youtube-metadata.md" "$OUT/DSHD-Native-YouTube-metadata.md"
fi
if [ -f "$ROOT/promo-video/renders/DSHD-Native-Promo-0.4.0-youtube.mp4" ]; then
  cp "$ROOT/promo-video/renders/DSHD-Native-Promo-0.4.0-youtube.mp4" "$OUT/"
fi

( cd "$OUT" && shasum -a 256 -c SHA256SUMS-$VERSION.txt )
printf 'release payload: %s\n' "$OUT"
ls -lh "$OUT"
