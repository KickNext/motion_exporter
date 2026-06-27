# Flutter Favorite readiness

This package is aiming for Flutter Favorite quality, not merely a green local
build. Checked against the Flutter 3.44 documentation, the public Flutter
Favorite metrics emphasize package score, permissive license, matching GitHub
tags, feature completeness, verified publisher, docs, examples, API quality,
runtime behavior, and dependency quality:
https://docs.flutter.dev/packages-and-plugins/favorites

## Current evidence

- MIT license is present.
- Public API has WebP-first export, APNG export, raw `.motion` animation
  goldens, loop-boundary capture, deterministic canvas recording, and capture
  diagnostics.
- `pubspec.yaml` declares a static PNG package thumbnail, while README keeps
  the animated WebP export artifact for human review.
- `pubspec.yaml` points `homepage`, `repository`, and `issue_tracker` to the
  public GitHub repository: https://github.com/KickNext/motion_exporter
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
- Public GitHub CI is green on `main` for formatting, analysis, package tests,
  example web/WebAssembly, raw golden workflow, benchmark validation, package
  archive dry-run, Linux, macOS, Windows, Android, and iOS smoke builds:
  https://github.com/KickNext/motion_exporter/actions/runs/28303973278
- `dart pub publish --dry-run` packages successfully with no warnings locally.
- `git status --short --branch` is clean on `main`, with the local branch
  tracking `origin/main`.
- `pana . --no-warning` on Flutter 3.44.1 / Dart 3.12.1 currently scores
  140/160 locally on Windows: static analysis, dependencies, platform support,
  README, CHANGELOG, license, and example are green.
- `dart doc --dry-run` fails locally with the same `RangeError` in
  `DocumentationComment._stripDocImports` that `pana` reports, so the lost
  dartdoc score is reproducible outside `pana`. Upstream tracking issue:
  https://github.com/dart-lang/dartdoc/issues/4180

## Known blockers

- `dartdoc` 9.0.4/9.0.5 currently crashes while precaching Flutter SDK
  comments that use `@docImport`. This costs the dartdoc-comments score even
  though package analysis is clean.
- Local Windows `pana` cannot fully validate screenshots without WebP CLI
  tools. Adding the cached `cwebp.exe` to `PATH` reduces the local screenshot
  error text, but `webpinfo` is still required. The pubspec thumbnail is PNG,
  and removing it would make the package presentation worse, so keep it.
- The package is not yet published from a verified publisher, and pub.dev
  automated publishing still needs to be linked to the real GitHub repository.
- There is no public GitHub release tag matching the pub.dev version.
- Runtime performance has a pure-Dart WebP encoder bottleneck. Current default
  WebP export settings use changed-frame trimming for captured full-snapshot
  clips, but a native/libwebp backend would be the next large performance step.
