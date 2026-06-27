part of '../motion_exporter.dart';

/// Reason why captured frames did not satisfy a [MotionCaptureQualityPolicy].
enum MotionCaptureQualityFailure {
  /// The policy required diagnostics, but none were supplied.
  missingDiagnostics,

  /// One or more capture requests were skipped because readback was saturated.
  skippedFrames,

  /// The effective sampled frame rate was below the configured policy ratio.
  belowTargetFrameRate,
}

/// Quality policy applied before encoding a captured [MotionClip].
///
/// Use the default policy when best-effort export is acceptable. Use
/// [MotionCaptureQualityPolicy.strict] when skipped samples or a live frame rate
/// below target should fail the export.
class MotionCaptureQualityPolicy {
  /// Creates a custom capture quality policy.
  const MotionCaptureQualityPolicy({
    this.requireDiagnostics = false,
    this.allowSkippedFrames = true,
    this.minimumTargetFrameRateRatio = 0,
  }) : assert(minimumTargetFrameRateRatio >= 0),
       assert(minimumTargetFrameRateRatio <= 1);

  /// Requires diagnostics and zero skipped frames.
  ///
  /// This is useful when dropped samples are unacceptable, but a lower live
  /// sampled FPS should remain visible as diagnostics instead of failing the
  /// export.
  const MotionCaptureQualityPolicy.noSkippedFrames({
    bool requireDiagnostics = true,
  }) : this(requireDiagnostics: requireDiagnostics, allowSkippedFrames: false);

  /// Requires diagnostics, zero skipped frames, and near-target sampled FPS.
  const MotionCaptureQualityPolicy.strict({
    double minimumTargetFrameRateRatio = 0.95,
  }) : this(
         requireDiagnostics: true,
         allowSkippedFrames: false,
         minimumTargetFrameRateRatio: minimumTargetFrameRateRatio,
       );

  /// Whether missing diagnostics should fail validation.
  final bool requireDiagnostics;

  /// Whether exports may proceed when capture requests were skipped.
  final bool allowSkippedFrames;

  /// Minimum accepted ratio of sampled FPS to requested FPS.
  ///
  /// `0` disables the FPS ratio check. `0.95` means sampled FPS must be at
  /// least 95% of the requested recorder frame rate.
  final double minimumTargetFrameRateRatio;

  /// Returns every quality failure for [diagnostics].
  List<MotionCaptureQualityFailure> failuresFor(
    MotionCaptureDiagnostics? diagnostics,
  ) {
    final failures = <MotionCaptureQualityFailure>[];
    if (diagnostics == null) {
      if (requireDiagnostics) {
        failures.add(MotionCaptureQualityFailure.missingDiagnostics);
      }
      return List<MotionCaptureQualityFailure>.unmodifiable(failures);
    }
    if (!allowSkippedFrames && diagnostics.hasSkippedFrames) {
      failures.add(MotionCaptureQualityFailure.skippedFrames);
    }
    if (minimumTargetFrameRateRatio > 0 &&
        diagnostics.targetFrameRateRatio < minimumTargetFrameRateRatio) {
      failures.add(MotionCaptureQualityFailure.belowTargetFrameRate);
    }
    return List<MotionCaptureQualityFailure>.unmodifiable(failures);
  }

  /// Throws [MotionCaptureQualityException] when [diagnostics] fail this policy.
  void validate(MotionCaptureDiagnostics? diagnostics) {
    final failures = failuresFor(diagnostics);
    if (failures.isEmpty) {
      return;
    }
    throw MotionCaptureQualityException(
      policy: this,
      diagnostics: diagnostics,
      failures: failures,
    );
  }
}

/// Thrown when a capture does not satisfy a [MotionCaptureQualityPolicy].
class MotionCaptureQualityException implements Exception {
  /// Creates a capture quality exception.
  const MotionCaptureQualityException({
    required this.policy,
    required this.diagnostics,
    required this.failures,
  });

  /// Policy that rejected the capture.
  final MotionCaptureQualityPolicy policy;

  /// Diagnostics that failed validation, when available.
  final MotionCaptureDiagnostics? diagnostics;

  /// Reasons the capture failed validation.
  final List<MotionCaptureQualityFailure> failures;

  @override
  String toString() {
    final reasons = failures.map(_captureQualityFailureLabel).join(', ');
    final summary = diagnostics?.qualitySummary;
    if (summary == null) {
      return 'MotionCaptureQualityException: $reasons';
    }
    return 'MotionCaptureQualityException: $reasons ($summary)';
  }
}

String _captureQualityFailureLabel(MotionCaptureQualityFailure failure) {
  return switch (failure) {
    MotionCaptureQualityFailure.missingDiagnostics => 'missing diagnostics',
    MotionCaptureQualityFailure.skippedFrames => 'skipped frames',
    MotionCaptureQualityFailure.belowTargetFrameRate =>
      'below target frame rate',
  };
}
