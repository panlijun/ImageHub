import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/platform/apple_resource_gateway.dart';
import 'package:imagehost/platform/generated/apple_files.g.dart';

const _handle = '11111111-1111-4111-8111-111111111111';

void main() {
  test(
    'UT-075 Apple backup bounded reads consume one source and retire once',
    () async {
      final host = _Host();
      host.chunks.addAll([
        AppleReadReply(
          code: AppleIoCode.ok,
          bytes: Uint8List(64 * 1024),
          eof: false,
        ),
        AppleReadReply(
          code: AppleIoCode.ok,
          bytes: Uint8List.fromList([3, 4]),
          eof: true,
        ),
      ]);
      final resource = (await AppleResourceGateway(
        host: host,
      ).pickBackup()).single;
      expect(resource.sourceType, 'backup');
      final bytes = await resource.read().expand((chunk) => chunk).toList();
      expect(bytes.length, 64 * 1024 + 2);
      expect(bytes.sublist(bytes.length - 2), [3, 4]);
      await resource.release!();
      expect(host.closed, [_handle]);
      expect(host.reads, 2);
      await expectLater(
        resource.read().drain<void>(),
        throwsA(isA<ResourceFailure>()),
      );
      expect(host.reads, 2);
    },
  );

  test(
    'UT-075 malformed Apple selection retires only known unique handles',
    () async {
      for (final selection in [
        AppleSelection(cancelled: true, resources: [_picked()]),
        AppleSelection(cancelled: false, resources: [_picked(), _picked()]),
        AppleSelection(
          cancelled: false,
          resources: [
            ApplePickedResource(handle: _handle, displayName: 'bad\n.zip'),
          ],
        ),
        AppleSelection(
          cancelled: false,
          resources: [
            ApplePickedResource(
              handle: '/external/file',
              displayName: 'ok.zip',
            ),
          ],
        ),
        AppleSelection(cancelled: false, resources: []),
      ]) {
        final host = _Host()..selection = selection;
        await expectLater(
          AppleResourceGateway(host: host).pickBackup(),
          throwsA(isA<ResourceFailure>()),
        );
        expect(
          host.closed,
          selection.resources.any((item) => item.handle == _handle)
              ? [_handle]
              : isEmpty,
        );
        expect(host.reads, 0);
      }
    },
  );

  test(
    'UT-075 cancellation before picker does not start acquisition',
    () async {
      final host = _Host();
      final token = CancellationToken()..cancel();
      await expectLater(
        AppleResourceGateway(host: host).pickBackup(cancellation: token),
        _failure(FailureKind.cancelled),
      );
      expect(host.picks, 0);
      expect(host.cancelledSelections, isEmpty);
    },
  );

  test(
    'UT-075 selector cancellation waits both callbacks for the same UUID',
    () async {
      final host = _Host();
      final picked = Completer<AppleSelection>();
      final retired = Completer<void>();
      host.pickPending = picked.future;
      host.cancelPending = retired.future;
      final token = CancellationToken();
      var finished = false;
      final result = AppleResourceGateway(host: host)
          .pickBackup(cancellation: token)
          .then((value) {
            finished = true;
            return value;
          });
      await _tick();
      token.cancel();
      await _tick();
      expect(host.cancelledSelections, [host.selectionId]);
      picked.complete(AppleSelection(cancelled: true, resources: []));
      await _tick();
      expect(finished, false);
      retired.complete();
      await expectLater(result, _failure(FailureKind.cancelled));
      expect(host.reads, 0);
    },
  );

  test(
    'UT-075 late selected scope after cancellation retires before return',
    () async {
      final host = _Host();
      final picked = Completer<AppleSelection>();
      final closed = Completer<void>();
      host.pickPending = picked.future;
      host.closePending = closed.future;
      final token = CancellationToken();
      final result = AppleResourceGateway(host: host)
          .pickBackup(cancellation: token);
      final rejected = expectLater(result, _failure(FailureKind.cancelled));
      await _tick();
      token.cancel();
      picked.complete(AppleSelection(cancelled: false, resources: [_picked()]));
      await _tick();
      expect(host.closed, [_handle]);
      expect(host.reads, 0);
      closed.complete();
      await rejected;
    },
  );

  test(
    'UT-075 cancelled read still waits actual read even when scope close fails',
    () async {
      final host = _Host();
      final read = Completer<AppleReadReply>();
      host.readPending = read.future;
      host.failClose = true;
      final resource = (await AppleResourceGateway(
        host: host,
      ).pickBackup()).single;
      final token = CancellationToken();
      var finished = false;
      final consuming = resource.read(cancellation: token).drain<void>();
      final check = expectLater(
        consuming,
        _failure(FailureKind.storage),
      ).then((_) => finished = true);
      await _tick();
      token.cancel();
      await _tick();
      expect(finished, false);
      read.complete(
        AppleReadReply(
          code: AppleIoCode.ok,
          bytes: Uint8List.fromList([1]),
          eof: true,
        ),
      );
      await check;
      expect(host.reads, 1);
      expect(host.closed, isNotEmpty);
    },
  );

  test(
    'UT-075 nonempty malformed chunks and native failures never pass bytes',
    () async {
      for (final reply in [
        AppleReadReply(
          code: AppleIoCode.ok,
          bytes: Uint8List(64 * 1024 + 1),
          eof: true,
        ),
        AppleReadReply(code: AppleIoCode.ok, bytes: Uint8List(0), eof: false),
        AppleReadReply(
          code: AppleIoCode.cloudPending,
          bytes: Uint8List(0),
          eof: true,
        ),
        AppleReadReply(
          code: AppleIoCode.inputChanged,
          bytes: Uint8List(0),
          eof: true,
        ),
      ]) {
        final host = _Host()..chunks.add(reply);
        final resource = (await AppleResourceGateway(
          host: host,
        ).pickBackup()).single;
        await expectLater(
          resource.read().drain<void>(),
          throwsA(isA<ResourceFailure>()),
        );
        expect(host.closed, [_handle]);
      }
    },
  );

  test(
    'UT-089 Apple exception mapping ignores raw message and details',
    () async {
      final host = _Host()
        ..pickError = PlatformException(
          code: 'permissionDenied',
          message: 'PRIVATE_SOURCE_SECRET',
          details: '/external/private/path',
        );
      await expectLater(
        AppleResourceGateway(host: host).pickBackup(),
        _failure(FailureKind.permissionDenied),
      );
      expect(
        appleResourceFailure('permissionDenied').message,
        isNot(contains('PRIVATE_SOURCE_SECRET')),
      );
    },
  );
}

Matcher _failure(FailureKind kind) =>
    throwsA(isA<ResourceFailure>().having((error) => error.kind, 'kind', kind));
Future<void> _tick() => Future<void>.delayed(Duration.zero);
ApplePickedResource _picked() =>
    ApplePickedResource(handle: _handle, displayName: 'selected.zip');

class _Host extends AppleFileHost {
  AppleSelection selection = AppleSelection(
    cancelled: false,
    resources: [_picked()],
  );
  final chunks = <AppleReadReply>[];
  final closed = <String>[];
  final cancelledSelections = <String>[];
  Future<AppleSelection>? pickPending;
  Future<AppleReadReply>? readPending;
  Future<void>? closePending;
  Future<void>? cancelPending;
  PlatformException? pickError;
  bool failClose = false;
  int picks = 0;
  int reads = 0;
  String? selectionId;

  @override
  Future<AppleSelection> pickBackup(String selectionId) async {
    picks++;
    this.selectionId = selectionId;
    expect(appleHandlePattern.hasMatch(selectionId), true);
    if (pickError != null) throw pickError!;
    return pickPending ?? selection;
  }

  @override
  Future<AppleReadReply> readResource(String handle) async {
    expect(handle, _handle);
    reads++;
    return readPending ?? chunks.removeAt(0);
  }

  @override
  Future<void> closeResource(String handle) async {
    closed.add(handle);
    if (failClose) throw PlatformException(code: 'storage');
    await closePending;
  }

  @override
  Future<void> cancelSelection(String selectionId) async {
    cancelledSelections.add(selectionId);
    await cancelPending;
  }
}
