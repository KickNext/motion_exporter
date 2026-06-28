# Animation golden testing

Use raw `.motion` goldens for automated assertions. Use WebP/APNG only for
human-readable artifacts.

Do not compare WebP bytes in golden tests. The WebP frame payloads are lossless
in this package, but the file is still an export container: frame durations are
rounded to integer milliseconds, encoder/muxer details can change, and writing
the file costs CPU that the assertion does not need. Compare the raw
`MotionClip`, then encode a WebP/APNG preview only when a person needs to look
at the result.

## Test pattern

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:motion_exporter/motion_exporter.dart';
import 'package:motion_exporter/motion_exporter_io.dart';

void main() {
  test('spinner animation', () async {
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

`expectMotionCanvasGolden` returns the captured `MotionClip` when the same
frames should also be encoded as a WebP/APNG review artifact.

For a live widget loop, emit semantic loop boundaries from the animation and
capture the raw clip before export:

```dart
final clip = await const MotionExportEngine().recordNextLoopClip(
  controller: controller,
  loopSignal: loopSignal,
  options: const MotionRecorderOptions(framesPerSecond: 60),
  loopDuration: const Duration(seconds: 1),
);

await expectMotionClipGolden(
  actual: clip,
  file: File('test/goldens/spinner.motion'),
  update: Platform.environment['UPDATE_GOLDENS'] == '1',
  failureArtifactsDirectory: Directory('build/motion_failures'),
);
```

Create or intentionally refresh goldens:

```sh
UPDATE_GOLDENS=1 flutter test test/spinner_golden_test.dart
```

On PowerShell:

```powershell
$env:UPDATE_GOLDENS='1'
flutter test test/spinner_golden_test.dart
Remove-Item Env:\UPDATE_GOLDENS
```

Verify in CI without updating:

```sh
flutter test test/spinner_golden_test.dart
```

When `failureArtifactsDirectory` is set, a mismatch writes `actual`,
`expected`, and `diff` PNG files for the first comparable failing frame. Upload
that directory from CI when the test fails. The package CI uses
`actions/upload-artifact` for `build/motion_failures` and
`example/build/motion_failures`.

## Why raw goldens

`.motion` stores dimensions, per-frame durations, and straight-alpha RGBA
pixels, using lossless compression when it makes the file smaller. It avoids
lossy encoding, WebP millisecond delay rounding, and APNG/WebP container layout
differences. The test compares the captured animation itself.

Export WebP/APNG after the assertion when you need a file for pull request
artifacts or docs:

```dart
final result = await const MotionExportEngine().encode(clip);
await File(result.recommendedFileName).writeAsBytes(result.bytes);
```
