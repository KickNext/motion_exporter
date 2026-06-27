part of '../motion_exporter.dart';

/// Logical loop-boundary signal for recording one complete animation cycle.
///
/// A recorder cannot reliably infer semantic animation loops from pixels
/// without expensive and fragile image analysis. Use this signal when the
/// animated widget already knows where its loop boundary is.
class MotionLoopSignal extends ChangeNotifier {
  int _count = 0;

  /// Number of loop boundaries emitted so far.
  int get count => _count;

  /// Registers [listener] for loop-boundary changes.
  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
  }

  /// Removes a loop-boundary [listener].
  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
  }

  /// Releases listener resources held by this signal.
  @override
  void dispose() {
    super.dispose();
  }

  /// Emits a loop-boundary event.
  void markBoundary() {
    _count++;
    notifyListeners();
  }

  /// Completes when a boundary newer than [afterCount] is emitted.
  ///
  /// When [afterCount] is omitted, this waits for the next boundary after the
  /// current [count]. The returned value is the boundary count that completed
  /// the wait.
  ///
  /// When [timeout] is provided and no matching boundary arrives in time, the
  /// returned future completes with [TimeoutException].
  ///
  /// When [cancelSignal] completes before a matching boundary arrives, the
  /// returned future completes with [MotionLoopWaitCanceledException]. If the
  /// signal completes with an error, that error is forwarded instead.
  Future<int> waitForNextBoundary({
    int? afterCount,
    Duration? timeout,
    Future<void>? cancelSignal,
  }) {
    final observedCount = afterCount ?? _count;
    if (_count > observedCount) {
      return Future<int>.value(_count);
    }

    final completer = Completer<int>();
    Timer? timer;
    late VoidCallback listener;

    void cleanup() {
      timer?.cancel();
      removeListener(listener);
    }

    void complete(int boundaryCount) {
      if (completer.isCompleted) {
        return;
      }
      cleanup();
      completer.complete(boundaryCount);
    }

    void completeError(Object error, [StackTrace? stackTrace]) {
      if (completer.isCompleted) {
        return;
      }
      cleanup();
      if (stackTrace == null) {
        completer.completeError(error);
      } else {
        completer.completeError(error, stackTrace);
      }
    }

    listener = () {
      if (_count <= observedCount || completer.isCompleted) {
        return;
      }
      complete(_count);
    };
    addListener(listener);

    if (timeout != null) {
      timer = Timer(timeout, () {
        if (completer.isCompleted) {
          return;
        }
        completeError(
          TimeoutException('Timed out waiting for a loop boundary.', timeout),
        );
      });
    }

    if (cancelSignal != null) {
      unawaited(
        cancelSignal.then<void>(
          (_) => completeError(const MotionLoopWaitCanceledException()),
          onError: completeError,
        ),
      );
    }

    if (_count > observedCount && !completer.isCompleted) {
      complete(_count);
    }

    return completer.future;
  }
}

/// Thrown when a pending loop-boundary wait is canceled by caller intent.
class MotionLoopWaitCanceledException implements Exception {
  /// Creates a loop wait cancellation exception.
  const MotionLoopWaitCanceledException([
    this.message = 'Loop boundary wait was canceled.',
  ]);

  /// Developer-facing cancellation reason.
  final String message;

  @override
  String toString() {
    return 'MotionLoopWaitCanceledException: $message';
  }
}
