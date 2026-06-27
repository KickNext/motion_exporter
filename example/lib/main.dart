import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:motion_exporter/motion_exporter.dart';

import 'src/recording_writer.dart';

void main() {
  runApp(const MotionExporterExampleApp());
}

const _demoAnimationDuration = Duration(seconds: 2);
const _demoCaptureFps = 120;
const _demoOutputLogicalSize = 256.0;

Future<MotionClip> renderTransparentDemoClip({
  int framesPerSecond = _demoCaptureFps,
  Duration duration = _demoAnimationDuration,
  double size = _demoOutputLogicalSize,
}) async {
  return MotionCanvasRecorder(
    size: Size.square(size),
    duration: duration,
    framesPerSecond: framesPerSecond,
  ).record((canvas, frameSize, progress, elapsed) {
    _TransparentPainter(progress).paint(canvas, frameSize);
  });
}

class MotionExporterExampleApp extends StatelessWidget {
  const MotionExporterExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'motion_exporter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff008f8a),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const DemoScreen(),
    );
  }
}

class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key});

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  final MotionRecorderController _recorder = MotionRecorderController();
  final ScrollController _scrollController = ScrollController();
  final MotionLoopSignal _loopSignal = MotionLoopSignal();
  Uint8List? _lastBytes;
  String? _lastPath;
  String? _lastError;
  MotionExportFormat? _lastFormat;
  MotionExportInspection? _lastInspection;
  MotionExportValidation? _lastValidation;
  MotionClip? _lastClip;
  MotionCaptureDiagnostics? _lastDiagnostics;
  _ExportSource? _lastSource;
  Duration? _lastExportDuration;
  Duration? _lastEncodeDuration;
  Duration? _lastWriteDuration;
  Completer<void>? _loopCancelCompleter;
  bool _captureOneLoop = true;
  bool _lastExportClosedLoop = false;
  bool _busy = false;

  bool get _loopCaptureActive => _loopCancelCompleter != null;

  @override
  void dispose() {
    final cancelCompleter = _loopCancelCompleter;
    if (cancelCompleter != null && !cancelCompleter.isCompleted) {
      cancelCompleter.complete();
    }
    _loopSignal.dispose();
    _scrollController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_loopCaptureActive) {
      await _cancelLoopCapture();
      return;
    }

    if (_busy) {
      return;
    }

    try {
      if (_recorder.isRecording) {
        await _stopRecording(loopClosed: false);
      } else {
        setState(() {
          _clearOutput();
        });
        if (_captureOneLoop) {
          await _recordNextLoop();
        } else {
          await _startRecording();
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _lastError = error.toString());
      }
    }
  }

  Future<void> _recordNextLoop() async {
    if (_busy || _recorder.isRecording || _loopCaptureActive) {
      return;
    }

    final cancelCompleter = Completer<void>();
    final totalStopwatch = Stopwatch();

    setState(() {
      _busy = true;
      _loopCancelCompleter = cancelCompleter;
      _lastError = null;
    });

    try {
      final result = await _recorder.recordNextLoop(
        loopSignal: _loopSignal,
        options: const MotionRecorderOptions(
          framesPerSecond: _demoCaptureFps,
          pixelRatio: 1,
          loopCount: 0,
          collapseIdenticalFrames: false,
          maxPendingCaptures: 32,
        ),
        encoder: const MotionClipEncoder(
          qualityPolicy: MotionCaptureQualityPolicy.noSkippedFrames(),
        ),
        loopDuration: _demoAnimationDuration,
        boundaryTimeout: const Duration(seconds: 8),
        cancelSignal: cancelCompleter.future,
        onCaptureStarted: (_) {
          totalStopwatch.start();
        },
      );
      if (!totalStopwatch.isRunning) {
        totalStopwatch.start();
      }

      final writeStopwatch = Stopwatch()..start();
      final path = await writeRecording(result, basename: 'live_loop');
      writeStopwatch.stop();
      final validation = result.validation ?? result.validateEncodedFile();
      totalStopwatch.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _lastBytes = result.bytes;
        _lastPath = path;
        _lastFormat = result.format;
        _lastInspection = validation.inspection;
        _lastValidation = validation;
        _lastClip = result.clip;
        _lastDiagnostics = result.diagnostics;
        _lastSource = _ExportSource.live;
        _lastExportDuration = totalStopwatch.elapsed;
        _lastEncodeDuration = result.encodeDuration;
        _lastWriteDuration = writeStopwatch.elapsed;
        _lastExportClosedLoop = true;
      });
      _revealOutput();
    } on MotionLoopWaitCanceledException {
      // Intentional developer cancel from the example toolbar.
    } catch (error) {
      if (mounted) {
        setState(() => _lastError = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          if (identical(_loopCancelCompleter, cancelCompleter)) {
            _loopCancelCompleter = null;
          }
        });
      }
    }
  }

  Future<void> _cancelLoopCapture() async {
    final cancelCompleter = _loopCancelCompleter;
    if (cancelCompleter == null) {
      return;
    }
    if (!cancelCompleter.isCompleted) {
      cancelCompleter.complete();
    }
    if (_recorder.isRecording) {
      await _recorder.cancel();
    }
    if (mounted) {
      setState(() => _lastError = null);
    }
  }

  Future<void> _startRecording() async {
    if (_busy || _recorder.isRecording) {
      return;
    }

    setState(() {
      _busy = true;
      _lastError = null;
    });
    try {
      await _recorder.start(
        options: const MotionRecorderOptions(
          framesPerSecond: _demoCaptureFps,
          pixelRatio: 1,
          loopCount: 0,
          collapseIdenticalFrames: false,
          maxPendingCaptures: 32,
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _lastError = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _stopRecording({required bool loopClosed}) async {
    if (_busy || !_recorder.isRecording) {
      return;
    }

    setState(() {
      _busy = true;
      _lastError = null;
    });
    try {
      final totalStopwatch = Stopwatch()..start();
      final result = await _recorder.stopExport(
        encoder: const MotionClipEncoder(
          qualityPolicy: MotionCaptureQualityPolicy.noSkippedFrames(),
        ),
        clipTransform: loopClosed
            ? (clip) => clip
                  .withoutDuplicateLoopClosure(channelTolerance: 8)
                  .withDuration(_demoAnimationDuration)
            : null,
      );

      final writeStopwatch = Stopwatch()..start();
      final path = await writeRecording(result, basename: 'live_loop');
      writeStopwatch.stop();
      final validation = result.validation ?? result.validateEncodedFile();
      totalStopwatch.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _lastBytes = result.bytes;
        _lastPath = path;
        _lastFormat = result.format;
        _lastInspection = validation.inspection;
        _lastValidation = validation;
        _lastClip = result.clip;
        _lastDiagnostics = result.diagnostics;
        _lastSource = _ExportSource.live;
        _lastExportDuration = totalStopwatch.elapsed;
        _lastEncodeDuration = result.encodeDuration;
        _lastWriteDuration = writeStopwatch.elapsed;
        _lastExportClosedLoop = loopClosed;
      });
      _revealOutput();
    } catch (error) {
      if (mounted) {
        setState(() => _lastError = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _renderDeterministicExport() async {
    if (_busy || _recorder.isRecording) {
      return;
    }

    setState(() {
      _busy = true;
      _clearOutput();
    });
    try {
      final totalStopwatch = Stopwatch()..start();
      final renderStopwatch = Stopwatch()..start();
      final clip = await renderTransparentDemoClip();
      renderStopwatch.stop();

      final result = await const MotionClipEncoder().encode(clip);

      final writeStopwatch = Stopwatch()..start();
      final path = await writeRecording(result, basename: 'transparent_120fps');
      writeStopwatch.stop();
      final validation = result.validation ?? result.validateEncodedFile();
      totalStopwatch.stop();

      if (!mounted) {
        return;
      }
      setState(() {
        _lastBytes = result.bytes;
        _lastPath = path;
        _lastFormat = result.format;
        _lastInspection = validation.inspection;
        _lastValidation = validation;
        _lastClip = clip;
        _lastSource = _ExportSource.rendered;
        _lastDiagnostics = MotionCaptureDiagnostics(
          targetFramesPerSecond: _demoCaptureFps,
          pixelRatio: 1,
          captureElapsed: _demoAnimationDuration,
          requestedFrames: clip.frameCount,
          capturedFrames: clip.frameCount,
          keptFrames: clip.frameCount,
          skippedFrames: 0,
          collapsedFrames: 0,
          width: clip.width,
          height: clip.height,
          sampledBytes: clip.rawBytes,
          retainedBytes: clip.rawBytes,
          totalCaptureTime: renderStopwatch.elapsed,
          totalFrameWaitTime: Duration.zero,
          totalToImageTime: renderStopwatch.elapsed,
          totalToByteDataTime: Duration.zero,
          totalStoreTime: Duration.zero,
          maxCaptureTime: Duration.zero,
          maxFrameWaitTime: Duration.zero,
          maxToImageTime: Duration.zero,
          maxToByteDataTime: Duration.zero,
          maxStoreTime: Duration.zero,
        );
        _lastExportDuration = totalStopwatch.elapsed;
        _lastEncodeDuration = result.encodeDuration;
        _lastWriteDuration = writeStopwatch.elapsed;
        _lastExportClosedLoop = true;
      });
      _revealOutput();
    } catch (error) {
      if (mounted) {
        setState(() => _lastError = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _clearOutput() {
    _lastBytes = null;
    _lastPath = null;
    _lastError = null;
    _lastFormat = null;
    _lastInspection = null;
    _lastValidation = null;
    _lastClip = null;
    _lastDiagnostics = null;
    _lastSource = null;
    _lastExportDuration = null;
    _lastEncodeDuration = null;
    _lastWriteDuration = null;
    _lastExportClosedLoop = false;
    _loopCancelCompleter = null;
  }

  void _setCaptureOneLoop(bool value) {
    setState(() {
      _captureOneLoop = value;
    });
  }

  void _revealOutput() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      if (position.maxScrollExtent <= 0) {
        return;
      }
      unawaited(
        position.animateTo(
          position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final clip = _lastClip;

    return Scaffold(
      backgroundColor: const Color(0xfff7f8f8),
      appBar: AppBar(
        title: const Text('motion_exporter'),
        actions: [
          AnimatedBuilder(
            animation: _recorder,
            builder: (context, _) {
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    '${_recorder.frameCount} frames',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final content = [
              _RecorderPanel(
                recorder: _recorder,
                busy: _busy,
                loopCaptureActive: _loopCaptureActive,
                captureOneLoop: _captureOneLoop,
                loopSignal: _loopSignal,
                clip: clip,
                bytes: _lastBytes,
                path: _lastPath,
                error: _lastError,
                format: _lastFormat,
                inspection: _lastInspection,
                validation: _lastValidation,
                exportDuration: _lastExportDuration,
                encodeDuration: _lastEncodeDuration,
                writeDuration: _lastWriteDuration,
                loopCaptured: _lastExportClosedLoop,
                source: _lastSource,
                onToggleRecording: _toggleRecording,
                onRenderDeterministic: _renderDeterministicExport,
                onCaptureOneLoopChanged: _setCaptureOneLoop,
              ),
              _OutputPanel(
                bytes: _lastBytes,
                path: _lastPath,
                clip: clip,
                diagnostics: _lastDiagnostics,
                error: _lastError,
                format: _lastFormat,
                inspection: _lastInspection,
                validation: _lastValidation,
                exportDuration: _lastExportDuration,
                encodeDuration: _lastEncodeDuration,
                writeDuration: _lastWriteDuration,
                loopCaptured: _lastExportClosedLoop,
                source: _lastSource,
              ),
            ];

            return Padding(
              padding: const EdgeInsets.all(24),
              child: wide
                  ? SingleChildScrollView(
                      controller: _scrollController,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: content[0]),
                          const SizedBox(width: 20),
                          Expanded(child: content[1]),
                        ],
                      ),
                    )
                  : ListView.separated(
                      controller: _scrollController,
                      itemBuilder: (context, index) => content[index],
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 20),
                      itemCount: content.length,
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _RecorderPanel extends StatelessWidget {
  const _RecorderPanel({
    required this.recorder,
    required this.busy,
    required this.loopCaptureActive,
    required this.captureOneLoop,
    required this.loopSignal,
    required this.clip,
    required this.bytes,
    required this.path,
    required this.error,
    required this.format,
    required this.inspection,
    required this.validation,
    required this.exportDuration,
    required this.encodeDuration,
    required this.writeDuration,
    required this.loopCaptured,
    required this.source,
    required this.onToggleRecording,
    required this.onRenderDeterministic,
    required this.onCaptureOneLoopChanged,
  });

  final MotionRecorderController recorder;
  final bool busy;
  final bool loopCaptureActive;
  final bool captureOneLoop;
  final MotionLoopSignal loopSignal;
  final MotionClip? clip;
  final Uint8List? bytes;
  final String? path;
  final String? error;
  final MotionExportFormat? format;
  final MotionExportInspection? inspection;
  final MotionExportValidation? validation;
  final Duration? exportDuration;
  final Duration? encodeDuration;
  final Duration? writeDuration;
  final bool loopCaptured;
  final _ExportSource? source;
  final Future<void> Function() onToggleRecording;
  final Future<void> Function() onRenderDeterministic;
  final ValueChanged<bool> onCaptureOneLoopChanged;

  @override
  Widget build(BuildContext context) {
    final stats = clip;
    final data = bytes;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xffd9dfdd)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xffcdd5d1)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const _Checkerboard(),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final dimension = math.min(
                            _demoOutputLogicalSize,
                            math.min(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            ),
                          );
                          return Center(
                            child: SizedBox.square(
                              dimension: dimension,
                              child: MotionRecorder(
                                controller: recorder,
                                child: _TransparentAnimation(
                                  loopSignal: loopSignal,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            AnimatedBuilder(
              animation: recorder,
              builder: (context, _) {
                final isRecording = recorder.isRecording;
                final canToggle = !busy || loopCaptureActive || isRecording;
                return FilledButton.icon(
                  key: const Key('motion_exporter_example_record_button'),
                  onPressed: canToggle
                      ? () => unawaited(onToggleRecording())
                      : null,
                  icon: Icon(
                    loopCaptureActive
                        ? Icons.close
                        : isRecording
                        ? Icons.stop
                        : Icons.fiber_manual_record,
                  ),
                  label: Text(
                    loopCaptureActive
                        ? isRecording
                              ? 'Cancel loop'
                              : 'Waiting for loop'
                        : busy
                        ? isRecording
                              ? 'Exporting...'
                              : 'Starting...'
                        : isRecording
                        ? 'Stop'
                        : captureOneLoop
                        ? 'Record loop'
                        : 'Record',
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('motion_exporter_example_render_button'),
              onPressed: busy || loopCaptureActive || recorder.isRecording
                  ? null
                  : () => unawaited(onRenderDeterministic()),
              icon: const Icon(Icons.movie_creation_outlined),
              label: const Text('Render 120 fps'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.repeat),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'One loop',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                Switch(
                  key: const Key('motion_exporter_example_loop_switch'),
                  value: captureOneLoop,
                  onChanged: busy || loopCaptureActive || recorder.isRecording
                      ? null
                      : onCaptureOneLoopChanged,
                ),
              ],
            ),
            if (busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 3),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              _InlineStatus(
                icon: Icons.error_outline,
                text: 'Export failed',
                tone: _StatusTone.error,
              ),
            ] else if (stats != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (format != null)
                    _StatChip(icon: Icons.check_circle, label: format!.label),
                  if (inspection != null)
                    _StatChip(
                      icon: inspection!.isAnimated
                          ? Icons.verified_outlined
                          : Icons.image_outlined,
                      label: _formatEncodedFrames(inspection!),
                    ),
                  if (validation != null)
                    _StatChip(
                      icon: validation!.isValid
                          ? Icons.verified
                          : Icons.report_problem_outlined,
                      label: validation!.summary,
                    ),
                  if (source != null)
                    _StatChip(icon: source!.icon, label: source!.label),
                  if (data != null)
                    _StatChip(
                      icon: Icons.storage,
                      label: '${(data.length / 1024).toStringAsFixed(1)} KB',
                    ),
                  if (exportDuration != null)
                    _StatChip(
                      icon: Icons.timer,
                      label: '${_formatMs(exportDuration!)} total',
                    ),
                  if (encodeDuration != null)
                    _StatChip(
                      icon: Icons.memory,
                      label: '${_formatMs(encodeDuration!)} encode',
                    ),
                  if (loopCaptured)
                    const _StatChip(icon: Icons.repeat, label: '1 loop'),
                  _StatChip(
                    icon: Icons.schedule,
                    label: _formatDuration(stats.duration),
                  ),
                  if (path != null)
                    _StatChip(icon: Icons.folder, label: _fileName(path!)),
                ],
              ),
            ],
            AnimatedBuilder(
              animation: recorder,
              builder: (context, _) {
                final diagnostics = recorder.diagnostics;
                if (diagnostics == null || diagnostics.requestedFrames == 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _PerformanceChips(
                    diagnostics: diagnostics,
                    encodeDuration: encodeDuration,
                    writeDuration: writeDuration,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _OutputPanel extends StatelessWidget {
  const _OutputPanel({
    required this.bytes,
    required this.path,
    required this.clip,
    required this.diagnostics,
    required this.error,
    required this.format,
    required this.inspection,
    required this.validation,
    required this.exportDuration,
    required this.encodeDuration,
    required this.writeDuration,
    required this.loopCaptured,
    required this.source,
  });

  final Uint8List? bytes;
  final String? path;
  final MotionClip? clip;
  final MotionCaptureDiagnostics? diagnostics;
  final String? error;
  final MotionExportFormat? format;
  final MotionExportInspection? inspection;
  final MotionExportValidation? validation;
  final Duration? exportDuration;
  final Duration? encodeDuration;
  final Duration? writeDuration;
  final bool loopCaptured;
  final _ExportSource? source;

  @override
  Widget build(BuildContext context) {
    final data = bytes;
    final stats = clip;
    final exportError = error;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xffd9dfdd)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xffcdd5d1)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const _Checkerboard(),
                      if (exportError != null)
                        const Center(child: Icon(Icons.error_outline, size: 48))
                      else if (stats == null || data == null)
                        const Center(child: Icon(Icons.movie, size: 48))
                      else
                        _EncodedPlaybackView(
                          key: const Key('motion_exporter_example_playback'),
                          bytes: data,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (exportError != null) ...[
              Text(
                'Export failed',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              SelectableText(
                exportError,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else if (stats == null || data == null)
              Text('No output', style: Theme.of(context).textTheme.labelLarge)
            else
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _StatChip(
                    icon: Icons.layers,
                    label: '${stats.frameCount} frames',
                  ),
                  if (format != null)
                    _StatChip(icon: Icons.check_circle, label: format!.label),
                  if (inspection != null)
                    _StatChip(
                      icon: inspection!.isAnimated
                          ? Icons.verified_outlined
                          : Icons.image_outlined,
                      label: _formatEncodedFrames(inspection!),
                    ),
                  if (validation != null)
                    _StatChip(
                      icon: validation!.isValid
                          ? Icons.verified
                          : Icons.report_problem_outlined,
                      label: validation!.summary,
                    ),
                  _StatChip(
                    icon: Icons.aspect_ratio,
                    label: '${stats.width} x ${stats.height}',
                  ),
                  _StatChip(
                    icon: Icons.storage,
                    label: '${(data.length / 1024).toStringAsFixed(1)} KB',
                  ),
                  _StatChip(
                    icon: Icons.schedule,
                    label: _formatDuration(stats.duration),
                  ),
                  if (source != null)
                    _StatChip(icon: source!.icon, label: source!.label),
                  if (exportDuration != null)
                    _StatChip(
                      icon: Icons.timer,
                      label: '${_formatMs(exportDuration!)} total',
                    ),
                  if (loopCaptured)
                    const _StatChip(icon: Icons.repeat, label: '1 loop'),
                ],
              ),
            if (diagnostics != null) ...[
              const SizedBox(height: 12),
              _PerformanceChips(
                diagnostics: diagnostics!,
                encodeDuration: encodeDuration,
                writeDuration: writeDuration,
              ),
            ],
            if (path != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                path!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _ExportSource {
  live(Icons.radio_button_checked, 'live'),
  rendered(Icons.movie_creation_outlined, 'rendered');

  const _ExportSource(this.icon, this.label);

  final IconData icon;
  final String label;
}

enum _StatusTone { error }

class _InlineStatus extends StatelessWidget {
  const _InlineStatus({
    required this.icon,
    required this.text,
    required this.tone,
  });

  final IconData icon;
  final String text;
  final _StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      _StatusTone.error => const Color(0xffb42318),
    };

    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _PerformanceChips extends StatelessWidget {
  const _PerformanceChips({
    required this.diagnostics,
    required this.encodeDuration,
    required this.writeDuration,
  });

  final MotionCaptureDiagnostics diagnostics;
  final Duration? encodeDuration;
  final Duration? writeDuration;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _StatChip(
          icon: diagnostics.isCleanCapture
              ? Icons.check_circle_outline
              : Icons.warning_amber_rounded,
          label: diagnostics.qualityStatus.label,
        ),
        _StatChip(
          icon: Icons.speed,
          label:
              'capture ${_formatFps(diagnostics.effectiveCapturedFps)} / '
              'target ${diagnostics.targetFramesPerSecond} fps',
        ),
        _StatChip(
          icon: Icons.layers,
          label:
              '${diagnostics.capturedFrames} cap / '
              '${diagnostics.keptFrames} kept',
        ),
        _StatChip(
          icon: Icons.skip_next,
          label:
              '${diagnostics.skippedFrames} skipped '
              '(${_formatPercent(diagnostics.skippedFrameRatio)})',
        ),
        _StatChip(
          icon: Icons.camera,
          label: '${_formatMs(diagnostics.averageToImageTime)} toImage',
        ),
        _StatChip(
          icon: Icons.data_object,
          label: '${_formatMs(diagnostics.averageToByteDataTime)} readback',
        ),
        _StatChip(
          icon: Icons.content_copy,
          label: '${_formatMs(diagnostics.averageStoreTime)} store',
        ),
        _StatChip(
          icon: Icons.memory,
          label: '${_formatMib(diagnostics.retainedMebibytes)} raw',
        ),
        if (encodeDuration != null)
          _StatChip(
            icon: Icons.compress,
            label: '${_formatMs(encodeDuration!)} encode',
          ),
        if (writeDuration != null)
          _StatChip(
            icon: Icons.save,
            label: '${_formatMs(writeDuration!)} write',
          ),
      ],
    );
  }
}

String _formatMs(Duration duration) {
  final ms = duration.inMicroseconds / 1000;
  final digits = ms >= 10 ? 0 : 1;
  return '${ms.toStringAsFixed(digits)} ms';
}

String _formatFps(double fps) {
  return fps >= 10 ? fps.toStringAsFixed(0) : fps.toStringAsFixed(1);
}

String _formatMib(double mebibytes) {
  return '${mebibytes.toStringAsFixed(mebibytes >= 10 ? 1 : 2)} MiB';
}

String _formatPercent(double ratio) {
  return '${(ratio * 100).toStringAsFixed(0)}%';
}

String _formatDuration(Duration duration) {
  final seconds = duration.inMicroseconds / Duration.microsecondsPerSecond;
  return '${seconds.toStringAsFixed(seconds >= 10 ? 1 : 2)} s';
}

String _formatEncodedFrames(MotionExportInspection inspection) {
  final suffix = inspection.frameCount == 1 ? 'frame' : 'frames';
  return '${inspection.frameCount} encoded $suffix';
}

String _fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash == -1 ? normalized : normalized.substring(slash + 1);
}

class _EncodedPlaybackView extends StatelessWidget {
  const _EncodedPlaybackView({required this.bytes, super.key});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Image.memory(
      bytes,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        return const Center(child: Icon(Icons.broken_image_outlined, size: 48));
      },
    );
  }
}

class _TransparentAnimation extends StatefulWidget {
  const _TransparentAnimation({required this.loopSignal});

  final MotionLoopSignal loopSignal;

  @override
  State<_TransparentAnimation> createState() => _TransparentAnimationState();
}

class _TransparentAnimationState extends State<_TransparentAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: _demoAnimationDuration)
          ..addStatusListener(_handleAnimationStatus)
          ..forward();
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) {
      return;
    }

    if (mounted) {
      _controller.forward(from: 0);
      widget.loopSignal.markBoundary();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(painter: _TransparentPainter(_controller.value));
      },
    );
  }
}

class _TransparentPainter extends CustomPainter {
  const _TransparentPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final shortest = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final sweep = t * math.pi * 2;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = shortest * 0.055
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xcc008f8a);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: shortest * 0.28),
      sweep,
      math.pi * 1.35,
      false,
      ringPaint,
    );

    final orbPaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 4; i++) {
      final angle = sweep + i * math.pi / 2;
      final radius = shortest * (0.18 + i * 0.035);
      final offset = Offset(math.cos(angle), math.sin(angle)) * radius;
      orbPaint.color = [
        const Color(0xd9ff5a5f),
        const Color(0xd9008f8a),
        const Color(0xd9ffc145),
        const Color(0xd93862ff),
      ][i];
      canvas.drawCircle(
        center + offset,
        shortest * (0.08 + i * 0.01),
        orbPaint,
      );
    }

    final corePaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xeaffffff), Color(0x66008f8a), Color(0x00008f8a)],
      ).createShader(Rect.fromCircle(center: center, radius: shortest * 0.2));
    canvas.drawCircle(center, shortest * 0.2, corePaint);
  }

  @override
  bool shouldRepaint(covariant _TransparentPainter oldDelegate) {
    return oldDelegate.t != t;
  }
}

class _Checkerboard extends StatelessWidget {
  const _Checkerboard();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: const _CheckerboardPainter());
  }
}

class _CheckerboardPainter extends CustomPainter {
  const _CheckerboardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const tile = 18.0;
    final light = Paint()..color = const Color(0xffffffff);
    final dark = Paint()..color = const Color(0xffe5ebe8);

    canvas.drawRect(Offset.zero & size, light);
    for (var y = 0.0; y < size.height; y += tile) {
      for (var x = 0.0; x < size.width; x += tile) {
        final parity = ((x / tile).floor() + (y / tile).floor()).isEven;
        if (parity) {
          canvas.drawRect(Rect.fromLTWH(x, y, tile, tile), dark);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerboardPainter oldDelegate) => false;
}
