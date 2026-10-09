import 'dart:convert';

import 'package:integration_test/integration_test_driver.dart';

import '../integration_test/support/backup_interop_harness.dart';

/// Connects to a test application already installed by the owned platform tool.
/// Run through flutter drive --use-existing-app; this driver never installs.
Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 10),
  responseDataCallback: (data) {
    if (data == null || data.isEmpty) {
      throw StateError('No completed backup verification evidence.');
    }
    final exports = data['imageHubBackupExports'];
    final results = data['imageHubBackupInteropResults'];
    if (exports != null) {
      if (exports is! List || exports.length != 1) {
        throw StateError('Unexpected backup export evidence.');
      }
      for (final encoded in exports) {
        if (encoded is! String) {
          throw StateError('Invalid backup export evidence.');
        }
        BackupInteropPayload.decode(encoded);
        // Only the validated synthetic fixture is emitted.
        // ignore: avoid_print
        print('$interopExportPrefix$encoded');
      }
    }
    if (results != null) {
      if (results is! List || results.isEmpty || results.length > 3) {
        throw StateError('Unexpected backup restore evidence.');
      }
      // ignore: avoid_print
      print(jsonEncode({'backupInteropResults': results}));
    }
    if (exports == null && results == null) {
      throw StateError('No completed backup verification evidence.');
    }
  },
);
