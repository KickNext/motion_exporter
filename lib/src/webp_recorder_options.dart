part of '../motion_exporter.dart';

/// Capture and encoding options for [WebpRecorderController.start].
class WebpRecorderOptions {
  /// Creates recorder options.
  const WebpRecorderOptions({
    this.framesPerSecond = 30,
    this.pixelRatio = 1,
    this.loopCount = 0,
    this.backgroundColor = const ui.Color(0x00000000),
    this.collapseIdenticalFrames = true,
    this.frameBlend = WebpFrameBlend.replace,
    this.frameDispose = WebpFrameDispose.none,
    this.useBackgroundIsolate = true,
    this.maxPendingCaptures = 8,
    this.trimTransparentFrames = true,
    this.trimChangedFrames = true,
  }) : assert(framesPerSecond > 0),
       assert(framesPerSecond <= 240),
       assert(pixelRatio > 0),
       assert(loopCount >= 0),
       assert(loopCount <= 0xffff),
       assert(maxPendingCaptures > 0);

  /// Number of widget snapshots requested per second.
  ///
  /// Capture is synchronized with Flutter frames. Readbacks may overlap up to
  /// [maxPendingCaptures]; new samples are skipped only after that backpressure
  /// limit is reached.
  final int framesPerSecond;

  /// Pixel ratio passed to [RenderRepaintBoundary.toImage].
  ///
  /// Use `1` for logical-size output and lower memory pressure. Use
  /// `View.of(context).devicePixelRatio` when physical display resolution is
  /// required.
  final double pixelRatio;

  /// Animation loop count. `0` means infinite looping.
  final int loopCount;

  /// Canvas background hint stored in the WebP `ANIM` chunk.
  ///
  /// The default is fully transparent.
  final ui.Color backgroundColor;

  /// Merge consecutive identical RGBA frames by increasing frame duration.
  final bool collapseIdenticalFrames;

  /// WebP frame blending mode.
  final WebpFrameBlend frameBlend;

  /// WebP frame disposal mode.
  final WebpFrameDispose frameDispose;

  /// Encode on Flutter's [compute] helper when possible.
  ///
  /// On native targets this moves CPU-heavy WebP encoding away from the UI
  /// isolate. On web, Flutter may run it on the same event loop.
  final bool useBackgroundIsolate;

  /// Maximum number of GPU readback jobs allowed in flight.
  ///
  /// The recorder starts a capture for every requested sample while the number
  /// of pending readbacks is below this limit. If the limit is reached, new
  /// samples are skipped to prevent unbounded memory growth.
  final int maxPendingCaptures;

  /// Store WebP frames as cropped transparent rectangles when encoding.
  ///
  /// Recorder frames are full snapshots, so cropped WebP frames use background
  /// disposal internally to avoid leaving trails from previous frames.
  final bool trimTransparentFrames;

  /// Store WebP frames after the first as changed-pixel rectangles.
  ///
  /// This is useful for opaque or mostly opaque full-snapshot animations where
  /// transparent trimming cannot shrink frames. Changed-frame trimming keeps
  /// the first frame full-size, then encodes only pixels whose RGBA values
  /// differ from the previous full snapshot. It uses WebP replace blending and
  /// no disposal internally so semi-transparent pixels are not blended twice.
  /// Enabled by default because recorder captures are full snapshots.
  final bool trimChangedFrames;

  Duration get _frameDuration {
    final micros = (Duration.microsecondsPerSecond / framesPerSecond).round();
    return Duration(microseconds: micros);
  }
}

/// How a streaming WebP encoder retains the previous frame for changed-frame
/// trimming.
enum WebpPreviousFrameRetentionPolicy {
  /// Copy the previous frame bytes before returning from `addFrame`.
  ///
  /// This is the safe default for streaming encoders because callers may reuse
  /// or mutate their RGBA buffers after handing a frame to the encoder.
  copy,

  /// Keep a reference to the caller-owned previous frame bytes.
  ///
  /// Use this for high-throughput streaming exports only when the frame buffer
  /// will not be mutated or reused until after the next frame is added. It
  /// avoids one full-frame allocation and copy per streamed frame when
  /// changed-frame trimming is enabled.
  reference,
}

/// Options for animated WebP encoding.
class WebpAnimationOptions {
  /// Creates animation encoder options.
  const WebpAnimationOptions({
    this.loopCount = 0,
    this.backgroundColor = const ui.Color(0x00000000),
    this.frameBlend = WebpFrameBlend.replace,
    this.frameDispose = WebpFrameDispose.none,
    this.trimTransparentFrames = true,
    this.trimChangedFrames = false,
    this.previousFrameRetentionPolicy = WebpPreviousFrameRetentionPolicy.copy,
  }) : assert(loopCount >= 0),
       assert(loopCount <= 0xffff);

  /// Animation loop count. `0` means infinite looping.
  final int loopCount;

  /// Canvas background hint stored in the WebP `ANIM` chunk.
  final ui.Color backgroundColor;

  /// WebP frame blending mode.
  final WebpFrameBlend frameBlend;

  /// WebP frame disposal mode.
  final WebpFrameDispose frameDispose;

  /// Store frames as cropped transparent rectangles.
  ///
  /// When enabled, encoded frames use background disposal internally so
  /// full-snapshot transparent animations do not leave trails.
  final bool trimTransparentFrames;

  /// Store frames after the first as changed-pixel rectangles.
  ///
  /// When enabled, [trimTransparentFrames] is ignored for WebP encoding. The
  /// first frame is encoded as a full canvas, then later frames are cropped to
  /// the RGBA difference from the previous full snapshot. This is intended for
  /// full-snapshot captures and preserves replace-style alpha semantics.
  final bool trimChangedFrames;

  /// How streaming WebP encoders retain the previous full frame used for
  /// changed-frame bounds.
  ///
  /// This affects [WebpAnimationStreamEncoder] and
  /// [WebpAnimationFileWriter] only when [trimChangedFrames] is true. The
  /// non-streaming [WebpAnimationEncoder] already receives the whole frame
  /// list and does not need to retain an extra previous-frame snapshot.
  final WebpPreviousFrameRetentionPolicy previousFrameRetentionPolicy;

  _EncodeJob _toJob(List<MotionFrame> frames) {
    return _EncodeJob(
      frames: frames,
      loopCount: loopCount,
      backgroundArgb: backgroundColor.toARGB32(),
      frameBlend: frameBlend,
      frameDispose: frameDispose,
      trimTransparentFrames: trimTransparentFrames,
      trimChangedFrames: trimChangedFrames,
    );
  }
}
