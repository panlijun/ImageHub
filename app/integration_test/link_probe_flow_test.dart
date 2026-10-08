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
import 'package:imagehost/features/links/data/link_probe_gateway.dart';
import 'package:imagehost/features/links/domain/link_availability.dart';
import 'package:imagehost/features/links/presentation/link_results_screen.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';
import 'package:imagehost/platform/system_secret_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'IT-008 partial Windows explicit HEAD availability preserves real bytes history management secret and reopen',
    (tester) async {
      final sandbox = await Directory.systemTemp.createTemp(
        'imagehost-link-probe-engine-',
      );
      final root = Directory('${sandbox.path}/library');
      final secrets = SystemSecretStore();
      late LibraryRepository repository;
      LibraryRepository? repositoryToClose;
      LibrarySession? session;
      ProviderContainer? container;
      final ownedReferences = <String>{};
      final requests = <RequestOptions>[];
      final transports = <_ControlledHead>[];
      var nextStatus = 200;
      const management = 'https://ibb.co/ordinary/0123456789abcdefABCDEF';
      const displayName = 'Windows 主动检测.png';
      final boundary = GlobalKey();
      final gateway = DioLinkProbeGateway(
        transportFactory: () {
          final transport = _ControlledHead(nextStatus, requests);
          transports.add(transport);
          return transport;
        },
      );

      List<Map<String, Object?>> rows(String table) {
        final database = sqlite3.open(
          '${root.path}/library.sqlite',
          mode: OpenMode.readOnly,
        );
        try {
          return database
              .select('SELECT * FROM "$table" ORDER BY 1')
              .map((row) => Map<String, Object?>.from(row))
              .toList();
        } finally {
          database.close();
        }
      }

      void collectOwnedReferences() {
        final database = sqlite3.open(
          '${root.path}/library.sqlite',
          mode: OpenMode.readOnly,
        );
        try {
          // Read only this disposable library's opaque ownership references.
          // Include a partially committed fixture's journal, never enumerate
          // any system protected namespace or unrelated application library.
          for (final row in database.select(
            'SELECT secret_reference AS reference FROM provider_targets WHERE secret_reference IS NOT NULL '
            'UNION SELECT secret_reference FROM remote_upload_results WHERE secret_reference IS NOT NULL '
            'UNION SELECT secret_reference FROM upload_result_operations WHERE secret_reference IS NOT NULL '
            'UNION SELECT new_reference FROM credential_operations WHERE new_reference IS NOT NULL '
            'UNION SELECT old_reference FROM credential_operations WHERE old_reference IS NOT NULL',
          )) {
            ownedReferences.add(row['reference'] as String);
          }
        } finally {
          database.close();
        }
      }

      Future<void> until(bool Function() ready, String evidence) async {
        for (var i = 0; i < 160 && !ready(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(ready(), true, reason: evidence);
        expect(tester.takeException(), isNull);
      }

      Future<void> mount() async {
        session = LibrarySession(repository, const []);
        container = ProviderContainer(
          overrides: [
            librarySessionProvider.overrideWith((ref) async => session!),
            linkProbeGatewayProvider.overrideWithValue(gateway),
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
        await until(
          () => find.text(displayName).evaluate().isNotEmpty,
          'Real persisted ordinary result appears in native page',
        );
      }

      try {
        repository = await LibraryRepository.open(root, secretStore: secrets);
        repositoryToClose = repository;
        final pixels = img.encodePng(img.Image(width: 9, height: 7));
        final asset = (await repository.importResource(
          PlatformResource(
            displayName: displayName,
            openRead: () => Stream.value(pixels),
          ),
        )).asset!;
        final target = await repository.saveTarget(
          service: ImageHostService.imgbb,
          alias: 'Windows 检测历史目标',
          anonymous: false,
          credential: 'synthetic-link-probe-session-key',
          persistence: CredentialPersistence.session,
        );
        final batch = await repository.enqueueUploads(
          intentId: 'windows-link-probe-fixture',
          assetIds: [asset.id],
          targetIds: [target],
          allowOriginalMetadata: true,
        );
        final publicationId = batch.items.single.id;
        final execution = (await repository.beginUploadAttempt(publicationId))!;
        try {
          expect(
            await repository.authorizeUploadRequest(execution.attemptId),
            true,
          );
          // Synthetic upload confirmation exercises the real SQL and system
          // management-secret commit. No upload adapter or HTTP is invoked.
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
        collectOwnedReferences();
        expect(ownedReferences, hasLength(1));
        final managementReference = ownedReferences.single;
        expect(await secrets.read(managementReference), management);
        final ordinary = (await repository.listLinkResults()).items.single;
        final resultId = ordinary.id;
        expect(ordinary.availability.state, LinkAvailability.recorded);
        expect(ordinary.availability.lastAccessibleAt, isNull);
        final original = File(
          p.join(
            root.path,
            rows('device_copies').single['relative_path'] as String,
          ),
        );
        expect(await original.readAsBytes(), pixels);
        final protectedTables = {
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
        const observationFields = {
          'link_state',
          'link_reason',
          'link_checked_utc',
          'last_accessible_utc',
          'probe_generation',
          'probe_http_status',
        };
        Map<String, Object?> ordinaryIdentity() => Map.fromEntries(
          rows('remote_upload_results').single.entries
              .where((entry) => !observationFields.contains(entry.key)),
        );
        final ordinaryBefore = ordinaryIdentity();

        Future<void> expectPreserved() async {
          for (final entry in protectedTables.entries) {
            expect(rows(entry.key), entry.value, reason: entry.key);
          }
          expect(ordinaryIdentity(), ordinaryBefore);
          expect((await repository.listLinkResults()).total, 1);
          expect(await repository.getAsset(asset.id), isNotNull);
          expect(await original.readAsBytes(), pixels);
          expect(await secrets.read(managementReference), management);
          expect(
            (await repository.listUploadAttempts(publicationId)).single.id,
            execution.attemptId,
          );
        }

        await mount();
        expect(requests, isEmpty);
        expect(transports, isEmpty);
        expect(find.text('链接已记录，尚未主动检测'), findsOneWidget);

        Future<void> probe(int status, String expectedLabel) async {
          nextStatus = status;
          final before = requests.length;
          final button = find.byKey(ValueKey('links-probe-$resultId'));
          await until(
            () =>
                button.evaluate().isNotEmpty &&
                tester.widget<TextButton>(button).onPressed != null,
            'Single-item explicit probe is ready',
          );
          await tester.ensureVisible(button);
          await tester.pump();
          await tester.tap(button);
          await until(
            () => find.text('主动检测已选链接？').evaluate().isNotEmpty,
            'Network confirmation appears before request',
          );
          expect(requests, hasLength(before));
          expect(find.textContaining('不会自动重试、定期访问、删除历史或重新上传'), findsOneWidget);
          expect(find.textContaining('0123456789abcdefABCDEF'), findsNothing);
          await tester.tap(find.text('确认本次网络检测'));
          await until(
            () =>
                requests.length == before + 1 &&
                find.text(expectedLabel).evaluate().isNotEmpty &&
                button.evaluate().isNotEmpty &&
                tester.widget<TextButton>(button).onPressed != null,
            'Explicit HEAD completed and SQL-backed status rendered',
          );
          expect(requests, hasLength(before + 1));
          final request = requests.last;
          expect(request.method, 'HEAD');
          expect(
            request.uri,
            Uri.parse('https://i.ibb.co/ordinary/windows.png'),
          );
          expect(request.followRedirects, false);
          expect(request.maxRedirects, 0);
          expect(request.data, isNull);
          expect(
            request.headers.keys.map((key) => key.toLowerCase()),
            isNot(contains('authorization')),
          );
          expect(
            request.headers.keys.map((key) => key.toLowerCase()),
            isNot(contains('cookie')),
          );
          expect(
            request.headers.values.join(),
            isNot(contains('synthetic-link-probe-session-key')),
          );
          expect(transports.last.closed, true);
          await expectPreserved();
        }

        await probe(200, '可访问（检测时）');
        final accessible =
            (await repository.listLinkResults()).items.single.availability;
        expect(accessible.state, LinkAvailability.accessible);
        expect(accessible.reason, LinkProbeReason.reachable);
        expect(accessible.httpStatus, 200);
        expect(accessible.checkedAt, isNotNull);
        expect(accessible.lastAccessibleAt, accessible.checkedAt);
        final lastAccessible = accessible.lastAccessibleAt;

        await probe(404, '未能确认');
        final unknown =
            (await repository.listLinkResults()).items.single.availability;
        expect(unknown.state, LinkAvailability.unknown);
        expect(unknown.reason, LinkProbeReason.unconfirmed);
        expect(unknown.httpStatus, 404);
        expect(unknown.lastAccessibleAt, lastAccessible);
        expect(find.textContaining('上次可访问：'), findsOneWidget);

        await probe(410, '远端已删除（服务报告）');
        final deleted =
            (await repository.listLinkResults()).items.single.availability;
        expect(deleted.state, LinkAvailability.deleted);
        expect(deleted.reason, LinkProbeReason.gone);
        expect(deleted.httpStatus, 410);
        expect(deleted.lastAccessibleAt, lastAccessible);
        expect(rows('remote_upload_results').single['probe_generation'], 3);
        final observedBeforeClose = rows('remote_upload_results');
        final oldOwnerPlan = await repository.prepareLinkProbe([resultId]);

        await tester.ensureVisible(
          find.byKey(ValueKey('links-state-$resultId')),
        );
        await tester.pump();
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final picture = await render.toImage(pixelRatio: 1);
        try {
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final artifact = File(
            '${Directory.current.path}/build/validation/windows-link-probe.png',
          );
          await artifact.parent.create(recursive: true);
          await artifact.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
        } finally {
          picture.dispose();
        }

        await tester.pumpWidget(const SizedBox());
        container!.dispose();
        container = null;
        await session!.close();
        session = null;
        repository = await LibraryRepository.open(root, secretStore: secrets);
        repositoryToClose = repository;
        expect(rows('remote_upload_results'), observedBeforeClose);
        await expectLater(
          repository.beginLinkProbe(
            oldOwnerPlan,
            resultId,
            confirmNetwork: true,
          ),
          throwsA(isA<UploadQueueFailure>()),
        );
        expect(rows('remote_upload_results'), observedBeforeClose);
        await expectPreserved();
        await mount();
        await until(
          () => find.text('远端已删除（服务报告）').evaluate().isNotEmpty,
          'Native page reopens persisted deleted observation',
        );
        expect(find.textContaining('上次可访问：'), findsOneWidget);
        expect(
          requests,
          hasLength(3),
          reason: 'Reopen never automatically probes',
        );
        expect(transports, hasLength(3));
        expect(await secrets.read(managementReference), management);
      } finally {
        try {
          await tester.pumpWidget(const SizedBox());
        } finally {
          container?.dispose();
          try {
            // A fixture interrupted after secret write may still own a journal
            // UUID. A failed open has not run this fixture's secret operations.
            if (repositoryToClose != null) collectOwnedReferences();
          } finally {
            try {
              await session?.close();
            } finally {
              try {
                await repositoryToClose?.close();
              } finally {
                for (final reference in ownedReferences) {
                  await secrets.delete(reference);
                  expect(await secrets.read(reference), isNull);
                }
                final target = p.normalize(p.absolute(sandbox.path));
                final temporary = p.normalize(
                  p.absolute(Directory.systemTemp.path),
                );
                if (!p.isWithin(temporary, target) ||
                    !p
                        .basename(target)
                        .startsWith('imagehost-link-probe-engine-')) {
                  throw StateError(
                    'Test cleanup target is outside its private temporary directory',
                  );
                }
                await Directory(target).delete(recursive: true);
              }
            }
          }
        }
      }
    },
  );
}

/// Real native page/storage; every HTTP exchange is this controlled boundary.
/// No IOHttpClientAdapter, external service or real credential is contacted.
final class _ControlledHead implements HttpClientAdapter {
  _ControlledHead(this.status, this.requests);
  final int status;
  final List<RequestOptions> requests;
  bool closed = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    expect(options.method, 'HEAD');
    expect(requestStream, isNull);
    return ResponseBody(
      const Stream<Uint8List>.empty(),
      status,
      headers: {
        Headers.contentTypeHeader: [status == 200 ? 'image/png' : 'text/html'],
      },
    );
  }

  @override
  void close({bool force = false}) {
    expect(force, true);
    closed = true;
  }
}
