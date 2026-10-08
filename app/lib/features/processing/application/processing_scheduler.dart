import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import '../../../core/platform_resource.dart';
import '../domain/processing_models.dart';

/// Reserves candidate pixel budgets until the caller's real work has drained.
/// This scheduler has no database, file or network ownership of its own.
final class ProcessingScheduler {
  ProcessingScheduler({
    required this.totalMemoryBudgetBytes,
    int concurrency = 1,
  }) : _configuredConcurrency = concurrency {
    if (totalMemoryBudgetBytes <= 0) throw _invalidConfiguration;
    _validateConcurrency(concurrency);
  }

  static const _candidateMinimumBytes = 128 * 1024 * 1024;
  static const _invalidConfiguration = ProcessingFailure(
    ProcessingFailureKind.invalidParameters,
    '处理并发必须是 1–4 的整数，总候选内存预算必须大于零。',
  );
  static const _closedFailure = ProcessingFailure(
    ProcessingFailureKind.cancelled,
    '处理调度器已关闭，等待中的处理未开始。',
  );
  static const _cancelledFailure = ProcessingFailure(
    ProcessingFailureKind.cancelled,
    '等待中的处理已取消，未开始像素工作。',
  );

  final int totalMemoryBudgetBytes;
  int _configuredConcurrency;
  final Queue<_PendingProcessing> _pending = Queue<_PendingProcessing>();
  int _activeCount = 0;
  int _reservedBytes = 0;
  Completer<void>? _closing;
  Future<void>? _closeResult;
  bool _memoryPressureLimited = false;
  final _changes = StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;
  bool get memoryPressureLimited => _memoryPressureLimited;
  int get effectiveTotalMemoryBudgetBytes => _memoryPressureLimited
      ? math.min(totalMemoryBudgetBytes, _candidateMinimumBytes)
      : totalMemoryBudgetBytes;
  int get configuredConcurrency => _configuredConcurrency;
  int get effectiveConcurrency => math.min(
    _configuredConcurrency,
    math.max(
      1,
      math.min(4, effectiveTotalMemoryBudgetBytes ~/ _candidateMinimumBytes),
    ),
  );
  int get perJobMemoryBudgetBytes =>
      effectiveTotalMemoryBudgetBytes ~/ effectiveConcurrency;
  int get activeCount => _activeCount;

  String get budgetReason =>
      '${_memoryPressureLimited ? '系统已报告内存压力，本次资料库会话保持降载；已运行工作保留原预算，后续工作等待其真实释放。' : ''}'
      '候选总内存预算 $effectiveTotalMemoryBudgetBytes 字节；'
      '有效并发 $effectiveConcurrency；'
      '每项候选预算 $perJobMemoryBudgetBytes 字节。实际平台性能尚待测量。';

  static void _validateConcurrency(int value) {
    if (value < 1 || value > 4) throw _invalidConfiguration;
  }

  void configure(int concurrency) {
    if (_closing != null) throw _closedFailure;
    _validateConcurrency(concurrency);
    _configuredConcurrency = concurrency;
    _dispatch();
    _changes.add(null);
  }

  /// Latches for this scheduler's session. Settings and replacement cannot
  /// restore the original budget, and existing permits remain immutable.
  void reportMemoryPressure() {
    if (_closing != null || _memoryPressureLimited) return;
    _memoryPressureLimited = true;
    _dispatch();
    _changes.add(null);
  }

  Future<ProcessingPermit> acquire({CancellationToken? cancellation}) {
    if (_closing != null) return Future.error(_closedFailure);
    if (cancellation?.isCancelled ?? false) {
      return Future.error(_cancelledFailure);
    }
    final request = _PendingProcessing(cancellation);
    _pending.addLast(request);
    cancellation?.whenCancelled.then((_) {
      if (!request.pending) return;
      _pending.remove(request);
      request.pending = false;
      request.completion.completeError(_cancelledFailure);
      _dispatch();
    });
    _dispatch();
    return request.completion.future;
  }

  void _dispatch() {
    if (_closing != null) return;
    while (_pending.isNotEmpty) {
      final request = _pending.first;
      // Cancellation's synchronous flag closes the race with its future callback.
      if (request.cancellation?.isCancelled ?? false) {
        _pending.removeFirst();
        request.pending = false;
        request.completion.completeError(_cancelledFailure);
        continue;
      }
      final budget = perJobMemoryBudgetBytes;
      if (_activeCount >= effectiveConcurrency ||
          _reservedBytes > effectiveTotalMemoryBudgetBytes - budget) {
        return;
      }
      _pending.removeFirst();
      request.pending = false;
      _activeCount++;
      _reservedBytes += budget;
      request.completion.complete(ProcessingPermit._(this, budget));
    }
  }

  void _release(int reservedBytes) {
    _activeCount--;
    _reservedBytes -= reservedBytes;
    if (_closing != null) {
      if (_activeCount == 0 && !_closing!.isCompleted) _closing!.complete();
    } else {
      _dispatch();
    }
  }

  Future<void> close() {
    if (_closeResult != null) return _closeResult!;
    _closing = Completer<void>();
    _closeResult = _closing!.future.whenComplete(_changes.close);
    while (_pending.isNotEmpty) {
      final request = _pending.removeFirst();
      request.pending = false;
      request.completion.completeError(_closedFailure);
    }
    if (_activeCount == 0) _closing!.complete();
    return _closeResult!;
  }
}

final class ProcessingPermit {
  ProcessingPermit._(this._scheduler, this.memoryBudgetBytes);
  final ProcessingScheduler _scheduler;
  final int memoryBudgetBytes;
  bool _released = false;

  /// Call only after processor IO, output finalization and input lease release.
  void release() {
    if (_released) return;
    _released = true;
    _scheduler._release(memoryBudgetBytes);
  }
}

final class _PendingProcessing {
  _PendingProcessing(this.cancellation);
  final CancellationToken? cancellation;
  final Completer<ProcessingPermit> completion = Completer<ProcessingPermit>();
  bool pending = true;
}
