part of 'library_repository.dart';

final class SettingsSnapshot {
  SettingsSnapshot._(
    this._owner,
    this._epoch,
    this._fingerprint,
    this.values,
    Iterable<ProviderTarget> targets,
  ) : targets = List.unmodifiable(targets),
      defaultTargetIds = Set.unmodifiable(
        targets.where((t) => t.selectedByDefault).map((t) => t.id),
      );
  final LibraryRepository _owner;
  final String _epoch, _fingerprint;
  final DeviceSettings values;
  final List<ProviderTarget> targets;
  final Set<String> defaultTargetIds;
}

extension LibrarySettings on LibraryRepository {
  static const _settingsKey = 'device_settings_v1';

  /// Only declared target platforms participate; host paths and authorization
  /// are never fields of a portable setting.
  BackupSettingsRestorePlan planBackupSettings(
    BackupDeviceSettings? incoming,
  ) => BackupSettingsRestorePlan.plan(
    current: _deviceSettings,
    incoming: incoming,
    platform: Platform.isWindows
        ? BackupPlatform.windows
        : Platform.isMacOS
        ? BackupPlatform.macos
        : Platform.isAndroid
        ? BackupPlatform.android
        : Platform.isIOS
        ? BackupPlatform.ios
        : throw const SettingsFailure('当前平台不在备份设置恢复范围内。'),
  );

  // Called inside the same transaction as the restored business relations.
  // A failed/cancelled relation commit must roll back these values as well.
  Future<void> _writeRestoredSettings(BackupSettingsRestorePlan plan) async {
    await _verifyRestoreSettings(plan);
    if (plan.restored.isEmpty) return;
    DeviceSettings.fromJson(plan.values.toJson());
    await _db
        .into(_db.libraryMetadata)
        .insertOnConflictUpdate(
          LibraryMetadataCompanion.insert(
            key: _settingsKey,
            value: jsonEncode(plan.values.toJson()),
          ),
        );
  }

  Future<void> _verifyRestoreSettings(BackupSettingsRestorePlan plan) async {
    if (await _readDeviceSettings() != plan.current) {
      throw const SettingsFailure('本机设置已变化，未提交恢复；请重新预检和确认。');
    }
  }

  Future<BackupSettingsRestorePlan> _checkedBackupSettingsPlan(
    BackupDeviceSettings? incoming,
  ) => _serial(() async {
    if (await _readDeviceSettings() != _deviceSettings) {
      throw const SettingsFailure('本机设置与已加载状态不一致，未准备恢复；请重开核查。');
    }
    return planBackupSettings(incoming);
  }, maintenance: true);

  // Publish only after SQLite has confirmed the associated restore commit.
  void _activateRestoredSettings(BackupSettingsRestorePlan plan) {
    if (plan.restored.isEmpty) return;
    _deviceSettings = plan.values;
    if (_closing == null && !_closed) {
      processingScheduler.configure(plan.values.processingConcurrency);
      _settingsChanges.add(null);
    }
  }

  Future<DeviceSettings> _readDeviceSettings() async {
    final row = await (_db.select(
      _db.libraryMetadata,
    )..where((t) => t.key.equals(_settingsKey))).getSingleOrNull();
    if (row == null) return DeviceSettings.defaults;
    try {
      return DeviceSettings.fromJson(jsonDecode(row.value));
    } catch (_) {
      throw const SettingsFailure('本机设置无法安全加载，原值已保留，未使用空默认覆盖。');
    }
  }

  Future<String> _settingsFingerprint() async {
    final row = await (_db.select(
      _db.libraryMetadata,
    )..where((t) => t.key.equals(_settingsKey))).getSingleOrNull();
    final targets = await (_db.select(
      _db.providerTargets,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    final pending = await (_db.select(
      _db.credentialOperations,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    return hashing.sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'settings': row?.value,
              'targets': [
                for (final t in targets)
                  [
                    t.id,
                    t.generation,
                    t.enabled,
                    t.removed,
                    t.selectedByDefault,
                  ],
              ],
              'pending': [
                for (final op in pending) [op.id, op.targetId],
              ],
            }),
          ),
        )
        .toString();
  }

  Future<SettingsSnapshot> loadSettings() => _serial(() async {
    var namesSafe = true;
    try {
      await _syncOrdinaryLinkMasks();
    } catch (_) {
      namesSafe = false;
    }
    final values = await _readDeviceSettings();
    final rows =
        await (_db.select(_db.providerTargets)
              ..where((t) => t.removed.not())
              ..orderBy([
                (t) => OrderingTerm.asc(t.createdUtc),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    final operations = await _db.select(_db.credentialOperations).get();
    final targets = rows.map(
      (row) => ProviderTarget(
        id: row.id,
        service: ImageHostService.values.byName(row.service),
        alias: namesSafe
            ? _secretRedactor.redactText(row.alias)
            : SecretRedactor.unavailable,
        enabled: row.enabled && !row.anonymous,
        selectedByDefault: row.selectedByDefault && !row.anonymous,
        anonymous: row.anonymous,
        health: AccountHealth.values.byName(row.health),
        removed: row.removed,
        generation: row.generation,
        pendingOperation: operations.any((op) => op.targetId == row.id),
        sessionOnly: _sessionCredentials.containsKey(row.id),
      ),
    );
    return SettingsSnapshot._(
      this,
      _executionEpoch,
      await _settingsFingerprint(),
      values,
      targets,
    );
  });

  Future<void> saveSettings(
    SettingsSnapshot expected,
    DeviceSettings values, {
    required Iterable<String> defaultTargetIds,
  }) => _serial(
    () async {
      if (_closing != null ||
          !identical(expected._owner, this) ||
          expected._epoch != _executionEpoch ||
          await _settingsFingerprint() != expected._fingerprint) {
        throw const SettingsFailure('设置或目标已变化，请重新读取后再保存；旧有效值保留。');
      }
      // Validate again at the storage boundary, before any changes.
      DeviceSettings.fromJson(values.toJson());
      final ids = defaultTargetIds.toSet();
      final candidates = {
        for (final target in expected.targets) target.id: target,
      };
      for (final id in ids) {
        final target = candidates[id];
        if (target == null ||
            target.anonymous ||
            !target.enabled && !expected.defaultTargetIds.contains(id)) {
          throw const SettingsFailure('默认目标不可用或正在变更，请重新选择；未保存。');
        }
      }
      for (final target in expected.targets) {
        if (target.pendingOperation &&
            ids.contains(target.id) != target.selectedByDefault) {
          throw const SettingsFailure('目标凭据操作尚未完成，请稍后重试；未保存。');
        }
      }
      try {
        await _db.transaction(() async {
          await _db
              .into(_db.libraryMetadata)
              .insertOnConflictUpdate(
                LibraryMetadataCompanion.insert(
                  key: _settingsKey,
                  value: jsonEncode(values.toJson()),
                ),
              );
          for (final target in expected.targets) {
            final selected = ids.contains(target.id);
            if (selected != target.selectedByDefault) {
              await (_db.update(
                _db.providerTargets,
              )..where((t) => t.id.equals(target.id))).write(
                ProviderTargetsCompanion(selectedByDefault: Value(selected)),
              );
            }
          }
        });
      } catch (_) {
        throw const SettingsFailure('设置保存未确认，旧有效值保留；请检查后重试。');
      }
      _deviceSettings = values;
      if (_closing == null) {
        processingScheduler.configure(values.processingConcurrency);
      }
      _settingsChanges.add(null);
      // Do not make a confirmed settings commit depend on cache maintenance.
      unawaited(_maintainThumbnailCache());
      // Default selection is not a credential/authorization change. Reusing
      // accountChanges here would revoke running requests, violating OPS-001.
      if (expected.targets.any(
        (t) => ids.contains(t.id) != t.selectedByDefault,
      )) {
        _uploadChanges.add(null);
      }
    },
    diagnostic: const _DiagnosticAction(
      DiagnosticKind.settings,
      'settings.save',
      '本机设置已确认保存，后续工作使用新策略。',
      '保存失败时重新读取有效值，检查存储后重试。',
    ),
  );
}
