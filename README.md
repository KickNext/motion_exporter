# motion_exporter

[![CI](https://github.com/KickNext/motion_exporter/actions/workflows/ci.yml/badge.svg)](https://github.com/KickNext/motion_exporter/actions/workflows/ci.yml)

`motion_exporter` records an animated Flutter widget subtree and exports motion
formats with transparent pixels preserved.

Browser demo: https://kicknext.github.io/motion_exporter/

![Transparent animated Flutter motion exported as WebP](screenshots/transparent_orbit.webp)

The package captures a `RepaintBoundary` as raw straight-alpha RGBA frames,
collapses consecutive identical frames, and encodes the final animation off the
UI isolate with Flutter's `compute` helper when available.

## Features

- Record any animated Flutter widget subtree.
- Use format-neutral `MotionRecorder` APIs while keeping WebP-specific encoders
  available for explicit WebP workflows.
- Preserve alpha/transparency with RGBA capture and lossless VP8L WebP frames.
- Export animated WebP by default with a valid `VP8X`/`ANIM`/`ANMF` container.
- Export APNG explicitly when broad transparent-animation playback matters more
  than WebP-specific output.
- Use full-frame replacement by default to avoid transparent-frame trails.
- Collapse duplicate frames to reduce output size and encoding work.
- Queue several in-flight captures before applying backpressure, so normal
  readback jitter does not immediately drop samples.
- Use changed-rectangle WebP trimming by default for captured full-snapshot
  motion.
- Use `MotionClipEncoder` for APNG/WebP exports with byte metadata, filenames,
  and background-isolate encoding by default.
- Estimate raw capture memory before recording high-resolution or high-FPS
  clips.
- Read actual retained clip memory with `MotionClip.rawBytes` /
  `MotionClip.rawMebibytes` or directly from `MotionExportResult`.
- Inspect capture diagnostics: readback timings, skipped frames, effective FPS,
  capture quality status, and retained raw RGBA memory.
- Inspect encoded WebP/APNG containers to verify frame count, duration, alpha,
  loop count, and whether the saved file is structurally animated.
- Enforce capture quality policies before encoding when dropped samples are not
  acceptable.
- Direct encoder API for raw RGBA frame lists.
- WebP-first `MotionExportEngine` facade for deterministic export and raw
  frame-by-frame golden comparisons.
- Raw `.motion` clip goldens for CI-friendly animation tests without lossy
  encoding or WebP container differences.

## Usage

### Choosing the output

Pick the API layer by what you want to verify:

- Use `recordCanvasClip` or `recordNextLoopClip` when the result is an
  automated golden. They return a raw `MotionClip` without running an image
  encoder.
- Use `expectMotionCanvasGolden` for deterministic canvas-driven CI goldens.
  Use `expectMotionClipGolden` when you already have a raw `MotionClip`. The
  `.motion` file stores frame durations and straight-alpha RGBA pixels, using
  lossless compression when it shrinks the golden.
- Use `encode`, `recordCanvas`, or `recordNextLoop` when you need WebP/APNG
  bytes for a preview, pull request artifact, upload, or docs.
- Use `clip.withoutDuplicateFrames()` before preview exports when repeated
  still frames are not meaningful. It preserves playback duration while
  reducing encoded frames and raw memory retained by the export result.
- Use `WebpAnimationEncoder` only for low-level WebP work with already-built
  frames. It is not the recommended assertion surface for animation goldens.

`package:image` exposes `image.encodeWebP(Image)` as a lossless single-image
VP8L encoder. `motion_exporter` uses it internally for per-frame image chunks
and writes the animated WebP `VP8X`/`ANIM`/`ANMF` container itself. Even with
lossless frame pixels, WebP is still the wrong thing to compare in golden
tests: frame delays are stored in whole milliseconds, container layout can
change, and encoding is much more expensive than comparing captured RGBA bytes.

### Golden-first quick start

Use a raw `.motion` golden for the assertion:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:motion_exporter/motion_exporter.dart';
import 'package:motion_exporter/motion_exporter_io.dart';

void main() {
  test('spinner motion stays stable', () async {
    await expectMotionCanvasGolden(
      file: File('test/goldens/spinner.motion'),
      size: const Size.square(64),
      duration: const Duration(seconds: 1),
      framesPerSecond: 60,
      paint: (canvas, size, progress, elapsed) {
        // Paint the exact frame for progress/elapsed.
      },
      update: Platform.environment['UPDATE_GOLDENS'] == '1',
      failureArtifactsDirectory: Directory('build/motion_failures'),
      channelTolerance: 1,
    );
  });
}
```

Create or intentionally refresh the golden:

```powershell
$env:UPDATE_GOLDENS='1'
flutter test test/spinner_golden_test.dart
Remove-Item Env:\UPDATE_GOLDENS
```

CI should run the same test without `UPDATE_GOLDENS`. On mismatch, the helper
writes `actual`, `expected`, and `diff` PNGs for the first failing frame into
`build/motion_failures`. Encode WebP/APNG only for review artifacts after the
raw clip has already passed the assertion.

For quick debug exports, wrap your app with the developer overlay:

```dart
void main() {
  runApp(
    MotionExporterOverlay(
      qualityPolicy: const MotionCaptureQualityPolicy.strict(),
      clipTransform: (clip) => clip.withoutDuplicateLoopClosure(
        channelTolerance: 8,
      ),
      onExported: (result) {
        // Save result.bytes as result.recommendedFileName, upload it,
        // or inspect result.clip/result.diagnostics.
        debugPrint(
          '${result.format.label}: ${result.frameCount} frames, '
          '${result.diagnostics?.skippedFrames ?? 0} skipped',
        );
      },
      onError: (error) {
        debugPrint(
          'Motion export failed during ${error.phase}: ${error.error}',
        );
      },
      child: const MyApp(),
    ),
  );
}
```

The overlay draws record controls above your app. The controls are not included
in the captured animation. It exports WebP by default. Use
`format: MotionExportFormat.apng` when you explicitly need APNG bytes.

`MotionExportEngine` and `MotionClipEncoder` export WebP by default, using
changed-frame WebP trimming to avoid full-canvas work on snapshot exports.
Use `const MotionClipEncoder.webp()` or `const MotionClipEncoder.apng()` when
the selected preview format should be obvious at the call site.

For a custom UI, wrap only the animated subtree:


```dart
final controller = MotionRecorderController();
const engine = MotionExportEngine();
const loopDuration = Duration(seconds: 2);

MotionRecorder(
  controller: controller,
  child: const MyAnimatedWidget(),
);
```

Start and stop recording:

```dart
const options = MotionRecorderOptions(
  framesPerSecond: 30,
  pixelRatio: 1,
  maxPendingCaptures: 8,
);

final estimate = MotionCaptureEstimate.forWidget(
  logicalSize: const Size.square(256),
  duration: const Duration(seconds: 2),
  options: options,
);
const maxRetainedBytes = 128 * 1024 * 1024;
if (!estimate.fitsRawByteBudget(bytes: maxRetainedBytes)) {
  throw StateError(
    'Capture is too large: ${estimate.rawMebibytes.toStringAsFixed(1)} MiB',
  );
}

await controller.start(
  options: options,
);

// Let your animation run.

final result = await engine.stopRecording(
  controller,
  clipTransform: (clip) => clip
      .withoutDuplicateLoopClosure(channelTolerance: 8)
      .withoutDuplicateFrames(channelTolerance: 1)
      .withDuration(loopDuration),
);
```

Use `controller.stopCapture()` for raw `.motion` goldens, `controller.stopExport()`
when you want to choose APNG/WebP through `MotionClipEncoder`, and
`controller.stopWebp()` only for the direct-WebP shortcut.

Set encoder policy once on the engine when the workflow needs stricter export
rules:

```dart
final engine = MotionExportEngine(
  encoder: MotionClipEncoder(
    qualityPolicy: MotionCaptureQualityPolicy.noSkippedFrames(
      maxRetainedBytes: maxRetainedBytes,
    ),
  ),
);
final result = await engine.stopRecording(controller);
await File(result.recommendedFileName).writeAsBytes(result.bytes);

final validation = result.validateEncodedFile();
validation.throwIfInvalid();

debugPrint(
  '${validation.inspection.frameCount} encoded frames, '
  'capture ${result.diagnostics?.effectiveCapturedFps.toStringAsFixed(1)} fps, '
  '${result.diagnostics?.skippedFrames} skipped',
);
if (result.diagnostics?.isCleanCapture == false) {
  debugPrint(result.diagnostics?.qualitySummary);
}
```

`MotionClipEncoder` runs this structural encoded-file validation by default and
stores the result in `result.validation`. Pass
`validationPolicy: const MotionExportValidationPolicy.disabled()` only when you
need to skip the extra container pass for a hot export path.

Use `MotionCaptureQualityPolicy.strict()` with `MotionClipEncoder` or
`MotionExporterOverlay` when a capture with skipped frames or sampled FPS below
target should fail instead of producing an export. In the overlay, those
failures are also delivered through `onError` with the phase, stack trace,
selected format, and latest diagnostics.
Use `MotionCaptureQualityPolicy.noSkippedFrames()` when dropped samples should
fail the export but below-target live FPS should remain a visible diagnostic
warning.

For logical loop capture, emit a boundary signal from the animation that owns
the loop:

```dart
final loopSignal = MotionLoopSignal();

void onAnimationLoopBoundary() {
  loopSignal.markBoundary();
}
```

For a one-shot boundary-to-boundary export, let the controller do the start/stop
orchestration:

```dart
final result = await controller.recordNextLoop(
  loopSignal: loopSignal,
  options: options,
  encoder: const MotionClipEncoder(
    qualityPolicy: MotionCaptureQualityPolicy.noSkippedFrames(),
  ),
  loopDuration: loopDuration,
  boundaryTimeout: const Duration(seconds: 5),
  cancelSignal: cancelButtonCompleter.future,
);
```

The helper waits for one boundary, starts capture, waits for the next boundary,
then exports. It removes a terminal duplicate of the first frame when present
and normalizes frame delays to [loopDuration] when supplied. If
`boundaryTimeout` expires after capture starts, the helper cancels the active
recording before rethrowing the timeout. If `cancelSignal` completes before or
during capture, the helper completes with `MotionLoopWaitCanceledException` and
also cancels any active recording. For custom flows, use
`withoutDuplicateLoopClosure()` and `withDuration()` directly in `clipTransform`.

For deterministic high-FPS clips, render a time-driven canvas scene instead of
sampling the live window:

```dart
const engine = MotionExportEngine();

final clip = await engine.recordCanvasClip(
  size: const Size.square(256),
  duration: const Duration(seconds: 2),
  framesPerSecond: 120,
  paint: (canvas, size, progress, elapsed) {
    // Paint the scene for this exact timestamp.
  },
);

final result = await engine.encode(clip);
final bytes = result.bytes;
```

This path is independent from the display refresh rate. It is the right choice
when the animation can be expressed from explicit `progress`/`elapsed` values.
Deterministic frame counts are rounded up, so uneven durations still cover the
full requested clip instead of dropping the final time slice.
Animated WebP stores integer millisecond frame delays, so high-FPS WebP exports
distribute the rounding error across frames to preserve the total clip duration.
APNG frame delays are written as rational fractions, so an explicit APNG export
can store a 120 fps clip as `1/120` per frame.

For animation golden tests, compare the raw clips before export:

```dart
const engine = MotionExportEngine();
final comparison = engine.compare(
  actualClip,
  expectedClip,
  channelTolerance: 1,
);
comparison.throwIfMismatch(description: 'loading spinner');
```

For persistent goldens, store the raw clip instead of encoded WebP bytes:

```dart
final clip = await const MotionExportEngine().recordCanvasClip(
  size: const Size.square(64),
  duration: const Duration(seconds: 1),
  framesPerSecond: 60,
  paint: paintSpinnerFrame,
);

await expectMotionClipGolden(
  actual: clip,
  file: File('test/goldens/loading_spinner.motion'),
  update: Platform.environment['UPDATE_GOLDENS'] == '1',
  failureArtifactsDirectory: Directory('build/motion_failures'),
  channelTolerance: 1,
);
```

The `.motion` file stores dimensions, frame durations, and straight-alpha RGBA
pixels, using lossless compression when it shrinks the golden. Use WebP/APNG
exports for artifacts people inspect; use `.motion` for the test assertion.
Import `dart:io` and
`package:motion_exporter/motion_exporter_io.dart` for file-backed goldens. See
`doc/animation_golden_testing.md` for a complete test pattern.

For a live widget loop, capture the raw loop first and encode only when a
review artifact is needed:

```dart
final clip = await const MotionExportEngine().recordNextLoopClip(
  controller: controller,
  loopSignal: loopSignal,
  options: options,
  loopDuration: const Duration(seconds: 2),
);

await expectMotionClipGolden(
  actual: clip,
  file: File('test/goldens/live_spinner.motion'),
);

final preview = await const MotionExportEngine().encode(clip);
await File(preview.recommendedFileName).writeAsBytes(preview.bytes);
```

## Demo

Run the interactive example:

```sh
cd example
flutter run -d windows
```

The example records a 256 logical pixel live widget canvas with a 120 fps target
between two `MotionLoopSignal` boundary events, exports WebP, and plays the
encoded WebP bytes in the output panel. It validates the encoded file against
the export metadata and shows the result next to capture/export diagnostics, so
readback, encode, skipped-frame, raw-memory, and file-integrity costs are
visible immediately.

The example also includes a deterministic `Render 120 fps` path for the demo
motion scene. It renders frames from explicit timestamps instead of waiting for
the live window vsync, so it can produce exactly 240 frames for the two-second
loop on a 60 Hz display and round uneven durations up to the next frame.

Generate a transparent 120 fps WebP sample:

```sh
cd example
flutter test test/generate_120fps_demo_test.dart
```

The generated file is written to `example/output/transparent_120fps.webp`.
`pubspec.yaml` uses a static PNG thumbnail for pub.dev scoring; the animated
WebP remains the README/demo artifact.

Compare local encoder cost for the deterministic 120 fps scene:

```sh
cd example
flutter test tool/benchmark_exports.dart --reporter expanded
```

The benchmark prints encode time, total time, output size, and frame count for
WebP/APNG and WebP trimming modes, plus raw `.motion` golden encode/decode and
comparison cost. It does not run as part of the normal test suite. Set
`MOTION_EXPORTER_BENCHMARK_JSON` to also write a machine-readable snapshot with
Dart/OS metadata:

```powershell
cd example
$env:MOTION_EXPORTER_BENCHMARK_JSON='output/benchmark.json'
flutter test tool/benchmark_exports.dart --reporter expanded
dart run tool/validate_benchmark_json.dart output/benchmark.json
```

See [doc/performance.md](doc/performance.md) for a measured snapshot and
guidance on choosing raw goldens, WebP, or APNG.

For high-resolution output, pass a larger `pixelRatio`. For long animations,
keep `framesPerSecond` and `pixelRatio` conservative because Flutter must read
RGBA pixels back from the GPU for every captured frame.

Frame durations are based on elapsed capture time. If the pending-capture limit
is reached and a sample has to be skipped, playback keeps the original timing
instead of speeding up the exported animation.

Captured and deterministic-rendered RGBA frames retain Flutter's returned byte
buffer directly instead of making another full-frame copy.

The APNG encoder trims transparent regions after the first frame by default.
This keeps the first frame valid as a normal PNG image while reducing later
frame payloads for transparent widget animations. Animated WebP exports also
trim transparent frame rectangles by default and use background disposal
internally to avoid trails. Pass
`ApngAnimationOptions(trimTransparentFrames: false)` or
`WebpAnimationOptions(trimTransparentFrames: false)` when you need full-canvas
frames.

For full-snapshot captures, the default WebP export crops frames by changed
RGBA pixels instead of transparent bounds:

```dart
const encoder = MotionClipEncoder();
```

This keeps the first WebP frame full-size, then stores only changed rectangles
with replace blending and no disposal. The streaming WebP encoder and native
file writer use the same changed-rectangle default because they are intended
for large exports where keeping every frame in memory is unnecessary. Pass
`WebpAnimationOptions()` explicitly when you prefer transparent-bound trimming
for mostly transparent motion.

For high-throughput file-backed exports, keep the safe default unless your
capture pipeline owns immutable RGBA buffers after each `addFrame` call. If the
caller will not mutate or reuse those bytes before the next frame is added, the
streaming encoder can skip the defensive previous-frame copy:

```dart
final recording = await writeWebpAnimationFile(
  file: File('build/preview.webp'),
  clip: clip,
);
recording.validateEncodedFile().throwIfInvalid();
```

Use `WebpAnimationFileWriter` directly only when frames arrive incrementally:

```dart
final writer = await WebpAnimationFileWriter.open(
  file: File('build/preview.webp'),
  width: 512,
  height: 512,
  options: const WebpAnimationOptions(
    trimChangedFrames: true,
    previousFrameRetentionPolicy: WebpPreviousFrameRetentionPolicy.reference,
  ),
);
```

Use `WebpPreviousFrameRetentionPolicy.copy` when frames come from a reusable
scratch buffer, an object pool, or any producer that might mutate pixels after
`addFrame` returns.

WebP frame delays are stored in whole milliseconds by the format. The encoder
rounds against cumulative clip time instead of rounding each frame in isolation,
so a two-second 120 fps clip is written as 160 frames at `8 ms` and 80 frames at
`9 ms`, not as 240 frames at `8 ms`.

## Direct Encoding

APNG:

```dart
final bytes = const ApngAnimationEncoder().encode([
  MotionFrame(
    width: 64,
    height: 64,
    duration: const Duration(milliseconds: 33),
    rgbaBytes: rgbaBytes,
  ),
]);
```

WebP:

```dart
final bytes = const WebpAnimationEncoder().encode([
  WebpFrame(
    width: 64,
    height: 64,
    duration: const Duration(milliseconds: 33),
    rgbaBytes: rgbaBytes,
  ),
]);
```

## Notes

The current WebP path uses pure Dart lossless VP8L frame encoding and a
package-local animated WebP muxer. It is portable and transparent-safe, but
full-frame lossless WebP export is CPU-heavy and animated VP8L playback support
varies between viewers. Use explicit APNG export when playback compatibility
matters more than WebP output.
