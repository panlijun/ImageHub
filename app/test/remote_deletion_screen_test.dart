import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/links/data/remote_deletion_gateway.dart';
import 'package:imagehost/features/links/domain/link_transfer.dart';
import 'package:imagehost/features/links/domain/remote_deletion.dart';
import 'package:imagehost/features/links/presentation/link_results_screen.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'core/upload_repository_test.dart' show QueueTestSecrets;
import 'support/legacy_anonymous_fixture.dart';

// Genuine SQLite/files, controlled gateways. Alternate native IO with widget
// time; a cancelled request remains pending until its actual gateway completes.
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
  await _until(tester, () => done);
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
  fail('真实 IO 或链接页状态未收尾，不能将挂起包装为通过。');
}

class _DeletionGateway implements RemoteDeletionGateway {
  int calls = 0;
  CancelToken? token;
  Completer<void>? gate;
  bool cleanupFails = false;
  @override
  Future<RemoteDeletionOutcome> delete({
    required CatboxDeletionRequest request,
    required CancelToken cancelToken,
  }) async {
    calls++;
    token = cancelToken;
    expect(request.filename, 'synthetic.png');
    expect(request.userhash, _Fixture.credential);
    await gate?.future;
    if (cleanupFails) throw const RemoteDeletionCleanupFailure();
    return const RemoteDeletionOutcome(
      RemoteDeletionState.unknown,
      RemoteDeletionReason.unconfirmed,
      httpStatus: 200,
    );
  }
}

class _TransferGateway implements LinkTransferGateway {
  final copied = <String>[];
  @override
  Future<LinkTransferStatus> copyText(String text) async {
    copied.add(text);
    return LinkTransferStatus.copied;
  }

  @override
  Future<LinkTransferStatus> shareText(
    String text, {
    LinkShareAnchor? anchor,
  }) async => LinkTransferStatus.cancelled;
}

class _Fixture {
  _Fixture(
    this.directory,
    this.repository,
    this.session,
    this.container,
    this.secrets,
    this.deletions,
    this.transfers,
  );
  static const credential = 'synthetic-catbox-delete-credential';
  static const management =
      'https://ibb.co/remoteID/syntheticManagementToken012345';
  final Directory directory;
  final LibraryRepository repository;
  final LibrarySession session;
  final ProviderContainer container;
  final QueueTestSecrets secrets;
  final _DeletionGateway deletions;
  final _TransferGateway transfers;
  Future<void>? _closing;

  static Future<_Fixture> open() async {
    final directory = await Directory.systemTemp.createTemp(
      'imagehost-remote-delete-ui-',
    );
    final secrets = QueueTestSecrets();
    final repository = await LibraryRepository.open(
      Directory(p.join(directory.path, 'library')),
      secretStore: secrets,
    );
    final session = LibrarySession(repository, const []);
    final deletions = _DeletionGateway(), transfers = _TransferGateway();
    final container = ProviderContainer(
      overrides: [
        librarySessionProvider.overrideWith((_) async => session),
        remoteDeletionGatewayProvider.overrideWithValue(deletions),
        linkTransferGatewayProvider.overrideWithValue(transfers),
      ],
    );
    return _Fixture(
      directory,
      repository,
      session,
      container,
      secrets,
      deletions,
      transfers,
    );
  }

  Future<({String result, String target, String asset})> seed({
    ImageHostService service = ImageHostService.catbox,
    bool anonymous = false,
    String? url,
  }) async {
    final bytes = img.encodePng(img.Image(width: 6, height: 5));
    final asset = (await repository.importResource(
      PlatformResource(
        displayName: '真实合成图片.png',
        openRead: () => Stream.value(bytes),
      ),
    )).asset!.id;
    final target = await repository.saveTarget(
      service: service,
      alias: '明确账号',
      anonymous: false,
      credential: credential,
    );
    final batch = await repository.enqueueUploads(
      intentId: 'synthetic-ui-result',
      assetIds: [asset],
      targetIds: [target],
      allowOriginalMetadata: true,
    );
    final execution = (await repository.beginUploadAttempt(
      batch.items.single.id,
    ))!;
    final direct = Uri.parse(
      url ??
          (service == ImageHostService.catbox
              ? 'https://files.catbox.moe/synthetic.png'
              : 'https://i.ibb.co/remoteID/synthetic.png'),
    );
    try {
      await repository.authorizeUploadRequest(execution.attemptId);
      await repository.finishUploadAttempt(
        execution,
        ProviderUploadSuccess(
          service: service,
          remoteId: service == ImageHostService.catbox
              ? direct.pathSegments.last
              : 'remoteID',
          directUrl: direct,
          managementSecret: service == ImageHostService.imgbb
              ? SensitiveManagementSecret(management)
              : null,
        ),
        accumulatedRunning: Duration.zero,
      );
    } finally {
      await execution.release();
    }
    if (anonymous) {
      markLegacyAnonymous(Directory(p.join(directory.path, 'library')), target);
    }
    return (
      result: (await repository.listLinkResults()).items.single.id,
      target: target,
      asset: asset,
    );
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    container.dispose();
    await session.close();
    final temp = await Directory.systemTemp.resolveSymbolicLinks();
    final actual = await directory.resolveSymbolicLinks();
    if (!p.isWithin(temp, actual) ||
        !p.basename(actual).startsWith('imagehost-remote-delete-ui-')) {
      throw StateError('Refuse cleanup outside owned temporary directory.');
    }
    await Directory(actual).delete(recursive: true);
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture, {
  double width = 1280,
  double scale = 1,
  bool active = true,
}) async {
  tester.view.physicalSize = Size(width, 1500);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: fixture.container,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: LinkResultsScreen(active: active),
      ),
    ),
  );
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _showLoadedResult(WidgetTester tester, String result) async {
  final scrollable = find.byType(Scrollable).first;
  // At 390px with twice-sized text the filter controls fill the first viewport.
  // Read the loaded count first, then actually scroll the lazy result into view.
  await tester.scrollUntilVisible(
    find.textContaining('已展示 '),
    400,
    scrollable: scrollable,
    maxScrolls: 40,
  );
  await _until(
    tester,
    () => find.textContaining('已展示 1 / 1 项').evaluate().isNotEmpty,
  );
  await tester.scrollUntilVisible(
    find.byKey(ValueKey('links-remote-delete-$result')),
    400,
    scrollable: scrollable,
    maxScrolls: 40,
  );
  expect(find.text('真实合成图片.png'), findsOneWidget);
}

Future<_Fixture> _start(WidgetTester tester) async {
  final fixture = await _native(tester, _Fixture.open);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => _native(tester, fixture.close));
  return fixture;
}

Future<void> _dialog(WidgetTester tester, String result) async {
  await _tap(tester, find.byKey(ValueKey('links-remote-delete-$result')));
  await _until(tester, () => find.text('请求远端删除这个文件？').evaluate().isNotEmpty);
}

void main() {
  for (final viewport in [(390.0, 1.0), (1280.0, 1.0), (390.0, 2.0)]) {
    testWidgets(
      'UT-050 remote deletion independent confirmation ${viewport.$1}/${viewport.$2}',
      (tester) async {
        final fixture = await _start(tester);
        final ids = await _native(tester, fixture.seed);
        await _mount(tester, fixture, width: viewport.$1, scale: viewport.$2);
        await _showLoadedResult(tester, ids.result);
        expect(fixture.deletions.calls, 0);
        expect(fixture.session.existingRemoteDeletions, isNull);
        await _tap(tester, find.widgetWithText(OutlinedButton, '复制URL'));
        await _until(tester, () => fixture.transfers.copied.isNotEmpty);
        expect(fixture.deletions.calls, 0);
        await _dialog(tester, ids.result);
        expect(find.textContaining('可能失去远端内容'), findsOneWidget);
        expect(find.textContaining(_Fixture.credential), findsNothing);
        await _tap(tester, find.widgetWithText(TextButton, '取消'));
        await _until(tester, () => find.text('请求远端删除这个文件？').evaluate().isEmpty);
        expect(fixture.deletions.calls, 0);
        expect(fixture.session.existingRemoteDeletions, isNull);
        await _dialog(tester, ids.result);
        await _tap(tester, find.widgetWithText(FilledButton, '确认本次网络与远端删除'));
        await _until(
          tester,
          () => find
              .byKey(ValueKey('links-remote-deletion-state-${ids.result}'))
              .evaluate()
              .isNotEmpty,
        );
        expect(fixture.deletions.calls, 1);
        expect(find.textContaining('可能已生效'), findsWidgets);
        expect(find.textContaining('不会自动重试'), findsWidgets);
        expect(
          (await _native(tester, fixture.repository.listLinkResults)).total,
          1,
        );
        expect(
          await _native(tester, fixture.repository.listUploadBatches),
          hasLength(1),
        );
        expect(
          await _native(tester, () => fixture.repository.getAsset(ids.asset)),
          isNotNull,
        );
        await tester.pumpWidget(const SizedBox());
        await _mount(tester, fixture, width: viewport.$1, scale: viewport.$2);
        await _showLoadedResult(tester, ids.result);
        await _until(
          tester,
          () => find
              .byKey(ValueKey('links-remote-deletion-state-${ids.result}'))
              .evaluate()
              .isNotEmpty,
        );
        expect(fixture.deletions.calls, 1, reason: '页面重开和审计读取不自动请求');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final service in ImageHostService.values) {
    testWidgets(
      'UT-050 unsupported $service local removal and copy have zero remote requests',
      (tester) async {
        final fixture = await _start(tester);
        final ids = await _native(
          tester,
          () => fixture.seed(
            service: service,
            anonymous: service == ImageHostService.catbox,
          ),
        );
        await _mount(tester, fixture, width: 390, scale: 2);
        final button = find.byKey(
          ValueKey('links-remote-delete-${ids.result}'),
        );
        await _showLoadedResult(tester, ids.result);
        expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
        expect(find.textContaining(_Fixture.management), findsNothing);
        await _tap(tester, find.widgetWithText(OutlinedButton, '复制URL'));
        await _until(tester, () => fixture.transfers.copied.isNotEmpty);
        expect(
          fixture.transfers.copied.single.contains(_Fixture.management),
          isFalse,
        );
        await _tap(tester, find.widgetWithText(TextButton, '移除本地记录'));
        await _until(
          tester,
          () => find.text('仅移除本地链接记录？').evaluate().isNotEmpty,
        );
        await _tap(tester, find.widgetWithText(FilledButton, '移除本地记录'));
        await _until(
          tester,
          () => find.textContaining('已移除 1 项').evaluate().isNotEmpty,
        );
        expect(fixture.deletions.calls, 0);
        expect(
          await _native(tester, () => fixture.repository.getAsset(ids.asset)),
          isNotNull,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final removed in [false, true]) {
    testWidgets(
      'UT-050 missing credential or removed current UUID refused before HTTP removed=$removed',
      (tester) async {
        final fixture = await _start(tester);
        final ids = await _native(tester, fixture.seed);
        if (removed) {
          await _native(
            tester,
            () => fixture.repository.removeTarget(ids.target),
          );
        } else {
          fixture.secrets.values.clear();
        }
        await _mount(tester, fixture);
        await _showLoadedResult(tester, ids.result);
        await _tap(
          tester,
          find.byKey(ValueKey('links-remote-delete-${ids.result}')),
        );
        await _until(
          tester,
          () => find.byKey(const Key('links-feedback')).evaluate().isNotEmpty,
        );
        expect(find.text('请求远端删除这个文件？'), findsNothing);
        expect(fixture.deletions.calls, 0);
        expect(
          (await _native(tester, fixture.repository.listLinkResults)).total,
          1,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'UT-050 unsafe Catbox filename disabled and failed read retains valid list',
    (tester) async {
      final fixture = await _start(tester);
      final ids = await _native(
        tester,
        () => fixture.seed(url: 'https://files.catbox.moe/synthetic-file.png'),
      );
      await _mount(tester, fixture);
      final button = find.byKey(ValueKey('links-remote-delete-${ids.result}'));
      await _showLoadedResult(tester, ids.result);
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      final hold = await _native(tester, fixture.repository.acquireRestoreHold);
      await _tap(tester, find.byTooltip('刷新链接'));
      await _until(
        tester,
        () => find.textContaining('保留上次有效列表').evaluate().isNotEmpty,
      );
      expect(
        find.text('https://files.catbox.moe/synthetic-file.png'),
        findsOneWidget,
      );
      expect(fixture.deletions.calls, 0);
      await _native(tester, hold.release);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'UT-050 cancel and leave wait for actual late fetch before safe library close',
    (tester) async {
      final fixture = await _start(tester);
      final ids = await _native(tester, fixture.seed);
      fixture.deletions.gate = Completer<void>();
      await _mount(tester, fixture);
      await _showLoadedResult(tester, ids.result);
      await _dialog(tester, ids.result);
      await _tap(tester, find.widgetWithText(FilledButton, '确认本次网络与远端删除'));
      await _until(tester, () => fixture.deletions.calls == 1);
      await _tap(tester, find.byKey(const Key('links-cancel-remote-deletion')));
      expect(fixture.deletions.token!.isCancelled, isTrue);
      expect(fixture.session.existingRemoteDeletions!.busy, isTrue);
      await _mount(tester, fixture, active: false);
      expect(fixture.session.existingRemoteDeletions!.busy, isTrue);
      var closed = false;
      await tester.runAsync(() async {
        unawaited(fixture.session.close().then((_) => closed = true));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      expect(closed, isFalse);
      fixture.deletions.gate!.complete();
      await _until(tester, () => closed);
      expect(fixture.deletions.calls, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
