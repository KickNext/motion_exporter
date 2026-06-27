# Flutter Favorite readiness

This package is aiming for Flutter Favorite quality, not merely a green local
build. The public Flutter Favorite metrics emphasize package score, permissive
license, matching GitHub tags, feature completeness, verified publisher, docs,
examples, API quality, runtime behavior, and dependency quality:
https://docs.flutter.dev/packages-and-plugins/favorites

## Current evidence

- MIT license is present.
- Public API has WebP-first export, APNG export, raw `.motion` animation
  goldens, loop-boundary capture, deterministic canvas recording, and capture
  diagnostics.
- `pubspec.yaml` declares a static PNG package thumbnail, while README keeps
  the animated WebP export artifact for human review.
- `pubspec.yaml` explicitly declares Android, iOS, Linux, macOS, web, and
  Windows support for pub.dev platform metadata.
- Root package gate is green locally:
  `dart format --set-exit-if-changed .`, `flutter analyze`, and
  `flutter test test/motion_exporter_test.dart`.
- Example gate is green locally:
  `cd example && flutter analyze && flutter build web --release --output
  build/web && flutter test test/widget_test.dart
  test/motion_golden_workflow_test.dart test/generate_120fps_demo_test.dart`.
- CI is configured in `.github/workflows/ci.yml` for formatting, analyze,
  root tests, example tests, raw golden workflow tests, package archive
  validation, deterministic WebP demo generation, web and WebAssembly
  compatibility, validated export benchmark JSON with WebP changed-rectangle
  and APNG transparent-trim performance regression guards plus raw `.motion`
  golden assertion timing, Linux, macOS, Windows, Android, and iOS example
  build smoke checks, and `v*` release tag checks against `pubspec.yaml` and
  `CHANGELOG.md` versions.
- CD is configured in `.github/workflows/publish.yml` for `vX.Y.Z` tags. It
  checks the tag against `pubspec.yaml`/`CHANGELOG.md`, runs package and
  example verification including package archive dry-run, web build, and the
  benchmark JSON validator, then delegates publishing to the official
  `dart-lang/setup-dart` pub.dev workflow.
- GitHub project intake has a security policy, bug report issue form, and PR
  checklist aligned with the local CI gate.
- `dart pub publish --dry-run` packages successfully and reports only the
  missing `homepage`/`repository` warning.
- `pana . --no-warning` currently scores 130/160 locally on Windows: static
  analysis, dependencies, platform support, README, CHANGELOG, license, and
  example are green.

## Known blockers

- `pubspec.yaml` has no `repository` or `homepage`; `dart pub publish --dry-run`
  warns until the real public URL exists.
- `dartdoc` 9.0.5, as invoked by `pana`, currently crashes while precaching
  Flutter SDK `animation.dart` docs with `@docImport` offsets. This costs the
  dartdoc-comments score even though package analysis is clean.
- Local Windows `pana` cannot validate screenshots without WebP CLI tools
  (`webpinfo`, `cwebp`, `gif2webp`). The pubspec thumbnail is PNG, but the
  scorer still tries those converters when screenshots are present.
- The package is not yet published from a verified publisher, and pub.dev
  automated publishing still needs to be linked to the real GitHub repository.
- There is no public GitHub release tag matching the pub.dev version.
- Runtime performance has a pure-Dart WebP encoder bottleneck. Current default
  WebP export settings use changed-frame trimming for captured full-snapshot
  clips, but a native/libwebp backend would be the next large performance step.
- macOS and iOS compatibility are covered by configured CI smoke builds, but
  those jobs still need to pass on the real GitHub repository before claiming
  full Apple platform release confidence.
