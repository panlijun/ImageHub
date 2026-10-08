import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/backup/domain/backup_restore_plan.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/upload/domain/queue_policy.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';
import 'package:uuid/uuid.dart';

String id(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';
ImageVersion version(
  int n, {
  String hash = 'a',
  int width = 10,
  int frames = 2,
}) => ImageVersion(
  id: id(n),
  sha256: hash * 64,
  byteCount: 100,
  format: 'PNG',
  width: width,
  height: 20,
  frameCount: frames,
  orientation: 1,
);
BackupAsset asset(int n, int v) => BackupAsset(
  id: id(n),
  versionId: id(v),
  displayName: '本地',
  sourceType: 'selected',
  importedUtc: 100,
  updatedUtc: 200,
  favorite: false,
  tagIds: const [],
  recycled: false,
);
BackupAccount account(
  int n, {
  ImageHostService service = ImageHostService.catbox,
  String alias = '同名',
  bool anonymous = false,
}) => BackupAccount(
  id: id(n),
  service: service,
  alias: alias,
  anonymous: anonymous,
);
TargetSnapshot target(
  int n, {
  ImageHostService service = ImageHostService.catbox,
  String alias = '历史别名',
  bool anonymous = false,
}) => TargetSnapshot(id(n), service, alias, anonymous);
FrozenUploadInput input(int ref, ImageVersion v, {bool processed = false}) =>
    FrozenUploadInput(
      kind: processed ? UploadInputKind.processed : UploadInputKind.original,
      referenceId: id(ref),
      displayName: '历史名称',
      version: v,
      policyKey: 'policy',
      processingSummary: '只读处理描述',
    );
BackupRemoteResult result(
  int n,
  int attempt,
  FrozenUploadInput i, {
  TargetSnapshot? t,
  int confirmed = 300,
  String url = 'https://example.test/a.png',
}) => BackupRemoteResult(
  id: id(n),
  attemptId: id(attempt),
  input: i,
  target: t ?? target(40),
  remoteId: 'remote',
  directUrl: Uri.parse(url),
  confirmedUtc: confirmed,
  late: false,
);
BackupProcessingSnapshot processing(int a, ImageVersion v, {int side = 100}) =>
    BackupProcessingSnapshot(
      operation: ProcessingOperation.compress,
      inputs: [
        BackupProcessingInput(assetId: id(a), version: v, selectedFrame: 1),
      ],
      mode: ProcessingMode.fidelity,
      outputFormat: ProcessingFormat.png,
      longestSide: side,
      quality: null,
      crop: null,
      layout: StitchLayout.horizontal,
      gap: 0,
      backgroundArgb: 0xffffffff,
      backgroundConfirmed: true,
      explicitStaticConversion: true,
    );
BackupOrigin origin(int out, int v, BackupProcessingSnapshot p) => BackupOrigin(
  outputId: id(out),
  versionId: id(v),
  createdUtc: 200,
  processing: p,
);
BackupTaskHistory history(
  int n,
  FrozenUploadInput i, {
  int batch = 80,
  int position = 0,
  List<int> attempts = const [],
  TargetSnapshot? t,
  String? message,
  PublishState state = PublishState.succeeded,
}) => BackupTaskHistory(
  id: id(n),
  batchId: id(batch),
  position: position,
  input: i,
  target: t ?? target(40),
  state: state,
  attempts: attempts.indexed.map(
    (entry) => BackupAttemptHistory(
      id: id(entry.$2),
      generation: entry.$1 + 1,
      startedUtc: 200,
      endedUtc: 250,
      outcome: 'confirmed',
    ),
  ),
  createdUtc: 100,
  updatedUtc: 300,
  message: message,
);
BackupManifest manifest({
  int package = 900,
  List<ImageVersion> versions = const [],
  List<BackupAsset> assets = const [],
  List<BackupOrigin> origins = const [],
  List<BackupAccount> accounts = const [],
  List<BackupRemoteResult> results = const [],
  List<BackupTaskHistory> history = const [],
}) => BackupManifest(
  packageId: id(package),
  createdUtc: 400,
  mode: BackupMode.metadata,
  versions: versions,
  assets: assets,
  categories: const [],
  tags: const [],
  origins: origins,
  accounts: accounts,
  results: results,
  history: history,
  images: const [],
);
BackupRestorePlan merge(
  BackupManifest current,
  BackupManifest incoming, {
  Set<String> activeTasks = const {},
  Set<String> activeAttempts = const {},
}) => BackupRestorePlanner.plan(
  current: current,
  incoming: incoming,
  activeTaskIds: activeTasks,
  activeAttemptIds: activeAttempts,
);

void main() {
  group('UT-076/077/078/081 partial + DAT-003 relation restore proposal', () {
    test('active batch positions reject incoming historical rows', () {
      final incoming = manifest(history: [history(70, input(10, version(1)))]);
      final plan = BackupRestorePlanner.plan(
        current: manifest(),
        incoming: incoming,
        activePositions: {
          jsonEncode([id(80), 0]),
        },
      );
      expect(plan.canCommit, isTrue);
      expect(plan.metadata!.history, isEmpty);
      expect(
        plan.relationIssues.single.kind,
        BackupRestoreIssueKind.batchPositionConflict,
      );
      expect(plan.relationIssues.single.targetId, id(80));
    });
    test('same content different IDs remap origin and result accurately', () {
      final current = manifest(versions: [version(1)], assets: [asset(10, 1)]);
      final incoming = manifest(
        versions: [version(2)],
        assets: [asset(11, 2)],
        origins: [origin(30, 2, processing(11, version(2)))],
        results: [result(50, 60, input(30, version(2), processed: true))],
      );
      final plan = merge(current, incoming);
      final metadata = plan.metadata!;
      expect(plan.canCommit, isTrue);
      expect(plan.versionIds[id(2)], id(1));
      expect(plan.assetIds[id(11)], id(10));
      expect(metadata.origins.single.versionId, id(1));
      expect(metadata.origins.single.processing.inputs.single.assetId, id(10));
      expect(
        metadata.origins.single.processing.inputs.single.version,
        version(1),
      );
      expect(metadata.origins.single.processing.inputs.single.selectedFrame, 1);
      expect(metadata.results.single.input.version, version(1));
      expect(metadata.results.single.input.referenceId, id(30));
      expect(metadata.mode, BackupMode.metadata);
      expect(metadata.images, isEmpty);
      expect(metadata.packageId, incoming.packageId);
      expect(metadata.createdUtc, incoming.createdUtc);
    });

    test('conflicting origin gets stable identity; replay preserves all associations', () {
      final current = manifest(
        versions: [version(1)],
        origins: [origin(30, 1, processing(10, version(1)))],
      );
      final incoming = manifest(
        versions: [version(2)],
        origins: [origin(30, 2, processing(11, version(2), side: 90))],
        results: [result(50, 60, input(30, version(2), processed: true))],
        history: [
          history(70, input(30, version(2), processed: true), attempts: [60]),
        ],
      );
      final plan = merge(current, incoming);
      final mapped = plan.outputIds[id(30)];
      expect(plan.canCommit, isTrue);
      expect(mapped, isNot(id(30)));
      expect(plan.metadata!.origins, hasLength(2));
      expect(plan.metadata!.results.single.input.referenceId, mapped);
      expect(plan.metadata!.history.single.input.referenceId, mapped);
      final replay = merge(plan.metadata!, incoming);
      expect(replay.canCommit, isTrue);
      expect(replay.outputIds[id(30)], mapped);
      expect(replay.metadata!.origins, hasLength(2));
      expect(replay.metadata!.results, hasLength(1));
      expect(replay.metadata!.history, hasLength(1));
    });

    test('historical-only versions remain audit-only and choose current permanent first', () {
      final current = manifest(
        versions: [version(1)],
        results: [result(50, 60, input(10, version(3)))],
      );
      final incoming = manifest(
        results: [result(51, 61, input(11, version(4)))],
        history: [history(70, input(99, version(5, hash: 'b')))],
      );
      final plan = merge(current, incoming);
      expect(plan.canCommit, isTrue);
      expect(plan.metadata!.versions.map((v) => v.id), [id(1)]);
      expect(plan.versionIds[id(4)], id(1));
      expect(plan.metadata!.history.single.input.version.id, id(5));
      expect(plan.metadata!.assets, isEmpty);
      expect(plan.metadata!.history.single.attempts, isEmpty);
    });

    test('audit identity collision derives isolated version and asset reference with replay', () {
      final current = manifest(versions: [version(1)], assets: [asset(10, 1)]);
      final incoming = manifest(
        results: [result(50, 60, input(10, version(1, hash: 'b')))],
        history: [
          history(70, input(10, version(1, hash: 'b')), attempts: [60]),
        ],
      );
      final plan = merge(current, incoming);
      expect(plan.canCommit, isTrue);
      final r = plan.metadata!.results.single;
      expect(r.input.version.id, isNot(id(1)));
      expect(r.input.referenceId, isNot(id(10)));
      expect(
        plan.metadata!.history.single.input.referenceId,
        r.input.referenceId,
      );
      expect(plan.metadata!.versions.single, version(1));
      expect(plan.metadata!.assets.single.id, id(10));
      final replay = merge(plan.metadata!, incoming);
      expect(replay.metadata!.results, hasLength(1));
      expect(replay.metadata!.history, hasLength(1));
      expect(replay.versionIds[id(1)], r.input.version.id);
      expect(replay.assetIds[id(10)], r.input.referenceId);
    });

    test(
      'permanent collision with current audit preserves historical description',
      () {
        final current = manifest(
          results: [result(50, 60, input(10, version(1)))],
        );
        final incoming = manifest(
          versions: [version(1, hash: 'b')],
          assets: [asset(11, 1)],
        );
        final plan = merge(current, incoming);
        expect(plan.canCommit, isTrue);
        expect(plan.versionIds[id(1)], isNot(id(1)));
        expect(plan.metadata!.results.single.input.version, version(1));
        expect(plan.metadata!.versions.single.sha256, 'b' * 64);
      },
    );

    test(
      'blocking frame conflict remains a typed proposal when origins collide',
      () {
        final current = manifest(
          versions: [
            version(1, frames: 1),
            version(2, hash: 'b'),
          ],
          origins: [origin(30, 2, processing(10, version(2, hash: 'b')))],
        );
        final incoming = manifest(
          versions: [version(3, hash: 'b')],
          origins: [origin(30, 3, processing(11, version(4)))],
        );
        final plan = merge(current, incoming);
        expect(plan.canCommit, isFalse);
        expect(plan.metadata, isNull);
        expect(
          plan.relationIssues.any(
            (i) =>
                i.kind == BackupRestoreIssueKind.versionDescriptionConflict &&
                i.blocking,
          ),
          isTrue,
        );
      },
    );

    test('same content incompatible descriptions block complete proposal', () {
      final current = manifest(
        results: [result(50, 60, input(10, version(1)))],
      );
      final incoming = manifest(
        history: [history(70, input(11, version(2, width: 99)))],
      );
      final plan = merge(current, incoming);
      expect(plan.canCommit, isFalse);
      expect(plan.metadata, isNull);
      expect(
        plan.relationIssues,
        contains(
          isA<BackupRestoreIssue>()
              .having(
                (i) => i.kind,
                'kind',
                BackupRestoreIssueKind.versionDescriptionConflict,
              )
              .having((i) => i.blocking, 'blocking', isTrue),
        ),
      );
      expect(plan.permanent.versions, isEmpty);
    });

    test('same-name accounts stay independent and collision preserves historical aliases', () {
      final current = manifest(accounts: [account(40, alias: '当前别名')]);
      final incoming = manifest(
        accounts: [
          account(40, service: ImageHostService.imgbb),
          account(41),
        ],
        results: [
          result(
            50,
            60,
            input(10, version(1)),
            t: target(40, service: ImageHostService.imgbb, alias: '过去的名字'),
          ),
        ],
      );
      final plan = merge(current, incoming);
      expect(plan.canCommit, isTrue);
      expect(plan.metadata!.accounts, hasLength(3));
      expect(plan.accountIds[id(40)], isNot(id(40)));
      expect(plan.accountIds[id(41)], id(41));
      expect(plan.metadata!.results.single.target.id, plan.accountIds[id(40)]);
      expect(plan.metadata!.results.single.target.alias, '过去的名字');
      final replay = merge(plan.metadata!, incoming);
      expect(replay.metadata!.accounts, hasLength(3));
      expect(replay.metadata!.results, hasLength(1));
    });

    test('matching account identity keeps configuration alias; absent audit target creates no account', () {
      final current = manifest(accounts: [account(40, alias: '当前别名')]);
      final incoming = manifest(
        accounts: [account(40, alias: '来包别名')],
        results: [
          result(50, 60, input(10, version(1)), t: target(40, alias: '冻结别名')),
        ],
      );
      final plan = merge(current, incoming);
      expect(plan.metadata!.accounts.single.alias, '当前别名');
      expect(plan.metadata!.results.single.target.alias, '冻结别名');
      final absent = merge(
        current,
        manifest(
          results: [
            result(
              51,
              61,
              input(10, version(1)),
              t: target(40, service: ImageHostService.imgbb),
            ),
          ],
        ),
      );
      expect(absent.metadata!.accounts, hasLength(1));
      expect(absent.metadata!.results.single.target.id, isNot(id(40)));
      expect(
        merge(
          absent.metadata!,
          manifest(
            results: [
              result(
                51,
                61,
                input(10, version(1)),
                t: target(40, service: ImageHostService.imgbb),
              ),
            ],
          ),
        ).metadata!.results,
        hasLength(1),
      );
    });

    test('same URL independent confirmations retained; conflicting identity refused', () {
      final i = input(10, version(1));
      final current = manifest(results: [result(50, 60, i)]);
      final incoming = manifest(
        results: [result(51, 61, i), result(52, 60, i, confirmed: 301)],
      );
      final plan = merge(current, incoming);
      expect(plan.canCommit, isTrue);
      expect(plan.metadata!.results.map((r) => r.id), [id(50), id(51)]);
      expect(plan.resultIds[id(51)], id(51));
      expect(plan.resultIds.containsKey(id(52)), isFalse);
      expect(
        plan.relationIssues.single.kind,
        BackupRestoreIssueKind.confirmationIdentityConflict,
      );
      final identity = merge(current, manifest(results: [result(50, 62, i)]));
      expect(
        identity.relationIssues.single.kind,
        BackupRestoreIssueKind.resultIdentityConflict,
      );
    });

    test('portable origins and orphan processed references cannot bind to local temporary outputs', () {
      final incoming = manifest(
        versions: [version(1)],
        origins: [origin(30, 1, processing(10, version(1)))],
        results: [result(50, 60, input(30, version(1), processed: true))],
      );
      final plan = BackupRestorePlanner.plan(
        current: manifest(),
        incoming: incoming,
        localOutputIds: {id(30)},
      );
      expect(plan.canCommit, true);
      final newId = plan.metadata!.origins.single.outputId;
      expect(newId, isNot(id(30)));
      expect(plan.metadata!.results.single.input.referenceId, newId);
      final replay = BackupRestorePlanner.plan(
        current: plan.metadata!,
        incoming: incoming,
        localOutputIds: {id(30)},
      );
      expect(replay.metadata!.origins, hasLength(1));
      expect(replay.metadata!.results, hasLength(1));
      expect(replay.metadata!.origins.single.outputId, newId);
      final orphan = manifest(
        results: [result(51, 61, input(31, version(2), processed: true))],
      );
      final audit = BackupRestorePlanner.plan(
        current: manifest(),
        incoming: orphan,
        localOutputIds: {id(31)},
      );
      expect(audit.metadata!.origins, isEmpty);
      expect(audit.metadata!.versions, isEmpty);
      expect(audit.metadata!.results.single.input.referenceId, isNot(id(31)));
      final again = BackupRestorePlanner.plan(
        current: audit.metadata!,
        incoming: orphan,
        localOutputIds: {id(31)},
      );
      expect(again.metadata!.results, hasLength(1));
    });

    test('ordinary confirmations cannot attach new backup evidence to an active attempt', () {
      final i = input(10, version(1));
      final incoming = manifest(results: [result(50, 60, i)]);
      final rejected = merge(manifest(), incoming, activeAttempts: {id(60)});
      expect(rejected.canCommit, true);
      expect(rejected.metadata!.results, isEmpty);
      expect(rejected.resultIds, isEmpty);
      expect(
        rejected.relationIssues.single.kind,
        BackupRestoreIssueKind.activeAttemptConflict,
      );
      expect(rejected.relationIssues.single.scope, BackupRestoreScope.result);
      // A current, independently saved late confirmation is still retained.
      final retained = merge(incoming, incoming, activeAttempts: {id(60)});
      expect(retained.metadata!.results, hasLength(1));
      expect(retained.relationIssues, isEmpty);
    });

    test('terminal histories replay with unchanged task, batch and attempt identities', () {
      final i = input(10, version(1));
      final incoming = manifest(
        history: [
          history(70, i, attempts: [60]),
        ],
        results: [result(50, 60, i)],
      );
      final plan = merge(manifest(), incoming);
      expect(plan.canCommit, isTrue);
      expect(plan.metadata!.history.single.id, id(70));
      expect(plan.metadata!.history.single.batchId, id(80));
      expect(plan.metadata!.history.single.attempts.single.id, id(60));
      expect(plan.metadata!.results.single.attemptId, id(60));
      final replay = merge(plan.metadata!, incoming);
      expect(replay.relationIssues, isEmpty);
      expect(replay.metadata!.history, hasLength(1));
      expect(replay.metadata!.results, hasLength(1));
    });

    test('N-way typed history issues preserve current and reject conflicting incoming payload', () {
      final i = input(10, version(1));
      final current = manifest(
        history: [
          history(70, i, attempts: [60]),
        ],
      );
      final incoming = manifest(
        history: [
          history(71, i, attempts: [60]),
        ],
      );
      final plan = merge(
        current,
        incoming,
        activeTasks: {id(71)},
        activeAttempts: {id(60)},
      );
      expect(plan.canCommit, isTrue);
      expect(plan.metadata!.history.single.id, id(70));
      expect(plan.relationIssues.map((i) => i.kind).toSet(), {
        BackupRestoreIssueKind.activeTaskConflict,
        BackupRestoreIssueKind.historyAttemptConflict,
        BackupRestoreIssueKind.activeAttemptConflict,
        BackupRestoreIssueKind.batchPositionConflict,
      });
      final payloadConflict = merge(
        current,
        manifest(
          history: [
            history(70, i, attempts: [60], message: '另一份'),
          ],
        ),
        activeTasks: {id(70)},
      );
      expect(
        payloadConflict.relationIssues.map((i) => i.kind),
        contains(BackupRestoreIssueKind.historyIdentityConflict),
      );
      expect(payloadConflict.metadata!.history.single.message, isNull);
      expect(plan.relationIssues.every((i) => !i.blocking), isTrue);
    });

    test(
      'immutable proposals and stable IDs avoid every imported UUID domain',
      () {
        final current = manifest(
          versions: [version(1)],
          assets: [asset(10, 1)],
        );
        final candidate = const Uuid().v5(
          id(900),
          jsonEncode([
            'imagehost-restore-audit-v1',
            BackupRestoreScope.version.name,
            id(1),
            '${'b' * 64}:100',
            0,
          ]),
        );
        final incoming = manifest(
          results: [result(50, 60, input(10, version(1, hash: 'b')))],
          history: [
            BackupTaskHistory(
              id: id(70),
              batchId: id(80),
              position: 0,
              input: input(10, version(1, hash: 'b')),
              target: target(40),
              state: PublishState.failed,
              attempts: [
                BackupAttemptHistory(
                  id: candidate,
                  generation: 1,
                  startedUtc: 100,
                  endedUtc: 200,
                ),
              ],
              createdUtc: 100,
              updatedUtc: 300,
            ),
          ],
        );
        final plan = merge(current, incoming);
        expect(plan.versionIds[id(1)], isNot(candidate));
        expect(() => plan.versionIds.clear(), throwsUnsupportedError);
        expect(() => plan.assetIds.clear(), throwsUnsupportedError);
        expect(() => plan.accountIds.clear(), throwsUnsupportedError);
        expect(() => plan.outputIds.clear(), throwsUnsupportedError);
        expect(() => plan.resultIds.clear(), throwsUnsupportedError);
        expect(() => plan.relationIssues.clear(), throwsUnsupportedError);
        expect(() => plan.metadata!.history.clear(), throwsUnsupportedError);
        expect(
          () => plan.metadata!.history.single.attempts.clear(),
          throwsUnsupportedError,
        );
        expect(current.versions.single, version(1));
        expect(incoming.results.single.input.version, version(1, hash: 'b'));
      },
    );
  });
}
