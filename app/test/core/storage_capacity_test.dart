import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/platform/storage_capacity.dart';
import 'package:imagehost/features/backup/application/backup_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.imagehost/storage_capacity');
  const platform = StorageCapacity();
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test('Windows capacity contract rejects missing invalid and unsafe backend errors', () async {
    for (final result in [null, -1, 'bad']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => result);
      await expectLater(
        platform.availableBytes(Directory.systemTemp),
        throwsA(isA<BackupSnapshotFailure>()),
      );
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(
            code: 'read_error',
            message: 'synthetic-private-key',
          );
        });
    await expectLater(
      platform.availableBytes(Directory.systemTemp),
      throwsA(
        isA<BackupSnapshotFailure>().having(
          (e) => e.message,
          'safe feedback',
          isNot(contains('synthetic-private-key')),
        ),
      ),
    );
  }, skip: !Platform.isWindows);
  test('Windows capacity and exclusive publication adapt normalized paths and collision result', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'availableBytes' ? 1234567 : false;
        });
    expect(await platform.availableBytes(Directory.systemTemp), 1234567);
    expect(
      await platform.publishExclusive(
        File('source.partial'),
        File('result.zip'),
      ),
      false,
    );
    expect(calls.last.arguments, isA<Map>());
    expect(
      (calls.last.arguments as Map)['source'],
      File('source.partial').absolute.path,
    );
  }, skip: !Platform.isWindows);
}
