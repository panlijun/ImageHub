import 'dart:async';

import 'package:imagehost/core/network_state.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'package:imagehost/app.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/upload/application/upload_coordinator.dart';
import 'package:imagehost/features/upload/data/library_upload_queue_store.dart';
import 'package:imagehost/features/upload/data/provider_adapters.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/queue_policy.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';

import '../test/core/secret_store_test.dart' show MemorySecretStore;

// Real Windows engine, SQLite and managed input reads; completion is an
// explicitly controlled endpoint boundary, with no HTTP or external account.
class _LocalAdapter implements ProviderAdapter {
  @override
  ImageHostService get service => ImageHostService.catbox;
  @override
  ProviderUploadLimits get limits =>
      ProviderUploadLimits(maximumBytes: 1000000, formats: {'png'});
  final calls =
      <({CancelToken cancel, Completer<ProviderUploadResult> result})>[];
  final digests = <String>[];
  final reads = <({String format, int actualBytes, int expectedBytes})>[];
  String? readFailure;
  @override
  Future<ProviderUploadResult> upload({
    required File file,
    required String actualFormat,
    required int expectedBytes,
    required ResolvedTarget target,
    required CancelToken cancelToken,
    UploadActivityCallback? onActivity,
  }) async {
    List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException catch (error) {
      readFailure = 'file-read:${error.osError?.errorCode}';
      rethrow;
    }
    // Assertions belong to the test body: the production coordinator safely
    // catches adapter failures and must not hide a test assertion as unknown.
    reads.add((
      format: actualFormat,
      actualBytes: bytes.length,
      expectedBytes: expectedBytes,
    ));
    digests.add(sha256.convert(bytes).toString());
    final result = Completer<ProviderUploadResult>();
    calls.add((cancel: cancelToken, result: result));
    return result.future;
  }

  void complete(int index) => calls[index].result.complete(
    ProviderUploadSuccess(
      service: service,
      remoteId: 'controlled-pause-$index.png',
      directUrl: Uri.parse(
        'https://files.catbox.moe/controlled-pause-$index.png',
      ),
    ),
  );
  void settle() {
    for (final call in calls) {
      if (!call.result.isCompleted) {
        call.result.complete(
          const ProviderUploadCancelled(UploadDeliveryEvidence.notSent),
        );
      }
    }
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var index = 0; index < 300; index++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (ready()) return;
  }
  fail('Windows 单项暂停原生流程未到达预期状态');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'IT-004 partial Windows item pause persists across batch resume and reopen while real input IO completes',
    (tester) async {
      final sandbox = await Directory.systemTemp.createTemp(
        'imagehost-item-pause-engine-',
      );
      final root = Directory(p.join(sandbox.path, 'library'));
      final accountSecrets = MemorySecretStore();
      var repository = await LibraryRepository.open(
        root,
        secretStore: accountSecrets,
      );
      LibrarySession? session;
      ProviderContainer? container;
      final adapters = <_LocalAdapter>[];
      final boundary = GlobalKey();
      Future<UploadCoordinator> mount() async {
        final adapter = _LocalAdapter();
        adapters.add(adapter);
        final queue = UploadCoordinator(
          initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
          LibraryUploadQueueStore(repository),
          adapters: [adapter],
        );
        session = LibrarySession(repository, const [], uploads: queue);
        queue.setConcurrency(1);
        container = ProviderContainer(
          overrides: [
            librarySessionProvider.overrideWith((_) async => session!),
          ],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container!,
            child: RepaintBoundary(key: boundary, child: const ImageHostApp()),
          ),
        );
        final entry = find.ancestor(
          of: find.text('上传任务'),
          matching: find.byType(ListTile),
        );
        await _until(
          tester,
          () =>
              entry.evaluate().isNotEmpty &&
              tester.widget<ListTile>(entry).onTap != null,
        );
        await tester.tap(entry);
        await tester.pump();
        return queue;
      }

      Future<void> unmount() async {
        await tester.pumpWidget(const SizedBox());
        container?.dispose();
        container = null;
        await session?.close();
        session = null;
      }

      Future<void> tap(Key key, String labelAfter) async {
        final button = find.byKey(key);
        await _until(
          tester,
          () =>
              button.evaluate().isNotEmpty &&
              tester.widget<TextButton>(button).onPressed != null,
        );
        await Scrollable.ensureVisible(tester.element(button), alignment: 0.5);
        await tester.pump(const Duration(milliseconds: 100));
        await _until(tester, () => button.hitTestable().evaluate().isNotEmpty);
        await tester.tap(button.hitTestable());
        await tester.pump();
        await _until(
          tester,
          () =>
              tester.widget<TextButton>(button).onPressed != null &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty &&
              find
                  .descendant(of: button, matching: find.text(labelAfter))
                  .evaluate()
                  .isNotEmpty,
        );
      }

      Future<UploadBatch> saved() async =>
          (await repository.listUploadBatches()).single;
      try {
        final assets = <String>[];
        final sourceDigests = <String>[];
        for (var index = 0; index < 3; index++) {
          final bytes = img.encodePng(img.Image(width: 6 + index, height: 4));
          sourceDigests.add(sha256.convert(bytes).toString());
          assets.add(
            (await repository.importResource(
              PlatformResource(
                displayName: '原生暂停${index + 1}.png',
                openRead: () => Stream.value(bytes),
              ),
            )).asset!.id,
          );
        }
        final target = await repository.saveTarget(
          service: ImageHostService.catbox,
          alias: '受控端点',
          anonymous: false,
          credential: 'SyntheticAccountFixture0123456789',
        );
        final batch = await repository.enqueueUploads(
          intentId: 'native-single-pause',
          assetIds: assets,
          targetIds: [target],
          allowOriginalMetadata: true,
        );
        var queue = await mount();
        expect(queue.networkAllowed, false);
        await queue.setNetworkAllowed(true);
        final firstAdapter = adapters.last;
        await _until(tester, () => firstAdapter.calls.length == 1);
        final second = batch.items[1];
        final itemKey = ValueKey('tasks-pause-item-${second.id}');
        final batchKey = ValueKey('tasks-pause-batch-${batch.id}');
        await tap(itemKey, '继续本项');
        expect((await saved()).items[1].userPaused, true);
        await tap(batchKey, '恢复派发');
        expect((await saved()).paused, true);
        expect(firstAdapter.calls.single.cancel.isCancelled, false);
        firstAdapter.complete(0);
        await _until(tester, () => queue.activeCount == 0);
        expect(firstAdapter.calls, hasLength(1));
        expect((await saved()).items.first.state, PublishState.succeeded);
        await tap(batchKey, '暂停派发');
        expect((await saved()).paused, false);
        try {
          await _until(tester, () => firstAdapter.calls.length == 2);
        } catch (_) {
          final observed = await saved();
          final states = observed.items
              .map(
                (item) =>
                    '${item.position}:${item.state.name}:${item.userPaused}:'
                    '${item.waitReason?.name}:${item.attemptCount}',
              )
              .join(',');
          fail(
            '受控派发未出现：network=${queue.networkAllowed}, '
            'active=${queue.activeCount}, failure=${queue.failure}, '
            'readFailure=${firstAdapter.readFailure}, reads=${firstAdapter.reads}, '
            'batchPaused=${observed.paused}, '
            'items=$states',
          );
        }
        expect(firstAdapter.digests, [sourceDigests[0], sourceDigests[2]]);
        for (final read in firstAdapter.reads) {
          expect(read.actualBytes, read.expectedBytes);
          expect(read.format.toLowerCase(), 'png');
        }
        expect((await saved()).items[1].state, PublishState.paused);
        firstAdapter.complete(1);
        await _until(tester, () => queue.activeCount == 0);
        await tester.ensureVisible(find.byKey(itemKey));
        await tester.pump(const Duration(milliseconds: 100));
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        expect(png, isNotNull);
        await File(
          p.join(
            Directory.current.parent.path,
            'docs',
            'validation',
            'windows-item-pause.png',
          ),
        ).writeAsBytes(png!.buffer.asUint8List(), flush: true);
        final before = await saved();
        await unmount();
        repository = await LibraryRepository.open(
          root,
          secretStore: accountSecrets,
        );
        final reopened = await saved();
        expect(reopened.id, before.id);
        expect(
          reopened.items.map((item) => item.id),
          before.items.map((item) => item.id),
        );
        expect(reopened.items[1].userPaused, true);
        expect(reopened.items[1].state, PublishState.paused);
        expect(reopened.items.map((item) => item.attemptCount), [1, 0, 1]);
        queue = await mount();
        await tap(itemKey, '暂停本项');
        expect((await saved()).items[1].userPaused, false);
        expect((await saved()).items[1].attemptCount, 0);
        expect(adapters.last.calls, isEmpty);
        expect(queue.networkAllowed, false);
        await queue.setNetworkAllowed(true);
        await _until(tester, () => adapters.last.calls.length == 1);
        expect(adapters.last.digests, [sourceDigests[1]]);
        expect(
          adapters.last.reads.single.actualBytes,
          adapters.last.reads.single.expectedBytes,
        );
        expect(adapters.last.reads.single.format.toLowerCase(), 'png');
        adapters.last.complete(0);
        await _until(tester, () => queue.activeCount == 0);
        final done = await saved();
        expect(done.summary.state, BatchState.succeeded);
        expect(done.items.map((item) => item.attemptCount), [1, 1, 1]);
        expect(done.items.every((item) => !item.userPaused), true);
        expect((await repository.listUploadResults()).length, 3);
        expect(tester.takeException(), isNull);
      } finally {
        for (final adapter in adapters) {
          adapter.settle();
        }
        await unmount();
        await repository.close();
        final owned = p.normalize(p.absolute(sandbox.path));
        if (!p.isWithin(
              p.normalize(p.absolute(Directory.systemTemp.path)),
              owned,
            ) ||
            !p.basename(owned).startsWith('imagehost-item-pause-engine-')) {
          throw StateError('Refuse cleanup outside the owned pause fixture');
        }
        await Directory(owned).delete(recursive: true);
      }
    },
  );
}
