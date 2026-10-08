import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/diagnostics/application/diagnostic_exporter.dart';
import 'package:imagehost/features/diagnostics/domain/diagnostic_models.dart';
import 'package:imagehost/features/diagnostics/presentation/diagnostics_screen.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/processing/domain/export_models.dart';
import 'package:imagehost/platform/export_gateway.dart';
import 'package:material_ui/material_ui.dart' hide DiagnosticLevel;

import '../core/upload_repository_test.dart' show QueueTestSecrets;
import 'mobile_recycle_test.dart' show mobileNative;

// Real host SQLite/files and controlled native replies; no Android device PT.
void main() {
  test('UT-085 mobile diagnostic transfer receives closed verified JSON and preserves native saved URI', () async {
    final parent = await _temporary();
    final document = DiagnosticExportDocument(
      utf8.encode('{"eventCount":1,"summary":"本机记录"}'),
      1,
    );
    ExportInput? selected;
    final result = await const DiagnosticExporter().exportUsing(document, (
      inputs,
    ) async {
      selected = inputs.single;
      expect(() => inputs.add(inputs.single), throwsUnsupportedError);
      expect(await selected!.source.readAsBytes(), document.bytes);
      expect(selected!.expectedByteCount, document.bytes.length);
      expect(
        selected!.expectedSha256,
        sha256.convert(document.bytes).toString(),
      );
      expect(selected!.source.parent.parent.path, parent.path);
      return [_saved(selected!, reason: '系统保存位置授权收尾待确认。')];
    }, temporaryParent: parent);
    expect(result.status, ExportStatus.saved);
    expect(result.destinationUri, 'content://documents/confirmed');
    expect(result.destinationPath, isNull);
    expect(result.fileName, selected!.displayName);
    expect(result.reason, '系统保存位置授权收尾待确认。');
    expect(await parent.list().isEmpty, true);
  });

  for (final lateSaved in [false, true]) {
    test(
      'UT-085/089 mobile diagnostic cancellation waits real transfer and retains late saved $lateSaved',
      () async {
        final parent = await _temporary();
        final entered = Completer<ExportInput>();
        final release = Completer<List<ExportItemResult>>();
        final token = CancellationToken();
        var completed = false;
        final operation = const DiagnosticExporter().exportUsing(
          DiagnosticExportDocument(utf8.encode('{"eventCount":0}'), 0),
          (inputs) {
            entered.complete(inputs.single);
            return release.future;
          },
          cancellation: token,
          temporaryParent: parent,
        );
        unawaited(operation.then((_) => completed = true));
        final input = await entered.future;
        try {
          token.cancel();
          await Future<void>.delayed(Duration.zero);
          expect(completed, false);
          expect(await input.source.exists(), true);
          expect(await input.source.parent.exists(), true);
        } finally {
          release.complete([
            lateSaved
                ? _saved(input)
                : ExportItemResult(
                    id: input.id,
                    status: ExportStatus.cancelled,
                  ),
          ]);
        }
        final result = await operation;
        expect(
          result.status,
          lateSaved ? ExportStatus.saved : ExportStatus.cancelled,
        );
        expect(
          result.destinationUri,
          lateSaved ? 'content://documents/confirmed' : null,
        );
        expect(await parent.list().isEmpty, true);
      },
    );
  }

  test('UT-085 confirmed native save survives changed-source cleanup failure and keeps separate feedback', () async {
    final parent = await _temporary();
    ExportInput? selected;
    final result = await const DiagnosticExporter().exportUsing(
      DiagnosticExportDocument(utf8.encode('{"eventCount":1}'), 1),
      (inputs) async {
        selected = inputs.single;
        await selected!.source.writeAsString('changed-source', flush: true);
        return [_saved(selected!, reason: '系统位置授权收尾待确认。')];
      },
      temporaryParent: parent,
    );
    expect(result.status, ExportStatus.saved);
    expect(result.destinationUri, 'content://documents/confirmed');
    expect(result.reason, contains('系统位置授权收尾待确认'));
    expect(result.reason, contains('诊断临时内容清理未确认'));
    expect(await selected!.source.readAsString(), 'changed-source');
    expect(await selected!.source.parent.exists(), true);
  });

  test('UT-085 mobile unknown transfer error never stringifies secrets or claims saved', () async {
    final parent = await _temporary();
    final failure = _UntrustedFailure();
    final result = await const DiagnosticExporter().exportUsing(
      DiagnosticExportDocument(utf8.encode('{"eventCount":0}'), 0),
      (_) async => throw failure,
      temporaryParent: parent,
    );
    expect(result.status, ExportStatus.failed);
    expect(failure.stringified, false);
    expect(result.reason, isNot(contains('private-secret')));
    expect(await parent.list().isEmpty, true);
  });

  test('UT-085 cancelled before preparation creates no private JSON and invokes no native transfer', () async {
    final parent = await _temporary();
    final token = CancellationToken()..cancel();
    var called = false;
    final result = await const DiagnosticExporter().exportUsing(
      DiagnosticExportDocument(utf8.encode('{"eventCount":0}'), 0),
      (inputs) async {
        called = true;
        return [_saved(inputs.single)];
      },
      cancellation: token,
      temporaryParent: parent,
    );
    expect(result.status, ExportStatus.cancelled);
    expect(called, false);
    expect(await parent.list().isEmpty, true);
  });

  for (final supported in [false, true]) {
    testWidgets(
      'UT-084 mobile diagnostic file capability $supported is independent of directory support',
      (tester) async {
        final gateway = _Gateway(supported: supported);
        final fixture = await _Fixture.create(tester, gateway);
        await fixture.mount(tester, width: 320, scale: 1.8);
        await _reveal(tester, 'diagnostics-export');
        expect(
          tester.widget<OutlinedButton>(_key('diagnostics-export')).onPressed !=
              null,
          supported,
        );
        if (!supported) {
          await _reveal(tester, 'diagnostics-mobile-disabled');
          expect(find.textContaining('原生诊断文件导出尚未接入'), findsOneWidget);
        }
        expect(gateway.inputs, isNull);
        expect(gateway.directoryCalls, 0);
        expect(fixture.temporaryCalls, 0);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'UT-085 Android diagnostic confirmation dispatches system file save with safe document first',
    (tester) async {
      final gateway = _Gateway();
      final fixture = await _Fixture.create(tester, gateway);
      await fixture.mount(tester);
      await _tap(tester, 'diagnostics-export');
      await _until(
        tester,
        () => _key('diagnostics-confirm').evaluate().isNotEmpty,
      );
      expect(find.text('选择保存位置并导出'), findsOneWidget);
      expect(find.textContaining('通过系统选择保存位置'), findsOneWidget);
      expect(gateway.inputs, isNull);
      expect(fixture.temporaryCalls, 0);
      await _tap(tester, 'diagnostics-confirm');
      await _until(tester, () => gateway.inputs != null);
      final input = gateway.inputs!.single;
      try {
        expect(gateway.directoryCalls, 0);
        expect(gateway.photos, false);
        expect(fixture.temporaryCalls, 1);
        final bytes = await mobileNative(tester, input.source.readAsBytes);
        expect(utf8.decode(bytes), contains('本机测试记录'));
        expect(input.expectedSha256, sha256.convert(bytes).toString());
        expect(input.expectedByteCount, bytes.length);
        expect(find.textContaining('已导出'), findsNothing);
      } finally {
        gateway.finish([_saved(input)]);
      }
      await _feedback(tester, '已导出 1 条');
      expect(await mobileNative(tester, input.source.exists), false);
      expect(find.textContaining('content://'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final dispose in [false, true]) {
    testWidgets(
      'UT-089 mobile diagnostic ${dispose ? 'dispose' : 'cancel'} preserves source until real native future ends',
      (tester) async {
        final gateway = _Gateway();
        final fixture = await _Fixture.create(tester, gateway);
        await fixture.mount(tester);
        await _tap(tester, 'diagnostics-export');
        await _until(
          tester,
          () => _key('diagnostics-confirm').evaluate().isNotEmpty,
        );
        await _tap(tester, 'diagnostics-confirm');
        await _until(tester, () => gateway.inputs != null);
        final input = gateway.inputs!.single;
        try {
          if (dispose) {
            await tester.pumpWidget(const SizedBox());
          } else {
            await _tap(tester, 'diagnostics-cancel');
          }
          expect(gateway.cancellation!.isCancelled, true);
          expect(await mobileNative(tester, input.source.exists), true);
          if (!dispose) {
            expect(
              tester
                  .widget<OutlinedButton>(_key('diagnostics-export'))
                  .onPressed,
              isNull,
            );
            expect(find.textContaining('已导出'), findsNothing);
          }
        } finally {
          gateway.finish([
            ExportItemResult(id: input.id, status: ExportStatus.cancelled),
          ]);
        }
        if (!dispose) await _feedback(tester, '已取消导出，实际文件 IO 已收尾。');
        await _sourceRemoved(tester, input.source);
        expect(await mobileNative(tester, input.source.parent.exists), false);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}

ExportItemResult _saved(ExportInput input, {String? reason}) =>
    ExportItemResult(
      id: input.id,
      status: ExportStatus.saved,
      fileName: input.displayName,
      destinationUri: 'content://documents/confirmed',
      reason: reason,
    );

Future<Directory> _temporary() async {
  final directory = await Directory.systemTemp.createTemp(
    'diagnostic-mobile-transfer-test-',
  );
  addTearDown(() => directory.delete(recursive: true));
  return directory;
}

class _UntrustedFailure {
  var stringified = false;
  @override
  String toString() {
    stringified = true;
    return 'private-secret';
  }
}

class _Gateway extends ExportGateway {
  _Gateway({this.supported = true});
  final bool supported;
  final pending = Completer<List<ExportItemResult>>();
  List<ExportInput>? inputs;
  CancellationToken? cancellation;
  bool? photos;
  var directoryCalls = 0;
  @override
  bool get supportsDirectoryExport => false;
  @override
  bool get supportsFileExport => supported;
  @override
  bool get supportsPhotos => false;
  @override
  Future<Directory?> pickDirectory() async {
    directoryCalls++;
    throw StateError('Mobile diagnostics must use the file export gateway.');
  }

  @override
  Future<List<ExportItemResult>> exportFiles(
    List<ExportInput> inputs, {
    CancellationToken? cancellation,
    bool photos = false,
  }) {
    this.inputs = inputs;
    this.cancellation = cancellation;
    this.photos = photos;
    return pending.future;
  }

  void finish(List<ExportItemResult> results) {
    if (!pending.isCompleted) pending.complete(results);
  }
}

class _Fixture {
  _Fixture(this.root, this.session, this.gateway) {
    container = ProviderContainer(
      overrides: [
        librarySessionProvider.overrideWith((_) async => session),
        diagnosticExportGatewayProvider.overrideWithValue(gateway),
        diagnosticTemporaryParentProvider.overrideWithValue(() async {
          temporaryCalls++;
          return temporaryParent;
        }),
      ],
    );
  }
  final Directory root;
  final LibrarySession session;
  final _Gateway gateway;
  late final Directory temporaryParent = Directory('${root.path}/temporary');
  late final ProviderContainer container;
  var temporaryCalls = 0;

  static Future<_Fixture> create(WidgetTester tester, _Gateway gateway) async {
    final fixture = await mobileNative(tester, () async {
      final root = await Directory.systemTemp.createTemp(
        'diagnostic-mobile-widget-test-',
      );
      final repository = await LibraryRepository.open(
        Directory('${root.path}/library'),
        secretStore: QueueTestSecrets(),
      );
      await repository.recordDiagnostic(
        DiagnosticEvent(
          id: '00000000-0000-4000-8000-000000000001',
          occurredAt: DateTime.now().toUtc(),
          kind: DiagnosticKind.system,
          level: DiagnosticLevel.info,
          code: 'test.event',
          summary: '本机测试记录',
          recoveryAction: '重新读取确认',
        ),
      );
      final fixture = _Fixture(
        root,
        LibrarySession(repository, const []),
        gateway,
      );
      await fixture.temporaryParent.create();
      return fixture;
    });
    addTearDown(() async {
      gateway.finish(
        gateway.inputs
                ?.map(
                  (input) => ExportItemResult(
                    id: input.id,
                    status: ExportStatus.cancelled,
                  ),
                )
                .toList() ??
            [],
      );
      await tester.pumpWidget(const SizedBox());
      final input = gateway.inputs?.single;
      if (input != null) await _sourceRemoved(tester, input.source);
      fixture.container.dispose();
      await mobileNative(tester, fixture.session.close);
      await mobileNative(tester, () => fixture.root.delete(recursive: true));
    });
    return fixture;
  }

  Future<void> mount(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
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
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const DiagnosticsScreen(),
        ),
      ),
    );
    await _until(
      tester,
      () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
    );
  }
}

Finder _key(String key) => find.byKey(Key(key));

Future<void> _reveal(WidgetTester tester, String key) async {
  final scroll = find
      .descendant(
        of: _key('diagnostics-list'),
        matching: find.byType(Scrollable),
      )
      .first;
  if (_key(key).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      _key(key),
      150,
      scrollable: scroll,
      maxScrolls: 120,
    );
  }
  await tester.ensureVisible(_key(key));
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  if (key != 'diagnostics-confirm') await _reveal(tester, key);
  await tester.tap(_key(key));
  await tester.pump();
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 500; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
  }
  fail('诊断导出真实 IO 与 widget continuation 必须完成。');
}

Future<void> _feedback(WidgetTester tester, String text) async {
  final scroll = find
      .descendant(
        of: _key('diagnostics-list'),
        matching: find.byType(Scrollable),
      )
      .first;
  tester.state<ScrollableState>(scroll).position.jumpTo(0);
  await tester.pump();
  await _until(tester, () => find.textContaining(text).evaluate().isNotEmpty);
}

Future<void> _sourceRemoved(WidgetTester tester, File source) async {
  for (var i = 0; i < 250; i++) {
    final removed = await mobileNative(
      tester,
      () async => !await source.exists() && !await source.parent.exists(),
    );
    if (removed) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  fail('实际系统保存 future 结束后才清理私有诊断源。');
}
