import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/network_state.dart';
import 'package:imagehost/core/secret_redactor.dart';
import 'package:imagehost/features/backup/application/backup_snapshot.dart';
import 'package:imagehost/features/backup/data/backup_zip_writer.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/backup/domain/backup_settings.dart';
import 'package:imagehost/features/backup/presentation/backup_screen.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/processing/domain/output_models.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/settings/domain/device_settings.dart';
import 'package:imagehost/features/upload/application/upload_coordinator.dart';
import 'package:imagehost/features/upload/data/library_upload_queue_store.dart';
import 'package:imagehost/platform/backup_import_gateway.dart';
import 'package:imagehost/platform/export_gateway.dart';
import 'package:imagehost/platform/storage_capacity.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

final _incoming = DeviceSettings(
  uploadConcurrency: 5,
  processingConcurrency: 2,
  quality: 73,
  longestSide: 2300,
  processingMode: ProcessingMode.sizeFirst,
  cacheLimitMiB: 384,
  defaultOutputRetention: OutputRetention.week,
);
final _local = DeviceSettings(
  uploadConcurrency: 2,
  processingConcurrency: 1,
  quality: 91,
  longestSide: 900,
  processingMode: ProcessingMode.fidelity,
  cacheLimitMiB: 128,
  defaultOutputRetention: OutputRetention.hour,
  networkUploadPolicy: NetworkUploadPolicy.anyKnownNetwork,
);
final _expected = DeviceSettings.fromJson({
  ..._incoming.toJson(),
  'quality': 91,
});

// Drain actual database/archive IO and widget fake time alternately. Timeout
// remains a failure, never a substitute for confirming that real IO finished.
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
  for (var i = 0; i < 1200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (ready()) return;
  }
  fail('BAK-005 真实备份 IO 与页面状态未结束');
}

Future<void> _deleteOwnedTemporaryDirectory(
  Directory directory,
  String prefix,
) async {
  final temporaryRoot = p.normalize(
    await Directory.systemTemp.resolveSymbolicLinks(),
  );
  final resolved = p.normalize(await directory.resolveSymbolicLinks());
  if (!p.isAbsolute(resolved) ||
      !p.isWithin(temporaryRoot, resolved) ||
      !p.basename(resolved).startsWith(prefix)) {
    throw StateError('临时测试目录归属未确认，拒绝递归删除。');
  }
  await Directory(resolved).delete(recursive: true);
}

class _ImportPicker extends BackupImportGateway {
  _ImportPicker(this.file);
  final File file;
  @override
  bool get supportsPlatform => true;
  @override
  Future<File?> pickBackup() async => file;
  @override
  Future<Directory> temporaryParent() async => file.parent;
}

class _ExportPicker extends ExportGateway {
  @override
  bool get supportsDirectoryExport => true;
  @override
  Future<Directory?> pickDirectory() async => null;
}

Future<File> _package(WidgetTester tester, {bool legacy = false}) async {
  final directory = await _native(
    tester,
    () => Directory.systemTemp.createTemp('backup-settings-package-'),
  );
  addTearDown(
    () => tester.runAsync(
      () =>
          _deleteOwnedTemporaryDirectory(directory, 'backup-settings-package-'),
    ),
  );
  final manifest = BackupManifest(
    packageId: '00000000-0000-4000-8000-000000000999',
    createdUtc: 1700000000000,
    mode: BackupMode.metadata,
    versions: const [],
    assets: const [],
    categories: const [],
    tags: const [],
    origins: const [],
    accounts: const [],
    results: const [],
    history: const [],
    images: const [],
    settings: legacy
        ? null
        : BackupDeviceSettings(
            values: _incoming,
            availability: const {
              BackupSetting.quality: {
                BackupPlatform.android,
                BackupPlatform.ios,
              },
            },
          ),
  );
  var manifestBytes = manifest.encode(redactor: SecretRedactor());
  if (legacy) {
    final json = jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
    json.remove('settings');
    json['formatVersion'] = 1;
    manifestBytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
  }
  final lease = BackupSnapshotLease(
    manifest: manifest,
    manifestBytes: manifestBytes,
    permanentFiles: const {},
    onRelease: () async {},
  );
  final zip = File(p.join(directory.path, 'settings.zip'));
  try {
    await _native(tester, () => BackupZipWriter().write(lease, zip));
  } finally {
    await lease.release();
  }
  return zip;
}

Future<(Directory, LibrarySession, ProviderContainer)> _open(
  WidgetTester tester,
  File zip,
) async {
  final sandbox = await _native(
    tester,
    () => Directory.systemTemp.createTemp('backup-settings-ui-'),
  );
  final root = Directory(p.join(sandbox.path, 'library'));
  final repository = await _native(tester, () => LibraryRepository.open(root));
  await _native(tester, () async {
    final before = await repository.loadSettings();
    await repository.saveSettings(before, _local, defaultTargetIds: const []);
  });
  const channel = MethodChannel('io.imagehost/test_backup_settings_capacity');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'availableBytes') return 1 << 40;
        if (call.method == 'publishExclusive') {
          // Controlled widget publication; real Windows exclusivity is covered
          // separately by backup_flow_test on the actual engine.
          final args = Map<String, Object?>.from(call.arguments as Map);
          final source = File(args['source']! as String);
          final target = File(args['destination']! as String);
          if (await target.exists()) return false;
          await source.rename(target.path);
          return true;
        }
        throw MissingPluginException();
      });
  final session = LibrarySession(
    repository,
    const [],
    uploads: UploadCoordinator(
      LibraryUploadQueueStore(repository),
      adapters: const [],
    ),
  );
  final container = ProviderContainer(
    overrides: [
      librarySessionProvider.overrideWith((_) async => session),
      backupExportGatewayProvider.overrideWithValue(_ExportPicker()),
      backupImportGatewayProvider.overrideWithValue(_ImportPicker(zip)),
      backupStorageCapacityProvider.overrideWithValue(
        const StorageCapacity(channel: channel),
      ),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await _native(tester, session.close);
    await tester.runAsync(
      () => _deleteOwnedTemporaryDirectory(sandbox, 'backup-settings-ui-'),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  return (root, session, container);
}

Future<void> _mount(
  WidgetTester tester,
  ProviderContainer container,
  double width,
) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: const BackupScreen(),
      ),
    ),
  );
  await _until(
    tester,
    () =>
        find.byType(LinearProgressIndicator).evaluate().isEmpty &&
        find.text('导出完整备份').evaluate().isNotEmpty,
  );
}

Future<void> _confirm(WidgetTester tester, {required bool replacement}) async {
  final entry = replacement ? '选择备份并替换恢复' : '选择备份并合并恢复';
  await tester.ensureVisible(find.text(entry));
  await tester.tap(find.text(entry));
  await _until(tester, () => find.byType(AlertDialog).evaluate().isNotEmpty);
}

void _assertValues({required bool confirmed}) {
  expect(
    find.text('${confirmed ? '已恢复' : '将覆盖'} 7 项可用设置；跳过 1 项。'),
    findsOneWidget,
  );
  for (final text in const [
    '上传并发：5',
    '处理并发：2',
    '体积优先最长边：2300 像素',
    '默认处理模式：体积优先',
    '缩略图缓存上限：384 MiB',
    '临时输出默认保留时间：7 天',
    '允许上传的网络类型：仅 Wi-Fi / 有线网络',
    '当前平台不适用，保留本机值：有损输出质量。',
  ]) {
    expect(find.text(text), findsOneWidget);
  }
  expect(find.text('有损输出质量：73'), findsNothing);
}

Future<void> _closeAndCheckDurable(
  WidgetTester tester,
  Directory root,
  LibrarySession session,
  DeviceSettings expected,
) async {
  await tester.pumpWidget(const SizedBox());
  await _until(tester, () => !session.repository.restoring);
  await _native(tester, session.close);
  final reopened = await _native(tester, () => LibraryRepository.open(root));
  try {
    expect((await _native(tester, reopened.loadSettings)).values, expected);
    expect(reopened.currentDeviceSettings, expected);
    expect(
      reopened.processingScheduler.configuredConcurrency,
      expected.processingConcurrency,
    );
  } finally {
    await _native(tester, reopened.close);
  }
}

void main() {
  for (final width in [390.0, 1280.0]) {
    for (final replacement in [false, true]) {
      testWidgets(
        'UT-073/078/081 BAK-005 partial ${replacement ? 'replacement' : 'merge'} setting values and platform skip at $width 2x text persist after reopen',
        (tester) async {
          final zip = await _package(tester);
          final (root, session, container) = await _open(tester, zip);
          await _mount(tester, container, width);
          await _confirm(tester, replacement: replacement);
          _assertValues(confirmed: false);
          expect(session.repository.currentDeviceSettings, _local);
          expect(session.uploads.networkAllowed, isFalse);
          expect(tester.takeException(), isNull);
          final button = find.widgetWithText(
            FilledButton,
            replacement ? '确认替换恢复' : '确认合并恢复',
          );
          if (replacement) {
            expect(tester.widget<FilledButton>(button).onPressed, isNull);
            await tester.ensureVisible(
              find.byKey(const Key('replacement-risk-consent')),
            );
            await tester.tap(find.byKey(const Key('replacement-risk-consent')));
            await tester.pump();
            expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
          }
          await tester.ensureVisible(button);
          await tester.tap(button);
          await _until(
            tester,
            () => find
                .text(replacement ? '替换恢复已提交' : '合并恢复已提交')
                .evaluate()
                .isNotEmpty,
          );
          _assertValues(confirmed: true);
          expect(session.repository.currentDeviceSettings, _expected);
          expect(
            session.repository.processingScheduler.configuredConcurrency,
            2,
          );
          expect(session.uploads.networkAllowed, isFalse);
          expect(session.uploads.concurrency, 5);
          expect(
            session.uploads.networkPolicy,
            NetworkUploadPolicy.wifiAndEthernet,
          );
          expect(tester.takeException(), isNull);
          await _closeAndCheckDurable(tester, root, session, _expected);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }
  }

  for (final replacement in [false, true]) {
    testWidgets(
      'UT-075/079/081 BAK-005 partial cancelling ${replacement ? 'replacement risk' : 'merge'} confirmation leaves settings durable and permission absent',
      (tester) async {
        final zip = await _package(tester);
        final (root, session, container) = await _open(tester, zip);
        await _mount(tester, container, 390);
        await _confirm(tester, replacement: replacement);
        _assertValues(confirmed: false);
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('取消恢复'),
          ),
        );
        await _until(
          tester,
          () =>
              !session.repository.restoring &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        expect(session.repository.currentDeviceSettings, _local);
        expect(session.uploads.networkAllowed, isFalse);
        expect(find.textContaining('已恢复 7 项'), findsNothing);
        expect(tester.takeException(), isNull);
        await _closeAndCheckDurable(tester, root, session, _local);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'UT-072/078/081 BAK-005 partial legacy format 1 reports absent settings and preserves local values',
    (tester) async {
      final zip = await _package(tester, legacy: true);
      final (root, session, container) = await _open(tester, zip);
      await _mount(tester, container, 1280);
      await _confirm(tester, replacement: false);
      expect(find.text('此备份未包含设置，保留当前本机设置。'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '确认合并恢复'));
      await _until(tester, () => find.text('合并恢复已提交').evaluate().isNotEmpty);
      expect(find.text('此备份未包含设置，保留当前本机设置。'), findsOneWidget);
      expect(session.repository.currentDeviceSettings, _local);
      expect(session.uploads.networkAllowed, isFalse);
      expect(tester.takeException(), isNull);
      await _closeAndCheckDurable(tester, root, session, _local);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
