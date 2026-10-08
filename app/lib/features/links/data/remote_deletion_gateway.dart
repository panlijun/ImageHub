import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../domain/remote_deletion.dart';

abstract interface class RemoteDeletionGateway {
  Future<RemoteDeletionOutcome> delete({
    required CatboxDeletionRequest request,
    required CancelToken cancelToken,
  });
}

/// Callers retain IO protection when actual cleanup cannot be confirmed.
final class RemoteDeletionCleanupFailure implements Exception {
  const RemoteDeletionCleanupFailure();
  @override
  String toString() => '远端删除实际收尾尚未确认，已保留保护。';
}

final class DioRemoteDeletionGateway implements RemoteDeletionGateway {
  DioRemoteDeletionGateway({
    this.transportFactory,
    this.deadline = const Duration(seconds: 20),
  }) {
    if (deadline <= Duration.zero) {
      throw ArgumentError('删除请求时限必须大于零。');
    }
  }

  final HttpClientAdapter Function()? transportFactory;
  final Duration deadline;
  // Candidate defensive bounds, not measured service capabilities.
  static const responseBudgetBytes = 16 * 1024;
  static final _endpoint = Uri.parse('https://catbox.moe/user/api.php');

  @override
  Future<RemoteDeletionOutcome> delete({
    required CatboxDeletionRequest request,
    required CancelToken cancelToken,
  }) async {
    if (cancelToken.isCancelled) return RemoteDeletionOutcome.cancelled;
    final internalCancel = CancelToken();
    var timedOut = false, finished = false;
    cancelToken.whenCancel.then((_) {
      if (!finished && !internalCancel.isCancelled) internalCancel.cancel();
    });
    final timer = Timer(deadline, () {
      timedOut = true;
      internalCancel.cancel();
    });
    final dio = Dio(
      BaseOptions(
        followRedirects: false,
        maxRedirects: 0,
        responseType: ResponseType.stream,
        validateStatus: (_) => true,
        connectTimeout: deadline,
        sendTimeout: deadline,
        receiveTimeout: deadline,
      ),
    );
    _DeletionTransport? tracked;
    int? status;
    try {
      tracked = _DeletionTransport(
        transportFactory?.call() ?? dio.httpClientAdapter,
        () => internalCancel.isCancelled || cancelToken.isCancelled,
      );
      dio.httpClientAdapter = tracked;
      final response = await dio.postUri<ResponseBody>(
        _endpoint,
        data: FormData.fromMap({
          'reqtype': 'deletefiles',
          'userhash': request.userhash,
          'files': request.filename,
        }),
        cancelToken: internalCancel,
      );
      final rawStatus = response.statusCode;
      if (rawStatus != null && rawStatus >= 100 && rawStatus <= 599) {
        status = rawStatus;
      }
      final body = response.data;
      if (body != null) {
        final reader = StreamIterator(body.stream);
        try {
          while (await Future.any<bool>([
            reader.moveNext(),
            internalCancel.whenCancel.then((_) => false),
          ])) {
            // Body bytes are discarded by the raw transport, never interpreted.
          }
        } finally {
          await reader.cancel();
        }
      }
    } on DioException catch (error) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        timedOut = true;
      }
    } catch (_) {
      // Never stringify provider body, headers, errors or protected request.
    } finally {
      timer.cancel();
      var closeFailed = false;
      try {
        dio.close(force: true);
      } catch (_) {
        closeFailed = true;
      }
      // Cancellation of Dio's future alone does not end native IO.
      await tracked?.settled;
      finished = true;
      if (closeFailed || (tracked?.cleanupFailed ?? false)) {
        throw const RemoteDeletionCleanupFailure();
      }
    }
    final sent = tracked?.fetchStarted ?? false;
    return RemoteDeletionOutcome(
      sent ? RemoteDeletionState.unknown : RemoteDeletionState.notSent,
      cancelToken.isCancelled
          ? RemoteDeletionReason.cancelled
          : timedOut
          ? RemoteDeletionReason.timeout
          : RemoteDeletionReason.unconfirmed,
      httpStatus: sent ? status : null,
    );
  }
}

final class _SafeDeletionStreamFailure implements Exception {
  const _SafeDeletionStreamFailure();
}

final class _DeletionTransport implements HttpClientAdapter {
  _DeletionTransport(this.delegate, this.cancelled);
  final HttpClientAdapter delegate;
  final bool Function() cancelled;
  final _fetches = <Future<void>>[];
  final _inputs = <_DeletionStream>[];
  final _responses = <_DeletionStream>[];
  bool _closed = false, _closeFailed = false, _subscribeFailed = false;
  bool fetchStarted = false;
  bool get cleanupFailed =>
      _closeFailed ||
      _subscribeFailed ||
      [..._inputs, ..._responses].any((stream) => stream.cleanupFailed);
  Future<void> get settled async {
    await Future.wait(_fetches);
    // Late response streams are registered before actual fetch completes.
    await Future.wait(
      [..._inputs, ..._responses].map((stream) => stream.settled),
    );
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final safeOptions = RequestOptions(path: 'https://catbox.moe/user/api.php');
    if (_closed || cancelled()) {
      throw DioException(requestOptions: safeOptions, message: '删除请求未发送。');
    }
    final done = Completer<void>();
    _fetches.add(done.future);
    _DeletionStream? input;
    try {
      if (requestStream != null) {
        try {
          input = _DeletionStream(requestStream, forward: true);
        } catch (_) {
          _subscribeFailed = true;
          throw const _SafeDeletionStreamFailure();
        }
        _inputs.add(input);
      }
      fetchStarted = true;
      final body = await delegate.fetch(options, input?.stream, cancelFuture);
      late final _DeletionStream response;
      try {
        response = _DeletionStream(body.stream, forward: false);
      } catch (_) {
        _subscribeFailed = true;
        throw const _SafeDeletionStreamFailure();
      }
      _responses.add(response);
      body.stream = response.stream;
      if (_closed) unawaited(response.stop());
      return body;
    } catch (error) {
      // Replace errors before Dio can stringify or retain a raw provider object.
      throw DioException(
        requestOptions: safeOptions,
        type: error is DioException ? error.type : DioExceptionType.unknown,
        message: '远端删除未确认。',
      );
    } finally {
      // A delegate may finish without subscribing to the multipart input.
      await input?.stop();
      done.complete();
    }
  }

  @override
  void close({bool force = false}) {
    if (_closed) return;
    _closed = true;
    for (final stream in [..._inputs, ..._responses]) {
      unawaited(stream.stop());
    }
    try {
      delegate.close(force: force);
    } catch (_) {
      _closeFailed = true;
    }
  }
}

/// Own the original subscription, independently of Dio/adapter sink wrappers.
final class _DeletionStream {
  _DeletionStream(Stream<Uint8List> source, {required bool forward}) {
    _controller = StreamController<Uint8List>(
      onCancel: stop,
      onPause: () => _subscription.pause(),
      onResume: () => _subscription.resume(),
    );
    _subscription = source.listen(
      (chunk) {
        if (_stopping != null || _failed) return;
        if (forward) {
          _controller.add(chunk);
        } else {
          _bytes += chunk.length;
          if (_bytes > DioRemoteDeletionGateway.responseBudgetBytes) _fail();
        }
      },
      onError: (Object _) => _fail(),
      onDone: () => scheduleMicrotask(stop),
    );
  }
  late final StreamController<Uint8List> _controller;
  late final StreamSubscription<Uint8List> _subscription;
  final _done = Completer<void>();
  Future<void>? _stopping;
  int _bytes = 0;
  bool _failed = false, cleanupFailed = false;
  Stream<Uint8List> get stream => _controller.stream;
  Future<void> get settled => _done.future;
  void _fail() {
    if (_stopping != null || _failed) return;
    _failed = true;
    _controller.addError(const _SafeDeletionStreamFailure());
    scheduleMicrotask(stop);
  }

  Future<void> stop() => _stopping ??= _stop();
  Future<void> _stop() async {
    try {
      await _subscription.cancel();
    } catch (_) {
      cleanupFailed = true;
    } finally {
      // Unconsumed sink completion is not evidence about original source IO.
      unawaited(_controller.close());
      _done.complete();
    }
  }
}
