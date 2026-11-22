# DeepSeek Harness promo video

A 50-second, 1920×1080 YouTube promo for DeepSeek Harness 0.4.0, built with
[Hyperframes](https://hyperframes.heygen.com) (HTML + seekable GSAP timeline)
and a deterministic three.js particle/NAS background.

## Deliverables

| File | Purpose |
|---|---|
| `renders/DSHD-Native-Promo-0.4.0-youtube.mp4` | Upload master: 1920×1080, 30 fps, H.264/AAC, ~-14.8 LUFS |
| `youtube-thumbnail.png` | 1280×720 thumbnail |
| `DSHD-Native-Promo.srt` | English captions |
| `youtube-metadata.md` | Title, description, tags, chapters, upload checklist |
| `../docs/social-preview.png` | GitHub social preview (1280×640) |

The rendered MP4 and generated music WAV are intentionally not committed; they
are release artifacts.

## Storyboard

| Time | Scene | Visual |
|---|---|---|
| 0:00–0:07 | Your NAS. Your AI agent. | three.js NAS wireframe, particle field, dolly-in |
| 0:07–0:15 | Docker-in-Docker is over | Before/after path cards, red vs. cyan |
| 0:15–0:25 | Install it like a NAS package | Package Center screenshot + wizard crop |
| 0:25–0:34 | Your files. Your UI. Your NAS. | dsh web UI in a browser frame |
| 0:34–0:42 | Three steps. No Docker. | Step cards |
| 0:42–0:50 | DeepSeek Harness 0.4.0 | Icon, CTA, GitHub search hint |

## Rebuild

Requirements: Node 22+, FFmpeg, and a Chromium/Chrome installation.

```bash
cd promo-video
npm run check                 # Hyperframes lint/layout/contrast/runtime
python3 make-music.py         # regenerate assets/music.wav
npm run render -- -o renders/DSHD-Native-Promo-0.4.0.mp4 -q delivery --fps 30
# Optional: YouTube loudness normalization (-16 LUFS, -1.5 dBTP)
ffmpeg -y -i renders/DSHD-Native-Promo-0.4.0.mp4 \
  -c:v copy -af 'loudnorm=I=-16:TP=-1.5:LRA=11' \
  -c:a aac -b:a 192k -ar 48000 -movflags +faststart \
  renders/DSHD-Native-Promo-0.4.0-youtube.mp4
```

`npm run check` must pass before rendering. Snapshot a few timestamps to review
the composition without a full render:

```bash
npx --yes hyperframes@0.9.31 snapshot --at 1,9,18,28,38,45,48
```

## Source assets

- `assets/package-center-crop.png` — cropped Package Center screenshot.
- `assets/web-ui-clean.png` — dsh UI captured at 2× DPR.
- `assets/install-wizard-crop.png` — install wizard dialog.
- `assets/app-icon.png` — package icon.
- `assets/vendor/three.min.js` — three.js r160 UMD build; license alongside.
- `assets/vendor/gsap.min.js` — GSAP 3.15.0 timeline runtime; license notice alongside.
- `make-music.py` — deterministic, royalty-free ambient score.

No stock footage or third-party music is used. The package screenshots are from
the project's own VirtualDSM acceptance run; no credentials or token URLs appear.

## Notes

- Hyperframes renders WebGL deterministically by seeking the registered GSAP
  timeline; the three.js scene is rendered from the timeline's `onUpdate`, not a
  free-running `requestAnimationFrame` loop.
- The video deliberately says “Search: dshd-synology-spk” instead of showing a
  guessed GitHub URL. Put the real URL in the YouTube description and pinned
  comment once the repository is live.
- If you re-record the UI, redact any token URLs and API keys first.
