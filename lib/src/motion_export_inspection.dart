part of '../motion_exporter.dart';

const _defaultExportValidationDurationTolerance = Duration(milliseconds: 1);

/// Structural metadata parsed from encoded motion export bytes.
///
/// This is a lightweight container check. It verifies the animation wrapper and
/// frame timing metadata, but it does not decode every compressed frame image.
class MotionExportInspection {
  /// Creates parsed export metadata.
  const MotionExportInspection({
    required this.format,
    required this.width,
    required this.height,
    required this.frameDurations,
    required this.loopCount,
    required this.hasAnimationContainer,
    required this.hasAlpha,
  });

  /// Parses [bytes] as [format] and returns structural animation metadata.
  factory MotionExportInspection.inspect({
    required MotionExportFormat format,
    required Uint8List bytes,
  }) {
    return switch (format) {
      MotionExportFormat.webp => _inspectWebpExport(bytes),
      MotionExportFormat.apng => _inspectApngExport(bytes),
    };
  }

  /// Encoded file format that was inspected.
  final MotionExportFormat format;

  /// Encoded canvas width in physical pixels.
  final int width;

  /// Encoded canvas height in physical pixels.
  final int height;

  /// Per-frame delays from the encoded animation container.
  final List<Duration> frameDurations;

  /// Animation loop count from the encoded container. `0` means infinite.
  final int loopCount;

  /// Whether the encoded bytes contain the expected animation container chunks.
  final bool hasAnimationContainer;

  /// Whether the encoded container advertises alpha-capable pixels.
  final bool hasAlpha;

  /// Number of frames declared by the encoded animation container.
  int get frameCount => frameDurations.length;

  /// Total playback duration represented by encoded frame delays.
  Duration get duration {
    final micros = frameDurations.fold<int>(
      0,
      (total, duration) => total + duration.inMicroseconds,
    );
    return Duration(microseconds: micros);
  }

  /// Whether this encoded file contains more than one animated frame.
  bool get isAnimated => hasAnimationContainer && frameCount > 1;
}

/// Structural mismatch found while validating encoded export bytes.
enum MotionExportValidationFailure {
  /// Encoded container format differs from the export result format.
  formatMismatch('format mismatch'),

  /// Encoded canvas size differs from the export result size.
  sizeMismatch('size mismatch'),

  /// Encoded frame count differs from the export result frame count.
  frameCountMismatch('frame count mismatch'),

  /// Encoded frame delays do not add up to the export result duration.
  durationMismatch('duration mismatch'),

  /// Encoded bytes do not advertise an animation container.
  missingAnimationContainer('missing animation container'),

  /// Encoded bytes do not advertise alpha-capable pixels.
  missingAlpha('missing alpha');

  const MotionExportValidationFailure(this.label);

  /// Short human-readable failure label.
  final String label;
}

/// Result of checking encoded bytes against a [MotionExportResult].
class MotionExportValidation {
  const MotionExportValidation._({
    required this.inspection,
    required this.failures,
  });

  /// Validates [result.bytes] against the metadata attached to [result].
  ///
  /// The check is structural: it parses the encoded animation container and
  /// compares format, canvas size, frame count, total duration, animation
  /// container presence, and alpha support. It does not decode and compare
  /// every compressed frame pixel.
  factory MotionExportValidation.forResult(
    MotionExportResult result, {
    MotionExportInspection? inspection,
    Duration durationTolerance = _defaultExportValidationDurationTolerance,
    bool requireAlpha = true,
  }) {
    if (durationTolerance < Duration.zero) {
      throw ArgumentError.value(
        durationTolerance,
        'durationTolerance',
        'Duration tolerance must not be negative.',
      );
    }

    final actual = inspection ?? result.inspect();
    final failures = <MotionExportValidationFailure>[];

    if (actual.format != result.format) {
      failures.add(MotionExportValidationFailure.formatMismatch);
    }
    if (actual.width != result.width || actual.height != result.height) {
      failures.add(MotionExportValidationFailure.sizeMismatch);
    }
    if (actual.frameCount != result.frameCount) {
      failures.add(MotionExportValidationFailure.frameCountMismatch);
    }
    if (_durationDifference(actual.duration, result.duration) >
        durationTolerance) {
      failures.add(MotionExportValidationFailure.durationMismatch);
    }
    if (!actual.hasAnimationContainer) {
      failures.add(MotionExportValidationFailure.missingAnimationContainer);
    }
    if (requireAlpha && !actual.hasAlpha) {
      failures.add(MotionExportValidationFailure.missingAlpha);
    }

    return MotionExportValidation._(
      inspection: actual,
      failures: List<MotionExportValidationFailure>.unmodifiable(failures),
    );
  }

  /// Parsed metadata from the encoded export bytes.
  final MotionExportInspection inspection;

  /// Structural mismatches found during validation.
  final List<MotionExportValidationFailure> failures;

  /// Whether the encoded file matches the export result metadata.
  bool get isValid => failures.isEmpty;

  /// Compact human-readable summary.
  String get summary {
    if (isValid) {
      return 'file verified';
    }
    return failures.map((failure) => failure.label).join(', ');
  }

  /// Throws [MotionExportValidationException] if [isValid] is false.
  void throwIfInvalid() {
    if (!isValid) {
      throw MotionExportValidationException(this);
    }
  }

  @override
  String toString() {
    return 'MotionExportValidation($summary)';
  }
}

/// Policy for structural validation after encoding an export.
class MotionExportValidationPolicy {
  /// Creates an encoded-file validation policy.
  const MotionExportValidationPolicy({
    this.enabled = true,
    this.durationTolerance = _defaultExportValidationDurationTolerance,
    this.requireAlpha = true,
  });

  /// Disables automatic post-encode validation.
  const MotionExportValidationPolicy.disabled()
    : enabled = false,
      durationTolerance = _defaultExportValidationDurationTolerance,
      requireAlpha = false;

  /// Whether [MotionClipEncoder] should validate encoded bytes before returning.
  final bool enabled;

  /// Allowed total-duration difference between clip metadata and container
  /// frame delays.
  final Duration durationTolerance;

  /// Whether the encoded container must advertise alpha-capable pixels.
  final bool requireAlpha;

  /// Validates [result] or returns `null` when [enabled] is false.
  MotionExportValidation? validate(MotionExportResult result) {
    if (!enabled) {
      return null;
    }
    final validation = result.validateEncodedFile(
      durationTolerance: durationTolerance,
      requireAlpha: requireAlpha,
    );
    validation.throwIfInvalid();
    return validation;
  }
}

/// Thrown when an encoded export fails structural validation.
class MotionExportValidationException implements Exception {
  /// Creates an exception for [validation].
  const MotionExportValidationException(this.validation);

  /// Failed validation details.
  final MotionExportValidation validation;

  @override
  String toString() {
    return 'MotionExportValidationException: ${validation.summary}';
  }
}

Duration _durationDifference(Duration left, Duration right) {
  final micros = left.inMicroseconds - right.inMicroseconds;
  return Duration(microseconds: micros.abs());
}

MotionExportInspection _inspectWebpExport(Uint8List bytes) {
  if (bytes.length < 12 ||
      !_inspectMatchesAscii(bytes, 0, 'RIFF') ||
      !_inspectMatchesAscii(bytes, 8, 'WEBP')) {
    throw const FormatException('Expected a RIFF WEBP file.');
  }

  var width = 0;
  var height = 0;
  var loopCount = 1;
  var hasAnimation = false;
  var hasAlpha = false;
  var hasAnimChunk = false;
  final frameDurations = <Duration>[];

  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final tag = _inspectAsciiAt(bytes, offset, 4);
    final size = _inspectReadUint32Le(bytes, offset + 4);
    final payload = offset + 8;
    final payloadEnd = payload + size;
    final chunkEnd = payloadEnd + (size.isOdd ? 1 : 0);
    if (payloadEnd > bytes.length || chunkEnd > bytes.length) {
      throw FormatException('Truncated WebP $tag chunk.');
    }

    if (tag == 'VP8X') {
      if (size < 10) {
        throw const FormatException('Truncated WebP VP8X payload.');
      }
      final flags = bytes[payload];
      hasAnimation = (flags & 0x02) != 0;
      hasAlpha = (flags & 0x10) != 0;
      width = _inspectReadUint24Le(bytes, payload + 4) + 1;
      height = _inspectReadUint24Le(bytes, payload + 7) + 1;
    } else if (tag == 'ANIM') {
      if (size < 6) {
        throw const FormatException('Truncated WebP ANIM payload.');
      }
      hasAnimChunk = true;
      loopCount = _inspectReadUint16Le(bytes, payload + 4);
    } else if (tag == 'ANMF') {
      if (size < 16) {
        throw const FormatException('Truncated WebP ANMF payload.');
      }
      final durationMs = _inspectReadUint24Le(bytes, payload + 12);
      frameDurations.add(Duration(milliseconds: durationMs));
    }

    offset = chunkEnd;
  }

  if (width <= 0 || height <= 0) {
    throw const FormatException('WebP file does not contain VP8X canvas info.');
  }
  if (!hasAnimation || !hasAnimChunk || frameDurations.isEmpty) {
    throw const FormatException('WebP file does not contain animation chunks.');
  }

  return MotionExportInspection(
    format: MotionExportFormat.webp,
    width: width,
    height: height,
    frameDurations: List<Duration>.unmodifiable(frameDurations),
    loopCount: loopCount,
    hasAnimationContainer: hasAnimation && hasAnimChunk,
    hasAlpha: hasAlpha,
  );
}

MotionExportInspection _inspectApngExport(Uint8List bytes) {
  if (bytes.length < _pngSignature.length ||
      !_inspectListMatches(bytes, 0, _pngSignature)) {
    throw const FormatException('Expected a PNG file.');
  }

  var width = 0;
  var height = 0;
  var declaredFrames = 0;
  var loopCount = 1;
  var hasAnimation = false;
  var hasAlpha = false;
  final frameDurations = <Duration>[];

  var offset = _pngSignature.length;
  while (offset + 8 <= bytes.length) {
    final size = _inspectReadUint32Be(bytes, offset);
    final tagOffset = offset + 4;
    final tag = _inspectAsciiAt(bytes, tagOffset, 4);
    final payload = offset + 8;
    final payloadEnd = payload + size;
    final chunkEnd = payloadEnd + 4;
    if (payloadEnd > bytes.length || chunkEnd > bytes.length) {
      throw FormatException('Truncated PNG $tag chunk.');
    }

    if (tag == 'IHDR') {
      if (size < 13) {
        throw const FormatException('Truncated PNG IHDR payload.');
      }
      width = _inspectReadUint32Be(bytes, payload);
      height = _inspectReadUint32Be(bytes, payload + 4);
      final colorType = bytes[payload + 9];
      hasAlpha = colorType == 4 || colorType == 6;
    } else if (tag == 'acTL') {
      if (size < 8) {
        throw const FormatException('Truncated APNG acTL payload.');
      }
      hasAnimation = true;
      declaredFrames = _inspectReadUint32Be(bytes, payload);
      loopCount = _inspectReadUint32Be(bytes, payload + 4);
    } else if (tag == 'fcTL') {
      if (size < 26) {
        throw const FormatException('Truncated APNG fcTL payload.');
      }
      final numerator = _inspectReadUint16Be(bytes, payload + 20);
      final denominator = _inspectReadUint16Be(bytes, payload + 22);
      frameDurations.add(_inspectApngDelay(numerator, denominator));
    } else if (tag == 'IEND') {
      break;
    }

    offset = chunkEnd;
  }

  if (width <= 0 || height <= 0) {
    throw const FormatException('PNG file does not contain IHDR canvas info.');
  }
  if (!hasAnimation || frameDurations.isEmpty) {
    throw const FormatException('PNG file does not contain APNG chunks.');
  }
  if (declaredFrames != 0 && declaredFrames != frameDurations.length) {
    throw FormatException(
      'APNG declared $declaredFrames frames but contains '
      '${frameDurations.length} frame controls.',
    );
  }

  return MotionExportInspection(
    format: MotionExportFormat.apng,
    width: width,
    height: height,
    frameDurations: List<Duration>.unmodifiable(frameDurations),
    loopCount: loopCount,
    hasAnimationContainer: hasAnimation,
    hasAlpha: hasAlpha,
  );
}

Duration _inspectApngDelay(int numerator, int denominator) {
  final safeNumerator = numerator == 0 ? 1 : numerator;
  final safeDenominator = denominator == 0 ? 100 : denominator;
  final micros =
      (safeNumerator * Duration.microsecondsPerSecond / safeDenominator)
          .round();
  return Duration(microseconds: math.max(1, micros));
}

bool _inspectMatchesAscii(Uint8List bytes, int offset, String value) {
  if (offset + value.length > bytes.length) {
    return false;
  }
  for (var i = 0; i < value.length; i++) {
    if (bytes[offset + i] != value.codeUnitAt(i)) {
      return false;
    }
  }
  return true;
}

bool _inspectListMatches(Uint8List bytes, int offset, List<int> value) {
  if (offset + value.length > bytes.length) {
    return false;
  }
  for (var i = 0; i < value.length; i++) {
    if (bytes[offset + i] != value[i]) {
      return false;
    }
  }
  return true;
}

String _inspectAsciiAt(Uint8List bytes, int offset, int length) {
  return String.fromCharCodes(bytes.sublist(offset, offset + length));
}

int _inspectReadUint16Le(Uint8List bytes, int offset) {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

int _inspectReadUint16Be(Uint8List bytes, int offset) {
  return (bytes[offset] << 8) | bytes[offset + 1];
}

int _inspectReadUint24Le(Uint8List bytes, int offset) {
  return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
}

int _inspectReadUint32Le(Uint8List bytes, int offset) {
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}

int _inspectReadUint32Be(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}
