part of 'library_repository.dart';

extension LibraryOutputs on LibraryRepository {
  Future<void> _maintainOutputs() async {
    if (_closing != null || _closed || _restoreRequested) return;
    try {
      final result = await cleanupOutputs();
      for (final id in result.failedIds) {
        if (!_recoveryIssues.any((issue) => issue.operationId == id)) {
          _recoveryIssues = List.unmodifiable([
            ..._recoveryIssues,
            RecoveryIssue(id, '一项到期结果清理失败，记录与现场保留，将在可运行期间重试。'),
          ]);
        }
      }
    } catch (_) {
      if (!_closed &&
          !_recoveryIssues.any(
            (issue) => issue.operationId == 'output-cleanup',
          )) {
        _recoveryIssues = List.unmodifiable([
          ..._recoveryIssues,
          const RecoveryIssue('output-cleanup', '到期结果清理未完成，原数据已保留，请重试。'),
        ]);
      }
    }
  }

  Future<OutputWriteIntent> beginOutput(
    ProcessingRequest request, {
    required String displayName,
    OutputRetention retention = OutputRetention.day,
    int requiredStorageBytes = 0,
  }) => _serial(() async {
    if (_closing != null) throw StateError('图库正在关闭。');
    await _requireStorageBytes(requiredStorageBytes);
    final snapshot = request.toSnapshot();
    final sources = <String>{};
    final inputs = snapshot['inputs'] as List<Map<String, Object?>>;
    for (var i = 0; i < request.inputs.length; i++) {
      final input = request.inputs[i];
      final assetRow = await (_db.select(
        _db.assets,
      )..where((t) => t.id.equals(input.assetId))).getSingleOrNull();
      if (assetRow == null ||
          assetRow.recycled ||
          assetRow.versionId != input.version.id) {
        throw StateError('处理来源已失效。');
      }
      final asset = await _asset(assetRow);
      final lease =
          await (_db.select(_db.fileLeases)..where(
                (t) =>
                    t.versionId.equals(input.version.id) &
                    t.ownerId.equals(_leaseOwnerId),
              ))
              .get();
      final file = await _files.file(asset.deviceCopy.relativePath);
      if (lease.isEmpty ||
          asset.version != input.version ||
          file.path != input.file.absolute.path) {
        throw StateError('处理必须读取已取得使用租约的指定本机版本。');
      }
      inputs[i]['path'] = asset.deviceCopy.relativePath;
      sources.add(input.version.id);
    }
    final id = const Uuid().v4();
    final destination = await _files.file(
      'cache/outputs/$id.${request.outputFormat.name}.part',
    );
    final now = clock.now().toUtc();
    final row = ProcessedOutputsCompanion.insert(
      id: id,
      displayName: LibraryRepository._safeName(displayName),
      state: 'writing',
      relativePath: 'cache/outputs/$id.${request.outputFormat.name}',
      requestJson: jsonEncode(snapshot),
      createdUtc: now.millisecondsSinceEpoch,
      expiresUtc: now.add(retention.duration).millisecondsSinceEpoch,
    );
    await _db.transaction(() async {
      await _db.into(_db.processedOutputs).insert(row);
      for (final source in sources) {
        await _db
            .into(_db.versionReferences)
            .insert(
              VersionReferencesCompanion.insert(
                id: const Uuid().v4(),
                versionId: source,
                ownerType: 'output',
                ownerId: id,
              ),
            );
      }
    });
    _activeOutputWrites.add(id);
    _activeLeaseIds.add('output-write:$id');
    _leaseDrain ??= Completer<void>();
    // Faults here simulate termination after the durable intent. The caller
    // receives ownership before any normal pixel work starts.
    return OutputWriteIntent(id, destination);
  });

  Future<void> outputIntentBoundary() async =>
      _outputFaultHook?.call(OutputBoundary.intent);

  Future<ProcessedOutput> confirmOutput(
    String id,
    ProcessingResult result,
  ) => _serial(() async {
    final row = await _outputRow(id);
    if (!_activeOutputWrites.contains(id) || row.state != 'writing') {
      throw StateError('处理意图已结束。');
    }
    final request = await _outputRequest(row);
    if (jsonEncode(request.toSnapshot()) !=
            jsonEncode(result.request.toSnapshot()) ||
        result.file.absolute.path !=
            (await _files.file('${row.relativePath}.part')).path) {
      throw StateError('处理结果与原始策略或位置不一致。');
    }
    await _validateOutputBytes(result.file, result.version);
    // Flush a successfully closed encoder output before publishing its journal.
    final handle = await result.file.open(mode: FileMode.append);
    try {
      await handle.flush();
    } finally {
      await handle.close();
    }
    await (_db.update(
      _db.processedOutputs,
    )..where((t) => t.id.equals(id))).write(
      ProcessedOutputsCompanion(
        state: const Value('prepared'),
        versionJson: Value(jsonEncode(versionSnapshot(result.version))),
        warningsJson: Value(jsonEncode(result.warnings)),
        lossy: Value(result.lossy),
        transparencyRemoved: Value(result.transparencyRemoved),
        animationRemoved: Value(result.animationRemoved),
      ),
    );
    await _outputFaultHook?.call(OutputBoundary.prepared);
    await _publishOutput(await _outputRow(id));
    await _outputFaultHook?.call(OutputBoundary.published);
    await (_db.update(
      _db.processedOutputs,
    )..where((t) => t.id.equals(id))).write(
      const ProcessedOutputsCompanion(
        state: Value('ready'),
        availability: Value('available'),
      ),
    );
    await _outputFaultHook?.call(OutputBoundary.committed);
    if (!_restoreRequested) {
      await _noteDiagnostic(
        _DiagnosticAction(
          DiagnosticKind.processing,
          'processing.ready',
          '处理结果的独立文件已校验并提交。',
          '如结果不可用，请核查输入副本后重新处理。',
          entityId: id,
        ),
      );
    }
    return _output(await _outputRow(id));
  }, settling: true);

  /// Invoke after the worker's actual onExit, including cancellation/failure.
  Future<void> finishOutputWrite(String id, {ProcessingFailure? failure}) =>
      _serial(() async {
        try {
          final row = await _outputRow(id);
          if (failure != null && row.state == 'writing') {
            await (_db.update(
              _db.processedOutputs,
            )..where((t) => t.id.equals(id))).write(
              ProcessedOutputsCompanion(
                state: Value(
                  failure.kind == ProcessingFailureKind.cancelled
                      ? 'cancelled'
                      : 'failed',
                ),
                failureMessage: Value(_outputFailureMessage(failure)),
              ),
            );
            final part = await _files.file('${row.relativePath}.part');
            if (await part.exists()) await part.delete();
            await (_db.delete(_db.versionReferences)..where(
                  (t) => t.ownerType.equals('output') & t.ownerId.equals(id),
                ))
                .go();
          } else if (failure != null && row.state == 'prepared') {
            await (_db.update(
              _db.processedOutputs,
            )..where((t) => t.id.equals(id))).write(
              const ProcessedOutputsCompanion(
                failureMessage: Value('结果尚未完成提交，请重开后检查恢复结果。'),
              ),
            );
          }
          if (failure != null && !_restoreRequested) {
            await _noteDiagnostic(
              _DiagnosticAction(
                DiagnosticKind.processing,
                'processing.stopped',
                '处理线程已结束，原有资料保持有效。',
                '请核查输入与处理参数；存储故障请检查空间和权限。',
                entityId: id,
              ),
              failed: failure.kind != ProcessingFailureKind.cancelled,
            );
          }
        } finally {
          _activeOutputWrites.remove(id);
          _activeLeaseIds.remove('output-write:$id');
          if (_activeLeaseIds.isEmpty) {
            _leaseDrain?.complete();
            _leaseDrain = null;
          }
        }
      }, settling: true);

  // Persist only our known messages; never store arbitrary exception paths.
  String _outputFailureMessage(ProcessingFailure failure) =>
      switch (failure.kind) {
        ProcessingFailureKind.cancelled => '处理已取消，输入与已确认结果保留。',
        ProcessingFailureKind.storage => '结果写入或校验失败，请检查空间和权限。',
        ProcessingFailureKind.resourceBudget => '超出当前候选处理预算，请降低尺寸或减少输入。',
        ProcessingFailureKind.confirmationRequired => '需要明确确认动画选帧或透明背景转换。',
        ProcessingFailureKind.colorMetadataUnsupported =>
          '当前色彩元数据不能可靠保留，请选择支持的图片。',
        ProcessingFailureKind.unsupported => '不支持此次图片转换。',
        ProcessingFailureKind.inputChanged => '输入字节与指定版本不符，未生成可用结果。',
        ProcessingFailureKind.invalidParameters => '处理参数无效，请核对确认的像素区域和策略。',
        ProcessingFailureKind.invalidImage => '图片无法完整解码，未生成可用结果。',
      };

  Future<List<ProcessedOutput>> listOutputs() => _serial(() async {
    final rows =
        await (_db.select(_db.processedOutputs)..orderBy([
              (t) => OrderingTerm.desc(t.createdUtc),
              (t) => OrderingTerm.asc(t.id),
            ]))
            .get();
    return List.unmodifiable(await Future.wait(rows.map(_output)));
  });

  Future<ProcessedOutput> getOutput(String id) =>
      _serial(() async => _output(await _outputRow(id)));

  Future<ProcessedOutputRow> _outputRow(String id) async {
    final row = await (_db.select(
      _db.processedOutputs,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) throw StateError('处理结果已不存在。');
    _validateOutputRow(row);
    return row;
  }

  void _validateOutputRow(ProcessedOutputRow row) {
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    if (!uuid.hasMatch(row.id) ||
        !ProcessingFormat.values.any(
          (f) => row.relativePath == 'cache/outputs/${row.id}.${f.name}',
        ) ||
        row.createdUtc < 0 ||
        row.expiresUtc <= row.createdUtc ||
        !OutputState.values.any((s) => s.name == row.state)) {
      throw StateError('结果记录无法安全识别，已保留现场。');
    }
  }

  Future<ProcessingRequest> _outputRequest(ProcessedOutputRow row) async {
    _validateOutputRow(row);
    final snapshot = jsonDecode(row.requestJson) as Map<String, Object?>;
    for (final input
        in (snapshot['inputs'] as List).cast<Map<String, Object?>>()) {
      final relative = input['path'] as String;
      _validateOriginalPath(relative);
      input['path'] = (await _files.file(relative)).path;
    }
    final request = ProcessingRequest.fromSnapshot(snapshot);
    if (request.inputs.isEmpty ||
        row.relativePath !=
            'cache/outputs/${row.id}.${request.outputFormat.name}') {
      throw StateError('结果来源或格式不一致。');
    }
    return request;
  }

  Future<void> _validateOutputBytes(File file, ImageVersion version) async {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError('结果文件缺失或不是普通文件。');
    }
    final digest = await _files.digest(file);
    if (digest.sha256 != version.sha256 ||
        digest.byteCount != version.byteCount) {
      throw StateError('结果字节校验失败。');
    }
    final metadata = await _inspector.inspect(file);
    if (metadata.format != version.format ||
        metadata.width != version.width ||
        metadata.height != version.height ||
        metadata.frameCount != version.frameCount ||
        metadata.orientation != version.orientation) {
      throw StateError('结果元信息校验失败。');
    }
  }

  Future<ProcessedOutput> _output(ProcessedOutputRow row) async {
    final request = await _outputRequest(row);
    final version = row.versionJson == null
        ? null
        : versionFromSnapshot(
            jsonDecode(row.versionJson!) as Map<String, Object?>,
          );
    final state = OutputState.values.byName(row.state);
    File? usableFile;
    var availability = CopyAvailability.missing;
    if (state == OutputState.ready && version != null) {
      try {
        final file = await _files.file(row.relativePath);
        if (await file.exists()) {
          final digest = await _files.digest(file);
          availability =
              digest.sha256 == version.sha256 &&
                  digest.byteCount == version.byteCount
              ? CopyAvailability.available
              : CopyAvailability.damaged;
          if (availability == CopyAvailability.available) usableFile = file;
        }
      } catch (_) {
        availability = CopyAvailability.inaccessible;
      }
      if (availability.name != row.availability) {
        await (_db.update(
          _db.processedOutputs,
        )..where((t) => t.id.equals(row.id))).write(
          ProcessedOutputsCompanion(availability: Value(availability.name)),
        );
      }
    }
    return ProcessedOutput(
      id: row.id,
      displayName: row.displayName,
      state: state,
      request: request,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row.createdUtc,
        isUtc: true,
      ),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        row.expiresUtc,
        isUtc: true,
      ),
      version: version,
      availability: availability,
      file: usableFile,
      savedVersionId: row.savedVersionId,
      failureMessage: row.failureMessage,
      lossy: row.lossy,
      transparencyRemoved: row.transparencyRemoved,
      animationRemoved: row.animationRemoved,
      warnings: (jsonDecode(row.warningsJson) as List).cast<String>(),
    );
  }

  Future<void> _publishOutput(ProcessedOutputRow row) async {
    _validateOutputRow(row);
    final version = versionFromSnapshot(
      jsonDecode(row.versionJson!) as Map<String, Object?>,
    );
    final finalFile = await _files.file(row.relativePath);
    final part = await _files.file('${row.relativePath}.part');
    final candidate = await finalFile.exists() ? finalFile : part;
    await _validateOutputBytes(candidate, version);
    if (candidate == part) {
      await _files.publish('${row.relativePath}.part', row.relativePath);
    }
    await _validateOutputBytes(finalFile, version);
  }

  Future<ImportResult> saveOutput(
    String id, {
    String? displayName,
    CancellationToken? cancellation,
  }) => _serial(() async {
    final output = await _output(await _outputRow(id));
    if (!output.usable) throw StateError('结果缺失、损坏或尚未确认，不能永久保存。');
    final result = await _importResource(
      PlatformResource(
        displayName: displayName ?? output.displayName,
        sourceType: 'processed',
        openRead: output.file!.openRead,
      ),
      outputId: id,
      cancellation: cancellation,
    );
    await _noteImportDiagnostic(result, outputId: id);
    return result;
  });

  Future<void> _commitOutputSave(
    OperationRow operation,
    String versionId,
  ) async {
    final id = operation.outputId;
    if (id == null) return;
    final row = await _outputRow(id);
    final version = versionFromSnapshot(
      jsonDecode(row.versionJson!) as Map<String, Object?>,
    );
    if (row.state != 'ready' ||
        version.sha256 != operation.digest ||
        version.byteCount != operation.byteCount) {
      throw StateError('永久保存的来源结果不一致。');
    }
    final prior = await (_db.select(
      _db.savedOutputOrigins,
    )..where((t) => t.outputId.equals(id))).getSingleOrNull();
    if (prior != null &&
        (prior.versionId != versionId ||
            prior.requestJson != row.requestJson)) {
      throw StateError('永久保存来源记录冲突，已保留数据。');
    }
    await _db
        .into(_db.savedOutputOrigins)
        .insert(
          SavedOutputOriginsCompanion.insert(
            outputId: id,
            versionId: versionId,
            requestJson: row.requestJson,
            createdUtc: row.createdUtc,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    await (_db.update(_db.processedOutputs)..where((t) => t.id.equals(id)))
        .write(ProcessedOutputsCompanion(savedVersionId: Value(versionId)));
  }

  /// Provenance contains ordered source versions/parameters, never source grants.
  Future<List<ProcessingRequest>> savedOutputOrigins(String versionId) =>
      _serial(() async {
        final rows = await (_db.select(
          _db.savedOutputOrigins,
        )..where((t) => t.versionId.equals(versionId))).get();
        final result = <ProcessingRequest>[];
        for (final row in rows) {
          final snapshot = jsonDecode(row.requestJson) as Map<String, Object?>;
          for (final input
              in (snapshot['inputs'] as List).cast<Map<String, Object?>>()) {
            _validateOriginalPath(input['path'] as String);
            input['path'] = (await _files.file(input['path'] as String)).path;
          }
          result.add(ProcessingRequest.fromSnapshot(snapshot));
        }
        return List.unmodifiable(result);
      });

  Future<OutputFileLease> acquireOutputLease(String id) => _serial(() async {
    if (_closing != null) throw StateError('图库正在关闭。');
    final output = await _output(await _outputRow(id));
    if (!output.usable) throw StateError('结果不能读取，未取得文件使用权。');
    final leaseId = const Uuid().v4();
    await _db
        .into(_db.outputLeases)
        .insert(
          OutputLeasesCompanion.insert(
            id: leaseId,
            outputId: id,
            ownerId: _leaseOwnerId,
          ),
        );
    _activeLeaseIds.add(leaseId);
    _leaseDrain ??= Completer<void>();
    return OutputFileLease(
      output,
      () => _serial(() async {
        try {
          await (_db.delete(_db.outputLeases)..where(
                (t) => t.id.equals(leaseId) & t.ownerId.equals(_leaseOwnerId),
              ))
              .go();
        } finally {
          // Actual IO has ended even if its DB row cannot yet be cleared.
          // Leave persistent protection for retry/reopen, not a dead worker
          // in the in-process shutdown drain.
          _activeLeaseIds.remove(leaseId);
          if (_activeLeaseIds.isEmpty) {
            _leaseDrain?.complete();
            _leaseDrain = null;
          }
        }
      }, settling: true),
    );
  });

  Future<void> registerOutputProtection({
    required String outputId,
    required String ownerType,
    required String ownerId,
  }) => _serial(() async {
    if (!{
          'permanent',
          'task',
          'export',
          'backup',
          'restore',
        }.contains(ownerType) ||
        ownerId.trim().isEmpty ||
        ownerId.length > 200 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(ownerId)) {
      throw ArgumentError('保护引用无效。');
    }
    final row = await _outputRow(outputId);
    if (row.state != 'ready') throw StateError('结果尚不可引用。');
    await _db
        .into(_db.outputReferences)
        .insert(
          OutputReferencesCompanion.insert(
            id: const Uuid().v4(),
            outputId: outputId,
            ownerType: ownerType,
            ownerId: ownerId,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  });

  Future<void> releaseOutputProtection({
    required String outputId,
    required String ownerType,
    required String ownerId,
  }) => _serial(() async {
    await (_db.delete(_db.outputReferences)..where(
          (t) =>
              t.outputId.equals(outputId) &
              t.ownerType.equals(ownerType) &
              t.ownerId.equals(ownerId),
        ))
        .go();
  });

  /// Even manual cleaning only considers expired, safely unused managed files.
  Future<OutputCleanupResult> cleanupOutputs() => _serial(() async {
    var removed = 0;
    var protected = 0;
    final failures = <String>[];
    final now = clock.now().toUtc().millisecondsSinceEpoch;
    final rows = await (_db.select(
      _db.processedOutputs,
    )..where((t) => t.expiresUtc.isSmallerOrEqualValue(now))).get();
    for (final row in rows) {
      try {
        _validateOutputRow(row);
        final references = await (_db.select(
          _db.outputReferences,
        )..where((t) => t.outputId.equals(row.id))).get();
        final leases = await (_db.select(
          _db.outputLeases,
        )..where((t) => t.outputId.equals(row.id))).get();
        final saves = await (_db.select(
          _db.importOperations,
        )..where((t) => t.outputId.equals(row.id))).get();
        if (references.isNotEmpty ||
            leases.isNotEmpty ||
            saves.isNotEmpty ||
            _activeOutputWrites.contains(row.id)) {
          protected++;
          continue;
        }
        await (_db.update(_db.processedOutputs)
              ..where((t) => t.id.equals(row.id)))
            .write(const ProcessedOutputsCompanion(state: Value('deleting')));
        await _outputFaultHook?.call(OutputBoundary.beforeDelete);
        for (final relative in [row.relativePath, '${row.relativePath}.part']) {
          final file = await _files.file(relative);
          final type = await FileSystemEntity.type(
            file.path,
            followLinks: false,
          );
          if (type == FileSystemEntityType.file) {
            await file.delete();
          } else if (type != FileSystemEntityType.notFound) {
            throw StateError('清理目标不是普通文件。');
          }
        }
        await _db.transaction(() async {
          await (_db.delete(_db.versionReferences)..where(
                (t) => t.ownerType.equals('output') & t.ownerId.equals(row.id),
              ))
              .go();
          await (_db.delete(
            _db.processedOutputs,
          )..where((t) => t.id.equals(row.id))).go();
        });
        removed++;
      } catch (_) {
        failures.add(row.id);
      }
    }
    if ((removed > 0 || failures.isNotEmpty) && !_restoreRequested) {
      await _noteDiagnostic(
        const _DiagnosticAction(
          DiagnosticKind.cleanup,
          'outputs.cleanup',
          '到期且无保护的处理结果清理已结束。',
          '未清除的受保护结果需等待使用结束；失败项保留并稍后重试。',
        ),
        failed: failures.isNotEmpty,
      );
    }
    return OutputCleanupResult(removed, protected, failures);
  });

  Future<void> _recoverOutputs() => _serial(() async {
    final issues = [..._recoveryIssues];
    final rows = await _db.select(_db.processedOutputs).get();
    for (final row in rows) {
      try {
        _validateOutputRow(row);
        await _outputRequest(row);
        if (row.state == 'prepared') {
          await _publishOutput(row);
          await (_db.update(
            _db.processedOutputs,
          )..where((t) => t.id.equals(row.id))).write(
            const ProcessedOutputsCompanion(
              state: Value('ready'),
              availability: Value('available'),
            ),
          );
        } else if (row.state == 'writing') {
          await (_db.update(
            _db.processedOutputs,
          )..where((t) => t.id.equals(row.id))).write(
            const ProcessedOutputsCompanion(
              state: Value('failed'),
              failureMessage: Value('上次处理被中断，半成品没有成为有效结果。'),
            ),
          );
          final part = await _files.file('${row.relativePath}.part');
          if (await part.exists()) await part.delete();
          await (_db.delete(_db.versionReferences)..where(
                (t) => t.ownerType.equals('output') & t.ownerId.equals(row.id),
              ))
              .go();
        } else if (row.state == 'ready') {
          await _output(row);
        }
      } catch (_) {
        issues.add(RecoveryIssue(row.id, '一项处理结果无法安全恢复，已保留记录及现场。'));
      }
    }
    _recoveryIssues = List.unmodifiable(issues);
  });
}
