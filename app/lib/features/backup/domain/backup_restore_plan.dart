import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../accounts/domain/account_models.dart';
import '../../gallery/domain/library_models.dart';
import '../../gallery/domain/version_description_policy.dart';
import '../../upload/domain/upload_queue_models.dart';
import 'backup_manifest.dart';
import 'backup_merge_plan.dart';
import 'backup_result_merge.dart';

enum BackupRestoreScope {
  manifest,
  version,
  assetReference,
  account,
  targetSnapshot,
  output,
  outputReference,
  result,
  history,
  attempt,
  batchPosition,
}

enum BackupRestoreIssueKind {
  identityCollision,
  versionDescriptionConflict,
  resultIdentityConflict,
  confirmationIdentityConflict,
  historyIdentityConflict,
  activeTaskConflict,
  historyAttemptConflict,
  activeAttemptConflict,
  batchPositionConflict,
  invalidRelations,
}

/// Diagnostics contain UUIDs and fixed enums, never names, URLs or errors.
final class BackupRestoreIssue {
  const BackupRestoreIssue({
    required this.kind,
    required this.scope,
    required this.incomingId,
    required this.targetId,
    this.blocking = false,
  });
  final BackupRestoreIssueKind kind;
  final BackupRestoreScope scope;
  final String incomingId, targetId;
  final bool blocking;
  String get message => switch (kind) {
    BackupRestoreIssueKind.identityCollision => '身份对应不同内容，保留当前关系并重映射恢复项。',
    BackupRestoreIssueKind.versionDescriptionConflict =>
      '相同内容的图片描述不一致，不能提交恢复提议。',
    BackupRestoreIssueKind.resultIdentityConflict => '结果身份对应不同确认，拒绝恢复该结果关联。',
    BackupRestoreIssueKind.confirmationIdentityConflict =>
      '尝试身份对应不同确认，拒绝恢复该结果关联。',
    BackupRestoreIssueKind.historyIdentityConflict => '历史任务身份对应不同内容，拒绝恢复该历史。',
    BackupRestoreIssueKind.activeTaskConflict => '历史任务身份与活动任务冲突，拒绝恢复该历史。',
    BackupRestoreIssueKind.historyAttemptConflict => '历史尝试身份已被其他历史使用，拒绝恢复该历史。',
    BackupRestoreIssueKind.activeAttemptConflict => '备份尝试身份与活动尝试冲突，拒绝恢复该关联。',
    BackupRestoreIssueKind.batchPositionConflict => '批次位置已被其他历史使用，拒绝恢复该历史。',
    BackupRestoreIssueKind.invalidRelations => '恢复提议的关联不能通过完整清单验证，禁止提交。',
  };
}

/// Pure metadata proposal. No bytes, credentials, queue reconstruction or IO.
final class BackupRestorePlan {
  BackupRestorePlan._({
    required this.metadata,
    required this.permanent,
    required Map<String, String> versionIds,
    required Map<String, String> assetIds,
    required Map<String, String> accountIds,
    required Map<String, String> outputIds,
    required Map<String, String> resultIds,
    required Iterable<BackupRestoreIssue> relationIssues,
  }) : versionIds = Map.unmodifiable(versionIds),
       assetIds = Map.unmodifiable(assetIds),
       accountIds = Map.unmodifiable(accountIds),
       outputIds = Map.unmodifiable(outputIds),
       resultIds = Map.unmodifiable(resultIds),
       relationIssues = List.unmodifiable(relationIssues);
  final BackupManifest? metadata;
  final BackupMergePlan permanent;
  final Map<String, String> versionIds,
      assetIds,
      accountIds,
      outputIds,
      resultIds;
  final List<BackupRestoreIssue> relationIssues;
  bool get canCommit =>
      metadata != null &&
      permanent.canCommit &&
      !relationIssues.any((issue) => issue.blocking);
}

abstract final class BackupRestorePlanner {
  static BackupRestorePlan plan({
    required BackupManifest current,
    required BackupManifest incoming,
    Set<String> activeTaskIds = const {},
    Set<String> activeAttemptIds = const {},
    Set<String> localOutputIds = const {},

    /// Keys are jsonEncode([batchId, position]) from live publications.
    Set<String> activePositions = const {},
  }) {
    final permanent = BackupMergePlanner.plan(
      current: current,
      incoming: incoming,
    );
    final work = _Relations(current, incoming, permanent, localOutputIds);
    return work.plan(activeTaskIds, activeAttemptIds, activePositions);
  }
}

bool _auditAgainstPermanent(ImageVersion audit, ImageVersion permanent) =>
    VersionDescriptionPolicy.same(audit, permanent) ||
    VersionDescriptionPolicy.isPngOrientationCorrection(audit, permanent);

final class _Relations {
  _Relations(this.current, this.incoming, this.permanent, this.localOutputIds)
    : versionIds = Map.of(permanent.versionIds),
      assetIds = Map.of(permanent.assetIds) {
    reserved.addAll(_identities(current));
    reserved.addAll(_identities(incoming));
    reserved.addAll(localOutputIds);
    reserved.addAll(permanent.versions.map((v) => v.id));
    reserved.addAll(permanent.assets.map((a) => a.id));
    reserved.addAll(permanent.categories.map((n) => n.id));
    reserved.addAll(permanent.tags.map((n) => n.id));
  }
  final BackupManifest current, incoming;
  final Set<String> localOutputIds;
  final BackupMergePlan permanent;
  final Map<String, String> versionIds, assetIds;
  final accountIds = <String, String>{}, outputIds = <String, String>{};
  final issues = <BackupRestoreIssue>[];
  final reserved = <String>{};
  final allocated = <String, String>{};
  final descriptions = <String, ImageVersion>{};
  final byContent = <String, ImageVersion>{};
  final permanentDescriptions = <String, ImageVersion>{};
  final permanentContent = <String, ImageVersion>{};
  late final currentAssets = {for (final a in current.assets) a.id: a};
  late final currentAccounts = {for (final a in current.accounts) a.id: a};

  void issue(
    BackupRestoreIssueKind kind,
    BackupRestoreScope scope,
    String source,
    String target, {
    bool blocking = false,
  }) {
    issues.add(
      BackupRestoreIssue(
        kind: kind,
        scope: scope,
        incomingId: source,
        targetId: target,
        blocking: blocking,
      ),
    );
  }

  String allocate(
    BackupRestoreScope scope,
    String source,
    String content,
    bool Function(String) reusable,
  ) {
    final key = jsonEncode([scope.name, source, content]);
    final existing = allocated[key];
    if (existing != null) return existing;
    for (var salt = 0; ; salt++) {
      final candidate = const Uuid().v5(
        incoming.packageId,
        jsonEncode([
          'imagehost-restore-audit-v1',
          scope.name,
          source,
          content,
          salt,
        ]),
      );
      if (reusable(candidate) || reserved.add(candidate)) {
        allocated[key] = candidate;
        return candidate;
      }
    }
  }

  void register(ImageVersion v, {bool audit = false}) {
    final prior = descriptions[v.id];
    final fixed = permanentDescriptions[v.id];
    final compatibleIdentity =
        prior == null ||
        (audit
            ? fixed == null
                  ? VersionDescriptionPolicy.auditCompatible(prior, v)
                  : _auditAgainstPermanent(v, fixed)
            : prior == v);
    if (!compatibleIdentity) {
      issue(
        audit && _content(prior) == _content(v)
            ? BackupRestoreIssueKind.versionDescriptionConflict
            : BackupRestoreIssueKind.invalidRelations,
        BackupRestoreScope.version,
        v.id,
        prior.id,
        blocking: true,
      );
      return;
    }
    descriptions[v.id] = prior == null || !audit
        ? v
        : fixed ?? VersionDescriptionPolicy.preferredAudit(prior, v);
    final same = byContent[_content(v)];
    final fixedContent = permanentContent[_content(v)];
    if (same != null &&
        !(audit
            ? fixedContent == null
                  ? VersionDescriptionPolicy.auditCompatible(v, same)
                  : _auditAgainstPermanent(v, fixedContent)
            : _description(v, same))) {
      issue(
        BackupRestoreIssueKind.versionDescriptionConflict,
        BackupRestoreScope.version,
        v.id,
        same.id,
        blocking: true,
      );
    }
    if (!audit) {
      permanentDescriptions[v.id] = v;
      permanentContent[_content(v)] = v;
    }
    if (same == null || !audit) {
      byContent[_content(v)] = v;
    } else if (fixedContent == null) {
      byContent[_content(v)] = _version(
        VersionDescriptionPolicy.preferredAudit(same, v),
        same.id,
      );
    }
  }

  ImageVersion version(ImageVersion v) => _version(v, versionIds[v.id] ?? v.id);

  void versions() {
    // Register all permanent descriptions before validating frozen audits.
    for (final v in _sorted(current.versions, (v) => v.id)) {
      register(v);
    }
    for (final v in _sorted(permanent.versions, (v) => v.id)) {
      register(v);
    }
    for (final v in _sorted(_auditVersions(current), (v) => v.id)) {
      register(v, audit: true);
    }
    final incomingPermanent = incoming.versions.map((v) => v.id).toSet();
    for (final v in _sorted(_auditVersions(incoming), (v) => v.id)) {
      if (incomingPermanent.contains(v.id)) {
        register(version(v), audit: true);
        continue;
      }
      final same = byContent[_content(v)];
      if (same != null) {
        versionIds[v.id] = same.id;
        if (descriptions[v.id] != null &&
            _content(descriptions[v.id]!) != _content(v)) {
          issue(
            BackupRestoreIssueKind.identityCollision,
            BackupRestoreScope.version,
            v.id,
            same.id,
          );
        }
        register(_version(v, same.id), audit: true);
      } else {
        final collision = descriptions[v.id] != null;
        final target = collision
            ? allocate(
                BackupRestoreScope.version,
                v.id,
                _content(v),
                (id) =>
                    descriptions[id] != null &&
                    _content(descriptions[id]!) == _content(v) &&
                    VersionDescriptionPolicy.auditCompatible(
                      descriptions[id]!,
                      v,
                    ),
              )
            : v.id;
        versionIds[v.id] = target;
        register(_version(v, target), audit: true);
        if (collision) {
          issue(
            BackupRestoreIssueKind.identityCollision,
            BackupRestoreScope.version,
            v.id,
            target,
          );
        }
      }
    }
  }

  String assetReference(String id, ImageVersion v) {
    final mapped = permanent.assetIds[id];
    if (mapped != null) return mapped;
    final currentAsset = currentAssets[id];
    if (currentAsset == null ||
        _content(descriptions[currentAsset.versionId]!) == _content(v)) {
      assetIds.putIfAbsent(id, () => id);
      return id;
    }
    final target = allocate(
      BackupRestoreScope.assetReference,
      id,
      _content(v),
      (candidate) => _assetReferences(current)
          .any((ref) => ref.$1 == candidate && _content(ref.$2) == _content(v)),
    );
    // A deleted asset can have multiple historical versions. Each input keeps
    // its contextual mapping; this summary map only represents one reference.
    assetIds.putIfAbsent(id, () => target);
    issue(
      BackupRestoreIssueKind.identityCollision,
      BackupRestoreScope.assetReference,
      id,
      target,
    );
    return target;
  }

  List<BackupAccount> accounts() {
    final retained = {for (final a in current.accounts) a.id: a};
    for (final a in _sorted(incoming.accounts, (a) => a.id)) {
      final prior = retained[a.id];
      final collision = prior != null && !_account(prior, a);
      final target = collision
          ? allocate(
              BackupRestoreScope.account,
              a.id,
              jsonEncode([a.service.name, a.anonymous]),
              (id) => retained[id] != null && _account(retained[id]!, a),
            )
          : a.id;
      accountIds[a.id] = target;
      retained.putIfAbsent(
        target,
        () => BackupAccount(
          id: target,
          service: a.service,
          alias: a.alias,
          anonymous: a.anonymous,
        ),
      );
      if (collision) {
        issue(
          BackupRestoreIssueKind.identityCollision,
          BackupRestoreScope.account,
          a.id,
          target,
        );
      }
    }
    return retained.values.toList();
  }

  TargetSnapshot target(TargetSnapshot t) {
    var id = accountIds[t.id];
    if (id == null) {
      final currentAccount = currentAccounts[t.id];
      if (currentAccount != null &&
          (currentAccount.service != t.service ||
              currentAccount.anonymous != t.anonymous)) {
        id = allocate(
          BackupRestoreScope.targetSnapshot,
          t.id,
          jsonEncode([t.service.name, t.anonymous]),
          (candidate) => _targets(current).any(
            (prior) =>
                prior.id == candidate &&
                prior.service == t.service &&
                prior.anonymous == t.anonymous,
          ),
        );
        issue(
          BackupRestoreIssueKind.identityCollision,
          BackupRestoreScope.targetSnapshot,
          t.id,
          id,
        );
      }
    }
    return TargetSnapshot(id ?? t.id, t.service, t.alias, t.anonymous);
  }

  BackupProcessingSnapshot processing(BackupProcessingSnapshot p) =>
      BackupProcessingSnapshot(
        operation: p.operation,
        inputs: p.inputs.map(
          (i) => BackupProcessingInput(
            assetId: assetReference(i.assetId, i.version),
            version: version(i.version),
            selectedFrame: i.selectedFrame,
          ),
        ),
        mode: p.mode,
        outputFormat: p.outputFormat,
        longestSide: p.longestSide,
        quality: p.quality,
        crop: p.crop,
        layout: p.layout,
        gap: p.gap,
        backgroundArgb: p.backgroundArgb,
        backgroundConfirmed: p.backgroundConfirmed,
        explicitStaticConversion: p.explicitStaticConversion,
      );

  List<BackupOrigin> origins() {
    final retained = {for (final o in current.origins) o.outputId: o};
    for (final o in _sorted(incoming.origins, (o) => o.outputId)) {
      final remapped = BackupOrigin(
        outputId: o.outputId,
        versionId: versionIds[o.versionId]!,
        createdUtc: o.createdUtc,
        processing: processing(o.processing),
      );
      final prior = retained[o.outputId];
      final collision =
          (prior != null && !_origin(prior, remapped)) ||
          (prior == null && localOutputIds.contains(o.outputId));
      final id = collision
          ? allocate(
              BackupRestoreScope.output,
              o.outputId,
              jsonEncode(_originPayload(remapped)),
              (candidate) =>
                  retained[candidate] != null &&
                  _origin(retained[candidate]!, remapped),
            )
          : o.outputId;
      outputIds[o.outputId] = id;
      retained.putIfAbsent(
        id,
        () => BackupOrigin(
          outputId: id,
          versionId: remapped.versionId,
          createdUtc: remapped.createdUtc,
          processing: remapped.processing,
        ),
      );
      if (collision) {
        issue(
          BackupRestoreIssueKind.identityCollision,
          BackupRestoreScope.output,
          o.outputId,
          id,
        );
      }
    }
    return retained.values.toList();
  }

  String outputReference(FrozenUploadInput input) {
    final mapped = outputIds[input.referenceId];
    if (mapped != null) return mapped;
    if (!localOutputIds.contains(input.referenceId)) return input.referenceId;
    final id = allocate(
      BackupRestoreScope.outputReference,
      input.referenceId,
      _content(input.version),
      (candidate) =>
          [
            ...current.results.map((r) => r.input),
            ...current.history.map((h) => h.input),
          ].any(
            (prior) =>
                prior.kind == UploadInputKind.processed &&
                prior.referenceId == candidate &&
                _content(prior.version) == _content(input.version),
          ),
    );
    issue(
      BackupRestoreIssueKind.identityCollision,
      BackupRestoreScope.outputReference,
      input.referenceId,
      id,
    );
    return id;
  }

  FrozenUploadInput input(FrozenUploadInput i) => FrozenUploadInput(
    kind: i.kind,
    referenceId: i.kind == UploadInputKind.original
        ? assetReference(i.referenceId, i.version)
        : outputReference(i),
    displayName: i.displayName,
    version: version(i.version),
    policyKey: i.policyKey,
    processingSummary: i.processingSummary,
  );

  List<BackupTaskHistory> histories(
    Set<String> activeTasks,
    Set<String> activeAttempts,
    Set<String> activePositions,
  ) {
    final retained = {for (final h in current.history) h.id: h};
    final attempts = {
      for (final h in current.history)
        for (final a in h.attempts) a.id: h.id,
    };
    final positions = {
      for (final h in current.history) '${h.batchId}:${h.position}': h.id,
    };
    for (final h in _sorted(incoming.history, (h) => h.id)) {
      final mapped = BackupTaskHistory(
        id: h.id,
        batchId: h.batchId,
        position: h.position,
        input: input(h.input),
        target: target(h.target),
        state: h.state,
        attempts: h.attempts,
        createdUtc: h.createdUtc,
        updatedUtc: h.updatedUtc,
        message: h.message,
      );
      final prior = retained[h.id];
      final duplicate = prior != null && _history(prior, mapped);
      var rejected = false;
      void reject(
        BackupRestoreIssueKind kind,
        BackupRestoreScope scope,
        String source,
        String target,
      ) {
        rejected = true;
        issue(kind, scope, source, target);
      }

      if (activeTasks.contains(h.id)) {
        reject(
          BackupRestoreIssueKind.activeTaskConflict,
          BackupRestoreScope.history,
          h.id,
          h.id,
        );
      }
      if (activePositions.contains(jsonEncode([h.batchId, h.position]))) {
        reject(
          BackupRestoreIssueKind.batchPositionConflict,
          BackupRestoreScope.batchPosition,
          h.id,
          h.batchId,
        );
      }
      if (prior != null && !duplicate) {
        reject(
          BackupRestoreIssueKind.historyIdentityConflict,
          BackupRestoreScope.history,
          h.id,
          prior.id,
        );
      }
      if (!duplicate) {
        for (final a in h.attempts) {
          if (attempts.containsKey(a.id)) {
            reject(
              BackupRestoreIssueKind.historyAttemptConflict,
              BackupRestoreScope.attempt,
              a.id,
              attempts[a.id]!,
            );
          }
          if (activeAttempts.contains(a.id)) {
            reject(
              BackupRestoreIssueKind.activeAttemptConflict,
              BackupRestoreScope.attempt,
              a.id,
              a.id,
            );
          }
        }
        final occupied = positions['${h.batchId}:${h.position}'];
        if (occupied != null && occupied != h.id) {
          reject(
            BackupRestoreIssueKind.batchPositionConflict,
            BackupRestoreScope.batchPosition,
            h.id,
            occupied,
          );
        }
      }
      if (rejected || duplicate) continue;
      retained[h.id] = mapped;
      positions['${h.batchId}:${h.position}'] = h.id;
      for (final a in h.attempts) {
        attempts[a.id] = h.id;
      }
    }
    return retained.values.toList();
  }

  BackupRestorePlan plan(
    Set<String> activeTasks,
    Set<String> activeAttempts,
    Set<String> activePositions,
  ) {
    versions();
    final mergedAccounts = accounts();
    final mergedOrigins = origins();
    final currentConfirmations = current.results
        .map((r) => r.attemptId)
        .toSet();
    final eligibleResults = incoming.results.where((r) {
      if (activeAttempts.contains(r.attemptId) &&
          !currentConfirmations.contains(r.attemptId)) {
        issue(
          BackupRestoreIssueKind.activeAttemptConflict,
          BackupRestoreScope.result,
          r.id,
          r.attemptId,
        );
        return false;
      }
      return true;
    });
    final resultPlan = BackupResultMergePlanner.plan(
      current: current.results,
      incoming: eligibleResults.map(
        (r) => BackupRemoteResult(
          id: r.id,
          attemptId: r.attemptId,
          input: input(r.input),
          target: target(r.target),
          remoteId: r.remoteId,
          directUrl: r.directUrl,
          viewerUrl: r.viewerUrl,
          confirmedUtc: r.confirmedUtc,
          late: r.late,
        ),
      ),
    );
    for (final c in resultPlan.conflicts) {
      issue(
        c.kind == BackupResultConflictKind.resultIdentity
            ? BackupRestoreIssueKind.resultIdentityConflict
            : BackupRestoreIssueKind.confirmationIdentityConflict,
        BackupRestoreScope.result,
        c.resultId,
        c.attemptId,
      );
    }
    final mergedHistory = histories(
      activeTasks,
      activeAttempts,
      activePositions,
    );
    BackupManifest? metadata;
    if (permanent.canCommit && !issues.any((i) => i.blocking)) {
      try {
        metadata = BackupManifest(
          packageId: incoming.packageId,
          createdUtc: incoming.createdUtc,
          mode: BackupMode.metadata,
          versions: permanent.versions,
          assets: permanent.assets,
          categories: permanent.categories,
          tags: permanent.tags,
          origins: mergedOrigins,
          accounts: mergedAccounts,
          results: resultPlan.results,
          history: mergedHistory,
          images: const [],
          settings: incoming.settings,
        );
      } catch (_) {
        issue(
          BackupRestoreIssueKind.invalidRelations,
          BackupRestoreScope.manifest,
          incoming.packageId,
          current.packageId,
          blocking: true,
        );
      }
    }
    return BackupRestorePlan._(
      metadata: metadata,
      permanent: permanent,
      versionIds: versionIds,
      assetIds: assetIds,
      accountIds: accountIds,
      outputIds: outputIds,
      resultIds: resultPlan.resultIds,
      relationIssues: issues,
    );
  }
}

Iterable<ImageVersion> _auditVersions(BackupManifest m) sync* {
  for (final o in m.origins) {
    for (final i in o.processing.inputs) {
      yield i.version;
    }
  }
  for (final r in m.results) {
    yield r.input.version;
  }
  for (final h in m.history) {
    yield h.input.version;
  }
}

Iterable<(String, ImageVersion)> _assetReferences(BackupManifest m) sync* {
  for (final o in m.origins) {
    for (final i in o.processing.inputs) {
      yield (i.assetId, i.version);
    }
  }
  for (final i in [
    ...m.results.map((r) => r.input),
    ...m.history.map((h) => h.input),
  ]) {
    if (i.kind == UploadInputKind.original) yield (i.referenceId, i.version);
  }
}

Iterable<TargetSnapshot> _targets(BackupManifest m) => [
  ...m.results.map((r) => r.target),
  ...m.history.map((h) => h.target),
];

Set<String> _identities(BackupManifest m) => {
  m.packageId,
  ...m.versions.map((v) => v.id),
  ..._auditVersions(m).map((v) => v.id),
  ...m.assets.map((a) => a.id),
  ...m.categories.map((n) => n.id),
  ...m.tags.map((n) => n.id),
  ...m.accounts.map((a) => a.id),
  ...m.origins.map((o) => o.outputId),
  ..._assetReferences(m).map((r) => r.$1),
  ..._targets(m).map((t) => t.id),
  for (final r in m.results) ...[r.id, r.attemptId, r.input.referenceId],
  for (final h in m.history) ...[
    h.id,
    h.batchId,
    h.input.referenceId,
    ...h.attempts.map((a) => a.id),
  ],
};

List<T> _sorted<T>(Iterable<T> values, String Function(T) id) =>
    values.toList()..sort((a, b) => id(a).compareTo(id(b)));
String _content(ImageVersion v) => '${v.sha256}:${v.byteCount}';
bool _description(ImageVersion a, ImageVersion b) =>
    a.format == b.format &&
    a.width == b.width &&
    a.height == b.height &&
    a.frameCount == b.frameCount &&
    a.orientation == b.orientation;
ImageVersion _version(ImageVersion v, String id) => ImageVersion(
  id: id,
  sha256: v.sha256,
  byteCount: v.byteCount,
  format: v.format,
  width: v.width,
  height: v.height,
  frameCount: v.frameCount,
  orientation: v.orientation,
);
bool _account(BackupAccount a, BackupAccount b) =>
    a.service == b.service && a.anonymous == b.anonymous;
List<Object?> _originPayload(BackupOrigin o) {
  final p = o.processing;
  return [
    o.versionId,
    o.createdUtc,
    p.operation.name,
    p.inputs
        .map(
          (i) => [
            i.assetId,
            i.version.id,
            _content(i.version),
            i.version.format,
            i.version.width,
            i.version.height,
            i.version.frameCount,
            i.version.orientation,
            i.selectedFrame,
          ],
        )
        .toList(),
    p.mode.name,
    p.outputFormat.name,
    p.longestSide,
    p.quality,
    p.crop == null
        ? null
        : [p.crop!.x, p.crop!.y, p.crop!.width, p.crop!.height],
    p.layout.name,
    p.gap,
    p.backgroundArgb,
    p.backgroundConfirmed,
    p.explicitStaticConversion,
  ];
}

bool _origin(BackupOrigin a, BackupOrigin b) =>
    jsonEncode(_originPayload(a)) == jsonEncode(_originPayload(b));
List<Object?> _inputPayload(FrozenUploadInput i) => [
  i.kind.name,
  i.referenceId,
  i.displayName,
  i.version.id,
  _content(i.version),
  i.version.format,
  i.version.width,
  i.version.height,
  i.version.frameCount,
  i.version.orientation,
  i.policyKey,
  i.processingSummary,
];
List<Object?> _historyPayload(BackupTaskHistory h) => [
  h.batchId,
  h.position,
  _inputPayload(h.input),
  [h.target.id, h.target.service.name, h.target.alias, h.target.anonymous],
  h.state.name,
  h.createdUtc,
  h.updatedUtc,
  h.message,
  h.attempts
      .map((a) => [a.id, a.generation, a.startedUtc, a.endedUtc, a.outcome])
      .toList(),
];
bool _history(BackupTaskHistory a, BackupTaskHistory b) =>
    jsonEncode(_historyPayload(a)) == jsonEncode(_historyPayload(b));
