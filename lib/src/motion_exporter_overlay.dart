part of '../motion_exporter.dart';

/// Position of the developer overlay controls.
enum MotionExporterOverlayPosition {
  /// Top-left corner.
  topLeft,

  /// Top-right corner.
  topRight,

  /// Bottom-left corner.
  bottomLeft,

  /// Bottom-right corner.
  bottomRight,
}

enum _ToolbarSymbol { close, record, stop }

/// Operation that failed inside [MotionExporterOverlay].
enum MotionExporterOverlayErrorPhase {
  /// Starting capture failed.
  start,

  /// Stopping capture or encoding the export failed.
  export,

  /// Cancelling capture failed.
  cancel,
}

/// Error event reported by [MotionExporterOverlay.onError].
class MotionExporterOverlayError {
  /// Creates a typed overlay error event.
  const MotionExporterOverlayError({
    required this.phase,
    required this.error,
    required this.stackTrace,
    required this.format,
    this.diagnostics,
  });

  /// Operation that failed.
  final MotionExporterOverlayErrorPhase phase;

  /// Original thrown error.
  final Object error;

  /// Stack trace captured with [error].
  final StackTrace stackTrace;

  /// Export format selected by the overlay at the time of the error.
  final MotionExportFormat format;

  /// Current or last capture diagnostics, when available.
  final MotionCaptureDiagnostics? diagnostics;

  @override
  String toString() {
    return 'MotionExporterOverlayError($phase, $format): $error';
  }
}

/// A developer overlay for quickly recording a widget subtree to APNG or WebP.
///
/// Wrap your app with this widget in debug builds. The overlay controls are
/// drawn above [child] and are not included in the recording.
class MotionExporterOverlay extends StatefulWidget {
  /// Creates a developer recording overlay.
  const MotionExporterOverlay({
    required this.child,
    super.key,
    this.enabled = !kReleaseMode,
    this.options = const MotionRecorderOptions(),
    this.format = MotionExportFormat.webp,
    this.apngOptions,
    this.webpOptions,
    this.qualityPolicy = const MotionCaptureQualityPolicy(),
    this.validationPolicy = const MotionExportValidationPolicy(),
    this.clipTransform,
    this.position = MotionExporterOverlayPosition.topRight,
    this.onExported,
    this.onError,
  });

  /// The subtree that will be recorded.
  final Widget child;

  /// Whether the overlay should be visible and active.
  final bool enabled;

  /// Recording options used for each export.
  final MotionRecorderOptions options;

  /// Encoded format produced by the overlay.
  final MotionExportFormat format;

  /// APNG encoder options.
  ///
  /// When omitted, the overlay derives loop and frame-trimming settings from
  /// [options].
  final ApngAnimationOptions? apngOptions;

  /// WebP encoder options.
  ///
  /// When omitted, the overlay derives WebP encoding settings from [options].
  final WebpAnimationOptions? webpOptions;

  /// Capture quality policy checked before export encoding.
  final MotionCaptureQualityPolicy qualityPolicy;

  /// Encoded-file validation policy checked after export encoding.
  final MotionExportValidationPolicy validationPolicy;

  /// Optional final clip edit applied before export encoding.
  ///
  /// Use this for loop cleanup such as [MotionClip.withoutDuplicateLoopClosure]
  /// or [MotionClip.withDuration].
  final MotionClipTransform? clipTransform;

  /// Where the floating controls should be placed.
  final MotionExporterOverlayPosition position;

  /// Called after an export completes.
  final FutureOr<void> Function(MotionExportResult result)? onExported;

  /// Called when capture, export, or cancellation fails.
  ///
  /// Callback failures are reported through [FlutterError.reportError] so the
  /// overlay can keep its own UI state consistent.
  final FutureOr<void> Function(MotionExporterOverlayError error)? onError;

  @override
  State<MotionExporterOverlay> createState() => _MotionExporterOverlayState();
}

class _MotionExporterOverlayState extends State<MotionExporterOverlay> {
  final MotionRecorderController _controller = MotionRecorderController();
  MotionExportResult? _lastExport;
  Object? _lastError;
  bool _busy = false;

  @override
  void dispose() {
    if (_controller.isRecording && _controller._state != null) {
      unawaited(_controller.cancel());
    }
    _controller.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy || _controller.isRecording) {
      return;
    }
    setState(() {
      _busy = true;
      _lastExport = null;
      _lastError = null;
    });
    try {
      await _controller.start(options: widget.options);
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _lastError = error);
      }
      await _reportError(
        phase: MotionExporterOverlayErrorPhase.start,
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _stop() async {
    if (_busy || !_controller.isRecording) {
      return;
    }
    setState(() {
      _busy = true;
      _lastError = null;
    });
    try {
      final result = await _controller.stopExport(
        encoder: MotionClipEncoder(
          format: widget.format,
          apngOptions: _effectiveApngOptions(),
          webpOptions: _effectiveWebpOptions(),
          useBackgroundIsolate: widget.options.useBackgroundIsolate,
          qualityPolicy: widget.qualityPolicy,
          validationPolicy: widget.validationPolicy,
        ),
        clipTransform: widget.clipTransform,
      );
      await widget.onExported?.call(result);
      if (mounted) {
        setState(() => _lastExport = result);
      }
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _lastError = error);
      }
      await _reportError(
        phase: MotionExporterOverlayErrorPhase.export,
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  ApngAnimationOptions _effectiveApngOptions() {
    return widget.apngOptions ??
        ApngAnimationOptions(
          loopCount: widget.options.loopCount,
          trimTransparentFrames: widget.options.trimTransparentFrames,
        );
  }

  WebpAnimationOptions _effectiveWebpOptions() {
    return widget.webpOptions ??
        WebpAnimationOptions(
          loopCount: widget.options.loopCount,
          backgroundColor: widget.options.backgroundColor,
          frameBlend: widget.options.frameBlend,
          frameDispose: widget.options.frameDispose,
          trimTransparentFrames: widget.options.trimTransparentFrames,
          trimChangedFrames: widget.options.trimChangedFrames,
        );
  }

  Future<void> _cancel() async {
    if (_busy || !_controller.isRecording) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _controller.cancel();
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _lastError = error);
      }
      await _reportError(
        phase: MotionExporterOverlayErrorPhase.cancel,
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    return Stack(
      alignment: Alignment.topLeft,
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: MotionRecorder(controller: _controller, child: widget.child),
        ),
        _positionedToolbar(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: _OverlayToolbar(
              controller: _controller,
              busy: _busy,
              format: widget.format,
              lastExport: _lastExport,
              lastError: _lastError,
              onStart: _start,
              onStop: _stop,
              onCancel: _cancel,
            ),
          ),
        ),
      ],
    );
  }

  Widget _positionedToolbar({required Widget child}) {
    const inset = 16.0;
    return switch (widget.position) {
      MotionExporterOverlayPosition.topLeft => Positioned(
        top: inset,
        left: inset,
        child: child,
      ),
      MotionExporterOverlayPosition.topRight => Positioned(
        top: inset,
        right: inset,
        child: child,
      ),
      MotionExporterOverlayPosition.bottomLeft => Positioned(
        bottom: inset,
        left: inset,
        child: child,
      ),
      MotionExporterOverlayPosition.bottomRight => Positioned(
        right: inset,
        bottom: inset,
        child: child,
      ),
    };
  }

  Future<void> _reportError({
    required MotionExporterOverlayErrorPhase phase,
    required Object error,
    required StackTrace stackTrace,
  }) async {
    final callback = widget.onError;
    if (callback == null) {
      return;
    }

    try {
      await callback(
        MotionExporterOverlayError(
          phase: phase,
          error: error,
          stackTrace: stackTrace,
          format: widget.format,
          diagnostics: _controller.diagnostics,
        ),
      );
    } catch (callbackError, callbackStackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: callbackError,
          stack: callbackStackTrace,
          library: 'motion_exporter',
          context: ErrorDescription(
            'while reporting a MotionExporterOverlay error',
          ),
        ),
      );
    }
  }
}

class _OverlayToolbar extends StatelessWidget {
  const _OverlayToolbar({
    required this.controller,
    required this.busy,
    required this.format,
    required this.lastExport,
    required this.lastError,
    required this.onStart,
    required this.onStop,
    required this.onCancel,
  });

  final MotionRecorderController controller;
  final bool busy;
  final MotionExportFormat format;
  final MotionExportResult? lastExport;
  final Object? lastError;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;
  final Future<void> Function() onCancel;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final export = lastExport;
        final error = lastError;
        final isRecording = controller.isRecording;
        final isEncoding = controller.isEncoding || busy;

        return DecoratedBox(
          decoration: BoxDecoration(
            color: const ui.Color(0xee111827),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: ui.Color(0x33000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusDot(active: isRecording),
                const SizedBox(width: 8),
                Text(
                  _statusText(
                    isRecording: isRecording,
                    isEncoding: isEncoding,
                    frameCount: controller.frameCount,
                    format: format,
                    export: export,
                    error: error,
                  ),
                  style: const TextStyle(
                    color: ui.Color(0xffffffff),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(width: 10),
                if (isRecording)
                  _ToolbarIconButton(
                    semanticLabel: 'Cancel recording',
                    symbol: _ToolbarSymbol.close,
                    key: const Key('motion_exporter_cancel'),
                    onPressed: isEncoding ? null : () => unawaited(onCancel()),
                  ),
                _ToolbarIconButton(
                  semanticLabel: isRecording
                      ? 'Stop and export ${format.label}'
                      : 'Start recording',
                  symbol: isRecording
                      ? _ToolbarSymbol.stop
                      : _ToolbarSymbol.record,
                  key: const Key('motion_exporter_primary_action'),
                  onPressed: isEncoding
                      ? null
                      : isRecording
                      ? () => unawaited(onStop())
                      : () => unawaited(onStart()),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _statusText({
    required bool isRecording,
    required bool isEncoding,
    required int frameCount,
    required MotionExportFormat format,
    required MotionExportResult? export,
    required Object? error,
  }) {
    if (error != null) {
      return 'Export failed';
    }
    if (isEncoding && !isRecording) {
      return 'Encoding ${format.label}...';
    }
    if (isRecording) {
      return '$frameCount frames';
    }
    if (export != null) {
      final kb = export.bytes.lengthInBytes / 1024;
      return '${format.label}: ${export.frameCount} frames - '
          '${kb.toStringAsFixed(1)} KB';
    }
    return 'Ready ${format.label}';
  }
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    required this.semanticLabel,
    required this.symbol,
    required this.onPressed,
    super.key,
  });

  final String semanticLabel;
  final _ToolbarSymbol symbol;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      width: 34,
      height: 34,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Center(
            child: CustomPaint(
              size: const Size.square(18),
              painter: _ToolbarSymbolPainter(
                symbol: symbol,
                color: enabled
                    ? const ui.Color(0xffffffff)
                    : const ui.Color(0x77ffffff),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarSymbolPainter extends CustomPainter {
  const _ToolbarSymbolPainter({required this.symbol, required this.color});

  final _ToolbarSymbol symbol;
  final ui.Color color;

  @override
  void paint(ui.Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = ui.Paint()
      ..color = color
      ..strokeCap = ui.StrokeCap.round
      ..strokeWidth = 2;

    switch (symbol) {
      case _ToolbarSymbol.close:
        canvas
          ..drawLine(
            Offset(size.width * 0.28, size.height * 0.28),
            Offset(size.width * 0.72, size.height * 0.72),
            paint,
          )
          ..drawLine(
            Offset(size.width * 0.72, size.height * 0.28),
            Offset(size.width * 0.28, size.height * 0.72),
            paint,
          );
      case _ToolbarSymbol.record:
        canvas.drawCircle(center, size.shortestSide * 0.32, paint);
      case _ToolbarSymbol.stop:
        final side = size.shortestSide * 0.54;
        canvas.drawRect(
          ui.Rect.fromCenter(center: center, width: side, height: side),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_ToolbarSymbolPainter oldDelegate) {
    return symbol != oldDelegate.symbol || color != oldDelegate.color;
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: active ? const ui.Color(0xffff4d4f) : const ui.Color(0xff22c55e),
        shape: BoxShape.circle,
      ),
      child: const SizedBox.square(dimension: 8),
    );
  }
}
