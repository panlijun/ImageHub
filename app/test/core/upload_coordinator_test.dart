import 'dart:async';

import 'package:imagehost/core/network_state.dart';

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/time_source.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/upload/application/upload_coordinator.dart';
import 'package:imagehost/features/upload/application/upload_queue_store.dart';
import 'package:imagehost/features/upload/data/provider_adapters.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/queue_policy.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';

void main() {
  test('UT-063 unknown offline and cellular wait; repeated Wi-Fi wake keeps one intent and attempt', () async {
    final store = _Store(1);
    final adapter = _Adapter();
    final coordinator = UploadCoordinator(store, adapters: [adapter]);
    await coordinator.setNetworkAllowed(true);
    await _drain();
    expect(coordinator.networkAllowed, isTrue);
    expect(coordinator.dispatchAllowed, isFalse);
    expect(store.waitReasons['item-0'], QueueWaitReason.network);
    expect(store.attempts, isEmpty);
    for (final network in [
      const NetworkSnapshot.offline(),
      NetworkSnapshot.connected([NetworkTransport.cellular]),
      NetworkSnapshot.connected([
        NetworkTransport.wifi,
        NetworkTransport.cellular,
      ]),
    ]) {
      coordinator.setNetworkSnapshot(network);
      await _drain();
      expect(adapter.calls, isEmpty);
      expect(coordinator.networkAllowed, isTrue);
    }
    for (var i = 0; i < 20; i++) {
      coordinator.setNetworkSnapshot(
        NetworkSnapshot.connected([NetworkTransport.wifi]),
      );
    }
    await _drain();
    expect(adapter.calls, hasLength(1));
    expect(store.attempts['item-0'], 1);
    adapter.calls.single.complete(_success());
    await _drain();
    expect(store.states['item-0'], PublishState.succeeded);
    await coordinator.close();
    await store.close();
  });

  test('UT-063 transport policy affects future dispatch; running IO and consent remain independent', () async {
    final store = _Store(3);
    final adapter = _Adapter();
    final coordinator = UploadCoordinator(
      store,
      adapters: [adapter],
      concurrency: 1,
      initialNetwork: NetworkSnapshot.connected([NetworkTransport.ethernet]),
    );
    await coordinator.setNetworkAllowed(true);
    await _drain();
    coordinator.setNetworkSnapshot(
      NetworkSnapshot.connected([NetworkTransport.cellular]),
    );
    await _drain();
    expect(adapter.calls.single.cancel.isCancelled, isFalse);
    adapter.calls.single.complete(_success());
    await _drain();
    expect(adapter.calls, hasLength(1));
    expect(store.waitReasons['item-1'], QueueWaitReason.network);
    coordinator.setNetworkPolicy(NetworkUploadPolicy.anyKnownNetwork);
    await _drain();
    expect(adapter.calls, hasLength(2));
    coordinator.setNetworkPolicy(NetworkUploadPolicy.wifiAndEthernet);
    expect(adapter.calls.last.cancel.isCancelled, isFalse);
    adapter.calls.last.complete(_success());
    await _drain();
    expect(adapter.calls, hasLength(2));
    coordinator.setNetworkSnapshot(
      NetworkSnapshot.connected([NetworkTransport.wifi]),
    );
    await _drain();
    expect(adapter.calls, hasLength(3));
    adapter.calls.last.complete(_success());
    await _drain();
    await coordinator.close();
    await store.close();
  });

  test('UT-063 observation and settings cannot grant consent or override item pause and unknown', () async {
    final store = _Store(3);
    store.states['item-0'] = PublishState.unknown;
    final adapter = _Adapter();
    final coordinator = UploadCoordinator(store, adapters: [adapter]);
    await coordinator.pauseItem('item-1', true);
    coordinator.setNetworkPolicy(NetworkUploadPolicy.anyKnownNetwork);
    coordinator.setNetworkSnapshot(
      NetworkSnapshot.connected([NetworkTransport.cellular]),
    );
    await _drain();
    expect(adapter.calls, isEmpty);
    await coordinator.setNetworkAllowed(true);
    await _drain();
    expect(adapter.calls, hasLength(1));
    expect(store.attempts, {'item-2': 1});
    coordinator.setNetworkSnapshot(const NetworkSnapshot.offline());
    coordinator.setNetworkSnapshot(
      NetworkSnapshot.connected([NetworkTransport.cellular]),
    );
    await _drain();
    expect(adapter.calls, hasLength(1));
    expect(store.states['item-0'], PublishState.unknown);
    expect(store.states['item-1'], PublishState.paused);
    adapter.calls.single.complete(_success());
    await _drain();
    await coordinator.setNetworkAllowed(false);
    await coordinator.pauseItem('item-1', false);
    coordinator.setNetworkSnapshot(
      NetworkSnapshot.connected([NetworkTransport.wifi]),
    );
    await _drain();
    expect(coordinator.networkAllowed, isFalse);
    expect(adapter.calls, hasLength(1));
    await coordinator.close();
    coordinator.setNetworkSnapshot(
      NetworkSnapshot.connected([NetworkTransport.cellular]),
    );
    coordinator.setNetworkPolicy(NetworkUploadPolicy.anyKnownNetwork);
    await _drain();
    expect(adapter.calls, hasLength(1));
    await store.close();
  });

  test('UT-063 network wake preserves monotonic Retry-After instead of shortening or restarting it', () async {
    final store = _Store(1);
    final adapter = _Adapter();
    final time = _Time();
    final coordinator = UploadCoordinator(
      store,
      adapters: [adapter],
      time: time,
      initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
    );
    await coordinator.setNetworkAllowed(true);
    await _drain();
    adapter.calls.single.complete(
      const ProviderUploadFailure(
        UploadFailureKind.rateLimited,
        UploadDeliveryEvidence.confirmedRejected,
        retryAfterSeconds: 10,
      ),
    );
    await _drain();
    time.elapsed = const Duration(seconds: 3);
    coordinator.setNetworkSnapshot(const NetworkSnapshot.offline());
    await _drain();
    time.elapsed = const Duration(seconds: 9);
    coordinator.setNetworkSnapshot(
      NetworkSnapshot.connected([NetworkTransport.ethernet]),
    );
    await _drain();
    expect(adapter.calls, hasLength(1));
    expect(store.delays['item-0'], const Duration(seconds: 10));
    time.elapsed = const Duration(seconds: 10);
    await coordinator.refresh();
    await _drain();
    expect(adapter.calls, hasLength(2));
    expect(store.attempts['item-0'], 2);
    adapter.calls.last.complete(_success());
    await _drain();
    await coordinator.close();
    await store.close();
  });

  test('UT-063 network loss after durable authorize prevents any adapter input read or request', () async {
    final store = _Store(1)..authorizationGate = Completer<bool>();
    final adapter = _Adapter();
    final coordinator = UploadCoordinator(
      store,
      adapters: [adapter],
      initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
    );
    await coordinator.setNetworkAllowed(true);
    await _drain();
    coordinator.setNetworkSnapshot(const NetworkSnapshot.offline());
    store.authorizationGate!.complete(true);
    await _drain();
    expect(adapter.calls, isEmpty);
    expect(store.released, ['item-0']);
    expect(coordinator.networkAllowed, isTrue);
    expect(store.waitReasons['item-0'], QueueWaitReason.network);
    coordinator.setNetworkSnapshot(
      NetworkSnapshot.connected([NetworkTransport.wifi]),
    );
    await _drain();
    expect(adapter.calls, hasLength(1));
    adapter.calls.single.complete(_success());
    await _drain();
    await coordinator.close();
    await store.close();
  });

  test('UT-052/053 construction is idle; dispatch bounded; lowering does not kill active IO', () async {
    final store = _Store(5);
    final adapter = _Adapter();
    final coordinator = UploadCoordinator(
      initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
      store,
      adapters: [adapter],
      concurrency: 3,
    );
    await _drain();
    expect(adapter.calls, isEmpty);
    await coordinator.setNetworkAllowed(true);
    await _drain();
    expect(adapter.calls.length, 3);
    coordinator.setConcurrency(1);
    await _drain();
    expect(adapter.calls.every((call) => !call.cancel.isCancelled), isTrue);
    adapter.calls[0].complete(_success());
    adapter.calls[1].complete(_success());
    await _drain();
    expect(adapter.calls.length, 3);
    adapter.calls[2].complete(_success());
    await _drain();
    expect(adapter.calls.length, 4);
    adapter.calls[3].complete(_success());
    await _drain();
    expect(adapter.calls.length, 5);
    adapter.calls[4].complete(_success());
    await _drain();
    expect(coordinator.activeCount, 0);
    await coordinator.close();
    await store.close();
  });

  test('UT-054/057 pause blocks later dispatch; cancelled intent waits for actual adapter settlement', () async {
    final store = _Store(2);
    final adapter = _Adapter();
    final coordinator = UploadCoordinator(
      initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
      store,
      adapters: [adapter],
      concurrency: 1,
    );
    await coordinator.setNetworkAllowed(true);
    await _drain();
    await coordinator.pauseBatch('batch', true);
    await coordinator.cancelItems(['item-0']);
    expect(adapter.calls.single.cancel.isCancelled, isTrue);
    expect(store.released, isEmpty);
    expect(coordinator.activeCount, 1);
    adapter.calls.single.complete(_success());
    await _drain();
    expect(store.released, ['item-0']);
    expect(store.states['item-0'], PublishState.cancelled);
    expect(store.lateConfirmations, ['item-0']);
    expect(adapter.calls.length, 1);
    await coordinator.pauseBatch('batch', false);
    await _drain();
    expect(adapter.calls.length, 2);
    adapter.calls.last.complete(_success());
    await _drain();
    await coordinator.close();
    await store.close();
  });

  test('UT-054 single pause leaves active IO running and later ready items dispatch', () async {
    final store = _Store(3);
    final adapter = _Adapter();
    final coordinator = UploadCoordinator(
      initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
      store,
      adapters: [adapter],
      concurrency: 1,
    );
    await coordinator.setNetworkAllowed(true);
    await _drain();
    await coordinator.pauseItem('item-1', true);
    await coordinator.pauseItem('item-1', true);
    expect(adapter.calls.single.cancel.isCancelled, isFalse);
    expect(store.states['item-1'], PublishState.paused);
    expect(store.attempts['item-1'], isNull);
    adapter.calls.single.complete(_success());
    await _drain();
    expect(store.states['item-0'], PublishState.succeeded);
    expect(store.states['item-2'], PublishState.running);
    expect(store.attempts['item-1'], isNull);
    expect(adapter.calls, hasLength(2));
    adapter.calls.last.complete(_success());
    await _drain();
    await coordinator.pauseItem('item-1', false);
    await _drain();
    expect(adapter.calls, hasLength(3));
    expect(store.attempts['item-1'], 1);
    adapter.calls.last.complete(_success());
    await _drain();
    await coordinator.close();
    await store.close();
  });

  for (final itemFirst in [true, false]) {
    test(
      'UT-054 batch and single pause stay independent; itemFirst=$itemFirst',
      () async {
        final store = _Store(1);
        final adapter = _Adapter();
        final coordinator = UploadCoordinator(
          initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
          store,
          adapters: [adapter],
        );
        if (itemFirst) {
          await coordinator.pauseItem('item-0', true);
          await coordinator.pauseBatch('batch', true);
          await coordinator.pauseBatch('batch', false);
          expect(store.userPaused['item-0'], isTrue);
          expect(store.states['item-0'], PublishState.paused);
          await coordinator.setNetworkAllowed(true);
          await _drain();
          expect(adapter.calls, isEmpty);
          await coordinator.pauseItem('item-0', false);
        } else {
          await coordinator.pauseBatch('batch', true);
          await coordinator.pauseItem('item-0', true);
          await coordinator.pauseItem('item-0', false);
          expect(store.userPaused['item-0'], isFalse);
          expect(store.states['item-0'], PublishState.paused);
          await coordinator.setNetworkAllowed(true);
          await _drain();
          expect(adapter.calls, isEmpty);
          await coordinator.pauseBatch('batch', false);
        }
        await _drain();
        expect(adapter.calls, hasLength(1));
        expect(store.attempts['item-0'], 1);
        adapter.calls.single.complete(_success());
        await _drain();
        await coordinator.close();
        await store.close();
      },
    );
  }

  for (final resumeAt in [9, 12]) {
    test(
      'UT-054/061 paused retry preserves Retry-After deadline; resumeAt=$resumeAt',
      () async {
        final store = _Store(1);
        final adapter = _Adapter();
        final time = _Time();
        final coordinator = UploadCoordinator(
          initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
          store,
          adapters: [adapter],
          time: time,
        );
        await coordinator.setNetworkAllowed(true);
        await _drain();
        adapter.calls.single.complete(
          const ProviderUploadFailure(
            UploadFailureKind.rateLimited,
            UploadDeliveryEvidence.confirmedRejected,
            retryAfterSeconds: 10,
          ),
        );
        await _drain();
        expect(store.delays['item-0'], const Duration(seconds: 10));
        await coordinator.pauseItem('item-0', true);
        final wakeCount = store.wakeRequests.length;
        time.utc = time.utc.add(const Duration(days: 365));
        time.elapsed = const Duration(seconds: 2);
        await coordinator.refresh();
        await coordinator.resumeWaiting();
        await coordinator.setNetworkAllowed(false);
        await coordinator.setNetworkAllowed(true);
        await coordinator.pauseItem('item-0', true);
        time.utc = time.utc.subtract(const Duration(days: 730));
        time.elapsed = Duration(seconds: resumeAt);
        await coordinator.refresh();
        await coordinator.resumeWaiting();
        await _drain();
        expect(store.wakeRequests, hasLength(wakeCount));
        expect(store.attempts['item-0'], 1);
        expect(adapter.calls, hasLength(1));
        expect(store.states['item-0'], PublishState.paused);
        await coordinator.pauseItem('item-0', false);
        await _drain();
        if (resumeAt < 10) {
          expect(adapter.calls, hasLength(1));
          expect(store.states['item-0'], PublishState.waiting);
          await coordinator.pauseItem('item-0', false);
          await coordinator.resumeWaiting();
          await coordinator.refresh();
          expect(store.attempts['item-0'], 1);
          time.elapsed = const Duration(seconds: 10);
          await coordinator.refresh();
          await _drain();
        }
        expect(adapter.calls, hasLength(2));
        expect(store.attempts['item-0'], 2);
        expect(adapter.calls.last.cancel.isCancelled, isFalse);
        adapter.calls.last.complete(_success());
        await _drain();
        await coordinator.close();
        await store.close();
      },
    );
  }

  test('UT-054 repeated pause/resume and account wake do not dispatch paused items twice', () async {
    final store = _Store(2);
    store.states['item-0'] = PublishState.interrupted;
    store.states['item-1'] = PublishState.waiting;
    store.waitReasons['item-1'] = QueueWaitReason.authorization;
    final adapter = _Adapter();
    final coordinator = UploadCoordinator(
      initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
      store,
      adapters: [adapter],
    );
    for (final id in store.states.keys) {
      await coordinator.pauseItem(id, true);
      await coordinator.pauseItem(id, true);
    }
    await coordinator.setNetworkAllowed(true);
    store.accountController.add('target');
    await coordinator.resumeWaiting();
    await coordinator.refresh();
    await _drain();
    expect(adapter.calls, isEmpty);
    expect(store.wakeRequests, isEmpty);
    await coordinator.setNetworkAllowed(false);
    for (final id in store.states.keys) {
      await coordinator.pauseItem(id, false);
      await coordinator.pauseItem(id, false);
    }
    await coordinator.setNetworkAllowed(true);
    await coordinator.refresh();
    await coordinator.resumeWaiting();
    await _drain();
    expect(adapter.calls, hasLength(2));
    expect(store.attempts.values, everyElement(1));
    expect(adapter.calls.every((call) => !call.cancel.isCancelled), isTrue);
    for (final call in adapter.calls) {
      call.complete(_success());
    }
    await _drain();
    await coordinator.close();
    await store.close();
  });

  test(
    'UT-054 running/unknown/terminal cannot be paused or resumed into queued',
    () async {
      final store = _Store(1);
      final adapter = _Adapter();
      final coordinator = UploadCoordinator(
        initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
        store,
        adapters: [adapter],
      );
      await coordinator.setNetworkAllowed(true);
      await _drain();
      for (final value in [true, false]) {
        await expectLater(
          coordinator.pauseItem('item-0', value),
          throwsA(isA<UploadQueueFailure>()),
        );
      }
      expect(adapter.calls.single.cancel.isCancelled, isFalse);
      expect(store.states['item-0'], PublishState.running);
      adapter.calls.single.complete(
        const ProviderUploadUnknown(UploadFailureKind.timeout),
      );
      await _drain();
      for (final state in [
        PublishState.unknown,
        PublishState.succeeded,
        PublishState.failed,
        PublishState.cancelled,
      ]) {
        store.states['item-0'] = state;
        for (final value in [true, false]) {
          await expectLater(
            coordinator.pauseItem('item-0', value),
            throwsA(isA<UploadQueueFailure>()),
          );
        }
        await store.wake('item-0');
        await store.setWaiting('item-0', QueueWaitReason.network);
        await coordinator.resumeWaiting();
        await coordinator.refresh();
        expect(store.states['item-0'], state);
      }
      expect(adapter.calls, hasLength(1));
      expect(store.attempts['item-0'], 1);
      await coordinator.close();
      await store.close();
    },
  );

  test('UT-059/061/067 retry waits monotonic 2/4/8; UTC jumps and repeated wake do not accelerate', () async {
    final store = _Store(1);
    final adapter = _Adapter();
    final time = _Time();
    final coordinator = UploadCoordinator(
      initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
      store,
      adapters: [adapter],
      time: time,
    );
    await coordinator.setNetworkAllowed(true);
    await _drain();
    for (final seconds in [2, 4, 8]) {
      adapter.calls.last.complete(
        const ProviderUploadFailure(
          UploadFailureKind.rateLimited,
          UploadDeliveryEvidence.confirmedRejected,
        ),
      );
      await _drain();
      final count = adapter.calls.length;
      time.utc = time.utc.add(const Duration(days: 365));
      await coordinator.refresh();
      await coordinator.resumeWaiting();
      await _drain();
      expect(adapter.calls.length, count);
      time.elapsed += Duration(seconds: seconds - 1);
      await coordinator.refresh();
      await _drain();
      expect(adapter.calls.length, count);
      time.elapsed += const Duration(seconds: 1);
      await coordinator.refresh();
      await _drain();
      expect(adapter.calls.length, count + 1);
    }
    adapter.calls.last.complete(
      const ProviderUploadFailure(
        UploadFailureKind.rateLimited,
        UploadDeliveryEvidence.confirmedRejected,
      ),
    );
    await _drain();
    expect(adapter.calls.length, 4);
    expect(store.states['item-0'], PublishState.failed);
    await coordinator.close();
    await store.close();
  });

  test('UT-060/062 unknown never wakes into another request', () async {
    final store = _Store(1);
    final adapter = _Adapter();
    final coordinator = UploadCoordinator(
      initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
      store,
      adapters: [adapter],
    );
    await coordinator.setNetworkAllowed(true);
    await _drain();
    adapter.calls.single.complete(
      const ProviderUploadUnknown(UploadFailureKind.timeout),
    );
    await _drain();
    await coordinator.resumeWaiting();
    await coordinator.refresh();
    await coordinator.setNetworkAllowed(false);
    await coordinator.setNetworkAllowed(true);
    await _drain();
    expect(adapter.calls.length, 1);
    expect(store.states['item-0'], PublishState.unknown);
    await coordinator.close();
    await store.close();
  });

  test('UT-047/063 unverified service limit blocks before any attempt or file lease', () async {
    final store = _Store(1);
    final adapter = _Adapter(verified: false);
    final coordinator = UploadCoordinator(
      initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
      store,
      adapters: [adapter],
    );
    await coordinator.setNetworkAllowed(true);
    await _drain();
    expect(adapter.calls, isEmpty);
    expect(store.attempts, isEmpty);
    expect(store.waitReasons['item-0'], QueueWaitReason.capabilityUnknown);
    await coordinator.close();
    await store.close();
  });

  test('UT-043/063 account mutation stops old authorization; last gate prevents request', () async {
    final store = _Store(1)..authorizationGate = Completer<bool>();
    final adapter = _Adapter();
    final coordinator = UploadCoordinator(
      initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
      store,
      adapters: [adapter],
    );
    await coordinator.setNetworkAllowed(true);
    await _drain();
    store.accountController.add('target');
    await _drain();
    store.authorizationGate!.complete(false);
    await _drain();
    expect(adapter.calls, isEmpty);
    expect(store.released, ['item-0']);
    expect(store.waitReasons['item-0'], QueueWaitReason.authorization);
    await coordinator.close();
    await store.close();
  });

  test('UT-068 real watchdog ignores duplicate bytes, stops at 120 seconds without activity', () async {
    final store = _Store(1);
    final adapter = _Adapter();
    final time = _Time();
    final coordinator = UploadCoordinator(
      initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
      store,
      adapters: [adapter],
      time: time,
      watchdogInterval: const Duration(milliseconds: 5),
    );
    await coordinator.setNetworkAllowed(true);
    await _drain();
    final call = adapter.calls.single;
    call.activity(
      const UploadActivity(UploadActivityDirection.sending, 10, 100),
    );
    time.elapsed = const Duration(seconds: 119);
    call.activity(
      const UploadActivity(UploadActivityDirection.sending, 10, 100),
    );
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(call.cancel.isCancelled, isFalse);
    time.elapsed = const Duration(seconds: 120);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(call.cancel.isCancelled, isTrue);
    expect(store.released, isEmpty);
    call.complete(
      const ProviderUploadCancelled(UploadDeliveryEvidence.uncertain),
    );
    await _drain();
    expect(store.states['item-0'], PublishState.unknown);
    expect(store.accumulated, const Duration(seconds: 120));
    await coordinator.close();
    await store.close();
  });

  test('UT-102 graceful close waits for real IO, preserves unknown rather than cancelled', () async {
    final store = _Store(1);
    final adapter = _Adapter();
    final coordinator = UploadCoordinator(
      initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
      store,
      adapters: [adapter],
    );
    await coordinator.setNetworkAllowed(true);
    await _drain();
    var closed = false;
    final close = coordinator.close().then((_) => closed = true);
    await _drain();
    for (final value in [true, false]) {
      await expectLater(
        coordinator.pauseItem('item-0', value),
        throwsA(isA<UploadQueueFailure>()),
      );
      await expectLater(
        coordinator.pauseBatch('batch', value),
        throwsA(isA<UploadQueueFailure>()),
      );
    }
    expect(adapter.calls.single.cancel.isCancelled, isTrue);
    expect(closed, isFalse);
    expect(store.released, isEmpty);
    adapter.calls.single.complete(
      const ProviderUploadCancelled(UploadDeliveryEvidence.uncertain),
    );
    await close;
    expect(store.states['item-0'], PublishState.unknown);
    expect(store.released, ['item-0']);
    for (final value in [true, false]) {
      await expectLater(
        coordinator.pauseItem('item-0', value),
        throwsA(isA<UploadQueueFailure>()),
      );
      await expectLater(
        coordinator.pauseBatch('batch', value),
        throwsA(isA<UploadQueueFailure>()),
      );
    }
    await store.close();
  });

  test('UT-079 partial: restore hold waits for actual IO and result commit before release', () async {
    final store = _Store(2)..finishGate = Completer<void>();
    final adapter = _Adapter();
    final coordinator = UploadCoordinator(
      initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
      store,
      adapters: [adapter],
      concurrency: 1,
    );
    await coordinator.setNetworkAllowed(true);
    await _drain();
    await coordinator.pauseItem('item-1', true);
    var ready = false;
    final holding = coordinator.holdForRestore().then((hold) {
      ready = true;
      return hold;
    });
    await _drain();
    expect(coordinator.restoreBlocked, isTrue);
    expect(store.paused, isTrue);
    expect(ready, isFalse);
    expect(store.released, isEmpty);
    expect(adapter.calls.single.cancel.isCancelled, isTrue);
    await coordinator.setNetworkAllowed(true);
    await coordinator.refresh();
    await coordinator.resumeWaiting();
    expect(adapter.calls, hasLength(1));
    expect(coordinator.networkAllowed, isFalse);
    await expectLater(
      coordinator.pauseBatch('batch', false),
      throwsA(isA<UploadQueueFailure>()),
    );
    await expectLater(
      coordinator.pauseItem('item-1', false),
      throwsA(isA<UploadQueueFailure>()),
    );
    expect(store.userPaused['item-1'], isTrue);
    adapter.calls.single.complete(
      const ProviderUploadCancelled(UploadDeliveryEvidence.uncertain),
    );
    await _drain();
    expect(ready, isFalse);
    expect(store.released, isEmpty);
    store.finishGate!.complete();
    final hold = await holding;
    expect(store.released, ['item-0']);
    expect(coordinator.activeCount, 0);
    expect(store.states['item-0'], PublishState.unknown);
    hold.release();
    hold.release();
    await _drain();
    expect(coordinator.restoreBlocked, isFalse);
    expect(store.paused, isTrue);
    expect(store.userPaused['item-1'], isTrue);
    expect(coordinator.networkAllowed, isFalse);
    expect(adapter.calls, hasLength(1));
    await coordinator.close();
    await store.close();
  });

  test(
    'UT-079 partial: dispatch being prepared cannot send after restore barrier',
    () async {
      final store = _Store(1)..beginGate = Completer<void>();
      final adapter = _Adapter();
      final coordinator = UploadCoordinator(
        initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
        store,
        adapters: [adapter],
      );
      final enabling = coordinator.setNetworkAllowed(true);
      await _drain();
      expect(store.attempts.length, 1);
      var ready = false;
      final holding = coordinator.holdForRestore().then((hold) {
        ready = true;
        return hold;
      });
      await _drain();
      expect(ready, isFalse);
      expect(adapter.calls, isEmpty);
      store.beginGate!.complete();
      final hold = await holding;
      await enabling;
      expect(adapter.calls, isEmpty);
      expect(store.released, ['item-0']);
      expect(store.paused, isTrue);
      hold.release();
      await coordinator.close();
      await store.close();
    },
  );

  test('UT-079 partial: pause persistence failure stays blocked and can be retried', () async {
    final store = _Store(1)..failPauseOnce = true;
    final coordinator = UploadCoordinator(
      initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
      store,
      adapters: [_Adapter()],
    );
    await expectLater(
      coordinator.holdForRestore(),
      throwsA(isA<UploadQueueFailure>()),
    );
    expect(coordinator.restoreBlocked, isTrue);
    await coordinator.setNetworkAllowed(true);
    expect(coordinator.networkAllowed, isFalse);
    final hold = await coordinator.holdForRestore();
    await expectLater(
      coordinator.holdForRestore(),
      throwsA(isA<UploadQueueFailure>()),
    );
    expect(store.paused, isTrue);
    hold.release();
    await coordinator.close();
    await store.close();
  });

  test(
    'UT-079 partial: unconfirmed cleanup cannot produce a restore hold',
    () async {
      final store = _Store(1);
      final adapter = _Adapter();
      final coordinator = UploadCoordinator(
        initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
        store,
        adapters: [adapter],
      );
      await coordinator.setNetworkAllowed(true);
      await _drain();
      final holding = coordinator.holdForRestore();
      final assertion = expectLater(
        holding,
        throwsA(isA<UploadQueueFailure>()),
      );
      adapter.calls.single.result.completeError(
        const ProviderCleanupException(),
      );
      await assertion;
      expect(coordinator.restoreBlocked, isTrue);
      expect(coordinator.hasUnsettledIO, isTrue);
      expect(store.released, isEmpty);
      await expectLater(
        coordinator.close(),
        throwsA(isA<UploadQueueFailure>()),
      );
      await store.close();
    },
  );
}

Future<void> _drain() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ProviderUploadSuccess _success() => ProviderUploadSuccess(
  service: ImageHostService.catbox,
  remoteId: 'fixture',
  directUrl: Uri.parse('https://files.catbox.moe/fixture.png'),
);

class _Time implements TimeSource {
  DateTime utc = DateTime.utc(2026);
  Duration elapsed = Duration.zero;
  @override
  DateTime get utcNow => utc;
  @override
  Duration get monotonic => elapsed;
}

class _Call {
  _Call(this.cancel, this.activity);
  final CancelToken cancel;
  final UploadActivityCallback activity;
  final Completer<ProviderUploadResult> result = Completer();
  void complete(ProviderUploadResult value) => result.complete(value);
}

class _Adapter implements ProviderAdapter {
  _Adapter({this.verified = true});
  final bool verified;
  final List<_Call> calls = [];
  @override
  ImageHostService get service => ImageHostService.catbox;
  @override
  ProviderUploadLimits get limits => verified
      ? ProviderUploadLimits(maximumBytes: 1000, formats: {'PNG'})
      : const ProviderUploadLimits.unknown();
  @override
  Future<ProviderUploadResult> upload({
    required File file,
    required String actualFormat,
    required int expectedBytes,
    required ResolvedTarget target,
    required CancelToken cancelToken,
    UploadActivityCallback? onActivity,
  }) {
    final call = _Call(cancelToken, onActivity ?? (_) {});
    calls.add(call);
    return call.result.future;
  }
}

/// An in-memory scheduling port, not the production queue. Separate repository
/// tests exercise actual transactions, file protections and restart recovery.
class _Store implements UploadQueueStore {
  _Store(int count) {
    for (var i = 0; i < count; i++) {
      states['item-$i'] = PublishState.queued;
    }
  }
  final states = <String, PublishState>{};
  final waitReasons = <String, QueueWaitReason>{};
  final delays = <String, Duration>{};
  final userPaused = <String, bool>{};
  final wakeRequests = <String>[];
  final attempts = <String, int>{};
  final released = <String>[];
  final lateConfirmations = <String>[];
  final controller = StreamController<void>.broadcast();
  final accountController = StreamController<String>.broadcast();
  Completer<bool>? authorizationGate;
  Completer<void>? beginGate, finishGate;
  bool failPauseOnce = false;
  Duration accumulated = Duration.zero;
  bool paused = false;
  @override
  Stream<void> get changes => controller.stream;
  @override
  Stream<String> get accountChanges => accountController.stream;
  void changed() => controller.add(null);
  UploadPublication item(String id) => UploadPublication(
    id: id,
    batchId: 'batch',
    position: states.keys.toList().indexOf(id),
    input: FrozenUploadInput(
      kind: UploadInputKind.original,
      referenceId: id,
      displayName: id,
      version: const ImageVersion(
        id: 'v',
        sha256: 'digest',
        byteCount: 20,
        format: 'PNG',
        width: 1,
        height: 1,
        frameCount: 1,
        orientation: 1,
      ),
      policyKey: 'original-confirmed-v1',
    ),
    target: const TargetSnapshot(
      'target',
      ImageHostService.catbox,
      'fixture',
      false,
    ),
    state: states[id]!,
    attemptCount: attempts[id] ?? 0,
    generation: attempts[id] ?? 0,
    accumulatedRunning: accumulated,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    userPaused: userPaused[id] ?? false,
    waitReason: waitReasons[id],
    retryDelay: delays[id],
  );
  @override
  Future<List<UploadBatch>> listBatches() async => [
    UploadBatch(
      id: 'batch',
      intentId: 'intent',
      createdAt: DateTime.utc(2026),
      paused: paused,
      items: states.keys.map(item),
    ),
  ];
  @override
  Future<void> setWaiting(String id, QueueWaitReason reason) async {
    if (paused ||
        (userPaused[id] ?? false) ||
        !{
          PublishState.queued,
          PublishState.waiting,
          PublishState.interrupted,
        }.contains(states[id])) {
      return;
    }
    states[id] = PublishState.waiting;
    waitReasons[id] = reason;
    changed();
  }

  @override
  Future<void> wake(String id) async {
    wakeRequests.add(id);
    if (paused || (userPaused[id] ?? false)) return;
    if (states[id] == PublishState.waiting ||
        states[id] == PublishState.interrupted) {
      states[id] = PublishState.queued;
      waitReasons.remove(id);
      delays.remove(id);
      changed();
    }
  }

  @override
  Future<UploadExecution?> begin(
    String id, {
    required bool Function() mayDispatch,
  }) async {
    if (states[id] != PublishState.queued ||
        paused ||
        (userPaused[id] ?? false) ||
        !mayDispatch()) {
      return null;
    }
    attempts[id] = (attempts[id] ?? 0) + 1;
    states[id] = PublishState.running;
    changed();
    await beginGate?.future;
    return UploadExecution(
      item: item(id),
      attemptId: '$id-${attempts[id]}',
      generation: attempts[id]!,
      target: await resolveTarget('target'),
      file: File('fixture.png'),
      release: () async => released.add(id),
    );
  }

  @override
  Future<bool> authorize(String id) async =>
      authorizationGate == null ? true : await authorizationGate!.future;
  @override
  Future<void> checkpoint(String id, Duration accumulatedRunning) async {}
  @override
  Future<void> finish(
    UploadExecution execution,
    ProviderUploadResult result, {
    required Duration accumulatedRunning,
    Duration? retryDelay,
    bool interrupted = false,
  }) async {
    await finishGate?.future;
    final id = execution.item.id;
    accumulated = accumulatedRunning;
    if (states[id] == PublishState.cancelled) {
      if (result is ProviderUploadSuccess) lateConfirmations.add(id);
    } else if (result is ProviderUploadSuccess) {
      states[id] = PublishState.succeeded;
    } else if (result is ProviderUploadUnknown ||
        result is ProviderUploadCancelled &&
            result.evidence == UploadDeliveryEvidence.uncertain) {
      states[id] = PublishState.unknown;
    } else if (result is ProviderUploadFailure &&
        result.kind == UploadFailureKind.targetUnavailable) {
      states[id] = PublishState.waiting;
      waitReasons[id] = QueueWaitReason.authorization;
    } else if (retryDelay != null) {
      states[id] = PublishState.waiting;
      waitReasons[id] = QueueWaitReason.retry;
      delays[id] = retryDelay;
    } else if (interrupted) {
      states[id] = PublishState.interrupted;
    } else {
      states[id] = PublishState.failed;
    }
    changed();
  }

  @override
  Future<void> cancel(Iterable<String> ids) async {
    for (final id in ids) {
      if (!states[id]!.terminal) states[id] = PublishState.cancelled;
    }
    changed();
  }

  @override
  Future<void> pauseBatch(String id, bool value) async {
    if (failPauseOnce) {
      failPauseOnce = false;
      throw StateError('controlled persistence failure');
    }
    paused = value;
    for (final id in states.keys) {
      if (value &&
          {
            PublishState.queued,
            PublishState.waiting,
            PublishState.interrupted,
          }.contains(states[id])) {
        states[id] = PublishState.paused;
      } else if (!value &&
          !(userPaused[id] ?? false) &&
          states[id] == PublishState.paused) {
        states[id] = waitReasons[id] == null
            ? PublishState.queued
            : PublishState.waiting;
      }
    }
    changed();
  }

  @override
  Future<void> pauseItem(String id, bool value) async {
    if (!{
      PublishState.queued,
      PublishState.waiting,
      PublishState.paused,
      PublishState.interrupted,
    }.contains(states[id])) {
      throw const UploadQueueFailure('仅未运行的上传项可以暂停或继续。');
    }
    if ((userPaused[id] ?? false) == value) return;
    userPaused[id] = value;
    states[id] = value || paused
        ? PublishState.paused
        : waitReasons[id] == null
        ? PublishState.queued
        : PublishState.waiting;
    changed();
  }

  @override
  Future<ResolvedTarget> resolveTarget(String id) async => const ResolvedTarget(
    ProviderTarget(
      id: 'target',
      service: ImageHostService.catbox,
      alias: 'fixture',
      enabled: true,
      selectedByDefault: true,
      anonymous: false,
      health: AccountHealth.unverified,
      removed: false,
      generation: 1,
    ),
    'SyntheticCoordinatorAccountCredential',
  );
  Future<void> close() async {
    await controller.close();
    await accountController.close();
  }
}
