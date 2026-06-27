# motion_exporter example

Interactive Flutter demo for recording a transparent animated widget and
exporting it to WebP.

```sh
flutter run -d windows
```

The app records one complete live animation loop with a 120 fps target between
two loop-boundary signals, saves the resulting WebP to a temporary directory,
and plays the encoded WebP bytes in the output panel. The live loop button uses
`recordNextLoop` with a cancel signal, so canceling the wait or active capture
does not leave a background recorder task running.

Use `Render 120 fps` to export the demo motion scene from deterministic
timestamps instead of the live window vsync. The generated WebP has 240 frames
and preserves the total two-second duration with distributed millisecond delays.

To regenerate the checked-in sample output:

```sh
flutter test test/generate_120fps_demo_test.dart
```

Output path:

```text
output/transparent_120fps.webp
```

Verify the raw `.motion` golden workflow:

```sh
flutter test test/motion_golden_workflow_test.dart
```

Compare local export and raw golden cost for the same deterministic scene:

```sh
flutter test tool/benchmark_exports.dart --reporter expanded
```

Optional JSON snapshot with WebP/APNG rows and `.motion` golden timings:

```powershell
$env:MOTION_EXPORTER_BENCHMARK_JSON='output/benchmark.json'
flutter test tool/benchmark_exports.dart --reporter expanded
dart run tool/validate_benchmark_json.dart output/benchmark.json
```
