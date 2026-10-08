import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/core/secret_redactor.dart';
import 'package:imagehost/core/secret_store.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/backup/application/backup_snapshot.dart';
import 'package:imagehost/features/backup/application/restore_coordinator.dart';
import 'package:imagehost/features/backup/data/backup_zip_writer.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/backup/presentation/backup_screen.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/gallery/presentation/desktop_gallery.dart';
import 'package:imagehost/features/gallery/presentation/mobile_gallery.dart';
import 'package:imagehost/platform/export_gateway.dart';
import 'package:imagehost/platform/backup_import_gateway.dart';
import 'package:imagehost/platform/storage_capacity.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'core/upload_repository_test.dart' show QueueTestSecrets;

class _DeleteGateSecrets extends QueueTestSecrets {
  final gate = Completer<void>();
  bool entered = false;
  @override
  Future<void> delete(String reference) async {
    entered = true;
    await gate.future;
    await super.delete(reference);
  }
}

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
  for (var i = 0; i < 1200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (ready()) return;
  }
  fail(
    '备份页面的真实 IO 与 widget 状态未完成：${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).whereType<String>().join(' | ')}',
  );
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
  _Picker(this.directory);
  final Directory? directory;
  int calls = 0;
  @override
  bool get supportsDirectoryExport => true;
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
        tagIds: const [],
        recycled: false,
      ),
    ],
    categories: const [],
    tags: const [],
    origins: const [],
    accounts: const [
      BackupAccount(
        id: '00000000-0000-4000-8000-000000000003',
        service: ImageHostService.catbox,
        alias: '导入账号',
        anonymous: false,
      ),
    ],
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
  Future<int> Function(String directory)? capacity,
  _ImportPicker? importPicker,
  SecretStore? secrets,
}) async {
  final sandbox = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('imagehost-backup-ui-'),
  ))!;
  final repository = (await tester.runAsync(
    () => LibraryRepository.open(
      Directory(p.join(sandbox.path, 'library')),
      secretStore: secrets,
    ),
  ))!;
  const channel = MethodChannel('io.imagehost/test_backup_capacity');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'availableBytes') {
          return capacity == null
              ? 1 << 40
              : await capacity(call.arguments as String);
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
    'UT-080 partial postcommit route disposal still resets surviving gallery intent and old secrets',
    (tester) async {
      final zip = await _writePackage(tester);
      final secrets = _DeleteGateSecrets();
      final (_, repository, container) = await _open(
        tester,
        _Picker(null),
        importPicker: _ImportPicker(zip),
        secrets: secrets,
      );
      await _native(tester, () async {
        await repository.importResource(
          PlatformResource(
            displayName: '旧选择.png',
            openRead: () =>
                Stream.value(img.encodePng(img.Image(width: 7, height: 6))),
          ),
        );
        await repository.saveTarget(
          service: ImageHostService.catbox,
          alias: '旧账号',
          anonymous: false,
          credential: 'synthetic-previous-key',
        );
      });
      final session = await _native(
        tester,
        () => container.read(librarySessionProvider.future),
      );
      await _native(tester, () => session.uploads.setNetworkAllowed(true));
      expect(session.uploads.networkAllowed, isTrue);
      final page = await _native(tester, repository.listAssets);
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: DesktopGallery(
              gallery: AsyncData(page),
              session: AsyncData(session),
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
      await tester.tap(find.text('多选'));
      await tester.pump();
      await tester.tap(find.text('旧选择.png').first);
      await tester.pump();
      expect(find.text('已选 1 张'), findsOneWidget);
      container.read(galleryQueryProvider.notifier).setKeyword('旧筛选');
      final navigator = Navigator.of(
        tester.element(find.byType(DesktopGallery)),
      );
      final route = MaterialPageRoute<void>(
        builder: (_) => const BackupScreen(),
      );
      unawaited(navigator.push(route));
      await tester.pump();
      await _ready(tester);
      await tester.ensureVisible(find.text('选择备份并替换恢复'));
      await tester.tap(find.text('选择备份并替换恢复'));
      await _until(
        tester,
        () => find.byType(AlertDialog).evaluate().isNotEmpty,
      );
      await tester.ensureVisible(
        find.byKey(const Key('replacement-risk-consent')),
      );
      await tester.tap(find.byKey(const Key('replacement-risk-consent')));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '确认替换恢复'));
      await _until(tester, () => secrets.entered);
      // Secret cleanup is reached only after the durable replacement commit.
      // Dispose the backup route while that real cleanup remains unfinished.
      navigator.removeRoute(route);
      await tester.pump();
      expect(repository.restoring, isTrue);
      expect(container.read(libraryReplacementRevisionProvider), 0);
      secrets.gate.complete();
      await _until(
        tester,
        () =>
            !repository.restoring &&
            container.read(libraryReplacementRevisionProvider) == 1,
      );
      expect(container.read(galleryQueryProvider).keyword, isEmpty);
      expect(find.text('已选 1 张'), findsNothing);
      expect(find.text('多选'), findsOneWidget);
      final targets = await _native(
        tester,
        () => repository.listTargets(includeRemoved: true),
      );
      expect(targets.single.alias, '导入账号');
      expect(targets.single.enabled, isFalse);
      expect(secrets.values, isEmpty);
      expect(session.uploads.networkAllowed, isFalse);
      await tester.pumpWidget(const SizedBox());
      await _native(tester, repository.close);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-080 partial orchestrator precommit fault preserves old library and releases maintenance',
    (tester) async {
      final zip = await _writePackage(tester);
      final (_, repository, container) = await _open(tester, _Picker(null));
      await _native(tester, () async {
        await repository.importResource(
          PlatformResource(
            displayName: '故障前.png',
            openRead: () =>
                Stream.value(img.encodePng(img.Image(width: 8, height: 7))),
          ),
        );
      });
      final session = await _native(
        tester,
        () => container.read(librarySessionProvider.future),
      );
      final coordinator = RestoreCoordinator(
        repository: repository,
        pauseUploads: session.uploads.holdForRestore,
        availableBytes: (_) async => 1 << 40,
        publishExclusive: (source, target) async {
          if (await target.exists()) return false;
          await source.rename(target.path);
          return true;
        },
      );
      Object? failure;
      await _native(tester, () async {
        try {
          await coordinator.replace(
            zip,
            zip.parent,
            confirm: (_) async => true,
            faultHook: (boundary) async {
              if (boundary == RestoreBoundary.beforeCommit) {
                throw StateError('controlled replacement failure');
              }
            },
          );
        } catch (error) {
          failure = error;
        }
      });
      expect(failure, isA<BackupSnapshotFailure>());
      expect(repository.restoring, isFalse);
      final page = await _native(tester, repository.listAssets);
      expect(page.items.single.displayName, '故障前.png');
      expect(
        await _native(tester, () => repository.verifyCopy(page.items.single)),
        CopyAvailability.available,
      );
      await _native(tester, repository.close);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-080 partial committed replacement survives postcommit session callback failure',
    (tester) async {
      final zip = await _writePackage(tester);
      final (_, repository, container) = await _open(tester, _Picker(null));
      final session = await _native(
        tester,
        () => container.read(librarySessionProvider.future),
      );
      final coordinator = RestoreCoordinator(
        repository: repository,
        pauseUploads: session.uploads.holdForRestore,
        availableBytes: (_) async => 1 << 40,
        publishExclusive: (source, target) async {
          if (await target.exists()) return false;
          await source.rename(target.path);
          return true;
        },
        afterReplacement: () async =>
            throw StateError('controlled session cleanup failure'),
      );
      final outcome = await _native(
        tester,
        () => coordinator.replace(zip, zip.parent, confirm: (_) async => true),
      );
      expect(outcome!.replaced, isTrue);
      expect(outcome.cleanupPending, isTrue);
      expect(repository.restoring, isFalse);
      expect(
        (await _native(tester, repository.listAssets)).items.single.displayName,
        '恢复图片.png',
      );
      await _native(tester, repository.close);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final mobile in [false, true]) {
    testWidgets(
      'UT-080 partial ${mobile ? 'M1' : 'desktop'} replacement revision clears an existing UUID selection',
      (tester) async {
        final (_, repository, container) = await _open(tester, _Picker(null));
        await _native(tester, () async {
          await repository.importResource(
            PlatformResource(
              displayName: '原选择.png',
              openRead: () =>
                  Stream.value(img.encodePng(img.Image(width: 3, height: 4))),
            ),
          );
        });
        final session = await _native(
          tester,
          () => container.read(librarySessionProvider.future),
        );
        final page = await _native(tester, repository.listAssets);
        tester.view.physicalSize = Size(mobile ? 390 : 1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final gallery = mobile
            ? MobileGallery(
                gallery: AsyncData(page),
                session: AsyncData(session),
                busy: false,
                loadingMore: false,
                supportsPhotos: false,
                onImport: (_) async {},
                onRetry: () {},
                onRefresh: () async {},
                onLoadMore: () async {},
                notices: const [],
              )
            : DesktopGallery(
                gallery: AsyncData(page),
                session: AsyncData(session),
                busy: false,
                loadingMore: false,
                onImport: (_) async {},
                onRetry: () {},
                onRefresh: () async {},
                onLoadMore: () async {},
                notices: const [],
              );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(home: gallery),
          ),
        );
        await tester.tap(find.text(mobile ? '选择' : '多选'));
        await tester.pump();
        await tester.tap(find.text('原选择.png').first);
        await tester.pump();
        expect(find.textContaining('已选 1 张'), findsWidgets);
        // Keep the exact same asset UUID visible: a fresh library must still
        // discard old UI intent instead of inheriting selection by identity.
        container.read(libraryReplacementRevisionProvider.notifier).committed();
        await tester.pump();
        expect(find.textContaining('已选 1 张'), findsNothing);
        expect(find.text(mobile ? '选择' : '多选'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await _native(tester, repository.close);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  Future<void> begin(WidgetTester tester) async {
    await tester.ensureVisible(find.text('选择备份并替换恢复'));
    await tester.tap(find.text('选择备份并替换恢复'));
    await _until(tester, () => find.byType(AlertDialog).evaluate().isNotEmpty);
  }

  Future<void> consent(WidgetTester tester) async {
    await tester.ensureVisible(
      find.byKey(const Key('replacement-risk-consent')),
    );
    await tester.tap(find.byKey(const Key('replacement-risk-consent')));
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '确认替换恢复'));
    await tester.tap(find.widgetWithText(FilledButton, '确认替换恢复'));
  }

  Future<void> sentinel(WidgetTester tester, LibraryRepository repository) =>
      _native(tester, () async {
        await repository.importResource(
          PlatformResource(
            displayName: '当前资料.png',
            openRead: () =>
                Stream.value(img.encodePng(img.Image(width: 5, height: 4))),
          ),
        );
      });

  testWidgets(
    'UT-080/AT-005 partial replacement requires independent risk consent and cancellation preserves real library',
    (tester) async {
      final zip = await _writePackage(tester);
      final (sandbox, repository, container) = await _open(
        tester,
        _Picker(null),
        importPicker: _ImportPicker(zip),
      );
      await sentinel(tester, repository);
      await _mount(tester, container, width: 390, scale: 1.6);
      await _ready(tester);
      await begin(tester);
      expect(await _storedAssetCount(tester, sandbox), 1);
      expect(find.text('模式：完整备份 → 替换恢复'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认替换恢复'))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('取消恢复'),
        ),
      );
      await _until(tester, () => !repository.restoring);
      expect(
        (await _native(tester, repository.listAssets)).items.single.displayName,
        '当前资料.png',
      );
      expect(container.read(libraryReplacementRevisionProvider), 0);
      expect(find.text('替换恢复已提交'), findsNothing);
      await _finishRestoreTest(tester, repository);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-080 partial full replacement commits real PNG, resets actor permission and survives reopen',
    (tester) async {
      final zip = await _writePackage(tester);
      final (sandbox, repository, container) = await _open(
        tester,
        _Picker(null),
        importPicker: _ImportPicker(zip),
      );
      await sentinel(tester, repository);
      final session = await _native(
        tester,
        () => container.read(librarySessionProvider.future),
      );
      final oldActor = session.uploads;
      await _native(tester, () => oldActor.setNetworkAllowed(true));
      expect(oldActor.networkAllowed, isTrue);
      container.read(galleryQueryProvider.notifier).setKeyword('当前');
      await _mount(tester, container);
      await _ready(tester);
      await begin(tester);
      expect(await _storedAssetCount(tester, sandbox), 1);
      await consent(tester);
      await _until(tester, () => find.text('替换恢复已提交').evaluate().isNotEmpty);
      final page = await _native(tester, repository.listAssets);
      expect(page.items.single.displayName, '恢复图片.png');
      expect(
        await _native(tester, () => repository.verifyCopy(page.items.single)),
        CopyAvailability.available,
      );
      expect(identical(session.uploads, oldActor), isFalse);
      expect(session.uploads.networkAllowed, isFalse);
      expect(container.read(galleryQueryProvider).keyword, isEmpty);
      expect(container.read(libraryReplacementRevisionProvider), 1);
      await _finishRestoreTest(tester, repository);
      final reopened = await _native(
        tester,
        () =>
            LibraryRepository.open(Directory(p.join(sandbox.path, 'library'))),
      );
      try {
        final page = await _native(tester, reopened.listAssets);
        expect(page.items.single.displayName, '恢复图片.png');
        expect(
          await _native(tester, () => reopened.verifyCopy(page.items.single)),
          CopyAvailability.available,
        );
      } finally {
        await _native(tester, reopened.close);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-080 partial metadata replacement explicitly creates missing image and does not reuse old bytes',
    (tester) async {
      final zip = await _writePackage(tester, mode: BackupMode.metadata);
      final (_, repository, container) = await _open(
        tester,
        _Picker(null),
        importPicker: _ImportPicker(zip),
      );
      await sentinel(tester, repository);
      await _mount(tester, container);
      await _ready(tester);
      await begin(tester);
      expect(find.text('元数据备份不包含图片字节。替换后的图片副本记为缺失，不能沿用旧图片内容。'), findsOneWidget);
      await consent(tester);
      await _until(tester, () => find.text('替换恢复已提交').evaluate().isNotEmpty);
      final page = await _native(tester, repository.listAssets);
      expect(page.items.single.displayName, '恢复图片.png');
      expect(
        await _native(tester, () => repository.verifyCopy(page.items.single)),
        CopyAvailability.missing,
      );
      await _finishRestoreTest(tester, repository);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-080 partial replacement dispose resolves confirmation and drains actual preparation',
    (tester) async {
      final zip = await _writePackage(tester);
      final (_, repository, container) = await _open(
        tester,
        _Picker(null),
        importPicker: _ImportPicker(zip),
      );
      await sentinel(tester, repository);
      await _mount(tester, container);
      await _ready(tester);
      await begin(tester);
      await tester.pumpWidget(const SizedBox());
      await _until(tester, () => !repository.restoring);
      expect(
        (await _native(tester, repository.listAssets)).items.single.displayName,
        '当前资料.png',
      );
      await _native(tester, repository.close);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-080 partial replacement cancellation waits outstanding capacity IO before releasing holds',
    (tester) async {
      final zip = await _writePackage(tester);
      final gate = Completer<int>();
      var entered = false;
      final (_, repository, container) = await _open(
        tester,
        _Picker(null),
        importPicker: _ImportPicker(zip),
        capacity: (directory) {
          // Preflight checks its private package directory. The managed library
          // space check belongs to snapshot preparation under both holds.
          if (p.basename(directory) == 'library' && !entered) {
            entered = true;
            return gate.future;
          }
          return Future.value(1 << 40);
        },
      );
      await sentinel(tester, repository);
      await _mount(tester, container);
      await _ready(tester);
      await tester.ensureVisible(find.text('选择备份并替换恢复'));
      await tester.tap(find.text('选择备份并替换恢复'));
      await _until(tester, () => entered);
      await tester.ensureVisible(find.text('取消恢复'));
      await tester.tap(find.text('取消恢复'));
      await tester.pump();
      expect(repository.restoring, isTrue);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      gate.complete(1 << 40);
      await _until(tester, () => !repository.restoring);
      expect(
        (await _native(tester, repository.listAssets)).items.single.displayName,
        '当前资料.png',
      );
      expect(find.text('替换恢复已提交'), findsNothing);
      await _finishRestoreTest(tester, repository);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
