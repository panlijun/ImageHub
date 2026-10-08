import 'dart:io';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/app.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/processing/presentation/processing_workbench.dart';
import 'package:imagehost/platform/export_gateway.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;

class _DirectoryGateway extends ExportGateway {
  const _DirectoryGateway(this.directory);
  final Directory directory;
  @override
  Future<Directory?> pickDirectory() async => directory;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'IT-003 Windows engine actual processing/save/export conflict/restart/expiry',
    (tester) async {
      final sandbox = await Directory.systemTemp.createTemp(
        'imagehost_processing_engine_',
      );
      final root = Directory('${sandbox.path}/library');
      final target = await Directory('${sandbox.path}/export').create();
      var repository = await LibraryRepository.open(root);
      final sourceImage = img.Image(width: 80, height: 60);
      for (final pixel in sourceImage) {
        pixel.setRgb(pixel.x * 255 ~/ 80, pixel.y * 255 ~/ 60, 180);
      }
      final bytes = img.encodePng(sourceImage);
      final source = (await repository.importResource(
        PlatformResource(
          displayName: '新照片.png',
          openRead: () => Stream.value(bytes),
        ),
      )).asset!;
      var container = ProviderContainer(
        overrides: [
          librarySessionProvider.overrideWith(
            (_) async => LibrarySession(repository, const []),
          ),
          exportGatewayProvider.overrideWithValue(_DirectoryGateway(target)),
        ],
      );
      final boundary = GlobalKey();
      Future<void> show() => tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(key: boundary, child: const ImageHostApp()),
        ),
      );
      Future<void> until(bool Function() test) async {
        for (var i = 0; i < 200; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (test()) return;
        }
        fail('Actual Windows engine did not finish the expected flow');
      }

      Future<void> capture(String name) async {
        await tester.pump(const Duration(milliseconds: 200));
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = File(
          '${Directory.current.path}/build/validation/$name.png',
        );
        await output.parent.create(recursive: true);
        await output.writeAsBytes(png!.buffer.asUint8List(), flush: true);
        image.dispose();
      }

      try {
        await show();
        await until(() => find.text('新照片.png').evaluate().isNotEmpty);
        await tester.tap(find.text('图片处理'));
        await until(() => find.text('图片处理工作台').evaluate().isNotEmpty);
        await until(
          () =>
              find
                  .byKey(Key('processing-asset-${source.id}'))
                  .evaluate()
                  .isNotEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        await tester.tap(find.byKey(Key('processing-asset-${source.id}')));
        await tester.pump();
        final mode = find.byType(DropdownButtonFormField<ProcessingMode>);
        await tester.ensureVisible(mode);
        await tester.tap(mode);
        await tester.pumpAndSettle();
        await tester.tap(find.text('体积优先').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('processing-longest-side')),
          '40',
        );
        await capture('windows-processing-workbench');
        await tester.ensureVisible(find.byKey(const Key('processing-start')));
        await tester.tap(find.byKey(const Key('processing-start')));
        await until(
          () =>
              find.text('已就绪').evaluate().isNotEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        final output = (await repository.listOutputs()).single;
        expect(output.usable, true);
        expect(output.version!.width, 40);
        expect(output.version!.height, 30);
        final old = File('${target.path}/${output.displayName}');
        await old.writeAsBytes([9, 9, 9], flush: true);
        await tester.ensureVisible(find.text('导出此结果'));
        await tester.tap(find.text('导出此结果'));
        await until(() => find.textContaining('已导出').evaluate().isNotEmpty);
        expect(await old.readAsBytes(), [9, 9, 9]);
        final files = (await target.list().toList())
            .whereType<File>()
            .where((f) => !path.equals(f.path, old.path))
            .toList();
        expect(files, hasLength(1));
        expect(
          sha256.convert(await files.single.readAsBytes()).toString(),
          output.version!.sha256,
        );
        final save = find.byKey(Key('processing-save-${output.id}'));
        await tester.ensureVisible(save);
        await tester.tap(save);
        await until(
          () =>
              find.textContaining('已永久保存：').evaluate().isNotEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        await tester.ensureVisible(save);
        await capture('windows-processing-result');
        final savedVersion = (await repository.getOutput(output.id))
            .savedVersionId!;
        expect((await repository.listAssets()).total, 2);
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await repository.close();
        repository = await LibraryRepository.open(root);
        expect((await repository.listOutputs()).single.id, output.id);
        expect(
          (await repository.savedOutputOrigins(savedVersion))
              .single
              .inputs
              .single
              .version
              .id,
          source.version.id,
        );
        expect(
          (await withClock(
            Clock.fixed(output.expiresAt),
            repository.cleanupOutputs,
          )).removed,
          1,
        );
        final saved = (await repository.listAssets()).items.singleWhere(
          (a) => a.version.id == savedVersion,
        );
        expect(await repository.verifyCopy(saved), CopyAvailability.available);
        expect(
          await (await repository.originalFor(source)).readAsBytes(),
          bytes,
        );
        container = ProviderContainer(
          overrides: [
            librarySessionProvider.overrideWith(
              (_) async => LibrarySession(repository, const []),
            ),
          ],
        );
        await show();
        await until(() => find.text(saved.displayName).evaluate().isNotEmpty);
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await repository.close();
      } finally {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await repository.close();
        await sandbox.delete(recursive: true);
      }
    },
  );
}
