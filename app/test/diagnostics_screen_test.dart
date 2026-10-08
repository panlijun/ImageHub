import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/diagnostics/application/diagnostic_exporter.dart';
import 'package:imagehost/features/diagnostics/domain/diagnostic_models.dart';
import 'package:imagehost/features/diagnostics/presentation/diagnostics_screen.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/processing/application/file_exporter.dart';
import 'package:imagehost/features/processing/domain/export_models.dart';
import 'package:imagehost/platform/export_gateway.dart';
import 'package:material_ui/material_ui.dart' hide DiagnosticLevel;

import 'core/upload_repository_test.dart' show QueueTestSecrets;

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
  await _until(tester, () => done);
  if (failure != null) {
    throw failure!;
  }
  return result as T;
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 500; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 40));
    if (ready()) {
      return;
    }
  }
  fail('诊断 UI / 真实 IO 必须完成，不用 fake time 假装原生 IO 已收尾');
}

Finder _key(String key) => find.byKey(ValueKey(key));
Future<void> _tap(WidgetTester tester, String key) async {
  await _reveal(tester, key);
  await tester.tap(_key(key));
  await tester.pump();
}

Future<void> _reveal(WidgetTester tester, String key) async {
  final finder = _key(key);
  final scroll = find
      .descendant(
        of: _key('diagnostics-list'),
        matching: find.byType(Scrollable),
      )
      .first;
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: scroll,
      maxScrolls: 120,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _top(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  final scroll = find
      .descendant(
        of: _key('diagnostics-list'),
        matching: find.byType(Scrollable),
      )
      .first;
  tester.state<ScrollableState>(scroll).position.jumpTo(0);
  await tester.pump();
}

DiagnosticEvent _event(
  int number, {
  DiagnosticKind kind = DiagnosticKind.system,
  DiagnosticLevel level = DiagnosticLevel.info,
  String? batchId,
  String? attemptId,
}) => DiagnosticEvent(
  id: '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
  occurredAt: DateTime.now().toUtc(),
  kind: kind,
  level: level,
  code: 'test.event',
  summary: '测试记录 $number',
  recoveryAction: '重新读取确认',
  batchId: batchId,
  attemptId: attemptId,
);

class _Gateway extends ExportGateway {
  _Gateway({this.supported = true, this.destination});
  final bool supported;
  final Directory? destination;
  int calls = 0;
  @override
  bool get supportsDirectoryExport => supported;
  @override
  Future<Directory?> pickDirectory() async {
    calls++;
    return destination;
  }
}

class _BlockingExporter extends FileExporter {
  _BlockingExporter(this.entered, this.release);
  final Completer<void> entered, release;
  @override
  Future<List<ExportItemResult>> exportToDirectory(
    List<ExportInput> inputs,
    Directory directory, {
    CancellationToken? cancellation,
    ExportFaultHook? faultHook,
  }) => super.exportToDirectory(
    inputs,
    directory,
    cancellation: cancellation,
    faultHook: (boundary, input, target) async {
      if (boundary == ExportBoundary.beforeTargetClose) {
        entered.complete();
        await release.future;
      }
    },
  );
}

class _Fixture {
  _Fixture(this.directory, this.repository, this.gateway, this.exporter);
  final Directory directory;
  final LibraryRepository repository;
  final ExportGateway gateway;
  final DiagnosticExporter exporter;
  late final session = LibrarySession(repository, const []);
  late final container = ProviderContainer(
    overrides: [
      librarySessionProvider.overrideWith((_) async => session),
      diagnosticExportGatewayProvider.overrideWithValue(gateway),
      diagnosticExporterProvider.overrideWithValue(exporter),
    ],
  );
  static Future<_Fixture> open({
    ExportGateway? gateway,
    DiagnosticExporter exporter = const DiagnosticExporter(),
  }) async {
    final root = await Directory.systemTemp.createTemp('diagnostic-ui-test-');
    final repository = await LibraryRepository.open(
      Directory('${root.path}/library'),
      secretStore: QueueTestSecrets(),
    );
    return _Fixture(
      root,
      repository,
      gateway ?? _Gateway(supported: false),
      exporter,
    );
  }

  Future<void> close() async {
    container.dispose();
    await session.close();
    await directory.delete(recursive: true);
  }
}

Future<_Fixture> _fixture(
  WidgetTester tester, {
  ExportGateway? gateway,
  DiagnosticExporter exporter = const DiagnosticExporter(),
}) async {
  final fixture = await _native(
    tester,
    () => _Fixture.open(gateway: gateway, exporter: exporter),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await _native(tester, fixture.close);
  });
  return fixture;
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture, {
  double width = 390,
  double scale = 1,
  DiagnosticQuery? initialQuery,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: fixture.container,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: DiagnosticsScreen(initialQuery: initialQuery),
      ),
    ),
  );
  await _until(
    tester,
    () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
  );
}

void main() {
  testWidgets(
    'UT-084 initial task query prefilled and SQL matches exact batch attempt kind level',
    (tester) async {
      final fixture = await _fixture(tester);
      const batch = '00000000-0000-4000-8000-000000000100';
      const otherBatch = '00000000-0000-4000-8000-000000000101';
      const attempt = '00000000-0000-4000-8000-000000000200';
      const otherAttempt = '00000000-0000-4000-8000-000000000201';
      await _native(tester, () async {
        await fixture.repository.recordDiagnostic(
          _event(
            1,
            kind: DiagnosticKind.upload,
            level: DiagnosticLevel.error,
            batchId: batch,
            attemptId: attempt,
          ),
        );
        await fixture.repository.recordDiagnostic(
          _event(
            2,
            kind: DiagnosticKind.upload,
            level: DiagnosticLevel.error,
            batchId: otherBatch,
            attemptId: attempt,
          ),
        );
        await fixture.repository.recordDiagnostic(
          _event(
            3,
            kind: DiagnosticKind.upload,
            level: DiagnosticLevel.error,
            batchId: batch,
            attemptId: otherAttempt,
          ),
        );
        await fixture.repository.recordDiagnostic(
          _event(
            4,
            kind: DiagnosticKind.upload,
            batchId: batch,
            attemptId: attempt,
          ),
        );
      });
      await _mount(
        tester,
        fixture,
        initialQuery: DiagnosticQuery(
          kind: DiagnosticKind.upload,
          level: DiagnosticLevel.error,
          batchId: batch,
          attemptId: attempt,
        ),
      );
      expect(
        tester.widget<TextField>(_key('diagnostics-batch')).controller!.text,
        batch,
      );
      expect(
        tester.widget<TextField>(_key('diagnostics-attempt')).controller!.text,
        attempt,
      );
      expect(
        tester
            .widget<DropdownButton<DiagnosticKind>>(_key('diagnostics-kind'))
            .value,
        DiagnosticKind.upload,
      );
      expect(
        tester
            .widget<DropdownButton<DiagnosticLevel>>(_key('diagnostics-level'))
            .value,
        DiagnosticLevel.error,
      );
      await _reveal(tester, 'diagnostics-total');
      expect(find.textContaining('当前筛选共 1 条'), findsOneWidget);
      await _reveal(tester, 'diagnostic-${_event(1).id}');
      expect(find.text('测试记录 1'), findsOneWidget);
      for (final excluded in [2, 3, 4]) {
        expect(_key('diagnostic-${_event(excluded).id}'), findsNothing);
      }
      expect(fixture.session.existingUploads, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('UT-084 UT-089 loading failure exposes fixed retry feedback', (
    tester,
  ) async {
    final pending = Completer<LibrarySession>();
    final container = ProviderContainer(
      overrides: [
        librarySessionProvider.overrideWith((_) => pending.future),
        diagnosticExportGatewayProvider.overrideWithValue(
          _Gateway(supported: false),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DiagnosticsScreen()),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    pending.completeError(StateError('never-reveal-this-secret'));
    await _until(
      tester,
      () => find.textContaining('诊断读取失败').evaluate().isNotEmpty,
    );
    expect(find.textContaining('never-reveal-this-secret'), findsNothing);
    await _tap(tester, 'diagnostics-reload');
    await _until(
      tester,
      () => find.textContaining('诊断读取失败').evaluate().isNotEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'UT-084 empty mobile disabled export and 320 large text no overflow',
    (tester) async {
      final fixture = await _fixture(tester);
      await _mount(tester, fixture, width: 320, scale: 1.8);
      await _tap(tester, 'diagnostics-clear');
      await _top(tester);
      await _until(
        tester,
        () => find.text('当前范围没有诊断记录。').evaluate().isNotEmpty,
      );
      await _reveal(tester, 'diagnostics-mobile-disabled');
      expect(find.textContaining('原生诊断文件导出尚未接入'), findsOneWidget);
      await _reveal(tester, 'diagnostics-export');
      expect(
        tester.widget<OutlinedButton>(_key('diagnostics-export')).onPressed,
        isNull,
      );
      await _reveal(tester, 'diagnostics-empty');
      expect(find.text('当前范围暂无诊断记录。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('UT-084 SQL kind level UUID filter validation and reset', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    await _native(tester, () async {
      await fixture.repository.recordDiagnostic(_event(1));
      await fixture.repository.recordDiagnostic(
        _event(2, kind: DiagnosticKind.upload, level: DiagnosticLevel.warning),
      );
    });
    await _mount(tester, fixture);
    tester
        .widget<DropdownButton<DiagnosticKind>>(_key('diagnostics-kind'))
        .onChanged!(DiagnosticKind.upload);
    await tester.pump();
    tester
        .widget<DropdownButton<DiagnosticLevel>>(_key('diagnostics-level'))
        .onChanged!(DiagnosticLevel.warning);
    await _tap(tester, 'diagnostics-filter');
    await _reveal(tester, 'diagnostics-total');
    await _until(
      tester,
      () => find.textContaining('当前筛选共 1 条').evaluate().isNotEmpty,
    );
    await tester.ensureVisible(_key('diagnostics-batch'));
    await tester.enterText(_key('diagnostics-batch'), 'not-a-uuid');
    await _tap(tester, 'diagnostics-filter');
    await _top(tester);
    expect(find.textContaining('须为完整 UUID'), findsOneWidget);
    await _tap(tester, 'diagnostics-reset');
    await _reveal(tester, 'diagnostics-total');
    await _until(
      tester,
      () => find.textContaining('当前筛选共 2 条').evaluate().isNotEmpty,
    );
    await _reveal(tester, 'diagnostics-kind');
    expect(
      tester
          .widget<DropdownButton<DiagnosticKind>>(_key('diagnostics-kind'))
          .value,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'UT-084 clear confirmation freezes all matching records excludes later events',
    (tester) async {
      final fixture = await _fixture(tester);
      await _native(
        tester,
        () => fixture.repository.recordDiagnostic(_event(1)),
      );
      await _mount(tester, fixture);
      await _tap(tester, 'diagnostics-clear');
      await _until(
        tester,
        () => _key('diagnostics-confirm').evaluate().isNotEmpty,
      );
      expect(find.textContaining('已冻结 1 条'), findsOneWidget);
      expect(find.textContaining('不删除图片、任务'), findsOneWidget);
      await _native(
        tester,
        () => fixture.repository.recordDiagnostic(_event(2)),
      );
      await tester.tap(_key('diagnostics-confirm'));
      await tester.pump();
      await _top(tester);
      await _until(
        tester,
        () => find.textContaining('已清理 1 条').evaluate().isNotEmpty,
      );
      final page = await _native(tester, fixture.repository.loadDiagnostics);
      expect(page.items.single.id, _event(2).id);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'UT-084 pagination uses total and new events reset to first page',
    (tester) async {
      final fixture = await _fixture(tester);
      await _native(tester, () async {
        for (var number = 1; number <= 51; number++) {
          await fixture.repository.recordDiagnostic(_event(number));
        }
      });
      await _mount(tester, fixture);
      await _reveal(tester, 'diagnostics-total');
      expect(find.textContaining('当前筛选共 51 条'), findsOneWidget);
      await _tap(tester, 'diagnostics-next');
      await _until(
        tester,
        () => find.text('本页 51–51 / 51').evaluate().isNotEmpty,
      );
      await _native(
        tester,
        () => fixture.repository.recordDiagnostic(_event(52)),
      );
      await _until(
        tester,
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      await _top(tester);
      await _reveal(tester, 'diagnostics-total');
      expect(find.textContaining('当前筛选共 52 条'), findsOneWidget);
      await _reveal(tester, 'diagnostic-${_event(52).id}');
      expect(find.text('测试记录 52'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'UT-085 export scope excludes protected data requires confirm before picker',
    (tester) async {
      final gateway = _Gateway();
      final fixture = await _fixture(tester, gateway: gateway);
      await _native(
        tester,
        () => fixture.repository.recordDiagnostic(_event(1)),
      );
      await _mount(tester, fixture);
      await _tap(tester, 'diagnostics-export');
      await _until(
        tester,
        () => _key('diagnostics-confirm').evaluate().isNotEmpty,
      );
      expect(gateway.calls, 0);
      expect(find.textContaining('图片、凭据、管理秘密、完整来源路径和原始响应'), findsOneWidget);
      await tester.tap(_key('diagnostics-confirm'));
      await tester.pump();
      await _top(tester);
      await _until(tester, () => find.text('已取消目录选择。').evaluate().isNotEmpty);
      expect(gateway.calls, 1);
    },
  );

  testWidgets(
    'UT-089 system exit waits actual diagnostic file IO before library close',
    (tester) async {
      final output = await _native(
        tester,
        () => Directory.systemTemp.createTemp('diagnostic-ui-output-'),
      );
      addTearDown(() => _native(tester, () => output.delete(recursive: true)));
      final entered = Completer<void>(), release = Completer<void>();
      final fixture = await _fixture(
        tester,
        gateway: _Gateway(destination: output),
        exporter: DiagnosticExporter(
          fileExporter: _BlockingExporter(entered, release),
        ),
      );
      await _native(
        tester,
        () => fixture.repository.recordDiagnostic(_event(1)),
      );
      await _mount(tester, fixture);
      Future<AppExitResponse>? exit;
      try {
        await _tap(tester, 'diagnostics-export');
        await _until(
          tester,
          () => _key('diagnostics-confirm').evaluate().isNotEmpty,
        );
        await tester.tap(_key('diagnostics-confirm'));
        await tester.pump();
        await _until(tester, () => entered.isCompleted);
        var exited = false;
        await tester.runAsync(() async {
          exit = tester.binding.handleRequestAppExit();
          unawaited(exit!.then((_) => exited = true));
        });
        await tester.pump();
        expect(exited, isFalse);
        expect(
          tester.widget<PopScope>(find.byType(PopScope).last).canPop,
          isFalse,
        );
        release.complete();
        expect(await _native(tester, () => exit!), AppExitResponse.exit);
        expect(await _native(tester, () => output.list().isEmpty), isTrue);
      } finally {
        if (!release.isCompleted) {
          release.complete();
        }
        if (exit != null) {
          await _native(tester, () => exit!);
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final export in [false, true]) {
    for (final systemExit in [false, true]) {
      testWidgets(
        'UT-089 ${systemExit ? 'system exit' : 'dispose'} resolves owned '
        '${export ? 'export' : 'clear'} confirmation without changing records',
        (tester) async {
          final gateway = _Gateway();
          final fixture = await _fixture(tester, gateway: gateway);
          await _native(
            tester,
            () => fixture.repository.recordDiagnostic(_event(1)),
          );
          await _mount(tester, fixture);
          await _tap(
            tester,
            export ? 'diagnostics-export' : 'diagnostics-clear',
          );
          await _until(
            tester,
            () => _key('diagnostics-confirm').evaluate().isNotEmpty,
          );
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(gateway.calls, 0);
          if (systemExit) {
            final result = await _native(
              tester,
              tester.binding.handleRequestAppExit,
            );
            expect(result, AppExitResponse.exit);
            await tester.pump();
            expect(find.byType(AlertDialog), findsNothing);
            final reopened = await _native(
              tester,
              () => LibraryRepository.open(
                Directory('${fixture.directory.path}/library'),
                secretStore: QueueTestSecrets(),
              ),
            );
            try {
              expect(
                (await _native(
                  tester,
                  reopened.loadDiagnostics,
                )).items.single.id,
                _event(1).id,
              );
            } finally {
              await _native(tester, reopened.close);
            }
          } else {
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
            expect(
              (await _native(
                tester,
                fixture.repository.loadDiagnostics,
              )).items.single.id,
              _event(1).id,
            );
          }
          expect(gateway.calls, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
