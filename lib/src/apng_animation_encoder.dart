part of '../motion_exporter.dart';

/// Encodes raw RGBA frames into an animated PNG file.
class ApngAnimationEncoder {
  /// Creates an animated PNG encoder.
  const ApngAnimationEncoder([this.options = const ApngAnimationOptions()]);

  /// Encoding options.
  final ApngAnimationOptions options;

  /// Encodes [frames] into APNG bytes.
  Uint8List encode(List<MotionFrame> frames) {
    return _encodeApngAnimation(options._toJob(frames));
  }

  /// Encodes a captured [clip] into APNG bytes.
  Uint8List encodeClip(MotionClip clip) {
    return encode(clip.frames);
  }
}

/// Options for [ApngAnimationEncoder].
class ApngAnimationOptions {
  /// Creates animated PNG options.
  const ApngAnimationOptions({
    this.loopCount = 0,
    this.compressionLevel = 1,
    this.trimTransparentFrames = true,
  }) : assert(loopCount >= 0),
       assert(compressionLevel >= 0),
       assert(compressionLevel <= 9);

  /// Animation loop count. `0` means infinite looping.
  final int loopCount;

  /// zlib compression level from `0` to `9`.
  ///
  /// Lower values export faster. The default favors developer export speed.
  final int compressionLevel;

  /// Store frames after the first one as the smallest rectangle containing
  /// non-transparent pixels.
  ///
  /// This keeps full-snapshot Flutter captures visually correct by using APNG
  /// source blending and background disposal, while avoiding full-canvas frame
  /// payloads when most pixels are transparent.
  final bool trimTransparentFrames;

  _ApngEncodeJob _toJob(List<MotionFrame> frames) {
    return _ApngEncodeJob(
      frames: frames,
      loopCount: loopCount,
      compressionLevel: compressionLevel,
      trimTransparentFrames: trimTransparentFrames,
    );
  }
}

class _ApngEncodeJob {
  const _ApngEncodeJob({
    required this.frames,
    required this.loopCount,
    required this.compressionLevel,
    required this.trimTransparentFrames,
  });

  final List<MotionFrame> frames;
  final int loopCount;
  final int compressionLevel;
  final bool trimTransparentFrames;
}

Uint8List _encodeApngAnimation(_ApngEncodeJob job) {
  final frames = job.frames;
  if (frames.isEmpty) {
    throw ArgumentError.value(frames, 'frames', 'At least one frame required.');
  }

  final firstFrame = frames.first;
  for (var i = 1; i < frames.length; i++) {
    final frame = frames[i];
    if (frame.width != firstFrame.width || frame.height != firstFrame.height) {
      throw ArgumentError.value(
        '${frame.width} x ${frame.height}',
        'frames',
        'All frames must use the same dimensions as the first frame.',
      );
    }
  }

  return _ApngMuxer(
    frames: frames,
    loopCount: job.loopCount,
    compressionLevel: job.compressionLevel,
    trimTransparentFrames: job.trimTransparentFrames,
  ).encode();
}

img.Image _pngImageFromFrame(MotionFrame frame) {
  return img.Image.fromBytes(
    width: frame.width,
    height: frame.height,
    bytes: frame.rgbaBytes.buffer,
    bytesOffset: frame.rgbaBytes.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}

_FrameDelay _frameDelay(Duration duration) {
  final micros = math.max(1, duration.inMicroseconds);
  final exactGcd = _gcd(micros, Duration.microsecondsPerSecond);
  final exactNumerator = micros ~/ exactGcd;
  final exactDenominator = Duration.microsecondsPerSecond ~/ exactGcd;
  final targetSeconds = micros / Duration.microsecondsPerSecond;
  _FrameDelay? best;
  var bestError = double.infinity;

  void addCandidate(int numerator, int denominator) {
    if (numerator <= 0 || denominator <= 0) {
      return;
    }

    final gcd = _gcd(numerator, denominator);
    final reducedNumerator = numerator ~/ gcd;
    final reducedDenominator = denominator ~/ gcd;
    if (reducedNumerator > 0xffff || reducedDenominator > 0xffff) {
      return;
    }

    final error = (reducedNumerator / reducedDenominator - targetSeconds).abs();
    if (error < bestError) {
      best = _FrameDelay(reducedNumerator, reducedDenominator);
      bestError = error;
    }
  }

  addCandidate(exactNumerator, exactDenominator);
  addCandidate((micros / 1000).round(), 1000);

  if (micros < Duration.microsecondsPerSecond) {
    addCandidate(1, (Duration.microsecondsPerSecond / micros).round());
  }

  addCandidate((targetSeconds * 0xffff).round(), 0xffff);
  addCandidate(targetSeconds.round(), 1);

  return best ?? const _FrameDelay(0xffff, 1);
}

int _gcd(int a, int b) {
  var left = a.abs();
  var right = b.abs();
  while (right != 0) {
    final next = left % right;
    left = right;
    right = next;
  }
  return left == 0 ? 1 : left;
}

class _FrameDelay {
  const _FrameDelay(this.numerator, this.denominator);

  final int numerator;
  final int denominator;
}

class _ApngMuxer {
  _ApngMuxer({
    required this.frames,
    required this.loopCount,
    required this.compressionLevel,
    required this.trimTransparentFrames,
  });

  final List<MotionFrame> frames;
  final int loopCount;
  final int compressionLevel;
  final bool trimTransparentFrames;

  Uint8List encode() {
    final firstFrame = frames.first;
    final out = _PngBytesWriter()
      ..writeBytes(_pngSignature)
      ..writeChunk('IHDR', _ihdrPayload(firstFrame.width, firstFrame.height))
      ..writeChunk('acTL', _actlPayload(frames.length, loopCount));

    var sequenceNumber = 0;
    for (var i = 0; i < frames.length; i++) {
      final frame = frames[i];
      final rect = i == 0 || !trimTransparentFrames
          ? _FrameRect.full(frame.width, frame.height)
          : _transparentTrimRect(frame);
      final image = _imageForRect(frame, rect);
      final png = img.PngEncoder(
        filter: img.PngFilter.none,
        level: compressionLevel,
      ).encode(image);
      final idatPayloads = _extractIdatPayloads(png);

      out.writeChunk(
        'fcTL',
        _fctlPayload(
          sequenceNumber: sequenceNumber++,
          rect: rect,
          duration: frame.duration,
        ),
      );

      if (i == 0) {
        for (final payload in idatPayloads) {
          out.writeChunk('IDAT', payload);
        }
      } else {
        for (final payload in idatPayloads) {
          out.writeChunk('fdAT', _prefixedFrameData(sequenceNumber++, payload));
        }
      }
    }

    out.writeChunk('IEND', Uint8List(0));
    return out.takeBytes();
  }
}

const _pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

Uint8List _ihdrPayload(int width, int height) {
  return (_PngBytesWriter()
        ..writeUint32(width)
        ..writeUint32(height)
        ..writeByte(8) // Bit depth.
        ..writeByte(6) // RGBA.
        ..writeByte(0) // Deflate.
        ..writeByte(0) // Adaptive filtering.
        ..writeByte(0)) // No interlace.
      .takeBytes();
}

Uint8List _actlPayload(int frameCount, int loopCount) {
  return (_PngBytesWriter()
        ..writeUint32(frameCount)
        ..writeUint32(loopCount))
      .takeBytes();
}

Uint8List _fctlPayload({
  required int sequenceNumber,
  required _FrameRect rect,
  required Duration duration,
}) {
  final delay = _frameDelay(duration);
  return (_PngBytesWriter()
        ..writeUint32(sequenceNumber)
        ..writeUint32(rect.width)
        ..writeUint32(rect.height)
        ..writeUint32(rect.x)
        ..writeUint32(rect.y)
        ..writeUint16(delay.numerator)
        ..writeUint16(delay.denominator)
        ..writeByte(1) // APNG_DISPOSE_OP_BACKGROUND.
        ..writeByte(0)) // APNG_BLEND_OP_SOURCE.
      .takeBytes();
}

Uint8List _prefixedFrameData(int sequenceNumber, Uint8List payload) {
  return (_PngBytesWriter()
        ..writeUint32(sequenceNumber)
        ..writeBytes(payload))
      .takeBytes();
}

List<Uint8List> _extractIdatPayloads(Uint8List png) {
  final payloads = <Uint8List>[];
  var offset = _pngSignature.length;
  while (offset + 8 <= png.length) {
    final size = _readPngUint32(png, offset);
    final typeOffset = offset + 4;
    final payloadOffset = offset + 8;
    final payloadEnd = payloadOffset + size;
    final chunkEnd = payloadEnd + 4;
    if (chunkEnd > png.length) {
      throw StateError('PNG encoder returned a truncated chunk.');
    }
    if (_matchesPngChunkType(png, typeOffset, _pngChunkIdat)) {
      payloads.add(Uint8List.sublistView(png, payloadOffset, payloadEnd));
    }
    if (_matchesPngChunkType(png, typeOffset, _pngChunkIend)) {
      break;
    }
    offset = chunkEnd;
  }
  if (payloads.isEmpty) {
    throw StateError('PNG encoder returned no IDAT chunks.');
  }
  return payloads;
}

int _readPngUint32(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

_FrameRect _transparentTrimRect(MotionFrame frame) {
  var minX = frame.width;
  var minY = frame.height;
  var maxX = -1;
  var maxY = -1;
  final bytes = frame.rgbaBytes;

  final canUsePixelView =
      Endian.host == Endian.little && bytes.offsetInBytes % 4 == 0;
  if (canUsePixelView) {
    final pixels = Uint32List.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 4,
    );
    var pixelOffset = 0;
    for (var y = 0; y < frame.height; y++) {
      for (var x = 0; x < frame.width; x++) {
        if (pixels[pixelOffset] & 0xff000000 != 0) {
          if (x < minX) {
            minX = x;
          }
          if (y < minY) {
            minY = y;
          }
          if (x > maxX) {
            maxX = x;
          }
          if (y > maxY) {
            maxY = y;
          }
        }
        pixelOffset++;
      }
    }
  } else {
    for (var y = 0; y < frame.height; y++) {
      var offset = y * frame.width * 4 + 3;
      for (var x = 0; x < frame.width; x++) {
        if (bytes[offset] != 0) {
          if (x < minX) {
            minX = x;
          }
          if (y < minY) {
            minY = y;
          }
          if (x > maxX) {
            maxX = x;
          }
          if (y > maxY) {
            maxY = y;
          }
        }
        offset += 4;
      }
    }
  }

  if (maxX < minX || maxY < minY) {
    return const _FrameRect(x: 0, y: 0, width: 1, height: 1);
  }
  return _FrameRect(
    x: minX,
    y: minY,
    width: maxX - minX + 1,
    height: maxY - minY + 1,
  );
}

img.Image _imageForRect(MotionFrame frame, _FrameRect rect) {
  if (rect.x == 0 &&
      rect.y == 0 &&
      rect.width == frame.width &&
      rect.height == frame.height) {
    return _pngImageFromFrame(frame);
  }

  final cropped = Uint8List(rect.width * rect.height * 4);
  for (var y = 0; y < rect.height; y++) {
    final srcStart = ((rect.y + y) * frame.width + rect.x) * 4;
    final dstStart = y * rect.width * 4;
    cropped.setRange(
      dstStart,
      dstStart + rect.width * 4,
      frame.rgbaBytes,
      srcStart,
    );
  }

  return img.Image.fromBytes(
    width: rect.width,
    height: rect.height,
    bytes: cropped.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}

class _FrameRect {
  const _FrameRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory _FrameRect.full(int width, int height) {
    return _FrameRect(x: 0, y: 0, width: width, height: height);
  }

  final int x;
  final int y;
  final int width;
  final int height;
}

class _PngBytesWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void writeByte(int value) {
    _builder.addByte(value & 0xff);
  }

  void writeBytes(List<int> bytes) {
    _builder.add(bytes);
  }

  void writeUint16(int value) {
    if (value < 0 || value > 0xffff) {
      throw RangeError.range(value, 0, 0xffff);
    }
    writeByte(value >> 8);
    writeByte(value);
  }

  void writeUint32(int value) {
    if (value < 0 || value > 0xffffffff) {
      throw RangeError.range(value, 0, 0xffffffff);
    }
    writeByte(value >> 24);
    writeByte(value >> 16);
    writeByte(value >> 8);
    writeByte(value);
  }

  void writeChunk(String type, Uint8List payload) {
    if (type.length != 4) {
      throw ArgumentError.value(type, 'type', 'PNG chunk types are 4 bytes.');
    }
    final typeBytes = _pngChunkTypeBytes(type);
    writeUint32(payload.length);
    writeBytes(typeBytes);
    writeBytes(payload);
    writeUint32(_crc32(typeBytes, payload));
  }

  Uint8List takeBytes() => _builder.toBytes();
}

const _pngChunkActl = <int>[0x61, 0x63, 0x54, 0x4c];
const _pngChunkFctl = <int>[0x66, 0x63, 0x54, 0x4c];
const _pngChunkFdat = <int>[0x66, 0x64, 0x41, 0x54];
const _pngChunkIdat = <int>[0x49, 0x44, 0x41, 0x54];
const _pngChunkIend = <int>[0x49, 0x45, 0x4e, 0x44];
const _pngChunkIhdr = <int>[0x49, 0x48, 0x44, 0x52];

List<int> _pngChunkTypeBytes(String type) {
  return switch (type) {
    'acTL' => _pngChunkActl,
    'fcTL' => _pngChunkFctl,
    'fdAT' => _pngChunkFdat,
    'IDAT' => _pngChunkIdat,
    'IEND' => _pngChunkIend,
    'IHDR' => _pngChunkIhdr,
    _ => type.codeUnits,
  };
}

bool _matchesPngChunkType(Uint8List bytes, int offset, List<int> typeBytes) {
  if (offset + typeBytes.length > bytes.length) {
    return false;
  }
  for (var i = 0; i < typeBytes.length; i++) {
    if (bytes[offset + i] != typeBytes[i]) {
      return false;
    }
  }
  return true;
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
