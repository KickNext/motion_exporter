import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:motion_exporter/motion_exporter.dart';
import 'package:motion_exporter_example/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'benchmarks deterministic export encoders',
    () async {
      final clip = await renderTransparentDemoClip();
      final cases = <_BenchmarkCase>[
        _BenchmarkCase(
          name: 'WebP default changed rect',
          encoder: const MotionClipEncoder(useBackgroundIsolate: false),
        ),
        _BenchmarkCase(
          name: 'WebP transparent trim',
          encoder: const MotionClipEncoder(
            useBackgroundIsolate: false,
            webpOptions: WebpAnimationOptions(),
          ),
        ),
        _BenchmarkCase(
          name: 'WebP full canvas',
          encoder: const MotionClipEncoder(
            useBackgroundIsolate: false,
            webpOptions: WebpAnimationOptions(trimTransparentFrames: false),
          ),
        ),
        _BenchmarkCase(
          name: 'APNG transparent trim',
          encoder: const MotionClipEncoder(
            format: MotionExportFormat.apng,
            useBackgroundIsolate: false,
          ),
        ),
        _BenchmarkCase(
          name: 'APNG full canvas',
          encoder: const MotionClipEncoder(
            format: MotionExportFormat.apng,
            useBackgroundIsolate: false,
            apngOptions: ApngAnimationOptions(trimTransparentFrames: false),
          ),
        ),
      ];

      final rows = <_BenchmarkRow>[];
      for (final benchmarkCase in cases) {
        final totalStopwatch = Stopwatch()..start();
        final result = await benchmarkCase.encoder.encode(clip);
        totalStopwatch.stop();
        final validation = result.validation ?? result.validateEncodedFile();
        expect(validation.isValid, isTrue);
        rows.add(
          _BenchmarkRow(
            name: benchmarkCase.name,
            format: result.format.label,
            frames: result.frameCount,
            bytes: result.byteLength,
            encodeDuration: result.encodeDuration,
            totalDuration: totalStopwatch.elapsed,
          ),
        );
      }

      final golden = _benchmarkMotionGolden(clip);

      // Print a compact table for local comparison. This file is intentionally
      // under tool/ so it does not run as part of the normal example test suite.
      // Run with: flutter test tool/benchmark_exports.dart --reporter expanded
      // ignore: avoid_print
      print(
        _formatBenchmarkRows(
          rows,
          golden: golden,
          rawMebibytes: clip.rawMebibytes,
        ),
      );
      final jsonPath = Platform.environment['MOTION_EXPORTER_BENCHMARK_JSON'];
      if (jsonPath != null && jsonPath.isNotEmpty) {
        final file = File(jsonPath);
        await file.parent.create(recursive: true);
        await file.writeAsString(
          const JsonEncoder.withIndent(
            '  ',
          ).convert(_benchmarkJson(rows, golden: golden, clip: clip)),
          flush: true,
        );
        // ignore: avoid_print
        print('benchmark JSON: ${file.path}');
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

class _BenchmarkCase {
  const _BenchmarkCase({required this.name, required this.encoder});

  final String name;
  final MotionClipEncoder encoder;
}

class _BenchmarkRow {
  const _BenchmarkRow({
    required this.name,
    required this.format,
    required this.frames,
    required this.bytes,
    required this.encodeDuration,
    required this.totalDuration,
  });

  final String name;
  final String format;
  final int frames;
  final int bytes;
  final Duration encodeDuration;
  final Duration totalDuration;
}

class _GoldenBenchmarkRow {
  const _GoldenBenchmarkRow({
    required this.frames,
    required this.bytes,
    required this.encodeDuration,
    required this.decodeDuration,
    required this.compareDuration,
  });

  final int frames;
  final int bytes;
  final Duration encodeDuration;
  final Duration decodeDuration;
  final Duration compareDuration;
}

_GoldenBenchmarkRow _benchmarkMotionGolden(MotionClip clip) {
  const codec = MotionClipGoldenCodec();

  final encodeStopwatch = Stopwatch()..start();
  final bytes = codec.encode(clip);
  encodeStopwatch.stop();

  final decodeStopwatch = Stopwatch()..start();
  final decoded = codec.decode(bytes);
  decodeStopwatch.stop();

  final compareStopwatch = Stopwatch()..start();
  final comparison = MotionClipComparison.compare(
    actual: decoded,
    expected: clip,
  );
  compareStopwatch.stop();
  expect(comparison.isMatch, isTrue);

  return _GoldenBenchmarkRow(
    frames: decoded.frameCount,
    bytes: bytes.lengthInBytes,
    encodeDuration: encodeStopwatch.elapsed,
    decodeDuration: decodeStopwatch.elapsed,
    compareDuration: compareStopwatch.elapsed,
  );
}

String _formatBenchmarkRows(
  List<_BenchmarkRow> rows, {
  required _GoldenBenchmarkRow golden,
  required double rawMebibytes,
}) {
  final buffer = StringBuffer()
    ..writeln('')
    ..writeln('motion_exporter deterministic export benchmark')
    ..writeln('raw RGBA retained: ${rawMebibytes.toStringAsFixed(1)} MiB')
    ..writeln('')
    ..writeln(
      '${'case'.padRight(24)} '
      '${'fmt'.padRight(5)} '
      '${'frames'.padLeft(6)} '
      '${'size'.padLeft(10)} '
      '${'encode'.padLeft(10)} '
      '${'total'.padLeft(10)}',
    );
  for (final row in rows) {
    buffer.writeln(
      '${row.name.padRight(24)} '
      '${row.format.padRight(5)} '
      '${row.frames.toString().padLeft(6)} '
      '${_formatKib(row.bytes).padLeft(10)} '
      '${_formatMs(row.encodeDuration).padLeft(10)} '
      '${_formatMs(row.totalDuration).padLeft(10)}',
    );
  }
  buffer
    ..writeln('')
    ..writeln(
      'raw .motion golden: ${golden.frames} frames, '
      '${_formatKib(golden.bytes)}, '
      '${_formatMs(golden.encodeDuration)} encode, '
      '${_formatMs(golden.decodeDuration)} decode, '
      '${_formatMs(golden.compareDuration)} compare',
    );
  return buffer.toString();
}

String _formatKib(int bytes) {
  return '${(bytes / 1024).toStringAsFixed(1)} KiB';
}

String _formatMs(Duration duration) {
  return '${(duration.inMicroseconds / 1000).toStringAsFixed(1)} ms';
}

Map<String, Object?> _benchmarkJson(
  List<_BenchmarkRow> rows, {
  required _GoldenBenchmarkRow golden,
  required MotionClip clip,
}) {
  final byName = {for (final row in rows) row.name: row};
  final webpDefault = byName['WebP default changed rect']!;
  final webpFullCanvas = byName['WebP full canvas']!;
  final apngTransparent = byName['APNG transparent trim']!;

  return <String, Object?>{
    'schemaVersion': 4,
    'environment': <String, Object?>{
      'dartVersion': Platform.version,
      'operatingSystem': Platform.operatingSystem,
      'operatingSystemVersion': Platform.operatingSystemVersion,
      'numberOfProcessors': Platform.numberOfProcessors,
    },
    'scene': <String, Object?>{
      'width': clip.width,
      'height': clip.height,
      'frames': clip.frameCount,
      'durationMicros': clip.duration.inMicroseconds,
      'rawBytes': clip.rawBytes,
      'rawMebibytes': clip.rawMebibytes,
    },
    'golden': golden.toJson(),
    'results': rows.map((row) => row.toJson()).toList(growable: false),
    'ratios': <String, Object?>{
      'motionEncodeToWebpDefault':
          golden.encodeDuration.inMicroseconds /
          webpDefault.encodeDuration.inMicroseconds,
      'motionCompareToWebpDefault':
          golden.compareDuration.inMicroseconds /
          webpDefault.encodeDuration.inMicroseconds,
      'apngTransparentEncodeToWebpDefault':
          apngTransparent.encodeDuration.inMicroseconds /
          webpDefault.encodeDuration.inMicroseconds,
      'webpChangedRectEncodeToFullCanvas':
          webpDefault.encodeDuration.inMicroseconds /
          webpFullCanvas.encodeDuration.inMicroseconds,
    },
  };
}

extension on _BenchmarkRow {
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'format': format,
      'frames': frames,
      'bytes': bytes,
      'kibibytes': bytes / 1024,
      'encodeMicros': encodeDuration.inMicroseconds,
      'totalMicros': totalDuration.inMicroseconds,
    };
  }
}

extension on _GoldenBenchmarkRow {
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'format': '.motion',
      'frames': frames,
      'bytes': bytes,
      'kibibytes': bytes / 1024,
      'encodeMicros': encodeDuration.inMicroseconds,
      'decodeMicros': decodeDuration.inMicroseconds,
      'compareMicros': compareDuration.inMicroseconds,
    };
  }
}
