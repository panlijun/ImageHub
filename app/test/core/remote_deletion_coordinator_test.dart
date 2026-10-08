import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/links/application/remote_deletion_coordinator.dart';
import 'package:imagehost/features/links/data/remote_deletion_gateway.dart';
import 'package:imagehost/features/links/domain/remote_deletion.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';
import 'package:path/path.dart' as p;

import 'remote_deletion_repository_test.dart' show RemoteDeletionFixture;

const _unconfirmed200 = RemoteDeletionOutcome(
  RemoteDeletionState.unknown,
  RemoteDeletionReason.unconfirmed,
  httpStatus: 200,
);

class _Gateway implements RemoteDeletionGateway {
  final entered = Completer<void>();
  final actualExit = Completer<void>();
  int calls = 0;
  bool held = false;
  CancelToken? token;
  CatboxDeletionRequest? request;
  Object? failure;
  RemoteDeletionOutcome outcome = _unconfirmed200;
  @override
  Future<RemoteDeletionOutcome> delete({
    required CatboxDeletionRequest request,
    required CancelToken cancelToken,
  }) async {
    calls++;
    this.request = request;
    token = cancelToken;
    entered.complete();
    if (held) await actualExit.future;
    if (failure != null) throw failure!;
    return outcome;
  }
}

class _UnsafeFailure {
  int strings = 0;
  @override
  String toString() {
    strings++;
    return RemoteDeletionFixture.credential;
  }
}

void main() {
  late RemoteDeletionFixture f;
  setUp(() async {
    f = RemoteDeletionFixture();
    await f.open();
  });
  tearDown(() => f.dispose());

  test('UT-050 construction preparation read cancel and reopen never dispatch automatically', () async {
    final id = await f.result();
    final gateway = _Gateway();
    final actor = RemoteDeletionCoordinator(f.repository, gateway);
    await f.repository.prepareRemoteDeletion(id);
    await f.repository.listRemoteDeletions();
    actor.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(gateway.calls, 0);
    expect(actor.busy, false);
    await actor.close();
    await f.reopen();
    final reopened = RemoteDeletionCoordinator(f.repository, gateway);
    await f.repository.listUploadResults();
    await Future<void>.delayed(Duration.zero);
    expect(gateway.calls, 0);
    expect(f.auditRows(), isEmpty);
    await reopened.close();
  });

  test('UT-050 each independent confirmation missing rejects before audit and request', () async {
    final id = await f.result(),
        plan = await f.repository.prepareRemoteDeletion(id);
    final gateway = _Gateway();
    final tested = RemoteDeletionCoordinator(f.repository, gateway);
    for (final confirm in [(false, true), (true, false), (false, false)]) {
      await expectLater(
        tested.run(
          plan,
          confirmNetwork: confirm.$1,
          confirmRemoteDeletion: confirm.$2,
        ),
        throwsA(isA<UploadQueueFailure>()),
      );
    }
    expect(gateway.calls, 0);
    expect(f.auditRows(), isEmpty);
    await tested.close();
  });

  test('UT-050 one explicit run persists sending before gateway and exposes busy transitions', () async {
    final id = await f.result(),
        plan = await f.repository.prepareRemoteDeletion(id);
    final gateway = _Gateway()..held = true;
    final actor = RemoteDeletionCoordinator(f.repository, gateway);
    final changes = <bool>[];
    final subscription = actor.changes.listen((_) => changes.add(actor.busy));
    final running = actor.run(
      plan,
      confirmNetwork: true,
      confirmRemoteDeletion: true,
    );
    await gateway.entered.future;
    expect(actor.busy, true);
    expect(
      (await f.repository.listRemoteDeletions()).single.state,
      RemoteDeletionState.sending,
    );
    expect(gateway.request!.userhash, RemoteDeletionFixture.credential);
    await expectLater(
      actor.run(plan, confirmNetwork: true, confirmRemoteDeletion: true),
      throwsA(isA<UploadQueueFailure>()),
    );
    expect(gateway.calls, 1);
    gateway.actualExit.complete();
    expect((await running).state, RemoteDeletionState.unknown);
    await Future<void>.delayed(Duration.zero);
    expect(actor.busy, false);
    expect(changes, containsAllInOrder([true, false]));
    await subscription.cancel();
    await actor.close();
    await expectLater(
      actor.run(plan, confirmNetwork: true, confirmRemoteDeletion: true),
      throwsA(isA<UploadQueueFailure>()),
    );
    expect(gateway.calls, 1);
  });

  test('UT-050 cancellation cannot complete actor before actual gateway exit or mark late 200 deleted', () async {
    final id = await f.result(),
        plan = await f.repository.prepareRemoteDeletion(id);
    final gateway = _Gateway()..held = true;
    final actor = RemoteDeletionCoordinator(f.repository, gateway);
    var done = false;
    final running = actor
        .run(plan, confirmNetwork: true, confirmRemoteDeletion: true)
        .then((record) {
          done = true;
          return record;
        });
    await gateway.entered.future;
    actor.cancel();
    await gateway.token!.whenCancel;
    await Future<void>.delayed(Duration.zero);
    expect(done, false);
    expect(actor.busy, true);
    expect(
      (await f.repository.listRemoteDeletions()).single.state,
      RemoteDeletionState.sending,
    );
    gateway.actualExit.complete();
    expect((await running).state, RemoteDeletionState.unknown);
    expect((await f.repository.listUploadResults()).single.id, id);
    await actor.close();
    await f.reopen();
    final next = RemoteDeletionCoordinator(f.repository, gateway);
    await Future<void>.delayed(Duration.zero);
    expect(gateway.calls, 1, reason: 'unknown audit never retries on reopen');
    await next.close();
  });

  test('UT-050 account authorization change cancels the owned request and still waits real IO', () async {
    final id = await f.result(),
        plan = await f.repository.prepareRemoteDeletion(id);
    final gateway = _Gateway()..held = true;
    final actor = RemoteDeletionCoordinator(f.repository, gateway);
    var finished = false;
    final running = actor
        .run(plan, confirmNetwork: true, confirmRemoteDeletion: true)
        .then((record) {
          finished = true;
          return record;
        });
    await gateway.entered.future;
    await f.repository.saveTarget(
      id: f.target,
      service: ImageHostService.catbox,
      alias: '更换授权',
      anonymous: false,
      credential: 'synthetic-new-userhash',
    );
    await gateway.token!.whenCancel;
    expect(finished, false);
    gateway.actualExit.complete();
    expect((await running).state, RemoteDeletionState.unknown);
    expect(gateway.calls, 1);
    expect((await f.repository.listUploadResults()).single.target.id, f.target);
    await actor.close();
  });

  test('UT-050 unrelated account change does not cancel the original target request', () async {
    final id = await f.result(),
        plan = await f.repository.prepareRemoteDeletion(id);
    final gateway = _Gateway()..held = true;
    final actor = RemoteDeletionCoordinator(f.repository, gateway);
    final running = actor.run(
      plan,
      confirmNetwork: true,
      confirmRemoteDeletion: true,
    );
    await gateway.entered.future;
    await f.repository.saveTarget(
      service: ImageHostService.catbox,
      alias: '其他账号',
      anonymous: false,
      credential: 'synthetic-other-userhash',
    );
    await Future<void>.delayed(Duration.zero);
    expect(gateway.token!.isCancelled, false);
    gateway.actualExit.complete();
    await running;
    await actor.close();
  });

  test(
    'UT-050 actor close and repository close both wait real gateway completion',
    () async {
      final id = await f.result(),
          plan = await f.repository.prepareRemoteDeletion(id);
      final gateway = _Gateway()..held = true;
      final actor = RemoteDeletionCoordinator(f.repository, gateway);
      final running = actor.run(
        plan,
        confirmNetwork: true,
        confirmRemoteDeletion: true,
      );
      await gateway.entered.future;
      var actorClosed = false, libraryClosed = false;
      final closingActor = actor.close().then((_) => actorClosed = true);
      final closingLibrary = f.repository.close().then(
        (_) => libraryClosed = true,
      );
      await gateway.token!.whenCancel;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(actorClosed, false);
      expect(libraryClosed, false);
      gateway.actualExit.complete();
      await running;
      await closingActor;
      await closingLibrary;
      await f.reopen();
      expect(
        (await f.repository.listRemoteDeletions()).single.state,
        RemoteDeletionState.unknown,
      );
      expect(gateway.calls, 1);
    },
  );

  test(
    'UT-050 foreign plan and expired actor owner reject before gateway',
    () async {
      final id = await f.result(),
          plan = await f.repository.prepareRemoteDeletion(id);
      final gateway = _Gateway();
      final other = await LibraryRepository.open(
        Directory(p.join(f.sandbox.path, 'other-actor')),
        secretStore: f.secrets,
      );
      final foreign = RemoteDeletionCoordinator(other, gateway);
      try {
        await expectLater(
          foreign.run(plan, confirmNetwork: true, confirmRemoteDeletion: true),
          throwsA(isA<UploadQueueFailure>()),
        );
        expect(await other.listRemoteDeletions(), isEmpty);
      } finally {
        await foreign.close();
        await other.close();
      }
      final stale = RemoteDeletionCoordinator(f.repository, gateway);
      await f.reopen();
      final freshPlan = await f.repository.prepareRemoteDeletion(id);
      await expectLater(
        stale.run(freshPlan, confirmNetwork: true, confirmRemoteDeletion: true),
        throwsA(isA<UploadQueueFailure>()),
      );
      expect(gateway.calls, 0);
      expect(f.auditRows(), isEmpty);
      await stale.close();
    },
  );

  test('UT-050 generic gateway exception stays unknown without stringifying protected objects or retry', () async {
    final id = await f.result(),
        plan = await f.repository.prepareRemoteDeletion(id);
    final unsafe = _UnsafeFailure(), gateway = _Gateway();
    gateway.failure = unsafe;
    final actor = RemoteDeletionCoordinator(f.repository, gateway);
    final record = await actor.run(
      plan,
      confirmNetwork: true,
      confirmRemoteDeletion: true,
    );
    expect(record.state, RemoteDeletionState.unknown);
    expect(record.reason, RemoteDeletionReason.unconfirmed);
    expect(unsafe.strings, 0);
    expect(gateway.calls, 1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(gateway.calls, 1);
    expect((await f.repository.listUploadResults()).single.id, id);
    await actor.close();
  });

  test('UT-050 invalid gateway outcome fails safely and reopen classifies retained sending evidence', () async {
    final id = await f.result(),
        plan = await f.repository.prepareRemoteDeletion(id);
    final gateway = _Gateway()
      ..outcome = const RemoteDeletionOutcome(
        RemoteDeletionState.notSent,
        RemoteDeletionReason.unconfirmed,
        httpStatus: 200,
      );
    final actor = RemoteDeletionCoordinator(f.repository, gateway);
    await expectLater(
      actor.run(plan, confirmNetwork: true, confirmRemoteDeletion: true),
      throwsA(isA<UploadQueueFailure>()),
    );
    expect(actor.busy, false);
    expect(
      (await f.repository.listRemoteDeletions()).single.state,
      RemoteDeletionState.sending,
    );
    expect((await f.repository.listUploadResults()).single.id, id);
    await actor.close();
    await f.reopen();
    expect(
      (await f.repository.listRemoteDeletions()).single.state,
      RemoteDeletionState.unknown,
    );
    expect(gateway.calls, 1);
  });
}
