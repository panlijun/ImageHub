import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/platform/android_resource_gateway.dart';
import 'package:imagehost/platform/generated/android_files.g.dart';

const _first = 'bdfaa907-b209-4fd7-8a9b-1dc536402485';
const _second = '4dcbe5a0-76d8-448a-bd23-e727a84ecf7c';

// These tests exercise Dart with controlled Host futures, not an Android provider.
void main() {
  test(
    'UT-010 Android bounded chunks preserve unknown source size and EOF closes',
    () async {
      final host = _ResourceHost()..selection = _selection([_first]);
      host.read = (_, index) async => _reply(
        index == 0 ? List.filled(64 * 1024, 7) : [8, 9],
        eof: index == 1,
      );
      final resource = (await AndroidResourceGateway(host: host).pick()).single;
      final chunks = await resource.read().toList();
      expect(chunks.map((chunk) => chunk.length), [64 * 1024, 2]);
      expect(chunks.last, [8, 9]);
      expect(host.closed, [_first]);
      expect(host.readCalls[_first], 2);
      await resource.release!();
      expect(host.closed, [_first]);
    },
  );

  test('UT-010 Android one source failure does not prevent a second selected source', () async {
    final host = _ResourceHost()..selection = _selection([_first, _second]);
    host.read = (handle, _) async => handle == _first
        ? _reply([], code: AndroidIoCode.cloudPending, eof: true)
        : _reply([42], eof: true);
    final resources = await AndroidResourceGateway(host: host)
        .pick(photos: true);
    await expectLater(
      resources.first.read().drain<void>(),
      throwsA(_failure(FailureKind.cloudPending)),
    );
    expect(await resources.last.read().toList(), [
      [42],
    ]);
    expect(host.closed, [_first, _second]);
    expect(host.selectedFlags, [true, false]);
  });

  test(
    'UT-010 Android rejects oversize empty non-EOF and unexpected read status',
    () async {
      for (final reply in [
        _reply(List.filled(64 * 1024 + 1, 1), eof: true),
        _reply([], eof: false),
        _reply([], code: AndroidIoCode.ok, eof: false),
        _reply([], code: AndroidIoCode.unconfirmed, eof: true),
        _reply([], code: AndroidIoCode.inputChanged, eof: true),
      ]) {
        final host = _ResourceHost()..selection = _selection([_first]);
        host.read = (_, _) async => reply;
        final resource = (await AndroidResourceGateway(
          host: host,
        ).pick()).single;
        await expectLater(
          resource.read().drain<void>(),
          throwsA(_failure(FailureKind.unavailable)),
        );
        expect(host.closed, [_first]);
      }
    },
  );

  test('UT-010 Android typed native read failures keep their fixed classifications', () async {
    final cases = <AndroidIoCode, FailureKind>{
      AndroidIoCode.cancelled: FailureKind.cancelled,
      AndroidIoCode.permissionDenied: FailureKind.permissionDenied,
      AndroidIoCode.sourceMissing: FailureKind.sourceMissing,
      AndroidIoCode.unsupported: FailureKind.unsupported,
      AndroidIoCode.storage: FailureKind.storage,
      AndroidIoCode.cleanupPending: FailureKind.storage,
    };
    for (final entry in cases.entries) {
      final host = _ResourceHost()..selection = _selection([_first]);
      host.read = (_, _) async => _reply([], code: entry.key, eof: true);
      final resource = (await AndroidResourceGateway(host: host).pick()).single;
      await expectLater(
        resource.read().drain<void>(),
        throwsA(_failure(entry.value)),
      );
      expect(host.closed, [_first]);
    }
  });

  test(
    'UT-010 Android cancellation waits for both pending read and actual close',
    () async {
      final host = _ResourceHost()..selection = _selection([_first]);
      final reading = Completer<AndroidReadReply>();
      final closing = Completer<void>();
      final started = Completer<void>();
      host.read = (_, _) {
        started.complete();
        return reading.future;
      };
      host.close = (_) => closing.future;
      final resource = (await AndroidResourceGateway(host: host).pick()).single;
      final token = CancellationToken();
      var finished = false;
      final operation = resource.read(cancellation: token).drain<void>();
      final checked = expectLater(
        operation,
        throwsA(_failure(FailureKind.cancelled)),
      );
      final observed = operation.then(
        (_) {
          finished = true;
        },
        onError: (Object _) {
          finished = true;
        },
      );
      await started.future;
      token.cancel();
      await _settle();
      expect(host.closed, [_first]);
      expect(finished, isFalse);
      closing.complete();
      await _settle();
      expect(
        finished,
        isFalse,
        reason: 'A completed close is not a completed pending read.',
      );
      reading.complete(_reply([99], eof: true));
      await checked;
      await observed;
      expect(finished, isTrue);
    },
  );

  test('UT-010 Android cancellation with failing close still drains the pending read', () async {
    final host = _ResourceHost()..selection = _selection([_first]);
    final reading = Completer<AndroidReadReply>();
    final started = Completer<void>();
    var closeAttempts = 0;
    host.read = (_, _) {
      started.complete();
      return reading.future;
    };
    host.close = (_) async {
      if (closeAttempts++ == 0) throw _UnsafeFailure();
    };
    final resource = (await AndroidResourceGateway(host: host).pick()).single;
    final token = CancellationToken();
    var finished = false;
    final operation = resource.read(cancellation: token).drain<void>();
    final captured = operation.then<Object?>(
      (_) => null,
      onError: (Object error) => error,
    );
    captured.then((_) {
      finished = true;
    });
    await started.future;
    token.cancel();
    await _settle();
    final premature = finished;
    // Always settle the fake IO, including when the regression assertion fails.
    reading.complete(_reply([], eof: true));
    final error = await captured;
    expect(
      premature,
      isFalse,
      reason: 'A close error must not abandon actual source reading.',
    );
    expect(error is ResourceFailure, isTrue);
    expect((error as ResourceFailure).kind, FailureKind.storage);
  });

  test('UT-010 Android unopened resources release once and retired resource cannot reopen', () async {
    final host = _ResourceHost()..selection = _selection([_first, _second]);
    final resources = await AndroidResourceGateway(host: host)
        .pick(backup: true);
    await Future.wait(resources.map((resource) => resource.release!()));
    await resources.first.release!();
    expect(host.closed, [_first, _second]);
    expect(host.readCalls, isEmpty);
    await expectLater(
      resources.first.read().drain<void>(),
      throwsA(_failure(FailureKind.sourceMissing)),
    );
    expect(host.selectedFlags, [false, true]);
  });

  test('UT-010 Android late selector return can be released without opening cancelled sources', () async {
    final host = _ResourceHost();
    final selection = Completer<AndroidSelection>();
    host.pick = () => selection.future;
    final token = CancellationToken();
    final picking = AndroidResourceGateway(host: host).pick();
    token.cancel();
    selection.complete(_selection([_first, _second]));
    final resources = await picking;
    if (token.isCancelled) {
      await Future.wait(resources.map((resource) => resource.release!()));
    }
    expect(host.closed, [_first, _second]);
    expect(host.readCalls, isEmpty);
  });

  test('UT-010 Android malformed handles duplicates and future source kinds fail closed', () async {
    for (final selected in [
      [_picked('-' * 36)],
      [_picked('00000000-0000-0000-0000-000000000000')],
      [_picked(_first), _picked(_first)],
      [
        AndroidPickedResource(
          handle: _first,
          displayName: 'a.png',
          sourceType: 'future',
        ),
      ],
      [
        AndroidPickedResource(
          handle: _first,
          displayName: '',
          sourceType: 'file',
        ),
      ],
      [
        AndroidPickedResource(
          handle: _first,
          displayName: 'a' * 513,
          sourceType: 'file',
        ),
      ],
    ]) {
      final host = _ResourceHost()
        ..selection = AndroidSelection(cancelled: false, resources: selected);
      final captured = await AndroidResourceGateway(host: host)
          .pick()
          .then<Object?>((_) => null, onError: (Object error) => error);
      expect(captured is ResourceFailure, isTrue);
      expect(host.readCalls, isEmpty);
    }
  });

  test('UT-010 Android invalid later selection releases every valid granted handle', () async {
    final host = _ResourceHost()
      ..selection = AndroidSelection(
        cancelled: false,
        resources: [
          _picked(_first),
          AndroidPickedResource(
            handle: _second,
            displayName: 'b.png',
            sourceType: 'future',
          ),
        ],
      );
    final captured = await AndroidResourceGateway(host: host)
        .pick()
        .then<Object?>((_) => null, onError: (Object error) => error);
    await _settle();
    expect(captured is ResourceFailure, isTrue);
    expect(host.closed.toSet(), {_first, _second});
    expect(host.readCalls, isEmpty);
  });

  test('UT-010 Android duplicate handle selection closes the granted handle only once', () async {
    final host = _ResourceHost()..selection = _selection([_first, _first]);
    final error = await AndroidResourceGateway(host: host)
        .pick()
        .then<Object?>((_) => null, onError: (Object error) => error);
    expect(error is ResourceFailure, isTrue);
    expect(host.closed, [_first]);
    expect(host.readCalls, isEmpty);
  });

  test('UT-010 Android malformed typed read result becomes fixed unavailable failure', () async {
    final host = _ResourceHost()..selection = _selection([_first]);
    host.read = (_, _) => Future<AndroidReadReply>.value(null as dynamic);
    final resource = (await AndroidResourceGateway(host: host).pick()).single;
    await expectLater(
      resource.read().drain<void>(),
      throwsA(_failure(FailureKind.unavailable)),
    );
    expect(host.closed, [_first]);
  });

  test('UT-010 Android malformed selection waits for actual resource cleanup before returning failure', () async {
    final host = _ResourceHost()
      ..selection = AndroidSelection(
        cancelled: false,
        resources: [
          _picked(_first),
          AndroidPickedResource(
            handle: _second,
            displayName: 'b.png',
            sourceType: 'future',
          ),
        ],
      );
    final closing = Completer<void>();
    host.close = (_) => closing.future;
    var finished = false;
    final operation = AndroidResourceGateway(host: host)
        .pick()
        .then<Object?>((_) => null, onError: (Object error) => error);
    operation.then((_) {
      finished = true;
    });
    await _settle();
    final premature = finished;
    closing.complete();
    final error = await operation;
    expect(premature, isFalse);
    expect(error is ResourceFailure, isTrue);
    expect(host.closed.toSet(), {_first, _second});
  });

  test(
    'UT-010 Android malformed cancelled selection releases its valid grants',
    () async {
      final host = _ResourceHost()
        ..selection = AndroidSelection(
          cancelled: true,
          resources: [_picked(_first)],
        );
      final error = await AndroidResourceGateway(host: host)
          .pick()
          .then<Object?>((_) => null, onError: (Object error) => error);
      expect(error is ResourceFailure, isTrue);
      expect(host.closed, [_first]);
      expect(host.readCalls, isEmpty);
    },
  );

  test('UT-010 Android empty cancelled selection and recovered source are separate outcomes', () async {
    final host = _ResourceHost()
      ..selection = AndroidSelection(cancelled: true, resources: []);
    final gateway = AndroidResourceGateway(host: host);
    expect(await gateway.pick(), isEmpty);
    host.selection = _selection([_first]);
    final recovered = await gateway.recover();
    expect(recovered.single.displayName, 'image.png');
    await recovered.single.release!();
    expect(host.recoverCalls, 1);
  });

  test('UT-010 Android unknown selector and read exceptions never stringify or escape raw values', () async {
    final selectorError = _UnsafeFailure();
    final host = _ResourceHost()..pick = () async => throw selectorError;
    final selectedError = await AndroidResourceGateway(host: host)
        .pick()
        .then<Object?>((_) => null, onError: (Object error) => error);
    expect(selectedError is ResourceFailure, isTrue);
    expect(selectorError.toStringCalls, 0);

    final readError = _UnsafeFailure();
    host.pick = null;
    host.selection = _selection([_first]);
    host.read = (_, _) async => throw readError;
    final resource = (await AndroidResourceGateway(host: host).pick()).single;
    final failed = await resource.read().drain<void>().then<Object?>(
      (_) => null,
      onError: (Object error) => error,
    );
    expect(failed is ResourceFailure, isTrue);
    expect(readError.toStringCalls, 0);
    expect(host.closed, [_first]);
  });

  test('UT-010 Android unknown recovered-selection exception never escapes raw values', () async {
    final unsafe = _UnsafeFailure();
    final host = _ResourceHost()..recover = () async => throw unsafe;
    final error = await AndroidResourceGateway(host: host)
        .recover()
        .then<Object?>((_) => null, onError: (Object error) => error);
    expect(error is ResourceFailure, isTrue);
    expect(unsafe.toStringCalls, 0);
  });
}

Matcher _failure(FailureKind kind) =>
    isA<ResourceFailure>().having((error) => error.kind, 'kind', kind);
Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

AndroidPickedResource _picked(String handle) => AndroidPickedResource(
  handle: handle,
  displayName: 'image.png',
  sourceType: 'file',
);
AndroidSelection _selection(List<String> handles) => AndroidSelection(
  cancelled: false,
  resources: handles.map(_picked).toList(),
);
AndroidReadReply _reply(
  List<int> bytes, {
  bool eof = false,
  AndroidIoCode code = AndroidIoCode.ok,
}) => AndroidReadReply(code: code, bytes: Uint8List.fromList(bytes), eof: eof);

class _UnsafeFailure implements Exception {
  int toStringCalls = 0;
  @override
  String toString() {
    toStringCalls++;
    return 'unsafe-source-path-secret';
  }
}

class _ResourceHost extends AndroidResourceHost {
  AndroidSelection selection = AndroidSelection(
    cancelled: false,
    resources: [],
  );
  Future<AndroidSelection> Function()? pick;
  Future<AndroidSelection> Function()? recover;
  Future<AndroidReadReply> Function(String handle, int readIndex)? read;
  Future<void> Function(String handle)? close;
  List<bool>? selectedFlags;
  final readCalls = <String, int>{};
  final closed = <String>[];
  int recoverCalls = 0;

  @override
  Future<AndroidSelection> pickResources(bool photos, bool backup) async {
    selectedFlags = [photos, backup];
    return await (pick?.call() ?? Future.value(selection));
  }

  @override
  Future<AndroidSelection> recoverSelection() async {
    recoverCalls++;
    return await (recover?.call() ?? Future.value(selection));
  }

  @override
  Future<AndroidReadReply> readResource(String handle) {
    final index = readCalls[handle] ?? 0;
    readCalls[handle] = index + 1;
    return read?.call(handle, index) ?? Future.value(_reply([], eof: true));
  }

  @override
  Future<void> closeResource(String handle) async {
    closed.add(handle);
    await close?.call(handle);
  }
}
