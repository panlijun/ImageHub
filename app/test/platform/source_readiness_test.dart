import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/platform/source_readiness.dart';

void main() {
  test(
    'UT-010 Windows explicit offline and recall flags identify cloud pending',
    () {
      for (final flag in [0x1000, 0x400000]) {
        expect(
          SourceReadinessProbe.classifyWindowsAttributes(flag),
          SourceReadiness.cloudPending,
        );
        expect(
          SourceReadinessProbe.classifyWindowsAttributes(
            flag | 0x20 | 0x400 | 0x40000,
          ),
          SourceReadiness.cloudPending,
        );
      }
    },
  );

  test(
    'UT-010 attribute failure, directory and reparse target remain unknown',
    () {
      for (final attributes in [
        null,
        -1,
        0xffffffff,
        0x100000000,
        0x10,
        0x410,
        0x400,
        // GetFileAttributesW uses 0x40000 for EA; directory enumeration alone
        // uses this value for RECALL_ON_OPEN. Never infer cloudPending here.
        // https://learn.microsoft.com/en-us/windows/win32/fileio/file-attribute-constants
        0x40000,
        0x40000 | 0x20,
      ]) {
        expect(
          SourceReadinessProbe.classifyWindowsAttributes(attributes),
          SourceReadiness.unknown,
        );
      }
    },
  );

  test(
    'UT-010 confirmed plain file attributes without cloud flags are ready',
    () {
      for (final attributes in [0, 0x80, 0x20, 0x1, 0x2 | 0x20, 0x2000]) {
        expect(
          SourceReadinessProbe.classifyWindowsAttributes(attributes),
          SourceReadiness.ready,
        );
      }
    },
  );

  test(
    'UT-010 malformed Windows path never reaches attribute acquisition',
    () async {
      const probe = SourceReadinessProbe();
      for (final path in ['', 'prefix\u0000suffix', 'a' * 32767]) {
        expect(await probe.check(path), SourceReadiness.unknown);
      }
    },
  );

  test(
    'UT-010 UNC device relative and traversal paths invoke no native metadata',
    () {
      for (final path in [
        r'\\server\share\image.png',
        r'\\?\C:\image.png',
        r'\\.\C:\image.png',
        r'relative\image.png',
        r'C:relative\image.png',
        r'C:\folder\..\image.png',
        r'C:\folder\.\image.png',
        'C:\\folder\u0000\\image.png',
      ]) {
        final readiness = SourceReadinessProbe.inspectWindowsPath(
          path,
          driveType: (_) =>
              throw StateError('Invalid path must not query a drive.'),
          attributes: (_) =>
              throw StateError('Invalid path must not query attributes.'),
        );
        expect(readiness, SourceReadiness.unknown);
      }
    },
  );

  test('UT-010 remote and unknown drive types never query target or ancestor attributes', () {
    for (final type in [0, 1, 4]) {
      final roots = <String>[];
      final readiness = SourceReadinessProbe.inspectWindowsPath(
        r'Z:\folder\image.png',
        driveType: (root) {
          roots.add(root);
          return type;
        },
        attributes: (_) =>
            throw StateError('Remote drive must not query attributes.'),
      );
      expect(readiness, SourceReadiness.unknown);
      expect(roots, ['Z:\\']);
    }
  });

  test(
    'UT-010 reparse ancestor stops before querying any following source path',
    () {
      final queries = <String>[];
      final readiness = SourceReadinessProbe.inspectWindowsPath(
        r'C:\junction\subdir\image.png',
        driveType: (_) => 3,
        attributes: (path) {
          queries.add(path);
          if (path == 'C:\\') return 0x10;
          if (path == r'C:\junction') return 0x10 | 0x400;
          throw StateError(
            'Reparse parent must stop later metadata acquisition.',
          );
        },
      );
      expect(readiness, SourceReadiness.unknown);
      expect(queries, ['C:\\', r'C:\junction']);
    },
  );

  test('UT-010 allowed local drives walk ordinary ancestors and preserve final recall evidence', () {
    for (final type in [2, 3, 5, 6]) {
      for (final target in [0x80, 0x400, 0x40000, 0x400 | 0x400000]) {
        final queries = <String>[];
        final readiness = SourceReadinessProbe.inspectWindowsPath(
          r'C:\ordinary\image.png',
          driveType: (_) => type,
          attributes: (path) {
            queries.add(path);
            return path == r'C:\ordinary\image.png' ? target : 0x10;
          },
        );
        expect(queries, ['C:\\', r'C:\ordinary', r'C:\ordinary\image.png']);
        expect(
          readiness,
          SourceReadinessProbe.classifyWindowsAttributes(target),
        );
      }
    }
  });

  test('UT-010 Windows actual ordinary file is ready; absent file and directory are unknown', () async {
    final root = await Directory.systemTemp.createTemp('imagehost_readiness_');
    try {
      final file = File('${root.path}/ordinary.bin');
      await file.writeAsBytes([1, 2, 3], flush: true);
      const probe = SourceReadinessProbe();
      expect(await probe.check(file.path), SourceReadiness.ready);
      expect(
        await probe.check('${root.path}/absent.bin'),
        SourceReadiness.unknown,
      );
      expect(await probe.check(root.path), SourceReadiness.unknown);
      expect(await file.readAsBytes(), [1, 2, 3]);
    } finally {
      await root.delete(recursive: true);
    }
  }, skip: !Platform.isWindows);

  test('UT-010 unimplemented source platform remains unknown', () async {
    expect(
      await const SourceReadinessProbe().check('/ordinary/source.png'),
      SourceReadiness.unknown,
    );
  }, skip: Platform.isWindows);
}
