part of '../motion_exporter.dart';

/// Format-neutral name for [WebpRecorder].
///
/// Prefer this name for new code. The recorder captures raw RGBA frames from a
/// widget subtree; choose APNG or WebP later with [MotionClipEncoder].
typedef MotionRecorder = WebpRecorder;

/// Format-neutral name for [WebpRecorderController].
///
/// Prefer this name for new code. Use [MotionRecorderController.stopExport] for
/// one-step APNG/WebP export or [MotionRecorderController.stopCapture] for raw
/// frames.
typedef MotionRecorderController = WebpRecorderController;

/// Format-neutral name for [WebpRecorderOptions].
typedef MotionRecorderOptions = WebpRecorderOptions;

/// Format-neutral name for [WebpCaptureDiagnostics].
typedef MotionCaptureDiagnostics = WebpCaptureDiagnostics;

/// Format-neutral name for [WebpRecording].
typedef MotionRecording = WebpRecording;
