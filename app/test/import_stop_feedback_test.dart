import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/app.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/platform/import_gateway.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'UT-011 Windows stop feedback remains pending until actual source cleanup',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('imagehost_stop_widget_'),
      ))!;
      final repository = (await tester.runAsync(
        () => LibraryRepository.open(root),
      ))!;
      final session = (await tester.runAsync(
        () async => LibrarySession(repository, const []),
      ))!;
      final listening = Completer<void>();
      final cancelling = Completer<void>();
      final drained = Completer<void>();
      final source = StreamController<List<int>>(
        onListen: listening.complete,
        onCancel: () {
          cancelling.complete();
          return drained.future;
        },
      );
      final container = ProviderContainer(
        overrides: [
          librarySessionProvider.overrideWith((ref) async => session),
          importGatewayProvider.overrideWithValue(
            _Gateway(
              PlatformResource(
                displayName: 'waiting-source.png',
                openRead: () => source.stream,
              ),
            ),
          ),
        ],
      );
      try {
        await tester.runAsync(() => container.read(galleryProvider.future));
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const ImageHostApp(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('import-files')));
        await _until(tester, () => listening.isCompleted);
        await tester.tap(find.text('停止后续导入'));
        await _until(tester, () => cancelling.isCompleted);
        expect(find.text('正在停止，等待来源读取和本机写入结束…'), findsOneWidget);
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, '停止后续导入'))
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('import-files')))
              .onPressed,
          isNull,
        );
        expect(find.textContaining('导入结束：'), findsNothing);
        drained.complete();
        await _until(
          tester,
          () => find.textContaining('导入结束：').evaluate().isNotEmpty,
        );
        expect(find.textContaining('1 已停止。'), findsOneWidget);
        expect(find.text('正在停止，等待来源读取和本机写入结束…'), findsNothing);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('import-files')))
              .onPressed,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
        expect(
          (await tester.runAsync(() => repository.listAssets()))!.total,
          0,
        );
      } finally {
        if (!drained.isCompleted) drained.complete();
        await tester.pumpWidget(const SizedBox());
        var closed = false;
        await tester.runAsync(() async {
          unawaited(session.close().then((_) => closed = true));
        });
        await _until(tester, () => closed);
        container.dispose();
        await tester.runAsync(() => root.delete(recursive: true));
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 200 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump();
  expect(
    ready(),
    true,
    reason: 'Expected explicit IO boundary did not complete.',
  );
}

class _Gateway extends ImportGateway {
  _Gateway(this.resource);
  final PlatformResource resource;
  @override
  Future<List<PlatformResource>> pickFiles() async => [resource];
}
