import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart' hide DiagnosticLevel;
import 'package:path/path.dart' as p;

import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/diagnostics/domain/diagnostic_models.dart';
import 'package:imagehost/features/diagnostics/presentation/diagnostics_screen.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/platform/export_gateway.dart';

class _FixtureDirectory extends ExportGateway {
  const _FixtureDirectory(this.directory);
  final Directory directory;
  @override
  Future<Directory?> pickDirectory() async => directory;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'IT-006 partial Windows diagnostic SQL reopen export re-sanitizes and clear preserves permanent image',
    (tester) async {
      final sandbox = await Directory.systemTemp.createTemp(
        'imagehost-diagnostics-engine-',
      );
      final root = Directory(p.join(sandbox.path, 'library'));
      final output = await Directory(p.join(sandbox.path, 'output')).create();
      LibraryRepository? repository;
      LibrarySession? session;
      ProviderContainer? container;
      final boundary = GlobalKey();
      Future<void> until(bool Function() ready) async {
        for (var i = 0; i < 200 && !ready(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(ready(), isTrue);
        expect(tester.takeException(), isNull);
      }

      Future<void> tap(String key) async {
        final finder = find.byKey(ValueKey(key));
        await tester.scrollUntilVisible(
          finder,
          200,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 30,
        );
        await tester.ensureVisible(finder);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(finder);
        await tester.pump();
      }

      Future<void> mount() async {
        session = LibrarySession(repository!, const []);
        container = ProviderContainer(
          overrides: [
            librarySessionProvider.overrideWith((ref) async => session!),
            diagnosticExportGatewayProvider.overrideWithValue(
              _FixtureDirectory(output),
            ),
          ],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container!,
            child: MaterialApp(
              home: RepaintBoundary(
                key: boundary,
                child: const DiagnosticsScreen(),
              ),
            ),
          ),
        );
        await until(
          () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
      }

      Future<void> close() async {
        await tester.pumpWidget(const SizedBox());
        container?.dispose();
        container = null;
        await session?.close();
        session = null;
        await repository?.close();
        repository = null;
      }

      try {
        repository = await LibraryRepository.open(root);
        final picture = img.encodePng(img.Image(width: 7, height: 5));
        final imported = await repository!.importResource(
          PlatformResource(
            displayName: '永久副本.png',
            openRead: () => Stream.value(picture),
          ),
        );
        final asset = imported.asset!;
        final original = await repository!.originalFor(asset);
        const secret = 'synthetic-diagnostic-private-key-0123456789';
        await repository!.recordDiagnostic(
          DiagnosticEvent(
            id: '11111111-1111-4111-8111-111111111111',
            occurredAt: DateTime.now().toUtc(),
            kind: DiagnosticKind.system,
            level: DiagnosticLevel.error,
            code: 'fixture.recovery',
            summary: '需要核查 $secret',
            recoveryAction: '保留资料库，重开后核查。',
            details: {
              'sourcePath': r'C:\private-source\original.png',
              'userhash': 'private-userhash',
              'rawBody': 'private-body',
            },
          ),
        );
        await repository!.saveTarget(
          service: ImageHostService.catbox,
          alias: '会话配置',
          anonymous: false,
          credential: secret,
          persistence: CredentialPersistence.session,
        );
        final preserved = (await repository!.loadDiagnostics()).items
            .map((event) => event.toJson())
            .toList();
        expect(preserved, hasLength(3));
        await mount();
        await close();
        repository = await LibraryRepository.open(root);
        expect(
          (await repository!.loadDiagnostics()).items
              .map((event) => event.toJson())
              .toList(),
          preserved,
        );
        await mount();
        await tap('diagnostics-export');
        await until(
          () => find
              .byKey(const Key('diagnostics-confirm'))
              .evaluate()
              .isNotEmpty,
        );
        expect(find.textContaining('已冻结 3 条'), findsOneWidget);
        await tester.tap(find.byKey(const Key('diagnostics-confirm')));
        await tester.pump(const Duration(milliseconds: 350));
        final viewport = find
            .descendant(
              of: find.byKey(const Key('diagnostics-list')),
              matching: find.byType(Scrollable),
            )
            .first;
        tester.state<ScrollableState>(viewport).position.jumpTo(0);
        await tester.pump();
        await until(() => find.textContaining('已导出 3 条').evaluate().isNotEmpty);
        final files = await output
            .list()
            .where((entry) => entry is File)
            .cast<File>()
            .toList();
        expect(files, hasLength(1));
        final exported = await files.single.readAsString();
        for (final forbidden in [
          secret,
          'private-source',
          'private-userhash',
          'private-body',
        ]) {
          expect(exported, isNot(contains(forbidden)));
        }
        expect((jsonDecode(exported) as Map)['eventCount'], 3);
        final render =
            boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        await tester.pump(const Duration(milliseconds: 400));
        final screenshot = await render.toImage(pixelRatio: 1);
        try {
          final data = await screenshot.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final directory = Directory(
            p.join(Directory.current.parent.path, 'docs', 'validation'),
          );
          await directory.create(recursive: true);
          await File(p.join(directory.path, 'windows-diagnostics.png'))
              .writeAsBytes(data!.buffer.asUint8List(), flush: true);
        } finally {
          screenshot.dispose();
        }
        await tap('diagnostics-clear');
        await until(
          () => find
              .byKey(const Key('diagnostics-confirm'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.tap(find.byKey(const Key('diagnostics-confirm')));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.scrollUntilVisible(
          find.byKey(const Key('diagnostics-empty')),
          200,
          scrollable: viewport,
          maxScrolls: 30,
        );
        expect(find.byKey(const Key('diagnostics-empty')), findsOneWidget);
        expect((await repository!.listAssets()).items.single.id, asset.id);
        expect(await original.readAsBytes(), picture);
        await close();
        repository = await LibraryRepository.open(root);
        expect((await repository!.loadDiagnostics()).total, 0);
        expect((await repository!.listAssets()).items.single.id, asset.id);
        expect(
          await (await repository!.originalFor(asset)).readAsBytes(),
          picture,
        );
      } finally {
        await close();
        final absolute = p.normalize(p.absolute(sandbox.path));
        if (!p.isWithin(
              p.normalize(p.absolute(Directory.systemTemp.path)),
              absolute,
            ) ||
            !p.basename(absolute).startsWith('imagehost-diagnostics-engine-')) {
          throw StateError('Unsafe fixture cleanup');
        }
        await Directory(absolute).delete(recursive: true);
      }
    },
  );
}
