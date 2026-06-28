part of '../motion_exporter.dart';

/// High-level quality state derived from [MotionCaptureDiagnostics].
enum MotionCaptureQualityStatus {
  /// Capture reached the requested sampled FPS and had no skipped samples.
  clean('clean capture'),

  /// Capture had skipped samples because readback could not keep up.
  backpressure('backpressure'),

  /// Capture had no skipped samples, but sampled FPS stayed below target.
  belowTargetFrameRate('below target');

  const MotionCaptureQualityStatus(this.label);

  /// Short developer-facing label for diagnostics chips and logs.
  final String label;
}

/// Immutable performance snapshot for the current or last capture session.
class MotionCaptureDiagnostics {
  /// Creates a capture diagnostics snapshot.
  const MotionCaptureDiagnostics({
    required this.targetFramesPerSecond,
    required this.pixelRatio,
    required this.captureElapsed,
    required this.requestedFrames,
    required this.capturedFrames,
    required this.keptFrames,
    required this.skippedFrames,
    required this.collapsedFrames,
    required this.width,
    required this.height,
    required this.sampledBytes,
    required this.retainedBytes,
    required this.totalCaptureTime,
    required this.totalFrameWaitTime,
    required this.totalToImageTime,
    required this.totalToByteDataTime,
    required this.totalStoreTime,
    required this.maxCaptureTime,
    required this.maxFrameWaitTime,
    required this.maxToImageTime,
    required this.maxToByteDataTime,
    required this.maxStoreTime,
  });

  /// Requested recorder frame rate.
  final int targetFramesPerSecond;

  /// Pixel ratio used for [RenderRepaintBoundary.toImage].
  final double pixelRatio;

  /// Elapsed wall-clock time for the capture session.
  final Duration captureElapsed;

  /// Number of capture requests made by the ticker or by manual calls.
  final int requestedFrames;

  /// Number of Flutter frames read back into RGBA bytes.
  final int capturedFrames;

  /// Number of frames retained in the final clip after duplicate collapse.
  final int keptFrames;

  /// Number of capture requests skipped because a previous readback was busy.
  final int skippedFrames;

  /// Number of captured frames removed or merged before the final export.
  final int collapsedFrames;

  /// Captured frame width in physical pixels.
  final int width;

  /// Captured frame height in physical pixels.
  final int height;

  /// Total RGBA bytes sampled from Flutter.
  final int sampledBytes;

  /// RGBA bytes retained by the current clip.
  final int retainedBytes;

  /// Total time spent in a full capture request.
  final Duration totalCaptureTime;

  /// Total time spent waiting for Flutter's end-of-frame boundary.
  final Duration totalFrameWaitTime;

  /// Total time spent in [RenderRepaintBoundary.toImage].
  final Duration totalToImageTime;

  /// Total time spent in [ui.Image.toByteData].
  final Duration totalToByteDataTime;

  /// Total time spent copying and storing RGBA bytes.
  final Duration totalStoreTime;

  /// Slowest full capture request.
  final Duration maxCaptureTime;

  /// Slowest end-of-frame wait.
  final Duration maxFrameWaitTime;

  /// Slowest [RenderRepaintBoundary.toImage] call.
  final Duration maxToImageTime;

  /// Slowest [ui.Image.toByteData] call.
  final Duration maxToByteDataTime;

  /// Slowest RGBA copy/store step.
  final Duration maxStoreTime;

  /// Effective sampled FPS for the elapsed capture window.
  double get effectiveCapturedFps {
    final micros = captureElapsed.inMicroseconds;
    if (micros <= 0) {
      return 0;
    }
    return capturedFrames * Duration.microsecondsPerSecond / micros;
  }

  /// Ratio of skipped requests among requested frames.
  double get skippedFrameRatio {
    if (requestedFrames <= 0) {
      return 0;
    }
    return skippedFrames / requestedFrames;
  }

  /// Ratio of actual sampled FPS to the requested frame rate.
  double get targetFrameRateRatio {
    if (targetFramesPerSecond <= 0) {
      return 0;
    }
    return effectiveCapturedFps / targetFramesPerSecond;
  }

  /// Whether any capture request was skipped because readback was saturated.
  bool get hasSkippedFrames => skippedFrames > 0;

  /// Whether duplicate-frame collapse merged any captured frames.
  bool get hasCollapsedFrames => collapsedFrames > 0;

  /// High-level capture quality state.
  ///
  /// `backpressure` takes priority over `belowTargetFrameRate` because skipped
  /// samples mean Flutter readback was saturated. A live 120 fps target on a
  /// 60 Hz window usually reports `belowTargetFrameRate` instead.
  MotionCaptureQualityStatus get qualityStatus {
    if (hasSkippedFrames) {
      return MotionCaptureQualityStatus.backpressure;
    }
    if (!isNearTargetFrameRate) {
      return MotionCaptureQualityStatus.belowTargetFrameRate;
    }
    return MotionCaptureQualityStatus.clean;
  }

  /// Whether sampled FPS is close to the requested frame rate.
  ///
  /// Live widget capture is synchronized with Flutter frames. A 120 fps target
  /// on a 60 Hz window can be backpressure-free but still not near target.
  bool get isNearTargetFrameRate => targetFrameRateRatio >= 0.95;

  /// Whether the capture avoided backpressure skips and stayed near target FPS.
  bool get isCleanCapture => qualityStatus == MotionCaptureQualityStatus.clean;

  /// Compact developer-facing quality summary for logs and error messages.
  String get qualitySummary {
    return '${qualityStatus.label}: capture '
        '${_formatDiagnosticsFps(effectiveCapturedFps)} / '
        'target $targetFramesPerSecond fps, '
        '$skippedFrames skipped (${_formatDiagnosticsPercent(skippedFrameRatio)}), '
        '$capturedFrames captured / $keptFrames kept';
  }

  /// Average full capture request time.
  Duration get averageCaptureTime {
    return _averageDuration(totalCaptureTime, capturedFrames);
  }

  /// Average end-of-frame wait time.
  Duration get averageFrameWaitTime {
    return _averageDuration(totalFrameWaitTime, capturedFrames);
  }

  /// Average [RenderRepaintBoundary.toImage] time.
  Duration get averageToImageTime {
    return _averageDuration(totalToImageTime, capturedFrames);
  }

  /// Average [ui.Image.toByteData] time.
  Duration get averageToByteDataTime {
    return _averageDuration(totalToByteDataTime, capturedFrames);
  }

  /// Average RGBA copy/store time.
  Duration get averageStoreTime {
    return _averageDuration(totalStoreTime, capturedFrames);
  }

  /// Total sampled RGBA bytes as mebibytes.
  double get sampledMebibytes => sampledBytes / (1024 * 1024);

  /// Retained RGBA bytes as mebibytes.
  double get retainedMebibytes => retainedBytes / (1024 * 1024);

  /// Returns diagnostics whose final clip counters match [clip].
  ///
  /// Capture timings and skipped-frame counters remain unchanged. Final counters
  /// such as [keptFrames], [collapsedFrames], and [retainedBytes] are updated so
  /// an export-time [MotionClipTransform] is reflected in the result.
  MotionCaptureDiagnostics forClip(MotionClip clip) {
    return copyWith(
      keptFrames: clip.frameCount,
      collapsedFrames: math.max(0, capturedFrames - clip.frameCount),
      retainedBytes: clip.rawBytes,
    );
  }

  /// Returns a diagnostics snapshot with selected fields replaced.
  MotionCaptureDiagnostics copyWith({
    int? targetFramesPerSecond,
    double? pixelRatio,
    Duration? captureElapsed,
    int? requestedFrames,
    int? capturedFrames,
    int? keptFrames,
    int? skippedFrames,
    int? collapsedFrames,
    int? width,
    int? height,
    int? sampledBytes,
    int? retainedBytes,
    Duration? totalCaptureTime,
    Duration? totalFrameWaitTime,
    Duration? totalToImageTime,
    Duration? totalToByteDataTime,
    Duration? totalStoreTime,
    Duration? maxCaptureTime,
    Duration? maxFrameWaitTime,
    Duration? maxToImageTime,
    Duration? maxToByteDataTime,
    Duration? maxStoreTime,
  }) {
    return MotionCaptureDiagnostics(
      targetFramesPerSecond:
          targetFramesPerSecond ?? this.targetFramesPerSecond,
      pixelRatio: pixelRatio ?? this.pixelRatio,
      captureElapsed: captureElapsed ?? this.captureElapsed,
      requestedFrames: requestedFrames ?? this.requestedFrames,
      capturedFrames: capturedFrames ?? this.capturedFrames,
      keptFrames: keptFrames ?? this.keptFrames,
      skippedFrames: skippedFrames ?? this.skippedFrames,
      collapsedFrames: collapsedFrames ?? this.collapsedFrames,
      width: width ?? this.width,
      height: height ?? this.height,
      sampledBytes: sampledBytes ?? this.sampledBytes,
      retainedBytes: retainedBytes ?? this.retainedBytes,
      totalCaptureTime: totalCaptureTime ?? this.totalCaptureTime,
      totalFrameWaitTime: totalFrameWaitTime ?? this.totalFrameWaitTime,
      totalToImageTime: totalToImageTime ?? this.totalToImageTime,
      totalToByteDataTime: totalToByteDataTime ?? this.totalToByteDataTime,
      totalStoreTime: totalStoreTime ?? this.totalStoreTime,
      maxCaptureTime: maxCaptureTime ?? this.maxCaptureTime,
      maxFrameWaitTime: maxFrameWaitTime ?? this.maxFrameWaitTime,
      maxToImageTime: maxToImageTime ?? this.maxToImageTime,
      maxToByteDataTime: maxToByteDataTime ?? this.maxToByteDataTime,
      maxStoreTime: maxStoreTime ?? this.maxStoreTime,
    );
  }
}

String _formatDiagnosticsFps(double fps) {
  return fps >= 10 ? fps.toStringAsFixed(0) : fps.toStringAsFixed(1);
}

String _formatDiagnosticsPercent(double ratio) {
  return '${(ratio * 100).toStringAsFixed(0)}%';
}

/// Controls a [MotionRecorder] widget.
class MotionRecorderController extends ChangeNotifier {
  _MotionRecorderState? _state;
  bool _isRecording = false;
  bool _isEncoding = false;
  int _frameCount = 0;
  Object? _lastError;
  MotionCaptureDiagnostics? _diagnostics;

  /// Whether frames are currently being captured.
  bool get isRecording => _isRecording;

  /// Whether captured frames are currently being encoded into export bytes.
  bool get isEncoding => _isEncoding;

  /// Number of captured frames kept for encoding.
  ///
  /// When duplicate-frame collapsing is enabled, this may be lower than the
  /// number of sampled Flutter frames.
  int get frameCount => _frameCount;

  /// Last asynchronous capture error, if recording stopped because of one.
  Object? get lastError => _lastError;

  /// Performance diagnostics for the current or last capture session.
  MotionCaptureDiagnostics? get diagnostics => _diagnostics;

  /// Registers [listener] for capture and encoding status changes.
  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
  }

  /// Removes a status [listener].
  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
  }

  /// Releases listener resources held by this controller.
  @override
  void dispose() {
    super.dispose();
  }

  /// Starts capturing frames from the attached [MotionRecorder].
  Future<void> start({
    MotionRecorderOptions options = const MotionRecorderOptions(),
  }) {
    return _requireState()._start(options);
  }

  /// Captures one frame immediately.
  ///
  /// This is useful for deterministic tests or externally driven animation
  /// timelines. The controller must already be recording.
  Future<void> captureFrame() {
    return _requireState()._captureFrame();
  }

  /// Stops recording and returns the encoded animated WebP.
  ///
  /// Prefer [stopCapture] or [stopExport] for format-neutral workflows.
  Future<MotionRecording> stopWebp() {
    return _requireState()._stop();
  }

  /// Legacy shorthand for [stopWebp].
  Future<MotionRecording> stop() {
    return stopWebp();
  }

  /// Stops recording and returns an encoded motion export.
  ///
  /// Use [encoder] to choose APNG/WebP options and capture quality policy. Use
  /// [clipTransform] for final clip edits such as
  /// [MotionClip.withoutDuplicateLoopClosure] before encoding.
  Future<MotionExportResult> stopExport({
    MotionClipEncoder encoder = const MotionClipEncoder(),
    MotionClipTransform? clipTransform,
  }) async {
    final capturedClip = await stopCapture();
    final exportClip = clipTransform == null
        ? capturedClip
        : clipTransform(capturedClip);
    final exportDiagnostics = diagnostics?.forClip(exportClip);
    _setStatus(isEncoding: true);
    try {
      return await encoder.encode(exportClip, diagnostics: exportDiagnostics);
    } finally {
      _setStatus(isEncoding: false, diagnostics: exportDiagnostics);
    }
  }

  /// Records the next complete logical loop and returns a raw clip.
  ///
  /// The recorder waits for the next [loopSignal] boundary, starts capture,
  /// waits for the following boundary, then stops. The animated
  /// widget keeps its own clock; this method only uses semantic boundary
  /// events emitted by that widget.
  ///
  /// A terminal duplicate of the first frame is removed when present. Pass
  /// [loopDuration] when the animation has a known semantic duration and the
  /// clip frame durations should be normalized to that exact loop clock. Pass
  /// [boundaryTimeout] when a missing boundary should fail instead of leaving a
  /// pending future; if the timeout happens after capture starts, the active
  /// recording is cancelled before the error is rethrown.
  ///
  /// Pass [cancelSignal] when a UI cancel action should abort either the
  /// initial boundary wait or the active loop capture. [onCaptureStarted] is
  /// called after the first boundary is observed and recording has started.
  Future<MotionClip> recordNextLoopClip({
    required MotionLoopSignal loopSignal,
    MotionRecorderOptions options = const MotionRecorderOptions(),
    Duration? loopDuration,
    Duration? boundaryTimeout,
    Future<void>? cancelSignal,
    FutureOr<void> Function(int boundaryCount)? onCaptureStarted,
    int duplicateLoopClosureTolerance = 8,
    MotionClipTransform? clipTransform,
  }) async {
    if (isRecording) {
      throw StateError('Motion recording is already active.');
    }

    final startBoundary = await loopSignal.waitForNextBoundary(
      timeout: boundaryTimeout,
      cancelSignal: cancelSignal,
    );
    await start(options: options);
    try {
      await onCaptureStarted?.call(startBoundary);
      await loopSignal.waitForNextBoundary(
        afterCount: startBoundary,
        timeout: boundaryTimeout,
        cancelSignal: cancelSignal,
      );
    } catch (_) {
      if (isRecording) {
        await cancel();
      }
      rethrow;
    }
    var loopClip = (await stopCapture()).withoutDuplicateLoopClosure(
      channelTolerance: duplicateLoopClosureTolerance,
    );
    if (loopDuration != null) {
      loopClip = loopClip.withDuration(loopDuration);
    }
    return clipTransform == null ? loopClip : clipTransform(loopClip);
  }

  /// Records the next complete logical loop and returns an encoded export.
  ///
  /// Use [recordNextLoopClip] when a golden test should compare raw RGBA
  /// frames before any APNG/WebP encoding.
  Future<MotionExportResult> recordNextLoop({
    required MotionLoopSignal loopSignal,
    MotionRecorderOptions options = const MotionRecorderOptions(),
    MotionClipEncoder encoder = const MotionClipEncoder(),
    Duration? loopDuration,
    Duration? boundaryTimeout,
    Future<void>? cancelSignal,
    FutureOr<void> Function(int boundaryCount)? onCaptureStarted,
    int duplicateLoopClosureTolerance = 8,
    MotionClipTransform? clipTransform,
  }) async {
    final clip = await recordNextLoopClip(
      loopSignal: loopSignal,
      options: options,
      loopDuration: loopDuration,
      boundaryTimeout: boundaryTimeout,
      cancelSignal: cancelSignal,
      onCaptureStarted: onCaptureStarted,
      duplicateLoopClosureTolerance: duplicateLoopClosureTolerance,
      clipTransform: clipTransform,
    );
    final exportDiagnostics = diagnostics?.forClip(clip);
    _setStatus(isEncoding: true);
    try {
      return await encoder.encode(clip, diagnostics: exportDiagnostics);
    } finally {
      _setStatus(isEncoding: false, diagnostics: exportDiagnostics);
    }
  }

  /// Stops recording and returns raw RGBA frames without encoding them.
  ///
  /// Use this when exporting the same capture to another encoder or plugin.
  Future<MotionClip> stopCapture() {
    return _requireState()._stopCapture();
  }

  /// Stops recording and drops all captured frames.
  Future<void> cancel() {
    return _requireState()._cancel();
  }

  void _attach(_MotionRecorderState state) {
    if (_state != null && _state != state) {
      throw StateError('This MotionRecorderController is already attached.');
    }
    _state = state;
  }

  void _detach(_MotionRecorderState state) {
    if (_state == state) {
      _state = null;
    }
  }

  _MotionRecorderState _requireState() {
    final state = _state;
    if (state == null) {
      throw StateError(
        'MotionRecorderController is not attached to a MotionRecorder widget.',
      );
    }
    return state;
  }

  void _setStatus({
    bool? isRecording,
    bool? isEncoding,
    int? frameCount,
    Object? lastError,
    MotionCaptureDiagnostics? diagnostics,
    bool clearError = false,
    bool clearDiagnostics = false,
  }) {
    var changed = false;

    if (isRecording != null && isRecording != _isRecording) {
      _isRecording = isRecording;
      changed = true;
    }
    if (isEncoding != null && isEncoding != _isEncoding) {
      _isEncoding = isEncoding;
      changed = true;
    }
    if (frameCount != null && frameCount != _frameCount) {
      _frameCount = frameCount;
      changed = true;
    }
    if (clearError && _lastError != null) {
      _lastError = null;
      changed = true;
    } else if (lastError != null && lastError != _lastError) {
      _lastError = lastError;
      changed = true;
    }
    if (clearDiagnostics && _diagnostics != null) {
      _diagnostics = null;
      changed = true;
    } else if (diagnostics != null && diagnostics != _diagnostics) {
      _diagnostics = diagnostics;
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }
}

Duration _averageDuration(Duration total, int count) {
  if (count <= 0) {
    return Duration.zero;
  }
  return Duration(microseconds: total.inMicroseconds ~/ count);
}
