import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/core/secret_redactor.dart';
import 'package:imagehost/features/backup/application/backup_snapshot.dart';
import 'package:imagehost/features/backup/data/backup_zip_reader.dart';
import 'package:imagehost/features/backup/data/backup_zip_writer.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/backup/presentation/backup_screen.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/platform/export_gateway.dart';
import 'package:imagehost/platform/backup_import_gateway.dart';
import 'package:imagehost/platform/storage_capacity.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

// Native SQLite/archive IO and widget fake time must both be drained. These
// loops fail when IO does not finish; they do not turn a hung test into success.
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
  for (var i = 0; i < 300 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done, isTrue, reason: '真实资料库/备份 IO 必须结束');
  if (failure != null) throw failure!;
  return value as T;
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 300; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (ready()) return;
  }
  fail('备份页面的真实 IO 与 widget 状态未完成');
}

Future<int> _storedAssetCount(WidgetTester tester, Directory sandbox) =>
    _native(tester, () async {
      final database = sqlite.sqlite3.open(
        p.join(sandbox.path, 'library', 'library.sqlite'),
        mode: sqlite.OpenMode.readOnly,
      );
      try {
        return database
                .select('SELECT COUNT(*) AS count FROM assets')
                .single['count']
            as int;
      } finally {
        database.close();
      }
    });

Future<void> _finishRestoreTest(
  WidgetTester tester,
  LibraryRepository repository,
) async {
  await tester.pumpWidget(const SizedBox());
  await _until(tester, () => !repository.restoring);
  // Restore releases restart maintenance in the widget zone. Close during the
  // test body, before Flutter verifies that no fake timer remains pending.
  await _native(tester, repository.close);
}

class _Picker extends ExportGateway {
  _Picker(this.directory, {this.supported = true});
  final Directory? directory;
  final bool supported;
  int calls = 0;
  @override
  bool get supportsDirectoryExport => supported;
  @override
  Future<Directory?> pickDirectory() async {
    calls++;
    return directory;
  }
}

class _ImportPicker extends BackupImportGateway {
  _ImportPicker(this.file, {this.supported = true});
  final File? file;
  final bool supported;
  int calls = 0;
  @override
  bool get supportsPlatform => supported;
  @override
  Future<File?> pickBackup() async {
    calls++;
    return file;
  }

  @override
  Future<Directory> temporaryParent() async =>
      file?.parent ?? Directory.systemTemp;
}

Future<File> _writePackage(
  WidgetTester tester, {
  BackupMode mode = BackupMode.full,
  bool conflictingDescription = false,
  int incomingTags = 0,
}) async {
  final directory = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('backup-ui-package-'),
  ))!;
  addTearDown(() => tester.runAsync(() => directory.delete(recursive: true)));
  final bytes = img.encodePng(img.Image(width: 3, height: 2));
  const versionId = '00000000-0000-4000-8000-000000000001';
  final version = ImageVersion(
    id: versionId,
    sha256: sha256.convert(bytes).toString(),
    byteCount: bytes.length,
    format: 'PNG',
    width: conflictingDescription ? 4 : 3,
    height: 2,
    frameCount: 1,
    orientation: 1,
  );
  final manifest = BackupManifest(
    packageId: '00000000-0000-4000-8000-000000000999',
    createdUtc: 1700000000000,
    mode: mode,
    versions: [version],
    assets: [
      BackupAsset(
        id: '00000000-0000-4000-8000-000000000002',
        versionId: versionId,
        displayName: '恢复图片.png',
        sourceType: 'selected',
        importedUtc: 1700000000000,
        updatedUtc: 1700000000000,
        favorite: false,
        tagIds: List.generate(
          incomingTags,
          (i) =>
              '00000000-0000-4000-9000-${(i + 1).toString().padLeft(12, '0')}',
        ),
        recycled: false,
      ),
    ],
    categories: const [],
    tags: List.generate(
      incomingTags,
      (i) => BackupName(
        id: '00000000-0000-4000-9000-${(i + 1).toString().padLeft(12, '0')}',
        name: '来源标签$i',
      ),
    ),
    origins: const [],
    accounts: const [],
    results: const [],
    history: const [],
    images: mode == BackupMode.metadata
        ? const []
        : [
            BackupImageEntry(
              versionId: versionId,
              name: 'images/$versionId.png',
              byteCount: version.byteCount,
              sha256: version.sha256,
            ),
          ],
  );
  final file = File(p.join(directory.path, 'source.png'));
  await tester.runAsync(() => file.writeAsBytes(bytes, flush: true));
  final lease = BackupSnapshotLease(
    manifest: manifest,
    manifestBytes: manifest.encode(redactor: SecretRedactor()),
    permanentFiles: mode == BackupMode.metadata ? {} : {versionId: file},
    onRelease: () async {},
  );
  final zip = File(p.join(directory.path, 'restore.zip'));
  await _native(tester, () => BackupZipWriter().write(lease, zip));
  await lease.release();
  return zip;
}

Future<void> _mount(
  WidgetTester tester,
  ProviderContainer container, {
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const BackupScreen(),
      ),
    ),
  );
}

Future<(Directory, LibraryRepository, ProviderContainer)> _open(
  WidgetTester tester,
  _Picker picker, {
  Future<int> Function()? capacity,
  _ImportPicker? importPicker,
}) async {
  final sandbox = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('imagehost-backup-ui-'),
  ))!;
  final repository = (await tester.runAsync(
    () => LibraryRepository.open(Directory(p.join(sandbox.path, 'library'))),
  ))!;
  const channel = MethodChannel('io.imagehost/test_backup_capacity');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'availableBytes') {
          return capacity == null ? 1 << 40 : await capacity();
        }
        if (call.method == 'publishExclusive') {
          // Controlled publication is an application/widget test, not evidence of
          // Windows native atomic exclusivity; that is independently integrated.
          final args = Map<String, Object?>.from(call.arguments as Map);
          final source = File(args['source']! as String);
          final target = File(args['destination']! as String);
          if (await target.exists()) return false;
          await source.rename(target.path);
          return true;
        }
        throw MissingPluginException();
      });
  final session = LibrarySession(repository, const []);
  final container = ProviderContainer(
    overrides: [
      librarySessionProvider.overrideWith((_) async => session),
      backupExportGatewayProvider.overrideWithValue(picker),
      backupImportGatewayProvider.overrideWithValue(
        importPicker ?? _ImportPicker(null, supported: false),
      ),
      backupStorageCapacityProvider.overrideWithValue(
        const StorageCapacity(channel: channel),
      ),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await _native(tester, session.close);
    await tester.runAsync(() => sandbox.delete(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  return (sandbox, repository, container);
}

Future<void> _ready(WidgetTester tester) => _until(
  tester,
  () =>
      find.byType(LinearProgressIndicator).evaluate().isEmpty &&
      find.widgetWithText(FilledButton, '导出完整备份').evaluate().isNotEmpty,
);

void main() {
  testWidgets(
    'UT-075 partial ZIP picker cancellation never starts restore maintenance or changes assets',
    (tester) async {
      final picker = _ImportPicker(null);
      final (_, repository, container) = await _open(
        tester,
        _Picker(null),
        importPicker: picker,
      );
      await _mount(tester, container);
      await _ready(tester);
      await tester.ensureVisible(find.text('选择备份并合并恢复'));
      await tester.tap(find.text('选择备份并合并恢复'));
      await tester.pump();
      expect(find.text('已取消选择备份，当前资料库没有变化。'), findsOneWidget);
      expect(picker.calls, 1);
      expect(repository.restoring, isFalse);
      expect((await _native(tester, repository.listAssets)).total, 0);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('合并恢复已提交'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-075/AT-003 partial real ZIP confirmation precedes permanent PNG commit at 390 large text',
    (tester) async {
      final zip = await _writePackage(tester);
      final picker = _ImportPicker(zip);
      final (sandbox, repository, container) = await _open(
        tester,
        _Picker(null),
        importPicker: picker,
      );
      await _mount(tester, container, width: 390, scale: 1.6);
      await _ready(tester);
      await tester.ensureVisible(find.text('选择备份并合并恢复'));
      await tester.tap(find.text('选择备份并合并恢复'));
      await _until(
        tester,
        () => find.byType(AlertDialog).evaluate().isNotEmpty,
      );
      expect(await _storedAssetCount(tester, sandbox), 0);
      expect(find.text('模式：完整备份 → 合并恢复'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.widgetWithText(FilledButton, '确认合并恢复'));
      await tester.tap(find.widgetWithText(FilledButton, '确认合并恢复'));
      await _until(tester, () => find.text('合并恢复已提交').evaluate().isNotEmpty);
      final page = await _native(tester, repository.listAssets);
      expect(page.total, 1);
      expect(
        await _native(tester, () => repository.verifyCopy(page.items.single)),
        CopyAvailability.available,
      );
      expect(find.textContaining('保存 1 个图片副本'), findsOneWidget);
      expect(
        identical(
          await _native(
            tester,
            () => container.read(librarySessionProvider.future),
          ),
          container.read(librarySessionProvider).value,
        ),
        isTrue,
      );
      expect(picker.calls, 1);
      expect(tester.takeException(), isNull);
      await _finishRestoreTest(tester, repository);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-075 partial confirmation cancellation writes no assets and closes maintenance',
    (tester) async {
      final zip = await _writePackage(tester);
      final (_, repository, container) = await _open(
        tester,
        _Picker(null),
        importPicker: _ImportPicker(zip),
      );
      await _mount(tester, container);
      await _ready(tester);
      await tester.ensureVisible(find.text('选择备份并合并恢复'));
      await tester.tap(find.text('选择备份并合并恢复'));
      await _until(
        tester,
        () => find.byType(AlertDialog).evaluate().isNotEmpty,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('取消恢复'),
        ),
      );
      await _until(
        tester,
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      expect((await _native(tester, repository.listAssets)).total, 0);
      expect(find.text('合并恢复已提交'), findsNothing);
      expect(find.text('已取消合并恢复，当前资料库没有变化。已暂停的上传任务须手动恢复。'), findsOneWidget);
      // A fresh normal write proves that the restore hold was really released.
      await _native(
        tester,
        () => repository.importResource(
          PlatformResource(
            displayName: '取消后.png',
            openRead: () =>
                Stream.value(img.encodePng(img.Image(width: 1, height: 1))),
          ),
        ),
      );
      await _finishRestoreTest(tester, repository);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-075 partial metadata restore explicitly keeps new copy missing',
    (tester) async {
      final zip = await _writePackage(tester, mode: BackupMode.metadata);
      final (_, repository, container) = await _open(
        tester,
        _Picker(null),
        importPicker: _ImportPicker(zip),
      );
      await _mount(tester, container);
      await _ready(tester);
      await tester.ensureVisible(find.text('选择备份并合并恢复'));
      await tester.tap(find.text('选择备份并合并恢复'));
      await _until(
        tester,
        () => find.byType(AlertDialog).evaluate().isNotEmpty,
      );
      expect(find.text('元数据备份不恢复图片字节。新增副本记为缺失；已有可用图片副本保留。'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '确认合并恢复'));
      await _until(tester, () => find.text('合并恢复已提交').evaluate().isNotEmpty);
      final page = await _native(tester, repository.listAssets);
      expect(
        await _native(tester, () => repository.verifyCopy(page.items.single)),
        CopyAvailability.missing,
      );
      expect(find.text('本次为元数据恢复，不恢复图片字节；没有可用副本的图片显示缺失。'), findsOneWidget);
      expect(find.textContaining('保存 0 个图片副本'), findsOneWidget);
      await _finishRestoreTest(tester, repository);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-075 partial blocking description conflict disables confirmation without changing current library',
    (tester) async {
      final zip = await _writePackage(
        tester,
        mode: BackupMode.metadata,
        conflictingDescription: true,
      );
      final (sandbox, repository, container) = await _open(
        tester,
        _Picker(null),
        importPicker: _ImportPicker(zip),
      );
      await _native(
        tester,
        () => repository.importResource(
          PlatformResource(
            displayName: '当前.png',
            openRead: () =>
                Stream.value(img.encodePng(img.Image(width: 3, height: 2))),
          ),
        ),
      );
      await _mount(tester, container);
      await _ready(tester);
      await tester.ensureVisible(find.text('选择备份并合并恢复'));
      await tester.tap(find.text('选择备份并合并恢复'));
      await _until(
        tester,
        () => find.byType(AlertDialog).evaluate().isNotEmpty,
      );
      expect(find.text('存在阻断冲突，不能确认恢复。请取消并处理冲突后重试。'), findsOneWidget);
      expect(find.textContaining('核对同 SHA-256 和字节数版本'), findsOneWidget);
      expect(find.textContaining('本机保留版本：格式 PNG，尺寸 3 × 2'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认合并恢复'))
            .onPressed,
        isNull,
      );
      expect(await _storedAssetCount(tester, sandbox), 1);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('取消恢复'),
        ),
      );
      await _until(
        tester,
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      expect(
        (await _native(tester, repository.listAssets)).items.single.displayName,
        '当前.png',
      );
      await _finishRestoreTest(tester, repository);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-076/077 tag conflict explains both sides and action without truncation',
    (tester) async {
      final zip = await _writePackage(
        tester,
        mode: BackupMode.metadata,
        incomingTags: 3,
      );
      final (sandbox, repository, container) = await _open(
        tester,
        _Picker(null),
        importPicker: _ImportPicker(zip),
      );
      final imported = await _native(
        tester,
        () => repository.importResource(
          PlatformResource(
            displayName: '本机保留图片.png',
            openRead: () =>
                Stream.value(img.encodePng(img.Image(width: 3, height: 2))),
          ),
        ),
      );
      await _native(
        tester,
        () => repository.updateOrganization([
          imported.asset!.id,
        ], addTags: List.generate(50, (i) => '本机标签$i')),
      );
      await _mount(tester, container);
      await _ready(tester);
      await tester.ensureVisible(find.text('选择备份并合并恢复'));
      await tester.tap(find.text('选择备份并合并恢复'));
      await _until(
        tester,
        () => find.byType(AlertDialog).evaluate().isNotEmpty,
      );
      expect(find.textContaining('规则：BAK-004 / LIB-003'), findsOneWidget);
      expect(find.textContaining('备份来源「恢复图片.png」：3 个标签'), findsOneWidget);
      expect(find.textContaining('本机保留值「本机保留图片.png」：50 个标签'), findsOneWidget);
      expect(find.textContaining('并集：53 个（上限 50 个）'), findsOneWidget);
      expect(find.textContaining('重新导出备份并预检'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认合并恢复'))
            .onPressed,
        isNull,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('取消恢复'),
        ),
      );
      await _until(
        tester,
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      final current = (await _native(
        tester,
        repository.listAssets,
      )).items.single;
      expect(current.tags.length, 50);
      expect(current.displayName, '本机保留图片.png');
      expect(await _storedAssetCount(tester, sandbox), 1);
      await _finishRestoreTest(tester, repository);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-075 partial disposing during confirmation resolves pending restore without writing',
    (tester) async {
      final zip = await _writePackage(tester);
      final (_, repository, container) = await _open(
        tester,
        _Picker(null),
        importPicker: _ImportPicker(zip),
      );
      await _mount(tester, container);
      await _ready(tester);
      await tester.ensureVisible(find.text('选择备份并合并恢复'));
      await tester.tap(find.text('选择备份并合并恢复'));
      await _until(
        tester,
        () => find.byType(AlertDialog).evaluate().isNotEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      await _until(tester, () => !repository.restoring);
      await _native(
        tester,
        () => repository.importResource(
          PlatformResource(
            displayName: '退出后.png',
            openRead: () =>
                Stream.value(img.encodePng(img.Image(width: 1, height: 1))),
          ),
        ),
      );
      final page = await _native(tester, repository.listAssets);
      expect(page.total, 1);
      expect(page.items.single.displayName, '退出后.png');
      expect(tester.takeException(), isNull);
      await _native(tester, repository.close);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-073 partial entering backup again reads current asset count',
    (tester) async {
      final (_, repository, container) = await _open(tester, _Picker(null));
      await _mount(tester, container);
      await _ready(tester);
      expect(find.text('当前没有资产。仍可备份资料库中的其他有效记录。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      final bytes = img.encodePng(img.Image(width: 3, height: 2));
      await _native(
        tester,
        () => repository.importResource(
          PlatformResource(
            displayName: '新加入.png',
            openRead: () => Stream.value(bytes),
          ),
        ),
      );
      await _mount(tester, container);
      await _ready(tester);
      expect(find.text('资料库已载入：1 个资产（包含回收区）。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'UT-073 partial backup loading and library failure never enable export or expose exceptions',
    (tester) async {
      final waiting = Completer<LibrarySession>();
      final picker = _Picker(null);
      final loading = ProviderContainer(
        overrides: [
          librarySessionProvider.overrideWith((_) => waiting.future),
          backupExportGatewayProvider.overrideWithValue(picker),
        ],
      );
      await _mount(tester, loading);
      expect(find.text('正在读取资料库…'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '导出完整备份'))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      loading.dispose();
      final failed = ProviderContainer(
        overrides: [
          librarySessionProvider.overrideWith(
            (_) async => throw StateError('private-path-and-secret'),
          ),
          backupExportGatewayProvider.overrideWithValue(picker),
        ],
      );
      addTearDown(failed.dispose);
      await _mount(tester, failed);
      await tester.pump();
      expect(find.text('资料库读取失败，不能开始备份。已有资料库保留，请返回图库检查后重试。'), findsOneWidget);
      expect(find.textContaining('private-path-and-secret'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '导出完整备份'))
            .onPressed,
        isNull,
      );
      expect(picker.calls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'AT-003 partial backup $width empty library large text and explicit unavailable platform',
      (tester) async {
        final picker = _Picker(null, supported: false);
        final (_, _, container) = await _open(tester, picker);
        await _mount(tester, container, width: width, scale: 1.6);
        await _ready(tester);
        expect(find.text('当前没有资产。仍可备份资料库中的其他有效记录。'), findsOneWidget);
        expect(find.text('此平台的原生备份导出尚未接入，暂不能选择目录或生成备份。'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '导出完整备份'))
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, '导出元数据备份'),
              )
              .onPressed,
          isNull,
        );
        await tester.ensureVisible(
          find.widgetWithText(FilledButton, '选择备份并合并恢复'),
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, '选择备份并合并恢复'),
              )
              .onPressed,
          isNull,
        );
        expect(picker.calls, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'UT-073 partial backup directory picker cancellation creates no package and retains library',
    (tester) async {
      final picker = _Picker(null);
      final (sandbox, repository, container) = await _open(tester, picker);
      await _mount(tester, container);
      await _ready(tester);
      await tester.ensureVisible(find.text('导出完整备份'));
      await tester.tap(find.text('导出完整备份'));
      await tester.pump();
      expect(find.text('已取消选择目录，没有生成备份文件。'), findsOneWidget);
      expect(picker.calls, 1);
      expect((await _native(tester, repository.listAssets)).total, 0);
      expect(
        (await tester.runAsync(() => sandbox.list().toList()))!
            .whereType<File>(),
        isEmpty,
      );
      expect(find.text('备份已提交'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-073/082 partial backup real SQLite metadata export omits image bytes and source paths',
    (tester) async {
      final exports = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('imagehost-backup-export-'),
      ))!;
      addTearDown(() => tester.runAsync(() => exports.delete(recursive: true)));
      final picker = _Picker(exports);
      final (_, repository, container) = await _open(tester, picker);
      final bytes = img.encodePng(img.Image(width: 3, height: 4));
      await _native(
        tester,
        () => repository.importResource(
          PlatformResource(
            displayName: '原图.png',
            openRead: () => Stream.value(bytes),
          ),
        ),
      );
      await _mount(tester, container);
      await _ready(tester);
      expect(find.textContaining('1 个资产'), findsOneWidget);
      await tester.ensureVisible(find.text('导出元数据备份'));
      await tester.tap(find.text('导出元数据备份'));
      await _until(tester, () => find.text('备份已提交').evaluate().isNotEmpty);
      expect(find.text('元数据备份（不能恢复图片内容）'), findsOneWidget);
      expect(find.textContaining(exports.path), findsNothing);
      final files = (await tester.runAsync(() => exports.list().toList()))!
          .whereType<File>()
          .toList();
      expect(files, hasLength(1));
      expect(find.text(p.basename(files.single.path)), findsOneWidget);
      final validated = await _native(
        tester,
        () => const BackupZipReader().preflight(
          files.single,
          exports,
          availableBytes: (_) async => 1 << 40,
        ),
      );
      expect(validated.manifest.mode, BackupMode.metadata);
      expect(validated.manifest.assets, hasLength(1));
      expect(validated.imageFiles, isEmpty);
      await _native(tester, validated.dispose);
      expect((await _native(tester, repository.listAssets)).total, 1);
      expect(picker.calls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-073/082 partial corrupt full backup lists UUID and never silently switches to metadata',
    (tester) async {
      final exports = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('imagehost-backup-corrupt-'),
      ))!;
      addTearDown(() => tester.runAsync(() => exports.delete(recursive: true)));
      final picker = _Picker(exports);
      final (sandbox, repository, container) = await _open(tester, picker);
      final bytes = img.encodePng(img.Image(width: 4, height: 4));
      final imported = await _native(
        tester,
        () => repository.importResource(
          PlatformResource(
            displayName: '待核查.png',
            openRead: () => Stream.value(bytes),
          ),
        ),
      );
      final asset = imported.asset!;
      await tester.runAsync(
        () =>
            File(p.join(sandbox.path, 'library', asset.deviceCopy.relativePath))
                .writeAsString('corrupt', flush: true),
      );
      await _mount(tester, container);
      await _ready(tester);
      await tester.ensureVisible(find.text('导出完整备份'));
      await tester.tap(find.text('导出完整备份'));
      await _until(tester, () => find.text('改为元数据备份').evaluate().isNotEmpty);
      expect(find.text('版本 UUID：${asset.version.id}'), findsOneWidget);
      expect((await tester.runAsync(() => exports.list().toList()))!, isEmpty);
      expect(find.text('备份已提交'), findsNothing);
      expect(picker.calls, 1);
      await tester.ensureVisible(find.text('改为元数据备份'));
      await tester.tap(find.text('改为元数据备份'));
      await _until(tester, () => find.text('备份已提交').evaluate().isNotEmpty);
      expect(picker.calls, 2, reason: '用户明确改用元数据时必须重新选择目标');
      expect(find.text('元数据备份（不能恢复图片内容）'), findsOneWidget);
      expect((await _native(tester, repository.listAssets)).total, 1);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-082 partial backup cancellation waits real work and publishes no package',
    (tester) async {
      final exports = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('imagehost-backup-cancel-'),
      ))!;
      addTearDown(() => tester.runAsync(() => exports.delete(recursive: true)));
      final gate = Completer<int>();
      var capacityEntered = false;
      final picker = _Picker(exports);
      final (_, repository, container) = await _open(
        tester,
        picker,
        capacity: () {
          capacityEntered = true;
          return gate.future;
        },
      );
      await _mount(tester, container);
      await _ready(tester);
      await tester.ensureVisible(find.text('导出完整备份'));
      await tester.tap(find.text('导出完整备份'));
      await _until(tester, () => capacityEntered);
      await tester.ensureVisible(find.text('取消备份'));
      await tester.tap(find.text('取消备份'));
      await tester.pump();
      expect(find.text('正在停止，请等待操作结束…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '导出完整备份'))
            .onPressed,
        isNull,
      );
      expect(find.text('备份已提交'), findsNothing);
      gate.complete(1 << 40);
      await _until(
        tester,
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      expect(find.text('备份已取消，原资料库保持有效。'), findsOneWidget);
      expect((await tester.runAsync(() => exports.list().toList()))!, isEmpty);
      expect((await _native(tester, repository.listAssets)).total, 0);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
