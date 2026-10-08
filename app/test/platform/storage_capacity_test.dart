import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/features/backup/application/backup_snapshot.dart';
import 'package:imagehost/platform/storage_capacity.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.imagehost/storage_capacity');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const operatingSystems = ['windows', 'android', 'ios', 'macos'];

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'UT-086 capacity supports four native targets and refuses others',
    () async {
      for (final os in operatingSystems) {
        expect(StorageCapacity(operatingSystem: os).supportsPlatform, isTrue);
      }
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        return 999;
      });
      for (final os in ['linux', 'web', 'unknown']) {
        final storage = StorageCapacity(operatingSystem: os);
        expect(storage.supportsPlatform, isFalse);
        await expectLater(
          storage.availableBytes(Directory.systemTemp),
          throwsA(isA<BackupSnapshotFailure>()),
        );
        await expectLater(
          storage.publishExclusive(File('source'), File('destination')),
          throwsA(isA<BackupSnapshotFailure>()),
        );
      }
      expect(calls, 0);
    },
  );

  test('UT-086 zero and low capacity remain real values with normalized absolute paths', () async {
    final calls = <MethodCall>[];
    var value = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return value;
    });
    final directory = Directory(p.join('relative', '..', 'target'));
    for (final os in operatingSystems) {
      final storage = StorageCapacity(operatingSystem: os);
      for (final bytes in [0, 1, 1234567, 1 << 40]) {
        value = bytes;
        expect(await storage.availableBytes(directory), bytes);
        expect(calls.last.method, 'availableBytes');
        expect(calls.last.arguments, p.normalize(directory.absolute.path));
      }
    }
  });

  test(
    'UT-086 unknown invalid and failing capacity never become a fallback',
    () async {
      for (final os in operatingSystems) {
        final storage = StorageCapacity(operatingSystem: os);
        for (final response in [null, -1, 'bad', true, 1.25]) {
          messenger.setMockMethodCallHandler(channel, (_) async => response);
          await expectLater(
            storage.availableBytes(Directory.systemTemp),
            throwsA(
              isA<BackupSnapshotFailure>().having(
                (e) => e.message,
                'fixed feedback',
                '无法确认目标可用空间，请选择其他目标。',
              ),
            ),
          );
        }
        for (final error in [
          MissingPluginException('synthetic-private-key'),
          PlatformException(
            code: 'read_error',
            message: 'synthetic-private-key',
          ),
        ]) {
          messenger.setMockMethodCallHandler(channel, (_) async => throw error);
          await expectLater(
            storage.availableBytes(Directory.systemTemp),
            throwsA(
              isA<BackupSnapshotFailure>().having(
                (e) => e.message,
                'fixed feedback',
                '无法确认目标可用空间，请选择其他目标。',
              ),
            ),
          );
        }
      }
    },
  );

  test(
    'UT-086 exclusive publication preserves collision and committed results',
    () async {
      final calls = <MethodCall>[];
      var response = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return response;
      });
      final source = File(p.join('relative', '..', 'source.partial'));
      final destination = File(p.join('relative', '..', 'result.zip'));
      for (final os in operatingSystems) {
        final storage = StorageCapacity(operatingSystem: os);
        for (final published in [false, true]) {
          response = published;
          expect(
            await storage.publishExclusive(source, destination),
            published,
          );
          expect(calls.last.method, 'publishExclusive');
          expect(calls.last.arguments, {
            'source': p.normalize(source.absolute.path),
            'destination': p.normalize(destination.absolute.path),
          });
        }
      }
    },
  );

  test(
    'UT-086 invalid and missing publication backend never reports success',
    () async {
      for (final os in operatingSystems) {
        final storage = StorageCapacity(operatingSystem: os);
        for (final response in [null, 1, 'true']) {
          messenger.setMockMethodCallHandler(channel, (_) async => response);
          await expectLater(
            storage.publishExclusive(File('source'), File('destination')),
            throwsA(isA<BackupSnapshotFailure>()),
          );
        }
        for (final error in [
          MissingPluginException('synthetic-private-key'),
          PlatformException(
            code: 'publish_error',
            message: 'synthetic-private-key',
          ),
        ]) {
          messenger.setMockMethodCallHandler(channel, (_) async => throw error);
          await expectLater(
            storage.publishExclusive(File('source'), File('destination')),
            throwsA(
              isA<BackupSnapshotFailure>().having(
                (e) => e.message,
                'fixed feedback',
                '无法安全发布备份文件，请选择其他目标。',
              ),
            ),
          );
        }
      }
    },
  );
}
