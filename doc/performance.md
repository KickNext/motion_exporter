# Performance

`motion_exporter` keeps automated animation tests on raw `.motion` clips and
uses WebP/APNG as review artifacts. That split is intentional: raw clip
comparison is the fast path, while lossless WebP export is CPU-heavy.

## Current benchmark

Measured on 2026-06-28 with:

- Windows 11 build 26200, Flutter 3.44.1 / Dart 3.12.1, 32 logical
  processors.
- Deterministic demo scene: 256 x 256 pixels, 240 frames, 2 seconds.
- Retained raw RGBA input: 60.0 MiB.

| Case | Format | Size | Encode |
| --- | --- | ---: | ---: |
| Raw `.motion` golden | `.motion` | 17287.0 KiB | 159.6 ms |
| Raw `.motion` compare | `.motion` | same | 22.7 ms |
| WebP default changed rect | WebP | 5087.7 KiB | 2987.9 ms |
| WebP transparent trim | WebP | 5087.2 KiB | 2997.9 ms |
| WebP full canvas | WebP | 5196.6 KiB | 6967.9 ms |
| APNG transparent trim | APNG | 5302.4 KiB | 326.9 ms |
| APNG full canvas | APNG | 5746.3 KiB | 372.6 ms |

The default WebP encoder is about 2.3x faster than full-canvas WebP for this
scene because it writes only changed rectangles after the first frame. APNG is
much faster in the current pure-Dart implementation, but WebP remains the
default preview format because the package is WebP-first and keeps WebP file
validation in CI.

## Guidance

- Use `expectMotionCanvasGolden` or `expectMotionClipGolden` for CI assertions.
- Encode WebP or APNG only after the raw golden has passed.
- Use `MotionClipEncoder.webp()` for the default changed-rectangle WebP preview.
- Use `MotionClipEncoder.apng()` when export speed or broad transparent
  animation playback compatibility matters more than WebP output.
- Use `clip.withoutDuplicateFrames()` before preview export when repeated still
  frames do not add review value.
- Keep `pixelRatio`, canvas size, and `framesPerSecond` conservative for live
  widget capture; Flutter must read back RGBA pixels for every sampled frame.

## Reproduce

```powershell
cd example
$env:MOTION_EXPORTER_BENCHMARK_JSON='output/benchmark.json'
flutter test tool/benchmark_exports.dart --reporter expanded
dart run tool/validate_benchmark_json.dart output/benchmark.json
Remove-Item Env:\MOTION_EXPORTER_BENCHMARK_JSON
```

The JSON is for local comparison and CI smoke validation. Absolute timings are
machine-dependent; relative ordering is the useful signal.
