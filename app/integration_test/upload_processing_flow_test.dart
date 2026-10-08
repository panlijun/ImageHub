import 'dart:io';

import '../test/core/secret_store_test.dart' show MemorySecretStore;

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/app.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/upload/domain/queue_policy.dart';
import 'package:imagehost/features/upload/domain/upload_processing_models.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';
import 'package:imagehost/platform/storage_capacity.dart';
import 'package:imagehost/platform/system_network_monitor.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

Future<void> _until(WidgetTester tester, Future<bool> Function() ready) async {
  for (var i = 0; i < 400; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (await ready()) return;
  }
  fail('Windows 自动处理真实页面或像素结果未到达预期状态。');
}

Future<void> _deleteOwnedTemp(Directory directory) async {
  final temp = p.normalize(await Directory.systemTemp.resolveSymbolicLinks());
  final owned = p.normalize(await directory.resolveSymbolicLinks());
  if (!p.isAbsolute(owned) ||
      !p.isWithin(temp, owned) ||
      !p.basename(owned).startsWith('imagehost-upload-processing-engine-')) {
    throw StateError('拒绝删除未确认归属的 Windows 测试目录。');
  }
  await Directory(owned).delete(recursive: true);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'UT-046 UT-062 IT-004 partial Windows real automatic processing UI without network authorization and same identities after reopen',
    (tester) async {
      final sandbox = await Directory.systemTemp.createTemp(
        'imagehost-upload-processing-engine-',
      );
      final root = Directory(p.join(sandbox.path, 'library'));
      final accountSecrets = MemorySecretStore();
      var repository = await LibraryRepository.open(
        root,
        secretStore: accountSecrets,
        availableStorageBytes: const StorageCapacity().availableBytes,
        publishCacheExclusive: const StorageCapacity().publishExclusive,
      );
      LibrarySession? session;
      ProviderContainer? container;
      final boundary = GlobalKey();
      try {
        final pixels = img.Image(width: 32, height: 24, numChannels: 4);
        for (var y = 0; y < pixels.height; y++) {
          for (var x = 0; x < pixels.width; x++) {
            pixels.setPixelRgba(
              x,
              y,
              x * 7,
              y * 9,
              (x + y) * 4,
              x < 16 ? 128 : 255,
            );
          }
        }
        final bytes = img.encodePng(pixels);
        final asset = (await repository.importResource(
          PlatformResource(
            displayName: 'Windows 真实透明PNG.png',
            openRead: () => Stream.value(bytes),
          ),
        )).asset!;
        final target = await repository.saveTarget(
          service: ImageHostService.catbox,
          alias: 'Windows 合成账号',
          anonymous: false,
          credential: 'SyntheticAccountFixture0123456789',
          selectedByDefault: false,
        );
        // Production local actor and adapters with isolated synthetic account
        // credentials. No real account or HTTP request is used.
        // OS route observation never probes remote hosts or grants permission.
        final opened = LibrarySession(
          repository,
          const [],
          networkMonitor: SystemNetworkMonitor(),
        );
        session = opened;
        container = ProviderContainer(
          overrides: [librarySessionProvider.overrideWith((_) async => opened)],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(key: boundary, child: const ImageHostApp()),
          ),
        );
        final taskEntry = find.ancestor(
          of: find.text('上传任务'),
          matching: find.byType(ListTile),
        );
        await _until(
          tester,
          () async =>
              taskEntry.evaluate().isNotEmpty &&
              tester.widget<ListTile>(taskEntry).onTap != null,
        );
        await tester.tap(taskEntry);
        final source = find.byKey(ValueKey('upload-source-${asset.id}'));
        final destination = find.byKey(ValueKey('upload-target-$target'));
        await _until(
          tester,
          () async =>
              source.evaluate().isNotEmpty &&
              destination.evaluate().isNotEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '上传前自动处理'))
              .selected,
          isTrue,
        );
        expect(opened.uploads.networkAllowed, isFalse);
        expect((await repository.listUploadBatches()), isEmpty);
        await tester.ensureVisible(source);
        await tester.tap(source);
        await tester.pump();
        await tester.ensureVisible(destination);
        await tester.tap(destination);
        await tester.pump();
        expect(tester.widget<CheckboxListTile>(source).value, isTrue);
        expect(tester.widget<CheckboxListTile>(destination).value, isTrue);
        final submit = find.widgetWithText(FilledButton, '确认并入队');
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await _until(tester, () async {
          final jobs = await repository.listUploadProcessingJobs();
          if (jobs.any((j) => j.state == UploadProcessingState.failed)) {
            fail('真实 Windows 上传前处理失败，不能以入队成功替代结果确认。');
          }
          return jobs.length == 1 &&
              jobs.single.state == UploadProcessingState.ready &&
              opened.existingUploadProcessing!.activeCount == 0 &&
              find.textContaining('结果已确认').evaluate().isNotEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty;
        });
        await opened.uploads.refresh();
        final job = (await repository.listUploadProcessingJobs()).single;
        final batch = (await repository.listUploadBatches()).single;
        final item = batch.items.single;
        final output = await repository.getOutput(job.outputId!);
        expect(output.usable, isTrue);
        expect(output.version!.width, 32);
        expect(output.version!.height, 24);
        expect(output.request.inputs.single.assetId, asset.id);
        expect(
          img.decodePng(await output.file!.readAsBytes())!.getPixel(2, 2).a,
          128,
        );
        expect(job.plan.assetIds, [asset.id]);
        expect(job.plan.versions, [asset.version]);
        expect(item.input.kind, UploadInputKind.processed);
        expect(item.input.referenceId, output.id);
        expect(item.input.version, output.version);
        expect(item.target.id, target);
        expect(item.state, PublishState.waiting);
        expect(item.waitReason, QueueWaitReason.network);
        expect(item.attemptCount, 0);
        expect(await repository.listUploadAttempts(item.id), isEmpty);
        expect(await repository.listUploadResults(), isEmpty);
        expect(opened.uploads.networkAllowed, isFalse);
        expect(opened.uploads.activeCount, 0);
        expect(find.textContaining('精确字节及格式能力待核验'), findsOneWidget);
        expect(
          tester
              .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, '允许本次会话网络上传'),
              )
              .value,
          isFalse,
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.textContaining('结果已确认'));
        await tester.pump(const Duration(milliseconds: 300));
        final picture =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        try {
          final png = await picture.toByteData(format: ui.ImageByteFormat.png);
          final screenshot = File(
            p.join(
              Directory.current.path,
              '..',
              'docs',
              'validation',
              'windows-upload-processing.png',
            ),
          );
          await screenshot.parent.create(recursive: true);
          await screenshot.writeAsBytes(png!.buffer.asUint8List(), flush: true);
        } finally {
          picture.dispose();
        }
        final originalOutputBytes = await output.file!.readAsBytes();
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        container = null;
        await opened.close();
        session = null;
        repository = await LibraryRepository.open(
          root,
          secretStore: accountSecrets,
          availableStorageBytes: const StorageCapacity().availableBytes,
          publishCacheExclusive: const StorageCapacity().publishExclusive,
        );
        final reopened = LibrarySession(
          repository,
          const [],
          networkMonitor: SystemNetworkMonitor(),
        );
        session = reopened;
        await reopened.existingUploadProcessing!.refresh();
        await reopened.uploads.refresh();
        final restoredJob =
            (await repository.listUploadProcessingJobs()).single;
        final restoredBatch = (await repository.listUploadBatches()).single;
        final restoredOutput = (await repository.listOutputs()).single;
        expect(restoredJob.id, job.id);
        expect(restoredJob.plan.canonical, job.plan.canonical);
        expect(restoredJob.outputId, output.id);
        expect(restoredJob.state, UploadProcessingState.ready);
        expect(restoredBatch.id, batch.id);
        expect(restoredBatch.items.single.id, item.id);
        expect(restoredBatch.items.single.input.referenceId, output.id);
        expect(restoredOutput.id, output.id);
        expect(restoredOutput.version, output.version);
        expect(await restoredOutput.file!.readAsBytes(), originalOutputBytes);
        expect(restoredBatch.items.single.attemptCount, 0);
        expect(reopened.uploads.networkAllowed, isFalse);
        expect(reopened.existingUploadProcessing!.activeCount, 0);
        expect(await repository.listUploadResults(), isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox());
        container?.dispose();
        await session?.close();
        await repository.close();
        await _deleteOwnedTemp(sandbox);
      }
    },
  );
}
