import 'dart:async';

import 'package:imagehost/core/network_state.dart';

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/upload/application/upload_coordinator.dart';
import 'package:imagehost/features/upload/data/library_upload_queue_store.dart';
import 'package:imagehost/features/upload/data/provider_adapters.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/queue_policy.dart';
import 'package:sqlite3/sqlite3.dart';

final class _ControlledAdapter implements ProviderAdapter {
  final entered = Completer<void>();
  final finished = Completer<ProviderUploadResult>();
  CancelToken? cancel;
  int calls = 0;
  @override
  ImageHostService get service => ImageHostService.catbox;
  @override
  ProviderUploadLimits get limits =>
      ProviderUploadLimits(maximumBytes: 1024 * 1024, formats: {'PNG'});
  @override
  Future<ProviderUploadResult> upload({
    required File file,
    required String actualFormat,
    required int expectedBytes,
    required ResolvedTarget target,
    required CancelToken cancelToken,
    UploadActivityCallback? onActivity,
  }) async {
    calls++;
    cancel = cancelToken;
    entered.complete();
    // Read actual managed bytes before the controlled in-flight wait.
    var readBytes = 0;
    await for (final chunk in file.openRead()) {
      readBytes += chunk.length;
    }
    expect(readBytes, expectedBytes);
    return finished.future;
  }
}

void main() {
  test('UT-079 partial: real SQLite pauses pending intent, retains lease until actual attempt settles, and survives reopen', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'imagehost-restore-gate-',
    );
    final root = Directory('${sandbox.path}/library');
    LibraryRepository? repository;
    UploadCoordinator? coordinator;
    final adapter = _ControlledAdapter();
    try {
      repository = await LibraryRepository.open(root);
      final imported = await repository.importResource(
        PlatformResource(
          displayName: '独立本机图片.png',
          openRead: () =>
              Stream.value(img.encodePng(img.Image(width: 8, height: 6))),
        ),
      );
      final target = await repository.saveTarget(
        service: ImageHostService.catbox,
        alias: '匿名受控验证',
        anonymous: false,
        credential: 'SyntheticAccountFixture0123456789',
        persistence: CredentialPersistence.session,
      );
      final first = await repository.enqueueUploads(
        intentId: 'restore-gate-first',
        assetIds: [imported.asset!.id],
        targetIds: [target],
        allowOriginalMetadata: true,
      );
      final second = await repository.enqueueUploads(
        intentId: 'restore-gate-second',
        assetIds: [imported.asset!.id],
        targetIds: [target],
        allowOriginalMetadata: true,
        forceAgain: true,
      );
      coordinator = UploadCoordinator(
        initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
        LibraryUploadQueueStore(repository),
        adapters: [adapter],
        concurrency: 1,
      );
      await coordinator.setNetworkAllowed(true);
      await adapter.entered.future;
      int leases() {
        final database = sqlite3.open(
          '${root.path}/library.sqlite',
          mode: OpenMode.readOnly,
        );
        try {
          return database
                  .select('SELECT COUNT(*) AS n FROM file_leases')
                  .single['n']
              as int;
        } finally {
          database.close();
        }
      }

      expect(leases(), 1);
      var ready = false;
      final holding = coordinator.holdForRestore().then((hold) {
        ready = true;
        return hold;
      });
      var paused = await repository.listUploadBatches();
      // Drain ordinary asynchronous work while the real attempt stays open.
      for (var i = 0; i < 200 && paused.any((b) => !b.paused); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        paused = await repository.listUploadBatches();
      }
      expect(
        (await repository.listUploadBatches()).every((b) => b.paused),
        isTrue,
      );
      expect(ready, isFalse);
      expect(leases(), 1);
      expect(adapter.cancel!.isCancelled, isTrue);
      adapter.finished.complete(
        const ProviderUploadCancelled(UploadDeliveryEvidence.uncertain),
      );
      final hold = await holding;
      expect(leases(), 0);
      expect(adapter.calls, 1);
      hold.release();
      await coordinator.close();
      coordinator = null;
      await repository.close();
      repository = await LibraryRepository.open(root);
      final reopened = await repository.listUploadBatches();
      expect(reopened.map((b) => b.id).toSet(), {first.id, second.id});
      expect(reopened.every((b) => b.paused), isTrue);
      expect(
        reopened.expand((b) => b.items).map((i) => i.state),
        contains(PublishState.unknown),
      );
      expect(
        (await repository.listAssets()).items.single.id,
        imported.asset!.id,
      );
      expect(
        (await repository.originalFor(imported.asset!)).existsSync(),
        isTrue,
      );
    } finally {
      if (!adapter.finished.isCompleted) {
        adapter.finished.complete(
          const ProviderUploadCancelled(UploadDeliveryEvidence.notSent),
        );
      }
      await coordinator?.close();
      await repository?.close();
      await sandbox.delete(recursive: true);
    }
  });
}
