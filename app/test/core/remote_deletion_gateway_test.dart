import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/features/links/data/remote_deletion_gateway.dart';
import 'package:imagehost/features/links/domain/remote_deletion.dart';

final class _UnsafeFailure implements Exception {
  int strings = 0;
  @override
  String toString() {
    strings++;
    throw StateError('protected synthetic error must not be stringified');
  }
}

typedef _Reply = Future<ResponseBody> Function(
  RequestOptions,
  Stream<Uint8List>?,
  Future<void>?,
);

final class _Transport implements HttpClientAdapter {
  _Transport(this.reply);
  final _Reply reply;
  final requests = <RequestOptions>[];
  int closes = 0;
  Object? closeError;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return reply(options, stream, cancelFuture);
  }

  @override
  void close({bool force = false}) {
    closes++;
    expect(force, true);
    if (closeError case final Object error) throw error;
  }
}

final class _BadListen extends Stream<Uint8List> {
  _BadListen(this.error);
  final Object error;
  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => throw error;
}

void main() {
  final request = CatboxDeletionRequest(
    filename: 'single123.png',
    userhash: 'protected-synthetic-userhash',
  );
  ResponseBody response(int status, {Stream<Uint8List>? source}) =>
      ResponseBody(
        source ?? const Stream<Uint8List>.empty(),
        status,
        headers: {
          'x-protected': ['never-display-header'],
        },
        statusMessage: 'never-display-status-message',
      );
  Future<RemoteDeletionOutcome> delete(
    _Transport transport, {
    CancelToken? token,
    Duration deadline = const Duration(seconds: 20),
  }) => DioRemoteDeletionGateway(
    transportFactory: () => transport,
    deadline: deadline,
  ).delete(request: request, cancelToken: token ?? CancelToken());
  void expectOutcome(
    RemoteDeletionOutcome outcome,
    RemoteDeletionState state,
    RemoteDeletionReason reason, {
    int? status,
  }) {
    expect(outcome.valid, true);
    expect(outcome.state, state);
    expect(outcome.reason, reason);
    expect(outcome.httpStatus, status);
  }

  test('UT-050 construction is passive and one explicit deletion sends one fixed multipart POST without retry or redirects', () async {
    var factories = 0;
    late _Transport transport;
    final gateway = DioRemoteDeletionGateway(
      transportFactory: () {
        factories++;
        transport = _Transport((options, stream, _) async {
          final form = options.data as FormData;
          // Do not expose synthetic credential values in matcher diagnostics.
          expect(form.fields.length, 3);
          expect(form.files, isEmpty);
          expect(form.fields[0].key, 'reqtype');
          expect(form.fields[0].value == 'deletefiles', true);
          expect(form.fields[1].key, 'userhash');
          expect(form.fields[1].value == request.userhash, true);
          expect(form.fields[2].key, 'files');
          expect(form.fields[2].value == request.filename, true);
          final bytes = await stream!.fold<List<int>>(
            [],
            (all, chunk) => all..addAll(chunk),
          );
          final encoded = utf8.decode(bytes);
          expect(encoded.contains('name="reqtype"\r\n\r\ndeletefiles'), true);
          expect(
            encoded.contains('name="userhash"\r\n\r\n${request.userhash}'),
            true,
          );
          expect(
            encoded.contains('name="files"\r\n\r\n${request.filename}'),
            true,
          );
          return response(200);
        });
        return transport;
      },
    );
    await Future<void>.delayed(Duration.zero);
    expect(factories, 0);
    expectOutcome(
      await gateway.delete(request: request, cancelToken: CancelToken()),
      RemoteDeletionState.unknown,
      RemoteDeletionReason.unconfirmed,
      status: 200,
    );
    expect(factories, 1);
    expect(transport.requests, hasLength(1));
    final sent = transport.requests.single;
    expect(sent.uri, Uri.parse('https://catbox.moe/user/api.php'));
    expect(sent.method, 'POST');
    expect(sent.followRedirects, false);
    expect(sent.maxRedirects, 0);
    expect(sent.responseType, ResponseType.stream);
    expect(sent.extra, isEmpty);
    expect(sent.uri.hasQuery, false);
    expect(
      sent.headers.keys.map((key) => key.toLowerCase()),
      isNot(contains('authorization')),
    );
    expect(
      sent.headers.keys.map((key) => key.toLowerCase()),
      isNot(contains('cookie')),
    );
    expect(transport.closes, 1);
  });

  for (final status in [
    200,
    204,
    301,
    302,
    307,
    308,
    400,
    403,
    404,
    410,
    429,
    500,
    503,
    0,
    999,
  ]) {
    test(
      'UT-050 HTTP $status empty or text body is unknown without service deletion confirmation',
      () async {
        for (final source in [
          const Stream<Uint8List>.empty(),
          Stream.value(
            Uint8List.fromList(utf8.encode('File deleted successfully')),
          ),
        ]) {
          final transport = _Transport(
            (_, _, _) async => response(status, source: source),
          );
          expectOutcome(
            await delete(transport),
            RemoteDeletionState.unknown,
            RemoteDeletionReason.unconfirmed,
            status: status >= 100 && status <= 599 ? status : null,
          );
          expect(transport.requests, hasLength(1));
          expect(transport.closes, 1);
        }
      },
    );
  }

  test('UT-050 pre-cancellation creates no transport and no fetch', () async {
    var factories = 0;
    final unsafe = _UnsafeFailure();
    final gateway = DioRemoteDeletionGateway(
      transportFactory: () {
        factories++;
        return _Transport((_, _, _) async => response(200));
      },
    );
    expectOutcome(
      await gateway.delete(
        request: request,
        cancelToken: CancelToken()..cancel(unsafe),
      ),
      RemoteDeletionState.notSent,
      RemoteDeletionReason.cancelled,
    );
    expect(factories, 0);
    expect(unsafe.strings, 0);
  });

  test(
    'UT-050 cancellation between factory and fetch does not dispatch',
    () async {
      final token = CancelToken();
      final transport = _Transport((_, _, _) async => response(200));
      final gateway = DioRemoteDeletionGateway(
        transportFactory: () {
          token.cancel();
          return transport;
        },
      );
      expectOutcome(
        await gateway.delete(request: request, cancelToken: token),
        RemoteDeletionState.notSent,
        RemoteDeletionReason.cancelled,
      );
      expect(transport.requests, isEmpty);
      expect(transport.closes, 1);
    },
  );

  test('UT-050 cancellation waits for actual delegate fetch and late response cancellation', () async {
    final started = Completer<void>(), actualFetch = Completer<ResponseBody>();
    final cancelStarted = Completer<void>(), ioExited = Completer<void>();
    final source = StreamController<Uint8List>(
      onCancel: () {
        cancelStarted.complete();
        return ioExited.future;
      },
    );
    final transport = _Transport((_, _, _) {
      started.complete();
      return actualFetch.future;
    });
    final token = CancelToken();
    var completed = false;
    final future = delete(transport, token: token).then((value) {
      completed = true;
      return value;
    });
    await started.future;
    token.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(completed, false);
    actualFetch.complete(response(200, source: source.stream));
    await cancelStarted.future;
    await Future<void>.delayed(Duration.zero);
    expect(completed, false);
    ioExited.complete();
    expectOutcome(
      await future,
      RemoteDeletionState.unknown,
      RemoteDeletionReason.cancelled,
    );
    expect(transport.closes, 1);
    unawaited(source.close());
  });

  test('UT-050 deadline cancels once but waits for actual fetch and late response IO', () async {
    final actualFetch = Completer<ResponseBody>(),
        deadlineReached = Completer<void>();
    final cancelStarted = Completer<void>(), ioExited = Completer<void>();
    final source = StreamController<Uint8List>(
      onCancel: () {
        cancelStarted.complete();
        return ioExited.future;
      },
    );
    final transport = _Transport((_, _, cancel) {
      cancel!.then((_) => deadlineReached.complete());
      return actualFetch.future;
    });
    var completed = false;
    final token = CancelToken();
    final future =
        delete(
          transport,
          token: token,
          deadline: const Duration(milliseconds: 5),
        ).then((value) {
          completed = true;
          return value;
        });
    await deadlineReached.future;
    expect(completed, false);
    expect(token.isCancelled, false);
    actualFetch.complete(response(200, source: source.stream));
    await cancelStarted.future;
    expect(completed, false);
    ioExited.complete();
    expectOutcome(
      await future,
      RemoteDeletionState.unknown,
      RemoteDeletionReason.timeout,
    );
    expect(transport.requests, hasLength(1));
    unawaited(source.close());
  });

  test('UT-050 dispatch input consumption remains protected until the real adapter completes', () async {
    final inputRead = Completer<void>(), inputExited = Completer<void>();
    final transport = _Transport((_, stream, _) async {
      await stream!.drain<void>();
      inputRead.complete();
      await inputExited.future;
      return response(200);
    });
    final token = CancelToken();
    var completed = false;
    final future = delete(transport, token: token).then((value) {
      completed = true;
      return value;
    });
    await inputRead.future;
    token.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(completed, false);
    inputExited.complete();
    expectOutcome(
      await future,
      RemoteDeletionState.unknown,
      RemoteDeletionReason.cancelled,
    );
  });

  test('UT-050 response remains pending until original source ends even when POST fetch already returned', () async {
    final listened = Completer<void>();
    final source = StreamController<Uint8List>(onListen: listened.complete);
    final transport = _Transport(
      (_, _, _) async => response(200, source: source.stream),
    );
    var completed = false;
    final future = delete(transport).then((value) {
      completed = true;
      return value;
    });
    await listened.future;
    source.add(Uint8List.fromList([1, 2, 3]));
    await Future<void>.delayed(Duration.zero);
    expect(completed, false);
    await source.close();
    expectOutcome(
      await future,
      RemoteDeletionState.unknown,
      RemoteDeletionReason.unconfirmed,
      status: 200,
    );
  });

  test('UT-050 cancelling stalled response waits for original source cancellation future', () async {
    final listened = Completer<void>(),
        cancelStarted = Completer<void>(),
        ioExited = Completer<void>();
    final source = StreamController<Uint8List>(
      onListen: listened.complete,
      onCancel: () {
        cancelStarted.complete();
        return ioExited.future;
      },
    );
    final transport = _Transport(
      (_, _, _) async => response(200, source: source.stream),
    );
    final token = CancelToken();
    var completed = false;
    final future = delete(transport, token: token).then((value) {
      completed = true;
      return value;
    });
    await listened.future;
    token.cancel();
    await cancelStarted.future;
    expect(completed, false);
    ioExited.complete();
    final outcome = await future;
    expect(outcome.state, RemoteDeletionState.unknown);
    expect(outcome.reason, RemoteDeletionReason.cancelled);
    unawaited(source.close());
  });

  test('UT-050 cumulative raw response budget cancels source and waits for its real IO cleanup', () async {
    final cancelStarted = Completer<void>(), ioExited = Completer<void>();
    final source = StreamController<Uint8List>(
      onCancel: () {
        cancelStarted.complete();
        return ioExited.future;
      },
    );
    final transport = _Transport((_, _, _) async {
      scheduleMicrotask(() {
        source.add(Uint8List(DioRemoteDeletionGateway.responseBudgetBytes));
        source.add(Uint8List(1));
      });
      return response(200, source: source.stream);
    });
    var completed = false;
    final future = delete(transport).then((value) {
      completed = true;
      return value;
    });
    await cancelStarted.future;
    expect(completed, false);
    ioExited.complete();
    expectOutcome(
      await future,
      RemoteDeletionState.unknown,
      RemoteDeletionReason.unconfirmed,
      status: 200,
    );
    expect(transport.requests, hasLength(1));
    unawaited(source.close());
  });

  for (final type in [
    DioExceptionType.connectionTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.receiveTimeout,
  ]) {
    test(
      'UT-050 $type remains unknown after dispatch and sanitizes raw errors',
      () async {
        final unsafe = _UnsafeFailure();
        final transport = _Transport(
          (options, _, _) async => throw DioException(
            requestOptions: options,
            type: type,
            error: unsafe,
            message: 'never-display-protected-provider-prose',
          ),
        );
        expectOutcome(
          await delete(transport),
          RemoteDeletionState.unknown,
          RemoteDeletionReason.timeout,
        );
        expect(unsafe.strings, 0);
        expect(transport.requests, hasLength(1));
      },
    );
  }

  test('UT-050 synchronous asynchronous and original stream failures never stringify unsafe objects', () async {
    final unsafe = _UnsafeFailure();
    for (final transport in [
      _Transport((_, _, _) => throw unsafe),
      _Transport((_, _, _) async => throw unsafe),
      _Transport(
        (_, _, _) async => response(200, source: Stream.error(unsafe)),
      ),
    ]) {
      final outcome = await delete(transport);
      expect(outcome.state, RemoteDeletionState.unknown);
      expect(outcome.reason, RemoteDeletionReason.unconfirmed);
      expect(transport.closes, 1);
    }
    expect(unsafe.strings, 0);
    expect(request.toString().contains(request.userhash), false);
  });

  test('UT-050 transport factory failure is notSent without stringification and invalid deadline rejects before work', () async {
    final unsafe = _UnsafeFailure();
    final gateway = DioRemoteDeletionGateway(
      transportFactory: () => throw unsafe,
    );
    expectOutcome(
      await gateway.delete(request: request, cancelToken: CancelToken()),
      RemoteDeletionState.notSent,
      RemoteDeletionReason.unconfirmed,
    );
    expect(unsafe.strings, 0);
    expect(
      () => DioRemoteDeletionGateway(deadline: Duration.zero),
      throwsArgumentError,
    );
  });

  test('UT-050 raw response cancellation failure preserves protection using fixed cleanup exception', () async {
    final unsafe = _UnsafeFailure();
    final source = StreamController<Uint8List>(
      onCancel: () => Future<void>.error(unsafe),
    );
    final transport = _Transport((_, _, _) async {
      scheduleMicrotask(
        () => source.add(
          Uint8List(DioRemoteDeletionGateway.responseBudgetBytes + 1),
        ),
      );
      return response(200, source: source.stream);
    });
    await expectLater(
      delete(transport),
      throwsA(isA<RemoteDeletionCleanupFailure>()),
    );
    expect(unsafe.strings, 0);
    expect(
      const RemoteDeletionCleanupFailure().toString(),
      '远端删除实际收尾尚未确认，已保留保护。',
    );
    unawaited(source.close());
  });

  test('UT-050 delegate close failure still waits for late fetch and never stringifies native errors', () async {
    final started = Completer<void>(), actualFetch = Completer<ResponseBody>();
    final unsafe = _UnsafeFailure();
    final transport = _Transport((_, _, _) {
      started.complete();
      return actualFetch.future;
    })..closeError = unsafe;
    final token = CancelToken();
    var completed = false;
    final assertion = expectLater(
      delete(transport, token: token).whenComplete(() => completed = true),
      throwsA(isA<RemoteDeletionCleanupFailure>()),
    );
    await started.future;
    token.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(completed, false);
    actualFetch.complete(response(200));
    await assertion;
    expect(unsafe.strings, 0);
    expect(transport.closes, 1);
  });

  test('UT-050 original source subscription failure cannot claim confirmed cleanup', () async {
    final unsafe = _UnsafeFailure();
    final transport = _Transport(
      (_, _, _) async => response(200, source: _BadListen(unsafe)),
    );
    await expectLater(
      delete(transport),
      throwsA(isA<RemoteDeletionCleanupFailure>()),
    );
    expect(unsafe.strings, 0);
  });
}
