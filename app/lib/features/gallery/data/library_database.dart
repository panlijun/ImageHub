import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:uuid/uuid.dart';

import '../../../core/platform_resource.dart';
import '../../../core/text_policy.dart';

part 'library_database.g.dart';

const librarySchemaVersion = 10;

String _migrationUuid() => const Uuid().v4();

/// Local diagnostic evidence is independent of the entities it describes.
@DataClassName('DiagnosticRow')
class DiagnosticRecords extends Table {
  TextColumn get id => text()();
  IntColumn get occurredUtc => integer()();
  TextColumn get kind => text()();
  TextColumn get level => text()();
  TextColumn get code => text()();
  TextColumn get entityId => text().nullable()();
  TextColumn get batchId => text().nullable()();
  TextColumn get attemptId => text().nullable()();
  TextColumn get payloadJson => text()();
  IntColumn get contentBytes => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Portable provenance is audit data; it cannot reconstruct executable IO.
class RestoredOutputOrigins extends Table {
  TextColumn get outputId => text()();
  TextColumn get versionId => text().references(Versions, #id)();
  TextColumn get snapshotJson => text()();
  @override
  Set<Column> get primaryKey => {outputId};
}

/// Terminal backup history never enters UploadPublications or the scheduler.
class ImportedUploadHistories extends Table {
  TextColumn get id => text()();
  TextColumn get batchId => text()();
  IntColumn get position => integer()();
  TextColumn get snapshotJson => text()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
    {batchId, position},
  ];
}

@DataClassName('RestoreOperationRow')
class RestoreOperations extends Table {
  TextColumn get id => text()();
  TextColumn get phase => text()();
  TextColumn get payloadJson => text()();
  IntColumn get createdUtc => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('UploadBatchRow')
class UploadBatches extends Table {
  TextColumn get id => text()();
  TextColumn get intentId => text().unique()();
  IntColumn get createdUtc => integer()();
  BoolColumn get paused => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('UploadPublicationRow')
class UploadPublications extends Table {
  TextColumn get id => text()();
  TextColumn get batchId => text().references(UploadBatches, #id)();
  TextColumn get processingJobId =>
      text().nullable().references(UploadProcessingJobs, #id)();
  IntColumn get position => integer()();
  TextColumn get inputJson => text()();
  TextColumn get targetJson => text()();
  TextColumn get targetId => text()();
  TextColumn get versionDigest => text()();
  IntColumn get byteCount => integer()();
  TextColumn get policyKey => text()();
  TextColumn get state => text()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  IntColumn get generation => integer().withDefault(const Constant(0))();
  BoolColumn get userPaused => boolean().withDefault(const Constant(false))();
  TextColumn get waitReason => text().nullable()();
  IntColumn get retryDelayMicros => integer().nullable()();
  IntColumn get accumulatedRunningMicros =>
      integer().withDefault(const Constant(0))();
  TextColumn get currentAttemptId => text().nullable()();
  TextColumn get resultId => text().nullable()();
  TextColumn get message => text().nullable()();
  IntColumn get createdUtc => integer()();
  IntColumn get updatedUtc => integer()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
    {batchId, position},
  ];
}

/// A frozen processing dependency shared by one batch and policy.
@DataClassName('UploadProcessingJobRow')
class UploadProcessingJobs extends Table {
  TextColumn get id => text()();
  TextColumn get batchId => text().references(UploadBatches, #id)();
  TextColumn get policyKey => text()();
  TextColumn get requestJson => text()();
  TextColumn get state => text()();
  // Outputs can expire while this ordinary dependency audit is retained.
  TextColumn get outputId => text().nullable()();
  TextColumn get message => text().nullable()();
  IntColumn get createdUtc => integer()();
  IntColumn get updatedUtc => integer()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
    {batchId, policyKey},
  ];
}

class UploadAttempts extends Table {
  TextColumn get id => text()();
  TextColumn get itemId => text().references(UploadPublications, #id)();
  IntColumn get generation => integer()();
  IntColumn get targetGeneration => integer()();
  IntColumn get startedUtc => integer()();
  BoolColumn get requestMayHaveStarted =>
      boolean().withDefault(const Constant(false))();
  IntColumn get endedUtc => integer().nullable()();
  TextColumn get outcome => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
    {itemId, generation},
  ];
}

@DataClassName('RemoteUploadResultRow')
class RemoteUploadResults extends Table {
  TextColumn get id => text()();
  TextColumn get attemptId => text().unique()();
  TextColumn get inputJson => text()();
  TextColumn get targetJson => text()();
  TextColumn get targetId => text()();
  TextColumn get versionDigest => text()();
  IntColumn get byteCount => integer()();
  TextColumn get policyKey => text()();
  TextColumn get remoteId => text()();
  TextColumn get directUrl => text()();
  TextColumn get viewerUrl => text().nullable()();
  IntColumn get confirmedUtc => integer()();
  BoolColumn get late => boolean()();
  TextColumn get secretReference => text().nullable()();
  BoolColumn get managementAvailable =>
      boolean().withDefault(const Constant(false))();
  TextColumn get linkState => text().withDefault(const Constant('recorded'))();
  TextColumn get linkReason => text().nullable()();
  IntColumn get linkCheckedUtc => integer().nullable()();
  IntColumn get lastAccessibleUtc => integer().nullable()();
  IntColumn get probeGeneration => integer().withDefault(const Constant(0))();
  IntColumn get probeHttpStatus => integer().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Contains only ordinary confirmation evidence and an opaque UUID reference.
class UploadResultOperations extends Table {
  TextColumn get id => text()();
  TextColumn get attemptId => text().unique()();
  TextColumn get proposalJson => text()();
  TextColumn get secretReference => text().nullable()();
  IntColumn get createdUtc => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

class UploadEvents extends Table {
  TextColumn get id => text()();
  TextColumn get itemId => text().references(UploadPublications, #id)();
  TextColumn get attemptId => text().nullable()();
  TextColumn get state => text()();
  TextColumn get reason => text()();
  IntColumn get createdUtc => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ProviderTargetRow')
class ProviderTargets extends Table {
  TextColumn get id => text()();
  TextColumn get service => text()();
  TextColumn get alias => text()();
  BoolColumn get enabled => boolean()();
  BoolColumn get selectedByDefault => boolean()();
  BoolColumn get anonymous => boolean()();
  TextColumn get health => text()();
  TextColumn get secretReference => text().nullable()();
  BoolColumn get removed => boolean().withDefault(const Constant(false))();
  IntColumn get generation => integer().withDefault(const Constant(1))();
  IntColumn get createdUtc => integer()();
  IntColumn get modifiedUtc => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

class CredentialOperations extends Table {
  TextColumn get id => text()();
  TextColumn get targetId => text().references(ProviderTargets, #id)();
  TextColumn get action => text()();
  TextColumn get proposalJson => text()();
  TextColumn get newReference => text().nullable()();
  TextColumn get oldReference => text().nullable()();
  IntColumn get createdUtc => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CategoryRow')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get nameKey => text().unique()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TagRow')
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get nameKey => text().unique()();
  @override
  Set<Column> get primaryKey => {id};
}

class AssetTags extends Table {
  TextColumn get assetId => text().references(Assets, #id)();
  TextColumn get tagId => text().references(Tags, #id)();
  IntColumn get position => integer()();
  @override
  Set<Column> get primaryKey => {assetId, tagId};
}

class FileLeases extends Table {
  TextColumn get id => text()();
  TextColumn get versionId => text().references(Versions, #id)();
  TextColumn get ownerId => text()();
  TextColumn get purpose => text()();
  IntColumn get createdUtc => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

class VersionReferences extends Table {
  TextColumn get id => text()();
  TextColumn get versionId => text().references(Versions, #id)();
  TextColumn get ownerType => text()();
  TextColumn get ownerId => text()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
    {versionId, ownerType, ownerId},
  ];
}

class PurgeOperations extends Table {
  TextColumn get id => text()();
  TextColumn get versionId => text().references(Versions, #id)();
  TextColumn get relativePath => text()();
  TextColumn get assetIdsJson => text()();
  BoolColumn get removeRecords => boolean()();
  IntColumn get createdUtc => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

class LibraryMetadata extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

@DataClassName('ProcessedOutputRow')
class ProcessedOutputs extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text()();
  TextColumn get state => text()();
  TextColumn get relativePath => text().unique()();
  TextColumn get requestJson => text()();
  TextColumn get versionJson => text().nullable()();
  TextColumn get warningsJson => text().withDefault(const Constant('[]'))();
  BoolColumn get lossy => boolean().withDefault(const Constant(false))();
  BoolColumn get transparencyRemoved =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get animationRemoved =>
      boolean().withDefault(const Constant(false))();
  IntColumn get createdUtc => integer()();
  IntColumn get expiresUtc => integer()();
  TextColumn get availability =>
      text().withDefault(const Constant('missing'))();
  TextColumn get savedVersionId =>
      text().nullable().references(Versions, #id)();
  TextColumn get failureMessage => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class OutputReferences extends Table {
  TextColumn get id => text()();
  TextColumn get outputId => text().references(ProcessedOutputs, #id)();
  TextColumn get ownerType => text()();
  TextColumn get ownerId => text()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
    {outputId, ownerType, ownerId},
  ];
}

class OutputLeases extends Table {
  TextColumn get id => text()();
  TextColumn get outputId => text().references(ProcessedOutputs, #id)();
  TextColumn get ownerId => text()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Durable provenance survives expiry/deletion of the separate temporary file.
class SavedOutputOrigins extends Table {
  TextColumn get outputId => text()();
  TextColumn get versionId => text().references(Versions, #id)();
  TextColumn get requestJson => text()();
  IntColumn get createdUtc => integer()();
  @override
  Set<Column> get primaryKey => {outputId};
}

@DataClassName('VersionRow')
class Versions extends Table {
  TextColumn get id => text()();
  TextColumn get digest => text()();
  IntColumn get byteCount => integer()();
  TextColumn get format => text()();
  IntColumn get width => integer()();
  IntColumn get height => integer()();
  IntColumn get frameCount => integer()();
  IntColumn get orientation => integer()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
    {digest, byteCount},
  ];
}

@DataClassName('AssetRow')
class Assets extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text()();
  TextColumn get versionId => text().references(Versions, #id)();
  IntColumn get importedUtc => integer()();
  IntColumn get updatedUtc => integer()();
  TextColumn get sourceType => text()();
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();
  TextColumn get category => text().nullable().references(Categories, #id)();
  BoolColumn get recycled => boolean().withDefault(const Constant(false))();
  IntColumn get recycledUtc => integer().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CopyRow')
class DeviceCopies extends Table {
  TextColumn get id => text()();
  TextColumn get versionId => text().references(Versions, #id).unique()();
  TextColumn get relativePath => text().unique()();
  TextColumn get availability =>
      text().withDefault(const Constant('unknown'))();
  IntColumn get verifiedUtc => integer().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('OperationRow')
class ImportOperations extends Table {
  TextColumn get id => text()();
  TextColumn get assetId => text()();
  TextColumn get versionId => text()();
  TextColumn get copyId => text()();
  TextColumn get stagePath => text()();
  TextColumn get finalPath => text()();
  TextColumn get displayName => text()();
  TextColumn get sourceType => text()();
  IntColumn get createdUtc => integer()();
  TextColumn get phase => text()();
  TextColumn get digest => text().nullable()();
  IntColumn get byteCount => integer().nullable()();
  TextColumn get format => text().nullable()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  IntColumn get frameCount => integer().nullable()();
  IntColumn get orientation => integer().nullable()();
  TextColumn get outputId =>
      text().nullable().references(ProcessedOutputs, #id)();
  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    UploadBatches,
    UploadProcessingJobs,
    UploadPublications,
    UploadAttempts,
    RemoteUploadResults,
    UploadResultOperations,
    UploadEvents,
    ProviderTargets,
    CredentialOperations,
    Versions,
    Assets,
    DeviceCopies,
    ImportOperations,
    Categories,
    Tags,
    AssetTags,
    FileLeases,
    VersionReferences,
    PurgeOperations,
    LibraryMetadata,
    ProcessedOutputs,
    OutputReferences,
    OutputLeases,
    SavedOutputOrigins,
    RestoredOutputOrigins,
    ImportedUploadHistories,
    RestoreOperations,
    DiagnosticRecords,
  ],
)
class LibraryDatabase extends _$LibraryDatabase {
  LibraryDatabase(File file)
    : super(
        NativeDatabase.createInBackground(
          file,
          setup: (database) {
            final version =
                database.select('PRAGMA user_version').first.values.first
                    as int;
            if (version > librarySchemaVersion) {
              throw const LibraryOpenException('此图库来自更高版本，请使用兼容版本打开。原数据已保留。');
            }
            if ((version == 6 ||
                    version == 7 ||
                    version == 8 ||
                    version == 9) &&
                database
                        .select('SELECT COUNT(*) FROM restore_operations')
                        .single
                        .values
                        .single !=
                    0) {
              throw const LibraryOpenException('升级前须先用兼容版本完成恢复操作；原数据与恢复证据已保留。');
            }
            final check = database.select('PRAGMA integrity_check');
            if (check.length != 1 || check.first.values.first != 'ok') {
              throw const LibraryOpenException('图库校验失败，请保留数据并修复。');
            }
            if (version == 0 &&
                database
                    .select(
                      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
                    )
                    .isNotEmpty) {
              throw const LibraryOpenException('无法识别此数据库版本，已阻止打开并保留数据。');
            }
            database.execute('PRAGMA foreign_keys=ON');
            database.execute('PRAGMA journal_mode=WAL');
            database.execute('PRAGMA synchronous=FULL');
            // SQLite LOWER only covers ASCII. Use the shared Unicode policy
            // without allowing a stored schema to invoke this pure function.
            database.createFunction(
              functionName: 'imagehost_casefold',
              argumentCount: const sqlite.AllowedArgumentCount(1),
              deterministic: true,
              directOnly: true,
              function: (arguments) =>
                  TextPolicy.key(arguments.single as String),
            );
          },
        ),
      );
  @override
  int get schemaVersion => librarySchemaVersion;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(
        'CREATE INDEX processed_outputs_expiry ON processed_outputs(expires_utc, id)',
      );
      await customStatement(
        'CREATE INDEX assets_import_order ON assets(imported_utc DESC, id ASC)',
      );
      await customStatement(
        'CREATE INDEX asset_tags_by_tag ON asset_tags(tag_id, asset_id)',
      );
      await _createDiagnosticIndexes();
      await into(libraryMetadata).insert(
        LibraryMetadataCompanion.insert(
          key: 'text_policy',
          value: 'unicode-17-nfc-full-cf-v1',
        ),
      );
    },
    onUpgrade: (m, from, to) async {
      if (from < 1 || from > 9 || to != librarySchemaVersion) {
        throw const LibraryOpenException('尚未支持此图库升级，原数据已保留。');
      }
      await transaction(() async {
        if (from >= 2) {
          final policy = await (select(
            libraryMetadata,
          )..where((t) => t.key.equals('text_policy'))).getSingleOrNull();
          if (policy?.value != 'unicode-17-nfc-full-cf-v1') {
            throw const LibraryOpenException('文本规范版本不兼容，已阻止升级并保留原数据。');
          }
        }
        if (from == 1) {
          await m.createTable(categories);
          await m.createTable(tags);
          // Version 1 stored a category display name. Convert only our own format
          // and reject invalid names instead of silently discarding metadata.
          final oldNames = await customSelect(
            'SELECT id, category FROM assets WHERE category IS NOT NULL',
          ).get();
          final keys = <String, String>{};
          for (final row in oldNames) {
            final name = TextPolicy.normalizeName(row.read<String>('category'));
            final key = TextPolicy.key(name);
            var id = keys[key];
            if (id == null) {
              // Stable identity is persisted before rewriting the asset relation.
              id = _migrationUuid();
              keys[key] = id;
              await into(categories).insert(
                CategoriesCompanion.insert(id: id, name: name, nameKey: key),
              );
            }
            await customStatement('UPDATE assets SET category=? WHERE id=?', [
              id,
              row.read<String>('id'),
            ]);
          }
          await m.alterTable(
            TableMigration(assets, newColumns: [assets.recycledUtc]),
          );
          await m.addColumn(deviceCopies, deviceCopies.availability);
          await m.addColumn(deviceCopies, deviceCopies.verifiedUtc);
          await m.createTable(assetTags);
          await m.createTable(fileLeases);
          await m.createTable(versionReferences);
          await m.createTable(purgeOperations);
          await m.createTable(libraryMetadata);
          await customStatement(
            'CREATE INDEX IF NOT EXISTS assets_import_order ON assets(imported_utc DESC, id ASC)',
          );
          await customStatement(
            'CREATE INDEX asset_tags_by_tag ON asset_tags(tag_id, asset_id)',
          );
          await into(libraryMetadata).insert(
            LibraryMetadataCompanion.insert(
              key: 'text_policy',
              value: 'unicode-17-nfc-full-cf-v1',
            ),
          );
        }
        if (from < 3) {
          await m.createTable(processedOutputs);
          await m.createTable(outputReferences);
          await m.createTable(outputLeases);
          await m.createTable(savedOutputOrigins);
          await m.addColumn(importOperations, importOperations.outputId);
          await customStatement(
            'CREATE INDEX processed_outputs_expiry ON processed_outputs(expires_utc, id)',
          );
        }
        if (from < 4) {
          await m.createTable(providerTargets);
          await m.createTable(credentialOperations);
        }
        if (from < 5) {
          await m.createTable(uploadBatches);
          await m.createTable(uploadProcessingJobs);
          await m.createTable(uploadPublications);
          await m.createTable(uploadAttempts);
          await m.createTable(remoteUploadResults);
          await m.createTable(uploadResultOperations);
          await m.createTable(uploadEvents);
        }
        if (from >= 5) {
          await m.createTable(uploadProcessingJobs);
          await m.addColumn(
            uploadPublications,
            uploadPublications.processingJobId,
          );
        }
        if (from >= 5 && from < 9) {
          await m.addColumn(uploadPublications, uploadPublications.userPaused);
        }
        if (from < 6) {
          await m.createTable(restoredOutputOrigins);
          await m.createTable(importedUploadHistories);
          await m.createTable(restoreOperations);
        }
        if (from >= 5 && from < 7) {
          await m.addColumn(remoteUploadResults, remoteUploadResults.linkState);
          await m.addColumn(
            remoteUploadResults,
            remoteUploadResults.linkReason,
          );
          await m.addColumn(
            remoteUploadResults,
            remoteUploadResults.linkCheckedUtc,
          );
          await m.addColumn(
            remoteUploadResults,
            remoteUploadResults.lastAccessibleUtc,
          );
          await m.addColumn(
            remoteUploadResults,
            remoteUploadResults.probeGeneration,
          );
          await m.addColumn(
            remoteUploadResults,
            remoteUploadResults.probeHttpStatus,
          );
        }
        if (from < 8) {
          await m.createTable(diagnosticRecords);
          await _createDiagnosticIndexes();
        }
      });
    },
    beforeOpen: (_) async {
      final policy = await (select(
        libraryMetadata,
      )..where((t) => t.key.equals('text_policy'))).getSingleOrNull();
      if (policy?.value != 'unicode-17-nfc-full-cf-v1') {
        throw const LibraryOpenException('文本规范版本不兼容，已保留数据并阻止写入。');
      }
      for (final pragma in {'foreign_keys': 1, 'synchronous': 2}.entries) {
        final actual = await customSelect('PRAGMA ${pragma.key}').getSingle();
        if (actual.data.values.first != pragma.value) {
          throw const LibraryOpenException('数据库安全配置无法生效，已阻止打开。');
        }
      }
      final mode = await customSelect('PRAGMA journal_mode').getSingle();
      if (mode.data.values.first != 'wal') {
        throw const LibraryOpenException('数据库日志保护无法生效，已阻止打开。');
      }
    },
  );

  Future<void> _createDiagnosticIndexes() async {
    await customStatement(
      'CREATE INDEX diagnostic_records_order ON diagnostic_records(occurred_utc, id)',
    );
    await customStatement(
      'CREATE INDEX diagnostic_records_batch ON diagnostic_records(batch_id, occurred_utc, id)',
    );
    await customStatement(
      'CREATE INDEX diagnostic_records_attempt ON diagnostic_records(attempt_id, occurred_utc, id)',
    );
  }
}
