import 'package:integration_test/integration_test_driver.dart';

/// Uses the official completed-test response from an already running app.
/// The owned iOS CI launcher installs and starts the exact test entry point.
Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 10),
  responseDataCallback: null,
);
