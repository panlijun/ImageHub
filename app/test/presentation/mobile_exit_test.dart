import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/links/presentation/link_results_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'mobile_recycle_test.dart'
    show
        MobileTestFixture,
        mountMobileTest,
        flushMobileTest,
        openMobileRecycle,
        selectMobileAsset;

void main() {
  for (final retryPanel in [false, true]) {
    testWidgets(
      'LIB-001 M1 direct refresh failure ${retryPanel ? 'retained list retry' : 'tools menu'} is caught without formatting unknown errors',
      (tester) async {
        final fixture = await MobileTestFixture.create(
          tester,
          names: ['刷新失败仍保留.png'],
        );
        final failure = _UnformattableFailure();
        var calls = 0;
        Future<void> refresh() async {
          calls++;
          throw failure;
        }

        await mountMobileTest(tester, fixture, onRefresh: refresh);
        if (retryPanel) {
          await mountMobileTest(
            tester,
            fixture,
            onRefresh: refresh,
            galleryOverride: AsyncValue<GalleryPage>.error(
              StateError('controlled gallery read failure'),
              StackTrace.empty,
            ),
          );
          await tester.ensureVisible(find.text('重试读取'));
          await tester.tap(find.text('重试读取'));
        } else {
          await tester.tap(find.byTooltip('工具与设置'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('重新读取图库'));
        }
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(failure.formatted, false);
        expect(find.text('图库刷新失败，最后有效列表保留，请重试读取。'), findsOneWidget);
        expect(
          find.byKey(Key('mobile-asset-${fixture.assets.single.id}')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'UT-100 M1 root back awaits one exit callback and refuses a concurrent duplicate',
    (tester) async {
      final fixture = await MobileTestFixture.create(tester);
      final drain = Completer<void>();
      var calls = 0;
      await mountMobileTest(
        tester,
        fixture,
        onRequestExit: () async {
          calls++;
          await drain.future;
        },
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(calls, 1);
      expect(find.text('我的图库'), findsOneWidget);
      drain.complete();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(
        calls,
        2,
        reason:
            'An earlier rejected/cancelled exit must permit a later request.',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-100 M1 import busy still delegates root back to parent stop confirmation',
    (tester) async {
      final fixture = await MobileTestFixture.create(tester);
      var calls = 0;
      await mountMobileTest(
        tester,
        fixture,
        busy: true,
        onRequestExit: () async {
          calls++;
        },
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-100 M1 back cancels selection then returns recycle to gallery before requesting exit',
    (tester) async {
      final fixture = await MobileTestFixture.create(tester, names: ['选择.png']);
      var calls = 0;
      await mountMobileTest(
        tester,
        fixture,
        onRequestExit: () async {
          calls++;
        },
      );
      await selectMobileAsset(tester, fixture, fixture.assets.single.id);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mobile-select')), findsOneWidget);
      expect(find.textContaining('已选 1 张'), findsNothing);
      expect(calls, 0);
      await openMobileRecycle(tester, fixture);
      await tester.binding.handlePopRoute();
      await flushMobileTest(tester, fixture);
      expect(fixture.container.read(galleryQueryProvider).recycledOnly, false);
      expect(calls, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-100 M1 links section back returns gallery without issuing an exit request',
    (tester) async {
      final fixture = await MobileTestFixture.create(tester);
      var calls = 0;
      await mountMobileTest(
        tester,
        fixture,
        onRequestExit: () async {
          calls++;
        },
      );
      await tester.tap(find.byType(NavigationDestination).at(1));
      await flushMobileTest(tester, fixture);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(calls, 0);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-100 M1 absent exit capability does not remove its root page',
    (tester) async {
      final fixture = await MobileTestFixture.create(tester);
      await mountMobileTest(tester, fixture);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('我的图库'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-100 M1 an unsettled link operation blocks root exit until the child reports drain',
    (tester) async {
      final fixture = await MobileTestFixture.create(tester);
      var calls = 0;
      await mountMobileTest(
        tester,
        fixture,
        onRequestExit: () async {
          calls++;
        },
      );
      final child = tester.widget<LinkResultsScreen>(
        find.byType(LinkResultsScreen, skipOffstage: false),
      );
      child.onBusyChanged!(true);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(calls, 0);
      child.onBusyChanged!(false);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final size in [const Size(320, 700), const Size(640, 320)]) {
    testWidgets(
      'PLT-004 partial M1 import source at $size large text remains scrollable and selectable',
      (tester) async {
        final fixture = await MobileTestFixture.create(tester);
        final imported = <bool>[];
        await mountMobileTest(
          tester,
          fixture,
          size: size,
          textScale: 2,
          onImport: (photos) async => imported.add(photos),
        );
        await tester.ensureVisible(find.byKey(const Key('import-files')));
        await tester.tap(find.byKey(const Key('import-files')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('mobile-import-source-scroll')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const Key('import-source-files')),
        );
        await tester.tap(find.byKey(const Key('import-source-files')));
        await tester.pumpAndSettle();
        expect(imported, [false]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'PLT-004 partial M1 source cancellation closes only its sheet without acquiring images',
    (tester) async {
      final fixture = await MobileTestFixture.create(tester);
      var imports = 0;
      var exits = 0;
      await mountMobileTest(
        tester,
        fixture,
        onImport: (_) async {
          imports++;
        },
        onRequestExit: () async {
          exits++;
        },
      );
      await tester.tap(find.byKey(const Key('import-files')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('mobile-import-source-scroll')),
        findsNothing,
      );
      expect(imports, 0);
      expect(exits, 0);
      expect(find.text('我的图库'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'LIB-001 M1 query read failure retains a real previous list and disables mutation',
    (tester) async {
      final fixture = await MobileTestFixture.create(
        tester,
        names: ['最后有效.png'],
      );
      await mountMobileTest(tester, fixture);
      expect(
        find.byKey(Key('mobile-asset-${fixture.assets.single.id}')),
        findsOneWidget,
      );
      await mountMobileTest(
        tester,
        fixture,
        galleryOverride: AsyncValue<GalleryPage>.error(
          StateError('test failure'),
          StackTrace.empty,
        ),
      );
      expect(
        find.byKey(Key('mobile-asset-${fixture.assets.single.id}')),
        findsOneWidget,
      );
      expect(find.text('读取失败，最后有效列表仍保留。当前操作已暂停，请重试读取。'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('mobile-select')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('import-files')))
            .onPressed,
        isNull,
      );
      await tester.tap(
        find.byKey(Key('mobile-asset-${fixture.assets.single.id}')),
      );
      await tester.pump();
      expect(find.text('图片详情'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

class _UnformattableFailure implements Exception {
  bool formatted = false;
  @override
  String toString() {
    formatted = true;
    throw StateError('An unknown refresh failure must never be formatted.');
  }
}
