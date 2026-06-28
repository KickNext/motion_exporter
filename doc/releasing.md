# Releasing

## First pub.dev release

Automated publishing only works for existing pub.dev packages. Publish the
first version manually from a clean `main` checkout:

```sh
dart format --set-exit-if-changed .
fvm spawn 3.41.0 analyze --no-pub lib test
fvm spawn 3.41.0 test --no-pub test/motion_exporter_test.dart
flutter analyze
flutter test test/motion_exporter_test.dart
cd example
flutter analyze
flutter build web --release --output build/web
flutter test test/widget_test.dart test/motion_golden_workflow_test.dart test/generate_120fps_demo_test.dart
MOTION_EXPORTER_BENCHMARK_JSON=output/benchmark.json flutter test tool/benchmark_exports.dart --reporter expanded
dart run tool/validate_benchmark_json.dart output/benchmark.json
cd ..
dart pub publish --dry-run
dart pub publish
```

Prefer publishing under a verified publisher before requesting Flutter
Favorite review.

## Enable automated publishing

After the first version exists on pub.dev, open the package Admin tab and enable
GitHub Actions automated publishing with:

- Repository: `KickNext/motion_exporter`
- Tag pattern: `v{{version}}`

Do not push a `vX.Y.Z` tag before this is enabled. The GitHub workflow verifies
the package, but pub.dev rejects OIDC publishing until the package exists and
the repository/tag pattern are linked.

## Later releases

1. Update `version:` in `pubspec.yaml`.
2. Add a matching `## X.Y.Z` entry in `CHANGELOG.md`.
3. Wait for `main` CI to pass, including the lower-bound job.
4. Create and push the matching tag:

```sh
git tag vX.Y.Z
git push origin vX.Y.Z
```
