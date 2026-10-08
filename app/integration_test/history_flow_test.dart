import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/presentation/upload_tasks_screen.dart';
import 'package:imagehost/platform/system_secret_store.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'IT-004/007 partial Windows history clear, retained ordinary result and system secret, replay and reopen',
    (tester) async {
      final sandbox = await Directory.systemTemp.createTemp(
        'imagehost-history-engine-',
      );
      final root = Directory('${sandbox.path}/library');
      final secrets = SystemSecretStore();
      var repository = await LibraryRepository.open(root, secretStore: secrets);
      LibrarySession? session;
      ProviderContainer? container;
      final ownedReferences = <String>{};
      const management = 'https://ibb.co/history/0123456789abcdefABCDEF';
      final boundary = GlobalKey();
      Future<void> until(bool Function() ready) async {
        for (var i = 0; i < 200; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (ready()) return;
        }
        fail('Windows history view did not finish real IO');
      }

      try {
        final picture = img.Image(width: 30, height: 20);
        for (final pixel in picture) {
          pixel.setRgb(40 + pixel.x, 80 + pixel.y, 190);
        }
        final asset = (await repository.importResource(
          PlatformResource(
            displayName: 'Windows 历史保留.png',
            openRead: () => Stream.value(img.encodePng(picture)),
          ),
        )).asset!;
        final target = await repository.saveTarget(
          service: ImageHostService.imgbb,
          alias: 'Windows 历史目标',
          anonymous: false,
          credential: 'synthetic-history-session-key',
          persistence: CredentialPersistence.session,
        );
        final batch = await repository.enqueueUploads(
          intentId: 'windows-history-idempotence',
          assetIds: [asset.id],
          targetIds: [target],
          allowOriginalMetadata: true,
        );
        final execution = (await repository.beginUploadAttempt(
          batch.items.single.id,
        ))!;
        try {
          await repository.authorizeUploadRequest(execution.attemptId);
          await repository.finishUploadAttempt(
            execution,
            ProviderUploadSuccess(
              service: ImageHostService.imgbb,
              remoteId: 'history',
              directUrl: Uri.parse('https://i.ibb.co/history/fixture.png'),
              viewerUrl: Uri.parse('https://ibb.co/history'),
              managementSecret: SensitiveManagementSecret(management),
            ),
            accumulatedRunning: Duration.zero,
          );
        } finally {
          await execution.release();
        }
        final database = sqlite3.open(
          '${root.path}/library.sqlite',
          mode: OpenMode.readOnly,
        );
        late String reference;
        try {
          reference =
              database
                      .select(
                        'SELECT secret_reference FROM remote_upload_results',
                      )
                      .single['secret_reference']
                  as String;
          ownedReferences.add(reference);
        } finally {
          database.close();
        }
        expect(await secrets.read(reference), management);
        session = LibrarySession(repository, const []);
        container = ProviderContainer(
          overrides: [
            librarySessionProvider.overrideWith((_) async => session!),
          ],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(
              key: boundary,
              child: const MaterialApp(home: UploadTasksScreen()),
            ),
          ),
        );
        await until(
          () =>
              find.byType(LinearProgressIndicator).evaluate().isEmpty &&
              find.text('恢复的完成历史').evaluate().isNotEmpty,
        );
        expect(session.uploads.networkAllowed, isFalse);
        await tester.ensureVisible(
          find.byKey(const Key('upload-history-select-completed')),
        );
        await tester.tap(
          find.byKey(const Key('upload-history-select-completed')),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const Key('upload-history-clear-selected')),
        );
        await until(() => find.text('清理已选历史？').evaluate().isNotEmpty);
        expect(find.text('可清理 1 项；另有 0 项保留。'), findsOneWidget);
        await tester.tap(find.byKey(const Key('upload-history-confirm-clear')));
        await until(
          () => find.text('已清理 1 项历史，保留 0 项。图片与普通结果保留。').evaluate().isNotEmpty,
        );
        expect(find.text('还没有上传任务。'), findsOneWidget);
        expect(await secrets.read(reference), management);
        expect(await repository.listUploadResults(), hasLength(1));
        final replay = await repository.enqueueUploads(
          intentId: 'windows-history-idempotence',
          assetIds: [asset.id],
          targetIds: [target],
          allowOriginalMetadata: true,
        );
        expect(replay.id, batch.id);
        expect(replay.items, isEmpty);
        await tester.ensureVisible(find.text('还没有上传任务。'));
        await tester.pump();
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final screenshot = await render.toImage(pixelRatio: 1);
        try {
          final bytes = await screenshot.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final output = File(
            '${Directory.current.path}/build/validation/windows-upload-history.png',
          );
          await output.parent.create(recursive: true);
          await output.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
        } finally {
          screenshot.dispose();
        }
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        container = null;
        await session.close();
        session = null;
        repository = await LibraryRepository.open(root, secretStore: secrets);
        expect((await repository.listUploadBatches()).single.items, isEmpty);
        expect(
          (await repository.listUploadResults()).single.directUrl.toString(),
          'https://i.ibb.co/history/fixture.png',
        );
        expect(await secrets.read(reference), management);
        final reopened = (await repository.listAssets()).items.single;
        expect(reopened.id, asset.id);
        expect(
          await (await repository.originalFor(reopened)).length(),
          asset.version.byteCount,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        container?.dispose();
        if (session != null) {
          await session.close();
        } else {
          await repository.close();
        }
        for (final reference in ownedReferences) {
          await secrets.delete(reference);
        }
        await sandbox.delete(recursive: true);
      }
    },
  );
}
