import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/links/data/link_probe_gateway.dart';
import 'package:imagehost/features/links/domain/link_availability.dart';

final class _UnsafeFailure implements Exception {
  int strings = 0;
  @override
  String toString() {
    strings++;
    throw StateError('must not stringify protected synthetic error');
  }
}

typedef _Reply = Future<ResponseBody> Function(RequestOptions, Future<void>?);

final class _Transport implements HttpClientAdapter {
  _Transport(this.reply);
  final _Reply reply;
  final requests = <RequestOptions>[];
  final bodies = <Stream<Uint8List>?>[];
  int closes = 0;
  Object? closeError;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    bodies.add(stream);
    return reply(options, cancelFuture);
  }

  @override
  void close({bool force = false}) {
    closes++;
    expect(force, true);
    if (closeError case final Object error) {
      throw error;
    }
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
  const cat = ImageHostService.catbox, imgbb = ImageHostService.imgbb;
  final catUrl = Uri.parse('https://files.catbox.moe/probe.png');
  final imgbbUrl = Uri.parse('https://i.ibb.co/probe/image.png');
  ResponseBody response(
    int status, {
    String? mime = 'image/png',
    Stream<Uint8List>? source,
    bool isRedirect = false,
    List<String>? duplicateMime,
    String? length,
  }) => ResponseBody(
    source ?? const Stream<Uint8List>.empty(),
    status,
    headers: {
      if (mime != null) Headers.contentTypeHeader: duplicateMime ?? [mime],
      if (length != null) Headers.contentLengthHeader: [length],
      'x-synthetic-secret': ['never-output-response-secret'],
    },
    isRedirect: isRedirect,
    statusMessage: 'never-output-provider-prose',
  );
  Future<LinkProbeOutcome> check(
    _Transport transport, {
    CancelToken? token,
    Duration deadline = const Duration(seconds: 20),
    Uri? url,
    ImageHostService service = cat,
  }) =>
      DioLinkProbeGateway(
        transportFactory: () => transport,
        deadline: deadline,
      ).check(
        url: url ?? catUrl,
        service: service,
        cancelToken: token ?? CancelToken(),
      );
  void expectOutcome(
    LinkProbeOutcome value,
    LinkAvailability state,
    LinkProbeReason reason, {
    int? status,
  }) {
    expect(value.state, state);
    expect(value.reason, reason);
    expect(value.httpStatus, status);
    expect(value.toString(), isNot(contains('never-output')));
  }

  test('UT-072 passive construction never fetches and each explicit check owns one isolated HEAD without credentials or retry', () async {
    final created = <_Transport>[];
    final gateway = DioLinkProbeGateway(
      transportFactory: () {
        final transport = _Transport((_, _) async => response(200));
        created.add(transport);
        return transport;
      },
    );
    await Future<void>.delayed(Duration.zero);
    expect(created, isEmpty);
    for (final (service, url) in [(cat, catUrl), (imgbb, imgbbUrl)]) {
      expectOutcome(
        await gateway.check(
          url: url,
          service: service,
          cancelToken: CancelToken(),
        ),
        LinkAvailability.accessible,
        LinkProbeReason.reachable,
        status: 200,
      );
    }
    expect(created, hasLength(2));
    for (final transport in created) {
      expect(transport.requests, hasLength(1));
      expect(transport.bodies.single, isNull);
      expect(transport.closes, 1);
      final request = transport.requests.single;
      expect(request.method, 'HEAD');
      expect(request.data, isNull);
      expect(request.followRedirects, false);
      expect(request.maxRedirects, 0);
      expect(request.responseType, ResponseType.stream);
      expect(request.connectTimeout, const Duration(seconds: 20));
      expect(request.uri.hasQuery, false);
      expect(request.uri.userInfo, isEmpty);
      expect(request.extra, isEmpty);
      expect(
        request.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('authorization')),
      );
      expect(
        request.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('cookie')),
      );
      expect(request.headers.values.join(), isNot(contains('secret')));
    }
  });

  test('UT-072 unsupported URLs and pre-cancellation dispatch zero requests and create no transport', () async {
    var factories = 0;
    final gateway = DioLinkProbeGateway(
      transportFactory: () {
        factories++;
        return _Transport((_, _) async => response(200));
      },
    );
    for (final raw in [
      'http://files.catbox.moe/image.png',
      'https://credential@files.catbox.moe/image.png',
      'https://files.catbox.moe/image.png?key=secret',
      'https://files.catbox.moe/image.png?',
      'https://files.catbox.moe/image.png#secret',
      'https://files.catbox.moe/image.png#',
      'https://files.catbox.moe:8443/image.png',
      'https://files.catbox.moe.evil.test/image.png',
      'https://catbox.moe/user/api.php',
      'https://api.imgbb.com/1/upload',
      'https://ibb.co/manage/deleteSecret',
      'https://localhost/image.png',
      'https://127.0.0.1/image.png',
      'https://files.catbox.moe/%00image.png',
      'file:///image.png',
      '/relative.png',
    ]) {
      final outcome = await gateway.check(
        url: Uri.parse(raw),
        service: cat,
        cancelToken: CancelToken(),
      );
      expect(factories, 0, reason: 'Rejected before fetch: $raw');
      expectOutcome(
        outcome,
        LinkAvailability.unknown,
        LinkProbeReason.unsupported,
      );
    }
    expectOutcome(
      await gateway.check(
        url: imgbbUrl,
        service: cat,
        cancelToken: CancelToken(),
      ),
      LinkAvailability.unknown,
      LinkProbeReason.unsupported,
    );
    expectOutcome(
      await gateway.check(
        url: catUrl,
        service: imgbb,
        cancelToken: CancelToken(),
      ),
      LinkAvailability.unknown,
      LinkProbeReason.unsupported,
    );
    expectOutcome(
      await gateway.check(
        url: catUrl,
        service: cat,
        cancelToken: CancelToken()..cancel(_UnsafeFailure()),
      ),
      LinkAvailability.unknown,
      LinkProbeReason.cancelled,
    );
    expect(factories, 0);
  });

  test('UT-072 Uri-normalized dot segments retain only the canonical whitelisted host and path', () async {
    final normalized = Uri.parse('https://files.catbox.moe/%2e%2e/image.png');
    expect(normalized, Uri.parse('https://files.catbox.moe/image.png'));
    final transport = _Transport((_, _) async => response(200));
    expectOutcome(
      await check(transport, url: normalized),
      LinkAvailability.accessible,
      LinkProbeReason.reachable,
      status: 200,
    );
    expect(transport.requests.single.uri, normalized);
    expect(transport.requests.single.method, 'HEAD');
    expect(transport.requests, hasLength(1));
  });

  test('UT-072 HEAD 200 image metadata is accessible without consuming the image representation length', () async {
    final transport = _Transport(
      (_, _) async => response(
        200,
        mime: 'IMAGE/JPEG; charset=binary',
        length: '9876543210',
      ),
    );
    expectOutcome(
      await check(transport),
      LinkAvailability.accessible,
      LinkProbeReason.reachable,
      status: 200,
    );
    expect(transport.requests, hasLength(1));
  });

  test('UT-072 empty 410 records service Gone evidence only and performs no delete or GET', () async {
    final transport = _Transport(
      (_, _) async => response(410, mime: 'text/html'),
    );
    expectOutcome(
      await check(transport),
      LinkAvailability.deleted,
      LinkProbeReason.gone,
      status: 410,
    );
    expect(transport.requests.single.method, 'HEAD');
    expect(transport.requests, hasLength(1));
  });

  for (final status in [
    404,
    403,
    405,
    429,
    500,
    502,
    503,
    301,
    302,
    307,
    308,
    204,
    201,
  ]) {
    test(
      'UT-072 HTTP $status is unconfirmed without redirects retries GET fallback or provider prose',
      () async {
        final transport = _Transport((_, _) async => response(status));
        expectOutcome(
          await check(transport),
          LinkAvailability.unknown,
          LinkProbeReason.unconfirmed,
          status: status,
        );
        expect(transport.requests, hasLength(1));
        expect(transport.closes, 1);
      },
    );
  }

  test('UT-072 malformed statuses content types duplicated headers or redirect evidence cannot become accessible', () async {
    for (final body in [
      response(0),
      response(999),
      response(200, mime: null),
      response(200, mime: 'text/html'),
      response(200, mime: 'application/json'),
      response(200, mime: 'image/*'),
      response(200, mime: 'image/'),
      response(200, mime: 'image/png, text/html'),
      response(200, mime: 'image/png\r\nsecret:bad'),
      response(200, duplicateMime: ['image/png', 'text/html']),
      response(200, isRedirect: true),
    ]) {
      final transport = _Transport((_, _) async => body);
      final outcome = await check(transport);
      expect(outcome.state, LinkAvailability.unknown);
      expect(outcome.reason, LinkProbeReason.unconfirmed);
      expect(
        outcome.httpStatus,
        body.statusCode < 100 || body.statusCode > 599 ? null : body.statusCode,
      );
      expect(transport.requests, hasLength(1));
    }
  });

  for (final bytes in [
    1,
    DioLinkProbeGateway.responseBudgetBytes,
    DioLinkProbeGateway.responseBudgetBytes + 1,
  ]) {
    test(
      'UT-072 nonempty HEAD body $bytes bytes stops the original source and never reports accessible',
      () async {
        final stopped = Completer<void>();
        final source = StreamController<Uint8List>(onCancel: stopped.complete);
        final transport = _Transport((_, _) async {
          scheduleMicrotask(() => source.add(Uint8List(bytes)));
          return response(200, source: source.stream);
        });
        final outcome = await check(transport);
        expect(outcome.state, LinkAvailability.unknown);
        expect(outcome.reason, LinkProbeReason.unconfirmed);
        expect(stopped.isCompleted, true);
        expect(transport.requests, hasLength(1));
        unawaited(source.close());
      },
    );
  }

  test(
    'UT-072 a body-bearing 410 is malformed and cannot report service Gone',
    () async {
      final transport = _Transport(
        (_, _) async =>
            response(410, source: Stream.value(Uint8List.fromList([1]))),
      );
      final outcome = await check(transport);
      expect(outcome.state, LinkAvailability.unknown);
      expect(outcome.reason, LinkProbeReason.unconfirmed);
    },
  );

  test('UT-072 malformed body waits for real source cancellation gate before returning', () async {
    final cancelStarted = Completer<void>(), ioExited = Completer<void>();
    final source = StreamController<Uint8List>(
      onCancel: () {
        cancelStarted.complete();
        return ioExited.future;
      },
    );
    final transport = _Transport((_, _) async {
      scheduleMicrotask(
        () =>
            source.add(Uint8List(DioLinkProbeGateway.responseBudgetBytes + 1)),
      );
      return response(200, source: source.stream);
    });
    var completed = false;
    final future = check(transport).then((value) {
      completed = true;
      return value;
    });
    await cancelStarted.future;
    await Future<void>.delayed(Duration.zero);
    expect(completed, false);
    ioExited.complete();
    expectOutcome(
      await future,
      LinkAvailability.unknown,
      LinkProbeReason.unconfirmed,
      status: 200,
    );
    unawaited(source.close());
  });

  test('UT-072 cancellation waits for actual delegate fetch and late response source shutdown', () async {
    final started = Completer<void>(), actualFetch = Completer<ResponseBody>();
    final cancelStarted = Completer<void>(), ioExited = Completer<void>();
    final source = StreamController<Uint8List>(
      onCancel: () {
        cancelStarted.complete();
        return ioExited.future;
      },
    );
    final transport = _Transport((_, _) {
      started.complete();
      return actualFetch.future;
    });
    final token = CancelToken();
    var completed = false;
    final future = check(transport, token: token).then((value) {
      completed = true;
      return value;
    });
    await started.future;
    token.cancel(_UnsafeFailure());
    await Future<void>.delayed(Duration.zero);
    expect(completed, false);
    actualFetch.complete(response(200, source: source.stream));
    await cancelStarted.future;
    await Future<void>.delayed(Duration.zero);
    expect(completed, false);
    ioExited.complete();
    expectOutcome(
      await future,
      LinkAvailability.unknown,
      LinkProbeReason.cancelled,
    );
    expect(transport.closes, 1);
    unawaited(source.close());
  });

  test('UT-072 deadline signals cancellation yet waits for real late fetch and raw source completion', () async {
    final started = Completer<void>(),
        actualFetch = Completer<ResponseBody>(),
        deadlineReached = Completer<void>();
    final cancelStarted = Completer<void>(), ioExited = Completer<void>();
    final source = StreamController<Uint8List>(
      onCancel: () {
        cancelStarted.complete();
        return ioExited.future;
      },
    );
    final transport = _Transport((_, cancel) {
      started.complete();
      cancel!.then((_) => deadlineReached.complete());
      return actualFetch.future;
    });
    final callerToken = CancelToken();
    var completed = false;
    final future =
        check(
          transport,
          token: callerToken,
          deadline: const Duration(milliseconds: 5),
        ).then((value) {
          completed = true;
          return value;
        });
    await started.future;
    await deadlineReached.future;
    expect(callerToken.isCancelled, false);
    expect(completed, false);
    actualFetch.complete(response(200, source: source.stream));
    await cancelStarted.future;
    await Future<void>.delayed(Duration.zero);
    expect(completed, false);
    ioExited.complete();
    expectOutcome(
      await future,
      LinkAvailability.unknown,
      LinkProbeReason.timeout,
    );
    expect(transport.requests, hasLength(1));
    unawaited(source.close());
  });

  test('UT-072 cancelling an already-returned stalled response waits for its original onCancel', () async {
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
      (_, _) async => response(200, source: source.stream),
    );
    final token = CancelToken();
    var completed = false;
    final future = check(transport, token: token).then((value) {
      completed = true;
      return value;
    });
    await listened.future;
    token.cancel();
    await cancelStarted.future;
    await Future<void>.delayed(Duration.zero);
    expect(completed, false);
    ioExited.complete();
    expectOutcome(
      await future,
      LinkAvailability.unknown,
      LinkProbeReason.cancelled,
    );
    unawaited(source.close());
  });

  for (final type in [
    DioExceptionType.connectionTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.receiveTimeout,
  ]) {
    test('UT-072 $type maps to safe unknown timeout without retry', () async {
      final transport = _Transport(
        (options, _) async => throw DioException(
          requestOptions: options,
          type: type,
          error: _UnsafeFailure(),
          message: 'synthetic secret-bearing prose',
        ),
      );
      expectOutcome(
        await check(transport),
        LinkAvailability.unknown,
        LinkProbeReason.timeout,
      );
      expect(transport.requests, hasLength(1));
    });
  }

  test('UT-072 offline fetch synchronous throw and raw stream exceptions are safe unconfirmed without stringify', () async {
    final unsafe = _UnsafeFailure();
    for (final transport in [
      _Transport((_, _) async => throw unsafe),
      _Transport((_, _) => throw unsafe),
      _Transport((_, _) async => response(200, source: Stream.error(unsafe))),
      _Transport(
        (options, _) async => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: unsafe,
          message: 'never-output-offline-secret',
        ),
      ),
    ]) {
      final outcome = await check(transport);
      expect(outcome.state, LinkAvailability.unknown);
      expect(outcome.reason, LinkProbeReason.unconfirmed);
      expect(transport.closes, 1);
    }
    expect(unsafe.strings, 0);
  });

  test('UT-072 factory exceptions never dispatch or stringify and invalid deadline is rejected before work', () async {
    final unsafe = _UnsafeFailure();
    final gateway = DioLinkProbeGateway(transportFactory: () => throw unsafe);
    expectOutcome(
      await gateway.check(
        url: catUrl,
        service: cat,
        cancelToken: CancelToken(),
      ),
      LinkAvailability.unknown,
      LinkProbeReason.unconfirmed,
    );
    expect(unsafe.strings, 0);
    expect(
      () => DioLinkProbeGateway(deadline: Duration.zero),
      throwsArgumentError,
    );
  });

  test('UT-072 source cancel failure raises fixed cleanup failure instead of reporting settled IO', () async {
    final unsafe = _UnsafeFailure();
    final source = StreamController<Uint8List>(
      onCancel: () => Future<void>.error(unsafe),
    );
    final transport = _Transport((_, _) async {
      scheduleMicrotask(() => source.add(Uint8List.fromList([1])));
      return response(200, source: source.stream);
    });
    await expectLater(
      check(transport),
      throwsA(isA<LinkProbeCleanupFailure>()),
    );
    expect(unsafe.strings, 0);
    expect(
      const LinkProbeCleanupFailure().toString(),
      isNot(contains('secret')),
    );
    unawaited(source.close());
  });

  test('UT-072 delegate close failure still waits for a late actual fetch before fixed cleanup failure', () async {
    final started = Completer<void>(), actualFetch = Completer<ResponseBody>();
    final unsafe = _UnsafeFailure();
    final transport = _Transport((_, _) {
      started.complete();
      return actualFetch.future;
    })..closeError = unsafe;
    final token = CancelToken();
    var completed = false;
    final future = check(transport, token: token);
    final assertion = expectLater(
      future.whenComplete(() => completed = true),
      throwsA(isA<LinkProbeCleanupFailure>()),
    );
    await started.future;
    token.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(completed, false);
    actualFetch.complete(response(200));
    await assertion;
    expect(transport.closes, 1);
    expect(unsafe.strings, 0);
  });

  test('UT-072 failed raw source subscription cannot claim IO cleanup and exposes only a fixed failure', () async {
    final unsafe = _UnsafeFailure();
    final transport = _Transport(
      (_, _) async => response(200, source: _BadListen(unsafe)),
    );
    await expectLater(
      check(transport),
      throwsA(isA<LinkProbeCleanupFailure>()),
    );
    expect(unsafe.strings, 0);
  });
}
