import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/backup/domain/backup_result_merge.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';

String id(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

BackupRemoteResult result(
  int identity,
  int attempt, {
  String digest = 'a',
  int target = 30,
  int asset = 20,
  String url = 'https://example.org/same.png',
  int confirmedUtc = 1700000000000,
}) => BackupRemoteResult(
  id: id(identity),
  attemptId: id(attempt),
  input: FrozenUploadInput(
    kind: UploadInputKind.original,
    referenceId: id(asset),
    displayName: '已确认的图片',
    version: ImageVersion(
      id: id(10),
      sha256: digest * 64,
      byteCount: 100,
      format: 'PNG',
      width: 10,
      height: 10,
      frameCount: 1,
      orientation: 1,
    ),
    policyKey: 'original-confirmed-v1',
  ),
  target: TargetSnapshot(id(target), ImageHostService.imgbb, '普通账号标识', false),
  remoteId: 'remote-id',
  directUrl: Uri.parse(url),
  confirmedUtc: confirmedUtc,
  late: false,
);

void main() {
  test(
    'UT-078 partial: same URL with independent confirmations is retained',
    () {
      final first = result(1, 101);
      final second = result(2, 102);
      final plan = BackupResultMergePlanner.plan(
        current: [first],
        incoming: [second],
      );
      expect(plan.results, [first, second]);
      expect(plan.resultIds, {id(2): id(2)});
      expect(plan.conflicts, isEmpty);
    },
  );

  test('UT-078 partial: same result and confirmation replay is idempotent', () {
    final original = result(1, 101);
    final once = BackupResultMergePlanner.plan(
      current: [],
      incoming: [original],
    );
    final twice = BackupResultMergePlanner.plan(
      current: once.results,
      incoming: [result(1, 101)],
    );
    expect(twice.results, [original]);
    expect(twice.resultIds[id(1)], id(1));
    expect(twice.conflicts, isEmpty);
  });

  test('UT-078 partial: a duplicate confirmation maps to preserved result', () {
    final original = result(1, 101);
    final plan = BackupResultMergePlanner.plan(
      current: [original],
      incoming: [result(2, 101)],
    );
    expect(plan.results, [original]);
    expect(plan.resultIds[id(2)], id(1));
    expect(plan.conflicts, isEmpty);
  });

  test(
    'UT-078 partial: conflicting content cannot overwrite result identity',
    () {
      final original = result(1, 101);
      final distinct = result(2, 102);
      final plan = BackupResultMergePlanner.plan(
        current: [original],
        incoming: [
          result(1, 101, digest: 'b'),
          distinct,
        ],
      );
      expect(plan.results, [original, distinct]);
      expect(plan.resultIds.containsKey(id(1)), isFalse);
      expect(
        plan.conflicts.single.kind,
        BackupResultConflictKind.resultIdentity,
      );
    },
  );

  test(
    'UT-078 partial: confirmation conflict checks content, target and URL',
    () {
      final original = result(1, 101);
      for (final candidate in [
        result(2, 101, digest: 'b'),
        result(2, 101, target: 31),
        result(2, 101, asset: 21),
        result(2, 101, url: 'https://example.org/different.png'),
        result(2, 101, confirmedUtc: 1700000000001),
      ]) {
        final plan = BackupResultMergePlanner.plan(
          current: [original],
          incoming: [candidate],
        );
        expect(plan.results, [original]);
        expect(plan.resultIds, isEmpty);
        expect(
          plan.conflicts.single.kind,
          BackupResultConflictKind.confirmationIdentity,
        );
      }
    },
  );

  test(
    'UT-078 partial: conflicting result and attempt cannot fuse two histories',
    () {
      final first = result(1, 101);
      final second = result(2, 102);
      final plan = BackupResultMergePlanner.plan(
        current: [first, second],
        incoming: [result(1, 102)],
      );
      expect(plan.results, [first, second]);
      expect(
        plan.conflicts.single.kind,
        BackupResultConflictKind.resultIdentity,
      );
    },
  );

  test(
    'UT-078 partial: immutable plan and invalid duplicate input boundaries',
    () {
      final original = result(1, 101);
      final values = <BackupRemoteResult>[original];
      final plan = BackupResultMergePlanner.plan(current: [], incoming: values);
      values.clear();
      expect(plan.results, [original]);
      expect(() => plan.results.clear(), throwsUnsupportedError);
      expect(() => plan.resultIds.clear(), throwsUnsupportedError);
      expect(() => plan.conflicts.clear(), throwsUnsupportedError);
      for (final values in [
        [original, result(1, 102)],
        [original, result(2, 101)],
      ]) {
        expect(
          () => BackupResultMergePlanner.plan(current: [], incoming: values),
          throwsA(isA<BackupFailure>()),
        );
        expect(
          () => BackupResultMergePlanner.plan(current: values, incoming: []),
          throwsA(isA<BackupFailure>()),
        );
      }
    },
  );
}
