import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/app.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/platform/import_gateway.dart';
import 'package:material_ui/material_ui.dart';

class _MobileFixtureGateway extends ImportGateway {
  _MobileFixtureGateway(this.resources);
  final List<PlatformResource> resources;
  @override
  Future<List<PlatformResource>> pickFiles() async => resources;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'IT-001 partial Windows engine with M1 layout: real import, favorite and restart',
    (tester) async {
      // Android visual platform on a Windows engine is not Android device evidence.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await binding.setSurfaceSize(const Size(390, 844));
      final sandbox = await Directory.systemTemp.createTemp(
        'imagehost_m1_engine_',
      );
      final root = Directory('${sandbox.path}/library');
      final source = File('${sandbox.path}/真实导入.png');
      final picture = img.Image(width: 600, height: 500);
      for (final pixel in picture) {
        pixel.setRgb(pixel.x * 190 ~/ 600 + 30, pixel.y * 130 ~/ 500 + 65, 160);
      }
      await source.writeAsBytes(img.encodePng(picture), flush: true);
      final gateway = _MobileFixtureGateway([
        PlatformResource.file(source),
        PlatformResource(
          displayName: '损坏.jpg',
          openRead: () => Stream.value([1, 2, 3]),
        ),
        PlatformResource.file(source),
      ]);
      final boundary = GlobalKey();
      LibraryRepository? currentRepository;
      var container = ProviderContainer(
        overrides: [
          libraryLocationProvider.overrideWithValue(() async => root),
          importGatewayProvider.overrideWithValue(gateway),
        ],
      );
      Future<void> showApp() => tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(key: boundary, child: const ImageHostApp()),
        ),
      );
      Future<void> until(Finder finder) async {
        for (var attempt = 0; attempt < 250; attempt++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (finder.evaluate().isNotEmpty) return;
        }
        fail('Timed out waiting for $finder');
      }

      Future<void> capture(String name) async {
        await tester.pump(const Duration(milliseconds: 500));
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final screenshot = await render.toImage(pixelRatio: 1);
        final bytes = await screenshot.toByteData(
          format: ui.ImageByteFormat.png,
        );
        final output = File(
          '${Directory.current.path}/build/validation/$name.png',
        );
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
        screenshot.dispose();
      }

      try {
        await showApp();
        await until(find.text('把第一张图片放进来'));
        await tester.tap(find.byKey(const Key('import-files')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('import-source-files')));
        await until(find.textContaining('导入结束：1 已保存'));
        expect(find.textContaining('1 重复'), findsOneWidget);
        expect(find.textContaining('1 未保存'), findsOneWidget);
        final repository = (await container.read(librarySessionProvider.future))
            .repository;
        currentRepository = repository;
        final before = (await repository.listAssets()).items.single;
        await source.delete();
        await tester.tap(find.byKey(ValueKey('mobile-asset-${before.id}')));
        await until(find.text('本机副本可用'));
        await tester.tap(find.byKey(const Key('mobile-favorite')));
        await until(find.byTooltip('取消收藏'));
        await tester.ensureVisible(find.byKey(const Key('mobile-organize')));
        await tester.tap(find.byKey(const Key('mobile-organize')));
        await until(find.byKey(const Key('organization-save')));
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (tester
                  .widget<TextField>(find.byKey(const Key('organization-tags')))
                  .enabled ==
              true) {
            break;
          }
        }
        await tester.enterText(
          find.byKey(const Key('organization-tags')),
          '旅行，工作',
        );
        await tester.tap(find.byKey(const Key('organization-save')));
        await until(find.widgetWithText(Chip, '旅行'));
        expect(
          (await repository.getAsset(before.id))!.tags.map((tag) => tag.name),
          ['旅行', '工作'],
        );
        await capture('windows-engine-m1-detail');
        await tester.tap(find.byKey(const Key('mobile-detail-back')));
        await tester.pumpAndSettle();
        await capture('windows-engine-m1-gallery');
        expect((await repository.getAsset(before.id))!.favorite, true);
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await repository.close();
        currentRepository = null;
        container = ProviderContainer(
          overrides: [
            libraryLocationProvider.overrideWithValue(() async => root),
            importGatewayProvider.overrideWithValue(
              _MobileFixtureGateway(const []),
            ),
          ],
        );
        await showApp();
        await until(find.text('真实导入.png'));
        final reopened = (await container.read(librarySessionProvider.future))
            .repository;
        currentRepository = reopened;
        final after = (await reopened.listAssets()).items.single;
        expect(after.id, before.id);
        expect(after.version, before.version);
        expect(after.deviceCopy, before.deviceCopy);
        expect(after.favorite, true);
        expect(after.tags.map((tag) => tag.name), ['旅行', '工作']);
        expect(
          await (await reopened.originalFor(after)).length(),
          before.version.byteCount,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await currentRepository?.close();
        await binding.setSurfaceSize(null);
        debugDefaultTargetPlatformOverride = null;
        await sandbox.delete(recursive: true);
      }
    },
  );
}
