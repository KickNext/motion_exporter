part of '../motion_exporter.dart';

/// Random-access byte target used by [WebpAnimationStreamEncoder].
///
/// Animated WebP is a RIFF container, so the final file size must be patched
/// into the header after the last frame is written. Implementations can back
/// this with a file, memory buffer, or any other seekable byte store.
abstract interface class WebpAnimationStreamSink {
  /// Current write position in bytes from the start of the WebP file.
  int get position;

  /// Appends [bytes] at the current write position.
  void writeBytes(Uint8List bytes);

  /// Overwrites a little-endian uint32 at [offset] without changing
  /// [position].
  void patchUint32(int offset, int value);
}

/// Streams raw RGBA frames into an animated WebP container.
///
/// Unlike [WebpAnimationEncoder], this encoder does not require a completed
/// [MotionClip] or a `List<MotionFrame>`. Feed frames as soon as they are
/// captured, then call [close] to patch the RIFF size. With changed-frame
/// trimming enabled it retains only one previous full frame for diff bounds.
class WebpAnimationStreamEncoder {
  /// Creates an animated WebP stream encoder and writes the file header.
  WebpAnimationStreamEncoder({
    required this.sink,
    required this.width,
    required this.height,
    this.options = const WebpAnimationOptions(trimChangedFrames: true),
  }) {
    _checkVp8lSize(width, height);
    _writeHeader();
  }

  /// Destination for encoded WebP bytes.
  final WebpAnimationStreamSink sink;

  /// Encoded canvas width in physical pixels.
  final int width;

  /// Encoded canvas height in physical pixels.
  final int height;

  /// Animation encoding options.
  final WebpAnimationOptions options;

  final _WebpFrameDurationAccumulator _durationAccumulator =
      _WebpFrameDurationAccumulator();
  int _frameCount = 0;
  int _riffSizeOffset = -1;
  bool _closed = false;
  Uint8List? _previousChangedTrimFrameBytes;

  /// Number of frames written so far.
  int get frameCount => _frameCount;

  /// Total input duration across frames written so far.
  Duration get duration => _durationAccumulator.duration;

  /// Current encoded byte length written to [WebpAnimationStreamSink].
  int get byteLength => sink.position;

  /// Whether [close] has already been called successfully.
  bool get isClosed => _closed;

  /// Encodes and appends one frame.
  void addFrame(MotionFrame frame) {
    _checkOpen();
    _checkFrameSize(frame);

    final durationMs = _durationAccumulator.next(frame.duration);
    final trimChangedFrame = options.trimChangedFrames && _frameCount > 0;
    final rect = options.trimChangedFrames
        ? trimChangedFrame
              ? _webpChangedTrimRectBytes(
                  frame,
                  _previousChangedTrimFrameBytes!,
                )
              : _FrameRect.full(frame.width, frame.height)
        : options.trimTransparentFrames
        ? _webpTransparentTrimRect(frame)
        : _FrameRect.full(frame.width, frame.height);
    final frameChunk = _frameImageChunk(frame, rect);

    _writeAnmf(
      rect: rect,
      durationMs: durationMs,
      frameData: frameChunk,
      blend: options.trimChangedFrames
          ? WebpFrameBlend.replace
          : options.frameBlend,
      dispose: options.trimChangedFrames
          ? WebpFrameDispose.none
          : options.trimTransparentFrames
          ? WebpFrameDispose.background
          : options.frameDispose,
    );

    _frameCount++;
    if (options.trimChangedFrames) {
      _previousChangedTrimFrameBytes =
          options.previousFrameRetentionPolicy ==
              WebpPreviousFrameRetentionPolicy.reference
          ? frame.rgbaBytes
          : Uint8List.fromList(frame.rgbaBytes);
    }
  }

  /// Finishes the WebP file by patching the RIFF size.
  void close() {
    _checkOpen();
    if (_frameCount == 0) {
      throw StateError('At least one frame must be written before close().');
    }

    final riffSize = sink.position - 8;
    if (riffSize > 0xffffffff) {
      throw StateError('Encoded WebP is too large for a RIFF container.');
    }
    sink.patchUint32(_riffSizeOffset, riffSize);
    _closed = true;
  }

  void _writeHeader() {
    _writeAscii('RIFF');
    _riffSizeOffset = sink.position;
    _writeUint32(0);
    _writeAscii('WEBP');
    _writeChunk('VP8X', _vp8xPayload(width, height));
    _writeChunk(
      'ANIM',
      _animPayload(_colorToArgb32(options.backgroundColor), options.loopCount),
    );
  }

  void _writeAnmf({
    required _FrameRect rect,
    required int durationMs,
    required Uint8List frameData,
    required WebpFrameBlend blend,
    required WebpFrameDispose dispose,
  }) {
    final payloadSize = 16 + frameData.lengthInBytes;
    sink.writeBytes(
      _webpAnmfHeader(
        rect: rect,
        payloadSize: payloadSize,
        durationMs: durationMs,
        blend: blend,
        dispose: dispose,
      ),
    );
    sink.writeBytes(frameData);
    _writePaddingIfOdd(payloadSize);
  }

  void _writeChunk(String tag, Uint8List payload) {
    _writeAscii(tag);
    _writeUint32(payload.lengthInBytes);
    sink.writeBytes(payload);
    _writePaddingIfOdd(payload.lengthInBytes);
  }

  void _writeAscii(String value) {
    if (value.length != 4) {
      throw ArgumentError.value(value, 'value', 'Expected a 4-byte tag.');
    }
    sink.writeBytes(Uint8List.fromList(value.codeUnits));
  }

  void _writeByte(int value) {
    sink.writeBytes(Uint8List(1)..[0] = value & 0xff);
  }

  void _writeUint32(int value) {
    if (value < 0 || value > 0xffffffff) {
      throw RangeError.range(value, 0, 0xffffffff);
    }
    sink.writeBytes(_webpUint32Le(value));
  }

  void _writePaddingIfOdd(int length) {
    if (length.isOdd) {
      _writeByte(0);
    }
  }

  void _checkOpen() {
    if (_closed) {
      throw StateError('Cannot write to a closed WebP animation stream.');
    }
  }

  void _checkFrameSize(MotionFrame frame) {
    if (frame.width != width || frame.height != height) {
      throw ArgumentError.value(
        '${frame.width} x ${frame.height}',
        'frame',
        'Frame dimensions must be $width x $height.',
      );
    }
    _checkVp8lSize(frame.width, frame.height);
  }
}

class _WebpFrameDurationAccumulator {
  int _elapsedMicros = 0;
  int _previousRoundedMs = 0;

  Duration get duration => Duration(microseconds: _elapsedMicros);

  int next(Duration duration) {
    final nextElapsedMicros = _elapsedMicros + duration.inMicroseconds;
    final roundedElapsedMs = math.max(
      _previousRoundedMs + 1,
      (nextElapsedMicros + 500) ~/ 1000,
    );
    final durationMs = roundedElapsedMs - _previousRoundedMs;
    if (durationMs > 0xffffff) {
      throw ArgumentError.value(
        duration,
        'duration',
        'WebP frame duration must fit into 24 bits of milliseconds.',
      );
    }
    _elapsedMicros = nextElapsedMicros;
    _previousRoundedMs = roundedElapsedMs;
    return durationMs;
  }
}

Uint8List _webpUint32Le(int value) {
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

Uint8List _webpAnmfHeader({
  required _FrameRect rect,
  required int payloadSize,
  required int durationMs,
  required WebpFrameBlend blend,
  required WebpFrameDispose dispose,
}) {
  var flags = 0;
  if (dispose == WebpFrameDispose.background) {
    flags |= 0x01;
  }
  if (blend == WebpFrameBlend.replace) {
    flags |= 0x02;
  }

  final header = Uint8List(24);
  header.setAll(0, 'ANMF'.codeUnits);
  _writeUint32LeAt(header, 4, payloadSize);
  _writeUint24LeAt(header, 8, rect.x ~/ 2);
  _writeUint24LeAt(header, 11, rect.y ~/ 2);
  _writeUint24LeAt(header, 14, rect.width - 1);
  _writeUint24LeAt(header, 17, rect.height - 1);
  _writeUint24LeAt(header, 20, durationMs);
  header[23] = flags;
  return header;
}

void _writeUint24LeAt(Uint8List target, int offset, int value) {
  if (value < 0 || value > 0xffffff) {
    throw RangeError.range(value, 0, 0xffffff);
  }
  target[offset] = value & 0xff;
  target[offset + 1] = (value >> 8) & 0xff;
  target[offset + 2] = (value >> 16) & 0xff;
}

void _writeUint32LeAt(Uint8List target, int offset, int value) {
  if (value < 0 || value > 0xffffffff) {
    throw RangeError.range(value, 0, 0xffffffff);
  }
  target[offset] = value & 0xff;
  target[offset + 1] = (value >> 8) & 0xff;
  target[offset + 2] = (value >> 16) & 0xff;
  target[offset + 3] = (value >> 24) & 0xff;
}
