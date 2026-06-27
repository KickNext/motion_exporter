## Summary

Describe the change and the user-facing behavior it affects.

## Checks

- [ ] `dart format --set-exit-if-changed .`
- [ ] `flutter analyze`
- [ ] `flutter test test/motion_exporter_test.dart`
- [ ] `cd example && flutter analyze`
- [ ] `cd example && flutter build web --release --output build/web`
- [ ] `cd example && flutter build web --wasm --release --output build/web_wasm` (CI)
- [ ] `cd example && flutter build linux --release` (CI)
- [ ] `cd example && flutter build macos --release` (CI)
- [ ] `cd example && flutter build windows --release` (CI)
- [ ] `cd example && flutter build apk --debug` (CI)
- [ ] `cd example && flutter build ios --simulator` (CI)
- [ ] `cd example && flutter test test/widget_test.dart test/motion_golden_workflow_test.dart test/generate_120fps_demo_test.dart`
- [ ] `cd example && MOTION_EXPORTER_BENCHMARK_JSON=output/benchmark.json flutter test tool/benchmark_exports.dart --reporter expanded && dart run tool/validate_benchmark_json.dart output/benchmark.json`
- [ ] `dart pub publish --dry-run`
