import 'package:imagehost/core/network_state.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:imagehost/app.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/platform/system_secret_store.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/processing/application/processing_coordinator.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/upload/application/upload_coordinator.dart';
import 'package:imagehost/features/upload/data/library_upload_queue_store.dart';
import 'package:imagehost/features/upload/data/provider_adapters.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/queue_policy.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqlite3/sqlite3.dart';

import '../test/core/upload_pipeline_test.dart' show ControlledUploadTransport;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'IT-004 partial Windows engine enqueue actual file transport fixture secure result and reopen',
    (tester) async {
      final sandbox = await Directory.systemTemp.createTemp(
        'imagehost-upload-engine-',
      );
      final root = Directory('${sandbox.path}/library');
      final protected = SystemSecretStore();
      var repository = await LibraryRepository.open(
        root,
        secretStore: protected,
      );
      LibrarySession? session;
      ProviderContainer? container;
      final boundary = GlobalKey();
      try {
        final bytes = img.encodePng(img.Image(width: 9, height: 7));
        final asset = (await repository.importResource(
          PlatformResource(
            displayName: '引擎验证图片.png',
            openRead: () => Stream.value(bytes),
          ),
        )).asset!;
        final output = await ProcessingCoordinator(repository).process(
          [asset.id],
          (inputs) => ProcessingRequest(
            operation: ProcessingOperation.compress,
            mode: ProcessingMode.sizeFirst,
            inputs: inputs,
            longestSide: 4,
          ),
          displayName: '引擎确认输出.png',
        );
        await repository.saveTarget(
          service: ImageHostService.catbox,
          alias: '个人图床',
          anonymous: false,
          credential: 'SyntheticAccountFixture0123456789',
          selectedByDefault: true,
        );
        await repository.saveTarget(
          service: ImageHostService.imgbb,
          alias: '个人图床',
          anonymous: false,
          selectedByDefault: true,
          credential: 'synthetic-windows-upload-key',
          persistence: CredentialPersistence.session,
        );
        final transport = ControlledUploadTransport(false);
        final limits = ProviderUploadLimits(
          maximumBytes: 1000000,
          formats: {'png'},
        );
        final queue = UploadCoordinator(
          initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
          LibraryUploadQueueStore(repository),
          adapters: [
            CatboxAdapter(limits: limits, transportFactory: () => transport),
            ImgBBAdapter(limits: limits, transportFactory: () => transport),
          ],
        );
        session = LibrarySession(repository, const [], uploads: queue);
        container = ProviderContainer(
          overrides: [
            librarySessionProvider.overrideWith((_) async => session!),
          ],
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
          () =>
              taskEntry.evaluate().isNotEmpty &&
              tester.widget<ListTile>(taskEntry).onTap != null,
        );
        await tester.tap(taskEntry);
        final source = find.byKey(ValueKey('upload-source-${output.id}'));
        await _until(
          tester,
          () =>
              source.evaluate().isNotEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        expect(transport.requests, isEmpty);
        expect(queue.networkAllowed, isFalse);
        await tester.ensureVisible(source);
        await tester.tap(source);
        await tester.pump();
        final submit = find.widgetWithText(FilledButton, '确认并入队');
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await _until(
          tester,
          () => find.textContaining('等待本次会话网络授权').evaluate().isNotEmpty,
        );
        expect((await repository.listUploadBatches()).single.items.length, 2);
        expect(transport.requests, isEmpty);
        // Only controlled adapters are installed in this test. Clicking permission
        // does not send a socket request to a real provider or use real user data.
        final permission = find.text('允许本次会话网络上传');
        await tester.ensureVisible(permission);
        await tester.tap(permission);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.widgetWithText(FilledButton, '允许上传'));
        await _until(
          tester,
          () =>
              find.textContaining('全部成功').evaluate().isNotEmpty &&
              queue.activeCount == 0,
        );
        expect(transport.requests.length, 2);
        final confirmed = await repository.listUploadResults();
        expect(confirmed.length, 2);
        expect(
          confirmed
              .singleWhere((r) => r.target.service == ImageHostService.imgbb)
              .managementAvailable,
          isTrue,
        );
        expect(
          find.textContaining('synthetic-windows-upload-key'),
          findsNothing,
        );
        expect(find.textContaining('managementToken0123456789'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('普通结果'));
        await tester.pump(const Duration(milliseconds: 300));
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final picture = await render.toImage(pixelRatio: 1);
        try {
          final png = await picture.toByteData(format: ui.ImageByteFormat.png);
          final artifact = File(
            '${Directory.current.path}/build/validation/windows-upload-tasks.png',
          );
          await artifact.parent.create(recursive: true);
          await artifact.writeAsBytes(png!.buffer.asUint8List(), flush: true);
        } finally {
          picture.dispose();
        }
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        container = null;
        await session.close();
        session = null;
        repository = await LibraryRepository.open(root, secretStore: protected);
        expect(
          (await repository.listUploadBatches()).single.summary.state,
          BatchState.succeeded,
        );
        expect((await repository.listUploadResults()).length, 2);
        // Actual Windows protected backend, addressed through this test DB's UUID.
        await repository.close();
        final database = sqlite3.open('${root.path}/library.sqlite');
        try {
          final refs = database.select(
            'SELECT secret_reference FROM remote_upload_results WHERE secret_reference IS NOT NULL',
          );
          expect(refs.length, 1);
          for (final row in refs) {
            final reference = row['secret_reference'] as String;
            expect(
              await protected.read(reference),
              ControlledUploadTransport.management,
            );
          }
        } finally {
          database.close();
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        container?.dispose();
        await session?.close();
        await repository.close();
        // Clean only UUIDs allocated by this isolated new test library.
        if (await File('${root.path}/library.sqlite').exists()) {
          final database = sqlite3.open('${root.path}/library.sqlite');
          try {
            final refs = <String>{
              for (final row in database.select(
                'SELECT secret_reference FROM remote_upload_results WHERE secret_reference IS NOT NULL',
              ))
                row['secret_reference'] as String,
              for (final row in database.select(
                'SELECT secret_reference FROM upload_result_operations WHERE secret_reference IS NOT NULL',
              ))
                row['secret_reference'] as String,
            };
            for (final reference in refs) {
              await protected.delete(reference);
              expect(await protected.read(reference), isNull);
            }
          } finally {
            database.close();
          }
        }
        await sandbox.delete(recursive: true);
      }
    },
  );
}

Future<void> _until(WidgetTester tester, bool Function() predicate) async {
  for (var i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (predicate()) return;
  }
  fail('Windows 引擎页面未到达预期真实状态');
}
