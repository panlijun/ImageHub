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
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/processing/presentation/processing_workbench.dart';
import 'package:imagehost/features/settings/domain/device_settings.dart';
import 'package:imagehost/features/settings/presentation/settings_screen.dart';
import 'package:imagehost/platform/system_secret_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'IT-006 partial Windows settings save reopen initializes new real pixel workbench without rewriting old output',
    (tester) async {
      final sandbox = await Directory.systemTemp.createTemp(
        'imagehost-settings-engine-',
      );
      final root = Directory(p.join(sandbox.path, 'library'));
      final secrets = SystemSecretStore();
      late LibraryRepository repository;
      LibraryRepository? repositoryToClose;
      LibrarySession? session;
      ProviderContainer? container;
      final boundary = GlobalKey();

      Future<void> until(bool Function() ready, String evidence) async {
        for (var i = 0; i < 160 && !ready(); i++) {
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
          return database
              .select('SELECT * FROM "$table" ORDER BY 1')
              .map((row) => Map<String, Object?>.from(row))
              .toList();
        } finally {
          database.close();
        }
      }

      Future<void> mount(Widget page) async {
        // Recreate the native route and page state for a genuinely new draft.
        await tester.pumpWidget(const SizedBox());
        if (container == null) {
          session = LibrarySession(repository, const []);
          container = ProviderContainer(
            overrides: [
              librarySessionProvider.overrideWith((ref) async => session!),
            ],
          );
        }
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container!,
            child: MaterialApp(
              home: RepaintBoundary(key: boundary, child: page),
            ),
          ),
        );
      }

      Future<void> visible(Finder finder, {bool upward = false}) async {
        await tester.scrollUntilVisible(
          finder,
          upward ? -300 : 300,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 30,
        );
        await tester.ensureVisible(finder);
        await tester.pump(const Duration(milliseconds: 350));
      }

      String fieldText(String key) =>
          tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

      Future<void> edit(String key, String value) async {
        final field = find.byKey(ValueKey(key));
        await visible(field);
        await tester.enterText(field, value);
        await tester.pump();
      }

      Future<void> saveFromPage() async {
        final save = find.byKey(const Key('settings-save'));
        await visible(save, upward: true);
        expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
        await tester.tap(save);
        await until(
          () =>
              find.text('已保存。').evaluate().isNotEmpty &&
              tester.widget<FilledButton>(save).onPressed != null,
          'Settings page confirms its real transaction and reload',
        );
      }

      Future<void> unmountAndClose() async {
        try {
          await tester.pumpWidget(const SizedBox());
        } finally {
          container?.dispose();
          container = null;
          try {
            await session?.close();
          } finally {
            session = null;
            await repositoryToClose?.close();
          }
        }
      }

      try {
        repository = await LibraryRepository.open(root, secretStore: secrets);
        repositoryToClose = repository;
        // A real opaque RGB PNG permits JPEG without a transparency waiver.
        final source = img.Image(width: 64, height: 48, numChannels: 3);
        img.fill(source, color: img.ColorRgb8(80, 120, 160));
        final sourceBytes = img.encodePng(source);
        final asset = (await repository.importResource(
          PlatformResource(
            displayName: 'Windows 设置原图.png',
            openRead: () => Stream.value(sourceBytes),
          ),
        )).asset!;
        final targetId = await repository.saveTarget(
          service: ImageHostService.catbox,
          alias: 'Windows 默认账号目标',
          anonymous: false,
          credential: 'SyntheticAccountFixture0123456789',
        );
        final original = File(p.join(root.path, asset.deviceCopy.relativePath));
        expect(await original.readAsBytes(), sourceBytes);
        expect(
          p.isWithin(
            p.join(root.absolute.path, 'originals'),
            original.absolute.path,
          ),
          true,
        );
        final assetRows = rows('assets');
        final versionRows = rows('versions');
        final copyRows = rows('device_copies');

        await mount(const SettingsScreen());
        await until(
          () =>
              find
                  .byKey(const Key('settings-upload-concurrency'))
                  .evaluate()
                  .isNotEmpty &&
              tester
                      .widget<TextField>(
                        find.byKey(const Key('settings-upload-concurrency')),
                      )
                      .enabled ==
                  true,
          'Settings loads the real temporary repository',
        );
        await edit('settings-upload-concurrency', '5');
        await edit('settings-processing-concurrency', '2');
        await edit('settings-quality', '73');
        await edit('settings-longest-side', '16');
        final mode = find.byWidgetPredicate(
          (widget) => widget is DropdownButtonFormField<ProcessingMode>,
        );
        await visible(mode);
        await tester.tap(mode);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(find.text('体积优先').last);
        await tester.pump(const Duration(milliseconds: 350));
        final target = find.byKey(ValueKey('settings-target-$targetId'));
        await visible(target);
        expect(tester.widget<CheckboxListTile>(target).value, false);
        await tester.tap(target);
        await tester.pump();
        expect(tester.widget<CheckboxListTile>(target).value, true);
        // Draft editing has not granted network permission or persisted values.
        expect(
          (await repository.loadSettings()).values,
          DeviceSettings.defaults,
        );
        expect((await repository.loadSettings()).defaultTargetIds, isEmpty);
        await saveFromPage();
        final expected = DeviceSettings(
          uploadConcurrency: 5,
          processingConcurrency: 2,
          quality: 73,
          longestSide: 16,
          processingMode: ProcessingMode.sizeFirst,
        );
        expect((await repository.loadSettings()).values, expected);
        expect((await repository.loadSettings()).defaultTargetIds, {targetId});
        expect(repository.processingScheduler.configuredConcurrency, 2);

        await tester.pump(const Duration(milliseconds: 350));
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final picture = await render.toImage(pixelRatio: 1);
        try {
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final artifact = File(
            p.join(
              Directory.current.parent.path,
              'docs',
              'validation',
              'windows-settings.png',
            ),
          );
          await artifact.parent.create(recursive: true);
          await artifact.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
        } finally {
          picture.dispose();
        }

        await unmountAndClose();
        repository = await LibraryRepository.open(root, secretStore: secrets);
        repositoryToClose = repository;
        final reopened = await repository.loadSettings();
        expect(reopened.values, expected);
        expect(reopened.defaultTargetIds, {targetId});
        expect(reopened.targets.single.id, targetId);
        expect(reopened.targets.single.anonymous, false);
        expect(await original.readAsBytes(), sourceBytes);
        expect(rows('assets'), assetRows);
        expect(rows('versions'), versionRows);
        expect(rows('device_copies'), copyRows);

        await mount(const ProcessingWorkbench());
        final selected = find.byKey(Key('processing-asset-${asset.id}'));
        await until(
          () =>
              selected.evaluate().isNotEmpty &&
              find
                  .byKey(const Key('processing-longest-side'))
                  .evaluate()
                  .isNotEmpty,
          'New workbench applies persisted size-first defaults to its draft',
        );
        expect(fieldText('processing-longest-side'), '16');
        final format = find.byWidgetPredicate(
          (widget) => widget is DropdownButtonFormField<ProcessingFormat>,
        );
        await visible(format);
        await tester.tap(format);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(find.text('JPEG').last);
        await tester.pump(const Duration(milliseconds: 350));
        expect(fieldText('processing-quality'), '73');
        await visible(selected, upward: true);
        await tester.tap(selected);
        await tester.pump();
        final start = find.byKey(const Key('processing-start'));
        await visible(start);
        expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
        await tester.tap(start);
        await until(
          () =>
              find.text('已就绪').evaluate().isNotEmpty &&
              tester.widget<FilledButton>(start).onPressed != null,
          'Real isolate pixel processing and output commit finish before ready',
        );
        final output = (await repository.listOutputs()).single;
        expect(output.usable, true);
        expect(output.request.mode, ProcessingMode.sizeFirst);
        expect(output.request.quality, 73);
        expect(output.request.longestSide, 16);
        expect(output.request.outputFormat, ProcessingFormat.jpeg);
        expect(output.version!.width, 16);
        expect(output.version!.height, 12);
        final outputBytes = await output.file!.readAsBytes();
        final decoded = img.decodeJpg(outputBytes);
        expect(decoded, isNotNull);
        expect(decoded!.width, 16);
        expect(decoded.height, 12);
        final frozenOutputRows = rows('processed_outputs');
        final frozenRequest = output.request.toSnapshot();

        await mount(const SettingsScreen());
        await until(
          () =>
              find
                  .byKey(const Key('settings-upload-concurrency'))
                  .evaluate()
                  .isNotEmpty &&
              tester
                      .widget<TextField>(
                        find.byKey(const Key('settings-upload-concurrency')),
                      )
                      .enabled ==
                  true,
          'A new settings page reads the persisted defaults',
        );
        await edit('settings-quality', '91');
        await edit('settings-longest-side', '24');
        await saveFromPage();
        expect((await repository.loadSettings()).values.quality, 91);
        expect((await repository.loadSettings()).values.longestSide, 24);
        final preserved = await repository.getOutput(output.id);
        expect(preserved.request.toSnapshot(), frozenRequest);
        expect(rows('processed_outputs'), frozenOutputRows);
        expect(await preserved.file!.readAsBytes(), outputBytes);
        expect(await original.readAsBytes(), sourceBytes);
        expect(rows('assets'), assetRows);
        expect(rows('versions'), versionRows);
        expect(rows('device_copies'), copyRows);
        expect(rows('upload_publications'), isEmpty);
        expect(rows('remote_upload_results'), isEmpty);
        expect(rows('credential_operations'), isEmpty);
        expect(rows('provider_targets').single['secret_reference'], isNotNull);
        expect(tester.takeException(), isNull);
      } finally {
        try {
          await unmountAndClose();
        } finally {
          // Anonymous fixture never writes a system credential. Delete only
          // its verified private test directory, never any protected namespace.
          final target = p.normalize(p.absolute(sandbox.path));
          final temporary = p.normalize(p.absolute(Directory.systemTemp.path));
          if (!p.isWithin(temporary, target) ||
              !p.basename(target).startsWith('imagehost-settings-engine-')) {
            throw StateError(
              'Settings test cleanup is outside its temporary root',
            );
          }
          await Directory(target).delete(recursive: true);
        }
      }
    },
  );
}
