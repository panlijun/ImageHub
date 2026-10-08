import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/network_state.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/processing/domain/output_models.dart';
import 'package:imagehost/features/settings/domain/device_settings.dart';
import 'package:imagehost/features/settings/presentation/settings_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqlite3/sqlite3.dart';

import 'core/upload_repository_test.dart' show QueueTestSecrets;

// Alternate real SQLite/file IO with widget fake time; do not conceal a stuck
// future with pumpAndSettle or report this as device/force-exit validation.
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
  for (var i = 0; i < 500 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 40));
  }
  expect(done, isTrue, reason: '真实 IO 必须收尾');
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
  final offset = _pageScroll.evaluate().isEmpty
      ? null
      : tester.state<ScrollableState>(_pageScroll).position.pixels;
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data ?? '')
      .where((text) => text.isNotEmpty)
      .join(' | ');
  fail('设置页或真实 IO 未完成；页面滚动位置=$offset；已构建文本=$texts');
}

Finder _key(String name) => find.byKey(ValueKey(name));

Finder get _pageScroll => find
    .descendant(of: _key('settings-list'), matching: find.byType(Scrollable))
    .first;

Future<void> _top(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  // Drain the existing EditableText caret animation before navigating.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  final navigation = <String>[];
  for (var attempt = 0; attempt < 6; attempt++) {
    final before = tester.state<ScrollableState>(_pageScroll).position;
    final oldOffset = before.pixels;
    before.jumpTo(0);
    await tester.pump();
    final after = tester.state<ScrollableState>(_pageScroll).position;
    navigation.add(
      '$attempt: before=$oldOffset after=${after.pixels} '
      'min=${after.minScrollExtent} max=${after.maxScrollExtent} '
      'samePosition=${identical(before, after)} '
      'focused=${FocusManager.instance.primaryFocus?.hasFocus ?? false}',
    );
    // RenderSliverList may correct the offset when a previously unbuilt error
    // slot grows from zero. A timed pump cannot lay out offscreen leading
    // children; finish that correction before making the next navigation.
    if (after.pixels == 0) break;
  }
  expect(
    tester.state<ScrollableState>(_pageScroll).position.pixels,
    0,
    reason: '反馈检查必须在设置页实际顶部；${navigation.join(' | ')}',
  );
}

Future<void> _reveal(
  WidgetTester tester,
  Finder finder, {
  bool top = false,
}) async {
  if (top) await _top(tester);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      top ? -300 : 300,
      // TextField owns a nested Scrollable. Only scroll the page's outer one.
      scrollable: _pageScroll,
      maxScrolls: 60,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String name) async {
  final finder = _key(name);
  final top = !name.startsWith('settings-target-');
  await _reveal(tester, finder, top: top);
  await tester.tap(finder);
  await tester.pump();
  if (top) await _top(tester);
}

Future<void> _enter(WidgetTester tester, String name, String value) async {
  final finder = _key(name);
  // Restore to the top first so the scan direction is deterministic.
  await _reveal(tester, _key('settings-save'), top: true);
  await _reveal(tester, finder);
  await tester.enterText(finder, value);
  await tester.pump();
}

String _text(WidgetTester tester, String name) =>
    tester.widget<TextField>(_key(name)).controller!.text;

final class _Fixture {
  _Fixture(this.directory, this.repository);
  final Directory directory;
  final LibraryRepository repository;
  late final session = LibrarySession(repository, const []);
  late final container = ProviderContainer(
    overrides: [librarySessionProvider.overrideWith((_) async => session)],
  );
  Future<void>? _closing;
  static Future<_Fixture> open({ImportFaultHook? faultHook}) async {
    final directory = await Directory.systemTemp.createTemp(
      'imagehost-settings-ui-',
    );
    final repository = await LibraryRepository.open(
      Directory('${directory.path}/library'),
      secretStore: QueueTestSecrets(),
      faultHook: faultHook,
    );
    return _Fixture(directory, repository);
  }

  Future<void> close() => _closing ??= () async {
    container.dispose();
    await session.close();
    await directory.delete(recursive: true);
  }();

  Future<void> sql(String statement) async {
    final database = sqlite3.open('${directory.path}/library/library.sqlite');
    try {
      database.execute(statement);
    } finally {
      database.close();
    }
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture, {
  double width = 390,
  double textScale = 1,
  ValueChanged<bool>? onBusyChanged,
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
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: SettingsScreen(onBusyChanged: onBusyChanged),
      ),
    ),
  );
  await _until(
    tester,
    () => tester.widget<FilledButton>(_key('settings-save')).onPressed != null,
  );
}

Future<_Fixture> _fixture(
  WidgetTester tester, {
  ImportFaultHook? faultHook,
}) async {
  final fixture = await _native(
    tester,
    () => _Fixture.open(faultHook: faultHook),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await _native(tester, fixture.close);
  });
  return fixture;
}

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'UT-099 retention guidance and real backup route preserve draft $width',
      (tester) async {
        final fixture = await _fixture(tester);
        await _mount(tester, fixture, width: width);
        await _enter(tester, 'settings-upload-concurrency', '5');
        await _reveal(tester, _key('settings-backup'));
        expect(find.textContaining('30 天或 10,000,000 字节'), findsOneWidget);
        expect(find.textContaining('卸载行为不保证系统删除凭据'), findsOneWidget);
        await tester.tap(_key('settings-backup'));
        await _until(tester, () => find.text('备份与恢复').evaluate().isNotEmpty);
        expect(
          (await _native(
            tester,
            fixture.repository.loadSettings,
          )).values.uploadConcurrency,
          3,
        );
        await tester.pageBack();
        await tester.pump(const Duration(milliseconds: 350));
        await _top(tester);
        expect(_text(tester, 'settings-upload-concurrency'), '5');
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'UT-063/087 AT-005 partial network policy $width double text saves only after confirmation and restores default draft',
      (tester) async {
        final fixture = await _fixture(tester);
        await _mount(tester, fixture, width: width, textScale: 2);
        final policy = find.byType(
          DropdownButtonFormField<NetworkUploadPolicy>,
        );
        await _reveal(tester, policy);
        expect(find.text('仅 Wi-Fi / 有线网络'), findsOneWidget);
        expect(find.textContaining('仅控制已确认上传任务'), findsOneWidget);
        await tester.tap(policy);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final allNetworks = find.text('所有已识别网络（含移动网络）').hitTestable();
        expect(allNetworks, findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(allNetworks);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final selectedPolicy = find.descendant(
          of: policy,
          matching: find.text('所有已识别网络（含移动网络）'),
        );
        await _until(
          tester,
          () =>
              selectedPolicy.evaluate().length == 1 &&
              find.text('所有已识别网络（含移动网络）').evaluate().length == 1,
        );
        expect(selectedPolicy, findsOneWidget);
        expect(find.text('所有已识别网络（含移动网络）'), findsOneWidget);
        expect(
          (await _native(tester, fixture.repository.loadSettings)).values,
          DeviceSettings.defaults,
        );
        await _tap(tester, 'settings-save');
        await _until(tester, () => find.text('已保存。').evaluate().isNotEmpty);
        expect(
          (await _native(
            tester,
            fixture.repository.loadSettings,
          )).values.networkUploadPolicy,
          NetworkUploadPolicy.anyKnownNetwork,
        );
        expect(fixture.session.existingUploads, isNull);
        await _tap(tester, 'settings-defaults');
        expect(
          (await _native(
            tester,
            fixture.repository.loadSettings,
          )).values.networkUploadPolicy,
          NetworkUploadPolicy.anyKnownNetwork,
        );
        await _reveal(tester, policy);
        expect(find.text('仅 Wi-Fi / 有线网络'), findsOneWidget);
        await _tap(tester, 'settings-save');
        await _until(tester, () => find.text('已保存。').evaluate().isNotEmpty);
        expect(
          (await _native(tester, fixture.repository.loadSettings)).values,
          DeviceSettings.defaults,
        );
        expect(fixture.session.existingUploads, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'UT-086 shared settings entry opens real storage without authorizing uploads',
    (tester) async {
      final fixture = await _fixture(tester);
      await _mount(tester, fixture);
      // This action is below the defaults and navigates away. Scroll down to
      // the actual button; the save helper restores the settings route's top.
      await _reveal(tester, _key('settings-storage'));
      await tester.tap(_key('settings-storage'));
      await tester.pump();
      await _until(
        tester,
        () => find.byKey(const Key('storage-total')).evaluate().isNotEmpty,
      );
      expect(find.text('空间管理'), findsOneWidget);
      expect(fixture.session.existingUploads, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'UT-083 UT-088 AT-005 partial settings $width large type actual save and reopen',
      (tester) async {
        final fixture = await _fixture(tester);
        await _mount(tester, fixture, width: width, textScale: 1.8);
        await _enter(tester, 'settings-upload-concurrency', '8');
        await _enter(tester, 'settings-processing-concurrency', '4');
        await _enter(tester, 'settings-quality', '100');
        await _enter(tester, 'settings-longest-side', '16384');
        final mode = find.byType(DropdownButtonFormField<ProcessingMode>);
        await _reveal(tester, mode);
        tester.widget<DropdownButtonFormField<ProcessingMode>>(mode).onChanged!(
          ProcessingMode.sizeFirst,
        );
        await tester.pump();
        await _enter(tester, 'settings-cache-limit', '2048');
        final retention = find.byType(DropdownButtonFormField<OutputRetention>);
        await _reveal(tester, retention);
        tester
            .widget<DropdownButtonFormField<OutputRetention>>(retention)
            .onChanged!(OutputRetention.week);
        await tester.pump();
        await _tap(tester, 'settings-save');
        await _until(tester, () => find.text('已保存。').evaluate().isNotEmpty);
        final expected = DeviceSettings(
          uploadConcurrency: 8,
          processingConcurrency: 4,
          quality: 100,
          longestSide: 16384,
          processingMode: ProcessingMode.sizeFirst,
          cacheLimitMiB: 2048,
          defaultOutputRetention: OutputRetention.week,
        );
        expect(
          (await _native(tester, fixture.repository.loadSettings)).values,
          expected,
        );
        expect(fixture.session.existingUploads, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        fixture.container.dispose();
        await _native(tester, fixture.repository.close);
        final reopened = await _native(
          tester,
          () => LibraryRepository.open(
            Directory('${fixture.directory.path}/library'),
            secretStore: QueueTestSecrets(),
          ),
        );
        expect((await _native(tester, reopened.loadSettings)).values, expected);
        await _native(tester, reopened.close);
      },
    );
  }

  testWidgets(
    'UT-083 invalid numeric drafts never clamp or persist all bounds',
    (tester) async {
      final fixture = await _fixture(tester);
      final busy = <bool>[];
      await _mount(tester, fixture, onBusyChanged: busy.add);
      final fields = {
        'settings-upload-concurrency': ('3', '9'),
        'settings-processing-concurrency': ('1', '5'),
        'settings-quality': ('85', '101'),
        'settings-longest-side': ('1600', '16385'),
        'settings-cache-limit': ('256', '2049'),
      };
      for (final entry in fields.entries) {
        for (final invalid in [
          '',
          '0',
          '-1',
          '1.5',
          'NaN',
          'Infinity',
          entry.value.$2,
        ]) {
          await _enter(tester, entry.key, invalid);
          await _tap(tester, 'settings-save');
          expect(find.textContaining('必须是'), findsOneWidget);
          expect(
            (await _native(tester, fixture.repository.loadSettings)).values,
            DeviceSettings.defaults,
          );
          await _reveal(tester, _key(entry.key));
          expect(_text(tester, entry.key), invalid);
        }
        await _enter(tester, entry.key, entry.value.$1);
      }
      expect(busy, isEmpty);
      for (final entry in fields.entries) {
        await _enter(
          tester,
          entry.key,
          entry.key == 'settings-cache-limit' ? '64' : '1',
        );
      }
      await _tap(tester, 'settings-save');
      await _until(tester, () => find.text('已保存。').evaluate().isNotEmpty);
      expect(
        (await _native(tester, fixture.repository.loadSettings)).values,
        DeviceSettings(
          uploadConcurrency: 1,
          processingConcurrency: 1,
          quality: 1,
          longestSide: 1,
          cacheLimitMiB: 64,
        ),
      );
    },
  );

  testWidgets(
    'UT-083 UT-087 failed SQL commit preserves complete draft and old values retry',
    (tester) async {
      final fixture = await _fixture(tester);
      await _mount(tester, fixture);
      await _native(
        tester,
        () => fixture.sql(
          "CREATE TRIGGER settings_fail BEFORE INSERT ON library_metadata WHEN NEW.key = 'device_settings_v1' BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
        ),
      );
      await _enter(tester, 'settings-upload-concurrency', '6');
      await _enter(tester, 'settings-processing-concurrency', '2');
      await _enter(tester, 'settings-quality', '71');
      await _enter(tester, 'settings-longest-side', '900');
      await _enter(tester, 'settings-cache-limit', '128');
      await _tap(tester, 'settings-save');
      await _until(
        tester,
        () => find.textContaining('设置保存未确认').evaluate().isNotEmpty,
      );
      expect(
        (await _native(tester, fixture.repository.loadSettings)).values,
        DeviceSettings.defaults,
      );
      for (final entry in {
        'settings-upload-concurrency': '6',
        'settings-processing-concurrency': '2',
        'settings-quality': '71',
        'settings-longest-side': '900',
        'settings-cache-limit': '128',
      }.entries) {
        await _reveal(tester, _key(entry.key));
        expect(_text(tester, entry.key), entry.value);
      }
      await _native(tester, () => fixture.sql('DROP TRIGGER settings_fail'));
      await _tap(tester, 'settings-save');
      await _until(tester, () => find.text('已保存。').evaluate().isNotEmpty);
      expect(
        (await _native(tester, fixture.repository.loadSettings)).values,
        DeviceSettings(
          uploadConcurrency: 6,
          processingConcurrency: 2,
          quality: 71,
          longestSide: 900,
          cacheLimitMiB: 128,
        ),
      );
    },
  );

  testWidgets(
    'UT-083 default reset is only draft and target UUIDs distinguish aliases',
    (tester) async {
      final fixture = await _fixture(tester);
      final targets = await _native(tester, () async {
        final first = await fixture.repository.saveTarget(
          service: ImageHostService.catbox,
          alias: '同名',
          anonymous: false,
          credential: 'SyntheticAccountFixture0123456789',
          selectedByDefault: true,
          enabled: false,
        );
        final second = await fixture.repository.saveTarget(
          service: ImageHostService.catbox,
          alias: '同名',
          anonymous: false,
          credential: 'SyntheticAccountFixture0123456789',
        );
        final disabled = await fixture.repository.saveTarget(
          service: ImageHostService.catbox,
          alias: '同名',
          anonymous: false,
          credential: 'SyntheticAccountFixture0123456789',
          enabled: false,
        );
        final initial = await fixture.repository.loadSettings();
        await fixture.repository.saveSettings(
          initial,
          DeviceSettings(
            uploadConcurrency: 7,
            cacheLimitMiB: 128,
            defaultOutputRetention: OutputRetention.week,
            networkUploadPolicy: NetworkUploadPolicy.anyKnownNetwork,
          ),
          defaultTargetIds: initial.defaultTargetIds,
        );
        return (first, second, disabled);
      });
      await _mount(tester, fixture);
      await _reveal(tester, _key('settings-target-${targets.$1}'));
      expect(
        tester
            .widget<CheckboxListTile>(_key('settings-target-${targets.$1}'))
            .value,
        isTrue,
      );
      expect(
        tester
            .widget<CheckboxListTile>(_key('settings-target-${targets.$1}'))
            .onChanged,
        isNotNull,
      );
      expect(
        tester
            .widget<CheckboxListTile>(_key('settings-target-${targets.$3}'))
            .onChanged,
        isNull,
      );
      await _tap(tester, 'settings-target-${targets.$2}');
      await _tap(tester, 'settings-save');
      await _until(tester, () => find.text('已保存。').evaluate().isNotEmpty);
      expect(
        (await _native(
          tester,
          fixture.repository.loadSettings,
        )).defaultTargetIds,
        {targets.$1, targets.$2},
      );
      await _tap(tester, 'settings-defaults');
      expect(find.textContaining('默认值已填入草稿'), findsOneWidget);
      final persisted = await _native(tester, fixture.repository.loadSettings);
      expect(persisted.values.uploadConcurrency, 7);
      expect(persisted.values.cacheLimitMiB, 128);
      expect(persisted.values.defaultOutputRetention, OutputRetention.week);
      expect(
        persisted.values.networkUploadPolicy,
        NetworkUploadPolicy.anyKnownNetwork,
      );
      expect(persisted.defaultTargetIds, {targets.$1, targets.$2});
      await _tap(tester, 'settings-save');
      await _until(tester, () => find.text('已保存。').evaluate().isNotEmpty);
      final reset = await _native(tester, fixture.repository.loadSettings);
      expect(reset.values, DeviceSettings.defaults);
      expect(reset.defaultTargetIds, isEmpty);
      await _reveal(tester, _key('settings-target-${targets.$1}'));
      expect(
        tester
            .widget<CheckboxListTile>(_key('settings-target-${targets.$1}'))
            .onChanged,
        isNull,
      );
    },
  );

  testWidgets(
    'UT-083 pending credential default is fixed while numeric settings save',
    (tester) async {
      final fixture = await _fixture(tester);
      final target = await _native(
        tester,
        () => fixture.repository.saveTarget(
          service: ImageHostService.catbox,
          alias: '等待安全操作',
          anonymous: false,
          credential: 'SyntheticAccountFixture0123456789',
          selectedByDefault: true,
        ),
      );
      await _native(
        tester,
        () => fixture.sql(
          "INSERT INTO credential_operations(id,target_id,action,proposal_json,created_utc) "
          "VALUES('00000000-0000-4000-8000-000000000083','$target','update','{}',1)",
        ),
      );
      await _mount(tester, fixture);
      await _reveal(tester, _key('settings-target-$target'));
      expect(
        tester
            .widget<CheckboxListTile>(_key('settings-target-$target'))
            .onChanged,
        isNull,
      );
      expect(find.text('凭据操作尚未完成，暂不可编辑'), findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(_key('settings-target-$target')).value,
        isTrue,
      );
      await _reveal(tester, _key('settings-defaults'), top: true);
      expect(
        tester.widget<TextButton>(_key('settings-defaults')).onPressed,
        isNull,
      );
      expect(find.text('默认目标凭据操作尚未完成，暂不能整体恢复默认；数值仍可编辑并保存。'), findsOneWidget);
      await _enter(tester, 'settings-quality', '71');
      await _tap(tester, 'settings-save');
      await _until(tester, () => find.text('已保存。').evaluate().isNotEmpty);
      final persisted = await _native(tester, fixture.repository.loadSettings);
      expect(persisted.defaultTargetIds, {target});
      expect(persisted.values.quality, 71);
    },
  );

  testWidgets(
    'UT-083 unselected pending target cannot become default or block reset',
    (tester) async {
      final fixture = await _fixture(tester);
      final target = await _native(
        tester,
        () => fixture.repository.saveTarget(
          service: ImageHostService.catbox,
          alias: '未选等待目标',
          anonymous: false,
          credential: 'SyntheticAccountFixture0123456789',
        ),
      );
      await _native(
        tester,
        () => fixture.sql(
          "INSERT INTO credential_operations(id,target_id,action,proposal_json,created_utc) "
          "VALUES('00000000-0000-4000-8000-000000000084','$target','update','{}',1)",
        ),
      );
      await _mount(tester, fixture);
      await _reveal(tester, _key('settings-target-$target'));
      final checkbox = tester.widget<CheckboxListTile>(
        _key('settings-target-$target'),
      );
      expect(checkbox.value, isFalse);
      expect(checkbox.onChanged, isNull);
      await _reveal(tester, _key('settings-defaults'), top: true);
      expect(
        tester.widget<TextButton>(_key('settings-defaults')).onPressed,
        isNotNull,
      );
      await _tap(tester, 'settings-defaults');
      await _tap(tester, 'settings-save');
      await _until(tester, () => find.text('已保存。').evaluate().isNotEmpty);
      expect(
        (await _native(
          tester,
          fixture.repository.loadSettings,
        )).defaultTargetIds,
        isEmpty,
      );
    },
  );

  testWidgets(
    'UT-087 loading failure disables saving without revealing unknown exception',
    (tester) async {
      final pending = Completer<LibrarySession>();
      final container = ProviderContainer(
        overrides: [librarySessionProvider.overrideWith((_) => pending.future)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<FilledButton>(_key('settings-save')).onPressed,
        isNull,
      );
      pending.completeError(StateError('secret-must-never-appear'));
      await _until(
        tester,
        () => find.textContaining('设置读取失败').evaluate().isNotEmpty,
      );
      expect(
        tester.widget<FilledButton>(_key('settings-save')).onPressed,
        isNull,
      );
      expect(find.textContaining('secret-must-never-appear'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'UT-087 reload failure keeps last view and draft until explicit reread',
    (tester) async {
      final fixture = await _fixture(tester);
      await _mount(tester, fixture);
      await _enter(tester, 'settings-upload-concurrency', '5');
      await _native(
        tester,
        () => fixture.sql(
          "INSERT INTO library_metadata(key,value) VALUES('device_settings_v1','invalid-json')",
        ),
      );
      await _tap(tester, 'settings-reload');
      await _until(
        tester,
        () => find.textContaining('设置读取失败').evaluate().isNotEmpty,
      );
      expect(_text(tester, 'settings-upload-concurrency'), '5');
      expect(
        tester.widget<FilledButton>(_key('settings-save')).onPressed,
        isNull,
      );
      await _native(
        tester,
        () => fixture.sql(
          "DELETE FROM library_metadata WHERE key='device_settings_v1'",
        ),
      );
      await _tap(tester, 'settings-reload');
      await _until(
        tester,
        () =>
            tester.widget<FilledButton>(_key('settings-save')).onPressed !=
            null,
      );
      expect(_text(tester, 'settings-upload-concurrency'), '3');
    },
  );

  testWidgets(
    'UT-087 external settings revision and replacement reset reject old draft',
    (tester) async {
      final fixture = await _fixture(tester);
      await _mount(tester, fixture);
      await _enter(tester, 'settings-upload-concurrency', '5');
      await _native(tester, () async {
        final snapshot = await fixture.repository.loadSettings();
        await fixture.repository.saveSettings(
          snapshot,
          DeviceSettings(uploadConcurrency: 6),
          defaultTargetIds: [],
        );
      });
      await _top(tester);
      await _until(
        tester,
        () => find.textContaining('草稿保留。请重新读取').evaluate().isNotEmpty,
      );
      expect(_text(tester, 'settings-upload-concurrency'), '5');
      expect(
        tester.widget<FilledButton>(_key('settings-save')).onPressed,
        isNull,
      );
      fixture.container
          .read(libraryReplacementRevisionProvider.notifier)
          .committed();
      await _until(
        tester,
        () =>
            tester.widget<FilledButton>(_key('settings-save')).onPressed !=
            null,
      );
      expect(_text(tester, 'settings-upload-concurrency'), '6');
      expect(find.textContaining('草稿保留。请重新读取'), findsNothing);
    },
  );

  for (final systemExit in [false, true]) {
    testWidgets(
      'UT-087 ${systemExit ? 'system exit' : 'dispose'} waits for real queued settings commit',
      (tester) async {
        final entered = Completer<void>(), release = Completer<void>();
        final fixture = await _fixture(
          tester,
          faultHook: (boundary) async {
            if (boundary == ImportBoundary.copy) {
              entered.complete();
              await release.future;
            }
          },
        );
        final busy = <bool>[];
        await _mount(tester, fixture, onBusyChanged: busy.add);
        await _enter(tester, 'settings-upload-concurrency', '5');
        final bytes = img.encodePng(img.Image(width: 5, height: 5));
        Future<ImportResult>? import;
        Future<AppExitResponse>? exit;
        try {
          await tester.runAsync(() async {
            import = fixture.repository.importResource(
              PlatformResource(
                displayName: 'hold.png',
                openRead: () => Stream.value(bytes),
              ),
            );
          });
          await _until(tester, () => entered.isCompleted);
          await _tap(tester, 'settings-save');
          expect(busy, [true]);
          expect(find.text('已保存。'), findsNothing);
          expect(
            tester.widget<PopScope>(find.byType(PopScope).last).canPop,
            isFalse,
          );
          var exited = false;
          if (systemExit) {
            await tester.runAsync(() async {
              exit = tester.binding.handleRequestAppExit();
              unawaited(exit!.then((_) => exited = true));
            });
            await tester.pump();
            expect(exited, isFalse);
          } else {
            await tester.pumpWidget(const SizedBox());
          }
          release.complete();
          await _native(tester, () => import!);
          if (systemExit) {
            expect(await _native(tester, () => exit!), AppExitResponse.exit);
            expect(busy, [true, false]);
            await tester.pumpWidget(const SizedBox());
          } else {
            // The disposed UI does not touch its controllers or cancel storage.
            expect(
              (await _native(
                tester,
                fixture.repository.loadSettings,
              )).values.uploadConcurrency,
              5,
            );
            await _native(tester, fixture.repository.close);
          }
        } finally {
          // An assertion or finder failure must not strand the native writer
          // behind this fixture gate and poison the following tests.
          if (!release.isCompleted) release.complete();
          if (import != null) await _native(tester, () => import!);
          if (exit != null) await _native(tester, () => exit!);
        }
        final reopened = await _native(
          tester,
          () => LibraryRepository.open(
            Directory('${fixture.directory.path}/library'),
            secretStore: QueueTestSecrets(),
          ),
        );
        expect(
          (await _native(
            tester,
            reopened.loadSettings,
          )).values.uploadConcurrency,
          5,
        );
        await _native(tester, reopened.close);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
