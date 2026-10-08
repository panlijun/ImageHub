import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/network_state.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/settings/domain/device_settings.dart';
import 'package:imagehost/features/upload/application/upload_coordinator.dart';
import 'package:imagehost/features/upload/data/library_upload_queue_store.dart';
import 'package:imagehost/features/upload/data/provider_adapters.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/queue_policy.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'upload_pipeline_test.dart' show ControlledUploadTransport;
import 'secret_store_test.dart' show MemorySecretStore;

final class _Monitor implements NetworkMonitor {
  final controller = StreamController<NetworkSnapshot>.broadcast(sync: true);
  NetworkSnapshot value = const NetworkSnapshot.offline();
  int starts = 0, closes = 0, refreshes = 0;
  @override
  NetworkSnapshot get current => value;
  @override
  Stream<NetworkSnapshot> get changes => controller.stream;
  void emit(NetworkSnapshot snapshot) {
    value = snapshot;
    controller.add(snapshot);
  }

  @override
  Future<void> start() async {
    starts++;
  }

  @override
  Future<void> refresh() async {
    refreshes++;
    controller.add(value);
  }

  @override
  Future<void> close() async {
    closes++;
    await controller.close();
  }
}

Future<void> _until(Future<bool> Function() ready) async {
  for (var i = 0; i < 300; i++) {
    if (await ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('真实资料库网络条件切换未完成。');
}

void main() {
  test('UT-063/087 IT-004 partial session observation and persisted policy resume one real intent without granting new-session permission', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'imagehost-network-session-',
    );
    final root = Directory(p.join(sandbox.path, 'library'));
    final accountSecrets = MemorySecretStore();
    var repository = await LibraryRepository.open(
      root,
      secretStore: accountSecrets,
    );
    LibrarySession? session;
    final monitor = _Monitor();
    final transport = ControlledUploadTransport(false);
    final actor = UploadCoordinator(
      LibraryUploadQueueStore(repository),
      adapters: [
        CatboxAdapter(
          limits: ProviderUploadLimits(maximumBytes: 100000, formats: {'png'}),
          transportFactory: () => transport,
        ),
      ],
    );
    try {
      final bytes = img.encodePng(img.Image(width: 7, height: 9));
      final asset = (await repository.importResource(
        PlatformResource(
          displayName: 'network.png',
          openRead: () => Stream.value(bytes),
        ),
      )).asset!;
      final target = await repository.saveTarget(
        service: ImageHostService.catbox,
        alias: '受控网络验证',
        anonymous: false,
        credential: 'SyntheticAccountFixture0123456789',
      );
      final batch = await repository.enqueueUploads(
        intentId: 'network-single-intent',
        assetIds: [asset.id],
        targetIds: [target],
        allowOriginalMetadata: true,
      );
      var gateChecks = 0;
      final denied = await LibraryUploadQueueStore(repository).begin(
        batch.items.single.id,
        mayDispatch: () {
          gateChecks++;
          return false;
        },
      );
      expect(denied, isNull);
      expect(gateChecks, 1);
      expect(
        (await repository.listUploadBatches()).single.items.single.attemptCount,
        0,
      );
      final sql = sqlite3.open(
        p.join(root.path, 'library.sqlite'),
        mode: OpenMode.readOnly,
      );
      try {
        for (final table in [
          'upload_attempts',
          'file_leases',
          'output_leases',
        ]) {
          expect(
            sql.select('SELECT COUNT(*) AS n FROM $table').single['n'],
            0,
            reason: '网络写入门拒绝后不能新建尝试或实际输入租约。',
          );
        }
      } finally {
        sql.close();
      }
      session = LibrarySession(
        repository,
        const [],
        uploads: actor,
        networkMonitor: monitor,
      );
      await actor.setNetworkAllowed(true);
      expect(monitor.starts, 1);
      await session.refreshNetwork();
      expect(monitor.refreshes, 1);
      expect(actor.networkAllowed, isTrue);
      expect(transport.requests, isEmpty);
      monitor.emit(NetworkSnapshot.connected([NetworkTransport.cellular]));
      await actor.refresh();
      expect(transport.requests, isEmpty);
      expect(
        (await repository.listUploadBatches()).single.items.single.waitReason,
        QueueWaitReason.network,
      );
      final snapshot = await repository.loadSettings();
      await repository.saveSettings(
        snapshot,
        DeviceSettings(
          networkUploadPolicy: NetworkUploadPolicy.anyKnownNetwork,
        ),
        defaultTargetIds: [],
      );
      await _until(
        () async =>
            actor.activeCount == 0 &&
            (await repository.listUploadBatches()).single.items.single.state ==
                PublishState.succeeded,
      );
      expect(transport.requests, hasLength(1));
      expect(
        transport.requests.single.contentLength,
        transport.requests.single.bytes.length,
      );
      for (var i = 0; i < 20; i++) {
        monitor.emit(NetworkSnapshot.connected([NetworkTransport.cellular]));
      }
      await actor.refresh();
      final after = (await repository.listUploadBatches()).single;
      expect(after.id, batch.id);
      expect(after.items.single.attemptCount, 1);
      expect(transport.requests, hasLength(1));
      await session.resetUploadsAfterReplacement();
      expect(session.uploads.networkAllowed, isFalse);
      expect(
        session.uploads.networkPolicy,
        NetworkUploadPolicy.anyKnownNetwork,
      );
      expect(session.uploads.networkSnapshot, monitor.current);
      monitor.emit(NetworkSnapshot.connected([NetworkTransport.wifi]));
      await session.uploads.refresh();
      expect(session.uploads.networkAllowed, isFalse);
      expect(transport.requests, hasLength(1));
      await session.close();
      session = null;
      expect(monitor.closes, 1);
      repository = await LibraryRepository.open(
        root,
        secretStore: accountSecrets,
      );
      session = LibrarySession(repository, const []);
      expect(session.uploads.networkAllowed, isFalse);
      expect(
        session.uploads.networkPolicy,
        NetworkUploadPolicy.anyKnownNetwork,
      );
      expect(session.uploads.networkSnapshot, const NetworkSnapshot.unknown());
      expect((await repository.listUploadBatches()).single.id, batch.id);
      expect(
        (await repository.listUploadBatches()).single.items.single.attemptCount,
        1,
      );
    } finally {
      await session?.close();
      await repository.close();
      final resolved = p.normalize(p.absolute(sandbox.path));
      if (!p.isWithin(
            p.normalize(p.absolute(Directory.systemTemp.path)),
            resolved,
          ) ||
          !p.basename(resolved).startsWith('imagehost-network-session-')) {
        throw StateError('测试目录不在预期临时根目录。');
      }
      await sandbox.delete(recursive: true);
    }
  });
}
