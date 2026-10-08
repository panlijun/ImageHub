import 'dart:async';

import 'package:imagehost/core/network_state.dart';

import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/backup/data/backup_zip_reader.dart';
import 'package:imagehost/features/backup/data/backup_zip_writer.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/upload/application/upload_coordinator.dart';
import 'package:imagehost/features/upload/data/library_upload_queue_store.dart';
import 'package:imagehost/features/upload/data/provider_adapters.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';
import 'package:imagehost/features/upload/presentation/upload_tasks_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'core/upload_repository_test.dart' show QueueTestSecrets;

Future<T> _native<T>(WidgetTester tester, Future<T> Function() action) async {
  var done = false;
  T? value;
  Object? failure;
  await tester.runAsync(() async {
    unawaited(
      action().then(
        (result) {
          value = result;
          done = true;
        },
        onError: (Object error) {
          failure = error;
          done = true;
        },
      ),
    );
  });
  for (var i = 0; i < 300 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done, isTrue, reason: '真实历史资料库 IO 必须结束');
  if (failure != null) throw failure!;
  return value as T;
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 300; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (ready()) return;
  }
  fail('真实历史 IO 和 widget 状态未完成');
}

class _NoNetwork implements ProviderAdapter {
  int calls = 0;
  @override
  ImageHostService get service => ImageHostService.catbox;
  @override
  ProviderUploadLimits get limits => const ProviderUploadLimits.unknown();
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
    return const ProviderUploadUnknown(UploadFailureKind.unknown);
  }
}

class _Fixture {
  _Fixture(this.directory, this.repository, this.secrets);
  final Directory directory;
  final LibraryRepository repository;
  final QueueTestSecrets secrets;
  final adapter = _NoNetwork();
  late final session = LibrarySession(
    repository,
    const [],
    uploads: UploadCoordinator(
      initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
      LibraryUploadQueueStore(repository),
      adapters: [adapter],
    ),
  );
  late final container = ProviderContainer(
    overrides: [librarySessionProvider.overrideWith((_) async => session)],
  );
  ImageAsset? asset;
  String? target;

  static Future<_Fixture> create(
    WidgetTester tester, {
    bool empty = false,
    Future<void> Function()? fault,
  }) => _native(tester, () async {
    final directory = await Directory.systemTemp.createTemp(
      'imagehost-history-ui-',
    );
    final secrets = QueueTestSecrets();
    final repository = await LibraryRepository.open(
      Directory('${directory.path}/library'),
      secretStore: secrets,
      historyClearFaultHook: fault == null ? null : (_) => fault(),
    );
    final fixture = _Fixture(directory, repository, secrets);
    if (!empty) {
      final bytes = img.encodePng(img.Image(width: 3, height: 2));
      fixture.asset = (await repository.importResource(
        PlatformResource(
          displayName: '历史原图.png',
          openRead: () => Stream.value(bytes),
        ),
      )).asset!;
      fixture.target = await repository.saveTarget(
        service: ImageHostService.catbox,
        alias: '历史目标',
        anonymous: false,
        credential: 'SyntheticAccountFixture0123456789',
      );
    }
    return fixture;
  });

  Future<UploadBatch> enqueue(String intent) => repository.enqueueUploads(
    intentId: intent,
    assetIds: [asset!.id],
    targetIds: [target!],
    allowOriginalMetadata: true,
    forceAgain: true,
  );

  Future<UploadBatch> complete(String intent) async {
    final batch = await enqueue(intent);
    final execution = (await repository.beginUploadAttempt(
      batch.items.single.id,
    ))!;
    try {
      await repository.authorizeUploadRequest(execution.attemptId);
      await repository.finishUploadAttempt(
        execution,
        ProviderUploadSuccess(
          service: ImageHostService.catbox,
          remoteId: '$intent.png',
          directUrl: Uri.parse('https://files.catbox.moe/$intent.png'),
        ),
        accumulatedRunning: Duration.zero,
      );
    } finally {
      await execution.release();
    }
    return batch;
  }

  Future<void> mount(
    WidgetTester tester, {
    double width = 1280,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const UploadTasksScreen(),
        ),
      ),
    );
    await _until(
      tester,
      () =>
          find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          find.text('恢复的完成历史').evaluate().isNotEmpty,
    );
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await _native(tester, session.close);
    await tester.runAsync(() => directory.delete(recursive: true));
  }
}

const _select = Key('upload-history-select-completed');
const _clear = Key('upload-history-clear-selected');
const _confirm = Key('upload-history-confirm-clear');

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _review(WidgetTester tester) async {
  await _tap(tester, find.byKey(_select));
  await _tap(tester, find.byKey(_clear));
  await _until(tester, () => find.text('清理已选历史？').evaluate().isNotEmpty);
}

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'QUE-010 AT-003 partial history $width large text empty and no network',
      (tester) async {
        final f = await _Fixture.create(tester, empty: true);
        await f.mount(tester, width: width, scale: 1.6);
        expect(
          tester.widget<FilledButton>(find.byKey(_clear)).onPressed,
          isNull,
        );
        await tester.ensureVisible(find.text('恢复的完成历史'));
        expect(f.session.uploads.networkAllowed, isFalse);
        expect(f.adapter.calls, 0);
        expect(tester.takeException(), isNull);
        await f.close(tester);
      },
    );
  }

  testWidgets(
    'UT-066 partial clear confirmation cancels then removes selected terminal only',
    (tester) async {
      final f = await _Fixture.create(tester);
      final completed = await _native(
        tester,
        () => f.complete('history-selected'),
      );
      final active = await _native(tester, () => f.enqueue('history-active'));
      await f.mount(tester);
      await _review(tester);
      expect(find.text('可清理 1 项；另有 0 项保留。'), findsOneWidget);
      await _tap(tester, find.widgetWithText(TextButton, '返回'));
      await _until(tester, () => find.text('清理已选历史？').evaluate().isEmpty);
      expect(
        (await _native(
          tester,
          f.repository.listUploadBatches,
        )).expand((b) => b.items).length,
        2,
      );
      await _tap(tester, find.byKey(_clear));
      await _until(tester, () => find.text('清理已选历史？').evaluate().isNotEmpty);
      await _tap(tester, find.byKey(_confirm));
      await _until(
        tester,
        () => find.text('已清理 1 项历史，保留 0 项。图片与普通结果保留。').evaluate().isNotEmpty,
      );
      final batches = await _native(tester, f.repository.listUploadBatches);
      expect(batches.singleWhere((b) => b.id == completed.id).items, isEmpty);
      expect(
        batches.singleWhere((b) => b.id == active.id).items.single.id,
        active.items.single.id,
      );
      expect(
        await _native(tester, f.repository.listUploadResults),
        hasLength(1),
      );
      expect(
        (await _native(tester, f.repository.listAssets)).items,
        hasLength(1),
      );
      expect(f.adapter.calls, 0);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );

  testWidgets(
    'UT-066 partial new completion during review is not added to selection',
    (tester) async {
      final f = await _Fixture.create(tester);
      final selected = await _native(tester, () => f.complete('review-first'));
      await f.mount(tester, width: 390);
      await _review(tester);
      final additional = await _native(tester, () => f.complete('review-new'));
      await _tap(tester, find.byKey(_confirm));
      await _until(
        tester,
        () => find.text('已清理 1 项历史，保留 0 项。图片与普通结果保留。').evaluate().isNotEmpty,
      );
      final batches = await _native(tester, f.repository.listUploadBatches);
      expect(batches.singleWhere((b) => b.id == selected.id).items, isEmpty);
      expect(
        batches.singleWhere((b) => b.id == additional.id).items,
        hasLength(1),
      );
      expect(
        await _native(tester, f.repository.listUploadResults),
        hasLength(2),
      );
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );

  testWidgets(
    'UT-066 partial selected evidence changes reject stale confirmation',
    (tester) async {
      final f = await _Fixture.create(tester);
      await _native(tester, () => f.complete('review-stale'));
      await f.mount(tester);
      await _review(tester);
      final result = (await _native(
        tester,
        f.repository.listUploadResults,
      )).single;
      await _native(tester, () async {
        await f.repository.removeLocalLinkResults([
          result.id,
        ], confirmLocalRemoval: true);
      });
      await _tap(tester, find.byKey(_confirm));
      await _until(
        tester,
        () => find.text('任务历史清理未提交，记录保留；请重新加载并确认。').evaluate().isNotEmpty,
      );
      expect(
        (await _native(tester, f.repository.listUploadBatches)).single.items,
        hasLength(1),
      );
      expect(find.textContaining('已清理 1 项历史'), findsNothing);
      await f.close(tester);
    },
  );

  testWidgets(
    'UT-066 partial transaction failure preserves records and explicit retry succeeds',
    (tester) async {
      var failOnce = true;
      final f = await _Fixture.create(
        tester,
        fault: () async {
          if (failOnce) {
            failOnce = false;
            throw StateError('synthetic history commit failure');
          }
        },
      );
      await _native(tester, () => f.complete('review-retry'));
      await f.mount(tester);
      await _review(tester);
      await _tap(tester, find.byKey(_confirm));
      await _until(
        tester,
        () => find.text('任务历史清理未提交，记录保留；请重新加载并确认。').evaluate().isNotEmpty,
      );
      expect(
        (await _native(tester, f.repository.listUploadBatches)).single.items,
        hasLength(1),
      );
      await _tap(tester, find.byKey(_clear));
      await _until(tester, () => find.text('清理已选历史？').evaluate().isNotEmpty);
      await _tap(tester, find.byKey(_confirm));
      await _until(
        tester,
        () => find.text('已清理 1 项历史，保留 0 项。图片与普通结果保留。').evaluate().isNotEmpty,
      );
      expect(
        (await _native(tester, f.repository.listUploadBatches)).single.items,
        isEmpty,
      );
      expect(
        await _native(tester, f.repository.listUploadResults),
        hasLength(1),
      );
      expect(f.adapter.calls, 0);
      await f.close(tester);
    },
  );

  testWidgets(
    'UT-066 partial disposing review resolves cancellation without deleting history',
    (tester) async {
      final f = await _Fixture.create(tester);
      await _native(tester, () => f.complete('review-dispose'));
      await f.mount(tester);
      await _review(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        (await _native(tester, f.repository.listUploadBatches)).single.items,
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );

  testWidgets(
    'UT-038/066 partial cancelled history remains protected until actual lease release',
    (tester) async {
      final f = await _Fixture.create(tester);
      final batch = await _native(tester, () => f.enqueue('cancelled-io'));
      final execution = (await _native(
        tester,
        () => f.repository.beginUploadAttempt(batch.items.single.id),
      ))!;
      await _native(
        tester,
        () => f.repository.cancelUploadItems([batch.items.single.id]),
      );
      await f.mount(tester, width: 390);
      await _review(tester);
      expect(find.text('可清理 0 项；另有 1 项保留。'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(_confirm)).onPressed,
        isNull,
      );
      await _tap(tester, find.widgetWithText(TextButton, '返回'));
      await _until(tester, () => find.text('清理已选历史？').evaluate().isEmpty);
      await _native(
        tester,
        () => f.repository.finishUploadAttempt(
          execution,
          const ProviderUploadCancelled(UploadDeliveryEvidence.notSent),
          accumulatedRunning: Duration.zero,
        ),
      );
      await _native(tester, execution.release);
      await _until(
        tester,
        () => tester.widget<FilledButton>(find.byKey(_clear)).onPressed != null,
      );
      await _tap(tester, find.byKey(_clear));
      await _until(
        tester,
        () => find.text('可清理 1 项；另有 0 项保留。').evaluate().isNotEmpty,
      );
      await _tap(tester, find.byKey(_confirm));
      await _until(
        tester,
        () => find.text('已清理 1 项历史，保留 0 项。图片与普通结果保留。').evaluate().isNotEmpty,
      );
      expect(
        (await _native(tester, f.repository.listAssets)).items,
        hasLength(1),
      );
      await f.close(tester);
    },
  );

  testWidgets(
    'UT-066 partial system exit cancels review and drains before reopening unchanged history',
    (tester) async {
      final f = await _Fixture.create(tester);
      await _native(tester, () => f.complete('exit-review'));
      await f.mount(tester);
      await _review(tester);
      expect(
        await _native(tester, tester.binding.handleRequestAppExit),
        AppExitResponse.exit,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('清理已选历史？'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      final reopened = await _native(
        tester,
        () => LibraryRepository.open(
          Directory('${f.directory.path}/library'),
          secretStore: f.secrets,
        ),
      );
      expect(
        (await _native(tester, reopened.listUploadBatches)).single.items,
        hasLength(1),
      );
      expect(await _native(tester, reopened.listUploadResults), hasLength(1));
      await _native(tester, reopened.close);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );

  testWidgets(
    'UT-066 partial actual metadata restore history shown with attempts then cleared independently',
    (tester) async {
      final source = await _Fixture.create(tester);
      await _native(tester, () => source.complete('restored-history'));
      final destination = await _native(tester, () async {
        final snapshot = await source.repository.captureBackupSnapshot(
          mode: BackupMode.metadata,
        );
        final zip = File('${source.directory.path}/metadata.zip');
        try {
          await BackupZipWriter().write(snapshot, zip);
        } finally {
          await snapshot.release();
        }
        final backup = await const BackupZipReader().preflight(
          zip,
          await Directory('${source.directory.path}/preflight').create(),
          availableBytes: (_) async => 1 << 40,
        );
        final directory = await Directory.systemTemp.createTemp(
          'imagehost-history-restored-ui-',
        );
        final secrets = QueueTestSecrets();
        final repository = await LibraryRepository.open(
          Directory('${directory.path}/library'),
          secretStore: secrets,
        );
        final hold = await repository.acquireRestoreHold();
        try {
          final preparation = await repository.prepareMergeRestore(
            hold: hold,
            backup: backup,
          );
          await repository.commitMergeRestore(
            preparation: preparation,
            availableBytes: (_) async => 1 << 40,
            publishExclusive: (_, _) async =>
                throw StateError('metadata restore must not publish originals'),
          );
        } finally {
          await hold.release();
          await backup.dispose();
        }
        return _Fixture(directory, repository, secrets);
      });
      await destination.mount(tester, width: 390);
      expect(find.text('这些记录只供查阅，不会重新上传。'), findsOneWidget);
      expect(find.text('恢复的尝试记录'), findsOneWidget);
      await _review(tester);
      expect(find.text('可清理 1 项；另有 0 项保留。'), findsOneWidget);
      await _tap(tester, find.byKey(_confirm));
      await _until(
        tester,
        () => find.text('已清理 1 项历史，保留 0 项。图片与普通结果保留。').evaluate().isNotEmpty,
      );
      expect(
        await _native(
          tester,
          destination.repository.listImportedUploadHistories,
        ),
        isEmpty,
      );
      expect(
        await _native(tester, destination.repository.listUploadResults),
        hasLength(1),
      );
      expect(
        (await _native(
          tester,
          source.repository.listUploadBatches,
        )).single.items,
        hasLength(1),
      );
      expect(destination.adapter.calls, 0);
      expect(tester.takeException(), isNull);
      await destination.close(tester);
      await source.close(tester);
    },
  );
}
