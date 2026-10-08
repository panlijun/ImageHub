import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/gallery/presentation/mobile_gallery.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

// Host widget/SQLite evidence only; these tests do not claim Android device PT.
void main() {
  testWidgets(
    'UT-019 partial M1 confirmed removal and restoration retain identities and organization',
    (tester) async {
      final fixture = await MobileTestFixture.create(
        tester,
        names: ['保留整理.png'],
      );
      final original = fixture.assets.single;
      await mobileNative(tester, () async {
        final category = await fixture.repository.createCategory('分类');
        await fixture.repository.updateOrganization(
          [original.id],
          setCategory: true,
          categoryId: category.id,
          replaceTags: ['保留标签'],
          favorite: true,
        );
        await fixture.container.read(galleryProvider.notifier).reload();
      });
      await mountMobileTest(tester, fixture);
      await tester.tap(find.byKey(Key('mobile-asset-${original.id}')));
      await flushMobileTest(tester, fixture);
      await tester.ensureVisible(find.byKey(const Key('mobile-remove-asset')));
      await tester.tap(find.byKey(const Key('mobile-remove-asset')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(
        (await mobileNative(
          tester,
          () => fixture.repository.getAsset(original.id),
        ))!.recycled,
        false,
      );
      await tester.tap(find.byKey(const Key('mobile-remove-asset')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '移入回收区'));
      await flushMobileTest(tester, fixture);
      final recycled = (await mobileNative(
        tester,
        () => fixture.repository.getAsset(original.id, includeRecycled: true),
      ))!;
      expect(recycled.recycled, true);
      expect(
        await mobileNative(
          tester,
          () => fixture.repository.verifyCopy(recycled),
        ),
        CopyAvailability.available,
      );
      await openMobileRecycle(tester, fixture);
      await tester.tap(find.byKey(Key('mobile-asset-${original.id}')));
      await flushMobileTest(tester, fixture);
      await tester.ensureVisible(find.byKey(const Key('mobile-restore-asset')));
      await tester.tap(find.byKey(const Key('mobile-restore-asset')));
      await flushMobileTest(tester, fixture);
      final restored = (await mobileNative(
        tester,
        () => fixture.repository.getAsset(original.id),
      ))!;
      expect(restored.version, original.version);
      expect(restored.deviceCopy, original.deviceCopy);
      expect(restored.tags.single.name, '保留标签');
      expect(restored.category, '分类');
      expect(restored.favorite, true);
      expect(fixture.container.read(galleryQueryProvider).recycledOnly, true);
      expect(fixture.container.read(galleryProvider).requireValue.total, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final mode in [0, 1, 2]) {
    testWidgets(
      'UT-020 partial M1 purge mode $mode requires independent confirmations and affects only chosen resources',
      (tester) async {
        final fixture = await MobileTestFixture.create(
          tester,
          names: ['清理.png', '保留.png'],
        );
        final chosen = fixture.assets.first;
        final other = fixture.assets.last;
        await mobileNative(
          tester,
          () => fixture.repository.removeAssets([chosen.id, other.id]),
        );
        await mountMobileTest(tester, fixture);
        await openMobileRecycle(tester, fixture);
        await selectMobileAsset(tester, fixture, chosen.id);
        await tester.tap(find.byKey(const Key('mobile-purge-selection')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('mobile-purge-execute')),
              )
              .onPressed,
          isNull,
        );
        if (mode != 0) {
          await tester.tap(find.byKey(const Key('mobile-purge-mode')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(mode == 1 ? '只清副本' : '同时清除').last);
          await tester.pumpAndSettle();
        }
        if (mode != 1) {
          await tester.ensureVisible(
            find.byKey(const Key('mobile-purge-confirm-records')),
          );
          await tester.tap(
            find.byKey(const Key('mobile-purge-confirm-records')),
          );
          await tester.pump();
        }
        if (mode == 2) {
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const Key('mobile-purge-execute')),
                )
                .onPressed,
            isNull,
          );
        }
        if (mode != 0) {
          await tester.ensureVisible(
            find.byKey(const Key('mobile-purge-confirm-copies')),
          );
          await tester.tap(
            find.byKey(const Key('mobile-purge-confirm-copies')),
          );
          await tester.pump();
        }
        await tester.tap(find.byKey(const Key('mobile-purge-execute')));
        await flushMobileTest(tester, fixture);
        final kept = await mobileNative(
          tester,
          () => fixture.repository.getAsset(chosen.id, includeRecycled: true),
        );
        expect(kept == null, mode != 1);
        final file = File(
          p.join(fixture.libraryRoot.path, chosen.deviceCopy.relativePath),
        );
        expect(await mobileNative(tester, file.exists), mode == 0);
        if (kept != null) {
          expect(kept.recycled, true);
          expect(
            await mobileNative(
              tester,
              () => fixture.repository.verifyCopy(kept),
            ),
            CopyAvailability.missing,
          );
        }
        final untouched = (await mobileNative(
          tester,
          () => fixture.repository.getAsset(other.id, includeRecycled: true),
        ))!;
        expect(untouched.version, other.version);
        expect(
          await mobileNative(
            tester,
            () => fixture.repository.verifyCopy(untouched),
          ),
          CopyAvailability.available,
        );
        expect(find.textContaining('永久清除已完成：'), findsOneWidget);
        expect(find.textContaining('已选 0 张'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'UT-020/102 partial M1 purge rejects an actual file lease and retains selection without success',
    (tester) async {
      final fixture = await MobileTestFixture.create(
        tester,
        names: ['仍在读取.png'],
      );
      final asset = fixture.assets.single;
      final lease = await mobileNative(
        tester,
        () => fixture.repository.acquireAssetLease([
          asset.id,
        ], purpose: 'test-reader'),
      );
      try {
        await mobileNative(
          tester,
          () => fixture.repository.removeAssets([asset.id]),
        );
        await mountMobileTest(tester, fixture);
        await openMobileRecycle(tester, fixture);
        await selectMobileAsset(tester, fixture, asset.id);
        await tester.tap(find.byKey(const Key('mobile-purge-selection')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('mobile-purge-confirm-records')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('mobile-purge-execute')));
        await flushMobileTest(tester, fixture);
        expect(find.textContaining('操作未全部完成'), findsOneWidget);
        expect(find.textContaining('永久清除已完成：'), findsNothing);
        expect(find.textContaining('已选 1 张'), findsWidgets);
        expect(
          await mobileNative(
            tester,
            () => fixture.repository.getAsset(asset.id, includeRecycled: true),
          ),
          isNotNull,
        );
        expect(
          await mobileNative(
            tester,
            () => File(lease.pathsByVersion[asset.version.id]!).exists(),
          ),
          true,
        );
        await tester.pumpWidget(const SizedBox());
      } finally {
        await mobileNative(tester, lease.release);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-020 partial M1 purge rechecks frozen UUIDs after a selected asset leaves recycle',
    (tester) async {
      final fixture = await MobileTestFixture.create(
        tester,
        names: ['恢复竞态.png'],
      );
      final asset = fixture.assets.single;
      await mobileNative(
        tester,
        () => fixture.repository.removeAssets([asset.id]),
      );
      await mountMobileTest(tester, fixture);
      await openMobileRecycle(tester, fixture);
      await selectMobileAsset(tester, fixture, asset.id);
      await tester.tap(find.byKey(const Key('mobile-purge-selection')));
      await tester.pumpAndSettle();
      await mobileNative(
        tester,
        () => fixture.repository.restoreAssets([asset.id]),
      );
      await tester.tap(find.byKey(const Key('mobile-purge-confirm-records')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('mobile-purge-execute')));
      await flushMobileTest(tester, fixture);
      expect(find.textContaining('操作未全部完成'), findsOneWidget);
      final active = (await mobileNative(
        tester,
        () => fixture.repository.getAsset(asset.id),
      ))!;
      expect(
        await mobileNative(tester, () => fixture.repository.verifyCopy(active)),
        CopyAvailability.available,
      );
      expect(find.textContaining('永久清除已完成：'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

Future<void> openMobileRecycle(
  WidgetTester tester,
  MobileTestFixture fixture,
) async {
  await tester.tap(find.byTooltip('工具与设置'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('mobile-recycle-entry')));
  await flushMobileTest(tester, fixture);
  expect(fixture.container.read(galleryQueryProvider).recycledOnly, true);
}

Future<void> selectMobileAsset(
  WidgetTester tester,
  MobileTestFixture fixture,
  String id,
) async {
  await tester.ensureVisible(find.byKey(const Key('mobile-select')));
  await tester.tap(find.byKey(const Key('mobile-select')));
  await tester.pump();
  await tester.ensureVisible(find.byKey(Key('mobile-asset-$id')));
  await tester.tap(find.byKey(Key('mobile-asset-$id')));
  await tester.pump();
}

Future<void> mountMobileTest(
  WidgetTester tester,
  MobileTestFixture fixture, {
  bool busy = false,
  Future<void> Function()? onRequestExit,
  Future<void> Function(bool)? onImport,
  Future<void> Function()? onRefresh,
  Size size = const Size(390, 900),
  double textScale = 1,
  AsyncValue<GalleryPage>? galleryOverride,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: fixture.container,
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Consumer(
          builder: (context, ref, _) => MobileGallery(
            gallery: galleryOverride ?? ref.watch(galleryProvider),
            session: ref.watch(librarySessionProvider),
            busy: busy,
            loadingMore: false,
            supportsPhotos: true,
            onImport: onImport ?? (_) async {},
            onRetry: () {},
            onRefresh:
                onRefresh ?? () => ref.read(galleryProvider.notifier).reload(),
            onLoadMore: () => ref.read(galleryProvider.notifier).loadMore(),
            onRequestExit: onRequestExit,
            notices: const [],
          ),
        ),
      ),
    ),
  );
  await flushMobileTest(tester, fixture);
}

Future<void> flushMobileTest(
  WidgetTester tester,
  MobileTestFixture fixture,
) async {
  var idle = 0;
  for (var i = 0; i < 2000 && idle < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    if (!fixture.container.read(galleryProvider).isLoading &&
        find
            .byType(CircularProgressIndicator, skipOffstage: false)
            .evaluate()
            .isEmpty &&
        find
            .byType(LinearProgressIndicator, skipOffstage: false)
            .evaluate()
            .isEmpty) {
      idle++;
    } else {
      idle = 0;
    }
  }
  expect(idle, 5, reason: 'Real SQLite, file and widget queues must settle.');
  await tester.pumpAndSettle();
}

Future<T> mobileNative<T>(
  WidgetTester tester,
  Future<T> Function() action,
) async {
  var finished = false;
  T? value;
  Object? failure;
  StackTrace? trace;
  await tester.runAsync(() async {
    unawaited(
      action().then(
        (result) {
          value = result;
          finished = true;
        },
        onError: (Object error, StackTrace stack) {
          failure = error;
          trace = stack;
          finished = true;
        },
      ),
    );
  });
  for (var i = 0; i < 250 && !finished; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(
    finished,
    true,
    reason: 'Native and widget continuations must both finish.',
  );
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
  return value as T;
}

class MobileTestFixture {
  MobileTestFixture(
    this.repository,
    this.container,
    this.assets,
    this.libraryRoot,
  );
  final LibraryRepository repository;
  final ProviderContainer container;
  final List<ImageAsset> assets;
  final Directory libraryRoot;

  static Future<MobileTestFixture> create(
    WidgetTester tester, {
    List<String> names = const [],
  }) async {
    final sandbox = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('imagehost_mobile_recycle_'),
    ))!;
    final libraryRoot = Directory(p.join(sandbox.path, 'library'));
    final repository = (await tester.runAsync(
      () => LibraryRepository.open(libraryRoot),
    ))!;
    final assets = <ImageAsset>[];
    await tester.runAsync(() async {
      for (var i = 0; i < names.length; i++) {
        final image = img.Image(width: 6, height: 4, numChannels: 4);
        img.fill(image, color: img.ColorRgba8(i + 1, 70, 150, 255));
        final result = await repository.importResource(
          PlatformResource(
            displayName: names[i],
            openRead: () => Stream.value(img.encodePng(image)),
          ),
        );
        expect(result.status, ImportStatus.saved);
        assets.add(result.asset!);
      }
    });
    final container = ProviderContainer(
      overrides: [
        librarySessionProvider.overrideWith(
          (ref) => Future.value(LibrarySession(repository, const [])),
        ),
      ],
    );
    await tester.runAsync(() => container.read(galleryProvider.future));
    addTearDown(() async {
      container.dispose();
      await mobileNative(tester, repository.close);
      await tester.runAsync(() => sandbox.delete(recursive: true));
    });
    return MobileTestFixture(repository, container, assets, libraryRoot);
  }
}
