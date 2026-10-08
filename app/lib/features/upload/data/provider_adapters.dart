import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../accounts/domain/account_models.dart';
import '../domain/provider_models.dart';

typedef ProviderTransportFactory = HttpClientAdapter Function();

abstract class ProviderAdapter {
  ImageHostService get service;
  ProviderUploadLimits get limits;
  Future<ProviderUploadResult> upload({
    required File file,
    required String actualFormat,
    required int expectedBytes,
    required ResolvedTarget target,
    required CancelToken cancelToken,
    UploadActivityCallback? onActivity,
  });
}

final class CatboxAdapter extends _MultipartProviderAdapter {
  CatboxAdapter({
    super.limits = const ProviderUploadLimits.unknown(),
    super.transportFactory,
  });
  @override
  ImageHostService get service => ImageHostService.catbox;
  @override
  String get endpoint => 'https://catbox.moe/user/api.php';
  @override
  FormData createForm(MultipartFile file, ResolvedTarget target) =>
      _StreamingFormData({
        'reqtype': 'fileupload',
        'fileToUpload': file,
        'userhash': target.credential!,
      });
  @override
  ProviderUploadResult parseResponse(
    String body,
    int status,
    String? credential,
  ) {
    final raw = body.trim();
    final url = _ordinaryUrl(raw, credential: credential);
    if (url == null ||
        url.host != 'files.catbox.moe' ||
        !RegExp(r'^/[a-zA-Z0-9_-]+\.[a-zA-Z0-9]{1,10}$').hasMatch(url.path)) {
      return const ProviderUploadUnknown(UploadFailureKind.protocol);
    }
    return ProviderUploadSuccess(
      service: service,
      remoteId: url.pathSegments.single,
      directUrl: url,
    );
  }
}

final class ImgBBAdapter extends _MultipartProviderAdapter {
  ImgBBAdapter({
    super.limits = const ProviderUploadLimits.unknown(),
    super.transportFactory,
  });
  @override
  ImageHostService get service => ImageHostService.imgbb;
  @override
  String get endpoint => 'https://api.imgbb.com/1/upload';
  @override
  FormData createForm(MultipartFile file, ResolvedTarget target) =>
      _StreamingFormData({'key': target.credential!, 'image': file});
  @override
  ProviderUploadResult parseResponse(
    String body,
    int status,
    String? credential,
  ) {
    try {
      final root = jsonDecode(body);
      if (root is! Map<String, dynamic> ||
          root['success'] != true ||
          root['status'] != status ||
          root['data'] is! Map<String, dynamic>) {
        return const ProviderUploadUnknown(UploadFailureKind.protocol);
      }
      final data = root['data'] as Map<String, dynamic>;
      final id = data['id'];
      if (id is! String ||
          !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id) ||
          _containsSecret(id, credential)) {
        return const ProviderUploadUnknown(UploadFailureKind.protocol);
      }
      final image = data['image'];
      final imageRaw = image is Map<String, dynamic> ? image['url'] : null;
      final raw = imageRaw ?? data['url'];
      final url = _imgbbDirectUrl(raw, credential);
      if (url == null) {
        return const ProviderUploadUnknown(UploadFailureKind.protocol);
      }
      // Two purported direct URLs must agree; an unsafe fallback is never kept.
      if (data['url'] != null &&
          _imgbbDirectUrl(data['url'], credential) != url) {
        return const ProviderUploadUnknown(UploadFailureKind.protocol);
      }
      Uri? viewer;
      if (data['url_viewer'] != null) {
        viewer = _ordinaryUrl(data['url_viewer'], credential: credential);
        if (viewer == null ||
            viewer.host != 'ibb.co' ||
            viewer.path != '/$id') {
          return const ProviderUploadUnknown(UploadFailureKind.protocol);
        }
      }
      SensitiveManagementSecret? management;
      final deleteRaw = data['delete_url'];
      if (deleteRaw != null) {
        final delete = _ordinaryUrl(deleteRaw, credential: credential);
        if (delete == null ||
            delete.scheme != 'https' ||
            delete.host != 'ibb.co' ||
            !RegExp(r'^/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]{16,128}$')
                .hasMatch(delete.path) ||
            delete.pathSegments.first != id) {
          return const ProviderUploadUnknown(UploadFailureKind.protocol);
        }
        // No ordinary success field may contain the management secret or token.
        final token = delete.pathSegments.last;
        if (url.toString().contains(token) ||
            (viewer?.toString().contains(token) ?? false) ||
            id.contains(token)) {
          return const ProviderUploadUnknown(UploadFailureKind.protocol);
        }
        management = SensitiveManagementSecret(delete.toString());
      }
      return ProviderUploadSuccess(
        service: service,
        remoteId: id,
        directUrl: url,
        viewerUrl: viewer,
        managementSecret: management,
      );
    } catch (_) {
      return const ProviderUploadUnknown(UploadFailureKind.protocol);
    }
  }
}

abstract class _MultipartProviderAdapter implements ProviderAdapter {
  _MultipartProviderAdapter({required this.limits, this.transportFactory});
  @override
  final ProviderUploadLimits limits;
  final ProviderTransportFactory? transportFactory;
  String get endpoint;
  FormData createForm(MultipartFile file, ResolvedTarget target);
  ProviderUploadResult parseResponse(
    String body,
    int status,
    String? credential,
  );
  static const responseBudgetBytes = 64 * 1024;

  @override
  Future<ProviderUploadResult> upload({
    required File file,
    required String actualFormat,
    required int expectedBytes,
    required ResolvedTarget target,
    required CancelToken cancelToken,
    UploadActivityCallback? onActivity,
  }) async {
    if (cancelToken.isCancelled) {
      return const ProviderUploadCancelled(UploadDeliveryEvidence.notSent);
    }
    final account = target.target;
    if (account.service != service ||
        !account.enabled ||
        account.removed ||
        account.pendingOperation) {
      return const ProviderUploadFailure(
        UploadFailureKind.targetUnavailable,
        UploadDeliveryEvidence.notSent,
      );
    }
    if (account.anonymous || (target.credential?.trim().isEmpty ?? true)) {
      return const ProviderUploadFailure(
        UploadFailureKind.authorization,
        UploadDeliveryEvidence.notSent,
      );
    }
    try {
      if (expectedBytes <= 0 ||
          !await file.exists() ||
          await file.length() != expectedBytes) {
        return const ProviderUploadFailure(
          UploadFailureKind.fileUnavailable,
          UploadDeliveryEvidence.notSent,
        );
      }
    } catch (_) {
      return const ProviderUploadFailure(
        UploadFailureKind.fileUnavailable,
        UploadDeliveryEvidence.notSent,
      );
    }
    if (!limits.verified) {
      return const ProviderUploadFailure(
        UploadFailureKind.capabilityUnknown,
        UploadDeliveryEvidence.notSent,
      );
    }
    final format = actualFormat.toLowerCase();
    if (!limits.formats!.any((value) => value.toLowerCase() == format) ||
        !_mimeTypes.containsKey(format)) {
      return const ProviderUploadFailure(
        UploadFailureKind.formatUnsupported,
        UploadDeliveryEvidence.notSent,
      );
    }
    if (expectedBytes > limits.maximumBytesFor(format)!) {
      return const ProviderUploadFailure(
        UploadFailureKind.sizeExceeded,
        UploadDeliveryEvidence.notSent,
      );
    }
    if (cancelToken.isCancelled) {
      return const ProviderUploadCancelled(UploadDeliveryEvidence.notSent);
    }
    final dio = Dio(
      BaseOptions(
        followRedirects: false,
        maxRedirects: 0,
        responseType: ResponseType.stream,
        validateStatus: (_) => true,
        // Activity/total-runtime watchdogs belong to the scheduler. These are
        // transport timeouts only and do not claim QUE inactivity enforcement.
        connectTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 120),
        receiveTimeout: const Duration(seconds: 120),
      ),
    );
    late final _TrackedTransport tracked;
    try {
      tracked = _TrackedTransport(
        transportFactory?.call() ?? dio.httpClientAdapter,
      );
    } catch (_) {
      try {
        dio.close(force: true);
      } catch (_) {
        // No request or input stream has started.
      }
      return const ProviderUploadFailure(
        UploadFailureKind.protocol,
        UploadDeliveryEvidence.notSent,
      );
    }
    dio.httpClientAdapter = tracked;
    final input = _TrackedInput(file, expectedBytes);
    var received = 0;
    void activity(UploadActivityDirection direction, int bytes, int? total) {
      try {
        onActivity?.call(UploadActivity(direction, bytes, total));
      } catch (_) {
        // Observer failure cannot alter the network result or expose objects.
      }
    }

    try {
      if (cancelToken.isCancelled) {
        return const ProviderUploadCancelled(UploadDeliveryEvidence.notSent);
      }
      final multipart = MultipartFile.fromStream(
        input.open,
        expectedBytes,
        filename: 'image.${format == 'jpeg' ? 'jpg' : format}',
        contentType: DioMediaType.parse(_mimeTypes[format]!),
      );
      final response = await dio.post<ResponseBody>(
        endpoint,
        data: createForm(multipart, target),
        cancelToken: cancelToken,
        onSendProgress: (count, total) {
          activity(
            UploadActivityDirection.sending,
            count,
            total >= 0 ? total : null,
          );
        },
      );
      final responseBody = response.data;
      if (responseBody == null) {
        return const ProviderUploadUnknown(UploadFailureKind.protocol);
      }
      final status = response.statusCode ?? 0;
      final bytes = BytesBuilder(copy: false);
      final total = int.tryParse(
        response.headers.value(Headers.contentLengthHeader) ?? '',
      );
      // Even explicit refusals close/cancel their stream. Never consume an
      // unbounded body or publish provider-controlled error prose.
      if (status < 200 || status >= 300) {
        await _stopStream(responseBody.stream);
        return _httpFailure(status, response.headers.value('retry-after'));
      }
      if (status != 200) {
        await _stopStream(responseBody.stream);
        return const ProviderUploadUnknown(UploadFailureKind.protocol);
      }
      final stream = StreamIterator(responseBody.stream);
      try {
        while (await Future.any<bool>([
          stream.moveNext(),
          cancelToken.whenCancel.then((_) => false),
        ])) {
          final chunk = stream.current;
          received += chunk.length;
          activity(UploadActivityDirection.receiving, received, total);
          if (received > responseBudgetBytes) {
            return const ProviderUploadUnknown(UploadFailureKind.protocol);
          }
          bytes.add(chunk);
          if (cancelToken.isCancelled) break;
        }
      } finally {
        await stream.cancel();
      }
      if (cancelToken.isCancelled &&
          tracked.completeResponseBytes != received) {
        return const ProviderUploadCancelled(UploadDeliveryEvidence.uncertain);
      }
      final parsed = parseResponse(
        utf8.decode(bytes.takeBytes()),
        status,
        target.credential,
      );
      // Keep a full remote confirmation as evidence; the scheduler retains its
      // separate cancellation intent and never rewrites that durable state.
      if (cancelToken.isCancelled && parsed is! ProviderUploadSuccess) {
        return const ProviderUploadCancelled(UploadDeliveryEvidence.uncertain);
      }
      return parsed;
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel || cancelToken.isCancelled) {
        return const ProviderUploadCancelled(UploadDeliveryEvidence.uncertain);
      }
      if (input.failed) {
        return const ProviderUploadUnknown(UploadFailureKind.fileUnavailable);
      }
      if (error.type == DioExceptionType.connectionTimeout &&
          transportFactory == null &&
          !tracked.requestBodyConsumed) {
        return ProviderUploadFailure(
          UploadFailureKind.timeout,
          UploadDeliveryEvidence.notSent,
        );
      }
      final kind = switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => UploadFailureKind.timeout,
        DioExceptionType.connectionError => UploadFailureKind.network,
        _ => UploadFailureKind.unknown,
      };
      return ProviderUploadUnknown(kind);
    } catch (_) {
      return ProviderUploadUnknown(
        input.failed
            ? UploadFailureKind.fileUnavailable
            : UploadFailureKind.protocol,
      );
    } finally {
      // A stalled local source cannot rely on async*'s next event to observe
      // downstream cancellation. Stop its actual subscription concurrently
      // with network close, before waiting for the delegate's fetch to finish.
      final inputStopped = input.stop();
      dio.close(force: true);
      // Dio cancellation can finish before the underlying adapter. This Future
      // ends only after actual transport and local input IO have settled.
      try {
        await Future.wait([tracked.settled, inputStopped]);
      } catch (_) {
        throw const ProviderCleanupException();
      }
      if (tracked.cleanupFailed || input.cleanupFailed) {
        throw const ProviderCleanupException();
      }
    }
  }
}

const _mimeTypes = {
  'png': 'image/png',
  'jpeg': 'image/jpeg',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'bmp': 'image/bmp',
};

/// Dio's stock FormData producer fills a controller independently of socket
/// backpressure. This fixed-field variant consumes the local file only when
/// the transport consumes the multipart stream, and propagates cancellation.
final class _StreamingFormData extends FormData {
  _StreamingFormData(super.map) : super.fromMap();
  bool _used = false;
  @override
  bool get isFinalized => _used;
  @override
  Stream<Uint8List> finalize() {
    if (_used) throw StateError('multipart already consumed');
    _used = true;
    return _produce();
  }

  Stream<Uint8List> _produce() async* {
    Uint8List encode(String value) => Uint8List.fromList(utf8.encode(value));
    for (final field in fields) {
      // Field names are fixed reqtype/userhash/key; secret values are body only.
      yield encode(
        '--$boundary\r\ncontent-disposition: form-data; '
        'name="${field.key}"\r\n\r\n${field.value}\r\n',
      );
    }
    for (final entry in files) {
      final file = entry.value;
      yield encode(
        '--$boundary\r\ncontent-disposition: form-data; '
        'name="${entry.key}"; filename="${file.filename}"\r\n'
        'content-type: ${file.contentType}\r\n\r\n',
      );
      yield* file.finalize();
      yield encode('\r\n');
    }
    yield encode('--$boundary--\r\n');
  }
}

bool _containsSecret(String value, String? credential) =>
    credential != null &&
    credential.isNotEmpty &&
    (value.contains(credential) ||
        value.contains(Uri.encodeComponent(credential)));

Uri? _ordinaryUrl(Object? value, {String? credential}) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 4096 ||
      _containsSecret(value, credential) ||
      RegExp(r'[\s\x00-\x1f\x7f\\]').hasMatch(value) ||
      RegExp(
        r'%0[0-9a-f]|%1[0-9a-f]|%7f',
        caseSensitive: false,
      ).hasMatch(value)) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.hasAuthority ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.userInfo.isNotEmpty ||
      uri.host.isEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.hasPort ||
      uri.path.isEmpty ||
      uri.pathSegments.any((segment) => segment == '.' || segment == '..')) {
    return null;
  }
  return uri;
}

Uri? _imgbbDirectUrl(Object? raw, String? credential) {
  final url = _ordinaryUrl(raw, credential: credential);
  return url != null &&
          url.host == 'i.ibb.co' &&
          RegExp(
            r'^/[a-zA-Z0-9_-]+/[a-zA-Z0-9._-]+\.(?:png|jpe?g|gif|webp|bmp)$',
            caseSensitive: false,
          ).hasMatch(url.path)
      ? url
      : null;
}

ProviderUploadResult _httpFailure(int status, String? retryAfter) {
  final kind = switch (status) {
    401 || 403 => UploadFailureKind.authorization,
    402 => UploadFailureKind.quota,
    413 => UploadFailureKind.sizeExceeded,
    415 || 422 => UploadFailureKind.formatUnsupported,
    429 => UploadFailureKind.rateLimited,
    _ => null,
  };
  if (kind == null) {
    return const ProviderUploadUnknown(UploadFailureKind.protocol);
  }
  int? delta;
  DateTime? utc;
  if (retryAfter != null && retryAfter.length <= 128) {
    if (RegExp(r'^[0-9]+$').hasMatch(retryAfter)) {
      delta = int.tryParse(retryAfter);
    } else {
      try {
        utc = HttpDate.parse(retryAfter).toUtc();
      } catch (_) {
        // Invalid evidence is distinct from an absent waiting instruction.
      }
    }
  }
  return ProviderUploadFailure(
    kind,
    UploadDeliveryEvidence.confirmedRejected,
    retryAfterSeconds: delta,
    retryAfterUtc: utc,
    retryAfterInvalid: retryAfter != null && delta == null && utc == null,
  );
}

Future<void> _stopStream(Stream<Uint8List> stream) async {
  final subscription = stream.listen((_) {}, onError: (Object _) {});
  await subscription.cancel();
}

final class _TrackedTransport implements HttpClientAdapter {
  _TrackedTransport(this.delegate);
  final HttpClientAdapter delegate;
  final List<Future<void>> _pending = [];
  final List<_BoundedResponse> _responses = [];
  bool _closed = false;
  bool requestBodyConsumed = false;
  bool _closeFailed = false;
  bool _subscribeFailed = false;
  bool get cleanupFailed =>
      _closeFailed ||
      _subscribeFailed ||
      _responses.any((response) => response.cleanupFailed);
  int? get completeResponseBytes =>
      _responses.isNotEmpty && _responses.last.completed
      ? _responses.last.bytesReceived
      : null;
  Future<void> get settled async {
    await Future.wait(_pending);
    // A response can arrive after cancellation while fetch is still pending.
    await Future.wait(_responses.map((value) => value.settled));
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final done = Completer<void>();
    _pending.add(done.future);
    final trackedRequest = requestStream?.map((chunk) {
      if (chunk.isNotEmpty) requestBodyConsumed = true;
      return chunk;
    });
    try {
      final body = await delegate.fetch(options, trackedRequest, cancelFuture);
      late final _BoundedResponse bounded;
      try {
        bounded = _BoundedResponse(body.stream);
      } catch (_) {
        // A source which refuses subscription has no confirmed cleanup. The
        // caller must retain its IO protection, rather than guess it is idle.
        _subscribeFailed = true;
        throw const _MalformedResponse();
      }
      _responses.add(bounded);
      _pending.add(bounded.settled);
      body.stream = bounded.stream;
      if (_closed) unawaited(bounded.stop());
      return body;
    } catch (error) {
      // Sanitize before Dio formats or retains a provider-controlled object.
      throw DioException(
        requestOptions: options,
        type: error is DioException ? error.type : DioExceptionType.unknown,
        message: '上传请求未得到确认。',
      );
    } finally {
      // Includes a synchronous throw before the delegate returns a Future.
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

final class _ResponseTooLarge implements Exception {
  const _ResponseTooLarge();
}

final class _MalformedResponse implements Exception {
  const _MalformedResponse();
}

/// Cap the original stream before Dio eagerly subscribes its response wrapper.
/// Explicit cancellation reaches the source even when Dio's returned stream
/// cancellation does not propagate to that source.
final class _BoundedResponse {
  _BoundedResponse(Stream<Uint8List> source) {
    _controller = StreamController<Uint8List>(
      onCancel: stop,
      onPause: () => _subscription.pause(),
      onResume: () => _subscription.resume(),
    );
    _subscription = source.listen(
      (chunk) {
        if (_stopping != null) return;
        _bytes += chunk.length;
        if (_bytes > _MultipartProviderAdapter.responseBudgetBytes) {
          _controller.addError(const _ResponseTooLarge());
          scheduleMicrotask(stop);
        } else {
          _controller.add(chunk);
        }
      },
      onError: (Object _) {
        if (_stopping == null) _controller.addError(const _MalformedResponse());
        scheduleMicrotask(stop);
      },
      onDone: () {
        completed = true;
        scheduleMicrotask(stop);
      },
    );
  }
  late final StreamController<Uint8List> _controller;
  late final StreamSubscription<Uint8List> _subscription;
  final _done = Completer<void>();
  Future<void>? _stopping;
  int _bytes = 0;
  bool completed = false;
  bool cleanupFailed = false;
  int get bytesReceived => _bytes;
  Stream<Uint8List> get stream => _controller.stream;
  Future<void> get settled => _done.future;
  Future<void> stop() => _stopping ??= _stop();
  Future<void> _stop() async {
    try {
      await _subscription.cancel();
    } catch (_) {
      cleanupFailed = true;
    } finally {
      // Do not wait for a never-listened sink; only the actual source IO matters.
      unawaited(_controller.close());
      _done.complete();
    }
  }
}

final class _TrackedInput {
  _TrackedInput(this.file, this.expectedBytes);
  final File file;
  final int expectedBytes;
  final _done = Completer<void>();
  StreamController<List<int>>? _controller;
  StreamSubscription<List<int>>? _subscription;
  Future<void>? _stopping;
  bool _opened = false;
  int _read = 0;
  bool failed = false;
  bool cleanupFailed = false;
  Stream<List<int>> open() {
    if (_opened) throw StateError('input stream already opened');
    _opened = true;
    if (_stopping != null) return const Stream.empty();
    _controller = StreamController<List<int>>(
      onListen: _start,
      onPause: () => _subscription?.pause(),
      onResume: () => _subscription?.resume(),
      onCancel: stop,
    );
    return _controller!.stream;
  }

  void _start() {
    if (_stopping != null) {
      unawaited(_controller!.close());
      return;
    }
    try {
      _subscription = file.openRead().listen(
        (chunk) {
          if (_stopping != null) return;
          _read += chunk.length;
          if (_read > expectedBytes) {
            _fail();
          } else {
            _controller!.add(chunk);
          }
        },
        onError: (Object _) => _fail(),
        onDone: () {
          if (_read != expectedBytes) {
            _fail();
          } else {
            unawaited(stop());
          }
        },
      );
    } catch (_) {
      _fail();
    }
  }

  void _fail() {
    if (_stopping != null) return;
    failed = true;
    _controller!.addError(const _FileChanged());
    unawaited(stop());
  }

  Future<void> stop() => _stopping ??= _stop();
  Future<void> _stop() async {
    try {
      await _subscription?.cancel();
    } catch (_) {
      // Never expose a native file-close exception or its path to callers.
      failed = true;
      cleanupFailed = true;
    } finally {
      final controller = _controller;
      if (controller != null) unawaited(controller.close());
      _done.complete();
    }
    await _done.future;
  }
}

final class _FileChanged implements Exception {
  const _FileChanged();
}
