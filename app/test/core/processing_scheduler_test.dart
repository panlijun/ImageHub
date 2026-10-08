import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/processing/application/processing_scheduler.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';

const mib = 1024 * 1024;

Matcher failure(ProcessingFailureKind kind) =>
    isA<ProcessingFailure>().having((value) => value.kind, 'kind', kind);

Future<void> microtasks() async {
  await Future<void>.value();
  await Future<void>.value();
}

void main() {
  test('UT-053 default one candidate budget with honest reason', () async {
    final scheduler = ProcessingScheduler(totalMemoryBudgetBytes: 512 * mib);
    expect(scheduler.configuredConcurrency, 1);
    expect(scheduler.effectiveConcurrency, 1);
    expect(scheduler.perJobMemoryBudgetBytes, 512 * mib);
    expect(scheduler.activeCount, 0);
    expect(scheduler.budgetReason, contains('候选总内存预算'));
    expect(scheduler.budgetReason, contains('有效并发 1'));
    expect(scheduler.budgetReason, contains('尚待测量'));
    final permit = await scheduler.acquire();
    expect(permit.memoryBudgetBytes, 512 * mib);
    expect(scheduler.activeCount, 1);
    permit.release();
    await scheduler.close();
  });

  for (final specification in [
    (64 * mib, 4, 1),
    (128 * mib, 4, 1),
    (255 * mib, 4, 1),
    (256 * mib, 4, 2),
    (384 * mib, 4, 3),
    (512 * mib, 4, 4),
    (1024 * mib, 4, 4),
    (512 * mib, 2, 2),
  ]) {
    test('UT-053 effective concurrency budget $specification', () async {
      final scheduler = ProcessingScheduler(
        totalMemoryBudgetBytes: specification.$1,
        concurrency: specification.$2,
      );
      expect(scheduler.effectiveConcurrency, specification.$3);
      expect(
        scheduler.perJobMemoryBudgetBytes,
        specification.$1 ~/ specification.$3,
      );
      await scheduler.close();
    });
  }

  test(
    'UT-102 invalid concurrency and total budget reject without clamp',
    () async {
      for (final concurrency in [-1, 0, 5, 100]) {
        expect(
          () => ProcessingScheduler(
            totalMemoryBudgetBytes: 512 * mib,
            concurrency: concurrency,
          ),
          throwsA(failure(ProcessingFailureKind.invalidParameters)),
        );
      }
      for (final budget in [-1, 0]) {
        expect(
          () => ProcessingScheduler(totalMemoryBudgetBytes: budget),
          throwsA(failure(ProcessingFailureKind.invalidParameters)),
        );
      }
      final scheduler = ProcessingScheduler(totalMemoryBudgetBytes: 512 * mib);
      for (final concurrency in [0, 5]) {
        expect(
          () => scheduler.configure(concurrency),
          throwsA(failure(ProcessingFailureKind.invalidParameters)),
        );
        expect(scheduler.configuredConcurrency, 1);
      }
      await scheduler.close();
    },
  );

  test('UT-102 runtime floating values are rejected as non-integers', () async {
    dynamic floating = 2.0;
    expect(
      () => ProcessingScheduler(
        totalMemoryBudgetBytes: 512 * mib,
        concurrency: floating,
      ),
      throwsA(isA<TypeError>()),
    );
    expect(
      () => ProcessingScheduler(totalMemoryBudgetBytes: floating),
      throwsA(isA<TypeError>()),
    );
    final scheduler = ProcessingScheduler(totalMemoryBudgetBytes: 512 * mib);
    expect(() => scheduler.configure(floating), throwsA(isA<TypeError>()));
    expect(scheduler.configuredConcurrency, 1);
    await scheduler.close();
  });

  test('UT-087 waiting grants stay FIFO without implicit extra work', () async {
    final scheduler = ProcessingScheduler(totalMemoryBudgetBytes: 512 * mib);
    final first = await scheduler.acquire();
    final grants = <int>[];
    final secondFuture = scheduler.acquire().then((permit) {
      grants.add(2);
      return permit;
    });
    final thirdFuture = scheduler.acquire().then((permit) {
      grants.add(3);
      return permit;
    });
    await microtasks();
    expect(grants, isEmpty);
    first.release();
    final second = await secondFuture;
    expect(grants, [2]);
    expect(scheduler.activeCount, 1);
    second.release();
    final third = await thirdFuture;
    expect(grants, [2, 3]);
    third.release();
    await scheduler.close();
  });

  test(
    'UT-087 decreasing concurrency preserves active frozen budgets',
    () async {
      final scheduler = ProcessingScheduler(
        totalMemoryBudgetBytes: 512 * mib,
        concurrency: 4,
      );
      final first = await scheduler.acquire();
      final second = await scheduler.acquire();
      scheduler.configure(1);
      expect(scheduler.activeCount, 2);
      expect(first.memoryBudgetBytes, 128 * mib);
      expect(second.memoryBudgetBytes, 128 * mib);
      expect(scheduler.perJobMemoryBudgetBytes, 512 * mib);
      ProcessingPermit? waiting;
      final waitingFuture = scheduler.acquire().then(
        (value) => waiting = value,
      );
      first.release();
      await microtasks();
      expect(scheduler.activeCount, 1);
      expect(waiting, isNull);
      second.release();
      await waitingFuture;
      expect(waiting!.memoryBudgetBytes, 512 * mib);
      waiting!.release();
      await scheduler.close();
    },
  );

  test(
    'UT-087 increasing concurrency cannot overcommit old reservation',
    () async {
      final scheduler = ProcessingScheduler(totalMemoryBudgetBytes: 512 * mib);
      final old = await scheduler.acquire();
      scheduler.configure(4);
      final grants = <ProcessingPermit>[];
      final futures = [
        for (var i = 0; i < 4; i++)
          scheduler.acquire().then((permit) => grants.add(permit)),
      ];
      await microtasks();
      expect(grants, isEmpty);
      expect(old.memoryBudgetBytes, 512 * mib);
      expect(scheduler.activeCount, 1);
      old.release();
      await Future.wait(futures);
      expect(grants, hasLength(4));
      expect(scheduler.activeCount, 4);
      expect(
        grants.fold<int>(0, (sum, p) => sum + p.memoryBudgetBytes),
        512 * mib,
      );
      for (final permit in grants) {
        permit.release();
      }
      await scheduler.close();
    },
  );

  test(
    'UT-087 configure can dispatch against available frozen headroom',
    () async {
      final scheduler = ProcessingScheduler(
        totalMemoryBudgetBytes: 512 * mib,
        concurrency: 2,
      );
      final first = await scheduler.acquire();
      final second = await scheduler.acquire();
      ProcessingPermit? third;
      final queued = scheduler.acquire().then((value) => third = value);
      scheduler.configure(4);
      await microtasks();
      expect(third, isNull);
      first.release();
      await queued;
      expect(second.memoryBudgetBytes, 256 * mib);
      expect(third!.memoryBudgetBytes, 128 * mib);
      expect(second.memoryBudgetBytes + third!.memoryBudgetBytes, 384 * mib);
      second.release();
      third!.release();
      await scheduler.close();
    },
  );

  test('UT-053 integer division does not exceed non-divisible total', () async {
    final total = 384 * mib + 1;
    final scheduler = ProcessingScheduler(
      totalMemoryBudgetBytes: total,
      concurrency: 3,
    );
    final permits = [for (var i = 0; i < 3; i++) await scheduler.acquire()];
    final reserved = permits.fold<int>(
      0,
      (sum, p) => sum + p.memoryBudgetBytes,
    );
    expect(reserved, lessThanOrEqualTo(total));
    expect(total - reserved, 1);
    for (final permit in permits) {
      permit.release();
    }
    await scheduler.close();
  });

  test(
    'UT-102 large integer reservation cannot overflow into a grant',
    () async {
      const total = 0x7fffffffffffffff;
      final scheduler = ProcessingScheduler(totalMemoryBudgetBytes: total);
      final first = await scheduler.acquire();
      scheduler.configure(4);
      ProcessingPermit? next;
      final queued = scheduler.acquire().then((value) => next = value);
      await microtasks();
      expect(next, isNull);
      expect(first.memoryBudgetBytes, total);
      first.release();
      await queued;
      expect(next!.memoryBudgetBytes, total ~/ 4);
      next!.release();
      await scheduler.close();
    },
  );

  test(
    'UT-087 queued cancellation removes middle item and preserves FIFO',
    () async {
      final scheduler = ProcessingScheduler(totalMemoryBudgetBytes: 512 * mib);
      final active = await scheduler.acquire();
      final cancelledToken = CancellationToken();
      final cancelled = expectLater(
        scheduler.acquire(cancellation: cancelledToken),
        throwsA(failure(ProcessingFailureKind.cancelled)),
      );
      final successor = scheduler.acquire();
      cancelledToken.cancel();
      await cancelled;
      expect(scheduler.activeCount, 1);
      active.release();
      final permit = await successor;
      expect(scheduler.activeCount, 1);
      permit.release();
      await scheduler.close();
    },
  );

  test(
    'UT-087 synchronous cancellation wins before release dispatch callback',
    () async {
      final scheduler = ProcessingScheduler(totalMemoryBudgetBytes: 512 * mib);
      final active = await scheduler.acquire();
      final token = CancellationToken();
      final cancelled = expectLater(
        scheduler.acquire(cancellation: token),
        throwsA(failure(ProcessingFailureKind.cancelled)),
      );
      token.cancel();
      active.release();
      await cancelled;
      expect(scheduler.activeCount, 0);
      await scheduler.close();
    },
  );

  test(
    'UT-087 cancellation after grant never releases actual active budget',
    () async {
      final scheduler = ProcessingScheduler(totalMemoryBudgetBytes: 512 * mib);
      final token = CancellationToken();
      final granted = scheduler.acquire(cancellation: token);
      token.cancel();
      final permit = await granted;
      await token.whenCancelled;
      expect(scheduler.activeCount, 1);
      var closed = false;
      final closing = scheduler.close().then((_) => closed = true);
      await microtasks();
      expect(closed, false);
      permit.release();
      await closing;
      expect(closed, true);
    },
  );

  test('UT-087 pre-cancelled token never receives a permit', () async {
    final scheduler = ProcessingScheduler(totalMemoryBudgetBytes: 512 * mib);
    final token = CancellationToken()..cancel();
    await expectLater(
      scheduler.acquire(cancellation: token),
      throwsA(failure(ProcessingFailureKind.cancelled)),
    );
    expect(scheduler.activeCount, 0);
    await scheduler.close();
  });

  test(
    'UT-087 cancellation future is stable idempotent synchronous flag',
    () async {
      final token = CancellationToken();
      final future = token.whenCancelled;
      var notifications = 0;
      future.then((_) => notifications++);
      expect(identical(future, token.whenCancelled), true);
      expect(token.isCancelled, false);
      token.cancel();
      expect(token.isCancelled, true);
      expect(
        token.throwIfCancelled,
        throwsA(
          isA<ResourceFailure>().having(
            (e) => e.kind,
            'kind',
            FailureKind.cancelled,
          ),
        ),
      );
      token.cancel();
      await future;
      await microtasks();
      expect(notifications, 1);
    },
  );

  test('UT-087 cancellation and scheduler create no polling timer', () async {
    var timers = 0;
    await runZoned(
      () async {
        final scheduler = ProcessingScheduler(
          totalMemoryBudgetBytes: 512 * mib,
        );
        final active = await scheduler.acquire();
        final token = CancellationToken();
        final cancelled = expectLater(
          scheduler.acquire(cancellation: token),
          throwsA(failure(ProcessingFailureKind.cancelled)),
        );
        token.cancel();
        await cancelled;
        active.release();
        await scheduler.close();
      },
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          timers++;
          return parent.createTimer(zone, duration, callback);
        },
        createPeriodicTimer: (self, parent, zone, duration, callback) {
          timers++;
          return parent.createPeriodicTimer(zone, duration, callback);
        },
      ),
    );
    expect(timers, 0);
  });

  test(
    'UT-087 close rejects queue and waits for every active real release',
    () async {
      final scheduler = ProcessingScheduler(
        totalMemoryBudgetBytes: 512 * mib,
        concurrency: 2,
      );
      final first = await scheduler.acquire();
      final second = await scheduler.acquire();
      final queued = expectLater(
        scheduler.acquire(),
        throwsA(failure(ProcessingFailureKind.cancelled)),
      );
      final closing = scheduler.close();
      expect(identical(closing, scheduler.close()), true);
      await queued;
      var drained = false;
      closing.then((_) => drained = true);
      await expectLater(
        scheduler.acquire(),
        throwsA(failure(ProcessingFailureKind.cancelled)),
      );
      expect(
        () => scheduler.configure(1),
        throwsA(failure(ProcessingFailureKind.cancelled)),
      );
      first.release();
      await microtasks();
      expect(drained, false);
      expect(scheduler.activeCount, 1);
      second.release();
      await closing;
      expect(scheduler.activeCount, 0);
      expect(drained, true);
    },
  );

  test('UT-087 release is idempotent and cannot release a successor', () async {
    final scheduler = ProcessingScheduler(totalMemoryBudgetBytes: 512 * mib);
    final first = await scheduler.acquire();
    final waiting = scheduler.acquire();
    first.release();
    final second = await waiting;
    first.release();
    first.release();
    expect(scheduler.activeCount, 1);
    second.release();
    second.release();
    expect(scheduler.activeCount, 0);
    await scheduler.close();
  });

  test('UT-087 empty close drains and remains closed', () async {
    final scheduler = ProcessingScheduler(totalMemoryBudgetBytes: 512 * mib);
    await scheduler.close();
    await scheduler.close();
    expect(scheduler.activeCount, 0);
    await expectLater(
      scheduler.acquire(),
      throwsA(failure(ProcessingFailureKind.cancelled)),
    );
  });
}
