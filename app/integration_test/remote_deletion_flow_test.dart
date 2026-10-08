import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/links/data/remote_deletion_gateway.dart';
import 'package:imagehost/features/links/domain/remote_deletion.dart';
import 'package:imagehost/features/links/presentation/link_results_screen.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'IT-008 partial Windows explicit single deletion unknown preserves bytes and ordinary evidence across reopen',
    (tester) async {
      final sandbox = await Directory.systemTemp.createTemp(
        'imagehost-remote-delete-engine-',
      );
      final root = Directory(p.join(sandbox.path, 'library'));
      LibraryRepository? repository;
      LibrarySession? session;
      ProviderContainer? container;
      final boundary = GlobalKey();
      var calls = 0, closes = 0;
      const credential = 'synthetic-windows-delete-session-credential';
      final gateway = DioRemoteDeletionGateway(
        transportFactory: () =>
            _ControlledDeletion(() => calls++, () => closes++, credential),
      );

      List<Map<String, Object?>> rows(String table) {
        final db = sqlite3.open(
          p.join(root.path, 'library.sqlite'),
          mode: OpenMode.readOnly,
        );
        try {
          return db
              .select('SELECT * FROM "$table" ORDER BY 1')
              .map((r) => Map<String, Object?>.from(r))
              .toList();
        } finally {
          db.close();
        }
      }

      Future<void> until(bool Function() ready) async {
        for (var i = 0; i < 200 && !ready(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          ready(),
          true,
          reason: 'Native page and actual SQLite work must settle',
        );
        expect(tester.takeException(), isNull);
      }

      Future<void> mount() async {
        session = LibrarySession(repository!, const []);
        container = ProviderContainer(
          overrides: [
            librarySessionProvider.overrideWith((_) async => session!),
            remoteDeletionGatewayProvider.overrideWithValue(gateway),
          ],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container!,
            child: MaterialApp(
              home: RepaintBoundary(
                key: boundary,
                child: const LinkResultsScreen(),
              ),
            ),
          ),
        );
        await until(() => find.text('Windows 远端删除.png').evaluate().isNotEmpty);
      }

      try {
        repository = await LibraryRepository.open(root);
        final bytes = img.encodePng(img.Image(width: 9, height: 7));
        final asset = (await repository.importResource(
          PlatformResource(
            displayName: 'Windows 远端删除.png',
            openRead: () => Stream.value(bytes),
          ),
        )).asset!;
        final target = await repository.saveTarget(
          service: ImageHostService.catbox,
          alias: 'Windows 单文件目标',
          anonymous: false,
          credential: credential,
          persistence: CredentialPersistence.session,
        );
        final batch = await repository.enqueueUploads(
          intentId: 'windows-deletion-fixture',
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
            true,
          );
          await repository.finishUploadAttempt(
            execution,
            ProviderUploadSuccess(
              service: ImageHostService.catbox,
              remoteId: 'synthetic.png',
              directUrl: Uri.parse('https://files.catbox.moe/synthetic.png'),
            ),
            accumulatedRunning: Duration.zero,
          );
        } finally {
          await execution.release();
        }
        final resultId = (await repository.listLinkResults()).items.single.id;
        final original = File(
          p.join(
            root.path,
            rows('device_copies').single['relative_path'] as String,
          ),
        );
        final preserved = {
          for (final table in [
            'assets',
            'versions',
            'device_copies',
            'upload_batches',
            'upload_publications',
            'upload_attempts',
            'upload_events',
            'provider_targets',
            'version_references',
            'file_leases',
            'upload_result_operations',
          ])
            table: rows(table),
        };
        final oldPlan = await repository.prepareRemoteDeletion(resultId);
        await mount();
        expect(calls, 0);
        final button = find.byKey(ValueKey('links-remote-delete-$resultId'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await until(() => find.text('请求远端删除这个文件？').evaluate().isNotEmpty);
        expect(find.textContaining(credential), findsNothing);
        await tester.tap(find.widgetWithText(TextButton, '取消'));
        await until(() => find.text('请求远端删除这个文件？').evaluate().isEmpty);
        expect(calls, 0);
        expect(await repository.listRemoteDeletions(), isEmpty);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await until(() => find.text('请求远端删除这个文件？').evaluate().isNotEmpty);
        await tester.ensureVisible(
          find.widgetWithText(FilledButton, '确认本次网络与远端删除'),
        );
        await tester.tap(find.widgetWithText(FilledButton, '确认本次网络与远端删除'));
        await until(
          () =>
              find
                  .byKey(ValueKey('links-remote-deletion-state-$resultId'))
                  .evaluate()
                  .isNotEmpty &&
              session!.existingRemoteDeletions?.busy == false,
        );
        expect(calls, 1);
        expect(closes, 1);
        final audit = (await repository.listRemoteDeletions()).single;
        expect(audit.state, RemoteDeletionState.unknown);
        expect(audit.httpStatus, 200);
        expect(find.textContaining('可能已生效'), findsWidgets);
        expect(find.textContaining('不会自动重试'), findsWidgets);
        for (final entry in preserved.entries) {
          expect(rows(entry.key), entry.value, reason: entry.key);
        }
        expect(await original.readAsBytes(), bytes);
        expect((await repository.listLinkResults()).total, 1);
        final auditSql = rows('library_metadata')
            .where((r) => (r['key'] as String).startsWith('remote_delete_v1/'))
            .single;
        expect((auditSql['value'] as String).contains(credential), false);
        expect((auditSql['value'] as String).contains('https://'), false);
        await tester.ensureVisible(
          find.byKey(ValueKey('links-remote-deletion-state-$resultId')),
        );
        await tester.pump();
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final picture = await render.toImage(pixelRatio: 1);
        try {
          final png = await picture.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            p.join(
              Directory.current.path,
              'build',
              'validation',
              'windows-remote-deletion.png',
            ),
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(png!.buffer.asUint8List(), flush: true);
        } finally {
          picture.dispose();
        }
        await tester.pumpWidget(const SizedBox());
        container!.dispose();
        container = null;
        await session!.close();
        session = null;
        repository = await LibraryRepository.open(root);
        final reopened = (await repository.listRemoteDeletions()).single;
        expect(reopened.id, audit.id);
        expect(reopened.state, RemoteDeletionState.unknown);
        expect(reopened.httpStatus, 200);
        await expectLater(
          repository.beginRemoteDeletion(
            oldPlan,
            confirmNetwork: true,
            confirmRemoteDeletion: true,
          ),
          throwsA(isA<UploadQueueFailure>()),
        );
        await mount();
        await until(
          () => find
              .byKey(ValueKey('links-remote-deletion-state-$resultId'))
              .evaluate()
              .isNotEmpty,
        );
        expect(
          calls,
          1,
          reason: 'Reopen never dispatches deletion or grants credentials',
        );
        expect(await original.readAsBytes(), bytes);
        expect(await repository.getAsset(asset.id), isNotNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        container?.dispose();
        await session?.close();
        await repository?.close();
        final actual = await sandbox.resolveSymbolicLinks();
        final temporary = await Directory.systemTemp.resolveSymbolicLinks();
        if (!p.isWithin(temporary, actual) ||
            !p.basename(actual).startsWith('imagehost-remote-delete-engine-')) {
          throw StateError('Refuse cleanup outside owned temporary directory');
        }
        await Directory(actual).delete(recursive: true);
      }
    },
  );
}

final class _ControlledDeletion implements HttpClientAdapter {
  _ControlledDeletion(this.onCall, this.onClose, this.credential);
  final void Function() onCall, onClose;
  final String credential;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? source,
    Future<void>? cancelFuture,
  ) async {
    onCall();
    expect(options.method, 'POST');
    expect(options.uri, Uri.parse('https://catbox.moe/user/api.php'));
    expect(options.followRedirects, false);
    expect(options.maxRedirects, 0);
    final fields = (options.data as FormData).fields;
    expect(fields.length, 3);
    expect(fields[0].value, 'deletefiles');
    expect(fields[1].value == credential, true);
    expect(fields[2].value, 'synthetic.png');
    final bytes = await source!.fold<List<int>>(
      [],
      (all, chunk) => all..addAll(chunk),
    );
    expect(utf8.decode(bytes).contains(credential), true);
    return ResponseBody(const Stream<Uint8List>.empty(), 200);
  }

  @override
  void close({bool force = false}) {
    expect(force, true);
    onClose();
  }
}
