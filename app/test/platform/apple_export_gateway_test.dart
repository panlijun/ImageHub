import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/processing/domain/export_models.dart';
import 'package:imagehost/platform/apple_export_gateway.dart';
import 'package:imagehost/platform/apple_resource_gateway.dart';
import 'package:imagehost/platform/backup_import_gateway.dart';
import 'package:imagehost/platform/export_gateway.dart';
import 'package:imagehost/platform/generated/apple_files.g.dart';

const _handle = '22222222-2222-4222-8222-222222222222';

void main() {
  test('UT-036 platform capabilities enable iOS native files and photos', () {
    for (final os in ['windows', 'macos', 'android', 'ios']) {
      final gateway = ExportGateway(operatingSystem: os);
      expect(gateway.supportsFileExport, true);
      expect(gateway.supportsPhotos, os == 'android' || os == 'ios');
      expect(gateway.supportsDirectoryExport, os == 'windows' || os == 'macos');
      expect(BackupImportGateway(operatingSystem: os).supportsPlatform, true);
    }
    expect(
      const ExportGateway(operatingSystem: 'linux').supportsFileExport,
      false,
    );
    expect(
      const BackupImportGateway(operatingSystem: 'linux').supportsPlatform,
      false,
    );
  });

  test('UT-073 platform file receipts retain Android content and accept only valid iOS file saves', () {
    ExportItemResult result(
      String uri, {
      String name = 'backup.zip',
      ExportStatus status = ExportStatus.saved,
    }) => ExportItemResult(
      id: 'owned',
      status: status,
      fileName: name,
      destinationUri: uri,
    );
    const android = ExportGateway(operatingSystem: 'android');
    const ios = ExportGateway(operatingSystem: 'ios');
    expect(
      android.confirmsSystemFileSave(result('content://documents/backup')),
      true,
    );
    expect(
      android.confirmsSystemFileSave(result('file:///selected/backup.zip')),
      false,
    );
    expect(
      ios.confirmsSystemFileSave(result('file:///selected/backup.zip')),
      true,
    );
    for (final uri in [
      'content://documents/backup',
      'file:backup.zip',
      'file:///selected/../backup.zip',
      'file:///selected/backup.zip?secret=value',
      'file:///selected/other.zip',
      'ph://asset/opaque',
    ]) {
      expect(ios.confirmsSystemFileSave(result(uri)), false, reason: uri);
    }
    expect(
      ios.confirmsSystemFileSave(
        result('file:///selected/backup.zip', status: ExportStatus.cancelled),
      ),
      false,
    );
    expect(
      ios.confirmsSystemFileSave(
        result('file:///selected/backup.zip', name: ''),
      ),
      false,
    );
  });

  test(
    'UT-036 Apple batch freezes IDs, forwards hashes and keeps selected order',
    () async {
      final host = _Host()
        ..replies.addAll([_saved('one (1).png'), _saved('two.png')]);
      final results = await AppleExportGateway(host: host)
          .export([_input('one'), _input('two')]);
      expect(results.map((result) => result.id), ['one', 'two']);
      expect(
        results.map((result) => result.status),
        everyElement(ExportStatus.saved),
      );
      expect(results.first.fileName, 'one (1).png');
      expect(
        host.requests.map((request) => request.operationId),
        host.operations,
      );
      expect(
        host.requests.map((request) => request.destinationHandle),
        everyElement(_handle),
      );
      expect(
        host.requests.map((request) => request.sha256),
        everyElement('a' * 64),
      );
      expect(
        host.requests.map((request) => request.byteCount),
        everyElement(3),
      );
      expect(
        host.requests.map((request) => request.mimeType),
        everyElement('image/png'),
      );
      expect(host.closed, [_handle]);
    },
  );

  test('UT-036 late confirmed save survives cancellation and stops remaining items', () async {
    final host = _Host();
    final reply = Completer<AppleExportReply>();
    host.replyPending = reply.future;
    final token = CancellationToken();
    var finished = false;
    final exporting = AppleExportGateway(host: host)
        .export([_input('one'), _input('two')], cancellation: token)
        .then((value) {
          finished = true;
          return value;
        });
    await _tick();
    token.cancel();
    await _tick();
    expect(finished, false);
    expect(host.cancelledOperations, [host.requests.single.operationId]);
    reply.complete(_saved('one.png'));
    final results = await exporting;
    expect(results.map((item) => item.status), [
      ExportStatus.saved,
      ExportStatus.cancelled,
    ]);
    expect(host.requests.length, 1);
    expect(host.closed, [_handle]);
  });

  test(
    'UT-036 actual scope retirement precedes releasing export ownership',
    () async {
      final host = _Host()..replies.add(_saved('one.png'));
      final retiring = Completer<void>();
      host.closePending = retiring.future;
      var finished = false;
      final pending = AppleExportGateway(host: host)
          .export([_input('one')])
          .then((value) {
            finished = true;
            return value;
          });
      await _tick();
      expect(host.closed, [_handle]);
      expect(finished, false);
      retiring.complete();
      expect((await pending).single.status, ExportStatus.saved);
    },
  );

  test(
    'UT-036 Photos confirmation and failed cleanup preserve saved evidence',
    () async {
      final host = _Host()
        ..replies.add(
          AppleExportReply(
            code: AppleIoCode.ok,
            cleanupPending: true,
            displayName: 'one.png',
            uri: 'ph://asset/ABC-DEF%2FL0%2F001',
          ),
        );
      final result = (await AppleExportGateway(
        host: host,
      ).export([_input('one')], photos: true)).single;
      expect(result.status, ExportStatus.saved);
      expect(result.reason, contains('暂存清理未确认'));
      expect(host.picks, 0);
      expect(host.requests.single.kind, AppleDestinationKind.photos);
      expect(host.closed, isEmpty);
    },
  );

  test('UT-036 malformed file or photo success never reports saved', () async {
    for (final uri in [
      'https://example.invalid/one.png',
      'content://provider/file/one.png',
      'file:one.png',
      'file:///target/two.png',
      'file:///target/one.png?secret=value',
      'file:///target/../one.png',
      'ph://asset/ABC-DEF%2FL0%2F001',
    ]) {
      final host = _Host()
        ..replies.add(
          AppleExportReply(
            code: AppleIoCode.ok,
            cleanupPending: false,
            displayName: 'one.png',
            uri: uri,
          ),
        );
      expect(
        (await AppleExportGateway(host: host).export([_input('one')]))
            .single
            .status,
        ExportStatus.failed,
      );
      expect(host.closed, [_handle]);
    }
    for (final uri in [
      'file:///target/one.png',
      'ph://asset/',
      'ph://wrong/id',
      'ph://asset/id?secret=value',
      'ph://asset/id/second',
      'ph://asset/a%0Ab',
    ]) {
      final host = _Host()
        ..replies.add(
          AppleExportReply(
            code: AppleIoCode.ok,
            cleanupPending: false,
            displayName: 'one.png',
            uri: uri,
          ),
        );
      expect(
        (await AppleExportGateway(
          host: host,
        ).export([_input('one')], photos: true)).single.status,
        ExportStatus.failed,
      );
    }
  });

  test(
    'UT-036 cancellation during picker drains and never starts native writes',
    () async {
      final host = _Host();
      final selection = Completer<AppleDestination>();
      final cancellation = Completer<void>();
      host.pickPending = selection.future;
      host.cancelSelectionPending = cancellation.future;
      final token = CancellationToken();
      var finished = false;
      final pending = AppleExportGateway(host: host)
          .export([_input('one')], cancellation: token)
          .then((value) {
            finished = true;
            return value;
          });
      await _tick();
      token.cancel();
      await _tick();
      expect(host.cancelledSelections, [host.selectionId]);
      selection.complete(AppleDestination(cancelled: false, handle: _handle));
      await _tick();
      expect(finished, false);
      expect(host.requests, isEmpty);
      cancellation.complete();
      expect((await pending).single.status, ExportStatus.cancelled);
      expect(host.closed, [_handle]);
    },
  );

  test('UT-036 scope cleanup failure cannot erase successful save', () async {
    final host = _Host()
      ..replies.add(_saved('one.png'))
      ..failClose = true;
    final result = (await AppleExportGateway(
      host: host,
    ).export([_input('one')])).single;
    expect(result.status, ExportStatus.saved);
    expect(result.reason, contains('授权收尾未确认'));
    expect(result.destinationUri, 'file:///target/one.png');
  });

  test(
    'UT-036 per-item failures and permission denial remain fixed feedback',
    () async {
      final host = _Host()
        ..replies.addAll([
          AppleExportReply(
            code: AppleIoCode.permissionDenied,
            cleanupPending: false,
          ),
          AppleExportReply(
            code: AppleIoCode.unconfirmed,
            cleanupPending: false,
          ),
        ]);
      final results = await AppleExportGateway(host: host)
          .export([_input('one'), _input('two')]);
      expect(results.first.failureKind, ExportFailureKind.permissionDenied);
      expect(results.last.reason, contains('现场保留'));
      expect(
        results.map((result) => result.status),
        everyElement(ExportStatus.failed),
      );
      final bad = _Host()
        ..pickError = PlatformException(
          code: 'unavailable',
          message: 'RAW_PRIVATE_SECRET',
        );
      final failed = await AppleExportGateway(host: bad)
          .export([_input('one')]);
      expect(failed.single.reason, isNot(contains('RAW_PRIVATE_SECRET')));
    },
  );

  test(
    'UT-036 duplicate input identities do not acquire a directory',
    () async {
      final host = _Host();
      final result = await AppleExportGateway(host: host)
          .export([_input('one'), _input('one')]);
      expect(
        result.map((item) => item.status),
        everyElement(ExportStatus.failed),
      );
      expect(host.picks, 0);
      expect(host.requests, isEmpty);
    },
  );
}

ExportInput _input(String id) => ExportInput(
  id: id,
  source: File('private/$id.png'),
  displayName: '$id.png',
  expectedSha256: 'a' * 64,
  expectedByteCount: 3,
);
AppleExportReply _saved(String name) => AppleExportReply(
  code: AppleIoCode.ok,
  cleanupPending: false,
  displayName: name,
  uri: Uri.file('/target/$name', windows: false).toString(),
);
Future<void> _tick() => Future<void>.delayed(Duration.zero);

class _Host extends AppleFileHost {
  final replies = <AppleExportReply>[];
  final requests = <AppleExportRequest>[];
  final closed = <String>[];
  final cancelledOperations = <String>[];
  final cancelledSelections = <String>[];
  List<String> operations = [];
  String? selectionId;
  int picks = 0;
  bool failClose = false;
  Future<AppleExportReply>? replyPending;
  Future<AppleDestination>? pickPending;
  Future<void>? closePending;
  Future<void>? cancelSelectionPending;
  PlatformException? pickError;

  @override
  Future<AppleDestination> pickDirectory(
    String selectionId,
    List<String> operationIds,
  ) async {
    picks++;
    this.selectionId = selectionId;
    operations = List.of(operationIds);
    expect(appleHandlePattern.hasMatch(selectionId), true);
    expect(operationIds.toSet().length, operationIds.length);
    expect(operationIds.every(appleHandlePattern.hasMatch), true);
    if (pickError != null) throw pickError!;
    return pickPending ?? AppleDestination(cancelled: false, handle: _handle);
  }

  @override
  Future<AppleExportReply> exportFile(AppleExportRequest request) async {
    requests.add(request);
    return replyPending ?? replies.removeAt(0);
  }

  @override
  Future<void> closeDestination(String handle) async {
    closed.add(handle);
    if (failClose) throw PlatformException(code: 'cleanupPending');
    await closePending;
  }

  @override
  Future<void> cancelExport(String operationId) async {
    cancelledOperations.add(operationId);
  }

  @override
  Future<void> cancelSelection(String selectionId) async {
    cancelledSelections.add(selectionId);
    await cancelSelectionPending;
  }
}
