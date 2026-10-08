import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/core/secret_store.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/accounts/presentation/accounts_screen.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:material_ui/material_ui.dart';

import 'core/accounts_repository_test.dart' show TestSecrets;

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
  for (var i = 0; i < 200 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done, isTrue);
  if (failure != null) throw failure!;
  return value as T;
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (ready()) return;
  }
  fail('真实账号 IO 与 widget 状态未完成');
}

void _size(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'UT-041 account result event refreshes health while preserving open edit draft',
    (tester) async {
      _size(tester, 1280);
      final sandbox = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('imagehost-health-widget-'),
      ))!;
      final repository = (await tester.runAsync(
        () => LibraryRepository.open(
          Directory('${sandbox.path}/library'),
          secretStore: TestSecrets(),
        ),
      ))!;
      final bytes = img.encodePng(img.Image(width: 6, height: 4));
      final asset = (await _native(
        tester,
        () => repository.importResource(
          PlatformResource(
            displayName: 'original.png',
            openRead: () => Stream.value(bytes),
          ),
        ),
      )).asset!;
      final target = await _native(
        tester,
        () => repository.saveTarget(
          service: ImageHostService.catbox,
          alias: '当前账号',
          anonymous: false,
          credential: 'synthetic-health-widget-key',
        ),
      );
      final batch = await _native(
        tester,
        () => repository.enqueueUploads(
          intentId: 'health-widget',
          assetIds: [asset.id],
          targetIds: [target],
          allowOriginalMetadata: true,
        ),
      );
      final execution = (await _native(
        tester,
        () => repository.beginUploadAttempt(batch.items.single.id),
      ))!;
      final container = ProviderContainer(
        overrides: [
          librarySessionProvider.overrideWith(
            (_) async => LibrarySession(repository, const []),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await _native(tester, execution.release);
        await _native(tester, repository.close);
        await tester.runAsync(() => sandbox.delete(recursive: true));
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AccountsScreen()),
        ),
      );
      await _until(tester, () => find.text('未验证').evaluate().isNotEmpty);
      await tester.ensureVisible(find.text('编辑'));
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await _until(tester, () => find.byType(TextField).evaluate().isNotEmpty);
      await tester.enterText(find.byType(TextField).first, '尚未保存的名称');
      await _native(tester, () async {
        await repository.finishUploadAttempt(
          execution,
          ProviderUploadSuccess(
            service: ImageHostService.catbox,
            remoteId: 'health.png',
            directUrl: Uri.parse('https://files.catbox.moe/health.png'),
          ),
          accumulatedRunning: const Duration(milliseconds: 1),
        );
        await execution.release();
      });
      await _until(tester, () => find.text('可用').evaluate().isNotEmpty);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '尚未保存的名称',
      );
      expect(
        (await _native(tester, repository.listTargets)).single.alias,
        '当前账号',
      );
      expect(find.textContaining('synthetic-health-widget-key'), findsNothing);
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      expect(find.text('可用'), findsOneWidget);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
  for (final width in [320.0, 1280.0]) {
    testWidgets(
      'AT-003 partial account $width empty loading failure and actual form save',
      (tester) async {
        _size(tester, width);
        final sandbox = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('imagehost-accounts-widget-'),
        ))!;
        final secrets = TestSecrets();
        final repository = (await tester.runAsync(
          () => LibraryRepository.open(
            Directory('${sandbox.path}/library'),
            secretStore: secrets,
          ),
        ))!;
        var container = ProviderContainer(
          overrides: [
            librarySessionProvider.overrideWith(
              (_) async => LibrarySession(repository, const []),
            ),
          ],
        );
        addTearDown(() async {
          container.dispose();
          await _native(tester, repository.close);
          await tester.runAsync(() => sandbox.delete(recursive: true));
        });
        Future<void> mount() => tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: AccountsScreen()),
          ),
        );
        await mount();
        await _until(tester, () => find.text('还没有账号目标').evaluate().isNotEmpty);
        await tester.ensureVisible(find.text('添加目标').first);
        await tester.tap(find.text('添加目标').first);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, '个人图片');
        await tester.enterText(
          find.byType(TextField).last,
          'synthetic-widget-key',
        );
        expect(
          tester.widget<TextField>(find.byType(TextField).last).obscureText,
          isTrue,
        );
        await tester.ensureVisible(find.text('系统安全存储'));
        await tester.tap(find.text('系统安全存储'));
        await tester.pump();
        await tester.tap(find.text('保存'));
        await _until(tester, () => find.text('未验证').evaluate().isNotEmpty);
        expect(
          (await _native(tester, repository.listTargets)).single.alias,
          '个人图片',
        );
        expect(secrets.values.values, ['synthetic-widget-key']);
        expect(find.textContaining('synthetic-widget-key'), findsNothing);
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        final pending = Completer<LibrarySession>();
        container = ProviderContainer(
          overrides: [
            librarySessionProvider.overrideWith((_) => pending.future),
          ],
        );
        await mount();
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        pending.completeError(StateError('合成加载失败'));
        await _until(
          tester,
          () => find.text('账号列表暂时无法读取，已有资料不会被覆盖。').evaluate().isNotEmpty,
        );
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
  testWidgets(
    'UT-095 account secure write failure keeps explicit input and never displays healthy success',
    (tester) async {
      _size(tester, 390);
      final sandbox = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('imagehost-account-failure-'),
      ))!;
      final secrets = TestSecrets()..unavailable = true;
      final repository = (await tester.runAsync(
        () => LibraryRepository.open(
          Directory('${sandbox.path}/library'),
          secretStore: secrets,
        ),
      ))!;
      final container = ProviderContainer(
        overrides: [
          librarySessionProvider.overrideWith(
            (_) async => LibrarySession(repository, const []),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await _native(tester, repository.close);
        await tester.runAsync(() => sandbox.delete(recursive: true));
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AccountsScreen()),
        ),
      );
      await _until(tester, () => find.text('还没有账号目标').evaluate().isNotEmpty);
      await tester.ensureVisible(find.text('添加目标').first);
      await tester.tap(find.text('添加目标').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '会话测试');
      await tester.enterText(
        find.byType(TextField).last,
        'synthetic-not-persisted',
      );
      await tester.ensureVisible(find.text('系统安全存储'));
      await tester.tap(find.text('系统安全存储'));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await _until(
        tester,
        () => find.text(SecretStorageException.message).evaluate().isNotEmpty,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        'synthetic-not-persisted',
      );
      expect(find.text('可用'), findsNothing);
      await tester.ensureVisible(find.text('仅本次会话'));
      await tester.tap(find.text('仅本次会话'));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await _until(tester, () => find.text('未验证').evaluate().isNotEmpty);
      expect(find.text('仅本次会话'), findsOneWidget);
      expect(secrets.values, isEmpty);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
