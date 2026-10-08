import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/network_state.dart';
import 'package:imagehost/features/settings/domain/device_settings.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/processing/domain/output_models.dart';

void main() {
  test('UT-083/087 validated default values and immutable roundtrip', () {
    expect(DeviceSettings(), DeviceSettings.defaults);
    expect(
      DeviceSettings.fromJson(DeviceSettings.defaults.toJson()),
      DeviceSettings.defaults,
    );
    expect(DeviceSettings.defaults.uploadConcurrency, 3);
    expect(DeviceSettings.defaults.processingConcurrency, 1);
    expect(DeviceSettings.defaults.processingMode, ProcessingMode.fidelity);
    expect(DeviceSettings.defaults.cacheLimitMiB, 256);
    expect(DeviceSettings.defaults.defaultOutputRetention, OutputRetention.day);
    expect(
      DeviceSettings.defaults.networkUploadPolicy,
      NetworkUploadPolicy.wifiAndEthernet,
    );
    expect(DeviceSettings.defaults.toJson()['formatVersion'], 3);
  });
  final fields = <String, (int, int)>{
    'uploadConcurrency': (1, 8),
    'processingConcurrency': (1, 4),
    'quality': (1, 100),
    'longestSide': (1, 16384),
    'cacheLimitMiB': (64, 2048),
  };
  for (final entry in fields.entries) {
    test(
      '${entry.key == 'cacheLimitMiB' ? 'UT-088' : 'UT-083/087'} ${entry.key} rejects noninteger nonfinite and outside bounds without clamping',
      () {
        for (final bad in [
          entry.value.$1 - 1,
          entry.value.$2 + 1,
          -1,
          1.0,
          1.5,
          double.nan,
          double.infinity,
          '3',
          null,
          true,
        ]) {
          final json = Map<String, Object?>.from(
            DeviceSettings.defaults.toJson(),
          );
          json[entry.key] = bad;
          expect(
            () => DeviceSettings.fromJson(json),
            throwsA(isA<SettingsFailure>()),
            reason: '${entry.key} runtime type ${bad.runtimeType}',
          );
        }
        for (final good in [entry.value.$1, entry.value.$2]) {
          final json = DeviceSettings.defaults.toJson();
          json[entry.key] = good;
          expect(DeviceSettings.fromJson(json).toJson()[entry.key], good);
        }
      },
    );
  }
  test(
    'UT-083/093 malformed future extra or missing fields refuse safe decode',
    () {
      final defaults = DeviceSettings.defaults.toJson();
      for (final bad in [
        null,
        [],
        'raw-secret',
        {...defaults, 'formatVersion': 4},
        {...defaults, 'formatVersion': 1.0},
        {...defaults, 'secret': 'never-display'},
        {...defaults}..remove('quality'),
        {...defaults, 'processingMode': 'future'},
        {...defaults, 'defaultOutputRetention': 'future'},
        {...defaults, 'defaultOutputRetention': 24},
        {...defaults, 'networkUploadPolicy': 'future'},
        {...defaults, 'networkUploadPolicy': 1},
        {...defaults, 'networkUploadPolicy': null},
        {...defaults, 'networkUploadPolicy': true},
        {...defaults}..remove('networkUploadPolicy'),
        {...defaults, 'formatVersion': 1},
      ]) {
        expect(
          () => DeviceSettings.fromJson(bad),
          throwsA(
            isA<SettingsFailure>().having(
              (e) => e.message,
              'fixed prose',
              isNot(contains('raw-secret')),
            ),
          ),
        );
      }
    },
  );
  test('UT-088 prior project format decodes new defaults without mutating stored input', () {
    final prior = <String, Object>{
      'formatVersion': 1,
      'uploadConcurrency': 5,
      'processingConcurrency': 2,
      'quality': 80,
      'longestSide': 1200,
      'processingMode': 'sizeFirst',
    };
    final unchanged = Map<String, Object>.of(prior);
    final decoded = DeviceSettings.fromJson(prior);
    expect(decoded.cacheLimitMiB, 256);
    expect(decoded.defaultOutputRetention, OutputRetention.day);
    expect(decoded.uploadConcurrency, 5);
    expect(decoded.processingMode, ProcessingMode.sizeFirst);
    expect(prior, unchanged);
    expect(decoded.toJson()['formatVersion'], 3);
    expect(decoded.networkUploadPolicy, NetworkUploadPolicy.wifiAndEthernet);
    for (final bad in [
      {...prior}..remove('quality'),
      {...prior, 'cacheLimitMiB': 256},
      {...prior, 'uploadConcurrency': 5.0},
      {...prior, 'formatVersion': 1.0},
    ]) {
      expect(
        () => DeviceSettings.fromJson(bad),
        throwsA(isA<SettingsFailure>()),
      );
    }
  });
  test(
    'UT-063/087 format 2 adds default network policy without rewriting input',
    () {
      final prior = <String, Object>{
        'formatVersion': 2,
        'uploadConcurrency': 5,
        'processingConcurrency': 2,
        'quality': 80,
        'longestSide': 1200,
        'processingMode': 'sizeFirst',
        'cacheLimitMiB': 128,
        'defaultOutputRetention': 'week',
      };
      final unchanged = Map<String, Object>.of(prior);
      final decoded = DeviceSettings.fromJson(prior);
      expect(decoded.networkUploadPolicy, NetworkUploadPolicy.wifiAndEthernet);
      expect(decoded.cacheLimitMiB, 128);
      expect(decoded.defaultOutputRetention, OutputRetention.week);
      expect(prior, unchanged);
      for (final bad in [
        {...prior}..remove('cacheLimitMiB'),
        {...prior, 'networkUploadPolicy': 'wifiAndEthernet'},
        {...prior, 'defaultOutputRetention': 'future'},
      ]) {
        expect(
          () => DeviceSettings.fromJson(bad),
          throwsA(isA<SettingsFailure>()),
        );
      }
    },
  );
  test('UT-063/087 network policies roundtrip and participate in identity', () {
    final distinct = {
      DeviceSettings.defaults,
      DeviceSettings(networkUploadPolicy: NetworkUploadPolicy.anyKnownNetwork),
    };
    expect(distinct, hasLength(2));
    for (final value in distinct) {
      expect(
        value.toJson()['networkUploadPolicy'],
        value.networkUploadPolicy.name,
      );
      expect(DeviceSettings.fromJson(value.toJson()), value);
      expect(DeviceSettings.fromJson(value.toJson()).hashCode, value.hashCode);
    }
  });
  test('UT-088 retention policies and cache limit participate in identity', () {
    final distinct = {
      DeviceSettings.defaults,
      DeviceSettings(cacheLimitMiB: 64),
      DeviceSettings(defaultOutputRetention: OutputRetention.hour),
      DeviceSettings(defaultOutputRetention: OutputRetention.week),
    };
    expect(distinct, hasLength(4));
    for (final value in distinct) {
      expect(DeviceSettings.fromJson(value.toJson()), value);
      expect(DeviceSettings.fromJson(value.toJson()).hashCode, value.hashCode);
    }
    for (final bad in [63, 2049, 64.0, '256', null, true]) {
      expect(
        () => DeviceSettings(cacheLimitMiB: bad),
        throwsA(isA<SettingsFailure>()),
      );
    }
  });
}
