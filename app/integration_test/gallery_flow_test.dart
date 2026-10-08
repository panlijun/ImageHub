import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/app.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/gallery/presentation/original_preview_screen.dart';
import 'package:imagehost/platform/import_gateway.dart';
import 'package:material_ui/material_ui.dart';

class FixtureGateway extends ImportGateway {
  FixtureGateway(this.resources);
  final List<PlatformResource> resources;
  @override
  Future<List<PlatformResource>> pickFiles() async => resources;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'IT-001/002 Windows engine: import, original preview, independent copy, restart, failure',
    (tester) async {
      final sandbox = await Directory.systemTemp.createTemp(
        'imagehost_engine_',
      );
      final root = Directory('${sandbox.path}/library');
      final source = File('${sandbox.path}/实际照片.png');
      final picture = img.Image(width: 800, height: 520);
      for (final pixel in picture) {
        pixel.setRgb(pixel.x * 255 ~/ 800, pixel.y * 255 ~/ 520, 180);
      }
      await source.writeAsBytes(img.encodePng(picture), flush: true);
      final gateway = FixtureGateway([
        PlatformResource.file(source),
        PlatformResource(
          displayName: '损坏图片.jpg',
          openRead: () => Stream.value([1, 2, 3]),
        ),
        PlatformResource.file(source),
      ]);
      final boundaryKey = GlobalKey();
      var container = ProviderContainer(
        overrides: [
          libraryLocationProvider.overrideWithValue(() async => root),
          importGatewayProvider.overrideWithValue(gateway),
        ],
      );
      LibrarySession? currentSession;
      Future<void> showApp() => tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(key: boundaryKey, child: const ImageHostApp()),
        ),
      );
      Future<void> until(Finder finder) async {
        for (var i = 0; i < 200; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (finder.evaluate().isNotEmpty) return;
        }
        fail('Timeout waiting for $finder');
      }

      Future<void> untilAbsent(Finder finder) async {
        for (var i = 0; i < 200; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (finder.evaluate().isEmpty) return;
        }
        fail('Timeout draining route $finder');
      }

      try {
        await showApp();
        await until(find.text('图库还是空的'));
        final firstSession = await container.read(
          librarySessionProvider.future,
        );
        currentSession = firstSession;
        await tester.tap(find.byKey(const Key('import-files')));
        await until(find.textContaining('导入结束：1 已保存'));
        expect(find.text('实际照片.png'), findsOneWidget);
        expect(find.textContaining('1 重复'), findsOneWidget);
        expect(find.textContaining('1 未保存'), findsOneWidget);
        final repository = firstSession.repository;
        final before = (await repository.listAssets()).items.single;
        expect((await repository.originalFor(before)).path, isNot(source.path));
        await source.delete();
        await tester.tap(find.text('实际照片.png'));
        await until(find.text('本机副本可用'));
        final previewButton = find.byKey(const Key('desktop-original-preview'));
        await tester.ensureVisible(previewButton);
        await tester.tap(previewButton);
        final originalImage = find.descendant(
          of: find.byType(OriginalPreviewScreen),
          matching: find.byWidgetPredicate(
            (widget) => widget is RawImage && widget.image != null,
          ),
        );
        await until(originalImage);
        final originalPreview = tester.widget<RawImage>(originalImage);
        expect(
          [originalPreview.image!.width, originalPreview.image!.height],
          [800, 520],
        );
        expect(repository.processingScheduler.activeCount, 1);
        expect(find.byType(InteractiveViewer), findsOneWidget);
        await tester.tap(find.byKey(const Key('original-preview-back')));
        await untilAbsent(find.byType(OriginalPreviewScreen));
        await until(find.text('本机副本可用'));
        expect(find.byKey(const Key('original-preview-back')), findsNothing);
        expect(repository.processingScheduler.activeCount, 0);
        await tester.pump(const Duration(seconds: 1));
        final render =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final screenshot = File(
          '${Directory.current.path}/build/validation/windows-gallery.png',
        );
        await screenshot.parent.create(recursive: true);
        await screenshot.writeAsBytes(png!.buffer.asUint8List(), flush: true);
        image.dispose();
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await firstSession.close();
        currentSession = null;
        container = ProviderContainer(
          overrides: [
            libraryLocationProvider.overrideWithValue(() async => root),
            importGatewayProvider.overrideWithValue(FixtureGateway(const [])),
          ],
        );
        await showApp();
        await until(find.text('实际照片.png'));
        final reopenedSession = await container.read(
          librarySessionProvider.future,
        );
        currentSession = reopenedSession;
        final reopened = reopenedSession.repository;
        final after = (await reopened.listAssets()).items.single;
        expect(after.id, before.id);
        expect(after.version, before.version);
        expect(
          await (await reopened.originalFor(after)).length(),
          before.version.byteCount,
        );
        expect(find.text('图库还是空的'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await reopenedSession.close();
      } finally {
        await tester.pumpWidget(const SizedBox());
        currentSession ??= container.read(librarySessionProvider).asData?.value;
        container.dispose();
        await currentSession?.close();
        expect(
          sandbox.parent.absolute.path,
          Directory.systemTemp.absolute.path,
        );
        await sandbox.delete(recursive: true);
      }
    },
  );
}
