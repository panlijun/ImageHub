part of 'library_repository.dart';

const _accountHealthPrefix = 'account_health_observation_v1/';
const _accountHealthStartedPrefix = 'account_health_started_v1/';

final class _AccountHealthStarted {
  const _AccountHealthStarted(
    this.targetGeneration,
    this.startedUtc,
    this.attemptId,
  );
  final int targetGeneration, startedUtc;
  final String attemptId;
  Map<String, Object> toJson() => {
    'formatVersion': 1,
    'targetGeneration': targetGeneration,
    'startedUtc': startedUtc,
    'attemptId': attemptId,
  };
}

final class _AccountHealthObservation {
  const _AccountHealthObservation(
    this.targetGeneration,
    this.startedUtc,
    this.attemptId,
    this.health,
  );
  final int targetGeneration, startedUtc;
  final String attemptId;
  final AccountHealth health;
  Map<String, Object> toJson() => {
    'formatVersion': 1,
    'targetGeneration': targetGeneration,
    'startedUtc': startedUtc,
    'attemptId': attemptId,
    'health': health.name,
  };
  int compareAttempt(UploadAttempt attempt) {
    final time = startedUtc.compareTo(attempt.startedUtc);
    return time == 0 ? attemptId.compareTo(attempt.id) : time;
  }
}

extension LibraryAccounts on LibraryRepository {
  Map<String, dynamic> _readAccountHealthFields(
    LibraryMetadataData row, {
    required bool observation,
  }) {
    try {
      final prefix = observation
          ? _accountHealthPrefix
          : _accountHealthStartedPrefix;
      if (!row.key.startsWith(prefix) ||
          !_replacementUuid.hasMatch(row.key.substring(prefix.length)) ||
          row.value.length > 1024 ||
          utf8.encode(row.value).length > 1024) {
        throw const FormatException();
      }
      final raw = jsonDecode(row.value);
      final keys = {
        'formatVersion',
        'targetGeneration',
        'startedUtc',
        'attemptId',
        if (observation) 'health',
      };
      if (raw is! Map<String, dynamic> ||
          raw.length != keys.length ||
          !raw.keys.every(keys.contains) ||
          raw['formatVersion'] is! int ||
          raw['formatVersion'] != 1 ||
          raw['targetGeneration'] is! int ||
          raw['targetGeneration'] < 1 ||
          raw['startedUtc'] is! int ||
          raw['startedUtc'] < 0 ||
          raw['startedUtc'] > 8640000000000000 ||
          raw['attemptId'] is! String ||
          !_replacementUuid.hasMatch(raw['attemptId'] as String) ||
          observation && raw['health'] is! String) {
        throw const FormatException();
      }
      if (observation &&
          !const {
            'available',
            'authorizationInvalid',
            'temporarilyUnavailable',
          }.contains(raw['health'])) {
        throw const FormatException();
      }
      return raw;
    } catch (_) {
      throw const AccountFailure('账号观察格式无法安全读取，原记录已保留；请使用兼容版本或检查资料库。');
    }
  }

  _AccountHealthObservation _readAccountHealthObservation(
    LibraryMetadataData row,
  ) {
    final raw = _readAccountHealthFields(row, observation: true);
    return _AccountHealthObservation(
      raw['targetGeneration'] as int,
      raw['startedUtc'] as int,
      raw['attemptId'] as String,
      AccountHealth.values.byName(raw['health'] as String),
    );
  }

  _AccountHealthStarted _readAccountHealthStarted(LibraryMetadataData row) {
    final raw = _readAccountHealthFields(row, observation: false);
    return _AccountHealthStarted(
      raw['targetGeneration'] as int,
      raw['startedUtc'] as int,
      raw['attemptId'] as String,
    );
  }

  Future<void> _validateAccountHealthObservations() async {
    final rows =
        await (_db.select(_db.libraryMetadata)..where(
              (t) =>
                  t.key.like('account_health_observation_v1/%') |
                  t.key.like('account_health_started_v1/%'),
            ))
            .get();
    for (final row in rows) {
      if (row.key.startsWith(_accountHealthPrefix)) {
        _readAccountHealthObservation(row);
      } else if (row.key.startsWith(_accountHealthStartedPrefix)) {
        _readAccountHealthStarted(row);
      }
    }
  }

  Future<_AccountHealthStarted?> _accountHealthStarted(String targetId) async {
    final row =
        await (_db.select(_db.libraryMetadata)..where(
              (t) => t.key.equals('$_accountHealthStartedPrefix$targetId'),
            ))
            .getSingleOrNull();
    return row == null ? null : _readAccountHealthStarted(row);
  }

  Future<_AccountHealthObservation?> _accountHealthObservation(
    String targetId,
  ) async {
    final row =
        await (_db.select(_db.libraryMetadata)
              ..where((t) => t.key.equals('$_accountHealthPrefix$targetId')))
            .getSingleOrNull();
    return row == null ? null : _readAccountHealthObservation(row);
  }

  Future<void> _clearAccountHealthObservations() async {
    final rows =
        await (_db.select(_db.libraryMetadata)..where(
              (t) =>
                  t.key.like('account_health_observation_v1/%') |
                  t.key.like('account_health_started_v1/%'),
            ))
            .get();
    for (final row in rows.where(
      (row) =>
          row.key.startsWith(_accountHealthPrefix) ||
          row.key.startsWith(_accountHealthStartedPrefix),
    )) {
      _readAccountHealthFields(
        row,
        observation: row.key.startsWith(_accountHealthPrefix),
      );
      await (_db.delete(
        _db.libraryMetadata,
      )..where((t) => t.key.equals(row.key))).go();
    }
  }

  Future<TargetUploadImpact> targetUploadImpact(String targetId) =>
      _serial(() async {
        if (_closing != null || !_replacementUuid.hasMatch(targetId)) {
          throw const AccountFailure('账号身份已失效，无法确认受影响任务；未修改配置。');
        }
        final target = await (_db.select(
          _db.providerTargets,
        )..where((t) => t.id.equals(targetId))).getSingleOrNull();
        if (target == null || target.removed) {
          throw const AccountFailure('账号已移除或不存在，无法确认受影响任务；未修改配置。');
        }
        final rows = await _db
            .customSelect(
              'SELECT state, COUNT(*) AS item_count FROM upload_publications '
              'WHERE target_id = ? GROUP BY state',
              variables: [Variable<String>(targetId)],
              readsFrom: {_db.uploadPublications},
            )
            .get();
        var pending = 0, running = 0, unknown = 0;
        for (final row in rows) {
          final count = row.read<int>('item_count');
          switch (row.read<String>('state')) {
            case 'queued':
            case 'waiting':
            case 'paused':
            case 'interrupted':
              pending += count;
            case 'running':
              running += count;
            case 'unknown':
              unknown += count;
            case 'succeeded':
            case 'failed':
            case 'cancelled':
              break;
            default:
              throw const AccountFailure('任务状态无法安全读取，未修改账号配置。');
          }
        }
        return TargetUploadImpact(
          targetId: targetId,
          pending: pending,
          running: running,
          unknown: unknown,
        );
      });

  Future<List<ProviderTarget>> listTargets({bool includeRemoved = false}) =>
      _serial(() async {
        await _recoverAccounts();
        final rows =
            await (_db.select(_db.providerTargets)..orderBy([
                  (t) => OrderingTerm.asc(t.createdUtc),
                  (t) => OrderingTerm.asc(t.id),
                ]))
                .get();
        final operations = await _db.select(_db.credentialOperations).get();
        final result = <ProviderTarget>[];
        for (final row in rows) {
          if (row.removed && !includeRemoved) continue;
          var health = AccountHealth.values.byName(row.health);
          final session = _sessionCredentials.containsKey(row.id);
          if (!row.anonymous && !row.removed) {
            try {
              final secret = session
                  ? _sessionCredentials[row.id]
                  : row.secretReference == null
                  ? null
                  : await _secretStore.read(row.secretReference!);
              if (secret == null) {
                health = AccountHealth.unconfigured;
              } else {
                _credential(secret);
                _secretRedactor.register(secret);
                // A valid current session may display the result observation
                // for this generation. Pending credential changes must still
                // remain unverified; a reopened session has no value above.
                if (session &&
                    (health == AccountHealth.unconfigured ||
                        operations.any((op) => op.targetId == row.id))) {
                  health = AccountHealth.unverified;
                }
              }
            } on SecretStorageException {
              health = AccountHealth.temporarilyUnavailable;
            } on AccountFailure {
              health = AccountHealth.unconfigured;
            }
          }
          result.add(
            _target(
              row,
              health: health,
              sessionOnly: session,
              pending: operations.any((op) => op.targetId == row.id),
            ),
          );
        }
        return List.unmodifiable(result);
      });

  ProviderTarget _target(
    ProviderTargetRow row, {
    AccountHealth? health,
    bool pending = false,
    bool sessionOnly = false,
  }) => ProviderTarget(
    id: row.id,
    service: ImageHostService.values.byName(row.service),
    alias: row.alias,
    enabled: row.enabled && !row.anonymous,
    selectedByDefault: row.selectedByDefault && !row.anonymous,
    anonymous: row.anonymous,
    health: health ?? AccountHealth.values.byName(row.health),
    removed: row.removed,
    generation: row.generation,
    pendingOperation: pending,
    sessionOnly: sessionOnly,
  );

  String _credential(String value) {
    final secret = value.trim();
    if (secret.isEmpty || secret.runes.any((c) => c <= 32 || c == 127)) {
      throw const AccountFailure('凭据不能为空，也不能包含空白或控制字符。');
    }
    return secret;
  }

  Future<String> saveTarget({
    String? id,
    required ImageHostService service,
    required String alias,
    required bool anonymous,
    bool enabled = true,
    bool selectedByDefault = false,
    String? credential,
    CredentialPersistence persistence = CredentialPersistence.protected,
  }) => _serial(
    () async {
      if (_closing != null) throw const AccountFailure('应用正在关闭，请重开后再配置。');
      if (anonymous) {
        throw const AccountFailure('匿名上传已停用，请添加具有凭据的独立账号目标。');
      }
      if (id != null) {
        final existing = await (_db.select(
          _db.providerTargets,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (existing?.anonymous ?? false) {
          throw const AccountFailure('既有匿名目标仅保留历史，可本地移除，不能修改或重新启用。');
        }
      }
      await _recoverAccounts();
      final secret = credential == null ? null : _credential(credential);
      if (secret != null) _secretRedactor.register(secret);
      final previous = id == null
          ? null
          : await (_db.select(
              _db.providerTargets,
            )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (id != null && (previous == null || previous.removed)) {
        throw const AccountFailure('该账号配置已移除，不能复用原身份。');
      }
      if (previous != null &&
          (previous.service != service.name ||
              previous.anonymous != anonymous)) {
        throw const AccountFailure('服务与匿名类型不能改变，请添加独立目标。');
      }
      if (previous?.secretReference != null) {
        try {
          final oldSecret = await _secretStore.read(previous!.secretReference!);
          if (oldSecret != null) _secretRedactor.register(oldSecret);
        } on SecretStorageException {
          if (alias.trim() != previous!.alias) {
            throw const AccountFailure('安全存储暂不可用，无法安全确认新别名；请保持原名称或稍后重试。');
          }
        }
      }
      final displayAlias = _secretRedactor.redactText(alias.trim());
      if (displayAlias.isEmpty ||
          displayAlias.runes.any((c) => c < 32 || c == 127)) {
        throw const AccountFailure('请填写不含控制字符的显示名称。');
      }
      if (previous != null &&
          await (_db.select(_db.credentialOperations)
                    ..where((t) => t.targetId.equals(previous.id)))
                  .getSingleOrNull() !=
              null) {
        throw const AccountFailure('该账号还有未完成的凭据操作，请恢复后再修改。');
      }
      if (secret == null &&
          previous?.secretReference == null &&
          !_sessionCredentials.containsKey(id)) {
        throw const AccountFailure('请填写此目标的凭据；配置不会上传图片验证。');
      }
      final targetId = previous?.id ?? const Uuid().v4();
      final now = clock.now().toUtc().millisecondsSinceEpoch;
      final proposal = <String, Object?>{
        'alias': displayAlias,
        'enabled': enabled,
        'default': selectedByDefault,
        'health': secret != null
            ? AccountHealth.unverified.name
            : previous!.health,
      };
      if (secret == null || persistence == CredentialPersistence.session) {
        // Explicit session choice never writes the credential to SQLite or disk.
        await _db.transaction(() async {
          if (previous == null) {
            await _db
                .into(_db.providerTargets)
                .insert(
                  ProviderTargetsCompanion.insert(
                    id: targetId,
                    service: service.name,
                    alias: displayAlias,
                    enabled: enabled,
                    selectedByDefault: selectedByDefault,
                    anonymous: false,
                    health: AccountHealth.unconfigured.name,
                    createdUtc: now,
                    modifiedUtc: now,
                  ),
                );
          } else {
            await (_db.update(
              _db.providerTargets,
            )..where((t) => t.id.equals(targetId))).write(
              ProviderTargetsCompanion(
                alias: Value(displayAlias),
                enabled: Value(enabled),
                selectedByDefault: Value(selectedByDefault),
                modifiedUtc: Value(now),
                secretReference:
                    secret != null &&
                        persistence == CredentialPersistence.session
                    ? const Value(null)
                    : const Value.absent(),
                health:
                    secret != null &&
                        persistence == CredentialPersistence.session
                    ? const Value('unconfigured')
                    : const Value.absent(),
                generation: Value(previous.generation + 1),
              ),
            );
            if (secret != null &&
                persistence == CredentialPersistence.session &&
                previous.secretReference != null) {
              await _db
                  .into(_db.credentialOperations)
                  .insert(
                    CredentialOperationsCompanion.insert(
                      id: const Uuid().v4(),
                      targetId: targetId,
                      action: 'forget',
                      proposalJson: '{}',
                      oldReference: Value(previous.secretReference),
                      createdUtc: now,
                    ),
                  );
            }
          }
        });
        if (secret != null) {
          _sessionCredentials[targetId] = secret;
        }
        _accountChanges.add(targetId);
        return targetId;
      }
      final operationId = const Uuid().v4();
      final reference = const Uuid().v4();
      await _db.transaction(() async {
        if (previous == null) {
          await _db
              .into(_db.providerTargets)
              .insert(
                ProviderTargetsCompanion.insert(
                  id: targetId,
                  service: service.name,
                  alias: displayAlias,
                  enabled: false,
                  selectedByDefault: false,
                  anonymous: false,
                  health: AccountHealth.unconfigured.name,
                  createdUtc: now,
                  modifiedUtc: now,
                ),
              );
        }
        await _db
            .into(_db.credentialOperations)
            .insert(
              CredentialOperationsCompanion.insert(
                id: operationId,
                targetId: targetId,
                action: 'activate',
                proposalJson: jsonEncode(proposal),
                newReference: Value(reference),
                oldReference: Value(previous?.secretReference),
                createdUtc: now,
              ),
            );
      });
      await _accountFaultHook?.call(AccountBoundary.intent);
      await _secretStore.write(reference, secret);
      if (await _secretStore.read(reference) != secret) {
        throw const SecretStorageException();
      }
      await _accountFaultHook?.call(AccountBoundary.secretWritten);
      await _applyCredentialOperation(operationId);
      _sessionCredentials.remove(targetId);
      _accountChanges.add(targetId);
      return targetId;
    },
    diagnostic: _DiagnosticAction(
      DiagnosticKind.account,
      'account.save',
      '上传目标配置已提交，凭据能力以安全存储核查为准。',
      '请到账号页核查配置状态，未完成的凭据操作可重开后重试。',
      entityId: id,
    ),
  );

  Future<void> removeTarget(String id) => _serial(
    () async {
      if (_closing != null) throw const AccountFailure('应用正在关闭，请重开后再配置。');
      await _recoverAccounts();
      final row = await (_db.select(
        _db.providerTargets,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) throw const AccountFailure('目标不存在。');
      final pending = await (_db.select(
        _db.credentialOperations,
      )..where((t) => t.targetId.equals(id))).getSingleOrNull();
      if (row.removed) {
        if (pending != null) await _applyCredentialOperation(pending.id);
        return;
      }
      final operationId = pending?.id ?? const Uuid().v4();
      await _db.transaction(() async {
        await (_db.update(
          _db.providerTargets,
        )..where((t) => t.id.equals(id))).write(
          ProviderTargetsCompanion(
            removed: const Value(true),
            enabled: const Value(false),
            selectedByDefault: const Value(false),
            generation: Value(row.generation + 1),
            modifiedUtc: Value(clock.now().toUtc().millisecondsSinceEpoch),
          ),
        );
        if (pending == null) {
          await _db
              .into(_db.credentialOperations)
              .insert(
                CredentialOperationsCompanion.insert(
                  id: operationId,
                  targetId: id,
                  action: 'remove',
                  proposalJson: '{}',
                  oldReference: Value(row.secretReference),
                  createdUtc: clock.now().toUtc().millisecondsSinceEpoch,
                ),
              );
        } else {
          await (_db.update(
            _db.credentialOperations,
          )..where((t) => t.id.equals(operationId))).write(
            const CredentialOperationsCompanion(
              action: Value('remove'),
              proposalJson: Value('{}'),
            ),
          );
        }
      });
      _sessionCredentials.remove(id);
      _accountChanges.add(id);
      await _accountFaultHook?.call(AccountBoundary.intent);
      await _applyCredentialOperation(operationId);
    },
    diagnostic: _DiagnosticAction(
      DiagnosticKind.account,
      'account.remove',
      '目标已停止派发，安全凭据清理已完成。',
      '请在账号页核查，清理失败保留记录后重试。',
      entityId: id,
    ),
  );

  Future<ResolvedTarget> resolveTarget(String id) =>
      _serial(() => _resolveTarget(id));

  Future<ResolvedTarget> _resolveTarget(String id) async {
    if (_closing != null) throw const AccountFailure('应用正在关闭。');
    await _recoverAccounts();
    final row = await (_db.select(
      _db.providerTargets,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null || row.removed || !row.enabled) {
      throw const AccountFailure('目标已停用或移除，不能派发请求。');
    }
    final pending = await (_db.select(
      _db.credentialOperations,
    )..where((t) => t.targetId.equals(id))).getSingleOrNull();
    if (pending != null &&
        !(pending.action == 'forget' && _sessionCredentials.containsKey(id))) {
      throw const AccountFailure('凭据操作待恢复，不能派发请求。');
    }
    if (row.anonymous) {
      throw const AccountFailure('匿名上传已停用，既有任务不会派发；请取消或使用账号新建任务。');
    }
    final secret =
        _sessionCredentials[id] ??
        (row.secretReference == null
            ? null
            : await _secretStore.read(row.secretReference!));
    if (secret == null) throw const AccountFailure('凭据缺失，请重新配置授权。');
    final validSecret = _credential(secret);
    _secretRedactor.register(validSecret);
    return ResolvedTarget(
      _target(row, sessionOnly: _sessionCredentials.containsKey(id)),
      validSecret,
    );
  }

  Future<void> _recoverAccounts() async {
    await _validateAccountHealthObservations();
    final operations = await _db.select(_db.credentialOperations).get();
    for (final operation in operations) {
      try {
        await _applyCredentialOperation(operation.id);
      } on SecretStorageException {
        // Secure backend failure must not prevent independent local gallery use.
      } catch (_) {
        if (!_recoveryIssues.any(
          (issue) => issue.operationId == operation.id,
        )) {
          _recoveryIssues = List.unmodifiable([
            ..._recoveryIssues,
            RecoveryIssue(operation.id, '一项账号凭据操作无法安全恢复，已保留记录，请检查账号页面。'),
          ]);
        }
      }
    }
  }

  Future<void> _applyCredentialOperation(String id) async {
    final operation = await (_db.select(
      _db.credentialOperations,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (operation == null) return;
    final row = await (_db.select(
      _db.providerTargets,
    )..where((t) => t.id.equals(operation.targetId))).getSingle();
    if (operation.action == 'activate') {
      final newReference = operation.newReference!;
      if (row.secretReference != newReference) {
        final secret = await _secretStore.read(newReference);
        if (secret == null) {
          // Intent exists, but secure bytes never committed: preserve prior state.
          await (_db.delete(
            _db.credentialOperations,
          )..where((t) => t.id.equals(id))).go();
          return;
        }
        _credential(secret);
        _secretRedactor.register(secret);
        final proposal =
            jsonDecode(operation.proposalJson) as Map<String, dynamic>;
        await (_db.update(
          _db.providerTargets,
        )..where((t) => t.id.equals(row.id))).write(
          ProviderTargetsCompanion(
            alias: Value(
              _secretRedactor.redactText(proposal['alias'] as String),
            ),
            enabled: Value(proposal['enabled'] as bool),
            selectedByDefault: Value(proposal['default'] as bool),
            health: Value(AccountHealth.unverified.name),
            secretReference: Value(newReference),
            modifiedUtc: Value(clock.now().toUtc().millisecondsSinceEpoch),
            generation: Value(row.generation + 1),
          ),
        );
        await _accountFaultHook?.call(AccountBoundary.associated);
      }
    } else if (operation.action != 'remove' && operation.action != 'forget') {
      throw const AccountFailure('凭据恢复记录无法识别，请保留数据。');
    }
    if (operation.action == 'remove' && operation.newReference != null) {
      await _secretStore.delete(operation.newReference!);
      if (await _secretStore.read(operation.newReference!) != null) {
        throw const SecretStorageException();
      }
    }
    if (operation.oldReference != null) {
      await _secretStore.delete(operation.oldReference!);
      if (await _secretStore.read(operation.oldReference!) != null) {
        throw const SecretStorageException();
      }
      await _accountFaultHook?.call(AccountBoundary.secretDeleted);
    }
    await _db.transaction(() async {
      if (operation.action == 'remove') {
        await (_db.update(
          _db.providerTargets,
        )..where((t) => t.id.equals(row.id))).write(
          const ProviderTargetsCompanion(
            secretReference: Value(null),
            health: Value('unconfigured'),
          ),
        );
      }
      await (_db.delete(
        _db.credentialOperations,
      )..where((t) => t.id.equals(id))).go();
    });
  }
}
