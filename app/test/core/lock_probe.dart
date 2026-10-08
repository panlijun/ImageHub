import 'dart:convert';
import 'dart:io';

import 'package:imagehost/core/managed_file_store.dart';
import 'package:imagehost/core/platform_resource.dart';

/// Manual real-process lock probe: start two instances with the same new path.
/// First emits LOCKED and holds until one stdin line; second must emit BLOCKED.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    exitCode = 2;
    return;
  }
  try {
    final store = await ManagedFileStore.open(Directory(arguments.single));
    stdout.writeln('LOCKED');
    await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;
    await store.close();
  } on LibraryOpenException {
    stdout.writeln('BLOCKED');
    exitCode = 3;
  }
}
