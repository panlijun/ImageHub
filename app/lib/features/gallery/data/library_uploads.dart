part of 'library_repository.dart';

/// All public mutations use the repository's sole writer gate. Private helpers
/// deliberately never acquire that gate again.
extension LibraryUploads on LibraryRepository {
  int get _uploadNow => clock.now().toUtc().millisecondsSinceEpoch;

  Map<String, Object?> _inputSnapshot(FrozenUploadInput input) => {
    'kind': input.kind.name,
    'referenceId': input.referenceId,
    'displayName': _secretRedactor.redactText(input.displayName),
    'version': versionSnapshot(input.version),
    'policyKey': input.policyKey,
    'processingSummary': input.processingSummary == null
        ? null
        : _secretRedactor.redactText(input.processingSummary!),
  };

  FrozenUploadInput _readUploadInput(String value) {
    final data = jsonDecode(value) as Map<String, dynamic>;
    return FrozenUploadInput(
      kind: UploadInputKind.values.byName(data['kind'] as String),
      referenceId: data['referenceId'] as String,
      displayName: _secretRedactor.redactText(data['displayName'] as String),
      version: versionFromSnapshot(
        (data['version'] as Map).cast<String, Object?>(),
      ),
      policyKey: data['policyKey'] as String,
      processingSummary: data['processingSummary'] == null
          ? null
          : _secretRedactor.redactText(data['processingSummary'] as String),
    );
  }

  Map<String, Object?> _targetSnapshot(TargetSnapshot target) => {
    'id': target.id,
    'service': target.service.name,
    'alias': _secretRedactor.redactText(target.alias),
    'anonymous': target.anonymous,
  };

  TargetSnapshot _readUploadTarget(String value) {
    final data = jsonDecode(value) as Map<String, dynamic>;
    return TargetSnapshot(
      data['id'] as String,
      ImageHostService.values.byName(data['service'] as String),
      _secretRedactor.redactText(data['alias'] as String),
      data['anonymous'] as bool,
    );
  }

  UploadPublication _publication(UploadPublicationRow row) => UploadPublication(
    id: row.id,
    batchId: row.batchId,
    position: row.position,
    input: _readUploadInput(row.inputJson),
    target: _readUploadTarget(row.targetJson),
    state: PublishState.values.byName(row.state),
    userPaused: row.userPaused,
    attemptCount: row.attemptCount,
    generation: row.generation,
    accumulatedRunning: Duration(microseconds: row.accumulatedRunningMicros),
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdUtc, isUtc: true),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedUtc, isUtc: true),
    waitReason: row.waitReason == null
        ? null
        : QueueWaitReason.values.byName(row.waitReason!),
    retryDelay: row.retryDelayMicros == null
        ? null
        : Duration(microseconds: row.retryDelayMicros!),
    currentAttemptId: row.currentAttemptId,
    resultId: row.resultId,
    processingJobId: row.processingJobId,
    message: row.message == null
        ? null
        : _secretRedactor.redactText(row.message!),
  );

  Future<UploadPublicationRow> _uploadRow(String id) => (_db.select(
    _db.uploadPublications,
  )..where((t) => t.id.equals(id))).getSingle();

  Future<UploadBatch> _uploadBatch(UploadBatchRow row) async {
    final items =
        await (_db.select(_db.uploadPublications)
              ..where((t) => t.batchId.equals(row.id))
              ..orderBy([(t) => OrderingTerm.asc(t.position)]))
            .get();
    return UploadBatch(
      id: row.id,
      intentId: row.intentId,
      paused: row.paused,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row.createdUtc,
        isUtc: true,
      ),
      items: items.map(_publication),
    );
  }

  Future<List<UploadBatch>> listUploadBatches() => _serial(() async {
    final rows =
        await (_db.select(_db.uploadBatches)..orderBy([
              (t) => OrderingTerm.desc(t.createdUtc),
              (t) => OrderingTerm.asc(t.id),
            ]))
            .get();
    return List.unmodifiable(await Future.wait(rows.map(_uploadBatch)));
  });

  Future<List<UploadAttemptRecord>> listUploadAttempts(String itemId) =>
      _serial(() async {
        final rows =
            await (_db.select(_db.uploadAttempts)
                  ..where((t) => t.itemId.equals(itemId))
                  ..orderBy([(t) => OrderingTerm.asc(t.generation)]))
                .get();
        return List.unmodifiable(
          rows.map(
            (row) => UploadAttemptRecord(
              id: row.id,
              itemId: row.itemId,
              generation: row.generation,
              startedAt: DateTime.fromMillisecondsSinceEpoch(
                row.startedUtc,
                isUtc: true,
              ),
              requestMayHaveStarted: row.requestMayHaveStarted,
              endedAt: row.endedUtc == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(
                      row.endedUtc!,
                      isUtc: true,
                    ),
              outcome: row.outcome,
            ),
          ),
        );
      });

  Future<List<RemoteUploadResult>> listUploadResults() => _serial(() async {
    await _syncOrdinaryLinkMasks();
    final rows =
        await (_db.select(_db.remoteUploadResults)..orderBy([
              (t) => OrderingTerm.desc(t.confirmedUtc),
              (t) => OrderingTerm.asc(t.id),
            ]))
            .get();
    return List.unmodifiable(rows.map(_linkResult));
  });

  /// Stable canonical processing snapshot excludes all runtime paths. The
  /// pixel engine's versioned parameters remain part of the policy identity.
  String _processedUploadCanonical(String requestJson) {
    Object? canonical(Object? value) {
      if (value is Map) {
        final keys =
            value.keys.cast<String>().where((key) => key != 'path').toList()
              ..sort();
        return {for (final key in keys) key: canonical(value[key])};
      }
      if (value is List) return value.map(canonical).toList();
      return value;
    }

    return jsonEncode(canonical(jsonDecode(requestJson)));
  }

  String _processedUploadPolicy(String requestJson) =>
      'processed-confirmed-v1:${hashing.sha256.convert(utf8.encode(_processedUploadCanonical(requestJson)))}';

  Future<UploadBatch> enqueueUploads({
    required String intentId,
    Iterable<String> assetIds = const [],
    Iterable<String> outputIds = const [],
    Iterable<UploadProcessingSelection> processing = const [],
    required Iterable<String> targetIds,
    bool allowOriginalMetadata = false,
    bool forceAgain = false,
  }) => _serial(() async {
    if (_closing != null) throw const UploadQueueFailure('图库正在关闭。');
    if (intentId.trim().isEmpty || intentId.length > 200) {
      throw const UploadQueueFailure('上传意图无效。');
    }
    final previous = await (_db.select(
      _db.uploadBatches,
    )..where((t) => t.intentId.equals(intentId))).getSingleOrNull();
    if (previous != null) return _uploadBatch(previous);
    final assets = assetIds.toSet(),
        outputs = outputIds.toSet(),
        targets = targetIds.toSet();
    final processingSelections = processing.toList(growable: false);
    if ((assets.isEmpty && outputs.isEmpty && processingSelections.isEmpty) ||
        targets.isEmpty) {
      throw const UploadQueueFailure('请选择非空的输入和目标。');
    }
    if (assets.isNotEmpty && !allowOriginalMetadata) {
      throw const UploadQueueFailure('上传原图须明确确认可能保留原始元数据。');
    }
    await _recoverAccounts();
    final targetRows = <ProviderTargetRow>[];
    for (final id in targets) {
      final row = await (_db.select(
        _db.providerTargets,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null || row.removed) {
        throw const UploadQueueFailure('目标不存在或已移除。');
      }
      if (row.anonymous) {
        throw const UploadQueueFailure('匿名上传已停用，请选择具有凭据的账号目标。');
      }
      // Register even disabled targets, and all selected secrets BEFORE any
      // snapshot: one target's alias can contain another target's credential.
      try {
        final secret =
            _sessionCredentials[id] ??
            (row.secretReference == null
                ? null
                : await _secretStore.read(row.secretReference!));
        if (secret != null) _secretRedactor.register(secret);
      } on SecretStorageException {
        /* local enqueue remains available */
      }
      targetRows.add(row);
    }
    final snapshots = targetRows
        .map(
          (row) => TargetSnapshot(
            row.id,
            ImageHostService.values.byName(row.service),
            _secretRedactor.redactText(row.alias),
            row.anonymous,
          ),
        )
        .toList();
    final inputs = <FrozenUploadInput>[];
    final jobs = <String, (String, FrozenProcessingPlan, OutputRetention)>{};
    final jobByInput = <FrozenUploadInput, String>{};
    for (final id in assets) {
      final row = await (_db.select(
        _db.assets,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null || row.recycled) {
        throw const UploadQueueFailure('原图不存在或已回收。');
      }
      final asset = await _asset(row);
      await _rejectPendingPurge({asset.version.id});
      final input = FrozenUploadInput(
        kind: UploadInputKind.original,
        referenceId: id,
        displayName: _secretRedactor.redactText(asset.displayName),
        version: asset.version,
        policyKey: 'original-confirmed-v1',
      );
      await _uploadInputFile(input);
      inputs.add(input);
    }
    for (final selection in processingSelections) {
      final sources = <ProcessingInput>[];
      for (final id in selection.assetIds) {
        final row = await (_db.select(
          _db.assets,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (row == null || row.recycled) {
          throw const UploadQueueFailure('处理来源不存在或已回收。');
        }
        final asset = await _asset(row);
        await _rejectPendingPurge({asset.version.id});
        sources.add(
          ProcessingInput(
            file: await _files.file(asset.deviceCopy.relativePath),
            assetId: id,
            version: asset.version,
            selectedFrame: selection.selectedFrames[id],
          ),
        );
      }
      final plan = FrozenProcessingPlan.capture(selection.recipe.bind(sources));
      final job = jobs.putIfAbsent(
        plan.batchReuseKey,
        () => (
          const Uuid().v4(),
          plan,
          currentDeviceSettings.defaultOutputRetention,
        ),
      );
      if (jobByInput.values.contains(job.$1)) continue;
      final first = sources.first;
      final sourceRow = await (_db.select(
        _db.assets,
      )..where((t) => t.id.equals(first.assetId))).getSingle();
      final input = FrozenUploadInput(
        kind: UploadInputKind.original,
        referenceId: first.assetId,
        displayName: _secretRedactor.redactText(
          selection.displayName ?? sourceRow.displayName,
        ),
        version: first.version,
        policyKey: plan.policyKey,
        processingSummary: _secretRedactor.redactText(plan.canonical),
      );
      jobByInput[input] = job.$1;
      inputs.add(input);
    }
    for (final id in outputs) {
      final row = await _outputRow(id);
      if (row.state != 'ready' || row.versionJson == null) {
        throw const UploadQueueFailure('只能上传已确认的可用处理结果。');
      }
      final input = FrozenUploadInput(
        kind: UploadInputKind.processed,
        referenceId: id,
        displayName: _secretRedactor.redactText(row.displayName),
        version: versionFromSnapshot(
          (jsonDecode(row.versionJson!) as Map).cast<String, Object?>(),
        ),
        policyKey: _processedUploadPolicy(row.requestJson),
        processingSummary: _secretRedactor.redactText(
          _processedUploadCanonical(row.requestJson),
        ),
      );
      await _uploadInputFile(input);
      inputs.add(input);
    }
    final batchId = const Uuid().v4(), now = _uploadNow;
    await _db.transaction(() async {
      await _db
          .into(_db.uploadBatches)
          .insert(
            UploadBatchesCompanion.insert(
              id: batchId,
              intentId: intentId,
              createdUtc: now,
            ),
          );
      var position = 0;
      for (final job in jobs.values) {
        await _db
            .into(_db.uploadProcessingJobs)
            .insert(
              UploadProcessingJobsCompanion.insert(
                id: job.$1,
                batchId: batchId,
                policyKey: job.$2.policyKey,
                requestJson: jsonEncode({
                  'plan': job.$2.toJson(),
                  'retention': job.$3.name,
                  'forceAgain': forceAgain,
                }),
                state: UploadProcessingState.queued.name,
                createdUtc: now,
                updatedUtc: now,
              ),
            );
        for (final version in job.$2.versions) {
          await _db
              .into(_db.versionReferences)
              .insert(
                VersionReferencesCompanion.insert(
                  id: const Uuid().v4(),
                  versionId: version.id,
                  ownerType: 'task',
                  ownerId: job.$1,
                ),
                mode: InsertMode.insertOrIgnore,
              );
        }
      }
      for (final input in inputs) {
        for (final target in snapshots) {
          final id = const Uuid().v4();
          var publicationInput = input;
          String? reused;
          final processingJobId = jobByInput[input];
          var state = processingJobId == null
              ? PublishState.queued
              : PublishState.waiting;
          if (!forceAgain && processingJobId == null) {
            final results =
                await (_db.select(_db.remoteUploadResults)..where(
                      (t) =>
                          t.targetId.equals(target.id) &
                          t.versionDigest.equals(input.version.sha256) &
                          t.byteCount.equals(input.version.byteCount) &
                          t.policyKey.equals(input.policyKey),
                    ))
                    .get();
            for (final result in results) {
              try {
                if (result.linkState == LinkAvailability.deleted.name) continue;
                _safeUploadUrl(Uri.parse(result.directUrl));
                reused = result.id;
                break;
              } catch (_) {
                /* unusable history is not a dispatch receipt */
              }
            }
            if (reused != null) {
              state = PublishState.succeeded;
            } else {
              final unknown =
                  await (_db.select(_db.uploadPublications)..where(
                        (t) =>
                            t.targetId.equals(target.id) &
                            t.versionDigest.equals(input.version.sha256) &
                            t.byteCount.equals(input.version.byteCount) &
                            t.policyKey.equals(input.policyKey) &
                            t.state.equals('unknown'),
                      ))
                      .get();
              if (unknown.isNotEmpty) state = PublishState.unknown;
            }
          }
          if (!forceAgain && processingJobId != null) {
            final results =
                await (_db.select(_db.remoteUploadResults)..where(
                      (t) =>
                          t.targetId.equals(target.id) &
                          t.policyKey.equals(input.policyKey),
                    ))
                    .get();
            for (final result in results) {
              try {
                if (result.linkState == LinkAvailability.deleted.name) continue;
                _safeUploadUrl(Uri.parse(result.directUrl));
                final confirmed = _readUploadInput(result.inputJson);
                if (confirmed.kind != UploadInputKind.processed ||
                    confirmed.policyKey != input.policyKey ||
                    confirmed.version.sha256 != result.versionDigest ||
                    confirmed.version.byteCount != result.byteCount) {
                  continue;
                }
                publicationInput = FrozenUploadInput(
                  kind: confirmed.kind,
                  referenceId: confirmed.referenceId,
                  displayName: input.displayName,
                  version: confirmed.version,
                  policyKey: confirmed.policyKey,
                  processingSummary: confirmed.processingSummary,
                );
                reused = result.id;
                state = PublishState.succeeded;
                break;
              } catch (_) {
                /* an invalid receipt cannot complete an intent */
              }
            }
            if (reused == null) {
              final unknown =
                  await (_db.select(_db.uploadPublications)..where(
                        (t) =>
                            t.targetId.equals(target.id) &
                            t.policyKey.equals(input.policyKey) &
                            t.state.equals('unknown'),
                      ))
                      .get();
              if (unknown.isNotEmpty) {
                publicationInput = _readUploadInput(unknown.first.inputJson);
                state = PublishState.unknown;
              }
            }
          }
          await _db
              .into(_db.uploadPublications)
              .insert(
                UploadPublicationsCompanion.insert(
                  id: id,
                  batchId: batchId,
                  position: position++,
                  inputJson: jsonEncode(_inputSnapshot(publicationInput)),
                  targetJson: jsonEncode(_targetSnapshot(target)),
                  targetId: target.id,
                  versionDigest: publicationInput.version.sha256,
                  byteCount: publicationInput.version.byteCount,
                  policyKey: publicationInput.policyKey,
                  state: state.name,
                  createdUtc: now,
                  updatedUtc: now,
                  resultId: Value(reused),
                  processingJobId: Value(processingJobId),
                  waitReason: Value(
                    processingJobId == null || state != PublishState.waiting
                        ? null
                        : QueueWaitReason.processing.name,
                  ),
                  message: state == PublishState.unknown
                      ? const Value('相同输入存在未确认远端结果，请核查或明确再次上传。')
                      : const Value.absent(),
                ),
              );
          if (!state.terminal) await _protectUploadInput(publicationInput, id);
          await _uploadEvent(id, state, 'enqueue');
        }
      }
      await _retireUnusedProcessingJobs();
    });
    _uploadChanges.add(null);
    return _uploadBatch(
      await (_db.select(
        _db.uploadBatches,
      )..where((t) => t.id.equals(batchId))).getSingle(),
    );
  });

  Future<File> _uploadInputFile(FrozenUploadInput input) async {
    File file;
    if (input.kind == UploadInputKind.original) {
      await _rejectPendingPurge({input.version.id});
      final version = await (_db.select(
        _db.versions,
      )..where((t) => t.id.equals(input.version.id))).getSingleOrNull();
      final copy = await (_db.select(
        _db.deviceCopies,
      )..where((t) => t.versionId.equals(input.version.id))).getSingleOrNull();
      if (version == null ||
          copy == null ||
          version.digest != input.version.sha256 ||
          version.byteCount != input.version.byteCount) {
        throw const UploadQueueFailure('冻结原图版本不可用。');
      }
      _validateOriginalPath(copy.relativePath);
      file = await _files.file(copy.relativePath);
    } else {
      final row = await _outputRow(input.referenceId);
      if (row.state != 'ready' ||
          row.versionJson == null ||
          versionFromSnapshot(
                (jsonDecode(row.versionJson!) as Map).cast<String, Object?>(),
              ) !=
              input.version ||
          _processedUploadPolicy(row.requestJson) != input.policyKey) {
        throw const UploadQueueFailure('冻结处理版本不可用。');
      }
      file = await _files.file(row.relativePath);
    }
    await _validateOutputBytes(file, input.version);
    return file;
  }

  Future<void> _protectUploadInput(FrozenUploadInput input, String id) async {
    if (input.kind == UploadInputKind.original) {
      await _db
          .into(_db.versionReferences)
          .insert(
            VersionReferencesCompanion.insert(
              id: const Uuid().v4(),
              versionId: input.version.id,
              ownerType: 'task',
              ownerId: id,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    } else {
      await _db
          .into(_db.outputReferences)
          .insert(
            OutputReferencesCompanion.insert(
              id: const Uuid().v4(),
              outputId: input.referenceId,
              ownerType: 'task',
              ownerId: id,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  Future<void> _unprotectUpload(String id) async {
    await (_db.delete(
      _db.versionReferences,
    )..where((t) => t.ownerType.equals('task') & t.ownerId.equals(id))).go();
    await (_db.delete(
      _db.outputReferences,
    )..where((t) => t.ownerType.equals('task') & t.ownerId.equals(id))).go();
  }

  Future<void> _uploadEvent(
    String id,
    PublishState state,
    String reason, {
    String? attemptId,
  }) async {
    await _db
        .into(_db.uploadEvents)
        .insert(
          UploadEventsCompanion.insert(
            id: const Uuid().v4(),
            itemId: id,
            state: state.name,
            reason: reason,
            createdUtc: _uploadNow,
            attemptId: Value(attemptId),
          ),
        )
        .then((_) {});
    if (!_restoreRequested) {
      final row = await _uploadRow(id);
      await _noteDiagnostic(
        _DiagnosticAction(
          DiagnosticKind.upload,
          'upload.${state.name.toLowerCase()}',
          '上传发布项状态已记录：${state.name}。',
          '请按任务页原因处理；未知结果需先核查，避免重复上传。',
          entityId: id,
          batchId: row.batchId,
          attemptId: attemptId,
        ),
        failed: state == PublishState.failed,
      );
    }
  }

  Future<void> _setUploadState(
    String id,
    PublishState state, {
    QueueWaitReason? reason,
    String? message,
    Duration? retryDelay,
    String? attemptId,
  }) async {
    await (_db.update(
      _db.uploadPublications,
    )..where((t) => t.id.equals(id))).write(
      UploadPublicationsCompanion(
        state: Value(state.name),
        waitReason: Value(reason?.name),
        message: Value(message),
        retryDelayMicros: Value(retryDelay?.inMicroseconds),
        updatedUtc: Value(_uploadNow),
      ),
    );
    await _uploadEvent(
      id,
      state,
      reason?.name ?? state.name,
      attemptId: attemptId,
    );
  }

  Future<void> _prepareInterruptedUploadPause(UploadPublicationRow row) async {
    if (row.state != PublishState.interrupted.name) return;
    // SRS 8.1 does not allow interrupted -> paused. Both legal transitions
    // commit in the caller's transaction, without releasing the writer gate
    // or notifying the scheduler between them.
    await _setUploadState(
      row.id,
      PublishState.queued,
      reason: row.waitReason == null
          ? null
          : QueueWaitReason.values.byName(row.waitReason!),
      message: row.message,
      retryDelay: row.retryDelayMicros == null
          ? null
          : Duration(microseconds: row.retryDelayMicros!),
    );
  }

  Future<void> setUploadBatchPaused(
    String batchId,
    bool paused,
  ) => _serial(() async {
    await _db.transaction(() async {
      await (_db.select(
        _db.uploadBatches,
      )..where((t) => t.id.equals(batchId))).getSingle();
      await (_db.update(_db.uploadBatches)..where((t) => t.id.equals(batchId)))
          .write(UploadBatchesCompanion(paused: Value(paused)));
      final rows = await (_db.select(
        _db.uploadPublications,
      )..where((t) => t.batchId.equals(batchId))).get();
      for (final row in rows) {
        final state = PublishState.values.byName(row.state);
        if (paused &&
            {
              PublishState.queued,
              PublishState.waiting,
              PublishState.interrupted,
            }.contains(state)) {
          await _prepareInterruptedUploadPause(row);
          await _setUploadState(
            row.id,
            PublishState.paused,
            reason: row.waitReason == null
                ? null
                : QueueWaitReason.values.byName(row.waitReason!),
            retryDelay: row.retryDelayMicros == null
                ? null
                : Duration(microseconds: row.retryDelayMicros!),
          );
        } else if (!paused && !row.userPaused && state == PublishState.paused) {
          await _setUploadState(
            row.id,
            row.waitReason == null ? PublishState.queued : PublishState.waiting,
            reason: row.waitReason == null
                ? null
                : QueueWaitReason.values.byName(row.waitReason!),
            retryDelay: row.retryDelayMicros == null
                ? null
                : Duration(microseconds: row.retryDelayMicros!),
          );
          await _resolveProcessingDependency(await _uploadRow(row.id));
        }
      }
    });
    _uploadChanges.add(null);
  });

  Future<void> setUploadItemPaused(String itemId, bool paused) =>
      _serial(() async {
        var changed = false;
        await _db.transaction(() async {
          final row = await _uploadRow(itemId);
          final state = PublishState.values.byName(row.state);
          if (!{
            PublishState.queued,
            PublishState.waiting,
            PublishState.paused,
            PublishState.interrupted,
          }.contains(state)) {
            throw const UploadQueueFailure('仅未运行的上传项可以暂停或继续。');
          }
          if (row.userPaused == paused) return;
          final batch = await (_db.select(
            _db.uploadBatches,
          )..where((t) => t.id.equals(row.batchId))).getSingle();
          final nextState = paused || batch.paused
              ? PublishState.paused
              : row.waitReason == null
              ? PublishState.queued
              : PublishState.waiting;
          if (nextState == PublishState.paused) {
            await _prepareInterruptedUploadPause(row);
          }
          await (_db.update(
            _db.uploadPublications,
          )..where((t) => t.id.equals(itemId))).write(
            UploadPublicationsCompanion(
              userPaused: Value(paused),
              state: Value(nextState.name),
              updatedUtc: Value(_uploadNow),
            ),
          );
          // User intent changes independently from a batch pause. Keep the
          // original wait reason and retry delay until the scheduler wakes it.
          await _uploadEvent(
            itemId,
            nextState,
            paused ? 'item-paused' : 'item-resumed',
          );
          if (!paused && !batch.paused) {
            await _resolveProcessingDependency(await _uploadRow(itemId));
          }
          changed = true;
        });
        if (changed) _uploadChanges.add(null);
      });
  Future<void> cancelUploadItems(Iterable<String> ids) => _serial(() async {
    await _db.transaction(() async {
      for (final id in ids.toSet()) {
        final row = await _uploadRow(id);
        if (PublishState.values.byName(row.state).terminal) continue;
        await _setUploadState(
          id,
          PublishState.cancelled,
          message: '本次上传意图已取消；运行中的远端副作用可能无法撤回。',
          attemptId: row.currentAttemptId,
        );
        final attempt = row.currentAttemptId == null
            ? null
            : await (_db.select(_db.uploadAttempts)
                    ..where((t) => t.id.equals(row.currentAttemptId!)))
                  .getSingleOrNull();
        if (attempt == null || attempt.endedUtc != null) {
          await _unprotectUpload(id);
        }
      }
      await _retireUnusedProcessingJobs();
    });
    _uploadChanges.add(null);
  });

  Future<void> setUploadWaiting(String itemId, QueueWaitReason reason) =>
      _serial(() async {
        final row = await _uploadRow(itemId);
        final batch = await (_db.select(
          _db.uploadBatches,
        )..where((t) => t.id.equals(row.batchId))).getSingle();
        if (row.userPaused || batch.paused) return;
        if (!{
          PublishState.queued,
          PublishState.waiting,
          PublishState.interrupted,
        }.contains(PublishState.values.byName(row.state))) {
          return;
        }
        await _db.transaction(
          () => _setUploadState(
            itemId,
            PublishState.waiting,
            reason: reason,
            retryDelay: row.retryDelayMicros == null
                ? null
                : Duration(microseconds: row.retryDelayMicros!),
          ),
        );
        _uploadChanges.add(null);
      });

  Future<void> wakeUploadItem(String itemId) => _serial(() async {
    final row = await _uploadRow(itemId);
    final batch = await (_db.select(
      _db.uploadBatches,
    )..where((t) => t.id.equals(row.batchId))).getSingle();
    if (batch.paused ||
        row.userPaused ||
        !{'waiting', 'interrupted'}.contains(row.state)) {
      return;
    }
    await _db.transaction(() async {
      if (await _resolveProcessingDependency(row)) {
        await _setUploadState(itemId, PublishState.queued);
      }
    });
    _uploadChanges.add(null);
  });

  Future<UploadExecution?> beginUploadAttempt(
    String itemId, {
    bool Function()? mayDispatch,
  }) => _serial(() async {
    if (_closing != null) return null;
    await _validateAccountHealthObservations();
    final row = await _uploadRow(itemId);
    final batch = await (_db.select(
      _db.uploadBatches,
    )..where((t) => t.id.equals(row.batchId))).getSingle();
    if (batch.paused || row.userPaused || row.state != 'queued') return null;
    if (!await _db.transaction(() => _resolveProcessingDependency(row))) {
      _uploadChanges.add(null);
      return null;
    }
    if (row.attemptCount >= 4 ||
        row.accumulatedRunningMicros >=
            ExecutionBudget.totalLimit.inMicroseconds) {
      await _db.transaction(() async {
        await _setUploadState(
          itemId,
          PublishState.failed,
          message: row.attemptCount >= 4
              ? '已达到本任务四次执行上限，请明确新建上传任务。'
              : '累计实际运行已达到三十分钟上限，请明确新建上传任务。',
        );
        await _unprotectUpload(itemId);
      });
      _uploadChanges.add(null);
      return null;
    }
    ResolvedTarget target;
    try {
      target = await _resolveTarget(row.targetId);
    } catch (_) {
      await _db.transaction(
        () => _setUploadState(
          itemId,
          PublishState.waiting,
          reason: QueueWaitReason.authorization,
          message: '目标或凭据不可用，请检查当前账号配置。',
        ),
      );
      _uploadChanges.add(null);
      return null;
    }
    final input = _readUploadInput(row.inputJson);
    File file;
    try {
      file = await _uploadInputFile(input);
    } catch (_) {
      await _db.transaction(
        () => _setUploadState(
          itemId,
          PublishState.waiting,
          reason: QueueWaitReason.inputUnavailable,
          message: '冻结输入缺失或损坏，请修复该版本或取消。',
        ),
      );
      _uploadChanges.add(null);
      return null;
    }
    final attemptId = const Uuid().v4(),
        leaseId = const Uuid().v4(),
        generation = row.generation + 1,
        startedUtc = _uploadNow;
    final started = await _db.transaction(() async {
      // File verification and credential reads can outlive the observed route.
      // Recheck under the actual writer gate before creating any attempt/lease.
      if (mayDispatch != null && !mayDispatch()) {
        await _setUploadState(
          itemId,
          PublishState.waiting,
          reason: QueueWaitReason.network,
        );
        return false;
      }
      if (input.kind == UploadInputKind.original) {
        await _db
            .into(_db.fileLeases)
            .insert(
              FileLeasesCompanion.insert(
                id: leaseId,
                versionId: input.version.id,
                ownerId: _leaseOwnerId,
                purpose: 'upload',
                createdUtc: _uploadNow,
              ),
            );
      } else {
        await _db
            .into(_db.outputLeases)
            .insert(
              OutputLeasesCompanion.insert(
                id: leaseId,
                outputId: input.referenceId,
                ownerId: _leaseOwnerId,
              ),
            );
      }
      await _db
          .into(_db.uploadAttempts)
          .insert(
            UploadAttemptsCompanion.insert(
              id: attemptId,
              itemId: itemId,
              generation: generation,
              targetGeneration: target.target.generation,
              startedUtc: startedUtc,
            ),
          );
      // The writer gate, not wall-clock UTC, establishes actual start order.
      // Persist with the attempt and lease so failure cannot leave either one.
      await _db
          .into(_db.libraryMetadata)
          .insertOnConflictUpdate(
            LibraryMetadataCompanion.insert(
              key: '$_accountHealthStartedPrefix${row.targetId}',
              value: jsonEncode(
                _AccountHealthStarted(
                  target.target.generation,
                  startedUtc,
                  attemptId,
                ).toJson(),
              ),
            ),
          );
      await (_db.update(
        _db.uploadPublications,
      )..where((t) => t.id.equals(itemId))).write(
        UploadPublicationsCompanion(
          currentAttemptId: Value(attemptId),
          generation: Value(generation),
          attemptCount: Value(row.attemptCount + 1),
        ),
      );
      await _setUploadState(itemId, PublishState.running, attemptId: attemptId);
      return true;
    });
    if (!started) {
      _uploadChanges.add(null);
      return null;
    }
    _activeLeaseIds.add(leaseId);
    _leaseDrain ??= Completer<void>();
    _uploadChanges.add(null);
    return UploadExecution(
      item: _publication(await _uploadRow(itemId)),
      attemptId: attemptId,
      generation: generation,
      libraryEpoch: _executionEpoch,
      target: target,
      file: file,
      release: () => _releaseUploadLease(leaseId, itemId),
    );
  });

  Future<void> _releaseUploadLease(String leaseId, String itemId) =>
      _serial(() async {
        try {
          await _db.transaction(() async {
            await (_db.delete(_db.fileLeases)..where(
                  (t) => t.id.equals(leaseId) & t.ownerId.equals(_leaseOwnerId),
                ))
                .go();
            await (_db.delete(_db.outputLeases)..where(
                  (t) => t.id.equals(leaseId) & t.ownerId.equals(_leaseOwnerId),
                ))
                .go();
            final row = await _uploadRow(itemId);
            if (PublishState.values.byName(row.state).terminal) {
              await _unprotectUpload(itemId);
            }
          });
        } finally {
          _activeLeaseIds.remove(leaseId);
          if (_activeLeaseIds.isEmpty) {
            _leaseDrain?.complete();
            _leaseDrain = null;
          }
        }
      }, settling: true);

  Future<bool> authorizeUploadRequest(String attemptId) => _serial(() async {
    if (_restoreRequested) return false;
    final attempt = await (_db.select(
      _db.uploadAttempts,
    )..where((t) => t.id.equals(attemptId))).getSingleOrNull();
    if (attempt == null ||
        attempt.endedUtc != null ||
        attempt.requestMayHaveStarted) {
      return false;
    }
    final item = await _uploadRow(attempt.itemId);
    if (item.state != 'running' ||
        item.currentAttemptId != attemptId ||
        item.generation != attempt.generation) {
      return false;
    }
    final target = await (_db.select(
      _db.providerTargets,
    )..where((t) => t.id.equals(item.targetId))).getSingleOrNull();
    final pending = await (_db.select(
      _db.credentialOperations,
    )..where((t) => t.targetId.equals(item.targetId))).get();
    if (target == null ||
        target.anonymous ||
        !target.enabled ||
        target.removed ||
        target.generation != attempt.targetGeneration ||
        pending.any(
          (operation) =>
              operation.action != 'forget' ||
              !_sessionCredentials.containsKey(item.targetId),
        )) {
      return false;
    }
    await (_db.update(
      _db.uploadAttempts,
    )..where((t) => t.id.equals(attemptId))).write(
      const UploadAttemptsCompanion(requestMayHaveStarted: Value(true)),
    );
    return true;
  });

  /// Monotonic elapsed time comes from the live coordinator. UTC audit time
  /// cannot reconstruct execution duration after a process ends.
  Future<void> checkpointUploadAttempt(
    String attemptId,
    Duration accumulatedRunning,
  ) => _serial(() async {
    if (accumulatedRunning.isNegative) throw ArgumentError('持续时间不能为负数。');
    final attempt = await (_db.select(
      _db.uploadAttempts,
    )..where((t) => t.id.equals(attemptId))).getSingleOrNull();
    if (attempt == null || attempt.endedUtc != null) return;
    final row = await _uploadRow(attempt.itemId);
    if (row.state != 'running' ||
        row.currentAttemptId != attemptId ||
        row.generation != attempt.generation ||
        accumulatedRunning.inMicroseconds <= row.accumulatedRunningMicros) {
      return;
    }
    await (_db.update(
      _db.uploadPublications,
    )..where((t) => t.id.equals(row.id))).write(
      UploadPublicationsCompanion(
        accumulatedRunningMicros: Value(accumulatedRunning.inMicroseconds),
      ),
    );
  }, settling: true);

  Uri _safeUploadUrl(Uri uri) {
    final value = uri.toString();
    String decoded;
    try {
      decoded = Uri.decodeFull(value);
    } catch (_) {
      throw const UploadQueueFailure('远端链接未通过安全校验。');
    }
    if (value.length > 4096 ||
        !{'https', 'http'}.contains(uri.scheme) ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.hasPort ||
        uri.path.isEmpty ||
        uri.pathSegments.any((segment) => segment == '.' || segment == '..') ||
        decoded.contains('\\') ||
        decoded.runes.any((c) => c <= 32 || c == 127) ||
        _secretRedactor.redactText(value) != value ||
        _secretRedactor.redactText(decoded) != decoded) {
      throw const UploadQueueFailure('远端链接未通过安全校验。');
    }
    return uri;
  }

  void _validateUploadConfirmation(
    TargetSnapshot target,
    String remoteId,
    Uri direct,
    Uri? viewer,
  ) {
    if (remoteId.isEmpty ||
        _secretRedactor.redactText(remoteId) != remoteId ||
        _secretRedactor.redactText(Uri.decodeFull(remoteId)) != remoteId) {
      throw const UploadQueueFailure('远端确认身份无效。');
    }
    final valid = switch (target.service) {
      ImageHostService.catbox =>
        direct.host == 'files.catbox.moe' &&
            RegExp(r'^/[a-zA-Z0-9_-]+\.[a-zA-Z0-9]{1,10}$')
                .hasMatch(direct.path) &&
            direct.pathSegments.single == remoteId &&
            viewer == null,
      ImageHostService.imgbb =>
        RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(remoteId) &&
            direct.host == 'i.ibb.co' &&
            RegExp(
              r'^/[a-zA-Z0-9_-]+/[a-zA-Z0-9._-]+\.(?:png|jpe?g|gif|webp|bmp)$',
              caseSensitive: false,
            ).hasMatch(direct.path) &&
            (viewer == null ||
                (viewer.host == 'ibb.co' && viewer.path == '/$remoteId')),
    };
    if (!valid) throw const UploadQueueFailure('远端确认与服务协议不符。');
  }

  bool _validManagementSecret(
    String secret,
    TargetSnapshot target,
    String remoteId,
  ) {
    final uri = Uri.tryParse(secret);
    return target.service == ImageHostService.imgbb &&
        uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'ibb.co' &&
        !uri.hasPort &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        uri.pathSegments.length == 2 &&
        uri.pathSegments.first == remoteId &&
        RegExp(r'^/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]{16,128}$').hasMatch(uri.path);
  }

  void _registerManagementSecret(String secret) {
    _secretRedactor.register(secret);
    final uri = Uri.tryParse(secret);
    if (uri != null && uri.host == 'ibb.co' && uri.pathSegments.length == 2) {
      _secretRedactor.register(uri.pathSegments.last);
    }
  }

  Future<void> finishUploadAttempt(
    UploadExecution execution,
    ProviderUploadResult result, {
    required Duration accumulatedRunning,
    Duration? retryDelay,
    bool interrupted = false,
  }) => _serial(() async {
    if (execution.libraryEpoch != _executionEpoch) {
      throw const UploadQueueFailure('旧上传会话已停止，未写入当前资料库；请重新打开任务页。');
    }
    await _validateAccountHealthObservations();
    var effectiveResult = result;
    if (accumulatedRunning.isNegative || (retryDelay?.isNegative ?? false)) {
      throw ArgumentError('持续时间不能为负数。');
    }
    final attempt = await (_db.select(
      _db.uploadAttempts,
    )..where((t) => t.id.equals(execution.attemptId))).getSingle();
    if (attempt.itemId != execution.item.id ||
        attempt.generation != execution.generation) {
      throw const UploadQueueFailure('尝试身份不一致。');
    }
    if (attempt.endedUtc != null) return;
    final row = await _uploadRow(attempt.itemId);
    if (effectiveResult is ProviderUploadSuccess) {
      final management = effectiveResult.managementSecret
          ?.revealForProtectedStorage();
      if (management != null) _registerManagementSecret(management);
      try {
        if (effectiveResult.service !=
                _readUploadTarget(row.targetJson).service ||
            effectiveResult.remoteId.isEmpty ||
            effectiveResult.remoteId.runes.any((c) => c <= 32 || c == 127) ||
            _secretRedactor.redactText(effectiveResult.remoteId) !=
                effectiveResult.remoteId) {
          throw const UploadQueueFailure('远端确认身份无效。');
        }
        final direct = _safeUploadUrl(effectiveResult.directUrl),
            viewer = effectiveResult.viewerUrl == null
                ? null
                : _safeUploadUrl(effectiveResult.viewerUrl!);
        _validateUploadConfirmation(
          _readUploadTarget(row.targetJson),
          effectiveResult.remoteId,
          direct,
          viewer,
        );
        var operation = await (_db.select(
          _db.uploadResultOperations,
        )..where((t) => t.attemptId.equals(attempt.id))).getSingleOrNull();
        if (operation == null) {
          final validManagement =
              management != null &&
              _validManagementSecret(
                management,
                _readUploadTarget(row.targetJson),
                effectiveResult.remoteId,
              );
          final proposal = {
            'resultId': const Uuid().v4(),
            'directUrl': direct.toString(),
            'viewerUrl': viewer?.toString(),
            'remoteId': effectiveResult.remoteId,
            'confirmedUtc': _uploadNow,
            'accumulatedRunningMicros':
                accumulatedRunning.inMicroseconds < row.accumulatedRunningMicros
                ? row.accumulatedRunningMicros
                : accumulatedRunning.inMicroseconds,
            'secretDigest': validManagement
                ? hashing.sha256.convert(utf8.encode(management)).toString()
                : null,
          };
          final operationId = const Uuid().v4(),
              reference = validManagement ? const Uuid().v4() : null;
          await _db
              .into(_db.uploadResultOperations)
              .insert(
                UploadResultOperationsCompanion.insert(
                  id: operationId,
                  attemptId: attempt.id,
                  proposalJson: jsonEncode(proposal),
                  secretReference: Value(reference),
                  createdUtc: _uploadNow,
                ),
              );
          operation = await (_db.select(
            _db.uploadResultOperations,
          )..where((t) => t.id.equals(operationId))).getSingle();
        }
        if (operation.secretReference != null && management != null) {
          try {
            await _secretStore.write(operation.secretReference!, management);
            if (await _secretStore.read(operation.secretReference!) !=
                management) {
              throw const SecretStorageException();
            }
          } catch (_) {
            /* valid ordinary remote confirmation still commits below */
          }
        }
        await _applyUploadResultOperation(operation);
        _uploadChanges.add(null);
        return;
      } on UploadQueueFailure {
        effectiveResult = const ProviderUploadUnknown(
          UploadFailureKind.protocol,
        );
      }
    }
    var state = PublishState.failed;
    QueueWaitReason? reason;
    String message = '上传未完成，请检查输入和目标。';
    if (effectiveResult is ProviderUploadUnknown ||
        (effectiveResult is ProviderUploadFailure &&
            effectiveResult.evidence == UploadDeliveryEvidence.uncertain)) {
      state = PublishState.unknown;
      message = '远端结果未确认，请核查后再决定是否再次上传。';
    } else if (effectiveResult is ProviderUploadCancelled) {
      state = effectiveResult.evidence == UploadDeliveryEvidence.notSent
          ? (interrupted ? PublishState.interrupted : PublishState.waiting)
          : PublishState.unknown;
      reason = state == PublishState.waiting
          ? QueueWaitReason.authorization
          : null;
      message = state == PublishState.unknown
          ? '请求可能已发送，远端结果未确认。'
          : '本次执行未发送请求；检查条件后可继续。';
    } else if (effectiveResult is ProviderUploadFailure) {
      message = effectiveResult.message;
      reason = switch (effectiveResult.kind) {
        UploadFailureKind.authorization ||
        UploadFailureKind.targetUnavailable => QueueWaitReason.authorization,
        UploadFailureKind.fileUnavailable => QueueWaitReason.inputUnavailable,
        UploadFailureKind.capabilityUnknown =>
          QueueWaitReason.capabilityUnknown,
        _ => null,
      };
      if (reason != null) {
        state = PublishState.waiting;
      } else if (retryDelay != null &&
          row.attemptCount < 4 &&
          {
            UploadFailureKind.network,
            UploadFailureKind.rateLimited,
            UploadFailureKind.timeout,
          }.contains(effectiveResult.kind)) {
        state = PublishState.waiting;
        reason = QueueWaitReason.retry;
      }
    }
    var healthChanged = false;
    final observedHealth = _uploadFailureHealth(effectiveResult);
    await _db.transaction(() async {
      await (_db.update(
        _db.uploadAttempts,
      )..where((t) => t.id.equals(attempt.id))).write(
        UploadAttemptsCompanion(
          endedUtc: Value(_uploadNow),
          outcome: Value(state.name),
        ),
      );
      if (row.currentAttemptId == attempt.id &&
          row.generation == attempt.generation) {
        await (_db.update(
          _db.uploadPublications,
        )..where((t) => t.id.equals(row.id))).write(
          UploadPublicationsCompanion(
            accumulatedRunningMicros: Value(
              accumulatedRunning.inMicroseconds < row.accumulatedRunningMicros
                  ? row.accumulatedRunningMicros
                  : accumulatedRunning.inMicroseconds,
            ),
          ),
        );
        if (!PublishState.values.byName(row.state).terminal) {
          await _setUploadState(
            row.id,
            state,
            reason: reason,
            message: message,
            retryDelay: reason == QueueWaitReason.retry ? retryDelay : null,
            attemptId: attempt.id,
          );
        }
        if (PublishState.values
            .byName((await _uploadRow(row.id)).state)
            .terminal) {
          await _unprotectUpload(row.id);
        }
      }
      if (observedHealth != null) {
        healthChanged = await _observeUploadAccountHealth(
          attempt,
          row,
          observedHealth,
          epoch: execution.libraryEpoch!,
        );
      }
    });
    if (healthChanged) _accountHealthChanges.add(null);
    _uploadChanges.add(null);
  }, settling: true);

  AccountHealth? _uploadFailureHealth(ProviderUploadResult result) {
    if (result is! ProviderUploadFailure ||
        result.evidence == UploadDeliveryEvidence.uncertain) {
      return null;
    }
    return switch (result.kind) {
      UploadFailureKind.authorization => AccountHealth.authorizationInvalid,
      UploadFailureKind.network ||
      UploadFailureKind.rateLimited ||
      UploadFailureKind.timeout ||
      UploadFailureKind.targetUnavailable =>
        AccountHealth.temporarilyUnavailable,
      _ => null,
    };
  }

  /// Runs inside the result transaction. New attempts use the persisted writer
  /// start marker, including across clock rollback and history removal. Existing
  /// schema-10 attempts without a marker fall back to UTC then UUID order; that
  /// legacy fallback cannot claim a clock-independent causal ordering.
  Future<bool> _observeUploadAccountHealth(
    UploadAttempt attempt,
    UploadPublicationRow item,
    AccountHealth health, {
    required String epoch,
  }) async {
    if (epoch != _executionEpoch) return false;
    final target = await (_db.select(
      _db.providerTargets,
    )..where((t) => t.id.equals(item.targetId))).getSingleOrNull();
    if (target == null ||
        target.removed ||
        target.generation != attempt.targetGeneration) {
      return false;
    }
    final pending =
        await (_db.select(_db.credentialOperations)
              ..where((t) => t.targetId.equals(target.id))
              ..limit(1))
            .getSingleOrNull();
    if (pending != null) return false;
    final started = await _accountHealthStarted(target.id);
    final authoritativeStart =
        started?.targetGeneration == attempt.targetGeneration;
    if (authoritativeStart && started!.attemptId != attempt.id) return false;
    final attempts = _db.uploadAttempts, items = _db.uploadPublications;
    final latest = _db.selectOnly(attempts)
      ..addColumns([attempts.id])
      ..join([innerJoin(items, items.id.equalsExp(attempts.itemId))])
      ..where(
        items.targetId.equals(target.id) &
            attempts.targetGeneration.equals(attempt.targetGeneration),
      )
      ..orderBy([
        OrderingTerm.desc(attempts.startedUtc),
        OrderingTerm.desc(attempts.id),
      ])
      ..limit(1);
    if (!authoritativeStart &&
        (await latest.getSingleOrNull())?.read(attempts.id) != attempt.id) {
      return false;
    }
    // The watermark remains after task history removal. It contains ordinary
    // observation data only, and does not protect or recreate any task.
    final previous = await _accountHealthObservation(target.id);
    if (!authoritativeStart &&
        previous != null &&
        previous.targetGeneration == attempt.targetGeneration &&
        previous.compareAttempt(attempt) > 0) {
      return false;
    }
    final observation = _AccountHealthObservation(
      attempt.targetGeneration,
      attempt.startedUtc,
      attempt.id,
      health,
    );
    await _db
        .into(_db.libraryMetadata)
        .insertOnConflictUpdate(
          LibraryMetadataCompanion.insert(
            key: '$_accountHealthPrefix${target.id}',
            value: jsonEncode(observation.toJson()),
          ),
        );
    if (target.health == health.name) return false;
    await (_db.update(_db.providerTargets)
          ..where((t) => t.id.equals(target.id)))
        .write(ProviderTargetsCompanion(health: Value(health.name)));
    return true;
  }

  Future<void> _applyUploadResultOperation(
    UploadResultOperation operation,
  ) async {
    final epoch = _executionEpoch;
    await _validateAccountHealthObservations();
    final proposal = jsonDecode(operation.proposalJson) as Map<String, dynamic>;
    if (proposal['action'] == 'remove-local-result-v1') {
      await _applyLocalLinkRemoval(operation);
      return;
    }
    final attempt = await (_db.select(
      _db.uploadAttempts,
    )..where((t) => t.id.equals(operation.attemptId))).getSingle();
    final item = await _uploadRow(attempt.itemId);
    var available = false, storageUnavailable = false;
    if (operation.secretReference != null) {
      try {
        final secret = await _secretStore.read(operation.secretReference!);
        if (secret != null && secret.isNotEmpty) {
          _registerManagementSecret(secret);
          available =
              hashing.sha256.convert(utf8.encode(secret)).toString() ==
                  proposal['secretDigest'] &&
              _validManagementSecret(
                secret,
                _readUploadTarget(item.targetJson),
                proposal['remoteId'] as String,
              );
          if (!available) {
            // This is an operation-owned UUID, never an account reference.
            // Remove unconfirmed bytes while retaining the journal if cleanup
            // cannot itself be confirmed by the protected backend.
            await _secretStore.delete(operation.secretReference!);
            if (await _secretStore.read(operation.secretReference!) != null) {
              throw const SecretStorageException();
            }
          }
        }
      } catch (_) {
        storageUnavailable = true;
      }
    }
    final direct = _safeUploadUrl(Uri.parse(proposal['directUrl'] as String));
    final viewer = proposal['viewerUrl'] == null
        ? null
        : _safeUploadUrl(Uri.parse(proposal['viewerUrl'] as String));
    _validateUploadConfirmation(
      _readUploadTarget(item.targetJson),
      proposal['remoteId'] as String,
      direct,
      viewer,
    );
    // Secret IO above is outside SQLite's transaction. The journal remains
    // retryable when the backend cannot confirm whether secure bytes exist.
    var healthChanged = false;
    await _db.transaction(() async {
      final late =
          item.state == 'cancelled' ||
          item.currentAttemptId != attempt.id ||
          item.generation != attempt.generation;
      await _db
          .into(_db.remoteUploadResults)
          .insert(
            RemoteUploadResultsCompanion.insert(
              id: proposal['resultId'] as String,
              attemptId: attempt.id,
              inputJson: jsonEncode(
                _inputSnapshot(_readUploadInput(item.inputJson)),
              ),
              targetJson: jsonEncode(
                _targetSnapshot(_readUploadTarget(item.targetJson)),
              ),
              targetId: item.targetId,
              versionDigest: item.versionDigest,
              byteCount: item.byteCount,
              policyKey: item.policyKey,
              remoteId: _secretRedactor.redactText(
                proposal['remoteId'] as String,
              ),
              directUrl: direct.toString(),
              viewerUrl: Value(viewer?.toString()),
              confirmedUtc: proposal['confirmedUtc'] as int,
              late: late,
              secretReference: available
                  ? Value(operation.secretReference)
                  : const Value(null),
              managementAvailable: Value(available),
            ),
            mode: InsertMode.insertOrIgnore,
          );
      if (available) {
        await (_db.update(
          _db.remoteUploadResults,
        )..where((t) => t.attemptId.equals(attempt.id))).write(
          RemoteUploadResultsCompanion(
            secretReference: Value(operation.secretReference),
            managementAvailable: const Value(true),
          ),
        );
      }
      await (_db.update(
        _db.uploadAttempts,
      )..where((t) => t.id.equals(attempt.id))).write(
        UploadAttemptsCompanion(
          endedUtc: Value(_uploadNow),
          outcome: Value(late ? 'late-success' : 'succeeded'),
        ),
      );
      if (item.currentAttemptId == attempt.id &&
          item.generation == attempt.generation) {
        if (!PublishState.values.byName(item.state).terminal) {
          await (_db.update(
            _db.uploadPublications,
          )..where((t) => t.id.equals(item.id))).write(
            UploadPublicationsCompanion(
              resultId: Value(proposal['resultId'] as String),
              accumulatedRunningMicros: Value(
                proposal['accumulatedRunningMicros'] as int,
              ),
            ),
          );
          await _setUploadState(
            item.id,
            PublishState.succeeded,
            message: available || operation.secretReference == null
                ? null
                : '远端已确认；受保护管理信息暂不可用。',
            attemptId: attempt.id,
          );
        }
        await _unprotectUpload(item.id);
      }
      // A newly confirmed management token may already appear in names of
      // earlier queued batches. Persist the masking for every ordinary upload
      // snapshot before dropping the journal, so reopening never depends on
      // this process's in-memory redactor for historical display safety.
      await _scrubUploadSnapshots();
      if (!storageUnavailable) {
        await (_db.delete(
          _db.uploadResultOperations,
        )..where((t) => t.id.equals(operation.id))).go();
      }
      healthChanged = await _observeUploadAccountHealth(
        attempt,
        item,
        AccountHealth.available,
        epoch: epoch,
      );
    });
    if (healthChanged) _accountHealthChanges.add(null);
  }

  Future<void> _scrubUploadSnapshots() async {
    final archived = await _db.select(_db.importedUploadHistories).get();
    for (final row in archived) {
      final fragment = _readRestoreFragment(row.snapshotJson);
      if (fragment.history.length != 1 ||
          fragment.history.single.id != row.id ||
          fragment.history.single.batchId != row.batchId ||
          fragment.history.single.position != row.position) {
        throw const UploadQueueFailure('恢复历史结构无法安全读取，保留现场。');
      }
      final masked = utf8.decode(fragment.encode(redactor: _secretRedactor));
      if (masked != row.snapshotJson) {
        await (_db.update(
          _db.importedUploadHistories,
        )..where((t) => t.id.equals(row.id))).write(
          ImportedUploadHistoriesCompanion(snapshotJson: Value(masked)),
        );
      }
    }
    final publications = await _db.select(_db.uploadPublications).get();
    for (final row in publications) {
      final inputJson = jsonEncode(
        _inputSnapshot(_readUploadInput(row.inputJson)),
      );
      final targetJson = jsonEncode(
        _targetSnapshot(_readUploadTarget(row.targetJson)),
      );
      if (inputJson != row.inputJson || targetJson != row.targetJson) {
        await (_db.update(
          _db.uploadPublications,
        )..where((t) => t.id.equals(row.id))).write(
          UploadPublicationsCompanion(
            inputJson: Value(inputJson),
            targetJson: Value(targetJson),
          ),
        );
      }
    }
    final results = await _db.select(_db.remoteUploadResults).get();
    for (final row in results) {
      final inputJson = jsonEncode(
        _inputSnapshot(_readUploadInput(row.inputJson)),
      );
      final targetJson = jsonEncode(
        _targetSnapshot(_readUploadTarget(row.targetJson)),
      );
      if (inputJson != row.inputJson || targetJson != row.targetJson) {
        await (_db.update(
          _db.remoteUploadResults,
        )..where((t) => t.id.equals(row.id))).write(
          RemoteUploadResultsCompanion(
            inputJson: Value(inputJson),
            targetJson: Value(targetJson),
          ),
        );
      }
    }
  }

  Future<void> _recoverUploads() async {
    final results = await (_db.select(
      _db.remoteUploadResults,
    )..where((t) => t.secretReference.isNotNull())).get();
    final pendingResults = await (_db.select(
      _db.uploadResultOperations,
    )..where((t) => t.secretReference.isNotNull())).get();
    final references = {
      for (final row in results) row.secretReference!,
      for (final row in pendingResults) row.secretReference!,
    };
    for (final reference in references) {
      try {
        // Read only references already owned by this library's confirmed
        // remote results. Never enumerate the system's protected namespace.
        final secret = await _secretStore.read(reference);
        if (secret != null) {
          _registerManagementSecret(secret);
        }
      } catch (_) {
        // The ordinary snapshots were masked in the confirmation transaction.
        // Backend failure does not recreate or reveal those retired strings.
      }
    }
    await _db.transaction(_scrubUploadSnapshots);
    final operations = await _db.select(_db.uploadResultOperations).get();
    for (final operation in operations) {
      try {
        await _applyUploadResultOperation(operation);
      } catch (_) {
        _recoveryIssues = List.unmodifiable([
          ..._recoveryIssues,
          RecoveryIssue(operation.id, '一项结果关联或管理清理尚未完成，已保留恢复证据。'),
        ]);
      }
    }
    final attempts = await (_db.select(
      _db.uploadAttempts,
    )..where((t) => t.endedUtc.isNull())).get();
    await _db.transaction(() async {
      for (final attempt in attempts) {
        final item = await _uploadRow(attempt.itemId);
        final state = PublishTransitions.recoverRunning(
          remoteSideEffectPossible: attempt.requestMayHaveStarted,
        );
        await (_db.update(
          _db.uploadAttempts,
        )..where((t) => t.id.equals(attempt.id))).write(
          UploadAttemptsCompanion(
            endedUtc: Value(_uploadNow),
            outcome: Value(state.name),
          ),
        );
        if (item.currentAttemptId == attempt.id &&
            item.generation == attempt.generation &&
            item.state == 'running') {
          await _setUploadState(
            item.id,
            state,
            message: state == PublishState.unknown
                ? '上次请求可能已发送，请核查远端结果。'
                : '上次执行已中断，可明确继续。',
            attemptId: attempt.id,
          );
        }
        if (PublishState.values
            .byName((await _uploadRow(item.id)).state)
            .terminal) {
          await _unprotectUpload(item.id);
        }
      }
    });
  }
}
