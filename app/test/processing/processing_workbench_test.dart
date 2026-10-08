import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/processing/domain/output_models.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/processing/presentation/processing_workbench.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'AT-002 replacement notification clears workbench UUID choices before reloading',
    (tester) async {
      _size(tester, 1280);
      final fixture = await _Fixture.create(tester);
      await _mount(tester, fixture.container);
      await _flush(tester);
      final tile = find.byKey(
        Key('processing-asset-${fixture.assets.single.id}'),
      );
      await tester.tap(tile);
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(tile).value, true);
      fixture.container
          .read(libraryReplacementRevisionProvider.notifier)
          .committed();
      await _flush(tester);
      expect(tester.widget<CheckboxListTile>(tile).value, false);
      expect(find.text('1 · 选择原图（0 项）'), findsOneWidget);
      expect(find.text('资料库已替换，请重新选择原图并确认处理参数。'), findsOneWidget);
      expect(await _native(tester, fixture.repository.listOutputs), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final width in [320.0, 1280.0]) {
    testWidgets(
      'AT-002 partial shared workbench $width loading empty/error without overflow',
      (tester) async {
        _size(tester, width);
        final fixture = await _Fixture.create(tester, count: 0);
        await _mount(tester, fixture.container);
        await _flush(tester);
        expect(find.text('图库还是空的，请返回图库导入图片。'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const Key('processing-start')));
        await tester.tap(find.byKey(const Key('processing-start')));
        await tester.pump();
        expect(find.textContaining('请先选择图片'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        final pending = Completer<LibrarySession>();
        final container = ProviderContainer(
          overrides: [
            librarySessionProvider.overrideWith((_) => pending.future),
          ],
        );
        await _mount(tester, container);
        await tester.pump();
        expect(find.text('正在打开本机图库…'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('processing-start')))
              .onPressed,
          null,
        );
        pending.completeError(const LibraryOpenException('测试加载失败，原库保留。'));
        await _flush(tester);
        expect(find.textContaining('加载失败'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        container.dispose();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'AT-002 real size-first compression -> durable output -> permanent save',
    (tester) async {
      _size(tester, 1280);
      final fixture = await _Fixture.create(tester);
      await _mount(tester, fixture.container);
      await _flush(tester);
      await tester.tap(
        find.byKey(Key('processing-asset-${fixture.assets.single.id}')),
      );
      await tester.pump();
      await _choose<ProcessingMode>(tester, '体积优先');
      await tester.ensureVisible(
        find.byKey(const Key('processing-longest-side')),
      );
      await tester.enterText(
        find.byKey(const Key('processing-longest-side')),
        '4',
      );
      await _start(tester);
      final output = (await _native(
        tester,
        fixture.repository.listOutputs,
      )).single;
      expect(output.usable, true);
      expect(output.version!.width, 4);
      expect(output.version!.height, 3);
      expect(output.request.longestSide, 4);
      final save = find.byKey(Key('processing-save-${output.id}'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await _flush(tester);
      expect(find.textContaining('已永久保存：'), findsOneWidget);
      expect((await _native(tester, fixture.repository.listAssets)).total, 2);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'AT-002 crop rejects decimal pixels then confirms real integer result',
    (tester) async {
      _size(tester, 390);
      final fixture = await _Fixture.create(tester);
      await _mount(tester, fixture.container);
      await _flush(tester);
      await tester.tap(
        find.byKey(Key('processing-asset-${fixture.assets.single.id}')),
      );
      await tester.pump();
      await _choose<ProcessingOperation>(tester, '裁剪（单张）');
      await tester.ensureVisible(find.byKey(const Key('processing-crop-x')));
      await tester.enterText(find.byKey(const Key('processing-crop-x')), '0.5');
      await _start(tester);
      expect(find.textContaining('X 必须是'), findsOneWidget);
      expect(await _native(tester, fixture.repository.listOutputs), isEmpty);
      await tester.ensureVisible(find.byKey(const Key('processing-crop-x')));
      await tester.enterText(find.byKey(const Key('processing-crop-x')), '1');
      await tester.enterText(find.byKey(const Key('processing-crop-y')), '1');
      await tester.enterText(
        find.byKey(const Key('processing-crop-width')),
        '3',
      );
      await tester.enterText(
        find.byKey(const Key('processing-crop-height')),
        '2',
      );
      await _start(tester);
      final output = (await _native(
        tester,
        fixture.repository.listOutputs,
      )).single;
      expect(output.usable, true);
      expect(output.version!.width, 3);
      expect(output.version!.height, 2);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'AT-002 stitching uses user-confirmed reversed order and actual geometry',
    (tester) async {
      _size(tester, 1280);
      final fixture = await _Fixture.create(tester, count: 2);
      await _mount(tester, fixture.container);
      await _flush(tester);
      for (final asset in fixture.assets) {
        await tester.tap(find.byKey(Key('processing-asset-${asset.id}')));
        await tester.pump();
      }
      await _choose<ProcessingOperation>(tester, '拼接（一组）');
      await _choose<StitchLayout>(tester, '横向');
      await tester.ensureVisible(find.byTooltip('下移').first);
      await tester.tap(find.byTooltip('下移').first);
      await tester.pump();
      await _start(tester);
      expect(find.textContaining('请确认下方顺序'), findsOneWidget);
      await tester.ensureVisible(find.text('确认以上拼接顺序'));
      await tester.tap(find.text('确认以上拼接顺序'));
      await tester.pump();
      await _start(tester);
      final output = (await _native(
        tester,
        fixture.repository.listOutputs,
      )).single;
      expect(
        output.request.inputs.map((i) => i.assetId),
        fixture.assets.reversed.map((a) => a.id),
      );
      expect(output.version!.width, 16);
      expect(output.version!.height, 6);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'OUT-005 failed actual write intention never enables permanent-save action',
    (tester) async {
      _size(tester, 1280);
      final fixture = await _Fixture.create(
        tester,
        hook: (b) async {
          if (b == OutputBoundary.intent) {
            throw const FileSystemException('injected');
          }
        },
      );
      await _mount(tester, fixture.container);
      await _flush(tester);
      await tester.tap(
        find.byKey(Key('processing-asset-${fixture.assets.single.id}')),
      );
      await tester.pump();
      await _start(tester);
      final output = (await _native(
        tester,
        fixture.repository.listOutputs,
      )).single;
      expect(output.state, OutputState.failed);
      expect(output.usable, false);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(Key('processing-save-${output.id}')),
            )
            .onPressed,
        null,
      );
      expect((await _native(tester, fixture.repository.listAssets)).total, 1);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

Future<void> _start(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('processing-start')));
  await tester.tap(find.byKey(const Key('processing-start')));
  await _flush(tester);
}

Future<void> _choose<T>(WidgetTester tester, String label) async {
  final field = find.byType(DropdownButtonFormField<T>);
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void _size(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _mount(WidgetTester tester, ProviderContainer container) =>
    tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProcessingWorkbench()),
      ),
    );
Future<void> _flush(WidgetTester tester) async {
  var idle = 0;
  for (var i = 0; i < 250 && idle < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (find
            .byType(LinearProgressIndicator, skipOffstage: false)
            .evaluate()
            .isEmpty &&
        find
            .byType(CircularProgressIndicator, skipOffstage: false)
            .evaluate()
            .isEmpty) {
      idle++;
    } else {
      idle = 0;
    }
  }
  expect(
    idle,
    5,
    reason: 'Native IO/worker and widget continuations must both finish.',
  );
  await tester.pumpAndSettle();
}

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
  expect(finished, true);
  if (failure != null) throw failure!;
  return result as T;
}

class _Fixture {
  _Fixture(this.repository, this.container, this.assets);
  final LibraryRepository repository;
  final ProviderContainer container;
  final List<ImageAsset> assets;
  static Future<_Fixture> create(
    WidgetTester tester, {
    int count = 1,
    OutputFaultHook? hook,
  }) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('imagehost_workbench_'),
    ))!;
    final repository = (await tester.runAsync(
      () => LibraryRepository.open(
        Directory('${root.path}/library'),
        outputFaultHook: hook,
      ),
    ))!;
    final assets = <ImageAsset>[];
    await tester.runAsync(() async {
      for (var i = 0; i < count; i++) {
        final picture = img.Image(width: 8, height: 6);
        img.fill(picture, color: img.ColorRgb8(i + 50, 100, 190));
        assets.add(
          (await repository.importResource(
            PlatformResource(
              displayName: 'image-$i.png',
              openRead: () => Stream.value(img.encodePng(picture)),
            ),
          )).asset!,
        );
      }
    });
    final container = ProviderContainer(
      overrides: [
        librarySessionProvider.overrideWith(
          (_) async => LibrarySession(repository, const []),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await _native(tester, repository.close);
      await tester.runAsync(() async {
        await root.delete(recursive: true);
      });
    });
    return _Fixture(repository, container, assets);
  }
}
