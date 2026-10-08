import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:imagehost/app.dart';
import 'package:imagehost/platform/system_secret_store.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/accounts/presentation/accounts_screen.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'IT-007 partial Windows real protected credentials and account identity survive reopen then delete',
    (tester) async {
      final sandbox = await Directory.systemTemp.createTemp(
        'imagehost-credentials-engine-',
      );
      final root = Directory('${sandbox.path}/library');
      var repository = await LibraryRepository.open(
        root,
        secretStore: SystemSecretStore(),
      );
      final created = <String>[];
      var container = ProviderContainer(
        overrides: [
          librarySessionProvider.overrideWith(
            (_) async => LibrarySession(repository, const []),
          ),
        ],
      );
      final key = GlobalKey();
      try {
        // Synthetic, non-user credentials. No upload client exists in this flow.
        final first = await repository.saveTarget(
          service: ImageHostService.catbox,
          alias: '个人图片',
          anonymous: false,
          credential: 'synthetic-windows-engine-A',
        );
        created.add(first);
        final second = await repository.saveTarget(
          service: ImageHostService.catbox,
          alias: '个人图片',
          anonymous: false,
          credential: 'SyntheticAccountFixture0123456789',
          selectedByDefault: true,
        );
        created.add(second);
        await repository.close();
        repository = await LibraryRepository.open(
          root,
          secretStore: SystemSecretStore(),
        );
        expect(
          (await repository.resolveTarget(first)).credential,
          'synthetic-windows-engine-A',
        );
        expect(
          (await repository.resolveTarget(second)).credential,
          'SyntheticAccountFixture0123456789',
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(key: key, child: const ImageHostApp()),
          ),
        );
        final accountEntry = find.ancestor(
          of: find.text('图床账号'),
          matching: find.byType(ListTile),
        );
        for (var i = 0; i < 200; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (accountEntry.evaluate().isNotEmpty &&
              tester.widget<ListTile>(accountEntry).onTap != null) {
            break;
          }
        }
        expect(accountEntry, findsOneWidget);
        expect(tester.widget<ListTile>(accountEntry).onTap, isNotNull);
        await tester.tap(accountEntry);
        for (
          var i = 0;
          i < 200 && find.text('个人图片').evaluate().length < 2;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(AccountsScreen), findsOneWidget);
        expect(find.text('个人图片'), findsNWidgets(2));
        expect(find.text('未验证'), findsNWidgets(2));
        expect(find.textContaining('synthetic-windows-engine-A'), findsNothing);
        expect(tester.takeException(), isNull);
        final render =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = File(
            '${Directory.current.path}/build/validation/windows-accounts.png',
          );
          await output.parent.create(recursive: true);
          await output.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
        } finally {
          image.dispose();
        }
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await repository.removeTarget(first);
        await expectLater(
          repository.resolveTarget(first),
          throwsA(isA<AccountFailure>()),
        );
        expect(
          (await repository.listTargets(includeRemoved: true))
              .singleWhere((t) => t.id == first)
              .pendingOperation,
          isFalse,
        );
        await repository.close();
        repository = await LibraryRepository.open(
          root,
          secretStore: SystemSecretStore(),
        );
        expect(
          (await repository.listTargets(includeRemoved: true))
              .singleWhere((t) => t.id == first)
              .removed,
          isTrue,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        // Only UUIDs allocated above in the new test namespace are removed.
        for (final id in created) {
          await repository.removeTarget(id);
        }
        await repository.close();
        await sandbox.delete(recursive: true);
      }
    },
  );
}
