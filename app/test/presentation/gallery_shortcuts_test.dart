import 'dart:io';

import 'package:crypto/crypto.dart' as hashing;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/gallery/presentation/asset_widgets.dart';
import 'package:imagehost/features/gallery/presentation/gallery_screen.dart';
import 'package:imagehost/features/gallery/presentation/library_organization_editor.dart';
import 'package:imagehost/features/gallery/presentation/original_preview_screen.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/processing/presentation/processing_workbench.dart';
import 'package:imagehost/features/upload/application/upload_coordinator.dart';
import 'package:imagehost/features/upload/data/library_upload_queue_store.dart';
import 'package:imagehost/features/upload/data/provider_adapters.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/presentation/upload_tasks_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqlite3/sqlite3.dart';

import 'mobile_recycle_test.dart'
    show MobileTestFixture, mobileNative, selectMobileAsset, openMobileRecycle;

// Real temporary SQLite and widget navigation; no device PT or service requests.
void main() {
  for (final replacedRevision in [true, false]) {
    testWidgets(
      'original route freezes identity before builder starts ($replacedRevision)',
      (tester) async {
        final fixture = await _create(tester, ['冻结原图.png']);
        var sessionReads = 0;
        final container = ProviderContainer(
          overrides: [
            librarySessionProvider.overrideWith((_) async {
              sessionReads++;
              return fixture.$3;
            }),
          ],
        );
        addTearDown(container.dispose);
        final revision = container.read(libraryReplacementRevisionProvider);
        final entry = OriginalPreviewScreen(
          asset: fixture.$1.assets.single,
          initialLibraryRevision: revision,
          initialExecutionEpoch: replacedRevision
              ? fixture.$1.repository.executionEpoch
              : 'stale-execution-epoch',
        );
        if (replacedRevision) {
          container
              .read(libraryReplacementRevisionProvider.notifier)
              .committed();
        }
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(home: entry),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('资料库已替换，原图入口已失效；请返回图库重新打开。'), findsOneWidget);
        expect(sessionReads, replacedRevision ? 0 : 1);
        expect(find.byType(RawImage), findsNothing);
        expect(find.byType(InteractiveViewer), findsNothing);
        expect(fixture.$1.repository.processingScheduler.activeCount, 0);
        final leaseCount = await mobileNative(tester, () async {
          final db = sqlite3.open(
            '${fixture.$1.libraryRoot.path}/library.sqlite',
          );
          try {
            return db.select('SELECT id FROM file_leases').length;
          } finally {
            db.close();
          }
        });
        expect(leaseCount, 0);
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, '重试预览'))
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  test('organization errors never format unknown objects', () {
    final error = _UnformattableError();
    expect(organizationError(error), '整理未确认保存，已有信息保留，请重新读取后核对。');
    expect(error.formatted, false);
  });

  for (final recycled in [false, true]) {
    testWidgets(
      'old M1 details reject shortcuts and writes after same UUID replacement ($recycled)',
      (tester) async {
        final fixture = await _create(tester, ['旧详情.png']);
        final id = fixture.$1.assets.single.id;
        if (recycled) {
          await mobileNative(
            tester,
            () => fixture.$1.repository.removeAssets([id]),
          );
          await mobileNative(
            tester,
            () => fixture.$1.container.read(galleryProvider.notifier).reload(),
          );
        }
        await _mount(tester, fixture.$1, const GalleryScreen());
        if (recycled) await openMobileRecycle(tester, fixture.$1);
        await _tap(tester, find.byKey(Key('mobile-asset-$id')));
        await _flushShortcuts(tester, fixture.$1);
        final keys = recycled
            ? ['mobile-restore-asset', 'mobile-purge-asset']
            : [
                'mobile-favorite',
                'mobile-organize',
                'mobile-remove-asset',
                'mobile-edit-copy',
                'mobile-upload-original',
              ];
        final oldCallbacks = keys
            .map((key) => _buttonCallback(tester, key)!)
            .toList();
        fixture.$1.container
            .read(libraryReplacementRevisionProvider.notifier)
            .committed();
        // Invoke the old frame's callbacks before a rebuild to exercise the
        // synchronous guard as well as the disabled replacement UI.
        for (final callback in oldCallbacks) {
          callback();
        }
        await _flushShortcuts(tester, fixture.$1);
        expect(find.text('资料库已替换，此详情保留原信息；请返回图库重新打开，当前操作已禁用。'), findsOneWidget);
        final details = find.ancestor(
          of: find.text('图片详情'),
          matching: find.byType(Scaffold),
        );
        expect(
          find.descendant(
            of: details,
            matching: find.byType(AssetPreviewImage),
          ),
          findsNothing,
        );
        expect(find.text('资料库已替换，副本校验已禁用。'), findsOneWidget);
        for (final key in keys) {
          expect(_buttonCallback(tester, key), isNull);
        }
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(ProcessingWorkbench), findsNothing);
        expect(find.byType(UploadTasksScreen), findsNothing);
        final asset = await mobileNative(
          tester,
          () => fixture.$1.repository.getAsset(id, includeRecycled: true),
        );
        expect(asset!.recycled, recycled);
        expect(asset.favorite, false);
        expect(asset.categoryId, isNull);
        await _noWork(tester, fixture);
        await _tap(tester, find.byKey(const Key('mobile-detail-back')));
        await _flushShortcuts(tester, fixture.$1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'organization draft keeps old content and cannot save or manage after replacement',
    (tester) async {
      final fixture = await _create(tester, ['整理旧图.png']);
      final id = fixture.$1.assets.single.id;
      await _mount(tester, fixture.$1, const GalleryScreen());
      await _tap(tester, find.byKey(Key('mobile-asset-$id')));
      await _flushShortcuts(tester, fixture.$1);
      await _tap(tester, find.byKey(const Key('mobile-organize')));
      await _flushShortcuts(tester, fixture.$1);
      await tester.enterText(find.byKey(const Key('organization-tags')), '旧草稿');
      final oldSave = tester
          .widget<FilledButton>(find.byKey(const Key('organization-save')))
          .onPressed!;
      fixture.$1.container
          .read(libraryReplacementRevisionProvider.notifier)
          .committed();
      oldSave();
      await _flushShortcuts(tester, fixture.$1);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('organization-tags')))
            .controller!
            .text,
        '旧草稿',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('organization-tags')))
            .enabled,
        false,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('organization-save')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '管理分类'))
            .onPressed,
        isNull,
      );
      expect(find.text('资料库已替换，当前整理草稿保留；请返回图库重新打开，当前操作已禁用。'), findsOneWidget);
      expect(
        (await mobileNative(
          tester,
          () => fixture.$1.repository.getAsset(id),
        ))!.tags,
        isEmpty,
      );
      await _tap(tester, find.widgetWithText(TextButton, '取消'));
      await _noWork(tester, fixture);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final openNameEditor in [false, true]) {
    testWidgets(
      'category dialog tree freezes identity before replacement ($openNameEditor)',
      (tester) async {
        final fixture = await _create(tester, ['分类旧图.png']);
        final id = fixture.$1.assets.single.id;
        final category = await mobileNative(
          tester,
          () => fixture.$1.repository.createCategory('旧分类'),
        );
        await _mount(tester, fixture.$1, const GalleryScreen());
        await _tap(tester, find.byKey(Key('mobile-asset-$id')));
        await _flushShortcuts(tester, fixture.$1);
        await _tap(tester, find.byKey(const Key('mobile-organize')));
        await _flushShortcuts(tester, fixture.$1);
        await _tap(tester, find.widgetWithText(TextButton, '管理分类'));
        await _flushShortcuts(tester, fixture.$1);
        final oldEdit = tester
            .widget<IconButton>(
              find.byKey(Key('category-rename-${category.id}')),
            )
            .onPressed!;
        final oldRemove = tester
            .widget<IconButton>(
              find.byKey(Key('category-remove-${category.id}')),
            )
            .onPressed!;
        VoidCallback? oldSave;
        if (openNameEditor) {
          await _tap(tester, find.byKey(Key('category-rename-${category.id}')));
          await _flushShortcuts(tester, fixture.$1);
          await tester.enterText(
            find.byKey(const Key('category-name')),
            '旧改名草稿',
          );
          oldSave = tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '确定'))
              .onPressed!;
        }
        fixture.$1.container
            .read(libraryReplacementRevisionProvider.notifier)
            .committed();
        if (openNameEditor) {
          oldSave!();
        } else {
          oldEdit();
          oldRemove();
        }
        await _flushShortcuts(tester, fixture.$1);
        if (openNameEditor) {
          expect(
            tester
                .widget<TextField>(find.byKey(const Key('category-name')))
                .enabled,
            false,
          );
          expect(
            tester
                .widget<TextField>(find.byKey(const Key('category-name')))
                .controller!
                .text,
            '旧改名草稿',
          );
          expect(
            tester
                .widget<FilledButton>(find.widgetWithText(FilledButton, '确定'))
                .onPressed,
            isNull,
          );
          final nameDialog = find.ancestor(
            of: find.byKey(const Key('category-name')),
            matching: find.byType(AlertDialog),
          );
          expect(nameDialog, findsOneWidget);
          await _tap(
            tester,
            find.descendant(
              of: nameDialog,
              matching: find.widgetWithText(TextButton, '取消'),
            ),
          );
          await _flushShortcuts(tester, fixture.$1);
          expect(find.byKey(const Key('category-name')), findsNothing);
          expect(
            find.byKey(Key('category-rename-${category.id}')),
            findsOneWidget,
          );
        }
        expect(
          tester
              .widget<IconButton>(
                find.byKey(Key('category-rename-${category.id}')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<IconButton>(
                find.byKey(Key('category-remove-${category.id}')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, '新建分类'))
              .onPressed,
          isNull,
        );
        final categories = await mobileNative(
          tester,
          fixture.$1.repository.listCategories,
        );
        expect(categories.single.id, category.id);
        expect(categories.single.name, '旧分类');
        await _tap(tester, find.widgetWithText(FilledButton, '关闭'));
        await _noWork(tester, fixture);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  for (final operation in [
    ProcessingOperation.compress,
    ProcessingOperation.stitch,
  ]) {
    testWidgets(
      'M1 selected $operation opens review with exact UUIDs and no processing',
      (tester) async {
        final fixture = await _create(tester, ['甲.png', '乙.png']);
        await _mount(tester, fixture.$1, const GalleryScreen());
        final ids = fixture.$1.assets.map((asset) => asset.id).toList();
        await selectMobileAsset(tester, fixture.$1, ids.first);
        final stitch = find.byKey(const Key('mobile-stitch-selection'));
        expect(tester.widget<OutlinedButton>(stitch).onPressed, isNull);
        await _tap(tester, find.byKey(Key('mobile-asset-${ids.last}')));
        await _tap(
          tester,
          find.byKey(Key('mobile-${operation.name}-selection')),
        );
        await _flushShortcuts(tester, fixture.$1);
        final page = tester.widget<ProcessingWorkbench>(
          find.byType(ProcessingWorkbench),
        );
        expect(page.initialAssetIds, ids);
        expect(page.initialOperation, operation);
        expect(
          tester
              .widget<DropdownButton<ProcessingOperation>>(
                find.byType(DropdownButton<ProcessingOperation>),
              )
              .value,
          operation,
        );
        expect(_selectedProcessing(tester), ids.toSet());
        if (operation == ProcessingOperation.stitch) {
          expect(
            tester
                .widget<CheckboxListTile>(
                  find.widgetWithText(CheckboxListTile, '确认以上拼接顺序'),
                )
                .value,
            false,
          );
        }
        await _noWork(tester, fixture);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'M1 details crop and original upload return through gallery and retain confirmations',
    (tester) async {
      final fixture = await _create(tester, ['详情.png']);
      final id = fixture.$1.assets.single.id;
      await _mount(tester, fixture.$1, const GalleryScreen());
      await _tap(tester, find.byKey(Key('mobile-asset-$id')));
      await _flushShortcuts(tester, fixture.$1);
      await _tap(tester, find.byKey(const Key('mobile-edit-copy')));
      await _flushShortcuts(tester, fixture.$1);
      final workbench = tester.widget<ProcessingWorkbench>(
        find.byType(ProcessingWorkbench),
      );
      expect(workbench.initialOperation, ProcessingOperation.crop);
      expect(_selectedProcessing(tester), {id});
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('processing-crop-width')))
            .controller!
            .text,
        '6',
      );
      await _noWork(tester, fixture);
      await _tap(tester, find.byTooltip('返回图库'));
      await _flushShortcuts(tester, fixture.$1);
      expect(find.byKey(const Key('mobile-edit-copy')), findsNothing);
      await _tap(tester, find.byKey(Key('mobile-asset-$id')));
      await _flushShortcuts(tester, fixture.$1);
      await _tap(tester, find.byKey(const Key('mobile-upload-original')));
      await _flushShortcuts(tester, fixture.$1);
      final upload = tester.widget<UploadTasksScreen>(
        find.byType(UploadTasksScreen),
      );
      expect(upload.initialAssetIds, [id]);
      expect(upload.initialOriginal, true);
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(Key('upload-source-$id')))
            .value,
        true,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, '我确认上传原图，可能包含位置、设备等元数据'),
            )
            .value,
        false,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认并入队'))
            .onPressed,
        isNull,
      );
      await _noWork(tester, fixture);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'M1 batch upload retains automatic processing draft without enqueue or authorization',
    (tester) async {
      final fixture = await _create(tester, ['上传.png']);
      final id = fixture.$1.assets.single.id;
      await _mount(tester, fixture.$1, const GalleryScreen());
      await selectMobileAsset(tester, fixture.$1, id);
      await _tap(tester, find.byKey(const Key('mobile-upload-selection')));
      await _flushShortcuts(tester, fixture.$1);
      expect(
        tester
            .widget<UploadTasksScreen>(find.byType(UploadTasksScreen))
            .initialOriginal,
        false,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '上传前自动处理'))
            .selected,
        true,
      );
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(Key('upload-source-$id')))
            .value,
        true,
      );
      await _noWork(tester, fixture);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final upload in [false, true]) {
    testWidgets(
      'entry created before replacement cannot select the same UUID in the new revision ($upload)',
      (tester) async {
        final fixture = await _create(tester, ['同UUID.png']);
        final id = fixture.$1.assets.single.id;
        final revision = fixture.$1.container.read(
          libraryReplacementRevisionProvider,
        );
        final Widget entry = upload
            ? UploadTasksScreen(
                initialAssetIds: [id],
                initialOriginal: true,
                initialLibraryRevision: revision,
              )
            : ProcessingWorkbench(
                initialAssetIds: [id],
                initialOperation: ProcessingOperation.crop,
                initialLibraryRevision: revision,
              );
        fixture.$1.container
            .read(libraryReplacementRevisionProvider.notifier)
            .committed();
        await _mount(tester, fixture.$1, entry);
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(
                  Key('${upload ? 'upload-source' : 'processing-asset'}-$id'),
                ),
              )
              .value,
          false,
        );
        expect(
          find.text(
            upload ? '资料库已替换，请重新选择图片并确认上传参数。' : '资料库已替换，请重新选择原图并确认处理参数。',
          ),
          findsOneWidget,
        );
        if (upload) {
          expect(
            tester
                .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '上传前自动处理'))
                .selected,
            true,
          );
          expect(find.text('我确认上传原图，可能包含位置、设备等元数据'), findsNothing);
        }
        await _noWork(tester, fixture);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'refresh preserves unavailable selection and requires explicit removal ($upload)',
      (tester) async {
        final fixture = await _create(tester, ['随后回收.png']);
        final id = fixture.$1.assets.single.id;
        await _mount(
          tester,
          fixture.$1,
          upload
              ? UploadTasksScreen(initialAssetIds: [id])
              : ProcessingWorkbench(initialAssetIds: [id]),
        );
        await mobileNative(
          tester,
          () => fixture.$1.repository.removeAssets([id]),
        );
        await _tap(
          tester,
          upload ? find.byTooltip('刷新上传资料') : find.text('刷新原图与结果'),
        );
        await _flushShortcuts(tester, fixture.$1);
        expect(
          find.textContaining(
            upload ? '已选 1 张图片已移除或进入回收区，入队已禁用' : '已选 1 张图片已移除或进入回收区，处理已禁用',
          ),
          findsOneWidget,
        );
        expect(
          upload ? find.textContaining('已选 1 张') : find.text('1 · 选择原图（1 项）'),
          findsWidgets,
        );
        final start = upload
            ? find.widgetWithText(FilledButton, '确认并入队')
            : find.byKey(const Key('processing-start'));
        expect(tester.widget<FilledButton>(start).onPressed, isNull);
        await _tap(tester, find.text(upload ? '移除当前列表之外的输入选择' : '清除失效选择'));
        await tester.pump();
        expect(
          upload ? find.textContaining('已选 0 张') : find.text('1 · 选择原图（0 项）'),
          findsOneWidget,
        );
        await _noWork(tester, fixture);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets('shortcut beyond first 60 keeps pagination intact ($upload)', (
      tester,
    ) async {
      final fixture = await _create(
        tester,
        List.generate(62, (i) => '图$i.png'),
      );
      final page = await mobileNative(
        tester,
        () => fixture.$1.repository.listAssets(limit: 60),
      );
      final visible = page.items.map((asset) => asset.id).toSet();
      final id = fixture.$1.assets
          .firstWhere((asset) => !visible.contains(asset.id))
          .id;
      // This case verifies pagination and deliberate selection. Generate real
      // caches first in the native zone; cold batch generation is validated
      // separately from widget scheduling and device performance.
      await _warmShortcutThumbnails(tester, fixture.$1);
      await _mount(
        tester,
        fixture.$1,
        upload
            ? UploadTasksScreen(initialAssetIds: [id])
            : ProcessingWorkbench(initialAssetIds: [id]),
      );
      final key = Key('${upload ? 'upload-source' : 'processing-asset'}-$id');
      expect(tester.widget<CheckboxListTile>(find.byKey(key)).value, true);
      if (upload) {
        expect(find.text('已加载 60 / 62 张；已选 1 张'), findsOneWidget);
        await _tap(tester, find.text('加载更多原图'));
      } else {
        expect(find.text('加载更多（60/62）'), findsOneWidget);
        await _tap(tester, find.text('加载更多（60/62）'));
      }
      final sourceTiles = find.byWidgetPredicate(
        (widget) =>
            widget is CheckboxListTile &&
            widget.key.toString().contains(
              upload ? 'upload-source-' : 'processing-asset-',
            ),
      );
      await _flushShortcuts(
        tester,
        fixture.$1,
        ready: () => sourceTiles.evaluate().length == 62,
      );
      expect(sourceTiles, findsNWidgets(62));
      expect(tester.widget<CheckboxListTile>(find.byKey(key)).value, true);
      // Refresh preserves a deliberate deselection and never reapplies entry IDs.
      await _tap(tester, find.byKey(key));
      await _tap(
        tester,
        upload ? find.byTooltip('刷新上传资料') : find.text('刷新原图与结果'),
      );
      await _flushShortcuts(tester, fixture.$1);
      expect(
        upload ? find.textContaining('已选 0 张') : find.text('1 · 选择原图（0 项）'),
        findsOneWidget,
      );
      await _noWork(tester, fixture);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets(
      'missing shortcut does not partially select; replacement never revives UUID ($upload)',
      (tester) async {
        final fixture = await _create(tester, ['可见.png', '已回收.png']);
        final id = fixture.$1.assets.first.id;
        final recycled = fixture.$1.assets.last.id;
        await mobileNative(
          tester,
          () => fixture.$1.repository.removeAssets([recycled]),
        );
        await _mount(
          tester,
          fixture.$1,
          upload
              ? UploadTasksScreen(initialAssetIds: [id, recycled, 'missing-id'])
              : ProcessingWorkbench(
                  initialAssetIds: [id, recycled, 'missing-id'],
                ),
        );
        expect(
          find.text('快捷入口中 2 张图片已移除或进入回收区，未预选任何图片，请重新选择。'),
          findsOneWidget,
        );
        final key = Key('${upload ? 'upload-source' : 'processing-asset'}-$id');
        expect(tester.widget<CheckboxListTile>(find.byKey(key)).value, false);
        await tester.pumpWidget(const SizedBox());
        await _mount(
          tester,
          fixture.$1,
          upload
              ? UploadTasksScreen(initialAssetIds: [id])
              : ProcessingWorkbench(initialAssetIds: [id]),
        );
        expect(tester.widget<CheckboxListTile>(find.byKey(key)).value, true);
        fixture.$1.container
            .read(libraryReplacementRevisionProvider.notifier)
            .committed();
        await _flushShortcuts(tester, fixture.$1);
        expect(tester.widget<CheckboxListTile>(find.byKey(key)).value, false);
        await _noWork(tester, fixture);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}

Set<String> _selectedProcessing(WidgetTester tester) => find
    .byType(CheckboxListTile)
    .evaluate()
    .map((element) => element.widget as CheckboxListTile)
    .where(
      (widget) =>
          widget.value == true &&
          widget.key is ValueKey<String> &&
          widget.key.toString().contains('processing-asset-'),
    )
    .map(
      (widget) => (widget.key as ValueKey<String>).value.substring(
        'processing-asset-'.length,
      ),
    )
    .toSet();

VoidCallback? _buttonCallback(WidgetTester tester, String key) {
  final button = tester.widget(find.byKey(Key(key)));
  if (button is IconButton) return button.onPressed;
  return (button as ButtonStyleButton).onPressed;
}

class _UnformattableError {
  bool formatted = false;
  @override
  String toString() {
    formatted = true;
    throw StateError('Must not format unknown errors');
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _mount(
  WidgetTester tester,
  MobileTestFixture fixture,
  Widget page,
) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: fixture.container,
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: page,
      ),
    ),
  );
  await _flushShortcuts(tester, fixture);
}

Future<void> _warmShortcutThumbnails(
  WidgetTester tester,
  MobileTestFixture fixture,
) async {
  final warmed = await tester.runAsync(() async {
    for (final asset in fixture.assets) {
      expect(
        await fixture.repository.verifyCopy(asset),
        CopyAvailability.available,
      );
      final lease = await fixture.repository.acquireThumbnailLease(asset);
      expect(lease, isNotNull);
      final current = lease!;
      try {
        // readBytes verifies the registered digest/length. Independently read
        // the actual generated file while its cache hold remains owned.
        final bytes = await current.readBytes();
        final stored = await current.file.readAsBytes();
        expect(bytes, isNotEmpty);
        expect(await current.file.length(), bytes.length);
        expect(stored.length, bytes.length);
        expect(hashing.sha256.convert(stored), hashing.sha256.convert(bytes));
      } finally {
        await current.release();
      }
    }
    final db = sqlite3.open('${fixture.libraryRoot.path}/library.sqlite');
    try {
      expect(db.select('SELECT id FROM file_leases'), isEmpty);
    } finally {
      db.close();
    }
    return true;
  });
  expect(
    warmed,
    true,
    reason: 'All real thumbnail caches must finish warming.',
  );
}

Future<void> _flushShortcuts(
  WidgetTester tester,
  MobileTestFixture fixture, {
  bool Function()? ready,
}) async {
  // Alternate native IO with fake-zone continuations without adding a 10 ms
  // delay to every file/SQL await in the serial thumbnail writer. Keep the
  // same real-time deadline and wait for every mounted preview, including
  // hidden routes whose Riverpod subscriptions are paused by TickerMode.
  final elapsed = Stopwatch()..start();
  var idle = 0;
  while (idle < 5 && elapsed.elapsed < const Duration(seconds: 45)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    final previews = _shortcutPreviewStates(fixture);
    // A hidden Consumer can retain an old loading widget after its actual
    // Future completes. Visible rendering and actual provider work are checked
    // separately; hiding a route cannot excuse unfinished thumbnail IO.
    final indicators = find.byWidgetPredicate(
      (widget) =>
          widget is CircularProgressIndicator ||
          widget is LinearProgressIndicator,
    );
    final complete =
        !fixture.container.read(galleryProvider).isLoading &&
        previews.every((preview) => !preview.state.isLoading) &&
        indicators.evaluate().isEmpty &&
        find.text('正在读取…').evaluate().isEmpty &&
        fixture.repository.processingScheduler.activeCount == 0 &&
        (ready?.call() ?? true);
    idle = complete ? idle + 1 : 0;
  }
  if (idle != 5) {
    final previews = _shortcutPreviewStates(fixture);
    final pending = previews
        .where((preview) => preview.state.isLoading)
        .map((preview) => preview.image.asset.id)
        .toSet();
    debugPrint(
      'Shortcut IO timeout: pending thumbnails=${pending.length}, IDs=${pending.take(5).join(",")}, '
      'active pixels=${fixture.repository.processingScheduler.activeCount}, '
      'gallery loading=${fixture.container.read(galleryProvider).isLoading}, '
      'pagination reading=${find.text("正在读取…", skipOffstage: false).evaluate().length}, '
      'elapsed=${elapsed.elapsedMilliseconds}ms',
    );
    final indicators = find.byWidgetPredicate(
      (widget) =>
          widget is CircularProgressIndicator ||
          widget is LinearProgressIndicator,
      skipOffstage: false,
    );
    for (final element in indicators.evaluate().take(8)) {
      final ancestors = <String>[];
      element.visitAncestorElements((ancestor) {
        ancestors.add(ancestor.widget.runtimeType.toString());
        return ancestors.length < 12;
      });
      debugPrint(
        'Shortcut indicator: ${element.widget.runtimeType}, '
        'ticker=${TickerMode.getValuesNotifier(element).value.enabled}, '
        'routeCurrent=${ModalRoute.of(element)?.isCurrent}, '
        'ancestors=${ancestors.join(" > ")}',
      );
    }
    for (final preview in previews.take(8)) {
      debugPrint(
        'Shortcut provider: asset=${preview.image.asset.id}, '
        'frame=${preview.image.selectedFrame ?? 0}, '
        'loading=${preview.state.isLoading}, '
        'hasData=${preview.state.hasValue}, '
        'hasError=${preview.state.hasError}, '
        'ticker=${TickerMode.getValuesNotifier(preview.element).value.enabled}, '
        'routeCurrent=${ModalRoute.of(preview.element)?.isCurrent}',
      );
    }
  }
  expect(
    idle,
    5,
    reason:
        'Every real thumbnail, page read and widget continuation must finish.',
  );
  await tester.pumpAndSettle();
  // Provider completion must include the real input-read lease finalizers.
  // Cached display holds do not create persistent file_leases and remain
  // intentionally owned by mounted previews.
  final leaseCount = await mobileNative(tester, () async {
    final db = sqlite3.open('${fixture.libraryRoot.path}/library.sqlite');
    try {
      return db.select('SELECT id FROM file_leases').length;
    } finally {
      db.close();
    }
  });
  expect(leaseCount, 0, reason: 'Actual thumbnail input leases must drain.');
}

List<
  ({Element element, AssetPreviewImage image, AsyncValue<AssetPreview> state})
>
_shortcutPreviewStates(MobileTestFixture fixture) => find
    .byType(AssetPreviewImage, skipOffstage: false)
    .evaluate()
    .map((element) {
      final image = element.widget as AssetPreviewImage;
      final frame = image.selectedFrame;
      final state = fixture.container.read(
        frame == null
            ? assetPreviewProvider(image.asset)
            : assetFramePreviewProvider((image.asset, frame)),
      );
      return (element: element, image: image, state: state);
    })
    .toList();

Future<(MobileTestFixture, _NoNetworkAdapter, LibrarySession)> _create(
  WidgetTester tester,
  List<String> names,
) async {
  final base = await MobileTestFixture.create(tester, names: names);
  final adapter = _NoNetworkAdapter();
  final queue = UploadCoordinator(
    LibraryUploadQueueStore(base.repository),
    adapters: [adapter],
  );
  final session = LibrarySession(base.repository, const [], uploads: queue);
  final container = ProviderContainer(
    overrides: [librarySessionProvider.overrideWith((_) async => session)],
  );
  await mobileNative(tester, () => container.read(galleryProvider.future));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await mobileNative(tester, session.close);
  });
  return (
    MobileTestFixture(
      base.repository,
      container,
      base.assets,
      base.libraryRoot,
    ),
    adapter,
    session,
  );
}

Future<void> _noWork(
  WidgetTester tester,
  (MobileTestFixture, _NoNetworkAdapter, LibrarySession) fixture,
) async {
  expect(
    await mobileNative(tester, fixture.$1.repository.listOutputs),
    isEmpty,
  );
  expect(
    await mobileNative(tester, fixture.$1.repository.listUploadBatches),
    isEmpty,
  );
  expect(
    await mobileNative(tester, fixture.$1.repository.listUploadProcessingJobs),
    isEmpty,
  );
  expect(fixture.$2.calls, 0);
  expect(fixture.$3.uploads.networkAllowed, false);
}

class _NoNetworkAdapter implements ProviderAdapter {
  int calls = 0;
  @override
  ImageHostService get service => ImageHostService.catbox;
  @override
  ProviderUploadLimits get limits =>
      ProviderUploadLimits(maximumBytes: 1000000, formats: {'png'});
  @override
  Future<ProviderUploadResult> upload({
    required File file,
    required String actualFormat,
    required int expectedBytes,
    required ResolvedTarget target,
    required CancelToken cancelToken,
    UploadActivityCallback? onActivity,
  }) async {
    calls++;
    throw StateError('Shortcut must never start a request');
  }
}
