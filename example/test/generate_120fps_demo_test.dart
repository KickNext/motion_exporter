import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:motion_exporter/motion_exporter.dart';
import 'package:motion_exporter_example/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('writes deterministic 120 fps WebP demo file', () async {
    final clip = await renderTransparentDemoClip();
    final result = await const MotionClipEncoder().encode(clip);

    final file = File('output/transparent_120fps.webp');
    await file.create(recursive: true);
    await file.writeAsBytes(result.bytes, flush: true);

    final frameControls = _webpFrameControls(result.bytes);
    final frameDurations = frameControls
        .map((control) => control.durationMs)
        .toList();
    final inspection = result.validation?.inspection ?? result.inspect();

    expect(result.format, MotionExportFormat.webp);
    expect(result.frameCount, 240);
    expect(result.duration, const Duration(seconds: 2));
    expect(inspection.format, MotionExportFormat.webp);
    expect(inspection.frameCount, result.frameCount);
    expect(inspection.duration, result.duration);
    expect(inspection.isAnimated, isTrue);
    expect(inspection.hasAlpha, isTrue);
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), result.byteLength);
    expect(String.fromCharCodes(result.bytes.take(4)), 'RIFF');
    expect(String.fromCharCodes(result.bytes.skip(8).take(4)), 'WEBP');
    expect(
      _webpTopLevelChunks(result.bytes),
      containsAll(<String>['VP8X', 'ANIM']),
    );
    expect(frameControls, hasLength(result.frameCount));
    expect(frameDurations.reduce((a, b) => a + b), 2000);
    expect(frameDurations.where((duration) => duration == 8), hasLength(160));
    expect(frameDurations.where((duration) => duration == 9), hasLength(80));
  });
}

List<String> _webpTopLevelChunks(Uint8List bytes) {
  final chunks = <String>[];
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final size = _readUint32(bytes, offset + 4);
    chunks.add(_asciiAt(bytes, offset, 4));
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  return chunks;
}

List<_WebpFrameControl> _webpFrameControls(Uint8List bytes) {
  final controls = <_WebpFrameControl>[];
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final type = _asciiAt(bytes, offset, 4);
    final size = _readUint32(bytes, offset + 4);
    final payload = offset + 8;
    if (type == 'ANMF') {
      controls.add(
        _WebpFrameControl(durationMs: _readUint24(bytes, payload + 12)),
      );
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  return controls;
}

String _asciiAt(Uint8List bytes, int offset, int length) {
  return String.fromCharCodes(bytes.sublist(offset, offset + length));
}

int _readUint24(Uint8List bytes, int offset) {
  return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
}

int _readUint32(Uint8List bytes, int offset) {
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}

class _WebpFrameControl {
  const _WebpFrameControl({required this.durationMs});

  final int durationMs;
}
