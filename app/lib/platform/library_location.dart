import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Returns the V1 library directory inside the application's support area.
///
/// This intentionally resolves only the new namespace and does not search for
/// or adopt directories from earlier applications.
Future<Directory> locateLibrary() async {
  final supportDirectory = await getApplicationSupportDirectory();
  await supportDirectory.create(recursive: true);
  final canonical = await supportDirectory.resolveSymbolicLinks();
  return Directory(path.join(canonical, 'imagehost_library_v1'));
}
