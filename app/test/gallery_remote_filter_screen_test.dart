import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/app.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/gallery_query.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/gallery/presentation/desktop_gallery.dart';
import 'package:imagehost/features/gallery/presentation/gallery_filter_controls.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:material_ui/material_ui.dart';

import 'core/upload_repository_test.dart' show QueueTestSecrets;

class _OpaqueFailure implements Exception {
  int stringifications = 0;
  @override
  String toString() {
    stringifications++;
    throw StateError('Unknown failures must not be converted to display text');
  }
}

Future<T> _native<T>(WidgetTester tester, Future<T> Function() action) async {
  var done = false;
  T? result;
  Object? failure;
  await tester.runAsync(() async {
    unawaited(
      action().then(
        (value) {
          result = value;
          done = true;
        },
        onError: (Object error) {
          failure = error;
          done = true;
        },
      ),
    );
  });
  for (var i = 0; i < 500 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done, isTrue, reason: '真实 SQLite / 文件 IO 必须完成');
  if (failure != null) throw failure!;
  return result as T;
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 500; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (ready()) return;
  }
  fail('图库组合筛选状态未完成');
}

class _Fixture {
  _Fixture(this.directory, this.repository, this.session, this.container);
  final Directory directory;
  final LibraryRepository repository;
  final LibrarySession session;
  final ProviderContainer container;
  Future<void>? _closing;
  static Future<_Fixture> open({bool targetMetadataFailure = false}) async {
    final directory = await Directory.systemTemp.createTemp(
      'imagehost-gallery-remote-ui-',
    );
    final repository = await LibraryRepository.open(
      Directory('${directory.path}/library'),
      secretStore: QueueTestSecrets(),
    );
    final session = LibrarySession(repository, const []);
    final container = ProviderContainer(
      overrides: [
        librarySessionProvider.overrideWith((_) async => session),
        if (targetMetadataFailure)
          galleryRemoteTargetsProvider.overrideWith(
            (_) async => throw StateError('fixture unavailable'),
          ),
      ],
    );
    return _Fixture(directory, repository, session, container);
  }

  Future<String> asset(String name, int width) async {
    final bytes = img.encodePng(img.Image(width: width, height: 4));
    return (await repository.importResource(
      PlatformResource(displayName: name, openRead: () => Stream.value(bytes)),
    )).asset!.id;
  }

  Future<String> target(String alias) => repository.saveTarget(
    service: ImageHostService.catbox,
    alias: alias,
    anonymous: false,
    credential: 'SyntheticAccountFixture0123456789',
  );
  int _sequence = 0;
  Future<void> evidence(String asset, String target, {String? url}) async {
    final batch = await repository.enqueueUploads(
      intentId: 'ui-evidence-${_sequence++}',
      assetIds: [asset],
      targetIds: [target],
      allowOriginalMetadata: true,
      forceAgain: true,
    );
    final execution = (await repository.beginUploadAttempt(
      batch.items.single.id,
    ))!;
    try {
      await repository.authorizeUploadRequest(execution.attemptId);
      await repository.finishUploadAttempt(
        execution,
        url == null
            ? const ProviderUploadFailure(
                UploadFailureKind.formatUnsupported,
                UploadDeliveryEvidence.confirmedRejected,
              )
            : ProviderUploadSuccess(
                service: ImageHostService.catbox,
                remoteId: Uri.parse(url).pathSegments.last,
                directUrl: Uri.parse(url),
              ),
        accumulatedRunning: Duration.zero,
      );
    } finally {
      await execution.release();
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    container.dispose();
    await session.close();
    await directory.delete(recursive: true);
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture, {
  bool app = false,
  double scale = 1,
}) async {
  addTearDown(() => _native(tester, fixture.close));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: fixture.container,
      child: app
          ? const ImageHostApp()
          : MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) {
                    final page = ref.watch(galleryProvider);
                    return Column(
                      children: [
                        FilledButton(
                          key: const Key('open-combined-filters'),
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => const GalleryFilterDialog(),
                          ),
                          child: const Text('组合筛选'),
                        ),
                        Expanded(
                          child: page.when(
                            data: (page) => ListView(
                              children: [
                                Text('匹配 ${page.total} 张'),
                                for (final asset in page.items)
                                  Text(asset.displayName),
                              ],
                            ),
                            loading: () => const CircularProgressIndicator(),
                            error: (_, _) => const Text('读取失败，记录保留'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
    ),
  );
  await _until(
    tester,
    () =>
        fixture.container.read(galleryProvider).hasValue &&
        !fixture.container.read(galleryProvider).isLoading,
  );
}

Future<void> _openFilters(
  WidgetTester tester, {
  bool mobile = false,
  bool desktop = false,
}) async {
  final finder = find.byKey(
    Key(
      mobile
          ? 'mobile-filters'
          : desktop
          ? 'desktop-filters'
          : 'open-combined-filters',
    ),
  );
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
  await _until(
    tester,
    () => find.byType(GalleryFilterDialog).evaluate().isNotEmpty,
  );
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is DropdownButtonFormField<String> &&
      widget.decoration.labelText == label,
);

Future<void> _bring(
  WidgetTester tester,
  Finder finder, {
  double delta = 250,
}) async {
  final scroll = find
      .byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      )
      .last;
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      delta,
      scrollable: scroll,
      maxScrolls: 30,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _choose(WidgetTester tester, String label, String value) async {
  final finder = _field(label);
  await _bring(tester, finder);
  tester.widget<DropdownButtonFormField<String>>(finder).onChanged!(value);
  await tester.pump();
}

void _size(WidgetTester tester, double width, {double height = 1000}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  testWidgets(
    'UT-017 SEC-003 desktop unknown query failure uses fixed feedback without stringification',
    (tester) async {
      _size(tester, 1280);
      final fixture = await _native(tester, _Fixture.open);
      addTearDown(() => _native(tester, fixture.close));
      final failure = _OpaqueFailure();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: MaterialApp(
            home: DesktopGallery(
              gallery: AsyncError<GalleryPage>(failure, StackTrace.current),
              session: AsyncData(fixture.session),
              busy: false,
              loadingMore: false,
              onImport: (_) async {},
              onRetry: () {},
              onRefresh: () async {},
              onLoadMore: () async {},
              notices: const [],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('读取失败，现有数据已保留。请检查空间或权限后重试。'), findsOneWidget);
      expect(failure.stringifications, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'UT-017 UT-018 AT-001 partial shared combined filters $width large text local empty',
      (tester) async {
        _size(tester, width);
        final fixture = await _native(tester, _Fixture.open);
        await _mount(tester, fixture, scale: 1.5);
        await _openFilters(tester);
        await _until(
          tester,
          () => fixture.container.read(galleryRemoteTargetsProvider).hasValue,
        );
        await _bring(tester, _field('上传记录状态'));
        expect(
          tester
              .widget<DropdownButton<String>>(
                find.descendant(
                  of: _field('上传记录状态'),
                  matching: find.byType(DropdownButton<String>),
                ),
              )
              .items!
              .map((i) => i.value),
          [
            '',
            'confirmed',
            'failed',
            'unknown',
            'active',
            'cancelled',
            'withoutLinks',
          ],
        );
        await _choose(tester, '上传记录状态', 'confirmed');
        await _bring(
          tester,
          find.byType(DropdownButtonFormField<GallerySort>),
          delta: -250,
        );
        final sorting = tester.widget<DropdownButtonFormField<GallerySort>>(
          find.byType(DropdownButtonFormField<GallerySort>),
        );
        expect(
          tester
              .widget<DropdownButton<GallerySort>>(
                find.byType(DropdownButton<GallerySort>),
              )
              .items!
              .singleWhere((item) => item.value == GallerySort.uploaded)
              .enabled,
          isTrue,
        );
        sorting.onChanged!(GallerySort.uploaded);
        await _until(
          tester,
          () => !fixture.container.read(galleryProvider).isLoading,
        );
        expect(
          fixture.container.read(galleryQueryProvider).sort,
          GallerySort.uploaded,
        );
        expect(fixture.container.read(galleryProvider).requireValue.total, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      'AT-001 partial ${platform.name} actual gallery exposes shared remote filters',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        _size(tester, platform == TargetPlatform.android ? 390 : 1280);
        final fixture = await _native(tester, _Fixture.open);
        await _mount(tester, fixture, app: true);
        final search = find.byKey(
          Key(
            platform == TargetPlatform.android
                ? 'mobile-search'
                : 'desktop-search',
          ),
        );
        await tester.enterText(search, 'pending draft');
        await tester.pump(const Duration(milliseconds: 50));
        fixture.container
            .read(galleryQueryProvider.notifier)
            .replace(const GalleryQuery(keyword: 'external keyword'));
        await tester.pump();
        expect(
          tester.widget<TextField>(search).controller!.text,
          'pending draft',
          reason: '外部查询变化不能覆盖 debounce 草稿',
        );
        await tester.pump(const Duration(milliseconds: 250));
        await _until(
          tester,
          () =>
              !fixture.container.read(galleryProvider).isLoading &&
              fixture.container.read(galleryQueryProvider).keyword ==
                  'pending draft',
        );
        await _openFilters(
          tester,
          mobile: platform == TargetPlatform.android,
          desktop: platform == TargetPlatform.windows,
        );
        await _until(
          tester,
          () => fixture.container.read(galleryRemoteTargetsProvider).hasValue,
        );
        await _choose(tester, '上传记录状态', 'withoutLinks');
        expect(
          fixture.container.read(galleryQueryProvider).uploadFilter,
          GalleryUploadFilter.withoutLinks,
        );
        await tester.tap(find.text('清空筛选与排序'));
        await _until(
          tester,
          () => !fixture.container.read(galleryProvider).isLoading,
        );
        expect(fixture.container.read(galleryQueryProvider).keyword, isEmpty);
        expect(
          tester.widget<TextField>(search).controller!.text,
          isEmpty,
          reason: '无草稿时共同清空动作须同步输入框',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets(
    'UT-017 category failed target intersect on same evidence stable removed target and nullable clear',
    (tester) async {
      _size(tester, 1280, height: 1400);
      final fixture = await _native(tester, _Fixture.open);
      final setup = await _native(tester, () async {
        final a = await fixture.asset('A failed old.png', 8),
            b = await fixture.asset('B failed old.png', 9);
        final old = await fixture.target('Same Alias');
        await fixture.evidence(a, old);
        await fixture.evidence(b, old);
        await fixture.repository.removeTarget(old);
        final current = await fixture.target('Same Alias');
        await fixture.evidence(
          a,
          current,
          url: 'https://files.catbox.moe/a.png',
        );
        final category = await fixture.repository.createCategory('Category A');
        await fixture.repository.assignCategory([a], category.id);
        return (a, b, old, current, category.id);
      });
      await _mount(tester, fixture);
      await _openFilters(tester);
      await _until(
        tester,
        () =>
            fixture.container.read(galleryRemoteTargetsProvider).hasValue &&
            fixture.container.read(categoriesProvider).hasValue,
      );
      expect(
        fixture.container
            .read(galleryRemoteTargetsProvider)
            .requireValue
            .map((t) => t.id)
            .toSet(),
        containsAll([setup.$3, setup.$4]),
      );
      await _choose(tester, '分类', setup.$5);
      await _choose(tester, '历史上传目标', setup.$3);
      await _choose(tester, '上传记录状态', 'failed');
      await _until(
        tester,
        () => !fixture.container.read(galleryProvider).isLoading,
      );
      expect(
        fixture.container
            .read(galleryProvider)
            .requireValue
            .items
            .map((a) => a.id),
        [setup.$1],
      );
      await _choose(tester, '历史上传目标', setup.$4);
      await _until(
        tester,
        () => !fixture.container.read(galleryProvider).isLoading,
      );
      expect(
        fixture.container.read(galleryProvider).requireValue.items,
        isEmpty,
        reason: '新目标成功不能与旧目标失败跨证据拼条件',
      );
      await _choose(tester, '历史上传目标', '');
      await _choose(tester, '图床服务', 'catbox');
      await _choose(tester, '图床服务', '');
      await _choose(tester, '上传图片类型', 'original');
      await _choose(tester, '上传图片类型', '');
      await _choose(tester, '上传记录状态', '');
      await _until(
        tester,
        () => !fixture.container.read(galleryProvider).isLoading,
      );
      final query = fixture.container.read(galleryQueryProvider);
      expect(query.remoteTargetId, isNull);
      expect(query.remoteService, isNull);
      expect(query.remoteInputKind, isNull);
      expect(query.uploadFilter, isNull);
      expect(query.categoryId, setup.$5);
      final asset = fixture.container
          .read(galleryProvider)
          .requireValue
          .items
          .single;
      expect(asset.confirmedRemoteResultCount, 1);
      expect(asset.lastConfirmedUploadAt, isNotNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'UT-017 disappeared remote UUID remains an explicit condition with clear control',
    (tester) async {
      _size(tester, 390);
      final fixture = await _native(tester, _Fixture.open);
      const absent = '65b4c417-6b79-40ba-8c2e-13998dc685d6';
      fixture.container
          .read(galleryQueryProvider.notifier)
          .replace(const GalleryQuery(remoteTargetId: absent));
      await _mount(tester, fixture);
      await _openFilters(tester);
      await _until(
        tester,
        () => fixture.container.read(galleryRemoteTargetsProvider).hasValue,
      );
      await _bring(tester, _field('历史上传目标'));
      expect(find.text('此目标暂无匹配记录，可清空条件'), findsOneWidget);
      expect(
        fixture.container.read(galleryQueryProvider).remoteTargetId,
        absent,
      );
      await _choose(tester, '历史上传目标', '');
      expect(
        fixture.container.read(galleryQueryProvider).remoteTargetId,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'UT-017 remote metadata failure retains missing UUID until explicit clear',
    (tester) async {
      _size(tester, 390);
      final fixture = await _native(
        tester,
        () => _Fixture.open(targetMetadataFailure: true),
      );
      const absent = 'd09bd8f8-5d20-4072-b177-00340a7a2a91';
      fixture.container
          .read(galleryQueryProvider.notifier)
          .replace(
            const GalleryQuery(
              remoteTargetId: absent,
              remoteService: ImageHostService.catbox,
              uploadFilter: GalleryUploadFilter.confirmed,
            ),
          );
      await _mount(tester, fixture);
      await _openFilters(tester);
      await _until(
        tester,
        () => fixture.container.read(galleryRemoteTargetsProvider).hasError,
      );
      await _bring(tester, find.text('历史目标读取失败，目标选择已暂停，现有筛选条件保持。'));
      expect(_field('历史上传目标'), findsNothing);
      expect(
        fixture.container.read(galleryQueryProvider).remoteTargetId,
        absent,
      );
      await _bring(
        tester,
        find.byKey(const Key('gallery-clear-remote-filters')),
      );
      await tester.tap(find.byKey(const Key('gallery-clear-remote-filters')));
      await tester.pump();
      expect(
        fixture.container.read(galleryQueryProvider).remoteTargetId,
        isNull,
      );
      expect(
        fixture.container.read(galleryQueryProvider).remoteService,
        isNull,
      );
      expect(fixture.container.read(galleryQueryProvider).uploadFilter, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
