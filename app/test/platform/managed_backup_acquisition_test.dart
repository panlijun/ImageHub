import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/platform/mobile_file_workspace.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory parent;
  late Directory root;
  setUp(() async {
    parent = Directory(await Directory.systemTemp.resolveSymbolicLinks());
    root = await parent.createTemp('imagehub-managed-backup-test-');
  });
  tearDown(() async {
    final canonical = await root.resolveSymbolicLinks();
    expect(p.dirname(canonical), parent.path);
    expect(p.basename(canonical), startsWith('imagehub-managed-backup-test-'));
    await Directory(canonical).delete(recursive: true);
  });

  Future<BackupSource?> acquire(
    List<PlatformResource> resources, {
    CancellationToken? cancellation,
    int space = 100 * 1024 * 1024,
  }) => acquireManagedBackup(
    resources,
    cancellation: cancellation,
    createWorkspace: () => MobileFileWorkspace.create(parent: root),
    availableBytes: (_) async => space,
  );

  test(
    'UT-075 copied backup survives original loss after all grants retire',
    () async {
      final original = File(p.join(root.path, 'original.zip'));
      final bytes = List<int>.generate(128 * 1024 + 17, (index) => index % 251);
      await original.writeAsBytes(bytes, flush: true);
      var retired = false;
      final selected = await acquire([
        PlatformResource(
          displayName: 'backup.zip',
          sourceType: 'backup',
          openRead: original.openRead,
          release: () async => retired = true,
        ),
      ]);
      expect(retired, true);
      expect(selected, isNotNull);
      expect(selected!.file.path, isNot(original.path));
      await original.delete();
      expect(await fileSha256(selected.file), sha256.convert(bytes).toString());
      expect(await selected.file.length(), bytes.length);
      await selected.release!();
      expect(await selected.file.exists(), false);
      expect(await root.list().toList(), isEmpty);
    },
  );

  test(
    'UT-075 handoff waits actual native scope retirement after writer closes',
    () async {
      final retirement = Completer<void>();
      var finished = false;
      var releasing = false;
      final pending =
          acquire([
            PlatformResource(
              displayName: 'backup.zip',
              sourceType: 'backup',
              openRead: () => Stream.value([1, 2, 3]),
              release: () async {
                releasing = true;
                await retirement.future;
              },
            ),
          ]).then((value) {
            finished = true;
            return value;
          });
      try {
        await _until(() => releasing);
        expect(finished, false);
        final folders = await root
            .list()
            .where((entry) => entry is Directory)
            .toList();
        expect(folders.length, 1);
        final copied = File(p.join(folders.single.path, 'selected.zip'));
        expect(await copied.readAsBytes(), [1, 2, 3]);
      } finally {
        if (!retirement.isCompleted) retirement.complete();
      }
      final selected = await pending;
      await selected!.release!();
      expect(await root.list().toList(), isEmpty);
    },
  );

  test('UT-075 failed retirement refuses handoff and cleans confirmed private bytes', () async {
    final pending = acquire([
      PlatformResource(
        displayName: 'backup.zip',
        sourceType: 'backup',
        openRead: () => Stream.value([1, 2, 3]),
        release: () async => throw const ResourceFailure(FailureKind.storage),
      ),
    ]);
    await expectLater(pending, _failure(FailureKind.storage));
    expect(await root.list().toList(), isEmpty);
  });

  test(
    'UT-075 insufficient capacity stops private copy and still retires source',
    () async {
      var retired = false;
      await expectLater(
        acquire([
          PlatformResource(
            displayName: 'backup.zip',
            sourceType: 'backup',
            openRead: () => Stream.value([1, 2, 3]),
            release: () async => retired = true,
          ),
        ], space: 0),
        _failure(FailureKind.lowSpace),
      );
      expect(retired, true);
      expect(await root.list().toList(), isEmpty);
    },
  );

  test(
    'UT-075 cancellation during source copying drains before private cleanup',
    () async {
      final token = CancellationToken();
      var retired = false;
      Stream<List<int>> chunks() async* {
        yield [1, 2, 3];
        token.cancel();
        yield [4, 5, 6];
      }

      await expectLater(
        acquire([
          PlatformResource(
            displayName: 'backup.zip',
            sourceType: 'backup',
            openRead: chunks,
            release: () async => retired = true,
          ),
        ], cancellation: token),
        _failure(FailureKind.cancelled),
      );
      expect(retired, true);
      expect(await root.list().toList(), isEmpty);
    },
  );

  test(
    'UT-075 invalid acquired group releases each grant without opening data',
    () async {
      var opened = 0;
      var retired = 0;
      final resource = PlatformResource(
        displayName: 'file.png',
        sourceType: 'file',
        openRead: () {
          opened++;
          return Stream.value([1]);
        },
        release: () async => retired++,
      );
      await expectLater(
        acquire([resource, resource]),
        _failure(FailureKind.unavailable),
      );
      expect(opened, 0);
      expect(retired, 2);
      expect(await root.list().toList(), isEmpty);
    },
  );
}

Matcher _failure(FailureKind kind) =>
    throwsA(isA<ResourceFailure>().having((error) => error.kind, 'kind', kind));
Future<void> _until(bool Function() condition) async {
  for (var index = 0; index < 100 && !condition(); index++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), true);
}
