import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/backup/data/backup_zip_reader.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/backup/presentation/backup_screen.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/processing/domain/export_models.dart';
import 'package:imagehost/platform/backup_import_gateway.dart';
import 'package:imagehost/platform/export_gateway.dart';
import 'package:imagehost/platform/mobile_file_workspace.dart';
import 'package:imagehost/platform/storage_capacity.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'mobile_recycle_test.dart' show MobileTestFixture, mobileNative;

// Software/widget evidence with real SQLite/files/ZIP and controlled system
// replies. No Android/Apple backend, service confirmation, device PT or network IO.
void main() {
  for (final capabilities in [(false, true), (true, false), (true, true)]) {
    testWidgets(
      'mobile backup file ${capabilities.$1} capacity ${capabilities.$2} gate independently of directories',
      (tester) async {
        final fixture = await _Fixture.create(
          tester,
          files: capabilities.$1,
          capacitySupported: capabilities.$2,
        );
        await fixture.mount(tester, size: const Size(320, 700), textScale: 1.5);
        final enabled = capabilities.$1 && capabilities.$2;
        expect(
          tester.widget<FilledButton>(_fullButton()).onPressed != null,
          enabled,
        );
        expect(
          tester
                  .widget<OutlinedButton>(
                    find.widgetWithText(OutlinedButton, '导出元数据备份'),
                  )
                  .onPressed !=
              null,
          enabled,
        );
        expect(fixture.gateway.supportsDirectoryExport, false);
        expect(fixture.gateway.calls, isEmpty);
        expect(fixture.workspaces, isEmpty);
        expect(tester.takeException(), isNull);
        await fixture.finish(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'UT-073/074 partial mobile real full ZIP precedes user save and preserves active/recycled UUIDs and bytes',
    (tester) async {
      final fixture = await _Fixture.create(tester);
      await fixture.mount(tester);
      await fixture.begin(tester);
      final call = fixture.gateway.calls.single;
      expect(call.photos, false);
      expect(call.inputs, hasLength(1));
      final input = call.inputs.single;
      expect(await mobileNative(tester, input.source.exists), true);
      expect(
        await mobileNative(tester, input.source.length),
        input.expectedByteCount,
      );
      expect(
        sha256
            .convert(await mobileNative(tester, input.source.readAsBytes))
            .toString(),
        input.expectedSha256,
      );
      expect(
        p.isWithin(fixture.workspaces.single.directory.path, input.source.path),
        true,
      );
      expect(find.text('备份已保存'), findsNothing);
      expect(find.text('备份已提交'), findsNothing);
      expect(tester.widget<FilledButton>(_fullButton()).onPressed, isNull);
      final validated = await mobileNative(
        tester,
        () => const BackupZipReader().preflight(
          input.source,
          fixture.preflight,
          availableBytes: fixture.capacity.availableBytes,
        ),
      );
      try {
        expect(validated.manifest.mode, BackupMode.full);
        expect(
          validated.manifest.assets.map((asset) => asset.id),
          unorderedEquals(fixture.assets.map((asset) => asset.id)),
        );
        expect(
          validated.manifest.versions,
          unorderedEquals(fixture.assets.map((asset) => asset.version)),
        );
        expect(
          validated.manifest.assets.where((asset) => asset.recycled),
          hasLength(1),
        );
        expect(validated.imageFiles.length, 2);
        for (final image in validated.imageFiles.entries) {
          expect(
            await mobileNative(tester, image.value.readAsBytes),
            fixture.originalBytes[image.key],
          );
        }
      } finally {
        await mobileNative(tester, validated.dispose);
      }
      await fixture.assertLibrary(tester);
      fixture.gateway.complete(ExportStatus.saved, name: '系统确认备份.zip');
      await _idle(tester);
      expect(find.text('备份已保存'), findsOneWidget);
      expect(find.text('系统确认备份.zip'), findsOneWidget);
      expect(find.textContaining('2 个资产 · 2 个内容版本'), findsOneWidget);
      expect(find.textContaining('content://'), findsNothing);
      expect(find.textContaining(fixture.privateRoot.path), findsNothing);
      expect(await mobileNative(tester, input.source.exists), false);
      expect(
        await mobileNative(tester, fixture.workspaces.single.directory.exists),
        false,
      );
      await fixture.assertLibrary(tester);
      expect(tester.takeException(), isNull);
      await fixture.finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final late in [false, true]) {
    testWidgets(
      'UT-073/100 iOS full backup file receipt late $late preserves confirmed save and warning',
      (tester) async {
        final fixture = await _Fixture.create(tester, operatingSystem: 'ios');
        await fixture.mount(tester);
        await fixture.begin(tester);
        final input = fixture.gateway.calls.single.inputs.single;
        expect(await mobileNative(tester, input.source.exists), true);
        expect(find.text('备份已保存'), findsNothing);
        if (late) {
          await tester.ensureVisible(find.text('取消备份'));
          await tester.tap(find.text('取消备份'));
          await tester.pump();
          expect(fixture.gateway.calls.single.cancellation!.isCancelled, true);
          expect(await mobileNative(tester, input.source.exists), true);
        }
        const name = 'iOS 已确认备份.zip';
        final uri = Uri.file('/selected/$name', windows: false).toString();
        const warning = '已确认保存；系统位置授权收尾未确认。';
        fixture.gateway.complete(
          ExportStatus.saved,
          name: name,
          uri: uri,
          reason: warning,
        );
        await _idle(tester);
        expect(find.text('备份已保存'), findsOneWidget);
        expect(find.text(name), findsOneWidget);
        expect(find.textContaining(warning), findsOneWidget);
        expect(find.textContaining('2 个资产 · 2 个内容版本'), findsOneWidget);
        expect(find.textContaining('file:///'), findsNothing);
        expect(await mobileNative(tester, input.source.exists), false);
        await fixture.assertLibrary(tester);
        expect(tester.takeException(), isNull);
        await fixture.finish(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'UT-074 iOS metadata backup reports confirmed file save without image entries',
    (tester) async {
      final fixture = await _Fixture.create(tester, operatingSystem: 'ios');
      await fixture.mount(tester);
      await tester.ensureVisible(find.text('导出元数据备份'));
      await tester.tap(find.text('导出元数据备份'));
      await tester.pump();
      await _until(tester, () => fixture.gateway.calls.isNotEmpty);
      final input = fixture.gateway.calls.single.inputs.single;
      final validated = await mobileNative(
        tester,
        () => const BackupZipReader().preflight(
          input.source,
          fixture.preflight,
          availableBytes: fixture.capacity.availableBytes,
        ),
      );
      try {
        expect(validated.manifest.mode, BackupMode.metadata);
        expect(validated.imageFiles, isEmpty);
      } finally {
        await mobileNative(tester, validated.dispose);
      }
      const name = 'iOS-metadata.zip';
      fixture.gateway.complete(
        ExportStatus.saved,
        name: name,
        uri: 'file:///selected/$name',
      );
      await _idle(tester);
      expect(find.text('备份已保存'), findsOneWidget);
      expect(find.text(name), findsOneWidget);
      expect(await mobileNative(tester, input.source.exists), false);
      await fixture.assertLibrary(tester);
      expect(tester.takeException(), isNull);
      await fixture.finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-100 partial mobile backup cancellation retains private ZIP until actual transfer and keeps late saved evidence',
    (tester) async {
      final fixture = await _Fixture.create(tester);
      await fixture.mount(tester);
      await fixture.begin(tester);
      final call = fixture.gateway.calls.single;
      final input = call.inputs.single;
      await tester.ensureVisible(find.text('取消备份'));
      await tester.tap(find.text('取消备份'));
      await tester.pump();
      expect(call.cancellation!.isCancelled, true);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '取消备份'))
            .onPressed,
        isNull,
      );
      expect(tester.widget<FilledButton>(_fullButton()).onPressed, isNull);
      expect(await mobileNative(tester, input.source.exists), true);
      expect(find.text('备份已保存'), findsNothing);
      fixture.gateway.complete(ExportStatus.saved, name: '迟到确认的用户备份.zip');
      await _idle(tester);
      expect(find.text('备份已保存'), findsOneWidget);
      expect(find.text('迟到确认的用户备份.zip'), findsOneWidget);
      expect(find.textContaining('2 个资产 · 2 个内容版本'), findsOneWidget);
      expect(await mobileNative(tester, input.source.exists), false);
      await fixture.assertLibrary(tester);
      expect(tester.takeException(), isNull);
      await fixture.finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'UT-100 partial disposing mobile backup requests cancellation without early private ZIP deletion',
    (tester) async {
      final fixture = await _Fixture.create(tester);
      await fixture.mount(tester);
      await fixture.begin(tester);
      final call = fixture.gateway.calls.single;
      final source = call.inputs.single.source;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(call.cancellation!.isCancelled, true);
      expect(await mobileNative(tester, source.exists), true);
      expect(
        await mobileNative(tester, fixture.workspaces.single.directory.exists),
        true,
      );
      fixture.gateway.complete(ExportStatus.saved, name: '页面关闭后的用户备份.zip');
      await _untilRemoved(tester, source.exists);
      await _untilRemoved(tester, fixture.workspaces.single.directory.exists);
      expect(
        await mobileNative(tester, fixture.workspaces.single.directory.exists),
        false,
      );
      await fixture.assertLibrary(tester);
      expect(tester.takeException(), isNull);
      await fixture.finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final status in [ExportStatus.failed, ExportStatus.cancelled]) {
    testWidgets(
      'mobile backup controlled $status result never reports the private ZIP as a saved backup',
      (tester) async {
        final fixture = await _Fixture.create(tester);
        await fixture.mount(tester);
        await fixture.begin(tester);
        final source = fixture.gateway.calls.single.inputs.single.source;
        fixture.gateway.complete(status, reason: '系统保存未确认，请核查目标位置。');
        await _idle(tester);
        expect(find.text('备份已保存'), findsNothing);
        expect(find.text('备份已提交'), findsNothing);
        expect(
          find.text(
            status == ExportStatus.cancelled
                ? '已取消系统保存，没有确认新的用户备份。'
                : '系统保存未确认，请核查目标位置。',
          ),
          findsOneWidget,
        );
        expect(await mobileNative(tester, source.exists), false);
        await fixture.assertLibrary(tester);
        expect(tester.takeException(), isNull);
        await fixture.finish(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  for (final destination in [
    ('', '备份.zip'),
    ('file:///private/backup.zip', '备份.zip'),
    ('content://documents/confirmed', ''),
  ]) {
    testWidgets(
      'mobile backup rejects incomplete saved evidence URI ${destination.$1.isEmpty ? 'missing' : Uri.parse(destination.$1).scheme} name ${destination.$2.isNotEmpty}',
      (tester) async {
        final fixture = await _Fixture.create(tester);
        await fixture.mount(tester);
        await fixture.begin(tester);
        fixture.gateway.complete(
          ExportStatus.saved,
          uri: destination.$1,
          name: destination.$2,
        );
        await _idle(tester);
        expect(find.text('备份已保存'), findsNothing);
        expect(find.text('备份已提交'), findsNothing);
        expect(find.text('系统尚未确认备份保存，请核查目标位置后重试。'), findsOneWidget);
        await fixture.assertLibrary(tester);
        expect(tester.takeException(), isNull);
        await fixture.finish(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'UT-074/100 partial changed closed mobile ZIP refuses cleanup while preserving confirmed user save',
    (tester) async {
      final fixture = await _Fixture.create(tester);
      await fixture.mount(tester);
      await fixture.begin(tester);
      final source = fixture.gateway.calls.single.inputs.single.source;
      final originalLength = await mobileNative(tester, source.length);
      await mobileNative(
        tester,
        () =>
            source.writeAsBytes([7, 8, 9], mode: FileMode.append, flush: true),
      );
      fixture.gateway.complete(ExportStatus.saved, name: '已确认的备份仍保留.zip');
      await _idle(tester);
      expect(find.text('备份已保存'), findsOneWidget);
      expect(find.text('已确认的备份仍保留.zip'), findsOneWidget);
      expect(find.textContaining('2 个资产 · 2 个内容版本'), findsOneWidget);
      expect(find.text('备份私有暂存清理未确认，现场已保留；已确认保存的备份保留。'), findsOneWidget);
      expect(find.textContaining(source.path), findsNothing);
      expect(await mobileNative(tester, source.exists), true);
      expect(await mobileNative(tester, source.length), originalLength + 3);
      expect(
        await mobileNative(tester, fixture.workspaces.single.directory.exists),
        true,
      );
      await fixture.assertLibrary(tester);
      expect(tester.takeException(), isNull);
      await fixture.finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

Finder _fullButton() => find.widgetWithText(FilledButton, '导出完整备份');

class _MobileGateway extends ExportGateway {
  _MobileGateway({required this.files, required String operatingSystem})
    : super(operatingSystem: operatingSystem);
  final bool files;
  final calls = <_Transfer>[];
  @override
  bool get supportsDirectoryExport => false;
  @override
  bool get supportsFileExport => files;
  @override
  bool get supportsPhotos => false;
  @override
  Future<Directory?> pickDirectory() => throw StateError(
    'Directory selection must not run in this mobile software test.',
  );
  @override
  Future<List<ExportItemResult>> exportFiles(
    List<ExportInput> inputs, {
    CancellationToken? cancellation,
    bool photos = false,
  }) {
    final call = _Transfer(List.unmodifiable(inputs), cancellation, photos);
    calls.add(call);
    return call.result.future;
  }

  void complete(
    ExportStatus status, {
    String name = '测试备份.zip',
    String uri = 'content://documents/confirmed',
    String? reason,
  }) {
    final call = calls.single;
    call.result.complete([
      ExportItemResult(
        id: call.inputs.single.id,
        status: status,
        fileName: name,
        destinationUri: uri,
        reason: reason,
      ),
    ]);
  }
}

class _Transfer {
  _Transfer(this.inputs, this.cancellation, this.photos);
  final List<ExportInput> inputs;
  final CancellationToken? cancellation;
  final bool photos;
  final result = Completer<List<ExportItemResult>>();
}

class _NoImport extends BackupImportGateway {
  const _NoImport();
  @override
  bool get supportsPlatform => false;
}

class _Fixture {
  _Fixture(
    this.base,
    this.container,
    this.gateway,
    this.capacity,
    this.privateRoot,
    this.preflight,
    this.workspaces,
    this.assets,
    this.originalBytes,
  );
  final MobileTestFixture base;
  final ProviderContainer container;
  final _MobileGateway gateway;
  final StorageCapacity capacity;
  final Directory privateRoot, preflight;
  final List<MobileFileWorkspace> workspaces;
  final List<ImageAsset> assets;
  final Map<String, List<int>> originalBytes;

  static Future<_Fixture> create(
    WidgetTester tester, {
    bool files = true,
    bool capacitySupported = true,
    String operatingSystem = 'android',
  }) async {
    final base = await MobileTestFixture.create(
      tester,
      names: ['普通原图.png', '回收原图.png'],
    );
    await mobileNative(
      tester,
      () => base.repository.removeAssets([base.assets.last.id]),
    );
    final assets = <ImageAsset>[];
    final bytes = <String, List<int>>{};
    for (final imported in base.assets) {
      final asset = (await mobileNative(
        tester,
        () => base.repository.getAsset(imported.id, includeRecycled: true),
      ))!;
      assets.add(asset);
      bytes[asset.version.id] = await mobileNative(
        tester,
        () =>
            File(p.join(base.libraryRoot.path, asset.deviceCopy.relativePath))
                .readAsBytes(),
      );
    }
    final privateRoot = Directory(p.dirname(base.libraryRoot.path));
    final transfers = await mobileNative(
      tester,
      () => Directory(p.join(privateRoot.path, 'transfers')).create(),
    );
    final preflight = await mobileNative(
      tester,
      () => Directory(p.join(privateRoot.path, 'preflight')).create(),
    );
    final channel = MethodChannel(
      'io.imagehost/test_mobile_backup_${const Uuid().v4()}',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      void privatePath(String path) {
        expect(
          p.isWithin(
                privateRoot.absolute.path,
                p.normalize(p.absolute(path)),
              ) ||
              p.equals(
                privateRoot.absolute.path,
                p.normalize(p.absolute(path)),
              ),
          true,
        );
      }

      if (call.method == 'availableBytes') {
        privatePath(call.arguments as String);
        expect(await Directory(call.arguments as String).exists(), true);
        return 1 << 40;
      }
      if (call.method == 'publishExclusive') {
        // Controlled exclusive creation/copy only in this unique test sandbox;
        // this does not prove Android native atomic publication or real space.
        final arguments = Map<String, Object?>.from(call.arguments as Map);
        final source = File(arguments['source']! as String);
        final target = File(arguments['destination']! as String);
        privatePath(source.path);
        privatePath(target.path);
        try {
          await target.create(exclusive: true);
        } on FileSystemException {
          if (await target.exists()) return false;
          rethrow;
        }
        await target.writeAsBytes(await source.readAsBytes(), flush: true);
        await source.delete();
        return true;
      }
      throw MissingPluginException();
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final capacity = StorageCapacity(
      channel: channel,
      operatingSystem: capacitySupported ? operatingSystem : 'linux',
    );
    final gateway = _MobileGateway(
      files: files,
      operatingSystem: operatingSystem,
    );
    final workspaces = <MobileFileWorkspace>[];
    final container = ProviderContainer(
      parent: base.container,
      overrides: [
        backupExportGatewayProvider.overrideWithValue(gateway),
        backupImportGatewayProvider.overrideWithValue(const _NoImport()),
        backupStorageCapacityProvider.overrideWithValue(capacity),
        backupTransferWorkspaceProvider.overrideWithValue(() async {
          final workspace = await MobileFileWorkspace.create(parent: transfers);
          workspaces.add(workspace);
          return workspace;
        }),
      ],
    );
    addTearDown(container.dispose);
    return _Fixture(
      base,
      container,
      gateway,
      capacity,
      privateRoot,
      preflight,
      workspaces,
      assets,
      bytes,
    );
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
          theme: ThemeData(
            platform: gateway.operatingSystem == 'ios'
                ? TargetPlatform.iOS
                : TargetPlatform.android,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const BackupScreen(),
        ),
      ),
    );
    await _idle(tester);
  }

  Future<void> begin(WidgetTester tester) async {
    await tester.ensureVisible(_fullButton());
    await tester.tap(_fullButton());
    await tester.pump();
    await _until(tester, () => gateway.calls.isNotEmpty);
    expect(workspaces, hasLength(1));
  }

  Future<void> assertLibrary(WidgetTester tester) async {
    for (final expected in assets) {
      expect(
        await mobileNative(
          tester,
          () => base.repository.getAsset(expected.id, includeRecycled: true),
        ),
        expected,
      );
      expect(
        await mobileNative(
          tester,
          () => File(
            p.join(base.libraryRoot.path, expected.deviceCopy.relativePath),
          ).readAsBytes(),
        ),
        originalBytes[expected.version.id],
      );
    }
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await mobileNative(tester, base.repository.close);
    await tester.pumpAndSettle();
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 2000 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(
    ready(),
    true,
    reason: 'Actual ZIP/SQLite IO and widget continuations must finish.',
  );
}

Future<void> _idle(WidgetTester tester) async {
  var idle = 0;
  await _until(tester, () {
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty &&
        find
            .byType(CircularProgressIndicator, skipOffstage: false)
            .evaluate()
            .isEmpty) {
      idle++;
    } else {
      idle = 0;
    }
    return idle >= 5;
  });
  await tester.pumpAndSettle();
}

Future<void> _untilRemoved(
  WidgetTester tester,
  Future<bool> Function() exists,
) async {
  for (var i = 0; i < 250; i++) {
    if (!await mobileNative(tester, exists)) {
      await tester.pumpAndSettle();
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail(
    'Disposed backup must await actual export and cleanup before removing its ZIP.',
  );
}
