import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/links/application/link_transfer_coordinator.dart';
import 'package:imagehost/features/links/domain/link_query.dart';
import 'package:imagehost/features/links/domain/link_transfer.dart';
import 'package:imagehost/features/links/presentation/link_results_screen.dart';
import 'package:imagehost/features/upload/domain/link_format.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/platform/system_secret_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'IT-004/007 partial Windows ordinary link query, local transfer retry, protected removal and reopen',
    (tester) async {
      final sandbox = await Directory.systemTemp.createTemp(
        'imagehost-links-engine-',
      );
      final root = Directory('${sandbox.path}/library');
      final secrets = SystemSecretStore();
      var repository = await LibraryRepository.open(root, secretStore: secrets);
      LibrarySession? session;
      ProviderContainer? container;
      final ownedReferences = <String>{};
      const management = 'https://ibb.co/ordinary/0123456789abcdefABCDEF';
      final boundary = GlobalKey();
      try {
        final asset = (await repository.importResource(
          PlatformResource(
            displayName: 'Windows 普通结果.png',
            openRead: () =>
                Stream.value(img.encodePng(img.Image(width: 9, height: 7))),
          ),
        )).asset!;
        final target = await repository.saveTarget(
          service: ImageHostService.imgbb,
          alias: 'Windows 历史目标',
          anonymous: false,
          credential: 'synthetic-links-session-key',
          persistence: CredentialPersistence.session,
        );
        final batch = await repository.enqueueUploads(
          intentId: 'windows-link-fixture',
          assetIds: [asset.id],
          targetIds: [target],
          allowOriginalMetadata: true,
        );
        final execution = (await repository.beginUploadAttempt(
          batch.items.single.id,
        ))!;
        try {
          expect(
            await repository.authorizeUploadRequest(execution.attemptId),
            isTrue,
          );
          // Synthetic provider evidence only; no adapter or HTTP request is run.
          await repository.finishUploadAttempt(
            execution,
            ProviderUploadSuccess(
              service: ImageHostService.imgbb,
              remoteId: 'ordinary',
              directUrl: Uri.parse('https://i.ibb.co/ordinary/windows.png'),
              viewerUrl: Uri.parse('https://ibb.co/ordinary'),
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
        try {
          for (final row in database.select(
            'SELECT secret_reference FROM remote_upload_results WHERE secret_reference IS NOT NULL',
          )) {
            ownedReferences.add(row['secret_reference'] as String);
          }
        } finally {
          database.close();
        }
        expect(ownedReferences.length, 1);
        expect(await secrets.read(ownedReferences.single), management);
        final results = await repository.listLinkResults(
          query: LinkResultQuery(
            keyword: 'windows',
            targetId: target,
            service: ImageHostService.imgbb,
          ),
        );
        expect(results.total, 1);
        final id = results.items.single.id;
        final plan = await repository.prepareVisibleLinkCopy([
          id,
        ], UploadLinkFormat.markdown);
        final gateway = _LocalGateway();
        final coordinator = LinkTransferCoordinator(repository, gateway);
        expect(
          (await coordinator.copy(plan)).status,
          LinkTransferStatus.failed,
        );
        gateway.fail = false;
        expect(
          (await coordinator.copy(plan)).status,
          LinkTransferStatus.copied,
        );
        expect(gateway.lastText, plan.batch.text);
        expect(gateway.lastText, isNot(contains('0123456789abcdefABCDEF')));
        expect(
          (await repository.listUploadAttempts(batch.items.single.id)).length,
          1,
        );
        session = LibrarySession(repository, const []);
        container = ProviderContainer(
          overrides: [
            librarySessionProvider.overrideWith((ref) async => session!),
            linkTransferGatewayProvider.overrideWithValue(gateway),
          ],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: RepaintBoundary(
                key: boundary,
                child: const LinkResultsScreen(),
              ),
            ),
          ),
        );
        for (
          var i = 0;
          i < 160 && find.text('Windows 普通结果.png').evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('Windows 普通结果.png'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final picture = await render.toImage(pixelRatio: 1);
        try {
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final artifact = File(
            '${Directory.current.path}/build/validation/windows-links.png',
          );
          await artifact.parent.create(recursive: true);
          await artifact.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
        } finally {
          picture.dispose();
        }
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        container = null;
        await session.close();
        session = null;
        repository = await LibraryRepository.open(root, secretStore: secrets);
        expect((await repository.listLinkResults()).total, 1);
        expect(await secrets.read(ownedReferences.single), management);
        final removal = await repository.removeLocalLinkResults([
          id,
        ], confirmLocalRemoval: true);
        expect(removal.removed, 1);
        expect(removal.cleanupPending, 0);
        expect(await secrets.read(ownedReferences.single), isNull);
        expect(
          (await repository.listUploadBatches()).single.items.single.resultId,
          isNull,
        );
        expect(
          (await repository.listUploadAttempts(batch.items.single.id)).length,
          1,
        );
        await repository.close();
        repository = await LibraryRepository.open(root, secretStore: secrets);
        expect((await repository.listLinkResults()).total, 0);
        expect(await repository.getAsset(asset.id), isNotNull);
        expect(await secrets.read(ownedReferences.single), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        container?.dispose();
        await session?.close();
        await repository.close();
        for (final reference in ownedReferences) {
          await secrets.delete(reference);
          expect(await secrets.read(reference), isNull);
        }
        await sandbox.delete(recursive: true);
      }
    },
  );
}

// Native rendering and protected storage are real. Clipboard/share are a
// controlled boundary here; this is not a system clipboard/share PT receipt.
class _LocalGateway implements LinkTransferGateway {
  bool fail = true;
  String? lastText;
  @override
  Future<LinkTransferStatus> copyText(String text) async {
    lastText = text;
    return fail ? LinkTransferStatus.failed : LinkTransferStatus.copied;
  }

  @override
  Future<LinkTransferStatus> shareText(
    String text, {
    LinkShareAnchor? anchor,
  }) async => LinkTransferStatus.unconfirmed;
}
