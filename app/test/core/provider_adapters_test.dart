import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/upload/data/provider_adapters.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';

// Test-only exact fixture limits. These are NOT verified service capabilities.
final _limits = ProviderUploadLimits(maximumBytes: 64, formats: {'png'});
const _key = 'fixture-key-never-a-real-credential';
const _managementToken = 'fixtureDeleteToken0123456789';
const _management = 'https://ibb.co/resultId/$_managementToken';
const _catboxLink = 'https://files.catbox.moe/abc123.png';

ResolvedTarget _target(
  ImageHostService service, {
  bool anonymous = false,
  String id = 'fixture-target-a',
  String? key = _key,
  bool enabled = true,
}) => ResolvedTarget(
  ProviderTarget(
    id: id,
    service: service,
    alias: '同名测试账号',
    enabled: enabled,
    selectedByDefault: false,
    anonymous: anonymous,
    health: AccountHealth.unverified,
    removed: false,
    generation: 1,
  ),
  anonymous ? null : key,
);

String _imgbbBody({
  String url = 'https://i.ibb.co/imageId/image.png',
  bool success = true,
  int status = 200,
  String? delete = _management,
}) => jsonEncode({
  'success': success,
  'status': status,
  'data': {
    'id': 'resultId',
    'image': {'url': url},
    'url': url,
    'url_viewer': 'https://ibb.co/resultId',
    'delete_url': ?delete,
  },
});

typedef _Reply = Future<ResponseBody> Function(RequestOptions options);

final class _FakeTransport implements HttpClientAdapter {
  _FakeTransport(this.reply);
  final _Reply reply;
  final options = <RequestOptions>[];
  final bodies = <List<int>>[];
  int closes = 0;
  bool failClose = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions request,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    options.add(request);
    final bytes = BytesBuilder();
    if (stream != null) {
      await for (final chunk in stream) {
        bytes.add(chunk);
      }
    }
    bodies.add(bytes.takeBytes());
    return reply(request);
  }

  @override
  void close({bool force = false}) {
    closes++;
    if (failClose) throw _UnsafeFailure();
  }
}

final class _UnsafeFailure implements Exception {
  @override
  String toString() => throw StateError('must not stringify transport error');
}

final class _ManualTransport implements HttpClientAdapter {
  _ManualTransport(this.handler);
  final Future<ResponseBody> Function(
    RequestOptions,
    Stream<Uint8List>?,
    Future<void>?,
  )
  handler;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) => handler(options, stream, cancelFuture);
  @override
  void close({bool force = false}) {}
}

final class _RefusingResponse extends Stream<Uint8List> {
  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => throw _UnsafeFailure();
}

final class _ProbeFile implements File {
  _ProbeFile(this.source);
  final Stream<Uint8List> source;
  int opens = 0;
  int checks = 0;
  @override
  Future<bool> exists() async {
    checks++;
    return true;
  }

  @override
  Future<int> length() async {
    checks++;
    return 8;
  }

  @override
  Stream<Uint8List> openRead([int? start, int? end]) {
    opens++;
    return source;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unused file operation');
}

void main() {
  late Directory temporary;
  late File file;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('imagehost-adapter-ut-');
    file = File('${temporary.path}/fixture.png');
    await file.writeAsBytes([137, 80, 78, 71, 13, 10, 26, 10]);
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test(
    'UT-047 upload capability format snapshot cannot change after construction',
    () {
      final mutable = <String>{'png'};
      final limits = ProviderUploadLimits(maximumBytes: 64, formats: mutable);
      mutable.add('gif');
      expect(limits.formats, {'png'});
      expect(() => limits.formats!.add('jpeg'), throwsUnsupportedError);
    },
  );

  test('UT-047 format-specific fixture limits normalize and keep immutable snapshots', () {
    final mutableFormats = <String>{'PNG', 'GIF'};
    final mutableLimits = <String, int>{'gIf': 4};
    final limits = ProviderUploadLimits(
      maximumBytes: 8,
      formats: mutableFormats,
      formatMaximumBytes: mutableLimits,
    );
    mutableFormats.clear();
    mutableLimits['gIf'] = 8;
    mutableLimits['png'] = 1;
    expect(limits.verified, isTrue);
    expect(limits.formatMaximumBytes, {'gif': 4});
    expect(limits.maximumBytesFor('GIF'), 4);
    expect(limits.maximumBytesFor('gIf'), 4);
    expect(limits.maximumBytesFor('png'), 8);
    expect(limits.maximumBytesFor('webp'), isNull);
    expect(() => limits.formatMaximumBytes['gif'] = 8, throwsUnsupportedError);
    expect(() => limits.formatMaximumBytes.clear(), throwsUnsupportedError);
    expect(
      ProviderUploadLimits(
        maximumBytes: 8,
        formats: {'gif'},
        formatMaximumBytes: {'GIF': 12},
      ).maximumBytesFor('gif'),
      8,
    );
  });

  test(
    'UT-047 conflicting normalized format-limit keys reject construction',
    () {
      expect(
        () => ProviderUploadLimits(
          maximumBytes: 8,
          formats: {'gif'},
          formatMaximumBytes: {'GIF': 4, 'gif': 4},
        ),
        throwsArgumentError,
      );
    },
  );

  Future<ProviderUploadResult> upload(
    ProviderAdapter adapter,
    ResolvedTarget target, {
    CancelToken? token,
    int expectedBytes = 8,
    String format = 'PNG',
    UploadActivityCallback? activity,
  }) => adapter.upload(
    file: file,
    actualFormat: format,
    expectedBytes: expectedBytes,
    target: target,
    cancelToken: token ?? CancelToken(),
    onActivity: activity,
  );

  for (final service in ImageHostService.values) {
    ProviderAdapter withFixtureLimits(
      ProviderUploadLimits limits,
      ProviderTransportFactory factory,
    ) => service == ImageHostService.catbox
        ? CatboxAdapter(limits: limits, transportFactory: factory)
        : ImgBBAdapter(limits: limits, transportFactory: factory);

    test(
      'UT-047 ${service.name} applies stricter GIF fixture limit before transport',
      () async {
        // These tiny byte counts are synthetic fixtures, not service limits.
        final limits = ProviderUploadLimits(
          maximumBytes: 8,
          formats: {'PNG', 'GIF'},
          formatMaximumBytes: {'gIf': 4},
        );
        final fake = _FakeTransport(
          (_) async => ResponseBody.fromString(
            service == ImageHostService.catbox ? _catboxLink : _imgbbBody(),
            200,
          ),
        );
        var factories = 0;
        final adapter = withFixtureLimits(limits, () {
          factories++;
          return fake;
        });
        await file.writeAsBytes(List.filled(4, 0));
        expect(
          await upload(
            adapter,
            _target(service),
            expectedBytes: 4,
            format: 'GiF',
          ),
          isA<ProviderUploadSuccess>(),
        );
        expect(factories, 1);
        expect(fake.options, hasLength(1));

        await file.writeAsBytes(List.filled(5, 0));
        final rejected = await upload(
          adapter,
          _target(service),
          expectedBytes: 5,
          format: 'GIF',
        ) as ProviderUploadFailure;
        expect(rejected.kind, UploadFailureKind.sizeExceeded);
        expect(rejected.evidence, UploadDeliveryEvidence.notSent);
        expect(factories, 1);
        expect(fake.options, hasLength(1));

        expect(
          await upload(
            adapter,
            _target(service),
            expectedBytes: 5,
            format: 'pNg',
          ),
          isA<ProviderUploadSuccess>(),
        );
        expect(factories, 2);
        expect(fake.options, hasLength(2));
      },
    );

    test(
      'UT-047 ${service.name} invalid format fixture limits reject all before transport',
      () async {
        final fake = _FakeTransport(
          (_) async => ResponseBody.fromString('', 200),
        );
        var factories = 0;
        for (final extraLimits in [
          {'webp': 4},
          {'gif': 0},
          {'GIF': -1},
        ]) {
          final limits = ProviderUploadLimits(
            maximumBytes: 8,
            formats: {'png', 'gif'},
            formatMaximumBytes: extraLimits,
          );
          expect(limits.verified, isFalse);
          expect(limits.maximumBytesFor('png'), isNull);
          final rejected = await upload(
            withFixtureLimits(limits, () {
              factories++;
              return fake;
            }),
            _target(service),
          ) as ProviderUploadFailure;
          expect(rejected.kind, UploadFailureKind.capabilityUnknown);
          expect(rejected.evidence, UploadDeliveryEvidence.notSent);
        }
        expect(factories, 0);
        expect(fake.options, isEmpty);
      },
    );

    test(
      'UT-047 ${service.name} production default capabilities remain unknown',
      () async {
        final fake = _FakeTransport(
          (_) async => ResponseBody.fromString('', 200),
        );
        var factories = 0;
        HttpClientAdapter factory() {
          factories++;
          return fake;
        }

        final ProviderAdapter adapter = service == ImageHostService.catbox
            ? CatboxAdapter(transportFactory: factory)
            : ImgBBAdapter(transportFactory: factory);
        expect(adapter.limits.verified, isFalse);
        expect(adapter.limits.maximumBytes, isNull);
        expect(adapter.limits.formats, isNull);
        expect(adapter.limits.formatMaximumBytes, isEmpty);
        expect(adapter.limits.maximumBytesFor('png'), isNull);
        final rejected =
            await upload(adapter, _target(service)) as ProviderUploadFailure;
        expect(rejected.kind, UploadFailureKind.capabilityUnknown);
        expect(rejected.evidence, UploadDeliveryEvidence.notSent);
        expect(factories, 0);
        expect(fake.options, isEmpty);
      },
    );
  }

  test(
    'UT-047 unknown exact capabilities fail closed, not unlimited MB guesses',
    () async {
      final fake = _FakeTransport(
        (_) async => ResponseBody.fromString(_catboxLink, 200),
      );
      final result = await upload(
        CatboxAdapter(transportFactory: () => fake),
        _target(ImageHostService.catbox),
      );
      expect(result, isA<ProviderUploadFailure>());
      expect(
        (result as ProviderUploadFailure).kind,
        UploadFailureKind.capabilityUnknown,
      );
      expect(result.evidence, UploadDeliveryEvidence.notSent);
      expect(fake.options, isEmpty);
    },
  );

  test('UT-047 actual size, format, missing file and credential reject before request', () async {
    final fake = _FakeTransport(
      (_) async => ResponseBody.fromString(_catboxLink, 200),
    );
    final adapter = CatboxAdapter(
      limits: _limits,
      transportFactory: () => fake,
    );
    final target = _target(ImageHostService.catbox);
    expect(
      (await upload(
        adapter,
        target,
        expectedBytes: 7,
      ) as ProviderUploadFailure).kind,
      UploadFailureKind.fileUnavailable,
    );
    expect(
      (await upload(
        adapter,
        target,
        format: 'GIF',
      ) as ProviderUploadFailure).kind,
      UploadFailureKind.formatUnsupported,
    );
    expect(
      (await upload(
        adapter,
        _target(ImageHostService.catbox, key: null),
      ) as ProviderUploadFailure).kind,
      UploadFailureKind.authorization,
    );
    await file.writeAsBytes(List.filled(65, 0));
    expect(
      (await upload(
        adapter,
        target,
        expectedBytes: 65,
      ) as ProviderUploadFailure).kind,
      UploadFailureKind.sizeExceeded,
    );
    await file.delete();
    expect(
      (await upload(adapter, target) as ProviderUploadFailure).kind,
      UploadFailureKind.fileUnavailable,
    );
    expect(fake.options, isEmpty);
  });

  test(
    'UT-041/045 Catbox same-alias accounts keep body secrets isolated',
    () async {
      final fake = _FakeTransport(
        (_) async => ResponseBody.fromString(_catboxLink, 200),
      );
      final adapter = CatboxAdapter(
        limits: _limits,
        transportFactory: () => fake,
      );
      for (final target in [
        _target(ImageHostService.catbox),
        _target(
          ImageHostService.catbox,
          id: 'fixture-target-b',
          key: 'fixture-other-key',
        ),
      ]) {
        expect(await upload(adapter, target), isA<ProviderUploadSuccess>());
      }
      final text = fake.bodies.map(latin1.decode).toList();
      expect(text[0], contains('name="reqtype"'));
      expect(text[0], contains('fileupload'));
      expect(text[0], contains('name="userhash"'));
      expect(text[0], contains(_key));
      expect(text[0], isNot(contains('fixture-other-key')));
      expect(text[1], contains('fixture-other-key'));
      expect(text[1], isNot(contains(_key)));
      for (final request in fake.options) {
        expect(request.uri.toString(), 'https://catbox.moe/user/api.php');
        expect(request.followRedirects, isFalse);
        expect(request.maxRedirects, 0);
        expect(request.uri.hasQuery, isFalse);
      }
      for (var i = 0; i < fake.options.length; i++) {
        expect(
          fake.bodies[i].length,
          int.parse(
            fake.options[i].headers[Headers.contentLengthHeader] as String,
          ),
        );
      }
    },
  );

  test('UT-041/048 ImgBB key is multipart body and viewer/management stay separate', () async {
    final fake = _FakeTransport(
      (_) async => ResponseBody.fromString(_imgbbBody(), 200),
    );
    final result = await upload(
      ImgBBAdapter(limits: _limits, transportFactory: () => fake),
      _target(ImageHostService.imgbb),
    ) as ProviderUploadSuccess;
    final request = fake.options.single;
    expect(request.uri.toString(), 'https://api.imgbb.com/1/upload');
    expect(request.uri.hasQuery, isFalse);
    final body = latin1.decode(fake.bodies.single);
    expect(
      fake.bodies.single.length,
      int.parse(request.headers[Headers.contentLengthHeader] as String),
    );
    expect(body, contains('name="key"'));
    expect(body, contains(_key));
    expect(body, contains('name="image"'));
    expect(body, isNot(contains('expiration')));
    expect(result.directUrl.toString(), 'https://i.ibb.co/imageId/image.png');
    expect(result.viewerUrl.toString(), 'https://ibb.co/resultId');
    expect(result.managementSecret!.revealForProtectedStorage(), _management);
    expect(
      result.managementSecret.toString(),
      isNot(contains(_managementToken)),
    );
    expect(result.toString(), isNot(contains(_managementToken)));
    expect(result.toString(), isNot(contains(_key)));
  });

  test(
    'UT-060 each explicit new attempt creates fresh multipart and file stream',
    () async {
      final fake = _FakeTransport(
        (_) async => ResponseBody.fromString(_catboxLink, 200),
      );
      final adapter = CatboxAdapter(
        limits: _limits,
        transportFactory: () => fake,
      );
      final target = _target(ImageHostService.catbox);
      expect(await upload(adapter, target), isA<ProviderUploadSuccess>());
      await file.writeAsBytes([1, 2, 3, 4, 5, 6, 7, 8]);
      expect(await upload(adapter, target), isA<ProviderUploadSuccess>());
      expect(identical(fake.options[0].data, fake.options[1].data), isFalse);
      expect(fake.bodies[0], contains(137));
      expect(fake.bodies[1], isNot(contains(137)));
      expect(fake.options, hasLength(2));
    },
  );

  test(
    'UT-041 multipart byte length includes exact UTF8 credential encoding',
    () async {
      const credential = '测试密钥🔐é';
      for (final service in ImageHostService.values) {
        final fake = _FakeTransport(
          (_) async => ResponseBody.fromString(
            service == ImageHostService.catbox ? _catboxLink : _imgbbBody(),
            200,
          ),
        );
        final ProviderAdapter adapter = service == ImageHostService.catbox
            ? CatboxAdapter(limits: _limits, transportFactory: () => fake)
            : ImgBBAdapter(limits: _limits, transportFactory: () => fake);
        expect(
          await upload(adapter, _target(service, key: credential)),
          isA<ProviderUploadSuccess>(),
        );
        final bytes = fake.bodies.single;
        final request = fake.options.single;
        expect(
          bytes.length,
          int.parse(request.headers[Headers.contentLengthHeader] as String),
        );
        expect(
          latin1.decode(bytes),
          contains(latin1.decode(utf8.encode(credential))),
        );
        expect(request.uri.hasQuery, isFalse);
      }
    },
  );

  test(
    'UT-047 stream changed after length check is unknown fileUnavailable',
    () async {
      for (final actualBytes in [7, 9]) {
        file = _ProbeFile(Stream.value(Uint8List(actualBytes)));
        final fake = _FakeTransport(
          (_) async => ResponseBody.fromString(_catboxLink, 200),
        );
        final result = await upload(
          CatboxAdapter(limits: _limits, transportFactory: () => fake),
          _target(ImageHostService.catbox),
        ) as ProviderUploadUnknown;
        expect(result.kind, UploadFailureKind.fileUnavailable);
        expect(result.evidence, UploadDeliveryEvidence.uncertain);
      }
    },
  );

  test(
    'UT-047 input source exception becomes safe unknown fileUnavailable',
    () async {
      file = _ProbeFile(Stream.error(_UnsafeFailure()));
      final fake = _FakeTransport(
        (_) async => ResponseBody.fromString(_catboxLink, 200),
      );
      final result = await upload(
        CatboxAdapter(limits: _limits, transportFactory: () => fake),
        _target(ImageHostService.catbox),
      ) as ProviderUploadUnknown;
      expect(result.kind, UploadFailureKind.fileUnavailable);
      expect(result.toString(), isNot(contains(_key)));
    },
  );

  test('UT-048/096 Catbox malformed, HTML, userinfo and unsafe URLs remain unknown', () async {
    for (final response in [
      '',
      '<html>$_key</html>',
      'Error: invalid userhash $_key',
      'javascript:alert(1)',
      'https://evil.example/a.png',
      'https://$_key@files.catbox.moe/a.png',
      'https://files.catbox.moe/a.png?key=$_key',
      'https://files.catbox.moe/a.png#secret',
      'https://files.catbox.moe/a.png%0a',
      'https://files.catbox.moe:444/a.png',
    ]) {
      final fake = _FakeTransport(
        (_) async => ResponseBody.fromString(response, 200),
      );
      final result = await upload(
        CatboxAdapter(limits: _limits, transportFactory: () => fake),
        _target(ImageHostService.catbox),
      );
      expect(result, isA<ProviderUploadUnknown>());
      expect(result.toString(), isNot(contains(_key)));
    }
  });

  test(
    'UT-048 ImgBB malformed and inconsistent success evidence is not success',
    () async {
      final inconsistent = jsonDecode(_imgbbBody()) as Map<String, dynamic>;
      (inconsistent['data'] as Map<String, dynamic>)['url'] =
          'https://i.ibb.co/imageId/other.png';
      for (final body in [
        '<html>$_key</html>',
        '{',
        '{}',
        _imgbbBody(success: false),
        _imgbbBody(status: 201),
        jsonEncode(inconsistent),
        jsonEncode({
          'success': true,
          'status': 200,
          'data': {'url': 'https://i.ibb.co/id/a.png'},
        }),
        _imgbbBody(url: 'https://ibb.co/resultId'),
        _imgbbBody(url: 'https://i.ibb.co/imageId/$_key.png'),
        _imgbbBody(delete: 'https://evil.example/resultId/$_managementToken'),
        _imgbbBody(delete: 'http://ibb.co/resultId/$_managementToken'),
        _imgbbBody(delete: 'https://ibb.co/otherId/$_managementToken'),
        _imgbbBody(
          delete: 'https://ibb.co/resultId/$_managementToken?key=$_key',
        ),
      ]) {
        final fake = _FakeTransport(
          (_) async => ResponseBody.fromString(body, 200),
        );
        final result = await upload(
          ImgBBAdapter(limits: _limits, transportFactory: () => fake),
          _target(ImageHostService.imgbb),
        );
        expect(result, isA<ProviderUploadUnknown>());
        expect(result.toString(), isNot(contains(_key)));
        expect(result.toString(), isNot(contains(_managementToken)));
      }
    },
  );

  test('UT-048 ImgBB accepts data.url fallback without image; HTTP is explicitly marked', () async {
    final response = jsonDecode(
      _imgbbBody(url: 'http://i.ibb.co/imageId/image.png', delete: null),
    ) as Map<String, dynamic>;
    (response['data'] as Map<String, dynamic>).remove('image');
    final fake = _FakeTransport(
      (_) async => ResponseBody.fromString(jsonEncode(response), 200),
    );
    final result = await upload(
      ImgBBAdapter(limits: _limits, transportFactory: () => fake),
      _target(ImageHostService.imgbb),
    ) as ProviderUploadSuccess;
    expect(result.usesInsecureHttp, isTrue);
    expect(result.managementSecret, isNull);
  });

  test(
    'UT-058/059 explicit refusals and Retry-After retain safe classification',
    () async {
      for (final entry in {
        401: UploadFailureKind.authorization,
        403: UploadFailureKind.authorization,
        402: UploadFailureKind.quota,
        413: UploadFailureKind.sizeExceeded,
        415: UploadFailureKind.formatUnsupported,
        422: UploadFailureKind.formatUnsupported,
        429: UploadFailureKind.rateLimited,
      }.entries) {
        final fake = _FakeTransport(
          (_) async => ResponseBody.fromString(
            _key,
            entry.key,
            headers: {
              'retry-after': ['172800'],
            },
          ),
        );
        final result = await upload(
          CatboxAdapter(limits: _limits, transportFactory: () => fake),
          _target(ImageHostService.catbox),
        ) as ProviderUploadFailure;
        expect(result.kind, entry.value);
        expect(result.evidence, UploadDeliveryEvidence.confirmedRejected);
        expect(result.retryAfterSeconds, 172800); // Never clipped to 24 hours.
        expect(result.toString(), isNot(contains(_key)));
        expect(fake.options, hasLength(1));
      }
    },
  );

  test('UT-059 Retry-After supports absolute HTTP date and flags malformed evidence', () async {
    for (final value in ['Wed, 21 Oct 2026 07:28:00 GMT', '-1', _key]) {
      final fake = _FakeTransport(
        (_) async => ResponseBody.fromString(
          'refused',
          429,
          headers: {
            'retry-after': [value],
          },
        ),
      );
      final result = await upload(
        CatboxAdapter(limits: _limits, transportFactory: () => fake),
        _target(ImageHostService.catbox),
      ) as ProviderUploadFailure;
      if (value.startsWith('Wed')) {
        expect(result.retryAfterUtc, DateTime.utc(2026, 10, 21, 7, 28));
        expect(result.retryAfterInvalid, isFalse);
      } else {
        expect(result.retryAfterInvalid, isTrue);
        expect(result.retryAfterSeconds, isNull);
      }
    }
  });

  test('UT-058/061 408, 5xx and redirects have uncertain side effects and no retry', () async {
    for (final status in [302, 400, 408, 500, 502, 503]) {
      final fake = _FakeTransport(
        (_) async => ResponseBody.fromString(_key, status),
      );
      final result = await upload(
        CatboxAdapter(limits: _limits, transportFactory: () => fake),
        _target(ImageHostService.catbox),
      );
      expect(result, isA<ProviderUploadUnknown>());
      expect(fake.options, hasLength(1));
      expect(result.toString(), isNot(contains(_key)));
    }
  });

  test(
    'UT-058/097 transport timeout/error never exposes Dio payload or object',
    () async {
      for (final type in [
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
        DioExceptionType.badCertificate,
        DioExceptionType.unknown,
      ]) {
        final fake = _FakeTransport(
          (request) async => throw DioException(
            requestOptions: request,
            type: type,
            error: _UnsafeFailure(),
            message: 'key=$_key delete_url=$_management',
          ),
        );
        final result = await upload(
          CatboxAdapter(limits: _limits, transportFactory: () => fake),
          _target(ImageHostService.catbox),
        );
        expect(result, isA<ProviderUploadUnknown>());
        expect(result.toString(), isNot(contains(_key)));
        expect(result.toString(), isNot(contains(_managementToken)));
        expect(fake.options, hasLength(1));
      }
    },
  );

  test('UT-058 connectionTimeout after request consumption is unknown despite exception type', () async {
    final fake = _FakeTransport(
      (request) async => throw DioException.connectionTimeout(
        requestOptions: request,
        timeout: const Duration(seconds: 30),
      ),
    );
    final result = await upload(
      CatboxAdapter(limits: _limits, transportFactory: () => fake),
      _target(ImageHostService.catbox),
    ) as ProviderUploadUnknown;
    expect(result.kind, UploadFailureKind.timeout);
    expect(result.evidence, UploadDeliveryEvidence.uncertain);
  });

  test('UT-055 pre-cancel does not read a missing file or dispatch', () async {
    await file.delete();
    final token = CancelToken()..cancel(_key);
    final fake = _FakeTransport(
      (_) async => ResponseBody.fromString(_catboxLink, 200),
    );
    final result = await upload(
      CatboxAdapter(limits: _limits, transportFactory: () => fake),
      _target(ImageHostService.catbox),
      token: token,
    ) as ProviderUploadCancelled;
    expect(result.evidence, UploadDeliveryEvidence.notSent);
    expect(fake.options, isEmpty);
    expect(result.toString(), isNot(contains(_key)));
  });

  test('UT-056 cancellation at final receive activity retains complete success evidence', () async {
    final token = CancelToken();
    final fake = _FakeTransport(
      (_) async => ResponseBody.fromString(_catboxLink, 200),
    );
    final result = await upload(
      CatboxAdapter(limits: _limits, transportFactory: () => fake),
      _target(ImageHostService.catbox),
      token: token,
      activity: (event) {
        if (event.direction == UploadActivityDirection.receiving) {
          token.cancel();
        }
      },
    );
    expect(token.isCancelled, isTrue);
    expect(result, isA<ProviderUploadSuccess>());
    expect((result as ProviderUploadSuccess).directUrl.toString(), _catboxLink);
  });

  test('UT-056 syntactically valid partial URL cannot turn cancellation into success', () async {
    final token = CancelToken();
    final source = StreamController<Uint8List>();
    final fake = _FakeTransport((_) async {
      scheduleMicrotask(() {
        source.add(Uint8List.fromList(utf8.encode(_catboxLink)));
        source.add(
          Uint8List.fromList(utf8.encode('invalid trailing response')),
        );
        unawaited(source.close());
      });
      return ResponseBody(source.stream, 200);
    });
    final result = await upload(
      CatboxAdapter(limits: _limits, transportFactory: () => fake),
      _target(ImageHostService.catbox),
      token: token,
      activity: (event) {
        if (event.direction == UploadActivityDirection.receiving) {
          token.cancel();
        }
      },
    );
    expect(result, isA<ProviderUploadCancelled>());
  });

  test(
    'UT-055 cancellation after length check prevents stream open and dispatch',
    () async {
      final probe = _ProbeFile(const Stream.empty());
      file = probe;
      final token = CancelToken();
      final fake = _FakeTransport(
        (_) async => ResponseBody.fromString(_catboxLink, 200),
      );
      final adapter = CatboxAdapter(
        limits: _limits,
        transportFactory: () {
          token.cancel();
          return fake;
        },
      );
      final result = await upload(
        adapter,
        _target(ImageHostService.catbox),
        token: token,
      ) as ProviderUploadCancelled;
      expect(result.evidence, UploadDeliveryEvidence.notSent);
      expect(probe.checks, 2);
      expect(probe.opens, 0);
      expect(fake.options, isEmpty);
    },
  );

  test('UT-058 untrusted connectionTimeout before consumption lacks notSent evidence', () async {
    final probe = _ProbeFile(const Stream.empty());
    file = probe;
    final fake = _ManualTransport(
      (request, _, _) async => throw DioException.connectionTimeout(
        requestOptions: request,
        timeout: const Duration(seconds: 30),
      ),
    );
    final result = await upload(
      CatboxAdapter(limits: _limits, transportFactory: () => fake),
      _target(ImageHostService.catbox),
    ) as ProviderUploadUnknown;
    expect(result.kind, UploadFailureKind.timeout);
    expect(
      probe.opens,
      0,
    ); // Multipart preparation never reads ahead of socket.
  });

  test(
    'UT-055/102 cancelled request waits for actual input source cancellation',
    () async {
      final readStarted = Completer<void>();
      final cancelStarted = Completer<void>();
      final ioExited = Completer<void>();
      final source = StreamController<Uint8List>(
        onListen: readStarted.complete,
        onCancel: () {
          cancelStarted.complete();
          return ioExited.future;
        },
      );
      final probe = _ProbeFile(source.stream);
      file = probe;
      final fake = _ManualTransport((_, request, cancellation) async {
        final reader = StreamIterator(request!);
        cancellation?.then((_) => reader.cancel());
        try {
          while (await reader.moveNext()) {}
        } finally {
          await reader.cancel();
        }
        return ResponseBody.fromString(_catboxLink, 200);
      });
      final token = CancelToken();
      var completed = false;
      final future =
          upload(
            CatboxAdapter(limits: _limits, transportFactory: () => fake),
            _target(ImageHostService.catbox),
            token: token,
          ).then((result) {
            completed = true;
            return result;
          });
      await readStarted.future;
      token.cancel();
      await cancelStarted.future;
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      ioExited.complete();
      expect(await future, isA<ProviderUploadCancelled>());
      expect(probe.opens, 1);
      unawaited(source.close());
    },
  );

  test('UT-055/102 cancellation waits for underlying fetch completion before IO release', () async {
    final started = Completer<void>();
    final actualExit = Completer<ResponseBody>();
    final fake = _FakeTransport((_) {
      started.complete();
      return actualExit.future;
    });
    final token = CancelToken();
    var completed = false;
    final future =
        upload(
          CatboxAdapter(limits: _limits, transportFactory: () => fake),
          _target(ImageHostService.catbox),
          token: token,
        ).then((value) {
          completed = true;
          return value;
        });
    await started.future;
    token.cancel(_key);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    actualExit.complete(ResponseBody.fromString(_catboxLink, 200));
    final result = await future as ProviderUploadCancelled;
    expect(result.evidence, UploadDeliveryEvidence.uncertain);
    expect(result.toString(), isNot(contains(_key)));
  });

  test(
    'UT-048/096 response over 64KiB is stopped at source without success',
    () async {
      final cancelled = Completer<void>();
      final source = StreamController<Uint8List>(onCancel: cancelled.complete);
      final fake = _FakeTransport((_) async {
        scheduleMicrotask(() {
          source.add(Uint8List(64 * 1024));
          source.add(Uint8List.fromList([1]));
        });
        return ResponseBody(source.stream, 200);
      });
      final result = await upload(
        CatboxAdapter(limits: _limits, transportFactory: () => fake),
        _target(ImageHostService.catbox),
      );
      expect(result, isA<ProviderUploadUnknown>());
      expect(cancelled.isCompleted, isTrue);
      unawaited(source.close());
    },
  );

  test(
    'UT-048/102 64KiB budget waits for delayed underlying response shutdown',
    () async {
      final cancelStarted = Completer<void>();
      final ioExited = Completer<void>();
      final source = StreamController<Uint8List>(
        onCancel: () {
          cancelStarted.complete();
          return ioExited.future;
        },
      );
      final fake = _FakeTransport((_) async {
        scheduleMicrotask(() => source.add(Uint8List(64 * 1024 + 1)));
        return ResponseBody(source.stream, 200);
      });
      var completed = false;
      final future =
          upload(
            CatboxAdapter(limits: _limits, transportFactory: () => fake),
            _target(ImageHostService.catbox),
          ).then((result) {
            completed = true;
            return result;
          });
      await cancelStarted.future;
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      ioExited.complete();
      expect(await future, isA<ProviderUploadUnknown>());
      unawaited(source.close());
    },
  );

  test('UT-055/102 response arriving after cancelled fetch still awaits source shutdown', () async {
    final fetchStarted = Completer<void>();
    final lateResponse = Completer<ResponseBody>();
    final cancelStarted = Completer<void>();
    final ioExited = Completer<void>();
    final source = StreamController<Uint8List>(
      onCancel: () {
        cancelStarted.complete();
        return ioExited.future;
      },
    );
    final fake = _FakeTransport((_) {
      fetchStarted.complete();
      return lateResponse.future;
    });
    final token = CancelToken();
    var completed = false;
    final future =
        upload(
          CatboxAdapter(limits: _limits, transportFactory: () => fake),
          _target(ImageHostService.catbox),
          token: token,
        ).then((result) {
          completed = true;
          return result;
        });
    await fetchStarted.future;
    token.cancel();
    await Future<void>.delayed(Duration.zero);
    lateResponse.complete(ResponseBody(source.stream, 200));
    await cancelStarted.future;
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    ioExited.complete();
    expect(await future, isA<ProviderUploadCancelled>());
    unawaited(source.close());
  });

  test(
    'UT-055/102 cancellation while response stalls closes source before return',
    () async {
      final started = Completer<void>();
      final cancelled = Completer<void>();
      final source = StreamController<Uint8List>(
        onListen: started.complete,
        onCancel: cancelled.complete,
      );
      final fake = _FakeTransport(
        (_) async => ResponseBody(source.stream, 200),
      );
      final token = CancelToken();
      final future = upload(
        CatboxAdapter(limits: _limits, transportFactory: () => fake),
        _target(ImageHostService.catbox),
        token: token,
      );
      await started.future;
      token.cancel();
      final result = await future;
      expect(result, isA<ProviderUploadCancelled>());
      expect(cancelled.isCompleted, isTrue);
      unawaited(source.close());
    },
  );

  test('UT-097 transport factory errors never escape as raw objects', () async {
    final result = await upload(
      CatboxAdapter(
        limits: _limits,
        transportFactory: () => throw _UnsafeFailure(),
      ),
      _target(ImageHostService.catbox),
    ) as ProviderUploadFailure;
    expect(result.evidence, UploadDeliveryEvidence.notSent);
    expect(result.toString(), isNot(contains(_key)));
  });

  test(
    'UT-097 close errors are fixed failures after actual transport settles',
    () async {
      final fake = _FakeTransport(
        (_) async => ResponseBody.fromString(_catboxLink, 200),
      )..failClose = true;
      await expectLater(
        upload(
          CatboxAdapter(limits: _limits, transportFactory: () => fake),
          _target(ImageHostService.catbox),
        ),
        throwsA(isA<ProviderCleanupException>()),
      );
      expect(fake.closes, 1);
      expect(
        const ProviderCleanupException().toString(),
        isNot(contains(_key)),
      );
    },
  );

  test('UT-058 progress reports actual transport bytes including multipart framing', () async {
    final activities = <UploadActivity>[];
    final fake = _FakeTransport(
      (_) async => ResponseBody.fromString(_catboxLink, 200),
    );
    expect(
      await upload(
        CatboxAdapter(limits: _limits, transportFactory: () => fake),
        _target(ImageHostService.catbox),
        activity: activities.add,
      ),
      isA<ProviderUploadSuccess>(),
    );
    final sent = activities
        .where((value) => value.direction == UploadActivityDirection.sending)
        .last;
    final received = activities
        .where((value) => value.direction == UploadActivityDirection.receiving)
        .last;
    expect(sent.bytes, fake.bodies.single.length);
    expect(sent.bytes, greaterThan(8));
    expect(received.bytes, utf8.encode(_catboxLink).length);
    expect(received.totalBytes, isNull);
  });

  test('UT-041 latest scope rejects anonymous targets before file or transport use', () async {
    final probe = _ProbeFile(const Stream.empty());
    file = probe;
    var factories = 0;
    for (final service in ImageHostService.values) {
      final ProviderAdapter adapter = service == ImageHostService.catbox
          ? CatboxAdapter(
              limits: _limits,
              transportFactory: () {
                factories++;
                throw StateError('must not create anonymous transport');
              },
            )
          : ImgBBAdapter(
              limits: _limits,
              transportFactory: () {
                factories++;
                throw StateError('must not create anonymous transport');
              },
            );
      for (final credential in [null, _key]) {
        final rejected = await upload(
          adapter,
          ResolvedTarget(_target(service, anonymous: true).target, credential),
        ) as ProviderUploadFailure;
        expect(rejected.kind, UploadFailureKind.authorization);
        expect(rejected.evidence, UploadDeliveryEvidence.notSent);
      }
    }
    expect(probe.checks, 0);
    expect(probe.opens, 0);
    expect(factories, 0);
  });

  test('UT-055/102 synchronous fetch failure settles without formatting untrusted exception', () async {
    final probe = _ProbeFile(const Stream.empty());
    file = probe;
    final fake = _ManualTransport((_, _, _) => throw _UnsafeFailure());
    final result = await upload(
      CatboxAdapter(limits: _limits, transportFactory: () => fake),
      _target(ImageHostService.catbox),
    ).timeout(const Duration(seconds: 3));
    expect(result, isA<ProviderUploadUnknown>());
    expect(probe.opens, 0);
    expect(result.toString(), isNot(contains(_key)));
  });

  test('UT-055/102 raw response failure waits for actual cleanup and hides exception', () async {
    final listening = Completer<void>();
    final cancelStarted = Completer<void>();
    final drained = Completer<void>();
    final source = StreamController<Uint8List>(
      onListen: listening.complete,
      onCancel: () {
        cancelStarted.complete();
        return drained.future;
      },
    );
    final fake = _ManualTransport(
      (_, _, _) async => ResponseBody(source.stream, 200),
    );
    var completed = false;
    final operation =
        upload(
          CatboxAdapter(limits: _limits, transportFactory: () => fake),
          _target(ImageHostService.catbox),
        ).then((value) {
          completed = true;
          return value;
        });
    try {
      await listening.future.timeout(const Duration(seconds: 3));
      source.addError(_UnsafeFailure());
      await cancelStarted.future.timeout(const Duration(seconds: 3));
      await Future<void>.delayed(Duration.zero);
      expect(completed, false);
      drained.complete();
      final result = await operation.timeout(const Duration(seconds: 3));
      expect(result, isA<ProviderUploadUnknown>());
      expect(result.toString(), isNot(contains(_key)));
    } finally {
      if (!drained.isCompleted) drained.complete();
      unawaited(source.close());
    }
  });

  test(
    'UT-055/102 response subscription failure refuses to claim safe cleanup',
    () async {
      final fake = _ManualTransport(
        (_, _, _) async => ResponseBody(_RefusingResponse(), 200),
      );
      await expectLater(
        upload(
          CatboxAdapter(limits: _limits, transportFactory: () => fake),
          _target(ImageHostService.catbox),
        ).timeout(const Duration(seconds: 3)),
        throwsA(isA<ProviderCleanupException>()),
      );
    },
  );
}
