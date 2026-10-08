import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_database.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  for (final invalidPolicy in [false, true]) {
    test(
      'UT-093 own schema 2 to current ${invalidPolicy ? 'invalid policy rolls back before upgrade' : 'preserves IDs organization and bytes'}',
      () async {
        final sandbox = await Directory.systemTemp.createTemp(
          'imagehost_schema2_output_',
        );
        final root = Directory('${sandbox.path}/library');
        var repository = await LibraryRepository.open(root);
        try {
          final image = img.Image(width: 3, height: 2);
          final imported = (await repository.importResource(
            PlatformResource(
              displayName: 'new-schema-fixture.png',
              openRead: () => Stream.value(img.encodePng(image)),
            ),
          )).asset!;
          final category = await repository.createCategory('保留分类');
          await repository.updateOrganization(
            [imported.id],
            categoryId: category.id,
            setCategory: true,
            replaceTags: ['保留标签'],
          );
          await repository.setFavorite(imported.id, true);
          final before = (await repository.getAsset(imported.id))!;
          final source = await repository.originalFor(before);
          final bytes = await source.readAsBytes();
          await repository.close();
          // Our own schema-2 fixture: remove all later additions, no old app.
          var db = sqlite3.open('${root.path}/library.sqlite');
          try {
            db.execute('PRAGMA foreign_keys=ON');
            db.execute(
              'ALTER TABLE upload_publications DROP COLUMN processing_job_id',
            );
            db.execute('DROP TABLE upload_processing_jobs');
            db.execute('ALTER TABLE import_operations DROP COLUMN output_id');
            for (final table in [
              'diagnostic_records',
              'restore_operations',
              'imported_upload_histories',
              'restored_output_origins',
              'upload_events',
              'upload_result_operations',
              'remote_upload_results',
              'upload_attempts',
              'upload_publications',
              'upload_batches',
              'credential_operations',
              'provider_targets',
              'output_leases',
              'output_references',
              'saved_output_origins',
              'processed_outputs',
            ]) {
              db.execute('DROP TABLE $table');
            }
            db.execute('PRAGMA user_version=2');
            if (invalidPolicy) {
              db.execute(
                "UPDATE library_metadata SET value='unsupported-policy' WHERE key='text_policy'",
              );
            }
            expect(db.select('PRAGMA foreign_key_check'), isEmpty);
          } finally {
            db.close();
          }
          if (invalidPolicy) {
            await expectLater(
              LibraryRepository.open(root),
              throwsA(isA<LibraryOpenException>()),
            );
            db = sqlite3.open('${root.path}/library.sqlite');
            try {
              expect(db.select('PRAGMA user_version').single.values.single, 2);
              expect(
                db.select(
                  "SELECT name FROM sqlite_master WHERE type='table' AND name='processed_outputs'",
                ),
                isEmpty,
              );
              expect(
                db.select('SELECT id FROM assets').single.values.single,
                before.id,
              );
            } finally {
              db.close();
            }
            expect(await source.readAsBytes(), bytes);
          } else {
            repository = await LibraryRepository.open(root);
            expect(await repository.getAsset(before.id), before);
            expect(
              await repository.verifyCopy(before),
              CopyAvailability.available,
            );
            expect(await repository.listOutputs(), isEmpty);
            expect(await source.readAsBytes(), bytes);
            await repository.close();
            db = sqlite3.open('${root.path}/library.sqlite');
            try {
              expect(
                db.select('PRAGMA user_version').single.values.single,
                librarySchemaVersion,
              );
              expect(db.select('PRAGMA foreign_key_check'), isEmpty);
              expect(
                db.select('PRAGMA integrity_check').single.values.single,
                'ok',
              );
            } finally {
              db.close();
            }
          }
        } finally {
          await repository.close();
          await sandbox.delete(recursive: true);
        }
      },
    );
  }
}
