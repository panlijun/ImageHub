import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/app.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  // Desktop A must remain the desktop layout even in a narrow window. Flutter
  // widget tests otherwise default to Android independent of the host OS.
  const desktop = TargetPlatformVariant({TargetPlatform.windows});

  testWidgets('DAT-001 loading disables import without creating empty data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pending = Completer<LibrarySession>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          librarySessionProvider.overrideWith((ref) => pending.future),
        ],
        child: const ImageHostApp(),
      ),
    );
    await tester.pump();
    expect(find.text('正在打开本机图库…'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('import-files')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('图库还是空的'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, variant: desktop);

  testWidgets('DAT-001 load failure remains failure and provides retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          librarySessionProvider.overrideWith(
            (ref) =>
                Future.error(const LibraryOpenException('此图库版本不兼容，原数据已保留。')),
          ),
        ],
        child: const ImageHostApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('图库打开失败'), findsOneWidget);
    expect(find.text('重试打开'), findsOneWidget);
    expect(find.text('图库还是空的'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('import-files')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, variant: desktop);

  for (final size in [
    const Size(1280, 850),
    const Size(390, 844),
    const Size(760, 600),
  ]) {
    testWidgets('AT-001 partial: real empty library at ${size.width} width', (
      tester,
    ) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('imagehost_widget_'),
      ))!;
      final repository = await tester.runAsync(
        () => LibraryRepository.open(root),
      );
      final container = ProviderContainer(
        overrides: [
          librarySessionProvider.overrideWith(
            (ref) => Future.value(LibrarySession(repository!, const [])),
          ),
        ],
      );
      await tester.runAsync(() => container.read(galleryProvider.future));
      addTearDown(() async {
        container.dispose();
        await repository!.close();
        await root.delete(recursive: true);
      });
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ImageHostApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('图库还是空的'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('import-files')))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }, variant: desktop);
  }
}
