import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/backup/domain/backup_merge_plan.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:uuid/uuid.dart';

import 'dart:convert';

String id(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

ImageVersion version(
  int n, {
  String hash = 'a',
  int bytes = 100,
  String format = 'PNG',
  int width = 10,
  int height = 20,
  int frames = 1,
  int orientation = 1,
}) => ImageVersion(
  id: id(n),
  sha256: hash * 64,
  byteCount: bytes,
  format: format,
  width: width,
  height: height,
  frameCount: frames,
  orientation: orientation,
);

BackupName name(int n, String value) => BackupName(id: id(n), name: value);

BackupAsset asset(
  int n,
  int v, {
  String displayName = '原名',
  int? category,
  Iterable<int> tags = const [],
  bool favorite = false,
  bool recycled = false,
  int imported = 100,
  int updated = 200,
  String source = 'selected',
  int? recycledUtc,
}) => BackupAsset(
  id: id(n),
  versionId: id(v),
  displayName: displayName,
  sourceType: source,
  importedUtc: imported,
  updatedUtc: updated,
  favorite: favorite,
  tagIds: tags.map(id),
  categoryId: category == null ? null : id(category),
  recycled: recycled,
  recycledUtc: recycled ? recycledUtc ?? 300 : null,
);

BackupManifest manifest({
  int package = 900,
  BackupMode mode = BackupMode.metadata,
  List<ImageVersion> versions = const [],
  List<BackupAsset> assets = const [],
  List<BackupName> categories = const [],
  List<BackupName> tags = const [],
}) => BackupManifest(
  packageId: id(package),
  createdUtc: 400,
  mode: mode,
  versions: versions,
  assets: assets,
  categories: categories,
  tags: tags,
  origins: const [],
  accounts: const [],
  results: const [],
  history: const [],
  images: mode == BackupMode.full
      ? versions.map(
          (v) => BackupImageEntry(
            versionId: v.id,
            name: 'images/${v.id}.${v.format.toLowerCase()}',
            byteCount: v.byteCount,
            sha256: v.sha256,
          ),
        )
      : const [],
);

BackupManifest fromPlan(BackupMergePlan plan) => manifest(
  versions: plan.versions,
  assets: plan.assets,
  categories: plan.categories,
  tags: plan.tags,
);

BackupMergePlan merge(BackupManifest current, BackupManifest incoming) =>
    BackupMergePlanner.plan(current: current, incoming: incoming);

void main() {
  group('UT-076 partial permanent metadata merge', () {
    test('keeps current name/category/timestamps/source/recycle; tags union and favorite OR', () {
      final current = manifest(
        versions: [version(1)],
        assets: [
          asset(10, 1, category: 20, tags: [30], recycled: true),
        ],
        categories: [name(20, '本地')],
        tags: [name(30, '保留')],
      );
      final incoming = manifest(
        versions: [version(2)],
        assets: [
          asset(
            11,
            2,
            displayName: '来包',
            category: 21,
            tags: [31, 32],
            favorite: true,
            imported: 500,
            updated: 600,
            source: 'camera',
          ),
        ],
        categories: [name(21, '备份')],
        tags: [name(31, '保留'), name(32, '新增')],
      );
      final plan = merge(current, incoming);
      final result = plan.assets.single;
      expect(plan.canCommit, isTrue);
      expect(result.id, id(10));
      expect(result.displayName, '原名');
      expect(result.categoryId, id(20));
      expect(result.tagIds, [id(30), id(32)]);
      expect(result.favorite, isTrue);
      expect(result.importedUtc, 100);
      expect(result.updatedUtc, 200);
      expect(result.sourceType, 'selected');
      expect(result.recycled, isTrue);
      expect(result.recycledUtc, 300);
      expect(plan.issues.single.kind, BackupMergeIssueKind.categoryConflict);
      expect(current.assets.single.tagIds, [id(30)]);
      expect(incoming.assets.single.tagIds, [id(31), id(32)]);
    });

    test(
      'empty current name/category accepts incoming without inventing time',
      () {
        final plan = merge(
          manifest(
            versions: [version(1)],
            assets: [asset(10, 1, displayName: '  ')],
          ),
          manifest(
            versions: [version(2)],
            assets: [asset(11, 2, displayName: '恢复名', category: 20)],
            categories: [name(20, '分类')],
          ),
        );
        expect(plan.assets.single.displayName, '恢复名');
        expect(plan.assets.single.categoryId, id(20));
        expect(plan.assets.single.updatedUtc, 200);
      },
    );

    test(
      'same content different UUID maps both version and asset to current',
      () {
        final plan = merge(
          manifest(versions: [version(1)], assets: [asset(10, 1)]),
          manifest(versions: [version(2)], assets: [asset(11, 2)]),
        );
        expect(plan.versionIds, {id(2): id(1)});
        expect(plan.assetIds, {id(11): id(10)});
        expect(plan.versions.single.id, id(1));
        expect(plan.assets.single.versionId, id(1));
      },
    );

    test('same UUID same content takes priority over smallest other asset', () {
      final plan = merge(
        manifest(versions: [version(1)], assets: [asset(9, 1), asset(10, 1)]),
        manifest(versions: [version(2)], assets: [asset(10, 2)]),
      );
      expect(plan.assetIds[id(10)], id(10));
      expect(plan.assets.length, 2);
    });

    test(
      'multiple current candidates use UUID order independent of input order',
      () {
        final incoming = manifest(
          versions: [version(2)],
          assets: [asset(50, 2)],
        );
        final a = merge(
          manifest(
            versions: [version(1)],
            assets: [asset(20, 1), asset(10, 1)],
          ),
          incoming,
        );
        final b = merge(
          manifest(
            versions: [version(1)],
            assets: [asset(10, 1), asset(20, 1)],
          ),
          incoming,
        );
        expect(a.assetIds[id(50)], id(10));
        expect(b.assetIds, a.assetIds);
      },
    );

    test('multiple incoming same-content assets aggregate in UUID order', () {
      final plan = merge(
        manifest(),
        manifest(
          versions: [version(1)],
          assets: [
            asset(20, 1, displayName: '第二', tags: [32]),
            asset(10, 1, displayName: '第一', tags: [31]),
          ],
          tags: [name(32, '二'), name(31, '一')],
        ),
      );
      expect(plan.assets.single.id, id(10));
      expect(plan.assets.single.displayName, '第一');
      expect(plan.assets.single.tagIds, [id(31), id(32)]);
      expect(plan.assetIds, {id(10): id(10), id(20): id(10)});
    });

    test('new recycled asset preserves all backup metadata', () {
      final plan = merge(
        manifest(),
        manifest(
          versions: [version(1)],
          assets: [
            asset(
              10,
              1,
              recycled: true,
              recycledUtc: 750,
              imported: 500,
              updated: 600,
              source: 'processed',
            ),
          ],
        ),
      );
      expect(plan.assets.single.recycled, isTrue);
      expect(plan.assets.single.recycledUtc, 750);
      expect(plan.assets.single.importedUtc, 500);
      expect(plan.assets.single.updatedUtc, 600);
      expect(plan.assets.single.sourceType, 'processed');
    });

    test('Unicode full folding reuses current spelling and directory ID', () {
      final plan = merge(
        manifest(
          versions: [version(1)],
          assets: [
            asset(10, 1, category: 20, tags: [30, 32]),
          ],
          categories: [name(20, 'Straße')],
          tags: [name(30, 'Straße'), name(32, 'Σ')],
        ),
        manifest(
          versions: [version(2)],
          assets: [
            asset(11, 2, category: 21, tags: [31, 33]),
          ],
          categories: [name(21, 'STRASSE')],
          tags: [name(31, 'STRASSE'), name(33, 'ς')],
        ),
      );
      expect(plan.categoryIds[id(21)], id(20));
      expect(plan.tagIds[id(31)], id(30));
      expect(plan.tagIds[id(33)], id(32));
      expect(plan.tags.map((n) => n.name), ['Straße', 'Σ']);
      expect(plan.assets.single.tagIds, [id(30), id(32)]);
      expect(plan.issues, isEmpty);
    });

    test('50 union accepted; 51 blocks without truncating current labels', () {
      final currentTags = [for (var i = 0; i < 50; i++) name(100 + i, '标签$i')];
      final current = manifest(
        versions: [version(1)],
        assets: [asset(10, 1, tags: List.generate(50, (i) => 100 + i))],
        tags: currentTags,
      );
      final accepted = merge(
        current,
        manifest(
          versions: [version(2)],
          assets: [
            asset(11, 2, tags: [200]),
          ],
          tags: [name(200, '标签49')],
        ),
      );
      expect(accepted.canCommit, isTrue);
      expect(accepted.assets.single.tagIds.length, 50);
      final blocked = merge(
        current,
        manifest(
          versions: [version(2)],
          assets: [
            asset(11, 2, tags: [200]),
          ],
          tags: [name(200, '第51个')],
        ),
      );
      expect(blocked.canCommit, isFalse);
      expect(blocked.assets.single.tagIds, current.assets.single.tagIds);
      expect(blocked.issues.single.kind, BackupMergeIssueKind.tagLimitConflict);
      expect(blocked.issues.single.ruleIds, ['BAK-004', 'LIB-003']);
      expect(blocked.tags.length, 51);
      expect(current.assets.single.tagIds.length, 50);
    });

    test('later aggregate overflow restores original current tags and stays blocked', () {
      final tags = [for (var i = 0; i < 49; i++) name(100 + i, '标签$i')];
      final current = manifest(
        versions: [version(1)],
        assets: [asset(10, 1, tags: List.generate(49, (i) => 100 + i))],
        tags: tags,
      );
      final plan = merge(
        current,
        manifest(
          versions: [version(2)],
          assets: [
            asset(20, 2, tags: [200]),
            asset(21, 2, tags: [201]),
            asset(22, 2, tags: [202]),
          ],
          tags: [name(200, '新增一'), name(201, '新增二'), name(202, '新增三')],
        ),
      );
      expect(plan.canCommit, isFalse);
      expect(plan.assets.single.tagIds, current.assets.single.tagIds);
    });

    for (final mode in BackupMode.values) {
      test('accepts ${mode.name} manifest as pure metadata plan', () {
        final plan = merge(
          manifest(),
          manifest(mode: mode, versions: [version(1)], assets: [asset(10, 1)]),
        );
        expect(plan.canCommit, isTrue);
        expect(plan.assets.single.id, id(10));
      });
    }
  });

  group('UT-077 partial identity and contradiction handling', () {
    test('UUID content collisions preserve current and allocate stable IDs; replay is idempotent', () {
      final current = manifest(versions: [version(1)], assets: [asset(10, 1)]);
      final incoming = manifest(
        package: 901,
        versions: [version(1, hash: 'b')],
        assets: [asset(10, 1, displayName: '恢复')],
      );
      final plan = merge(current, incoming);
      expect(plan.canCommit, isTrue);
      expect(plan.versions.length, 2);
      expect(plan.assets.length, 2);
      expect(plan.versionIds[id(1)], isNot(id(1)));
      expect(plan.assetIds[id(10)], isNot(id(10)));
      expect(plan.versions.first, current.versions.first);
      expect(plan.assets.first.displayName, '原名');
      expect(plan.issues.map((i) => i.scope), [
        BackupMergeScope.version,
        BackupMergeScope.asset,
      ]);
      final replay = merge(fromPlan(plan), incoming);
      expect(replay.versionIds, plan.versionIds);
      expect(replay.assetIds, plan.assetIds);
      expect(replay.versions.length, 2);
      expect(replay.assets.length, 2);
    });

    test('asset identity collision remains distinct even if another current asset shares content', () {
      final current = manifest(
        versions: [
          version(1),
          version(2, hash: 'b'),
        ],
        assets: [asset(10, 1), asset(11, 2)],
      );
      final incoming = manifest(
        versions: [version(3, hash: 'b')],
        assets: [asset(10, 3)],
      );
      final plan = merge(current, incoming);
      final restoredId = plan.assetIds[id(10)]!;
      expect(restoredId, isNot(id(10)));
      expect(restoredId, isNot(id(11)));
      expect(plan.assets.length, 3);
      expect(plan.assets.last.versionId, id(2));
      final replay = merge(fromPlan(plan), incoming);
      expect(replay.assetIds[id(10)], restoredId);
      expect(replay.assets.length, 3);
    });

    test('derived UUID avoids all current and incoming identifiers via stable salt', () {
      final content = '${'b' * 64}:100';
      final blockedCandidate = const Uuid().v5(
        id(901),
        jsonEncode(['imagehost-backup-merge-v1', 'version', id(1), content, 0]),
      );
      final current = manifest(
        versions: [version(1)],
        tags: [BackupName(id: blockedCandidate, name: '保留身份')],
      );
      final incoming = manifest(
        package: 901,
        versions: [version(1, hash: 'b')],
      );
      final plan = merge(current, incoming);
      final expected = const Uuid().v5(
        id(901),
        jsonEncode(['imagehost-backup-merge-v1', 'version', id(1), content, 1]),
      );
      expect(plan.versionIds[id(1)], expected);
      expect(plan.tags.single.id, blockedCandidate);
      expect(merge(fromPlan(plan), incoming).versionIds, plan.versionIds);
    });

    test('directory identity conflicts preserve names and references across replay', () {
      final current = manifest(
        categories: [name(20, '当前分类')],
        tags: [name(30, '当前标签')],
      );
      final incoming = manifest(
        package: 901,
        versions: [version(1)],
        assets: [
          asset(10, 1, category: 20, tags: [30]),
        ],
        categories: [name(20, '来包分类')],
        tags: [name(30, '来包标签')],
      );
      final plan = merge(current, incoming);
      expect(plan.categories.map((n) => n.name), ['当前分类', '来包分类']);
      expect(plan.tags.map((n) => n.name), ['当前标签', '来包标签']);
      expect(plan.categoryIds[id(20)], isNot(id(20)));
      expect(plan.tagIds[id(30)], isNot(id(30)));
      expect(plan.assets.single.categoryId, plan.categoryIds[id(20)]);
      expect(plan.assets.single.tagIds, [plan.tagIds[id(30)]]);
      final replay = merge(fromPlan(plan), incoming);
      expect(replay.categoryIds, plan.categoryIds);
      expect(replay.tagIds, plan.tagIds);
      expect(replay.categories.length, 2);
      expect(replay.tags.length, 2);
    });

    test(
      'directory name identity takes priority over conflicting source ID',
      () {
        final plan = merge(
          manifest(tags: [name(30, '占用'), name(31, 'Straße')]),
          manifest(tags: [name(30, 'STRASSE')]),
        );
        expect(plan.tagIds[id(30)], id(31));
        expect(plan.tags.length, 2);
        expect(plan.tags.first.name, '占用');
        expect(plan.issues.single.kind, BackupMergeIssueKind.identityCollision);
      },
    );

    test('all unused current and incoming directory entries are preserved', () {
      final plan = merge(
        manifest(categories: [name(20, '现有')], tags: [name(30, '现有')]),
        manifest(categories: [name(21, '新')], tags: [name(31, '新')]),
      );
      expect(plan.categories.map((n) => n.id), [id(20), id(21)]);
      expect(plan.tags.map((n) => n.id), [id(30), id(31)]);
    });

    test(
      'orphan permanent versions retained and incoming content reuses them',
      () {
        final current = manifest(
          versions: [
            version(1),
            version(2, hash: 'b'),
          ],
        );
        final plan = merge(
          current,
          manifest(versions: [version(3)], assets: [asset(10, 3)]),
        );
        expect(plan.versions.length, 2);
        expect(plan.versionIds[id(3)], id(1));
        expect(plan.assets.single.versionId, id(1));
      },
    );

    for (final inconsistent in [
      version(2, format: 'JPEG'),
      version(2, width: 11),
      version(2, height: 21),
      version(2, frames: 2),
      version(2, orientation: 8),
    ]) {
      test(
        'same SHA+bytes rejects inconsistent description ${inconsistent.format}/${inconsistent.width}/${inconsistent.height}/${inconsistent.frameCount}/${inconsistent.orientation}',
        () {
          final current = manifest(versions: [version(1)]);
          final plan = merge(
            current,
            manifest(versions: [inconsistent], assets: [asset(10, 2)]),
          );
          expect(plan.canCommit, isFalse);
          expect(plan.versions.single, current.versions.single);
          expect(
            plan.issues.single.kind,
            BackupMergeIssueKind.versionDescriptionConflict,
          );
          expect(plan.issues.single.blocking, isTrue);
        },
      );
    }

    test('same SHA different size is a distinct content version', () {
      final plan = merge(
        manifest(versions: [version(1)]),
        manifest(versions: [version(2, bytes: 101)]),
      );
      expect(plan.versions.length, 2);
      expect(plan.canCommit, isTrue);
    });

    test('all result collections and nested collections are immutable', () {
      final plan = merge(
        manifest(
          versions: [version(1)],
          assets: [asset(10, 1)],
          categories: [name(20, '旧')],
          tags: [name(30, '旧')],
        ),
        manifest(
          versions: [version(1, hash: 'b')],
          assets: [
            asset(10, 1, tags: [30]),
          ],
          tags: [name(30, '新')],
        ),
      );
      expect(() => plan.versions.clear(), throwsUnsupportedError);
      expect(() => plan.assets.clear(), throwsUnsupportedError);
      expect(() => plan.categories.clear(), throwsUnsupportedError);
      expect(() => plan.tags.clear(), throwsUnsupportedError);
      expect(() => plan.versionIds.clear(), throwsUnsupportedError);
      expect(() => plan.assetIds.clear(), throwsUnsupportedError);
      expect(() => plan.categoryIds.clear(), throwsUnsupportedError);
      expect(() => plan.tagIds.clear(), throwsUnsupportedError);
      expect(() => plan.issues.clear(), throwsUnsupportedError);
      expect(() => plan.assets.last.tagIds.clear(), throwsUnsupportedError);
      expect(
        () => plan.issues.first.ruleIds.add('bad'),
        throwsUnsupportedError,
      );
    });
  });
}
