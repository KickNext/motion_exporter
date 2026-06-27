part of '../motion_exporter.dart';

/// Estimated cost of recording a widget subtree into raw RGBA frames.
///
/// This is a preflight helper. It estimates the uncompressed frame buffer that
/// must be retained before APNG/WebP encoding can finish.
class MotionCaptureEstimate {
  /// Creates a capture estimate from already scaled values.
  const MotionCaptureEstimate({
    required this.logicalSize,
    required this.duration,
    required this.targetFramesPerSecond,
    required this.pixelRatio,
    required this.width,
    required this.height,
    required this.frameCount,
  }) : assert(duration > Duration.zero),
       assert(targetFramesPerSecond > 0),
       assert(pixelRatio > 0),
       assert(width > 0),
       assert(height > 0),
       assert(frameCount > 0);

  /// Estimates a live widget capture using [MotionRecorderOptions].
  factory MotionCaptureEstimate.forWidget({
    required Size logicalSize,
    required Duration duration,
    MotionRecorderOptions options = const MotionRecorderOptions(),
  }) {
    if (logicalSize.width <= 0 || logicalSize.height <= 0) {
      throw ArgumentError.value(
        logicalSize,
        'logicalSize',
        'Capture size must be positive.',
      );
    }
    if (!logicalSize.isFinite) {
      throw ArgumentError.value(
        logicalSize,
        'logicalSize',
        'Capture size must be finite.',
      );
    }
    if (duration <= Duration.zero) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Capture duration must be positive.',
      );
    }

    return MotionCaptureEstimate(
      logicalSize: logicalSize,
      duration: duration,
      targetFramesPerSecond: options.framesPerSecond,
      pixelRatio: options.pixelRatio,
      width: _scaledDimension(logicalSize.width, options.pixelRatio, 'width'),
      height: _scaledDimension(
        logicalSize.height,
        options.pixelRatio,
        'height',
      ),
      frameCount: _frameCountForDuration(duration, options.framesPerSecond),
    );
  }

  /// Widget size before [pixelRatio] is applied.
  final Size logicalSize;

  /// Intended capture duration.
  final Duration duration;

  /// Requested frame rate.
  final int targetFramesPerSecond;

  /// Pixel ratio applied to [logicalSize].
  final double pixelRatio;

  /// Estimated captured width in physical pixels.
  final int width;

  /// Estimated captured height in physical pixels.
  final int height;

  /// Estimated number of requested frames.
  final int frameCount;

  /// Bytes required for one straight-alpha RGBA frame.
  int get frameBytes => width * height * 4;

  /// Estimated raw RGBA bytes retained before encoding.
  int get rawBytes => frameBytes * frameCount;

  /// Estimated raw RGBA memory in MiB.
  double get rawMebibytes => rawBytes / (1024 * 1024);

  /// Approximate target frame interval.
  Duration get frameInterval {
    return Duration(
      microseconds: (Duration.microsecondsPerSecond / targetFramesPerSecond)
          .round(),
    );
  }

  /// Whether [rawBytes] fits within a raw-memory budget.
  bool fitsRawByteBudget({required int bytes}) {
    if (bytes <= 0) {
      throw ArgumentError.value(bytes, 'bytes', 'Budget must be positive.');
    }
    return rawBytes <= bytes;
  }

  /// Whether [rawBytes] fits within a raw-memory budget in MiB.
  bool fitsRawMemoryBudget({int mebibytes = 256}) {
    if (mebibytes <= 0) {
      throw ArgumentError.value(
        mebibytes,
        'mebibytes',
        'Budget must be positive.',
      );
    }
    return fitsRawByteBudget(bytes: mebibytes * 1024 * 1024);
  }
}

int _frameCountForDuration(Duration duration, int framesPerSecond) {
  final numerator = duration.inMicroseconds * framesPerSecond;
  return math.max(
    1,
    (numerator + Duration.microsecondsPerSecond - 1) ~/
        Duration.microsecondsPerSecond,
  );
}
