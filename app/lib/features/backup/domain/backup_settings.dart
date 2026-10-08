import '../../settings/domain/device_settings.dart';

enum BackupPlatform { windows, macos, android, ios }

enum BackupSetting {
  uploadConcurrency,
  processingConcurrency,
  quality,
  longestSide,
  processingMode,
  cacheLimitMiB,
  defaultOutputRetention,
  networkUploadPolicy;

  String get label => switch (this) {
    uploadConcurrency => '上传并发',
    processingConcurrency => '处理并发',
    quality => '有损输出质量',
    longestSide => '体积优先最长边',
    processingMode => '默认处理模式',
    cacheLimitMiB => '缩略图缓存上限',
    defaultOutputRetention => '临时输出默认保留时间',
    networkUploadPolicy => '允许上传的网络类型',
  };
}

/// Portable policy values only. No credential, target, permission or path.
final class BackupDeviceSettings {
  BackupDeviceSettings({
    required this.values,
    Map<BackupSetting, Set<BackupPlatform>> availability = const {},
  }) : availability = Map.unmodifiable({
         for (final setting in BackupSetting.values)
           setting: Set<BackupPlatform>.unmodifiable(
             availability[setting] ?? BackupPlatform.values,
           ),
       });

  static const formatVersion = 1;
  final DeviceSettings values;
  final Map<BackupSetting, Set<BackupPlatform>> availability;

  Map<String, Object?> toJson() => {
    'formatVersion': formatVersion,
    'values': values.toJson(),
    'availability': {
      for (final setting in BackupSetting.values)
        setting.name: [
          for (final platform in BackupPlatform.values)
            if (availability[setting]!.contains(platform)) platform.name,
        ],
    },
  };

  factory BackupDeviceSettings.fromJson(Object? value) {
    try {
      const envelopeKeys = {'formatVersion', 'values', 'availability'};
      if (value is! Map ||
          !_hasKeys(value, envelopeKeys) ||
          value['formatVersion'] is! int ||
          value['formatVersion'] != formatVersion) {
        _invalid();
      }
      final rawValues = value['values'];
      if (rawValues is! Map ||
          rawValues['formatVersion'] is! int ||
          rawValues['formatVersion'] != 3) {
        _invalid();
      }
      final values = DeviceSettings.fromJson(rawValues);
      final rawAvailability = value['availability'];
      if (rawAvailability is! Map ||
          !_hasKeys(
            rawAvailability,
            BackupSetting.values.map((setting) => setting.name).toSet(),
          )) {
        _invalid();
      }
      final availability = <BackupSetting, Set<BackupPlatform>>{};
      for (final setting in BackupSetting.values) {
        final rawPlatforms = rawAvailability[setting.name];
        if (rawPlatforms is! List ||
            rawPlatforms.length > BackupPlatform.values.length) {
          _invalid();
        }
        final platforms = <BackupPlatform>{};
        for (final rawPlatform in rawPlatforms) {
          if (rawPlatform is! String) _invalid();
          final platform = BackupPlatform.values.byName(rawPlatform);
          if (!platforms.add(platform)) _invalid();
        }
        availability[setting] = platforms;
      }
      return BackupDeviceSettings(values: values, availability: availability);
    } catch (_) {
      _invalid();
    }
  }
}

/// Compute policy application separately from metadata identity merging.
final class BackupSettingsRestorePlan {
  BackupSettingsRestorePlan._({
    required this.current,
    required this.values,
    required this.included,
    required Iterable<BackupSetting> restored,
    required Iterable<BackupSetting> skipped,
  }) : restored = List.unmodifiable(restored),
       skipped = List.unmodifiable(skipped);

  final DeviceSettings values;
  final DeviceSettings current;
  final bool included;
  final List<BackupSetting> restored, skipped;

  String get message => !included
      ? '备份未包含设置，保留当前本机设置。'
      : restored.isEmpty
      ? '当前平台没有可恢复的备份设置，保留当前本机设置。'
      : skipped.isEmpty
      ? '备份设置可在当前平台恢复。'
      : '仅恢复当前平台可用的设置，其余设置保留本机值。';

  static BackupSettingsRestorePlan plan({
    required DeviceSettings current,
    required BackupDeviceSettings? incoming,
    required BackupPlatform platform,
  }) {
    final values = current.toJson();
    final incomingValues = incoming?.values.toJson();
    final restored = <BackupSetting>[], skipped = <BackupSetting>[];
    for (final setting in BackupSetting.values) {
      if (incoming != null &&
          incoming.availability[setting]!.contains(platform)) {
        values[setting.name] = incomingValues![setting.name]!;
        restored.add(setting);
      } else {
        skipped.add(setting);
      }
    }
    return BackupSettingsRestorePlan._(
      current: current,
      values: incoming == null ? current : DeviceSettings.fromJson(values),
      included: incoming != null,
      restored: restored,
      skipped: skipped,
    );
  }
}

bool _hasKeys(Map value, Set<String> keys) =>
    value.length == keys.length &&
    value.keys.every((key) => key is String && keys.contains(key));

Never _invalid() => throw const SettingsFailure('备份设置损坏或版本不兼容，未恢复设置。');
