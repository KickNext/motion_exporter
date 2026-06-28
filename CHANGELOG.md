## 0.0.1

* Initial release as `motion_exporter`.
* Package metadata describes the WebP/APNG export and raw `.motion` golden test
  workflows for pub.dev discovery.
* Supports Flutter `>=3.41.0` / Dart `>=3.11.0`, with lower-bound analysis and
  package tests verified on Flutter 3.41.0.
* Added widget motion capture APIs: `MotionRecorder`,
  `MotionRecorderController`, `MotionExporterOverlay`, capture diagnostics,
  `MotionRecording`, raw-memory estimates, capture quality policies with
  retained-byte budget enforcement, byte/MiB estimate checks, and typed export
  errors.
  `MotionRecorderController.stopWebp` names the direct-WebP shortcut while
  `stopCapture` and `stopExport` remain the format-neutral paths.
* Added export APIs for transparent animated WebP and APNG, including
  background-isolate encoding, encoded-file validation, WebP changed-rectangle
  trimming by default for captured clips and streamed WebP file writes, APNG
  rational high-FPS delays, cumulative WebP delay rounding, and direct WebP
  animation chunk writing to avoid extra muxer allocations, a
  `writeWebpAnimationFile` helper for file-backed clip exports,
  `MotionClipEncoder.webp()` / `MotionClipEncoder.apng()` format-specific
  constructors, structural validation for file-backed WebP recordings, shared
  ANMF frame header writing, single-pass WebP frame-duration accumulation,
  32-bit changed-pixel and transparent-alpha scans, tiny streamed frame-header
  writes, and opt-in previous-frame reference retention for high-throughput
  streamed WebP exports with immutable RGBA buffers.
* Added deterministic rendering APIs: `MotionCanvasRecorder`,
  `MotionExportEngine.recordCanvasClip`, `MotionExportEngine.recordCanvas`,
  `MotionClip.withDuration`, and `MotionClip.withoutDuplicateFrames` for exact
  animation clocks and lean preview exports, with integer clip-duration
  accumulation.
* Added loop-oriented workflows: `MotionLoopSignal`,
  `MotionRecorderController.recordNextLoop`, `recordNextLoopClip`, cancellable
  boundary waits, timeout cleanup, duplicate loop-closure trimming, and
  `preserveDuration` for removed terminal loop frames.
* Added raw animation golden support with `MotionClipComparison`,
  `MotionClipGoldenCodec`, `.motion` file helpers in `motion_exporter_io`, and
  `expectMotionCanvasGolden` for one-call deterministic canvas goldens.
  Docs/example tests show CI-friendly animation goldens that compare raw RGBA
  frames instead of WebP/APNG bytes, with mismatch reports pointing to the
  first differing frame, pixel, channel, and frame duration, plus an exact-match
  fast path for green golden checks and duplicate-frame collapse. `.motion`
  goldens use lossless RLE compression when it reduces file size while
  remaining backward-compatible with raw `.motion` files, with a preallocated
  RLE writer for lower CI encode overhead. The README now leads with a
  golden-first quick start, including PowerShell update commands.
* Added an interactive example app, deterministic 120 fps demo generation,
  encoded WebP preview playback, and an optional benchmark tool with CI smoke
  coverage plus JSON validation for WebP/APNG export timing, size snapshots,
  non-identifying Dart/OS metadata, WebP changed-rectangle performance
  regression checks, APNG transparent-trim performance regression checks, and
  raw `.motion` golden encode/decode/compare timing with encode/compare
  regression guards. Added `doc/performance.md` with measured WebP/APNG/raw
  golden timing guidance.
* Added real motion export screenshots: an animated WebP for README review and
  a static PNG thumbnail for pub.dev package presentation.
* Improved package hygiene with archive ignores for generated Flutter files,
  strict analyzer options, root/example/web/WebAssembly CI, tag-driven pub.dev
  publish automation gated by example web/WebAssembly plus Android, iOS, Linux,
  macOS, and Windows example build smoke checks, explicit pub.dev platform
  metadata, GitHub intake templates, and malformed `.motion` golden validation.
* Kept the example app web-buildable by moving native file writes behind a
  conditional import.
