import '../../../core/time_source.dart';

enum PublishState {
  queued,
  waiting,
  running,
  paused,
  interrupted,
  unknown,
  succeeded,
  failed,
  cancelled;

  bool get terminal => switch (this) {
    succeeded || failed || cancelled => true,
    _ => false,
  };
  bool get protectsInput => !terminal;
}

enum BatchState {
  active,
  needsConfirmation,
  succeeded,
  partiallySucceeded,
  cancelled,
  failed,
}

/// SRS 8.2 priority order. Attempts and late evidence are deliberately not
/// members: only the fixed, nonempty publication item set is counted here.
final class BatchSummary {
  factory BatchSummary(Iterable<PublishState> states) {
    final items = states.toList(growable: false);
    if (items.isEmpty) throw ArgumentError('批次必须至少有一个发布项。');
    final total = items.length;
    var succeeded = 0, failed = 0, cancelled = 0, unknown = 0, active = 0;
    for (final item in items) {
      switch (item) {
        case PublishState.succeeded:
          succeeded++;
        case PublishState.failed:
          failed++;
        case PublishState.cancelled:
          cancelled++;
        case PublishState.unknown:
          unknown++;
        default:
          active++;
      }
    }
    final state = active > 0
        ? BatchState.active
        : unknown > 0
        ? BatchState.needsConfirmation
        : succeeded == total
        ? BatchState.succeeded
        : succeeded > 0
        ? BatchState.partiallySucceeded
        : cancelled == total
        ? BatchState.cancelled
        : BatchState.failed;
    return BatchSummary._(
      total,
      state,
      succeeded,
      failed,
      cancelled,
      unknown,
      active,
    );
  }
  const BatchSummary._(
    this.total,
    this.state,
    this.succeeded,
    this.failed,
    this.cancelled,
    this.unknown,
    this.active,
  );
  final int total;
  final BatchState state;
  final int succeeded, failed, cancelled, unknown, active;
}

final class PublishTransitions {
  static const _next = <PublishState, Set<PublishState>>{
    PublishState.queued: {
      PublishState.running,
      PublishState.waiting,
      PublishState.failed,
      PublishState.paused,
      PublishState.cancelled,
    },
    PublishState.waiting: {
      PublishState.queued,
      PublishState.paused,
      PublishState.failed,
      PublishState.cancelled,
    },
    PublishState.running: {
      PublishState.succeeded,
      PublishState.waiting,
      PublishState.failed,
      PublishState.interrupted,
      PublishState.unknown,
      PublishState.cancelled,
    },
    PublishState.paused: {
      PublishState.queued,
      PublishState.waiting,
      PublishState.cancelled,
    },
    PublishState.interrupted: {
      PublishState.queued,
      PublishState.waiting,
      PublishState.failed,
      PublishState.cancelled,
    },
    PublishState.unknown: {
      PublishState.succeeded,
      PublishState.failed,
      PublishState.cancelled,
    },
  };
  static bool permits(PublishState from, PublishState to) =>
      _next[from]?.contains(to) ?? false;

  /// Called after acquiring the exclusive library lock on reopen. Existing
  /// running rows are evidence of an ended local attempt, never live execution.
  static PublishState recoverRunning({
    required bool remoteSideEffectPossible,
  }) => remoteSideEffectPossible
      ? PublishState.unknown
      : PublishState.interrupted;
}

enum RetryableFailure { network, rateLimited, temporaryService, other }

/// The scheduler alone may create the next attempt. A transport's timeout or
/// status code cannot establish absence of remote side effects by itself.
final class AutomaticRetryPolicy {
  static Duration? delay({
    required int completedAttempts,
    required RetryableFailure failure,
    required bool confirmedNoUncertainSideEffect,
    Duration? retryAfter,
  }) {
    if (completedAttempts < 1 || completedAttempts > 4) {
      throw ArgumentError.value(completedAttempts, 'completedAttempts');
    }
    if (!confirmedNoUncertainSideEffect ||
        failure == RetryableFailure.other ||
        completedAttempts == 4) {
      return null;
    }
    final base = Duration(seconds: 1 << completedAttempts);
    return retryAfter != null && retryAfter > base ? retryAfter : base;
  }
}

enum DispatchCondition { network, authorization, dependency, storage, system }

final class DispatchConditions {
  DispatchConditions(Iterable<DispatchCondition> unmet)
    : unmet = Set.unmodifiable(unmet);
  final Set<DispatchCondition> unmet;
  bool permits({required bool paused, required bool cancelled}) =>
      !paused && !cancelled && unmet.isEmpty;
}

enum RuntimeLimit { inactivity, totalRunning }

/// One instance follows one publication item across actual attempts. Persist
/// accumulatedRunning after stopping each attempt; no Stopwatch origin is
/// persisted. The future scheduler must still wire timers and durable events.
final class ExecutionBudget {
  ExecutionBudget(this.time, {Duration accumulatedRunning = Duration.zero})
    : _accumulated = accumulatedRunning {
    if (accumulatedRunning.isNegative) {
      throw ArgumentError.value(accumulatedRunning, 'accumulatedRunning');
    }
  }
  static const inactivityLimit = Duration(seconds: 120);
  static const totalLimit = Duration(minutes: 30);
  final TimeSource time;
  Duration _accumulated;
  Duration? _started, _lastActivity;
  bool get running => _started != null;
  Duration get accumulatedRunning {
    final start = _started;
    return _accumulated + (start == null ? Duration.zero : _since(start));
  }

  Duration _since(Duration start) {
    final delta = time.monotonic - start;
    if (delta.isNegative) throw StateError('单调时钟倒退。');
    return delta;
  }

  void beginAttempt() {
    if (running) throw StateError('执行已经开始。');
    if (_accumulated >= totalLimit) {
      throw StateError('累计实际执行时间已达上限。');
    }
    _started = _lastActivity = time.monotonic;
  }

  void activity() {
    if (!running) return;
    _since(_lastActivity!);
    _lastActivity = time.monotonic;
  }

  void stopAttempt() {
    if (!running) return;
    _accumulated = accumulatedRunning;
    _started = _lastActivity = null;
  }

  RuntimeLimit? get reached {
    if (!running) return null;
    if (accumulatedRunning >= totalLimit) return RuntimeLimit.totalRunning;
    if (_since(_lastActivity!) >= inactivityLimit) {
      return RuntimeLimit.inactivity;
    }
    return null;
  }
}
