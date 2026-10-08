import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/features/processing/application/processing_scheduler.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';

const _mib = 1024 * 1024;

Future<void> _flush() async {
  await Future<void>.value();
  await Future<void>.value();
}

void main() {
  test('NFR-003 UT-101 pressure preserves frozen running budgets and FIFO until real releases', () async {
    final scheduler = ProcessingScheduler(
      totalMemoryBudgetBytes: 512 * _mib,
      concurrency: 2,
    );
    final first = await scheduler.acquire();
    final second = await scheduler.acquire();
    final order = <int>[];
    final third = scheduler.acquire().then((permit) {
      order.add(3);
      return permit;
    });
    final fourth = scheduler.acquire().then((permit) {
      order.add(4);
      return permit;
    });
    scheduler.reportMemoryPressure();
    expect(scheduler.effectiveTotalMemoryBudgetBytes, 128 * _mib);
    expect(scheduler.configuredConcurrency, 2);
    expect(scheduler.effectiveConcurrency, 1);
    expect(first.memoryBudgetBytes, 256 * _mib);
    expect(second.memoryBudgetBytes, 256 * _mib);
    scheduler.configure(4);
    scheduler.reportMemoryPressure();
    expect(scheduler.configuredConcurrency, 4);
    expect(scheduler.effectiveConcurrency, 1);
    first.release();
    await _flush();
    expect(order, isEmpty);
    expect(scheduler.activeCount, 1);
    second.release();
    final thirdPermit = await third;
    expect(order, [3]);
    expect(thirdPermit.memoryBudgetBytes, 128 * _mib);
    await _flush();
    expect(order, [3]);
    thirdPermit.release();
    final fourthPermit = await fourth;
    expect(order, [3, 4]);
    expect(fourthPermit.memoryBudgetBytes, 128 * _mib);
    fourthPermit.release();
    await scheduler.close();
  });

  test('NFR-003 UT-101 pressure never increases an already lower budget and reports candidate limits', () async {
    final scheduler = ProcessingScheduler(
      totalMemoryBudgetBytes: 64 * _mib,
      concurrency: 4,
    );
    var notifications = 0;
    final subscription = scheduler.changes.listen((_) => notifications++);
    scheduler.reportMemoryPressure();
    scheduler.reportMemoryPressure();
    await _flush();
    expect(notifications, 1);
    expect(scheduler.memoryPressureLimited, true);
    expect(scheduler.totalMemoryBudgetBytes, 64 * _mib);
    expect(scheduler.effectiveTotalMemoryBudgetBytes, 64 * _mib);
    expect(scheduler.budgetReason, contains('系统已报告内存压力'));
    expect(scheduler.budgetReason, contains('本次资料库会话保持降载'));
    expect(scheduler.budgetReason, contains('候选'));
    expect(scheduler.budgetReason, contains('尚待测量'));
    final permit = await scheduler.acquire();
    expect(permit.memoryBudgetBytes, 64 * _mib);
    permit.release();
    await subscription.cancel();
    await scheduler.close();
  });

  test('NFR-003 UT-101 close rejects queued work and ignores late pressure while draining old permit', () async {
    final scheduler = ProcessingScheduler(totalMemoryBudgetBytes: 512 * _mib);
    final running = await scheduler.acquire();
    scheduler.reportMemoryPressure();
    final queuedFailure = expectLater(
      scheduler.acquire(),
      throwsA(isA<ProcessingFailure>()),
    );
    var ended = false;
    final eventsDone = Completer<void>();
    scheduler.changes.listen((_) {}, onDone: eventsDone.complete);
    final close = scheduler.close();
    close.then((_) => ended = true);
    expect(identical(close, scheduler.close()), true);
    await queuedFailure;
    scheduler.reportMemoryPressure();
    await _flush();
    expect(ended, false);
    expect(running.memoryBudgetBytes, 512 * _mib);
    running.release();
    await close;
    await eventsDone.future;
    expect(ended, true);
  });
}
