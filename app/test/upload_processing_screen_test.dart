import 'dart:async';

import 'core/secret_store_test.dart' show MemorySecretStore;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/network_state.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/settings/domain/device_settings.dart';
import 'package:imagehost/features/upload/application/upload_coordinator.dart';
import 'package:imagehost/features/upload/application/upload_processing_coordinator.dart';
import 'package:imagehost/features/upload/data/library_upload_queue_store.dart';
import 'package:imagehost/features/upload/data/provider_adapters.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/queue_policy.dart';
import 'package:imagehost/features/upload/domain/upload_processing_models.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';
import 'package:imagehost/features/upload/presentation/upload_tasks_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

class _NoRequestAdapter implements ProviderAdapter {
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
    throw StateError('未授权的测试网络调用。');
  }
}

Future<T> _native<T>(WidgetTester tester, Future<T> Function() action) async {
  var done = false;
  T? result;
  Object? failure;
  await tester.runAsync(() async {
    unawaited(
      action().then(
        (value) {
          result = value;
          done = true;
        },
        onError: (Object error) {
          failure = error;
          done = true;
        },
      ),
    );
  });
  for (var i = 0; i < 400 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done, isTrue, reason: '真实资料库或像素 IO 必须结束');
  if (failure != null) throw failure!;
  return result as T;
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 400; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (ready()) return;
  }
  fail('上传前处理页面未达到真实预期状态。');
}

Future<void> _deleteOwnedTemp(Directory directory) async {
  final temp = p.normalize(await Directory.systemTemp.resolveSymbolicLinks());
  final owned = p.normalize(await directory.resolveSymbolicLinks());
  if (!p.isAbsolute(owned) ||
      !p.isWithin(temp, owned) ||
      !p.basename(owned).startsWith('imagehost-upload-processing-widget-')) {
    throw StateError('拒绝删除未确认归属的 widget 测试目录。');
  }
  await Directory(owned).delete(recursive: true);
}

void _size(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _mount(WidgetTester tester, ProviderContainer container) =>
    tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: const UploadTasksScreen(),
        ),
      ),
    );

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'UT-046 UT-062 AT-003 partial $width textScale2 automatic UI freezes UUID source recipe and applies defaults once without requests',
      (tester) async {
        _size(tester, width);
        final sandbox = await _native(
          tester,
          () => Directory.systemTemp.createTemp(
            'imagehost-upload-processing-widget-',
          ),
        );
        final repository = await _native(
          tester,
          () => LibraryRepository.open(
            Directory(p.join(sandbox.path, 'library')),
            secretStore: MemorySecretStore(),
          ),
        );
        final fixture = await _native(tester, () async {
          final pixels = img.Image(width: 12, height: 8);
          for (var y = 0; y < 8; y++) {
            for (var x = 0; x < 12; x++) {
              pixels.setPixelRgb(x, y, x * 19, y * 27, (x + y) * 11);
            }
          }
          final bytes = img.encodePng(pixels);
          final asset = (await repository.importResource(
            PlatformResource(
              displayName: '共同页面真实PNG.png',
              openRead: () => Stream.value(bytes),
            ),
          )).asset!;
          final targets = <String>[];
          for (var index = 0; index < 2; index++) {
            targets.add(
              await repository.saveTarget(
                service: ImageHostService.catbox,
                alias: '同名匿名目标',
                anonymous: false,
                credential: 'SyntheticAccountFixture0123456789',
                selectedByDefault: index == 0,
              ),
            );
          }
          final settings = await repository.loadSettings();
          await repository.saveSettings(
            settings,
            DeviceSettings(
              processingMode: ProcessingMode.sizeFirst,
              longestSide: 11,
              quality: 82,
            ),
            defaultTargetIds: [targets.first],
          );
          final adapter = _NoRequestAdapter();
          final local = UploadProcessingCoordinator(repository);
          final queue = UploadCoordinator(
            LibraryUploadQueueStore(repository),
            adapters: [adapter],
            processing: local,
            initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
          );
          final session = LibrarySession(
            repository,
            const [],
            uploads: queue,
            uploadProcessing: local,
          );
          return (asset, targets, adapter, session);
        });
        final session = fixture.$4;
        final container = ProviderContainer(
          overrides: [
            librarySessionProvider.overrideWith((_) async => session),
          ],
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          container.dispose();
          await _native(tester, session.close);
          await _native(tester, () => _deleteOwnedTemp(sandbox));
        });
        await _mount(tester, container);
        final source = find.byKey(ValueKey('upload-source-${fixture.$1.id}'));
        await _until(
          tester,
          () =>
              source.evaluate().isNotEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '上传前自动处理'))
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<DropdownButton<ProcessingMode>>(
                find.byKey(const Key('upload-processing-mode')),
              )
              .value,
          ProcessingMode.sizeFirst,
        );
        expect(find.text('最长边：11 像素'), findsOneWidget);
        final format = find.byKey(const Key('upload-processing-format'));
        await tester.ensureVisible(format);
        await tester.tap(format);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('JPEG').last);
        await tester.pump();
        // Use the actual slider callbacks to set exact confirmed integer values;
        // coordinate dragging cannot address every 1..16384 value deterministically.
        tester.widgetList<Slider>(find.byType(Slider)).first.onChanged!(6);
        tester.widgetList<Slider>(find.byType(Slider)).last.onChanged!(61);
        await tester.pump();
        await tester.ensureVisible(find.text('如存在透明区域，我确认使用白色背景'));
        await tester.tap(find.text('如存在透明区域，我确认使用白色背景'));
        await tester.pump();
        await tester.ensureVisible(source);
        await tester.tap(source);
        await tester.pump();
        final second = find.byKey(ValueKey('upload-target-${fixture.$2.last}'));
        await tester.ensureVisible(second);
        await tester.tap(second);
        await tester.pump();
        expect(tester.widget<CheckboxListTile>(source).value, isTrue);
        expect(tester.widget<CheckboxListTile>(second).value, isTrue);
        final added = await _native(tester, () async {
          final id = await repository.saveTarget(
            service: ImageHostService.catbox,
            alias: '稍后新增默认目标',
            anonymous: false,
            credential: 'SyntheticAccountFixture0123456789',
            selectedByDefault: true,
          );
          final settings = await repository.loadSettings();
          await repository.saveSettings(
            settings,
            DeviceSettings(
              quality: 22,
              longestSide: 2000,
              processingMode: ProcessingMode.fidelity,
            ),
            defaultTargetIds: [id],
          );
          return id;
        });
        await tester.tap(find.byTooltip('刷新上传资料'));
        await _until(
          tester,
          () =>
              find
                  .byKey(ValueKey('upload-target-$added'))
                  .evaluate()
                  .isNotEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        expect(find.text('最长边：6 像素'), findsOneWidget);
        expect(find.text('有损质量：61'), findsOneWidget);
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(ValueKey('upload-target-$added')),
              )
              .value,
          isFalse,
        );
        final submit = find.widgetWithText(FilledButton, '确认并入队');
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await _until(
          tester,
          () =>
              find.textContaining('结果已确认').evaluate().isNotEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        final job = (await _native(
          tester,
          repository.listUploadProcessingJobs,
        )).single;
        expect(job.state, UploadProcessingState.ready);
        expect(job.plan.assetIds, [fixture.$1.id]);
        expect(job.plan.versions, [fixture.$1.version]);
        expect(job.plan.recipe.longestSide, 6);
        expect(job.plan.recipe.quality, 61);
        expect(job.plan.recipe.outputFormat, ProcessingFormat.jpeg);
        await _native(tester, session.uploads.refresh);
        final batch = (await _native(
          tester,
          repository.listUploadBatches,
        )).single;
        expect(batch.items, hasLength(2));
        expect(batch.items.map((i) => i.target.id).toSet(), fixture.$2.toSet());
        for (final item in batch.items) {
          expect(item.input.kind, UploadInputKind.processed);
          expect(item.input.referenceId, job.outputId);
          expect(item.input.version.width, 6);
          expect(item.input.version.height, 4);
          expect(item.attemptCount, 0);
          expect(item.state, PublishState.waiting);
          expect(item.waitReason, QueueWaitReason.network);
        }
        final frozen = job.plan.canonical;
        tester.widgetList<Slider>(find.byType(Slider)).first.onChanged!(9);
        tester.widgetList<Slider>(find.byType(Slider)).last.onChanged!(44);
        await tester.pump();
        expect(
          (await _native(
            tester,
            repository.listUploadProcessingJobs,
          )).single.plan.canonical,
          frozen,
        );
        expect((await _native(tester, repository.listOutputs)), hasLength(1));
        expect(session.uploads.networkAllowed, isFalse);
        expect(fixture.$3.calls, 0);
        expect(
          tester
              .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, '允许本次会话网络上传'),
              )
              .value,
          isFalse,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  for (final animated in [false, true]) {
    testWidgets(
      'UT-023 UT-026 UT-046 UT-062 AT-003 partial automatic ${animated ? 'animation' : 'transparent JPEG'} failure never falls back to original',
      (tester) async {
        _size(tester, 390);
        final sandbox = await _native(
          tester,
          () => Directory.systemTemp.createTemp(
            'imagehost-upload-processing-widget-',
          ),
        );
        final repository = await _native(
          tester,
          () => LibraryRepository.open(
            Directory(p.join(sandbox.path, 'library')),
            secretStore: MemorySecretStore(),
          ),
        );
        final fixture = await _native(tester, () async {
          final pixels = img.Image(width: 10, height: 8, numChannels: 4);
          img.fill(pixels, color: img.ColorRgba8(240, 20, 80, 90));
          if (animated) {
            final other = img.Image(width: 10, height: 8, numChannels: 4);
            img.fill(other, color: img.ColorRgba8(10, 80, 240, 255));
            pixels.addFrame(other);
          }
          final bytes = animated
              ? img.encodeGif(pixels)
              : img.encodePng(pixels);
          final asset = (await repository.importResource(
            PlatformResource(
              displayName: animated ? '真实两帧动画.gif' : '真实透明区域.png',
              openRead: () => Stream.value(bytes),
            ),
          )).asset!;
          final target = await repository.saveTarget(
            service: ImageHostService.catbox,
            alias: '匿名目标',
            anonymous: false,
            credential: 'SyntheticAccountFixture0123456789',
            selectedByDefault: true,
          );
          final adapter = _NoRequestAdapter();
          final local = UploadProcessingCoordinator(repository);
          final queue = UploadCoordinator(
            LibraryUploadQueueStore(repository),
            adapters: [adapter],
            processing: local,
            initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
          );
          return (
            asset,
            target,
            adapter,
            LibrarySession(
              repository,
              const [],
              uploads: queue,
              uploadProcessing: local,
            ),
          );
        });
        final container = ProviderContainer(
          overrides: [
            librarySessionProvider.overrideWith((_) async => fixture.$4),
          ],
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          container.dispose();
          await _native(tester, fixture.$4.close);
          await _native(tester, () => _deleteOwnedTemp(sandbox));
        });
        await _mount(tester, container);
        final source = find.byKey(ValueKey('upload-source-${fixture.$1.id}'));
        await _until(
          tester,
          () =>
              source.evaluate().isNotEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        if (!animated) {
          final format = find.byKey(const Key('upload-processing-format'));
          await tester.ensureVisible(format);
          await tester.tap(format);
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.text('JPEG').last);
          await tester.pump();
        } else {
          expect(fixture.$1.version.frameCount, 2);
        }
        await tester.ensureVisible(source);
        await tester.tap(source);
        await tester.pump();
        await tester.ensureVisible(find.text('确认并入队'));
        await tester.tap(find.text('确认并入队'));
        await _until(
          tester,
          () =>
              find.textContaining('处理失败，依赖已跳过').evaluate().isNotEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        final job = (await _native(
          tester,
          repository.listUploadProcessingJobs,
        )).single;
        expect(job.state, UploadProcessingState.failed);
        final item = (await _native(
          tester,
          repository.listUploadBatches,
        )).single.items.single;
        expect(item.state, PublishState.failed);
        expect(item.input.kind, UploadInputKind.original);
        expect(item.processingPending, isTrue);
        expect(item.input.referenceId, fixture.$1.id);
        expect(item.attemptCount, 0);
        expect(
          await _native(tester, () => repository.beginUploadAttempt(item.id)),
          isNull,
        );
        expect(
          await _native(tester, () => repository.listUploadAttempts(item.id)),
          isEmpty,
        );
        expect(fixture.$4.uploads.networkAllowed, isFalse);
        expect(fixture.$3.calls, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}
