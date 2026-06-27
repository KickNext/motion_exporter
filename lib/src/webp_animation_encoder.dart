part of '../motion_exporter.dart';

/// Encodes raw RGBA frames into an animated WebP file.
class WebpAnimationEncoder {
  /// Creates an animated WebP encoder.
  const WebpAnimationEncoder([this.options = const WebpAnimationOptions()]);

  /// Encoding options.
  final WebpAnimationOptions options;

  /// Encodes [frames] into animated WebP bytes.
  Uint8List encode(List<MotionFrame> frames) {
    return _encodeWebpAnimation(options._toJob(frames));
  }

  /// Encodes a captured [clip] into animated WebP bytes.
  Uint8List encodeClip(MotionClip clip) {
    return encode(clip.frames);
  }
}

class _EncodeJob {
  const _EncodeJob({
    required this.frames,
    required this.loopCount,
    required this.backgroundArgb,
    required this.frameBlend,
    required this.frameDispose,
    required this.trimTransparentFrames,
    required this.trimChangedFrames,
  });

  final List<MotionFrame> frames;
  final int loopCount;
  final int backgroundArgb;
  final WebpFrameBlend frameBlend;
  final WebpFrameDispose frameDispose;
  final bool trimTransparentFrames;
  final bool trimChangedFrames;
}

Uint8List _encodeWebpAnimation(_EncodeJob job) {
  final frames = job.frames;
  if (frames.isEmpty) {
    throw ArgumentError.value(frames, 'frames', 'At least one frame required.');
  }

  final width = frames.first.width;
  final height = frames.first.height;
  _checkVp8lSize(width, height);

  for (final frame in frames) {
    if (frame.width != width || frame.height != height) {
      throw ArgumentError.value(
        '${frame.width} x ${frame.height}',
        'frames',
        'All frames must use the same dimensions as the first frame.',
      );
    }
    _checkVp8lSize(frame.width, frame.height);
  }

  final body = _WebpBytesWriter()
    ..writeChunk('VP8X', _vp8xPayload(width, height))
    ..writeChunk('ANIM', _animPayload(job.backgroundArgb, job.loopCount));

  final durationAccumulator = _WebpFrameDurationAccumulator();
  for (var i = 0; i < frames.length; i++) {
    final frame = frames[i];
    final durationMs = durationAccumulator.next(frame.duration);
    final trimChangedFrame = job.trimChangedFrames && i > 0;
    final rect = job.trimChangedFrames
        ? trimChangedFrame
              ? _webpChangedTrimRect(frame, frames[i - 1])
              : _FrameRect.full(frame.width, frame.height)
        : job.trimTransparentFrames
        ? _webpTransparentTrimRect(frame)
        : _FrameRect.full(frame.width, frame.height);
    final frameChunk = _frameImageChunk(frame, rect);
    body.writeAnmf(
      rect: rect,
      durationMs: durationMs,
      frameData: frameChunk,
      blend: job.trimChangedFrames ? WebpFrameBlend.replace : job.frameBlend,
      dispose: job.trimChangedFrames
          ? WebpFrameDispose.none
          : job.trimTransparentFrames
          ? WebpFrameDispose.background
          : job.frameDispose,
    );
  }

  final bodyBytes = body.takeBytes();
  final riffSize = 4 + bodyBytes.length;
  if (riffSize > 0xffffffff) {
    throw StateError('Encoded WebP is too large for a RIFF container.');
  }

  final out = _WebpBytesWriter()
    ..writeAscii('RIFF')
    ..writeUint32(riffSize)
    ..writeAscii('WEBP')
    ..writeBytes(bodyBytes);
  return out.takeBytes();
}

Uint8List _vp8xPayload(int width, int height) {
  return (_WebpBytesWriter()
        ..writeByte(0x12) // Animation + alpha.
        ..writeUint24(0)
        ..writeUint24(width - 1)
        ..writeUint24(height - 1))
      .takeBytes();
}

Uint8List _animPayload(int backgroundArgb, int loopCount) {
  final alpha = (backgroundArgb >> 24) & 0xff;
  final red = (backgroundArgb >> 16) & 0xff;
  final green = (backgroundArgb >> 8) & 0xff;
  final blue = backgroundArgb & 0xff;

  return (_WebpBytesWriter()
        ..writeByte(blue)
        ..writeByte(green)
        ..writeByte(red)
        ..writeByte(alpha)
        ..writeUint16(loopCount))
      .takeBytes();
}

Uint8List _frameImageChunk(MotionFrame frame, _FrameRect rect) {
  final image = _imageForRect(frame, rect);
  final encoded = img.encodeWebP(image);
  return _extractPrimaryImageChunk(encoded);
}

_FrameRect _webpTransparentTrimRect(MotionFrame frame) {
  return _webpEvenOffsetRect(_transparentTrimRect(frame), frame);
}

_FrameRect _webpChangedTrimRect(MotionFrame frame, MotionFrame previousFrame) {
  return _webpChangedTrimRectBytes(frame, previousFrame.rgbaBytes);
}

_FrameRect _webpChangedTrimRectBytes(
  MotionFrame frame,
  Uint8List previousBytes,
) {
  var minX = frame.width;
  var minY = frame.height;
  var maxX = -1;
  var maxY = -1;
  final bytes = frame.rgbaBytes;
  if (previousBytes.lengthInBytes != bytes.lengthInBytes) {
    throw ArgumentError.value(
      previousBytes.lengthInBytes,
      'previousBytes',
      'Previous frame bytes must match the current frame size.',
    );
  }

  final canUsePixelView =
      bytes.offsetInBytes % 4 == 0 && previousBytes.offsetInBytes % 4 == 0;
  if (canUsePixelView) {
    final pixels = Uint32List.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 4,
    );
    final previousPixels = Uint32List.view(
      previousBytes.buffer,
      previousBytes.offsetInBytes,
      previousBytes.lengthInBytes ~/ 4,
    );
    var pixelOffset = 0;
    for (var y = 0; y < frame.height; y++) {
      for (var x = 0; x < frame.width; x++) {
        if (pixels[pixelOffset] != previousPixels[pixelOffset]) {
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
      var offset = y * frame.width * 4;
      for (var x = 0; x < frame.width; x++) {
        if (bytes[offset] != previousBytes[offset] ||
            bytes[offset + 1] != previousBytes[offset + 1] ||
            bytes[offset + 2] != previousBytes[offset + 2] ||
            bytes[offset + 3] != previousBytes[offset + 3]) {
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

  return _webpEvenOffsetRect(
    _FrameRect(
      x: minX,
      y: minY,
      width: maxX - minX + 1,
      height: maxY - minY + 1,
    ),
    frame,
  );
}

_FrameRect _webpEvenOffsetRect(_FrameRect rect, MotionFrame frame) {
  var x = rect.x;
  var y = rect.y;
  var width = rect.width;
  var height = rect.height;

  if (x.isOdd) {
    x--;
    width++;
  }
  if (y.isOdd) {
    y--;
    height++;
  }

  return _FrameRect(
    x: x,
    y: y,
    width: math.min(width, frame.width - x),
    height: math.min(height, frame.height - y),
  );
}

Uint8List _extractPrimaryImageChunk(Uint8List webpBytes) {
  if (webpBytes.length < 20 ||
      !_matchesAscii(webpBytes, 0, 'RIFF') ||
      !_matchesAscii(webpBytes, 8, 'WEBP')) {
    throw StateError('The frame encoder did not return a valid WebP file.');
  }

  var offset = 12;
  while (offset + 8 <= webpBytes.length) {
    final isVp8l = _matchesAscii(webpBytes, offset, 'VP8L');
    final isVp8 = _matchesAscii(webpBytes, offset, 'VP8 ');
    final size = _readUint32(webpBytes, offset + 4);
    final payloadEnd = offset + 8 + size;
    final chunkEnd = payloadEnd + (size.isOdd ? 1 : 0);
    if (chunkEnd > webpBytes.length) {
      final tag = _asciiAt(webpBytes, offset, 4);
      throw StateError('The frame WebP contains a truncated $tag chunk.');
    }
    if (isVp8l || isVp8) {
      return Uint8List.sublistView(webpBytes, offset, chunkEnd);
    }
    offset = chunkEnd;
  }

  throw StateError('The frame WebP does not contain VP8/VP8L image data.');
}

void _checkVp8lSize(int width, int height) {
  if (width <= 0 || height <= 0 || width > 16384 || height > 16384) {
    throw ArgumentError.value(
      '$width x $height',
      'size',
      'VP8L lossless WebP frames must be between 1 and 16384 pixels per side.',
    );
  }
}

bool _matchesAscii(Uint8List bytes, int offset, String value) {
  if (offset + value.length > bytes.length) {
    return false;
  }
  for (var i = 0; i < value.length; i++) {
    if (bytes[offset + i] != value.codeUnitAt(i)) {
      return false;
    }
  }
  return true;
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

class _WebpBytesWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void writeAscii(String value) {
    for (var i = 0; i < value.length; i++) {
      writeByte(value.codeUnitAt(i));
    }
  }

  void writeByte(int value) {
    _builder.addByte(value & 0xff);
  }

  void writeBytes(List<int> bytes) {
    _builder.add(bytes);
  }

  void writeChunk(String tag, Uint8List payload) {
    if (tag.length != 4) {
      throw ArgumentError.value(tag, 'tag', 'RIFF tags must be 4 bytes.');
    }
    writeAscii(tag);
    writeUint32(payload.lengthInBytes);
    writeBytes(payload);
    writePaddingIfOdd(payload.lengthInBytes);
  }

  void writeAnmf({
    required _FrameRect rect,
    required int durationMs,
    required Uint8List frameData,
    required WebpFrameBlend blend,
    required WebpFrameDispose dispose,
  }) {
    final payloadSize = 16 + frameData.lengthInBytes;
    writeBytes(
      _webpAnmfHeader(
        rect: rect,
        payloadSize: payloadSize,
        durationMs: durationMs,
        blend: blend,
        dispose: dispose,
      ),
    );
    writeBytes(frameData);
    writePaddingIfOdd(payloadSize);
  }

  void writeUint16(int value) {
    if (value < 0 || value > 0xffff) {
      throw RangeError.range(value, 0, 0xffff);
    }
    writeByte(value);
    writeByte(value >> 8);
  }

  void writeUint24(int value) {
    if (value < 0 || value > 0xffffff) {
      throw RangeError.range(value, 0, 0xffffff);
    }
    writeByte(value);
    writeByte(value >> 8);
    writeByte(value >> 16);
  }

  void writeUint32(int value) {
    if (value < 0 || value > 0xffffffff) {
      throw RangeError.range(value, 0, 0xffffffff);
    }
    writeByte(value);
    writeByte(value >> 8);
    writeByte(value >> 16);
    writeByte(value >> 24);
  }

  void writePaddingIfOdd(int length) {
    if (length.isOdd) {
      writeByte(0);
    }
  }

  Uint8List takeBytes() => _builder.toBytes();
}
