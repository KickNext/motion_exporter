part of '../motion_exporter.dart';

/// Encodes [MotionClip] instances into a stable raw RGBA golden format.
///
/// The format stores dimensions, frame durations, and straight-alpha RGBA
/// bytes. It intentionally avoids WebP/APNG so animation goldens compare the
/// pixels the recorder captured, not encoder output. New files use lossless RLE
/// compression when it reduces the stored payload; older raw `.motion` files
/// remain readable.
class MotionClipGoldenCodec {
  /// Creates a raw clip golden codec.
  const MotionClipGoldenCodec({this.compress = true});

  /// Whether [encode] may compress the raw frame payload losslessly.
  ///
  /// Compression is used only when it makes the `.motion` bytes smaller.
  final bool compress;

  /// Encodes [clip] into `.motion` bytes.
  Uint8List encode(MotionClip clip) {
    final frameBytes = clip.width * clip.height * 4;
    final payloadBytes =
        clip.frameCount * (_motionGoldenFrameHeaderBytes + frameBytes);
    final payload = Uint8List(payloadBytes);
    final payloadData = ByteData.view(payload.buffer);

    var offset = 0;
    for (final frame in clip.frames) {
      payloadData.setUint64(
        offset,
        frame.duration.inMicroseconds,
        Endian.little,
      );
      offset += _motionGoldenFrameHeaderBytes;
      payload.setRange(offset, offset + frameBytes, frame.rgbaBytes);
      offset += frameBytes;
    }

    var flags = 0;
    var storedPayload = payload;
    if (compress) {
      final compressedPayload = _motionGoldenRleEncode(payload);
      if (compressedPayload.lengthInBytes < payload.lengthInBytes) {
        flags |= _motionGoldenFlagRle;
        storedPayload = compressedPayload;
      }
    }

    final out = Uint8List(
      _motionGoldenHeaderBytes + storedPayload.lengthInBytes,
    );
    final data = ByteData.view(out.buffer);
    out.setRange(0, _motionGoldenMagic.length, _motionGoldenMagic);
    data.setUint16(4, _motionGoldenVersion, Endian.little);
    data.setUint16(6, flags, Endian.little);
    data.setUint32(8, clip.width, Endian.little);
    data.setUint32(12, clip.height, Endian.little);
    data.setUint32(16, clip.frameCount, Endian.little);
    out.setRange(_motionGoldenHeaderBytes, out.lengthInBytes, storedPayload);

    return out;
  }

  /// Decodes `.motion` bytes into a [MotionClip].
  MotionClip decode(Uint8List bytes) {
    if (bytes.lengthInBytes < _motionGoldenHeaderBytes) {
      throw FormatException('Motion golden is too short.', bytes.lengthInBytes);
    }
    for (var i = 0; i < _motionGoldenMagic.length; i++) {
      if (bytes[i] != _motionGoldenMagic[i]) {
        throw const FormatException('Motion golden has an invalid header.');
      }
    }

    final data = ByteData.sublistView(bytes);
    final version = data.getUint16(4, Endian.little);
    if (version != _motionGoldenVersion) {
      throw FormatException('Unsupported motion golden version $version.');
    }
    final flags = data.getUint16(6, Endian.little);
    if ((flags & ~_motionGoldenFlagRle) != 0) {
      throw FormatException('Unsupported motion golden flags $flags.');
    }

    final width = data.getUint32(8, Endian.little);
    final height = data.getUint32(12, Endian.little);
    final frameCount = data.getUint32(16, Endian.little);
    if (width == 0 || height == 0 || frameCount == 0) {
      throw const FormatException(
        'Motion golden dimensions and frame count must be positive.',
      );
    }
    final frameBytes = width * height * 4;
    final expectedPayloadBytes =
        frameCount * (_motionGoldenFrameHeaderBytes + frameBytes);
    final storedPayload = Uint8List.sublistView(
      bytes,
      _motionGoldenHeaderBytes,
    );
    final payload = (flags & _motionGoldenFlagRle) == 0
        ? storedPayload
        : _motionGoldenRleDecode(
            storedPayload,
            expectedLength: expectedPayloadBytes,
          );
    if (payload.lengthInBytes != expectedPayloadBytes) {
      throw FormatException(
        'Motion golden payload length ${payload.lengthInBytes} does not match '
        'expected length $expectedPayloadBytes.',
      );
    }

    final payloadData = ByteData.sublistView(payload);
    var offset = 0;
    final frames = <MotionFrame>[];
    for (var i = 0; i < frameCount; i++) {
      final durationMicros = payloadData.getUint64(offset, Endian.little);
      if (durationMicros == 0) {
        throw FormatException('Motion golden frame $i has zero duration.');
      }
      offset += _motionGoldenFrameHeaderBytes;
      frames.add(
        MotionFrame(
          width: width,
          height: height,
          duration: Duration(microseconds: durationMicros),
          rgbaBytes: Uint8List.sublistView(
            payload,
            offset,
            offset + frameBytes,
          ),
        ),
      );
      offset += frameBytes;
    }

    return MotionClip(frames: frames);
  }
}

const _motionGoldenMagic = <int>[0x4d, 0x43, 0x4c, 0x50]; // MCLP.
const _motionGoldenVersion = 1;
const _motionGoldenFlagRle = 1;
const _motionGoldenHeaderBytes = 20;
const _motionGoldenFrameHeaderBytes = 8;

Uint8List _motionGoldenRleEncode(Uint8List bytes) {
  final out = BytesBuilder(copy: false);
  var literalStart = 0;
  var offset = 0;

  void flushLiteral(int end) {
    var start = literalStart;
    while (start < end) {
      final length = math.min(128, end - start);
      out.addByte(length - 1);
      out.add(Uint8List.sublistView(bytes, start, start + length));
      start += length;
    }
  }

  while (offset < bytes.lengthInBytes) {
    final value = bytes[offset];
    var runEnd = offset + 1;
    while (runEnd < bytes.lengthInBytes &&
        bytes[runEnd] == value &&
        runEnd - offset < 130) {
      runEnd++;
    }

    final runLength = runEnd - offset;
    if (runLength >= 3) {
      flushLiteral(offset);
      out.addByte(0x80 | (runLength - 3));
      out.addByte(value);
      offset = runEnd;
      literalStart = offset;
    } else {
      offset++;
    }
  }
  flushLiteral(bytes.lengthInBytes);
  return out.toBytes();
}

Uint8List _motionGoldenRleDecode(
  Uint8List bytes, {
  required int expectedLength,
}) {
  final out = Uint8List(expectedLength);
  var sourceOffset = 0;
  var targetOffset = 0;

  while (sourceOffset < bytes.lengthInBytes) {
    final control = bytes[sourceOffset++];
    if (control & 0x80 == 0) {
      final length = control + 1;
      final sourceEnd = sourceOffset + length;
      final targetEnd = targetOffset + length;
      if (sourceEnd > bytes.lengthInBytes || targetEnd > expectedLength) {
        throw const FormatException('Motion golden RLE literal is truncated.');
      }
      out.setRange(targetOffset, targetEnd, bytes, sourceOffset);
      sourceOffset = sourceEnd;
      targetOffset = targetEnd;
    } else {
      final length = (control & 0x7f) + 3;
      if (sourceOffset >= bytes.lengthInBytes ||
          targetOffset + length > expectedLength) {
        throw const FormatException('Motion golden RLE run is truncated.');
      }
      out.fillRange(targetOffset, targetOffset + length, bytes[sourceOffset++]);
      targetOffset += length;
    }
  }

  if (targetOffset != expectedLength) {
    throw FormatException(
      'Motion golden RLE decoded $targetOffset bytes, expected $expectedLength.',
    );
  }
  return out;
}
