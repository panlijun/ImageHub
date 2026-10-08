import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/memory_pressure.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/backup/data/backup_zip_reader.dart';
import 'package:imagehost/features/backup/data/backup_zip_writer.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/settings/domain/device_settings.dart';
import 'package:imagehost/features/settings/presentation/settings_screen.dart';
import 'package:imagehost/platform/system_memory_pressure_monitor.dart';
import 'package:material_ui/material_ui.dart';

const _mib = 1024 * 1024;

final class _Monitor implements MemoryPressureMonitor {
  _Monitor({this.onStart, this.onClose});
  final Future<void> Function(_Monitor)? onStart;
  final Future<void> Function()? onClose;
  final controller = StreamController<void>.broadcast(sync: true);
  int starts = 0, closes = 0;
  void pressure() => controller.add(null);
  @override
  Stream<void> get events => controller.stream;
  @override
  Future<void> start() async {
    starts++;
    await onStart?.call(this);
  }

  @override
  Future<void> close() async {
    closes++;
    await onClose?.call();
  }
}

final class _UnknownMonitorFailure {
  int strings = 0;
  @override
  String toString() {
    strings++;
    throw StateError('Unknown native failure must not be displayed.');
  }
}

Future<T> _native<T>(WidgetTester tester, Future<T> Function() action) async {
  var completed = false;
  T? result;
  Object? failure;
  await tester.runAsync(() async {
    unawaited(
      action().then(
        (value) {
          result = value;
          completed = true;
        },
        onError: (Object error) {
          failure = error;
          completed = true;
        },
      ),
    );
  });
  for (var count = 0; count < 500 && !completed; count++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 40));
  }
  expect(completed, true, reason: '真实 SQL/文件 IO 必须结束');
  if (failure != null) throw failure!;
  return result as T;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('NFR-003 UT-101 session subscribes before start and actual replacement cannot reset pressure or persisted settings', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'imagehost-memory-session-',
    );
    final repository = await LibraryRepository.open(
      Directory('${sandbox.path}/library'),
      memoryBudgetBytes: 512 * _mib,
    );
    final monitor = _Monitor(onStart: (monitor) async => monitor.pressure());
    final session = LibrarySession(
      repository,
      const [],
      memoryPressureMonitor: monitor,
    );
    try {
      final scheduler = repository.processingScheduler;
      expect(scheduler.memoryPressureLimited, true);
      expect(monitor.starts, 1);
      final oldSettings = (await repository.loadSettings()).values;
      final configured = DeviceSettings.fromJson({
        ...oldSettings.toJson(),
        'processingConcurrency': 4,
      });
      await repository.saveSettings(
        await repository.loadSettings(),
        configured,
        defaultTargetIds: const [],
      );
      expect(scheduler.configuredConcurrency, 4);
      expect(scheduler.effectiveConcurrency, 1);
      final snapshot = await repository.captureBackupSnapshot(
        mode: BackupMode.metadata,
      );
      final source = File('${sandbox.path}/replacement.zip');
      try {
        await BackupZipWriter().write(snapshot, source);
      } finally {
        await snapshot.release();
      }
      final backup = await const BackupZipReader().preflight(
        source,
        sandbox,
        availableBytes: (_) async => 1024 * _mib,
      );
      final hold = await repository.acquireRestoreHold();
      final epoch = repository.executionEpoch;
      try {
        final prepared = await repository.prepareReplacementRestore(
          hold: hold,
          backup: backup,
          availableBytes: (_) async => 1024 * _mib,
        );
        try {
          await repository.commitReplacementRestore(
            preparation: prepared,
            availableBytes: (_) async => 1024 * _mib,
            publishExclusive: (_, _) async => throw StateError(
              'Metadata replacement must not publish image bytes',
            ),
          );
          await session.resetUploadsAfterReplacement();
        } finally {
          await repository.discardReplacementPreparation(prepared);
        }
      } finally {
        await backup.dispose();
        await hold.release();
      }
      expect(repository.executionEpoch, isNot(epoch));
      expect(identical(repository.processingScheduler, scheduler), true);
      expect(scheduler.memoryPressureLimited, true);
      expect(scheduler.effectiveTotalMemoryBudgetBytes, 128 * _mib);
      expect((await repository.loadSettings()).values, configured);
    } finally {
      await session.close();
      await monitor.controller.close();
      await sandbox.delete(recursive: true);
    }
  });

  test('NFR-003 UT-101 session closing ignores delayed start and late monitor events before permit drain', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'imagehost-memory-close-',
    );
    final repository = await LibraryRepository.open(
      Directory('${sandbox.path}/library'),
      memoryBudgetBytes: 512 * _mib,
    );
    final started = Completer<void>();
    final monitor = _Monitor(onStart: (_) => started.future);
    final session = LibrarySession(
      repository,
      const [],
      memoryPressureMonitor: monitor,
    );
    final running = await repository.processingScheduler.acquire();
    try {
      var closed = false;
      final closing = session.close();
      closing.then((_) => closed = true);
      monitor.pressure();
      started.complete();
      await Future<void>.value();
      await Future<void>.value();
      expect(repository.processingScheduler.memoryPressureLimited, false);
      expect(closed, false);
      running.release();
      await closing;
      expect(monitor.closes, 1);
      monitor.pressure();
      expect(repository.processingScheduler.memoryPressureLimited, false);
    } finally {
      running.release();
      await session.close();
      await monitor.controller.close();
      await sandbox.delete(recursive: true);
    }
  });

  test('NFR-003 UT-101 actual Flutter binding pressure requires active observation and detaches on close', () async {
    final monitor = SystemMemoryPressureMonitor(
      binding: binding,
      nativeSignalFactory: () => null,
    );
    var events = 0;
    final subscription = monitor.events.listen((_) => events++);
    binding.handleMemoryPressure();
    expect(events, 0);
    await monitor.start();
    await monitor.start();
    binding.handleMemoryPressure();
    expect(events, 1);
    await subscription.cancel();
    await monitor.close();
    await monitor.close();
    await monitor.start();
    binding.handleMemoryPressure();
    monitor.didHaveMemoryPressure();
    expect(events, 1);
  });

  testWidgets(
    'NFR-003 UT-101 binding pressure refreshes settings budget without replacing focused numeric draft or saving it',
    (tester) async {
      final sandbox = await _native(
        tester,
        () => Directory.systemTemp.createTemp('imagehost-memory-settings-'),
      );
      final repository = await _native(
        tester,
        () => LibraryRepository.open(
          Directory('${sandbox.path}/library'),
          memoryBudgetBytes: 512 * _mib,
        ),
      );
      final monitor = SystemMemoryPressureMonitor(
        binding: binding,
        nativeSignalFactory: () => null,
      );
      final session = LibrarySession(
        repository,
        const [],
        memoryPressureMonitor: monitor,
      );
      final container = ProviderContainer(
        overrides: [librarySessionProvider.overrideWith((_) async => session)],
      );
      tester.view.physicalSize = const Size(1280, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: SettingsScreen()),
          ),
        );
        for (
          var count = 0;
          count < 500 &&
              tester
                      .widget<FilledButton>(
                        find.byKey(const Key('settings-save')),
                      )
                      .onPressed ==
                  null;
          count++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 40));
        }
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('settings-save')))
              .onPressed,
          isNotNull,
        );
        final field = find.byKey(const Key('settings-processing-concurrency'));
        await tester.scrollUntilVisible(
          field,
          250,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('settings-list')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, '3');
        await tester.pump();
        final editable = find.descendant(
          of: field,
          matching: find.byType(EditableText),
        );
        final oldState = tester.state<EditableTextState>(editable);
        final controller = tester.widget<TextField>(field).controller!;
        binding.handleMemoryPressure();
        expect(repository.processingScheduler.memoryPressureLimited, true);
        await tester.pump();
        expect(
          identical(tester.state<EditableTextState>(editable), oldState),
          true,
        );
        expect(controller.text, '3');
        expect(oldState.widget.focusNode.hasFocus, true);
        expect(find.textContaining('系统已报告内存压力'), findsOneWidget);
        expect(repository.currentDeviceSettings.processingConcurrency, 1);
        expect(tester.widget<TextField>(field).enabled, true);
        expect(tester.takeException(), isNull);
        expect(
          (await _native(
            tester,
            repository.loadSettings,
          )).values.processingConcurrency,
          1,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await _native(tester, session.close);
        await _native(tester, () => sandbox.delete(recursive: true));
      }
    },
  );

  test('NFR-003 UT-101 observer cleanup failure preserves actual lease drain and records only a fixed diagnostic', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'imagehost-pressure-close-failure-',
    );
    final root = Directory('${sandbox.path}/library');
    final repository = await LibraryRepository.open(root);
    final bytes = img.encodePng(img.Image(width: 3, height: 2));
    final asset = (await repository.importResource(
      PlatformResource(
        displayName: 'permanent.png',
        openRead: () => Stream.value(bytes),
      ),
    )).asset!;
    final lease = await repository.acquireAssetLease([
      asset.id,
    ], purpose: 'test active IO');
    final failure = _UnknownMonitorFailure();
    var monitorCloses = 0;
    final monitor = _Monitor(
      onClose: () async {
        if (monitorCloses++ == 0) throw failure;
      },
    );
    final session = LibrarySession(
      repository,
      const [],
      memoryPressureMonitor: monitor,
    );
    var closed = false;
    final closing = session.close().then((_) => closed = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(closed, false);
      await expectLater(
        LibraryRepository.open(root),
        throwsA(isA<LibraryOpenException>()),
      );
      expect(
        await File(lease.pathsByVersion[asset.version.id]!).readAsBytes(),
        bytes,
      );
      await lease.release();
      await closing;
      expect(closed, true);
      expect(failure.strings, 0);
      final reopened = await LibraryRepository.open(root);
      try {
        expect(
          (await reopened.getAsset(asset.id))!.version.id,
          asset.version.id,
        );
        final diagnostics = await reopened.loadDiagnostics();
        expect(
          diagnostics.items.where(
            (row) => row.code == 'memory_pressure.cleanup_failed',
          ),
          hasLength(1),
        );
        expect(
          diagnostics.items.map((row) => row.summary).join(),
          isNot(contains('Unknown native failure')),
        );
      } finally {
        await reopened.close();
      }
    } finally {
      await lease.release();
      await closing;
      await session.close();
      await monitor.controller.close();
      await sandbox.delete(recursive: true);
    }
  });
}
