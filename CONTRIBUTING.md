# Contributing

Run the same checks as CI before sending changes:

```sh
flutter pub get
dart format --set-exit-if-changed .
flutter analyze
flutter test test/motion_exporter_test.dart
cd example
flutter pub get
flutter analyze
flutter build web --release --output build/web
flutter test test/widget_test.dart
flutter test test/motion_golden_workflow_test.dart
flutter test test/generate_120fps_demo_test.dart
MOTION_EXPORTER_BENCHMARK_JSON=output/benchmark.json flutter test tool/benchmark_exports.dart --reporter expanded
cd ..
dart pub publish --dry-run
```

The publish dry-run currently exits with the known missing `homepage` or
`repository` warning. Treat any additional package warning or error as a
release blocker.

Tagged releases use `.github/workflows/publish.yml`, which calls the official
`dart-lang/setup-dart` pub.dev publishing workflow. Before pushing `vX.Y.Z`,
configure pub.dev automated publishing for the real GitHub repository, make the
tag match `pubspec.yaml`, and keep a matching `## X.Y.Z` entry in
`CHANGELOG.md`.

Animation goldens should use raw `.motion` files, not WebP/APNG bytes:

```dart
await expectMotionClipGolden(
  actual: actualClip,
  file: File('test/goldens/loading_spinner.motion'),
  update: Platform.environment['UPDATE_GOLDENS'] == '1',
  channelTolerance: 1,
);
```

Use WebP/APNG exports for human-readable artifacts and release demos. Use
`.motion` goldens for automated assertions.
