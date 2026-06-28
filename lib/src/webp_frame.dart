part of '../motion_exporter.dart';

/// A raw straight-alpha RGBA frame captured from a Flutter widget or supplied
/// manually.
class MotionFrame {
  /// Creates a frame from tightly packed straight-alpha RGBA pixels.
  MotionFrame({
    required this.rgbaBytes,
    required this.width,
    required this.height,
    required this.duration,
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError.value(
        '$width x $height',
        'size',
        'Frame size must be positive.',
      );
    }
    final expectedLength = width * height * 4;
    if (rgbaBytes.lengthInBytes != expectedLength) {
      throw ArgumentError.value(
        rgbaBytes.lengthInBytes,
        'rgbaBytes',
        'Expected $expectedLength bytes for $width x $height RGBA pixels.',
      );
    }
    if (duration <= Duration.zero) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Frame duration must be positive.',
      );
    }
  }

  /// Tightly packed straight-alpha pixels in red, green, blue, alpha byte
  /// order.
  final Uint8List rgbaBytes;

  /// Returns a copy of [rgbaBytes] with color channels premultiplied by alpha.
  ///
  /// Keep [rgbaBytes] for encoders such as APNG/WebP. Use this copy only when
  /// sending pixels back into Flutter APIs that expect premultiplied RGBA,
  /// such as `ui.decodeImageFromPixels` with `ui.PixelFormat.rgba8888`.
  Uint8List toPremultipliedRgbaBytes() {
    return _premultiplyRgba(Uint8List.fromList(rgbaBytes));
  }

  /// Frame width in physical pixels.
  final int width;

  /// Frame height in physical pixels.
  final int height;

  /// How long this frame should be displayed before the next frame.
  final Duration duration;
}

/// A raw straight-alpha RGBA frame that can be encoded into an animated WebP
/// file.
class WebpFrame extends MotionFrame {
  /// Creates a frame from tightly packed straight-alpha RGBA pixels.
  WebpFrame({
    required super.rgbaBytes,
    required super.width,
    required super.height,
    required super.duration,
  });
}

/// Transforms a captured clip before export encoding.
typedef MotionClipTransform = MotionClip Function(MotionClip clip);

/// A captured animation clip with raw RGBA frames.
class MotionClip {
  /// Creates a clip from consistent-size [frames].
  MotionClip({required List<MotionFrame> frames})
    : this._(_validatedClipFrames(frames));

  MotionClip._(this.frames)
    : duration = _clipDuration(frames),
      rawBytes = _clipRawBytes(frames);

  /// Raw RGBA frames in display order.
  final List<MotionFrame> frames;

  /// Number of frames.
  int get frameCount => frames.length;

  /// Clip width in physical pixels.
  int get width => frames.first.width;

  /// Clip height in physical pixels.
  int get height => frames.first.height;

  /// Total playback duration represented by all frame durations.
  final Duration duration;

  /// Total retained straight-alpha RGBA bytes across all frames.
  final int rawBytes;

  /// Total retained straight-alpha RGBA memory in mebibytes.
  double get rawMebibytes => rawBytes / (1024 * 1024);

  /// Returns this clip with frame durations scaled to [duration].
  ///
  /// Pixel data and frame count are unchanged. Use this only when an external
  /// animation clock already defines the semantic clip duration, such as a
  /// known loop period.
  MotionClip withDuration(Duration duration) {
    if (duration <= Duration.zero) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Clip duration must be positive.',
      );
    }
    final targetMicros = duration.inMicroseconds;
    if (targetMicros < frameCount) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Duration must allow at least one microsecond per frame.',
      );
    }
    if (duration == this.duration) {
      return this;
    }

    final sourceMicros = this.duration.inMicroseconds;
    var sourceElapsedMicros = 0;
    var targetElapsedMicros = 0;
    final scaledFrames = <MotionFrame>[];

    for (var i = 0; i < frames.length; i++) {
      final frame = frames[i];
      sourceElapsedMicros += frame.duration.inMicroseconds;
      final remainingFrames = frames.length - i - 1;
      final idealEndMicros = i == frames.length - 1
          ? targetMicros
          : (sourceElapsedMicros * targetMicros / sourceMicros).round();
      final endMicros = idealEndMicros.clamp(
        targetElapsedMicros + 1,
        targetMicros - remainingFrames,
      );
      scaledFrames.add(
        _frameWithDuration(
          frame,
          Duration(microseconds: endMicros - targetElapsedMicros),
        ),
      );
      targetElapsedMicros = endMicros;
    }

    return MotionClip(frames: scaledFrames);
  }

  /// Whether the final frame is an exact duplicate of the first frame.
  ///
  /// This can happen when a recording starts and stops on animation loop
  /// boundaries. Dropping that terminal duplicate prevents an extra pause at
  /// the playback seam.
  bool get hasDuplicateLoopClosure => hasSimilarLoopClosure();

  /// Whether the final frame visually matches the first frame.
  ///
  /// [channelTolerance] allows small per-channel RGBA differences caused by
  /// live rendering and antialiasing at loop boundaries.
  bool hasSimilarLoopClosure({int channelTolerance = 0}) {
    if (channelTolerance < 0 || channelTolerance > 255) {
      throw RangeError.range(channelTolerance, 0, 255, 'channelTolerance');
    }
    if (frames.length < 2) {
      return false;
    }

    final first = frames.first;
    final last = frames.last;
    return first.width == last.width &&
        first.height == last.height &&
        _bytesSimilar(
          first.rgbaBytes,
          last.rgbaBytes,
          channelTolerance: channelTolerance,
        );
  }

  /// Returns this clip without a terminal duplicate of the first frame.
  ///
  /// Set [preserveDuration] to keep the original clip duration by folding the
  /// removed terminal frame duration into the first retained frame. This is
  /// useful for boundary-to-boundary loop captures where the final sample is
  /// visually the start of the next loop.
  MotionClip withoutDuplicateLoopClosure({
    int channelTolerance = 0,
    bool preserveDuration = false,
  }) {
    if (!hasSimilarLoopClosure(channelTolerance: channelTolerance)) {
      return this;
    }

    final trimmedFrames = frames.sublist(0, frames.length - 1);
    if (preserveDuration) {
      final first = trimmedFrames.first;
      trimmedFrames[0] = _frameWithDuration(
        first,
        first.duration + frames.last.duration,
      );
    }
    return MotionClip(frames: trimmedFrames);
  }

  /// Returns this clip with consecutive visually identical frames merged.
  ///
  /// The first frame in each run keeps its pixels; duplicate frame durations are
  /// folded into it. Use this before human-readable exports to reduce encoding
  /// work without changing playback duration.
  MotionClip withoutDuplicateFrames({int channelTolerance = 0}) {
    if (channelTolerance < 0 || channelTolerance > 255) {
      throw RangeError.range(channelTolerance, 0, 255, 'channelTolerance');
    }
    if (frames.length < 2) {
      return this;
    }

    var changed = false;
    final collapsed = <MotionFrame>[frames.first];
    for (var i = 1; i < frames.length; i++) {
      final frame = frames[i];
      final previous = collapsed.last;
      if (_bytesSimilar(
        previous.rgbaBytes,
        frame.rgbaBytes,
        channelTolerance: channelTolerance,
      )) {
        collapsed[collapsed.length - 1] = _frameWithDuration(
          previous,
          previous.duration + frame.duration,
        );
        changed = true;
      } else {
        collapsed.add(frame);
      }
    }

    return changed ? MotionClip(frames: collapsed) : this;
  }
}

List<MotionFrame> _validatedClipFrames(List<MotionFrame> frames) {
  final validated = List<MotionFrame>.unmodifiable(frames);
  if (validated.isEmpty) {
    throw ArgumentError.value(frames, 'frames', 'At least one frame required.');
  }

  final first = validated.first;
  for (final frame in validated) {
    if (frame.width != first.width || frame.height != first.height) {
      throw ArgumentError.value(
        '${frame.width} x ${frame.height}',
        'frames',
        'All frames must use the same dimensions as the first frame.',
      );
    }
  }
  return validated;
}

Duration _clipDuration(List<MotionFrame> frames) {
  var micros = 0;
  for (final frame in frames) {
    micros += frame.duration.inMicroseconds;
  }
  return Duration(microseconds: micros);
}

int _clipRawBytes(List<MotionFrame> frames) {
  var total = 0;
  for (final frame in frames) {
    total += frame.rgbaBytes.lengthInBytes;
  }
  return total;
}

MotionFrame _frameWithDuration(MotionFrame frame, Duration duration) {
  return MotionFrame(
    rgbaBytes: frame.rgbaBytes,
    width: frame.width,
    height: frame.height,
    duration: duration,
  );
}

/// Controls how each full-frame snapshot is composited by WebP players.
enum WebpFrameBlend {
  /// Alpha-blend the frame over the current animation canvas.
  blend,

  /// Replace the covered rectangle with the frame.
  ///
  /// This is the default for widget recording because every captured frame is a
  /// full snapshot. Replacement prevents transparent pixels from leaving trails
  /// from earlier frames.
  replace,
}

/// Controls what happens to a frame rectangle after it has been displayed.
enum WebpFrameDispose {
  /// Keep the rendered frame on the canvas.
  none,

  /// Clear the frame rectangle to the animation background color.
  background,
}

/// Encoded WebP bytes plus useful recording metadata.
class MotionRecording {
  /// Creates a completed recording.
  const MotionRecording({
    required this.bytes,
    required this.frameCount,
    required this.width,
    required this.height,
    required this.duration,
    this.clip,
    this.diagnostics,
  });

  /// Animated WebP file bytes.
  final Uint8List bytes;

  /// Number of encoded frames after optional duplicate-frame collapse.
  final int frameCount;

  /// Encoded canvas width in physical pixels.
  final int width;

  /// Encoded canvas height in physical pixels.
  final int height;

  /// Total playback duration represented by all frame durations.
  final Duration duration;

  /// Raw clip used to produce this recording, when retained by the caller.
  final MotionClip? clip;

  /// Performance diagnostics captured during recording, when available.
  final MotionCaptureDiagnostics? diagnostics;
}

class _CapturedFrame {
  _CapturedFrame({
    required this.rgbaBytes,
    required this.width,
    required this.height,
    required this.capturedAt,
    this.hash,
    required this.duration,
  });

  final Uint8List rgbaBytes;
  final int width;
  final int height;
  final Duration capturedAt;
  final int? hash;
  Duration duration;

  MotionFrame toFrame() {
    return MotionFrame(
      rgbaBytes: rgbaBytes,
      width: width,
      height: height,
      duration: duration,
    );
  }
}
