import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/app.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/gallery_query.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:material_ui/material_ui.dart';

import '../test/core/secret_store_test.dart' show MemorySecretStore;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'IT-003/004 partial Windows gallery remote intersection, local evidence refresh, result removal and reopen',
    (tester) async {
      final sandbox = await Directory.systemTemp.createTemp(
        'imagehost-gallery-remote-engine-',
      );
      final root = Directory('${sandbox.path}/library');
      final accountSecrets = MemorySecretStore();
      var repository = await LibraryRepository.open(
        root,
        secretStore: accountSecrets,
      );
      ProviderContainer? container;
      final boundary = GlobalKey();
      Future<void> until(bool Function() ready) async {
        for (var i = 0; i < 200; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (ready()) return;
        }
        fail('Windows gallery did not finish its real local refresh');
      }

      try {
        final picture = img.Image(width: 110, height: 70);
        for (final pixel in picture) {
          pixel.setRgb(40 + pixel.x, 80 + pixel.y, 190);
        }
        final asset = (await repository.importResource(
          PlatformResource(
            displayName: '本机远程关联.png',
            openRead: () => Stream.value(img.encodePng(picture)),
          ),
        )).asset!;
        final category = await repository.createCategory('窗口验证');
        await repository.updateOrganization(
          [asset.id],
          setCategory: true,
          categoryId: category.id,
        );
        final target = await repository.saveTarget(
          service: ImageHostService.catbox,
          alias: '窗口历史目标',
          anonymous: false,
          credential: 'SyntheticAccountFixture0123456789',
        );
        final session = LibrarySession(repository, const []);
        container = ProviderContainer(
          overrides: [
            librarySessionProvider.overrideWith((_) async => session),
          ],
        );
        container
            .read(galleryQueryProvider.notifier)
            .replace(
              GalleryQuery(
                categoryId: category.id,
                remoteTargetId: target,
                uploadFilter: GalleryUploadFilter.failed,
              ),
            );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(key: boundary, child: const ImageHostApp()),
          ),
        );
        await until(
          () => container!.read(galleryProvider).asData?.value.total == 0,
        );
        expect(find.text('本机远程关联.png'), findsNothing);
        final batch = await repository.enqueueUploads(
          intentId: 'windows-gallery-local-evidence',
          assetIds: [asset.id],
          targetIds: [target],
          allowOriginalMetadata: true,
        );
        final execution = (await repository.beginUploadAttempt(
          batch.items.single.id,
        ))!;
        try {
          await repository.authorizeUploadRequest(execution.attemptId);
          // Controlled provider evidence; this test performs no HTTP request.
          await repository.finishUploadAttempt(
            execution,
            const ProviderUploadFailure(
              UploadFailureKind.formatUnsupported,
              UploadDeliveryEvidence.confirmedRejected,
            ),
            accumulatedRunning: Duration.zero,
          );
        } finally {
          await execution.release();
        }
        await until(
          () => container!.read(galleryProvider).asData?.value.total == 1,
        );
        expect(find.text('本机远程关联.png'), findsOneWidget);
        container
            .read(galleryQueryProvider.notifier)
            .replace(
              GalleryQuery(
                categoryId: category.id,
                remoteTargetId: target,
                uploadFilter: GalleryUploadFilter.confirmed,
                sort: GallerySort.uploaded,
              ),
            );
        await until(
          () => container!.read(galleryProvider).asData?.value.total == 0,
        );
        final confirmation = await repository.enqueueUploads(
          intentId: 'windows-gallery-confirmation',
          assetIds: [asset.id],
          targetIds: [target],
          allowOriginalMetadata: true,
          forceAgain: true,
        );
        final confirmed = (await repository.beginUploadAttempt(
          confirmation.items.single.id,
        ))!;
        try {
          await repository.authorizeUploadRequest(confirmed.attemptId);
          await repository.finishUploadAttempt(
            confirmed,
            ProviderUploadSuccess(
              service: ImageHostService.catbox,
              remoteId: 'gallery.png',
              directUrl: Uri.parse('https://files.catbox.moe/gallery.png'),
            ),
            accumulatedRunning: Duration.zero,
          );
        } finally {
          await confirmed.release();
        }
        await until(
          () =>
              container!
                  .read(galleryProvider)
                  .asData
                  ?.value
                  .items
                  .singleOrNull
                  ?.confirmedRemoteResultCount ==
              1,
        );
        expect(find.text('本机远程关联.png'), findsOneWidget);
        expect((await repository.listGalleryRemoteTargets()).single.id, target);
        expect(
          session.existingUploads,
          isNull,
          reason: 'Reading gallery evidence must not start the network actor.',
        );
        final visibleAsset = container
            .read(galleryProvider)
            .requireValue
            .items
            .single;
        final preview = await container.read(
          assetPreviewProvider(visibleAsset).future,
        );
        expect(preview.thumbnail, isNotNull);
        expect(await preview.thumbnail!.exists(), isTrue);
        await until(
          () => tester
              .widgetList<RawImage>(find.byType(RawImage))
              .any((image) => image.image != null),
        );
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final screenshot = await render.toImage(pixelRatio: 1);
        try {
          final bytes = await screenshot.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final output = File(
            '${Directory.current.path}/build/validation/windows-gallery-remote.png',
          );
          await output.parent.create(recursive: true);
          await output.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
        } finally {
          screenshot.dispose();
        }
        final results = await repository.listUploadResults();
        await repository.removeLocalLinkResults([
          results.single.id,
        ], confirmLocalRemoval: true);
        await until(
          () => container!.read(galleryProvider).asData?.value.total == 0,
        );
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        container = null;
        await session.close();
        repository = await LibraryRepository.open(
          root,
          secretStore: accountSecrets,
        );
        final reopened = await repository.listAssets(
          query: GalleryQuery(
            categoryId: category.id,
            remoteTargetId: target,
            uploadFilter: GalleryUploadFilter.failed,
          ),
        );
        expect(reopened.items.single.id, asset.id);
        expect(reopened.items.single.lastConfirmedUploadAt, isNull);
        expect(reopened.items.single.confirmedRemoteResultCount, 0);
        expect(
          await (await repository.originalFor(reopened.items.single)).length(),
          asset.version.byteCount,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        container?.dispose();
        await repository.close();
        await sandbox.delete(recursive: true);
      }
    },
  );
}
