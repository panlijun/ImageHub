import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/processing/application/processing_coordinator.dart';
import 'package:imagehost/features/processing/domain/export_models.dart';
import 'package:imagehost/features/processing/domain/output_models.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/processing/presentation/processing_workbench.dart';
import 'package:imagehost/platform/export_gateway.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqlite3/sqlite3.dart';

import 'mobile_recycle_test.dart' show MobileTestFixture, mobileNative;

// Host widgets and real SQLite/file leases; no Android device PT or external IO.
void main() {
  for (final supported in [false, true]) {
    testWidgets(
      'mobile export capability $supported gates files independently of directories',
      (tester) async {
        final gateway = _Gateway(files: supported, photos: supported);
        final fixture = await _Fixture.create(tester, gateway);
        await fixture.mount(tester, size: const Size(320, 700), textScale: 1.5);
        final id = fixture.outputs.single.id;
        expect(
          tester
                  .widget<TextButton>(find.byKey(Key('processing-export-$id')))
                  .onPressed !=
              null,
          supported,
        );
        expect(
          tester
                  .widget<TextButton>(
                    find.byKey(const Key('processing-export-all')),
                  )
                  .onPressed !=
              null,
          supported,
        );
        expect(
          find.byKey(Key('processing-export-photos-$id')),
          supported ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const Key('processing-export-photos-all')),
          supported ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('此平台的原生文件导出尚未接入，导出已禁用。'),
          supported ? findsNothing : findsOneWidget,
        );
        expect(gateway.calls, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets('mobile file support alone keeps the photos action unavailable', (
    tester,
  ) async {
    final gateway = _Gateway(photos: false);
    final fixture = await _Fixture.create(tester, gateway);
    await fixture.mount(tester);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('processing-export-all')))
          .onPressed,
      isNotNull,
    );
    expect(find.byKey(const Key('processing-export-photos-all')), findsNothing);
    expect(
      find.byKey(Key('processing-export-photos-${fixture.outputs.single.id}')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
    'mobile file and photos buttons dispatch distinct modes with frozen output identities',
    (tester) async {
      final gateway = _Gateway();
      final fixture = await _Fixture.create(tester, gateway, count: 2);
      await fixture.mount(tester);
      final chosen = fixture.outputs.first;
      await _tap(tester, Key('processing-export-${chosen.id}'));
      await _flush(tester);
      expect(gateway.calls.single.photos, false);
      expect(gateway.calls.single.inputs.single.id, chosen.id);
      expect(
        gateway.calls.single.inputs.single.expectedSha256,
        chosen.version!.sha256,
      );
      expect(
        gateway.calls.single.inputs.single.expectedByteCount,
        chosen.version!.byteCount,
      );
      expect(find.textContaining('已导出 ${chosen.displayName}'), findsOneWidget);
      await _tap(tester, Key('processing-export-photos-${chosen.id}'));
      await _flush(tester);
      expect(gateway.calls.last.photos, true);
      expect(gateway.calls.last.inputs.single.id, chosen.id);
      expect(
        find.textContaining('已保存到相册 ${chosen.displayName}'),
        findsOneWidget,
      );
      await _tap(tester, const Key('processing-export-photos-all'));
      await _flush(tester);
      expect(gateway.calls.last.photos, true);
      expect(
        gateway.calls.last.inputs.map((input) => input.id).toSet(),
        fixture.outputs.map((output) => output.id).toSet(),
      );
      expect(
        () => gateway.calls.last.inputs.add(gateway.calls.last.inputs.first),
        throwsUnsupportedError,
      );
      expect(fixture.leases, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-102 mobile batch keeps every actual output lease through selector/IO and cancellation drain',
    (tester) async {
      final gateway = _Gateway(pending: Completer<List<ExportItemResult>>());
      final fixture = await _Fixture.create(tester, gateway, count: 2);
      await fixture.mount(tester);
      expect(fixture.leases, 0);
      await _tap(tester, const Key('processing-export-all'));
      await _until(tester, () => gateway.calls.isNotEmpty);
      expect(fixture.leases, 2);
      expect(
        gateway.calls.single.inputs.map((input) => input.id).toSet(),
        fixture.outputs.map((output) => output.id).toSet(),
      );
      await tester.ensureVisible(find.text('停止后续操作'));
      await tester.tap(find.text('停止后续操作'));
      await tester.pump();
      expect(gateway.calls.single.cancellation!.isCancelled, true);
      expect(fixture.leases, 2);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('processing-export-all')))
            .onPressed,
        isNull,
      );
      expect(find.text('正在停止，等待实际读写结束…'), findsOneWidget);
      gateway.pending!.complete(
        gateway.calls.single.inputs
            .map(
              (input) => ExportItemResult(
                id: input.id,
                status: ExportStatus.cancelled,
                reason: '用户取消，实际工作已结束。',
              ),
            )
            .toList(),
      );
      await _flush(tester);
      expect(fixture.leases, 0);
      expect(find.textContaining('已取消'), findsOneWidget);
      expect(find.textContaining('已导出'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-100/102 mobile return waits for the actual export future after stop confirmation',
    (tester) async {
      final gateway = _Gateway(pending: Completer<List<ExportItemResult>>());
      final fixture = await _Fixture.create(tester, gateway);
      await fixture.mount(tester);
      await _tap(tester, const Key('processing-export-all'));
      await _until(tester, () => gateway.calls.isNotEmpty);
      await tester.tap(find.byTooltip('返回图库'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(FilledButton, '停止并离开'));
      await tester.pump();
      expect(gateway.calls.single.cancellation!.isCancelled, true);
      expect(find.byType(ProcessingWorkbench), findsOneWidget);
      expect(fixture.leases, 1);
      gateway.pending!.complete([
        ExportItemResult(
          id: fixture.outputs.single.id,
          status: ExportStatus.cancelled,
        ),
      ]);
      await _flush(tester);
      expect(find.byType(ProcessingWorkbench), findsNothing);
      expect(find.byKey(const Key('open-workbench')), findsOneWidget);
      expect(fixture.leases, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'mobile cancellation retains a late confirmed saved item beside cancelled items',
    (tester) async {
      final gateway = _Gateway(pending: Completer<List<ExportItemResult>>());
      final fixture = await _Fixture.create(tester, gateway, count: 2);
      await fixture.mount(tester);
      await _tap(tester, const Key('processing-export-all'));
      await _until(tester, () => gateway.calls.isNotEmpty);
      await tester.ensureVisible(find.text('停止后续操作'));
      await tester.tap(find.text('停止后续操作'));
      final inputs = gateway.calls.single.inputs;
      gateway.pending!.complete([
        ExportItemResult(
          id: inputs.first.id,
          status: ExportStatus.saved,
          fileName: '迟到确认.png',
          destinationUri: 'content://media/confirmed',
        ),
        ExportItemResult(id: inputs.last.id, status: ExportStatus.cancelled),
      ]);
      await _flush(tester);
      expect(find.textContaining('已导出 迟到确认.png'), findsOneWidget);
      expect(
        find.textContaining('${inputs.last.displayName}：已取消'),
        findsOneWidget,
      );
      expect(fixture.leases, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'mobile batch skips a preparation failure and reports saved and unconfirmed results separately',
    (tester) async {
      final gateway = _Gateway(pending: Completer<List<ExportItemResult>>());
      final fixture = await _Fixture.create(tester, gateway, count: 3);
      await fixture.mount(tester);
      final missing = fixture.outputs.first;
      await mobileNative(tester, missing.file!.delete);
      await _tap(tester, const Key('processing-export-all'));
      await _until(tester, () => gateway.calls.isNotEmpty);
      final prepared = gateway.calls.single.inputs;
      expect(prepared, hasLength(2));
      expect(prepared.any((input) => input.id == missing.id), false);
      expect(fixture.leases, 2);
      gateway.pending!.complete([
        ExportItemResult(
          id: prepared.first.id,
          status: ExportStatus.saved,
          fileName: '真实保存.png',
          destinationUri: 'content://media/confirmed',
        ),
        ExportItemResult(
          id: prepared.last.id,
          status: ExportStatus.failed,
          reason: '系统保存未确认。',
        ),
      ]);
      await _flush(tester);
      expect(find.textContaining('${missing.displayName}：失败'), findsOneWidget);
      expect(find.textContaining('已导出 真实保存.png'), findsOneWidget);
      expect(find.textContaining('失败 系统保存未确认。'), findsOneWidget);
      expect(find.textContaining('content://'), findsNothing);
      expect(fixture.leases, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'mobile unknown export exception uses fixed feedback and never stringifies the object',
    (tester) async {
      final exception = _UntrustedFailure();
      final gateway = _Gateway(failure: exception);
      final fixture = await _Fixture.create(tester, gateway);
      await fixture.mount(tester);
      await _tap(tester, const Key('processing-export-all'));
      await _flush(tester);
      expect(find.textContaining('失败 系统保存未确认，请检查所选位置后重试。'), findsOneWidget);
      expect(exception.stringified, false);
      expect(fixture.leases, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-102 mobile lease cleanup failure retains protection and continues other releases',
    (tester) async {
      final gateway = _Gateway(pending: Completer<List<ExportItemResult>>());
      final fixture = await _Fixture.create(tester, gateway, count: 2);
      await fixture.mount(tester);
      await _tap(tester, const Key('processing-export-all'));
      await _until(tester, () => gateway.calls.isNotEmpty);
      final protected = gateway.calls.single.inputs.first.id;
      final db = sqlite3.open(
        '${fixture.base.libraryRoot.path}/library.sqlite',
      );
      try {
        db.execute(
          "CREATE TRIGGER block_export_release BEFORE DELETE ON output_leases WHEN OLD.output_id = '$protected' BEGIN SELECT RAISE(FAIL, 'injected-release-failure'); END",
        );
        gateway.pending!.complete(
          gateway.calls.single.inputs
              .map(
                (input) => ExportItemResult(
                  id: input.id,
                  status: ExportStatus.saved,
                  fileName: input.displayName,
                  reason: '系统位置授权收尾待确认，已保存文件保留。',
                ),
              )
              .toList(),
        );
        await _flush(tester);
        expect(fixture.leases, 1);
        expect(
          db.select('SELECT output_id FROM output_leases').single['output_id'],
          protected,
        );
        expect(find.textContaining('文件使用保护收尾未确认，保护记录保留'), findsOneWidget);
        expect(find.textContaining('已导出'), findsOneWidget);
        expect(find.textContaining('系统位置授权收尾待确认'), findsOneWidget);
        expect(find.textContaining('injected-release-failure'), findsNothing);
        expect(
          tester
              .widget<TextButton>(
                find.byKey(const Key('processing-export-all')),
              )
              .onPressed,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      } finally {
        db.execute('DROP TRIGGER IF EXISTS block_export_release');
        db.close();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

class _Gateway extends ExportGateway {
  _Gateway({this.files = true, this.photos = true, this.pending, this.failure});
  final bool files;
  final bool photos;
  final Completer<List<ExportItemResult>>? pending;
  final Object? failure;
  final calls = <_ExportCall>[];
  @override
  bool get supportsDirectoryExport => false;
  @override
  bool get supportsFileExport => files;
  @override
  bool get supportsPhotos => photos;
  @override
  Future<List<ExportItemResult>> exportFiles(
    List<ExportInput> inputs, {
    CancellationToken? cancellation,
    bool photos = false,
  }) async {
    calls.add(_ExportCall(inputs, cancellation, photos));
    if (failure != null) throw failure!;
    if (pending != null) return pending!.future;
    return inputs
        .map(
          (input) => ExportItemResult(
            id: input.id,
            status: ExportStatus.saved,
            fileName: input.displayName,
            destinationUri: 'content://media/${input.id}',
          ),
        )
        .toList();
  }
}

class _ExportCall {
  _ExportCall(this.inputs, this.cancellation, this.photos);
  final List<ExportInput> inputs;
  final CancellationToken? cancellation;
  final bool photos;
}

class _UntrustedFailure {
  bool stringified = false;
  @override
  String toString() {
    stringified = true;
    return 'private-unknown-object';
  }
}

class _Fixture {
  _Fixture(this.base, this.container, this.outputs);
  final MobileTestFixture base;
  final ProviderContainer container;
  final List<ProcessedOutput> outputs;
  int get leases {
    final db = sqlite3.open(
      '${base.libraryRoot.path}/library.sqlite',
      mode: OpenMode.readOnly,
    );
    try {
      return db.select('SELECT id FROM output_leases').length;
    } finally {
      db.close();
    }
  }

  static Future<_Fixture> create(
    WidgetTester tester,
    _Gateway gateway, {
    int count = 1,
  }) async {
    final base = await MobileTestFixture.create(tester, names: ['原图.png']);
    final outputs = <ProcessedOutput>[];
    for (var i = 0; i < count; i++) {
      outputs.add(
        await mobileNative(
          tester,
          () => ProcessingCoordinator(base.repository).process(
            [base.assets.single.id],
            (inputs) => ProcessingRequest(
              operation: ProcessingOperation.compress,
              inputs: inputs,
            ),
            displayName: '结果${i + 1}.png',
          ),
        ),
      );
      expect(outputs.last.usable, true);
    }
    final container = ProviderContainer(
      parent: base.container,
      overrides: [exportGatewayProvider.overrideWithValue(gateway)],
    );
    addTearDown(container.dispose);
    return _Fixture(base, container, outputs);
  }

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(390, 900),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('open-workbench'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => const ProcessingWorkbench(),
                  ),
                ),
                child: const Text('打开工作台'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-workbench')));
    await _flush(tester);
    expect(leases, 0);
  }
}

Future<void> _tap(WidgetTester tester, Key key) async {
  final button = find.byKey(key);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 2000 && !condition(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(
    condition(),
    true,
    reason: 'Actual repository and widget continuations must finish.',
  );
}

Future<void> _flush(WidgetTester tester) async {
  var idle = 0;
  await _until(tester, () {
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty &&
        find
            .byType(CircularProgressIndicator, skipOffstage: false)
            .evaluate()
            .isEmpty &&
        find.text('正在读取结果预览…').evaluate().isEmpty) {
      idle++;
    } else {
      idle = 0;
    }
    return idle >= 5;
  });
  await tester.pumpAndSettle();
}
