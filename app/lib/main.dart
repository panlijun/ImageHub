import 'dart:io';

import 'package:flutter/widgets.dart';

import 'app.dart';
import 'features/diagnostics/application/diagnostic_runtime.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Decoded memory and disk thumbnails have separate candidate budgets.
  final mobile = Platform.isAndroid || Platform.isIOS;
  PaintingBinding.instance.imageCache
    ..maximumSize = mobile ? 100 : 200
    ..maximumSizeBytes = (mobile ? 32 : 64) * 1024 * 1024;
  DiagnosticRuntime.instance.install();
  launchImageHost();
}
