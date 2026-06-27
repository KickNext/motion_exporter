/// Native filesystem helpers for streamed WebP exports and raw motion goldens.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Size;

import 'motion_exporter.dart';

/// Streams animated WebP frames directly into a native filesystem file.
///
/// Import `package:motion_exporter/motion_exporter_io.dart` only on platforms
/// that support `dart:io`.
class WebpAnimationFileWriter {
  WebpAnimationFileWriter._(this.file, this._sink, this._encoder);

  /// Opens [file], truncates existing contents, and writes the WebP header.
  static Future<WebpAnimationFileWriter> open({
    required File file,
    required int width,
    required int height,
    WebpAnimationOptions options = const WebpAnimationOptions(
      trimChangedFrames: true,
    ),
  }) async {
    _checkWebpFileCanvasSize(width, height);
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final randomAccessFile = await file.open(mode: FileMode.write);
    await randomAccessFile.truncate(0);
    final sink = _RandomAccessFileWebpSink(randomAccessFile);
    late final WebpAnimationStreamEncoder encoder;
    try {
      encoder = WebpAnimationStreamEncoder(
        sink: sink,
        width: width,
        height: height,
        options: options,
      );
    } catch (_) {
      await sink.close();
      rethrow;
    }
    return WebpAnimationFileWriter._(file, sink, encoder);
  }

  /// Destination WebP file.
  final File file;
  final _RandomAccessFileWebpSink _sink;
  final WebpAnimationStreamEncoder _encoder;

  /// Number of frames written so far.
  int get frameCount => _encoder.frameCount;

  /// Encoded canvas width in physical pixels.
  int get width => _encoder.width;

  /// Encoded canvas height in physical pixels.
  int get height => _encoder.height;

  /// Total input duration across frames written so far.
  Duration get duration => _encoder.duration;

  /// Current encoded byte length.
  int get byteLength => _encoder.byteLength;

  /// Encodes and appends one frame.
  void addFrame(MotionFrame frame) {
    _encoder.addFrame(frame);
  }

  /// Finishes the WebP file and closes the underlying file handle.
  Future<WebpAnimationFileRecording> close() async {
    try {
      _encoder.close();
    } finally {
      await _sink.close();
    }
    return WebpAnimationFileRecording(
      file: file,
      frameCount: _encoder.frameCount,
      width: _encoder.width,
      height: _encoder.height,
      duration: _encoder.duration,
      byteLength: _encoder.byteLength,
    );
  }
}

/// Metadata for a completed [WebpAnimationFileWriter] export.
class WebpAnimationFileRecording {
  /// Creates file-backed animated WebP metadata.
  const WebpAnimationFileRecording({
    required this.file,
    required this.frameCount,
    required this.width,
    required this.height,
    required this.duration,
    required this.byteLength,
  });

  /// Written WebP file.
  final File file;

  /// Number of encoded frames.
  final int frameCount;

  /// Encoded canvas width in physical pixels.
  final int width;

  /// Encoded canvas height in physical pixels.
  final int height;

  /// Total playback duration represented by input frames.
  final Duration duration;

  /// Encoded byte length.
  final int byteLength;

  /// Reads and inspects the finished WebP container.
  MotionExportInspection inspect() {
    return MotionExportInspection.inspect(
      format: MotionExportFormat.webp,
      bytes: file.readAsBytesSync(),
    );
  }

  /// Validates the written file against this recording's metadata.
  MotionExportValidation validateEncodedFile({
    Duration durationTolerance = const Duration(milliseconds: 1),
    bool requireAlpha = true,
  }) {
    return MotionExportValidation.forMetadata(
      format: MotionExportFormat.webp,
      width: width,
      height: height,
      frameCount: frameCount,
      duration: duration,
      inspection: inspect(),
      durationTolerance: durationTolerance,
      requireAlpha: requireAlpha,
    );
  }
}

/// Writes [clip] as an animated WebP file without retaining encoded bytes.
Future<WebpAnimationFileRecording> writeWebpAnimationFile({
  required File file,
  required MotionClip clip,
  WebpAnimationOptions options = const WebpAnimationOptions(
    trimChangedFrames: true,
  ),
}) async {
  final writer = await WebpAnimationFileWriter.open(
    file: file,
    width: clip.width,
    height: clip.height,
    options: options,
  );
  try {
    for (final frame in clip.frames) {
      writer.addFrame(frame);
    }
    return await writer.close();
  } catch (_) {
    await writer._sink.close();
    rethrow;
  }
}

/// Reads a raw `.motion` animation golden from [file].
Future<MotionClip> readMotionClipGolden(
  File file, {
  MotionClipGoldenCodec codec = const MotionClipGoldenCodec(),
}) async {
  return codec.decode(await file.readAsBytes());
}

/// Writes [clip] as a raw `.motion` animation golden.
Future<void> writeMotionClipGolden(
  File file,
  MotionClip clip, {
  MotionClipGoldenCodec codec = const MotionClipGoldenCodec(),
}) async {
  final parent = file.parent;
  if (!await parent.exists()) {
    await parent.create(recursive: true);
  }
  await file.writeAsBytes(codec.encode(clip), flush: true);
}

/// Compares [actual] with a raw `.motion` golden file.
Future<MotionClipComparison> compareMotionClipGolden({
  required MotionClip actual,
  required File file,
  MotionClipGoldenCodec codec = const MotionClipGoldenCodec(),
  int channelTolerance = 0,
  double maxMismatchedPixelRatio = 0,
  Duration durationTolerance = Duration.zero,
}) async {
  final expected = await readMotionClipGolden(file, codec: codec);
  return MotionClipComparison.compare(
    actual: actual,
    expected: expected,
    channelTolerance: channelTolerance,
    maxMismatchedPixelRatio: maxMismatchedPixelRatio,
    durationTolerance: durationTolerance,
  );
}

/// Updates or verifies a raw `.motion` animation golden.
///
/// Set [update] from an explicit test flag, for example
/// `Platform.environment['UPDATE_GOLDENS'] == '1'`.
Future<void> expectMotionClipGolden({
  required MotionClip actual,
  required File file,
  bool update = false,
  MotionClipGoldenCodec codec = const MotionClipGoldenCodec(),
  int channelTolerance = 0,
  double maxMismatchedPixelRatio = 0,
  Duration durationTolerance = Duration.zero,
  String? description,
}) async {
  if (update) {
    await writeMotionClipGolden(file, actual, codec: codec);
    return;
  }
  if (!await file.exists()) {
    throw StateError(
      'Motion golden does not exist: ${file.path}. '
      'Run the test with update enabled to create it.',
    );
  }
  final comparison = await compareMotionClipGolden(
    actual: actual,
    file: file,
    codec: codec,
    channelTolerance: channelTolerance,
    maxMismatchedPixelRatio: maxMismatchedPixelRatio,
    durationTolerance: durationTolerance,
  );
  comparison.throwIfMismatch(description: description ?? file.path);
}

/// Renders deterministic canvas motion and verifies it against a `.motion`
/// golden file.
///
/// Returns the captured clip so the same frames can be exported as WebP/APNG
/// debug artifacts after the raw golden assertion passes.
Future<MotionClip> expectMotionCanvasGolden({
  required File file,
  required Size size,
  required Duration duration,
  required int framesPerSecond,
  required MotionCanvasPainter paint,
  double pixelRatio = 1,
  MotionClipTransform? clipTransform,
  bool update = false,
  MotionClipGoldenCodec codec = const MotionClipGoldenCodec(),
  int channelTolerance = 0,
  double maxMismatchedPixelRatio = 0,
  Duration durationTolerance = Duration.zero,
  String? description,
}) async {
  final clip = await const MotionExportEngine().recordCanvasClip(
    size: size,
    duration: duration,
    framesPerSecond: framesPerSecond,
    pixelRatio: pixelRatio,
    paint: paint,
    clipTransform: clipTransform,
  );
  await expectMotionClipGolden(
    actual: clip,
    file: file,
    update: update,
    codec: codec,
    channelTolerance: channelTolerance,
    maxMismatchedPixelRatio: maxMismatchedPixelRatio,
    durationTolerance: durationTolerance,
    description: description,
  );
  return clip;
}

class _RandomAccessFileWebpSink implements WebpAnimationStreamSink {
  _RandomAccessFileWebpSink(this._file);

  final RandomAccessFile _file;
  int _position = 0;
  bool _closed = false;

  @override
  int get position => _position;

  @override
  void writeBytes(Uint8List bytes) {
    _checkOpen();
    _file.writeFromSync(bytes);
    _position += bytes.lengthInBytes;
  }

  @override
  void patchUint32(int offset, int value) {
    _checkOpen();
    if (offset < 0 || offset + 4 > _position) {
      throw RangeError.range(offset, 0, _position - 4, 'offset');
    }
    final currentPosition = _position;
    _file.setPositionSync(offset);
    _file.writeFromSync(_uint32Le(value));
    _file.setPositionSync(currentPosition);
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _file.close();
  }

  void _checkOpen() {
    if (_closed) {
      throw StateError('Cannot write to a closed WebP file sink.');
    }
  }
}

Uint8List _uint32Le(int value) {
  if (value < 0 || value > 0xffffffff) {
    throw RangeError.range(value, 0, 0xffffffff);
  }
  return Uint8List.fromList(<int>[
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
    (value >> 24) & 0xff,
  ]);
}

void _checkWebpFileCanvasSize(int width, int height) {
  if (width <= 0 || height <= 0 || width > 16384 || height > 16384) {
    throw ArgumentError.value(
      '$width x $height',
      'size',
      'VP8L lossless WebP frames must be between 1 and 16384 pixels per side.',
    );
  }
}
