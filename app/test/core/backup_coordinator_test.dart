import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/backup/application/backup_coordinator.dart';
import 'package:imagehost/features/backup/application/backup_snapshot.dart';
import 'package:imagehost/features/backup/data/backup_zip_reader.dart';
import 'package:imagehost/features/backup/data/backup_temporary_workspace.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory sandbox, library, exports, validation;
  late LibraryRepository repository;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('backup-coordinator-');
    library = Directory('${sandbox.path}/library');
    exports = await Directory('${sandbox.path}/exports').create();
    validation = await Directory('${sandbox.path}/validation').create();
    repository = await LibraryRepository.open(library);
    final bytes = img.encodePng(img.Image(width: 7, height: 5));
    await repository.importResource(
      PlatformResource(
        displayName: '真实图片.png',
        openRead: () => Stream.value(bytes),
      ),
    );
  });
  tearDown(() async {
    await repository.close();
    await sandbox.delete(recursive: true);
  });

  // Controlled publication verifies coordinator decisions. The real Windows
  // exclusivity guarantee is separately exercised by native integration tests.
  Future<bool> publish(File source, File target) async {
    if (await target.exists()) return false;
    await source.rename(target.path);
    return true;
  }

  BackupCoordinator coordinator({
    Future<int> Function(Directory)? capacity,
    PublishBackup? publication,
  }) => BackupCoordinator(
    capture: (mode, token, progress) => repository.captureBackupSnapshot(
      mode: mode,
      cancellation: token,
      onVerification: progress,
    ),
    availableBytes: capacity ?? (_) async => 1 << 40,
    publishExclusive: publication ?? publish,
  );
  void noLeases() {
    final db = sqlite3.open('${library.path}/library.sqlite');
    try {
      expect(db.select('SELECT COUNT(*) AS n FROM file_leases').single['n'], 0);
    } finally {
      db.close();
    }
  }

  test('UT-073/082 partial actual full export passes independent preflight and releases sources', () async {
    final phases = <String>[];
    final report = await coordinator().export(
      exports,
      BackupMode.full,
      onProgress: (phase, _, _) => phases.add(phase),
    );
    expect(report.assets, 1);
    expect(report.versions, 1);
    expect(report.cleanupPending, false);
    expect(report.byteCount, await report.file.length());
    expect(phases, containsAll(['校验永久副本', '写入备份', '提交备份']));
    expect(await exports.list().toList(), hasLength(1));
    noLeases();
    final valid = await const BackupZipReader().preflight(
      report.file,
      validation,
      availableBytes: (_) async => 1 << 40,
    );
    expect(valid.manifest.assets.single.displayName, '真实图片.png');
    expect(valid.imageFiles, hasLength(1));
    await valid.dispose();
    await repository.close();
    repository = await LibraryRepository.open(library);
    expect((await repository.listAssets()).total, 1);
  });
  test(
    'UT-073 partial explicit metadata export cannot restore image bytes',
    () async {
      final report = await coordinator().export(exports, BackupMode.metadata);
      final valid = await const BackupZipReader().preflight(
        report.file,
        validation,
        availableBytes: (_) async => 1 << 40,
      );
      expect(valid.manifest.assets, hasLength(1));
      expect(valid.imageFiles, isEmpty);
      expect(report.mode, BackupMode.metadata);
      noLeases();
      await valid.dispose();
    },
  );
  test('UT-082 partial capacity failure or precommit cancellation publishes nothing', () async {
    await expectLater(
      coordinator(capacity: (_) async => 0).export(exports, BackupMode.full),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    expect(await exports.list().toList(), isEmpty);
    noLeases();
    final token = CancellationToken();
    await expectLater(
      coordinator().export(
        exports,
        BackupMode.full,
        cancellation: token,
        onProgress: (phase, _, _) {
          if (phase == '提交备份') token.cancel();
        },
      ),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    expect(await exports.list().toList(), isEmpty);
    noLeases();
    expect((await repository.listAssets()).total, 1);
  });
  test('UT-082 partial exclusive publication collision retains existing file and retries new identity', () async {
    File? existing;
    var calls = 0;
    final report = await coordinator(
      publication: (source, target) async {
        if (++calls == 1) {
          existing = await target.writeAsString('existing export', flush: true);
        }
        return publish(source, target);
      },
    ).export(exports, BackupMode.full);
    expect(calls, 2);
    expect(await existing!.readAsString(), 'existing export');
    expect(report.file.path, isNot(existing!.path));
    expect(await exports.list().toList(), hasLength(2));
    noLeases();
  });
  test('UT-082 partial publication is commit point late cancellation retains completed backup', () async {
    final token = CancellationToken();
    final report = await coordinator(
      publication: (source, target) async {
        final result = await publish(source, target);
        token.cancel();
        return result;
      },
    ).export(exports, BackupMode.full, cancellation: token);
    expect(await report.file.exists(), true);
    expect(await exports.list().toList(), hasLength(1));
    noLeases();
  });

  test('UT-082 failed publication preserves unknown child and complete owned ZIP without touching permanent images', () async {
    File? unknown, staged;
    late List<int> original;
    await expectLater(
      coordinator(
        publication: (source, _) async {
          staged = source;
          original = await source.readAsBytes();
          unknown = await File('${source.parent.path}/foreign.bin')
              .writeAsString('foreign owner', flush: true);
          throw StateError('injected publication failure');
        },
      ).export(exports, BackupMode.full),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    expect(await unknown!.readAsString(), 'foreign owner');
    expect(await staged!.readAsBytes(), original);
    expect((await repository.listAssets()).total, 1);
    final asset = (await repository.listAssets()).items.single;
    expect(
      await (await repository.originalFor(asset)).readAsBytes(),
      img.encodePng(img.Image(width: 7, height: 5)),
    );
    noLeases();
  });

  test('UT-082 successful published user ZIP is retained while foreign stage child reports cleanup pending', () async {
    File? unknown;
    final report = await coordinator(
      publication: (source, target) async {
        unknown = await File('${source.parent.path}/foreign.bin')
            .writeAsString('foreign owner', flush: true);
        return publish(source, target);
      },
    ).export(exports, BackupMode.full);
    expect(report.cleanupPending, true);
    expect(report.cleanupMessage, contains('备份暂存'));
    expect(report.cleanupMessage, isNot(contains('文件使用保护记录')));
    expect(report.cleanupMessage, isNot(contains(exports.path)));
    expect(await unknown!.readAsString(), 'foreign owner');
    expect(await report.file.exists(), true);
    final validated = await const BackupZipReader().preflight(
      report.file,
      validation,
      availableBytes: (_) async => 1 << 40,
    );
    expect(validated.imageFiles, hasLength(1));
    await validated.dispose();
    noLeases();
  });

  test('UT-082 published stage name is retired even when identical bytes reappear there', () async {
    File? foreign;
    late List<int> original;
    final report = await coordinator(
      publication: (source, target) async {
        original = await source.readAsBytes();
        final committed = await publish(source, target);
        foreign = await source.writeAsBytes(original, flush: true);
        return committed;
      },
    ).export(exports, BackupMode.full);
    expect(report.cleanupPending, true);
    expect(report.cleanupMessage, contains('备份暂存'));
    expect(await foreign!.readAsBytes(), original);
    expect(await report.file.readAsBytes(), original);
    expect((await repository.listAssets()).total, 1);
    noLeases();
  });

  test('UT-082 changed completed staged ZIP is never erased after publication failure', () async {
    File? staged;
    late List<int> changed;
    await expectLater(
      coordinator(
        publication: (source, _) async {
          staged = source;
          changed = await source.readAsBytes();
          changed[changed.length - 1] ^= 1;
          await source.writeAsBytes(changed, flush: true);
          throw StateError('injected publication failure');
        },
      ).export(exports, BackupMode.metadata),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    expect(await staged!.readAsBytes(), changed);
    expect(await staged!.parent.exists(), true);
    noLeases();
    expect((await repository.listAssets()).total, 1);
  });

  test('UT-082 linked stage descendant is preserved and user ZIP remains committed', () async {
    final external = await File('${sandbox.path}/external.bin')
        .writeAsString('external owner');
    Link? link;
    var linked = false;
    final report = await coordinator(
      publication: (source, target) async {
        link = Link('${source.parent.path}/foreign-link');
        try {
          await link!.create(external.path);
          linked = true;
        } on FileSystemException {
          markTestSkipped('当前测试进程无符号链接创建权限，真实链接分支未执行。');
        }
        return publish(source, target);
      },
    ).export(exports, BackupMode.full);
    try {
      expect(await report.file.exists(), true);
      expect(await external.readAsString(), 'external owner');
      if (linked) {
        expect(report.cleanupPending, true);
        expect(
          await FileSystemEntity.type(link!.path, followLinks: false),
          FileSystemEntityType.link,
        );
      }
      noLeases();
    } finally {
      if (linked) await link!.delete();
    }
  });

  test(
    'UT-082 uncertain IO marker blocks cleanup without deleting known partial',
    () async {
      final root = await exports.createTemp('.known-partial-');
      final workspace = BackupTemporaryWorkspace(root);
      final partial = await File('${root.path}/package.partial')
          .create(exclusive: true);
      workspace.registerFile(partial);
      await partial.writeAsString('partial', flush: true);
      workspace.markIoUncertain();
      await expectLater(
        workspace.remove(),
        throwsA(isA<BackupSnapshotFailure>()),
      );
      expect(await partial.readAsString(), 'partial');
      expect(await root.exists(), true);
    },
  );

  test('UT-082 real lease release SQL failure reports protection separately and never reclassifies published ZIP', () async {
    BackupSnapshotLease? captured;
    final exporter = BackupCoordinator(
      capture: (mode, token, progress) async {
        captured = await repository.captureBackupSnapshot(
          mode: mode,
          cancellation: token,
          onVerification: progress,
        );
        final db = sqlite3.open('${library.path}/library.sqlite');
        try {
          db.execute(
            "CREATE TRIGGER fail_backup_release BEFORE DELETE ON file_leases BEGIN SELECT RAISE(ABORT, 'injected'); END",
          );
        } finally {
          db.close();
        }
        return captured!;
      },
      availableBytes: (_) async => 1 << 40,
      publishExclusive: publish,
    );
    try {
      final report = await exporter.export(exports, BackupMode.full);
      expect(await report.file.exists(), true);
      expect(report.cleanupPending, true);
      expect(report.cleanupMessage, contains('文件使用保护记录'));
      expect(report.cleanupMessage, isNot(contains('备份暂存')));
      expect(report.cleanupMessage, isNot(contains(library.path)));
      expect(await exports.list().toList(), hasLength(1));
      final db = sqlite3.open('${library.path}/library.sqlite');
      try {
        expect(
          db.select('SELECT COUNT(*) AS n FROM file_leases').single['n'],
          1,
        );
      } finally {
        db.close();
      }
    } finally {
      final db = sqlite3.open('${library.path}/library.sqlite');
      try {
        db.execute('DROP TRIGGER fail_backup_release');
      } finally {
        db.close();
      }
      await captured?.release();
    }
    noLeases();
  });
}
