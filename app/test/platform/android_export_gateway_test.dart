import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/processing/domain/export_models.dart';
import 'package:imagehost/platform/android_export_gateway.dart';
import 'package:imagehost/platform/generated/android_files.g.dart';

const _handle = 'bdfaa907-b209-4fd7-8a9b-1dc536402485';
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

// No fake Host result is evidence that SAF or MediaStore works on a device.
void main() {
  test('UT-036 Android single document transports frozen source digest length and actual URI', () async {
    final host = _ExportHost();
    final input = _input('one', 'image.png');
    host.export = (_) async =>
        _saved('content://documents/document/new', 'image (1).png');
    final results = await AndroidExportGateway(host: host).export([input]);
    expect(host.created, [
      ['image.png', 'image/png'],
    ]);
    expect(host.directorySelections, isEmpty);
    final request = host.requests.single;
    expect(_uuid.hasMatch(request.operationId), isTrue);
    expect(request.kind, AndroidDestinationKind.document);
    expect(request.destinationHandle, _handle);
    expect(request.sourcePath, input.source.absolute.path);
    expect(request.sha256, input.expectedSha256);
    expect(request.byteCount, input.expectedByteCount);
    expect(results.single.status, ExportStatus.saved);
    expect(results.single.destinationUri, 'content://documents/document/new');
    expect(results.single.fileName, 'image (1).png');
    expect(results.single.destinationPath, isNull);
    expect(host.closed, [_handle]);
  });

  test('UT-036 Android batch chooses one tree with exact preallocated unique operations and continues failures', () async {
    final host = _ExportHost();
    final inputs = [
      _input('one', 'first.png'),
      _input('two', 'second.jpg'),
      _input('three', 'third.webp'),
    ];
    host.export = (request) async => request.displayName == 'second.jpg'
        ? AndroidExportReply(code: AndroidIoCode.permissionDenied)
        : _saved(
            'content://documents/document/${request.operationId}',
            request.displayName,
          );
    final results = await AndroidExportGateway(host: host).export(inputs);
    expect(host.created, isEmpty);
    expect(host.directorySelections, hasLength(1));
    final frozenIds = host.directorySelections.single;
    expect(frozenIds, hasLength(3));
    expect(frozenIds.toSet(), hasLength(3));
    expect(frozenIds.every(_uuid.hasMatch), isTrue);
    expect(host.requests.map((request) => request.operationId), frozenIds);
    expect(
      host.requests.every(
        (request) =>
            request.destinationHandle == _handle &&
            request.kind == AndroidDestinationKind.tree,
      ),
      isTrue,
    );
    expect(results.map((result) => result.status), [
      ExportStatus.saved,
      ExportStatus.failed,
      ExportStatus.saved,
    ]);
    expect(results[1].failureKind, ExportFailureKind.permissionDenied);
    expect(host.closed, [_handle]);
  });

  test('UT-036 Android photos bypasses selectors and sends no document URI or handle', () async {
    final host = _ExportHost();
    final results = await AndroidExportGateway(host: host)
        .export([_input('one', 'image.webp')], photos: true);
    expect(results.single.status, ExportStatus.saved);
    expect(host.created, isEmpty);
    expect(host.directorySelections, isEmpty);
    expect(host.closed, isEmpty);
    expect(host.requests.single.destinationHandle, isNull);
    expect(host.requests.single.kind, AndroidDestinationKind.photos);
    expect(host.requests.single.mimeType, 'image/webp');
  });

  test('UT-036 Android selector cancellation starts no writer while invalid cancelled handle is closed', () async {
    for (final handle in [null, _handle]) {
      final host = _ExportHost()
        ..destination = AndroidDestination(cancelled: true, handle: handle);
      final results = await AndroidExportGateway(host: host)
          .export([_input('one')]);
      expect(
        results.single.status,
        handle == null ? ExportStatus.cancelled : ExportStatus.failed,
      );
      expect(host.requests, isEmpty);
      expect(host.closed, handle == null ? <String>[] : [_handle]);
    }
  });

  test(
    'UT-036 Android invalid future destination handles never reach exportFile',
    () async {
      for (final handle in [
        null,
        '',
        '-' * 36,
        '00000000-0000-0000-0000-000000000000',
        'content://other/document/existing',
      ]) {
        final host = _ExportHost()
          ..destination = AndroidDestination(cancelled: false, handle: handle);
        final results = await AndroidExportGateway(host: host)
            .export([_input('one')]);
        expect(results.single.status, ExportStatus.failed);
        expect(host.requests, isEmpty);
      }
    },
  );

  test('UT-036 Android successful reply requires real content authority and nonempty actual name', () async {
    final replies = [
      _saved('/other/app/file.png', 'file.png'),
      _saved('file:///other/app/file.png', 'file.png'),
      _saved('https://example.invalid/file.png', 'file.png'),
      _saved('content:///document/file', 'file.png'),
      _saved('', 'file.png'),
      _saved('content://documents/document/file', ''),
      AndroidExportReply(
        code: AndroidIoCode.ok,
        uri: 'content://documents/document/file',
      ),
      AndroidExportReply(code: AndroidIoCode.ok, displayName: 'file.png'),
    ];
    for (final reply in replies) {
      final host = _ExportHost()..export = (_) async => reply;
      final result = (await AndroidExportGateway(
        host: host,
      ).export([_input('one')])).single;
      expect(result.status, ExportStatus.failed);
      expect(result.destinationPath, isNull);
      expect(result.destinationUri, isNull);
      expect(host.requests.single.destinationHandle, _handle);
      expect(host.closed, [_handle]);
    }
  });

  test('UT-036 Android every unconfirmed native status remains failed and the next item proceeds', () async {
    for (final code in AndroidIoCode.values.where(
      (value) => value != AndroidIoCode.ok && value != AndroidIoCode.cancelled,
    )) {
      final host = _ExportHost();
      host.export = (request) async => request.displayName == 'first.png'
          ? AndroidExportReply(code: code)
          : _saved('content://media/external/images/2', 'second.png');
      final results = await AndroidExportGateway(host: host)
          .export([_input('one', 'first.png'), _input('two', 'second.png')]);
      expect(results.map((result) => result.status), [
        ExportStatus.failed,
        ExportStatus.saved,
      ]);
      expect(results.first.reason, isNotEmpty);
      expect(host.requests, hasLength(2));
    }
  });

  test('UT-036 Android cancellation waits for actual export cancel request and destination close', () async {
    final host = _ExportHost();
    final actualExport = Completer<AndroidExportReply>();
    final cancelAcknowledged = Completer<void>();
    final actualClose = Completer<void>();
    final started = Completer<void>();
    host.export = (_) {
      started.complete();
      return actualExport.future;
    };
    host.cancel = (_) => cancelAcknowledged.future;
    host.close = (_) => actualClose.future;
    final token = CancellationToken();
    var finished = false;
    final operation = AndroidExportGateway(host: host)
        .export([_input('one')], cancellation: token);
    operation.then((_) {
      finished = true;
    });
    await started.future;
    token.cancel();
    await _settle();
    expect(host.cancelled, [host.requests.single.operationId]);
    expect(finished, isFalse);
    expect(host.closed, isEmpty);
    cancelAcknowledged.complete();
    await _settle();
    expect(
      finished,
      isFalse,
      reason: 'Acknowledging cancellation does not finish export IO.',
    );
    actualExport.complete(AndroidExportReply(code: AndroidIoCode.cancelled));
    await _settle();
    expect(host.closed, [_handle]);
    expect(finished, isFalse);
    actualClose.complete();
    expect((await operation).single.status, ExportStatus.cancelled);
  });

  test('UT-036 Android late confirmed save survives cancellation and later frozen items stay unexecuted', () async {
    final host = _ExportHost();
    final actualExport = Completer<AndroidExportReply>();
    final started = Completer<void>();
    host.export = (_) {
      started.complete();
      return actualExport.future;
    };
    final token = CancellationToken();
    final operation = AndroidExportGateway(host: host)
        .export([_input('one'), _input('two')], cancellation: token);
    await started.future;
    token.cancel();
    actualExport.complete(
      _saved('content://documents/document/first', 'first.png'),
    );
    final results = await operation;
    expect(results.map((result) => result.status), [
      ExportStatus.saved,
      ExportStatus.cancelled,
    ]);
    expect(results.first.destinationUri, 'content://documents/document/first');
    expect(host.requests, hasLength(1));
    expect(host.directorySelections.single, hasLength(2));
    expect(host.closed, [_handle]);
  });

  test('UT-036 Android late selector result after stop releases destination without export', () async {
    final host = _ExportHost();
    final selected = Completer<AndroidDestination>();
    final started = Completer<void>();
    host.select = () {
      started.complete();
      return selected.future;
    };
    final token = CancellationToken();
    var finished = false;
    final operation = AndroidExportGateway(host: host)
        .export([_input('one')], cancellation: token);
    operation.then((_) {
      finished = true;
    });
    await started.future;
    token.cancel();
    await _settle();
    expect(finished, isFalse);
    selected.complete(AndroidDestination(cancelled: false, handle: _handle));
    expect((await operation).single.status, ExportStatus.cancelled);
    expect(host.requests, isEmpty);
    expect(host.closed, [_handle]);
  });

  test('UT-036 Android cleanup failure gives fixed feedback without downgrading saved result', () async {
    final host = _ExportHost();
    final unsafe = _UnsafeFailure();
    host.close = (_) async => throw unsafe;
    final result = (await AndroidExportGateway(
      host: host,
    ).export([_input('one')])).single;
    expect(result.status, ExportStatus.saved);
    expect(result.destinationUri, 'content://media/external/images/1');
    expect(result.reason, contains('清理未确认'));
    expect(result.reason, isNot(contains('unsafe-native-path-secret')));
    expect(unsafe.toStringCalls, 0);
  });

  test('UT-036 Android opaque host failures do not stringify and other frozen items still export', () async {
    final host = _ExportHost();
    final unsafe = _UnsafeFailure();
    host.export = (request) async {
      if (request.displayName == 'first.png') throw unsafe;
      return _saved('content://documents/document/second', 'second.png');
    };
    final results = await AndroidExportGateway(host: host)
        .export([_input('one', 'first.png'), _input('two', 'second.png')]);
    expect(results.map((result) => result.status), [
      ExportStatus.failed,
      ExportStatus.saved,
    ]);
    expect(results.first.reason, isNot(contains('unsafe-native-path-secret')));
    expect(unsafe.toStringCalls, 0);
  });

  test('UT-036 Android opaque selector failure creates no writer and never stringifies', () async {
    final host = _ExportHost();
    final unsafe = _UnsafeFailure();
    host.select = () async => throw unsafe;
    final result = (await AndroidExportGateway(
      host: host,
    ).export([_input('one')])).single;
    expect(result.status, ExportStatus.failed);
    expect(result.reason, isNot(contains('unsafe-native-path-secret')));
    expect(unsafe.toStringCalls, 0);
    expect(host.requests, isEmpty);
    expect(host.closed, isEmpty);
  });

  test('UT-036 Android cancellation acknowledgement failure cannot replace a late saved result', () async {
    final host = _ExportHost();
    final actualExport = Completer<AndroidExportReply>();
    final started = Completer<void>();
    final unsafe = _UnsafeFailure();
    host.export = (_) {
      started.complete();
      return actualExport.future;
    };
    host.cancel = (_) async => throw unsafe;
    final token = CancellationToken();
    final operation = AndroidExportGateway(host: host)
        .export([_input('one')], cancellation: token);
    await started.future;
    token.cancel();
    await _settle();
    actualExport.complete(
      _saved('content://documents/document/completed', 'completed.png'),
    );
    final result = (await operation).single;
    expect(result.status, ExportStatus.saved);
    expect(result.destinationUri, 'content://documents/document/completed');
    expect(host.closed, [_handle]);
    expect(unsafe.toStringCalls, 0);
  });

  test('UT-036 Android cancelled or empty batch never chooses a destination or writes', () async {
    final host = _ExportHost();
    final gateway = AndroidExportGateway(host: host);
    expect(await gateway.export([]), isEmpty);
    final token = CancellationToken()..cancel();
    expect(
      (await gateway.export([
        _input('one'),
      ], cancellation: token)).single.status,
      ExportStatus.cancelled,
    );
    expect(host.created, isEmpty);
    expect(host.directorySelections, isEmpty);
    expect(host.requests, isEmpty);
    expect(host.closed, isEmpty);
  });

  test('UT-036 Android caller list changes after selector starts cannot change frozen inputs', () async {
    final host = _ExportHost();
    final selected = Completer<AndroidDestination>();
    final started = Completer<void>();
    host.select = () {
      started.complete();
      return selected.future;
    };
    final inputs = [_input('one'), _input('two')];
    final operation = AndroidExportGateway(host: host).export(inputs);
    await started.future;
    inputs.clear();
    selected.complete(AndroidDestination(cancelled: false, handle: _handle));
    expect((await operation).map((result) => result.id), ['one', 'two']);
    expect(host.requests, hasLength(2));
    expect(host.directorySelections.single, hasLength(2));
  });

  test('UT-036 Android MIME mapping is deterministic for images backup and diagnostic files', () {
    for (final entry in <String, String>{
      'a.JPG': 'image/jpeg',
      'a.jpeg': 'image/jpeg',
      'a.png': 'image/png',
      'a.webp': 'image/webp',
      'a.gif': 'image/gif',
      'a.bmp': 'image/bmp',
      'a.zip': 'application/zip',
      'a.json': 'application/json',
      'a.unknown': 'application/octet-stream',
    }.entries) {
      expect(AndroidExportGateway.mime(entry.key), entry.value);
    }
  });
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

ExportInput _input(String id, [String name = 'image.png']) => ExportInput(
  id: id,
  source: File('private-source-$id.bin'),
  displayName: name,
  expectedSha256: 'a' * 64,
  expectedByteCount: 23,
);
AndroidExportReply _saved(String uri, String name) =>
    AndroidExportReply(code: AndroidIoCode.ok, uri: uri, displayName: name);

class _UnsafeFailure implements Exception {
  int toStringCalls = 0;
  @override
  String toString() {
    toStringCalls++;
    return 'unsafe-native-path-secret';
  }
}

class _ExportHost extends AndroidExportHost {
  AndroidDestination destination = AndroidDestination(
    cancelled: false,
    handle: _handle,
  );
  Future<AndroidDestination> Function()? select;
  Future<AndroidExportReply> Function(AndroidExportRequest request)? export;
  Future<void> Function(String id)? cancel;
  Future<void> Function(String handle)? close;
  final created = <List<String>>[];
  final directorySelections = <List<String>>[];
  final requests = <AndroidExportRequest>[];
  final cancelled = <String>[];
  final closed = <String>[];
  @override
  Future<AndroidDestination> createDocument(
    String displayName,
    String mimeType,
  ) async {
    created.add([displayName, mimeType]);
    return await (select?.call() ?? Future.value(destination));
  }

  @override
  Future<AndroidDestination> pickDirectory(List<String> operationIds) async {
    directorySelections.add(List.unmodifiable(operationIds));
    return await (select?.call() ?? Future.value(destination));
  }

  @override
  Future<AndroidExportReply> exportFile(AndroidExportRequest request) {
    requests.add(request);
    return export?.call(request) ??
        Future.value(
          _saved('content://media/external/images/1', request.displayName),
        );
  }

  @override
  Future<void> cancelExport(String operationId) async {
    cancelled.add(operationId);
    await cancel?.call(operationId);
  }

  @override
  Future<void> closeDestination(String handle) async {
    closed.add(handle);
    await close?.call(handle);
  }
}
