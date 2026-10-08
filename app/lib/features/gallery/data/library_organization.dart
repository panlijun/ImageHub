part of 'library_repository.dart';

/// Shared mutations validate the complete batch before one metadata transaction.
extension LibraryOrganization on LibraryRepository {
  Future<List<LibraryCategory>> listCategories() => _serial(() async {
    final rows =
        await (_db.select(_db.categories)..orderBy([
              (t) => OrderingTerm.asc(t.nameKey),
              (t) => OrderingTerm.asc(t.id),
            ]))
            .get();
    final result = <LibraryCategory>[];
    for (final row in rows) {
      final count = _db.assets.id.count();
      final query = _db.selectOnly(_db.assets)
        ..addColumns([count])
        ..where(_db.assets.category.equals(row.id));
      result.add(
        LibraryCategory(
          id: row.id,
          name: row.name,
          assetCount: (await query.getSingle()).read(count) ?? 0,
        ),
      );
    }
    return List.unmodifiable(result);
  });

  Future<List<LibraryTag>> listTags() => _serial(
    () async => List.unmodifiable(
      (await (_db.select(_db.tags)..orderBy([
                (t) => OrderingTerm.asc(t.nameKey),
                (t) => OrderingTerm.asc(t.id),
              ]))
              .get())
          .map((row) => LibraryTag(id: row.id, name: row.name)),
    ),
  );

  Future<LibraryCategory> createCategory(String input) => _serial(() async {
    final name = TextPolicy.normalizeName(input);
    final key = TextPolicy.key(name);
    final existing = await (_db.select(
      _db.categories,
    )..where((t) => t.nameKey.equals(key))).getSingleOrNull();
    if (existing != null) {
      return LibraryCategory(id: existing.id, name: existing.name);
    }
    final id = const Uuid().v4();
    await _db
        .into(_db.categories)
        .insert(CategoriesCompanion.insert(id: id, name: name, nameKey: key));
    return LibraryCategory(id: id, name: name);
  });

  Future<void> renameCategory(String id, String input) => _serial(
    () => _db.transaction(() async {
      final name = TextPolicy.normalizeName(input);
      final key = TextPolicy.key(name);
      final current = await (_db.select(
        _db.categories,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (current == null) {
        throw const LibraryMutationException('分类已不存在，请重新读取。');
      }
      final duplicate =
          await (_db.select(_db.categories)
                ..where((t) => t.nameKey.equals(key) & t.id.equals(id).not()))
              .getSingleOrNull();
      if (duplicate != null) {
        throw const LibraryMutationException('已有同名分类，请使用其他名称。');
      }
      await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
        CategoriesCompanion(name: Value(name), nameKey: Value(key)),
      );
      await (_db.update(_db.assets)..where((t) => t.category.equals(id))).write(
        AssetsCompanion(
          updatedUtc: Value(clock.now().toUtc().millisecondsSinceEpoch),
        ),
      );
    }),
  );

  Future<void> removeCategory(String id) => _serial(
    () => _db.transaction(() async {
      final current = await (_db.select(
        _db.categories,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (current == null) {
        throw const LibraryMutationException('分类已不存在，请重新读取。');
      }
      await (_db.update(_db.assets)..where((t) => t.category.equals(id))).write(
        AssetsCompanion(
          category: const Value(null),
          updatedUtc: Value(clock.now().toUtc().millisecondsSinceEpoch),
        ),
      );
      await (_db.delete(_db.categories)..where((t) => t.id.equals(id))).go();
    }),
  );

  Future<List<AssetRow>> _requireAssetRows(
    Iterable<String> ids, {
    bool allowRecycled = false,
  }) async {
    final identities = ids.toSet();
    if (identities.isEmpty) throw const LibraryMutationException('请先选择图片。');
    final rows = await (_db.select(
      _db.assets,
    )..where((t) => t.id.isIn(identities))).get();
    if (rows.length != identities.length ||
        (!allowRecycled && rows.any((row) => row.recycled))) {
      throw const LibraryMutationException('部分所选图片已不存在或位于回收区，未修改任何项目。');
    }
    return rows;
  }

  Future<List<LibraryTag>> _readTags(String assetId) async {
    final links =
        await (_db.select(_db.assetTags)
              ..where((t) => t.assetId.equals(assetId))
              ..orderBy([
                (t) => OrderingTerm.asc(t.position),
                (t) => OrderingTerm.asc(t.tagId),
              ]))
            .get();
    final result = <LibraryTag>[];
    for (final link in links) {
      final tag = await (_db.select(
        _db.tags,
      )..where((t) => t.id.equals(link.tagId))).getSingle();
      result.add(LibraryTag(id: tag.id, name: tag.name));
    }
    return List.unmodifiable(result);
  }

  Future<void> assignCategory(Iterable<String> ids, String? categoryId) =>
      updateOrganization(ids, setCategory: true, categoryId: categoryId);
  Future<void> replaceTags(Iterable<String> ids, Iterable<String> tags) =>
      updateOrganization(ids, replaceTags: tags);
  Future<void> addTags(Iterable<String> ids, Iterable<String> tags) =>
      updateOrganization(ids, addTags: tags);
  Future<void> removeTags(Iterable<String> ids, Iterable<String> tags) =>
      updateOrganization(ids, removeTags: tags);
  Future<void> setFavorites(Iterable<String> ids, bool favorite) =>
      updateOrganization(ids, favorite: favorite);

  Future<void> updateOrganization(
    Iterable<String> ids, {
    Iterable<String>? replaceTags,
    Iterable<String>? addTags,
    Iterable<String>? removeTags,
    bool setCategory = false,
    String? categoryId,
    bool? favorite,
  }) async {
    // Capture caller-owned input now; editing a draft later cannot change a batch.
    final capturedIds = List<String>.unmodifiable(ids);
    final replace = replaceTags == null ? null : TextPolicy.tags(replaceTags);
    final add = addTags == null ? null : TextPolicy.tags(addTags);
    final remove = removeTags == null ? null : TextPolicy.tags(removeTags);
    return _serial(
      () => _db.transaction(() async {
        final assets = await _requireAssetRows(capturedIds);
        if (setCategory &&
            categoryId != null &&
            await (_db.select(
                  _db.categories,
                )..where((t) => t.id.equals(categoryId))).getSingleOrNull() ==
                null) {
          throw const LibraryMutationException('分类已不存在，未修改任何项目。');
        }
        final planned = <String, List<String>>{};
        if (replace != null || add != null || remove != null) {
          final removeKeys = remove?.map(TextPolicy.key).toSet() ?? <String>{};
          for (final asset in assets) {
            final previous = (await _readTags(asset.id)).map((tag) => tag.name);
            planned[asset.id] = TextPolicy.tags(
              [
                ...(replace ?? previous),
                ...?add,
              ].where((name) => !removeKeys.contains(TextPolicy.key(name))),
            );
          }
        }
        // All 50-tag limits have passed before any bridge/catalog write occurs.
        final catalog = <String, TagRow>{};
        for (final name in planned.values.expand((names) => names)) {
          final key = TextPolicy.key(name);
          if (catalog.containsKey(key)) continue;
          var row = await (_db.select(
            _db.tags,
          )..where((t) => t.nameKey.equals(key))).getSingleOrNull();
          if (row == null) {
            final id = const Uuid().v4();
            await _db
                .into(_db.tags)
                .insert(TagsCompanion.insert(id: id, name: name, nameKey: key));
            row = await (_db.select(
              _db.tags,
            )..where((t) => t.id.equals(id))).getSingle();
          }
          catalog[key] = row;
        }
        final now = clock.now().toUtc().millisecondsSinceEpoch;
        for (final asset in assets) {
          final tags = planned[asset.id];
          if (tags != null) {
            await (_db.delete(
              _db.assetTags,
            )..where((t) => t.assetId.equals(asset.id))).go();
            for (var i = 0; i < tags.length; i++) {
              await _db
                  .into(_db.assetTags)
                  .insert(
                    AssetTagsCompanion.insert(
                      assetId: asset.id,
                      tagId: catalog[TextPolicy.key(tags[i])]!.id,
                      position: i,
                    ),
                  );
            }
          }
          if (tags != null || setCategory || favorite != null) {
            await (_db.update(
              _db.assets,
            )..where((t) => t.id.equals(asset.id))).write(
              AssetsCompanion(
                updatedUtc: Value(now),
                category: setCategory
                    ? Value(categoryId)
                    : const Value.absent(),
                favorite: favorite == null
                    ? const Value.absent()
                    : Value(favorite),
              ),
            );
          }
        }
      }),
    );
  }

  Future<void> refreshCopyStatuses({
    CancellationToken? cancellation,
    void Function(int done, int total)? onProgress,
  }) => _serial(() async {
    final rows = await _db.select(_db.assets).get();
    final seen = <String>{};
    final versions = rows.where((row) => seen.add(row.versionId)).toList();
    var done = 0;
    onProgress?.call(done, versions.length);
    for (final row in versions) {
      cancellation?.throwIfCancelled();
      final asset = await _asset(row);
      final availability = await _verify(asset);
      await (_db.update(
        _db.deviceCopies,
      )..where((t) => t.versionId.equals(asset.version.id))).write(
        DeviceCopiesCompanion(
          availability: Value(availability.name),
          verifiedUtc: Value(clock.now().toUtc().millisecondsSinceEpoch),
        ),
      );
      onProgress?.call(++done, versions.length);
    }
  });
}
