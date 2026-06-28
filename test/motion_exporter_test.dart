import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:motion_exporter/motion_exporter.dart';
import 'package:motion_exporter/motion_exporter_io.dart';

const _pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

void main() {
  testWidgets('developer overlay records and exports WebP by default', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(64, 64);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final exported = Completer<MotionExportResult>();

    await tester.pumpWidget(
      MotionExporterOverlay(
        options: const WebpRecorderOptions(
          framesPerSecond: 30,
          pixelRatio: 1,
          useBackgroundIsolate: false,
        ),
        clipTransform: (clip) => clip.withDuration(const Duration(seconds: 1)),
        onExported: exported.complete,
        child: const ColoredBox(color: Color(0x80008f8a)),
      ),
    );

    expect(find.text('Ready WebP'), findsOneWidget);

    await tester.tap(find.byKey(const Key('motion_exporter_primary_action')));
    await tester.pump();

    expect(find.bySemanticsLabel('Cancel recording'), findsOneWidget);

    await _pumpUntil(
      tester,
      () => find
          .textContaining(RegExp(r'^[1-9]\d* frames$'))
          .evaluate()
          .isNotEmpty,
    );

    await tester.tap(find.byKey(const Key('motion_exporter_primary_action')));
    await tester.pump();

    await _pumpUntil(tester, () => exported.isCompleted);
    final recording = (await tester.runAsync(
      () => exported.future.timeout(const Duration(seconds: 5)),
    ))!;
    await tester.pump();

    expect(recording.format, MotionExportFormat.webp);
    expect(recording.bytes, isNotEmpty);
    expect(String.fromCharCodes(recording.bytes.take(4)), 'RIFF');
    expect(String.fromCharCodes(recording.bytes.skip(8).take(4)), 'WEBP');
    expect(recording.fileExtension, 'webp');
    expect(recording.mimeType, 'image/webp');
    expect(recording.recommendedFileName, startsWith('motion_export_64x64_'));
    expect(recording.recommendedFileName, endsWith('ms.webp'));
    expect(recording.width, 64);
    expect(recording.height, 64);
    expect(recording.duration, const Duration(seconds: 1));
    expect(recording.clip.frameCount, recording.frameCount);
    expect(recording.diagnostics, isNotNull);
    expect(recording.validation, isNotNull);
    expect(recording.validation!.isValid, isTrue);
    expect(find.textContaining('KB'), findsOneWidget);
  });

  testWidgets('developer overlay reports export errors', (tester) async {
    tester.view.physicalSize = const Size(64, 64);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final reported = Completer<MotionExporterOverlayError>();

    await tester.pumpWidget(
      MotionExporterOverlay(
        options: const WebpRecorderOptions(
          framesPerSecond: 30,
          pixelRatio: 1,
          useBackgroundIsolate: false,
        ),
        qualityPolicy: const _RejectingCaptureQualityPolicy(),
        onError: reported.complete,
        onExported: (_) => fail('Export should have been rejected.'),
        child: const ColoredBox(color: Color(0x80008f8a)),
      ),
    );

    await tester.tap(find.byKey(const Key('motion_exporter_primary_action')));
    await tester.pump();

    await _pumpUntil(
      tester,
      () => find
          .textContaining(RegExp(r'^[1-9]\d* frames$'))
          .evaluate()
          .isNotEmpty,
    );

    await tester.tap(find.byKey(const Key('motion_exporter_primary_action')));
    await tester.pump();

    await _pumpUntil(tester, () => reported.isCompleted);
    final error = (await tester.runAsync(
      () => reported.future.timeout(const Duration(seconds: 5)),
    ))!;
    await tester.pump();

    expect(error.phase, MotionExporterOverlayErrorPhase.export);
    expect(error.format, MotionExportFormat.webp);
    expect(error.error, isA<MotionCaptureQualityException>());
    expect(error.stackTrace, isNotNull);
    expect(error.diagnostics, isNotNull);
    expect(error.diagnostics!.capturedFrames, greaterThan(0));
    expect(find.text('Export failed'), findsOneWidget);
  });

  test('motion export formats expose file metadata', () {
    expect(MotionExportFormat.apng.label, 'APNG');
    expect(MotionExportFormat.apng.fileExtension, 'png');
    expect(MotionExportFormat.apng.mimeType, 'image/png');
    expect(MotionExportFormat.webp.label, 'WebP');
    expect(MotionExportFormat.webp.fileExtension, 'webp');
    expect(MotionExportFormat.webp.mimeType, 'image/webp');
  });

  test('main library keeps dart:io helpers separate', () {
    final mainLibrary = File('lib/motion_exporter.dart').readAsStringSync();
    final ioLibrary = File('lib/motion_exporter_io.dart').readAsStringSync();

    expect(mainLibrary, isNot(contains("import 'dart:io'")));
    expect(mainLibrary, isNot(contains('motion_exporter_io.dart')));
    expect(ioLibrary, contains("import 'dart:io'"));
  });

  test('encodes clips through the unified motion clip encoder', () async {
    final clip = MotionClip(
      frames: <MotionFrame>[
        MotionFrame(
          width: 1,
          height: 1,
          duration: const Duration(milliseconds: 100),
          rgbaBytes: Uint8List.fromList(<int>[0, 143, 138, 128]),
        ),
      ],
    );

    final result = await const MotionClipEncoder(
      useBackgroundIsolate: false,
    ).encode(clip);

    expect(result.format, MotionExportFormat.webp);
    expect(String.fromCharCodes(result.bytes.take(4)), 'RIFF');
    expect(String.fromCharCodes(result.bytes.skip(8).take(4)), 'WEBP');
    expect(result.byteLength, result.bytes.lengthInBytes);
    expect(result.kibibytes, result.byteLength / 1024);
    expect(clip.rawBytes, 4);
    expect(clip.rawMebibytes, closeTo(4 / (1024 * 1024), 0.000001));
    expect(result.rawBytes, clip.rawBytes);
    expect(result.rawMebibytes, clip.rawMebibytes);
    expect(result.recommendedFileName, 'motion_export_1x1_1f_100ms.webp');
    expect(result.fileName(basename: 'spinner'), 'spinner_1x1_1f_100ms.webp');
  });

  test('motion clip encoder defaults to changed WebP rectangles', () async {
    expect(const WebpRecorderOptions().trimChangedFrames, isTrue);

    final firstFrameBytes = _rectFrameBytes(
      width: 4,
      height: 4,
      x: 0,
      y: 0,
      rectWidth: 4,
      rectHeight: 4,
      color: <int>[16, 32, 48, 255],
    );
    final secondFrameBytes = _frameBytesWithPixel(
      firstFrameBytes,
      width: 4,
      x: 3,
      y: 2,
      color: <int>[0, 143, 138, 128],
    );
    final clip = MotionClip(
      frames: <MotionFrame>[
        MotionFrame(
          width: 4,
          height: 4,
          duration: const Duration(milliseconds: 80),
          rgbaBytes: firstFrameBytes,
        ),
        MotionFrame(
          width: 4,
          height: 4,
          duration: const Duration(milliseconds: 80),
          rgbaBytes: secondFrameBytes,
        ),
      ],
    );

    final result = await const MotionClipEncoder(
      useBackgroundIsolate: false,
    ).encode(clip);
    final controls = _webpFrameControls(result.bytes);

    expect(controls, hasLength(2));
    expect(controls.last.x, 2);
    expect(controls.last.y, 2);
    expect(controls.last.width, 2);
    expect(controls.last.height, 1);
    expect(controls.last.flags, 0x02);
  });

  test('motion clip encoder exposes explicit format constructors', () async {
    final clip = _singlePixelClip();

    final webp = await const MotionClipEncoder.webp(
      useBackgroundIsolate: false,
    ).encode(clip);
    final apng = await const MotionClipEncoder.apng(
      useBackgroundIsolate: false,
    ).encode(clip);

    expect(webp.format, MotionExportFormat.webp);
    expect(_topLevelChunks(webp.bytes), contains('ANIM'));
    expect(apng.format, MotionExportFormat.apng);
    expect(_pngChunks(apng.bytes), contains('acTL'));
  });

  test('motion export engine records deterministic WebP by default', () async {
    const engine = MotionExportEngine(
      encoder: MotionClipEncoder(useBackgroundIsolate: false),
    );

    final result = await engine.recordCanvas(
      size: const Size(2, 1),
      duration: const Duration(milliseconds: 200),
      framesPerSecond: 10,
      paint: (canvas, size, progress, elapsed) {
        final paint = ui.Paint()..color = const Color(0x80008f8a);
        canvas.drawRect(Offset.zero & size, paint);
      },
    );

    expect(result.format, MotionExportFormat.webp);
    expect(result.frameCount, 2);
    expect(result.duration, const Duration(milliseconds: 200));
    expect(result.validation, isNotNull);
    expect(result.validation!.isValid, isTrue);
    expect(String.fromCharCodes(result.bytes.take(4)), 'RIFF');
    expect(String.fromCharCodes(result.bytes.skip(8).take(4)), 'WEBP');
  });

  test('motion export engine transforms deterministic exports once', () async {
    var transformCalls = 0;
    final engine = MotionExportEngine(
      encoder: const MotionClipEncoder(useBackgroundIsolate: false),
      clipTransform: (clip) {
        transformCalls++;
        return clip.withDuration(const Duration(milliseconds: 300));
      },
    );

    final result = await engine.recordCanvas(
      size: const Size(1, 1),
      duration: const Duration(milliseconds: 100),
      framesPerSecond: 10,
      paint: (canvas, size, progress, elapsed) {
        final paint = ui.Paint()..color = const Color(0xff008f8a);
        canvas.drawRect(Offset.zero & size, paint);
      },
    );

    expect(transformCalls, 1);
    expect(result.duration, const Duration(milliseconds: 300));
    expect(result.clip.duration, const Duration(milliseconds: 300));
  });

  test(
    'motion export engine gives deterministic exports clean diagnostics',
    () async {
      final engine = MotionExportEngine(
        encoder: const MotionClipEncoder(
          useBackgroundIsolate: false,
          qualityPolicy: MotionCaptureQualityPolicy.strict(),
        ),
        clipTransform: (clip) =>
            clip.withDuration(const Duration(milliseconds: 300)),
      );

      final result = await engine.recordCanvas(
        size: const Size(1, 1),
        duration: const Duration(milliseconds: 100),
        framesPerSecond: 10,
        paint: (canvas, size, progress, elapsed) {
          final paint = ui.Paint()..color = const Color(0xff008f8a);
          canvas.drawRect(Offset.zero & size, paint);
        },
      );

      expect(result.duration, const Duration(milliseconds: 300));
      expect(result.diagnostics, isNotNull);
      expect(result.diagnostics!.isCleanCapture, isTrue);
      expect(result.diagnostics!.skippedFrames, 0);
    },
  );

  test(
    'motion export engine records deterministic raw clips for goldens',
    () async {
      const engine = MotionExportEngine();

      final clip = await engine.recordCanvasClip(
        size: const Size(2, 1),
        duration: const Duration(milliseconds: 200),
        framesPerSecond: 10,
        paint: (canvas, size, progress, elapsed) {
          final paint = ui.Paint()..color = const Color(0x80008f8a);
          canvas.drawRect(Offset.zero & size, paint);
        },
      );

      expect(clip.width, 2);
      expect(clip.height, 1);
      expect(clip.frameCount, 2);
      expect(clip.duration, const Duration(milliseconds: 200));
      expect(clip.rawBytes, 16);
    },
  );

  test('motion export engine compares clips for animation goldens', () {
    final expected = MotionClip(
      frames: <MotionFrame>[
        MotionFrame(
          width: 1,
          height: 1,
          duration: const Duration(milliseconds: 100),
          rgbaBytes: Uint8List.fromList(<int>[10, 20, 30, 255]),
        ),
      ],
    );
    final actual = MotionClip(
      frames: <MotionFrame>[
        MotionFrame(
          width: 1,
          height: 1,
          duration: const Duration(milliseconds: 100),
          rgbaBytes: Uint8List.fromList(<int>[10, 21, 30, 255]),
        ),
      ],
    );
    const engine = MotionExportEngine();

    final exactMatch = engine.compare(
      MotionClip(
        frames: <MotionFrame>[
          MotionFrame(
            width: 1,
            height: 1,
            duration: const Duration(milliseconds: 100),
            rgbaBytes: _unalignedBytes(Uint8List.fromList(<int>[1, 2, 3, 4])),
          ),
        ],
      ),
      MotionClip(
        frames: <MotionFrame>[
          MotionFrame(
            width: 1,
            height: 1,
            duration: const Duration(milliseconds: 100),
            rgbaBytes: _unalignedBytes(Uint8List.fromList(<int>[1, 2, 3, 4])),
          ),
        ],
      ),
    );
    expect(exactMatch.isMatch, isTrue);
    expect(exactMatch.summary, contains('clips match'));

    final exact = engine.compare(actual, expected);
    expect(exact.isMatch, isFalse);
    expect(exact.mismatchedPixels, 1);
    expect(exact.maxChannelDelta, 1);
    expect(
      exact.firstPixelMismatch,
      'frame 0 pixel 0,0 g actual 21 != expected 20 (delta 1)',
    );
    expect(exact.summary, contains('first frame 0 pixel 0,0 g'));
    expect(
      exact.throwIfMismatch,
      throwsA(isA<MotionClipComparisonException>()),
    );

    final tolerant = engine.compare(actual, expected, channelTolerance: 1);
    expect(tolerant.isMatch, isTrue);
    engine.expectMatches(actual, expected, channelTolerance: 1);

    final durationExpected = MotionClip(
      frames: <MotionFrame>[
        MotionFrame(
          width: 1,
          height: 1,
          duration: const Duration(milliseconds: 40),
          rgbaBytes: Uint8List.fromList(<int>[10, 20, 30, 255]),
        ),
        MotionFrame(
          width: 1,
          height: 1,
          duration: const Duration(milliseconds: 60),
          rgbaBytes: Uint8List.fromList(<int>[10, 20, 30, 255]),
        ),
      ],
    );
    final durationActual = MotionClip(
      frames: <MotionFrame>[
        MotionFrame(
          width: 1,
          height: 1,
          duration: const Duration(milliseconds: 50),
          rgbaBytes: Uint8List.fromList(<int>[10, 20, 30, 255]),
        ),
        MotionFrame(
          width: 1,
          height: 1,
          duration: const Duration(milliseconds: 50),
          rgbaBytes: Uint8List.fromList(<int>[10, 20, 30, 255]),
        ),
      ],
    );
    final frameDurationMismatch = engine.compare(
      durationActual,
      durationExpected,
    );
    expect(frameDurationMismatch.durationMatches, isTrue);
    expect(frameDurationMismatch.frameDurationsMatch, isFalse);
    expect(frameDurationMismatch.framePixelsMatch, isTrue);
    expect(
      frameDurationMismatch.firstFrameDurationMismatch,
      'frame 0 actual 50000us != expected 40000us (delta 10000us)',
    );
    expect(frameDurationMismatch.summary, contains('frame duration delta'));
    expect(frameDurationMismatch.summary, contains('first frame 0 actual'));
    expect(frameDurationMismatch.summary, isNot(contains('pixels differ')));
  });

  test('motion clip golden codec round-trips raw frames', () {
    final clip = MotionClip(
      frames: <MotionFrame>[
        MotionFrame(
          width: 2,
          height: 1,
          duration: const Duration(milliseconds: 80),
          rgbaBytes: Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
        ),
        MotionFrame(
          width: 2,
          height: 1,
          duration: const Duration(milliseconds: 120),
          rgbaBytes: Uint8List.fromList(<int>[9, 10, 11, 12, 13, 14, 15, 16]),
        ),
      ],
    );
    const codec = MotionClipGoldenCodec();

    final bytes = codec.encode(clip);
    final decoded = codec.decode(bytes);
    final comparison = MotionClipComparison.compare(
      actual: decoded,
      expected: clip,
    );

    expect(String.fromCharCodes(bytes.take(4)), 'MCLP');
    expect(decoded.frameCount, 2);
    expect(decoded.duration, const Duration(milliseconds: 200));
    expect(decoded.frames[0].rgbaBytes, clip.frames[0].rgbaBytes);
    expect(decoded.frames[1].rgbaBytes, clip.frames[1].rgbaBytes);
    expect(comparison.isMatch, isTrue);
  });

  test('motion clip golden codec compresses repeated bytes losslessly', () {
    final clip = MotionClip(
      frames: <MotionFrame>[
        MotionFrame(
          width: 8,
          height: 8,
          duration: const Duration(milliseconds: 80),
          rgbaBytes: Uint8List(8 * 8 * 4),
        ),
        MotionFrame(
          width: 8,
          height: 8,
          duration: const Duration(milliseconds: 120),
          rgbaBytes: Uint8List(8 * 8 * 4),
        ),
      ],
    );
    const compressedCodec = MotionClipGoldenCodec();
    const rawCodec = MotionClipGoldenCodec(compress: false);

    final compressedBytes = compressedCodec.encode(clip);
    final rawBytes = rawCodec.encode(clip);
    final decoded = compressedCodec.decode(compressedBytes);
    final comparison = MotionClipComparison.compare(
      actual: decoded,
      expected: clip,
    );

    expect(
      ByteData.sublistView(compressedBytes).getUint16(6, Endian.little),
      1,
    );
    expect(compressedBytes.lengthInBytes, lessThan(rawBytes.lengthInBytes));
    expect(comparison.isMatch, isTrue);
  });

  test('motion clip golden codec rejects malformed compressed payloads', () {
    const codec = MotionClipGoldenCodec();

    Uint8List compressedGolden(List<int> payload) {
      final bytes = Uint8List(20 + payload.length);
      final data = ByteData.sublistView(bytes);
      bytes.setRange(0, 4, 'MCLP'.codeUnits);
      data.setUint16(4, 1, Endian.little);
      data.setUint16(6, 1, Endian.little);
      data.setUint32(8, 1, Endian.little);
      data.setUint32(12, 1, Endian.little);
      data.setUint32(16, 1, Endian.little);
      bytes.setRange(20, bytes.length, payload);
      return bytes;
    }

    expect(
      () => codec.decode(compressedGolden(<int>[11, 1, 2, 3])),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('RLE literal is truncated'),
        ),
      ),
    );
    expect(
      () => codec.decode(compressedGolden(<int>[0x80])),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('RLE run is truncated'),
        ),
      ),
    );
    expect(
      () => codec.decode(compressedGolden(<int>[0x80, 0])),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('RLE decoded 3 bytes'),
        ),
      ),
    );
  });

  test('motion clip golden codec rejects malformed headers', () {
    const codec = MotionClipGoldenCodec();
    final bytes = Uint8List(20);
    final data = ByteData.sublistView(bytes);
    bytes.setRange(0, 4, 'MCLP'.codeUnits);
    data.setUint16(4, 1, Endian.little);
    data.setUint32(8, 1, Endian.little);
    data.setUint32(12, 1, Endian.little);

    expect(() => codec.decode(bytes), throwsA(isA<FormatException>()));

    data.setUint16(6, 0x8000, Endian.little);
    expect(
      () => codec.decode(bytes),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Unsupported motion golden flags'),
        ),
      ),
    );
    data.setUint16(6, 0, Endian.little);

    data.setUint32(16, 1, Endian.little);
    final zeroDuration = Uint8List(32)..setRange(0, bytes.length, bytes);
    expect(
      () => codec.decode(zeroDuration),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('zero duration'),
        ),
      ),
    );
  });

  test('motion clip golden file helper updates and verifies', () async {
    final directory = await Directory.systemTemp.createTemp(
      'motion_exporter_golden_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File(
      '${directory.path}${Platform.pathSeparator}spinner.motion',
    );
    final expected = _singlePixelClip();
    final actual = MotionClip(
      frames: <MotionFrame>[
        MotionFrame(
          width: 1,
          height: 1,
          duration: const Duration(milliseconds: 100),
          rgbaBytes: Uint8List.fromList(<int>[1, 143, 138, 128]),
        ),
      ],
    );

    await expectMotionClipGolden(actual: expected, file: file, update: true);
    expect(await file.exists(), isTrue);
    await expectMotionClipGolden(actual: expected, file: file);
    await expectMotionClipGolden(
      actual: actual,
      file: file,
      channelTolerance: 1,
    );
    await expectLater(
      expectMotionClipGolden(actual: actual, file: file),
      throwsA(isA<MotionClipComparisonException>()),
    );
  });

  test('motion canvas golden helper renders, updates, and verifies', () async {
    final directory = await Directory.systemTemp.createTemp(
      'motion_exporter_canvas_golden_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}dot.motion');

    MotionCanvasPainter paint(Color color) {
      return (canvas, size, progress, elapsed) {
        canvas.drawColor(color, ui.BlendMode.src);
      };
    }

    final clip = await expectMotionCanvasGolden(
      file: file,
      size: const Size.square(2),
      duration: const Duration(milliseconds: 100),
      framesPerSecond: 10,
      paint: paint(const Color(0x80008f8a)),
      update: true,
    );

    expect(clip.frameCount, 1);
    expect(await file.exists(), isTrue);
    await expectMotionCanvasGolden(
      file: file,
      size: const Size.square(2),
      duration: const Duration(milliseconds: 100),
      framesPerSecond: 10,
      paint: paint(const Color(0x80008f8a)),
    );
    await expectLater(
      expectMotionCanvasGolden(
        file: file,
        size: const Size.square(2),
        duration: const Duration(milliseconds: 100),
        framesPerSecond: 10,
        paint: paint(const Color(0x80008f8b)),
      ),
      throwsA(isA<MotionClipComparisonException>()),
    );
  });

  testWidgets('motion export engine stops widget capture', (tester) async {
    final controller = MotionRecorderController();
    const engine = MotionExportEngine(
      encoder: MotionClipEncoder(useBackgroundIsolate: false),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 2,
            height: 2,
            child: MotionRecorder(
              controller: controller,
              child: const ColoredBox(color: Color(0x80008f8a)),
            ),
          ),
        ),
      ),
    );

    await controller.start(
      options: const MotionRecorderOptions(
        framesPerSecond: 1,
        pixelRatio: 1,
        useBackgroundIsolate: false,
      ),
    );
    final capture = controller.captureFrame();
    await tester.pump();
    await tester.runAsync(() => capture);

    final result = await tester.runAsync(
      () => engine.stopRecording(controller),
    );

    expect(result!.format, MotionExportFormat.webp);
    expect(result.width, 2);
    expect(result.height, 2);
    expect(result.frameCount, 1);
    expect(result.diagnostics, isNotNull);
    expect(result.validation, isNotNull);
    expect(result.validation!.isValid, isTrue);
  });

  test('encodes APNG through the unified motion clip encoder', () async {
    final clip = MotionClip(
      frames: <MotionFrame>[
        MotionFrame(
          width: 1,
          height: 1,
          duration: const Duration(milliseconds: 100),
          rgbaBytes: Uint8List.fromList(<int>[0, 143, 138, 128]),
        ),
      ],
    );

    final result = await const MotionClipEncoder(
      format: MotionExportFormat.apng,
      useBackgroundIsolate: false,
    ).encode(clip);

    expect(result.format, MotionExportFormat.apng);
    expect(result.bytes.take(_pngSignature.length), _pngSignature);
    expect(result.recommendedFileName, 'motion_export_1x1_1f_100ms.png');

    final isolatedResult = await const MotionClipEncoder(
      format: MotionExportFormat.apng,
    ).encode(clip);

    expect(isolatedResult.format, MotionExportFormat.apng);
    expect(isolatedResult.bytes.take(_pngSignature.length), _pngSignature);
  });

  test('inspects encoded WebP and APNG animation containers', () async {
    final clip = MotionClip(
      frames: <MotionFrame>[
        MotionFrame(
          width: 2,
          height: 1,
          duration: const Duration(milliseconds: 80),
          rgbaBytes: Uint8List.fromList(<int>[255, 0, 0, 255, 0, 0, 0, 0]),
        ),
        MotionFrame(
          width: 2,
          height: 1,
          duration: const Duration(milliseconds: 120),
          rgbaBytes: Uint8List.fromList(<int>[0, 0, 0, 0, 0, 0, 255, 128]),
        ),
      ],
    );

    final webp = await const MotionClipEncoder(
      useBackgroundIsolate: false,
    ).encode(clip);
    final webpInspection = webp.inspect();

    expect(webpInspection.format, MotionExportFormat.webp);
    expect(webpInspection.width, 2);
    expect(webpInspection.height, 1);
    expect(webpInspection.frameCount, 2);
    expect(webpInspection.duration, const Duration(milliseconds: 200));
    expect(webpInspection.loopCount, 0);
    expect(webpInspection.hasAlpha, isTrue);
    expect(webpInspection.isAnimated, isTrue);
    expect(webp.validateEncodedFile().isValid, isTrue);

    final apng = await const MotionClipEncoder(
      format: MotionExportFormat.apng,
      useBackgroundIsolate: false,
    ).encode(clip);
    final apngInspection = apng.inspect();

    expect(apngInspection.format, MotionExportFormat.apng);
    expect(apngInspection.width, 2);
    expect(apngInspection.height, 1);
    expect(apngInspection.frameCount, 2);
    expect(apngInspection.duration, const Duration(milliseconds: 200));
    expect(apngInspection.loopCount, 0);
    expect(apngInspection.hasAlpha, isTrue);
    expect(apngInspection.isAnimated, isTrue);
    expect(apng.validateEncodedFile().isValid, isTrue);

    expect(
      () => MotionExportInspection.inspect(
        format: MotionExportFormat.apng,
        bytes: webp.bytes,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('validates encoded files against export metadata', () async {
    final result = await const MotionClipEncoder(
      useBackgroundIsolate: false,
    ).encode(_singlePixelClip());

    expect(result.validation, isNotNull);
    final valid = result.validateEncodedFile();
    expect(valid, same(result.validation));
    expect(valid.isValid, isTrue);
    expect(valid.failures, isEmpty);
    expect(valid.summary, 'file verified');
    valid.throwIfInvalid();

    final unchecked = await const MotionClipEncoder(
      useBackgroundIsolate: false,
      validationPolicy: MotionExportValidationPolicy.disabled(),
    ).encode(_singlePixelClip());

    expect(unchecked.validation, isNull);
    expect(unchecked.validateEncodedFile().isValid, isTrue);

    final mismatched = MotionExportResult(
      format: result.format,
      bytes: result.bytes,
      frameCount: result.frameCount + 1,
      width: result.width + 1,
      height: result.height,
      duration: result.duration + const Duration(milliseconds: 20),
      clip: result.clip,
      encodeDuration: result.encodeDuration,
    );
    final invalid = mismatched.validateEncodedFile(
      durationTolerance: Duration.zero,
    );

    expect(invalid.isValid, isFalse);
    expect(
      invalid.failures,
      containsAll(<MotionExportValidationFailure>[
        MotionExportValidationFailure.sizeMismatch,
        MotionExportValidationFailure.frameCountMismatch,
        MotionExportValidationFailure.durationMismatch,
      ]),
    );
    expect(
      invalid.throwIfInvalid,
      throwsA(isA<MotionExportValidationException>()),
    );
    expect(
      () => const MotionExportValidationPolicy().validate(mismatched),
      throwsA(isA<MotionExportValidationException>()),
    );
  });

  test(
    'capture quality policy can reject dirty captures before encoding',
    () async {
      final clip = _singlePixelClip();
      final dirtyDiagnostics = _captureDiagnostics(
        capturedFrames: 90,
        skippedFrames: 30,
        collapsedFrames: 10,
      );

      final failures = const MotionCaptureQualityPolicy.strict().failuresFor(
        dirtyDiagnostics,
      );
      expect(failures, <MotionCaptureQualityFailure>[
        MotionCaptureQualityFailure.skippedFrames,
        MotionCaptureQualityFailure.belowTargetFrameRate,
      ]);

      await expectLater(
        const MotionClipEncoder(
          useBackgroundIsolate: false,
          qualityPolicy: MotionCaptureQualityPolicy.strict(),
        ).encode(clip, diagnostics: dirtyDiagnostics),
        throwsA(
          isA<MotionCaptureQualityException>()
              .having(
                (error) => error.failures,
                'failures',
                contains(MotionCaptureQualityFailure.skippedFrames),
              )
              .having(
                (error) => error.failures,
                'failures',
                contains(MotionCaptureQualityFailure.belowTargetFrameRate),
              )
              .having(
                (error) => error.toString(),
                'message',
                contains('capture 45 / target 60 fps, 30 skipped (25%)'),
              ),
        ),
      );
    },
  );

  test('no-skipped capture quality policy rejects only skipped samples', () {
    const policy = MotionCaptureQualityPolicy.noSkippedFrames();

    expect(policy.failuresFor(null), <MotionCaptureQualityFailure>[
      MotionCaptureQualityFailure.missingDiagnostics,
    ]);
    expect(
      policy.failuresFor(
        _captureDiagnostics(capturedFrames: 90, skippedFrames: 0),
      ),
      isEmpty,
    );
    expect(
      policy.failuresFor(
        _captureDiagnostics(capturedFrames: 90, skippedFrames: 1),
      ),
      <MotionCaptureQualityFailure>[MotionCaptureQualityFailure.skippedFrames],
    );
  });

  test('capture quality policy can reject retained raw memory', () async {
    const policy = MotionCaptureQualityPolicy(maxRetainedBytes: 16);
    final diagnostics = _captureDiagnostics(capturedFrames: 5);

    expect(policy.failuresFor(null), <MotionCaptureQualityFailure>[
      MotionCaptureQualityFailure.missingDiagnostics,
    ]);
    expect(policy.failuresFor(diagnostics), <MotionCaptureQualityFailure>[
      MotionCaptureQualityFailure.retainedMemoryBudgetExceeded,
    ]);

    await expectLater(
      const MotionClipEncoder(
        useBackgroundIsolate: false,
        qualityPolicy: policy,
      ).encode(_singlePixelClip(), diagnostics: diagnostics),
      throwsA(
        isA<MotionCaptureQualityException>()
            .having(
              (error) => error.failures,
              'failures',
              <MotionCaptureQualityFailure>[
                MotionCaptureQualityFailure.retainedMemoryBudgetExceeded,
              ],
            )
            .having(
              (error) => error.toString(),
              'message',
              contains('retained memory budget exceeded'),
            ),
      ),
    );
  });

  test('strict capture quality policy accepts clean diagnostics', () async {
    final result = await const MotionClipEncoder(
      useBackgroundIsolate: false,
      qualityPolicy: MotionCaptureQualityPolicy.strict(),
    ).encode(_singlePixelClip(), diagnostics: _captureDiagnostics());

    expect(String.fromCharCodes(result.bytes.take(4)), 'RIFF');
    expect(String.fromCharCodes(result.bytes.skip(8).take(4)), 'WEBP');
  });

  test('strict capture quality policy rejects missing diagnostics', () {
    expect(
      const MotionCaptureQualityPolicy.strict().failuresFor(null),
      <MotionCaptureQualityFailure>[
        MotionCaptureQualityFailure.missingDiagnostics,
      ],
    );
  });

  test('estimates raw memory for widget capture settings', () {
    final estimate = MotionCaptureEstimate.forWidget(
      logicalSize: const Size(256, 128),
      duration: const Duration(seconds: 2),
      options: const MotionRecorderOptions(framesPerSecond: 120, pixelRatio: 2),
    );

    expect(estimate.width, 512);
    expect(estimate.height, 256);
    expect(estimate.frameCount, 240);
    expect(estimate.frameBytes, 512 * 256 * 4);
    expect(estimate.rawBytes, 512 * 256 * 4 * 240);
    expect(estimate.rawMebibytes, closeTo(120, 0.0001));
    expect(estimate.frameInterval, const Duration(microseconds: 8333));
    expect(estimate.fitsRawByteBudget(bytes: estimate.rawBytes), isTrue);
    expect(estimate.fitsRawByteBudget(bytes: estimate.rawBytes - 1), isFalse);
    expect(estimate.fitsRawMemoryBudget(mebibytes: 120), isTrue);
    expect(estimate.fitsRawMemoryBudget(mebibytes: 119), isFalse);

    final unevenEstimate = MotionCaptureEstimate.forWidget(
      logicalSize: const Size(1, 1),
      duration: const Duration(milliseconds: 101),
      options: const MotionRecorderOptions(framesPerSecond: 10, pixelRatio: 1),
    );

    expect(unevenEstimate.frameCount, 2);
    expect(unevenEstimate.rawBytes, 8);
  });

  testWidgets('records through the format-neutral MotionRecorder API', (
    tester,
  ) async {
    final controller = MotionRecorderController();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 2,
            height: 2,
            child: MotionRecorder(
              controller: controller,
              child: const ColoredBox(color: Color(0x80008f8a)),
            ),
          ),
        ),
      ),
    );

    await controller.start(
      options: const MotionRecorderOptions(
        framesPerSecond: 1,
        pixelRatio: 1,
        useBackgroundIsolate: false,
      ),
    );
    await tester.pump();

    final capture = controller.captureFrame();
    await tester.pump();
    await tester.runAsync(() => capture);

    final clip = await tester.runAsync(controller.stopCapture);
    final result = await const MotionClipEncoder(
      useBackgroundIsolate: false,
    ).encode(clip!, diagnostics: controller.diagnostics);

    expect(result.width, 2);
    expect(result.height, 2);
    expect(result.frameCount, 1);
    expect(result.diagnostics, isA<MotionCaptureDiagnostics>());
    expect(String.fromCharCodes(result.bytes.take(4)), 'RIFF');
    expect(String.fromCharCodes(result.bytes.skip(8).take(4)), 'WEBP');
  });

  testWidgets('stopWebp returns the format-neutral MotionRecording alias', (
    tester,
  ) async {
    final controller = MotionRecorderController();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 1,
            height: 1,
            child: MotionRecorder(
              controller: controller,
              child: const ColoredBox(color: Color(0x80008f8a)),
            ),
          ),
        ),
      ),
    );

    await controller.start(
      options: const MotionRecorderOptions(
        framesPerSecond: 1,
        pixelRatio: 1,
        useBackgroundIsolate: false,
      ),
    );
    final capture = controller.captureFrame();
    await tester.pump();
    await tester.runAsync(() => capture);

    final MotionRecording recording = (await tester.runAsync(
      controller.stopWebp,
    ))!;

    expect(recording.frameCount, 1);
    expect(recording.width, 1);
    expect(recording.height, 1);
    expect(recording.bytes, isNotEmpty);
  });

  testWidgets('collapses identical captures before retaining frame bytes', (
    tester,
  ) async {
    final controller = MotionRecorderController();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 2,
            height: 2,
            child: MotionRecorder(
              controller: controller,
              child: const ColoredBox(color: Color(0x80008f8a)),
            ),
          ),
        ),
      ),
    );

    await controller.start(
      options: const MotionRecorderOptions(
        framesPerSecond: 1,
        pixelRatio: 1,
        useBackgroundIsolate: false,
      ),
    );

    var capture = controller.captureFrame();
    await tester.pump();
    await tester.runAsync(() => capture);
    capture = controller.captureFrame();
    await tester.pump();
    await tester.runAsync(() => capture);

    expect(controller.frameCount, 1);
    expect(controller.diagnostics!.capturedFrames, 2);
    expect(controller.diagnostics!.keptFrames, 1);
    expect(controller.diagnostics!.collapsedFrames, 1);
    expect(controller.diagnostics!.sampledBytes, 32);
    expect(controller.diagnostics!.retainedBytes, 16);

    final clip = await tester.runAsync(controller.stopCapture);
    expect(clip!.frameCount, 1);
    expect(clip.rawBytes, 16);
  });

  testWidgets('stops and exports through the controller shortcut', (
    tester,
  ) async {
    final controller = MotionRecorderController();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 2,
            height: 2,
            child: MotionRecorder(
              controller: controller,
              child: const ColoredBox(color: Color(0x80008f8a)),
            ),
          ),
        ),
      ),
    );

    await controller.start(
      options: const MotionRecorderOptions(
        framesPerSecond: 1,
        pixelRatio: 1,
        useBackgroundIsolate: false,
        collapseIdenticalFrames: false,
      ),
    );

    var capture = controller.captureFrame();
    await tester.pump();
    await tester.runAsync(() => capture);
    capture = controller.captureFrame();
    await tester.pump();
    await tester.runAsync(() => capture);

    final result = await tester.runAsync(
      () => controller.stopExport(
        encoder: const MotionClipEncoder(useBackgroundIsolate: false),
        clipTransform: (clip) =>
            clip.withoutDuplicateLoopClosure(channelTolerance: 8),
      ),
    );

    expect(result!.frameCount, 1);
    expect(result.clip.frameCount, 1);
    expect(result.diagnostics, isNotNull);
    expect(result.diagnostics!.capturedFrames, 2);
    expect(result.diagnostics!.keptFrames, 1);
    expect(result.diagnostics!.collapsedFrames, 1);
    expect(result.diagnostics!.retainedBytes, 16);
    expect(controller.diagnostics!.keptFrames, 1);
    expect(controller.diagnostics!.retainedBytes, 16);
    expect(String.fromCharCodes(result.bytes.take(4)), 'RIFF');
    expect(String.fromCharCodes(result.bytes.skip(8).take(4)), 'WEBP');
  });

  testWidgets('records the next logical loop through the controller helper', (
    tester,
  ) async {
    final controller = MotionRecorderController();
    final loopSignal = MotionLoopSignal();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 2,
            height: 2,
            child: MotionRecorder(
              controller: controller,
              child: const ColoredBox(color: Color(0x80008f8a)),
            ),
          ),
        ),
      ),
    );

    final export = controller.recordNextLoop(
      loopSignal: loopSignal,
      options: const MotionRecorderOptions(
        framesPerSecond: 1,
        pixelRatio: 1,
        useBackgroundIsolate: false,
      ),
      encoder: const MotionClipEncoder(useBackgroundIsolate: false),
      loopDuration: const Duration(seconds: 1),
    );

    loopSignal.markBoundary();
    await _pumpUntil(tester, () => controller.isRecording);

    final capture = controller.captureFrame();
    await tester.pump();
    await tester.runAsync(() => capture);

    loopSignal.markBoundary();
    final result = await tester.runAsync(() => export);

    expect(controller.isRecording, isFalse);
    expect(controller.isEncoding, isFalse);
    expect(result!.duration, const Duration(seconds: 1));
    expect(result.frameCount, 1);
    expect(result.validation, isNotNull);
    expect(result.validation!.isValid, isTrue);
  });

  testWidgets('records the next logical loop as a raw clip', (tester) async {
    final controller = MotionRecorderController();
    final loopSignal = MotionLoopSignal();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 2,
            height: 2,
            child: MotionRecorder(
              controller: controller,
              child: const ColoredBox(color: Color(0x80008f8a)),
            ),
          ),
        ),
      ),
    );

    final clipFuture = controller.recordNextLoopClip(
      loopSignal: loopSignal,
      options: const MotionRecorderOptions(
        framesPerSecond: 1,
        pixelRatio: 1,
        useBackgroundIsolate: false,
      ),
      loopDuration: const Duration(seconds: 1),
    );

    loopSignal.markBoundary();
    await _pumpUntil(tester, () => controller.isRecording);

    final capture = controller.captureFrame();
    await tester.pump();
    await tester.runAsync(() => capture);

    loopSignal.markBoundary();
    final clip = await tester.runAsync(() => clipFuture);

    expect(controller.isRecording, isFalse);
    expect(controller.isEncoding, isFalse);
    expect(clip!.duration, const Duration(seconds: 1));
    expect(clip.frameCount, 1);
    expect(clip.rawBytes, 16);
  });

  testWidgets('recordNextLoopClip cancels capture when start hook fails', (
    tester,
  ) async {
    final controller = MotionRecorderController();
    final loopSignal = MotionLoopSignal();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 2,
            height: 2,
            child: MotionRecorder(
              controller: controller,
              child: const ColoredBox(color: Color(0x80008f8a)),
            ),
          ),
        ),
      ),
    );

    final clipFuture = controller.recordNextLoopClip(
      loopSignal: loopSignal,
      options: const MotionRecorderOptions(
        framesPerSecond: 1,
        pixelRatio: 1,
        useBackgroundIsolate: false,
      ),
      onCaptureStarted: (_) => throw StateError('hook failed'),
    );

    loopSignal.markBoundary();

    await expectLater(clipFuture, throwsA(isA<StateError>()));
    expect(controller.isRecording, isFalse);
    expect(controller.isEncoding, isFalse);
  });

  test('loop boundary waits can be canceled by caller intent', () async {
    final loopSignal = MotionLoopSignal();
    addTearDown(loopSignal.dispose);
    final cancel = Completer<void>();

    final wait = loopSignal.waitForNextBoundary(cancelSignal: cancel.future);
    cancel.complete();

    await expectLater(wait, throwsA(isA<MotionLoopWaitCanceledException>()));
  });

  testWidgets('recordNextLoop can be canceled before capture starts', (
    tester,
  ) async {
    final controller = MotionRecorderController();
    final loopSignal = MotionLoopSignal();
    addTearDown(loopSignal.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 2,
            height: 2,
            child: MotionRecorder(
              controller: controller,
              child: const ColoredBox(color: Color(0x80008f8a)),
            ),
          ),
        ),
      ),
    );

    final cancel = Completer<void>();
    final export = controller.recordNextLoop(
      loopSignal: loopSignal,
      options: const MotionRecorderOptions(
        framesPerSecond: 1,
        pixelRatio: 1,
        useBackgroundIsolate: false,
      ),
      encoder: const MotionClipEncoder(useBackgroundIsolate: false),
      cancelSignal: cancel.future,
    );

    cancel.complete();

    await expectLater(export, throwsA(isA<MotionLoopWaitCanceledException>()));
    expect(controller.isRecording, isFalse);
    expect(controller.isEncoding, isFalse);
  });

  testWidgets('recordNextLoop cancels active capture when caller cancels', (
    tester,
  ) async {
    final controller = MotionRecorderController();
    final loopSignal = MotionLoopSignal();
    addTearDown(loopSignal.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 2,
            height: 2,
            child: MotionRecorder(
              controller: controller,
              child: const ColoredBox(color: Color(0x80008f8a)),
            ),
          ),
        ),
      ),
    );

    final cancel = Completer<void>();
    final export = controller.recordNextLoop(
      loopSignal: loopSignal,
      options: const MotionRecorderOptions(
        framesPerSecond: 1,
        pixelRatio: 1,
        useBackgroundIsolate: false,
      ),
      encoder: const MotionClipEncoder(useBackgroundIsolate: false),
      cancelSignal: cancel.future,
    );

    loopSignal.markBoundary();
    await _pumpUntil(tester, () => controller.isRecording);

    cancel.complete();

    await expectLater(export, throwsA(isA<MotionLoopWaitCanceledException>()));
    expect(controller.isRecording, isFalse);
    expect(controller.isEncoding, isFalse);
  });

  testWidgets('recordNextLoop cancels recording after boundary timeout', (
    tester,
  ) async {
    final controller = MotionRecorderController();
    final loopSignal = MotionLoopSignal();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 2,
            height: 2,
            child: MotionRecorder(
              controller: controller,
              child: const ColoredBox(color: Color(0x80008f8a)),
            ),
          ),
        ),
      ),
    );

    final export = controller.recordNextLoop(
      loopSignal: loopSignal,
      options: const MotionRecorderOptions(
        framesPerSecond: 1,
        pixelRatio: 1,
        useBackgroundIsolate: false,
      ),
      encoder: const MotionClipEncoder(useBackgroundIsolate: false),
      boundaryTimeout: const Duration(milliseconds: 500),
    );

    loopSignal.markBoundary();
    await _pumpUntil(tester, () => controller.isRecording);

    final timeoutExpectation = expectLater(
      export,
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await timeoutExpectation;
    expect(controller.isRecording, isFalse);
    expect(controller.isEncoding, isFalse);
  });

  testWidgets('failed stopExport leaves controller idle', (tester) async {
    final controller = MotionRecorderController();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 2,
            height: 2,
            child: MotionRecorder(
              controller: controller,
              child: const ColoredBox(color: Color(0x80008f8a)),
            ),
          ),
        ),
      ),
    );

    await controller.start(
      options: const MotionRecorderOptions(
        framesPerSecond: 1,
        pixelRatio: 1,
        useBackgroundIsolate: false,
      ),
    );

    final capture = controller.captureFrame();
    await tester.pump();
    await tester.runAsync(() => capture);

    Object? exportError;
    await tester.runAsync(() async {
      try {
        await controller.stopExport(
          encoder: const _ThrowingMotionClipEncoder(),
        );
      } catch (error) {
        exportError = error;
      }
    });

    expect(exportError, isA<StateError>());

    expect(controller.isRecording, isFalse);
    expect(controller.isEncoding, isFalse);
  });

  test('summarizes capture diagnostics', () {
    const diagnostics = WebpCaptureDiagnostics(
      targetFramesPerSecond: 60,
      pixelRatio: 1,
      captureElapsed: Duration(seconds: 2),
      requestedFrames: 120,
      capturedFrames: 90,
      keptFrames: 80,
      skippedFrames: 30,
      collapsedFrames: 10,
      width: 10,
      height: 20,
      sampledBytes: 72000,
      retainedBytes: 64000,
      totalCaptureTime: Duration(milliseconds: 900),
      totalFrameWaitTime: Duration(milliseconds: 180),
      totalToImageTime: Duration(milliseconds: 450),
      totalToByteDataTime: Duration(milliseconds: 270),
      totalStoreTime: Duration(milliseconds: 90),
      maxCaptureTime: Duration(milliseconds: 20),
      maxFrameWaitTime: Duration(milliseconds: 5),
      maxToImageTime: Duration(milliseconds: 10),
      maxToByteDataTime: Duration(milliseconds: 8),
      maxStoreTime: Duration(milliseconds: 3),
    );

    expect(diagnostics.effectiveCapturedFps, 45);
    expect(diagnostics.skippedFrameRatio, 0.25);
    expect(diagnostics.targetFrameRateRatio, 0.75);
    expect(diagnostics.hasSkippedFrames, isTrue);
    expect(diagnostics.hasCollapsedFrames, isTrue);
    expect(diagnostics.qualityStatus, MotionCaptureQualityStatus.backpressure);
    expect(diagnostics.qualityStatus.label, 'backpressure');
    expect(
      diagnostics.qualitySummary,
      'backpressure: capture 45 / target 60 fps, '
      '30 skipped (25%), 90 captured / 80 kept',
    );
    expect(diagnostics.isNearTargetFrameRate, isFalse);
    expect(diagnostics.isCleanCapture, isFalse);
    expect(diagnostics.averageCaptureTime, const Duration(milliseconds: 10));
    expect(diagnostics.averageFrameWaitTime, const Duration(milliseconds: 2));
    expect(diagnostics.averageToImageTime, const Duration(milliseconds: 5));
    expect(diagnostics.averageToByteDataTime, const Duration(milliseconds: 3));
    expect(diagnostics.averageStoreTime, const Duration(milliseconds: 1));
    expect(diagnostics.sampledMebibytes, closeTo(0.0687, 0.0001));
    expect(diagnostics.retainedMebibytes, closeTo(0.0610, 0.0001));

    const clean = WebpCaptureDiagnostics(
      targetFramesPerSecond: 60,
      pixelRatio: 1,
      captureElapsed: Duration(seconds: 2),
      requestedFrames: 120,
      capturedFrames: 120,
      keptFrames: 120,
      skippedFrames: 0,
      collapsedFrames: 0,
      width: 10,
      height: 20,
      sampledBytes: 96000,
      retainedBytes: 96000,
      totalCaptureTime: Duration(milliseconds: 120),
      totalFrameWaitTime: Duration.zero,
      totalToImageTime: Duration(milliseconds: 60),
      totalToByteDataTime: Duration(milliseconds: 40),
      totalStoreTime: Duration(milliseconds: 20),
      maxCaptureTime: Duration(milliseconds: 2),
      maxFrameWaitTime: Duration.zero,
      maxToImageTime: Duration(milliseconds: 1),
      maxToByteDataTime: Duration(milliseconds: 1),
      maxStoreTime: Duration(milliseconds: 1),
    );

    expect(clean.targetFrameRateRatio, 1);
    expect(clean.hasSkippedFrames, isFalse);
    expect(clean.hasCollapsedFrames, isFalse);
    expect(clean.qualityStatus, MotionCaptureQualityStatus.clean);
    expect(clean.qualityStatus.label, 'clean capture');
    expect(
      clean.qualitySummary,
      'clean capture: capture 60 / target 60 fps, '
      '0 skipped (0%), 120 captured / 120 kept',
    );
    expect(clean.isNearTargetFrameRate, isTrue);
    expect(clean.isCleanCapture, isTrue);

    const belowTarget = WebpCaptureDiagnostics(
      targetFramesPerSecond: 60,
      pixelRatio: 1,
      captureElapsed: Duration(seconds: 2),
      requestedFrames: 90,
      capturedFrames: 90,
      keptFrames: 90,
      skippedFrames: 0,
      collapsedFrames: 0,
      width: 10,
      height: 20,
      sampledBytes: 72000,
      retainedBytes: 72000,
      totalCaptureTime: Duration(milliseconds: 90),
      totalFrameWaitTime: Duration.zero,
      totalToImageTime: Duration(milliseconds: 45),
      totalToByteDataTime: Duration(milliseconds: 30),
      totalStoreTime: Duration(milliseconds: 15),
      maxCaptureTime: Duration(milliseconds: 2),
      maxFrameWaitTime: Duration.zero,
      maxToImageTime: Duration(milliseconds: 1),
      maxToByteDataTime: Duration(milliseconds: 1),
      maxStoreTime: Duration(milliseconds: 1),
    );

    expect(
      belowTarget.qualityStatus,
      MotionCaptureQualityStatus.belowTargetFrameRate,
    );
    expect(belowTarget.qualityStatus.label, 'below target');
    expect(
      belowTarget.qualitySummary,
      'below target: capture 45 / target 60 fps, '
      '0 skipped (0%), 90 captured / 90 kept',
    );
    expect(belowTarget.hasSkippedFrames, isFalse);
    expect(belowTarget.isNearTargetFrameRate, isFalse);
    expect(belowTarget.isCleanCapture, isFalse);
  });

  testWidgets('records deterministic canvas motion clips', (tester) async {
    final clip = await tester.runAsync(
      () =>
          const MotionCanvasRecorder(
            size: Size(2, 2),
            duration: Duration(seconds: 1),
            framesPerSecond: 10,
          ).record((canvas, size, progress, elapsed) {
            canvas.drawRect(
              ui.Offset.zero & size,
              ui.Paint()..color = const ui.Color(0x80ff0000),
            );
          }),
    );

    expect(clip!.frameCount, 10);
    expect(clip.width, 2);
    expect(clip.height, 2);
    expect(clip.duration, const Duration(seconds: 1));
    expect(clip.frames.first.rgbaBytes.take(4), <int>[255, 0, 0, 128]);
  });

  testWidgets('ceil deterministic canvas frame counts for uneven durations', (
    tester,
  ) async {
    const recorder = MotionCanvasRecorder(
      size: Size(1, 1),
      duration: Duration(milliseconds: 101),
      framesPerSecond: 10,
    );

    expect(recorder.frameCount, 2);

    final clip = await tester.runAsync(
      () => recorder.record((canvas, size, progress, elapsed) {
        canvas.drawRect(
          ui.Offset.zero & size,
          ui.Paint()..color = const ui.Color(0xffffffff),
        );
      }),
    );

    expect(clip!.frameCount, 2);
    expect(clip.duration, const Duration(milliseconds: 101));
    expect(clip.frames.map((frame) => frame.duration.inMicroseconds), <int>[
      50500,
      50500,
    ]);
  });

  testWidgets('records a widget subtree into animated WebP', (tester) async {
    final controller = WebpRecorderController();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 2,
            height: 2,
            child: WebpRecorder(
              controller: controller,
              child: const ColoredBox(color: Color(0x80ff0000)),
            ),
          ),
        ),
      ),
    );

    await controller.start(
      options: const WebpRecorderOptions(
        framesPerSecond: 1,
        pixelRatio: 1,
        useBackgroundIsolate: false,
      ),
    );

    final capture = controller.captureFrame();
    await tester.pump();
    await tester.runAsync(() => capture);

    final recording = (await tester.runAsync(controller.stop))!;

    expect(recording.width, 2);
    expect(recording.height, 2);
    expect(recording.frameCount, 1);
    expect(recording.bytes, isNotEmpty);
    expect(recording.diagnostics, isNotNull);
    expect(recording.diagnostics!.capturedFrames, 1);
    expect(recording.diagnostics!.keptFrames, 1);
    expect(recording.diagnostics!.width, 2);
    expect(recording.diagnostics!.height, 2);
    expect(recording.diagnostics!.retainedBytes, 16);

    final decoder = img.WebPDecoder(recording.bytes);
    expect(decoder.info, isNotNull);
    expect(decoder.numFrames(), 1);
    final decoded = decoder.decodeFrame(0)!;
    final pixel = decoded.getPixel(0, 0);
    expect(pixel.r.toInt(), 255);
    expect(pixel.g.toInt(), 0);
    expect(pixel.b.toInt(), 0);
    expect(pixel.a.toInt(), 128);
  });

  testWidgets('converts captured Flutter pixels to straight alpha', (
    tester,
  ) async {
    final controller = WebpRecorderController();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 1,
            height: 1,
            child: WebpRecorder(
              controller: controller,
              child: const ColoredBox(color: Color(0x80ff0000)),
            ),
          ),
        ),
      ),
    );

    await controller.start(
      options: const WebpRecorderOptions(
        pixelRatio: 1,
        useBackgroundIsolate: false,
      ),
    );

    final capture = controller.captureFrame();
    await tester.pump();
    await tester.runAsync(() => capture);

    final clip = await tester.runAsync(controller.stopCapture);
    expect(clip!.frames.single.rgbaBytes.take(4), <int>[255, 0, 0, 128]);
  });

  testWidgets('uses elapsed capture time for frame durations', (tester) async {
    final controller = WebpRecorderController();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 2,
            height: 2,
            child: WebpRecorder(
              controller: controller,
              child: const ColoredBox(color: Color(0x80ff0000)),
            ),
          ),
        ),
      ),
    );

    await controller.start(
      options: const WebpRecorderOptions(
        framesPerSecond: 1,
        pixelRatio: 1,
        collapseIdenticalFrames: false,
        useBackgroundIsolate: false,
      ),
    );

    var capture = controller.captureFrame();
    await tester.pump();
    await tester.runAsync(() => capture);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );

    capture = controller.captureFrame();
    await tester.pump();
    await tester.runAsync(() => capture);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );

    final clip = await tester.runAsync(controller.stopCapture);

    expect(clip!.frameCount, 2);
    expect(clip.duration, greaterThan(const Duration(milliseconds: 80)));
  });

  test('creates premultiplied RGBA copies for Flutter image preview', () {
    final source = Uint8List.fromList(<int>[
      255,
      128,
      0,
      128,
      20,
      40,
      60,
      255,
      250,
      250,
      250,
      0,
    ]);
    final frame = MotionFrame(
      width: 3,
      height: 1,
      duration: const Duration(milliseconds: 16),
      rgbaBytes: source,
    );

    final premultiplied = frame.toPremultipliedRgbaBytes();

    expect(premultiplied, <int>[128, 64, 0, 128, 20, 40, 60, 255, 0, 0, 0, 0]);
    expect(frame.rgbaBytes, source);
    expect(identical(premultiplied, source), isFalse);
  });

  test('encodes animated WebP frames with transparency', () {
    final frames = <WebpFrame>[
      WebpFrame(
        width: 2,
        height: 2,
        duration: const Duration(milliseconds: 80),
        rgbaBytes: Uint8List.fromList(<int>[
          255,
          0,
          0,
          0,
          0,
          255,
          0,
          255,
          0,
          0,
          255,
          255,
          255,
          255,
          255,
          255,
        ]),
      ),
      WebpFrame(
        width: 2,
        height: 2,
        duration: const Duration(milliseconds: 120),
        rgbaBytes: Uint8List.fromList(<int>[
          255,
          0,
          0,
          128,
          0,
          255,
          0,
          255,
          0,
          0,
          255,
          255,
          255,
          255,
          255,
          0,
        ]),
      ),
    ];

    final bytes = const WebpAnimationEncoder().encode(frames);
    expect(_asciiAt(bytes, 0, 4), 'RIFF');
    expect(_asciiAt(bytes, 8, 4), 'WEBP');
    expect(_topLevelChunks(bytes), <String>['VP8X', 'ANIM', 'ANMF', 'ANMF']);

    const vp8xPayloadOffset = 12 + 8;
    expect(bytes[vp8xPayloadOffset], 0x12);

    final decoder = img.WebPDecoder(bytes);
    expect(decoder.info, isNotNull);
    expect(decoder.numFrames(), 2);

    final decodedFirst = decoder.decodeFrame(0)!;
    final decodedSecond = decoder.decodeFrame(1)!;

    expect(decodedFirst.width, 2);
    expect(decodedFirst.height, 2);
    expect(decodedFirst.getPixel(0, 0).r.toInt(), 255);
    expect(decodedFirst.getPixel(0, 0).g.toInt(), 0);
    expect(decodedFirst.getPixel(0, 0).b.toInt(), 0);
    expect(decodedFirst.getPixel(0, 0).a.toInt(), 0);
    expect(decodedSecond.getPixel(0, 0).r.toInt(), 255);
    expect(decodedSecond.getPixel(0, 0).g.toInt(), 0);
    expect(decodedSecond.getPixel(0, 0).b.toInt(), 0);
    expect(decodedSecond.getPixel(0, 0).a.toInt(), 128);
    expect(decodedSecond.getPixel(1, 1).a.toInt(), 0);
  });

  test('streams animated WebP frames through a seekable sink', () {
    final frames = <WebpFrame>[
      WebpFrame(
        width: 4,
        height: 4,
        duration: const Duration(milliseconds: 80),
        rgbaBytes: _rectFrameBytes(
          width: 4,
          height: 4,
          x: 0,
          y: 0,
          rectWidth: 4,
          rectHeight: 4,
          color: <int>[255, 255, 255, 255],
        ),
      ),
      WebpFrame(
        width: 4,
        height: 4,
        duration: const Duration(milliseconds: 120),
        rgbaBytes: _frameBytesWithPixel(
          _rectFrameBytes(
            width: 4,
            height: 4,
            x: 0,
            y: 0,
            rectWidth: 4,
            rectHeight: 4,
            color: <int>[255, 255, 255, 255],
          ),
          width: 4,
          x: 3,
          y: 2,
          color: <int>[0, 143, 138, 255],
        ),
      ),
    ];
    final sink = _MemoryWebpAnimationSink();
    final encoder = WebpAnimationStreamEncoder(sink: sink, width: 4, height: 4);

    for (final frame in frames) {
      final writesBefore = sink.writeCount;
      encoder.addFrame(frame);
      expect(sink.writeCount - writesBefore, lessThanOrEqualTo(3));
    }
    encoder.close();
    final bytes = sink.takeBytes();
    final controls = _webpFrameControls(bytes);

    expect(encoder.frameCount, 2);
    expect(encoder.duration, const Duration(milliseconds: 200));
    expect(_asciiAt(bytes, 0, 4), 'RIFF');
    expect(_asciiAt(bytes, 8, 4), 'WEBP');
    expect(_topLevelChunks(bytes), <String>['VP8X', 'ANIM', 'ANMF', 'ANMF']);
    expect(controls.last.width, 2);
    expect(controls.last.height, 1);

    final decoder = img.WebPDecoder(bytes);
    expect(decoder.info, isNotNull);
    expect(decoder.numFrames(), 2);
    final compositedFrames = _composeAnimatedWebpFrames(bytes);
    expect(compositedFrames[1], frames[1].rgbaBytes);
  });

  test('stream WebP copies previous frame bytes by default', () {
    final firstBytes = _rectFrameBytes(
      width: 4,
      height: 4,
      x: 0,
      y: 0,
      rectWidth: 4,
      rectHeight: 4,
      color: <int>[255, 255, 255, 255],
    );
    final secondBytes = _frameBytesWithPixel(
      Uint8List.fromList(firstBytes),
      width: 4,
      x: 3,
      y: 2,
      color: <int>[0, 143, 138, 255],
    );
    final sink = _MemoryWebpAnimationSink();
    final encoder = WebpAnimationStreamEncoder(sink: sink, width: 4, height: 4);

    encoder.addFrame(
      WebpFrame(
        width: 4,
        height: 4,
        duration: const Duration(milliseconds: 80),
        rgbaBytes: firstBytes,
      ),
    );
    firstBytes.setRange(0, firstBytes.lengthInBytes, secondBytes);
    encoder.addFrame(
      WebpFrame(
        width: 4,
        height: 4,
        duration: const Duration(milliseconds: 120),
        rgbaBytes: secondBytes,
      ),
    );
    encoder.close();

    final bytes = sink.takeBytes();
    final controls = _webpFrameControls(bytes);
    expect(controls.last.width, 2);
    expect(controls.last.height, 1);
    expect(_composeAnimatedWebpFrames(bytes)[1], secondBytes);
  });

  test('stream WebP can retain previous frame bytes by reference', () {
    final firstBytes = _rectFrameBytes(
      width: 4,
      height: 4,
      x: 0,
      y: 0,
      rectWidth: 4,
      rectHeight: 4,
      color: <int>[255, 255, 255, 255],
    );
    final secondBytes = _frameBytesWithPixel(
      Uint8List.fromList(firstBytes),
      width: 4,
      x: 3,
      y: 2,
      color: <int>[0, 143, 138, 255],
    );
    final sink = _MemoryWebpAnimationSink();
    final encoder = WebpAnimationStreamEncoder(
      sink: sink,
      width: 4,
      height: 4,
      options: const WebpAnimationOptions(
        trimChangedFrames: true,
        previousFrameRetentionPolicy:
            WebpPreviousFrameRetentionPolicy.reference,
      ),
    );

    encoder.addFrame(
      WebpFrame(
        width: 4,
        height: 4,
        duration: const Duration(milliseconds: 80),
        rgbaBytes: firstBytes,
      ),
    );
    firstBytes.setRange(0, firstBytes.lengthInBytes, secondBytes);
    encoder.addFrame(
      WebpFrame(
        width: 4,
        height: 4,
        duration: const Duration(milliseconds: 120),
        rgbaBytes: secondBytes,
      ),
    );
    encoder.close();

    final controls = _webpFrameControls(sink.takeBytes());
    expect(controls.last.width, 1);
    expect(controls.last.height, 1);
  });

  test('stream WebP duration errors do not advance encoder state', () {
    final sink = _MemoryWebpAnimationSink();
    final encoder = WebpAnimationStreamEncoder(sink: sink, width: 1, height: 1);
    final first = WebpFrame(
      width: 1,
      height: 1,
      duration: const Duration(milliseconds: 80),
      rgbaBytes: Uint8List.fromList(<int>[255, 255, 255, 255]),
    );
    final invalid = WebpFrame(
      width: 1,
      height: 1,
      duration: const Duration(milliseconds: 0x1000000),
      rgbaBytes: Uint8List.fromList(<int>[0, 0, 0, 255]),
    );
    final second = WebpFrame(
      width: 1,
      height: 1,
      duration: const Duration(milliseconds: 120),
      rgbaBytes: Uint8List.fromList(<int>[0, 0, 0, 255]),
    );

    encoder.addFrame(first);
    expect(() => encoder.addFrame(invalid), throwsArgumentError);
    expect(encoder.frameCount, 1);
    expect(encoder.duration, const Duration(milliseconds: 80));

    encoder.addFrame(second);
    encoder.close();

    expect(
      _webpFrameControls(sink.takeBytes()).map((control) => control.durationMs),
      <int>[80, 120],
    );
  });

  test('writes streamed WebP frames directly to a file', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'motion_exporter_webp_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final file = File('${tempDir.path}${Platform.pathSeparator}stream.webp');
    final writer = await WebpAnimationFileWriter.open(
      file: file,
      width: 4,
      height: 4,
    );

    writer.addFrame(
      WebpFrame(
        width: 4,
        height: 4,
        duration: const Duration(milliseconds: 80),
        rgbaBytes: _rectFrameBytes(
          width: 4,
          height: 4,
          x: 0,
          y: 0,
          rectWidth: 4,
          rectHeight: 4,
          color: <int>[255, 255, 255, 255],
        ),
      ),
    );
    writer.addFrame(
      WebpFrame(
        width: 4,
        height: 4,
        duration: const Duration(milliseconds: 120),
        rgbaBytes: _frameBytesWithPixel(
          _rectFrameBytes(
            width: 4,
            height: 4,
            x: 0,
            y: 0,
            rectWidth: 4,
            rectHeight: 4,
            color: <int>[255, 255, 255, 255],
          ),
          width: 4,
          x: 3,
          y: 2,
          color: <int>[0, 143, 138, 255],
        ),
      ),
    );

    final recording = await writer.close();
    final bytes = file.readAsBytesSync();

    expect(recording.file.path, file.path);
    expect(recording.frameCount, 2);
    expect(recording.width, 4);
    expect(recording.height, 4);
    expect(recording.duration, const Duration(milliseconds: 200));
    expect(recording.byteLength, file.lengthSync());
    expect(recording.inspect().frameCount, 2);
    expect(recording.validateEncodedFile().isValid, isTrue);
    final frameControls = _webpFrameControls(bytes);
    expect(frameControls.map((control) => control.durationMs), <int>[80, 120]);
    expect(frameControls.last.width, 2);
    expect(frameControls.last.height, 1);
    expect(img.WebPDecoder(bytes).numFrames(), 2);
  });

  test('writes a motion clip directly to a streamed WebP file', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'motion_exporter_webp_clip_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final clip = MotionClip(
      frames: <MotionFrame>[
        MotionFrame(
          width: 4,
          height: 4,
          duration: const Duration(milliseconds: 80),
          rgbaBytes: _rectFrameBytes(
            width: 4,
            height: 4,
            x: 0,
            y: 0,
            rectWidth: 4,
            rectHeight: 4,
            color: <int>[255, 255, 255, 255],
          ),
        ),
        MotionFrame(
          width: 4,
          height: 4,
          duration: const Duration(milliseconds: 120),
          rgbaBytes: _frameBytesWithPixel(
            _rectFrameBytes(
              width: 4,
              height: 4,
              x: 0,
              y: 0,
              rectWidth: 4,
              rectHeight: 4,
              color: <int>[255, 255, 255, 255],
            ),
            width: 4,
            x: 3,
            y: 2,
            color: <int>[0, 143, 138, 255],
          ),
        ),
      ],
    );
    final file = File('${tempDir.path}${Platform.pathSeparator}clip.webp');

    final recording = await writeWebpAnimationFile(file: file, clip: clip);

    expect(recording.file.path, file.path);
    expect(recording.frameCount, clip.frameCount);
    expect(recording.duration, clip.duration);
    expect(recording.byteLength, file.lengthSync());
    expect(recording.inspect().isAnimated, isTrue);
    expect(recording.validateEncodedFile().isValid, isTrue);
    expect(img.WebPDecoder(file.readAsBytesSync()).numFrames(), 2);
  });

  test('file writer closes file when open validation fails', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'motion_exporter_webp_open_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final file = File('${tempDir.path}${Platform.pathSeparator}stream.webp');
    await file.writeAsBytes(<int>[9, 8, 7], flush: true);

    await expectLater(
      WebpAnimationFileWriter.open(file: file, width: 0, height: 2),
      throwsArgumentError,
    );

    expect(file.readAsBytesSync(), <int>[9, 8, 7]);
  });

  test('file writer closes file when encoder close fails', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'motion_exporter_webp_close_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final file = File('${tempDir.path}${Platform.pathSeparator}stream.webp');
    final writer = await WebpAnimationFileWriter.open(
      file: file,
      width: 2,
      height: 2,
    );

    await expectLater(writer.close(), throwsStateError);
    await file.writeAsBytes(<int>[1, 2, 3], flush: true);

    expect(file.readAsBytesSync(), <int>[1, 2, 3]);
  });

  test('trims transparent WebP animation frames', () {
    final frames = <WebpFrame>[
      WebpFrame(
        width: 6,
        height: 6,
        duration: const Duration(milliseconds: 80),
        rgbaBytes: _rectFrameBytes(
          width: 6,
          height: 6,
          x: 0,
          y: 0,
          rectWidth: 1,
          rectHeight: 1,
          color: <int>[255, 0, 0, 255],
        ),
      ),
      WebpFrame(
        width: 6,
        height: 6,
        duration: const Duration(milliseconds: 80),
        rgbaBytes: _rectFrameBytes(
          width: 6,
          height: 6,
          x: 3,
          y: 3,
          rectWidth: 2,
          rectHeight: 2,
          color: <int>[0, 255, 0, 255],
        ),
      ),
    ];

    final bytes = const WebpAnimationEncoder().encode(frames);
    final controls = _webpFrameControls(bytes);

    expect(controls, hasLength(2));
    expect(
      controls.first,
      const _WebpFrameControl(
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        durationMs: 80,
        flags: 0x03,
      ),
    );
    expect(
      controls.last,
      const _WebpFrameControl(
        x: 2,
        y: 2,
        width: 3,
        height: 3,
        durationMs: 80,
        flags: 0x03,
      ),
    );

    final compositedFrames = _composeAnimatedWebpFrames(bytes);
    expect(compositedFrames, hasLength(2));
    expect(compositedFrames[0], frames[0].rgbaBytes);
    expect(compositedFrames[1], frames[1].rgbaBytes);
  });

  test('trims transparent WebP frames from unaligned RGBA buffers', () {
    final frames = <WebpFrame>[
      WebpFrame(
        width: 6,
        height: 6,
        duration: const Duration(milliseconds: 80),
        rgbaBytes: _unalignedBytes(
          _rectFrameBytes(
            width: 6,
            height: 6,
            x: 0,
            y: 0,
            rectWidth: 1,
            rectHeight: 1,
            color: <int>[255, 0, 0, 255],
          ),
        ),
      ),
      WebpFrame(
        width: 6,
        height: 6,
        duration: const Duration(milliseconds: 80),
        rgbaBytes: _unalignedBytes(
          _rectFrameBytes(
            width: 6,
            height: 6,
            x: 3,
            y: 3,
            rectWidth: 2,
            rectHeight: 2,
            color: <int>[0, 255, 0, 255],
          ),
        ),
      ),
    ];

    final controls = _webpFrameControls(
      const WebpAnimationEncoder().encode(frames),
    );

    expect(controls.last.x, 2);
    expect(controls.last.y, 2);
    expect(controls.last.width, 3);
    expect(controls.last.height, 3);
  });

  test(
    'preserves high-FPS WebP duration with distributed millisecond delays',
    () {
      final frames = <WebpFrame>[];
      for (var i = 0; i < 240; i++) {
        final frameStartMicros =
            (const Duration(seconds: 2).inMicroseconds * i / 240).round();
        final frameEndMicros =
            (const Duration(seconds: 2).inMicroseconds * (i + 1) / 240).round();
        frames.add(
          WebpFrame(
            width: 1,
            height: 1,
            duration: Duration(microseconds: frameEndMicros - frameStartMicros),
            rgbaBytes: Uint8List.fromList(<int>[0, 143, 138, 255]),
          ),
        );
      }

      final controls = _webpFrameControls(
        const WebpAnimationEncoder().encode(frames),
      );
      final durations = controls.map((control) => control.durationMs).toList();

      expect(controls, hasLength(240));
      expect(durations.reduce((a, b) => a + b), 2000);
      expect(durations.where((duration) => duration == 8), hasLength(160));
      expect(durations.where((duration) => duration == 9), hasLength(80));
    },
  );

  test('can trim WebP frames by changed RGBA bounds', () {
    final firstFrameBytes = _rectFrameBytes(
      width: 4,
      height: 4,
      x: 0,
      y: 0,
      rectWidth: 4,
      rectHeight: 4,
      color: <int>[16, 32, 48, 255],
    );
    final secondFrameBytes = _frameBytesWithPixel(
      firstFrameBytes,
      width: 4,
      x: 3,
      y: 2,
      color: <int>[0, 143, 138, 128],
    );
    final frames = <WebpFrame>[
      WebpFrame(
        width: 4,
        height: 4,
        duration: const Duration(milliseconds: 80),
        rgbaBytes: firstFrameBytes,
      ),
      WebpFrame(
        width: 4,
        height: 4,
        duration: const Duration(milliseconds: 80),
        rgbaBytes: secondFrameBytes,
      ),
    ];

    final bytes = const WebpAnimationEncoder(
      WebpAnimationOptions(trimChangedFrames: true),
    ).encode(frames);
    final controls = _webpFrameControls(bytes);

    expect(controls, hasLength(2));
    expect(
      controls.first,
      const _WebpFrameControl(
        x: 0,
        y: 0,
        width: 4,
        height: 4,
        durationMs: 80,
        flags: 0x02,
      ),
    );
    expect(
      controls.last,
      const _WebpFrameControl(
        x: 2,
        y: 2,
        width: 2,
        height: 1,
        durationMs: 80,
        flags: 0x02,
      ),
    );

    final compositedFrames = _composeAnimatedWebpFrames(bytes);
    expect(compositedFrames, hasLength(2));
    expect(compositedFrames[0], frames[0].rgbaBytes);
    expect(compositedFrames[1], frames[1].rgbaBytes);
  });

  test('can trim WebP frames from unaligned RGBA buffers', () {
    final firstFrameBytes = _unalignedBytes(
      _rectFrameBytes(
        width: 4,
        height: 4,
        x: 0,
        y: 0,
        rectWidth: 4,
        rectHeight: 4,
        color: <int>[16, 32, 48, 255],
      ),
    );
    final secondFrameBytes = _unalignedBytes(
      _frameBytesWithPixel(
        firstFrameBytes,
        width: 4,
        x: 3,
        y: 2,
        color: <int>[0, 143, 138, 128],
      ),
    );
    final frames = <WebpFrame>[
      WebpFrame(
        width: 4,
        height: 4,
        duration: const Duration(milliseconds: 80),
        rgbaBytes: firstFrameBytes,
      ),
      WebpFrame(
        width: 4,
        height: 4,
        duration: const Duration(milliseconds: 80),
        rgbaBytes: secondFrameBytes,
      ),
    ];

    final controls = _webpFrameControls(
      const WebpAnimationEncoder(
        WebpAnimationOptions(trimChangedFrames: true),
      ).encode(frames),
    );

    expect(controls.last.x, 2);
    expect(controls.last.y, 2);
    expect(controls.last.width, 2);
    expect(controls.last.height, 1);
  });

  test('can disable transparent WebP frame trimming', () {
    final frames = <WebpFrame>[
      WebpFrame(
        width: 2,
        height: 2,
        duration: const Duration(milliseconds: 80),
        rgbaBytes: Uint8List.fromList(<int>[
          255,
          0,
          0,
          255,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]),
      ),
      WebpFrame(
        width: 2,
        height: 2,
        duration: const Duration(milliseconds: 80),
        rgbaBytes: Uint8List.fromList(<int>[
          0,
          0,
          0,
          0,
          0,
          255,
          0,
          255,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]),
      ),
    ];

    final bytes = const WebpAnimationEncoder(
      WebpAnimationOptions(trimTransparentFrames: false),
    ).encode(frames);
    final controls = _webpFrameControls(bytes);

    expect(controls, hasLength(2));
    expect(
      controls.last,
      const _WebpFrameControl(
        x: 0,
        y: 0,
        width: 2,
        height: 2,
        durationMs: 80,
        flags: 0x02,
      ),
    );
  });

  test('encodes animated PNG frames with transparency', () {
    final frames = <MotionFrame>[
      MotionFrame(
        width: 2,
        height: 2,
        duration: const Duration(milliseconds: 80),
        rgbaBytes: Uint8List.fromList(<int>[
          255,
          0,
          0,
          128,
          0,
          255,
          0,
          255,
          0,
          0,
          255,
          255,
          255,
          255,
          255,
          0,
        ]),
      ),
      MotionFrame(
        width: 2,
        height: 2,
        duration: const Duration(milliseconds: 120),
        rgbaBytes: Uint8List.fromList(<int>[
          0,
          255,
          0,
          255,
          255,
          0,
          0,
          128,
          255,
          255,
          255,
          0,
          0,
          0,
          255,
          255,
        ]),
      ),
    ];

    final bytes = const ApngAnimationEncoder().encode(frames);
    expect(_asciiAt(bytes, 1, 3), 'PNG');
    expect(_pngChunks(bytes), containsAllInOrder(<String>['acTL', 'fcTL']));

    final decoder = img.PngDecoder();
    final decoded = decoder.decode(bytes)!;

    expect(decoded.numFrames, 2);
    expect(decoded.frames.first.getPixel(0, 0).r.toInt(), 255);
    expect(decoded.frames.first.getPixel(0, 0).a.toInt(), 128);
    expect(decoded.frames.last.getPixel(1, 0).r.toInt(), 255);
    expect(decoded.frames.last.getPixel(1, 0).a.toInt(), 128);
  });

  test('encodes high-FPS APNG delays as fractional frame rates', () {
    final frames = <MotionFrame>[
      MotionFrame(
        width: 1,
        height: 1,
        duration: const Duration(microseconds: 8333),
        rgbaBytes: Uint8List.fromList(<int>[0, 143, 138, 255]),
      ),
      MotionFrame(
        width: 1,
        height: 1,
        duration: const Duration(microseconds: 8334),
        rgbaBytes: Uint8List.fromList(<int>[255, 90, 95, 255]),
      ),
    ];

    final controls = _pngFrameControls(
      const ApngAnimationEncoder().encode(frames),
    );

    expect(controls, hasLength(2));
    expect(controls.every((control) => control.delayNumerator == 1), isTrue);
    expect(
      controls.every((control) => control.delayDenominator == 120),
      isTrue,
    );
  });

  test('trims transparent APNG frames after the first frame', () {
    final frames = <MotionFrame>[
      MotionFrame(
        width: 4,
        height: 4,
        duration: const Duration(milliseconds: 80),
        rgbaBytes: Uint8List.fromList(<int>[
          255,
          0,
          0,
          128,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]),
      ),
      MotionFrame(
        width: 4,
        height: 4,
        duration: const Duration(milliseconds: 80),
        rgbaBytes: Uint8List.fromList(<int>[
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          255,
          0,
          255,
          0,
          0,
          255,
          255,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          255,
          255,
          0,
          255,
          255,
          0,
          255,
          255,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]),
      ),
    ];

    final bytes = const ApngAnimationEncoder().encode(frames);
    final controls = _pngFrameControls(bytes);

    expect(controls, hasLength(2));
    expect(
      controls.first,
      const _PngFrameControl(width: 4, height: 4, x: 0, y: 0),
    );
    expect(
      controls.last,
      const _PngFrameControl(width: 2, height: 2, x: 1, y: 1),
    );

    final decoded = img.PngDecoder().decode(bytes)!;
    expect(decoded.numFrames, 2);
    expect(decoded.frames.last.getPixel(1, 1).g.toInt(), 255);
    expect(decoded.frames.last.getPixel(2, 2).b.toInt(), 255);

    final compositedFrames = _composeAnimatedPngFrames(bytes);
    expect(compositedFrames, hasLength(2));
    expect(compositedFrames[0], frames[0].rgbaBytes);
    expect(compositedFrames[1], frames[1].rgbaBytes);
  });

  test('trims transparent APNG frames from unaligned RGBA buffers', () {
    final frames = <MotionFrame>[
      MotionFrame(
        width: 2,
        height: 2,
        duration: const Duration(milliseconds: 80),
        rgbaBytes: _unalignedBytes(
          Uint8List.fromList(<int>[
            255,
            0,
            0,
            255,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
          ]),
        ),
      ),
      MotionFrame(
        width: 2,
        height: 2,
        duration: const Duration(milliseconds: 80),
        rgbaBytes: _unalignedBytes(
          Uint8List.fromList(<int>[
            0,
            0,
            0,
            0,
            0,
            255,
            0,
            255,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
          ]),
        ),
      ),
    ];

    final bytes = const ApngAnimationEncoder().encode(frames);
    final controls = _pngFrameControls(bytes);

    expect(controls, hasLength(2));
    expect(
      controls.last,
      const _PngFrameControl(width: 1, height: 1, x: 1, y: 0),
    );
    expect(_composeAnimatedPngFrames(bytes)[1], frames[1].rgbaBytes);
  });

  test('can disable transparent APNG frame trimming', () {
    final frames = <MotionFrame>[
      MotionFrame(
        width: 2,
        height: 2,
        duration: const Duration(milliseconds: 80),
        rgbaBytes: Uint8List.fromList(<int>[
          255,
          0,
          0,
          255,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]),
      ),
      MotionFrame(
        width: 2,
        height: 2,
        duration: const Duration(milliseconds: 80),
        rgbaBytes: Uint8List.fromList(<int>[
          0,
          0,
          0,
          0,
          0,
          255,
          0,
          255,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]),
      ),
    ];

    final bytes = const ApngAnimationEncoder(
      ApngAnimationOptions(trimTransparentFrames: false),
    ).encode(frames);
    final controls = _pngFrameControls(bytes);

    expect(controls, hasLength(2));
    expect(
      controls.last,
      const _PngFrameControl(width: 2, height: 2, x: 0, y: 0),
    );
  });

  test('notifies logical loop boundaries', () {
    final signal = MotionLoopSignal();
    var notifications = 0;
    signal.addListener(() => notifications++);

    signal.markBoundary();
    signal.markBoundary();

    expect(signal.count, 2);
    expect(notifications, 2);
  });

  test('waits for the next logical loop boundary', () async {
    final signal = MotionLoopSignal();

    var completed = false;
    final first = signal.waitForNextBoundary()
      ..then((_) {
        completed = true;
      });
    await Future<void>.delayed(Duration.zero);

    expect(completed, isFalse);
    signal.markBoundary();
    expect(await first, 1);
    expect(completed, isTrue);
    expect(await signal.waitForNextBoundary(afterCount: 0), 1);

    final second = signal.waitForNextBoundary();
    signal.markBoundary();
    expect(await second, 2);
  });

  test('times out while waiting for a logical loop boundary', () async {
    final signal = MotionLoopSignal();

    await expectLater(
      signal.waitForNextBoundary(timeout: const Duration(milliseconds: 1)),
      throwsA(isA<TimeoutException>()),
    );

    signal.markBoundary();
    expect(signal.count, 1);
    expect(await signal.waitForNextBoundary(afterCount: 0), 1);
  });

  test('removes duplicate terminal loop frame', () {
    final first = MotionFrame(
      width: 1,
      height: 1,
      duration: const Duration(milliseconds: 80),
      rgbaBytes: Uint8List.fromList(<int>[255, 0, 0, 128]),
    );
    final middle = MotionFrame(
      width: 1,
      height: 1,
      duration: const Duration(milliseconds: 80),
      rgbaBytes: Uint8List.fromList(<int>[0, 255, 0, 128]),
    );
    final duplicateFirst = MotionFrame(
      width: 1,
      height: 1,
      duration: const Duration(milliseconds: 80),
      rgbaBytes: Uint8List.fromList(<int>[255, 0, 0, 128]),
    );

    final clip = MotionClip(
      frames: <MotionFrame>[first, middle, duplicateFirst],
    );

    expect(clip.hasDuplicateLoopClosure, isTrue);

    final trimmed = clip.withoutDuplicateLoopClosure();
    expect(trimmed.frameCount, 2);
    expect(trimmed.rawBytes, 8);
    expect(trimmed.frames, <MotionFrame>[first, middle]);
  });

  test('can preserve duration when removing duplicate terminal loop frame', () {
    final first = MotionFrame(
      width: 1,
      height: 1,
      duration: const Duration(milliseconds: 40),
      rgbaBytes: Uint8List.fromList(<int>[255, 0, 0, 128]),
    );
    final middle = MotionFrame(
      width: 1,
      height: 1,
      duration: const Duration(milliseconds: 80),
      rgbaBytes: Uint8List.fromList(<int>[0, 255, 0, 128]),
    );
    final duplicateFirst = MotionFrame(
      width: 1,
      height: 1,
      duration: const Duration(milliseconds: 20),
      rgbaBytes: Uint8List.fromList(<int>[255, 0, 0, 128]),
    );

    final clip = MotionClip(
      frames: <MotionFrame>[first, middle, duplicateFirst],
    );

    final trimmed = clip.withoutDuplicateLoopClosure(preserveDuration: true);
    expect(trimmed.frameCount, 2);
    expect(trimmed.duration, clip.duration);
    expect(trimmed.frames.first.duration, const Duration(milliseconds: 60));
    expect(trimmed.frames.last, middle);
    expect(trimmed.frames.first.rgbaBytes, same(first.rgbaBytes));
  });

  test('collapses consecutive duplicate clip frames', () {
    final red = MotionFrame(
      width: 1,
      height: 1,
      duration: const Duration(milliseconds: 40),
      rgbaBytes: Uint8List.fromList(<int>[255, 0, 0, 128]),
    );
    final redAgain = MotionFrame(
      width: 1,
      height: 1,
      duration: const Duration(milliseconds: 20),
      rgbaBytes: Uint8List.fromList(<int>[255, 0, 0, 128]),
    );
    final green = MotionFrame(
      width: 1,
      height: 1,
      duration: const Duration(milliseconds: 30),
      rgbaBytes: Uint8List.fromList(<int>[0, 255, 0, 128]),
    );
    final greenAgain = MotionFrame(
      width: 1,
      height: 1,
      duration: const Duration(milliseconds: 10),
      rgbaBytes: Uint8List.fromList(<int>[0, 255, 0, 128]),
    );
    final clip = MotionClip(
      frames: <MotionFrame>[red, redAgain, green, greenAgain],
    );

    final collapsed = clip.withoutDuplicateFrames();

    expect(collapsed.frameCount, 2);
    expect(collapsed.duration, clip.duration);
    expect(collapsed.rawBytes, 8);
    expect(collapsed.frames[0].duration, const Duration(milliseconds: 60));
    expect(collapsed.frames[1].duration, const Duration(milliseconds: 40));
    expect(collapsed.frames[0].rgbaBytes, same(red.rgbaBytes));
    expect(collapsed.frames[1].rgbaBytes, same(green.rgbaBytes));
  });

  test('collapses duplicate clip frames from unaligned RGBA buffers', () {
    final red = MotionFrame(
      width: 1,
      height: 1,
      duration: const Duration(milliseconds: 40),
      rgbaBytes: _unalignedBytes(Uint8List.fromList(<int>[255, 0, 0, 128])),
    );
    final redAgain = MotionFrame(
      width: 1,
      height: 1,
      duration: const Duration(milliseconds: 20),
      rgbaBytes: _unalignedBytes(Uint8List.fromList(<int>[255, 0, 0, 128])),
    );
    final clip = MotionClip(frames: <MotionFrame>[red, redAgain]);

    final collapsed = clip.withoutDuplicateFrames();

    expect(collapsed.frameCount, 1);
    expect(collapsed.duration, clip.duration);
    expect(collapsed.frames.single.rgbaBytes, same(red.rgbaBytes));
  });

  test('collapses near-duplicate clip frames with tolerance', () {
    final first = MotionFrame(
      width: 1,
      height: 1,
      duration: const Duration(milliseconds: 40),
      rgbaBytes: Uint8List.fromList(<int>[100, 120, 140, 255]),
    );
    final nearDuplicate = MotionFrame(
      width: 1,
      height: 1,
      duration: const Duration(milliseconds: 20),
      rgbaBytes: Uint8List.fromList(<int>[103, 117, 142, 255]),
    );
    final clip = MotionClip(frames: <MotionFrame>[first, nearDuplicate]);

    expect(clip.withoutDuplicateFrames().frameCount, 2);
    expect(clip.withoutDuplicateFrames(channelTolerance: 4).frameCount, 1);
  });

  test('scales clip frame durations to a known total duration', () {
    final first = MotionFrame(
      width: 1,
      height: 1,
      duration: const Duration(milliseconds: 40),
      rgbaBytes: Uint8List.fromList(<int>[255, 0, 0, 128]),
    );
    final second = MotionFrame(
      width: 1,
      height: 1,
      duration: const Duration(milliseconds: 80),
      rgbaBytes: Uint8List.fromList(<int>[0, 255, 0, 128]),
    );
    final clip = MotionClip(frames: <MotionFrame>[first, second]);

    final scaled = clip.withDuration(const Duration(milliseconds: 300));

    expect(scaled.frameCount, 2);
    expect(scaled.duration, const Duration(milliseconds: 300));
    expect(scaled.frames[0].duration, const Duration(milliseconds: 100));
    expect(scaled.frames[1].duration, const Duration(milliseconds: 200));
    expect(scaled.frames[0].rgbaBytes, same(first.rgbaBytes));
    expect(scaled.frames[1].rgbaBytes, same(second.rgbaBytes));
  });

  test('rejects clip duration scaling below one microsecond per frame', () {
    final clip = MotionClip(
      frames: <MotionFrame>[
        MotionFrame(
          width: 1,
          height: 1,
          duration: const Duration(milliseconds: 1),
          rgbaBytes: Uint8List.fromList(<int>[255, 0, 0, 128]),
        ),
        MotionFrame(
          width: 1,
          height: 1,
          duration: const Duration(milliseconds: 1),
          rgbaBytes: Uint8List.fromList(<int>[0, 255, 0, 128]),
        ),
      ],
    );

    expect(
      () => clip.withDuration(const Duration(microseconds: 1)),
      throwsArgumentError,
    );
  });

  test('removes near-duplicate terminal loop frame', () {
    final first = MotionFrame(
      width: 1,
      height: 1,
      duration: const Duration(milliseconds: 80),
      rgbaBytes: Uint8List.fromList(<int>[100, 120, 140, 255]),
    );
    final middle = MotionFrame(
      width: 1,
      height: 1,
      duration: const Duration(milliseconds: 80),
      rgbaBytes: Uint8List.fromList(<int>[0, 255, 0, 255]),
    );
    final nearDuplicateFirst = MotionFrame(
      width: 1,
      height: 1,
      duration: const Duration(milliseconds: 80),
      rgbaBytes: Uint8List.fromList(<int>[104, 117, 142, 255]),
    );

    final clip = MotionClip(
      frames: <MotionFrame>[first, middle, nearDuplicateFirst],
    );

    expect(clip.hasDuplicateLoopClosure, isFalse);
    expect(clip.hasSimilarLoopClosure(channelTolerance: 4), isTrue);
    expect(
      clip.withoutDuplicateLoopClosure(channelTolerance: 4).frames,
      <MotionFrame>[first, middle],
    );
  });

  test('rejects frames with invalid RGBA buffer size', () {
    expect(
      () => WebpFrame(
        width: 2,
        height: 2,
        duration: const Duration(milliseconds: 16),
        rgbaBytes: Uint8List(4),
      ),
      throwsArgumentError,
    );
  });

  test('rejects mixed frame dimensions', () {
    final frames = <WebpFrame>[
      WebpFrame(
        width: 1,
        height: 1,
        duration: const Duration(milliseconds: 16),
        rgbaBytes: Uint8List.fromList(<int>[0, 0, 0, 0]),
      ),
      WebpFrame(
        width: 2,
        height: 1,
        duration: const Duration(milliseconds: 16),
        rgbaBytes: Uint8List.fromList(<int>[0, 0, 0, 0, 0, 0, 0, 0]),
      ),
    ];

    expect(
      () => const WebpAnimationEncoder().encode(frames),
      throwsArgumentError,
    );
  });
}

List<String> _topLevelChunks(Uint8List bytes) {
  final chunks = <String>[];
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final tag = _asciiAt(bytes, offset, 4);
    final size = _readUint32(bytes, offset + 4);
    chunks.add(tag);
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  return chunks;
}

List<_WebpFrameControl> _webpFrameControls(Uint8List bytes) {
  final controls = <_WebpFrameControl>[];
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final tag = _asciiAt(bytes, offset, 4);
    final size = _readUint32(bytes, offset + 4);
    final payload = offset + 8;
    if (tag == 'ANMF') {
      controls.add(
        _WebpFrameControl(
          x: _readUint24(bytes, payload) * 2,
          y: _readUint24(bytes, payload + 3) * 2,
          width: _readUint24(bytes, payload + 6) + 1,
          height: _readUint24(bytes, payload + 9) + 1,
          durationMs: _readUint24(bytes, payload + 12),
          flags: bytes[payload + 15],
        ),
      );
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  return controls;
}

List<Uint8List> _composeAnimatedWebpFrames(Uint8List bytes) {
  final (:width, :height) = _webpCanvasSize(bytes);
  final canvas = Uint8List(width * height * 4);
  final frames = <Uint8List>[];

  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final tag = _asciiAt(bytes, offset, 4);
    final size = _readUint32(bytes, offset + 4);
    final payload = offset + 8;
    final payloadEnd = payload + size;
    if (tag == 'ANMF') {
      final control = _WebpFrameControl(
        x: _readUint24(bytes, payload) * 2,
        y: _readUint24(bytes, payload + 3) * 2,
        width: _readUint24(bytes, payload + 6) + 1,
        height: _readUint24(bytes, payload + 9) + 1,
        durationMs: _readUint24(bytes, payload + 12),
        flags: bytes[payload + 15],
      );
      final frameImage = _decodeWebpFrameChunk(
        Uint8List.sublistView(bytes, payload + 16, payloadEnd),
      );
      _drawWebpFrame(canvas, width, control, frameImage);
      frames.add(Uint8List.fromList(canvas));
      if ((control.flags & 0x01) != 0) {
        _clearWebpRect(canvas, width, control);
      }
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }

  return frames;
}

({int width, int height}) _webpCanvasSize(Uint8List bytes) {
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final tag = _asciiAt(bytes, offset, 4);
    final size = _readUint32(bytes, offset + 4);
    final payload = offset + 8;
    if (tag == 'VP8X') {
      return (
        width: _readUint24(bytes, payload + 4) + 1,
        height: _readUint24(bytes, payload + 7) + 1,
      );
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  throw StateError('WebP file does not contain VP8X canvas info.');
}

img.Image _decodeWebpFrameChunk(Uint8List frameChunk) {
  final bytes = BytesBuilder(copy: false)
    ..add('RIFF'.codeUnits)
    ..add(_uint32Le(4 + frameChunk.length))
    ..add('WEBP'.codeUnits)
    ..add(frameChunk);
  final decoder = img.WebPDecoder(bytes.toBytes());
  return decoder.decodeFrame(0)!;
}

void _drawWebpFrame(
  Uint8List canvas,
  int canvasWidth,
  _WebpFrameControl control,
  img.Image frameImage,
) {
  final replace = (control.flags & 0x02) != 0;
  for (var y = 0; y < control.height; y++) {
    for (var x = 0; x < control.width; x++) {
      final pixel = frameImage.getPixel(x, y);
      final dstOffset = ((control.y + y) * canvasWidth + control.x + x) * 4;
      final srcR = pixel.r.toInt();
      final srcG = pixel.g.toInt();
      final srcB = pixel.b.toInt();
      final srcA = pixel.a.toInt();

      if (replace) {
        canvas[dstOffset] = srcR;
        canvas[dstOffset + 1] = srcG;
        canvas[dstOffset + 2] = srcB;
        canvas[dstOffset + 3] = srcA;
      } else {
        _blendPixel(canvas, dstOffset, srcR, srcG, srcB, srcA);
      }
    }
  }
}

void _blendPixel(
  Uint8List canvas,
  int dstOffset,
  int srcR,
  int srcG,
  int srcB,
  int srcA,
) {
  final dstR = canvas[dstOffset];
  final dstG = canvas[dstOffset + 1];
  final dstB = canvas[dstOffset + 2];
  final dstA = canvas[dstOffset + 3];
  final outA = srcA + ((dstA * (255 - srcA) + 127) ~/ 255);
  if (outA == 0) {
    canvas[dstOffset] = 0;
    canvas[dstOffset + 1] = 0;
    canvas[dstOffset + 2] = 0;
    canvas[dstOffset + 3] = 0;
    return;
  }

  canvas[dstOffset] = _blendChannel(srcR, srcA, dstR, dstA, outA);
  canvas[dstOffset + 1] = _blendChannel(srcG, srcA, dstG, dstA, outA);
  canvas[dstOffset + 2] = _blendChannel(srcB, srcA, dstB, dstA, outA);
  canvas[dstOffset + 3] = outA;
}

int _blendChannel(int src, int srcA, int dst, int dstA, int outA) {
  return ((src * srcA * 255 + dst * dstA * (255 - srcA)) / (outA * 255))
      .round()
      .clamp(0, 255)
      .toInt();
}

void _clearWebpRect(
  Uint8List canvas,
  int canvasWidth,
  _WebpFrameControl control,
) {
  for (var y = 0; y < control.height; y++) {
    final start = ((control.y + y) * canvasWidth + control.x) * 4;
    canvas.fillRange(start, start + control.width * 4, 0);
  }
}

int _readUint24(Uint8List bytes, int offset) {
  return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
}

String _asciiAt(Uint8List bytes, int offset, int length) {
  return String.fromCharCodes(bytes.sublist(offset, offset + length));
}

int _readUint32(Uint8List bytes, int offset) {
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}

Uint8List _uint32Le(int value) {
  return Uint8List.fromList(<int>[
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
    (value >> 24) & 0xff,
  ]);
}

Uint8List _uint32Be(int value) {
  return Uint8List.fromList(<int>[
    (value >> 24) & 0xff,
    (value >> 16) & 0xff,
    (value >> 8) & 0xff,
    value & 0xff,
  ]);
}

List<String> _pngChunks(Uint8List bytes) {
  final chunks = <String>[];
  var offset = 8;
  while (offset + 8 <= bytes.length) {
    final size =
        (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
    chunks.add(_asciiAt(bytes, offset + 4, 4));
    offset += 12 + size;
  }
  return chunks;
}

List<_PngFrameControl> _pngFrameControls(Uint8List bytes) {
  final controls = <_PngFrameControl>[];
  var offset = 8;
  while (offset + 8 <= bytes.length) {
    final size =
        (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
    final type = _asciiAt(bytes, offset + 4, 4);
    final payload = offset + 8;
    if (type == 'fcTL') {
      controls.add(
        _PngFrameControl(
          width: _readPngUint32(bytes, payload + 4),
          height: _readPngUint32(bytes, payload + 8),
          x: _readPngUint32(bytes, payload + 12),
          y: _readPngUint32(bytes, payload + 16),
          delayNumerator: _readPngUint16(bytes, payload + 20),
          delayDenominator: _readPngUint16(bytes, payload + 22),
          disposeOp: bytes[payload + 24],
          blendOp: bytes[payload + 25],
        ),
      );
    }
    offset += 12 + size;
  }
  return controls;
}

List<Uint8List> _composeAnimatedPngFrames(Uint8List bytes) {
  final (:width, :height) = _pngCanvasSize(bytes);
  final canvas = Uint8List(width * height * 4);
  final frames = <Uint8List>[];

  for (final part in _apngFrameParts(bytes)) {
    final image = _decodePngFramePart(part.control, part.idatPayloads);
    _drawPngFrame(canvas, width, part.control, image);
    frames.add(Uint8List.fromList(canvas));
    if (part.control.disposeOp == 1) {
      _clearPngRect(canvas, width, part.control);
    }
  }

  return frames;
}

List<_ApngFramePart> _apngFrameParts(Uint8List bytes) {
  final parts = <_ApngFramePart>[];
  _PngFrameControl? currentControl;
  var currentPayloads = <Uint8List>[];

  void finishCurrent() {
    final control = currentControl;
    if (control == null) {
      return;
    }
    parts.add(
      _ApngFramePart(
        control: control,
        idatPayloads: List<Uint8List>.unmodifiable(currentPayloads),
      ),
    );
    currentControl = null;
    currentPayloads = <Uint8List>[];
  }

  var offset = 8;
  while (offset + 8 <= bytes.length) {
    final size = _readPngUint32(bytes, offset);
    final type = _asciiAt(bytes, offset + 4, 4);
    final payload = offset + 8;
    final payloadEnd = payload + size;

    if (type == 'fcTL') {
      finishCurrent();
      currentControl = _PngFrameControl(
        width: _readPngUint32(bytes, payload + 4),
        height: _readPngUint32(bytes, payload + 8),
        x: _readPngUint32(bytes, payload + 12),
        y: _readPngUint32(bytes, payload + 16),
        delayNumerator: _readPngUint16(bytes, payload + 20),
        delayDenominator: _readPngUint16(bytes, payload + 22),
        disposeOp: bytes[payload + 24],
        blendOp: bytes[payload + 25],
      );
    } else if (type == 'IDAT') {
      currentPayloads.add(Uint8List.sublistView(bytes, payload, payloadEnd));
    } else if (type == 'fdAT') {
      currentPayloads.add(
        Uint8List.sublistView(bytes, payload + 4, payloadEnd),
      );
    } else if (type == 'IEND') {
      finishCurrent();
      break;
    }

    offset += 12 + size;
  }

  return parts;
}

({int width, int height}) _pngCanvasSize(Uint8List bytes) {
  var offset = 8;
  while (offset + 8 <= bytes.length) {
    final size = _readPngUint32(bytes, offset);
    final type = _asciiAt(bytes, offset + 4, 4);
    final payload = offset + 8;
    if (type == 'IHDR') {
      return (
        width: _readPngUint32(bytes, payload),
        height: _readPngUint32(bytes, payload + 4),
      );
    }
    offset += 12 + size;
  }
  throw StateError('PNG file does not contain IHDR canvas info.');
}

img.Image _decodePngFramePart(
  _PngFrameControl control,
  List<Uint8List> idatPayloads,
) {
  final out = BytesBuilder(copy: false)
    ..add(<int>[137, 80, 78, 71, 13, 10, 26, 10])
    ..add(
      _pngChunkBytes('IHDR', _pngIhdrPayload(control.width, control.height)),
    );
  for (final payload in idatPayloads) {
    out.add(_pngChunkBytes('IDAT', payload));
  }
  out.add(_pngChunkBytes('IEND', Uint8List(0)));
  return img.PngDecoder().decode(out.toBytes())!;
}

Uint8List _pngIhdrPayload(int width, int height) {
  return (BytesBuilder(copy: false)
        ..add(_uint32Be(width))
        ..add(_uint32Be(height))
        ..addByte(8)
        ..addByte(6)
        ..addByte(0)
        ..addByte(0)
        ..addByte(0))
      .toBytes();
}

Uint8List _pngChunkBytes(String type, Uint8List payload) {
  final typeBytes = type.codeUnits;
  final out = BytesBuilder(copy: false)
    ..add(_uint32Be(payload.length))
    ..add(typeBytes)
    ..add(payload)
    ..add(_uint32Be(_crc32(typeBytes, payload)));
  return out.toBytes();
}

int _crc32(List<int> typeBytes, Uint8List payload) {
  var crc = 0xffffffff;
  for (final byte in typeBytes) {
    crc = _crc32Table[(crc ^ byte) & 0xff] ^ (crc >> 8);
  }
  for (final byte in payload) {
    crc = _crc32Table[(crc ^ byte) & 0xff] ^ (crc >> 8);
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

final List<int> _crc32Table = List<int>.generate(256, (index) {
  var c = index;
  for (var k = 0; k < 8; k++) {
    c = c.isOdd ? 0xedb88320 ^ (c >> 1) : c >> 1;
  }
  return c & 0xffffffff;
}, growable: false);

void _drawPngFrame(
  Uint8List canvas,
  int canvasWidth,
  _PngFrameControl control,
  img.Image frameImage,
) {
  final source = control.blendOp == 0;
  for (var y = 0; y < control.height; y++) {
    for (var x = 0; x < control.width; x++) {
      final pixel = frameImage.getPixel(x, y);
      final dstOffset = ((control.y + y) * canvasWidth + control.x + x) * 4;
      final srcR = pixel.r.toInt();
      final srcG = pixel.g.toInt();
      final srcB = pixel.b.toInt();
      final srcA = pixel.a.toInt();

      if (source) {
        canvas[dstOffset] = srcR;
        canvas[dstOffset + 1] = srcG;
        canvas[dstOffset + 2] = srcB;
        canvas[dstOffset + 3] = srcA;
      } else {
        _blendPixel(canvas, dstOffset, srcR, srcG, srcB, srcA);
      }
    }
  }
}

void _clearPngRect(
  Uint8List canvas,
  int canvasWidth,
  _PngFrameControl control,
) {
  for (var y = 0; y < control.height; y++) {
    final start = ((control.y + y) * canvasWidth + control.x) * 4;
    canvas.fillRange(start, start + control.width * 4, 0);
  }
}

int _readPngUint32(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

int _readPngUint16(Uint8List bytes, int offset) {
  return (bytes[offset] << 8) | bytes[offset + 1];
}

Uint8List _rectFrameBytes({
  required int width,
  required int height,
  required int x,
  required int y,
  required int rectWidth,
  required int rectHeight,
  required List<int> color,
}) {
  final bytes = Uint8List(width * height * 4);
  for (var yy = y; yy < y + rectHeight; yy++) {
    for (var xx = x; xx < x + rectWidth; xx++) {
      final offset = (yy * width + xx) * 4;
      bytes[offset] = color[0];
      bytes[offset + 1] = color[1];
      bytes[offset + 2] = color[2];
      bytes[offset + 3] = color[3];
    }
  }
  return bytes;
}

Uint8List _frameBytesWithPixel(
  Uint8List source, {
  required int width,
  required int x,
  required int y,
  required List<int> color,
}) {
  final bytes = Uint8List.fromList(source);
  final offset = (y * width + x) * 4;
  bytes[offset] = color[0];
  bytes[offset + 1] = color[1];
  bytes[offset + 2] = color[2];
  bytes[offset + 3] = color[3];
  return bytes;
}

Uint8List _unalignedBytes(Uint8List bytes) {
  final storage = Uint8List(bytes.lengthInBytes + 1);
  storage.setRange(1, storage.lengthInBytes, bytes);
  return Uint8List.sublistView(storage, 1);
}

MotionClip _singlePixelClip() {
  return MotionClip(
    frames: <MotionFrame>[
      MotionFrame(
        width: 1,
        height: 1,
        duration: const Duration(milliseconds: 100),
        rgbaBytes: Uint8List.fromList(<int>[0, 143, 138, 128]),
      ),
    ],
  );
}

MotionCaptureDiagnostics _captureDiagnostics({
  int capturedFrames = 120,
  int skippedFrames = 0,
  int collapsedFrames = 0,
}) {
  return MotionCaptureDiagnostics(
    targetFramesPerSecond: 60,
    pixelRatio: 1,
    captureElapsed: const Duration(seconds: 2),
    requestedFrames: 120,
    capturedFrames: capturedFrames,
    keptFrames: capturedFrames - collapsedFrames,
    skippedFrames: skippedFrames,
    collapsedFrames: collapsedFrames,
    width: 1,
    height: 1,
    sampledBytes: capturedFrames * 4,
    retainedBytes: (capturedFrames - collapsedFrames) * 4,
    totalCaptureTime: Duration(milliseconds: capturedFrames),
    totalFrameWaitTime: Duration.zero,
    totalToImageTime: Duration.zero,
    totalToByteDataTime: Duration.zero,
    totalStoreTime: Duration.zero,
    maxCaptureTime: capturedFrames > 0
        ? const Duration(milliseconds: 1)
        : Duration.zero,
    maxFrameWaitTime: Duration.zero,
    maxToImageTime: Duration.zero,
    maxToByteDataTime: Duration.zero,
    maxStoreTime: Duration.zero,
  );
}

class _ThrowingMotionClipEncoder extends MotionClipEncoder {
  const _ThrowingMotionClipEncoder();

  @override
  Future<MotionExportResult> encode(
    MotionClip clip, {
    MotionCaptureDiagnostics? diagnostics,
  }) async {
    throw StateError('encoding failed');
  }
}

class _RejectingCaptureQualityPolicy extends MotionCaptureQualityPolicy {
  const _RejectingCaptureQualityPolicy();

  @override
  void validate(MotionCaptureDiagnostics? diagnostics) {
    throw MotionCaptureQualityException(
      policy: this,
      diagnostics: diagnostics,
      failures: const <MotionCaptureQualityFailure>[
        MotionCaptureQualityFailure.skippedFrames,
      ],
    );
  }
}

class _MemoryWebpAnimationSink implements WebpAnimationStreamSink {
  final List<int> _bytes = <int>[];
  int _writeCount = 0;

  @override
  int get position => _bytes.length;

  int get writeCount => _writeCount;

  @override
  void writeBytes(Uint8List bytes) {
    _writeCount++;
    _bytes.addAll(bytes);
  }

  @override
  void patchUint32(int offset, int value) {
    if (offset < 0 || offset + 4 > _bytes.length) {
      throw RangeError.range(offset, 0, _bytes.length - 4, 'offset');
    }
    _bytes[offset] = value & 0xff;
    _bytes[offset + 1] = (value >> 8) & 0xff;
    _bytes[offset + 2] = (value >> 16) & 0xff;
    _bytes[offset + 3] = (value >> 24) & 0xff;
  }

  Uint8List takeBytes() => Uint8List.fromList(_bytes);
}

class _WebpFrameControl {
  const _WebpFrameControl({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.durationMs,
    required this.flags,
  });

  final int x;
  final int y;
  final int width;
  final int height;
  final int durationMs;
  final int flags;

  @override
  bool operator ==(Object other) {
    return other is _WebpFrameControl &&
        other.x == x &&
        other.y == y &&
        other.width == width &&
        other.height == height &&
        other.durationMs == durationMs &&
        other.flags == flags;
  }

  @override
  int get hashCode => Object.hash(x, y, width, height, durationMs, flags);

  @override
  String toString() {
    return '_WebpFrameControl(x: $x, y: $y, width: $width, '
        'height: $height, durationMs: $durationMs, flags: $flags)';
  }
}

class _PngFrameControl {
  const _PngFrameControl({
    required this.width,
    required this.height,
    required this.x,
    required this.y,
    this.delayNumerator = 0,
    this.delayDenominator = 0,
    this.disposeOp = 1,
    this.blendOp = 0,
  });

  final int width;
  final int height;
  final int x;
  final int y;
  final int delayNumerator;
  final int delayDenominator;
  final int disposeOp;
  final int blendOp;

  @override
  bool operator ==(Object other) {
    return other is _PngFrameControl &&
        other.width == width &&
        other.height == height &&
        other.x == x &&
        other.y == y;
  }

  @override
  int get hashCode => Object.hash(width, height, x, y);

  @override
  String toString() {
    return '_PngFrameControl(width: $width, height: $height, x: $x, y: $y, '
        'delay: $delayNumerator/$delayDenominator, dispose: $disposeOp, '
        'blend: $blendOp)';
  }
}

class _ApngFramePart {
  const _ApngFramePart({required this.control, required this.idatPayloads});

  final _PngFrameControl control;
  final List<Uint8List> idatPayloads;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 20,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump();
    if (condition()) {
      return;
    }
  }
  final visibleText = tester
      .widgetList<Text>(find.byType(Text))
      .map((text) {
        final data = text.data;
        if (data != null) {
          return data;
        }
        return text.textSpan?.toPlainText() ?? '<rich text>';
      })
      .join(', ');
  fail('Timed out waiting for widget test condition. Text: $visibleText');
}
