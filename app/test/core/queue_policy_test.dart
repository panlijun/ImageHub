import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/time_source.dart';
import 'package:imagehost/features/upload/domain/queue_policy.dart';

class _Time implements TimeSource {
  @override
  DateTime utcNow = DateTime.utc(2026, 10, 5);
  @override
  Duration monotonic = Duration.zero;
  void advance(Duration duration) => monotonic += duration;
}

void main() {
  test('UT-065 six batch priorities and fixed item counts', () {
    final examples = <List<PublishState>, BatchState>{
      [PublishState.running, PublishState.unknown]: BatchState.active,
      [PublishState.unknown, PublishState.succeeded]:
          BatchState.needsConfirmation,
      [PublishState.succeeded, PublishState.succeeded]: BatchState.succeeded,
      [PublishState.succeeded, PublishState.cancelled]:
          BatchState.partiallySucceeded,
      [PublishState.cancelled, PublishState.cancelled]: BatchState.cancelled,
      [PublishState.failed, PublishState.cancelled]: BatchState.failed,
    };
    for (final entry in examples.entries) {
      expect(BatchSummary(entry.key).state, entry.value);
    }
    expect(() => BatchSummary([]), throwsArgumentError);
  });
  test(
    'UT-045/065 all 729 ordered triples aggregate independently of order',
    () {
      for (final a in PublishState.values) {
        for (final b in PublishState.values) {
          for (final c in PublishState.values) {
            final summary = BatchSummary([a, b, c]);
            expect(summary.state, BatchSummary([c, a, b]).state);
            expect(summary.state, BatchSummary([b, c, a]).state);
            expect(summary.total, 3);
            expect(
              summary.succeeded +
                  summary.failed +
                  summary.cancelled +
                  summary.unknown +
                  summary.active,
              summary.total,
            );
          }
        }
      }
    },
  );
  test('UT-055/056 terminal states cannot be changed by cancellation or late events', () {
    for (final terminal in [
      PublishState.succeeded,
      PublishState.failed,
      PublishState.cancelled,
    ]) {
      for (final next in PublishState.values) {
        expect(PublishTransitions.permits(terminal, next), isFalse);
      }
    }
    expect(
      PublishTransitions.permits(PublishState.unknown, PublishState.queued),
      isFalse,
    );
    expect(
      PublishTransitions.permits(PublishState.unknown, PublishState.succeeded),
      isTrue,
    );
    expect(PublishState.unknown.protectsInput, isTrue);
    // An actual IO lease separately protects a cancelled item until IO ends.
    expect(PublishState.cancelled.protectsInput, isFalse);
  });
  test(
    'UT-054/057 no running pause and cancellation always stops later dispatch',
    () {
      expect(
        PublishTransitions.permits(PublishState.running, PublishState.paused),
        isFalse,
      );
      expect(
        PublishTransitions.permits(PublishState.queued, PublishState.paused),
        isTrue,
      );
      final ready = DispatchConditions([]);
      expect(ready.permits(paused: false, cancelled: false), isTrue);
      expect(ready.permits(paused: true, cancelled: false), isFalse);
      expect(ready.permits(paused: false, cancelled: true), isFalse);
    },
  );
  test('UT-059/060 initial plus three retries; uncertainty and permanent errors refuse', () {
    for (final failure in RetryableFailure.values) {
      for (var attempt = 1; attempt <= 4; attempt++) {
        expect(
          AutomaticRetryPolicy.delay(
            completedAttempts: attempt,
            failure: failure,
            confirmedNoUncertainSideEffect: false,
          ),
          isNull,
        );
        final delay = AutomaticRetryPolicy.delay(
          completedAttempts: attempt,
          failure: failure,
          confirmedNoUncertainSideEffect: true,
        );
        expect(
          delay,
          attempt == 4 || failure == RetryableFailure.other
              ? null
              : Duration(seconds: 1 << attempt),
        );
      }
    }
    expect(
      () => AutomaticRetryPolicy.delay(
        completedAttempts: 0,
        failure: RetryableFailure.network,
        confirmedNoUncertainSideEffect: true,
      ),
      throwsArgumentError,
    );
  });
  test(
    'UT-061 every unmet condition blocks, server retry delay never shortened',
    () {
      for (final condition in DispatchCondition.values) {
        expect(
          DispatchConditions([condition])
              .permits(paused: false, cancelled: false),
          isFalse,
        );
      }
      expect(
        AutomaticRetryPolicy.delay(
          completedAttempts: 2,
          failure: RetryableFailure.rateLimited,
          confirmedNoUncertainSideEffect: true,
          retryAfter: const Duration(seconds: 20),
        ),
        const Duration(seconds: 20),
      );
      expect(
        AutomaticRetryPolicy.delay(
          completedAttempts: 2,
          failure: RetryableFailure.rateLimited,
          confirmedNoUncertainSideEffect: true,
          retryAfter: const Duration(seconds: 1),
        ),
        const Duration(seconds: 4),
      );
    },
  );
  test('UT-062 reopen never pretends an old running item is live', () {
    expect(
      PublishTransitions.recoverRunning(remoteSideEffectPossible: true),
      PublishState.unknown,
    );
    expect(
      PublishTransitions.recoverRunning(remoteSideEffectPossible: false),
      PublishState.interrupted,
    );
  });
  test('UT-067 actual execution excludes waiting and wall clock jumps', () {
    final time = _Time();
    final budget = ExecutionBudget(time);
    time.advance(const Duration(hours: 1));
    budget.beginAttempt();
    time.advance(const Duration(seconds: 20));
    time.utcNow = DateTime.utc(2000);
    expect(budget.accumulatedRunning, const Duration(seconds: 20));
    budget.stopAttempt();
    time.advance(const Duration(days: 1));
    expect(budget.accumulatedRunning, const Duration(seconds: 20));
    budget.beginAttempt();
    time.advance(const Duration(seconds: 40));
    budget.stopAttempt();
    budget.stopAttempt();
    expect(budget.accumulatedRunning, const Duration(minutes: 1));
  });
  test('UT-068 inactivity uses real activity, boundary 119/120 seconds', () {
    final time = _Time();
    final budget = ExecutionBudget(time)..beginAttempt();
    time.advance(const Duration(seconds: 119));
    expect(budget.reached, isNull);
    budget.activity();
    time.advance(const Duration(seconds: 119));
    expect(budget.reached, isNull);
    time.advance(const Duration(seconds: 1));
    expect(budget.reached, RuntimeLimit.inactivity);
  });
  test('UT-068 total actual 30 minutes spans attempts; waits do not trigger watchdog', () {
    final time = _Time();
    final budget = ExecutionBudget(
      time,
      accumulatedRunning: const Duration(minutes: 29, seconds: 59),
    );
    time.advance(const Duration(days: 3));
    expect(budget.reached, isNull);
    budget.beginAttempt();
    time.advance(const Duration(seconds: 1));
    budget.activity();
    expect(budget.reached, RuntimeLimit.totalRunning);
    budget.stopAttempt();
    expect(budget.accumulatedRunning, const Duration(minutes: 30));
    expect(budget.beginAttempt, throwsStateError);
    expect(
      ExecutionBudget(
        time,
        accumulatedRunning: const Duration(minutes: 30),
      ).beginAttempt,
      throwsStateError,
    );
  });
}
