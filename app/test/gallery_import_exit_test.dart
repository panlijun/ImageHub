import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/app.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/platform/import_gateway.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'UT-011 picker stop rejects late sources and permits a fresh selection',
    (tester) async {
      final h = await _Harness.open(tester);
      try {
        await tester.tap(find.byKey(const Key('import-files')));
        await _until(tester, () => h.gateway.calls == 1);
        await tester.tap(find.text('停止后续导入'));
        await tester.pump();
        expect(find.text('正在停止，等待图片选择结束…'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('import-files')))
              .onPressed,
          isNull,
        );
        h.gateway.selections[0].complete([h.resource]);
        await _until(
          tester,
          () => find.text('已停止导入，图库没有变化。').evaluate().isNotEmpty,
        );
        expect(h.sourceOpens, 0);
        expect(
          (await tester.runAsync(() => h.repository.listAssets()))!.total,
          0,
        );
        await tester.tap(find.byKey(const Key('import-files')));
        await _until(tester, () => h.gateway.calls == 2);
        h.gateway.selections[1].complete([h.resource]);
        await _until(
          tester,
          () => find.textContaining('1 已保存').evaluate().isNotEmpty,
        );
        expect(h.sourceOpens, 1);
        expect(
          (await tester.runAsync(() => h.repository.listAssets()))!.total,
          1,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-011/IT-002 exit waits for picker and retains the existing library on reopen',
    (tester) async {
      final h = await _Harness.open(tester, seed: true);
      try {
        await tester.tap(find.byKey(const Key('import-files')));
        await _until(tester, () => h.gateway.calls == 1);
        AppExitResponse? response;
        unawaited(
          tester.binding.handleRequestAppExit().then(
            (value) => response = value,
          ),
        );
        await _pumpUi(tester);
        await tester.tap(find.text('停止并退出'));
        await _pumpUi(tester);
        expect(response, isNull);
        expect(find.text('正在停止，等待图片选择结束…'), findsOneWidget);
        // The existing data and exclusive library owner remain usable while the
        // actual selection is pending. No returned source has been opened.
        expect(
          (await tester.runAsync(() => h.repository.listAssets()))!.total,
          1,
        );
        await tester.runAsync(() async {
          await expectLater(
            LibraryRepository.open(h.root),
            throwsA(isA<LibraryOpenException>()),
          );
        });
        h.gateway.selections[0].complete([h.resource]);
        await _until(tester, () => response != null);
        expect(response, AppExitResponse.exit);
        expect(h.sourceOpens, 0);
        await tester.runAsync(() async {
          final reopened = await LibraryRepository.open(h.root);
          try {
            final page = await reopened.listAssets();
            expect(page.total, 1);
            expect(page.items.single.displayName, '已保存.png');
          } finally {
            await reopened.close();
          }
        });
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('UT-011 declined exit leaves pending selection able to import', (
    tester,
  ) async {
    final h = await _Harness.open(tester);
    try {
      await tester.tap(find.byKey(const Key('import-files')));
      await _until(tester, () => h.gateway.calls == 1);
      AppExitResponse? response;
      unawaited(
        tester.binding.handleRequestAppExit().then((value) => response = value),
      );
      await _pumpUi(tester);
      await tester.tap(find.text('继续导入'));
      await _until(tester, () => response != null);
      expect(response, AppExitResponse.cancel);
      h.gateway.selections[0].complete([h.resource]);
      await _until(
        tester,
        () => find.textContaining('1 已保存').evaluate().isNotEmpty,
      );
      expect(h.sourceOpens, 1);
      expect(
        (await tester.runAsync(() => h.repository.listAssets()))!.total,
        1,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await h.close(tester);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
    'UT-011 picker failure after confirmed exit is handled before closing',
    (tester) async {
      final h = await _Harness.open(tester);
      try {
        await tester.tap(find.byKey(const Key('import-files')));
        await _until(tester, () => h.gateway.calls == 1);
        AppExitResponse? response;
        unawaited(
          tester.binding.handleRequestAppExit().then(
            (value) => response = value,
          ),
        );
        await _pumpUi(tester);
        await tester.tap(find.text('停止并退出'));
        await _pumpUi(tester);
        expect(response, isNull);
        h.gateway.selections[0].completeError(
          const ResourceFailure(FailureKind.permissionDenied),
        );
        await _until(tester, () => response != null);
        expect(response, AppExitResponse.exit);
        expect(h.sourceOpens, 0);
        expect(
          find.text(
            const ResourceFailure(FailureKind.permissionDenied).message,
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

final class _Harness {
  _Harness(
    this.root,
    this.repository,
    this.session,
    this.container,
    this.gateway,
  );
  final Directory root;
  final LibraryRepository repository;
  final LibrarySession session;
  final ProviderContainer container;
  final _PickerGateway gateway;
  int sourceOpens = 0;
  late final resource = PlatformResource(
    displayName: '新的图片.png',
    openRead: () {
      sourceOpens++;
      return Stream.value(img.encodePng(img.Image(width: 3, height: 2)));
    },
  );

  static Future<_Harness> open(WidgetTester tester, {bool seed = false}) async {
    tester.view.physicalSize = const Size(1280, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('imagehost_picker_exit_'),
    ))!;
    final repository = (await tester.runAsync(
      () => LibraryRepository.open(root),
    ))!;
    if (seed) {
      await tester.runAsync(
        () => repository.importResource(
          PlatformResource(
            displayName: '已保存.png',
            openRead: () =>
                Stream.value(img.encodePng(img.Image(width: 7, height: 5))),
          ),
        ),
      );
    }
    final session = (await tester.runAsync(
      () async => LibrarySession(repository, const []),
    ))!;
    final gateway = _PickerGateway();
    final container = ProviderContainer(
      overrides: [
        librarySessionProvider.overrideWith((ref) async => session),
        importGatewayProvider.overrideWithValue(gateway),
      ],
    );
    await tester.runAsync(() => container.read(galleryProvider.future));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ImageHostApp(),
      ),
    );
    await _pumpUi(tester);
    return _Harness(root, repository, session, container, gateway);
  }

  Future<void> close(WidgetTester tester) async {
    for (final selection in gateway.selections) {
      if (!selection.isCompleted) selection.complete([]);
    }
    await tester.pumpWidget(const SizedBox());
    var closed = false;
    await tester.runAsync(() async {
      unawaited(session.close().then((_) => closed = true));
    });
    await _until(tester, () => closed);
    container.dispose();
    await tester.runAsync(() => root.delete(recursive: true));
  }
}

final class _PickerGateway extends ImportGateway {
  final selections = [
    Completer<List<PlatformResource>>(),
    Completer<List<PlatformResource>>(),
  ];
  int calls = 0;
  @override
  Future<List<PlatformResource>> pickFiles() => selections[calls++].future;
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 300 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump();
  expect(
    ready(),
    true,
    reason: 'Expected selection or actual IO did not complete.',
  );
}

Future<void> _pumpUi(WidgetTester tester) async {
  // A pending selector or real thumbnail IO can keep an indeterminate loading
  // animation scheduled. Pump the route transition without waiting for it to
  // become idle; the tests use explicit acquisition and actual IO boundaries.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
