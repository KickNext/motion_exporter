part of '../motion_exporter.dart';

/// WebP-first facade for recording, encoding, and clip golden checks.
///
/// The engine keeps the package API small: capture a raw [MotionClip] for
/// animation goldens, then call [encode] only when WebP/APNG bytes are needed.
/// Use [compare] or [expectMatches] when a test already has two clips in memory.
class MotionExportEngine {
  /// Creates a motion export engine.
  const MotionExportEngine({
    this.encoder = const MotionClipEncoder(),
    this.clipTransform,
  });

  /// Encoder used for all exports.
  ///
  /// Defaults to animated WebP with changed-frame rectangle trimming. Pass a
  /// custom [MotionClipEncoder] to choose APNG or different WebP options.
  final MotionClipEncoder encoder;

  /// Optional transform applied before every export.
  final MotionClipTransform? clipTransform;

  /// Encodes [clip] with the configured [encoder].
  Future<MotionExportResult> encode(
    MotionClip clip, {
    MotionCaptureDiagnostics? diagnostics,
    MotionClipTransform? clipTransform,
  }) {
    final exportClip = _transformClip(clip, clipTransform);
    return encoder.encode(
      exportClip,
      diagnostics: diagnostics?.forClip(exportClip),
    );
  }

  /// Stops an active [MotionRecorder] capture and exports it.
  Future<MotionExportResult> stopRecording(
    MotionRecorderController controller, {
    MotionClipTransform? clipTransform,
  }) async {
    final clip = await controller.stopCapture();
    return encode(
      clip,
      diagnostics: controller.diagnostics,
      clipTransform: clipTransform,
    );
  }

  /// Records the next semantic loop from a widget recorder and exports it.
  Future<MotionExportResult> recordNextLoop({
    required MotionRecorderController controller,
    required MotionLoopSignal loopSignal,
    MotionRecorderOptions options = const MotionRecorderOptions(),
    Duration? loopDuration,
    Duration? boundaryTimeout,
    Future<void>? cancelSignal,
    FutureOr<void> Function(int boundaryCount)? onCaptureStarted,
    int duplicateLoopClosureTolerance = 8,
    MotionClipTransform? clipTransform,
  }) {
    return controller.recordNextLoop(
      loopSignal: loopSignal,
      options: options,
      encoder: encoder,
      loopDuration: loopDuration,
      boundaryTimeout: boundaryTimeout,
      cancelSignal: cancelSignal,
      onCaptureStarted: onCaptureStarted,
      duplicateLoopClosureTolerance: duplicateLoopClosureTolerance,
      clipTransform: (clip) => _transformClip(clip, clipTransform),
    );
  }

  /// Records the next semantic loop from a widget recorder without encoding.
  ///
  /// Use this for raw animation golden tests, then call [encode] only when you
  /// also need WebP/APNG bytes for a human-readable artifact.
  Future<MotionClip> recordNextLoopClip({
    required MotionRecorderController controller,
    required MotionLoopSignal loopSignal,
    MotionRecorderOptions options = const MotionRecorderOptions(),
    Duration? loopDuration,
    Duration? boundaryTimeout,
    Future<void>? cancelSignal,
    FutureOr<void> Function(int boundaryCount)? onCaptureStarted,
    int duplicateLoopClosureTolerance = 8,
    MotionClipTransform? clipTransform,
  }) {
    return controller.recordNextLoopClip(
      loopSignal: loopSignal,
      options: options,
      loopDuration: loopDuration,
      boundaryTimeout: boundaryTimeout,
      cancelSignal: cancelSignal,
      onCaptureStarted: onCaptureStarted,
      duplicateLoopClosureTolerance: duplicateLoopClosureTolerance,
      clipTransform: (clip) => _transformClip(clip, clipTransform),
    );
  }

  /// Renders a deterministic canvas animation without encoding it.
  ///
  /// This is the CI-friendly path when the animation can be driven from
  /// explicit `progress` or `elapsed` values instead of the live display clock.
  Future<MotionClip> recordCanvasClip({
    required Size size,
    required Duration duration,
    required int framesPerSecond,
    required MotionCanvasPainter paint,
    double pixelRatio = 1,
    MotionClipTransform? clipTransform,
  }) async {
    final clip = await _recordCanvasRaw(
      size: size,
      duration: duration,
      framesPerSecond: framesPerSecond,
      pixelRatio: pixelRatio,
      paint: paint,
    );
    return _transformClip(clip, clipTransform);
  }

  /// Renders a deterministic canvas animation and exports it.
  ///
  /// This is the CI-friendly path when the animation can be driven from
  /// explicit `progress` or `elapsed` values instead of the live display clock.
  Future<MotionExportResult> recordCanvas({
    required Size size,
    required Duration duration,
    required int framesPerSecond,
    required MotionCanvasPainter paint,
    double pixelRatio = 1,
    MotionClipTransform? clipTransform,
  }) async {
    final capturedClip = await _recordCanvasRaw(
      size: size,
      duration: duration,
      framesPerSecond: framesPerSecond,
      pixelRatio: pixelRatio,
      paint: paint,
    );
    final clip = _transformClip(capturedClip, clipTransform);
    return encoder.encode(
      clip,
      diagnostics: _deterministicCanvasDiagnostics(
        clip: capturedClip,
        framesPerSecond: framesPerSecond,
        pixelRatio: pixelRatio,
      ).forClip(clip),
    );
  }

  /// Compares two raw clips for frame-by-frame animation golden tests.
  MotionClipComparison compare(
    MotionClip actual,
    MotionClip expected, {
    int channelTolerance = 0,
    double maxMismatchedPixelRatio = 0,
    Duration durationTolerance = Duration.zero,
  }) {
    return MotionClipComparison.compare(
      actual: actual,
      expected: expected,
      channelTolerance: channelTolerance,
      maxMismatchedPixelRatio: maxMismatchedPixelRatio,
      durationTolerance: durationTolerance,
    );
  }

  /// Throws [MotionClipComparisonException] when [actual] differs from
  /// [expected].
  void expectMatches(
    MotionClip actual,
    MotionClip expected, {
    int channelTolerance = 0,
    double maxMismatchedPixelRatio = 0,
    Duration durationTolerance = Duration.zero,
    String? description,
  }) {
    compare(
      actual,
      expected,
      channelTolerance: channelTolerance,
      maxMismatchedPixelRatio: maxMismatchedPixelRatio,
      durationTolerance: durationTolerance,
    ).throwIfMismatch(description: description);
  }

  MotionClip _transformClip(
    MotionClip clip,
    MotionClipTransform? localTransform,
  ) {
    final baseTransform = clipTransform;
    final transformed = baseTransform == null ? clip : baseTransform(clip);
    return localTransform == null ? transformed : localTransform(transformed);
  }
}

/// Frame-by-frame comparison result for two [MotionClip] instances.
class MotionClipComparison {
  const MotionClipComparison._({
    required this.actualFrameCount,
    required this.expectedFrameCount,
    required this.actualWidth,
    required this.actualHeight,
    required this.expectedWidth,
    required this.expectedHeight,
    required this.actualDuration,
    required this.expectedDuration,
    required this.durationTolerance,
    required this.maxMismatchedPixelRatio,
    required this.frames,
  });

  /// Compares [actual] and [expected] without depending on `flutter_test`.
  factory MotionClipComparison.compare({
    required MotionClip actual,
    required MotionClip expected,
    int channelTolerance = 0,
    double maxMismatchedPixelRatio = 0,
    Duration durationTolerance = Duration.zero,
  }) {
    if (channelTolerance < 0 || channelTolerance > 255) {
      throw RangeError.range(channelTolerance, 0, 255, 'channelTolerance');
    }
    if (maxMismatchedPixelRatio < 0 || maxMismatchedPixelRatio > 1) {
      throw RangeError.range(
        maxMismatchedPixelRatio,
        0,
        1,
        'maxMismatchedPixelRatio',
      );
    }
    if (durationTolerance < Duration.zero) {
      throw ArgumentError.value(
        durationTolerance,
        'durationTolerance',
        'Duration tolerance must not be negative.',
      );
    }

    final frameCount = math.min(actual.frameCount, expected.frameCount);
    final frames = <MotionFrameComparison>[];
    for (var i = 0; i < frameCount; i++) {
      frames.add(
        MotionFrameComparison.compare(
          index: i,
          actual: actual.frames[i],
          expected: expected.frames[i],
          channelTolerance: channelTolerance,
        ),
      );
    }

    return MotionClipComparison._(
      actualFrameCount: actual.frameCount,
      expectedFrameCount: expected.frameCount,
      actualWidth: actual.width,
      actualHeight: actual.height,
      expectedWidth: expected.width,
      expectedHeight: expected.height,
      actualDuration: actual.duration,
      expectedDuration: expected.duration,
      durationTolerance: durationTolerance,
      maxMismatchedPixelRatio: maxMismatchedPixelRatio,
      frames: List<MotionFrameComparison>.unmodifiable(frames),
    );
  }

  /// Frame count in the actual clip.
  final int actualFrameCount;

  /// Frame count in the expected clip.
  final int expectedFrameCount;

  /// Actual clip width.
  final int actualWidth;

  /// Actual clip height.
  final int actualHeight;

  /// Expected clip width.
  final int expectedWidth;

  /// Expected clip height.
  final int expectedHeight;

  /// Actual total duration.
  final Duration actualDuration;

  /// Expected total duration.
  final Duration expectedDuration;

  /// Allowed total and per-frame duration delta.
  final Duration durationTolerance;

  /// Allowed mismatched-pixel ratio per compared frame.
  final double maxMismatchedPixelRatio;

  /// Per-frame comparison results for shared frame indexes.
  final List<MotionFrameComparison> frames;

  /// Whether the compared clips use the same dimensions.
  bool get dimensionsMatch {
    return actualWidth == expectedWidth && actualHeight == expectedHeight;
  }

  /// Whether the compared clips have the same frame count.
  bool get frameCountMatch => actualFrameCount == expectedFrameCount;

  /// Absolute total duration delta.
  Duration get durationDelta {
    return _durationDelta(actualDuration, expectedDuration);
  }

  /// Whether total duration is within [durationTolerance].
  bool get durationMatches => durationDelta <= durationTolerance;

  /// Number of compared pixels that exceeded the channel tolerance.
  int get mismatchedPixels {
    var total = 0;
    for (final frame in frames) {
      total += frame.mismatchedPixels;
    }
    return total;
  }

  /// Number of compared pixels.
  int get totalPixels {
    var total = 0;
    for (final frame in frames) {
      total += frame.totalPixels;
    }
    return total;
  }

  /// Overall mismatched-pixel ratio across compared frames.
  double get mismatchedPixelRatio {
    final pixels = totalPixels;
    return pixels == 0 ? 0 : mismatchedPixels / pixels;
  }

  /// Largest channel delta found across compared frames.
  int get maxChannelDelta {
    var maxDelta = 0;
    for (final frame in frames) {
      maxDelta = math.max(maxDelta, frame.maxChannelDelta);
    }
    return maxDelta;
  }

  /// Largest frame-duration delta found across compared frames.
  Duration get maxFrameDurationDelta {
    var maxDelta = Duration.zero;
    for (final frame in frames) {
      if (frame.durationDelta > maxDelta) {
        maxDelta = frame.durationDelta;
      }
    }
    return maxDelta;
  }

  /// Whether every compared frame duration is within [durationTolerance].
  bool get frameDurationsMatch => maxFrameDurationDelta <= durationTolerance;

  /// Whether every compared frame's pixels are within configured tolerances.
  bool get framePixelsMatch {
    for (final frame in frames) {
      if (frame.mismatchedPixelRatio > maxMismatchedPixelRatio) {
        return false;
      }
    }
    return true;
  }

  /// Whether every compared frame is within pixel and duration tolerances.
  bool get framesMatch => frameDurationsMatch && framePixelsMatch;

  /// Whether the clips match all configured tolerances.
  bool get isMatch {
    return dimensionsMatch && frameCountMatch && durationMatches && framesMatch;
  }

  /// Compact report suitable for test failure output.
  String get summary {
    if (isMatch) {
      return 'clips match: $actualFrameCount frames, '
          '${actualWidth}x$actualHeight, ${actualDuration.inMicroseconds}us';
    }

    final failures = <String>[];
    if (!dimensionsMatch) {
      failures.add(
        'size ${actualWidth}x$actualHeight != '
        '${expectedWidth}x$expectedHeight',
      );
    }
    if (!frameCountMatch) {
      failures.add('frames $actualFrameCount != $expectedFrameCount');
    }
    if (!durationMatches) {
      failures.add(
        'duration delta ${durationDelta.inMicroseconds}us '
        '> ${durationTolerance.inMicroseconds}us',
      );
    }
    if (!frameDurationsMatch) {
      final first = firstFrameDurationMismatch;
      failures.add(
        'frame duration delta ${maxFrameDurationDelta.inMicroseconds}us '
        '> ${durationTolerance.inMicroseconds}us'
        '${first == null ? '' : ', first $first'}',
      );
    }
    if (!framePixelsMatch) {
      final first = firstPixelMismatch;
      failures.add(
        '$mismatchedPixels/$totalPixels pixels differ, '
        'max channel delta $maxChannelDelta'
        '${first == null ? '' : ', first $first'}',
      );
    }
    return 'clips differ: ${failures.join(', ')}';
  }

  /// First pixel mismatch across compared frames, formatted for test output.
  String? get firstPixelMismatch {
    for (final frame in frames) {
      final mismatch = frame.firstPixelMismatch;
      if (mismatch != null) {
        return 'frame ${frame.index} $mismatch';
      }
    }
    return null;
  }

  /// First frame-duration mismatch across compared frames.
  String? get firstFrameDurationMismatch {
    for (final frame in frames) {
      if (frame.durationDelta > durationTolerance) {
        return 'frame ${frame.index} actual '
            '${frame.actualDuration.inMicroseconds}us != expected '
            '${frame.expectedDuration.inMicroseconds}us '
            '(delta ${frame.durationDelta.inMicroseconds}us)';
      }
    }
    return null;
  }

  /// Throws when [isMatch] is false.
  void throwIfMismatch({String? description}) {
    if (!isMatch) {
      throw MotionClipComparisonException(this, description: description);
    }
  }
}

/// Per-frame pixel and duration comparison result.
class MotionFrameComparison {
  const MotionFrameComparison._({
    required this.index,
    required this.totalPixels,
    required this.mismatchedPixels,
    required this.maxChannelDelta,
    required this.actualDuration,
    required this.expectedDuration,
    required this.firstPixelMismatch,
  });

  /// Compares two same-index frames.
  factory MotionFrameComparison.compare({
    required int index,
    required MotionFrame actual,
    required MotionFrame expected,
    required int channelTolerance,
  }) {
    if (actual.width != expected.width || actual.height != expected.height) {
      return MotionFrameComparison._(
        index: index,
        totalPixels: math.max(
          actual.width * actual.height,
          expected.width * expected.height,
        ),
        mismatchedPixels: math.max(
          actual.width * actual.height,
          expected.width * expected.height,
        ),
        maxChannelDelta: 255,
        actualDuration: actual.duration,
        expectedDuration: expected.duration,
        firstPixelMismatch: null,
      );
    }

    var mismatchedPixels = 0;
    var maxChannelDelta = 0;
    String? firstPixelMismatch;
    final actualBytes = actual.rgbaBytes;
    final expectedBytes = expected.rgbaBytes;
    if (channelTolerance == 0 &&
        _rgbaBytesExactlyEqual(actualBytes, expectedBytes)) {
      return MotionFrameComparison._(
        index: index,
        totalPixels: actual.width * actual.height,
        mismatchedPixels: 0,
        maxChannelDelta: 0,
        actualDuration: actual.duration,
        expectedDuration: expected.duration,
        firstPixelMismatch: null,
      );
    }

    for (var i = 0; i < actualBytes.lengthInBytes; i += 4) {
      var pixelMismatch = false;
      for (var channel = 0; channel < 4; channel++) {
        final delta = (actualBytes[i + channel] - expectedBytes[i + channel])
            .abs();
        maxChannelDelta = math.max(maxChannelDelta, delta);
        if (delta > channelTolerance) {
          pixelMismatch = true;
          firstPixelMismatch ??= _pixelMismatchSummary(
            offset: i,
            width: actual.width,
            channel: channel,
            actual: actualBytes[i + channel],
            expected: expectedBytes[i + channel],
            delta: delta,
          );
        }
      }
      if (pixelMismatch) {
        mismatchedPixels++;
      }
    }

    return MotionFrameComparison._(
      index: index,
      totalPixels: actual.width * actual.height,
      mismatchedPixels: mismatchedPixels,
      maxChannelDelta: maxChannelDelta,
      actualDuration: actual.duration,
      expectedDuration: expected.duration,
      firstPixelMismatch: firstPixelMismatch,
    );
  }

  /// Frame index.
  final int index;

  /// Pixels compared in this frame.
  final int totalPixels;

  /// Pixels with at least one channel above tolerance.
  final int mismatchedPixels;

  /// Largest absolute channel delta in this frame.
  final int maxChannelDelta;

  /// Actual frame duration.
  final Duration actualDuration;

  /// Expected frame duration.
  final Duration expectedDuration;

  /// First channel-level pixel mismatch in this frame.
  final String? firstPixelMismatch;

  /// Absolute frame duration delta.
  Duration get durationDelta {
    return _durationDelta(actualDuration, expectedDuration);
  }

  /// Mismatched-pixel ratio for this frame.
  double get mismatchedPixelRatio {
    return totalPixels == 0 ? 0 : mismatchedPixels / totalPixels;
  }
}

String _pixelMismatchSummary({
  required int offset,
  required int width,
  required int channel,
  required int actual,
  required int expected,
  required int delta,
}) {
  final pixel = offset ~/ 4;
  final x = pixel % width;
  final y = pixel ~/ width;
  final channelName = const <String>['r', 'g', 'b', 'a'][channel];
  return 'pixel $x,$y $channelName actual $actual != expected $expected '
      '(delta $delta)';
}

bool _rgbaBytesExactlyEqual(Uint8List a, Uint8List b) {
  if (a.lengthInBytes != b.lengthInBytes) {
    return false;
  }

  final canUsePixelView = a.offsetInBytes % 4 == 0 && b.offsetInBytes % 4 == 0;
  if (canUsePixelView) {
    final pixels = Uint32List.view(
      a.buffer,
      a.offsetInBytes,
      a.lengthInBytes ~/ 4,
    );
    final expectedPixels = Uint32List.view(
      b.buffer,
      b.offsetInBytes,
      b.lengthInBytes ~/ 4,
    );
    for (var i = 0; i < pixels.length; i++) {
      if (pixels[i] != expectedPixels[i]) {
        return false;
      }
    }
    return true;
  }

  for (var i = 0; i < a.lengthInBytes; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// Thrown by [MotionClipComparison.throwIfMismatch].
class MotionClipComparisonException implements Exception {
  /// Creates a clip comparison exception.
  const MotionClipComparisonException(this.comparison, {this.description});

  /// Comparison that failed.
  final MotionClipComparison comparison;

  /// Optional caller-supplied context.
  final String? description;

  @override
  String toString() {
    final prefix = description;
    if (prefix == null || prefix.isEmpty) {
      return 'MotionClipComparisonException: ${comparison.summary}';
    }
    return 'MotionClipComparisonException: $prefix: ${comparison.summary}';
  }
}

Future<MotionClip> _recordCanvasRaw({
  required Size size,
  required Duration duration,
  required int framesPerSecond,
  required double pixelRatio,
  required MotionCanvasPainter paint,
}) {
  return MotionCanvasRecorder(
    size: size,
    duration: duration,
    framesPerSecond: framesPerSecond,
    pixelRatio: pixelRatio,
  ).record(paint);
}

MotionCaptureDiagnostics _deterministicCanvasDiagnostics({
  required MotionClip clip,
  required int framesPerSecond,
  required double pixelRatio,
}) {
  return MotionCaptureDiagnostics(
    targetFramesPerSecond: framesPerSecond,
    pixelRatio: pixelRatio,
    captureElapsed: clip.duration,
    requestedFrames: clip.frameCount,
    capturedFrames: clip.frameCount,
    keptFrames: clip.frameCount,
    skippedFrames: 0,
    collapsedFrames: 0,
    width: clip.width,
    height: clip.height,
    sampledBytes: clip.rawBytes,
    retainedBytes: clip.rawBytes,
    totalCaptureTime: Duration.zero,
    totalFrameWaitTime: Duration.zero,
    totalToImageTime: Duration.zero,
    totalToByteDataTime: Duration.zero,
    totalStoreTime: Duration.zero,
    maxCaptureTime: Duration.zero,
    maxFrameWaitTime: Duration.zero,
    maxToImageTime: Duration.zero,
    maxToByteDataTime: Duration.zero,
    maxStoreTime: Duration.zero,
  );
}

Duration _durationDelta(Duration left, Duration right) {
  return Duration(microseconds: (left - right).inMicroseconds.abs());
}
