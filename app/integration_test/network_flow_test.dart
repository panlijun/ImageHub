import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/app.dart';
import 'package:imagehost/core/network_state.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 300; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (ready()) return;
  }
  fail('Windows 网络观察或应用接线未到达预期状态。');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'PT-002/UT-063 partial Windows native default path observation and production task feedback without external requests',
    (tester) async {
      // No network settings are changed and no host is probed. Actual OS route
      // changes, mobile switching and physical offline recovery remain PT work.
      final raw = await const MethodChannel('io.imagehost/network')
          .invokeMethod<Object?>('read')
          .timeout(const Duration(seconds: 5));
      final native = NetworkSnapshot.fromPlatform(raw);
      expect(native.status, isNot(NetworkStatus.unknown));
      final first = Completer<NetworkSnapshot>();
      final subscription = const EventChannel('io.imagehost/network_changes')
          .receiveBroadcastStream()
          .listen(
            (value) {
              if (!first.isCompleted) {
                first.complete(NetworkSnapshot.fromPlatform(value));
              }
            },
            onError: (Object error) {
              if (!first.isCompleted) first.completeError(error);
            },
          );
      try {
        final initial = await first.future.timeout(const Duration(seconds: 5));
        expect(initial.status, isNot(NetworkStatus.unknown));
      } finally {
        await subscription.cancel();
      }

      final sandbox = await Directory.systemTemp.createTemp(
        'imagehost-network-engine-',
      );
      final root = Directory(p.join(sandbox.path, 'library'));
      final boundary = GlobalKey();
      final container = ProviderContainer(
        overrides: [
          libraryLocationProvider.overrideWithValue(() async => root),
        ],
      );
      LibrarySession? session;
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(key: boundary, child: const ImageHostApp()),
          ),
        );
        final entry = find.ancestor(
          of: find.text('上传任务'),
          matching: find.byType(ListTile),
        );
        await _until(
          tester,
          () =>
              entry.evaluate().isNotEmpty &&
              tester.widget<ListTile>(entry).onTap != null,
        );
        await tester.tap(entry);
        await tester.pump();
        final opened = await container.read(librarySessionProvider.future);
        session = opened;
        await _until(
          tester,
          () =>
              opened.uploads.networkSnapshot.status != NetworkStatus.unknown &&
              find
                  .byKey(const ValueKey('tasks-network-status'))
                  .evaluate()
                  .isNotEmpty,
        );
        expect(opened.uploads.networkAllowed, isFalse);
        expect(opened.uploads.activeCount, 0);
        expect(await opened.repository.listUploadBatches(), isEmpty);
        final refresh = find.ancestor(
          of: find.byTooltip('刷新上传资料'),
          matching: find.byType(IconButton),
        );
        await tester.tap(refresh);
        await tester.pump();
        await _until(
          tester,
          () => tester.widget<IconButton>(refresh).onPressed != null,
        );
        expect(opened.uploads.networkAllowed, isFalse);
        expect(opened.uploads.activeCount, 0);
        final status = tester.widget<Text>(
          find.byKey(const ValueKey('tasks-network-status')),
        );
        expect(status.data, contains(opened.uploads.networkSnapshot.label));
        expect(status.data, contains('仅 Wi-Fi / 有线网络'));
        expect(tester.takeException(), isNull);
        await tester.pump();
        final pixels =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        try {
          final png = await pixels.toByteData(format: ui.ImageByteFormat.png);
          await File(
            p.join(
              Directory.current.path,
              '..',
              'docs',
              'validation',
              'windows-network.png',
            ),
          ).writeAsBytes(png!.buffer.asUint8List(), flush: true);
        } finally {
          pixels.dispose();
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        await session?.close();
        container.dispose();
        final resolved = p.normalize(p.absolute(sandbox.path));
        final temp = p.normalize(p.absolute(Directory.systemTemp.path));
        if (!p.isWithin(temp, resolved) ||
            !p.basename(resolved).startsWith('imagehost-network-engine-')) {
          throw StateError('测试目录不在预期临时根目录。');
        }
        await sandbox.delete(recursive: true);
      }
    },
  );
}
