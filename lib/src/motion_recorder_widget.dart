part of '../motion_exporter.dart';

/// Wraps a widget subtree and captures raw frames for motion export.
class MotionRecorder extends StatefulWidget {
  /// Creates a recorder around [child].
  const MotionRecorder({
    required this.controller,
    required this.child,
    super.key,
  });

  /// Controller used to start and stop recording.
  final MotionRecorderController controller;

  /// Widget subtree to capture.
  ///
  /// Transparent pixels are preserved as long as the child paints transparent
  /// output inside this repaint boundary.
  final Widget child;

  @override
  State<MotionRecorder> createState() => _MotionRecorderState();
}

class _MotionRecorderState extends State<MotionRecorder>
    with SingleTickerProviderStateMixin {
  final GlobalKey _boundaryKey = GlobalKey();
  final List<_CapturedFrame> _frames = <_CapturedFrame>[];

  Ticker? _ticker;
  MotionRecorderOptions? _options;
  _CaptureDiagnosticsBuilder? _diagnosticsBuilder;
  Duration _nextCaptureAt = Duration.zero;
  final Set<Future<void>> _captureFutures = <Future<void>>{};
  Future<void>? _frameBoundaryFuture;
  var _nextCaptureTaskId = 0;
  var _pendingFrameBytes = 0;
  int? _frameBoundaryTaskId;
  var _sessionActive = false;
  var _sessionId = 0;

  @override
  void initState() {
    super.initState();
    widget.controller._attach(this);
  }

  @override
  void didUpdateWidget(MotionRecorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._detach(this);
      widget.controller._attach(this);
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    widget.controller._detach(this);
    super.dispose();
  }

  Future<void> _start(MotionRecorderOptions options) async {
    if (_sessionActive) {
      throw StateError('Motion recording is already active.');
    }
    _validateMotionRecorderOptions(options);

    _sessionId++;
    _sessionActive = true;
    _options = options;
    _diagnosticsBuilder = _CaptureDiagnosticsBuilder(options)..start();
    _frames.clear();
    _pendingFrameBytes = 0;
    _captureFutures.clear();
    _frameBoundaryFuture = null;
    _frameBoundaryTaskId = null;
    _nextCaptureAt = Duration.zero;

    widget.controller._setStatus(
      isRecording: true,
      isEncoding: false,
      frameCount: 0,
      clearError: true,
      clearDiagnostics: true,
    );

    _ticker ??= createTicker(_onTick);
    _ticker!.start();
  }

  Future<MotionRecording> _stop() async {
    final options = _options;
    if (!_sessionActive || options == null) {
      throw StateError('Motion recording is not active.');
    }

    final clip = await _collectClip();
    final captureDiagnostics = widget.controller.diagnostics;

    widget.controller._setStatus(isEncoding: true);
    try {
      final job = _EncodeJob(
        frames: clip.frames,
        loopCount: options.loopCount,
        backgroundArgb: _colorToArgb32(options.backgroundColor),
        frameBlend: options.frameBlend,
        frameDispose: options.frameDispose,
        trimTransparentFrames: options.trimTransparentFrames,
        trimChangedFrames: options.trimChangedFrames,
      );
      final bytes = options.useBackgroundIsolate
          ? await compute(_encodeWebpAnimation, job, debugLabel: 'webp_encode')
          : _encodeWebpAnimation(job);

      return MotionRecording(
        bytes: bytes,
        frameCount: clip.frameCount,
        width: clip.width,
        height: clip.height,
        duration: clip.duration,
        clip: clip,
        diagnostics: captureDiagnostics,
      );
    } finally {
      _finishStoppedSession(isEncoding: false);
    }
  }

  Future<MotionClip> _stopCapture() async {
    if (!_sessionActive || _options == null) {
      throw StateError('Motion recording is not active.');
    }

    final clip = await _collectClip();
    _finishStoppedSession(isEncoding: false);
    return clip;
  }

  Future<MotionClip> _collectClip() async {
    _ticker?.stop();
    widget.controller._setStatus(isRecording: false);

    while (_captureFutures.isNotEmpty) {
      await Future.wait(_captureFutures.toList());
    }

    if (_frames.isEmpty) {
      await _captureFrame();
    }

    final clip = _buildClip();
    _diagnosticsBuilder?.stop();
    _diagnosticsBuilder?.setFinalFrameStats(
      collapsedFrames: _diagnosticsBuilder!.capturedFrames - clip.frameCount,
      retainedBytes: clip.rawBytes,
    );
    _publishDiagnostics(keptFrames: clip.frameCount);

    return clip;
  }

  void _finishStoppedSession({required bool isEncoding}) {
    _diagnosticsBuilder?.stop();
    final diagnostics =
        widget.controller.diagnostics ??
        _diagnosticsBuilder?.snapshot(keptFrames: _frames.length);
    _frames.clear();
    _pendingFrameBytes = 0;
    _options = null;
    _sessionActive = false;
    _diagnosticsBuilder = null;
    widget.controller._setStatus(
      isEncoding: isEncoding,
      frameCount: 0,
      diagnostics: diagnostics,
    );
  }

  Future<void> _cancel() async {
    if (!_sessionActive) {
      return;
    }

    _sessionId++;
    _ticker?.stop();
    _diagnosticsBuilder?.stop();
    final diagnostics = _diagnosticsBuilder?.snapshot(
      keptFrames: _frames.length,
    );
    _frames.clear();
    _pendingFrameBytes = 0;
    _captureFutures.clear();
    _frameBoundaryFuture = null;
    _frameBoundaryTaskId = null;
    _options = null;
    _diagnosticsBuilder = null;
    _sessionActive = false;
    widget.controller._setStatus(
      isRecording: false,
      isEncoding: false,
      frameCount: 0,
      clearError: true,
      diagnostics: diagnostics,
    );
  }

  void _onTick(Duration elapsed) {
    final options = _options;
    if (!_sessionActive || options == null || elapsed < _nextCaptureAt) {
      return;
    }

    _nextCaptureAt = elapsed + options._frameDuration;
    _diagnosticsBuilder?.recordRequestedFrame();
    if (_captureFutures.length >= options.maxPendingCaptures) {
      _diagnosticsBuilder?.recordSkippedFrame();
      _publishDiagnostics();
      return;
    }

    _captureFrame(countRequest: false).catchError((Object error) {
      _ticker?.stop();
      _sessionActive = false;
      widget.controller._setStatus(isRecording: false, lastError: error);
    });
  }

  Future<void> _captureFrame({bool countRequest = true}) {
    if (!_sessionActive) {
      throw StateError('Motion recording is not active.');
    }

    if (countRequest) {
      _diagnosticsBuilder?.recordRequestedFrame();
    }

    final frameBoundaryFuture = _frameBoundaryFuture;
    if (frameBoundaryFuture != null) {
      return frameBoundaryFuture;
    }

    final options = _options;
    if (options == null) {
      return Future<void>.value();
    }

    if (_captureFutures.length >= options.maxPendingCaptures) {
      if (!countRequest) {
        _diagnosticsBuilder?.recordSkippedFrame();
        _publishDiagnostics();
        return Future<void>.value();
      }
      return _waitForCaptureSlot().then(
        (_) => _captureFrame(countRequest: false),
      );
    }

    final sessionId = _sessionId;
    final taskId = ++_nextCaptureTaskId;
    final future = _captureFrameNow(sessionId, taskId);
    _frameBoundaryFuture = future;
    _frameBoundaryTaskId = taskId;
    _captureFutures.add(future);
    future.whenComplete(() {
      _captureFutures.remove(future);
      if (identical(_frameBoundaryFuture, future)) {
        _frameBoundaryFuture = null;
        _frameBoundaryTaskId = null;
      }
    });
    return future;
  }

  Future<void> _waitForCaptureSlot() async {
    while (_captureFutures.isNotEmpty) {
      await Future.any(_captureFutures.toList());
      final options = _options;
      if (!_sessionActive ||
          options == null ||
          _captureFutures.length < options.maxPendingCaptures) {
        return;
      }
    }
  }

  Future<void> _captureFrameNow(int sessionId, int taskId) async {
    final options = _options;
    if (options == null) {
      return;
    }

    final captureWatch = Stopwatch()..start();
    final frameWaitWatch = Stopwatch()..start();
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    frameWaitWatch.stop();
    final capturedAt = _diagnosticsBuilder?.elapsed ?? captureWatch.elapsed;
    if (_frameBoundaryTaskId == taskId) {
      _frameBoundaryFuture = null;
      _frameBoundaryTaskId = null;
    }

    if (!_sessionActive || sessionId != _sessionId) {
      return;
    }

    final renderObject = _boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw StateError(
        'MotionRecorder child is not attached to a repaint boundary.',
      );
    }
    if (!renderObject.hasSize || renderObject.size.isEmpty) {
      throw StateError('MotionRecorder child has no paint size.');
    }

    final toImageWatch = Stopwatch()..start();
    final image = await renderObject.toImage(pixelRatio: options.pixelRatio);
    toImageWatch.stop();
    try {
      if (!_sessionActive || sessionId != _sessionId) {
        return;
      }

      final toByteDataWatch = Stopwatch()..start();
      final bytes = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      toByteDataWatch.stop();
      if (!_sessionActive || sessionId != _sessionId) {
        return;
      }
      if (bytes == null) {
        throw StateError(
          'Flutter returned no RGBA bytes for the captured frame.',
        );
      }

      final rgba = Uint8List.sublistView(bytes);
      final storeWatch = Stopwatch()..start();
      _addCapturedFrame(
        rgba,
        width: image.width,
        height: image.height,
        capturedAt: capturedAt,
        options: options,
      );
      storeWatch.stop();
      captureWatch.stop();
      _diagnosticsBuilder?.recordCapturedFrame(
        width: image.width,
        height: image.height,
        frameBytes: rgba.lengthInBytes,
        retainedBytes: _pendingFrameBytes,
        captureTime: captureWatch.elapsed,
        frameWaitTime: frameWaitWatch.elapsed,
        toImageTime: toImageWatch.elapsed,
        toByteDataTime: toByteDataWatch.elapsed,
        storeTime: storeWatch.elapsed,
      );
      widget.controller._setStatus(
        frameCount: _frames.length,
        diagnostics: _diagnosticsBuilder?.snapshot(keptFrames: _frames.length),
      );
    } finally {
      image.dispose();
    }
  }

  bool _addCapturedFrame(
    Uint8List rgbaBytes, {
    required int width,
    required int height,
    required Duration capturedAt,
    required MotionRecorderOptions options,
  }) {
    final hash = options.collapseIdenticalFrames ? _fnv1a32(rgbaBytes) : null;
    final previous = _frames.isEmpty ? null : _frames.last;
    if (options.collapseIdenticalFrames &&
        previous != null &&
        previous.width == width &&
        previous.height == height &&
        previous.hash == hash &&
        _bytesEqual(previous.rgbaBytes, rgbaBytes)) {
      return false;
    }

    _frames.add(
      _CapturedFrame(
        rgbaBytes: rgbaBytes,
        width: width,
        height: height,
        capturedAt: capturedAt,
        hash: hash,
        duration: Duration.zero,
      ),
    );
    _pendingFrameBytes += rgbaBytes.lengthInBytes;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(key: _boundaryKey, child: widget.child);
  }

  void _publishDiagnostics({int? keptFrames}) {
    widget.controller._setStatus(
      diagnostics: _diagnosticsBuilder?.snapshot(
        keptFrames: keptFrames ?? _frames.length,
      ),
    );
  }

  MotionClip _buildClip() {
    final options = _options;
    if (options == null) {
      throw StateError('Motion recording is not active.');
    }

    final samples = _frames.toList()
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    final frames = <_CapturedFrame>[];
    final stopAt = _diagnosticsBuilder?.elapsed ?? samples.last.capturedAt;

    for (var i = 0; i < samples.length; i++) {
      final sample = samples[i];
      final nextAt = i + 1 < samples.length
          ? samples[i + 1].capturedAt
          : stopAt;
      final frameStart = i == 0 ? Duration.zero : sample.capturedAt;
      final delta = nextAt - frameStart;
      final duration = delta > Duration.zero ? delta : options._frameDuration;
      final sampleHash = options.collapseIdenticalFrames
          ? sample.hash ?? _fnv1a32(sample.rgbaBytes)
          : null;

      final previous = frames.isEmpty ? null : frames.last;
      if (options.collapseIdenticalFrames &&
          previous != null &&
          previous.width == sample.width &&
          previous.height == sample.height &&
          previous.hash == sampleHash &&
          _bytesEqual(previous.rgbaBytes, sample.rgbaBytes)) {
        previous.duration += duration;
      } else {
        frames.add(
          _CapturedFrame(
            rgbaBytes: sample.rgbaBytes,
            width: sample.width,
            height: sample.height,
            capturedAt: sample.capturedAt,
            hash: sampleHash,
            duration: duration,
          ),
        );
      }
    }

    return MotionClip(frames: frames.map((frame) => frame.toFrame()).toList());
  }
}

class _CaptureDiagnosticsBuilder {
  _CaptureDiagnosticsBuilder(this.options);

  final MotionRecorderOptions options;
  final Stopwatch _sessionWatch = Stopwatch();

  Duration get elapsed => _sessionWatch.elapsed;

  var _requestedFrames = 0;
  var _capturedFrames = 0;
  var _skippedFrames = 0;
  var _collapsedFrames = 0;
  var _width = 0;
  var _height = 0;
  var _sampledBytes = 0;
  var _retainedBytes = 0;
  var _totalCaptureTime = Duration.zero;
  var _totalFrameWaitTime = Duration.zero;
  var _totalToImageTime = Duration.zero;
  var _totalToByteDataTime = Duration.zero;
  var _totalStoreTime = Duration.zero;
  var _maxCaptureTime = Duration.zero;
  var _maxFrameWaitTime = Duration.zero;
  var _maxToImageTime = Duration.zero;
  var _maxToByteDataTime = Duration.zero;
  var _maxStoreTime = Duration.zero;

  void start() {
    _sessionWatch
      ..reset()
      ..start();
  }

  void stop() {
    _sessionWatch.stop();
  }

  void recordRequestedFrame() {
    _requestedFrames++;
  }

  void recordSkippedFrame() {
    _skippedFrames++;
  }

  void recordCapturedFrame({
    required int width,
    required int height,
    required int frameBytes,
    required int retainedBytes,
    required Duration captureTime,
    required Duration frameWaitTime,
    required Duration toImageTime,
    required Duration toByteDataTime,
    required Duration storeTime,
  }) {
    _capturedFrames++;
    _width = width;
    _height = height;
    _sampledBytes += frameBytes;
    _retainedBytes = retainedBytes;
    _totalCaptureTime += captureTime;
    _totalFrameWaitTime += frameWaitTime;
    _totalToImageTime += toImageTime;
    _totalToByteDataTime += toByteDataTime;
    _totalStoreTime += storeTime;
    _maxCaptureTime = _maxDuration(_maxCaptureTime, captureTime);
    _maxFrameWaitTime = _maxDuration(_maxFrameWaitTime, frameWaitTime);
    _maxToImageTime = _maxDuration(_maxToImageTime, toImageTime);
    _maxToByteDataTime = _maxDuration(_maxToByteDataTime, toByteDataTime);
    _maxStoreTime = _maxDuration(_maxStoreTime, storeTime);
  }

  int get capturedFrames => _capturedFrames;

  void setFinalFrameStats({
    required int collapsedFrames,
    required int retainedBytes,
  }) {
    _collapsedFrames = collapsedFrames;
    _retainedBytes = retainedBytes;
  }

  MotionCaptureDiagnostics snapshot({required int keptFrames}) {
    return MotionCaptureDiagnostics(
      targetFramesPerSecond: options.framesPerSecond,
      pixelRatio: options.pixelRatio,
      captureElapsed: _sessionWatch.elapsed,
      requestedFrames: _requestedFrames,
      capturedFrames: _capturedFrames,
      keptFrames: keptFrames,
      skippedFrames: _skippedFrames,
      collapsedFrames: math.max(_collapsedFrames, _capturedFrames - keptFrames),
      width: _width,
      height: _height,
      sampledBytes: _sampledBytes,
      retainedBytes: _retainedBytes,
      totalCaptureTime: _totalCaptureTime,
      totalFrameWaitTime: _totalFrameWaitTime,
      totalToImageTime: _totalToImageTime,
      totalToByteDataTime: _totalToByteDataTime,
      totalStoreTime: _totalStoreTime,
      maxCaptureTime: _maxCaptureTime,
      maxFrameWaitTime: _maxFrameWaitTime,
      maxToImageTime: _maxToImageTime,
      maxToByteDataTime: _maxToByteDataTime,
      maxStoreTime: _maxStoreTime,
    );
  }
}

Duration _maxDuration(Duration a, Duration b) {
  return a >= b ? a : b;
}

int _fnv1a32(Uint8List bytes) {
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  return _rgbaBytesExactlyEqual(a, b);
}

bool _bytesSimilar(Uint8List a, Uint8List b, {required int channelTolerance}) {
  if (identical(a, b)) {
    return true;
  }
  if (a.lengthInBytes != b.lengthInBytes) {
    return false;
  }
  if (channelTolerance == 0) {
    return _rgbaBytesExactlyEqual(a, b);
  }
  for (var i = 0; i < a.lengthInBytes; i++) {
    if ((a[i] - b[i]).abs() > channelTolerance) {
      return false;
    }
  }
  return true;
}

Uint8List _premultiplyRgba(Uint8List rgbaBytes) {
  for (var i = 0; i < rgbaBytes.lengthInBytes; i += 4) {
    final alpha = rgbaBytes[i + 3];
    if (alpha == 0) {
      rgbaBytes[i] = 0;
      rgbaBytes[i + 1] = 0;
      rgbaBytes[i + 2] = 0;
    } else if (alpha < 255) {
      rgbaBytes[i] = _premultiplyChannel(rgbaBytes[i], alpha);
      rgbaBytes[i + 1] = _premultiplyChannel(rgbaBytes[i + 1], alpha);
      rgbaBytes[i + 2] = _premultiplyChannel(rgbaBytes[i + 2], alpha);
    }
  }
  return rgbaBytes;
}

int _premultiplyChannel(int straight, int alpha) {
  return ((straight * alpha + 127) ~/ 255).clamp(0, 255);
}
