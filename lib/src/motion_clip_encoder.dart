part of '../motion_exporter.dart';

/// File format produced by [MotionClipEncoder] and [MotionExporterOverlay].
enum MotionExportFormat {
  /// Animated PNG, stored with a `.png` extension.
  apng(label: 'APNG', fileExtension: 'png', mimeType: 'image/png'),

  /// Animated WebP, stored with a `.webp` extension.
  webp(label: 'WebP', fileExtension: 'webp', mimeType: 'image/webp');

  const MotionExportFormat({
    required this.label,
    required this.fileExtension,
    required this.mimeType,
  });

  /// Short human-readable format label.
  final String label;

  /// Recommended file extension without a leading dot.
  final String fileExtension;

  /// MIME type for the encoded bytes.
  final String mimeType;
}

/// Encoded motion export plus metadata useful for saving or uploading.
class MotionExportResult {
  /// Creates an export result.
  const MotionExportResult({
    required this.format,
    required this.bytes,
    required this.frameCount,
    required this.width,
    required this.height,
    required this.duration,
    required this.clip,
    required this.encodeDuration,
    this.diagnostics,
    this.validation,
  });

  /// Encoded file format.
  final MotionExportFormat format;

  /// Encoded file bytes.
  final Uint8List bytes;

  /// Number of encoded frames.
  final int frameCount;

  /// Encoded canvas width in physical pixels.
  final int width;

  /// Encoded canvas height in physical pixels.
  final int height;

  /// Total playback duration represented by all frame durations.
  final Duration duration;

  /// Raw frames used for the export.
  final MotionClip clip;

  /// Capture diagnostics for the finished recording, when available.
  final MotionCaptureDiagnostics? diagnostics;

  /// CPU time spent encoding [clip] into [bytes].
  final Duration encodeDuration;

  /// Automatic post-encode validation, when enabled by [MotionClipEncoder].
  final MotionExportValidation? validation;

  /// Encoded byte count.
  int get byteLength => bytes.lengthInBytes;

  /// Encoded byte count in KiB.
  double get kibibytes => byteLength / 1024;

  /// Retained raw straight-alpha RGBA byte count for [clip].
  int get rawBytes => clip.rawBytes;

  /// Retained raw straight-alpha RGBA memory for [clip] in mebibytes.
  double get rawMebibytes => clip.rawMebibytes;

  /// Recommended file extension without a leading dot.
  String get fileExtension => format.fileExtension;

  /// MIME type for [bytes].
  String get mimeType => format.mimeType;

  /// Deterministic filename that includes output size, frame count, and duration.
  String get recommendedFileName => fileName();

  /// Builds a deterministic filename with [basename] and the correct extension.
  String fileName({String basename = 'motion_export'}) {
    if (basename.isEmpty) {
      throw ArgumentError.value(
        basename,
        'basename',
        'File basename must not be empty.',
      );
    }
    return '${basename}_${width}x${height}_${frameCount}f_'
        '${duration.inMilliseconds}ms.$fileExtension';
  }

  /// Parses encoded [bytes] and returns animation-container metadata.
  ///
  /// Use this to confirm the saved file is structurally animated and that the
  /// encoded frame count/duration match the captured clip.
  MotionExportInspection inspect() {
    return MotionExportInspection.inspect(format: format, bytes: bytes);
  }

  /// Validates encoded [bytes] against this export result metadata.
  ///
  /// The check compares the parsed container against the expected format,
  /// canvas size, frame count, duration, animation container, and alpha support.
  MotionExportValidation validateEncodedFile({
    Duration durationTolerance = _defaultExportValidationDurationTolerance,
    bool requireAlpha = true,
  }) {
    final cached = validation;
    if (cached != null &&
        durationTolerance == _defaultExportValidationDurationTolerance &&
        requireAlpha) {
      return cached;
    }
    return MotionExportValidation.forResult(
      this,
      durationTolerance: durationTolerance,
      requireAlpha: requireAlpha,
    );
  }

  MotionExportResult _withValidation(MotionExportValidation validation) {
    return MotionExportResult(
      format: format,
      bytes: bytes,
      frameCount: frameCount,
      width: width,
      height: height,
      duration: duration,
      clip: clip,
      encodeDuration: encodeDuration,
      diagnostics: diagnostics,
      validation: validation,
    );
  }
}

/// Encodes a captured [MotionClip] into an export format.
///
/// The encoder uses Flutter's [compute] helper by default, so custom recorder
/// UIs get the same off-UI-isolate encoding path as [MotionExporterOverlay].
/// WebP exports default to changed-frame rectangle trimming because
/// [MotionClip] frames are complete snapshots.
class MotionClipEncoder {
  /// Creates a clip encoder.
  const MotionClipEncoder({
    this.format = MotionExportFormat.webp,
    this.apngOptions = const ApngAnimationOptions(),
    this.webpOptions = const WebpAnimationOptions(trimChangedFrames: true),
    this.useBackgroundIsolate = true,
    this.qualityPolicy = const MotionCaptureQualityPolicy(),
    this.validationPolicy = const MotionExportValidationPolicy(),
  });

  /// Creates a WebP clip encoder.
  const MotionClipEncoder.webp({
    WebpAnimationOptions options = const WebpAnimationOptions(
      trimChangedFrames: true,
    ),
    bool useBackgroundIsolate = true,
    MotionCaptureQualityPolicy qualityPolicy =
        const MotionCaptureQualityPolicy(),
    MotionExportValidationPolicy validationPolicy =
        const MotionExportValidationPolicy(),
  }) : this(
         format: MotionExportFormat.webp,
         webpOptions: options,
         useBackgroundIsolate: useBackgroundIsolate,
         qualityPolicy: qualityPolicy,
         validationPolicy: validationPolicy,
       );

  /// Creates an APNG clip encoder.
  const MotionClipEncoder.apng({
    ApngAnimationOptions options = const ApngAnimationOptions(),
    bool useBackgroundIsolate = true,
    MotionCaptureQualityPolicy qualityPolicy =
        const MotionCaptureQualityPolicy(),
    MotionExportValidationPolicy validationPolicy =
        const MotionExportValidationPolicy(),
  }) : this(
         format: MotionExportFormat.apng,
         apngOptions: options,
         useBackgroundIsolate: useBackgroundIsolate,
         qualityPolicy: qualityPolicy,
         validationPolicy: validationPolicy,
       );

  /// Encoded output format.
  final MotionExportFormat format;

  /// Options used when [format] is [MotionExportFormat.apng].
  final ApngAnimationOptions apngOptions;

  /// Options used when [format] is [MotionExportFormat.webp].
  final WebpAnimationOptions webpOptions;

  /// Whether to encode through Flutter's [compute] helper.
  final bool useBackgroundIsolate;

  /// Capture quality policy checked before encoding.
  final MotionCaptureQualityPolicy qualityPolicy;

  /// Encoded-file validation policy checked after encoding.
  final MotionExportValidationPolicy validationPolicy;

  /// Encodes [clip] and returns bytes plus export metadata.
  Future<MotionExportResult> encode(
    MotionClip clip, {
    MotionCaptureDiagnostics? diagnostics,
  }) async {
    qualityPolicy.validate(diagnostics);
    final encodeStopwatch = Stopwatch()..start();
    final job = switch (format) {
      MotionExportFormat.apng => _MotionExportEncodeJob.apng(
        apngOptions._toJob(clip.frames),
      ),
      MotionExportFormat.webp => _MotionExportEncodeJob.webp(
        webpOptions._toJob(clip.frames),
      ),
    };
    final bytes = useBackgroundIsolate
        ? await compute(
            _encodeMotionExport,
            job,
            debugLabel: 'motion_export_encode',
          )
        : _encodeMotionExport(job);
    encodeStopwatch.stop();

    final result = MotionExportResult(
      format: format,
      bytes: bytes,
      frameCount: clip.frameCount,
      width: clip.width,
      height: clip.height,
      duration: clip.duration,
      clip: clip,
      diagnostics: diagnostics,
      encodeDuration: encodeStopwatch.elapsed,
    );
    final validation = validationPolicy.validate(result);
    return validation == null ? result : result._withValidation(validation);
  }
}

class _MotionExportEncodeJob {
  const _MotionExportEncodeJob.apng(_ApngEncodeJob job)
    : format = MotionExportFormat.apng,
      apngJob = job,
      webpJob = null;

  const _MotionExportEncodeJob.webp(_EncodeJob job)
    : format = MotionExportFormat.webp,
      apngJob = null,
      webpJob = job;

  final MotionExportFormat format;
  final _ApngEncodeJob? apngJob;
  final _EncodeJob? webpJob;
}

Uint8List _encodeMotionExport(_MotionExportEncodeJob job) {
  return switch (job.format) {
    MotionExportFormat.apng => _encodeApngAnimation(job.apngJob!),
    MotionExportFormat.webp => _encodeWebpAnimation(job.webpJob!),
  };
}
