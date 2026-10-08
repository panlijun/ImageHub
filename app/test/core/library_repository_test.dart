import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/core/managed_file_store.dart';
import 'package:imagehost/features/gallery/application/import_batch.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';

void main() {
  late Directory sandbox;
  late Directory root;
  LibraryRepository? repository;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('imagehost_new_test_');
    root = Directory(p.join(sandbox.path, 'library'));
  });
  tearDown(() async {
    await repository?.close();
    repository = null;
    await sandbox.delete(recursive: true);
  });

  Uint8List picture(String format, {int red = 80}) {
    final image = img.Image(width: 3, height: 2, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(red, 30, 160, 255));
    return switch (format) {
      'PNG' => img.encodePng(image),
      'JPEG' => img.encodeJpg(image),
      'GIF' => img.encodeGif(image),
      'BMP' => img.encodeBmp(image),
      'WebP' => img.encodeWebP(image),
      _ => throw ArgumentError(format),
    };
  }

  PlatformResource resource(List<int> bytes, {String name = 'example.txt'}) =>
      PlatformResource(displayName: name, openRead: () => Stream.value(bytes));

  for (final format in ['PNG', 'JPEG', 'GIF', 'BMP', 'WebP']) {
    test('UT-002 / IT-001 actual $format bytes with wrong extension', () async {
      repository = await LibraryRepository.open(root);
      final bytes = picture(format);
      // Confirm real encoder output can be decoded, independently of our
      // import validation. Static WebP has no animation-table records.
      final fixture = img.decodeImage(bytes);
      expect(fixture, isNotNull);
      expect(fixture!.numFrames, 1);
      final result = await repository!.importResource(resource(bytes));
      expect(result.status, ImportStatus.saved);
      expect(result.asset!.version.format, format);
      expect(result.asset!.version.width, 3);
      expect(result.asset!.version.height, 2);
      expect(
        await repository!.verifyCopy(result.asset!),
        CopyAvailability.available,
      );
    });
  }
  test(
    'UT-002 text masquerading as jpg and known unsupported bytes rejected',
    () async {
      repository = await LibraryRepository.open(root);
      final invalid = await repository!.importResource(
        resource('not a picture'.codeUnits, name: 'photo.jpg'),
      );
      final unsupported = await repository!.importResource(
        resource([0, 0, 0, 24, ...'ftypheic'.codeUnits]),
      );
      expect(invalid.failure!.kind, FailureKind.invalidImage);
      expect(unsupported.failure!.kind, FailureKind.unsupported);
      expect((await repository!.listAssets()).total, 0);
    },
  );
  test('UT-004 / UT-090 / IT-001 independent original survives source removal and reopen', () async {
    final source = File(p.join(sandbox.path, 'external.png'));
    final bytes = picture('PNG');
    await source.writeAsBytes(bytes);
    repository = await LibraryRepository.open(root);
    final saved = await repository!.importResource(
      PlatformResource.file(source),
    );
    expect(saved.status, ImportStatus.saved);
    expect(await source.readAsBytes(), bytes);
    await source.delete();
    await repository!.close();
    repository = await LibraryRepository.open(root);
    final page = await repository!.listAssets();
    expect(page.total, 1);
    expect(page.items.single.id, saved.asset!.id);
    expect(
      await (await repository!.originalFor(page.items.single)).readAsBytes(),
      bytes,
    );
    expect(page.items.single.importedAt.isUtc, true);
    expect(page.items.single.version.id, isNot(page.items.single.id));
    expect(
      page.items.single.deviceCopy.id,
      isNot(page.items.single.version.id),
    );
  });
  test(
    'UT-005 / UT-006 same bytes reuse identity and retain organization',
    () async {
      repository = await LibraryRepository.open(root);
      final first = await repository!.importResource(
        resource(picture('PNG'), name: 'first.png'),
      );
      final category = await repository!.createCategory('keep');
      await repository!.updateOrganization(
        [first.asset!.id],
        setCategory: true,
        categoryId: category.id,
        favorite: true,
      );
      await repository!.close();
      repository = null;
      repository = await LibraryRepository.open(root);
      final duplicate = await repository!.importResource(
        resource(picture('PNG'), name: 'renamed.png'),
      );
      expect(duplicate.status, ImportStatus.duplicate);
      expect(duplicate.asset!.id, first.asset!.id);
      expect(duplicate.asset!.displayName, 'first.png');
      expect(duplicate.asset!.favorite, true);
      expect(duplicate.asset!.category, 'keep');
      expect(duplicate.asset!.importedAt, first.asset!.importedAt);
      expect((await repository!.listAssets()).total, 1);
    },
  );
  test(
    'UT-006 same size but different bytes get distinct content identities',
    () async {
      final a = picture('BMP', red: 10);
      final b = picture('BMP', red: 20);
      expect(a.length, b.length);
      repository = await LibraryRepository.open(root);
      final first = await repository!.importResource(resource(a));
      final second = await repository!.importResource(resource(b));
      expect(second.status, ImportStatus.saved);
      expect(second.asset!.version.sha256, isNot(first.asset!.version.sha256));
      expect(second.asset!.version.id, isNot(first.asset!.version.id));
    },
  );
  test('UT-007 recycled duplicate requests restore without revival', () async {
    repository = await LibraryRepository.open(root);
    final first = await repository!.importResource(resource(picture('PNG')));
    await repository!.close();
    repository = null;
    final database = sqlite3.open(p.join(root.path, 'library.sqlite'));
    database.execute('UPDATE assets SET recycled=1 WHERE id=?', [
      first.asset!.id,
    ]);
    database.close();
    repository = await LibraryRepository.open(root);
    final result = await repository!.importResource(resource(picture('PNG')));
    expect(result.status, ImportStatus.needsRestore);
    expect(result.asset!.id, first.asset!.id);
    expect(result.asset!.recycled, true);
    expect((await repository!.listAssets()).total, 0);
  });
  test('UT-008 batch partial success equals per-item counts', () async {
    repository = await LibraryRepository.open(root);
    final report = await ImportBatch(repository!).run([
      resource(picture('PNG')),
      resource([1, 2, 3]),
      resource(picture('BMP')),
      resource(picture('PNG')),
    ]);
    expect(report.count(ImportStatus.saved), 2);
    expect(report.count(ImportStatus.failed), 1);
    expect(report.count(ImportStatus.duplicate), 1);
    expect((await repository!.listAssets()).total, 2);
  });
  test(
    'UT-011 stop skips unopened sources and preserves saved items',
    () async {
      repository = await LibraryRepository.open(root);
      final token = CancellationToken();
      var sourceCalls = 0;
      final report = await ImportBatch(repository!).run(
        [
          resource(picture('PNG')),
          PlatformResource(
            displayName: 'later',
            openRead: () {
              sourceCalls++;
              return Stream.value(picture('BMP'));
            },
          ),
        ],
        cancellation: token,
        onResult: (index, result) {
          if (index == 0) token.cancel();
        },
      );
      expect(sourceCalls, 0);
      expect(report.count(ImportStatus.saved), 1);
      expect(report.count(ImportStatus.cancelled), 1);
    },
  );
  for (final boundary in ImportBoundary.values) {
    test(
      'UT-003 / UT-091 interruption at ${boundary.name} preserves valid recovery state',
      () async {
        repository = await LibraryRepository.open(
          root,
          faultHook: (current) async {
            if (current == boundary) throw StateError('simulated termination');
          },
        );
        final result = await repository!.importResource(
          resource(picture('PNG')),
        );
        expect(
          result.status,
          boundary == ImportBoundary.afterDbCommit
              ? ImportStatus.saved
              : ImportStatus.failed,
        );
        final beforeRecovery = await repository!.listAssets();
        expect(
          beforeRecovery.total,
          boundary == ImportBoundary.afterDbCommit ? 1 : 0,
        );
        await repository!.close();
        repository = await LibraryRepository.open(root);
        final shouldCommit = [
          ImportBoundary.ready,
          ImportBoundary.published,
          ImportBoundary.beforeDbCommit,
          ImportBoundary.afterDbCommit,
        ].contains(boundary);
        final recovered = await repository!.listAssets();
        expect(recovered.total, shouldCommit ? 1 : 0);
        expect(repository!.recoveryIssues, isEmpty);
        if (shouldCommit) {
          expect(
            await repository!.verifyCopy(recovered.items.single),
            CopyAvailability.available,
          );
        }
        await repository!.recover();
        expect((await repository!.listAssets()).total, shouldCommit ? 1 : 0);
      },
    );
  }
  for (final boundary in [ImportBoundary.ready, ImportBoundary.published]) {
    test(
      'UT-011 cancellation at ${boundary.name} cannot later recover as saved',
      () async {
        final token = CancellationToken();
        repository = await LibraryRepository.open(
          root,
          faultHook: (current) async {
            if (current == boundary) token.cancel();
          },
        );
        expect(
          (await repository!.importResource(
            resource(picture('PNG')),
            cancellation: token,
          )).status,
          ImportStatus.cancelled,
        );
        await repository!.close();
        repository = await LibraryRepository.open(root);
        expect((await repository!.listAssets()).total, 0);
        expect(
          await Directory(p.join(root.path, 'originals')).list().toList(),
          isEmpty,
        );
      },
    );
  }
  test(
    'UT-003 source stream failure leaves previous committed bytes intact',
    () async {
      repository = await LibraryRepository.open(root);
      final first = await repository!.importResource(resource(picture('PNG')));
      final failed = await repository!.importResource(
        PlatformResource(
          displayName: 'broken',
          openRead: () async* {
            yield [137, 80, 78, 71];
            throw const ResourceFailure(FailureKind.permissionDenied);
          },
        ),
      );
      expect(failed.failure!.kind, FailureKind.permissionDenied);
      expect((await repository!.listAssets()).total, 1);
      expect(
        await repository!.verifyCopy(first.asset!),
        CopyAvailability.available,
      );
    },
  );
  test('UT-021 matching reimport repairs missing copy without changing logical identities', () async {
    repository = await LibraryRepository.open(root);
    final first = await repository!.importResource(resource(picture('PNG')));
    final file = await repository!.originalFor(first.asset!);
    await file.delete();
    expect(
      await repository!.verifyCopy(first.asset!),
      CopyAvailability.missing,
    );
    final wrongContent = await repository!.importResource(
      resource(picture('BMP')),
    );
    expect(wrongContent.status, ImportStatus.saved);
    expect(wrongContent.asset!.id, isNot(first.asset!.id));
    final repaired = await repository!.importResource(
      resource(picture('PNG'), name: 'different.png'),
    );
    expect(repaired.status, ImportStatus.repaired);
    expect(repaired.asset!.id, first.asset!.id);
    expect(repaired.asset!.version.id, first.asset!.version.id);
    expect(repaired.asset!.deviceCopy.id, first.asset!.deviceCopy.id);
    expect(repaired.asset!.displayName, first.asset!.displayName);
    expect(
      await repository!.verifyCopy(repaired.asset!),
      CopyAvailability.available,
    );
  });
  test('UT-093 future version refused with bytes preserved', () async {
    await root.create();
    final database = sqlite3.open(p.join(root.path, 'library.sqlite'));
    database.execute('PRAGMA user_version=99');
    database.execute('CREATE TABLE keep_me(value TEXT)');
    database.execute("INSERT INTO keep_me VALUES('preserved')");
    database.close();
    final before = await File(p.join(root.path, 'library.sqlite'))
        .readAsBytes();
    await expectLater(
      LibraryRepository.open(root),
      throwsA(isA<LibraryOpenException>()),
    );
    expect(
      await File(p.join(root.path, 'library.sqlite')).readAsBytes(),
      before,
    );
  });
  test(
    'UT-093 damaged database is not overwritten or treated as empty',
    () async {
      await root.create();
      final file = File(p.join(root.path, 'library.sqlite'));
      await file.writeAsBytes([1, 2, 3, 4, 5]);
      await expectLater(
        LibraryRepository.open(root),
        throwsA(isA<LibraryOpenException>()),
      );
      expect(await file.readAsBytes(), [1, 2, 3, 4, 5]);
    },
  );
  test(
    'UT-091 management lock blocks another coordinator and releases on close',
    () async {
      repository = await LibraryRepository.open(root);
      await expectLater(
        LibraryRepository.open(root),
        throwsA(isA<LibraryOpenException>()),
      );
      await repository!.close();
      repository = await LibraryRepository.open(root);
      expect((await repository!.listAssets()).total, 0);
    },
  );
  test('Close is idempotent for window exit and provider disposal', () async {
    repository = await LibraryRepository.open(root);
    await repository!.close();
    await repository!.close();
    repository = null;
  });
  test(
    'UT-009 actual metadata uses UTC and stable import-time order',
    () async {
      repository = await LibraryRepository.open(root);
      final early = await withClock(
        Clock.fixed(DateTime.parse('2026-10-04T01:00:00Z')),
        () => repository!.importResource(
          PlatformResource(
            displayName: 'first.png',
            sourceType: 'photo',
            openRead: () => Stream.value(picture('PNG')),
          ),
        ),
      );
      final later = await withClock(
        Clock.fixed(DateTime.parse('2026-10-04T10:30:00+08:00')),
        () => repository!.importResource(resource(picture('BMP'))),
      );
      expect(early.asset!.sourceType, 'photo');
      expect(early.asset!.version.byteCount, picture('PNG').length);
      expect(early.asset!.updatedAt, early.asset!.importedAt);
      expect(early.asset!.importedAt.isUtc, true);
      expect((await repository!.listAssets()).items.map((asset) => asset.id), [
        later.asset!.id,
        early.asset!.id,
      ]);
    },
  );
  for (final field in ['stage_path', 'final_path', 'id']) {
    test(
      'UT-091 / UT-093 tampered journal $field preserves unrelated files and journal',
      () async {
        repository = await LibraryRepository.open(
          root,
          faultHook: (boundary) async {
            if (boundary == ImportBoundary.copy) {
              throw StateError('interruption');
            }
          },
        );
        await repository!.importResource(resource(picture('PNG')));
        await repository!.close();
        repository = null;
        final database = sqlite3.open(p.join(root.path, 'library.sqlite'));
        final opId =
            database.select('SELECT id FROM import_operations').single['id']
                as String;
        final markerRelative = field == 'final_path'
            ? 'originals/unrelated.original'
            : 'staging/unrelated.part';
        final marker = File(p.join(root.path, markerRelative));
        await marker.writeAsBytes([9, 8, 7]);
        database.execute('UPDATE import_operations SET $field=? WHERE id=?', [
          field == 'id' ? 'invalid-id' : markerRelative,
          opId,
        ]);
        database.close();
        repository = await LibraryRepository.open(root);
        expect(repository!.recoveryIssues, hasLength(1));
        expect(await marker.readAsBytes(), [9, 8, 7]);
        expect((await repository!.listAssets()).total, 0);
        await repository!.close();
        repository = null;
        final after = sqlite3.open(p.join(root.path, 'library.sqlite'));
        expect(after.select('SELECT * FROM import_operations'), hasLength(1));
        after.close();
      },
    );
  }
  test(
    'UT-093 path traversal and absolute paths cannot escape managed root',
    () async {
      final store = await ManagedFileStore.open(root);
      try {
        for (final path in [
          '../outside.png',
          '/outside.png',
          'staging/../../outside',
          r'..\outside',
        ]) {
          await expectLater(store.file(path), throwsA(isA<ResourceFailure>()));
        }
      } finally {
        await store.close();
      }
    },
  );
  test('UT-003 candidate resource budget rejects before committing', () async {
    repository = await LibraryRepository.open(root, memoryBudgetBytes: 128);
    final result = await repository!.importResource(resource(picture('BMP')));
    expect(result.failure!.kind, FailureKind.resourceBudget);
    expect((await repository!.listAssets()).total, 0);
  });
  test('LIB-001 thumbnail regenerates after cache removal and does not replace original', () async {
    repository = await LibraryRepository.open(root);
    final first = await repository!.importResource(resource(picture('PNG')));
    final initialJob = repository!.thumbnailFor(first.asset!);
    final concurrentJob = repository!.thumbnailFor(first.asset!);
    expect(identical(initialJob, concurrentJob), true);
    final thumbnail = await initialJob.timeout(const Duration(seconds: 5));
    expect(await concurrentJob.timeout(const Duration(seconds: 5)), thumbnail);
    expect(thumbnail, isNotNull);
    await thumbnail!.delete();
    expect(
      await repository!
          .thumbnailFor(first.asset!)
          .timeout(const Duration(seconds: 5)),
      isNotNull,
    );
    expect(
      await repository!.verifyCopy(first.asset!),
      CopyAvailability.available,
    );
  });
}
