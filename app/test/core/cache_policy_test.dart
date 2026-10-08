import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/features/storage/domain/storage_models.dart';

void main() {
  const policy = CachePolicy();

  test(
    'UT-088 LRU uses persisted order then stable id regardless of input order',
    () {
      final entries = [
        const CacheCandidate('c', 10, 2),
        const CacheCandidate('b', 10, 1),
        const CacheCandidate('a', 10, 1),
      ];
      for (final input in [entries, entries.reversed]) {
        final result = policy.evaluate(entries: input, limitBytes: 15);
        expect(result.evictIds, ['a', 'b']);
        expect(result.remainingBytes, 10);
        expect(result.canAdmit, true);
      }
    },
  );

  test(
    'UT-088 protected and unknown bytes remain charged and cannot be evicted',
    () {
      final result = policy.evaluate(
        entries: [
          const CacheCandidate('protected', 40, 0, protected: true),
          const CacheCandidate('removable', 20, 1),
        ],
        limitBytes: 60,
        incomingBytes: 1,
        untrackedBytes: 20,
      );
      expect(result.evictIds, ['removable']);
      expect(result.remainingBytes, 60);
      expect(result.canAdmit, false);
    },
  );

  test(
    'UT-088 incoming image must fit after eviction including exact boundary',
    () {
      final fits = policy.evaluate(
        entries: [const CacheCandidate('old', 30, 1)],
        limitBytes: 64,
        incomingBytes: 44,
        untrackedBytes: 20,
      );
      expect(fits.evictIds, ['old']);
      expect(fits.canAdmit, true);
      final tooLarge = policy.evaluate(
        entries: [const CacheCandidate('old', 30, 1)],
        limitBytes: 64,
        incomingBytes: 45,
        untrackedBytes: 20,
      );
      expect(tooLarge.remainingBytes, 20);
      expect(tooLarge.canAdmit, false);
      expect(
        policy
            .evaluate(entries: [], limitBytes: 64, incomingBytes: 64)
            .canAdmit,
        true,
      );
    },
  );

  test(
    'UT-088 already within limit neither evicts nor expands supplied scope',
    () {
      final result = policy.evaluate(
        entries: [const CacheCandidate('zero', 0, 0)],
        limitBytes: 64,
        untrackedBytes: 64,
      );
      expect(result.evictIds, isEmpty);
      expect(result.remainingBytes, 64);
      expect(result.canAdmit, true);
      expect(() => result.evictIds.add('later'), throwsUnsupportedError);
    },
  );

  test(
    'UT-088 invalid accounting and duplicate identities reject without a plan',
    () {
      for (final entries in [
        [const CacheCandidate('a', -1, 0)],
        [const CacheCandidate('a', 1, -1)],
        [const CacheCandidate('a', 1, 0), const CacheCandidate('a', 2, 1)],
      ]) {
        expect(
          () => policy.evaluate(entries: entries, limitBytes: 64),
          throwsA(isA<StorageFailure>()),
        );
      }
      for (final values in [(0, 0, 0), (64, -1, 0), (64, 0, -1)]) {
        expect(
          () => policy.evaluate(
            entries: [],
            limitBytes: values.$1,
            incomingBytes: values.$2,
            untrackedBytes: values.$3,
          ),
          throwsA(isA<StorageFailure>()),
        );
      }
    },
  );
}
