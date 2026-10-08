import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../accounts/domain/account_models.dart';
import '../domain/link_availability.dart';

abstract interface class LinkProbeGateway {
  Future<LinkProbeOutcome> check({
    required Uri url,
    required ImageHostService service,
    required CancelToken cancelToken,
  });
}

/// The caller must retain its IO protection when cleanup cannot be confirmed.
final class LinkProbeCleanupFailure implements Exception {
  const LinkProbeCleanupFailure();
  @override
  String toString() => '链接探测实际收尾尚未确认，已保留保护。';
}

final class DioLinkProbeGateway implements LinkProbeGateway {
  DioLinkProbeGateway({
    this.transportFactory,
    this.deadline = const Duration(seconds: 20),
  }) {
    if (deadline <= Duration.zero) {
      throw ArgumentError('探测时限必须大于零。');
    }
  }

  final HttpClientAdapter Function()? transportFactory;
  final Duration deadline;
  // Candidate defensive transport budget, not a measured service capability.
  static const responseBudgetBytes = 1024;

  bool _supported(Uri url, ImageHostService service) {
    if (url.scheme != 'https' ||
        !url.hasAuthority ||
        url.userInfo.isNotEmpty ||
        url.hasFragment ||
        url.hasQuery ||
        url.hasPort ||
        url.path.isEmpty ||
        url.pathSegments.any((part) => part == '.' || part == '..') ||
        RegExp(r'[\s\x00-\x1f\x7f\\]').hasMatch(url.toString()) ||
        RegExp(
          r'%0[0-9a-f]|%1[0-9a-f]|%7f',
          caseSensitive: false,
        ).hasMatch(url.toString())) {
      return false;
    }
    return url.host ==
        switch (service) {
          ImageHostService.catbox => 'files.catbox.moe',
          ImageHostService.imgbb => 'i.ibb.co',
        };
  }

  LinkProbeOutcome _classify(Response<ResponseBody> response) {
    final status = response.statusCode;
    final safeStatus = status != null && status >= 100 && status <= 599
        ? status
        : null;
    if (response.isRedirect || response.redirects.isNotEmpty) {
      return LinkProbeOutcome(
        LinkAvailability.unknown,
        LinkProbeReason.unconfirmed,
        httpStatus: safeStatus,
      );
    }
    if (safeStatus == 410) {
      return const LinkProbeOutcome(
        LinkAvailability.deleted,
        LinkProbeReason.gone,
        httpStatus: 410,
      );
    }
    if (safeStatus == 200) {
      final type = response.headers.value(Headers.contentTypeHeader);
      final mime = type?.split(';').first.trim().toLowerCase();
      if (mime != null &&
          RegExp(r'^image/[a-z0-9!#$&^_.+\-]+$').hasMatch(mime)) {
        return const LinkProbeOutcome(
          LinkAvailability.accessible,
          LinkProbeReason.reachable,
          httpStatus: 200,
        );
      }
    }
    return LinkProbeOutcome(
      LinkAvailability.unknown,
      LinkProbeReason.unconfirmed,
      httpStatus: safeStatus,
    );
  }

  @override
  Future<LinkProbeOutcome> check({
    required Uri url,
    required ImageHostService service,
    required CancelToken cancelToken,
  }) async {
    if (!_supported(url, service)) return LinkProbeOutcome.unsupported;
    if (cancelToken.isCancelled) return LinkProbeOutcome.cancelled;
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
    _ProbeTransport? tracked;
    var outcome = LinkProbeOutcome.unconfirmed;
    int? status;
    try {
      tracked = _ProbeTransport(
        transportFactory?.call() ?? dio.httpClientAdapter,
      );
      dio.httpClientAdapter = tracked;
      final response = await dio.headUri<ResponseBody>(
        url,
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
            // The raw transport rejects any nonempty HEAD body before Dio.
            if (reader.current.isNotEmpty) {
              throw const _MalformedProbeResponse();
            }
          }
        } finally {
          await reader.cancel();
        }
        if (!internalCancel.isCancelled && !tracked.malformedResponse) {
          outcome = _classify(response);
        }
      }
    } on DioException catch (error) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        timedOut = true;
      }
    } catch (_) {
      // Raw response data, headers, URLs and error objects never become prose.
    } finally {
      timer.cancel();
      var closeFailed = false;
      try {
        dio.close(force: true);
      } catch (_) {
        closeFailed = true;
      }
      // Dio cancellation resolves early. The delegate and every original
      // response subscription, including a late response, must actually settle.
      await tracked?.settled;
      finished = true;
      if (closeFailed || (tracked?.cleanupFailed ?? false)) {
        throw const LinkProbeCleanupFailure();
      }
    }
    if (cancelToken.isCancelled) return LinkProbeOutcome.cancelled;
    if (timedOut) {
      return const LinkProbeOutcome(
        LinkAvailability.unknown,
        LinkProbeReason.timeout,
      );
    }
    if (outcome == LinkProbeOutcome.unconfirmed && status != null) {
      return LinkProbeOutcome(
        LinkAvailability.unknown,
        LinkProbeReason.unconfirmed,
        httpStatus: status,
      );
    }
    return outcome;
  }
}

final class _MalformedProbeResponse implements Exception {
  const _MalformedProbeResponse();
}

/// Tracks the actual delegate independently of Dio's cancellation future.
final class _ProbeTransport implements HttpClientAdapter {
  _ProbeTransport(this.delegate);
  final HttpClientAdapter delegate;
  final _fetches = <Future<void>>[];
  final _responses = <_ProbeResponse>[];
  bool _closed = false, _closeFailed = false, _subscribeFailed = false;
  bool get malformedResponse =>
      _responses.any((response) => response.malformed);
  bool get cleanupFailed =>
      _closeFailed ||
      _subscribeFailed ||
      _responses.any((response) => response.cleanupFailed);
  Future<void> get settled async {
    await Future.wait(_fetches);
    await Future.wait(_responses.map((response) => response.settled));
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_closed) {
      throw DioException(requestOptions: options, message: '探测已停止。');
    }
    final done = Completer<void>();
    _fetches.add(done.future);
    try {
      final body = await delegate.fetch(options, requestStream, cancelFuture);
      late final _ProbeResponse response;
      try {
        response = _ProbeResponse(body.stream);
      } catch (_) {
        _subscribeFailed = true;
        throw const _MalformedProbeResponse();
      }
      _responses.add(response);
      body.stream = response.stream;
      if (_closed) unawaited(response.stop());
      return body;
    } catch (error) {
      // Sanitize before Dio can format an exception or retain a raw object.
      throw DioException(
        requestOptions: options,
        type: error is DioException ? error.type : DioExceptionType.unknown,
        message: '链接探测未确认。',
      );
    } finally {
      done.complete();
    }
  }

  @override
  void close({bool force = false}) {
    _closed = true;
    for (final response in _responses) {
      unawaited(response.stop());
    }
    try {
      delegate.close(force: force);
    } catch (_) {
      _closeFailed = true;
    }
  }
}

/// Never retain provider body bytes. HEAD permits no body; the 1 KiB raw
/// budget is an additional bound, and even one actual byte rejects evidence.
final class _ProbeResponse {
  _ProbeResponse(Stream<Uint8List> source) {
    _controller = StreamController<Uint8List>(
      onCancel: stop,
      onPause: () => _subscription.pause(),
      onResume: () => _subscription.resume(),
    );
    _subscription = source.listen(
      (chunk) {
        if (_stopping != null || malformed) return;
        if (chunk.length > DioLinkProbeGateway.responseBudgetBytes ||
            chunk.isNotEmpty) {
          malformed = true;
          _controller.addError(const _MalformedProbeResponse());
          scheduleMicrotask(stop);
        }
      },
      onError: (Object _) {
        if (_stopping == null && !malformed) {
          malformed = true;
          _controller.addError(const _MalformedProbeResponse());
        }
        scheduleMicrotask(stop);
      },
      onDone: () => scheduleMicrotask(stop),
    );
  }
  late final StreamController<Uint8List> _controller;
  late final StreamSubscription<Uint8List> _subscription;
  final _done = Completer<void>();
  Future<void>? _stopping;
  bool malformed = false, cleanupFailed = false;
  Stream<Uint8List> get stream => _controller.stream;
  Future<void> get settled => _done.future;
  Future<void> stop() => _stopping ??= _stop();
  Future<void> _stop() async {
    try {
      await _subscription.cancel();
    } catch (_) {
      cleanupFailed = true;
    } finally {
      unawaited(_controller.close());
      _done.complete();
    }
  }
}
