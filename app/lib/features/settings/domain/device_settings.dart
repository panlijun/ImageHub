import '../../../core/network_state.dart';
import '../../processing/domain/processing_models.dart';
import '../../processing/domain/output_models.dart';

final class SettingsFailure implements Exception {
  const SettingsFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Device policy only. Credentials and permission to send are never settings.
final class DeviceSettings {
  const DeviceSettings._(
    this.uploadConcurrency,
    this.processingConcurrency,
    this.quality,
    this.longestSide,
    this.processingMode,
    this.cacheLimitMiB,
    this.defaultOutputRetention,
    this.networkUploadPolicy,
  );
  static const defaults = DeviceSettings._(
    3,
    1,
    85,
    1600,
    ProcessingMode.fidelity,
    256,
    OutputRetention.day,
    NetworkUploadPolicy.wifiAndEthernet,
  );
  final int uploadConcurrency, processingConcurrency, quality, longestSide;
  final ProcessingMode processingMode;
  final int cacheLimitMiB;
  final OutputRetention defaultOutputRetention;
  final NetworkUploadPolicy networkUploadPolicy;

  factory DeviceSettings({
    Object? uploadConcurrency = 3,
    Object? processingConcurrency = 1,
    Object? quality = 85,
    Object? longestSide = 1600,
    ProcessingMode processingMode = ProcessingMode.fidelity,
    Object? cacheLimitMiB = 256,
    OutputRetention defaultOutputRetention = OutputRetention.day,
    NetworkUploadPolicy networkUploadPolicy =
        NetworkUploadPolicy.wifiAndEthernet,
  }) => DeviceSettings._(
    _integer(uploadConcurrency, 1, 8, '上传并发'),
    _integer(processingConcurrency, 1, 4, '处理并发'),
    _integer(quality, 1, 100, '有损输出质量'),
    _integer(longestSide, 1, 16384, '体积优先最长边'),
    processingMode,
    _integer(cacheLimitMiB, 64, 2048, '缩略图缓存上限'),
    defaultOutputRetention,
    networkUploadPolicy,
  );
  static int _integer(Object? value, int min, int max, String label) {
    if (value is! int || value < min || value > max) {
      throw SettingsFailure('$label 必须是 $min–$max 的整数，未保存。');
    }
    return value;
  }

  Map<String, Object> toJson() => {
    'formatVersion': 3,
    'uploadConcurrency': uploadConcurrency,
    'processingConcurrency': processingConcurrency,
    'quality': quality,
    'longestSide': longestSide,
    'processingMode': processingMode.name,
    'cacheLimitMiB': cacheLimitMiB,
    'defaultOutputRetention': defaultOutputRetention.name,
    'networkUploadPolicy': networkUploadPolicy.name,
  };
  factory DeviceSettings.fromJson(Object? value) {
    try {
      const priorKeys = {
        'formatVersion',
        'uploadConcurrency',
        'processingConcurrency',
        'quality',
        'longestSide',
        'processingMode',
      };
      if (value is! Map || value['formatVersion'] is! int) {
        throw const SettingsFailure('本机设置格式不兼容，已有设置保留；请使用兼容版本。');
      }
      final version = value['formatVersion'];
      final versionTwoKeys = {
        ...priorKeys,
        'cacheLimitMiB',
        'defaultOutputRetention',
      };
      final expectedKeys = version == 1
          ? priorKeys
          : version == 2
          ? versionTwoKeys
          : version == 3
          ? DeviceSettings.defaults.toJson().keys.toSet()
          : null;
      if (expectedKeys == null ||
          value.length != expectedKeys.length ||
          value.keys.any(
            (key) => key is! String || !expectedKeys.contains(key),
          )) {
        throw const SettingsFailure('本机设置格式不兼容，已有设置保留；请使用兼容版本。');
      }
      return DeviceSettings(
        uploadConcurrency: value['uploadConcurrency'],
        processingConcurrency: value['processingConcurrency'],
        quality: value['quality'],
        longestSide: value['longestSide'],
        processingMode: ProcessingMode.values.byName(
          value['processingMode'] as String,
        ),
        cacheLimitMiB: version == 1 ? 256 : value['cacheLimitMiB'],
        defaultOutputRetention: version == 1
            ? OutputRetention.day
            : OutputRetention.values.byName(
                value['defaultOutputRetention'] as String,
              ),
        networkUploadPolicy: version == 3
            ? NetworkUploadPolicy.values.byName(
                value['networkUploadPolicy'] as String,
              )
            : NetworkUploadPolicy.wifiAndEthernet,
      );
    } catch (_) {
      throw const SettingsFailure('本机设置损坏或版本不兼容，已有设置保留；请使用兼容版本。');
    }
  }
  @override
  bool operator ==(Object other) =>
      other is DeviceSettings &&
      uploadConcurrency == other.uploadConcurrency &&
      processingConcurrency == other.processingConcurrency &&
      quality == other.quality &&
      longestSide == other.longestSide &&
      processingMode == other.processingMode &&
      cacheLimitMiB == other.cacheLimitMiB &&
      defaultOutputRetention == other.defaultOutputRetention &&
      networkUploadPolicy == other.networkUploadPolicy;
  @override
  int get hashCode => Object.hash(
    uploadConcurrency,
    processingConcurrency,
    quality,
    longestSide,
    processingMode,
    cacheLimitMiB,
    defaultOutputRetention,
    networkUploadPolicy,
  );
}
