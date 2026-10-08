import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' hide DiagnosticLevel;
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/features/diagnostics/application/diagnostic_runtime.dart';
import 'package:imagehost/features/diagnostics/domain/diagnostic_models.dart';

class _HostileException {
  bool inspected = false;
  @override
  String toString() {
    inspected = true;
    throw StateError('secret-source-path');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DiagnosticRuntime runtime;
  setUp(() => runtime = DiagnosticRuntime());
  tearDown(() => runtime.uninstall());

  test(
    'UT-085 SDK entrypoints never inspect raw errors or stack paths',
    () async {
      final oldFlutter = FlutterError.onError;
      final oldPlatform = PlatformDispatcher.instance.onError;
      runtime.install();
      final events = <DiagnosticEvent>[];
      final detach = runtime.attach((event) async => events.add(event));
      final hostile = _HostileException();
      FlutterError.onError!(
        FlutterErrorDetails(
          exception: hostile,
          stack: StackTrace.fromString(r'C:\Users\private\raw-secret.dart'),
        ),
      );
      expect(
        PlatformDispatcher.instance.onError!(
          hostile,
          StackTrace.fromString('/Users/private/raw-secret.dart'),
        ),
        isTrue,
      );
      await runtime.flush();
      expect(hostile.inspected, isFalse);
      expect(events.map((e) => e.code), ['sdk.flutter', 'sdk.platform']);
      expect(
        events.every(
          (e) =>
              e.level == DiagnosticLevel.error && e.recoveryAction.isNotEmpty,
        ),
        isTrue,
      );
      final json = jsonEncode(events.map((e) => e.toJson()).toList());
      expect(json, isNot(contains('raw-secret')));
      expect(json, isNot(contains('private')));
      await detach();
      await runtime.uninstall();
      expect(identical(FlutterError.onError, oldFlutter), isTrue);
      expect(
        identical(PlatformDispatcher.instance.onError, oldPlatform),
        isTrue,
      );
    },
  );

  test(
    'UT-084 startup buffer bounded and logger failure never recurses',
    () async {
      runtime.install();
      for (var i = 0; i < 120; i++) {
        FlutterError.onError!(
          FlutterErrorDetails(exception: _HostileException()),
        );
      }
      var calls = 0;
      final detach = runtime.attach((_) async {
        calls++;
        throw _HostileException();
      });
      await runtime.flush();
      expect(calls, 100);
      await detach();
    },
  );

  test(
    'UT-084 detach drains actual sink and old owner cannot detach new scope',
    () async {
      runtime.install();
      final gate = Completer<void>();
      final started = Completer<void>();
      final detachOld = runtime.attach((_) async {
        started.complete();
        await gate.future;
      });
      FlutterError.onError!(
        FlutterErrorDetails(exception: _HostileException()),
      );
      await started.future;
      final newEvents = <DiagnosticEvent>[];
      final detachNew = runtime.attach((event) async => newEvents.add(event));
      var drained = false;
      final draining = detachOld().then((_) => drained = true);
      FlutterError.onError!(
        FlutterErrorDetails(exception: _HostileException()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);
      gate.complete();
      await draining;
      await runtime.flush();
      expect(newEvents, hasLength(1));
      await detachNew();
    },
  );
}
