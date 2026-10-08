import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/links/domain/link_transfer.dart';
import 'package:imagehost/features/links/domain/link_availability.dart';
import 'package:imagehost/features/links/data/link_probe_gateway.dart';
import 'package:imagehost/features/links/presentation/link_results_screen.dart';
import 'package:imagehost/features/upload/domain/link_format.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:material_ui/material_ui.dart';

import 'core/upload_repository_test.dart' show QueueTestSecrets;

// Actual SQLite/file futures alternate with fake widget time. No HTTP adapter
// or system clipboard is invoked by these fixture-confirmation tests.
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
  expect(done, isTrue, reason: '真实 IO 应当收尾，不能将卡住包装成通过');
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
  fail(
    '链接页状态未完成：${tester.widgetList<Text>(find.byType(Text, skipOffstage: false)).map((w) => w.data).join(' | ')}',
  );
}

class _Gateway implements LinkTransferGateway {
  final copied = <String>[];
  final shared = <String>[];
  LinkTransferStatus copyStatus = LinkTransferStatus.copied;
  LinkTransferStatus shareStatus = LinkTransferStatus.cancelled;
  LinkShareAnchor? anchor;
  @override
  Future<LinkTransferStatus> copyText(String text) async {
    copied.add(text);
    return copyStatus;
  }

  @override
  Future<LinkTransferStatus> shareText(
    String text, {
    LinkShareAnchor? anchor,
  }) async {
    shared.add(text);
    this.anchor = anchor;
    return shareStatus;
  }
}

class _ProbeGateway implements LinkProbeGateway {
  final calls = <Uri>[];
  CancelToken? token;
  Completer<void>? gate;
  LinkProbeOutcome outcome = const LinkProbeOutcome(
    LinkAvailability.accessible,
    LinkProbeReason.reachable,
    httpStatus: 200,
  );
  @override
  Future<LinkProbeOutcome> check({
    required Uri url,
    required ImageHostService service,
    required CancelToken cancelToken,
  }) async {
    calls.add(url);
    token = cancelToken;
    await gate?.future;
    return outcome;
  }
}

class _Fixture {
  _Fixture(
    this.directory,
    this.repository,
    this.session,
    this.container,
    this.gateway,
    this.probes,
  );
  final Directory directory;
  final LibraryRepository repository;
  final LibrarySession session;
  final ProviderContainer container;
  final _Gateway gateway;
  final _ProbeGateway probes;
  Future<void>? _closing;
  static Future<_Fixture> open() async {
    final directory = await Directory.systemTemp.createTemp(
      'imagehost-links-ui-',
    );
    final repository = await LibraryRepository.open(
      Directory('${directory.path}/library'),
      secretStore: QueueTestSecrets(),
    );
    final session = LibrarySession(repository, const []);
    final gateway = _Gateway();
    final probes = _ProbeGateway();
    final container = ProviderContainer(
      overrides: [
        librarySessionProvider.overrideWith((_) async => session),
        linkTransferGatewayProvider.overrideWithValue(gateway),
        linkProbeGatewayProvider.overrideWithValue(probes),
      ],
    );
    return _Fixture(directory, repository, session, container, gateway, probes);
  }

  Future<String> asset(String name, int width) async {
    final bytes = img.encodePng(img.Image(width: width, height: 4));
    return (await repository.importResource(
      PlatformResource(displayName: name, openRead: () => Stream.value(bytes)),
    )).asset!.id;
  }

  Future<String> target(String alias) => repository.saveTarget(
    service: ImageHostService.catbox,
    alias: alias,
    anonymous: false,
    credential: 'SyntheticAccountFixture0123456789',
  );
  int _sequence = 0;
  Future<void> result(String asset, String target, String url) async {
    final batch = await repository.enqueueUploads(
      intentId: 'fixture-${_sequence++}',
      assetIds: [asset],
      targetIds: [target],
      allowOriginalMetadata: true,
      forceAgain: true,
    );
    final execution = (await repository.beginUploadAttempt(
      batch.items.single.id,
    ))!;
    try {
      await repository.authorizeUploadRequest(execution.attemptId);
      await repository.finishUploadAttempt(
        execution,
        ProviderUploadSuccess(
          service: ImageHostService.catbox,
          remoteId: Uri.parse(url).pathSegments.last,
          directUrl: Uri.parse(url),
        ),
        accumulatedRunning: Duration.zero,
      );
    } finally {
      await execution.release();
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    container.dispose();
    await session.close();
    await directory.delete(recursive: true);
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture, {
  double scale = 1,
  List<String> assets = const [],
}) async {
  if (scale == 1) {
    tester.view.physicalSize = const Size(1280, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  addTearDown(() => _native(tester, fixture.close));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: fixture.container,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: LinkResultsScreen(assetIdsInOrder: assets),
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

Future<String> _seedProbe(_Fixture fixture, {String name = 'Probe.png'}) async {
  final asset = await fixture.asset(name, 11);
  final target = await fixture.target('明确目标');
  await fixture.result(asset, target, 'https://files.catbox.moe/probe.png');
  return (await fixture.repository.listLinkResults()).items.single.id;
}

Future<void> _acceptProbe(WidgetTester tester, String id) async {
  await _tap(tester, find.byKey(ValueKey('links-probe-$id')));
  await _until(tester, () => find.text('主动检测已选链接？').evaluate().isNotEmpty);
  await _tap(tester, find.widgetWithText(FilledButton, '确认本次网络检测'));
}

void main() {
  testWidgets(
    'UT-072 passive page and cancelled confirmation never authorize IO',
    (tester) async {
      final fixture = await _native(tester, _Fixture.open);
      final id = await _native(tester, () => _seedProbe(fixture));
      await _mount(tester, fixture);
      await _until(
        tester,
        () => find.byKey(ValueKey('links-probe-$id')).evaluate().isNotEmpty,
      );
      expect(fixture.probes.calls, isEmpty);
      expect(fixture.session.existingLinkProbes, isNull);
      await _tap(tester, find.byKey(ValueKey('links-probe-$id')));
      await _until(tester, () => find.text('主动检测已选链接？').evaluate().isNotEmpty);
      expect(find.textContaining('可能计入服务访问'), findsOneWidget);
      expect(
        find.textContaining('https://files.catbox.moe/probe.png'),
        findsWidgets,
      );
      await _tap(tester, find.widgetWithText(TextButton, '取消'));
      await _until(tester, () => find.text('主动检测已选链接？').evaluate().isEmpty);
      expect(fixture.probes.calls, isEmpty);
      expect(fixture.session.existingLinkProbes, isNull);
      expect(
        (await _native(
          tester,
          fixture.repository.listLinkResults,
        )).items.single.availability.state,
        LinkAvailability.recorded,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'UT-072 explicit reachable then offline and Gone retain ordinary result and prior evidence',
    (tester) async {
      final fixture = await _native(tester, _Fixture.open);
      final id = await _native(tester, () => _seedProbe(fixture));
      await _mount(tester, fixture);
      await _until(
        tester,
        () => find.byKey(ValueKey('links-probe-$id')).evaluate().isNotEmpty,
      );
      await _acceptProbe(tester, id);
      await _until(
        tester,
        () =>
            find.text('可访问（检测时）').evaluate().isNotEmpty &&
            find.textContaining('检测结束：更新 1 项').evaluate().isNotEmpty,
      );
      final last = (await _native(
        tester,
        fixture.repository.listLinkResults,
      )).items.single.availability.lastAccessibleAt;
      expect(last, isNotNull);
      fixture.probes.outcome = LinkProbeOutcome.unconfirmed;
      await _acceptProbe(tester, id);
      await _until(
        tester,
        () =>
            find.text('未能确认').evaluate().isNotEmpty &&
            find.textContaining('上次可访问：').evaluate().isNotEmpty,
      );
      expect(
        (await _native(
          tester,
          fixture.repository.listLinkResults,
        )).items.single.availability.lastAccessibleAt,
        last,
      );
      fixture.probes.outcome = const LinkProbeOutcome(
        LinkAvailability.deleted,
        LinkProbeReason.gone,
        httpStatus: 410,
      );
      await _acceptProbe(tester, id);
      await _until(
        tester,
        () =>
            find.text('远端已删除（服务报告）').evaluate().isNotEmpty &&
            find.textContaining('检测结束：更新 1 项').evaluate().isNotEmpty,
      );
      expect(
        (await _native(tester, fixture.repository.listLinkResults)).total,
        1,
      );
      expect(
        await _native(tester, fixture.repository.listUploadBatches),
        hasLength(1),
      );
      await _tap(tester, find.widgetWithText(OutlinedButton, '复制URL'));
      await _until(tester, () => fixture.gateway.copied.isNotEmpty);
      expect(
        fixture.gateway.copied.single,
        'https://files.catbox.moe/probe.png',
      );
      expect(fixture.probes.calls, hasLength(3));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'UT-072 batch confirms selected visible frozen scope without later arrivals',
    (tester) async {
      final fixture = await _native(tester, _Fixture.open);
      final setup = await _native(tester, () async {
        final asset = await fixture.asset('Scope.png', 12);
        final target = await fixture.target('明确目标');
        await fixture.result(asset, target, 'https://files.catbox.moe/one.png');
        await fixture.result(asset, target, 'https://files.catbox.moe/two.png');
        return (asset, target);
      });
      await _mount(tester, fixture);
      await _until(
        tester,
        () => find.textContaining('已展示 2 / 2 项').evaluate().isNotEmpty,
      );
      await _tap(tester, find.byKey(const Key('links-select-visible')));
      await tester.enterText(find.byKey(const Key('links-search')), 'one.png');
      await _until(
        tester,
        () =>
            find.textContaining('已展示 1 / 1 项').evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      await _tap(tester, find.byKey(const Key('links-probe-selected')));
      await _until(tester, () => find.text('主动检测已选链接？').evaluate().isNotEmpty);
      expect(find.textContaining('明确选择的 1 项'), findsOneWidget);
      expect(find.textContaining('two.png'), findsNothing);
      await _native(
        tester,
        () => fixture.result(
          setup.$1,
          setup.$2,
          'https://files.catbox.moe/one-later.png',
        ),
      );
      await _tap(tester, find.widgetWithText(FilledButton, '确认本次网络检测'));
      await _until(
        tester,
        () => find.textContaining('检测结束：更新 1 项').evaluate().isNotEmpty,
      );
      expect(fixture.probes.calls.map((url) => url.path).toList(), [
        '/one.png',
      ]);
      final results = (await _native(
        tester,
        fixture.repository.listLinkResults,
      )).items;
      expect(
        results.where((r) => r.availability.state == LinkAvailability.recorded),
        hasLength(2),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'UT-072 cancellation waits actual IO and never dispatches remaining selected links',
    (tester) async {
      final fixture = await _native(tester, _Fixture.open);
      await _native(tester, () async {
        final asset = await fixture.asset('Cancel.png', 13);
        final target = await fixture.target('明确目标');
        await fixture.result(asset, target, 'https://files.catbox.moe/a.png');
        await fixture.result(asset, target, 'https://files.catbox.moe/b.png');
      });
      fixture.probes.gate = Completer<void>();
      await _mount(tester, fixture);
      await _until(
        tester,
        () => find.textContaining('已展示 2 / 2 项').evaluate().isNotEmpty,
      );
      await _tap(tester, find.byKey(const Key('links-select-visible')));
      await _tap(tester, find.byKey(const Key('links-probe-selected')));
      await _until(tester, () => find.text('主动检测已选链接？').evaluate().isNotEmpty);
      await _tap(tester, find.widgetWithText(FilledButton, '确认本次网络检测'));
      await _until(tester, () => fixture.probes.calls.isNotEmpty);
      await _tap(tester, find.byKey(const Key('links-cancel-probe')));
      expect(fixture.probes.token!.isCancelled, isTrue);
      expect(find.textContaining('检测已取消，等待实际网络收尾后结束'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('links-probe-selected')),
            )
            .onPressed,
        isNull,
      );
      fixture.probes.gate!.complete();
      await _until(
        tester,
        () => find.textContaining('检测已取消，等待实际网络收尾后结束').evaluate().isNotEmpty,
      );
      expect(fixture.probes.calls, hasLength(1));
      final results = (await _native(
        tester,
        fixture.repository.listLinkResults,
      )).items;
      expect(
        results.where(
          (r) => r.availability.reason == LinkProbeReason.cancelled,
        ),
        hasLength(1),
      );
      expect(
        results.where((r) => r.availability.state == LinkAvailability.recorded),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'UT-072 removed reviewed result rejects network and disposed confirmation resolves',
    (tester) async {
      final fixture = await _native(tester, _Fixture.open);
      final id = await _native(tester, () => _seedProbe(fixture));
      await _mount(tester, fixture);
      await _until(
        tester,
        () => find.byKey(ValueKey('links-probe-$id')).evaluate().isNotEmpty,
      );
      await _tap(tester, find.byKey(ValueKey('links-probe-$id')));
      await _until(tester, () => find.text('主动检测已选链接？').evaluate().isNotEmpty);
      await _native(
        tester,
        () => fixture.repository.removeLocalLinkResults([
          id,
        ], confirmLocalRemoval: true),
      );
      await _tap(tester, find.widgetWithText(FilledButton, '确认本次网络检测'));
      await _until(
        tester,
        () => find.textContaining('检测或状态保存未完整确认').evaluate().isNotEmpty,
      );
      expect(fixture.probes.calls, isEmpty);
      final next = await _native(tester, () => _seedProbe(fixture));
      await _until(
        tester,
        () => find.byKey(ValueKey('links-probe-$next')).evaluate().isNotEmpty,
      );
      await _tap(tester, find.byKey(ValueKey('links-probe-$next')));
      await _until(tester, () => find.text('主动检测已选链接？').evaluate().isNotEmpty);
      await tester.pumpWidget(const SizedBox());
      await _native(tester, fixture.close);
      expect(fixture.probes.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'UT-072 system exit cancels pending confirmation before safe library close',
    (tester) async {
      final fixture = await _native(tester, _Fixture.open);
      final id = await _native(tester, () => _seedProbe(fixture));
      await _mount(tester, fixture);
      await _until(
        tester,
        () => find.byKey(ValueKey('links-probe-$id')).evaluate().isNotEmpty,
      );
      await _tap(tester, find.byKey(ValueKey('links-probe-$id')));
      await _until(tester, () => find.text('主动检测已选链接？').evaluate().isNotEmpty);
      expect(
        await _native(tester, tester.binding.handleRequestAppExit),
        AppExitResponse.exit,
      );
      expect(fixture.probes.calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'UT-072 state intersection refresh excludes newly unknown without implicit probes',
    (tester) async {
      final fixture = await _native(tester, _Fixture.open);
      final id = await _native(tester, () => _seedProbe(fixture));
      await _mount(tester, fixture);
      await _until(
        tester,
        () => find.byKey(ValueKey('links-probe-$id')).evaluate().isNotEmpty,
      );
      final field = find.byType(DropdownButtonFormField<LinkAvailability>);
      tester
          .widget<DropdownButtonFormField<LinkAvailability>>(field)
          .onChanged!(LinkAvailability.recorded);
      await _until(
        tester,
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      fixture.probes.outcome = LinkProbeOutcome.unconfirmed;
      await _acceptProbe(tester, id);
      await _until(
        tester,
        () =>
            find.text('没有匹配的已确认链接。').evaluate().isNotEmpty &&
            find.textContaining('检测结束：更新 1 项').evaluate().isNotEmpty &&
            tester
                    .widget<DropdownButtonFormField<LinkAvailability>>(field)
                    .onChanged !=
                null,
      );
      tester
          .widget<DropdownButtonFormField<LinkAvailability>>(field)
          .onChanged!(LinkAvailability.unknown);
      await _until(
        tester,
        () => find.byKey(ValueKey('links-state-$id')).evaluate().isNotEmpty,
      );
      expect(
        tester.widget<Text>(find.byKey(ValueKey('links-state-$id'))).data,
        '未能确认',
      );
      expect(fixture.probes.calls, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'AT-004 partial UT-072 populated probe confirmation at $width with large text',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = await _native(tester, _Fixture.open);
        final id = await _native(
          tester,
          () => _seedProbe(fixture, name: '长名称图片与明确历史目标.png'),
        );
        await _mount(tester, fixture, scale: 1.5);
        for (
          var i = 0;
          i < 20 && find.byKey(ValueKey('links-probe-$id')).evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          if (find.byType(ListView).evaluate().isNotEmpty) {
            await tester.drag(find.byType(ListView), const Offset(0, -250));
          }
          await tester.pump(const Duration(milliseconds: 50));
        }
        await _until(
          tester,
          () => find.byKey(ValueKey('links-probe-$id')).evaluate().isNotEmpty,
        );
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('links-probe-$id')),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();
        for (
          var i = 0;
          i < 20 &&
              find
                  .byKey(ValueKey('links-probe-$id'))
                  .hitTestable()
                  .evaluate()
                  .isEmpty;
          i++
        ) {
          await tester.drag(find.byType(ListView), const Offset(0, -200));
          await tester.pump();
        }
        expect(
          find.byKey(ValueKey('links-probe-$id')).hitTestable(),
          findsOneWidget,
        );
        await _tap(tester, find.byKey(ValueKey('links-probe-$id')));
        await _until(
          tester,
          () => find.text('主动检测已选链接？').evaluate().isNotEmpty,
        );
        expect(tester.takeException(), isNull);
        await _tap(tester, find.widgetWithText(TextButton, '取消'));
        expect(fixture.probes.calls, isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('AT-004 partial links $width empty and large text layout', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = await _native(tester, _Fixture.open);
      await _mount(tester, fixture, scale: 1.5);
      // The compact screen deliberately scrolls. Bring the result region into
      // view while alternating real SQLite work with widget frames.
      for (
        var i = 0;
        i < 20 && find.text('暂无已确认普通链接。').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.drag(find.byType(ListView), const Offset(0, -250));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await _until(tester, () => find.text('暂无已确认普通链接。').evaluate().isNotEmpty);
      expect(tester.takeException(), isNull);
      expect(fixture.gateway.copied, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await _native(tester, fixture.close);
    });
  }

  testWidgets(
    'UT-017 AT-004 partial keyword intersection historical removed target and replacement reset',
    (tester) async {
      final fixture = await _native(tester, _Fixture.open);
      final setup = await _native(tester, () async {
        final asset = await fixture.asset('VisibleNeedle.png', 8);
        final old = await fixture.target('HistoricalNeedle');
        await fixture.result(
          asset,
          old,
          'https://files.catbox.moe/visible.png',
        );
        await fixture.repository.removeTarget(old);
        final current = await fixture.target('HistoricalNeedle');
        await fixture.result(
          asset,
          current,
          'https://files.catbox.moe/current.png',
        );
        return (old, current);
      });
      await _mount(tester, fixture);
      await _until(
        tester,
        () => find.textContaining('已展示 2 / 2 项').evaluate().isNotEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('links-search')),
        'HISTORICALNEEDLE',
      );
      await _until(
        tester,
        () =>
            find.textContaining('已展示 2 / 2 项').evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      final targetField = find.byType(DropdownButtonFormField<String>);
      tester.widget<DropdownButtonFormField<String>>(targetField).onChanged!(
        setup.$1,
      );
      await _until(
        tester,
        () => find.textContaining('已展示 1 / 1 项').evaluate().isNotEmpty,
      );
      expect(find.text('https://files.catbox.moe/visible.png'), findsOneWidget);
      expect(find.text('https://files.catbox.moe/current.png'), findsNothing);
      await _tap(tester, find.byKey(const Key('links-select-visible')));
      fixture.container
          .read(libraryReplacementRevisionProvider.notifier)
          .committed();
      await _until(
        tester,
        () => find.textContaining('已展示 2 / 2 项；选择 0 项').evaluate().isNotEmpty,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('links-search')))
            .controller!
            .text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      await _native(tester, fixture.close);
    },
  );

  testWidgets(
    'UT-070 first page scope cancel and confirmation never add hidden results',
    (tester) async {
      final fixture = await _native(tester, _Fixture.open);
      await _native(tester, () async {
        final asset = await fixture.asset('Many.png', 8);
        final target = await fixture.target('历史');
        for (var i = 0; i < 51; i++) {
          await fixture.result(
            asset,
            target,
            'https://files.catbox.moe/fixture-$i.png',
          );
        }
      });
      final page = await _native(
        tester,
        () => fixture.repository.listLinkResults(limit: 50),
      );
      final expected = (await _native(
        tester,
        () => fixture.repository.prepareVisibleLinkCopy(
          page.items.map((r) => r.id).toList(),
          UploadLinkFormat.url,
        ),
      )).batch.text;
      await _mount(tester, fixture);
      await _until(
        tester,
        () => find.textContaining('已展示 50 / 51 项').evaluate().isNotEmpty,
      );
      await _tap(tester, find.byKey(const Key('links-copy-visible')));
      await _until(tester, () => find.text('确认批量复制').evaluate().isNotEmpty);
      await _tap(tester, find.text('取消'));
      await _until(tester, () => find.byType(AlertDialog).evaluate().isEmpty);
      expect(fixture.gateway.copied, isEmpty);
      await _tap(tester, find.byKey(const Key('links-copy-visible')));
      await _until(tester, () => find.text('确认批量复制').evaluate().isNotEmpty);
      fixture.container
          .read(libraryReplacementRevisionProvider.notifier)
          .committed();
      await tester.pump();
      await _until(
        tester,
        () =>
            find.byType(LinearProgressIndicator).evaluate().isEmpty &&
            find.byType(AlertDialog).evaluate().isEmpty,
      );
      expect(fixture.gateway.copied, isEmpty, reason: '替换后不能使用旧确认发起系统操作');
      await _tap(tester, find.byKey(const Key('links-copy-visible')));
      await _until(tester, () => find.text('确认批量复制').evaluate().isNotEmpty);
      await _tap(tester, find.widgetWithText(FilledButton, '复制'));
      await _until(tester, () => fixture.gateway.copied.isNotEmpty);
      expect(fixture.gateway.copied.single, expected);
      expect(fixture.gateway.copied.single.split('\n'), hasLength(50));
      await tester.drag(find.byType(ListView), const Offset(0, 900));
      await tester.pump();
      expect(find.textContaining('已展示 50 / 51 项'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await _native(tester, fixture.close);
    },
  );

  testWidgets(
    'UT-071 copy failure retains result retries locally share cancellation and removal confirmation',
    (tester) async {
      final fixture = await _native(tester, _Fixture.open);
      await _native(tester, () async {
        final asset = await fixture.asset('Retry.png', 8);
        final target = await fixture.target('历史');
        await fixture.result(
          asset,
          target,
          'https://files.catbox.moe/retry.png',
        );
      });
      fixture.gateway.copyStatus = LinkTransferStatus.failed;
      await _mount(tester, fixture);
      await _until(
        tester,
        () => find.textContaining('已展示 1 / 1 项').evaluate().isNotEmpty,
      );
      final hold = await _native(tester, fixture.repository.acquireRestoreHold);
      await _tap(tester, find.byTooltip('刷新链接'));
      await _until(
        tester,
        () => find.textContaining('链接读取失败').evaluate().isNotEmpty,
      );
      expect(find.text('https://files.catbox.moe/retry.png'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '复制URL'),
            )
            .onPressed,
        isNull,
      );
      await _native(tester, hold.release);
      await _tap(tester, find.byKey(const Key('links-retry')));
      await _until(
        tester,
        () =>
            find.textContaining('链接读取失败').evaluate().isEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      await _tap(tester, find.widgetWithText(OutlinedButton, '复制URL'));
      await _until(
        tester,
        () => find.textContaining('本地复制或分享未完成').evaluate().isNotEmpty,
      );
      expect(
        await _native(tester, fixture.repository.listUploadResults),
        hasLength(1),
      );
      final attempts = (await _native(
        tester,
        fixture.repository.listUploadBatches,
      )).single.items.single.attemptCount;
      fixture.gateway.copyStatus = LinkTransferStatus.copied;
      await _tap(tester, find.widgetWithText(OutlinedButton, '复制URL'));
      await _until(
        tester,
        () => find.textContaining('已复制 1 项').evaluate().isNotEmpty,
      );
      expect(
        (await _native(
          tester,
          fixture.repository.listUploadBatches,
        )).single.items.single.attemptCount,
        attempts,
      );
      expect(fixture.gateway.copied, hasLength(2));
      await _tap(tester, find.widgetWithText(TextButton, '系统分享'));
      await _until(
        tester,
        () => find.text('已取消分享，结果记录保留。').evaluate().isNotEmpty,
      );
      expect(fixture.gateway.anchor!.width, greaterThan(0));
      await _tap(tester, find.widgetWithText(TextButton, '移除本地记录'));
      await _until(tester, () => find.text('仅移除本地链接记录？').evaluate().isNotEmpty);
      await _tap(tester, find.text('取消'));
      expect(
        await _native(tester, fixture.repository.listUploadResults),
        hasLength(1),
      );
      await _tap(tester, find.widgetWithText(TextButton, '移除本地记录'));
      await _until(tester, () => find.text('仅移除本地链接记录？').evaluate().isNotEmpty);
      await _tap(tester, find.widgetWithText(FilledButton, '移除本地记录'));
      await _until(tester, () => find.text('暂无已确认普通链接。').evaluate().isNotEmpty);
      expect(
        await _native(tester, fixture.repository.listUploadResults),
        isEmpty,
      );
      expect(
        await _native(tester, fixture.repository.listUploadBatches),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox());
      await _native(tester, fixture.close);
    },
  );

  testWidgets(
    'UT-070 asset target ordered scope reports skipped and deduplicates',
    (tester) async {
      final fixture = await _native(tester, _Fixture.open);
      final setup = await _native(tester, () async {
        final a = await fixture.asset('A.png', 8),
            b = await fixture.asset('B.png', 9),
            c = await fixture.asset('C.png', 10);
        final first = await fixture.target('I1'),
            second = await fixture.target('C1');
        await fixture.result(a, first, 'https://files.catbox.moe/a.png');
        await fixture.result(b, first, 'https://files.catbox.moe/b.png');
        await fixture.result(b, second, 'https://files.catbox.moe/b.png');
        return ([b, a, c], [first, second]);
      });
      await _mount(tester, fixture, assets: setup.$1);
      await _until(
        tester,
        () => find.byType(CheckboxListTile).evaluate().length == 2,
      );
      for (final id in setup.$2) {
        final marker = id.substring(0, 8);
        final tile = find.byWidgetPredicate(
          (widget) =>
              widget is CheckboxListTile &&
              widget.title is Text &&
              ((widget.title as Text).data ?? '').contains(marker),
        );
        await _tap(tester, tile);
      }
      await _tap(tester, find.byKey(const Key('links-copy-assets')));
      await _until(tester, () => find.text('确认批量复制').evaluate().isNotEmpty);
      expect(find.textContaining('B.png → A.png → C.png'), findsOneWidget);
      expect(find.textContaining('跳过 3 项，去重 1 项'), findsOneWidget);
      await _tap(tester, find.widgetWithText(FilledButton, '复制'));
      await _until(tester, () => fixture.gateway.copied.isNotEmpty);
      expect(
        fixture.gateway.copied.single,
        'https://files.catbox.moe/b.png\nhttps://files.catbox.moe/a.png',
      );
      await tester.pumpWidget(const SizedBox());
      await _native(tester, fixture.close);
    },
  );
}
