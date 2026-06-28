import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:motion_exporter/motion_exporter_io.dart';
import 'package:motion_exporter_example/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('verifies deterministic motion with a raw clip golden', () async {
    final clip = await renderTransparentDemoClip(
      framesPerSecond: 10,
      duration: const Duration(milliseconds: 200),
      size: 16,
    );

    // In a real app test, keep this under test/goldens and set update from an
    // explicit flag such as Platform.environment['UPDATE_GOLDENS'] == '1'.
    final directory = await Directory.systemTemp.createTemp(
      'motion_exporter_example_golden_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File(
      '${directory.path}${Platform.pathSeparator}transparent_demo.motion',
    );

    await expectMotionClipGolden(actual: clip, file: file, update: true);
    await expectMotionClipGolden(
      actual: clip,
      file: file,
      failureArtifactsDirectory: Directory('build/motion_failures'),
    );
  });
}
