part of 'library_repository.dart';

extension LibraryGalleryRemote on LibraryRepository {
  bool _hasRemoteScope(GalleryQuery query) =>
      query.remoteTargetId != null ||
      query.remoteService != null ||
      query.remoteInputKind != null;

  Expression<bool> _galleryRemoteScope(
    GalleryQuery query,
    Expression<String> targetId,
    Expression<String> service,
    Expression<String> kind,
  ) {
    Expression<bool> predicate = const Constant(true);
    if (query.remoteTargetId != null) {
      predicate = predicate & targetId.equals(query.remoteTargetId!);
    }
    if (query.remoteService != null) {
      predicate = predicate & service.equals(query.remoteService!.name);
    }
    if (query.remoteInputKind != null) {
      predicate = predicate & kind.equals(query.remoteInputKind!.name);
    }
    return predicate;
  }

  Expression<bool> _galleryRemoteWord(
    String? keyword,
    Expression<String> alias,
    Expression<String> service, {
    Expression<String>? url,
  }) {
    if (keyword == null || keyword.isEmpty) return const Constant(true);
    Expression<bool> contains(Expression<String> field) =>
        FunctionCallExpression<int>('instr', [
          _linkKey(field),
          Variable<String>(keyword),
        ]).isBiggerThanValue(0);
    return contains(alias) |
        contains(service) |
        (url == null ? const Constant(false) : contains(url));
  }

  Expression<bool> _galleryPublicationState(
    Expression<String> state,
    GalleryUploadFilter? filter,
  ) => switch (filter) {
    GalleryUploadFilter.confirmed => const Constant(false),
    GalleryUploadFilter.failed => state.equals(PublishState.failed.name),
    GalleryUploadFilter.unknown => state.equals(PublishState.unknown.name),
    GalleryUploadFilter.cancelled => state.equals(PublishState.cancelled.name),
    GalleryUploadFilter.active => state.isIn([
      PublishState.queued.name,
      PublishState.waiting.name,
      PublishState.running.name,
      PublishState.paused.name,
      PublishState.interrupted.name,
    ]),
    null || GalleryUploadFilter.withoutLinks => const Constant(true),
  };

  Expression<bool> _galleryResultEvidence(
    Assets assets,
    GalleryQuery query, {
    String? keyword,
  }) {
    if (query.uploadFilter != null &&
        query.uploadFilter != GalleryUploadFilter.confirmed &&
        query.uploadFilter != GalleryUploadFilter.withoutLinks) {
      return const Constant(false);
    }
    final result = _db.remoteUploadResults, version = _db.versions;
    final service = _linkJson(result.targetJson, 'service');
    final selected = _db.selectOnly(version)
      ..addColumns([version.id])
      ..join([
        innerJoin(
          result,
          result.versionDigest.equalsExp(version.digest) &
              result.byteCount.equalsExp(version.byteCount),
        ),
      ])
      ..where(
        _galleryRemoteScope(
              query,
              result.targetId,
              service,
              _linkJson(result.inputJson, 'kind'),
            ) &
            _galleryRemoteWord(
              keyword,
              _linkJson(result.targetJson, 'alias'),
              service,
              url: result.directUrl,
            ),
      );
    return assets.versionId.isInQuery(selected);
  }

  Expression<bool> _galleryPublicationEvidence(
    Assets assets,
    GalleryQuery query, {
    String? keyword,
  }) {
    final item = _db.uploadPublications, version = _db.versions;
    final service = _linkJson(item.targetJson, 'service');
    final selected = _db.selectOnly(version)
      ..addColumns([version.id])
      ..join([
        innerJoin(
          item,
          item.versionDigest.equalsExp(version.digest) &
              item.byteCount.equalsExp(version.byteCount),
        ),
      ])
      ..where(
        _galleryRemoteScope(
              query,
              item.targetId,
              service,
              _linkJson(item.inputJson, 'kind'),
            ) &
            _galleryPublicationState(item.state, query.uploadFilter) &
            _galleryRemoteWord(
              keyword,
              _linkJson(item.targetJson, 'alias'),
              service,
            ),
      );
    return assets.versionId.isInQuery(selected);
  }

  Expression<bool> _galleryArchivedEvidence(
    Assets assets,
    GalleryQuery query, {
    String? keyword,
  }) {
    final history = _db.importedUploadHistories, version = _db.versions;
    Expression<String> field(String path) =>
        _linkJson(history.snapshotJson, 'history[0].$path');
    final bytes = FunctionCallExpression<int>('json_extract', [
      history.snapshotJson,
      const Variable<String>(r'$.history[0].input.version.byteCount'),
    ]);
    final selected = _db.selectOnly(version)
      ..addColumns([version.id])
      ..join([
        innerJoin(
          history,
          field('input.version.sha256').equalsExp(version.digest) &
              bytes.equalsExp(version.byteCount),
        ),
      ])
      ..where(
        _galleryRemoteScope(
              query,
              field('target.id'),
              field('target.service'),
              field('input.kind'),
            ) &
            _galleryPublicationState(field('state'), query.uploadFilter) &
            _galleryRemoteWord(
              keyword,
              field('target.alias'),
              field('target.service'),
            ),
      );
    return assets.versionId.isInQuery(selected);
  }

  Expression<bool> _galleryRemotePredicate(
    Assets assets,
    GalleryQuery query, {
    String? keyword,
  }) {
    final results = _galleryResultEvidence(assets, query, keyword: keyword);
    final publications = _galleryPublicationEvidence(
      assets,
      query,
      keyword: keyword,
    );
    final archived = _galleryArchivedEvidence(assets, query, keyword: keyword);
    if (query.uploadFilter == GalleryUploadFilter.withoutLinks) {
      final none = _galleryResultEvidence(assets, query).not();
      return none &
          ((keyword != null || _hasRemoteScope(query))
              ? (publications | archived)
              : const Constant(true));
    }
    if (keyword == null &&
        query.uploadFilter == null &&
        !_hasRemoteScope(query)) {
      return const Constant(true);
    }
    return results | publications | archived;
  }

  Expression<int> _latestGalleryConfirmation(Assets assets) {
    final result = _db.remoteUploadResults, version = _db.versions;
    final latest = result.confirmedUtc.max();
    return subqueryExpression<int>(
      _db.selectOnly(result)
        ..addColumns([latest])
        ..join([
          innerJoin(
            version,
            version.digest.equalsExp(result.versionDigest) &
                version.byteCount.equalsExp(result.byteCount),
          ),
        ])
        ..where(version.id.equalsExp(assets.versionId)),
    );
  }

  Future<List<TargetSnapshot>> listGalleryRemoteTargets() => _serial(() async {
    await _syncOrdinaryLinkMasks();
    final rows = await _db
        .customSelect(
          'SELECT target_json FROM ('
          'SELECT target_json,ROW_NUMBER() OVER (PARTITION BY target_id ORDER BY stamp DESC,identity ASC,source ASC) AS ordinal FROM ('
          'SELECT target_id,target_json,confirmed_utc AS stamp,id AS identity,0 AS source FROM remote_upload_results '
          'UNION ALL SELECT target_id,target_json,updated_utc AS stamp,id AS identity,1 AS source FROM upload_publications '
          "UNION ALL SELECT json_extract(snapshot_json,'\$.history[0].target.id') AS target_id,"
          "json_extract(snapshot_json,'\$.history[0].target') AS target_json,"
          "json_extract(snapshot_json,'\$.history[0].updatedUtc') AS stamp,id AS identity,2 AS source FROM imported_upload_histories"
          ')) WHERE ordinal=1',
        )
        .get();
    final targets =
        rows
            .map((row) => _readUploadTarget(row.read<String>('target_json')))
            .toList()
          ..sort((a, b) {
            final name = TextPolicy.key(a.alias)
                .compareTo(TextPolicy.key(b.alias));
            return name == 0 ? a.id.compareTo(b.id) : name;
          });
    return List.unmodifiable(targets);
  });
}
