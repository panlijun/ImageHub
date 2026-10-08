import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/network_state.dart';
import 'package:imagehost/features/backup/domain/backup_settings.dart';
import 'package:imagehost/features/processing/domain/output_models.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/settings/domain/device_settings.dart';

final transferred = DeviceSettings(
  uploadConcurrency: 7,
  processingConcurrency: 4,
  quality: 72,
  longestSide: 2400,
  processingMode: ProcessingMode.sizeFirst,
  cacheLimitMiB: 512,
  defaultOutputRetention: OutputRetention.week,
  networkUploadPolicy: NetworkUploadPolicy.anyKnownNetwork,
);

Map<String, dynamic> rawSettings() =>
    jsonDecode(jsonEncode(BackupDeviceSettings(values: transferred).toJson()))
        as Map<String, dynamic>;

void main() {
  test('UT-078/081 partial BAK-005: four platform policies round trip all eight settings', () {
    final incoming = BackupDeviceSettings.fromJson(rawSettings());
    expect(incoming.values, transferred);
    expect(incoming.availability.keys, BackupSetting.values);
    expect(incoming.toJson()['formatVersion'], 1);
    expect((incoming.toJson()['values'] as Map)['formatVersion'], 3);
    for (final platform in BackupPlatform.values) {
      final plan = BackupSettingsRestorePlan.plan(
        current: DeviceSettings.defaults,
        incoming: incoming,
        platform: platform,
      );
      expect(plan.values, transferred);
      expect(plan.included, isTrue);
      expect(plan.restored, BackupSetting.values);
      expect(plan.skipped, isEmpty);
    }
    expect(
      BackupSetting.values.map((setting) => setting.label).toSet(),
      hasLength(8),
    );
  });

  test('UT-078/081 partial BAK-005: platform unavailable values retain each current field', () {
    for (final platform in BackupPlatform.values) {
      for (final setting in BackupSetting.values) {
        final incoming = BackupDeviceSettings(
          values: transferred,
          availability: {
            setting: BackupPlatform.values.where((p) => p != platform).toSet(),
          },
        );
        final plan = BackupSettingsRestorePlan.plan(
          current: DeviceSettings.defaults,
          incoming: incoming,
          platform: platform,
        );
        final expected = transferred.toJson();
        expected[setting.name] = DeviceSettings.defaults
            .toJson()[setting.name]!;
        expect(plan.values, DeviceSettings.fromJson(expected));
        expect(plan.skipped, [setting]);
        expect(plan.restored, BackupSetting.values.where((s) => s != setting));
      }
    }
  });

  test('UT-078/081 partial BAK-005: empty availability and absent settings preserve policies', () {
    final unavailable = BackupDeviceSettings(
      values: transferred,
      availability: {for (final setting in BackupSetting.values) setting: {}},
    );
    for (final platform in BackupPlatform.values) {
      for (final incoming in [null, unavailable]) {
        final plan = BackupSettingsRestorePlan.plan(
          current: DeviceSettings.defaults,
          incoming: incoming,
          platform: platform,
        );
        expect(plan.values, DeviceSettings.defaults);
        expect(plan.included, incoming != null);
        expect(plan.restored, isEmpty);
        expect(plan.skipped, BackupSetting.values);
        expect(plan.message, isNotEmpty);
      }
    }
  });

  test('UT-078/081 partial BAK-005: source and exposed availability and plans are deeply immutable', () {
    final platforms = {BackupPlatform.windows};
    final source = {BackupSetting.quality: platforms};
    final incoming = BackupDeviceSettings(
      values: transferred,
      availability: source,
    );
    platforms.clear();
    source.clear();
    expect(incoming.availability[BackupSetting.quality], {
      BackupPlatform.windows,
    });
    expect(() => incoming.availability.clear(), throwsUnsupportedError);
    expect(
      () => incoming.availability[BackupSetting.quality]!.clear(),
      throwsUnsupportedError,
    );
    final plan = BackupSettingsRestorePlan.plan(
      current: DeviceSettings.defaults,
      incoming: incoming,
      platform: BackupPlatform.ios,
    );
    expect(() => plan.restored.clear(), throwsUnsupportedError);
    expect(() => plan.skipped.clear(), throwsUnsupportedError);
    final json = incoming.toJson();
    ((json['availability'] as Map)['quality'] as List).clear();
    expect(incoming.availability[BackupSetting.quality], {
      BackupPlatform.windows,
    });
  });

  test('UT-078/081 partial BAK-005: strict envelope and current device format reject malformed or future data', () {
    final setters = <void Function(Map<String, dynamic>)>[
      (m) => m['formatVersion'] = 2,
      (m) => m['formatVersion'] = 1.0,
      (m) => m.remove('values'),
      (m) => m.remove('availability'),
      (m) => m['values'] = null,
      (m) => m['values']['formatVersion'] = 4,
      (m) => m['values']['formatVersion'] = 3.0,
      (m) {
        m['values']['formatVersion'] = 2;
        (m['values'] as Map).remove('networkUploadPolicy');
      },
      (m) => (m['values'] as Map).remove('quality'),
      (m) => m['values']['quality'] = 0,
      (m) => m['values']['uploadConcurrency'] = 9,
      (m) => m['values']['processingConcurrency'] = 5,
      (m) => m['values']['longestSide'] = 16385,
      (m) => m['values']['cacheLimitMiB'] = 63,
      (m) => m['values']['quality'] = 85.0,
      (m) => m['values']['processingMode'] = 'future',
      (m) => m['values']['defaultOutputRetention'] = 'future',
      (m) => m['values']['networkUploadPolicy'] = 'future',
      (m) => m['availability'] = [],
      (m) => (m['availability'] as Map).remove('quality'),
      (m) => m['availability']['future'] = [],
      (m) => m['availability']['quality'] = null,
      (m) => m['availability']['quality'] = ['windows', 'windows'],
      (m) => m['availability']['quality'] = ['linux'],
      (m) => m['availability']['quality'] = [1],
    ];
    for (final set in setters) {
      final raw = rawSettings();
      set(raw);
      expect(
        () => BackupDeviceSettings.fromJson(raw),
        throwsA(isA<SettingsFailure>()),
      );
    }
    for (final raw in [null, [], 'untrusted-secret', _NeverStringify()]) {
      expect(
        () => BackupDeviceSettings.fromJson(raw),
        throwsA(isA<SettingsFailure>()),
      );
    }
  });

  test('UT-078/081 partial BAK-005: unknown device paths credentials defaults and permission are refused', () {
    for (final field in [
      'path',
      'sourcePath',
      'credential',
      'secretReference',
      'defaultTargetId',
      'sessionPermission',
    ]) {
      for (final boundary in ['envelope', 'values', 'availability']) {
        final raw = rawSettings();
        final target = boundary == 'envelope' ? raw : raw[boundary] as Map;
        target[field] = 'untrusted-secret';
        expect(
          () => BackupDeviceSettings.fromJson(raw),
          throwsA(
            isA<SettingsFailure>().having(
              (failure) => failure.message,
              'safe fixed message',
              isNot(contains('untrusted-secret')),
            ),
          ),
        );
      }
    }
  });
}

final class _NeverStringify {
  @override
  String toString() => throw StateError('untrusted stringify called');
}
