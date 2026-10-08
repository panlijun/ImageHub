import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/gallery_query.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/gallery/presentation/desktop_gallery.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

// These are Windows-hosted desktop widget/real SQLite checks, not device AT.
void main() {
  testWidgets(
    'IT-002 original viewer system exit drains codec budget and closes library before reopen',
    (tester) async {
      _size(tester, 1280);
      final fixture = await _Fixture.create(tester, names: ['退出后保留.png']);
      await _mount(tester, fixture.container);
      await _flush(tester, fixture);
      await tester.tap(
        find.byKey(Key('desktop-asset-${fixture.assets.single.id}')),
      );
      await _flush(tester, fixture);
      await tester.tap(find.byKey(const Key('desktop-original-preview')));
      await _flush(tester, fixture);
      expect(fixture.repository.processingScheduler.activeCount, 1);
      AppExitResponse? response;
      await tester.runAsync(() async {
        unawaited(
          tester.binding.handleRequestAppExit().then(
            (value) => response = value,
          ),
        );
      });
      for (var i = 0; i < 200 && response == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(response, AppExitResponse.exit);
      expect(fixture.repository.processingScheduler.activeCount, 0);
      await tester.pumpWidget(const SizedBox());
      final reopened = (await tester.runAsync(
        () => LibraryRepository.open(fixture.libraryRoot),
      ))!;
      try {
        final assets = (await tester.runAsync(() => reopened.listAssets()))!
            .items;
        expect(assets.single.id, fixture.assets.single.id);
        expect(assets.single.version, fixture.assets.single.version);
      } finally {
        await tester.runAsync(reopened.close);
      }
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'IT-002 desktop original viewer $width uses independent bytes and drains before return',
      (tester) async {
        _size(tester, width);
        final fixture = await _Fixture.create(tester, names: ['独立图片.png']);
        await _mount(tester, fixture.container);
        await _flush(tester, fixture);
        await tester.tap(
          find.byKey(Key('desktop-asset-${fixture.assets.single.id}')),
        );
        await _flush(tester, fixture);
        await tester.tap(find.byKey(const Key('desktop-original-preview')));
        await _flush(tester, fixture);
        final raw = tester.widget<RawImage>(find.byType(RawImage));
        expect([raw.image!.width, raw.image!.height], [6, 4]);
        expect(find.byType(InteractiveViewer), findsOneWidget);
        expect(fixture.repository.processingScheduler.activeCount, 1);
        await tester.tap(find.byKey(const Key('original-preview-back')));
        await _flush(tester, fixture);
        expect(find.byKey(const Key('original-preview-back')), findsNothing);
        expect(fixture.repository.processingScheduler.activeCount, 0);
        expect(find.text('图片详情'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
  for (final width in [390.0, 760.0, 1280.0]) {
    testWidgets('AT-001 partial desktop A $width empty/loading/failure', (
      tester,
    ) async {
      _size(tester, width);
      final pending = Completer<LibrarySession>();
      final loading = ProviderContainer(
        overrides: [
          librarySessionProvider.overrideWith((ref) => pending.future),
        ],
      );
      await _mount(tester, loading);
      await tester.pump();
      expect(find.text('正在打开本机图库…'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('import-files')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      loading.dispose();
      final failed = ProviderContainer(
        overrides: [
          librarySessionProvider.overrideWith(
            (ref) => Future.error(const LibraryOpenException('测试读取失败，原库保留。')),
          ),
        ],
      );
      await _mount(tester, failed);
      await tester.pumpAndSettle();
      expect(find.text('图库打开失败'), findsOneWidget);
      expect(find.text('重试打开'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('import-files')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      failed.dispose();
      final fixture = await _Fixture.create(tester);
      await _mount(tester, fixture.container);
      await _flush(tester, fixture);
      expect(find.text('图库还是空的'), findsOneWidget);
      expect(find.text('把第一张图片放进来'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('import-files')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('desktop-filters')));
      await _flush(tester, fixture);
      expect(find.text('组合筛选与排序'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('完成'));
      await _flush(tester, fixture);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

  testWidgets(
    'UT-014/015/016 partial desktop continuous tag draft and atomic invalid rejection',
    (tester) async {
      _size(tester, 1280);
      final fixture = await _Fixture.create(
        tester,
        names: ['海边.png', '森林.png'],
      );
      await _mount(tester, fixture.container);
      await _flush(tester, fixture);
      final asset = fixture.assets.first;
      await tester.tap(find.byKey(Key('desktop-asset-${asset.id}')));
      await _flush(tester, fixture);
      expect(find.text('本机副本可用'), findsOneWidget);
      await tester.tap(find.text('整理图片'));
      await _flush(tester, fixture);
      await tester.enterText(
        find.byKey(const Key('organization-tags')),
        '第一，第二，',
      );
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('organization-tags')))
            .controller!
            .text,
        '第一，第二，',
      );
      await tester.tap(find.byKey(const Key('organization-save')));
      await _flush(tester, fixture);
      expect(
        (await _native(
          tester,
          () => fixture.repository.getAsset(asset.id),
        ))!.tags.map((tag) => tag.name),
        ['第一', '第二'],
      );
      await tester.tap(find.text('整理图片'));
      await _flush(tester, fixture);
      final longDraft = 'a' * 65;
      await tester.enterText(
        find.byKey(const Key('organization-tags')),
        longDraft,
      );
      await tester.tap(find.byKey(const Key('organization-save')));
      await _flush(tester, fixture);
      expect(find.text('名称不能超过 64 个 Unicode 字符。'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('organization-tags')))
            .controller!
            .text,
        longDraft,
      );
      expect(
        (await _native(
          tester,
          () => fixture.repository.getAsset(asset.id),
        ))!.tags.map((tag) => tag.name),
        ['第一', '第二'],
      );
      final manyDraft = List.generate(51, (i) => '标签$i').join('，');
      await tester.enterText(
        find.byKey(const Key('organization-tags')),
        manyDraft,
      );
      await tester.tap(find.byKey(const Key('organization-save')));
      await _flush(tester, fixture);
      expect(find.text('每项最多允许 50 个标签。'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('organization-tags')))
            .controller!
            .text,
        manyDraft,
      );
      expect(
        (await _native(
          tester,
          () => fixture.repository.getAsset(asset.id),
        ))!.tags.map((tag) => tag.name),
        ['第一', '第二'],
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-013/017 partial desktop selection survives combined query and loads real names',
    (tester) async {
      _size(tester, 1280);
      final fixture = await _Fixture.create(
        tester,
        names: ['海边.png', '森林.png', '远山.png'],
      );
      final first = fixture.assets.first;
      await _native(tester, () async {
        final category = await fixture.repository.createCategory('旅行');
        await fixture.repository.updateOrganization(
          [first.id],
          categoryId: category.id,
          setCategory: true,
          addTags: ['蓝色'],
          favorite: true,
        );
        await fixture.container.read(galleryProvider.notifier).reload();
      });
      await _mount(tester, fixture.container);
      await _flush(tester, fixture);
      await tester.tap(find.text('多选'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('desktop-select-matching')));
      await _flush(tester, fixture);
      expect(find.text('已选 3 张'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('desktop-search')), '旅行');
      await tester.pump(const Duration(milliseconds: 250));
      await _flush(tester, fixture);
      await tester.tap(find.byKey(const Key('desktop-favorites')));
      await _flush(tester, fixture);
      expect(fixture.container.read(galleryProvider).requireValue.total, 1);
      expect(find.text('已选 3 张'), findsOneWidget);
      await tester.tap(find.byKey(const Key('desktop-review-selection')));
      await _flush(tester, fixture);
      expect(find.text('森林.png'), findsOneWidget);
      expect(find.text('远山.png'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-019/020/021 partial desktop recycle identity and separate purge confirmations',
    (tester) async {
      _size(tester, 1280);
      final fixture = await _Fixture.create(tester, names: ['保留身份.png']);
      final original = fixture.assets.single;
      await _mount(tester, fixture.container);
      await _flush(tester, fixture);
      await tester.tap(find.byKey(Key('desktop-asset-${original.id}')));
      await _flush(tester, fixture);
      await tester.tap(find.text('移入回收区'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '移入回收区'));
      await _flush(tester, fixture);
      final recycled = (await _native(
        tester,
        () => fixture.repository.getAsset(original.id, includeRecycled: true),
      ))!;
      expect(recycled.recycled, isTrue);
      expect(
        (await _native(
          tester,
          () => File(
            p.join(fixture.libraryRoot.path, original.deviceCopy.relativePath),
          ).exists(),
        )),
        isTrue,
      );
      await tester.tap(find.text('回收区').first);
      await _flush(tester, fixture);
      await tester.tap(find.byKey(Key('desktop-asset-${original.id}')));
      await _flush(tester, fixture);
      await tester.tap(find.text('恢复图片'));
      await _flush(tester, fixture);
      final restored = (await _native(
        tester,
        () => fixture.repository.getAsset(original.id),
      ))!;
      expect(restored.id, original.id);
      expect(restored.version.id, original.version.id);
      expect(restored.deviceCopy.id, original.deviceCopy.id);
      await _native(tester, () async {
        await fixture.repository.removeAssets([original.id]);
        await fixture.container.read(galleryProvider.notifier).reload();
      });
      await _flush(tester, fixture);
      await tester.tap(find.byKey(Key('desktop-asset-${original.id}')));
      await _flush(tester, fixture);
      await tester.tap(find.text('永久清除'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('purge-execute')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('purge-confirm-records')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('purge-execute')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('只清记录').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('只清副本').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('purge-execute')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('purge-confirm-copies')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('purge-execute')));
      await _flush(tester, fixture);
      final kept = (await _native(
        tester,
        () => fixture.repository.getAsset(original.id, includeRecycled: true),
      ))!;
      expect(kept.id, original.id);
      expect(
        await _native(tester, () => fixture.repository.verifyCopy(kept)),
        CopyAvailability.missing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
  testWidgets(
    'UT-017 partial desktop actual PNG dropdown and removed category safety',
    (tester) async {
      _size(tester, 1280);
      final fixture = await _Fixture.create(
        tester,
        names: ['分类图片.png', '其他图片.png'],
      );
      final category = await _native(
        tester,
        () => fixture.repository.createCategory('测试分类'),
      );
      await _native(
        tester,
        () => fixture.repository.assignCategory([
          fixture.assets.first.id,
        ], category.id),
      );
      fixture.container
          .read(galleryQueryProvider.notifier)
          .replace(GalleryQuery(categoryId: category.id));
      await _mount(tester, fixture.container);
      await _flush(tester, fixture);
      await tester.tap(find.byKey(const Key('desktop-filters')));
      await _flush(tester, fixture);
      final formatField = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == '格式',
      );
      await tester.ensureVisible(formatField);
      await tester.tap(formatField);
      await tester.pumpAndSettle();
      await tester.tap(find.text('PNG').last);
      await _flush(tester, fixture);
      expect(fixture.container.read(galleryQueryProvider).format, 'PNG');
      expect(
        fixture.container.read(galleryProvider).requireValue.items.single.id,
        fixture.assets.first.id,
      );
      final sortField = tester.widget<DropdownButton<GallerySort>>(
        find.descendant(
          of: find.byType(DropdownButtonFormField<GallerySort>),
          matching: find.byType(DropdownButton<GallerySort>),
        ),
      );
      expect(
        sortField.items!
            .singleWhere((item) => item.value == GallerySort.uploaded)
            .enabled,
        isTrue,
      );
      await tester.ensureVisible(find.text('管理分类'));
      await tester.tap(find.text('管理分类'));
      await _flush(tester, fixture);
      await tester.tap(find.byTooltip('移除分类'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '移除分类'));
      await _flush(tester, fixture);
      await tester.tap(find.widgetWithText(FilledButton, '关闭'));
      await _flush(tester, fixture);
      expect(find.text('分类已移除，请清空条件'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('清空筛选与排序'));
      await _flush(tester, fixture);
      expect(fixture.container.read(galleryProvider).requireValue.total, 2);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

// Repository queues can contain callbacks started in both the widget fake zone
// and the native IO zone. Drain both rather than blocking runAsync on a queued
// fake-zone predecessor (which would prevent its continuation from running).
Future<T> _native<T>(WidgetTester tester, Future<T> Function() action) async {
  var finished = false;
  T? result;
  Object? failure;
  await tester.runAsync(() async {
    unawaited(
      action().then(
        (value) {
          result = value;
          finished = true;
        },
        onError: (Object error) {
          failure = error;
          finished = true;
        },
      ),
    );
  });
  for (var i = 0; i < 250 && !finished; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(
    finished,
    isTrue,
    reason: 'Native and queued widget work must finish.',
  );
  if (failure != null) throw failure!;
  return result as T;
}

class _Harness extends ConsumerWidget {
  const _Harness();
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    home: DesktopGallery(
      gallery: ref.watch(galleryProvider),
      session: ref.watch(librarySessionProvider),
      busy: false,
      loadingMore: false,
      onImport: (_) async {},
      onRetry: () {
        ref.invalidate(librarySessionProvider);
        ref.invalidate(galleryProvider);
      },
      onRefresh: () => ref.read(galleryProvider.notifier).reload(),
      onLoadMore: () => ref.read(galleryProvider.notifier).loadMore(),
      notices: const [],
    ),
  );
}

void _size(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _mount(WidgetTester tester, ProviderContainer container) =>
    tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const _Harness()),
    );
Future<void> _flush(WidgetTester tester, _Fixture fixture) async {
  // More native/fake-zone turns within the same nominal 4 s IO tick budget.
  // Small fake ticks avoid advancing the periodic janitor while draining a grid.
  var idle = 0;
  for (var i = 0; i < 2000 && idle < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    final waitingAction =
        find.byType(AlertDialog).evaluate().isEmpty &&
        find.text('等待操作结果…').evaluate().isNotEmpty;
    if (!fixture.container.read(galleryProvider).isLoading &&
        find
            .byType(CircularProgressIndicator, skipOffstage: false)
            .evaluate()
            .isEmpty &&
        !waitingAction &&
        find
            .byType(LinearProgressIndicator, skipOffstage: false)
            .evaluate()
            .isEmpty) {
      idle++;
    } else {
      idle = 0;
    }
  }
  expect(idle, 5, reason: 'Real SQLite and preview work must settle.');
  await tester.pumpAndSettle();
}

class _Fixture {
  _Fixture(this.repository, this.container, this.assets, this.libraryRoot);
  final LibraryRepository repository;
  final ProviderContainer container;
  final List<ImageAsset> assets;
  final Directory libraryRoot;
  static Future<_Fixture> create(
    WidgetTester tester, {
    List<String> names = const [],
  }) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('imagehost_desktop_widget_'),
    ))!;
    final repository = (await tester.runAsync(
      () => LibraryRepository.open(Directory(p.join(root.path, 'library'))),
    ))!;
    final assets = <ImageAsset>[];
    await tester.runAsync(() async {
      for (var i = 0; i < names.length; i++) {
        final image = img.Image(width: 6, height: 4, numChannels: 4);
        img.fill(image, color: img.ColorRgba8(i + 1, 70, 150, 255));
        final source = File(p.join(root.path, 'external-$i.png'));
        await source.writeAsBytes(img.encodePng(image));
        final imported = await repository.importResource(
          PlatformResource.file(source, displayName: names[i]),
        );
        expect(imported.status, ImportStatus.saved);
        assets.add(imported.asset!);
        await source.delete();
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
      var closed = false;
      await tester.runAsync(() async {
        unawaited(repository.close().then((_) => closed = true));
      });
      for (var i = 0; i < 200 && !closed; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(closed, isTrue);
      await tester.runAsync(() => root.delete(recursive: true));
    });
    return _Fixture(
      repository,
      container,
      assets,
      Directory(p.join(root.path, 'library')),
    );
  }
}
