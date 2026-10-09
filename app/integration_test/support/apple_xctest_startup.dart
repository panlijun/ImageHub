import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

bool _registered = false;

/// Wait for the real Simulator engine before WidgetTester records its baseline.
/// FlutterEngine enables semantics on Simulator asynchronously. Its platform
/// handle must already exist when a case starts; this leaves the framework's
/// per-case handle disposal and leak checks intact.
void registerAppleXctestStartup(IntegrationTestWidgetsFlutterBinding binding) {
  if (!const bool.fromEnvironment('IMAGEHUB_XCTEST_EVIDENCE') ||
      !Platform.isIOS ||
      _registered) {
    return;
  }
  _registered = true;
  setUpAll(() async {
    final waiting = Stopwatch()..start();
    while (!binding.platformDispatcher.semanticsEnabled ||
        !binding.semanticsEnabled) {
      if (waiting.elapsed >= const Duration(seconds: 20)) {
        throw StateError('iOS XCTest platform semantics did not become ready.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(binding.debugOutstandingSemanticsHandles, greaterThanOrEqualTo(1));
    // Fixed startup evidence only; it is not a test success result.
    // ignore: avoid_print
    print(
      'IMAGEHUB_IOS_XCTEST_SEMANTICS_READY:'
      '{"platformEnabled":true,"frameworkEnabled":true,'
      '"bindingHandles":${binding.debugOutstandingSemanticsHandles}}',
    );
  });
}
