import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/diagnostics/domain/diagnostic_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/processing/application/processing_coordinator.dart';
import 'package:imagehost/features/processing/domain/output_models.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/storage/domain/storage_models.dart';
import 'package:imagehost/features/storage/presentation/storage_screen.dart';
import 'package:material_ui/material_ui.dart' hide DiagnosticLevel;
import 'package:sqlite3/sqlite3.dart';

import 'core/upload_repository_test.dart' show QueueTestSecrets;

// Alternate real SQLite / file IO and Flutter fake time. These tests cover host
// layouts and deliberate fault boundaries, not mobile devices or hard exits.
Future<T> _native<T>(WidgetTester tester, Future<T> Function() action) async {
  var done = false;
  T? value;
  Object? failure;
  await tester.runAsync(() async {
    unawaited(
      action().then(
        (result) {
          value = result;
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
  if (failure != null) throw failure!;
  return value as T;
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 500; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 40));
    if (ready()) return;
  }
  fail('空间 UI 或真实文件 / SQL IO 必须完成。');
}

Finder _key(String name) => find.byKey(ValueKey(name));
Finder get _scroll => find
    .descendant(of: _key('storage-list'), matching: find.byType(Scrollable))
    .first;

Future<void> _top(WidgetTester tester) async {
  tester.state<ScrollableState>(_scroll).position.jumpTo(0);
  await tester.pump();
}

Future<void> _reveal(WidgetTester tester, String name) async {
  final finder = _key(name);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: _scroll,
      maxScrolls: 100,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String name) async {
  if (name.startsWith('storage-confirm')) {
    await tester.tap(_key(name));
    await tester.pump();
    return;
  }
  await _top(tester);
  await _reveal(tester, name);
  await tester.tap(_key(name));
  await tester.pump();
}

class _Fixture {
  _Fixture(this.directory, this.repository);
  final Directory directory;
  final LibraryRepository repository;
  late final session = LibrarySession(repository, const []);
  late final container = ProviderContainer(
    overrides: [librarySessionProvider.overrideWith((_) async => session)],
  );
  Future<void>? _closing;
  static Future<_Fixture> open({
    OutputFaultHook? outputFaultHook,
    int? availableBytes,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'imagehost-storage-ui-',
    );
    final repository = await LibraryRepository.open(
      Directory('${directory.path}/library'),
      secretStore: QueueTestSecrets(),
      outputFaultHook: outputFaultHook,
      availableStorageBytes: availableBytes == null
          ? null
          : (_) async => availableBytes,
    );
    return _Fixture(directory, repository);
  }

  Future<(ImageAsset, File)> thumbnail(int marker) async {
    final image = img.Image(width: 12, height: 12);
    image.setPixelRgba(0, 0, marker, 20, 30, 255);
    final bytes = img.encodePng(image);
    final result = await repository.importResource(
      PlatformResource(
        displayName: 'picture-$marker.png',
        openRead: () => Stream.value(bytes),
      ),
    );
    expect(result.status, ImportStatus.saved);
    final asset = result.asset!;
    final thumbnail = await repository.thumbnailFor(asset);
    expect(thumbnail, isNotNull);
    return (asset, thumbnail!);
  }

  Future<void> sql(String statement) async {
    final database = sqlite3.open('${directory.path}/library/library.sqlite');
    try {
      database.execute(statement);
    } finally {
      database.close();
    }
  }

  Future<void> close() => _closing ??= () async {
    container.dispose();
    await session.close();
    await directory.delete(recursive: true);
  }();
}

Future<_Fixture> _fixture(
  WidgetTester tester, {
  OutputFaultHook? outputFaultHook,
  int? availableBytes,
}) async {
  final fixture = await _native(
    tester,
    () => _Fixture.open(
      outputFaultHook: outputFaultHook,
      availableBytes: availableBytes,
    ),
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
        home: const StorageScreen(),
      ),
    ),
  );
  await _until(
    tester,
    () =>
        _key('storage-clear-thumbnails').evaluate().isNotEmpty &&
        tester
                .widget<OutlinedButton>(_key('storage-clear-thumbnails'))
                .onPressed !=
            null,
  );
}

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'UT-086/088 AT-005 partial storage $width large type physical report and independent diagnostics',
      (tester) async {
        final fixture = await _fixture(tester, availableBytes: 123456789);
        final source = await _native(tester, () => fixture.thumbnail(1));
        await _native(
          tester,
          () => fixture.repository.recordDiagnostic(
            DiagnosticEvent(
              id: '00000000-0000-4000-8000-000000000086',
              occurredAt: DateTime.now().toUtc(),
              kind: DiagnosticKind.system,
              level: DiagnosticLevel.info,
              code: 'storage.test',
              summary: '空间计量事件',
              recoveryAction: '重新读取',
            ),
          ),
        );
        final report = await _native(
          tester,
          fixture.repository.loadStorageReport,
        );
        expect(
          report.fileBytes[StorageCategory.permanent],
          source.$1.version.byteCount,
        );
        expect(
          report.fileBytes[StorageCategory.thumbnails],
          await _native(tester, source.$2.length),
        );
        expect(report.availableBytes, 123456789);
        expect(report.diagnosticContentBytes, greaterThan(0));
        await _mount(tester, fixture, width: width, scale: 1.8);
        await _reveal(tester, 'storage-total');
        expect(find.textContaining('文件合计：'), findsOneWidget);
        expect(
          tester.widget<Text>(_key('storage-available')).data,
          contains('123456789 字节'),
        );
        for (final category in StorageCategory.values) {
          await _reveal(tester, 'storage-category-${category.name}');
          expect(_key('storage-category-${category.name}'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await _reveal(tester, 'storage-diagnostic-content');
        expect(
          tester.widget<Text>(_key('storage-diagnostic-content')).data,
          contains('不重复计入'),
        );
        await _tap(tester, 'storage-diagnostics');
        await _until(tester, () => find.text('本机诊断').evaluate().isNotEmpty);
        expect(_key('diagnostics-list'), findsOneWidget);
        expect(fixture.session.existingUploads, isNull);
        expect(await _native(tester, source.$2.exists), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'UT-086/088 frozen thumbnail cleanup excludes later files protected reads and unknown files',
    (tester) async {
      final fixture = await _fixture(tester);
      final first = await _native(tester, () => fixture.thumbnail(1));
      final protected = await _native(tester, () => fixture.thumbnail(2));
      final lease = await _native(
        tester,
        () => fixture.repository.acquireThumbnailLease(protected.$1),
      );
      expect(lease, isNotNull);
      final held = lease!;
      final unknown = File(
        '${fixture.directory.path}/library/cache/thumbnails/unregistered.png',
      );
      try {
        await _native(tester, held.readBytes);
        await _native(
          tester,
          () => unknown.writeAsBytes([1, 2, 3, 4], flush: true),
        );
        await _mount(tester, fixture);
        await _reveal(tester, 'storage-available');
        expect(
          tester.widget<Text>(_key('storage-available')).data,
          contains('未知'),
        );
        await _tap(tester, 'storage-clear-thumbnails');
        await _until(
          tester,
          () => _key('storage-confirm').evaluate().isNotEmpty,
        );
        expect(find.textContaining('已冻结 1 个缩略图'), findsOneWidget);
        expect(find.textContaining('后来新增文件不会加入'), findsOneWidget);
        final later = await _native(tester, () => fixture.thumbnail(3));
        await _tap(tester, 'storage-confirm');
        await _until(
          tester,
          () =>
              _key('storage-feedback').evaluate().isNotEmpty &&
              tester
                  .widget<Text>(_key('storage-feedback'))
                  .data!
                  .contains('已清理 1 个缩略图'),
        );
        expect(await _native(tester, first.$2.exists), isFalse);
        expect(await _native(tester, protected.$2.exists), isTrue);
        expect(await _native(tester, later.$2.exists), isTrue);
        expect(await _native(tester, unknown.readAsBytes), [1, 2, 3, 4]);
        expect(
          await _native(tester, () => fixture.repository.verifyCopy(first.$1)),
          CopyAvailability.available,
        );
        expect(
          await _native(
            tester,
            () => fixture.repository.verifyCopy(protected.$1),
          ),
          CopyAvailability.available,
        );
        expect(
          await _native(
            tester,
            () => fixture.repository.thumbnailFor(first.$1),
          ),
          isNotNull,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _native(tester, held.release);
      }
    },
  );

  testWidgets(
    'UT-086 last valid storage report survives failed reread without enabling cleanup',
    (tester) async {
      final fixture = await _fixture(tester);
      await _native(tester, () => fixture.thumbnail(1));
      await _mount(tester, fixture);
      await _reveal(tester, 'storage-total');
      final previous = tester.widget<Text>(_key('storage-total')).data;
      await _native(tester, fixture.repository.close);
      await _tap(tester, 'storage-reload');
      await _until(
        tester,
        () => find.textContaining('空间读取失败').evaluate().isNotEmpty,
      );
      await _reveal(tester, 'storage-total');
      expect(tester.widget<Text>(_key('storage-total')).data, previous);
      await _top(tester);
      expect(
        tester
            .widget<OutlinedButton>(_key('storage-clear-thumbnails'))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'UT-086 replacement removes only owned pending cleanup confirmation',
    (tester) async {
      final fixture = await _fixture(tester);
      final source = await _native(tester, () => fixture.thumbnail(1));
      await _mount(tester, fixture);
      await _tap(tester, 'storage-clear-thumbnails');
      await _until(tester, () => _key('storage-confirm').evaluate().isNotEmpty);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      unawaited(
        navigator.push<void>(
          DialogRoute<void>(
            context: tester.element(_key('storage-confirm')),
            builder: (_) => const AlertDialog(title: Text('另一个窗口')),
          ),
        ),
      );
      await tester.pump();
      fixture.container
          .read(libraryReplacementRevisionProvider.notifier)
          .committed();
      await _until(tester, () => _key('storage-confirm').evaluate().isEmpty);
      expect(find.text('另一个窗口'), findsOneWidget);
      expect(await _native(tester, source.$2.exists), isTrue);
      navigator.pop();
      await _until(
        tester,
        () =>
            tester
                .widget<OutlinedButton>(_key('storage-clear-thumbnails'))
                .onPressed !=
            null,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'UT-086 system exit closes pending owned confirmation without clearing thumbnails',
    (tester) async {
      final fixture = await _fixture(tester);
      final source = await _native(tester, () => fixture.thumbnail(1));
      await _mount(tester, fixture);
      await _tap(tester, 'storage-clear-thumbnails');
      await _until(tester, () => _key('storage-confirm').evaluate().isNotEmpty);
      expect(
        await _native(tester, tester.binding.handleRequestAppExit),
        AppExitResponse.exit,
      );
      expect(_key('storage-confirm'), findsNothing);
      expect(await _native(tester, source.$2.exists), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'UT-086/088 system exit waits for actual expired output deletion and preserves other outputs',
    (tester) async {
      final entered = Completer<void>(), release = Completer<void>();
      final fixture = await _fixture(
        tester,
        outputFaultHook: (boundary) async {
          if (boundary == OutputBoundary.beforeDelete) {
            entered.complete();
            await release.future;
          }
        },
      );
      final source = await _native(tester, () => fixture.thumbnail(1));
      Future<ProcessedOutput> output(String name) =>
          ProcessingCoordinator(fixture.repository).process(
            [source.$1.id],
            (inputs) => ProcessingRequest(
              operation: ProcessingOperation.compress,
              inputs: inputs,
            ),
            displayName: name,
          );
      final expired = await _native(tester, () => output('expired.png'));
      final current = await _native(tester, () => output('current.png'));
      final protected = await _native(tester, () => output('protected.png'));
      await _native(
        tester,
        () => fixture.repository.registerOutputProtection(
          outputId: protected.id,
          ownerType: 'task',
          ownerId: 'storage-test-protection',
        ),
      );
      await _native(
        tester,
        () => fixture.sql(
          "UPDATE processed_outputs SET created_utc = 0, expires_utc = 1 WHERE id IN ('${expired.id}', '${protected.id}')",
        ),
      );
      await _mount(tester, fixture);
      await _tap(tester, 'storage-clear-outputs');
      await _until(tester, () => _key('storage-confirm').evaluate().isNotEmpty);
      Future<AppExitResponse>? exit;
      var exited = false;
      try {
        await _tap(tester, 'storage-confirm');
        await _until(tester, () => entered.isCompleted);
        await tester.runAsync(() async {
          exit = tester.binding.handleRequestAppExit();
          unawaited(exit!.then((_) => exited = true));
        });
        await tester.pump();
        expect(exited, isFalse);
        expect(await _native(tester, expired.file!.exists), isTrue);
        release.complete();
        expect(await _native(tester, () => exit!), AppExitResponse.exit);
        expect(await _native(tester, expired.file!.exists), isFalse);
        expect(await _native(tester, current.file!.exists), isTrue);
        expect(await _native(tester, protected.file!.exists), isTrue);
        expect(await _native(tester, source.$2.exists), isTrue);
        expect(
          await _native(
            tester,
            () => File(
              '${fixture.directory.path}/library/${source.$1.deviceCopy.relativePath}',
            ).exists(),
          ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      } finally {
        if (!release.isCompleted) release.complete();
        if (exit != null) await _native(tester, () => exit!);
      }
    },
  );
}
