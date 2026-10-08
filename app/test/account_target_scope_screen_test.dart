import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/accounts/presentation/accounts_screen.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqlite3/sqlite3.dart';

import 'core/accounts_repository_test.dart' show TestSecrets;
import 'support/legacy_anonymous_fixture.dart';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 30));
    if (ready()) return;
  }
  fail('账号范围页面未到达预期状态。');
}

Future<void> _closeFixture(
  WidgetTester tester,
  LibrarySession session,
  ProviderContainer container,
  Directory sandbox,
) async {
  await tester.pumpWidget(const SizedBox());
  var closed = false;
  Object? closeFailure;
  await tester.runAsync(() async {
    unawaited(
      session.close().then<void>(
        (_) {
          closed = true;
        },
        onError: (Object error) {
          closeFailure = error;
          closed = true;
        },
      ),
    );
  });
  await _until(tester, () => closed);
  if (closeFailure != null) throw closeFailure!;
  container.dispose();
  await tester.runAsync(() => sandbox.delete(recursive: true));
}

void main() {
  for (final removing in [false, true]) {
    for (final failRead in [false, true]) {
      testWidgets(
        'UT-043 ${removing ? 'removing' : 'stopping'} account ${failRead ? 'read failure' : 'cancel confirmation'} preserves draft and enabled target without requests',
        (tester) async {
          tester.view.physicalSize = const Size(1280, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final sandbox = (await tester.runAsync(
            () =>
                Directory.systemTemp.createTemp('imagehost-account-impact-ui-'),
          ))!;
          final root = Directory('${sandbox.path}/library');
          final repository = (await tester.runAsync(
            () => LibraryRepository.open(root, secretStore: TestSecrets()),
          ))!;
          final target = (await tester.runAsync(() async {
            final target = await repository.saveTarget(
              service: ImageHostService.catbox,
              alias: '原账号',
              anonymous: false,
              credential: 'SyntheticImpactWidgetCredential',
            );
            final asset = (await repository.importResource(
              PlatformResource(
                displayName: 'fixture.png',
                openRead: () =>
                    Stream.value(img.encodePng(img.Image(width: 3, height: 2))),
              ),
            )).asset!;
            final batch = await repository.enqueueUploads(
              intentId: 'impact-ui',
              assetIds: [asset.id],
              targetIds: [target],
              allowOriginalMetadata: true,
            );
            if (failRead) {
              final db = sqlite3.open('${root.path}/library.sqlite');
              try {
                db.execute(
                  'UPDATE upload_publications SET state=? WHERE id=?',
                  ['future-state', batch.items.single.id],
                );
              } finally {
                db.close();
              }
            }
            return target;
          }))!;
          final session = (await tester.runAsync(
            () async => LibrarySession(repository, const []),
          ))!;
          final container = ProviderContainer(
            overrides: [
              librarySessionProvider.overrideWith((_) async => session),
            ],
          );
          addTearDown(() => _closeFixture(tester, session, container, sandbox));
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: const MaterialApp(home: AccountsScreen()),
            ),
          );
          await _until(tester, () => find.text('编辑').evaluate().isNotEmpty);
          if (removing) {
            await tester.tap(find.text('移除'));
          } else {
            await tester.tap(find.text('编辑'));
            await tester.pump(const Duration(milliseconds: 300));
            await tester.pump();
            expect(find.text('使用匿名目标'), findsNothing);
            await tester.enterText(find.byType(TextField).first, '尚未保存的草稿');
            await tester.ensureVisible(find.text('启用目标'));
            await tester.tap(find.text('启用目标'));
            await tester.pump();
            await tester.tap(find.text('保存'));
          }
          final title = removing ? '移除账号目标？' : '停用账号目标？';
          if (failRead) {
            await _until(
              tester,
              () => find
                  .textContaining(removing ? '受影响任务读取失败' : '任务状态无法安全读取')
                  .evaluate()
                  .isNotEmpty,
            );
            expect(find.text(title), findsNothing);
          } else {
            await _until(tester, () => find.text(title).evaluate().isNotEmpty);
            expect(
              find.textContaining('待执行 1 项 · 正在运行 0 项 · 结果未知 0 项'),
              findsOneWidget,
            );
            expect(find.textContaining(target.substring(0, 8)), findsWidgets);
            expect(find.textContaining('晚到确认'), findsOneWidget);
            await tester.tap(find.text('取消').last);
            await _until(
              tester,
              () => removing
                  ? find.text(title).evaluate().isEmpty
                  : find.text('已取消停用，编辑草稿保留。').evaluate().isNotEmpty,
            );
          }
          if (!removing) {
            expect(
              tester
                  .widget<TextField>(find.byType(TextField).first)
                  .controller!
                  .text,
              '尚未保存的草稿',
            );
          }
          final saved = (await tester.runAsync(repository.listTargets))!.single;
          expect(saved.enabled, isTrue);
          expect(saved.alias, '原账号');
          expect(session.existingUploads, isNull);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }
  }

  testWidgets(
    'UT-040 legacy anonymous target has local removal only and new account dialog has no anonymous option',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sandbox = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('imagehost-legacy-target-ui-'),
      ))!;
      final root = Directory('${sandbox.path}/library');
      final repository = (await tester.runAsync(
        () => LibraryRepository.open(root, secretStore: TestSecrets()),
      ))!;
      await tester.runAsync(() async {
        final target = await repository.saveTarget(
          service: ImageHostService.catbox,
          alias: '遗留身份',
          anonymous: false,
          credential: 'SyntheticLegacyWidgetCredential',
          selectedByDefault: true,
        );
        markLegacyAnonymous(root, target);
      });
      final session = (await tester.runAsync(
        () async => LibrarySession(repository, const []),
      ))!;
      final container = ProviderContainer(
        overrides: [librarySessionProvider.overrideWith((_) async => session)],
      );
      addTearDown(() => _closeFixture(tester, session, container, sandbox));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AccountsScreen()),
        ),
      );
      await _until(tester, () => find.text('匿名历史 · 已停用').evaluate().isNotEmpty);
      final edit = find.widgetWithText(TextButton, '编辑');
      expect(tester.widget<TextButton>(edit).onPressed, isNull);
      expect(find.text('默认目标'), findsNothing);
      await tester.ensureVisible(find.text('添加目标').first);
      await tester.tap(find.text('添加目标').first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('使用匿名目标'), findsNothing);
      expect(find.text('凭据'), findsOneWidget);
      await tester.tap(find.text('取消').last);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
