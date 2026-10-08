import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// Seeds only a current-project isolated test database, never an old app.
/// Historical anonymous identities remain readable without creating new ones
/// through the production API.
void markLegacyAnonymous(Directory root, String targetId) {
  final database = sqlite3.open('${root.path}/library.sqlite');
  try {
    database.execute('UPDATE provider_targets SET anonymous=1 WHERE id=?', [
      targetId,
    ]);
    for (final table in ['upload_publications', 'remote_upload_results']) {
      final rows = database.select(
        'SELECT id,target_json FROM $table WHERE target_id=?',
        [targetId],
      );
      for (final row in rows) {
        final snapshot = jsonDecode(row['target_json'] as String) as Map;
        snapshot['anonymous'] = true;
        database.execute('UPDATE $table SET target_json=? WHERE id=?', [
          jsonEncode(snapshot),
          row['id'],
        ]);
      }
    }
  } finally {
    database.close();
  }
}
