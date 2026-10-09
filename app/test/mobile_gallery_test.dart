import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/app.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

// Windows-hosted widget tests emulate Android Theme/layout only. The tiny PNGs
// are independently generated test fixtures, never prototype/product samples.
void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final width in [320.0, 390.0, 430.0]) {
    testWidgets('AT-001 partial M1 $width loading/failure/real empty layouts', (
      tester,
    ) async {
      _size(tester, width);
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
      expect(_importButton(tester).onPressed, isNull);
      expect(find.text('把第一张图片放进来'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
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
      expect(_importButton(tester).onPressed, isNull);
      expect(find.text('把第一张图片放进来'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      final fixture = await _Fixture.create(tester);
      await _mount(tester, fixture);
      expect(find.text('把第一张图片放进来'), findsOneWidget);
      expect(_importButton(tester).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets(
    'UT-004 / IT-001 partial M1 independent copy, real search and favorite',
    (tester) async {
      _size(tester, 390);
      final fixture = await _Fixture.create(
        tester,
        names: ['海边.png', '森林.png'],
      );
      await _mount(tester, fixture);
      final beach = fixture.assets.first;
      await tester.tap(find.byKey(Key('mobile-asset-${beach.id}')));
      await _flush(tester, fixture);
      expect(find.text('图片详情'), findsOneWidget);
      expect(find.text('本机副本可用'), findsOneWidget);
      expect(find.text('来源被移除，也可以继续使用'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('mobile-original-preview')),
      );
      await tester.tap(find.byKey(const Key('mobile-original-preview')));
      await _flush(tester, fixture);
      final originalImage = tester.widget<RawImage>(find.byType(RawImage));
      expect([originalImage.image!.width, originalImage.image!.height], [6, 4]);
      expect(fixture.repository.processingScheduler.activeCount, 1);
      await tester.tap(find.byKey(const Key('original-preview-back')));
      await _flush(tester, fixture);
      expect(fixture.repository.processingScheduler.activeCount, 0);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '上传原图'))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '编辑副本'))
            .onPressed,
        isNotNull,
      );
      expect(find.text('已确认的普通远程结果请在链接页查看；链接存在不代表当前可达。'), findsOneWidget);
      await tester.tap(find.byKey(const Key('mobile-favorite')));
      await _flush(tester, fixture);
      expect(
        fixture.container
            .read(galleryProvider)
            .requireValue
            .items
            .singleWhere((asset) => asset.id == beach.id)
            .favorite,
        isTrue,
      );
      await tester.tap(find.byTooltip('返回'));
      await _flush(tester, fixture);
      await tester.tap(find.widgetWithText(TextButton, '收藏'));
      await _flush(tester, fixture);
      expect(
        fixture.container.read(galleryProvider).requireValue.items.single.id,
        beach.id,
      );
      await tester.enterText(find.byKey(const Key('mobile-search')), '不存在');
      await tester.pump(const Duration(milliseconds: 250));
      await _flush(tester, fixture);
      expect(find.text('没有匹配图片'), findsOneWidget);
      await tester.tap(find.text('清除筛选'));
      await _flush(tester, fixture);
      expect(fixture.container.read(galleryProvider).requireValue.total, 2);
      expect(fixture.container.read(galleryQueryProvider).isUnfiltered, isTrue);
      await tester.enterText(find.byKey(const Key('mobile-search')), '森林');
      await tester.pump(const Duration(milliseconds: 250));
      await _flush(tester, fixture);
      expect(
        fixture.container
            .read(galleryProvider)
            .requireValue
            .items
            .single
            .displayName,
        '森林.png',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'UT-013 partial M1 selection survives filtering and reviews real names',
    (tester) async {
      _size(tester, 320);
      final fixture = await _Fixture.create(
        tester,
        names: ['第一张.png', '第二张.png'],
      );
      await _mount(tester, fixture);
      await tester.tap(find.byKey(const Key('mobile-select')));
      await tester.pump();
      await tester.tap(
        find.byKey(Key('mobile-asset-${fixture.assets.first.id}')),
      );
      await tester.pump();
      expect(find.text('已选 1 张'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('mobile-search')), '第二张');
      await tester.pump(const Duration(milliseconds: 250));
      await _flush(tester, fixture);
      expect(find.text('已选 1 张'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '压缩'))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '拼接'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '上传'))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('review-selection')));
      await _flush(tester, fixture);
      expect(find.text('核对已选 1 张'), findsOneWidget);
      expect(find.text('第一张.png'), findsOneWidget);
      await tester.tap(find.text('清空选择'));
      await _flush(tester, fixture);
      expect(find.text('已选 0 张'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'UT-013 partial M1 select matching includes all 65 identities beyond page',
    (tester) async {
      _size(tester, 430);
      final fixture = await _Fixture.create(
        tester,
        names: List.generate(65, (i) => '分页-$i.png'),
      );
      await _mount(tester, fixture);
      final page = fixture.container.read(galleryProvider).requireValue;
      expect(page.total, 65);
      expect(page.items.length, 60);
      await tester.tap(find.byKey(const Key('mobile-select')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('select-matching')));
      await _flush(tester, fixture);
      expect(find.text('已选 65 张'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('mobile-search')),
        '分页-64.png',
      );
      await tester.pump(const Duration(milliseconds: 250));
      await _flush(tester, fixture);
      expect(fixture.container.read(galleryProvider).requireValue.total, 1);
      expect(find.text('已选 65 张'), findsOneWidget);
      await tester.tap(find.byKey(const Key('review-selection')));
      await _flush(tester, fixture);
      expect(find.text('核对已选 65 张'), findsOneWidget);
      await tester.tap(find.text('清空选择'));
      await _flush(tester, fixture);
      expect(find.text('已选 0 张'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'AT-001 partial M1 density, shared upload destination and scroll/query retention',
    (tester) async {
      _size(tester, 390);
      final fixture = await _Fixture.create(
        tester,
        names: List.generate(12, (i) => '保留-$i.png'),
      );
      await _mount(tester, fixture);
      expect(_columns(tester), 2);
      await tester.tap(find.byTooltip('紧凑视图'));
      await _flush(tester, fixture);
      expect(_columns(tester), 3);
      await tester.tap(find.byTooltip('舒适视图'));
      await _flush(tester, fixture);
      await tester.enterText(find.byKey(const Key('mobile-search')), '保留');
      await tester.pump(const Duration(milliseconds: 250));
      await _flush(tester, fixture);
      await tester.drag(
        find.byKey(const PageStorageKey('mobile-gallery-scroll')),
        const Offset(0, -320),
      );
      await _flush(tester, fixture);
      final scroll = tester
          .widget<CustomScrollView>(
            find.byKey(const PageStorageKey('mobile-gallery-scroll')),
          )
          .controller!;
      final offset = scroll.offset;
      expect(offset, greaterThan(0));
      await tester.tap(find.widgetWithText(NavigationDestination, '链接'));
      await _flush(tester, fixture);
      expect(find.text('成功链接'), findsOneWidget);
      for (
        var i = 0;
        i < 20 && find.text('暂无已确认普通链接。').evaluate().isEmpty;
        i++
      ) {
        await tester.drag(find.byType(ListView), const Offset(0, -250));
        await _flush(tester, fixture);
      }
      expect(find.text('暂无已确认普通链接。'), findsOneWidget);
      await tester.tap(find.widgetWithText(NavigationDestination, '任务'));
      await _flush(tester, fixture);
      expect(find.text('确认并入队'), findsOneWidget);
      expect(find.text('允许本次会话网络上传'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await _flush(tester, fixture);
      await tester.tap(find.widgetWithText(NavigationDestination, '图库'));
      await tester.pumpAndSettle();
      expect(scroll.offset, offset);
      expect(fixture.container.read(galleryQueryProvider).keyword, '保留');
      scroll.jumpTo(0);
      await _flush(tester, fixture);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('mobile-search')))
            .controller!
            .text,
        '保留',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets('UT-014/016 partial M1 real shared category/tag editing', (
    tester,
  ) async {
    _size(tester, 390);
    final fixture = await _Fixture.create(tester, names: ['整理.png']);
    final asset = fixture.assets.single;
    await _native(tester, () => fixture.repository.createCategory('旅行'));
    await _mount(tester, fixture);
    await tester.tap(find.byKey(Key('mobile-asset-${asset.id}')));
    await _flush(tester, fixture);
    await tester.ensureVisible(find.byKey(const Key('mobile-organize')));
    await tester.tap(find.byKey(const Key('mobile-organize')));
    await _flush(tester, fixture);
    const draft = ' 海边，Cafe\u0301，CAFÉ ';
    await tester.enterText(find.byKey(const Key('organization-tags')), draft);
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('organization-tags')))
          .controller!
          .text,
      draft,
    );
    await tester.tap(find.byKey(const Key('organization-save')));
    await _flush(tester, fixture);
    final updated = (await _native(
      tester,
      () => fixture.repository.getAsset(asset.id),
    ))!;
    expect(updated.tags.map((t) => t.name), ['海边', 'Café']);
    expect(updated.version, asset.version);
    expect(updated.deviceCopy, asset.deviceCopy);
    expect(find.widgetWithText(Chip, '海边'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Café'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}

void _size(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<T> _native<T>(WidgetTester tester, Future<T> Function() action) async {
  var finished = false;
  T? result;
  Object? error;
  StackTrace? stack;
  await tester.runAsync(() async {
    unawaited(
      action().then(
        (value) {
          result = value;
          finished = true;
        },
        onError: (Object failure, StackTrace trace) {
          error = failure;
          stack = trace;
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
  expect(finished, true, reason: 'Native and widget queues must both finish.');
  if (error != null) Error.throwWithStackTrace(error!, stack!);
  return result as T;
}

FilledButton _importButton(WidgetTester tester) =>
    tester.widget(find.byKey(const Key('import-files')));

int _columns(WidgetTester tester) =>
    (tester.widget<SliverGrid>(find.byType(SliverGrid).first).gridDelegate
            as SliverGridDelegateWithFixedCrossAxisCount)
        .crossAxisCount;

Future<void> _mount(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: fixture.container,
      child: const ImageHostApp(),
    ),
  );
  await _flush(tester, fixture);
}

Future<void> _flush(WidgetTester tester, _Fixture fixture) async {
  // Native SQLite/file/isolate responses and fake-zone provider continuations
  // must alternate. Awaiting a provider future alone cannot flush both zones.
  // Keep the nominal 4 s IO tick budget, but provide more interleaving turns
  // without artificially advancing minute maintenance during one grid load.
  var idleFrames = 0;
  for (var i = 0; i < 2000 && idleFrames < 5; i++) {
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
            .isEmpty &&
        find.text('正在读取图片名称…', skipOffstage: false).evaluate().isEmpty) {
      idleFrames++;
    } else {
      idleFrames = 0;
    }
  }
  expect(idleFrames, 5, reason: 'Real library/preview work should finish.');
  await tester.pumpAndSettle();
}

class _Fixture {
  _Fixture(this.repository, this.container, this.assets);
  final LibraryRepository repository;
  final ProviderContainer container;
  final List<ImageAsset> assets;

  static Future<_Fixture> create(
    WidgetTester tester, {
    List<String> names = const [],
  }) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('imagehost_m1_widget_'),
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
        final saved = await repository.importResource(
          PlatformResource.file(source, displayName: names[i]),
        );
        expect(saved.status, ImportStatus.saved);
        assets.add(saved.asset!);
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
      expect(closed, isTrue, reason: 'Native database cleanup must complete.');
      await tester.runAsync(() => root.delete(recursive: true));
    });
    return _Fixture(repository, container, assets);
  }
}
