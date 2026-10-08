import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/text_policy.dart';
import '../../gallery/domain/library_models.dart';
import '../../gallery/domain/version_description_policy.dart';
import 'backup_manifest.dart';

enum BackupMergeScope { version, asset, category, tag }

enum BackupMergeIssueKind {
  identityCollision,
  versionDescriptionConflict,
  categoryConflict,
  tagLimitConflict,
}

/// Structured diagnostics contain identities, never arbitrary exception text.
final class BackupMergeIssue {
  BackupMergeIssue({
    required this.kind,
    required this.scope,
    required this.incomingId,
    required this.targetId,
    this.blocking = false,
    Iterable<String> ruleIds = const [],
  }) : ruleIds = List.unmodifiable(ruleIds);

  final BackupMergeIssueKind kind;
  final BackupMergeScope scope;
  final String incomingId, targetId;
  final bool blocking;
  final List<String> ruleIds;

  String get message => switch (kind) {
    BackupMergeIssueKind.identityCollision => '同一身份对应不同内容，保留当前值并重映射恢复项。',
    BackupMergeIssueKind.versionDescriptionConflict =>
      '相同摘要和大小的图片描述不一致，不能提交合并。',
    BackupMergeIssueKind.categoryConflict => '分类不同，保留当前分类。',
    BackupMergeIssueKind.tagLimitConflict => '标签并集超过 50 个，保留当前标签并阻止提交。',
  };
}

/// A pure, immutable proposal. It makes no assertion about available bytes and
/// does not restore accounts, histories, origins, database rows or files.
final class BackupMergePlan {
  BackupMergePlan._({
    required Iterable<ImageVersion> versions,
    required Iterable<BackupAsset> assets,
    required Iterable<BackupName> categories,
    required Iterable<BackupName> tags,
    required Map<String, String> versionIds,
    required Map<String, String> assetIds,
    required Map<String, String> categoryIds,
    required Map<String, String> tagIds,
    required Iterable<BackupMergeIssue> issues,
  }) : versions = List.unmodifiable(versions),
       assets = List.unmodifiable(assets),
       categories = List.unmodifiable(categories),
       tags = List.unmodifiable(tags),
       versionIds = Map.unmodifiable(versionIds),
       assetIds = Map.unmodifiable(assetIds),
       categoryIds = Map.unmodifiable(categoryIds),
       tagIds = Map.unmodifiable(tagIds),
       issues = List.unmodifiable(issues);

  final List<ImageVersion> versions;
  final List<BackupAsset> assets;
  final List<BackupName> categories, tags;
  final Map<String, String> versionIds, assetIds, categoryIds, tagIds;
  final List<BackupMergeIssue> issues;
  bool get canCommit => !issues.any((issue) => issue.blocking);
}

abstract final class BackupMergePlanner {
  static BackupMergePlan plan({
    required BackupManifest current,
    required BackupManifest incoming,
  }) {
    final issues = <BackupMergeIssue>[];
    final reserved = <String>{
      for (final manifest in [current, incoming]) ..._allIds(manifest),
    };
    final ids = _StableIds(incoming.packageId, reserved);
    final versionIds = <String, String>{};
    final versions = {for (final v in current.versions) v.id: v};
    final descriptions = Map<String, ImageVersion>.of(versions);
    for (final v in _auditVersions(current)) {
      if (versions.containsKey(v.id)) continue;
      final prior = descriptions[v.id];
      descriptions[v.id] = prior == null
          ? v
          : VersionDescriptionPolicy.preferredAudit(prior, v);
    }
    final contentVersions = {for (final v in current.versions) _content(v): v};
    for (final v in _sorted(incoming.versions, (v) => v.id)) {
      final sameIdentity = descriptions[v.id];
      final sameContent = contentVersions[_content(v)];
      if (sameContent != null) {
        versionIds[v.id] = sameContent.id;
        if (!_sameDescription(v, sameContent)) {
          issues.add(
            BackupMergeIssue(
              kind: BackupMergeIssueKind.versionDescriptionConflict,
              scope: BackupMergeScope.version,
              incomingId: v.id,
              targetId: sameContent.id,
              blocking: true,
            ),
          );
        }
        if (sameIdentity != null && _content(sameIdentity) != _content(v)) {
          _collision(issues, BackupMergeScope.version, v.id, sameContent.id);
        }
        continue;
      }
      if (sameIdentity != null &&
          _content(sameIdentity) == _content(v) &&
          !_sameDescription(sameIdentity, v) &&
          (versions.containsKey(v.id) ||
              !VersionDescriptionPolicy.isPngOrientationCorrection(
                sameIdentity,
                v,
              ))) {
        issues.add(
          BackupMergeIssue(
            kind: BackupMergeIssueKind.versionDescriptionConflict,
            scope: BackupMergeScope.version,
            incomingId: v.id,
            targetId: sameIdentity.id,
            blocking: true,
          ),
        );
      }
      final identityCollision =
          sameIdentity != null && _content(sameIdentity) != _content(v);
      final targetId = !identityCollision
          ? v.id
          : ids.allocate(
              BackupMergeScope.version,
              v.id,
              _content(v),
              (candidate) =>
                  versions[candidate] != null &&
                  _content(versions[candidate]!) == _content(v),
            );
      if (identityCollision) {
        _collision(issues, BackupMergeScope.version, v.id, targetId);
      }
      final target = _versionWithId(v, targetId);
      versions[targetId] = target;
      descriptions[targetId] = target;
      contentVersions[_content(v)] = target;
      versionIds[v.id] = targetId;
    }

    final categoryIds = <String, String>{}, tagIds = <String, String>{};
    final categories = _mergeNames(
      current.categories,
      incoming.categories,
      BackupMergeScope.category,
      ids,
      categoryIds,
      issues,
    );
    final tags = _mergeNames(
      current.tags,
      incoming.tags,
      BackupMergeScope.tag,
      ids,
      tagIds,
      issues,
    );
    final currentVersions = {for (final v in current.versions) v.id: v};
    final incomingVersions = {for (final v in incoming.versions) v.id: v};
    final assets = {for (final a in current.assets) a.id: a};
    final originalTags = {for (final a in current.assets) a.id: a.tagIds};
    final blockedTags = <String>{};
    final assetIds = <String, String>{};
    final currentByContent = <String, List<BackupAsset>>{};
    for (final a in _sorted(current.assets, (a) => a.id)) {
      currentByContent
          .putIfAbsent(_content(currentVersions[a.versionId]!), () => [])
          .add(a);
    }
    final newByContent = <String, String>{};
    for (final a in _sorted(incoming.assets, (a) => a.id)) {
      final content = _content(incomingVersions[a.versionId]!);
      final sameIdentity = assets[a.id];
      String targetId;
      if (sameIdentity != null &&
          _content(versions[sameIdentity.versionId]!) == content) {
        targetId = sameIdentity.id;
      } else if (sameIdentity != null) {
        // An identity collision preserves the restored asset independently,
        // even when another current asset happens to share its content.
        targetId = ids.allocate(
          BackupMergeScope.asset,
          a.id,
          content,
          (candidate) =>
              assets[candidate] != null &&
              _content(versions[assets[candidate]!.versionId]!) == content,
        );
        _collision(issues, BackupMergeScope.asset, a.id, targetId);
      } else {
        targetId =
            currentByContent[content]?.first.id ??
            newByContent[content] ??
            a.id;
      }
      final existing = assets[targetId];
      final mapped = _assetWith(
        a,
        id: targetId,
        versionId: versionIds[a.versionId]!,
        categoryId: a.categoryId == null ? null : categoryIds[a.categoryId],
        tagIds: a.tagIds.map((id) => tagIds[id]!),
      );
      originalTags.putIfAbsent(targetId, () => mapped.tagIds);
      assets[targetId] = existing == null
          ? mapped
          : _mergeAsset(
              existing,
              mapped,
              a.id,
              issues,
              originalTags[targetId]!,
              blockedTags,
            );
      assetIds[a.id] = targetId;
      newByContent.putIfAbsent(content, () => targetId);
    }
    return BackupMergePlan._(
      versions: versions.values,
      assets: assets.values,
      categories: categories,
      tags: tags,
      versionIds: versionIds,
      assetIds: assetIds,
      categoryIds: categoryIds,
      tagIds: tagIds,
      issues: issues,
    );
  }
}

Iterable<ImageVersion> _auditVersions(BackupManifest manifest) sync* {
  for (final origin in manifest.origins) {
    for (final input in origin.processing.inputs) {
      yield input.version;
    }
  }
  for (final result in manifest.results) {
    yield result.input.version;
  }
  for (final history in manifest.history) {
    yield history.input.version;
  }
}

Iterable<String> _allIds(BackupManifest manifest) sync* {
  yield manifest.packageId;
  yield* manifest.versions.map((v) => v.id);
  yield* manifest.assets.map((a) => a.id);
  yield* manifest.categories.map((n) => n.id);
  yield* manifest.tags.map((n) => n.id);
  yield* manifest.accounts.map((a) => a.id);
  for (final origin in manifest.origins) {
    yield origin.outputId;
    for (final input in origin.processing.inputs) {
      yield input.assetId;
      yield input.version.id;
    }
  }
  for (final result in manifest.results) {
    yield result.id;
    yield result.attemptId;
    yield result.target.id;
    yield result.input.referenceId;
    yield result.input.version.id;
  }
  for (final history in manifest.history) {
    yield history.id;
    yield history.batchId;
    yield history.target.id;
    yield history.input.referenceId;
    yield history.input.version.id;
    yield* history.attempts.map((a) => a.id);
  }
}

List<T> _sorted<T>(Iterable<T> values, String Function(T) id) =>
    values.toList()..sort((a, b) => id(a).compareTo(id(b)));

String _content(ImageVersion v) => '${v.sha256}:${v.byteCount}';
bool _sameDescription(ImageVersion a, ImageVersion b) =>
    a.format == b.format &&
    a.width == b.width &&
    a.height == b.height &&
    a.frameCount == b.frameCount &&
    a.orientation == b.orientation;

ImageVersion _versionWithId(ImageVersion v, String id) => ImageVersion(
  id: id,
  sha256: v.sha256,
  byteCount: v.byteCount,
  format: v.format,
  width: v.width,
  height: v.height,
  frameCount: v.frameCount,
  orientation: v.orientation,
);

void _collision(
  List<BackupMergeIssue> issues,
  BackupMergeScope scope,
  String source,
  String target,
) => issues.add(
  BackupMergeIssue(
    kind: BackupMergeIssueKind.identityCollision,
    scope: scope,
    incomingId: source,
    targetId: target,
  ),
);

List<BackupName> _mergeNames(
  List<BackupName> current,
  List<BackupName> incoming,
  BackupMergeScope scope,
  _StableIds ids,
  Map<String, String> mapping,
  List<BackupMergeIssue> issues,
) {
  final names = {for (final n in current) n.id: n};
  final byKey = {for (final n in current) TextPolicy.key(n.name): n};
  for (final n in incoming) {
    final key = TextPolicy.key(n.name);
    final sameIdentity = names[n.id];
    final sameName = byKey[key];
    final collision =
        sameIdentity != null && TextPolicy.key(sameIdentity.name) != key;
    final targetId =
        sameName?.id ??
        (collision
            ? ids.allocate(
                scope,
                n.id,
                key,
                (candidate) =>
                    names[candidate] != null &&
                    TextPolicy.key(names[candidate]!.name) == key,
              )
            : n.id);
    if (collision) _collision(issues, scope, n.id, targetId);
    if (sameName == null) {
      final target = BackupName(id: targetId, name: n.name);
      names[targetId] = target;
      byKey[key] = target;
    }
    mapping[n.id] = targetId;
  }
  return names.values.toList();
}

BackupAsset _assetWith(
  BackupAsset a, {
  required String id,
  required String versionId,
  required String? categoryId,
  required Iterable<String> tagIds,
  String? displayName,
  bool? favorite,
}) => BackupAsset(
  id: id,
  versionId: versionId,
  displayName: displayName ?? a.displayName,
  sourceType: a.sourceType,
  importedUtc: a.importedUtc,
  updatedUtc: a.updatedUtc,
  favorite: favorite ?? a.favorite,
  tagIds: tagIds,
  categoryId: categoryId,
  recycled: a.recycled,
  recycledUtc: a.recycledUtc,
);

BackupAsset _mergeAsset(
  BackupAsset current,
  BackupAsset incoming,
  String incomingId,
  List<BackupMergeIssue> issues,
  List<String> originalTags,
  Set<String> blockedTags,
) {
  if (current.categoryId != null &&
      incoming.categoryId != null &&
      current.categoryId != incoming.categoryId) {
    issues.add(
      BackupMergeIssue(
        kind: BackupMergeIssueKind.categoryConflict,
        scope: BackupMergeScope.asset,
        incomingId: incomingId,
        targetId: current.id,
      ),
    );
  }
  final union = <String>{...current.tagIds, ...incoming.tagIds};
  final exceedsLimit = union.length > TextPolicy.maxTags;
  if (exceedsLimit) {
    blockedTags.add(current.id);
    issues.add(
      BackupMergeIssue(
        kind: BackupMergeIssueKind.tagLimitConflict,
        scope: BackupMergeScope.asset,
        incomingId: incomingId,
        targetId: current.id,
        blocking: true,
        ruleIds: const ['BAK-004', 'LIB-003'],
      ),
    );
  }
  return _assetWith(
    current,
    id: current.id,
    versionId: current.versionId,
    displayName: current.displayName.trim().isEmpty
        ? incoming.displayName
        : current.displayName,
    categoryId: current.categoryId ?? incoming.categoryId,
    favorite: current.favorite || incoming.favorite,
    tagIds: blockedTags.contains(current.id) ? originalTags : union,
  );
}

final class _StableIds {
  _StableIds(this.packageId, this.reserved);
  final String packageId;
  final Set<String> reserved;

  String allocate(
    BackupMergeScope scope,
    String source,
    String content,
    bool Function(String) reusable,
  ) {
    for (var salt = 0; ; salt++) {
      final candidate = const Uuid().v5(
        packageId,
        jsonEncode([
          'imagehost-backup-merge-v1',
          scope.name,
          source,
          content,
          salt,
        ]),
      );
      if (reusable(candidate)) return candidate;
      if (reserved.add(candidate)) return candidate;
    }
  }
}
