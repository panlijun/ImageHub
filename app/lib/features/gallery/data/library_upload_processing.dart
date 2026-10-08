part of 'library_repository.dart';

extension LibraryUploadProcessing on LibraryRepository {
  Future<UploadProcessingJobRow> _processingJobRow(String id) => (_db.select(
    _db.uploadProcessingJobs,
  )..where((t) => t.id.equals(id))).getSingle();

  Map<String, dynamic> _processingJobPayload(UploadProcessingJobRow row) {
    try {
      final data = jsonDecode(row.requestJson) as Map<String, dynamic>;
      if (data.length != 3 ||
          !data.keys.toSet().containsAll(['plan', 'retention', 'forceAgain']) ||
          data['forceAgain'] is! bool) {
        throw const UploadQueueFailure('上传处理日志无法安全读取。');
      }
      return data;
    } catch (_) {
      throw const UploadQueueFailure('上传处理日志无法安全读取，原记录已保留。');
    }
  }

  UploadProcessingJob _processingJob(UploadProcessingJobRow row) {
    try {
      final data = _processingJobPayload(row);
      final plan = FrozenProcessingPlan.fromJson(
        (data['plan'] as Map).cast<String, Object?>(),
      );
      if (plan.policyKey != row.policyKey) {
        throw const UploadQueueFailure('上传处理策略校验失败。');
      }
      return UploadProcessingJob(
        id: row.id,
        batchId: row.batchId,
        plan: plan,
        state: UploadProcessingState.values.byName(row.state),
        retention: OutputRetention.values.byName(data['retention'] as String),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row.createdUtc,
          isUtc: true,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          row.updatedUtc,
          isUtc: true,
        ),
        outputId: row.outputId,
        message: row.message == null
            ? null
            : _secretRedactor.redactText(row.message!),
      );
    } catch (_) {
      throw const UploadQueueFailure('上传处理日志无法安全读取，原记录已保留。');
    }
  }

  Future<List<UploadProcessingJob>> listUploadProcessingJobs() => _serial(
    () async => List.unmodifiable(
      (await (_db.select(_db.uploadProcessingJobs)..orderBy([
                (t) => OrderingTerm.asc(t.createdUtc),
                (t) => OrderingTerm.asc(t.id),
              ]))
              .get())
          .map(_processingJob),
    ),
  );

  Future<List<UploadPublicationRow>> _processingDependents(String id) =>
      (_db.select(
        _db.uploadPublications,
      )..where((t) => t.processingJobId.equals(id))).get();

  Future<bool> _processingHasRunnableDependent(String id) async {
    for (final row in await _processingDependents(id)) {
      if (row.userPaused ||
          PublishState.values.byName(row.state).terminal ||
          row.state == 'unknown' ||
          row.state == 'paused') {
        continue;
      }
      final batch = await (_db.select(
        _db.uploadBatches,
      )..where((t) => t.id.equals(row.batchId))).getSingle();
      if (!batch.paused) return true;
    }
    return false;
  }

  /// Claims local work only. A durable publication attempt is never created.
  Future<UploadProcessingJob?> beginUploadProcessingJob(String id) =>
      _serial(() async {
        if (_closing != null || _restoreRequested) return null;
        final row = await _processingJobRow(id);
        _processingJob(row);
        if (row.state != 'queued' ||
            _activeUploadProcessingJobs.contains(id) ||
            !await _processingHasRunnableDependent(id)) {
          return null;
        }
        await (_db.update(
          _db.uploadProcessingJobs,
        )..where((t) => t.id.equals(id))).write(
          UploadProcessingJobsCompanion(
            state: const Value('running'),
            updatedUtc: Value(_uploadNow),
          ),
        );
        _activeUploadProcessingJobs.add(id);
        _activeLeaseIds.add('upload-processing:$id');
        _leaseDrain ??= Completer<void>();
        _uploadChanges.add(null);
        return _processingJob(await _processingJobRow(id));
      });

  Future<void> recordUploadProcessingOutput(String id, String outputId) =>
      _serial(() async {
        final row = await _processingJobRow(id);
        if (!_activeUploadProcessingJobs.contains(id) ||
            row.state != 'running' ||
            (row.outputId != null && row.outputId != outputId)) {
          throw const UploadQueueFailure('上传处理执行身份已失效。');
        }
        final output = await _outputRow(outputId);
        if (_processedUploadCanonical(output.requestJson) !=
            _processingJob(row).plan.canonical) {
          throw const UploadQueueFailure('处理输出与冻结计划不一致。');
        }
        await _db.transaction(() async {
          await (_db.update(
            _db.uploadProcessingJobs,
          )..where((t) => t.id.equals(id))).write(
            UploadProcessingJobsCompanion(
              outputId: Value(outputId),
              updatedUtc: Value(_uploadNow),
            ),
          );
          await _db
              .into(_db.outputReferences)
              .insert(
                OutputReferencesCompanion.insert(
                  id: const Uuid().v4(),
                  outputId: outputId,
                  ownerType: 'task',
                  ownerId: id,
                ),
                mode: InsertMode.insertOrIgnore,
              );
        });
      }, settling: true);

  Future<void> _releaseProcessingOutputProtection(String id) async {
    await (_db.delete(
      _db.outputReferences,
    )..where((t) => t.ownerType.equals('task') & t.ownerId.equals(id))).go();
  }

  Future<void> _releaseProcessingProtection(String id) async {
    await (_db.delete(
      _db.versionReferences,
    )..where((t) => t.ownerType.equals('task') & t.ownerId.equals(id))).go();
    await _releaseProcessingOutputProtection(id);
  }

  /// Caller must wait for the pixel worker and its output/lease finalizers.
  Future<void> finishUploadProcessingJob(
    String id, {
    String? outputId,
    String? failureMessage,
    bool cancelled = false,
    bool interrupted = false,
    bool inputUnavailable = false,
  }) => _serial(() async {
    try {
      if (!_activeUploadProcessingJobs.contains(id)) {
        throw const UploadQueueFailure('上传处理执行身份已失效。');
      }
      final row = await _processingJobRow(id);
      if (outputId != null) {
        if (row.outputId != outputId) {
          throw const UploadQueueFailure('处理输出身份未确认。');
        }
        await _confirmProcessingJobOutput(row, outputId);
      } else {
        await _db.transaction(() async {
          final hasDependents = (await _processingDependents(id)).any(
            (item) =>
                !PublishState.values.byName(item.state).terminal &&
                item.state != 'unknown',
          );
          await (_db.update(
            _db.uploadProcessingJobs,
          )..where((t) => t.id.equals(id))).write(
            UploadProcessingJobsCompanion(
              state: Value(
                !hasDependents
                    ? 'cancelled'
                    : interrupted
                    ? 'queued'
                    : inputUnavailable
                    ? 'waiting'
                    : 'failed',
              ),
              outputId: interrupted ? const Value(null) : const Value.absent(),
              message: Value(
                _secretRedactor.redactText(
                  failureMessage ?? '上传前处理未完成，原图未上传；请明确新建任务。',
                ),
              ),
              updatedUtc: Value(_uploadNow),
            ),
          );
          for (final item in await _processingDependents(id)) {
            await _resolveProcessingDependency(item);
          }
          await _releaseProcessingOutputProtection(id);
          if (!hasDependents || (!interrupted && !inputUnavailable)) {
            await _releaseProcessingProtection(id);
          }
        });
      }
      _uploadChanges.add(null);
    } finally {
      // SQL cleanup failure preserves durable protection but cannot deadlock
      // exit after the actual IO and every pixel finalizer have ended.
      _activeUploadProcessingJobs.remove(id);
      _activeLeaseIds.remove('upload-processing:$id');
      if (_activeLeaseIds.isEmpty) {
        _leaseDrain?.complete();
        _leaseDrain = null;
      }
    }
  }, settling: true);

  Future<void> _confirmProcessingJobOutput(
    UploadProcessingJobRow row,
    String id,
  ) async {
    final output = await _outputRow(id);
    if (output.state != 'ready' ||
        output.versionJson == null ||
        _processedUploadCanonical(output.requestJson) !=
            _processingJob(row).plan.canonical) {
      throw const UploadQueueFailure('上传前处理结果尚未确认或策略不一致。');
    }
    final version = versionFromSnapshot(
      (jsonDecode(output.versionJson!) as Map).cast<String, Object?>(),
    );
    // Verify real bytes before associating any publication with the output.
    await _validateOutputBytes(await _files.file(output.relativePath), version);
    await _db.transaction(() async {
      await (_db.update(
        _db.uploadProcessingJobs,
      )..where((t) => t.id.equals(row.id))).write(
        UploadProcessingJobsCompanion(
          state: const Value('ready'),
          message: const Value(null),
          outputId: Value(id),
          updatedUtc: Value(_uploadNow),
        ),
      );
      for (final item in await _processingDependents(row.id)) {
        if (PublishState.values.byName(item.state).terminal ||
            item.state == 'unknown') {
          continue;
        }
        final original = _readUploadInput(item.inputJson);
        final input = FrozenUploadInput(
          kind: UploadInputKind.processed,
          referenceId: id,
          displayName: original.displayName,
          version: version,
          policyKey: _processedUploadPolicy(output.requestJson),
          processingSummary: _secretRedactor.redactText(
            _processedUploadCanonical(output.requestJson),
          ),
        );
        final batch = await (_db.select(
          _db.uploadBatches,
        )..where((t) => t.id.equals(item.batchId))).getSingle();
        final state = item.userPaused || batch.paused
            ? PublishState.paused
            : PublishState.queued;
        await _unprotectUpload(item.id);
        await (_db.update(
          _db.uploadPublications,
        )..where((t) => t.id.equals(item.id))).write(
          UploadPublicationsCompanion(
            inputJson: Value(jsonEncode(_inputSnapshot(input))),
            versionDigest: Value(version.sha256),
            byteCount: Value(version.byteCount),
            policyKey: Value(input.policyKey),
            resultId: const Value(null),
          ),
        );
        await _setUploadState(item.id, state);
        if (!state.terminal) await _protectUploadInput(input, item.id);
      }
      await _releaseProcessingProtection(row.id);
    });
  }

  /// Must run in the caller's writer transaction. False forbids original IO.
  Future<bool> _resolveProcessingDependency(UploadPublicationRow item) async {
    if (item.processingJobId == null) return true;
    if (PublishState.values.byName(item.state).terminal ||
        item.state == 'unknown') {
      return false;
    }
    final job = await _processingJobRow(item.processingJobId!);
    if (job.state == 'ready' &&
        _readUploadInput(item.inputJson).kind == UploadInputKind.processed) {
      return true;
    }
    final failed = job.state == 'failed' || job.state == 'cancelled';
    final waitingForRepair = job.state == 'waiting';
    if (item.state == 'paused') {
      await (_db.update(
        _db.uploadPublications,
      )..where((t) => t.id.equals(item.id))).write(
        UploadPublicationsCompanion(
          waitReason: Value(
            waitingForRepair ? 'inputUnavailable' : 'processing',
          ),
          message: Value(failed ? '上传前处理失败；继续时将跳过本项，原图未上传。' : '等待共享处理结果。'),
        ),
      );
    } else {
      await _setUploadState(
        item.id,
        failed ? PublishState.failed : PublishState.waiting,
        reason: failed
            ? null
            : waitingForRepair
            ? QueueWaitReason.inputUnavailable
            : QueueWaitReason.processing,
        message: failed
            ? '上传前处理失败，已跳过本项；原图未上传。'
            : waitingForRepair
            ? '冻结处理来源不可用；修复后明确重试处理，或取消。原图未上传。'
            : '等待共享处理结果。',
      );
      if (failed) await _unprotectUpload(item.id);
    }
    return false;
  }

  Future<bool> uploadProcessingHasActiveDependents(String id) => _serial(
    () async => (await _processingDependents(id)).any(
      (item) =>
          !PublishState.values.byName(item.state).terminal &&
          item.state != 'unknown',
    ),
  );

  Future<void> _retireUnusedProcessingJobs() async {
    for (final job in await (_db.select(
      _db.uploadProcessingJobs,
    )..where((t) => t.state.isIn(['queued', 'waiting']))).get()) {
      if ((await _processingDependents(job.id)).any(
        (item) =>
            !PublishState.values.byName(item.state).terminal &&
            item.state != 'unknown',
      )) {
        continue;
      }
      await (_db.update(
        _db.uploadProcessingJobs,
      )..where((t) => t.id.equals(job.id))).write(
        UploadProcessingJobsCompanion(
          state: const Value('cancelled'),
          updatedUtc: Value(_uploadNow),
        ),
      );
      await _releaseProcessingProtection(job.id);
    }
  }

  Future<void> retryUploadProcessingJob(String id) => _serial(() async {
    final row = await _processingJobRow(id);
    if (row.state != 'waiting' || _activeUploadProcessingJobs.contains(id)) {
      throw const UploadQueueFailure('只有等待修复的处理计划可以重试；失败终态请明确新建任务。');
    }
    final plan = _processingJob(row).plan;
    for (var i = 0; i < plan.assetIds.length; i++) {
      final asset = await (_db.select(
        _db.assets,
      )..where((t) => t.id.equals(plan.assetIds[i]))).getSingleOrNull();
      if (asset == null ||
          asset.recycled ||
          asset.versionId != plan.versions[i].id) {
        throw const UploadQueueFailure('冻结处理来源尚未恢复，不能替换为当前其他版本。');
      }
      await _uploadInputFile(
        FrozenUploadInput(
          kind: UploadInputKind.original,
          referenceId: asset.id,
          displayName: asset.displayName,
          version: plan.versions[i],
          policyKey: 'original-confirmed-v1',
        ),
      );
    }
    await (_db.update(
      _db.uploadProcessingJobs,
    )..where((t) => t.id.equals(id))).write(
      UploadProcessingJobsCompanion(
        state: const Value('queued'),
        outputId: const Value(null),
        message: const Value(null),
        updatedUtc: Value(_uploadNow),
      ),
    );
    _uploadChanges.add(null);
  });

  Future<void> _recoverUploadProcessing() async {
    for (final row in await _db.select(_db.uploadProcessingJobs).get()) {
      final job = _processingJob(
        row,
      ); // Reject corrupted/future logs, never reset.
      if (job.state == UploadProcessingState.running) {
        if (row.outputId != null) {
          final output = await (_db.select(
            _db.processedOutputs,
          )..where((t) => t.id.equals(row.outputId!))).getSingleOrNull();
          if (output?.state == 'ready') {
            await _confirmProcessingJobOutput(row, row.outputId!);
            continue;
          }
        }
        // A local pixel operation has no remote side effect. Rebuild from the
        // exact frozen version after normal output recovery; never infer files.
        await _db.transaction(() async {
          await _releaseProcessingOutputProtection(row.id);
          await (_db.update(
            _db.uploadProcessingJobs,
          )..where((t) => t.id.equals(row.id))).write(
            UploadProcessingJobsCompanion(
              state: const Value('queued'),
              outputId: const Value(null),
              updatedUtc: Value(_uploadNow),
            ),
          );
        });
      }
      if (job.state == UploadProcessingState.failed ||
          job.state == UploadProcessingState.cancelled) {
        await _db.transaction(() async {
          for (final item in await _processingDependents(row.id)) {
            await _resolveProcessingDependency(item);
          }
          await _releaseProcessingProtection(row.id);
        });
      }
    }
    await _db.transaction(_retireUnusedProcessingJobs);
  }
}
