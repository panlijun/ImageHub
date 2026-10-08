import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/processing/domain/output_models.dart';
import 'package:imagehost/features/settings/domain/device_settings.dart';
import 'package:imagehost/features/settings/presentation/settings_screen.dart';
import 'package:imagehost/features/storage/domain/storage_models.dart';
import 'package:imagehost/features/storage/presentation/storage_screen.dart';
import 'package:imagehost/platform/storage_capacity.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'IT-006 partial Windows native space cache confirmation settings SQL reopen and actual read drain',
    (tester) async {
      final sandbox = await Directory.systemTemp.createTemp(
        'imagehost-storage-engine-',
      );
      final root = Directory(p.join(sandbox.path, 'library'));
      const capacity = StorageCapacity();
      LibraryRepository? repository;
      LibrarySession? session;
      ProviderContainer? container;
      ThumbnailLease? protectedLease, readingLease;
      final boundary = GlobalKey();
      final readEntered = Completer<void>(), readContinue = Completer<void>();
      var blockRead = false;
      int? simulatedAvailable;
      var nativeProbes = 0, nativePublishes = 0;

      Future<void> until(bool Function() ready, String evidence) async {
        for (var i = 0; i < 200 && !ready(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(ready(), true, reason: evidence);
        expect(tester.takeException(), isNull);
      }

      List<Map<String, Object?>> rows(String table) {
        final database = sqlite.sqlite3.open(
          p.join(root.path, 'library.sqlite'),
          mode: sqlite.OpenMode.readOnly,
        );
        try {
          return [
            for (final row in database.select(
              'SELECT * FROM "$table" ORDER BY 1',
            ))
              Map<String, Object?>.from(row),
          ];
        } finally {
          database.close();
        }
      }

      List<Map<String, dynamic>> cacheRows() => [
        for (final row in rows('library_metadata'))
          if ((row['key']! as String).startsWith('thumbnail_cache_v1/'))
            Map<String, dynamic>.from(
              jsonDecode(row['value']! as String) as Map,
            ),
      ];

      List<int> picture(int red) {
        final image = img.Image(width: 32, height: 24, numChannels: 3);
        img.fill(image, color: img.ColorRgb8(red, 80, 120));
        return img.encodePng(image);
      }

      Future<(ImageAsset, File)> thumbnail(int red) async {
        final imported = await repository!.importResource(
          PlatformResource(
            displayName: '永久图片-$red.png',
            openRead: () => Stream.value(picture(red)),
          ),
        );
        expect(imported.status, ImportStatus.saved);
        final asset = imported.asset!;
        final thumbnail = await repository!.thumbnailFor(asset);
        expect(thumbnail, isNotNull);
        expect(
          p.isWithin(
            p.join(root.absolute.path, 'cache'),
            thumbnail!.absolute.path,
          ),
          true,
        );
        final decoded = img.decodePng(await thumbnail.readAsBytes());
        expect(decoded, isNotNull);
        expect(decoded!.width, 32);
        expect(decoded.height, 24);
        return (asset, thumbnail);
      }

      Future<void> open() async {
        repository = await LibraryRepository.open(
          root,
          availableStorageBytes: (directory) async {
            // Only the explicit low-space case is simulated. Every normal
            // call reaches the engine's real Windows capacity channel.
            if (simulatedAvailable != null) return simulatedAvailable;
            nativeProbes++;
            return capacity.availableBytes(directory);
          },
          publishCacheExclusive: (source, destination) async {
            nativePublishes++;
            return capacity.publishExclusive(source, destination);
          },
          cacheFaultHook: (value) async {
            if (blockRead && value == CacheBoundary.reading) {
              if (!readEntered.isCompleted) readEntered.complete();
              await readContinue.future;
            }
          },
        );
      }

      Future<void> mount(Widget page) async {
        await tester.pumpWidget(const SizedBox());
        session ??= LibrarySession(repository!, const []);
        container ??= ProviderContainer(
          overrides: [
            librarySessionProvider.overrideWith((ref) async => session!),
          ],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container!,
            // A default MaterialApp fixture, not the production theme.
            child: MaterialApp(
              home: RepaintBoundary(key: boundary, child: page),
            ),
          ),
        );
      }

      Future<void> visible(Finder finder, {bool upward = false}) async {
        await tester.scrollUntilVisible(
          finder,
          upward ? -250 : 250,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 40,
        );
        await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
        await tester.pump(const Duration(milliseconds: 250));
      }

      Future<void> close() async {
        await tester.pumpWidget(const SizedBox());
        container?.dispose();
        container = null;
        await session?.close();
        session = null;
        await repository?.close();
        repository = null;
      }

      try {
        expect(Platform.isWindows, true, reason: 'Windows engine fixture only');
        await open();
        expect(await capacity.availableBytes(root), greaterThan(0));

        // The native publication primitive must move only into an absent name.
        final publication = await Directory(p.join(sandbox.path, 'publication'))
            .create();
        final source = File(p.join(publication.path, 'source.part'));
        final destination = File(p.join(publication.path, 'published.png'));
        await source.writeAsBytes(picture(5), flush: true);
        expect(await capacity.publishExclusive(source, destination), true);
        expect(await source.exists(), false);
        expect(await destination.readAsBytes(), picture(5));
        await source.writeAsBytes(picture(6), flush: true);
        expect(await capacity.publishExclusive(source, destination), false);
        expect(await source.readAsBytes(), picture(6));
        expect(await destination.readAsBytes(), picture(5));

        final first = await thumbnail(10);
        final protected = await thumbnail(20);
        protectedLease = await repository!.acquireThumbnailLease(protected.$1);
        expect(protectedLease, isNotNull);
        expect(img.decodePng(await protectedLease!.readBytes()), isNotNull);
        final unknown = File(
          p.join(root.path, 'cache', 'thumbnails', 'unregistered.png'),
        );
        const unknownBytes = [11, 22, 33, 44];
        await unknown.writeAsBytes(unknownBytes, flush: true);
        final report = await repository!.loadStorageReport();
        expect(report.availableBytes, greaterThan(0));
        expect(
          report.fileBytes[StorageCategory.permanent],
          first.$1.version.byteCount + protected.$1.version.byteCount,
        );
        expect(
          report.fileBytes[StorageCategory.thumbnails],
          await first.$2.length() + await protected.$2.length() + 4,
        );
        expect(report.untrackedThumbnailBytes, 4);
        expect(report.protectedThumbnailBytes, await protected.$2.length());

        await mount(const StorageScreen());
        final clear = find.byKey(const Key('storage-clear-thumbnails'));
        await until(
          () =>
              clear.evaluate().isNotEmpty &&
              tester.widget<OutlinedButton>(clear).onPressed != null,
          'Real storage report enables cleanup after native capacity query',
        );
        await visible(find.byKey(const Key('storage-available')));
        expect(
          tester.widget<Text>(find.byKey(const Key('storage-available'))).data,
          isNot(contains('未知')),
        );
        await visible(clear, upward: true);
        await tester.tap(clear);
        await until(
          () => find.byKey(const Key('storage-confirm')).evaluate().isNotEmpty,
          'Real repository freezes its explicit cache cleanup scope',
        );
        expect(find.textContaining('已冻结 1 个缩略图'), findsOneWidget);
        expect(find.textContaining('1 个受保护项'), findsOneWidget);
        expect(find.textContaining('后来新增文件不会加入'), findsOneWidget);
        final later = await thumbnail(30);
        await tester.tap(find.byKey(const Key('storage-confirm')));
        await until(
          () =>
              find.textContaining('已清理 1 个缩略图').evaluate().isNotEmpty &&
              tester.widget<OutlinedButton>(clear).onPressed != null,
          'Confirmed page cleanup finishes real IO and reloads its report',
        );
        expect(await first.$2.exists(), false);
        expect(await protected.$2.exists(), true);
        expect(await later.$2.exists(), true);
        expect(await unknown.readAsBytes(), unknownBytes);

        await tester.pump(const Duration(milliseconds: 350));
        final render =
            boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final screenshot = await render.toImage(pixelRatio: 1);
        try {
          final bytes = await screenshot.toByteData(
            format: ui.ImageByteFormat.png,
          );
          // Resolve the real workspace from the runner's absolute working
          // directory; do not accidentally emit evidence beside its binary.
          var workspace = p.normalize(Directory.current.absolute.path);
          while (!await File(
            p.join(workspace, 'imagehost-new-project-kit', 'verify-kit.mjs'),
          ).exists()) {
            final parent = p.dirname(workspace);
            if (parent == workspace) {
              throw StateError('Cannot resolve storage evidence workspace');
            }
            workspace = parent;
          }
          final artifact = File(
            p.join(workspace, 'docs', 'validation', 'windows-storage.png'),
          );
          await artifact.parent.create(recursive: true);
          await artifact.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
        } finally {
          screenshot.dispose();
        }

        final rebuilt = await repository!.thumbnailFor(first.$1);
        expect(rebuilt, isNotNull);
        expect(rebuilt!.path, isNot(first.$2.path));
        expect(img.decodePng(await rebuilt.readAsBytes()), isNotNull);
        expect(cacheRows(), hasLength(3));
        expect(cacheRows().every((row) => row['state'] == 'ready'), true);
        final assetRows = rows('assets');
        final versionRows = rows('versions');
        final copyRows = rows('device_copies');

        await mount(const SettingsScreen());
        final cacheField = find.byKey(const Key('settings-cache-limit'));
        await until(
          () =>
              find.byKey(const Key('settings-save')).evaluate().isNotEmpty &&
              tester
                      .widget<FilledButton>(
                        find.byKey(const Key('settings-save')),
                      )
                      .onPressed !=
                  null,
          'Settings loads real device policy',
        );
        await visible(cacheField);
        expect(cacheField.hitTestable(), findsOneWidget);
        await tester.enterText(cacheField, '64');
        FocusManager.instance.primaryFocus?.unfocus();
        // Let the caret's pending showOnScreen request settle before moving
        // the real settings scroll viewport to the retention control.
        await tester.pump(const Duration(milliseconds: 100));
        final retention = find.byWidgetPredicate(
          (widget) => widget is DropdownButtonFormField<OutputRetention>,
        );
        await visible(retention);
        expect(retention.hitTestable(), findsOneWidget);
        await tester.tap(retention.hitTestable());
        await tester.pump(const Duration(milliseconds: 350));
        await until(
          () => find.text('1 小时').hitTestable().evaluate().isNotEmpty,
          'Actual retention dropdown opens after the text field loses focus',
        );
        await tester.tap(find.text('1 小时').hitTestable().last);
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          (await repository!.loadSettings()).values,
          DeviceSettings.defaults,
        );
        final save = find.byKey(const Key('settings-save'));
        await visible(save, upward: true);
        expect(save.hitTestable(), findsOneWidget);
        await tester.tap(save.hitTestable());
        await until(
          () =>
              find.text('已保存。').evaluate().isNotEmpty &&
              tester.widget<FilledButton>(save).onPressed != null,
          'Cache limit and output retention commit together',
        );
        final expected = DeviceSettings(
          cacheLimitMiB: 64,
          defaultOutputRetention: OutputRetention.hour,
        );
        expect((await repository!.loadSettings()).values, expected);
        final settingsValue =
            rows('library_metadata').singleWhere(
                  (row) => row['key'] == 'device_settings_v1',
                )['value']!
                as String;
        expect(jsonDecode(settingsValue), expected.toJson());

        // This is a deliberate probe simulation, not a full disk / hardware test.
        simulatedAvailable = 1;
        final refused = await repository!.importResource(
          PlatformResource(
            displayName: '模拟低空间.png',
            openRead: () => Stream.value(picture(40)),
          ),
        );
        expect(refused.status, ImportStatus.failed);
        expect(refused.failure?.kind, FailureKind.lowSpace);
        simulatedAvailable = null;
        expect(rows('assets'), assetRows);
        expect(rows('versions'), versionRows);
        expect(rows('device_copies'), copyRows);
        expect(nativeProbes, greaterThan(0));
        expect(nativePublishes, 4);
        await protectedLease.release();
        protectedLease = null;

        // Gate an actual file.openRead chunk, then prove close waits until that
        // stream and checksum finish. The gate is controlled fault injection.
        readingLease = await repository!.acquireThumbnailLease(first.$1);
        expect(readingLease, isNotNull);
        blockRead = true;
        final reading = readingLease!.readBytes();
        await until(
          () => readEntered.isCompleted,
          'Real cache stream entered its read boundary',
        );
        await tester.pumpWidget(const SizedBox());
        container?.dispose();
        container = null;
        var closed = false;
        final closing = session!.close().then((_) => closed = true);
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          closed,
          false,
          reason: 'Close cannot release the root while actual read IO is held',
        );
        readContinue.complete();
        expect(img.decodePng(await reading), isNotNull);
        await readingLease.release();
        readingLease = null;
        await closing;
        session = null;
        repository = null;
        blockRead = false;
        await open();
        expect((await repository!.loadSettings()).values, expected);
        expect(
          rows(
            'library_metadata',
          ).singleWhere((row) => row['key'] == 'device_settings_v1')['value'],
          settingsValue,
        );
        expect(rows('assets'), assetRows);
        expect(rows('versions'), versionRows);
        expect(rows('device_copies'), copyRows);
        expect(cacheRows(), hasLength(3));
        expect(await unknown.readAsBytes(), unknownBytes);
        for (final fixture in [(first, 10), (protected, 20), (later, 30)]) {
          final asset = fixture.$1.$1;
          final original = await repository!.originalFor(asset);
          expect(
            p.isWithin(
              p.join(root.absolute.path, 'originals'),
              original.absolute.path,
            ),
            true,
          );
          expect(await original.readAsBytes(), picture(fixture.$2));
          expect(
            await repository!.verifyCopy(asset),
            CopyAvailability.available,
          );
        }
        expect(rows('upload_publications'), isEmpty);
        expect(rows('remote_upload_results'), isEmpty);
        expect(rows('credential_operations'), isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        if (!readContinue.isCompleted) readContinue.complete();
        await protectedLease?.release();
        await readingLease?.release();
        await close();
        final target = p.normalize(p.absolute(sandbox.path));
        final temporary = p.normalize(p.absolute(Directory.systemTemp.path));
        if (!p.isWithin(temporary, target) ||
            !p.basename(target).startsWith('imagehost-storage-engine-')) {
          throw StateError(
            'Storage fixture cleanup is outside its owned temporary directory',
          );
        }
        // Only the verified, self-created sandbox is removed after IO drains.
        await Directory(target).delete(recursive: true);
      }
    },
  );
}
