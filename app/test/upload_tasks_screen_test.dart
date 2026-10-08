import 'dart:async';

import 'package:imagehost/core/network_state.dart';

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' hide DiagnosticLevel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/diagnostics/domain/diagnostic_models.dart';
import 'package:imagehost/features/diagnostics/presentation/diagnostics_screen.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/upload/application/upload_coordinator.dart';
import 'package:imagehost/features/upload/data/library_upload_queue_store.dart';
import 'package:imagehost/features/upload/data/provider_adapters.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/queue_policy.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';
import 'package:imagehost/features/upload/presentation/upload_tasks_screen.dart';
import 'package:material_ui/material_ui.dart' hide DiagnosticLevel;

import 'core/accounts_repository_test.dart' show TestSecrets;

// Exercise real temporary SQLite/files while alternating native work and fake
// widget time; a fake-zone pumpAndSettle cannot drain native repository IO.
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
  expect(done, isTrue, reason: '真实资料库 IO 必须结束');
  if (failure != null) {
    throw failure!;
  }
  return value as T;
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 300; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (ready()) {
      return;
    }
  }
  fail('上传页面真实 IO 与 widget 状态未完成');
}

void _size(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _NoNetworkAdapter implements ProviderAdapter {
  _NoNetworkAdapter(this.service, {this.verified = false});
  @override
  final ImageHostService service;
  final bool verified;
  int calls = 0;
  @override
  ProviderUploadLimits get limits => verified
      ? ProviderUploadLimits(maximumBytes: 1000000, formats: {'png'})
      : const ProviderUploadLimits.unknown();
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

Future<void> _mount(
  WidgetTester tester,
  ProviderContainer container, {
  double scale = 1,
}) => tester.pumpWidget(
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

void main() {
  for (final width in [1280.0, 390.0]) {
    testWidgets(
      'UT-054 AT-003 partial $width real SQL item pause survives batch resume and item resume respects batch pause',
      (tester) async {
        _size(tester, width);
        final sandbox = await _native(
          tester,
          () => Directory.systemTemp.createTemp('imagehost-item-pause-widget-'),
        );
        final repository = await _native(
          tester,
          () => LibraryRepository.open(
            Directory('${sandbox.path}/library'),
            secretStore: TestSecrets(),
          ),
        );
        final adapter = _NoNetworkAdapter(ImageHostService.catbox);
        final queue = UploadCoordinator(
          initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
          LibraryUploadQueueStore(repository),
          adapters: [adapter],
        );
        final session = LibrarySession(repository, const [], uploads: queue);
        final container = ProviderContainer(
          overrides: [
            librarySessionProvider.overrideWith((_) async => session),
          ],
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          container.dispose();
          await _native(tester, session.close);
          await _native(tester, () => sandbox.delete(recursive: true));
        });
        final batch = await _native(tester, () async {
          final ids = <String>[];
          for (var index = 0; index < 2; index++) {
            final bytes = img.encodePng(img.Image(width: 4 + index, height: 3));
            ids.add(
              (await repository.importResource(
                PlatformResource(
                  displayName: '单项暂停${index + 1}.png',
                  openRead: () => Stream.value(bytes),
                ),
              )).asset!.id,
            );
          }
          final target = await repository.saveTarget(
            service: ImageHostService.catbox,
            alias: '离线合成目标',
            anonymous: false,
            credential: 'SyntheticAccountFixture0123456789',
          );
          return repository.enqueueUploads(
            intentId: 'widget-item-pause',
            assetIds: ids,
            targetIds: [target],
            allowOriginalMetadata: true,
          );
        });
        await _mount(tester, container, scale: width < 600 ? 2 : 1);
        final itemKey = ValueKey('tasks-pause-item-${batch.items.first.id}');
        final batchKey = ValueKey('tasks-pause-batch-${batch.id}');
        Future<void> tap(Key key) async {
          final button = find.byKey(key);
          await _until(
            tester,
            () =>
                button.evaluate().isNotEmpty &&
                tester.widget<TextButton>(button).onPressed != null,
          );
          await tester.ensureVisible(button);
          await tester.pump();
          await tester.tap(button);
          await tester.pump();
          await _until(
            tester,
            () =>
                tester.widget<TextButton>(button).onPressed != null &&
                find.byType(LinearProgressIndicator).evaluate().isEmpty,
          );
        }

        Future<UploadBatch> current() async =>
            (await _native(tester, repository.listUploadBatches)).single;
        await tap(itemKey);
        var saved = await current();
        expect(saved.items.first.userPaused, true);
        expect(saved.items.first.state, PublishState.paused);
        expect(saved.items.last.userPaused, false);
        await tap(batchKey);
        expect((await current()).paused, true);
        await tap(batchKey);
        saved = await current();
        expect(saved.paused, false);
        expect(saved.items.first.userPaused, true);
        expect(saved.items.first.state, PublishState.paused);
        expect(saved.items.last.state, PublishState.waiting);
        await tap(batchKey);
        await tap(itemKey);
        saved = await current();
        expect(saved.paused, true);
        expect(saved.items.first.userPaused, false);
        expect(saved.items.first.state, PublishState.paused);
        expect(find.text('本项暂停已解除；整批仍暂停，暂不派发。'), findsOneWidget);
        await tap(batchKey);
        saved = await current();
        expect(saved.items.every((item) => !item.userPaused), true);
        expect(
          saved.items.every((item) => item.state == PublishState.waiting),
          true,
        );
        expect(saved.items.every((item) => item.attemptCount == 0), true);
        expect(queue.networkAllowed, false);
        expect(adapter.calls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'UT-084 OPS-002 failed task batch and real attempt navigate exact diagnostic scope without network',
    (tester) async {
      _size(tester, 1280);
      final sandbox = await _native(
        tester,
        () => Directory.systemTemp.createTemp('imagehost-task-diagnostic-'),
      );
      final repository = await _native(
        tester,
        () => LibraryRepository.open(
          Directory('${sandbox.path}/library'),
          secretStore: TestSecrets(),
        ),
      );
      final adapter = _NoNetworkAdapter(
        ImageHostService.catbox,
        verified: true,
      );
      final queue = UploadCoordinator(
        initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
        LibraryUploadQueueStore(repository),
        adapters: [adapter],
      );
      final session = LibrarySession(repository, const [], uploads: queue);
      final container = ProviderContainer(
        overrides: [librarySessionProvider.overrideWith((_) async => session)],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await _native(tester, session.close);
        await _native(tester, () => sandbox.delete(recursive: true));
      });
      final fixture = await _native(tester, () async {
        final bytes = img.encodePng(img.Image(width: 3, height: 3));
        final asset = (await repository.importResource(
          PlatformResource(
            displayName: '诊断关联合成图.png',
            openRead: () => Stream.value(bytes),
          ),
        )).asset!;
        final target = await repository.saveTarget(
          service: ImageHostService.catbox,
          alias: '本机合成目标',
          anonymous: false,
          credential: 'SyntheticAccountFixture0123456789',
        );
        final first = await repository.enqueueUploads(
          intentId: 'diagnostic-first',
          assetIds: [asset.id],
          targetIds: [target],
          allowOriginalMetadata: true,
        );
        final execution = (await repository.beginUploadAttempt(
          first.items.single.id,
        ))!;
        try {
          await repository.finishUploadAttempt(
            execution,
            const ProviderUploadFailure(
              UploadFailureKind.formatUnsupported,
              UploadDeliveryEvidence.notSent,
            ),
            accumulatedRunning: Duration.zero,
          );
        } finally {
          await execution.release();
        }
        final second = await repository.enqueueUploads(
          intentId: 'diagnostic-second',
          assetIds: [asset.id],
          targetIds: [target],
          allowOriginalMetadata: true,
          forceAgain: true,
        );
        await repository.recordDiagnostic(
          DiagnosticEvent(
            id: '00000000-0000-4000-8000-000000000084',
            occurredAt: DateTime.now().toUtc(),
            kind: DiagnosticKind.upload,
            level: DiagnosticLevel.error,
            code: 'test.task.failed',
            summary: '当前批次真实尝试诊断',
            recoveryAction: '核对尝试记录',
            batchId: first.id,
            attemptId: execution.attemptId,
          ),
        );
        await repository.recordDiagnostic(
          DiagnosticEvent(
            id: '00000000-0000-4000-8000-000000000085',
            occurredAt: DateTime.now().toUtc(),
            kind: DiagnosticKind.upload,
            level: DiagnosticLevel.info,
            code: 'test.task.other',
            summary: '其他批次诊断',
            recoveryAction: '查看其他批次',
            batchId: second.id,
          ),
        );
        return (first, execution.attemptId);
      });
      expect(
        (await _native(
          tester,
          repository.listUploadBatches,
        )).firstWhere((batch) => batch.id == fixture.$1.id).items.single.state,
        PublishState.failed,
      );
      await _mount(tester, container);
      await _until(
        tester,
        () =>
            find
                .byKey(ValueKey('tasks-diagnostics-${fixture.$1.id}'))
                .evaluate()
                .isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      final batchButton = find.byKey(
        ValueKey('tasks-diagnostics-${fixture.$1.id}'),
      );
      await tester.ensureVisible(batchButton);
      await tester.tap(batchButton);
      await tester.pump();
      await _until(
        tester,
        () =>
            find.byKey(const Key('diagnostics-total')).evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('diagnostics-batch')))
            .controller!
            .text,
        fixture.$1.id,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('diagnostics-attempt')))
            .controller!
            .text,
        isEmpty,
      );
      await tester.scrollUntilVisible(
        find.byKey(
          const Key('diagnostic-00000000-0000-4000-8000-000000000084'),
        ),
        180,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('diagnostics-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('当前批次真实尝试诊断'), findsOneWidget);
      expect(find.text('其他批次诊断'), findsNothing);
      expect(queue.networkAllowed, isFalse);
      expect(adapter.calls, 0);
      Navigator.of(tester.element(find.byType(DiagnosticsScreen))).pop();
      await _until(
        tester,
        () => find
            .byType(DiagnosticsScreen, skipOffstage: false)
            .evaluate()
            .isEmpty,
      );
      final attemptsButton = find.byKey(
        ValueKey('tasks-attempts-${fixture.$1.items.single.id}'),
      );
      await tester.ensureVisible(attemptsButton);
      await tester.tap(attemptsButton);
      // A second click while the real SQL read is pending must not own another dialog.
      await tester.tap(attemptsButton);
      await tester.pump();
      final attemptButton = find.byKey(
        ValueKey('tasks-attempt-diagnostics-${fixture.$2}'),
      );
      await _until(tester, () => attemptButton.evaluate().isNotEmpty);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining(fixture.$2),
        ),
        findsOneWidget,
      );
      await tester.tap(attemptButton);
      await tester.pump(const Duration(milliseconds: 400));
      await _until(
        tester,
        () =>
            find.byKey(const Key('diagnostics-total')).evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('diagnostics-batch')))
            .controller!
            .text,
        fixture.$1.id,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('diagnostics-attempt')))
            .controller!
            .text,
        fixture.$2,
      );
      final scoped = await _native(
        tester,
        () => repository.loadDiagnostics(
          query: DiagnosticQuery(batchId: fixture.$1.id, attemptId: fixture.$2),
        ),
      );
      expect(
        scoped.items.every(
          (event) =>
              event.batchId == fixture.$1.id && event.attemptId == fixture.$2,
        ),
        isTrue,
      );
      expect(
        scoped.items.any(
          (event) => event.id == '00000000-0000-4000-8000-000000000084',
        ),
        isTrue,
      );
      expect(find.textContaining('当前筛选共 ${scoped.total} 条'), findsOneWidget);
      expect(queue.networkAllowed, isFalse);
      expect(adapter.calls, 0);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'AT-003 partial upload $width empty large text and no implicit network permission',
      (tester) async {
        _size(tester, width);
        final sandbox = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('imagehost-upload-empty-'),
        ))!;
        final repository = (await tester.runAsync(
          () => LibraryRepository.open(
            Directory('${sandbox.path}/library'),
            secretStore: TestSecrets(),
          ),
        ))!;
        final adapter = _NoNetworkAdapter(
          ImageHostService.catbox,
          verified: true,
        );
        final queue = UploadCoordinator(
          initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
          LibraryUploadQueueStore(repository),
          adapters: [adapter],
        );
        final session = LibrarySession(repository, const [], uploads: queue);
        final container = ProviderContainer(
          overrides: [
            librarySessionProvider.overrideWith((_) async => session),
          ],
        );
        addTearDown(() async {
          container.dispose();
          await _native(tester, session.close);
          await tester.runAsync(() => sandbox.delete(recursive: true));
        });
        await _mount(tester, container, scale: 1.6);
        await _until(
          tester,
          () =>
              find.byType(LinearProgressIndicator).evaluate().isEmpty &&
              find.text('还没有上传任务。').evaluate().isNotEmpty,
        );
        expect(find.text('还没有已确认结果。'), findsOneWidget);
        expect(find.text('没有可选原图。'), findsOneWidget);
        expect(find.text('没有可用的处理结果。请先在处理工作台确认结果。'), findsNothing);
        expect(queue.networkAllowed, isFalse);
        expect(adapter.calls, 0);
        expect((await _native(tester, repository.listUploadBatches)), isEmpty);
        await tester.ensureVisible(find.text('已确认处理结果'));
        await tester.tap(find.text('已确认处理结果'));
        await tester.pump();
        expect(find.text('没有可用的处理结果。请先在处理工作台确认结果。'), findsOneWidget);
        final submit = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '确认并入队'),
        );
        expect(submit.onPressed, isNull);
        await tester.ensureVisible(find.text('允许本次会话网络上传'));
        await tester.tap(find.text('允许本次会话网络上传'));
        await tester.pump();
        expect(find.text('允许本次会话网络上传？'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('允许本次会话网络上传？'), findsNothing);
        expect(queue.networkAllowed, isFalse);
        expect(adapter.calls, 0);
        await tester.ensureVisible(find.text('还没有已确认结果。'));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'UT-094 AT-003 partial original privacy guard UUID multi-target capability wait and durable reopen',
    (tester) async {
      _size(tester, 1280);
      final sandbox = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('imagehost-upload-widget-'),
      ))!;
      final root = Directory('${sandbox.path}/library');
      final secrets = TestSecrets();
      var repository = (await tester.runAsync(
        () => LibraryRepository.open(root, secretStore: secrets),
      ))!;
      final bytes = img.encodePng(img.Image(width: 2, height: 2));
      final asset = (await _native(
        tester,
        () => repository.importResource(
          PlatformResource(
            displayName: '合成原图.png',
            openRead: () => Stream.value(bytes),
          ),
        ),
      )).asset!;
      final first = await _native(
        tester,
        () => repository.saveTarget(
          service: ImageHostService.catbox,
          alias: '同名目标',
          anonymous: false,
          credential: 'SyntheticAccountFixture0123456789',
          selectedByDefault: true,
        ),
      );
      final second = await _native(
        tester,
        () => repository.saveTarget(
          service: ImageHostService.catbox,
          alias: '同名目标',
          anonymous: false,
          credential: 'SyntheticAccountFixture0123456789',
          selectedByDefault: false,
        ),
      );
      final adapter = _NoNetworkAdapter(ImageHostService.catbox);
      var session = LibrarySession(
        repository,
        const [],
        uploads: UploadCoordinator(
          initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
          LibraryUploadQueueStore(repository),
          adapters: [adapter],
        ),
      );
      var container = ProviderContainer(
        overrides: [librarySessionProvider.overrideWith((_) async => session)],
      );
      addTearDown(() async {
        container.dispose();
        await _native(tester, session.close);
        await tester.runAsync(() => sandbox.delete(recursive: true));
      });
      await _mount(tester, container);
      await _until(
        tester,
        () =>
            find.byKey(ValueKey('upload-target-$first')).evaluate().isNotEmpty,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(ValueKey('upload-target-$first')),
            )
            .value,
        isTrue,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(ValueKey('upload-target-$second')),
            )
            .value,
        isFalse,
      );
      expect(session.uploads.networkAllowed, isFalse);
      await tester.tap(find.text('图库原图'));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(ValueKey('upload-source-${asset.id}')),
      );
      await tester.tap(find.byKey(ValueKey('upload-source-${asset.id}')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(ValueKey('upload-target-$second')));
      await tester.tap(find.byKey(ValueKey('upload-target-$second')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认并入队'))
            .onPressed,
        isNull,
      );
      expect((await _native(tester, repository.listUploadBatches)), isEmpty);
      await tester.ensureVisible(find.text('我确认上传原图，可能包含位置、设备等元数据'));
      await tester.tap(find.text('我确认上传原图，可能包含位置、设备等元数据'));
      await tester.pump();
      await tester.ensureVisible(find.text('确认并入队'));
      await tester.tap(find.text('确认并入队'));
      await _until(
        tester,
        () => find.textContaining('总计 2').evaluate().isNotEmpty,
      );
      final initial = (await _native(
        tester,
        repository.listUploadBatches,
      )).single;
      expect(initial.items.map((i) => i.target.id).toSet(), {first, second});
      expect(
        initial.items.every((i) => i.input.referenceId == asset.id),
        isTrue,
      );
      expect(adapter.calls, 0);
      expect(session.uploads.networkAllowed, isFalse);
      await tester.ensureVisible(find.text('允许本次会话网络上传'));
      await tester.tap(find.text('允许本次会话网络上传'));
      await tester.pump();
      expect(find.text('允许本次会话网络上传？'), findsOneWidget);
      expect(session.uploads.networkAllowed, isFalse);
      await tester.tap(find.text('允许上传'));
      await _until(
        tester,
        () => find.text('服务精确大小及格式限制尚未核验，暂不能派发。').evaluate().isNotEmpty,
      );
      expect(adapter.calls, 0);
      final waiting = (await _native(
        tester,
        repository.listUploadBatches,
      )).single;
      expect(
        waiting.items.every(
          (i) =>
              i.state == PublishState.waiting &&
              i.waitReason == QueueWaitReason.capabilityUnknown,
        ),
        isTrue,
      );
      // Reload never silently adds a newly configured default UUID.
      final added = await _native(
        tester,
        () => repository.saveTarget(
          service: ImageHostService.catbox,
          alias: '后加默认目标',
          anonymous: false,
          credential: 'SyntheticAccountFixture0123456789',
          selectedByDefault: true,
        ),
      );
      await _until(
        tester,
        () =>
            find.byKey(ValueKey('upload-target-$added')).evaluate().isNotEmpty,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(ValueKey('upload-target-$added')),
            )
            .value,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
      // Navigating away detaches UI only; a session-level service still exists.
      expect(session.uploads.networkAllowed, isTrue);
      container.dispose();
      await _native(tester, session.close);
      repository = await _native(
        tester,
        () => LibraryRepository.open(root, secretStore: secrets),
      );
      session = LibrarySession(
        repository,
        const [],
        uploads: UploadCoordinator(
          initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
          LibraryUploadQueueStore(repository),
          adapters: [adapter],
        ),
      );
      container = ProviderContainer(
        overrides: [librarySessionProvider.overrideWith((_) async => session)],
      );
      await _mount(tester, container);
      await _until(
        tester,
        () => find.textContaining('总计 2').evaluate().isNotEmpty,
      );
      expect(session.uploads.networkAllowed, isFalse);
      expect(
        (await _native(tester, repository.listUploadBatches)).single.id,
        initial.id,
      );
      expect(adapter.calls, 0);
      // A genuine read failure retains the last valid batch instead of an empty default.
      await _native(tester, session.close);
      await tester.tap(find.byTooltip('刷新上传资料'));
      await _until(
        tester,
        () => find.text('上传资料读取失败，保留上次有效列表；请重试。').evaluate().isNotEmpty,
      );
      expect(find.textContaining('总计 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'AT-003 partial upload initial load error gives retry and no fake data',
    (tester) async {
      _size(tester, 390);
      final pending = Completer<LibrarySession>();
      final container = ProviderContainer(
        overrides: [librarySessionProvider.overrideWith((_) => pending.future)],
      );
      addTearDown(container.dispose);
      await _mount(tester, container);
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      pending.completeError(StateError('synthetic-private-error-never-shown'));
      await _until(
        tester,
        () => find.text('上传资料读取失败，保留上次有效列表；请重试。').evaluate().isNotEmpty,
      );
      expect(
        find.textContaining('synthetic-private-error-never-shown'),
        findsNothing,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '刷新上传资料',
              ),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认并入队'))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
