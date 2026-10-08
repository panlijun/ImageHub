import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/upload/data/library_upload_queue_store.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

void main() {
  late Directory sandbox, root;
  late LibraryRepository repository;
  late ImageAsset asset;
  late UploadBatch batch;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('imagehost-upload-epoch-');
    root = Directory('${sandbox.path}/library');
    repository = await LibraryRepository.open(root);
    final bytes = img.encodePng(img.Image(width: 7, height: 5));
    asset = (await repository.importResource(
      PlatformResource(
        displayName: '当前资产.png',
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
    batch = await repository.enqueueUploads(
      intentId: const Uuid().v4(),
      assetIds: [asset.id],
      targetIds: [target],
      allowOriginalMetadata: true,
    );
  });
  tearDown(() async {
    await repository.close();
    await sandbox.delete(recursive: true);
  });
  List<Map<String, Object?>> publications() {
    final db = sqlite3.open(
      '${root.path}/library.sqlite',
      mode: OpenMode.readOnly,
    );
    try {
      return db
          .select('SELECT * FROM upload_publications')
          .map((r) => Map<String, Object?>.from(r))
          .toList();
    } finally {
      db.close();
    }
  }

  ProviderUploadSuccess success() => ProviderUploadSuccess(
    service: ImageHostService.catbox,
    remoteId: 'epoch.png',
    directUrl: Uri.parse('https://files.catbox.moe/epoch.png'),
  );

  test('UT-080 partial matching attempt identity cannot bypass a foreign execution epoch; current confirmation still commits', () async {
    final other = await LibraryRepository.open(
      Directory('${sandbox.path}/other'),
    );
    final current = (await repository.beginUploadAttempt(
      batch.items.single.id,
    ))!;
    try {
      final before = publications();
      final stale = UploadExecution(
        item: current.item,
        attemptId: current.attemptId,
        generation: current.generation,
        target: current.target,
        file: current.file,
        release: () async {},
        libraryEpoch: other.executionEpoch,
      );
      await expectLater(
        repository.finishUploadAttempt(
          stale,
          success(),
          accumulatedRunning: const Duration(seconds: 1),
        ),
        throwsA(isA<UploadQueueFailure>()),
      );
      expect(publications(), before);
      expect(await repository.listUploadResults(), isEmpty);
      expect(current.libraryEpoch, repository.executionEpoch);
      await repository.finishUploadAttempt(
        current,
        success(),
        accumulatedRunning: const Duration(seconds: 1),
      );
      expect(await repository.listUploadResults(), hasLength(1));
    } finally {
      await current.release();
      await other.close();
    }
  });

  test('UT-080 partial old queue actor refuses all database operations after close and cannot affect reopened pending intent', () async {
    final old = LibraryUploadQueueStore(repository);
    final oldEpoch = repository.executionEpoch;
    await repository.close();
    expect(repository.executionEpoch, isNot(oldEpoch));
    repository = await LibraryRepository.open(root);
    final before = publications();
    await expectLater(old.listBatches(), throwsA(isA<UploadQueueFailure>()));
    await expectLater(
      old.cancel([batch.items.single.id]),
      throwsA(isA<UploadQueueFailure>()),
    );
    await expectLater(
      old.pauseBatch(batch.id, true),
      throwsA(isA<UploadQueueFailure>()),
    );
    expect(publications(), before);
    final current = LibraryUploadQueueStore(repository);
    expect((await current.listBatches()).single.id, batch.id);
    await current.pauseBatch(batch.id, true);
    expect((await current.listBatches()).single.paused, true);
  });

  test('UT-080 partial delayed actor retains epoch across awaits and cannot write a newly opened repository', () async {
    final gate = Completer<void>();
    final oldEpoch = repository.executionEpoch;
    final callback = repository.runInExecutionEpoch(oldEpoch, () async {
      await gate.future;
      // Simulate a long-lived actor which resolves the current repository
      // after an await. Its captured epoch must still be checked by the gate.
      await repository.setFavorite(asset.id, true);
    });
    final rejected = expectLater(callback, throwsA(isA<UploadQueueFailure>()));
    await repository.close();
    repository = await LibraryRepository.open(root);
    gate.complete();
    await rejected;
    expect((await repository.getAsset(asset.id))!.favorite, false);
    await repository.setFavorite(asset.id, true);
    expect((await repository.getAsset(asset.id))!.favorite, true);
  });
}
