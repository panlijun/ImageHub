import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/network_state.dart';
import 'package:imagehost/platform/system_network_monitor.dart';

const _read = MethodChannel('io.imagehost/network');
const _events = MethodChannel('io.imagehost/network_changes');
const _codec = StandardMethodCodec();
const _wifi = {
  'status': 'connected',
  'transports': ['wifi'],
};
const _cellular = {
  'status': 'connected',
  'transports': ['cellular'],
};
const _offline = {'status': 'offline', 'transports': <String>[]};

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  late SystemNetworkMonitor monitor;
  late _TrackingMessenger tracking;
  late List<String> calls;
  late List<FlutterErrorDetails> reportedErrors;
  late void Function(FlutterErrorDetails)? previousErrorHandler;

  Future<void> flush() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> event(Object? value) async {
    await messenger.handlePlatformMessage(
      _events.name,
      _codec.encodeSuccessEnvelope(value),
      (_) {},
    );
  }

  Future<void> envelope(ByteData? data) async {
    await messenger.handlePlatformMessage(_events.name, data, (_) {});
  }

  setUp(() {
    reportedErrors = [];
    previousErrorHandler = FlutterError.onError;
    FlutterError.onError = reportedErrors.add;
    calls = [];
    tracking = _TrackingMessenger(messenger);
    monitor = SystemNetworkMonitor(
      readTimeout: const Duration(milliseconds: 40),
      binaryMessenger: tracking,
    );
    messenger.setMockMethodCallHandler(_read, (call) async {
      calls.add(call.method);
      return _wifi;
    });
    messenger.setMockMethodCallHandler(_events, (call) async {
      calls.add(call.method);
      return null;
    });
  });

  tearDown(() async {
    try {
      await monitor.close();
      messenger.setMockMethodCallHandler(_read, null);
      messenger.setMockMethodCallHandler(_events, null);
      // Assert the count without formatting raw platform error details.
      expect(reportedErrors.length, 0);
    } finally {
      FlutterError.onError = previousErrorHandler;
    }
  });

  test('UT-063 local read, initial event, idempotent start and duplicate suppression', () async {
    final observed = <NetworkSnapshot>[];
    final subscription = monitor.changes.listen(observed.add);
    await monitor.start();
    await monitor.start();
    await event(_wifi);
    await flush();
    expect(monitor.current, NetworkSnapshot.connected([NetworkTransport.wifi]));
    expect(observed, [
      NetworkSnapshot.connected([NetworkTransport.wifi]),
    ]);
    expect(calls.where((call) => call == 'listen'), hasLength(1));
    expect(calls.where((call) => call == 'read'), hasLength(1));
    await event(_cellular);
    await flush();
    expect(observed, hasLength(2));
    expect(
      NetworkUploadPolicy.wifiAndEthernet.allows(monitor.current),
      isFalse,
    );
    expect(NetworkUploadPolicy.anyKnownNetwork.allows(monitor.current), isTrue);
    await subscription.cancel();
  });

  test('UT-063 late read cannot overwrite a newer event', () async {
    final response = Completer<Object?>();
    messenger.setMockMethodCallHandler(_read, (_) => response.future);
    final started = monitor.start();
    await flush();
    await event(_cellular);
    await flush();
    response.complete(_wifi);
    await started;
    expect(
      monitor.current,
      NetworkSnapshot.connected([NetworkTransport.cellular]),
    );
  });

  test(
    'UT-063 native listen can deliver the initial snapshot before read',
    () async {
      messenger.setMockMethodCallHandler(_events, (call) async {
        calls.add(call.method);
        if (call.method == 'listen') await event(_cellular);
        return null;
      });
      await monitor.start();
      await flush();
      expect(
        monitor.current,
        NetworkSnapshot.connected([NetworkTransport.cellular]),
      );
    },
  );

  test('UT-063 concurrent refresh keeps the newer read', () async {
    await monitor.start();
    final older = Completer<Object?>();
    var readCount = 0;
    messenger.setMockMethodCallHandler(_read, (_) async {
      return ++readCount == 1 ? older.future : _cellular;
    });
    final first = monitor.refresh();
    await flush();
    await monitor.refresh();
    older.complete(_offline);
    await first;
    expect(
      monitor.current,
      NetworkSnapshot.connected([NetworkTransport.cellular]),
    );
  });

  test(
    'UT-063 timeout returns unknown and ignores the eventual read response',
    () async {
      await monitor.start();
      final response = Completer<Object?>();
      messenger.setMockMethodCallHandler(_read, (_) => response.future);
      await monitor.refresh();
      expect(monitor.current, const NetworkSnapshot.unknown());
      response.complete(_wifi);
      await flush();
      expect(monitor.current, const NetworkSnapshot.unknown());
    },
  );

  test(
    'UT-063/SEC-005 missing platform backends fail closed without FlutterError',
    () async {
      messenger.setMockMethodCallHandler(_read, null);
      messenger.setMockMethodCallHandler(_events, null);
      await monitor.start();
      await flush();
      expect(monitor.current, const NetworkSnapshot.unknown());
      expect(reportedErrors.length, 0);
    },
  );

  test(
    'UT-063 missing event backend never grants a successful read eligibility',
    () async {
      final observed = <NetworkSnapshot>[];
      final subscription = monitor.changes.listen(observed.add);
      messenger.setMockMethodCallHandler(_events, null);
      await monitor.start();
      await flush();
      expect(monitor.current, const NetworkSnapshot.unknown());
      expect(
        observed.where((value) => value.status == NetworkStatus.connected),
        isEmpty,
      );
      expect(calls.where((call) => call == 'read'), isEmpty);
      expect(reportedErrors.length, 0);
      await subscription.cancel();
    },
  );

  test(
    'UT-063 listen timeout rejects a buffered initial Wi-Fi event and read',
    () async {
      final observed = <NetworkSnapshot>[];
      final subscription = monitor.changes.listen(observed.add);
      final listening = Completer<Object?>();
      messenger.setMockMethodCallHandler(_events, (call) async {
        calls.add(call.method);
        if (call.method == 'listen') {
          await event(_wifi);
          return listening.future;
        }
        return null;
      });
      await monitor.start();
      await flush();
      expect(monitor.current, const NetworkSnapshot.unknown());
      expect(
        observed.where((value) => value.status == NetworkStatus.connected),
        isEmpty,
      );
      expect(calls.where((call) => call == 'read'), isEmpty);
      listening.complete(null);
      await flush();
      expect(monitor.current, const NetworkSnapshot.unknown());
      expect(
        observed.where((value) => value.status == NetworkStatus.connected),
        isEmpty,
      );
      await subscription.cancel();
    },
  );

  test('UT-063/SEC-005 malformed reads and events fail closed', () async {
    await monitor.start();
    await event({
      'status': 'connected',
      'transports': ['invalid-secret'],
    });
    await flush();
    expect(monitor.current, const NetworkSnapshot.unknown());
    await event(_wifi);
    await flush();
    messenger.setMockMethodCallHandler(
      _read,
      (_) async => {'status': 'connected'},
    );
    await monitor.refresh();
    expect(monitor.current, const NetworkSnapshot.unknown());
    expect(reportedErrors.length, 0);
  });

  test(
    'UT-063/SEC-005 stream error clears state and refresh rebuilds listening',
    () async {
      await monitor.start();
      await envelope(
        _codec.encodeErrorEnvelope(code: 'native', message: 'private-secret'),
      );
      await flush();
      expect(monitor.current, const NetworkSnapshot.unknown());
      expect(reportedErrors.length, 0);
      await monitor.refresh();
      expect(calls.where((call) => call == 'listen'), hasLength(2));
      await event(_cellular);
      await flush();
      expect(
        monitor.current,
        NetworkSnapshot.connected([NetworkTransport.cellular]),
      );
    },
  );

  test(
    'UT-063 malformed encoded event terminates and allows a fresh subscription',
    () async {
      await monitor.start();
      await envelope(ByteData(1));
      await flush();
      expect(monitor.current, const NetworkSnapshot.unknown());
      await monitor.refresh();
      expect(calls.where((call) => call == 'listen'), hasLength(2));
      expect(reportedErrors.length, 0);
    },
  );

  test(
    'UT-063 stream termination becomes unknown and refresh rebuilds listening',
    () async {
      await monitor.start();
      await envelope(null);
      await flush();
      expect(monitor.current, const NetworkSnapshot.unknown());
      await monitor.refresh();
      expect(calls.where((call) => call == 'listen'), hasLength(2));
      expect(
        monitor.current,
        NetworkSnapshot.connected([NetworkTransport.wifi]),
      );
    },
  );

  test(
    'UT-063 close ignores pending refresh and detaches the event handler',
    () async {
      await monitor.start();
      final oldHandler = tracking.networkHandler!;
      final response = Completer<Object?>();
      messenger.setMockMethodCallHandler(_read, (_) => response.future);
      final pending = monitor.refresh();
      await flush();
      await monitor.close();
      await monitor.close();
      response.complete(_offline);
      await pending;
      await oldHandler(_codec.encodeSuccessEnvelope(_offline));
      expect(
        monitor.current,
        NetworkSnapshot.connected([NetworkTransport.wifi]),
      );
      expect(tracking.networkHandler, isNull);
      final count = calls.length;
      await monitor.refresh();
      await monitor.start();
      monitor.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await flush();
      expect(calls.length, count);
    },
  );

  test(
    'UT-063 native listen and cancel timeout cannot block startup or close',
    () async {
      final listening = Completer<Object?>();
      final cancelling = Completer<Object?>();
      messenger.setMockMethodCallHandler(_events, (call) {
        calls.add(call.method);
        return call.method == 'listen' ? listening.future : cancelling.future;
      });
      await monitor.start();
      await Future<void>.delayed(const Duration(milliseconds: 55));
      expect(monitor.current, const NetworkSnapshot.unknown());
      await monitor.close();
      expect(tracking.networkHandler, isNull);
      listening.complete(null);
      cancelling.complete(null);
      await flush();
      expect(monitor.current, const NetworkSnapshot.unknown());
      expect(reportedErrors.length, 0);
    },
  );

  test(
    'UT-063 late expired listen cannot cancel a replacement subscription',
    () async {
      final firstListen = Completer<Object?>();
      var listens = 0;
      messenger.setMockMethodCallHandler(_events, (call) async {
        calls.add(call.method);
        if (call.method == 'listen' && ++listens == 1) {
          return firstListen.future;
        }
        return null;
      });
      await monitor.start();
      await Future<void>.delayed(const Duration(milliseconds: 55));
      await monitor.refresh();
      expect(listens, 2);
      final cancels = calls.where((call) => call == 'cancel').length;
      firstListen.complete(null);
      await flush();
      expect(calls.where((call) => call == 'cancel'), hasLength(cancels));
      await event(_cellular);
      await flush();
      expect(
        monitor.current,
        NetworkSnapshot.connected([NetworkTransport.cellular]),
      );
    },
  );

  test(
    'UT-063/SEC-005 native exceptions are never stringified or reported',
    () async {
      messenger.setMockMethodCallHandler(
        _read,
        (_) async => throw PlatformException(
          code: 'private',
          message: 'read-private-secret',
        ),
      );
      messenger.setMockMethodCallHandler(
        _events,
        (_) async => throw PlatformException(
          code: 'private',
          message: 'event-private-secret',
        ),
      );
      await monitor.start();
      await flush();
      await monitor.close();
      expect(monitor.current, const NetworkSnapshot.unknown());
      expect(reportedErrors.length, 0);
    },
  );

  test(
    'UT-063 non-resumed lifecycle blocks updates and resumed refreshes',
    () async {
      await monitor.start();
      for (final lifecycle in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      ]) {
        monitor.didChangeAppLifecycleState(lifecycle);
        await event(_wifi);
        await flush();
        expect(monitor.current, const NetworkSnapshot.unknown());
        final reads = calls.where((call) => call == 'read').length;
        await monitor.refresh();
        expect(calls.where((call) => call == 'read'), hasLength(reads));
      }
      monitor.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await flush();
      expect(
        monitor.current,
        NetworkSnapshot.connected([NetworkTransport.wifi]),
      );
    },
  );

  test('UT-063 backgrounding invalidates an in-flight read', () async {
    await monitor.start();
    final response = Completer<Object?>();
    messenger.setMockMethodCallHandler(_read, (_) => response.future);
    final refreshing = monitor.refresh();
    await flush();
    monitor.didChangeAppLifecycleState(AppLifecycleState.paused);
    response.complete(_wifi);
    await refreshing;
    expect(monitor.current, const NetworkSnapshot.unknown());
    await envelope(null);
    await flush();
    messenger.setMockMethodCallHandler(_read, (_) async => _wifi);
    monitor.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await flush();
    expect(calls.where((call) => call == 'listen'), hasLength(2));
    expect(monitor.current, NetworkSnapshot.connected([NetworkTransport.wifi]));
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
    test(
      'UT-063 visible desktop inactive keeps type observation; hidden blocks dispatch $platform',
      () async {
        await monitor.close();
        monitor = SystemNetworkMonitor(
          binaryMessenger: tracking,
          platform: platform,
        );
        await monitor.start();
        monitor.didChangeAppLifecycleState(AppLifecycleState.inactive);
        await event(_cellular);
        await flush();
        expect(
          monitor.current,
          NetworkSnapshot.connected([NetworkTransport.cellular]),
        );
        monitor.didChangeAppLifecycleState(AppLifecycleState.hidden);
        await event(_wifi);
        await flush();
        expect(monitor.current, const NetworkSnapshot.unknown());
        monitor.didChangeAppLifecycleState(AppLifecycleState.inactive);
        await flush();
        expect(
          monitor.current,
          NetworkSnapshot.connected([NetworkTransport.wifi]),
        );
      },
    );
  }
}

final class _TrackingMessenger extends BinaryMessenger {
  _TrackingMessenger(this.delegate);

  final BinaryMessenger delegate;
  MessageHandler? networkHandler;

  @override
  Future<ByteData?>? send(String channel, ByteData? message) =>
      delegate.send(channel, message);

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {
    if (channel == _events.name) networkHandler = handler;
    delegate.setMessageHandler(channel, handler);
  }

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) async {
    // ignore: deprecated_member_use
    await delegate.handlePlatformMessage(channel, data, callback);
  }
}
