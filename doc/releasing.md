# Releasing

## First pub.dev release

Automated publishing only works for existing pub.dev packages. Publish the
first version manually from a clean `main` checkout:

```sh
dart format --set-exit-if-changed .
flutter analyze
flutter test test/motion_exporter_test.dart
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
3. Wait for `main` CI to pass.
4. Create and push the matching tag:

```sh
git tag vX.Y.Z
git push origin vX.Y.Z
```
