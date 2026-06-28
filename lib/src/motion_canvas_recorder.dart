part of '../motion_exporter.dart';

/// Paints one deterministic motion frame into [canvas].
///
/// [progress] is normalized to `0..1` across the rendered clip, excluding the
/// terminal duplicate of the first frame. [elapsed] is the timestamp of the
/// frame being rendered.
typedef MotionCanvasPainter =
    void Function(
      ui.Canvas canvas,
      Size size,
      double progress,
      Duration elapsed,
    );

/// Renders deterministic canvas-driven motion into a [MotionClip].
///
/// This path is independent from the live Flutter window refresh rate. Use it
/// when the animation can be expressed from explicit time/progress values.
class MotionCanvasRecorder {
  /// Creates a deterministic canvas recorder.
  const MotionCanvasRecorder({
    required this.size,
    required this.duration,
    required this.framesPerSecond,
    this.pixelRatio = 1,
  }) : assert(framesPerSecond > 0),
       assert(framesPerSecond <= 240),
       assert(pixelRatio > 0);

  /// Logical canvas size.
  final Size size;

  /// Total clip duration.
  final Duration duration;

  /// Number of frames to render per second.
  final int framesPerSecond;

  /// Scale applied to the logical [size] for output pixels.
  final double pixelRatio;

  /// Number of frames that will be produced.
  int get frameCount {
    _validate();
    return _frameCountForDuration(duration, framesPerSecond);
  }

  /// Renders the full deterministic clip.
  Future<MotionClip> record(MotionCanvasPainter paint) async {
    _validate();
    final count = frameCount;
    final outputWidth = _scaledDimension(size.width, pixelRatio, 'width');
    final outputHeight = _scaledDimension(size.height, pixelRatio, 'height');
    final frames = <MotionFrame>[];

    for (var i = 0; i < count; i++) {
      final frameStartMicros = (duration.inMicroseconds * i / count).round();
      final frameEndMicros = (duration.inMicroseconds * (i + 1) / count)
          .round();
      final elapsed = Duration(microseconds: frameStartMicros);

      frames.add(
        MotionFrame(
          width: outputWidth,
          height: outputHeight,
          duration: Duration(microseconds: frameEndMicros - frameStartMicros),
          rgbaBytes: await _renderFrame(
            paint: paint,
            progress: i / count,
            elapsed: elapsed,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
          ),
        ),
      );
    }

    return MotionClip(frames: frames);
  }

  Future<Uint8List> _renderFrame({
    required MotionCanvasPainter paint,
    required double progress,
    required Duration elapsed,
    required int outputWidth,
    required int outputHeight,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    if (pixelRatio != 1) {
      canvas.scale(pixelRatio);
    }
    paint(canvas, size, progress, elapsed);
    final picture = recorder.endRecording();
    final image = await picture.toImage(outputWidth, outputHeight);
    picture.dispose();
    try {
      final bytes = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (bytes == null) {
        throw StateError('Flutter returned no RGBA bytes for rendered frame.');
      }
      return Uint8List.sublistView(bytes);
    } finally {
      image.dispose();
    }
  }

  void _validate() {
    if (size.width <= 0 || size.height <= 0 || !size.isFinite) {
      throw ArgumentError.value(
        size,
        'size',
        'Canvas size must be finite and positive.',
      );
    }
    if (duration <= Duration.zero) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Clip duration must be positive.',
      );
    }
    _validateFramesPerSecond(framesPerSecond);
    _validatePixelRatio(pixelRatio);
  }
}

int _scaledDimension(double logical, double pixelRatio, String name) {
  final scaled = (logical * pixelRatio).round();
  if (scaled <= 0) {
    throw ArgumentError.value(logical, name, 'Scaled dimension is zero.');
  }
  return scaled;
}
