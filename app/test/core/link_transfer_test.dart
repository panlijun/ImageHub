import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/backup/data/backup_zip_reader.dart';
import 'package:imagehost/features/backup/data/backup_zip_writer.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/links/application/link_transfer_coordinator.dart';
import 'package:imagehost/features/links/domain/link_transfer.dart';
import 'package:imagehost/features/upload/domain/link_format.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/platform/link_transfer_gateway.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UT-071 / SEC native transfer mapping', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('SDK clipboard writes exact text and only confirms after platform success', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      final gateway = SystemLinkTransferGateway();
      expect(
        await gateway.copyText('https://files.catbox.moe/test.png'),
        LinkTransferStatus.copied,
      );
      expect(calls.single.method, 'Clipboard.setData');
      expect(calls.single.arguments, {
        'text': 'https://files.catbox.moe/test.png',
      });
    });

    test(
      'SDK clipboard refusal and missing backend return safe failure states',
      () async {
        messenger.setMockMethodCallHandler(SystemChannels.platform, (_) async {
          throw PlatformException(code: 'denied', message: 'SECRET_SENTINEL');
        });
        final gateway = SystemLinkTransferGateway();
        expect(await gateway.copyText('ordinary'), LinkTransferStatus.failed);
        messenger.setMockMethodCallHandler(SystemChannels.platform, (_) async {
          throw MissingPluginException('SECRET_SENTINEL');
        });
        expect(
          await gateway.copyText('ordinary'),
          LinkTransferStatus.unsupported,
        );
      },
    );

    for (final entry in {
      ShareResultStatus.success: LinkTransferStatus.shared,
      ShareResultStatus.dismissed: LinkTransferStatus.cancelled,
      ShareResultStatus.unavailable: LinkTransferStatus.unconfirmed,
    }.entries) {
      test(
        'share ${entry.key.name} uses ordinary text and safe anchor',
        () async {
          ShareParams? captured;
          final gateway = SystemLinkTransferGateway(
            share: (params) async {
              captured = params;
              return ShareResult('SECRET_SENTINEL', entry.key);
            },
          );
          expect(
            await gateway.shareText(
              'ordinary',
              anchor: const LinkShareAnchor(
                left: 10,
                top: 20,
                width: 30,
                height: 40,
              ),
            ),
            entry.value,
          );
          expect(captured!.text, 'ordinary');
          expect(captured!.title, 'ImageHost 普通链接');
          expect(captured!.uri, isNull);
          expect(captured!.files, isNull);
          expect(captured!.previewThumbnail, isNull);
          expect(
            captured!.sharePositionOrigin,
            const Rect.fromLTWH(10, 20, 30, 40),
          );
        },
      );
    }

    test('share rejects invalid anchors without system calls and conceals exceptions', () async {
      var calls = 0;
      final gateway = SystemLinkTransferGateway(
        share: (_) async {
          calls++;
          throw PlatformException(code: 'denied', details: 'SECRET_SENTINEL');
        },
      );
      for (final anchor in [
        const LinkShareAnchor(left: double.nan, top: 0, width: 1, height: 1),
        const LinkShareAnchor(
          left: 0,
          top: double.infinity,
          width: 1,
          height: 1,
        ),
        const LinkShareAnchor(left: 0, top: 0, width: 0, height: 1),
        const LinkShareAnchor(left: 0, top: 0, width: 1, height: -1),
        const LinkShareAnchor(
          left: 0,
          top: 0,
          width: double.infinity,
          height: 1,
        ),
        const LinkShareAnchor(left: 0, top: 0, width: 1, height: double.nan),
      ]) {
        expect(
          await gateway.shareText('ordinary', anchor: anchor),
          LinkTransferStatus.failed,
        );
      }
      expect(calls, 0);
      expect(await gateway.shareText('ordinary'), LinkTransferStatus.failed);
      expect(calls, 1);
      final unsupported = SystemLinkTransferGateway(
        share: (_) async {
          throw MissingPluginException('SECRET_SENTINEL');
        },
      );
      expect(
        await unsupported.shareText('ordinary'),
        LinkTransferStatus.unsupported,
      );
    });
  });

  test(
    'UT-071 / SEC unknown backend errors never stringify or use a fallback',
    () async {
      final error = _UndisplayableFailure();
      var writes = 0, shares = 0;
      final gateway = SystemLinkTransferGateway(
        writeClipboard: (_) async {
          writes++;
          throw error;
        },
        share: (_) async {
          shares++;
          throw error;
        },
      );
      expect(await gateway.copyText('ordinary'), LinkTransferStatus.failed);
      expect(await gateway.shareText('ordinary'), LinkTransferStatus.failed);
      expect(writes, 1);
      expect(shares, 1);
      expect(error.stringifications, 0);
    },
  );

  group('UT-070/071 repository-owned local transfer', () {
    late Directory sandbox, root;
    late LibraryRepository repository;
    late String resultId;
    late _Gateway gateway;
    late LinkTransferCoordinator coordinator;

    List<Map<String, Object?>> rows(String table) {
      final db = sqlite3.open(
        '${root.path}/library.sqlite',
        mode: OpenMode.readOnly,
      );
      try {
        return db
            .select('SELECT * FROM "$table" ORDER BY 1')
            .map((row) => Map<String, Object?>.from(row))
            .toList();
      } finally {
        db.close();
      }
    }

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp(
        'imagehost-link-transfer-',
      );
      root = Directory('${sandbox.path}/library');
      repository = await LibraryRepository.open(root);
      final bytes = img.encodePng(img.Image(width: 8, height: 6));
      final asset = (await repository.importResource(
        PlatformResource(
          displayName: '普通结果.png',
          openRead: () => Stream.value(bytes),
        ),
      )).asset!;
      final target = await repository.saveTarget(
        service: ImageHostService.catbox,
        alias: '匿名目标',
        anonymous: false,
        credential: 'SyntheticAccountFixture0123456789',
        persistence: CredentialPersistence.session,
      );
      final batch = await repository.enqueueUploads(
        intentId: 'local-transfer-seed',
        assetIds: [asset.id],
        targetIds: [target],
        allowOriginalMetadata: true,
      );
      final execution = (await repository.beginUploadAttempt(
        batch.items.single.id,
      ))!;
      try {
        expect(
          await repository.authorizeUploadRequest(execution.attemptId),
          isTrue,
        );
        // No transport is invoked: synthetic remote evidence seeds the real SQL
        // result boundary, then all actions below are strictly local transfers.
        await repository.finishUploadAttempt(
          execution,
          ProviderUploadSuccess(
            service: ImageHostService.catbox,
            remoteId: 'ordinary.png',
            directUrl: Uri.parse('https://files.catbox.moe/ordinary.png'),
          ),
          accumulatedRunning: Duration.zero,
        );
      } finally {
        await execution.release();
      }
      resultId = (await repository.listUploadResults()).single.id;
      gateway = _Gateway();
      coordinator = LinkTransferCoordinator(repository, gateway);
    });

    tearDown(() async {
      await repository.close();
      await sandbox.delete(recursive: true);
    });

    test(
      'copy and all share outcomes preserve SQL; retry creates no upload',
      () async {
        final plan = await repository.prepareVisibleLinkCopy([
          resultId,
          '00000000-0000-4000-8000-000000000001',
        ], UploadLinkFormat.markdown);
        final beforeResults = rows('remote_upload_results');
        final beforeAttempts = rows('upload_attempts');
        final beforeItems = rows('upload_publications');
        gateway.fail = true;
        final failed = await coordinator.copy(plan);
        expect(failed.status, LinkTransferStatus.failed);
        expect(failed.message, isNot(contains('SECRET_SENTINEL')));
        gateway.fail = false;
        final copied = await coordinator.copy(plan);
        expect(copied.status, LinkTransferStatus.copied);
        expect(copied.copied, 1);
        expect(copied.skipped, 1);
        expect(copied.duplicates, 0);
        expect(gateway.copies, [plan.batch.text, plan.batch.text]);
        for (final status in [
          LinkTransferStatus.shared,
          LinkTransferStatus.cancelled,
          LinkTransferStatus.unconfirmed,
          LinkTransferStatus.unsupported,
          LinkTransferStatus.failed,
        ]) {
          gateway.shareStatus = status;
          final report = await coordinator.share(plan);
          expect(report.status, status);
          expect(report.copied, 1);
          expect(report.skipped, 1);
          expect(report.duplicates, 0);
          expect(report.message, isNot(contains('SECRET_SENTINEL')));
        }
        expect(rows('remote_upload_results'), beforeResults);
        expect(rows('upload_attempts'), beforeAttempts);
        expect(rows('upload_publications'), beforeItems);
        expect((await repository.listUploadResults()).single.id, resultId);
      },
    );

    test('empty plans do not invoke clipboard or share', () async {
      final plan = await repository.prepareVisibleLinkCopy([
        '00000000-0000-4000-8000-000000000001',
      ], UploadLinkFormat.url);
      expect(plan.batch.skipped, 1);
      expect((await coordinator.copy(plan)).status, LinkTransferStatus.empty);
      expect((await coordinator.share(plan)).status, LinkTransferStatus.empty);
      expect(gateway.copies, isEmpty);
      expect(gateway.shares, isEmpty);
      expect(await repository.listUploadResults(), hasLength(1));
    });

    test(
      'foreign owner and close/reopen plans are stale before system access',
      () async {
        final plan = await repository.prepareVisibleLinkCopy([
          resultId,
        ], UploadLinkFormat.url);
        final empty = await repository.prepareVisibleLinkCopy(
          [],
          UploadLinkFormat.url,
        );
        final other = await LibraryRepository.open(
          Directory('${sandbox.path}/other'),
        );
        try {
          final foreign = LinkTransferCoordinator(other, gateway);
          expect((await foreign.copy(plan)).status, LinkTransferStatus.stale);
          expect((await foreign.share(plan)).status, LinkTransferStatus.stale);
        } finally {
          await other.close();
        }
        await repository.close();
        expect((await coordinator.copy(plan)).status, LinkTransferStatus.stale);
        expect(
          (await coordinator.copy(empty)).status,
          LinkTransferStatus.stale,
        );
        repository = await LibraryRepository.open(root);
        coordinator = LinkTransferCoordinator(repository, gateway);
        expect(
          (await coordinator.share(plan)).status,
          LinkTransferStatus.stale,
        );
        expect(gateway.copies, isEmpty);
        expect(gateway.shares, isEmpty);
        expect((await repository.listUploadResults()).single.id, resultId);
      },
    );

    test('real replacement invalidates old plan despite retained ordinary result identity', () async {
      final plan = await repository.prepareVisibleLinkCopy([
        resultId,
      ], UploadLinkFormat.url);
      final epoch = repository.executionEpoch;
      final snapshot = await repository.captureBackupSnapshot(
        mode: BackupMode.metadata,
      );
      final archive = File('${sandbox.path}/metadata.zip');
      try {
        await BackupZipWriter().write(snapshot, archive);
      } finally {
        await snapshot.release();
      }
      final backup = await const BackupZipReader().preflight(
        archive,
        await Directory('${sandbox.path}/preflight').create(),
        availableBytes: (_) async => 1 << 40,
      );
      final hold = await repository.acquireRestoreHold();
      ReplacementRestorePreparation? preparation;
      try {
        preparation = await repository.prepareReplacementRestore(
          hold: hold,
          backup: backup,
          availableBytes: (_) async => 1 << 40,
        );
        final report = await repository.commitReplacementRestore(
          preparation: preparation,
          availableBytes: (_) async => 1 << 40,
          publishExclusive: (_, _) async => false,
        );
        expect(report.metadataOnly, isTrue);
      } finally {
        if (preparation != null) {
          await repository.discardReplacementPreparation(preparation);
        }
        await hold.release();
        await backup.dispose();
      }
      expect(repository.executionEpoch, isNot(epoch));
      expect((await coordinator.copy(plan)).status, LinkTransferStatus.stale);
      expect((await coordinator.share(plan)).status, LinkTransferStatus.stale);
      expect(gateway.copies, isEmpty);
      expect(gateway.shares, isEmpty);
      expect((await repository.listUploadResults()).single.id, resultId);
      final current = await repository.prepareVisibleLinkCopy([
        resultId,
      ], UploadLinkFormat.url);
      expect(
        (await coordinator.copy(current)).status,
        LinkTransferStatus.copied,
      );
    });
  });
}

final class _Gateway implements LinkTransferGateway {
  final copies = <String>[];
  final shares = <String>[];
  LinkTransferStatus copyStatus = LinkTransferStatus.copied;
  LinkTransferStatus shareStatus = LinkTransferStatus.shared;
  bool fail = false;
  @override
  Future<LinkTransferStatus> copyText(String text) async {
    copies.add(text);
    if (fail) throw StateError('SECRET_SENTINEL');
    return copyStatus;
  }

  @override
  Future<LinkTransferStatus> shareText(
    String text, {
    LinkShareAnchor? anchor,
  }) async {
    shares.add(text);
    if (fail) throw StateError('SECRET_SENTINEL');
    return shareStatus;
  }
}

final class _UndisplayableFailure implements Exception {
  int stringifications = 0;
  @override
  String toString() {
    stringifications++;
    throw StateError('SECRET_SENTINEL');
  }
}
