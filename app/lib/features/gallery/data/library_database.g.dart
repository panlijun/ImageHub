// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_database.dart';

// ignore_for_file: type=lint
class $UploadBatchesTable extends UploadBatches
    with TableInfo<$UploadBatchesTable, UploadBatchRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UploadBatchesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _intentIdMeta = const VerificationMeta(
    'intentId',
  );
  @override
  late final GeneratedColumn<String> intentId = GeneratedColumn<String>(
    'intent_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _createdUtcMeta = const VerificationMeta(
    'createdUtc',
  );
  @override
  late final GeneratedColumn<int> createdUtc = GeneratedColumn<int>(
    'created_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pausedMeta = const VerificationMeta('paused');
  @override
  late final GeneratedColumn<bool> paused = GeneratedColumn<bool>(
    'paused',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("paused" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [id, intentId, createdUtc, paused];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'upload_batches';
  @override
  VerificationContext validateIntegrity(
    Insertable<UploadBatchRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('intent_id')) {
      context.handle(
        _intentIdMeta,
        intentId.isAcceptableOrUnknown(data['intent_id']!, _intentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_intentIdMeta);
    }
    if (data.containsKey('created_utc')) {
      context.handle(
        _createdUtcMeta,
        createdUtc.isAcceptableOrUnknown(data['created_utc']!, _createdUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_createdUtcMeta);
    }
    if (data.containsKey('paused')) {
      context.handle(
        _pausedMeta,
        paused.isAcceptableOrUnknown(data['paused']!, _pausedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UploadBatchRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UploadBatchRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      intentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intent_id'],
      )!,
      createdUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_utc'],
      )!,
      paused: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}paused'],
      )!,
    );
  }

  @override
  $UploadBatchesTable createAlias(String alias) {
    return $UploadBatchesTable(attachedDatabase, alias);
  }
}

class UploadBatchRow extends DataClass implements Insertable<UploadBatchRow> {
  final String id;
  final String intentId;
  final int createdUtc;
  final bool paused;
  const UploadBatchRow({
    required this.id,
    required this.intentId,
    required this.createdUtc,
    required this.paused,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['intent_id'] = Variable<String>(intentId);
    map['created_utc'] = Variable<int>(createdUtc);
    map['paused'] = Variable<bool>(paused);
    return map;
  }

  UploadBatchesCompanion toCompanion(bool nullToAbsent) {
    return UploadBatchesCompanion(
      id: Value(id),
      intentId: Value(intentId),
      createdUtc: Value(createdUtc),
      paused: Value(paused),
    );
  }

  factory UploadBatchRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UploadBatchRow(
      id: serializer.fromJson<String>(json['id']),
      intentId: serializer.fromJson<String>(json['intentId']),
      createdUtc: serializer.fromJson<int>(json['createdUtc']),
      paused: serializer.fromJson<bool>(json['paused']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'intentId': serializer.toJson<String>(intentId),
      'createdUtc': serializer.toJson<int>(createdUtc),
      'paused': serializer.toJson<bool>(paused),
    };
  }

  UploadBatchRow copyWith({
    String? id,
    String? intentId,
    int? createdUtc,
    bool? paused,
  }) => UploadBatchRow(
    id: id ?? this.id,
    intentId: intentId ?? this.intentId,
    createdUtc: createdUtc ?? this.createdUtc,
    paused: paused ?? this.paused,
  );
  UploadBatchRow copyWithCompanion(UploadBatchesCompanion data) {
    return UploadBatchRow(
      id: data.id.present ? data.id.value : this.id,
      intentId: data.intentId.present ? data.intentId.value : this.intentId,
      createdUtc: data.createdUtc.present
          ? data.createdUtc.value
          : this.createdUtc,
      paused: data.paused.present ? data.paused.value : this.paused,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UploadBatchRow(')
          ..write('id: $id, ')
          ..write('intentId: $intentId, ')
          ..write('createdUtc: $createdUtc, ')
          ..write('paused: $paused')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, intentId, createdUtc, paused);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UploadBatchRow &&
          other.id == this.id &&
          other.intentId == this.intentId &&
          other.createdUtc == this.createdUtc &&
          other.paused == this.paused);
}

class UploadBatchesCompanion extends UpdateCompanion<UploadBatchRow> {
  final Value<String> id;
  final Value<String> intentId;
  final Value<int> createdUtc;
  final Value<bool> paused;
  final Value<int> rowid;
  const UploadBatchesCompanion({
    this.id = const Value.absent(),
    this.intentId = const Value.absent(),
    this.createdUtc = const Value.absent(),
    this.paused = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UploadBatchesCompanion.insert({
    required String id,
    required String intentId,
    required int createdUtc,
    this.paused = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       intentId = Value(intentId),
       createdUtc = Value(createdUtc);
  static Insertable<UploadBatchRow> custom({
    Expression<String>? id,
    Expression<String>? intentId,
    Expression<int>? createdUtc,
    Expression<bool>? paused,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (intentId != null) 'intent_id': intentId,
      if (createdUtc != null) 'created_utc': createdUtc,
      if (paused != null) 'paused': paused,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UploadBatchesCompanion copyWith({
    Value<String>? id,
    Value<String>? intentId,
    Value<int>? createdUtc,
    Value<bool>? paused,
    Value<int>? rowid,
  }) {
    return UploadBatchesCompanion(
      id: id ?? this.id,
      intentId: intentId ?? this.intentId,
      createdUtc: createdUtc ?? this.createdUtc,
      paused: paused ?? this.paused,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (intentId.present) {
      map['intent_id'] = Variable<String>(intentId.value);
    }
    if (createdUtc.present) {
      map['created_utc'] = Variable<int>(createdUtc.value);
    }
    if (paused.present) {
      map['paused'] = Variable<bool>(paused.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UploadBatchesCompanion(')
          ..write('id: $id, ')
          ..write('intentId: $intentId, ')
          ..write('createdUtc: $createdUtc, ')
          ..write('paused: $paused, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UploadProcessingJobsTable extends UploadProcessingJobs
    with TableInfo<$UploadProcessingJobsTable, UploadProcessingJobRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UploadProcessingJobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES upload_batches (id)',
    ),
  );
  static const VerificationMeta _policyKeyMeta = const VerificationMeta(
    'policyKey',
  );
  @override
  late final GeneratedColumn<String> policyKey = GeneratedColumn<String>(
    'policy_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _requestJsonMeta = const VerificationMeta(
    'requestJson',
  );
  @override
  late final GeneratedColumn<String> requestJson = GeneratedColumn<String>(
    'request_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _outputIdMeta = const VerificationMeta(
    'outputId',
  );
  @override
  late final GeneratedColumn<String> outputId = GeneratedColumn<String>(
    'output_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
    'message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdUtcMeta = const VerificationMeta(
    'createdUtc',
  );
  @override
  late final GeneratedColumn<int> createdUtc = GeneratedColumn<int>(
    'created_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedUtcMeta = const VerificationMeta(
    'updatedUtc',
  );
  @override
  late final GeneratedColumn<int> updatedUtc = GeneratedColumn<int>(
    'updated_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    batchId,
    policyKey,
    requestJson,
    state,
    outputId,
    message,
    createdUtc,
    updatedUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'upload_processing_jobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<UploadProcessingJobRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_batchIdMeta);
    }
    if (data.containsKey('policy_key')) {
      context.handle(
        _policyKeyMeta,
        policyKey.isAcceptableOrUnknown(data['policy_key']!, _policyKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_policyKeyMeta);
    }
    if (data.containsKey('request_json')) {
      context.handle(
        _requestJsonMeta,
        requestJson.isAcceptableOrUnknown(
          data['request_json']!,
          _requestJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_requestJsonMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('output_id')) {
      context.handle(
        _outputIdMeta,
        outputId.isAcceptableOrUnknown(data['output_id']!, _outputIdMeta),
      );
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    }
    if (data.containsKey('created_utc')) {
      context.handle(
        _createdUtcMeta,
        createdUtc.isAcceptableOrUnknown(data['created_utc']!, _createdUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_createdUtcMeta);
    }
    if (data.containsKey('updated_utc')) {
      context.handle(
        _updatedUtcMeta,
        updatedUtc.isAcceptableOrUnknown(data['updated_utc']!, _updatedUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {batchId, policyKey},
  ];
  @override
  UploadProcessingJobRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UploadProcessingJobRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      )!,
      policyKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}policy_key'],
      )!,
      requestJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_json'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      outputId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}output_id'],
      ),
      message: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message'],
      ),
      createdUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_utc'],
      )!,
      updatedUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_utc'],
      )!,
    );
  }

  @override
  $UploadProcessingJobsTable createAlias(String alias) {
    return $UploadProcessingJobsTable(attachedDatabase, alias);
  }
}

class UploadProcessingJobRow extends DataClass
    implements Insertable<UploadProcessingJobRow> {
  final String id;
  final String batchId;
  final String policyKey;
  final String requestJson;
  final String state;
  final String? outputId;
  final String? message;
  final int createdUtc;
  final int updatedUtc;
  const UploadProcessingJobRow({
    required this.id,
    required this.batchId,
    required this.policyKey,
    required this.requestJson,
    required this.state,
    this.outputId,
    this.message,
    required this.createdUtc,
    required this.updatedUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['batch_id'] = Variable<String>(batchId);
    map['policy_key'] = Variable<String>(policyKey);
    map['request_json'] = Variable<String>(requestJson);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || outputId != null) {
      map['output_id'] = Variable<String>(outputId);
    }
    if (!nullToAbsent || message != null) {
      map['message'] = Variable<String>(message);
    }
    map['created_utc'] = Variable<int>(createdUtc);
    map['updated_utc'] = Variable<int>(updatedUtc);
    return map;
  }

  UploadProcessingJobsCompanion toCompanion(bool nullToAbsent) {
    return UploadProcessingJobsCompanion(
      id: Value(id),
      batchId: Value(batchId),
      policyKey: Value(policyKey),
      requestJson: Value(requestJson),
      state: Value(state),
      outputId: outputId == null && nullToAbsent
          ? const Value.absent()
          : Value(outputId),
      message: message == null && nullToAbsent
          ? const Value.absent()
          : Value(message),
      createdUtc: Value(createdUtc),
      updatedUtc: Value(updatedUtc),
    );
  }

  factory UploadProcessingJobRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UploadProcessingJobRow(
      id: serializer.fromJson<String>(json['id']),
      batchId: serializer.fromJson<String>(json['batchId']),
      policyKey: serializer.fromJson<String>(json['policyKey']),
      requestJson: serializer.fromJson<String>(json['requestJson']),
      state: serializer.fromJson<String>(json['state']),
      outputId: serializer.fromJson<String?>(json['outputId']),
      message: serializer.fromJson<String?>(json['message']),
      createdUtc: serializer.fromJson<int>(json['createdUtc']),
      updatedUtc: serializer.fromJson<int>(json['updatedUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'batchId': serializer.toJson<String>(batchId),
      'policyKey': serializer.toJson<String>(policyKey),
      'requestJson': serializer.toJson<String>(requestJson),
      'state': serializer.toJson<String>(state),
      'outputId': serializer.toJson<String?>(outputId),
      'message': serializer.toJson<String?>(message),
      'createdUtc': serializer.toJson<int>(createdUtc),
      'updatedUtc': serializer.toJson<int>(updatedUtc),
    };
  }

  UploadProcessingJobRow copyWith({
    String? id,
    String? batchId,
    String? policyKey,
    String? requestJson,
    String? state,
    Value<String?> outputId = const Value.absent(),
    Value<String?> message = const Value.absent(),
    int? createdUtc,
    int? updatedUtc,
  }) => UploadProcessingJobRow(
    id: id ?? this.id,
    batchId: batchId ?? this.batchId,
    policyKey: policyKey ?? this.policyKey,
    requestJson: requestJson ?? this.requestJson,
    state: state ?? this.state,
    outputId: outputId.present ? outputId.value : this.outputId,
    message: message.present ? message.value : this.message,
    createdUtc: createdUtc ?? this.createdUtc,
    updatedUtc: updatedUtc ?? this.updatedUtc,
  );
  UploadProcessingJobRow copyWithCompanion(UploadProcessingJobsCompanion data) {
    return UploadProcessingJobRow(
      id: data.id.present ? data.id.value : this.id,
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
      policyKey: data.policyKey.present ? data.policyKey.value : this.policyKey,
      requestJson: data.requestJson.present
          ? data.requestJson.value
          : this.requestJson,
      state: data.state.present ? data.state.value : this.state,
      outputId: data.outputId.present ? data.outputId.value : this.outputId,
      message: data.message.present ? data.message.value : this.message,
      createdUtc: data.createdUtc.present
          ? data.createdUtc.value
          : this.createdUtc,
      updatedUtc: data.updatedUtc.present
          ? data.updatedUtc.value
          : this.updatedUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UploadProcessingJobRow(')
          ..write('id: $id, ')
          ..write('batchId: $batchId, ')
          ..write('policyKey: $policyKey, ')
          ..write('requestJson: $requestJson, ')
          ..write('state: $state, ')
          ..write('outputId: $outputId, ')
          ..write('message: $message, ')
          ..write('createdUtc: $createdUtc, ')
          ..write('updatedUtc: $updatedUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    batchId,
    policyKey,
    requestJson,
    state,
    outputId,
    message,
    createdUtc,
    updatedUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UploadProcessingJobRow &&
          other.id == this.id &&
          other.batchId == this.batchId &&
          other.policyKey == this.policyKey &&
          other.requestJson == this.requestJson &&
          other.state == this.state &&
          other.outputId == this.outputId &&
          other.message == this.message &&
          other.createdUtc == this.createdUtc &&
          other.updatedUtc == this.updatedUtc);
}

class UploadProcessingJobsCompanion
    extends UpdateCompanion<UploadProcessingJobRow> {
  final Value<String> id;
  final Value<String> batchId;
  final Value<String> policyKey;
  final Value<String> requestJson;
  final Value<String> state;
  final Value<String?> outputId;
  final Value<String?> message;
  final Value<int> createdUtc;
  final Value<int> updatedUtc;
  final Value<int> rowid;
  const UploadProcessingJobsCompanion({
    this.id = const Value.absent(),
    this.batchId = const Value.absent(),
    this.policyKey = const Value.absent(),
    this.requestJson = const Value.absent(),
    this.state = const Value.absent(),
    this.outputId = const Value.absent(),
    this.message = const Value.absent(),
    this.createdUtc = const Value.absent(),
    this.updatedUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UploadProcessingJobsCompanion.insert({
    required String id,
    required String batchId,
    required String policyKey,
    required String requestJson,
    required String state,
    this.outputId = const Value.absent(),
    this.message = const Value.absent(),
    required int createdUtc,
    required int updatedUtc,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       batchId = Value(batchId),
       policyKey = Value(policyKey),
       requestJson = Value(requestJson),
       state = Value(state),
       createdUtc = Value(createdUtc),
       updatedUtc = Value(updatedUtc);
  static Insertable<UploadProcessingJobRow> custom({
    Expression<String>? id,
    Expression<String>? batchId,
    Expression<String>? policyKey,
    Expression<String>? requestJson,
    Expression<String>? state,
    Expression<String>? outputId,
    Expression<String>? message,
    Expression<int>? createdUtc,
    Expression<int>? updatedUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (batchId != null) 'batch_id': batchId,
      if (policyKey != null) 'policy_key': policyKey,
      if (requestJson != null) 'request_json': requestJson,
      if (state != null) 'state': state,
      if (outputId != null) 'output_id': outputId,
      if (message != null) 'message': message,
      if (createdUtc != null) 'created_utc': createdUtc,
      if (updatedUtc != null) 'updated_utc': updatedUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UploadProcessingJobsCompanion copyWith({
    Value<String>? id,
    Value<String>? batchId,
    Value<String>? policyKey,
    Value<String>? requestJson,
    Value<String>? state,
    Value<String?>? outputId,
    Value<String?>? message,
    Value<int>? createdUtc,
    Value<int>? updatedUtc,
    Value<int>? rowid,
  }) {
    return UploadProcessingJobsCompanion(
      id: id ?? this.id,
      batchId: batchId ?? this.batchId,
      policyKey: policyKey ?? this.policyKey,
      requestJson: requestJson ?? this.requestJson,
      state: state ?? this.state,
      outputId: outputId ?? this.outputId,
      message: message ?? this.message,
      createdUtc: createdUtc ?? this.createdUtc,
      updatedUtc: updatedUtc ?? this.updatedUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (policyKey.present) {
      map['policy_key'] = Variable<String>(policyKey.value);
    }
    if (requestJson.present) {
      map['request_json'] = Variable<String>(requestJson.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (outputId.present) {
      map['output_id'] = Variable<String>(outputId.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (createdUtc.present) {
      map['created_utc'] = Variable<int>(createdUtc.value);
    }
    if (updatedUtc.present) {
      map['updated_utc'] = Variable<int>(updatedUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UploadProcessingJobsCompanion(')
          ..write('id: $id, ')
          ..write('batchId: $batchId, ')
          ..write('policyKey: $policyKey, ')
          ..write('requestJson: $requestJson, ')
          ..write('state: $state, ')
          ..write('outputId: $outputId, ')
          ..write('message: $message, ')
          ..write('createdUtc: $createdUtc, ')
          ..write('updatedUtc: $updatedUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UploadPublicationsTable extends UploadPublications
    with TableInfo<$UploadPublicationsTable, UploadPublicationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UploadPublicationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES upload_batches (id)',
    ),
  );
  static const VerificationMeta _processingJobIdMeta = const VerificationMeta(
    'processingJobId',
  );
  @override
  late final GeneratedColumn<String> processingJobId = GeneratedColumn<String>(
    'processing_job_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES upload_processing_jobs (id)',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inputJsonMeta = const VerificationMeta(
    'inputJson',
  );
  @override
  late final GeneratedColumn<String> inputJson = GeneratedColumn<String>(
    'input_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetJsonMeta = const VerificationMeta(
    'targetJson',
  );
  @override
  late final GeneratedColumn<String> targetJson = GeneratedColumn<String>(
    'target_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionDigestMeta = const VerificationMeta(
    'versionDigest',
  );
  @override
  late final GeneratedColumn<String> versionDigest = GeneratedColumn<String>(
    'version_digest',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _byteCountMeta = const VerificationMeta(
    'byteCount',
  );
  @override
  late final GeneratedColumn<int> byteCount = GeneratedColumn<int>(
    'byte_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _policyKeyMeta = const VerificationMeta(
    'policyKey',
  );
  @override
  late final GeneratedColumn<String> policyKey = GeneratedColumn<String>(
    'policy_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _generationMeta = const VerificationMeta(
    'generation',
  );
  @override
  late final GeneratedColumn<int> generation = GeneratedColumn<int>(
    'generation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _userPausedMeta = const VerificationMeta(
    'userPaused',
  );
  @override
  late final GeneratedColumn<bool> userPaused = GeneratedColumn<bool>(
    'user_paused',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("user_paused" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _waitReasonMeta = const VerificationMeta(
    'waitReason',
  );
  @override
  late final GeneratedColumn<String> waitReason = GeneratedColumn<String>(
    'wait_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _retryDelayMicrosMeta = const VerificationMeta(
    'retryDelayMicros',
  );
  @override
  late final GeneratedColumn<int> retryDelayMicros = GeneratedColumn<int>(
    'retry_delay_micros',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _accumulatedRunningMicrosMeta =
      const VerificationMeta('accumulatedRunningMicros');
  @override
  late final GeneratedColumn<int> accumulatedRunningMicros =
      GeneratedColumn<int>(
        'accumulated_running_micros',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
      );
  static const VerificationMeta _currentAttemptIdMeta = const VerificationMeta(
    'currentAttemptId',
  );
  @override
  late final GeneratedColumn<String> currentAttemptId = GeneratedColumn<String>(
    'current_attempt_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resultIdMeta = const VerificationMeta(
    'resultId',
  );
  @override
  late final GeneratedColumn<String> resultId = GeneratedColumn<String>(
    'result_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
    'message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdUtcMeta = const VerificationMeta(
    'createdUtc',
  );
  @override
  late final GeneratedColumn<int> createdUtc = GeneratedColumn<int>(
    'created_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedUtcMeta = const VerificationMeta(
    'updatedUtc',
  );
  @override
  late final GeneratedColumn<int> updatedUtc = GeneratedColumn<int>(
    'updated_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    batchId,
    processingJobId,
    position,
    inputJson,
    targetJson,
    targetId,
    versionDigest,
    byteCount,
    policyKey,
    state,
    attemptCount,
    generation,
    userPaused,
    waitReason,
    retryDelayMicros,
    accumulatedRunningMicros,
    currentAttemptId,
    resultId,
    message,
    createdUtc,
    updatedUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'upload_publications';
  @override
  VerificationContext validateIntegrity(
    Insertable<UploadPublicationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_batchIdMeta);
    }
    if (data.containsKey('processing_job_id')) {
      context.handle(
        _processingJobIdMeta,
        processingJobId.isAcceptableOrUnknown(
          data['processing_job_id']!,
          _processingJobIdMeta,
        ),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('input_json')) {
      context.handle(
        _inputJsonMeta,
        inputJson.isAcceptableOrUnknown(data['input_json']!, _inputJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_inputJsonMeta);
    }
    if (data.containsKey('target_json')) {
      context.handle(
        _targetJsonMeta,
        targetJson.isAcceptableOrUnknown(data['target_json']!, _targetJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_targetJsonMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_targetIdMeta);
    }
    if (data.containsKey('version_digest')) {
      context.handle(
        _versionDigestMeta,
        versionDigest.isAcceptableOrUnknown(
          data['version_digest']!,
          _versionDigestMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_versionDigestMeta);
    }
    if (data.containsKey('byte_count')) {
      context.handle(
        _byteCountMeta,
        byteCount.isAcceptableOrUnknown(data['byte_count']!, _byteCountMeta),
      );
    } else if (isInserting) {
      context.missing(_byteCountMeta);
    }
    if (data.containsKey('policy_key')) {
      context.handle(
        _policyKeyMeta,
        policyKey.isAcceptableOrUnknown(data['policy_key']!, _policyKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_policyKeyMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('generation')) {
      context.handle(
        _generationMeta,
        generation.isAcceptableOrUnknown(data['generation']!, _generationMeta),
      );
    }
    if (data.containsKey('user_paused')) {
      context.handle(
        _userPausedMeta,
        userPaused.isAcceptableOrUnknown(data['user_paused']!, _userPausedMeta),
      );
    }
    if (data.containsKey('wait_reason')) {
      context.handle(
        _waitReasonMeta,
        waitReason.isAcceptableOrUnknown(data['wait_reason']!, _waitReasonMeta),
      );
    }
    if (data.containsKey('retry_delay_micros')) {
      context.handle(
        _retryDelayMicrosMeta,
        retryDelayMicros.isAcceptableOrUnknown(
          data['retry_delay_micros']!,
          _retryDelayMicrosMeta,
        ),
      );
    }
    if (data.containsKey('accumulated_running_micros')) {
      context.handle(
        _accumulatedRunningMicrosMeta,
        accumulatedRunningMicros.isAcceptableOrUnknown(
          data['accumulated_running_micros']!,
          _accumulatedRunningMicrosMeta,
        ),
      );
    }
    if (data.containsKey('current_attempt_id')) {
      context.handle(
        _currentAttemptIdMeta,
        currentAttemptId.isAcceptableOrUnknown(
          data['current_attempt_id']!,
          _currentAttemptIdMeta,
        ),
      );
    }
    if (data.containsKey('result_id')) {
      context.handle(
        _resultIdMeta,
        resultId.isAcceptableOrUnknown(data['result_id']!, _resultIdMeta),
      );
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    }
    if (data.containsKey('created_utc')) {
      context.handle(
        _createdUtcMeta,
        createdUtc.isAcceptableOrUnknown(data['created_utc']!, _createdUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_createdUtcMeta);
    }
    if (data.containsKey('updated_utc')) {
      context.handle(
        _updatedUtcMeta,
        updatedUtc.isAcceptableOrUnknown(data['updated_utc']!, _updatedUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {batchId, position},
  ];
  @override
  UploadPublicationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UploadPublicationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      )!,
      processingJobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}processing_job_id'],
      ),
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      inputJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}input_json'],
      )!,
      targetJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_json'],
      )!,
      targetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_id'],
      )!,
      versionDigest: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version_digest'],
      )!,
      byteCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_count'],
      )!,
      policyKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}policy_key'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      generation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}generation'],
      )!,
      userPaused: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}user_paused'],
      )!,
      waitReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wait_reason'],
      ),
      retryDelayMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_delay_micros'],
      ),
      accumulatedRunningMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}accumulated_running_micros'],
      )!,
      currentAttemptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_attempt_id'],
      ),
      resultId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}result_id'],
      ),
      message: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message'],
      ),
      createdUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_utc'],
      )!,
      updatedUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_utc'],
      )!,
    );
  }

  @override
  $UploadPublicationsTable createAlias(String alias) {
    return $UploadPublicationsTable(attachedDatabase, alias);
  }
}

class UploadPublicationRow extends DataClass
    implements Insertable<UploadPublicationRow> {
  final String id;
  final String batchId;
  final String? processingJobId;
  final int position;
  final String inputJson;
  final String targetJson;
  final String targetId;
  final String versionDigest;
  final int byteCount;
  final String policyKey;
  final String state;
  final int attemptCount;
  final int generation;
  final bool userPaused;
  final String? waitReason;
  final int? retryDelayMicros;
  final int accumulatedRunningMicros;
  final String? currentAttemptId;
  final String? resultId;
  final String? message;
  final int createdUtc;
  final int updatedUtc;
  const UploadPublicationRow({
    required this.id,
    required this.batchId,
    this.processingJobId,
    required this.position,
    required this.inputJson,
    required this.targetJson,
    required this.targetId,
    required this.versionDigest,
    required this.byteCount,
    required this.policyKey,
    required this.state,
    required this.attemptCount,
    required this.generation,
    required this.userPaused,
    this.waitReason,
    this.retryDelayMicros,
    required this.accumulatedRunningMicros,
    this.currentAttemptId,
    this.resultId,
    this.message,
    required this.createdUtc,
    required this.updatedUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['batch_id'] = Variable<String>(batchId);
    if (!nullToAbsent || processingJobId != null) {
      map['processing_job_id'] = Variable<String>(processingJobId);
    }
    map['position'] = Variable<int>(position);
    map['input_json'] = Variable<String>(inputJson);
    map['target_json'] = Variable<String>(targetJson);
    map['target_id'] = Variable<String>(targetId);
    map['version_digest'] = Variable<String>(versionDigest);
    map['byte_count'] = Variable<int>(byteCount);
    map['policy_key'] = Variable<String>(policyKey);
    map['state'] = Variable<String>(state);
    map['attempt_count'] = Variable<int>(attemptCount);
    map['generation'] = Variable<int>(generation);
    map['user_paused'] = Variable<bool>(userPaused);
    if (!nullToAbsent || waitReason != null) {
      map['wait_reason'] = Variable<String>(waitReason);
    }
    if (!nullToAbsent || retryDelayMicros != null) {
      map['retry_delay_micros'] = Variable<int>(retryDelayMicros);
    }
    map['accumulated_running_micros'] = Variable<int>(accumulatedRunningMicros);
    if (!nullToAbsent || currentAttemptId != null) {
      map['current_attempt_id'] = Variable<String>(currentAttemptId);
    }
    if (!nullToAbsent || resultId != null) {
      map['result_id'] = Variable<String>(resultId);
    }
    if (!nullToAbsent || message != null) {
      map['message'] = Variable<String>(message);
    }
    map['created_utc'] = Variable<int>(createdUtc);
    map['updated_utc'] = Variable<int>(updatedUtc);
    return map;
  }

  UploadPublicationsCompanion toCompanion(bool nullToAbsent) {
    return UploadPublicationsCompanion(
      id: Value(id),
      batchId: Value(batchId),
      processingJobId: processingJobId == null && nullToAbsent
          ? const Value.absent()
          : Value(processingJobId),
      position: Value(position),
      inputJson: Value(inputJson),
      targetJson: Value(targetJson),
      targetId: Value(targetId),
      versionDigest: Value(versionDigest),
      byteCount: Value(byteCount),
      policyKey: Value(policyKey),
      state: Value(state),
      attemptCount: Value(attemptCount),
      generation: Value(generation),
      userPaused: Value(userPaused),
      waitReason: waitReason == null && nullToAbsent
          ? const Value.absent()
          : Value(waitReason),
      retryDelayMicros: retryDelayMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(retryDelayMicros),
      accumulatedRunningMicros: Value(accumulatedRunningMicros),
      currentAttemptId: currentAttemptId == null && nullToAbsent
          ? const Value.absent()
          : Value(currentAttemptId),
      resultId: resultId == null && nullToAbsent
          ? const Value.absent()
          : Value(resultId),
      message: message == null && nullToAbsent
          ? const Value.absent()
          : Value(message),
      createdUtc: Value(createdUtc),
      updatedUtc: Value(updatedUtc),
    );
  }

  factory UploadPublicationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UploadPublicationRow(
      id: serializer.fromJson<String>(json['id']),
      batchId: serializer.fromJson<String>(json['batchId']),
      processingJobId: serializer.fromJson<String?>(json['processingJobId']),
      position: serializer.fromJson<int>(json['position']),
      inputJson: serializer.fromJson<String>(json['inputJson']),
      targetJson: serializer.fromJson<String>(json['targetJson']),
      targetId: serializer.fromJson<String>(json['targetId']),
      versionDigest: serializer.fromJson<String>(json['versionDigest']),
      byteCount: serializer.fromJson<int>(json['byteCount']),
      policyKey: serializer.fromJson<String>(json['policyKey']),
      state: serializer.fromJson<String>(json['state']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      generation: serializer.fromJson<int>(json['generation']),
      userPaused: serializer.fromJson<bool>(json['userPaused']),
      waitReason: serializer.fromJson<String?>(json['waitReason']),
      retryDelayMicros: serializer.fromJson<int?>(json['retryDelayMicros']),
      accumulatedRunningMicros: serializer.fromJson<int>(
        json['accumulatedRunningMicros'],
      ),
      currentAttemptId: serializer.fromJson<String?>(json['currentAttemptId']),
      resultId: serializer.fromJson<String?>(json['resultId']),
      message: serializer.fromJson<String?>(json['message']),
      createdUtc: serializer.fromJson<int>(json['createdUtc']),
      updatedUtc: serializer.fromJson<int>(json['updatedUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'batchId': serializer.toJson<String>(batchId),
      'processingJobId': serializer.toJson<String?>(processingJobId),
      'position': serializer.toJson<int>(position),
      'inputJson': serializer.toJson<String>(inputJson),
      'targetJson': serializer.toJson<String>(targetJson),
      'targetId': serializer.toJson<String>(targetId),
      'versionDigest': serializer.toJson<String>(versionDigest),
      'byteCount': serializer.toJson<int>(byteCount),
      'policyKey': serializer.toJson<String>(policyKey),
      'state': serializer.toJson<String>(state),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'generation': serializer.toJson<int>(generation),
      'userPaused': serializer.toJson<bool>(userPaused),
      'waitReason': serializer.toJson<String?>(waitReason),
      'retryDelayMicros': serializer.toJson<int?>(retryDelayMicros),
      'accumulatedRunningMicros': serializer.toJson<int>(
        accumulatedRunningMicros,
      ),
      'currentAttemptId': serializer.toJson<String?>(currentAttemptId),
      'resultId': serializer.toJson<String?>(resultId),
      'message': serializer.toJson<String?>(message),
      'createdUtc': serializer.toJson<int>(createdUtc),
      'updatedUtc': serializer.toJson<int>(updatedUtc),
    };
  }

  UploadPublicationRow copyWith({
    String? id,
    String? batchId,
    Value<String?> processingJobId = const Value.absent(),
    int? position,
    String? inputJson,
    String? targetJson,
    String? targetId,
    String? versionDigest,
    int? byteCount,
    String? policyKey,
    String? state,
    int? attemptCount,
    int? generation,
    bool? userPaused,
    Value<String?> waitReason = const Value.absent(),
    Value<int?> retryDelayMicros = const Value.absent(),
    int? accumulatedRunningMicros,
    Value<String?> currentAttemptId = const Value.absent(),
    Value<String?> resultId = const Value.absent(),
    Value<String?> message = const Value.absent(),
    int? createdUtc,
    int? updatedUtc,
  }) => UploadPublicationRow(
    id: id ?? this.id,
    batchId: batchId ?? this.batchId,
    processingJobId: processingJobId.present
        ? processingJobId.value
        : this.processingJobId,
    position: position ?? this.position,
    inputJson: inputJson ?? this.inputJson,
    targetJson: targetJson ?? this.targetJson,
    targetId: targetId ?? this.targetId,
    versionDigest: versionDigest ?? this.versionDigest,
    byteCount: byteCount ?? this.byteCount,
    policyKey: policyKey ?? this.policyKey,
    state: state ?? this.state,
    attemptCount: attemptCount ?? this.attemptCount,
    generation: generation ?? this.generation,
    userPaused: userPaused ?? this.userPaused,
    waitReason: waitReason.present ? waitReason.value : this.waitReason,
    retryDelayMicros: retryDelayMicros.present
        ? retryDelayMicros.value
        : this.retryDelayMicros,
    accumulatedRunningMicros:
        accumulatedRunningMicros ?? this.accumulatedRunningMicros,
    currentAttemptId: currentAttemptId.present
        ? currentAttemptId.value
        : this.currentAttemptId,
    resultId: resultId.present ? resultId.value : this.resultId,
    message: message.present ? message.value : this.message,
    createdUtc: createdUtc ?? this.createdUtc,
    updatedUtc: updatedUtc ?? this.updatedUtc,
  );
  UploadPublicationRow copyWithCompanion(UploadPublicationsCompanion data) {
    return UploadPublicationRow(
      id: data.id.present ? data.id.value : this.id,
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
      processingJobId: data.processingJobId.present
          ? data.processingJobId.value
          : this.processingJobId,
      position: data.position.present ? data.position.value : this.position,
      inputJson: data.inputJson.present ? data.inputJson.value : this.inputJson,
      targetJson: data.targetJson.present
          ? data.targetJson.value
          : this.targetJson,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      versionDigest: data.versionDigest.present
          ? data.versionDigest.value
          : this.versionDigest,
      byteCount: data.byteCount.present ? data.byteCount.value : this.byteCount,
      policyKey: data.policyKey.present ? data.policyKey.value : this.policyKey,
      state: data.state.present ? data.state.value : this.state,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      generation: data.generation.present
          ? data.generation.value
          : this.generation,
      userPaused: data.userPaused.present
          ? data.userPaused.value
          : this.userPaused,
      waitReason: data.waitReason.present
          ? data.waitReason.value
          : this.waitReason,
      retryDelayMicros: data.retryDelayMicros.present
          ? data.retryDelayMicros.value
          : this.retryDelayMicros,
      accumulatedRunningMicros: data.accumulatedRunningMicros.present
          ? data.accumulatedRunningMicros.value
          : this.accumulatedRunningMicros,
      currentAttemptId: data.currentAttemptId.present
          ? data.currentAttemptId.value
          : this.currentAttemptId,
      resultId: data.resultId.present ? data.resultId.value : this.resultId,
      message: data.message.present ? data.message.value : this.message,
      createdUtc: data.createdUtc.present
          ? data.createdUtc.value
          : this.createdUtc,
      updatedUtc: data.updatedUtc.present
          ? data.updatedUtc.value
          : this.updatedUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UploadPublicationRow(')
          ..write('id: $id, ')
          ..write('batchId: $batchId, ')
          ..write('processingJobId: $processingJobId, ')
          ..write('position: $position, ')
          ..write('inputJson: $inputJson, ')
          ..write('targetJson: $targetJson, ')
          ..write('targetId: $targetId, ')
          ..write('versionDigest: $versionDigest, ')
          ..write('byteCount: $byteCount, ')
          ..write('policyKey: $policyKey, ')
          ..write('state: $state, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('generation: $generation, ')
          ..write('userPaused: $userPaused, ')
          ..write('waitReason: $waitReason, ')
          ..write('retryDelayMicros: $retryDelayMicros, ')
          ..write('accumulatedRunningMicros: $accumulatedRunningMicros, ')
          ..write('currentAttemptId: $currentAttemptId, ')
          ..write('resultId: $resultId, ')
          ..write('message: $message, ')
          ..write('createdUtc: $createdUtc, ')
          ..write('updatedUtc: $updatedUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    batchId,
    processingJobId,
    position,
    inputJson,
    targetJson,
    targetId,
    versionDigest,
    byteCount,
    policyKey,
    state,
    attemptCount,
    generation,
    userPaused,
    waitReason,
    retryDelayMicros,
    accumulatedRunningMicros,
    currentAttemptId,
    resultId,
    message,
    createdUtc,
    updatedUtc,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UploadPublicationRow &&
          other.id == this.id &&
          other.batchId == this.batchId &&
          other.processingJobId == this.processingJobId &&
          other.position == this.position &&
          other.inputJson == this.inputJson &&
          other.targetJson == this.targetJson &&
          other.targetId == this.targetId &&
          other.versionDigest == this.versionDigest &&
          other.byteCount == this.byteCount &&
          other.policyKey == this.policyKey &&
          other.state == this.state &&
          other.attemptCount == this.attemptCount &&
          other.generation == this.generation &&
          other.userPaused == this.userPaused &&
          other.waitReason == this.waitReason &&
          other.retryDelayMicros == this.retryDelayMicros &&
          other.accumulatedRunningMicros == this.accumulatedRunningMicros &&
          other.currentAttemptId == this.currentAttemptId &&
          other.resultId == this.resultId &&
          other.message == this.message &&
          other.createdUtc == this.createdUtc &&
          other.updatedUtc == this.updatedUtc);
}

class UploadPublicationsCompanion
    extends UpdateCompanion<UploadPublicationRow> {
  final Value<String> id;
  final Value<String> batchId;
  final Value<String?> processingJobId;
  final Value<int> position;
  final Value<String> inputJson;
  final Value<String> targetJson;
  final Value<String> targetId;
  final Value<String> versionDigest;
  final Value<int> byteCount;
  final Value<String> policyKey;
  final Value<String> state;
  final Value<int> attemptCount;
  final Value<int> generation;
  final Value<bool> userPaused;
  final Value<String?> waitReason;
  final Value<int?> retryDelayMicros;
  final Value<int> accumulatedRunningMicros;
  final Value<String?> currentAttemptId;
  final Value<String?> resultId;
  final Value<String?> message;
  final Value<int> createdUtc;
  final Value<int> updatedUtc;
  final Value<int> rowid;
  const UploadPublicationsCompanion({
    this.id = const Value.absent(),
    this.batchId = const Value.absent(),
    this.processingJobId = const Value.absent(),
    this.position = const Value.absent(),
    this.inputJson = const Value.absent(),
    this.targetJson = const Value.absent(),
    this.targetId = const Value.absent(),
    this.versionDigest = const Value.absent(),
    this.byteCount = const Value.absent(),
    this.policyKey = const Value.absent(),
    this.state = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.generation = const Value.absent(),
    this.userPaused = const Value.absent(),
    this.waitReason = const Value.absent(),
    this.retryDelayMicros = const Value.absent(),
    this.accumulatedRunningMicros = const Value.absent(),
    this.currentAttemptId = const Value.absent(),
    this.resultId = const Value.absent(),
    this.message = const Value.absent(),
    this.createdUtc = const Value.absent(),
    this.updatedUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UploadPublicationsCompanion.insert({
    required String id,
    required String batchId,
    this.processingJobId = const Value.absent(),
    required int position,
    required String inputJson,
    required String targetJson,
    required String targetId,
    required String versionDigest,
    required int byteCount,
    required String policyKey,
    required String state,
    this.attemptCount = const Value.absent(),
    this.generation = const Value.absent(),
    this.userPaused = const Value.absent(),
    this.waitReason = const Value.absent(),
    this.retryDelayMicros = const Value.absent(),
    this.accumulatedRunningMicros = const Value.absent(),
    this.currentAttemptId = const Value.absent(),
    this.resultId = const Value.absent(),
    this.message = const Value.absent(),
    required int createdUtc,
    required int updatedUtc,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       batchId = Value(batchId),
       position = Value(position),
       inputJson = Value(inputJson),
       targetJson = Value(targetJson),
       targetId = Value(targetId),
       versionDigest = Value(versionDigest),
       byteCount = Value(byteCount),
       policyKey = Value(policyKey),
       state = Value(state),
       createdUtc = Value(createdUtc),
       updatedUtc = Value(updatedUtc);
  static Insertable<UploadPublicationRow> custom({
    Expression<String>? id,
    Expression<String>? batchId,
    Expression<String>? processingJobId,
    Expression<int>? position,
    Expression<String>? inputJson,
    Expression<String>? targetJson,
    Expression<String>? targetId,
    Expression<String>? versionDigest,
    Expression<int>? byteCount,
    Expression<String>? policyKey,
    Expression<String>? state,
    Expression<int>? attemptCount,
    Expression<int>? generation,
    Expression<bool>? userPaused,
    Expression<String>? waitReason,
    Expression<int>? retryDelayMicros,
    Expression<int>? accumulatedRunningMicros,
    Expression<String>? currentAttemptId,
    Expression<String>? resultId,
    Expression<String>? message,
    Expression<int>? createdUtc,
    Expression<int>? updatedUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (batchId != null) 'batch_id': batchId,
      if (processingJobId != null) 'processing_job_id': processingJobId,
      if (position != null) 'position': position,
      if (inputJson != null) 'input_json': inputJson,
      if (targetJson != null) 'target_json': targetJson,
      if (targetId != null) 'target_id': targetId,
      if (versionDigest != null) 'version_digest': versionDigest,
      if (byteCount != null) 'byte_count': byteCount,
      if (policyKey != null) 'policy_key': policyKey,
      if (state != null) 'state': state,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (generation != null) 'generation': generation,
      if (userPaused != null) 'user_paused': userPaused,
      if (waitReason != null) 'wait_reason': waitReason,
      if (retryDelayMicros != null) 'retry_delay_micros': retryDelayMicros,
      if (accumulatedRunningMicros != null)
        'accumulated_running_micros': accumulatedRunningMicros,
      if (currentAttemptId != null) 'current_attempt_id': currentAttemptId,
      if (resultId != null) 'result_id': resultId,
      if (message != null) 'message': message,
      if (createdUtc != null) 'created_utc': createdUtc,
      if (updatedUtc != null) 'updated_utc': updatedUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UploadPublicationsCompanion copyWith({
    Value<String>? id,
    Value<String>? batchId,
    Value<String?>? processingJobId,
    Value<int>? position,
    Value<String>? inputJson,
    Value<String>? targetJson,
    Value<String>? targetId,
    Value<String>? versionDigest,
    Value<int>? byteCount,
    Value<String>? policyKey,
    Value<String>? state,
    Value<int>? attemptCount,
    Value<int>? generation,
    Value<bool>? userPaused,
    Value<String?>? waitReason,
    Value<int?>? retryDelayMicros,
    Value<int>? accumulatedRunningMicros,
    Value<String?>? currentAttemptId,
    Value<String?>? resultId,
    Value<String?>? message,
    Value<int>? createdUtc,
    Value<int>? updatedUtc,
    Value<int>? rowid,
  }) {
    return UploadPublicationsCompanion(
      id: id ?? this.id,
      batchId: batchId ?? this.batchId,
      processingJobId: processingJobId ?? this.processingJobId,
      position: position ?? this.position,
      inputJson: inputJson ?? this.inputJson,
      targetJson: targetJson ?? this.targetJson,
      targetId: targetId ?? this.targetId,
      versionDigest: versionDigest ?? this.versionDigest,
      byteCount: byteCount ?? this.byteCount,
      policyKey: policyKey ?? this.policyKey,
      state: state ?? this.state,
      attemptCount: attemptCount ?? this.attemptCount,
      generation: generation ?? this.generation,
      userPaused: userPaused ?? this.userPaused,
      waitReason: waitReason ?? this.waitReason,
      retryDelayMicros: retryDelayMicros ?? this.retryDelayMicros,
      accumulatedRunningMicros:
          accumulatedRunningMicros ?? this.accumulatedRunningMicros,
      currentAttemptId: currentAttemptId ?? this.currentAttemptId,
      resultId: resultId ?? this.resultId,
      message: message ?? this.message,
      createdUtc: createdUtc ?? this.createdUtc,
      updatedUtc: updatedUtc ?? this.updatedUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (processingJobId.present) {
      map['processing_job_id'] = Variable<String>(processingJobId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (inputJson.present) {
      map['input_json'] = Variable<String>(inputJson.value);
    }
    if (targetJson.present) {
      map['target_json'] = Variable<String>(targetJson.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (versionDigest.present) {
      map['version_digest'] = Variable<String>(versionDigest.value);
    }
    if (byteCount.present) {
      map['byte_count'] = Variable<int>(byteCount.value);
    }
    if (policyKey.present) {
      map['policy_key'] = Variable<String>(policyKey.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (generation.present) {
      map['generation'] = Variable<int>(generation.value);
    }
    if (userPaused.present) {
      map['user_paused'] = Variable<bool>(userPaused.value);
    }
    if (waitReason.present) {
      map['wait_reason'] = Variable<String>(waitReason.value);
    }
    if (retryDelayMicros.present) {
      map['retry_delay_micros'] = Variable<int>(retryDelayMicros.value);
    }
    if (accumulatedRunningMicros.present) {
      map['accumulated_running_micros'] = Variable<int>(
        accumulatedRunningMicros.value,
      );
    }
    if (currentAttemptId.present) {
      map['current_attempt_id'] = Variable<String>(currentAttemptId.value);
    }
    if (resultId.present) {
      map['result_id'] = Variable<String>(resultId.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (createdUtc.present) {
      map['created_utc'] = Variable<int>(createdUtc.value);
    }
    if (updatedUtc.present) {
      map['updated_utc'] = Variable<int>(updatedUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UploadPublicationsCompanion(')
          ..write('id: $id, ')
          ..write('batchId: $batchId, ')
          ..write('processingJobId: $processingJobId, ')
          ..write('position: $position, ')
          ..write('inputJson: $inputJson, ')
          ..write('targetJson: $targetJson, ')
          ..write('targetId: $targetId, ')
          ..write('versionDigest: $versionDigest, ')
          ..write('byteCount: $byteCount, ')
          ..write('policyKey: $policyKey, ')
          ..write('state: $state, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('generation: $generation, ')
          ..write('userPaused: $userPaused, ')
          ..write('waitReason: $waitReason, ')
          ..write('retryDelayMicros: $retryDelayMicros, ')
          ..write('accumulatedRunningMicros: $accumulatedRunningMicros, ')
          ..write('currentAttemptId: $currentAttemptId, ')
          ..write('resultId: $resultId, ')
          ..write('message: $message, ')
          ..write('createdUtc: $createdUtc, ')
          ..write('updatedUtc: $updatedUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UploadAttemptsTable extends UploadAttempts
    with TableInfo<$UploadAttemptsTable, UploadAttempt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UploadAttemptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES upload_publications (id)',
    ),
  );
  static const VerificationMeta _generationMeta = const VerificationMeta(
    'generation',
  );
  @override
  late final GeneratedColumn<int> generation = GeneratedColumn<int>(
    'generation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetGenerationMeta = const VerificationMeta(
    'targetGeneration',
  );
  @override
  late final GeneratedColumn<int> targetGeneration = GeneratedColumn<int>(
    'target_generation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedUtcMeta = const VerificationMeta(
    'startedUtc',
  );
  @override
  late final GeneratedColumn<int> startedUtc = GeneratedColumn<int>(
    'started_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _requestMayHaveStartedMeta =
      const VerificationMeta('requestMayHaveStarted');
  @override
  late final GeneratedColumn<bool> requestMayHaveStarted =
      GeneratedColumn<bool>(
        'request_may_have_started',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("request_may_have_started" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _endedUtcMeta = const VerificationMeta(
    'endedUtc',
  );
  @override
  late final GeneratedColumn<int> endedUtc = GeneratedColumn<int>(
    'ended_utc',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _outcomeMeta = const VerificationMeta(
    'outcome',
  );
  @override
  late final GeneratedColumn<String> outcome = GeneratedColumn<String>(
    'outcome',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    itemId,
    generation,
    targetGeneration,
    startedUtc,
    requestMayHaveStarted,
    endedUtc,
    outcome,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'upload_attempts';
  @override
  VerificationContext validateIntegrity(
    Insertable<UploadAttempt> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('generation')) {
      context.handle(
        _generationMeta,
        generation.isAcceptableOrUnknown(data['generation']!, _generationMeta),
      );
    } else if (isInserting) {
      context.missing(_generationMeta);
    }
    if (data.containsKey('target_generation')) {
      context.handle(
        _targetGenerationMeta,
        targetGeneration.isAcceptableOrUnknown(
          data['target_generation']!,
          _targetGenerationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetGenerationMeta);
    }
    if (data.containsKey('started_utc')) {
      context.handle(
        _startedUtcMeta,
        startedUtc.isAcceptableOrUnknown(data['started_utc']!, _startedUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_startedUtcMeta);
    }
    if (data.containsKey('request_may_have_started')) {
      context.handle(
        _requestMayHaveStartedMeta,
        requestMayHaveStarted.isAcceptableOrUnknown(
          data['request_may_have_started']!,
          _requestMayHaveStartedMeta,
        ),
      );
    }
    if (data.containsKey('ended_utc')) {
      context.handle(
        _endedUtcMeta,
        endedUtc.isAcceptableOrUnknown(data['ended_utc']!, _endedUtcMeta),
      );
    }
    if (data.containsKey('outcome')) {
      context.handle(
        _outcomeMeta,
        outcome.isAcceptableOrUnknown(data['outcome']!, _outcomeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {itemId, generation},
  ];
  @override
  UploadAttempt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UploadAttempt(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      generation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}generation'],
      )!,
      targetGeneration: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}target_generation'],
      )!,
      startedUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_utc'],
      )!,
      requestMayHaveStarted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}request_may_have_started'],
      )!,
      endedUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ended_utc'],
      ),
      outcome: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}outcome'],
      ),
    );
  }

  @override
  $UploadAttemptsTable createAlias(String alias) {
    return $UploadAttemptsTable(attachedDatabase, alias);
  }
}

class UploadAttempt extends DataClass implements Insertable<UploadAttempt> {
  final String id;
  final String itemId;
  final int generation;
  final int targetGeneration;
  final int startedUtc;
  final bool requestMayHaveStarted;
  final int? endedUtc;
  final String? outcome;
  const UploadAttempt({
    required this.id,
    required this.itemId,
    required this.generation,
    required this.targetGeneration,
    required this.startedUtc,
    required this.requestMayHaveStarted,
    this.endedUtc,
    this.outcome,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['item_id'] = Variable<String>(itemId);
    map['generation'] = Variable<int>(generation);
    map['target_generation'] = Variable<int>(targetGeneration);
    map['started_utc'] = Variable<int>(startedUtc);
    map['request_may_have_started'] = Variable<bool>(requestMayHaveStarted);
    if (!nullToAbsent || endedUtc != null) {
      map['ended_utc'] = Variable<int>(endedUtc);
    }
    if (!nullToAbsent || outcome != null) {
      map['outcome'] = Variable<String>(outcome);
    }
    return map;
  }

  UploadAttemptsCompanion toCompanion(bool nullToAbsent) {
    return UploadAttemptsCompanion(
      id: Value(id),
      itemId: Value(itemId),
      generation: Value(generation),
      targetGeneration: Value(targetGeneration),
      startedUtc: Value(startedUtc),
      requestMayHaveStarted: Value(requestMayHaveStarted),
      endedUtc: endedUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(endedUtc),
      outcome: outcome == null && nullToAbsent
          ? const Value.absent()
          : Value(outcome),
    );
  }

  factory UploadAttempt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UploadAttempt(
      id: serializer.fromJson<String>(json['id']),
      itemId: serializer.fromJson<String>(json['itemId']),
      generation: serializer.fromJson<int>(json['generation']),
      targetGeneration: serializer.fromJson<int>(json['targetGeneration']),
      startedUtc: serializer.fromJson<int>(json['startedUtc']),
      requestMayHaveStarted: serializer.fromJson<bool>(
        json['requestMayHaveStarted'],
      ),
      endedUtc: serializer.fromJson<int?>(json['endedUtc']),
      outcome: serializer.fromJson<String?>(json['outcome']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'itemId': serializer.toJson<String>(itemId),
      'generation': serializer.toJson<int>(generation),
      'targetGeneration': serializer.toJson<int>(targetGeneration),
      'startedUtc': serializer.toJson<int>(startedUtc),
      'requestMayHaveStarted': serializer.toJson<bool>(requestMayHaveStarted),
      'endedUtc': serializer.toJson<int?>(endedUtc),
      'outcome': serializer.toJson<String?>(outcome),
    };
  }

  UploadAttempt copyWith({
    String? id,
    String? itemId,
    int? generation,
    int? targetGeneration,
    int? startedUtc,
    bool? requestMayHaveStarted,
    Value<int?> endedUtc = const Value.absent(),
    Value<String?> outcome = const Value.absent(),
  }) => UploadAttempt(
    id: id ?? this.id,
    itemId: itemId ?? this.itemId,
    generation: generation ?? this.generation,
    targetGeneration: targetGeneration ?? this.targetGeneration,
    startedUtc: startedUtc ?? this.startedUtc,
    requestMayHaveStarted: requestMayHaveStarted ?? this.requestMayHaveStarted,
    endedUtc: endedUtc.present ? endedUtc.value : this.endedUtc,
    outcome: outcome.present ? outcome.value : this.outcome,
  );
  UploadAttempt copyWithCompanion(UploadAttemptsCompanion data) {
    return UploadAttempt(
      id: data.id.present ? data.id.value : this.id,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      generation: data.generation.present
          ? data.generation.value
          : this.generation,
      targetGeneration: data.targetGeneration.present
          ? data.targetGeneration.value
          : this.targetGeneration,
      startedUtc: data.startedUtc.present
          ? data.startedUtc.value
          : this.startedUtc,
      requestMayHaveStarted: data.requestMayHaveStarted.present
          ? data.requestMayHaveStarted.value
          : this.requestMayHaveStarted,
      endedUtc: data.endedUtc.present ? data.endedUtc.value : this.endedUtc,
      outcome: data.outcome.present ? data.outcome.value : this.outcome,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UploadAttempt(')
          ..write('id: $id, ')
          ..write('itemId: $itemId, ')
          ..write('generation: $generation, ')
          ..write('targetGeneration: $targetGeneration, ')
          ..write('startedUtc: $startedUtc, ')
          ..write('requestMayHaveStarted: $requestMayHaveStarted, ')
          ..write('endedUtc: $endedUtc, ')
          ..write('outcome: $outcome')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    itemId,
    generation,
    targetGeneration,
    startedUtc,
    requestMayHaveStarted,
    endedUtc,
    outcome,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UploadAttempt &&
          other.id == this.id &&
          other.itemId == this.itemId &&
          other.generation == this.generation &&
          other.targetGeneration == this.targetGeneration &&
          other.startedUtc == this.startedUtc &&
          other.requestMayHaveStarted == this.requestMayHaveStarted &&
          other.endedUtc == this.endedUtc &&
          other.outcome == this.outcome);
}

class UploadAttemptsCompanion extends UpdateCompanion<UploadAttempt> {
  final Value<String> id;
  final Value<String> itemId;
  final Value<int> generation;
  final Value<int> targetGeneration;
  final Value<int> startedUtc;
  final Value<bool> requestMayHaveStarted;
  final Value<int?> endedUtc;
  final Value<String?> outcome;
  final Value<int> rowid;
  const UploadAttemptsCompanion({
    this.id = const Value.absent(),
    this.itemId = const Value.absent(),
    this.generation = const Value.absent(),
    this.targetGeneration = const Value.absent(),
    this.startedUtc = const Value.absent(),
    this.requestMayHaveStarted = const Value.absent(),
    this.endedUtc = const Value.absent(),
    this.outcome = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UploadAttemptsCompanion.insert({
    required String id,
    required String itemId,
    required int generation,
    required int targetGeneration,
    required int startedUtc,
    this.requestMayHaveStarted = const Value.absent(),
    this.endedUtc = const Value.absent(),
    this.outcome = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       itemId = Value(itemId),
       generation = Value(generation),
       targetGeneration = Value(targetGeneration),
       startedUtc = Value(startedUtc);
  static Insertable<UploadAttempt> custom({
    Expression<String>? id,
    Expression<String>? itemId,
    Expression<int>? generation,
    Expression<int>? targetGeneration,
    Expression<int>? startedUtc,
    Expression<bool>? requestMayHaveStarted,
    Expression<int>? endedUtc,
    Expression<String>? outcome,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (itemId != null) 'item_id': itemId,
      if (generation != null) 'generation': generation,
      if (targetGeneration != null) 'target_generation': targetGeneration,
      if (startedUtc != null) 'started_utc': startedUtc,
      if (requestMayHaveStarted != null)
        'request_may_have_started': requestMayHaveStarted,
      if (endedUtc != null) 'ended_utc': endedUtc,
      if (outcome != null) 'outcome': outcome,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UploadAttemptsCompanion copyWith({
    Value<String>? id,
    Value<String>? itemId,
    Value<int>? generation,
    Value<int>? targetGeneration,
    Value<int>? startedUtc,
    Value<bool>? requestMayHaveStarted,
    Value<int?>? endedUtc,
    Value<String?>? outcome,
    Value<int>? rowid,
  }) {
    return UploadAttemptsCompanion(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      generation: generation ?? this.generation,
      targetGeneration: targetGeneration ?? this.targetGeneration,
      startedUtc: startedUtc ?? this.startedUtc,
      requestMayHaveStarted:
          requestMayHaveStarted ?? this.requestMayHaveStarted,
      endedUtc: endedUtc ?? this.endedUtc,
      outcome: outcome ?? this.outcome,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (generation.present) {
      map['generation'] = Variable<int>(generation.value);
    }
    if (targetGeneration.present) {
      map['target_generation'] = Variable<int>(targetGeneration.value);
    }
    if (startedUtc.present) {
      map['started_utc'] = Variable<int>(startedUtc.value);
    }
    if (requestMayHaveStarted.present) {
      map['request_may_have_started'] = Variable<bool>(
        requestMayHaveStarted.value,
      );
    }
    if (endedUtc.present) {
      map['ended_utc'] = Variable<int>(endedUtc.value);
    }
    if (outcome.present) {
      map['outcome'] = Variable<String>(outcome.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UploadAttemptsCompanion(')
          ..write('id: $id, ')
          ..write('itemId: $itemId, ')
          ..write('generation: $generation, ')
          ..write('targetGeneration: $targetGeneration, ')
          ..write('startedUtc: $startedUtc, ')
          ..write('requestMayHaveStarted: $requestMayHaveStarted, ')
          ..write('endedUtc: $endedUtc, ')
          ..write('outcome: $outcome, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RemoteUploadResultsTable extends RemoteUploadResults
    with TableInfo<$RemoteUploadResultsTable, RemoteUploadResultRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RemoteUploadResultsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptIdMeta = const VerificationMeta(
    'attemptId',
  );
  @override
  late final GeneratedColumn<String> attemptId = GeneratedColumn<String>(
    'attempt_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _inputJsonMeta = const VerificationMeta(
    'inputJson',
  );
  @override
  late final GeneratedColumn<String> inputJson = GeneratedColumn<String>(
    'input_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetJsonMeta = const VerificationMeta(
    'targetJson',
  );
  @override
  late final GeneratedColumn<String> targetJson = GeneratedColumn<String>(
    'target_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionDigestMeta = const VerificationMeta(
    'versionDigest',
  );
  @override
  late final GeneratedColumn<String> versionDigest = GeneratedColumn<String>(
    'version_digest',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _byteCountMeta = const VerificationMeta(
    'byteCount',
  );
  @override
  late final GeneratedColumn<int> byteCount = GeneratedColumn<int>(
    'byte_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _policyKeyMeta = const VerificationMeta(
    'policyKey',
  );
  @override
  late final GeneratedColumn<String> policyKey = GeneratedColumn<String>(
    'policy_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteIdMeta = const VerificationMeta(
    'remoteId',
  );
  @override
  late final GeneratedColumn<String> remoteId = GeneratedColumn<String>(
    'remote_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _directUrlMeta = const VerificationMeta(
    'directUrl',
  );
  @override
  late final GeneratedColumn<String> directUrl = GeneratedColumn<String>(
    'direct_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _viewerUrlMeta = const VerificationMeta(
    'viewerUrl',
  );
  @override
  late final GeneratedColumn<String> viewerUrl = GeneratedColumn<String>(
    'viewer_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _confirmedUtcMeta = const VerificationMeta(
    'confirmedUtc',
  );
  @override
  late final GeneratedColumn<int> confirmedUtc = GeneratedColumn<int>(
    'confirmed_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lateMeta = const VerificationMeta('late');
  @override
  late final GeneratedColumn<bool> late = GeneratedColumn<bool>(
    'late',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("late" IN (0, 1))',
    ),
  );
  static const VerificationMeta _secretReferenceMeta = const VerificationMeta(
    'secretReference',
  );
  @override
  late final GeneratedColumn<String> secretReference = GeneratedColumn<String>(
    'secret_reference',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _managementAvailableMeta =
      const VerificationMeta('managementAvailable');
  @override
  late final GeneratedColumn<bool> managementAvailable = GeneratedColumn<bool>(
    'management_available',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("management_available" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _linkStateMeta = const VerificationMeta(
    'linkState',
  );
  @override
  late final GeneratedColumn<String> linkState = GeneratedColumn<String>(
    'link_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('recorded'),
  );
  static const VerificationMeta _linkReasonMeta = const VerificationMeta(
    'linkReason',
  );
  @override
  late final GeneratedColumn<String> linkReason = GeneratedColumn<String>(
    'link_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _linkCheckedUtcMeta = const VerificationMeta(
    'linkCheckedUtc',
  );
  @override
  late final GeneratedColumn<int> linkCheckedUtc = GeneratedColumn<int>(
    'link_checked_utc',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastAccessibleUtcMeta = const VerificationMeta(
    'lastAccessibleUtc',
  );
  @override
  late final GeneratedColumn<int> lastAccessibleUtc = GeneratedColumn<int>(
    'last_accessible_utc',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _probeGenerationMeta = const VerificationMeta(
    'probeGeneration',
  );
  @override
  late final GeneratedColumn<int> probeGeneration = GeneratedColumn<int>(
    'probe_generation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _probeHttpStatusMeta = const VerificationMeta(
    'probeHttpStatus',
  );
  @override
  late final GeneratedColumn<int> probeHttpStatus = GeneratedColumn<int>(
    'probe_http_status',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    attemptId,
    inputJson,
    targetJson,
    targetId,
    versionDigest,
    byteCount,
    policyKey,
    remoteId,
    directUrl,
    viewerUrl,
    confirmedUtc,
    late,
    secretReference,
    managementAvailable,
    linkState,
    linkReason,
    linkCheckedUtc,
    lastAccessibleUtc,
    probeGeneration,
    probeHttpStatus,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'remote_upload_results';
  @override
  VerificationContext validateIntegrity(
    Insertable<RemoteUploadResultRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('attempt_id')) {
      context.handle(
        _attemptIdMeta,
        attemptId.isAcceptableOrUnknown(data['attempt_id']!, _attemptIdMeta),
      );
    } else if (isInserting) {
      context.missing(_attemptIdMeta);
    }
    if (data.containsKey('input_json')) {
      context.handle(
        _inputJsonMeta,
        inputJson.isAcceptableOrUnknown(data['input_json']!, _inputJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_inputJsonMeta);
    }
    if (data.containsKey('target_json')) {
      context.handle(
        _targetJsonMeta,
        targetJson.isAcceptableOrUnknown(data['target_json']!, _targetJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_targetJsonMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_targetIdMeta);
    }
    if (data.containsKey('version_digest')) {
      context.handle(
        _versionDigestMeta,
        versionDigest.isAcceptableOrUnknown(
          data['version_digest']!,
          _versionDigestMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_versionDigestMeta);
    }
    if (data.containsKey('byte_count')) {
      context.handle(
        _byteCountMeta,
        byteCount.isAcceptableOrUnknown(data['byte_count']!, _byteCountMeta),
      );
    } else if (isInserting) {
      context.missing(_byteCountMeta);
    }
    if (data.containsKey('policy_key')) {
      context.handle(
        _policyKeyMeta,
        policyKey.isAcceptableOrUnknown(data['policy_key']!, _policyKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_policyKeyMeta);
    }
    if (data.containsKey('remote_id')) {
      context.handle(
        _remoteIdMeta,
        remoteId.isAcceptableOrUnknown(data['remote_id']!, _remoteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_remoteIdMeta);
    }
    if (data.containsKey('direct_url')) {
      context.handle(
        _directUrlMeta,
        directUrl.isAcceptableOrUnknown(data['direct_url']!, _directUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_directUrlMeta);
    }
    if (data.containsKey('viewer_url')) {
      context.handle(
        _viewerUrlMeta,
        viewerUrl.isAcceptableOrUnknown(data['viewer_url']!, _viewerUrlMeta),
      );
    }
    if (data.containsKey('confirmed_utc')) {
      context.handle(
        _confirmedUtcMeta,
        confirmedUtc.isAcceptableOrUnknown(
          data['confirmed_utc']!,
          _confirmedUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_confirmedUtcMeta);
    }
    if (data.containsKey('late')) {
      context.handle(
        _lateMeta,
        late.isAcceptableOrUnknown(data['late']!, _lateMeta),
      );
    } else if (isInserting) {
      context.missing(_lateMeta);
    }
    if (data.containsKey('secret_reference')) {
      context.handle(
        _secretReferenceMeta,
        secretReference.isAcceptableOrUnknown(
          data['secret_reference']!,
          _secretReferenceMeta,
        ),
      );
    }
    if (data.containsKey('management_available')) {
      context.handle(
        _managementAvailableMeta,
        managementAvailable.isAcceptableOrUnknown(
          data['management_available']!,
          _managementAvailableMeta,
        ),
      );
    }
    if (data.containsKey('link_state')) {
      context.handle(
        _linkStateMeta,
        linkState.isAcceptableOrUnknown(data['link_state']!, _linkStateMeta),
      );
    }
    if (data.containsKey('link_reason')) {
      context.handle(
        _linkReasonMeta,
        linkReason.isAcceptableOrUnknown(data['link_reason']!, _linkReasonMeta),
      );
    }
    if (data.containsKey('link_checked_utc')) {
      context.handle(
        _linkCheckedUtcMeta,
        linkCheckedUtc.isAcceptableOrUnknown(
          data['link_checked_utc']!,
          _linkCheckedUtcMeta,
        ),
      );
    }
    if (data.containsKey('last_accessible_utc')) {
      context.handle(
        _lastAccessibleUtcMeta,
        lastAccessibleUtc.isAcceptableOrUnknown(
          data['last_accessible_utc']!,
          _lastAccessibleUtcMeta,
        ),
      );
    }
    if (data.containsKey('probe_generation')) {
      context.handle(
        _probeGenerationMeta,
        probeGeneration.isAcceptableOrUnknown(
          data['probe_generation']!,
          _probeGenerationMeta,
        ),
      );
    }
    if (data.containsKey('probe_http_status')) {
      context.handle(
        _probeHttpStatusMeta,
        probeHttpStatus.isAcceptableOrUnknown(
          data['probe_http_status']!,
          _probeHttpStatusMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RemoteUploadResultRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RemoteUploadResultRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      attemptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attempt_id'],
      )!,
      inputJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}input_json'],
      )!,
      targetJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_json'],
      )!,
      targetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_id'],
      )!,
      versionDigest: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version_digest'],
      )!,
      byteCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_count'],
      )!,
      policyKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}policy_key'],
      )!,
      remoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_id'],
      )!,
      directUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direct_url'],
      )!,
      viewerUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}viewer_url'],
      ),
      confirmedUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}confirmed_utc'],
      )!,
      late: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}late'],
      )!,
      secretReference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}secret_reference'],
      ),
      managementAvailable: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}management_available'],
      )!,
      linkState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}link_state'],
      )!,
      linkReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}link_reason'],
      ),
      linkCheckedUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}link_checked_utc'],
      ),
      lastAccessibleUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_accessible_utc'],
      ),
      probeGeneration: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}probe_generation'],
      )!,
      probeHttpStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}probe_http_status'],
      ),
    );
  }

  @override
  $RemoteUploadResultsTable createAlias(String alias) {
    return $RemoteUploadResultsTable(attachedDatabase, alias);
  }
}

class RemoteUploadResultRow extends DataClass
    implements Insertable<RemoteUploadResultRow> {
  final String id;
  final String attemptId;
  final String inputJson;
  final String targetJson;
  final String targetId;
  final String versionDigest;
  final int byteCount;
  final String policyKey;
  final String remoteId;
  final String directUrl;
  final String? viewerUrl;
  final int confirmedUtc;
  final bool late;
  final String? secretReference;
  final bool managementAvailable;
  final String linkState;
  final String? linkReason;
  final int? linkCheckedUtc;
  final int? lastAccessibleUtc;
  final int probeGeneration;
  final int? probeHttpStatus;
  const RemoteUploadResultRow({
    required this.id,
    required this.attemptId,
    required this.inputJson,
    required this.targetJson,
    required this.targetId,
    required this.versionDigest,
    required this.byteCount,
    required this.policyKey,
    required this.remoteId,
    required this.directUrl,
    this.viewerUrl,
    required this.confirmedUtc,
    required this.late,
    this.secretReference,
    required this.managementAvailable,
    required this.linkState,
    this.linkReason,
    this.linkCheckedUtc,
    this.lastAccessibleUtc,
    required this.probeGeneration,
    this.probeHttpStatus,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['attempt_id'] = Variable<String>(attemptId);
    map['input_json'] = Variable<String>(inputJson);
    map['target_json'] = Variable<String>(targetJson);
    map['target_id'] = Variable<String>(targetId);
    map['version_digest'] = Variable<String>(versionDigest);
    map['byte_count'] = Variable<int>(byteCount);
    map['policy_key'] = Variable<String>(policyKey);
    map['remote_id'] = Variable<String>(remoteId);
    map['direct_url'] = Variable<String>(directUrl);
    if (!nullToAbsent || viewerUrl != null) {
      map['viewer_url'] = Variable<String>(viewerUrl);
    }
    map['confirmed_utc'] = Variable<int>(confirmedUtc);
    map['late'] = Variable<bool>(late);
    if (!nullToAbsent || secretReference != null) {
      map['secret_reference'] = Variable<String>(secretReference);
    }
    map['management_available'] = Variable<bool>(managementAvailable);
    map['link_state'] = Variable<String>(linkState);
    if (!nullToAbsent || linkReason != null) {
      map['link_reason'] = Variable<String>(linkReason);
    }
    if (!nullToAbsent || linkCheckedUtc != null) {
      map['link_checked_utc'] = Variable<int>(linkCheckedUtc);
    }
    if (!nullToAbsent || lastAccessibleUtc != null) {
      map['last_accessible_utc'] = Variable<int>(lastAccessibleUtc);
    }
    map['probe_generation'] = Variable<int>(probeGeneration);
    if (!nullToAbsent || probeHttpStatus != null) {
      map['probe_http_status'] = Variable<int>(probeHttpStatus);
    }
    return map;
  }

  RemoteUploadResultsCompanion toCompanion(bool nullToAbsent) {
    return RemoteUploadResultsCompanion(
      id: Value(id),
      attemptId: Value(attemptId),
      inputJson: Value(inputJson),
      targetJson: Value(targetJson),
      targetId: Value(targetId),
      versionDigest: Value(versionDigest),
      byteCount: Value(byteCount),
      policyKey: Value(policyKey),
      remoteId: Value(remoteId),
      directUrl: Value(directUrl),
      viewerUrl: viewerUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(viewerUrl),
      confirmedUtc: Value(confirmedUtc),
      late: Value(late),
      secretReference: secretReference == null && nullToAbsent
          ? const Value.absent()
          : Value(secretReference),
      managementAvailable: Value(managementAvailable),
      linkState: Value(linkState),
      linkReason: linkReason == null && nullToAbsent
          ? const Value.absent()
          : Value(linkReason),
      linkCheckedUtc: linkCheckedUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(linkCheckedUtc),
      lastAccessibleUtc: lastAccessibleUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAccessibleUtc),
      probeGeneration: Value(probeGeneration),
      probeHttpStatus: probeHttpStatus == null && nullToAbsent
          ? const Value.absent()
          : Value(probeHttpStatus),
    );
  }

  factory RemoteUploadResultRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RemoteUploadResultRow(
      id: serializer.fromJson<String>(json['id']),
      attemptId: serializer.fromJson<String>(json['attemptId']),
      inputJson: serializer.fromJson<String>(json['inputJson']),
      targetJson: serializer.fromJson<String>(json['targetJson']),
      targetId: serializer.fromJson<String>(json['targetId']),
      versionDigest: serializer.fromJson<String>(json['versionDigest']),
      byteCount: serializer.fromJson<int>(json['byteCount']),
      policyKey: serializer.fromJson<String>(json['policyKey']),
      remoteId: serializer.fromJson<String>(json['remoteId']),
      directUrl: serializer.fromJson<String>(json['directUrl']),
      viewerUrl: serializer.fromJson<String?>(json['viewerUrl']),
      confirmedUtc: serializer.fromJson<int>(json['confirmedUtc']),
      late: serializer.fromJson<bool>(json['late']),
      secretReference: serializer.fromJson<String?>(json['secretReference']),
      managementAvailable: serializer.fromJson<bool>(
        json['managementAvailable'],
      ),
      linkState: serializer.fromJson<String>(json['linkState']),
      linkReason: serializer.fromJson<String?>(json['linkReason']),
      linkCheckedUtc: serializer.fromJson<int?>(json['linkCheckedUtc']),
      lastAccessibleUtc: serializer.fromJson<int?>(json['lastAccessibleUtc']),
      probeGeneration: serializer.fromJson<int>(json['probeGeneration']),
      probeHttpStatus: serializer.fromJson<int?>(json['probeHttpStatus']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'attemptId': serializer.toJson<String>(attemptId),
      'inputJson': serializer.toJson<String>(inputJson),
      'targetJson': serializer.toJson<String>(targetJson),
      'targetId': serializer.toJson<String>(targetId),
      'versionDigest': serializer.toJson<String>(versionDigest),
      'byteCount': serializer.toJson<int>(byteCount),
      'policyKey': serializer.toJson<String>(policyKey),
      'remoteId': serializer.toJson<String>(remoteId),
      'directUrl': serializer.toJson<String>(directUrl),
      'viewerUrl': serializer.toJson<String?>(viewerUrl),
      'confirmedUtc': serializer.toJson<int>(confirmedUtc),
      'late': serializer.toJson<bool>(late),
      'secretReference': serializer.toJson<String?>(secretReference),
      'managementAvailable': serializer.toJson<bool>(managementAvailable),
      'linkState': serializer.toJson<String>(linkState),
      'linkReason': serializer.toJson<String?>(linkReason),
      'linkCheckedUtc': serializer.toJson<int?>(linkCheckedUtc),
      'lastAccessibleUtc': serializer.toJson<int?>(lastAccessibleUtc),
      'probeGeneration': serializer.toJson<int>(probeGeneration),
      'probeHttpStatus': serializer.toJson<int?>(probeHttpStatus),
    };
  }

  RemoteUploadResultRow copyWith({
    String? id,
    String? attemptId,
    String? inputJson,
    String? targetJson,
    String? targetId,
    String? versionDigest,
    int? byteCount,
    String? policyKey,
    String? remoteId,
    String? directUrl,
    Value<String?> viewerUrl = const Value.absent(),
    int? confirmedUtc,
    bool? late,
    Value<String?> secretReference = const Value.absent(),
    bool? managementAvailable,
    String? linkState,
    Value<String?> linkReason = const Value.absent(),
    Value<int?> linkCheckedUtc = const Value.absent(),
    Value<int?> lastAccessibleUtc = const Value.absent(),
    int? probeGeneration,
    Value<int?> probeHttpStatus = const Value.absent(),
  }) => RemoteUploadResultRow(
    id: id ?? this.id,
    attemptId: attemptId ?? this.attemptId,
    inputJson: inputJson ?? this.inputJson,
    targetJson: targetJson ?? this.targetJson,
    targetId: targetId ?? this.targetId,
    versionDigest: versionDigest ?? this.versionDigest,
    byteCount: byteCount ?? this.byteCount,
    policyKey: policyKey ?? this.policyKey,
    remoteId: remoteId ?? this.remoteId,
    directUrl: directUrl ?? this.directUrl,
    viewerUrl: viewerUrl.present ? viewerUrl.value : this.viewerUrl,
    confirmedUtc: confirmedUtc ?? this.confirmedUtc,
    late: late ?? this.late,
    secretReference: secretReference.present
        ? secretReference.value
        : this.secretReference,
    managementAvailable: managementAvailable ?? this.managementAvailable,
    linkState: linkState ?? this.linkState,
    linkReason: linkReason.present ? linkReason.value : this.linkReason,
    linkCheckedUtc: linkCheckedUtc.present
        ? linkCheckedUtc.value
        : this.linkCheckedUtc,
    lastAccessibleUtc: lastAccessibleUtc.present
        ? lastAccessibleUtc.value
        : this.lastAccessibleUtc,
    probeGeneration: probeGeneration ?? this.probeGeneration,
    probeHttpStatus: probeHttpStatus.present
        ? probeHttpStatus.value
        : this.probeHttpStatus,
  );
  RemoteUploadResultRow copyWithCompanion(RemoteUploadResultsCompanion data) {
    return RemoteUploadResultRow(
      id: data.id.present ? data.id.value : this.id,
      attemptId: data.attemptId.present ? data.attemptId.value : this.attemptId,
      inputJson: data.inputJson.present ? data.inputJson.value : this.inputJson,
      targetJson: data.targetJson.present
          ? data.targetJson.value
          : this.targetJson,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      versionDigest: data.versionDigest.present
          ? data.versionDigest.value
          : this.versionDigest,
      byteCount: data.byteCount.present ? data.byteCount.value : this.byteCount,
      policyKey: data.policyKey.present ? data.policyKey.value : this.policyKey,
      remoteId: data.remoteId.present ? data.remoteId.value : this.remoteId,
      directUrl: data.directUrl.present ? data.directUrl.value : this.directUrl,
      viewerUrl: data.viewerUrl.present ? data.viewerUrl.value : this.viewerUrl,
      confirmedUtc: data.confirmedUtc.present
          ? data.confirmedUtc.value
          : this.confirmedUtc,
      late: data.late.present ? data.late.value : this.late,
      secretReference: data.secretReference.present
          ? data.secretReference.value
          : this.secretReference,
      managementAvailable: data.managementAvailable.present
          ? data.managementAvailable.value
          : this.managementAvailable,
      linkState: data.linkState.present ? data.linkState.value : this.linkState,
      linkReason: data.linkReason.present
          ? data.linkReason.value
          : this.linkReason,
      linkCheckedUtc: data.linkCheckedUtc.present
          ? data.linkCheckedUtc.value
          : this.linkCheckedUtc,
      lastAccessibleUtc: data.lastAccessibleUtc.present
          ? data.lastAccessibleUtc.value
          : this.lastAccessibleUtc,
      probeGeneration: data.probeGeneration.present
          ? data.probeGeneration.value
          : this.probeGeneration,
      probeHttpStatus: data.probeHttpStatus.present
          ? data.probeHttpStatus.value
          : this.probeHttpStatus,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RemoteUploadResultRow(')
          ..write('id: $id, ')
          ..write('attemptId: $attemptId, ')
          ..write('inputJson: $inputJson, ')
          ..write('targetJson: $targetJson, ')
          ..write('targetId: $targetId, ')
          ..write('versionDigest: $versionDigest, ')
          ..write('byteCount: $byteCount, ')
          ..write('policyKey: $policyKey, ')
          ..write('remoteId: $remoteId, ')
          ..write('directUrl: $directUrl, ')
          ..write('viewerUrl: $viewerUrl, ')
          ..write('confirmedUtc: $confirmedUtc, ')
          ..write('late: $late, ')
          ..write('secretReference: $secretReference, ')
          ..write('managementAvailable: $managementAvailable, ')
          ..write('linkState: $linkState, ')
          ..write('linkReason: $linkReason, ')
          ..write('linkCheckedUtc: $linkCheckedUtc, ')
          ..write('lastAccessibleUtc: $lastAccessibleUtc, ')
          ..write('probeGeneration: $probeGeneration, ')
          ..write('probeHttpStatus: $probeHttpStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    attemptId,
    inputJson,
    targetJson,
    targetId,
    versionDigest,
    byteCount,
    policyKey,
    remoteId,
    directUrl,
    viewerUrl,
    confirmedUtc,
    late,
    secretReference,
    managementAvailable,
    linkState,
    linkReason,
    linkCheckedUtc,
    lastAccessibleUtc,
    probeGeneration,
    probeHttpStatus,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RemoteUploadResultRow &&
          other.id == this.id &&
          other.attemptId == this.attemptId &&
          other.inputJson == this.inputJson &&
          other.targetJson == this.targetJson &&
          other.targetId == this.targetId &&
          other.versionDigest == this.versionDigest &&
          other.byteCount == this.byteCount &&
          other.policyKey == this.policyKey &&
          other.remoteId == this.remoteId &&
          other.directUrl == this.directUrl &&
          other.viewerUrl == this.viewerUrl &&
          other.confirmedUtc == this.confirmedUtc &&
          other.late == this.late &&
          other.secretReference == this.secretReference &&
          other.managementAvailable == this.managementAvailable &&
          other.linkState == this.linkState &&
          other.linkReason == this.linkReason &&
          other.linkCheckedUtc == this.linkCheckedUtc &&
          other.lastAccessibleUtc == this.lastAccessibleUtc &&
          other.probeGeneration == this.probeGeneration &&
          other.probeHttpStatus == this.probeHttpStatus);
}

class RemoteUploadResultsCompanion
    extends UpdateCompanion<RemoteUploadResultRow> {
  final Value<String> id;
  final Value<String> attemptId;
  final Value<String> inputJson;
  final Value<String> targetJson;
  final Value<String> targetId;
  final Value<String> versionDigest;
  final Value<int> byteCount;
  final Value<String> policyKey;
  final Value<String> remoteId;
  final Value<String> directUrl;
  final Value<String?> viewerUrl;
  final Value<int> confirmedUtc;
  final Value<bool> late;
  final Value<String?> secretReference;
  final Value<bool> managementAvailable;
  final Value<String> linkState;
  final Value<String?> linkReason;
  final Value<int?> linkCheckedUtc;
  final Value<int?> lastAccessibleUtc;
  final Value<int> probeGeneration;
  final Value<int?> probeHttpStatus;
  final Value<int> rowid;
  const RemoteUploadResultsCompanion({
    this.id = const Value.absent(),
    this.attemptId = const Value.absent(),
    this.inputJson = const Value.absent(),
    this.targetJson = const Value.absent(),
    this.targetId = const Value.absent(),
    this.versionDigest = const Value.absent(),
    this.byteCount = const Value.absent(),
    this.policyKey = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.directUrl = const Value.absent(),
    this.viewerUrl = const Value.absent(),
    this.confirmedUtc = const Value.absent(),
    this.late = const Value.absent(),
    this.secretReference = const Value.absent(),
    this.managementAvailable = const Value.absent(),
    this.linkState = const Value.absent(),
    this.linkReason = const Value.absent(),
    this.linkCheckedUtc = const Value.absent(),
    this.lastAccessibleUtc = const Value.absent(),
    this.probeGeneration = const Value.absent(),
    this.probeHttpStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RemoteUploadResultsCompanion.insert({
    required String id,
    required String attemptId,
    required String inputJson,
    required String targetJson,
    required String targetId,
    required String versionDigest,
    required int byteCount,
    required String policyKey,
    required String remoteId,
    required String directUrl,
    this.viewerUrl = const Value.absent(),
    required int confirmedUtc,
    required bool late,
    this.secretReference = const Value.absent(),
    this.managementAvailable = const Value.absent(),
    this.linkState = const Value.absent(),
    this.linkReason = const Value.absent(),
    this.linkCheckedUtc = const Value.absent(),
    this.lastAccessibleUtc = const Value.absent(),
    this.probeGeneration = const Value.absent(),
    this.probeHttpStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       attemptId = Value(attemptId),
       inputJson = Value(inputJson),
       targetJson = Value(targetJson),
       targetId = Value(targetId),
       versionDigest = Value(versionDigest),
       byteCount = Value(byteCount),
       policyKey = Value(policyKey),
       remoteId = Value(remoteId),
       directUrl = Value(directUrl),
       confirmedUtc = Value(confirmedUtc),
       late = Value(late);
  static Insertable<RemoteUploadResultRow> custom({
    Expression<String>? id,
    Expression<String>? attemptId,
    Expression<String>? inputJson,
    Expression<String>? targetJson,
    Expression<String>? targetId,
    Expression<String>? versionDigest,
    Expression<int>? byteCount,
    Expression<String>? policyKey,
    Expression<String>? remoteId,
    Expression<String>? directUrl,
    Expression<String>? viewerUrl,
    Expression<int>? confirmedUtc,
    Expression<bool>? late,
    Expression<String>? secretReference,
    Expression<bool>? managementAvailable,
    Expression<String>? linkState,
    Expression<String>? linkReason,
    Expression<int>? linkCheckedUtc,
    Expression<int>? lastAccessibleUtc,
    Expression<int>? probeGeneration,
    Expression<int>? probeHttpStatus,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (attemptId != null) 'attempt_id': attemptId,
      if (inputJson != null) 'input_json': inputJson,
      if (targetJson != null) 'target_json': targetJson,
      if (targetId != null) 'target_id': targetId,
      if (versionDigest != null) 'version_digest': versionDigest,
      if (byteCount != null) 'byte_count': byteCount,
      if (policyKey != null) 'policy_key': policyKey,
      if (remoteId != null) 'remote_id': remoteId,
      if (directUrl != null) 'direct_url': directUrl,
      if (viewerUrl != null) 'viewer_url': viewerUrl,
      if (confirmedUtc != null) 'confirmed_utc': confirmedUtc,
      if (late != null) 'late': late,
      if (secretReference != null) 'secret_reference': secretReference,
      if (managementAvailable != null)
        'management_available': managementAvailable,
      if (linkState != null) 'link_state': linkState,
      if (linkReason != null) 'link_reason': linkReason,
      if (linkCheckedUtc != null) 'link_checked_utc': linkCheckedUtc,
      if (lastAccessibleUtc != null) 'last_accessible_utc': lastAccessibleUtc,
      if (probeGeneration != null) 'probe_generation': probeGeneration,
      if (probeHttpStatus != null) 'probe_http_status': probeHttpStatus,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RemoteUploadResultsCompanion copyWith({
    Value<String>? id,
    Value<String>? attemptId,
    Value<String>? inputJson,
    Value<String>? targetJson,
    Value<String>? targetId,
    Value<String>? versionDigest,
    Value<int>? byteCount,
    Value<String>? policyKey,
    Value<String>? remoteId,
    Value<String>? directUrl,
    Value<String?>? viewerUrl,
    Value<int>? confirmedUtc,
    Value<bool>? late,
    Value<String?>? secretReference,
    Value<bool>? managementAvailable,
    Value<String>? linkState,
    Value<String?>? linkReason,
    Value<int?>? linkCheckedUtc,
    Value<int?>? lastAccessibleUtc,
    Value<int>? probeGeneration,
    Value<int?>? probeHttpStatus,
    Value<int>? rowid,
  }) {
    return RemoteUploadResultsCompanion(
      id: id ?? this.id,
      attemptId: attemptId ?? this.attemptId,
      inputJson: inputJson ?? this.inputJson,
      targetJson: targetJson ?? this.targetJson,
      targetId: targetId ?? this.targetId,
      versionDigest: versionDigest ?? this.versionDigest,
      byteCount: byteCount ?? this.byteCount,
      policyKey: policyKey ?? this.policyKey,
      remoteId: remoteId ?? this.remoteId,
      directUrl: directUrl ?? this.directUrl,
      viewerUrl: viewerUrl ?? this.viewerUrl,
      confirmedUtc: confirmedUtc ?? this.confirmedUtc,
      late: late ?? this.late,
      secretReference: secretReference ?? this.secretReference,
      managementAvailable: managementAvailable ?? this.managementAvailable,
      linkState: linkState ?? this.linkState,
      linkReason: linkReason ?? this.linkReason,
      linkCheckedUtc: linkCheckedUtc ?? this.linkCheckedUtc,
      lastAccessibleUtc: lastAccessibleUtc ?? this.lastAccessibleUtc,
      probeGeneration: probeGeneration ?? this.probeGeneration,
      probeHttpStatus: probeHttpStatus ?? this.probeHttpStatus,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (attemptId.present) {
      map['attempt_id'] = Variable<String>(attemptId.value);
    }
    if (inputJson.present) {
      map['input_json'] = Variable<String>(inputJson.value);
    }
    if (targetJson.present) {
      map['target_json'] = Variable<String>(targetJson.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (versionDigest.present) {
      map['version_digest'] = Variable<String>(versionDigest.value);
    }
    if (byteCount.present) {
      map['byte_count'] = Variable<int>(byteCount.value);
    }
    if (policyKey.present) {
      map['policy_key'] = Variable<String>(policyKey.value);
    }
    if (remoteId.present) {
      map['remote_id'] = Variable<String>(remoteId.value);
    }
    if (directUrl.present) {
      map['direct_url'] = Variable<String>(directUrl.value);
    }
    if (viewerUrl.present) {
      map['viewer_url'] = Variable<String>(viewerUrl.value);
    }
    if (confirmedUtc.present) {
      map['confirmed_utc'] = Variable<int>(confirmedUtc.value);
    }
    if (late.present) {
      map['late'] = Variable<bool>(late.value);
    }
    if (secretReference.present) {
      map['secret_reference'] = Variable<String>(secretReference.value);
    }
    if (managementAvailable.present) {
      map['management_available'] = Variable<bool>(managementAvailable.value);
    }
    if (linkState.present) {
      map['link_state'] = Variable<String>(linkState.value);
    }
    if (linkReason.present) {
      map['link_reason'] = Variable<String>(linkReason.value);
    }
    if (linkCheckedUtc.present) {
      map['link_checked_utc'] = Variable<int>(linkCheckedUtc.value);
    }
    if (lastAccessibleUtc.present) {
      map['last_accessible_utc'] = Variable<int>(lastAccessibleUtc.value);
    }
    if (probeGeneration.present) {
      map['probe_generation'] = Variable<int>(probeGeneration.value);
    }
    if (probeHttpStatus.present) {
      map['probe_http_status'] = Variable<int>(probeHttpStatus.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RemoteUploadResultsCompanion(')
          ..write('id: $id, ')
          ..write('attemptId: $attemptId, ')
          ..write('inputJson: $inputJson, ')
          ..write('targetJson: $targetJson, ')
          ..write('targetId: $targetId, ')
          ..write('versionDigest: $versionDigest, ')
          ..write('byteCount: $byteCount, ')
          ..write('policyKey: $policyKey, ')
          ..write('remoteId: $remoteId, ')
          ..write('directUrl: $directUrl, ')
          ..write('viewerUrl: $viewerUrl, ')
          ..write('confirmedUtc: $confirmedUtc, ')
          ..write('late: $late, ')
          ..write('secretReference: $secretReference, ')
          ..write('managementAvailable: $managementAvailable, ')
          ..write('linkState: $linkState, ')
          ..write('linkReason: $linkReason, ')
          ..write('linkCheckedUtc: $linkCheckedUtc, ')
          ..write('lastAccessibleUtc: $lastAccessibleUtc, ')
          ..write('probeGeneration: $probeGeneration, ')
          ..write('probeHttpStatus: $probeHttpStatus, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UploadResultOperationsTable extends UploadResultOperations
    with TableInfo<$UploadResultOperationsTable, UploadResultOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UploadResultOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptIdMeta = const VerificationMeta(
    'attemptId',
  );
  @override
  late final GeneratedColumn<String> attemptId = GeneratedColumn<String>(
    'attempt_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _proposalJsonMeta = const VerificationMeta(
    'proposalJson',
  );
  @override
  late final GeneratedColumn<String> proposalJson = GeneratedColumn<String>(
    'proposal_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _secretReferenceMeta = const VerificationMeta(
    'secretReference',
  );
  @override
  late final GeneratedColumn<String> secretReference = GeneratedColumn<String>(
    'secret_reference',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdUtcMeta = const VerificationMeta(
    'createdUtc',
  );
  @override
  late final GeneratedColumn<int> createdUtc = GeneratedColumn<int>(
    'created_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    attemptId,
    proposalJson,
    secretReference,
    createdUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'upload_result_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<UploadResultOperation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('attempt_id')) {
      context.handle(
        _attemptIdMeta,
        attemptId.isAcceptableOrUnknown(data['attempt_id']!, _attemptIdMeta),
      );
    } else if (isInserting) {
      context.missing(_attemptIdMeta);
    }
    if (data.containsKey('proposal_json')) {
      context.handle(
        _proposalJsonMeta,
        proposalJson.isAcceptableOrUnknown(
          data['proposal_json']!,
          _proposalJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_proposalJsonMeta);
    }
    if (data.containsKey('secret_reference')) {
      context.handle(
        _secretReferenceMeta,
        secretReference.isAcceptableOrUnknown(
          data['secret_reference']!,
          _secretReferenceMeta,
        ),
      );
    }
    if (data.containsKey('created_utc')) {
      context.handle(
        _createdUtcMeta,
        createdUtc.isAcceptableOrUnknown(data['created_utc']!, _createdUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_createdUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UploadResultOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UploadResultOperation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      attemptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attempt_id'],
      )!,
      proposalJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}proposal_json'],
      )!,
      secretReference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}secret_reference'],
      ),
      createdUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_utc'],
      )!,
    );
  }

  @override
  $UploadResultOperationsTable createAlias(String alias) {
    return $UploadResultOperationsTable(attachedDatabase, alias);
  }
}

class UploadResultOperation extends DataClass
    implements Insertable<UploadResultOperation> {
  final String id;
  final String attemptId;
  final String proposalJson;
  final String? secretReference;
  final int createdUtc;
  const UploadResultOperation({
    required this.id,
    required this.attemptId,
    required this.proposalJson,
    this.secretReference,
    required this.createdUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['attempt_id'] = Variable<String>(attemptId);
    map['proposal_json'] = Variable<String>(proposalJson);
    if (!nullToAbsent || secretReference != null) {
      map['secret_reference'] = Variable<String>(secretReference);
    }
    map['created_utc'] = Variable<int>(createdUtc);
    return map;
  }

  UploadResultOperationsCompanion toCompanion(bool nullToAbsent) {
    return UploadResultOperationsCompanion(
      id: Value(id),
      attemptId: Value(attemptId),
      proposalJson: Value(proposalJson),
      secretReference: secretReference == null && nullToAbsent
          ? const Value.absent()
          : Value(secretReference),
      createdUtc: Value(createdUtc),
    );
  }

  factory UploadResultOperation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UploadResultOperation(
      id: serializer.fromJson<String>(json['id']),
      attemptId: serializer.fromJson<String>(json['attemptId']),
      proposalJson: serializer.fromJson<String>(json['proposalJson']),
      secretReference: serializer.fromJson<String?>(json['secretReference']),
      createdUtc: serializer.fromJson<int>(json['createdUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'attemptId': serializer.toJson<String>(attemptId),
      'proposalJson': serializer.toJson<String>(proposalJson),
      'secretReference': serializer.toJson<String?>(secretReference),
      'createdUtc': serializer.toJson<int>(createdUtc),
    };
  }

  UploadResultOperation copyWith({
    String? id,
    String? attemptId,
    String? proposalJson,
    Value<String?> secretReference = const Value.absent(),
    int? createdUtc,
  }) => UploadResultOperation(
    id: id ?? this.id,
    attemptId: attemptId ?? this.attemptId,
    proposalJson: proposalJson ?? this.proposalJson,
    secretReference: secretReference.present
        ? secretReference.value
        : this.secretReference,
    createdUtc: createdUtc ?? this.createdUtc,
  );
  UploadResultOperation copyWithCompanion(
    UploadResultOperationsCompanion data,
  ) {
    return UploadResultOperation(
      id: data.id.present ? data.id.value : this.id,
      attemptId: data.attemptId.present ? data.attemptId.value : this.attemptId,
      proposalJson: data.proposalJson.present
          ? data.proposalJson.value
          : this.proposalJson,
      secretReference: data.secretReference.present
          ? data.secretReference.value
          : this.secretReference,
      createdUtc: data.createdUtc.present
          ? data.createdUtc.value
          : this.createdUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UploadResultOperation(')
          ..write('id: $id, ')
          ..write('attemptId: $attemptId, ')
          ..write('proposalJson: $proposalJson, ')
          ..write('secretReference: $secretReference, ')
          ..write('createdUtc: $createdUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, attemptId, proposalJson, secretReference, createdUtc);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UploadResultOperation &&
          other.id == this.id &&
          other.attemptId == this.attemptId &&
          other.proposalJson == this.proposalJson &&
          other.secretReference == this.secretReference &&
          other.createdUtc == this.createdUtc);
}

class UploadResultOperationsCompanion
    extends UpdateCompanion<UploadResultOperation> {
  final Value<String> id;
  final Value<String> attemptId;
  final Value<String> proposalJson;
  final Value<String?> secretReference;
  final Value<int> createdUtc;
  final Value<int> rowid;
  const UploadResultOperationsCompanion({
    this.id = const Value.absent(),
    this.attemptId = const Value.absent(),
    this.proposalJson = const Value.absent(),
    this.secretReference = const Value.absent(),
    this.createdUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UploadResultOperationsCompanion.insert({
    required String id,
    required String attemptId,
    required String proposalJson,
    this.secretReference = const Value.absent(),
    required int createdUtc,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       attemptId = Value(attemptId),
       proposalJson = Value(proposalJson),
       createdUtc = Value(createdUtc);
  static Insertable<UploadResultOperation> custom({
    Expression<String>? id,
    Expression<String>? attemptId,
    Expression<String>? proposalJson,
    Expression<String>? secretReference,
    Expression<int>? createdUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (attemptId != null) 'attempt_id': attemptId,
      if (proposalJson != null) 'proposal_json': proposalJson,
      if (secretReference != null) 'secret_reference': secretReference,
      if (createdUtc != null) 'created_utc': createdUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UploadResultOperationsCompanion copyWith({
    Value<String>? id,
    Value<String>? attemptId,
    Value<String>? proposalJson,
    Value<String?>? secretReference,
    Value<int>? createdUtc,
    Value<int>? rowid,
  }) {
    return UploadResultOperationsCompanion(
      id: id ?? this.id,
      attemptId: attemptId ?? this.attemptId,
      proposalJson: proposalJson ?? this.proposalJson,
      secretReference: secretReference ?? this.secretReference,
      createdUtc: createdUtc ?? this.createdUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (attemptId.present) {
      map['attempt_id'] = Variable<String>(attemptId.value);
    }
    if (proposalJson.present) {
      map['proposal_json'] = Variable<String>(proposalJson.value);
    }
    if (secretReference.present) {
      map['secret_reference'] = Variable<String>(secretReference.value);
    }
    if (createdUtc.present) {
      map['created_utc'] = Variable<int>(createdUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UploadResultOperationsCompanion(')
          ..write('id: $id, ')
          ..write('attemptId: $attemptId, ')
          ..write('proposalJson: $proposalJson, ')
          ..write('secretReference: $secretReference, ')
          ..write('createdUtc: $createdUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UploadEventsTable extends UploadEvents
    with TableInfo<$UploadEventsTable, UploadEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UploadEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES upload_publications (id)',
    ),
  );
  static const VerificationMeta _attemptIdMeta = const VerificationMeta(
    'attemptId',
  );
  @override
  late final GeneratedColumn<String> attemptId = GeneratedColumn<String>(
    'attempt_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdUtcMeta = const VerificationMeta(
    'createdUtc',
  );
  @override
  late final GeneratedColumn<int> createdUtc = GeneratedColumn<int>(
    'created_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    itemId,
    attemptId,
    state,
    reason,
    createdUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'upload_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<UploadEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('attempt_id')) {
      context.handle(
        _attemptIdMeta,
        attemptId.isAcceptableOrUnknown(data['attempt_id']!, _attemptIdMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    } else if (isInserting) {
      context.missing(_reasonMeta);
    }
    if (data.containsKey('created_utc')) {
      context.handle(
        _createdUtcMeta,
        createdUtc.isAcceptableOrUnknown(data['created_utc']!, _createdUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_createdUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UploadEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UploadEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      attemptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attempt_id'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      )!,
      createdUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_utc'],
      )!,
    );
  }

  @override
  $UploadEventsTable createAlias(String alias) {
    return $UploadEventsTable(attachedDatabase, alias);
  }
}

class UploadEvent extends DataClass implements Insertable<UploadEvent> {
  final String id;
  final String itemId;
  final String? attemptId;
  final String state;
  final String reason;
  final int createdUtc;
  const UploadEvent({
    required this.id,
    required this.itemId,
    this.attemptId,
    required this.state,
    required this.reason,
    required this.createdUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['item_id'] = Variable<String>(itemId);
    if (!nullToAbsent || attemptId != null) {
      map['attempt_id'] = Variable<String>(attemptId);
    }
    map['state'] = Variable<String>(state);
    map['reason'] = Variable<String>(reason);
    map['created_utc'] = Variable<int>(createdUtc);
    return map;
  }

  UploadEventsCompanion toCompanion(bool nullToAbsent) {
    return UploadEventsCompanion(
      id: Value(id),
      itemId: Value(itemId),
      attemptId: attemptId == null && nullToAbsent
          ? const Value.absent()
          : Value(attemptId),
      state: Value(state),
      reason: Value(reason),
      createdUtc: Value(createdUtc),
    );
  }

  factory UploadEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UploadEvent(
      id: serializer.fromJson<String>(json['id']),
      itemId: serializer.fromJson<String>(json['itemId']),
      attemptId: serializer.fromJson<String?>(json['attemptId']),
      state: serializer.fromJson<String>(json['state']),
      reason: serializer.fromJson<String>(json['reason']),
      createdUtc: serializer.fromJson<int>(json['createdUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'itemId': serializer.toJson<String>(itemId),
      'attemptId': serializer.toJson<String?>(attemptId),
      'state': serializer.toJson<String>(state),
      'reason': serializer.toJson<String>(reason),
      'createdUtc': serializer.toJson<int>(createdUtc),
    };
  }

  UploadEvent copyWith({
    String? id,
    String? itemId,
    Value<String?> attemptId = const Value.absent(),
    String? state,
    String? reason,
    int? createdUtc,
  }) => UploadEvent(
    id: id ?? this.id,
    itemId: itemId ?? this.itemId,
    attemptId: attemptId.present ? attemptId.value : this.attemptId,
    state: state ?? this.state,
    reason: reason ?? this.reason,
    createdUtc: createdUtc ?? this.createdUtc,
  );
  UploadEvent copyWithCompanion(UploadEventsCompanion data) {
    return UploadEvent(
      id: data.id.present ? data.id.value : this.id,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      attemptId: data.attemptId.present ? data.attemptId.value : this.attemptId,
      state: data.state.present ? data.state.value : this.state,
      reason: data.reason.present ? data.reason.value : this.reason,
      createdUtc: data.createdUtc.present
          ? data.createdUtc.value
          : this.createdUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UploadEvent(')
          ..write('id: $id, ')
          ..write('itemId: $itemId, ')
          ..write('attemptId: $attemptId, ')
          ..write('state: $state, ')
          ..write('reason: $reason, ')
          ..write('createdUtc: $createdUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, itemId, attemptId, state, reason, createdUtc);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UploadEvent &&
          other.id == this.id &&
          other.itemId == this.itemId &&
          other.attemptId == this.attemptId &&
          other.state == this.state &&
          other.reason == this.reason &&
          other.createdUtc == this.createdUtc);
}

class UploadEventsCompanion extends UpdateCompanion<UploadEvent> {
  final Value<String> id;
  final Value<String> itemId;
  final Value<String?> attemptId;
  final Value<String> state;
  final Value<String> reason;
  final Value<int> createdUtc;
  final Value<int> rowid;
  const UploadEventsCompanion({
    this.id = const Value.absent(),
    this.itemId = const Value.absent(),
    this.attemptId = const Value.absent(),
    this.state = const Value.absent(),
    this.reason = const Value.absent(),
    this.createdUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UploadEventsCompanion.insert({
    required String id,
    required String itemId,
    this.attemptId = const Value.absent(),
    required String state,
    required String reason,
    required int createdUtc,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       itemId = Value(itemId),
       state = Value(state),
       reason = Value(reason),
       createdUtc = Value(createdUtc);
  static Insertable<UploadEvent> custom({
    Expression<String>? id,
    Expression<String>? itemId,
    Expression<String>? attemptId,
    Expression<String>? state,
    Expression<String>? reason,
    Expression<int>? createdUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (itemId != null) 'item_id': itemId,
      if (attemptId != null) 'attempt_id': attemptId,
      if (state != null) 'state': state,
      if (reason != null) 'reason': reason,
      if (createdUtc != null) 'created_utc': createdUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UploadEventsCompanion copyWith({
    Value<String>? id,
    Value<String>? itemId,
    Value<String?>? attemptId,
    Value<String>? state,
    Value<String>? reason,
    Value<int>? createdUtc,
    Value<int>? rowid,
  }) {
    return UploadEventsCompanion(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      attemptId: attemptId ?? this.attemptId,
      state: state ?? this.state,
      reason: reason ?? this.reason,
      createdUtc: createdUtc ?? this.createdUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (attemptId.present) {
      map['attempt_id'] = Variable<String>(attemptId.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (createdUtc.present) {
      map['created_utc'] = Variable<int>(createdUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UploadEventsCompanion(')
          ..write('id: $id, ')
          ..write('itemId: $itemId, ')
          ..write('attemptId: $attemptId, ')
          ..write('state: $state, ')
          ..write('reason: $reason, ')
          ..write('createdUtc: $createdUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProviderTargetsTable extends ProviderTargets
    with TableInfo<$ProviderTargetsTable, ProviderTargetRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProviderTargetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serviceMeta = const VerificationMeta(
    'service',
  );
  @override
  late final GeneratedColumn<String> service = GeneratedColumn<String>(
    'service',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aliasMeta = const VerificationMeta('alias');
  @override
  late final GeneratedColumn<String> alias = GeneratedColumn<String>(
    'alias',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
  );
  static const VerificationMeta _selectedByDefaultMeta = const VerificationMeta(
    'selectedByDefault',
  );
  @override
  late final GeneratedColumn<bool> selectedByDefault = GeneratedColumn<bool>(
    'selected_by_default',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("selected_by_default" IN (0, 1))',
    ),
  );
  static const VerificationMeta _anonymousMeta = const VerificationMeta(
    'anonymous',
  );
  @override
  late final GeneratedColumn<bool> anonymous = GeneratedColumn<bool>(
    'anonymous',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("anonymous" IN (0, 1))',
    ),
  );
  static const VerificationMeta _healthMeta = const VerificationMeta('health');
  @override
  late final GeneratedColumn<String> health = GeneratedColumn<String>(
    'health',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _secretReferenceMeta = const VerificationMeta(
    'secretReference',
  );
  @override
  late final GeneratedColumn<String> secretReference = GeneratedColumn<String>(
    'secret_reference',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _removedMeta = const VerificationMeta(
    'removed',
  );
  @override
  late final GeneratedColumn<bool> removed = GeneratedColumn<bool>(
    'removed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("removed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _generationMeta = const VerificationMeta(
    'generation',
  );
  @override
  late final GeneratedColumn<int> generation = GeneratedColumn<int>(
    'generation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _createdUtcMeta = const VerificationMeta(
    'createdUtc',
  );
  @override
  late final GeneratedColumn<int> createdUtc = GeneratedColumn<int>(
    'created_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modifiedUtcMeta = const VerificationMeta(
    'modifiedUtc',
  );
  @override
  late final GeneratedColumn<int> modifiedUtc = GeneratedColumn<int>(
    'modified_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    service,
    alias,
    enabled,
    selectedByDefault,
    anonymous,
    health,
    secretReference,
    removed,
    generation,
    createdUtc,
    modifiedUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'provider_targets';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProviderTargetRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('service')) {
      context.handle(
        _serviceMeta,
        service.isAcceptableOrUnknown(data['service']!, _serviceMeta),
      );
    } else if (isInserting) {
      context.missing(_serviceMeta);
    }
    if (data.containsKey('alias')) {
      context.handle(
        _aliasMeta,
        alias.isAcceptableOrUnknown(data['alias']!, _aliasMeta),
      );
    } else if (isInserting) {
      context.missing(_aliasMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    } else if (isInserting) {
      context.missing(_enabledMeta);
    }
    if (data.containsKey('selected_by_default')) {
      context.handle(
        _selectedByDefaultMeta,
        selectedByDefault.isAcceptableOrUnknown(
          data['selected_by_default']!,
          _selectedByDefaultMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_selectedByDefaultMeta);
    }
    if (data.containsKey('anonymous')) {
      context.handle(
        _anonymousMeta,
        anonymous.isAcceptableOrUnknown(data['anonymous']!, _anonymousMeta),
      );
    } else if (isInserting) {
      context.missing(_anonymousMeta);
    }
    if (data.containsKey('health')) {
      context.handle(
        _healthMeta,
        health.isAcceptableOrUnknown(data['health']!, _healthMeta),
      );
    } else if (isInserting) {
      context.missing(_healthMeta);
    }
    if (data.containsKey('secret_reference')) {
      context.handle(
        _secretReferenceMeta,
        secretReference.isAcceptableOrUnknown(
          data['secret_reference']!,
          _secretReferenceMeta,
        ),
      );
    }
    if (data.containsKey('removed')) {
      context.handle(
        _removedMeta,
        removed.isAcceptableOrUnknown(data['removed']!, _removedMeta),
      );
    }
    if (data.containsKey('generation')) {
      context.handle(
        _generationMeta,
        generation.isAcceptableOrUnknown(data['generation']!, _generationMeta),
      );
    }
    if (data.containsKey('created_utc')) {
      context.handle(
        _createdUtcMeta,
        createdUtc.isAcceptableOrUnknown(data['created_utc']!, _createdUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_createdUtcMeta);
    }
    if (data.containsKey('modified_utc')) {
      context.handle(
        _modifiedUtcMeta,
        modifiedUtc.isAcceptableOrUnknown(
          data['modified_utc']!,
          _modifiedUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_modifiedUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProviderTargetRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProviderTargetRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      service: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}service'],
      )!,
      alias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}alias'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      selectedByDefault: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}selected_by_default'],
      )!,
      anonymous: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}anonymous'],
      )!,
      health: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}health'],
      )!,
      secretReference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}secret_reference'],
      ),
      removed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}removed'],
      )!,
      generation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}generation'],
      )!,
      createdUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_utc'],
      )!,
      modifiedUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}modified_utc'],
      )!,
    );
  }

  @override
  $ProviderTargetsTable createAlias(String alias) {
    return $ProviderTargetsTable(attachedDatabase, alias);
  }
}

class ProviderTargetRow extends DataClass
    implements Insertable<ProviderTargetRow> {
  final String id;
  final String service;
  final String alias;
  final bool enabled;
  final bool selectedByDefault;
  final bool anonymous;
  final String health;
  final String? secretReference;
  final bool removed;
  final int generation;
  final int createdUtc;
  final int modifiedUtc;
  const ProviderTargetRow({
    required this.id,
    required this.service,
    required this.alias,
    required this.enabled,
    required this.selectedByDefault,
    required this.anonymous,
    required this.health,
    this.secretReference,
    required this.removed,
    required this.generation,
    required this.createdUtc,
    required this.modifiedUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['service'] = Variable<String>(service);
    map['alias'] = Variable<String>(alias);
    map['enabled'] = Variable<bool>(enabled);
    map['selected_by_default'] = Variable<bool>(selectedByDefault);
    map['anonymous'] = Variable<bool>(anonymous);
    map['health'] = Variable<String>(health);
    if (!nullToAbsent || secretReference != null) {
      map['secret_reference'] = Variable<String>(secretReference);
    }
    map['removed'] = Variable<bool>(removed);
    map['generation'] = Variable<int>(generation);
    map['created_utc'] = Variable<int>(createdUtc);
    map['modified_utc'] = Variable<int>(modifiedUtc);
    return map;
  }

  ProviderTargetsCompanion toCompanion(bool nullToAbsent) {
    return ProviderTargetsCompanion(
      id: Value(id),
      service: Value(service),
      alias: Value(alias),
      enabled: Value(enabled),
      selectedByDefault: Value(selectedByDefault),
      anonymous: Value(anonymous),
      health: Value(health),
      secretReference: secretReference == null && nullToAbsent
          ? const Value.absent()
          : Value(secretReference),
      removed: Value(removed),
      generation: Value(generation),
      createdUtc: Value(createdUtc),
      modifiedUtc: Value(modifiedUtc),
    );
  }

  factory ProviderTargetRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProviderTargetRow(
      id: serializer.fromJson<String>(json['id']),
      service: serializer.fromJson<String>(json['service']),
      alias: serializer.fromJson<String>(json['alias']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      selectedByDefault: serializer.fromJson<bool>(json['selectedByDefault']),
      anonymous: serializer.fromJson<bool>(json['anonymous']),
      health: serializer.fromJson<String>(json['health']),
      secretReference: serializer.fromJson<String?>(json['secretReference']),
      removed: serializer.fromJson<bool>(json['removed']),
      generation: serializer.fromJson<int>(json['generation']),
      createdUtc: serializer.fromJson<int>(json['createdUtc']),
      modifiedUtc: serializer.fromJson<int>(json['modifiedUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'service': serializer.toJson<String>(service),
      'alias': serializer.toJson<String>(alias),
      'enabled': serializer.toJson<bool>(enabled),
      'selectedByDefault': serializer.toJson<bool>(selectedByDefault),
      'anonymous': serializer.toJson<bool>(anonymous),
      'health': serializer.toJson<String>(health),
      'secretReference': serializer.toJson<String?>(secretReference),
      'removed': serializer.toJson<bool>(removed),
      'generation': serializer.toJson<int>(generation),
      'createdUtc': serializer.toJson<int>(createdUtc),
      'modifiedUtc': serializer.toJson<int>(modifiedUtc),
    };
  }

  ProviderTargetRow copyWith({
    String? id,
    String? service,
    String? alias,
    bool? enabled,
    bool? selectedByDefault,
    bool? anonymous,
    String? health,
    Value<String?> secretReference = const Value.absent(),
    bool? removed,
    int? generation,
    int? createdUtc,
    int? modifiedUtc,
  }) => ProviderTargetRow(
    id: id ?? this.id,
    service: service ?? this.service,
    alias: alias ?? this.alias,
    enabled: enabled ?? this.enabled,
    selectedByDefault: selectedByDefault ?? this.selectedByDefault,
    anonymous: anonymous ?? this.anonymous,
    health: health ?? this.health,
    secretReference: secretReference.present
        ? secretReference.value
        : this.secretReference,
    removed: removed ?? this.removed,
    generation: generation ?? this.generation,
    createdUtc: createdUtc ?? this.createdUtc,
    modifiedUtc: modifiedUtc ?? this.modifiedUtc,
  );
  ProviderTargetRow copyWithCompanion(ProviderTargetsCompanion data) {
    return ProviderTargetRow(
      id: data.id.present ? data.id.value : this.id,
      service: data.service.present ? data.service.value : this.service,
      alias: data.alias.present ? data.alias.value : this.alias,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      selectedByDefault: data.selectedByDefault.present
          ? data.selectedByDefault.value
          : this.selectedByDefault,
      anonymous: data.anonymous.present ? data.anonymous.value : this.anonymous,
      health: data.health.present ? data.health.value : this.health,
      secretReference: data.secretReference.present
          ? data.secretReference.value
          : this.secretReference,
      removed: data.removed.present ? data.removed.value : this.removed,
      generation: data.generation.present
          ? data.generation.value
          : this.generation,
      createdUtc: data.createdUtc.present
          ? data.createdUtc.value
          : this.createdUtc,
      modifiedUtc: data.modifiedUtc.present
          ? data.modifiedUtc.value
          : this.modifiedUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProviderTargetRow(')
          ..write('id: $id, ')
          ..write('service: $service, ')
          ..write('alias: $alias, ')
          ..write('enabled: $enabled, ')
          ..write('selectedByDefault: $selectedByDefault, ')
          ..write('anonymous: $anonymous, ')
          ..write('health: $health, ')
          ..write('secretReference: $secretReference, ')
          ..write('removed: $removed, ')
          ..write('generation: $generation, ')
          ..write('createdUtc: $createdUtc, ')
          ..write('modifiedUtc: $modifiedUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    service,
    alias,
    enabled,
    selectedByDefault,
    anonymous,
    health,
    secretReference,
    removed,
    generation,
    createdUtc,
    modifiedUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProviderTargetRow &&
          other.id == this.id &&
          other.service == this.service &&
          other.alias == this.alias &&
          other.enabled == this.enabled &&
          other.selectedByDefault == this.selectedByDefault &&
          other.anonymous == this.anonymous &&
          other.health == this.health &&
          other.secretReference == this.secretReference &&
          other.removed == this.removed &&
          other.generation == this.generation &&
          other.createdUtc == this.createdUtc &&
          other.modifiedUtc == this.modifiedUtc);
}

class ProviderTargetsCompanion extends UpdateCompanion<ProviderTargetRow> {
  final Value<String> id;
  final Value<String> service;
  final Value<String> alias;
  final Value<bool> enabled;
  final Value<bool> selectedByDefault;
  final Value<bool> anonymous;
  final Value<String> health;
  final Value<String?> secretReference;
  final Value<bool> removed;
  final Value<int> generation;
  final Value<int> createdUtc;
  final Value<int> modifiedUtc;
  final Value<int> rowid;
  const ProviderTargetsCompanion({
    this.id = const Value.absent(),
    this.service = const Value.absent(),
    this.alias = const Value.absent(),
    this.enabled = const Value.absent(),
    this.selectedByDefault = const Value.absent(),
    this.anonymous = const Value.absent(),
    this.health = const Value.absent(),
    this.secretReference = const Value.absent(),
    this.removed = const Value.absent(),
    this.generation = const Value.absent(),
    this.createdUtc = const Value.absent(),
    this.modifiedUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProviderTargetsCompanion.insert({
    required String id,
    required String service,
    required String alias,
    required bool enabled,
    required bool selectedByDefault,
    required bool anonymous,
    required String health,
    this.secretReference = const Value.absent(),
    this.removed = const Value.absent(),
    this.generation = const Value.absent(),
    required int createdUtc,
    required int modifiedUtc,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       service = Value(service),
       alias = Value(alias),
       enabled = Value(enabled),
       selectedByDefault = Value(selectedByDefault),
       anonymous = Value(anonymous),
       health = Value(health),
       createdUtc = Value(createdUtc),
       modifiedUtc = Value(modifiedUtc);
  static Insertable<ProviderTargetRow> custom({
    Expression<String>? id,
    Expression<String>? service,
    Expression<String>? alias,
    Expression<bool>? enabled,
    Expression<bool>? selectedByDefault,
    Expression<bool>? anonymous,
    Expression<String>? health,
    Expression<String>? secretReference,
    Expression<bool>? removed,
    Expression<int>? generation,
    Expression<int>? createdUtc,
    Expression<int>? modifiedUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (service != null) 'service': service,
      if (alias != null) 'alias': alias,
      if (enabled != null) 'enabled': enabled,
      if (selectedByDefault != null) 'selected_by_default': selectedByDefault,
      if (anonymous != null) 'anonymous': anonymous,
      if (health != null) 'health': health,
      if (secretReference != null) 'secret_reference': secretReference,
      if (removed != null) 'removed': removed,
      if (generation != null) 'generation': generation,
      if (createdUtc != null) 'created_utc': createdUtc,
      if (modifiedUtc != null) 'modified_utc': modifiedUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProviderTargetsCompanion copyWith({
    Value<String>? id,
    Value<String>? service,
    Value<String>? alias,
    Value<bool>? enabled,
    Value<bool>? selectedByDefault,
    Value<bool>? anonymous,
    Value<String>? health,
    Value<String?>? secretReference,
    Value<bool>? removed,
    Value<int>? generation,
    Value<int>? createdUtc,
    Value<int>? modifiedUtc,
    Value<int>? rowid,
  }) {
    return ProviderTargetsCompanion(
      id: id ?? this.id,
      service: service ?? this.service,
      alias: alias ?? this.alias,
      enabled: enabled ?? this.enabled,
      selectedByDefault: selectedByDefault ?? this.selectedByDefault,
      anonymous: anonymous ?? this.anonymous,
      health: health ?? this.health,
      secretReference: secretReference ?? this.secretReference,
      removed: removed ?? this.removed,
      generation: generation ?? this.generation,
      createdUtc: createdUtc ?? this.createdUtc,
      modifiedUtc: modifiedUtc ?? this.modifiedUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (service.present) {
      map['service'] = Variable<String>(service.value);
    }
    if (alias.present) {
      map['alias'] = Variable<String>(alias.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (selectedByDefault.present) {
      map['selected_by_default'] = Variable<bool>(selectedByDefault.value);
    }
    if (anonymous.present) {
      map['anonymous'] = Variable<bool>(anonymous.value);
    }
    if (health.present) {
      map['health'] = Variable<String>(health.value);
    }
    if (secretReference.present) {
      map['secret_reference'] = Variable<String>(secretReference.value);
    }
    if (removed.present) {
      map['removed'] = Variable<bool>(removed.value);
    }
    if (generation.present) {
      map['generation'] = Variable<int>(generation.value);
    }
    if (createdUtc.present) {
      map['created_utc'] = Variable<int>(createdUtc.value);
    }
    if (modifiedUtc.present) {
      map['modified_utc'] = Variable<int>(modifiedUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProviderTargetsCompanion(')
          ..write('id: $id, ')
          ..write('service: $service, ')
          ..write('alias: $alias, ')
          ..write('enabled: $enabled, ')
          ..write('selectedByDefault: $selectedByDefault, ')
          ..write('anonymous: $anonymous, ')
          ..write('health: $health, ')
          ..write('secretReference: $secretReference, ')
          ..write('removed: $removed, ')
          ..write('generation: $generation, ')
          ..write('createdUtc: $createdUtc, ')
          ..write('modifiedUtc: $modifiedUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CredentialOperationsTable extends CredentialOperations
    with TableInfo<$CredentialOperationsTable, CredentialOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CredentialOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES provider_targets (id)',
    ),
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _proposalJsonMeta = const VerificationMeta(
    'proposalJson',
  );
  @override
  late final GeneratedColumn<String> proposalJson = GeneratedColumn<String>(
    'proposal_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _newReferenceMeta = const VerificationMeta(
    'newReference',
  );
  @override
  late final GeneratedColumn<String> newReference = GeneratedColumn<String>(
    'new_reference',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _oldReferenceMeta = const VerificationMeta(
    'oldReference',
  );
  @override
  late final GeneratedColumn<String> oldReference = GeneratedColumn<String>(
    'old_reference',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdUtcMeta = const VerificationMeta(
    'createdUtc',
  );
  @override
  late final GeneratedColumn<int> createdUtc = GeneratedColumn<int>(
    'created_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    targetId,
    action,
    proposalJson,
    newReference,
    oldReference,
    createdUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'credential_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<CredentialOperation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_targetIdMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('proposal_json')) {
      context.handle(
        _proposalJsonMeta,
        proposalJson.isAcceptableOrUnknown(
          data['proposal_json']!,
          _proposalJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_proposalJsonMeta);
    }
    if (data.containsKey('new_reference')) {
      context.handle(
        _newReferenceMeta,
        newReference.isAcceptableOrUnknown(
          data['new_reference']!,
          _newReferenceMeta,
        ),
      );
    }
    if (data.containsKey('old_reference')) {
      context.handle(
        _oldReferenceMeta,
        oldReference.isAcceptableOrUnknown(
          data['old_reference']!,
          _oldReferenceMeta,
        ),
      );
    }
    if (data.containsKey('created_utc')) {
      context.handle(
        _createdUtcMeta,
        createdUtc.isAcceptableOrUnknown(data['created_utc']!, _createdUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_createdUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CredentialOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CredentialOperation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      targetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_id'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      proposalJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}proposal_json'],
      )!,
      newReference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}new_reference'],
      ),
      oldReference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}old_reference'],
      ),
      createdUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_utc'],
      )!,
    );
  }

  @override
  $CredentialOperationsTable createAlias(String alias) {
    return $CredentialOperationsTable(attachedDatabase, alias);
  }
}

class CredentialOperation extends DataClass
    implements Insertable<CredentialOperation> {
  final String id;
  final String targetId;
  final String action;
  final String proposalJson;
  final String? newReference;
  final String? oldReference;
  final int createdUtc;
  const CredentialOperation({
    required this.id,
    required this.targetId,
    required this.action,
    required this.proposalJson,
    this.newReference,
    this.oldReference,
    required this.createdUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['target_id'] = Variable<String>(targetId);
    map['action'] = Variable<String>(action);
    map['proposal_json'] = Variable<String>(proposalJson);
    if (!nullToAbsent || newReference != null) {
      map['new_reference'] = Variable<String>(newReference);
    }
    if (!nullToAbsent || oldReference != null) {
      map['old_reference'] = Variable<String>(oldReference);
    }
    map['created_utc'] = Variable<int>(createdUtc);
    return map;
  }

  CredentialOperationsCompanion toCompanion(bool nullToAbsent) {
    return CredentialOperationsCompanion(
      id: Value(id),
      targetId: Value(targetId),
      action: Value(action),
      proposalJson: Value(proposalJson),
      newReference: newReference == null && nullToAbsent
          ? const Value.absent()
          : Value(newReference),
      oldReference: oldReference == null && nullToAbsent
          ? const Value.absent()
          : Value(oldReference),
      createdUtc: Value(createdUtc),
    );
  }

  factory CredentialOperation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CredentialOperation(
      id: serializer.fromJson<String>(json['id']),
      targetId: serializer.fromJson<String>(json['targetId']),
      action: serializer.fromJson<String>(json['action']),
      proposalJson: serializer.fromJson<String>(json['proposalJson']),
      newReference: serializer.fromJson<String?>(json['newReference']),
      oldReference: serializer.fromJson<String?>(json['oldReference']),
      createdUtc: serializer.fromJson<int>(json['createdUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'targetId': serializer.toJson<String>(targetId),
      'action': serializer.toJson<String>(action),
      'proposalJson': serializer.toJson<String>(proposalJson),
      'newReference': serializer.toJson<String?>(newReference),
      'oldReference': serializer.toJson<String?>(oldReference),
      'createdUtc': serializer.toJson<int>(createdUtc),
    };
  }

  CredentialOperation copyWith({
    String? id,
    String? targetId,
    String? action,
    String? proposalJson,
    Value<String?> newReference = const Value.absent(),
    Value<String?> oldReference = const Value.absent(),
    int? createdUtc,
  }) => CredentialOperation(
    id: id ?? this.id,
    targetId: targetId ?? this.targetId,
    action: action ?? this.action,
    proposalJson: proposalJson ?? this.proposalJson,
    newReference: newReference.present ? newReference.value : this.newReference,
    oldReference: oldReference.present ? oldReference.value : this.oldReference,
    createdUtc: createdUtc ?? this.createdUtc,
  );
  CredentialOperation copyWithCompanion(CredentialOperationsCompanion data) {
    return CredentialOperation(
      id: data.id.present ? data.id.value : this.id,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      action: data.action.present ? data.action.value : this.action,
      proposalJson: data.proposalJson.present
          ? data.proposalJson.value
          : this.proposalJson,
      newReference: data.newReference.present
          ? data.newReference.value
          : this.newReference,
      oldReference: data.oldReference.present
          ? data.oldReference.value
          : this.oldReference,
      createdUtc: data.createdUtc.present
          ? data.createdUtc.value
          : this.createdUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CredentialOperation(')
          ..write('id: $id, ')
          ..write('targetId: $targetId, ')
          ..write('action: $action, ')
          ..write('proposalJson: $proposalJson, ')
          ..write('newReference: $newReference, ')
          ..write('oldReference: $oldReference, ')
          ..write('createdUtc: $createdUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    targetId,
    action,
    proposalJson,
    newReference,
    oldReference,
    createdUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CredentialOperation &&
          other.id == this.id &&
          other.targetId == this.targetId &&
          other.action == this.action &&
          other.proposalJson == this.proposalJson &&
          other.newReference == this.newReference &&
          other.oldReference == this.oldReference &&
          other.createdUtc == this.createdUtc);
}

class CredentialOperationsCompanion
    extends UpdateCompanion<CredentialOperation> {
  final Value<String> id;
  final Value<String> targetId;
  final Value<String> action;
  final Value<String> proposalJson;
  final Value<String?> newReference;
  final Value<String?> oldReference;
  final Value<int> createdUtc;
  final Value<int> rowid;
  const CredentialOperationsCompanion({
    this.id = const Value.absent(),
    this.targetId = const Value.absent(),
    this.action = const Value.absent(),
    this.proposalJson = const Value.absent(),
    this.newReference = const Value.absent(),
    this.oldReference = const Value.absent(),
    this.createdUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CredentialOperationsCompanion.insert({
    required String id,
    required String targetId,
    required String action,
    required String proposalJson,
    this.newReference = const Value.absent(),
    this.oldReference = const Value.absent(),
    required int createdUtc,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       targetId = Value(targetId),
       action = Value(action),
       proposalJson = Value(proposalJson),
       createdUtc = Value(createdUtc);
  static Insertable<CredentialOperation> custom({
    Expression<String>? id,
    Expression<String>? targetId,
    Expression<String>? action,
    Expression<String>? proposalJson,
    Expression<String>? newReference,
    Expression<String>? oldReference,
    Expression<int>? createdUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (targetId != null) 'target_id': targetId,
      if (action != null) 'action': action,
      if (proposalJson != null) 'proposal_json': proposalJson,
      if (newReference != null) 'new_reference': newReference,
      if (oldReference != null) 'old_reference': oldReference,
      if (createdUtc != null) 'created_utc': createdUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CredentialOperationsCompanion copyWith({
    Value<String>? id,
    Value<String>? targetId,
    Value<String>? action,
    Value<String>? proposalJson,
    Value<String?>? newReference,
    Value<String?>? oldReference,
    Value<int>? createdUtc,
    Value<int>? rowid,
  }) {
    return CredentialOperationsCompanion(
      id: id ?? this.id,
      targetId: targetId ?? this.targetId,
      action: action ?? this.action,
      proposalJson: proposalJson ?? this.proposalJson,
      newReference: newReference ?? this.newReference,
      oldReference: oldReference ?? this.oldReference,
      createdUtc: createdUtc ?? this.createdUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (proposalJson.present) {
      map['proposal_json'] = Variable<String>(proposalJson.value);
    }
    if (newReference.present) {
      map['new_reference'] = Variable<String>(newReference.value);
    }
    if (oldReference.present) {
      map['old_reference'] = Variable<String>(oldReference.value);
    }
    if (createdUtc.present) {
      map['created_utc'] = Variable<int>(createdUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CredentialOperationsCompanion(')
          ..write('id: $id, ')
          ..write('targetId: $targetId, ')
          ..write('action: $action, ')
          ..write('proposalJson: $proposalJson, ')
          ..write('newReference: $newReference, ')
          ..write('oldReference: $oldReference, ')
          ..write('createdUtc: $createdUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VersionsTable extends Versions
    with TableInfo<$VersionsTable, VersionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VersionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _digestMeta = const VerificationMeta('digest');
  @override
  late final GeneratedColumn<String> digest = GeneratedColumn<String>(
    'digest',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _byteCountMeta = const VerificationMeta(
    'byteCount',
  );
  @override
  late final GeneratedColumn<int> byteCount = GeneratedColumn<int>(
    'byte_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  @override
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
    'format',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _frameCountMeta = const VerificationMeta(
    'frameCount',
  );
  @override
  late final GeneratedColumn<int> frameCount = GeneratedColumn<int>(
    'frame_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orientationMeta = const VerificationMeta(
    'orientation',
  );
  @override
  late final GeneratedColumn<int> orientation = GeneratedColumn<int>(
    'orientation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    digest,
    byteCount,
    format,
    width,
    height,
    frameCount,
    orientation,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'versions';
  @override
  VerificationContext validateIntegrity(
    Insertable<VersionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('digest')) {
      context.handle(
        _digestMeta,
        digest.isAcceptableOrUnknown(data['digest']!, _digestMeta),
      );
    } else if (isInserting) {
      context.missing(_digestMeta);
    }
    if (data.containsKey('byte_count')) {
      context.handle(
        _byteCountMeta,
        byteCount.isAcceptableOrUnknown(data['byte_count']!, _byteCountMeta),
      );
    } else if (isInserting) {
      context.missing(_byteCountMeta);
    }
    if (data.containsKey('format')) {
      context.handle(
        _formatMeta,
        format.isAcceptableOrUnknown(data['format']!, _formatMeta),
      );
    } else if (isInserting) {
      context.missing(_formatMeta);
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    } else if (isInserting) {
      context.missing(_widthMeta);
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    } else if (isInserting) {
      context.missing(_heightMeta);
    }
    if (data.containsKey('frame_count')) {
      context.handle(
        _frameCountMeta,
        frameCount.isAcceptableOrUnknown(data['frame_count']!, _frameCountMeta),
      );
    } else if (isInserting) {
      context.missing(_frameCountMeta);
    }
    if (data.containsKey('orientation')) {
      context.handle(
        _orientationMeta,
        orientation.isAcceptableOrUnknown(
          data['orientation']!,
          _orientationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_orientationMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {digest, byteCount},
  ];
  @override
  VersionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VersionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      digest: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}digest'],
      )!,
      byteCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_count'],
      )!,
      format: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}format'],
      )!,
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      )!,
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      )!,
      frameCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}frame_count'],
      )!,
      orientation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}orientation'],
      )!,
    );
  }

  @override
  $VersionsTable createAlias(String alias) {
    return $VersionsTable(attachedDatabase, alias);
  }
}

class VersionRow extends DataClass implements Insertable<VersionRow> {
  final String id;
  final String digest;
  final int byteCount;
  final String format;
  final int width;
  final int height;
  final int frameCount;
  final int orientation;
  const VersionRow({
    required this.id,
    required this.digest,
    required this.byteCount,
    required this.format,
    required this.width,
    required this.height,
    required this.frameCount,
    required this.orientation,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['digest'] = Variable<String>(digest);
    map['byte_count'] = Variable<int>(byteCount);
    map['format'] = Variable<String>(format);
    map['width'] = Variable<int>(width);
    map['height'] = Variable<int>(height);
    map['frame_count'] = Variable<int>(frameCount);
    map['orientation'] = Variable<int>(orientation);
    return map;
  }

  VersionsCompanion toCompanion(bool nullToAbsent) {
    return VersionsCompanion(
      id: Value(id),
      digest: Value(digest),
      byteCount: Value(byteCount),
      format: Value(format),
      width: Value(width),
      height: Value(height),
      frameCount: Value(frameCount),
      orientation: Value(orientation),
    );
  }

  factory VersionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VersionRow(
      id: serializer.fromJson<String>(json['id']),
      digest: serializer.fromJson<String>(json['digest']),
      byteCount: serializer.fromJson<int>(json['byteCount']),
      format: serializer.fromJson<String>(json['format']),
      width: serializer.fromJson<int>(json['width']),
      height: serializer.fromJson<int>(json['height']),
      frameCount: serializer.fromJson<int>(json['frameCount']),
      orientation: serializer.fromJson<int>(json['orientation']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'digest': serializer.toJson<String>(digest),
      'byteCount': serializer.toJson<int>(byteCount),
      'format': serializer.toJson<String>(format),
      'width': serializer.toJson<int>(width),
      'height': serializer.toJson<int>(height),
      'frameCount': serializer.toJson<int>(frameCount),
      'orientation': serializer.toJson<int>(orientation),
    };
  }

  VersionRow copyWith({
    String? id,
    String? digest,
    int? byteCount,
    String? format,
    int? width,
    int? height,
    int? frameCount,
    int? orientation,
  }) => VersionRow(
    id: id ?? this.id,
    digest: digest ?? this.digest,
    byteCount: byteCount ?? this.byteCount,
    format: format ?? this.format,
    width: width ?? this.width,
    height: height ?? this.height,
    frameCount: frameCount ?? this.frameCount,
    orientation: orientation ?? this.orientation,
  );
  VersionRow copyWithCompanion(VersionsCompanion data) {
    return VersionRow(
      id: data.id.present ? data.id.value : this.id,
      digest: data.digest.present ? data.digest.value : this.digest,
      byteCount: data.byteCount.present ? data.byteCount.value : this.byteCount,
      format: data.format.present ? data.format.value : this.format,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      frameCount: data.frameCount.present
          ? data.frameCount.value
          : this.frameCount,
      orientation: data.orientation.present
          ? data.orientation.value
          : this.orientation,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VersionRow(')
          ..write('id: $id, ')
          ..write('digest: $digest, ')
          ..write('byteCount: $byteCount, ')
          ..write('format: $format, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('frameCount: $frameCount, ')
          ..write('orientation: $orientation')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    digest,
    byteCount,
    format,
    width,
    height,
    frameCount,
    orientation,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VersionRow &&
          other.id == this.id &&
          other.digest == this.digest &&
          other.byteCount == this.byteCount &&
          other.format == this.format &&
          other.width == this.width &&
          other.height == this.height &&
          other.frameCount == this.frameCount &&
          other.orientation == this.orientation);
}

class VersionsCompanion extends UpdateCompanion<VersionRow> {
  final Value<String> id;
  final Value<String> digest;
  final Value<int> byteCount;
  final Value<String> format;
  final Value<int> width;
  final Value<int> height;
  final Value<int> frameCount;
  final Value<int> orientation;
  final Value<int> rowid;
  const VersionsCompanion({
    this.id = const Value.absent(),
    this.digest = const Value.absent(),
    this.byteCount = const Value.absent(),
    this.format = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.frameCount = const Value.absent(),
    this.orientation = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VersionsCompanion.insert({
    required String id,
    required String digest,
    required int byteCount,
    required String format,
    required int width,
    required int height,
    required int frameCount,
    required int orientation,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       digest = Value(digest),
       byteCount = Value(byteCount),
       format = Value(format),
       width = Value(width),
       height = Value(height),
       frameCount = Value(frameCount),
       orientation = Value(orientation);
  static Insertable<VersionRow> custom({
    Expression<String>? id,
    Expression<String>? digest,
    Expression<int>? byteCount,
    Expression<String>? format,
    Expression<int>? width,
    Expression<int>? height,
    Expression<int>? frameCount,
    Expression<int>? orientation,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (digest != null) 'digest': digest,
      if (byteCount != null) 'byte_count': byteCount,
      if (format != null) 'format': format,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (frameCount != null) 'frame_count': frameCount,
      if (orientation != null) 'orientation': orientation,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VersionsCompanion copyWith({
    Value<String>? id,
    Value<String>? digest,
    Value<int>? byteCount,
    Value<String>? format,
    Value<int>? width,
    Value<int>? height,
    Value<int>? frameCount,
    Value<int>? orientation,
    Value<int>? rowid,
  }) {
    return VersionsCompanion(
      id: id ?? this.id,
      digest: digest ?? this.digest,
      byteCount: byteCount ?? this.byteCount,
      format: format ?? this.format,
      width: width ?? this.width,
      height: height ?? this.height,
      frameCount: frameCount ?? this.frameCount,
      orientation: orientation ?? this.orientation,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (digest.present) {
      map['digest'] = Variable<String>(digest.value);
    }
    if (byteCount.present) {
      map['byte_count'] = Variable<int>(byteCount.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (frameCount.present) {
      map['frame_count'] = Variable<int>(frameCount.value);
    }
    if (orientation.present) {
      map['orientation'] = Variable<int>(orientation.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VersionsCompanion(')
          ..write('id: $id, ')
          ..write('digest: $digest, ')
          ..write('byteCount: $byteCount, ')
          ..write('format: $format, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('frameCount: $frameCount, ')
          ..write('orientation: $orientation, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, CategoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameKeyMeta = const VerificationMeta(
    'nameKey',
  );
  @override
  late final GeneratedColumn<String> nameKey = GeneratedColumn<String>(
    'name_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, nameKey];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<CategoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('name_key')) {
      context.handle(
        _nameKeyMeta,
        nameKey.isAcceptableOrUnknown(data['name_key']!, _nameKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_nameKeyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CategoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CategoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nameKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_key'],
      )!,
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class CategoryRow extends DataClass implements Insertable<CategoryRow> {
  final String id;
  final String name;
  final String nameKey;
  const CategoryRow({
    required this.id,
    required this.name,
    required this.nameKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['name_key'] = Variable<String>(nameKey);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      name: Value(name),
      nameKey: Value(nameKey),
    );
  }

  factory CategoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CategoryRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      nameKey: serializer.fromJson<String>(json['nameKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'nameKey': serializer.toJson<String>(nameKey),
    };
  }

  CategoryRow copyWith({String? id, String? name, String? nameKey}) =>
      CategoryRow(
        id: id ?? this.id,
        name: name ?? this.name,
        nameKey: nameKey ?? this.nameKey,
      );
  CategoryRow copyWithCompanion(CategoriesCompanion data) {
    return CategoryRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      nameKey: data.nameKey.present ? data.nameKey.value : this.nameKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CategoryRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameKey: $nameKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, nameKey);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CategoryRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.nameKey == this.nameKey);
}

class CategoriesCompanion extends UpdateCompanion<CategoryRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> nameKey;
  final Value<int> rowid;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameKey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoriesCompanion.insert({
    required String id,
    required String name,
    required String nameKey,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       nameKey = Value(nameKey);
  static Insertable<CategoryRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? nameKey,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (nameKey != null) 'name_key': nameKey,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoriesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? nameKey,
    Value<int>? rowid,
  }) {
    return CategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      nameKey: nameKey ?? this.nameKey,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameKey.present) {
      map['name_key'] = Variable<String>(nameKey.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameKey: $nameKey, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AssetsTable extends Assets with TableInfo<$AssetsTable, AssetRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionIdMeta = const VerificationMeta(
    'versionId',
  );
  @override
  late final GeneratedColumn<String> versionId = GeneratedColumn<String>(
    'version_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES versions (id)',
    ),
  );
  static const VerificationMeta _importedUtcMeta = const VerificationMeta(
    'importedUtc',
  );
  @override
  late final GeneratedColumn<int> importedUtc = GeneratedColumn<int>(
    'imported_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedUtcMeta = const VerificationMeta(
    'updatedUtc',
  );
  @override
  late final GeneratedColumn<int> updatedUtc = GeneratedColumn<int>(
    'updated_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceTypeMeta = const VerificationMeta(
    'sourceType',
  );
  @override
  late final GeneratedColumn<String> sourceType = GeneratedColumn<String>(
    'source_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _favoriteMeta = const VerificationMeta(
    'favorite',
  );
  @override
  late final GeneratedColumn<bool> favorite = GeneratedColumn<bool>(
    'favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES categories (id)',
    ),
  );
  static const VerificationMeta _recycledMeta = const VerificationMeta(
    'recycled',
  );
  @override
  late final GeneratedColumn<bool> recycled = GeneratedColumn<bool>(
    'recycled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("recycled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _recycledUtcMeta = const VerificationMeta(
    'recycledUtc',
  );
  @override
  late final GeneratedColumn<int> recycledUtc = GeneratedColumn<int>(
    'recycled_utc',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    displayName,
    versionId,
    importedUtc,
    updatedUtc,
    sourceType,
    favorite,
    category,
    recycled,
    recycledUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'assets';
  @override
  VerificationContext validateIntegrity(
    Insertable<AssetRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('version_id')) {
      context.handle(
        _versionIdMeta,
        versionId.isAcceptableOrUnknown(data['version_id']!, _versionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_versionIdMeta);
    }
    if (data.containsKey('imported_utc')) {
      context.handle(
        _importedUtcMeta,
        importedUtc.isAcceptableOrUnknown(
          data['imported_utc']!,
          _importedUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_importedUtcMeta);
    }
    if (data.containsKey('updated_utc')) {
      context.handle(
        _updatedUtcMeta,
        updatedUtc.isAcceptableOrUnknown(data['updated_utc']!, _updatedUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedUtcMeta);
    }
    if (data.containsKey('source_type')) {
      context.handle(
        _sourceTypeMeta,
        sourceType.isAcceptableOrUnknown(data['source_type']!, _sourceTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceTypeMeta);
    }
    if (data.containsKey('favorite')) {
      context.handle(
        _favoriteMeta,
        favorite.isAcceptableOrUnknown(data['favorite']!, _favoriteMeta),
      );
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('recycled')) {
      context.handle(
        _recycledMeta,
        recycled.isAcceptableOrUnknown(data['recycled']!, _recycledMeta),
      );
    }
    if (data.containsKey('recycled_utc')) {
      context.handle(
        _recycledUtcMeta,
        recycledUtc.isAcceptableOrUnknown(
          data['recycled_utc']!,
          _recycledUtcMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AssetRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AssetRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      versionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version_id'],
      )!,
      importedUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}imported_utc'],
      )!,
      updatedUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_utc'],
      )!,
      sourceType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_type'],
      )!,
      favorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}favorite'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      ),
      recycled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}recycled'],
      )!,
      recycledUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recycled_utc'],
      ),
    );
  }

  @override
  $AssetsTable createAlias(String alias) {
    return $AssetsTable(attachedDatabase, alias);
  }
}

class AssetRow extends DataClass implements Insertable<AssetRow> {
  final String id;
  final String displayName;
  final String versionId;
  final int importedUtc;
  final int updatedUtc;
  final String sourceType;
  final bool favorite;
  final String? category;
  final bool recycled;
  final int? recycledUtc;
  const AssetRow({
    required this.id,
    required this.displayName,
    required this.versionId,
    required this.importedUtc,
    required this.updatedUtc,
    required this.sourceType,
    required this.favorite,
    this.category,
    required this.recycled,
    this.recycledUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['display_name'] = Variable<String>(displayName);
    map['version_id'] = Variable<String>(versionId);
    map['imported_utc'] = Variable<int>(importedUtc);
    map['updated_utc'] = Variable<int>(updatedUtc);
    map['source_type'] = Variable<String>(sourceType);
    map['favorite'] = Variable<bool>(favorite);
    if (!nullToAbsent || category != null) {
      map['category'] = Variable<String>(category);
    }
    map['recycled'] = Variable<bool>(recycled);
    if (!nullToAbsent || recycledUtc != null) {
      map['recycled_utc'] = Variable<int>(recycledUtc);
    }
    return map;
  }

  AssetsCompanion toCompanion(bool nullToAbsent) {
    return AssetsCompanion(
      id: Value(id),
      displayName: Value(displayName),
      versionId: Value(versionId),
      importedUtc: Value(importedUtc),
      updatedUtc: Value(updatedUtc),
      sourceType: Value(sourceType),
      favorite: Value(favorite),
      category: category == null && nullToAbsent
          ? const Value.absent()
          : Value(category),
      recycled: Value(recycled),
      recycledUtc: recycledUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(recycledUtc),
    );
  }

  factory AssetRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AssetRow(
      id: serializer.fromJson<String>(json['id']),
      displayName: serializer.fromJson<String>(json['displayName']),
      versionId: serializer.fromJson<String>(json['versionId']),
      importedUtc: serializer.fromJson<int>(json['importedUtc']),
      updatedUtc: serializer.fromJson<int>(json['updatedUtc']),
      sourceType: serializer.fromJson<String>(json['sourceType']),
      favorite: serializer.fromJson<bool>(json['favorite']),
      category: serializer.fromJson<String?>(json['category']),
      recycled: serializer.fromJson<bool>(json['recycled']),
      recycledUtc: serializer.fromJson<int?>(json['recycledUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'displayName': serializer.toJson<String>(displayName),
      'versionId': serializer.toJson<String>(versionId),
      'importedUtc': serializer.toJson<int>(importedUtc),
      'updatedUtc': serializer.toJson<int>(updatedUtc),
      'sourceType': serializer.toJson<String>(sourceType),
      'favorite': serializer.toJson<bool>(favorite),
      'category': serializer.toJson<String?>(category),
      'recycled': serializer.toJson<bool>(recycled),
      'recycledUtc': serializer.toJson<int?>(recycledUtc),
    };
  }

  AssetRow copyWith({
    String? id,
    String? displayName,
    String? versionId,
    int? importedUtc,
    int? updatedUtc,
    String? sourceType,
    bool? favorite,
    Value<String?> category = const Value.absent(),
    bool? recycled,
    Value<int?> recycledUtc = const Value.absent(),
  }) => AssetRow(
    id: id ?? this.id,
    displayName: displayName ?? this.displayName,
    versionId: versionId ?? this.versionId,
    importedUtc: importedUtc ?? this.importedUtc,
    updatedUtc: updatedUtc ?? this.updatedUtc,
    sourceType: sourceType ?? this.sourceType,
    favorite: favorite ?? this.favorite,
    category: category.present ? category.value : this.category,
    recycled: recycled ?? this.recycled,
    recycledUtc: recycledUtc.present ? recycledUtc.value : this.recycledUtc,
  );
  AssetRow copyWithCompanion(AssetsCompanion data) {
    return AssetRow(
      id: data.id.present ? data.id.value : this.id,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      versionId: data.versionId.present ? data.versionId.value : this.versionId,
      importedUtc: data.importedUtc.present
          ? data.importedUtc.value
          : this.importedUtc,
      updatedUtc: data.updatedUtc.present
          ? data.updatedUtc.value
          : this.updatedUtc,
      sourceType: data.sourceType.present
          ? data.sourceType.value
          : this.sourceType,
      favorite: data.favorite.present ? data.favorite.value : this.favorite,
      category: data.category.present ? data.category.value : this.category,
      recycled: data.recycled.present ? data.recycled.value : this.recycled,
      recycledUtc: data.recycledUtc.present
          ? data.recycledUtc.value
          : this.recycledUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AssetRow(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('versionId: $versionId, ')
          ..write('importedUtc: $importedUtc, ')
          ..write('updatedUtc: $updatedUtc, ')
          ..write('sourceType: $sourceType, ')
          ..write('favorite: $favorite, ')
          ..write('category: $category, ')
          ..write('recycled: $recycled, ')
          ..write('recycledUtc: $recycledUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    versionId,
    importedUtc,
    updatedUtc,
    sourceType,
    favorite,
    category,
    recycled,
    recycledUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssetRow &&
          other.id == this.id &&
          other.displayName == this.displayName &&
          other.versionId == this.versionId &&
          other.importedUtc == this.importedUtc &&
          other.updatedUtc == this.updatedUtc &&
          other.sourceType == this.sourceType &&
          other.favorite == this.favorite &&
          other.category == this.category &&
          other.recycled == this.recycled &&
          other.recycledUtc == this.recycledUtc);
}

class AssetsCompanion extends UpdateCompanion<AssetRow> {
  final Value<String> id;
  final Value<String> displayName;
  final Value<String> versionId;
  final Value<int> importedUtc;
  final Value<int> updatedUtc;
  final Value<String> sourceType;
  final Value<bool> favorite;
  final Value<String?> category;
  final Value<bool> recycled;
  final Value<int?> recycledUtc;
  final Value<int> rowid;
  const AssetsCompanion({
    this.id = const Value.absent(),
    this.displayName = const Value.absent(),
    this.versionId = const Value.absent(),
    this.importedUtc = const Value.absent(),
    this.updatedUtc = const Value.absent(),
    this.sourceType = const Value.absent(),
    this.favorite = const Value.absent(),
    this.category = const Value.absent(),
    this.recycled = const Value.absent(),
    this.recycledUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AssetsCompanion.insert({
    required String id,
    required String displayName,
    required String versionId,
    required int importedUtc,
    required int updatedUtc,
    required String sourceType,
    this.favorite = const Value.absent(),
    this.category = const Value.absent(),
    this.recycled = const Value.absent(),
    this.recycledUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       displayName = Value(displayName),
       versionId = Value(versionId),
       importedUtc = Value(importedUtc),
       updatedUtc = Value(updatedUtc),
       sourceType = Value(sourceType);
  static Insertable<AssetRow> custom({
    Expression<String>? id,
    Expression<String>? displayName,
    Expression<String>? versionId,
    Expression<int>? importedUtc,
    Expression<int>? updatedUtc,
    Expression<String>? sourceType,
    Expression<bool>? favorite,
    Expression<String>? category,
    Expression<bool>? recycled,
    Expression<int>? recycledUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (displayName != null) 'display_name': displayName,
      if (versionId != null) 'version_id': versionId,
      if (importedUtc != null) 'imported_utc': importedUtc,
      if (updatedUtc != null) 'updated_utc': updatedUtc,
      if (sourceType != null) 'source_type': sourceType,
      if (favorite != null) 'favorite': favorite,
      if (category != null) 'category': category,
      if (recycled != null) 'recycled': recycled,
      if (recycledUtc != null) 'recycled_utc': recycledUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AssetsCompanion copyWith({
    Value<String>? id,
    Value<String>? displayName,
    Value<String>? versionId,
    Value<int>? importedUtc,
    Value<int>? updatedUtc,
    Value<String>? sourceType,
    Value<bool>? favorite,
    Value<String?>? category,
    Value<bool>? recycled,
    Value<int?>? recycledUtc,
    Value<int>? rowid,
  }) {
    return AssetsCompanion(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      versionId: versionId ?? this.versionId,
      importedUtc: importedUtc ?? this.importedUtc,
      updatedUtc: updatedUtc ?? this.updatedUtc,
      sourceType: sourceType ?? this.sourceType,
      favorite: favorite ?? this.favorite,
      category: category ?? this.category,
      recycled: recycled ?? this.recycled,
      recycledUtc: recycledUtc ?? this.recycledUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (versionId.present) {
      map['version_id'] = Variable<String>(versionId.value);
    }
    if (importedUtc.present) {
      map['imported_utc'] = Variable<int>(importedUtc.value);
    }
    if (updatedUtc.present) {
      map['updated_utc'] = Variable<int>(updatedUtc.value);
    }
    if (sourceType.present) {
      map['source_type'] = Variable<String>(sourceType.value);
    }
    if (favorite.present) {
      map['favorite'] = Variable<bool>(favorite.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (recycled.present) {
      map['recycled'] = Variable<bool>(recycled.value);
    }
    if (recycledUtc.present) {
      map['recycled_utc'] = Variable<int>(recycledUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssetsCompanion(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('versionId: $versionId, ')
          ..write('importedUtc: $importedUtc, ')
          ..write('updatedUtc: $updatedUtc, ')
          ..write('sourceType: $sourceType, ')
          ..write('favorite: $favorite, ')
          ..write('category: $category, ')
          ..write('recycled: $recycled, ')
          ..write('recycledUtc: $recycledUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DeviceCopiesTable extends DeviceCopies
    with TableInfo<$DeviceCopiesTable, CopyRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DeviceCopiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionIdMeta = const VerificationMeta(
    'versionId',
  );
  @override
  late final GeneratedColumn<String> versionId = GeneratedColumn<String>(
    'version_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'UNIQUE REFERENCES versions (id)',
    ),
  );
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _availabilityMeta = const VerificationMeta(
    'availability',
  );
  @override
  late final GeneratedColumn<String> availability = GeneratedColumn<String>(
    'availability',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unknown'),
  );
  static const VerificationMeta _verifiedUtcMeta = const VerificationMeta(
    'verifiedUtc',
  );
  @override
  late final GeneratedColumn<int> verifiedUtc = GeneratedColumn<int>(
    'verified_utc',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    versionId,
    relativePath,
    availability,
    verifiedUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'device_copies';
  @override
  VerificationContext validateIntegrity(
    Insertable<CopyRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('version_id')) {
      context.handle(
        _versionIdMeta,
        versionId.isAcceptableOrUnknown(data['version_id']!, _versionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_versionIdMeta);
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relativePathMeta);
    }
    if (data.containsKey('availability')) {
      context.handle(
        _availabilityMeta,
        availability.isAcceptableOrUnknown(
          data['availability']!,
          _availabilityMeta,
        ),
      );
    }
    if (data.containsKey('verified_utc')) {
      context.handle(
        _verifiedUtcMeta,
        verifiedUtc.isAcceptableOrUnknown(
          data['verified_utc']!,
          _verifiedUtcMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CopyRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CopyRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      versionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version_id'],
      )!,
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      )!,
      availability: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}availability'],
      )!,
      verifiedUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}verified_utc'],
      ),
    );
  }

  @override
  $DeviceCopiesTable createAlias(String alias) {
    return $DeviceCopiesTable(attachedDatabase, alias);
  }
}

class CopyRow extends DataClass implements Insertable<CopyRow> {
  final String id;
  final String versionId;
  final String relativePath;
  final String availability;
  final int? verifiedUtc;
  const CopyRow({
    required this.id,
    required this.versionId,
    required this.relativePath,
    required this.availability,
    this.verifiedUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['version_id'] = Variable<String>(versionId);
    map['relative_path'] = Variable<String>(relativePath);
    map['availability'] = Variable<String>(availability);
    if (!nullToAbsent || verifiedUtc != null) {
      map['verified_utc'] = Variable<int>(verifiedUtc);
    }
    return map;
  }

  DeviceCopiesCompanion toCompanion(bool nullToAbsent) {
    return DeviceCopiesCompanion(
      id: Value(id),
      versionId: Value(versionId),
      relativePath: Value(relativePath),
      availability: Value(availability),
      verifiedUtc: verifiedUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(verifiedUtc),
    );
  }

  factory CopyRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CopyRow(
      id: serializer.fromJson<String>(json['id']),
      versionId: serializer.fromJson<String>(json['versionId']),
      relativePath: serializer.fromJson<String>(json['relativePath']),
      availability: serializer.fromJson<String>(json['availability']),
      verifiedUtc: serializer.fromJson<int?>(json['verifiedUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'versionId': serializer.toJson<String>(versionId),
      'relativePath': serializer.toJson<String>(relativePath),
      'availability': serializer.toJson<String>(availability),
      'verifiedUtc': serializer.toJson<int?>(verifiedUtc),
    };
  }

  CopyRow copyWith({
    String? id,
    String? versionId,
    String? relativePath,
    String? availability,
    Value<int?> verifiedUtc = const Value.absent(),
  }) => CopyRow(
    id: id ?? this.id,
    versionId: versionId ?? this.versionId,
    relativePath: relativePath ?? this.relativePath,
    availability: availability ?? this.availability,
    verifiedUtc: verifiedUtc.present ? verifiedUtc.value : this.verifiedUtc,
  );
  CopyRow copyWithCompanion(DeviceCopiesCompanion data) {
    return CopyRow(
      id: data.id.present ? data.id.value : this.id,
      versionId: data.versionId.present ? data.versionId.value : this.versionId,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      availability: data.availability.present
          ? data.availability.value
          : this.availability,
      verifiedUtc: data.verifiedUtc.present
          ? data.verifiedUtc.value
          : this.verifiedUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CopyRow(')
          ..write('id: $id, ')
          ..write('versionId: $versionId, ')
          ..write('relativePath: $relativePath, ')
          ..write('availability: $availability, ')
          ..write('verifiedUtc: $verifiedUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, versionId, relativePath, availability, verifiedUtc);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CopyRow &&
          other.id == this.id &&
          other.versionId == this.versionId &&
          other.relativePath == this.relativePath &&
          other.availability == this.availability &&
          other.verifiedUtc == this.verifiedUtc);
}

class DeviceCopiesCompanion extends UpdateCompanion<CopyRow> {
  final Value<String> id;
  final Value<String> versionId;
  final Value<String> relativePath;
  final Value<String> availability;
  final Value<int?> verifiedUtc;
  final Value<int> rowid;
  const DeviceCopiesCompanion({
    this.id = const Value.absent(),
    this.versionId = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.availability = const Value.absent(),
    this.verifiedUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DeviceCopiesCompanion.insert({
    required String id,
    required String versionId,
    required String relativePath,
    this.availability = const Value.absent(),
    this.verifiedUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       versionId = Value(versionId),
       relativePath = Value(relativePath);
  static Insertable<CopyRow> custom({
    Expression<String>? id,
    Expression<String>? versionId,
    Expression<String>? relativePath,
    Expression<String>? availability,
    Expression<int>? verifiedUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (versionId != null) 'version_id': versionId,
      if (relativePath != null) 'relative_path': relativePath,
      if (availability != null) 'availability': availability,
      if (verifiedUtc != null) 'verified_utc': verifiedUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DeviceCopiesCompanion copyWith({
    Value<String>? id,
    Value<String>? versionId,
    Value<String>? relativePath,
    Value<String>? availability,
    Value<int?>? verifiedUtc,
    Value<int>? rowid,
  }) {
    return DeviceCopiesCompanion(
      id: id ?? this.id,
      versionId: versionId ?? this.versionId,
      relativePath: relativePath ?? this.relativePath,
      availability: availability ?? this.availability,
      verifiedUtc: verifiedUtc ?? this.verifiedUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (versionId.present) {
      map['version_id'] = Variable<String>(versionId.value);
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (availability.present) {
      map['availability'] = Variable<String>(availability.value);
    }
    if (verifiedUtc.present) {
      map['verified_utc'] = Variable<int>(verifiedUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeviceCopiesCompanion(')
          ..write('id: $id, ')
          ..write('versionId: $versionId, ')
          ..write('relativePath: $relativePath, ')
          ..write('availability: $availability, ')
          ..write('verifiedUtc: $verifiedUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProcessedOutputsTable extends ProcessedOutputs
    with TableInfo<$ProcessedOutputsTable, ProcessedOutputRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProcessedOutputsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _requestJsonMeta = const VerificationMeta(
    'requestJson',
  );
  @override
  late final GeneratedColumn<String> requestJson = GeneratedColumn<String>(
    'request_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionJsonMeta = const VerificationMeta(
    'versionJson',
  );
  @override
  late final GeneratedColumn<String> versionJson = GeneratedColumn<String>(
    'version_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _warningsJsonMeta = const VerificationMeta(
    'warningsJson',
  );
  @override
  late final GeneratedColumn<String> warningsJson = GeneratedColumn<String>(
    'warnings_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _lossyMeta = const VerificationMeta('lossy');
  @override
  late final GeneratedColumn<bool> lossy = GeneratedColumn<bool>(
    'lossy',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("lossy" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _transparencyRemovedMeta =
      const VerificationMeta('transparencyRemoved');
  @override
  late final GeneratedColumn<bool> transparencyRemoved = GeneratedColumn<bool>(
    'transparency_removed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("transparency_removed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _animationRemovedMeta = const VerificationMeta(
    'animationRemoved',
  );
  @override
  late final GeneratedColumn<bool> animationRemoved = GeneratedColumn<bool>(
    'animation_removed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("animation_removed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdUtcMeta = const VerificationMeta(
    'createdUtc',
  );
  @override
  late final GeneratedColumn<int> createdUtc = GeneratedColumn<int>(
    'created_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresUtcMeta = const VerificationMeta(
    'expiresUtc',
  );
  @override
  late final GeneratedColumn<int> expiresUtc = GeneratedColumn<int>(
    'expires_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _availabilityMeta = const VerificationMeta(
    'availability',
  );
  @override
  late final GeneratedColumn<String> availability = GeneratedColumn<String>(
    'availability',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('missing'),
  );
  static const VerificationMeta _savedVersionIdMeta = const VerificationMeta(
    'savedVersionId',
  );
  @override
  late final GeneratedColumn<String> savedVersionId = GeneratedColumn<String>(
    'saved_version_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES versions (id)',
    ),
  );
  static const VerificationMeta _failureMessageMeta = const VerificationMeta(
    'failureMessage',
  );
  @override
  late final GeneratedColumn<String> failureMessage = GeneratedColumn<String>(
    'failure_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    displayName,
    state,
    relativePath,
    requestJson,
    versionJson,
    warningsJson,
    lossy,
    transparencyRemoved,
    animationRemoved,
    createdUtc,
    expiresUtc,
    availability,
    savedVersionId,
    failureMessage,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'processed_outputs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProcessedOutputRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relativePathMeta);
    }
    if (data.containsKey('request_json')) {
      context.handle(
        _requestJsonMeta,
        requestJson.isAcceptableOrUnknown(
          data['request_json']!,
          _requestJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_requestJsonMeta);
    }
    if (data.containsKey('version_json')) {
      context.handle(
        _versionJsonMeta,
        versionJson.isAcceptableOrUnknown(
          data['version_json']!,
          _versionJsonMeta,
        ),
      );
    }
    if (data.containsKey('warnings_json')) {
      context.handle(
        _warningsJsonMeta,
        warningsJson.isAcceptableOrUnknown(
          data['warnings_json']!,
          _warningsJsonMeta,
        ),
      );
    }
    if (data.containsKey('lossy')) {
      context.handle(
        _lossyMeta,
        lossy.isAcceptableOrUnknown(data['lossy']!, _lossyMeta),
      );
    }
    if (data.containsKey('transparency_removed')) {
      context.handle(
        _transparencyRemovedMeta,
        transparencyRemoved.isAcceptableOrUnknown(
          data['transparency_removed']!,
          _transparencyRemovedMeta,
        ),
      );
    }
    if (data.containsKey('animation_removed')) {
      context.handle(
        _animationRemovedMeta,
        animationRemoved.isAcceptableOrUnknown(
          data['animation_removed']!,
          _animationRemovedMeta,
        ),
      );
    }
    if (data.containsKey('created_utc')) {
      context.handle(
        _createdUtcMeta,
        createdUtc.isAcceptableOrUnknown(data['created_utc']!, _createdUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_createdUtcMeta);
    }
    if (data.containsKey('expires_utc')) {
      context.handle(
        _expiresUtcMeta,
        expiresUtc.isAcceptableOrUnknown(data['expires_utc']!, _expiresUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_expiresUtcMeta);
    }
    if (data.containsKey('availability')) {
      context.handle(
        _availabilityMeta,
        availability.isAcceptableOrUnknown(
          data['availability']!,
          _availabilityMeta,
        ),
      );
    }
    if (data.containsKey('saved_version_id')) {
      context.handle(
        _savedVersionIdMeta,
        savedVersionId.isAcceptableOrUnknown(
          data['saved_version_id']!,
          _savedVersionIdMeta,
        ),
      );
    }
    if (data.containsKey('failure_message')) {
      context.handle(
        _failureMessageMeta,
        failureMessage.isAcceptableOrUnknown(
          data['failure_message']!,
          _failureMessageMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProcessedOutputRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProcessedOutputRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      )!,
      requestJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_json'],
      )!,
      versionJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version_json'],
      ),
      warningsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}warnings_json'],
      )!,
      lossy: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}lossy'],
      )!,
      transparencyRemoved: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}transparency_removed'],
      )!,
      animationRemoved: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}animation_removed'],
      )!,
      createdUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_utc'],
      )!,
      expiresUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expires_utc'],
      )!,
      availability: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}availability'],
      )!,
      savedVersionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}saved_version_id'],
      ),
      failureMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_message'],
      ),
    );
  }

  @override
  $ProcessedOutputsTable createAlias(String alias) {
    return $ProcessedOutputsTable(attachedDatabase, alias);
  }
}

class ProcessedOutputRow extends DataClass
    implements Insertable<ProcessedOutputRow> {
  final String id;
  final String displayName;
  final String state;
  final String relativePath;
  final String requestJson;
  final String? versionJson;
  final String warningsJson;
  final bool lossy;
  final bool transparencyRemoved;
  final bool animationRemoved;
  final int createdUtc;
  final int expiresUtc;
  final String availability;
  final String? savedVersionId;
  final String? failureMessage;
  const ProcessedOutputRow({
    required this.id,
    required this.displayName,
    required this.state,
    required this.relativePath,
    required this.requestJson,
    this.versionJson,
    required this.warningsJson,
    required this.lossy,
    required this.transparencyRemoved,
    required this.animationRemoved,
    required this.createdUtc,
    required this.expiresUtc,
    required this.availability,
    this.savedVersionId,
    this.failureMessage,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['display_name'] = Variable<String>(displayName);
    map['state'] = Variable<String>(state);
    map['relative_path'] = Variable<String>(relativePath);
    map['request_json'] = Variable<String>(requestJson);
    if (!nullToAbsent || versionJson != null) {
      map['version_json'] = Variable<String>(versionJson);
    }
    map['warnings_json'] = Variable<String>(warningsJson);
    map['lossy'] = Variable<bool>(lossy);
    map['transparency_removed'] = Variable<bool>(transparencyRemoved);
    map['animation_removed'] = Variable<bool>(animationRemoved);
    map['created_utc'] = Variable<int>(createdUtc);
    map['expires_utc'] = Variable<int>(expiresUtc);
    map['availability'] = Variable<String>(availability);
    if (!nullToAbsent || savedVersionId != null) {
      map['saved_version_id'] = Variable<String>(savedVersionId);
    }
    if (!nullToAbsent || failureMessage != null) {
      map['failure_message'] = Variable<String>(failureMessage);
    }
    return map;
  }

  ProcessedOutputsCompanion toCompanion(bool nullToAbsent) {
    return ProcessedOutputsCompanion(
      id: Value(id),
      displayName: Value(displayName),
      state: Value(state),
      relativePath: Value(relativePath),
      requestJson: Value(requestJson),
      versionJson: versionJson == null && nullToAbsent
          ? const Value.absent()
          : Value(versionJson),
      warningsJson: Value(warningsJson),
      lossy: Value(lossy),
      transparencyRemoved: Value(transparencyRemoved),
      animationRemoved: Value(animationRemoved),
      createdUtc: Value(createdUtc),
      expiresUtc: Value(expiresUtc),
      availability: Value(availability),
      savedVersionId: savedVersionId == null && nullToAbsent
          ? const Value.absent()
          : Value(savedVersionId),
      failureMessage: failureMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(failureMessage),
    );
  }

  factory ProcessedOutputRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProcessedOutputRow(
      id: serializer.fromJson<String>(json['id']),
      displayName: serializer.fromJson<String>(json['displayName']),
      state: serializer.fromJson<String>(json['state']),
      relativePath: serializer.fromJson<String>(json['relativePath']),
      requestJson: serializer.fromJson<String>(json['requestJson']),
      versionJson: serializer.fromJson<String?>(json['versionJson']),
      warningsJson: serializer.fromJson<String>(json['warningsJson']),
      lossy: serializer.fromJson<bool>(json['lossy']),
      transparencyRemoved: serializer.fromJson<bool>(
        json['transparencyRemoved'],
      ),
      animationRemoved: serializer.fromJson<bool>(json['animationRemoved']),
      createdUtc: serializer.fromJson<int>(json['createdUtc']),
      expiresUtc: serializer.fromJson<int>(json['expiresUtc']),
      availability: serializer.fromJson<String>(json['availability']),
      savedVersionId: serializer.fromJson<String?>(json['savedVersionId']),
      failureMessage: serializer.fromJson<String?>(json['failureMessage']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'displayName': serializer.toJson<String>(displayName),
      'state': serializer.toJson<String>(state),
      'relativePath': serializer.toJson<String>(relativePath),
      'requestJson': serializer.toJson<String>(requestJson),
      'versionJson': serializer.toJson<String?>(versionJson),
      'warningsJson': serializer.toJson<String>(warningsJson),
      'lossy': serializer.toJson<bool>(lossy),
      'transparencyRemoved': serializer.toJson<bool>(transparencyRemoved),
      'animationRemoved': serializer.toJson<bool>(animationRemoved),
      'createdUtc': serializer.toJson<int>(createdUtc),
      'expiresUtc': serializer.toJson<int>(expiresUtc),
      'availability': serializer.toJson<String>(availability),
      'savedVersionId': serializer.toJson<String?>(savedVersionId),
      'failureMessage': serializer.toJson<String?>(failureMessage),
    };
  }

  ProcessedOutputRow copyWith({
    String? id,
    String? displayName,
    String? state,
    String? relativePath,
    String? requestJson,
    Value<String?> versionJson = const Value.absent(),
    String? warningsJson,
    bool? lossy,
    bool? transparencyRemoved,
    bool? animationRemoved,
    int? createdUtc,
    int? expiresUtc,
    String? availability,
    Value<String?> savedVersionId = const Value.absent(),
    Value<String?> failureMessage = const Value.absent(),
  }) => ProcessedOutputRow(
    id: id ?? this.id,
    displayName: displayName ?? this.displayName,
    state: state ?? this.state,
    relativePath: relativePath ?? this.relativePath,
    requestJson: requestJson ?? this.requestJson,
    versionJson: versionJson.present ? versionJson.value : this.versionJson,
    warningsJson: warningsJson ?? this.warningsJson,
    lossy: lossy ?? this.lossy,
    transparencyRemoved: transparencyRemoved ?? this.transparencyRemoved,
    animationRemoved: animationRemoved ?? this.animationRemoved,
    createdUtc: createdUtc ?? this.createdUtc,
    expiresUtc: expiresUtc ?? this.expiresUtc,
    availability: availability ?? this.availability,
    savedVersionId: savedVersionId.present
        ? savedVersionId.value
        : this.savedVersionId,
    failureMessage: failureMessage.present
        ? failureMessage.value
        : this.failureMessage,
  );
  ProcessedOutputRow copyWithCompanion(ProcessedOutputsCompanion data) {
    return ProcessedOutputRow(
      id: data.id.present ? data.id.value : this.id,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      state: data.state.present ? data.state.value : this.state,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      requestJson: data.requestJson.present
          ? data.requestJson.value
          : this.requestJson,
      versionJson: data.versionJson.present
          ? data.versionJson.value
          : this.versionJson,
      warningsJson: data.warningsJson.present
          ? data.warningsJson.value
          : this.warningsJson,
      lossy: data.lossy.present ? data.lossy.value : this.lossy,
      transparencyRemoved: data.transparencyRemoved.present
          ? data.transparencyRemoved.value
          : this.transparencyRemoved,
      animationRemoved: data.animationRemoved.present
          ? data.animationRemoved.value
          : this.animationRemoved,
      createdUtc: data.createdUtc.present
          ? data.createdUtc.value
          : this.createdUtc,
      expiresUtc: data.expiresUtc.present
          ? data.expiresUtc.value
          : this.expiresUtc,
      availability: data.availability.present
          ? data.availability.value
          : this.availability,
      savedVersionId: data.savedVersionId.present
          ? data.savedVersionId.value
          : this.savedVersionId,
      failureMessage: data.failureMessage.present
          ? data.failureMessage.value
          : this.failureMessage,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProcessedOutputRow(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('state: $state, ')
          ..write('relativePath: $relativePath, ')
          ..write('requestJson: $requestJson, ')
          ..write('versionJson: $versionJson, ')
          ..write('warningsJson: $warningsJson, ')
          ..write('lossy: $lossy, ')
          ..write('transparencyRemoved: $transparencyRemoved, ')
          ..write('animationRemoved: $animationRemoved, ')
          ..write('createdUtc: $createdUtc, ')
          ..write('expiresUtc: $expiresUtc, ')
          ..write('availability: $availability, ')
          ..write('savedVersionId: $savedVersionId, ')
          ..write('failureMessage: $failureMessage')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    state,
    relativePath,
    requestJson,
    versionJson,
    warningsJson,
    lossy,
    transparencyRemoved,
    animationRemoved,
    createdUtc,
    expiresUtc,
    availability,
    savedVersionId,
    failureMessage,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProcessedOutputRow &&
          other.id == this.id &&
          other.displayName == this.displayName &&
          other.state == this.state &&
          other.relativePath == this.relativePath &&
          other.requestJson == this.requestJson &&
          other.versionJson == this.versionJson &&
          other.warningsJson == this.warningsJson &&
          other.lossy == this.lossy &&
          other.transparencyRemoved == this.transparencyRemoved &&
          other.animationRemoved == this.animationRemoved &&
          other.createdUtc == this.createdUtc &&
          other.expiresUtc == this.expiresUtc &&
          other.availability == this.availability &&
          other.savedVersionId == this.savedVersionId &&
          other.failureMessage == this.failureMessage);
}

class ProcessedOutputsCompanion extends UpdateCompanion<ProcessedOutputRow> {
  final Value<String> id;
  final Value<String> displayName;
  final Value<String> state;
  final Value<String> relativePath;
  final Value<String> requestJson;
  final Value<String?> versionJson;
  final Value<String> warningsJson;
  final Value<bool> lossy;
  final Value<bool> transparencyRemoved;
  final Value<bool> animationRemoved;
  final Value<int> createdUtc;
  final Value<int> expiresUtc;
  final Value<String> availability;
  final Value<String?> savedVersionId;
  final Value<String?> failureMessage;
  final Value<int> rowid;
  const ProcessedOutputsCompanion({
    this.id = const Value.absent(),
    this.displayName = const Value.absent(),
    this.state = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.requestJson = const Value.absent(),
    this.versionJson = const Value.absent(),
    this.warningsJson = const Value.absent(),
    this.lossy = const Value.absent(),
    this.transparencyRemoved = const Value.absent(),
    this.animationRemoved = const Value.absent(),
    this.createdUtc = const Value.absent(),
    this.expiresUtc = const Value.absent(),
    this.availability = const Value.absent(),
    this.savedVersionId = const Value.absent(),
    this.failureMessage = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProcessedOutputsCompanion.insert({
    required String id,
    required String displayName,
    required String state,
    required String relativePath,
    required String requestJson,
    this.versionJson = const Value.absent(),
    this.warningsJson = const Value.absent(),
    this.lossy = const Value.absent(),
    this.transparencyRemoved = const Value.absent(),
    this.animationRemoved = const Value.absent(),
    required int createdUtc,
    required int expiresUtc,
    this.availability = const Value.absent(),
    this.savedVersionId = const Value.absent(),
    this.failureMessage = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       displayName = Value(displayName),
       state = Value(state),
       relativePath = Value(relativePath),
       requestJson = Value(requestJson),
       createdUtc = Value(createdUtc),
       expiresUtc = Value(expiresUtc);
  static Insertable<ProcessedOutputRow> custom({
    Expression<String>? id,
    Expression<String>? displayName,
    Expression<String>? state,
    Expression<String>? relativePath,
    Expression<String>? requestJson,
    Expression<String>? versionJson,
    Expression<String>? warningsJson,
    Expression<bool>? lossy,
    Expression<bool>? transparencyRemoved,
    Expression<bool>? animationRemoved,
    Expression<int>? createdUtc,
    Expression<int>? expiresUtc,
    Expression<String>? availability,
    Expression<String>? savedVersionId,
    Expression<String>? failureMessage,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (displayName != null) 'display_name': displayName,
      if (state != null) 'state': state,
      if (relativePath != null) 'relative_path': relativePath,
      if (requestJson != null) 'request_json': requestJson,
      if (versionJson != null) 'version_json': versionJson,
      if (warningsJson != null) 'warnings_json': warningsJson,
      if (lossy != null) 'lossy': lossy,
      if (transparencyRemoved != null)
        'transparency_removed': transparencyRemoved,
      if (animationRemoved != null) 'animation_removed': animationRemoved,
      if (createdUtc != null) 'created_utc': createdUtc,
      if (expiresUtc != null) 'expires_utc': expiresUtc,
      if (availability != null) 'availability': availability,
      if (savedVersionId != null) 'saved_version_id': savedVersionId,
      if (failureMessage != null) 'failure_message': failureMessage,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProcessedOutputsCompanion copyWith({
    Value<String>? id,
    Value<String>? displayName,
    Value<String>? state,
    Value<String>? relativePath,
    Value<String>? requestJson,
    Value<String?>? versionJson,
    Value<String>? warningsJson,
    Value<bool>? lossy,
    Value<bool>? transparencyRemoved,
    Value<bool>? animationRemoved,
    Value<int>? createdUtc,
    Value<int>? expiresUtc,
    Value<String>? availability,
    Value<String?>? savedVersionId,
    Value<String?>? failureMessage,
    Value<int>? rowid,
  }) {
    return ProcessedOutputsCompanion(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      state: state ?? this.state,
      relativePath: relativePath ?? this.relativePath,
      requestJson: requestJson ?? this.requestJson,
      versionJson: versionJson ?? this.versionJson,
      warningsJson: warningsJson ?? this.warningsJson,
      lossy: lossy ?? this.lossy,
      transparencyRemoved: transparencyRemoved ?? this.transparencyRemoved,
      animationRemoved: animationRemoved ?? this.animationRemoved,
      createdUtc: createdUtc ?? this.createdUtc,
      expiresUtc: expiresUtc ?? this.expiresUtc,
      availability: availability ?? this.availability,
      savedVersionId: savedVersionId ?? this.savedVersionId,
      failureMessage: failureMessage ?? this.failureMessage,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (requestJson.present) {
      map['request_json'] = Variable<String>(requestJson.value);
    }
    if (versionJson.present) {
      map['version_json'] = Variable<String>(versionJson.value);
    }
    if (warningsJson.present) {
      map['warnings_json'] = Variable<String>(warningsJson.value);
    }
    if (lossy.present) {
      map['lossy'] = Variable<bool>(lossy.value);
    }
    if (transparencyRemoved.present) {
      map['transparency_removed'] = Variable<bool>(transparencyRemoved.value);
    }
    if (animationRemoved.present) {
      map['animation_removed'] = Variable<bool>(animationRemoved.value);
    }
    if (createdUtc.present) {
      map['created_utc'] = Variable<int>(createdUtc.value);
    }
    if (expiresUtc.present) {
      map['expires_utc'] = Variable<int>(expiresUtc.value);
    }
    if (availability.present) {
      map['availability'] = Variable<String>(availability.value);
    }
    if (savedVersionId.present) {
      map['saved_version_id'] = Variable<String>(savedVersionId.value);
    }
    if (failureMessage.present) {
      map['failure_message'] = Variable<String>(failureMessage.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProcessedOutputsCompanion(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('state: $state, ')
          ..write('relativePath: $relativePath, ')
          ..write('requestJson: $requestJson, ')
          ..write('versionJson: $versionJson, ')
          ..write('warningsJson: $warningsJson, ')
          ..write('lossy: $lossy, ')
          ..write('transparencyRemoved: $transparencyRemoved, ')
          ..write('animationRemoved: $animationRemoved, ')
          ..write('createdUtc: $createdUtc, ')
          ..write('expiresUtc: $expiresUtc, ')
          ..write('availability: $availability, ')
          ..write('savedVersionId: $savedVersionId, ')
          ..write('failureMessage: $failureMessage, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ImportOperationsTable extends ImportOperations
    with TableInfo<$ImportOperationsTable, OperationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImportOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _assetIdMeta = const VerificationMeta(
    'assetId',
  );
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
    'asset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionIdMeta = const VerificationMeta(
    'versionId',
  );
  @override
  late final GeneratedColumn<String> versionId = GeneratedColumn<String>(
    'version_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _copyIdMeta = const VerificationMeta('copyId');
  @override
  late final GeneratedColumn<String> copyId = GeneratedColumn<String>(
    'copy_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stagePathMeta = const VerificationMeta(
    'stagePath',
  );
  @override
  late final GeneratedColumn<String> stagePath = GeneratedColumn<String>(
    'stage_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _finalPathMeta = const VerificationMeta(
    'finalPath',
  );
  @override
  late final GeneratedColumn<String> finalPath = GeneratedColumn<String>(
    'final_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceTypeMeta = const VerificationMeta(
    'sourceType',
  );
  @override
  late final GeneratedColumn<String> sourceType = GeneratedColumn<String>(
    'source_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdUtcMeta = const VerificationMeta(
    'createdUtc',
  );
  @override
  late final GeneratedColumn<int> createdUtc = GeneratedColumn<int>(
    'created_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phaseMeta = const VerificationMeta('phase');
  @override
  late final GeneratedColumn<String> phase = GeneratedColumn<String>(
    'phase',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _digestMeta = const VerificationMeta('digest');
  @override
  late final GeneratedColumn<String> digest = GeneratedColumn<String>(
    'digest',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _byteCountMeta = const VerificationMeta(
    'byteCount',
  );
  @override
  late final GeneratedColumn<int> byteCount = GeneratedColumn<int>(
    'byte_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  @override
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
    'format',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _frameCountMeta = const VerificationMeta(
    'frameCount',
  );
  @override
  late final GeneratedColumn<int> frameCount = GeneratedColumn<int>(
    'frame_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _orientationMeta = const VerificationMeta(
    'orientation',
  );
  @override
  late final GeneratedColumn<int> orientation = GeneratedColumn<int>(
    'orientation',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _outputIdMeta = const VerificationMeta(
    'outputId',
  );
  @override
  late final GeneratedColumn<String> outputId = GeneratedColumn<String>(
    'output_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES processed_outputs (id)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    assetId,
    versionId,
    copyId,
    stagePath,
    finalPath,
    displayName,
    sourceType,
    createdUtc,
    phase,
    digest,
    byteCount,
    format,
    width,
    height,
    frameCount,
    orientation,
    outputId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'import_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<OperationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('asset_id')) {
      context.handle(
        _assetIdMeta,
        assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_assetIdMeta);
    }
    if (data.containsKey('version_id')) {
      context.handle(
        _versionIdMeta,
        versionId.isAcceptableOrUnknown(data['version_id']!, _versionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_versionIdMeta);
    }
    if (data.containsKey('copy_id')) {
      context.handle(
        _copyIdMeta,
        copyId.isAcceptableOrUnknown(data['copy_id']!, _copyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_copyIdMeta);
    }
    if (data.containsKey('stage_path')) {
      context.handle(
        _stagePathMeta,
        stagePath.isAcceptableOrUnknown(data['stage_path']!, _stagePathMeta),
      );
    } else if (isInserting) {
      context.missing(_stagePathMeta);
    }
    if (data.containsKey('final_path')) {
      context.handle(
        _finalPathMeta,
        finalPath.isAcceptableOrUnknown(data['final_path']!, _finalPathMeta),
      );
    } else if (isInserting) {
      context.missing(_finalPathMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('source_type')) {
      context.handle(
        _sourceTypeMeta,
        sourceType.isAcceptableOrUnknown(data['source_type']!, _sourceTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceTypeMeta);
    }
    if (data.containsKey('created_utc')) {
      context.handle(
        _createdUtcMeta,
        createdUtc.isAcceptableOrUnknown(data['created_utc']!, _createdUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_createdUtcMeta);
    }
    if (data.containsKey('phase')) {
      context.handle(
        _phaseMeta,
        phase.isAcceptableOrUnknown(data['phase']!, _phaseMeta),
      );
    } else if (isInserting) {
      context.missing(_phaseMeta);
    }
    if (data.containsKey('digest')) {
      context.handle(
        _digestMeta,
        digest.isAcceptableOrUnknown(data['digest']!, _digestMeta),
      );
    }
    if (data.containsKey('byte_count')) {
      context.handle(
        _byteCountMeta,
        byteCount.isAcceptableOrUnknown(data['byte_count']!, _byteCountMeta),
      );
    }
    if (data.containsKey('format')) {
      context.handle(
        _formatMeta,
        format.isAcceptableOrUnknown(data['format']!, _formatMeta),
      );
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    }
    if (data.containsKey('frame_count')) {
      context.handle(
        _frameCountMeta,
        frameCount.isAcceptableOrUnknown(data['frame_count']!, _frameCountMeta),
      );
    }
    if (data.containsKey('orientation')) {
      context.handle(
        _orientationMeta,
        orientation.isAcceptableOrUnknown(
          data['orientation']!,
          _orientationMeta,
        ),
      );
    }
    if (data.containsKey('output_id')) {
      context.handle(
        _outputIdMeta,
        outputId.isAcceptableOrUnknown(data['output_id']!, _outputIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OperationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OperationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_id'],
      )!,
      versionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version_id'],
      )!,
      copyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}copy_id'],
      )!,
      stagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stage_path'],
      )!,
      finalPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}final_path'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      sourceType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_type'],
      )!,
      createdUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_utc'],
      )!,
      phase: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phase'],
      )!,
      digest: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}digest'],
      ),
      byteCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_count'],
      ),
      format: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}format'],
      ),
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      ),
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      ),
      frameCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}frame_count'],
      ),
      orientation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}orientation'],
      ),
      outputId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}output_id'],
      ),
    );
  }

  @override
  $ImportOperationsTable createAlias(String alias) {
    return $ImportOperationsTable(attachedDatabase, alias);
  }
}

class OperationRow extends DataClass implements Insertable<OperationRow> {
  final String id;
  final String assetId;
  final String versionId;
  final String copyId;
  final String stagePath;
  final String finalPath;
  final String displayName;
  final String sourceType;
  final int createdUtc;
  final String phase;
  final String? digest;
  final int? byteCount;
  final String? format;
  final int? width;
  final int? height;
  final int? frameCount;
  final int? orientation;
  final String? outputId;
  const OperationRow({
    required this.id,
    required this.assetId,
    required this.versionId,
    required this.copyId,
    required this.stagePath,
    required this.finalPath,
    required this.displayName,
    required this.sourceType,
    required this.createdUtc,
    required this.phase,
    this.digest,
    this.byteCount,
    this.format,
    this.width,
    this.height,
    this.frameCount,
    this.orientation,
    this.outputId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['asset_id'] = Variable<String>(assetId);
    map['version_id'] = Variable<String>(versionId);
    map['copy_id'] = Variable<String>(copyId);
    map['stage_path'] = Variable<String>(stagePath);
    map['final_path'] = Variable<String>(finalPath);
    map['display_name'] = Variable<String>(displayName);
    map['source_type'] = Variable<String>(sourceType);
    map['created_utc'] = Variable<int>(createdUtc);
    map['phase'] = Variable<String>(phase);
    if (!nullToAbsent || digest != null) {
      map['digest'] = Variable<String>(digest);
    }
    if (!nullToAbsent || byteCount != null) {
      map['byte_count'] = Variable<int>(byteCount);
    }
    if (!nullToAbsent || format != null) {
      map['format'] = Variable<String>(format);
    }
    if (!nullToAbsent || width != null) {
      map['width'] = Variable<int>(width);
    }
    if (!nullToAbsent || height != null) {
      map['height'] = Variable<int>(height);
    }
    if (!nullToAbsent || frameCount != null) {
      map['frame_count'] = Variable<int>(frameCount);
    }
    if (!nullToAbsent || orientation != null) {
      map['orientation'] = Variable<int>(orientation);
    }
    if (!nullToAbsent || outputId != null) {
      map['output_id'] = Variable<String>(outputId);
    }
    return map;
  }

  ImportOperationsCompanion toCompanion(bool nullToAbsent) {
    return ImportOperationsCompanion(
      id: Value(id),
      assetId: Value(assetId),
      versionId: Value(versionId),
      copyId: Value(copyId),
      stagePath: Value(stagePath),
      finalPath: Value(finalPath),
      displayName: Value(displayName),
      sourceType: Value(sourceType),
      createdUtc: Value(createdUtc),
      phase: Value(phase),
      digest: digest == null && nullToAbsent
          ? const Value.absent()
          : Value(digest),
      byteCount: byteCount == null && nullToAbsent
          ? const Value.absent()
          : Value(byteCount),
      format: format == null && nullToAbsent
          ? const Value.absent()
          : Value(format),
      width: width == null && nullToAbsent
          ? const Value.absent()
          : Value(width),
      height: height == null && nullToAbsent
          ? const Value.absent()
          : Value(height),
      frameCount: frameCount == null && nullToAbsent
          ? const Value.absent()
          : Value(frameCount),
      orientation: orientation == null && nullToAbsent
          ? const Value.absent()
          : Value(orientation),
      outputId: outputId == null && nullToAbsent
          ? const Value.absent()
          : Value(outputId),
    );
  }

  factory OperationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OperationRow(
      id: serializer.fromJson<String>(json['id']),
      assetId: serializer.fromJson<String>(json['assetId']),
      versionId: serializer.fromJson<String>(json['versionId']),
      copyId: serializer.fromJson<String>(json['copyId']),
      stagePath: serializer.fromJson<String>(json['stagePath']),
      finalPath: serializer.fromJson<String>(json['finalPath']),
      displayName: serializer.fromJson<String>(json['displayName']),
      sourceType: serializer.fromJson<String>(json['sourceType']),
      createdUtc: serializer.fromJson<int>(json['createdUtc']),
      phase: serializer.fromJson<String>(json['phase']),
      digest: serializer.fromJson<String?>(json['digest']),
      byteCount: serializer.fromJson<int?>(json['byteCount']),
      format: serializer.fromJson<String?>(json['format']),
      width: serializer.fromJson<int?>(json['width']),
      height: serializer.fromJson<int?>(json['height']),
      frameCount: serializer.fromJson<int?>(json['frameCount']),
      orientation: serializer.fromJson<int?>(json['orientation']),
      outputId: serializer.fromJson<String?>(json['outputId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'assetId': serializer.toJson<String>(assetId),
      'versionId': serializer.toJson<String>(versionId),
      'copyId': serializer.toJson<String>(copyId),
      'stagePath': serializer.toJson<String>(stagePath),
      'finalPath': serializer.toJson<String>(finalPath),
      'displayName': serializer.toJson<String>(displayName),
      'sourceType': serializer.toJson<String>(sourceType),
      'createdUtc': serializer.toJson<int>(createdUtc),
      'phase': serializer.toJson<String>(phase),
      'digest': serializer.toJson<String?>(digest),
      'byteCount': serializer.toJson<int?>(byteCount),
      'format': serializer.toJson<String?>(format),
      'width': serializer.toJson<int?>(width),
      'height': serializer.toJson<int?>(height),
      'frameCount': serializer.toJson<int?>(frameCount),
      'orientation': serializer.toJson<int?>(orientation),
      'outputId': serializer.toJson<String?>(outputId),
    };
  }

  OperationRow copyWith({
    String? id,
    String? assetId,
    String? versionId,
    String? copyId,
    String? stagePath,
    String? finalPath,
    String? displayName,
    String? sourceType,
    int? createdUtc,
    String? phase,
    Value<String?> digest = const Value.absent(),
    Value<int?> byteCount = const Value.absent(),
    Value<String?> format = const Value.absent(),
    Value<int?> width = const Value.absent(),
    Value<int?> height = const Value.absent(),
    Value<int?> frameCount = const Value.absent(),
    Value<int?> orientation = const Value.absent(),
    Value<String?> outputId = const Value.absent(),
  }) => OperationRow(
    id: id ?? this.id,
    assetId: assetId ?? this.assetId,
    versionId: versionId ?? this.versionId,
    copyId: copyId ?? this.copyId,
    stagePath: stagePath ?? this.stagePath,
    finalPath: finalPath ?? this.finalPath,
    displayName: displayName ?? this.displayName,
    sourceType: sourceType ?? this.sourceType,
    createdUtc: createdUtc ?? this.createdUtc,
    phase: phase ?? this.phase,
    digest: digest.present ? digest.value : this.digest,
    byteCount: byteCount.present ? byteCount.value : this.byteCount,
    format: format.present ? format.value : this.format,
    width: width.present ? width.value : this.width,
    height: height.present ? height.value : this.height,
    frameCount: frameCount.present ? frameCount.value : this.frameCount,
    orientation: orientation.present ? orientation.value : this.orientation,
    outputId: outputId.present ? outputId.value : this.outputId,
  );
  OperationRow copyWithCompanion(ImportOperationsCompanion data) {
    return OperationRow(
      id: data.id.present ? data.id.value : this.id,
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      versionId: data.versionId.present ? data.versionId.value : this.versionId,
      copyId: data.copyId.present ? data.copyId.value : this.copyId,
      stagePath: data.stagePath.present ? data.stagePath.value : this.stagePath,
      finalPath: data.finalPath.present ? data.finalPath.value : this.finalPath,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      sourceType: data.sourceType.present
          ? data.sourceType.value
          : this.sourceType,
      createdUtc: data.createdUtc.present
          ? data.createdUtc.value
          : this.createdUtc,
      phase: data.phase.present ? data.phase.value : this.phase,
      digest: data.digest.present ? data.digest.value : this.digest,
      byteCount: data.byteCount.present ? data.byteCount.value : this.byteCount,
      format: data.format.present ? data.format.value : this.format,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      frameCount: data.frameCount.present
          ? data.frameCount.value
          : this.frameCount,
      orientation: data.orientation.present
          ? data.orientation.value
          : this.orientation,
      outputId: data.outputId.present ? data.outputId.value : this.outputId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OperationRow(')
          ..write('id: $id, ')
          ..write('assetId: $assetId, ')
          ..write('versionId: $versionId, ')
          ..write('copyId: $copyId, ')
          ..write('stagePath: $stagePath, ')
          ..write('finalPath: $finalPath, ')
          ..write('displayName: $displayName, ')
          ..write('sourceType: $sourceType, ')
          ..write('createdUtc: $createdUtc, ')
          ..write('phase: $phase, ')
          ..write('digest: $digest, ')
          ..write('byteCount: $byteCount, ')
          ..write('format: $format, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('frameCount: $frameCount, ')
          ..write('orientation: $orientation, ')
          ..write('outputId: $outputId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    assetId,
    versionId,
    copyId,
    stagePath,
    finalPath,
    displayName,
    sourceType,
    createdUtc,
    phase,
    digest,
    byteCount,
    format,
    width,
    height,
    frameCount,
    orientation,
    outputId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OperationRow &&
          other.id == this.id &&
          other.assetId == this.assetId &&
          other.versionId == this.versionId &&
          other.copyId == this.copyId &&
          other.stagePath == this.stagePath &&
          other.finalPath == this.finalPath &&
          other.displayName == this.displayName &&
          other.sourceType == this.sourceType &&
          other.createdUtc == this.createdUtc &&
          other.phase == this.phase &&
          other.digest == this.digest &&
          other.byteCount == this.byteCount &&
          other.format == this.format &&
          other.width == this.width &&
          other.height == this.height &&
          other.frameCount == this.frameCount &&
          other.orientation == this.orientation &&
          other.outputId == this.outputId);
}

class ImportOperationsCompanion extends UpdateCompanion<OperationRow> {
  final Value<String> id;
  final Value<String> assetId;
  final Value<String> versionId;
  final Value<String> copyId;
  final Value<String> stagePath;
  final Value<String> finalPath;
  final Value<String> displayName;
  final Value<String> sourceType;
  final Value<int> createdUtc;
  final Value<String> phase;
  final Value<String?> digest;
  final Value<int?> byteCount;
  final Value<String?> format;
  final Value<int?> width;
  final Value<int?> height;
  final Value<int?> frameCount;
  final Value<int?> orientation;
  final Value<String?> outputId;
  final Value<int> rowid;
  const ImportOperationsCompanion({
    this.id = const Value.absent(),
    this.assetId = const Value.absent(),
    this.versionId = const Value.absent(),
    this.copyId = const Value.absent(),
    this.stagePath = const Value.absent(),
    this.finalPath = const Value.absent(),
    this.displayName = const Value.absent(),
    this.sourceType = const Value.absent(),
    this.createdUtc = const Value.absent(),
    this.phase = const Value.absent(),
    this.digest = const Value.absent(),
    this.byteCount = const Value.absent(),
    this.format = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.frameCount = const Value.absent(),
    this.orientation = const Value.absent(),
    this.outputId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ImportOperationsCompanion.insert({
    required String id,
    required String assetId,
    required String versionId,
    required String copyId,
    required String stagePath,
    required String finalPath,
    required String displayName,
    required String sourceType,
    required int createdUtc,
    required String phase,
    this.digest = const Value.absent(),
    this.byteCount = const Value.absent(),
    this.format = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.frameCount = const Value.absent(),
    this.orientation = const Value.absent(),
    this.outputId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       assetId = Value(assetId),
       versionId = Value(versionId),
       copyId = Value(copyId),
       stagePath = Value(stagePath),
       finalPath = Value(finalPath),
       displayName = Value(displayName),
       sourceType = Value(sourceType),
       createdUtc = Value(createdUtc),
       phase = Value(phase);
  static Insertable<OperationRow> custom({
    Expression<String>? id,
    Expression<String>? assetId,
    Expression<String>? versionId,
    Expression<String>? copyId,
    Expression<String>? stagePath,
    Expression<String>? finalPath,
    Expression<String>? displayName,
    Expression<String>? sourceType,
    Expression<int>? createdUtc,
    Expression<String>? phase,
    Expression<String>? digest,
    Expression<int>? byteCount,
    Expression<String>? format,
    Expression<int>? width,
    Expression<int>? height,
    Expression<int>? frameCount,
    Expression<int>? orientation,
    Expression<String>? outputId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (assetId != null) 'asset_id': assetId,
      if (versionId != null) 'version_id': versionId,
      if (copyId != null) 'copy_id': copyId,
      if (stagePath != null) 'stage_path': stagePath,
      if (finalPath != null) 'final_path': finalPath,
      if (displayName != null) 'display_name': displayName,
      if (sourceType != null) 'source_type': sourceType,
      if (createdUtc != null) 'created_utc': createdUtc,
      if (phase != null) 'phase': phase,
      if (digest != null) 'digest': digest,
      if (byteCount != null) 'byte_count': byteCount,
      if (format != null) 'format': format,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (frameCount != null) 'frame_count': frameCount,
      if (orientation != null) 'orientation': orientation,
      if (outputId != null) 'output_id': outputId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ImportOperationsCompanion copyWith({
    Value<String>? id,
    Value<String>? assetId,
    Value<String>? versionId,
    Value<String>? copyId,
    Value<String>? stagePath,
    Value<String>? finalPath,
    Value<String>? displayName,
    Value<String>? sourceType,
    Value<int>? createdUtc,
    Value<String>? phase,
    Value<String?>? digest,
    Value<int?>? byteCount,
    Value<String?>? format,
    Value<int?>? width,
    Value<int?>? height,
    Value<int?>? frameCount,
    Value<int?>? orientation,
    Value<String?>? outputId,
    Value<int>? rowid,
  }) {
    return ImportOperationsCompanion(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      versionId: versionId ?? this.versionId,
      copyId: copyId ?? this.copyId,
      stagePath: stagePath ?? this.stagePath,
      finalPath: finalPath ?? this.finalPath,
      displayName: displayName ?? this.displayName,
      sourceType: sourceType ?? this.sourceType,
      createdUtc: createdUtc ?? this.createdUtc,
      phase: phase ?? this.phase,
      digest: digest ?? this.digest,
      byteCount: byteCount ?? this.byteCount,
      format: format ?? this.format,
      width: width ?? this.width,
      height: height ?? this.height,
      frameCount: frameCount ?? this.frameCount,
      orientation: orientation ?? this.orientation,
      outputId: outputId ?? this.outputId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (versionId.present) {
      map['version_id'] = Variable<String>(versionId.value);
    }
    if (copyId.present) {
      map['copy_id'] = Variable<String>(copyId.value);
    }
    if (stagePath.present) {
      map['stage_path'] = Variable<String>(stagePath.value);
    }
    if (finalPath.present) {
      map['final_path'] = Variable<String>(finalPath.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (sourceType.present) {
      map['source_type'] = Variable<String>(sourceType.value);
    }
    if (createdUtc.present) {
      map['created_utc'] = Variable<int>(createdUtc.value);
    }
    if (phase.present) {
      map['phase'] = Variable<String>(phase.value);
    }
    if (digest.present) {
      map['digest'] = Variable<String>(digest.value);
    }
    if (byteCount.present) {
      map['byte_count'] = Variable<int>(byteCount.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (frameCount.present) {
      map['frame_count'] = Variable<int>(frameCount.value);
    }
    if (orientation.present) {
      map['orientation'] = Variable<int>(orientation.value);
    }
    if (outputId.present) {
      map['output_id'] = Variable<String>(outputId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImportOperationsCompanion(')
          ..write('id: $id, ')
          ..write('assetId: $assetId, ')
          ..write('versionId: $versionId, ')
          ..write('copyId: $copyId, ')
          ..write('stagePath: $stagePath, ')
          ..write('finalPath: $finalPath, ')
          ..write('displayName: $displayName, ')
          ..write('sourceType: $sourceType, ')
          ..write('createdUtc: $createdUtc, ')
          ..write('phase: $phase, ')
          ..write('digest: $digest, ')
          ..write('byteCount: $byteCount, ')
          ..write('format: $format, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('frameCount: $frameCount, ')
          ..write('orientation: $orientation, ')
          ..write('outputId: $outputId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TagsTable extends Tags with TableInfo<$TagsTable, TagRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameKeyMeta = const VerificationMeta(
    'nameKey',
  );
  @override
  late final GeneratedColumn<String> nameKey = GeneratedColumn<String>(
    'name_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, nameKey];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<TagRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('name_key')) {
      context.handle(
        _nameKeyMeta,
        nameKey.isAcceptableOrUnknown(data['name_key']!, _nameKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_nameKeyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TagRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TagRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nameKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_key'],
      )!,
    );
  }

  @override
  $TagsTable createAlias(String alias) {
    return $TagsTable(attachedDatabase, alias);
  }
}

class TagRow extends DataClass implements Insertable<TagRow> {
  final String id;
  final String name;
  final String nameKey;
  const TagRow({required this.id, required this.name, required this.nameKey});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['name_key'] = Variable<String>(nameKey);
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(
      id: Value(id),
      name: Value(name),
      nameKey: Value(nameKey),
    );
  }

  factory TagRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TagRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      nameKey: serializer.fromJson<String>(json['nameKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'nameKey': serializer.toJson<String>(nameKey),
    };
  }

  TagRow copyWith({String? id, String? name, String? nameKey}) => TagRow(
    id: id ?? this.id,
    name: name ?? this.name,
    nameKey: nameKey ?? this.nameKey,
  );
  TagRow copyWithCompanion(TagsCompanion data) {
    return TagRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      nameKey: data.nameKey.present ? data.nameKey.value : this.nameKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TagRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameKey: $nameKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, nameKey);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TagRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.nameKey == this.nameKey);
}

class TagsCompanion extends UpdateCompanion<TagRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> nameKey;
  final Value<int> rowid;
  const TagsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameKey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TagsCompanion.insert({
    required String id,
    required String name,
    required String nameKey,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       nameKey = Value(nameKey);
  static Insertable<TagRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? nameKey,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (nameKey != null) 'name_key': nameKey,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TagsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? nameKey,
    Value<int>? rowid,
  }) {
    return TagsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      nameKey: nameKey ?? this.nameKey,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameKey.present) {
      map['name_key'] = Variable<String>(nameKey.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameKey: $nameKey, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AssetTagsTable extends AssetTags
    with TableInfo<$AssetTagsTable, AssetTag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssetTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _assetIdMeta = const VerificationMeta(
    'assetId',
  );
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
    'asset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES assets (id)',
    ),
  );
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<String> tagId = GeneratedColumn<String>(
    'tag_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tags (id)',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [assetId, tagId, position];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'asset_tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<AssetTag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('asset_id')) {
      context.handle(
        _assetIdMeta,
        assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_assetIdMeta);
    }
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {assetId, tagId};
  @override
  AssetTag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AssetTag(
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_id'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $AssetTagsTable createAlias(String alias) {
    return $AssetTagsTable(attachedDatabase, alias);
  }
}

class AssetTag extends DataClass implements Insertable<AssetTag> {
  final String assetId;
  final String tagId;
  final int position;
  const AssetTag({
    required this.assetId,
    required this.tagId,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['asset_id'] = Variable<String>(assetId);
    map['tag_id'] = Variable<String>(tagId);
    map['position'] = Variable<int>(position);
    return map;
  }

  AssetTagsCompanion toCompanion(bool nullToAbsent) {
    return AssetTagsCompanion(
      assetId: Value(assetId),
      tagId: Value(tagId),
      position: Value(position),
    );
  }

  factory AssetTag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AssetTag(
      assetId: serializer.fromJson<String>(json['assetId']),
      tagId: serializer.fromJson<String>(json['tagId']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'assetId': serializer.toJson<String>(assetId),
      'tagId': serializer.toJson<String>(tagId),
      'position': serializer.toJson<int>(position),
    };
  }

  AssetTag copyWith({String? assetId, String? tagId, int? position}) =>
      AssetTag(
        assetId: assetId ?? this.assetId,
        tagId: tagId ?? this.tagId,
        position: position ?? this.position,
      );
  AssetTag copyWithCompanion(AssetTagsCompanion data) {
    return AssetTag(
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AssetTag(')
          ..write('assetId: $assetId, ')
          ..write('tagId: $tagId, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(assetId, tagId, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssetTag &&
          other.assetId == this.assetId &&
          other.tagId == this.tagId &&
          other.position == this.position);
}

class AssetTagsCompanion extends UpdateCompanion<AssetTag> {
  final Value<String> assetId;
  final Value<String> tagId;
  final Value<int> position;
  final Value<int> rowid;
  const AssetTagsCompanion({
    this.assetId = const Value.absent(),
    this.tagId = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AssetTagsCompanion.insert({
    required String assetId,
    required String tagId,
    required int position,
    this.rowid = const Value.absent(),
  }) : assetId = Value(assetId),
       tagId = Value(tagId),
       position = Value(position);
  static Insertable<AssetTag> custom({
    Expression<String>? assetId,
    Expression<String>? tagId,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (assetId != null) 'asset_id': assetId,
      if (tagId != null) 'tag_id': tagId,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AssetTagsCompanion copyWith({
    Value<String>? assetId,
    Value<String>? tagId,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return AssetTagsCompanion(
      assetId: assetId ?? this.assetId,
      tagId: tagId ?? this.tagId,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<String>(tagId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssetTagsCompanion(')
          ..write('assetId: $assetId, ')
          ..write('tagId: $tagId, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FileLeasesTable extends FileLeases
    with TableInfo<$FileLeasesTable, FileLease> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FileLeasesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionIdMeta = const VerificationMeta(
    'versionId',
  );
  @override
  late final GeneratedColumn<String> versionId = GeneratedColumn<String>(
    'version_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES versions (id)',
    ),
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _purposeMeta = const VerificationMeta(
    'purpose',
  );
  @override
  late final GeneratedColumn<String> purpose = GeneratedColumn<String>(
    'purpose',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdUtcMeta = const VerificationMeta(
    'createdUtc',
  );
  @override
  late final GeneratedColumn<int> createdUtc = GeneratedColumn<int>(
    'created_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    versionId,
    ownerId,
    purpose,
    createdUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'file_leases';
  @override
  VerificationContext validateIntegrity(
    Insertable<FileLease> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('version_id')) {
      context.handle(
        _versionIdMeta,
        versionId.isAcceptableOrUnknown(data['version_id']!, _versionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_versionIdMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('purpose')) {
      context.handle(
        _purposeMeta,
        purpose.isAcceptableOrUnknown(data['purpose']!, _purposeMeta),
      );
    } else if (isInserting) {
      context.missing(_purposeMeta);
    }
    if (data.containsKey('created_utc')) {
      context.handle(
        _createdUtcMeta,
        createdUtc.isAcceptableOrUnknown(data['created_utc']!, _createdUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_createdUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FileLease map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FileLease(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      versionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version_id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      purpose: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}purpose'],
      )!,
      createdUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_utc'],
      )!,
    );
  }

  @override
  $FileLeasesTable createAlias(String alias) {
    return $FileLeasesTable(attachedDatabase, alias);
  }
}

class FileLease extends DataClass implements Insertable<FileLease> {
  final String id;
  final String versionId;
  final String ownerId;
  final String purpose;
  final int createdUtc;
  const FileLease({
    required this.id,
    required this.versionId,
    required this.ownerId,
    required this.purpose,
    required this.createdUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['version_id'] = Variable<String>(versionId);
    map['owner_id'] = Variable<String>(ownerId);
    map['purpose'] = Variable<String>(purpose);
    map['created_utc'] = Variable<int>(createdUtc);
    return map;
  }

  FileLeasesCompanion toCompanion(bool nullToAbsent) {
    return FileLeasesCompanion(
      id: Value(id),
      versionId: Value(versionId),
      ownerId: Value(ownerId),
      purpose: Value(purpose),
      createdUtc: Value(createdUtc),
    );
  }

  factory FileLease.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FileLease(
      id: serializer.fromJson<String>(json['id']),
      versionId: serializer.fromJson<String>(json['versionId']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      purpose: serializer.fromJson<String>(json['purpose']),
      createdUtc: serializer.fromJson<int>(json['createdUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'versionId': serializer.toJson<String>(versionId),
      'ownerId': serializer.toJson<String>(ownerId),
      'purpose': serializer.toJson<String>(purpose),
      'createdUtc': serializer.toJson<int>(createdUtc),
    };
  }

  FileLease copyWith({
    String? id,
    String? versionId,
    String? ownerId,
    String? purpose,
    int? createdUtc,
  }) => FileLease(
    id: id ?? this.id,
    versionId: versionId ?? this.versionId,
    ownerId: ownerId ?? this.ownerId,
    purpose: purpose ?? this.purpose,
    createdUtc: createdUtc ?? this.createdUtc,
  );
  FileLease copyWithCompanion(FileLeasesCompanion data) {
    return FileLease(
      id: data.id.present ? data.id.value : this.id,
      versionId: data.versionId.present ? data.versionId.value : this.versionId,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      purpose: data.purpose.present ? data.purpose.value : this.purpose,
      createdUtc: data.createdUtc.present
          ? data.createdUtc.value
          : this.createdUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FileLease(')
          ..write('id: $id, ')
          ..write('versionId: $versionId, ')
          ..write('ownerId: $ownerId, ')
          ..write('purpose: $purpose, ')
          ..write('createdUtc: $createdUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, versionId, ownerId, purpose, createdUtc);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FileLease &&
          other.id == this.id &&
          other.versionId == this.versionId &&
          other.ownerId == this.ownerId &&
          other.purpose == this.purpose &&
          other.createdUtc == this.createdUtc);
}

class FileLeasesCompanion extends UpdateCompanion<FileLease> {
  final Value<String> id;
  final Value<String> versionId;
  final Value<String> ownerId;
  final Value<String> purpose;
  final Value<int> createdUtc;
  final Value<int> rowid;
  const FileLeasesCompanion({
    this.id = const Value.absent(),
    this.versionId = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.purpose = const Value.absent(),
    this.createdUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FileLeasesCompanion.insert({
    required String id,
    required String versionId,
    required String ownerId,
    required String purpose,
    required int createdUtc,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       versionId = Value(versionId),
       ownerId = Value(ownerId),
       purpose = Value(purpose),
       createdUtc = Value(createdUtc);
  static Insertable<FileLease> custom({
    Expression<String>? id,
    Expression<String>? versionId,
    Expression<String>? ownerId,
    Expression<String>? purpose,
    Expression<int>? createdUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (versionId != null) 'version_id': versionId,
      if (ownerId != null) 'owner_id': ownerId,
      if (purpose != null) 'purpose': purpose,
      if (createdUtc != null) 'created_utc': createdUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FileLeasesCompanion copyWith({
    Value<String>? id,
    Value<String>? versionId,
    Value<String>? ownerId,
    Value<String>? purpose,
    Value<int>? createdUtc,
    Value<int>? rowid,
  }) {
    return FileLeasesCompanion(
      id: id ?? this.id,
      versionId: versionId ?? this.versionId,
      ownerId: ownerId ?? this.ownerId,
      purpose: purpose ?? this.purpose,
      createdUtc: createdUtc ?? this.createdUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (versionId.present) {
      map['version_id'] = Variable<String>(versionId.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (purpose.present) {
      map['purpose'] = Variable<String>(purpose.value);
    }
    if (createdUtc.present) {
      map['created_utc'] = Variable<int>(createdUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FileLeasesCompanion(')
          ..write('id: $id, ')
          ..write('versionId: $versionId, ')
          ..write('ownerId: $ownerId, ')
          ..write('purpose: $purpose, ')
          ..write('createdUtc: $createdUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VersionReferencesTable extends VersionReferences
    with TableInfo<$VersionReferencesTable, VersionReference> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VersionReferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionIdMeta = const VerificationMeta(
    'versionId',
  );
  @override
  late final GeneratedColumn<String> versionId = GeneratedColumn<String>(
    'version_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES versions (id)',
    ),
  );
  static const VerificationMeta _ownerTypeMeta = const VerificationMeta(
    'ownerType',
  );
  @override
  late final GeneratedColumn<String> ownerType = GeneratedColumn<String>(
    'owner_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, versionId, ownerType, ownerId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'version_references';
  @override
  VerificationContext validateIntegrity(
    Insertable<VersionReference> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('version_id')) {
      context.handle(
        _versionIdMeta,
        versionId.isAcceptableOrUnknown(data['version_id']!, _versionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_versionIdMeta);
    }
    if (data.containsKey('owner_type')) {
      context.handle(
        _ownerTypeMeta,
        ownerType.isAcceptableOrUnknown(data['owner_type']!, _ownerTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerTypeMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {versionId, ownerType, ownerId},
  ];
  @override
  VersionReference map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VersionReference(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      versionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version_id'],
      )!,
      ownerType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_type'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
    );
  }

  @override
  $VersionReferencesTable createAlias(String alias) {
    return $VersionReferencesTable(attachedDatabase, alias);
  }
}

class VersionReference extends DataClass
    implements Insertable<VersionReference> {
  final String id;
  final String versionId;
  final String ownerType;
  final String ownerId;
  const VersionReference({
    required this.id,
    required this.versionId,
    required this.ownerType,
    required this.ownerId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['version_id'] = Variable<String>(versionId);
    map['owner_type'] = Variable<String>(ownerType);
    map['owner_id'] = Variable<String>(ownerId);
    return map;
  }

  VersionReferencesCompanion toCompanion(bool nullToAbsent) {
    return VersionReferencesCompanion(
      id: Value(id),
      versionId: Value(versionId),
      ownerType: Value(ownerType),
      ownerId: Value(ownerId),
    );
  }

  factory VersionReference.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VersionReference(
      id: serializer.fromJson<String>(json['id']),
      versionId: serializer.fromJson<String>(json['versionId']),
      ownerType: serializer.fromJson<String>(json['ownerType']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'versionId': serializer.toJson<String>(versionId),
      'ownerType': serializer.toJson<String>(ownerType),
      'ownerId': serializer.toJson<String>(ownerId),
    };
  }

  VersionReference copyWith({
    String? id,
    String? versionId,
    String? ownerType,
    String? ownerId,
  }) => VersionReference(
    id: id ?? this.id,
    versionId: versionId ?? this.versionId,
    ownerType: ownerType ?? this.ownerType,
    ownerId: ownerId ?? this.ownerId,
  );
  VersionReference copyWithCompanion(VersionReferencesCompanion data) {
    return VersionReference(
      id: data.id.present ? data.id.value : this.id,
      versionId: data.versionId.present ? data.versionId.value : this.versionId,
      ownerType: data.ownerType.present ? data.ownerType.value : this.ownerType,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VersionReference(')
          ..write('id: $id, ')
          ..write('versionId: $versionId, ')
          ..write('ownerType: $ownerType, ')
          ..write('ownerId: $ownerId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, versionId, ownerType, ownerId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VersionReference &&
          other.id == this.id &&
          other.versionId == this.versionId &&
          other.ownerType == this.ownerType &&
          other.ownerId == this.ownerId);
}

class VersionReferencesCompanion extends UpdateCompanion<VersionReference> {
  final Value<String> id;
  final Value<String> versionId;
  final Value<String> ownerType;
  final Value<String> ownerId;
  final Value<int> rowid;
  const VersionReferencesCompanion({
    this.id = const Value.absent(),
    this.versionId = const Value.absent(),
    this.ownerType = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VersionReferencesCompanion.insert({
    required String id,
    required String versionId,
    required String ownerType,
    required String ownerId,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       versionId = Value(versionId),
       ownerType = Value(ownerType),
       ownerId = Value(ownerId);
  static Insertable<VersionReference> custom({
    Expression<String>? id,
    Expression<String>? versionId,
    Expression<String>? ownerType,
    Expression<String>? ownerId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (versionId != null) 'version_id': versionId,
      if (ownerType != null) 'owner_type': ownerType,
      if (ownerId != null) 'owner_id': ownerId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VersionReferencesCompanion copyWith({
    Value<String>? id,
    Value<String>? versionId,
    Value<String>? ownerType,
    Value<String>? ownerId,
    Value<int>? rowid,
  }) {
    return VersionReferencesCompanion(
      id: id ?? this.id,
      versionId: versionId ?? this.versionId,
      ownerType: ownerType ?? this.ownerType,
      ownerId: ownerId ?? this.ownerId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (versionId.present) {
      map['version_id'] = Variable<String>(versionId.value);
    }
    if (ownerType.present) {
      map['owner_type'] = Variable<String>(ownerType.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VersionReferencesCompanion(')
          ..write('id: $id, ')
          ..write('versionId: $versionId, ')
          ..write('ownerType: $ownerType, ')
          ..write('ownerId: $ownerId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PurgeOperationsTable extends PurgeOperations
    with TableInfo<$PurgeOperationsTable, PurgeOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PurgeOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionIdMeta = const VerificationMeta(
    'versionId',
  );
  @override
  late final GeneratedColumn<String> versionId = GeneratedColumn<String>(
    'version_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES versions (id)',
    ),
  );
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _assetIdsJsonMeta = const VerificationMeta(
    'assetIdsJson',
  );
  @override
  late final GeneratedColumn<String> assetIdsJson = GeneratedColumn<String>(
    'asset_ids_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _removeRecordsMeta = const VerificationMeta(
    'removeRecords',
  );
  @override
  late final GeneratedColumn<bool> removeRecords = GeneratedColumn<bool>(
    'remove_records',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("remove_records" IN (0, 1))',
    ),
  );
  static const VerificationMeta _createdUtcMeta = const VerificationMeta(
    'createdUtc',
  );
  @override
  late final GeneratedColumn<int> createdUtc = GeneratedColumn<int>(
    'created_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    versionId,
    relativePath,
    assetIdsJson,
    removeRecords,
    createdUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'purge_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<PurgeOperation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('version_id')) {
      context.handle(
        _versionIdMeta,
        versionId.isAcceptableOrUnknown(data['version_id']!, _versionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_versionIdMeta);
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relativePathMeta);
    }
    if (data.containsKey('asset_ids_json')) {
      context.handle(
        _assetIdsJsonMeta,
        assetIdsJson.isAcceptableOrUnknown(
          data['asset_ids_json']!,
          _assetIdsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_assetIdsJsonMeta);
    }
    if (data.containsKey('remove_records')) {
      context.handle(
        _removeRecordsMeta,
        removeRecords.isAcceptableOrUnknown(
          data['remove_records']!,
          _removeRecordsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_removeRecordsMeta);
    }
    if (data.containsKey('created_utc')) {
      context.handle(
        _createdUtcMeta,
        createdUtc.isAcceptableOrUnknown(data['created_utc']!, _createdUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_createdUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PurgeOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PurgeOperation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      versionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version_id'],
      )!,
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      )!,
      assetIdsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_ids_json'],
      )!,
      removeRecords: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}remove_records'],
      )!,
      createdUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_utc'],
      )!,
    );
  }

  @override
  $PurgeOperationsTable createAlias(String alias) {
    return $PurgeOperationsTable(attachedDatabase, alias);
  }
}

class PurgeOperation extends DataClass implements Insertable<PurgeOperation> {
  final String id;
  final String versionId;
  final String relativePath;
  final String assetIdsJson;
  final bool removeRecords;
  final int createdUtc;
  const PurgeOperation({
    required this.id,
    required this.versionId,
    required this.relativePath,
    required this.assetIdsJson,
    required this.removeRecords,
    required this.createdUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['version_id'] = Variable<String>(versionId);
    map['relative_path'] = Variable<String>(relativePath);
    map['asset_ids_json'] = Variable<String>(assetIdsJson);
    map['remove_records'] = Variable<bool>(removeRecords);
    map['created_utc'] = Variable<int>(createdUtc);
    return map;
  }

  PurgeOperationsCompanion toCompanion(bool nullToAbsent) {
    return PurgeOperationsCompanion(
      id: Value(id),
      versionId: Value(versionId),
      relativePath: Value(relativePath),
      assetIdsJson: Value(assetIdsJson),
      removeRecords: Value(removeRecords),
      createdUtc: Value(createdUtc),
    );
  }

  factory PurgeOperation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PurgeOperation(
      id: serializer.fromJson<String>(json['id']),
      versionId: serializer.fromJson<String>(json['versionId']),
      relativePath: serializer.fromJson<String>(json['relativePath']),
      assetIdsJson: serializer.fromJson<String>(json['assetIdsJson']),
      removeRecords: serializer.fromJson<bool>(json['removeRecords']),
      createdUtc: serializer.fromJson<int>(json['createdUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'versionId': serializer.toJson<String>(versionId),
      'relativePath': serializer.toJson<String>(relativePath),
      'assetIdsJson': serializer.toJson<String>(assetIdsJson),
      'removeRecords': serializer.toJson<bool>(removeRecords),
      'createdUtc': serializer.toJson<int>(createdUtc),
    };
  }

  PurgeOperation copyWith({
    String? id,
    String? versionId,
    String? relativePath,
    String? assetIdsJson,
    bool? removeRecords,
    int? createdUtc,
  }) => PurgeOperation(
    id: id ?? this.id,
    versionId: versionId ?? this.versionId,
    relativePath: relativePath ?? this.relativePath,
    assetIdsJson: assetIdsJson ?? this.assetIdsJson,
    removeRecords: removeRecords ?? this.removeRecords,
    createdUtc: createdUtc ?? this.createdUtc,
  );
  PurgeOperation copyWithCompanion(PurgeOperationsCompanion data) {
    return PurgeOperation(
      id: data.id.present ? data.id.value : this.id,
      versionId: data.versionId.present ? data.versionId.value : this.versionId,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      assetIdsJson: data.assetIdsJson.present
          ? data.assetIdsJson.value
          : this.assetIdsJson,
      removeRecords: data.removeRecords.present
          ? data.removeRecords.value
          : this.removeRecords,
      createdUtc: data.createdUtc.present
          ? data.createdUtc.value
          : this.createdUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PurgeOperation(')
          ..write('id: $id, ')
          ..write('versionId: $versionId, ')
          ..write('relativePath: $relativePath, ')
          ..write('assetIdsJson: $assetIdsJson, ')
          ..write('removeRecords: $removeRecords, ')
          ..write('createdUtc: $createdUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    versionId,
    relativePath,
    assetIdsJson,
    removeRecords,
    createdUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PurgeOperation &&
          other.id == this.id &&
          other.versionId == this.versionId &&
          other.relativePath == this.relativePath &&
          other.assetIdsJson == this.assetIdsJson &&
          other.removeRecords == this.removeRecords &&
          other.createdUtc == this.createdUtc);
}

class PurgeOperationsCompanion extends UpdateCompanion<PurgeOperation> {
  final Value<String> id;
  final Value<String> versionId;
  final Value<String> relativePath;
  final Value<String> assetIdsJson;
  final Value<bool> removeRecords;
  final Value<int> createdUtc;
  final Value<int> rowid;
  const PurgeOperationsCompanion({
    this.id = const Value.absent(),
    this.versionId = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.assetIdsJson = const Value.absent(),
    this.removeRecords = const Value.absent(),
    this.createdUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PurgeOperationsCompanion.insert({
    required String id,
    required String versionId,
    required String relativePath,
    required String assetIdsJson,
    required bool removeRecords,
    required int createdUtc,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       versionId = Value(versionId),
       relativePath = Value(relativePath),
       assetIdsJson = Value(assetIdsJson),
       removeRecords = Value(removeRecords),
       createdUtc = Value(createdUtc);
  static Insertable<PurgeOperation> custom({
    Expression<String>? id,
    Expression<String>? versionId,
    Expression<String>? relativePath,
    Expression<String>? assetIdsJson,
    Expression<bool>? removeRecords,
    Expression<int>? createdUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (versionId != null) 'version_id': versionId,
      if (relativePath != null) 'relative_path': relativePath,
      if (assetIdsJson != null) 'asset_ids_json': assetIdsJson,
      if (removeRecords != null) 'remove_records': removeRecords,
      if (createdUtc != null) 'created_utc': createdUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PurgeOperationsCompanion copyWith({
    Value<String>? id,
    Value<String>? versionId,
    Value<String>? relativePath,
    Value<String>? assetIdsJson,
    Value<bool>? removeRecords,
    Value<int>? createdUtc,
    Value<int>? rowid,
  }) {
    return PurgeOperationsCompanion(
      id: id ?? this.id,
      versionId: versionId ?? this.versionId,
      relativePath: relativePath ?? this.relativePath,
      assetIdsJson: assetIdsJson ?? this.assetIdsJson,
      removeRecords: removeRecords ?? this.removeRecords,
      createdUtc: createdUtc ?? this.createdUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (versionId.present) {
      map['version_id'] = Variable<String>(versionId.value);
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (assetIdsJson.present) {
      map['asset_ids_json'] = Variable<String>(assetIdsJson.value);
    }
    if (removeRecords.present) {
      map['remove_records'] = Variable<bool>(removeRecords.value);
    }
    if (createdUtc.present) {
      map['created_utc'] = Variable<int>(createdUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PurgeOperationsCompanion(')
          ..write('id: $id, ')
          ..write('versionId: $versionId, ')
          ..write('relativePath: $relativePath, ')
          ..write('assetIdsJson: $assetIdsJson, ')
          ..write('removeRecords: $removeRecords, ')
          ..write('createdUtc: $createdUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LibraryMetadataTable extends LibraryMetadata
    with TableInfo<$LibraryMetadataTable, LibraryMetadataData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LibraryMetadataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_metadata';
  @override
  VerificationContext validateIntegrity(
    Insertable<LibraryMetadataData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  LibraryMetadataData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LibraryMetadataData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $LibraryMetadataTable createAlias(String alias) {
    return $LibraryMetadataTable(attachedDatabase, alias);
  }
}

class LibraryMetadataData extends DataClass
    implements Insertable<LibraryMetadataData> {
  final String key;
  final String value;
  const LibraryMetadataData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  LibraryMetadataCompanion toCompanion(bool nullToAbsent) {
    return LibraryMetadataCompanion(key: Value(key), value: Value(value));
  }

  factory LibraryMetadataData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LibraryMetadataData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  LibraryMetadataData copyWith({String? key, String? value}) =>
      LibraryMetadataData(key: key ?? this.key, value: value ?? this.value);
  LibraryMetadataData copyWithCompanion(LibraryMetadataCompanion data) {
    return LibraryMetadataData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LibraryMetadataData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LibraryMetadataData &&
          other.key == this.key &&
          other.value == this.value);
}

class LibraryMetadataCompanion extends UpdateCompanion<LibraryMetadataData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const LibraryMetadataCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LibraryMetadataCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<LibraryMetadataData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LibraryMetadataCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return LibraryMetadataCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LibraryMetadataCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutputReferencesTable extends OutputReferences
    with TableInfo<$OutputReferencesTable, OutputReference> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutputReferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _outputIdMeta = const VerificationMeta(
    'outputId',
  );
  @override
  late final GeneratedColumn<String> outputId = GeneratedColumn<String>(
    'output_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES processed_outputs (id)',
    ),
  );
  static const VerificationMeta _ownerTypeMeta = const VerificationMeta(
    'ownerType',
  );
  @override
  late final GeneratedColumn<String> ownerType = GeneratedColumn<String>(
    'owner_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, outputId, ownerType, ownerId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'output_references';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutputReference> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('output_id')) {
      context.handle(
        _outputIdMeta,
        outputId.isAcceptableOrUnknown(data['output_id']!, _outputIdMeta),
      );
    } else if (isInserting) {
      context.missing(_outputIdMeta);
    }
    if (data.containsKey('owner_type')) {
      context.handle(
        _ownerTypeMeta,
        ownerType.isAcceptableOrUnknown(data['owner_type']!, _ownerTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerTypeMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {outputId, ownerType, ownerId},
  ];
  @override
  OutputReference map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutputReference(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      outputId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}output_id'],
      )!,
      ownerType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_type'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
    );
  }

  @override
  $OutputReferencesTable createAlias(String alias) {
    return $OutputReferencesTable(attachedDatabase, alias);
  }
}

class OutputReference extends DataClass implements Insertable<OutputReference> {
  final String id;
  final String outputId;
  final String ownerType;
  final String ownerId;
  const OutputReference({
    required this.id,
    required this.outputId,
    required this.ownerType,
    required this.ownerId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['output_id'] = Variable<String>(outputId);
    map['owner_type'] = Variable<String>(ownerType);
    map['owner_id'] = Variable<String>(ownerId);
    return map;
  }

  OutputReferencesCompanion toCompanion(bool nullToAbsent) {
    return OutputReferencesCompanion(
      id: Value(id),
      outputId: Value(outputId),
      ownerType: Value(ownerType),
      ownerId: Value(ownerId),
    );
  }

  factory OutputReference.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutputReference(
      id: serializer.fromJson<String>(json['id']),
      outputId: serializer.fromJson<String>(json['outputId']),
      ownerType: serializer.fromJson<String>(json['ownerType']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'outputId': serializer.toJson<String>(outputId),
      'ownerType': serializer.toJson<String>(ownerType),
      'ownerId': serializer.toJson<String>(ownerId),
    };
  }

  OutputReference copyWith({
    String? id,
    String? outputId,
    String? ownerType,
    String? ownerId,
  }) => OutputReference(
    id: id ?? this.id,
    outputId: outputId ?? this.outputId,
    ownerType: ownerType ?? this.ownerType,
    ownerId: ownerId ?? this.ownerId,
  );
  OutputReference copyWithCompanion(OutputReferencesCompanion data) {
    return OutputReference(
      id: data.id.present ? data.id.value : this.id,
      outputId: data.outputId.present ? data.outputId.value : this.outputId,
      ownerType: data.ownerType.present ? data.ownerType.value : this.ownerType,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutputReference(')
          ..write('id: $id, ')
          ..write('outputId: $outputId, ')
          ..write('ownerType: $ownerType, ')
          ..write('ownerId: $ownerId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, outputId, ownerType, ownerId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutputReference &&
          other.id == this.id &&
          other.outputId == this.outputId &&
          other.ownerType == this.ownerType &&
          other.ownerId == this.ownerId);
}

class OutputReferencesCompanion extends UpdateCompanion<OutputReference> {
  final Value<String> id;
  final Value<String> outputId;
  final Value<String> ownerType;
  final Value<String> ownerId;
  final Value<int> rowid;
  const OutputReferencesCompanion({
    this.id = const Value.absent(),
    this.outputId = const Value.absent(),
    this.ownerType = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutputReferencesCompanion.insert({
    required String id,
    required String outputId,
    required String ownerType,
    required String ownerId,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       outputId = Value(outputId),
       ownerType = Value(ownerType),
       ownerId = Value(ownerId);
  static Insertable<OutputReference> custom({
    Expression<String>? id,
    Expression<String>? outputId,
    Expression<String>? ownerType,
    Expression<String>? ownerId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (outputId != null) 'output_id': outputId,
      if (ownerType != null) 'owner_type': ownerType,
      if (ownerId != null) 'owner_id': ownerId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutputReferencesCompanion copyWith({
    Value<String>? id,
    Value<String>? outputId,
    Value<String>? ownerType,
    Value<String>? ownerId,
    Value<int>? rowid,
  }) {
    return OutputReferencesCompanion(
      id: id ?? this.id,
      outputId: outputId ?? this.outputId,
      ownerType: ownerType ?? this.ownerType,
      ownerId: ownerId ?? this.ownerId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (outputId.present) {
      map['output_id'] = Variable<String>(outputId.value);
    }
    if (ownerType.present) {
      map['owner_type'] = Variable<String>(ownerType.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutputReferencesCompanion(')
          ..write('id: $id, ')
          ..write('outputId: $outputId, ')
          ..write('ownerType: $ownerType, ')
          ..write('ownerId: $ownerId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutputLeasesTable extends OutputLeases
    with TableInfo<$OutputLeasesTable, OutputLease> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutputLeasesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _outputIdMeta = const VerificationMeta(
    'outputId',
  );
  @override
  late final GeneratedColumn<String> outputId = GeneratedColumn<String>(
    'output_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES processed_outputs (id)',
    ),
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, outputId, ownerId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'output_leases';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutputLease> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('output_id')) {
      context.handle(
        _outputIdMeta,
        outputId.isAcceptableOrUnknown(data['output_id']!, _outputIdMeta),
      );
    } else if (isInserting) {
      context.missing(_outputIdMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutputLease map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutputLease(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      outputId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}output_id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
    );
  }

  @override
  $OutputLeasesTable createAlias(String alias) {
    return $OutputLeasesTable(attachedDatabase, alias);
  }
}

class OutputLease extends DataClass implements Insertable<OutputLease> {
  final String id;
  final String outputId;
  final String ownerId;
  const OutputLease({
    required this.id,
    required this.outputId,
    required this.ownerId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['output_id'] = Variable<String>(outputId);
    map['owner_id'] = Variable<String>(ownerId);
    return map;
  }

  OutputLeasesCompanion toCompanion(bool nullToAbsent) {
    return OutputLeasesCompanion(
      id: Value(id),
      outputId: Value(outputId),
      ownerId: Value(ownerId),
    );
  }

  factory OutputLease.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutputLease(
      id: serializer.fromJson<String>(json['id']),
      outputId: serializer.fromJson<String>(json['outputId']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'outputId': serializer.toJson<String>(outputId),
      'ownerId': serializer.toJson<String>(ownerId),
    };
  }

  OutputLease copyWith({String? id, String? outputId, String? ownerId}) =>
      OutputLease(
        id: id ?? this.id,
        outputId: outputId ?? this.outputId,
        ownerId: ownerId ?? this.ownerId,
      );
  OutputLease copyWithCompanion(OutputLeasesCompanion data) {
    return OutputLease(
      id: data.id.present ? data.id.value : this.id,
      outputId: data.outputId.present ? data.outputId.value : this.outputId,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutputLease(')
          ..write('id: $id, ')
          ..write('outputId: $outputId, ')
          ..write('ownerId: $ownerId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, outputId, ownerId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutputLease &&
          other.id == this.id &&
          other.outputId == this.outputId &&
          other.ownerId == this.ownerId);
}

class OutputLeasesCompanion extends UpdateCompanion<OutputLease> {
  final Value<String> id;
  final Value<String> outputId;
  final Value<String> ownerId;
  final Value<int> rowid;
  const OutputLeasesCompanion({
    this.id = const Value.absent(),
    this.outputId = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutputLeasesCompanion.insert({
    required String id,
    required String outputId,
    required String ownerId,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       outputId = Value(outputId),
       ownerId = Value(ownerId);
  static Insertable<OutputLease> custom({
    Expression<String>? id,
    Expression<String>? outputId,
    Expression<String>? ownerId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (outputId != null) 'output_id': outputId,
      if (ownerId != null) 'owner_id': ownerId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutputLeasesCompanion copyWith({
    Value<String>? id,
    Value<String>? outputId,
    Value<String>? ownerId,
    Value<int>? rowid,
  }) {
    return OutputLeasesCompanion(
      id: id ?? this.id,
      outputId: outputId ?? this.outputId,
      ownerId: ownerId ?? this.ownerId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (outputId.present) {
      map['output_id'] = Variable<String>(outputId.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutputLeasesCompanion(')
          ..write('id: $id, ')
          ..write('outputId: $outputId, ')
          ..write('ownerId: $ownerId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SavedOutputOriginsTable extends SavedOutputOrigins
    with TableInfo<$SavedOutputOriginsTable, SavedOutputOrigin> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedOutputOriginsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _outputIdMeta = const VerificationMeta(
    'outputId',
  );
  @override
  late final GeneratedColumn<String> outputId = GeneratedColumn<String>(
    'output_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionIdMeta = const VerificationMeta(
    'versionId',
  );
  @override
  late final GeneratedColumn<String> versionId = GeneratedColumn<String>(
    'version_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES versions (id)',
    ),
  );
  static const VerificationMeta _requestJsonMeta = const VerificationMeta(
    'requestJson',
  );
  @override
  late final GeneratedColumn<String> requestJson = GeneratedColumn<String>(
    'request_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdUtcMeta = const VerificationMeta(
    'createdUtc',
  );
  @override
  late final GeneratedColumn<int> createdUtc = GeneratedColumn<int>(
    'created_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    outputId,
    versionId,
    requestJson,
    createdUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_output_origins';
  @override
  VerificationContext validateIntegrity(
    Insertable<SavedOutputOrigin> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('output_id')) {
      context.handle(
        _outputIdMeta,
        outputId.isAcceptableOrUnknown(data['output_id']!, _outputIdMeta),
      );
    } else if (isInserting) {
      context.missing(_outputIdMeta);
    }
    if (data.containsKey('version_id')) {
      context.handle(
        _versionIdMeta,
        versionId.isAcceptableOrUnknown(data['version_id']!, _versionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_versionIdMeta);
    }
    if (data.containsKey('request_json')) {
      context.handle(
        _requestJsonMeta,
        requestJson.isAcceptableOrUnknown(
          data['request_json']!,
          _requestJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_requestJsonMeta);
    }
    if (data.containsKey('created_utc')) {
      context.handle(
        _createdUtcMeta,
        createdUtc.isAcceptableOrUnknown(data['created_utc']!, _createdUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_createdUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {outputId};
  @override
  SavedOutputOrigin map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedOutputOrigin(
      outputId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}output_id'],
      )!,
      versionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version_id'],
      )!,
      requestJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_json'],
      )!,
      createdUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_utc'],
      )!,
    );
  }

  @override
  $SavedOutputOriginsTable createAlias(String alias) {
    return $SavedOutputOriginsTable(attachedDatabase, alias);
  }
}

class SavedOutputOrigin extends DataClass
    implements Insertable<SavedOutputOrigin> {
  final String outputId;
  final String versionId;
  final String requestJson;
  final int createdUtc;
  const SavedOutputOrigin({
    required this.outputId,
    required this.versionId,
    required this.requestJson,
    required this.createdUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['output_id'] = Variable<String>(outputId);
    map['version_id'] = Variable<String>(versionId);
    map['request_json'] = Variable<String>(requestJson);
    map['created_utc'] = Variable<int>(createdUtc);
    return map;
  }

  SavedOutputOriginsCompanion toCompanion(bool nullToAbsent) {
    return SavedOutputOriginsCompanion(
      outputId: Value(outputId),
      versionId: Value(versionId),
      requestJson: Value(requestJson),
      createdUtc: Value(createdUtc),
    );
  }

  factory SavedOutputOrigin.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedOutputOrigin(
      outputId: serializer.fromJson<String>(json['outputId']),
      versionId: serializer.fromJson<String>(json['versionId']),
      requestJson: serializer.fromJson<String>(json['requestJson']),
      createdUtc: serializer.fromJson<int>(json['createdUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'outputId': serializer.toJson<String>(outputId),
      'versionId': serializer.toJson<String>(versionId),
      'requestJson': serializer.toJson<String>(requestJson),
      'createdUtc': serializer.toJson<int>(createdUtc),
    };
  }

  SavedOutputOrigin copyWith({
    String? outputId,
    String? versionId,
    String? requestJson,
    int? createdUtc,
  }) => SavedOutputOrigin(
    outputId: outputId ?? this.outputId,
    versionId: versionId ?? this.versionId,
    requestJson: requestJson ?? this.requestJson,
    createdUtc: createdUtc ?? this.createdUtc,
  );
  SavedOutputOrigin copyWithCompanion(SavedOutputOriginsCompanion data) {
    return SavedOutputOrigin(
      outputId: data.outputId.present ? data.outputId.value : this.outputId,
      versionId: data.versionId.present ? data.versionId.value : this.versionId,
      requestJson: data.requestJson.present
          ? data.requestJson.value
          : this.requestJson,
      createdUtc: data.createdUtc.present
          ? data.createdUtc.value
          : this.createdUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavedOutputOrigin(')
          ..write('outputId: $outputId, ')
          ..write('versionId: $versionId, ')
          ..write('requestJson: $requestJson, ')
          ..write('createdUtc: $createdUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(outputId, versionId, requestJson, createdUtc);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedOutputOrigin &&
          other.outputId == this.outputId &&
          other.versionId == this.versionId &&
          other.requestJson == this.requestJson &&
          other.createdUtc == this.createdUtc);
}

class SavedOutputOriginsCompanion extends UpdateCompanion<SavedOutputOrigin> {
  final Value<String> outputId;
  final Value<String> versionId;
  final Value<String> requestJson;
  final Value<int> createdUtc;
  final Value<int> rowid;
  const SavedOutputOriginsCompanion({
    this.outputId = const Value.absent(),
    this.versionId = const Value.absent(),
    this.requestJson = const Value.absent(),
    this.createdUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavedOutputOriginsCompanion.insert({
    required String outputId,
    required String versionId,
    required String requestJson,
    required int createdUtc,
    this.rowid = const Value.absent(),
  }) : outputId = Value(outputId),
       versionId = Value(versionId),
       requestJson = Value(requestJson),
       createdUtc = Value(createdUtc);
  static Insertable<SavedOutputOrigin> custom({
    Expression<String>? outputId,
    Expression<String>? versionId,
    Expression<String>? requestJson,
    Expression<int>? createdUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (outputId != null) 'output_id': outputId,
      if (versionId != null) 'version_id': versionId,
      if (requestJson != null) 'request_json': requestJson,
      if (createdUtc != null) 'created_utc': createdUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavedOutputOriginsCompanion copyWith({
    Value<String>? outputId,
    Value<String>? versionId,
    Value<String>? requestJson,
    Value<int>? createdUtc,
    Value<int>? rowid,
  }) {
    return SavedOutputOriginsCompanion(
      outputId: outputId ?? this.outputId,
      versionId: versionId ?? this.versionId,
      requestJson: requestJson ?? this.requestJson,
      createdUtc: createdUtc ?? this.createdUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (outputId.present) {
      map['output_id'] = Variable<String>(outputId.value);
    }
    if (versionId.present) {
      map['version_id'] = Variable<String>(versionId.value);
    }
    if (requestJson.present) {
      map['request_json'] = Variable<String>(requestJson.value);
    }
    if (createdUtc.present) {
      map['created_utc'] = Variable<int>(createdUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedOutputOriginsCompanion(')
          ..write('outputId: $outputId, ')
          ..write('versionId: $versionId, ')
          ..write('requestJson: $requestJson, ')
          ..write('createdUtc: $createdUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RestoredOutputOriginsTable extends RestoredOutputOrigins
    with TableInfo<$RestoredOutputOriginsTable, RestoredOutputOrigin> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RestoredOutputOriginsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _outputIdMeta = const VerificationMeta(
    'outputId',
  );
  @override
  late final GeneratedColumn<String> outputId = GeneratedColumn<String>(
    'output_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionIdMeta = const VerificationMeta(
    'versionId',
  );
  @override
  late final GeneratedColumn<String> versionId = GeneratedColumn<String>(
    'version_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES versions (id)',
    ),
  );
  static const VerificationMeta _snapshotJsonMeta = const VerificationMeta(
    'snapshotJson',
  );
  @override
  late final GeneratedColumn<String> snapshotJson = GeneratedColumn<String>(
    'snapshot_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [outputId, versionId, snapshotJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'restored_output_origins';
  @override
  VerificationContext validateIntegrity(
    Insertable<RestoredOutputOrigin> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('output_id')) {
      context.handle(
        _outputIdMeta,
        outputId.isAcceptableOrUnknown(data['output_id']!, _outputIdMeta),
      );
    } else if (isInserting) {
      context.missing(_outputIdMeta);
    }
    if (data.containsKey('version_id')) {
      context.handle(
        _versionIdMeta,
        versionId.isAcceptableOrUnknown(data['version_id']!, _versionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_versionIdMeta);
    }
    if (data.containsKey('snapshot_json')) {
      context.handle(
        _snapshotJsonMeta,
        snapshotJson.isAcceptableOrUnknown(
          data['snapshot_json']!,
          _snapshotJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_snapshotJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {outputId};
  @override
  RestoredOutputOrigin map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RestoredOutputOrigin(
      outputId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}output_id'],
      )!,
      versionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version_id'],
      )!,
      snapshotJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot_json'],
      )!,
    );
  }

  @override
  $RestoredOutputOriginsTable createAlias(String alias) {
    return $RestoredOutputOriginsTable(attachedDatabase, alias);
  }
}

class RestoredOutputOrigin extends DataClass
    implements Insertable<RestoredOutputOrigin> {
  final String outputId;
  final String versionId;
  final String snapshotJson;
  const RestoredOutputOrigin({
    required this.outputId,
    required this.versionId,
    required this.snapshotJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['output_id'] = Variable<String>(outputId);
    map['version_id'] = Variable<String>(versionId);
    map['snapshot_json'] = Variable<String>(snapshotJson);
    return map;
  }

  RestoredOutputOriginsCompanion toCompanion(bool nullToAbsent) {
    return RestoredOutputOriginsCompanion(
      outputId: Value(outputId),
      versionId: Value(versionId),
      snapshotJson: Value(snapshotJson),
    );
  }

  factory RestoredOutputOrigin.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RestoredOutputOrigin(
      outputId: serializer.fromJson<String>(json['outputId']),
      versionId: serializer.fromJson<String>(json['versionId']),
      snapshotJson: serializer.fromJson<String>(json['snapshotJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'outputId': serializer.toJson<String>(outputId),
      'versionId': serializer.toJson<String>(versionId),
      'snapshotJson': serializer.toJson<String>(snapshotJson),
    };
  }

  RestoredOutputOrigin copyWith({
    String? outputId,
    String? versionId,
    String? snapshotJson,
  }) => RestoredOutputOrigin(
    outputId: outputId ?? this.outputId,
    versionId: versionId ?? this.versionId,
    snapshotJson: snapshotJson ?? this.snapshotJson,
  );
  RestoredOutputOrigin copyWithCompanion(RestoredOutputOriginsCompanion data) {
    return RestoredOutputOrigin(
      outputId: data.outputId.present ? data.outputId.value : this.outputId,
      versionId: data.versionId.present ? data.versionId.value : this.versionId,
      snapshotJson: data.snapshotJson.present
          ? data.snapshotJson.value
          : this.snapshotJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RestoredOutputOrigin(')
          ..write('outputId: $outputId, ')
          ..write('versionId: $versionId, ')
          ..write('snapshotJson: $snapshotJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(outputId, versionId, snapshotJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RestoredOutputOrigin &&
          other.outputId == this.outputId &&
          other.versionId == this.versionId &&
          other.snapshotJson == this.snapshotJson);
}

class RestoredOutputOriginsCompanion
    extends UpdateCompanion<RestoredOutputOrigin> {
  final Value<String> outputId;
  final Value<String> versionId;
  final Value<String> snapshotJson;
  final Value<int> rowid;
  const RestoredOutputOriginsCompanion({
    this.outputId = const Value.absent(),
    this.versionId = const Value.absent(),
    this.snapshotJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RestoredOutputOriginsCompanion.insert({
    required String outputId,
    required String versionId,
    required String snapshotJson,
    this.rowid = const Value.absent(),
  }) : outputId = Value(outputId),
       versionId = Value(versionId),
       snapshotJson = Value(snapshotJson);
  static Insertable<RestoredOutputOrigin> custom({
    Expression<String>? outputId,
    Expression<String>? versionId,
    Expression<String>? snapshotJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (outputId != null) 'output_id': outputId,
      if (versionId != null) 'version_id': versionId,
      if (snapshotJson != null) 'snapshot_json': snapshotJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RestoredOutputOriginsCompanion copyWith({
    Value<String>? outputId,
    Value<String>? versionId,
    Value<String>? snapshotJson,
    Value<int>? rowid,
  }) {
    return RestoredOutputOriginsCompanion(
      outputId: outputId ?? this.outputId,
      versionId: versionId ?? this.versionId,
      snapshotJson: snapshotJson ?? this.snapshotJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (outputId.present) {
      map['output_id'] = Variable<String>(outputId.value);
    }
    if (versionId.present) {
      map['version_id'] = Variable<String>(versionId.value);
    }
    if (snapshotJson.present) {
      map['snapshot_json'] = Variable<String>(snapshotJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RestoredOutputOriginsCompanion(')
          ..write('outputId: $outputId, ')
          ..write('versionId: $versionId, ')
          ..write('snapshotJson: $snapshotJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ImportedUploadHistoriesTable extends ImportedUploadHistories
    with TableInfo<$ImportedUploadHistoriesTable, ImportedUploadHistory> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImportedUploadHistoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotJsonMeta = const VerificationMeta(
    'snapshotJson',
  );
  @override
  late final GeneratedColumn<String> snapshotJson = GeneratedColumn<String>(
    'snapshot_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, batchId, position, snapshotJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'imported_upload_histories';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImportedUploadHistory> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_batchIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('snapshot_json')) {
      context.handle(
        _snapshotJsonMeta,
        snapshotJson.isAcceptableOrUnknown(
          data['snapshot_json']!,
          _snapshotJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_snapshotJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {batchId, position},
  ];
  @override
  ImportedUploadHistory map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImportedUploadHistory(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      snapshotJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot_json'],
      )!,
    );
  }

  @override
  $ImportedUploadHistoriesTable createAlias(String alias) {
    return $ImportedUploadHistoriesTable(attachedDatabase, alias);
  }
}

class ImportedUploadHistory extends DataClass
    implements Insertable<ImportedUploadHistory> {
  final String id;
  final String batchId;
  final int position;
  final String snapshotJson;
  const ImportedUploadHistory({
    required this.id,
    required this.batchId,
    required this.position,
    required this.snapshotJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['batch_id'] = Variable<String>(batchId);
    map['position'] = Variable<int>(position);
    map['snapshot_json'] = Variable<String>(snapshotJson);
    return map;
  }

  ImportedUploadHistoriesCompanion toCompanion(bool nullToAbsent) {
    return ImportedUploadHistoriesCompanion(
      id: Value(id),
      batchId: Value(batchId),
      position: Value(position),
      snapshotJson: Value(snapshotJson),
    );
  }

  factory ImportedUploadHistory.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImportedUploadHistory(
      id: serializer.fromJson<String>(json['id']),
      batchId: serializer.fromJson<String>(json['batchId']),
      position: serializer.fromJson<int>(json['position']),
      snapshotJson: serializer.fromJson<String>(json['snapshotJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'batchId': serializer.toJson<String>(batchId),
      'position': serializer.toJson<int>(position),
      'snapshotJson': serializer.toJson<String>(snapshotJson),
    };
  }

  ImportedUploadHistory copyWith({
    String? id,
    String? batchId,
    int? position,
    String? snapshotJson,
  }) => ImportedUploadHistory(
    id: id ?? this.id,
    batchId: batchId ?? this.batchId,
    position: position ?? this.position,
    snapshotJson: snapshotJson ?? this.snapshotJson,
  );
  ImportedUploadHistory copyWithCompanion(
    ImportedUploadHistoriesCompanion data,
  ) {
    return ImportedUploadHistory(
      id: data.id.present ? data.id.value : this.id,
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
      position: data.position.present ? data.position.value : this.position,
      snapshotJson: data.snapshotJson.present
          ? data.snapshotJson.value
          : this.snapshotJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImportedUploadHistory(')
          ..write('id: $id, ')
          ..write('batchId: $batchId, ')
          ..write('position: $position, ')
          ..write('snapshotJson: $snapshotJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, batchId, position, snapshotJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportedUploadHistory &&
          other.id == this.id &&
          other.batchId == this.batchId &&
          other.position == this.position &&
          other.snapshotJson == this.snapshotJson);
}

class ImportedUploadHistoriesCompanion
    extends UpdateCompanion<ImportedUploadHistory> {
  final Value<String> id;
  final Value<String> batchId;
  final Value<int> position;
  final Value<String> snapshotJson;
  final Value<int> rowid;
  const ImportedUploadHistoriesCompanion({
    this.id = const Value.absent(),
    this.batchId = const Value.absent(),
    this.position = const Value.absent(),
    this.snapshotJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ImportedUploadHistoriesCompanion.insert({
    required String id,
    required String batchId,
    required int position,
    required String snapshotJson,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       batchId = Value(batchId),
       position = Value(position),
       snapshotJson = Value(snapshotJson);
  static Insertable<ImportedUploadHistory> custom({
    Expression<String>? id,
    Expression<String>? batchId,
    Expression<int>? position,
    Expression<String>? snapshotJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (batchId != null) 'batch_id': batchId,
      if (position != null) 'position': position,
      if (snapshotJson != null) 'snapshot_json': snapshotJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ImportedUploadHistoriesCompanion copyWith({
    Value<String>? id,
    Value<String>? batchId,
    Value<int>? position,
    Value<String>? snapshotJson,
    Value<int>? rowid,
  }) {
    return ImportedUploadHistoriesCompanion(
      id: id ?? this.id,
      batchId: batchId ?? this.batchId,
      position: position ?? this.position,
      snapshotJson: snapshotJson ?? this.snapshotJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (snapshotJson.present) {
      map['snapshot_json'] = Variable<String>(snapshotJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImportedUploadHistoriesCompanion(')
          ..write('id: $id, ')
          ..write('batchId: $batchId, ')
          ..write('position: $position, ')
          ..write('snapshotJson: $snapshotJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RestoreOperationsTable extends RestoreOperations
    with TableInfo<$RestoreOperationsTable, RestoreOperationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RestoreOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phaseMeta = const VerificationMeta('phase');
  @override
  late final GeneratedColumn<String> phase = GeneratedColumn<String>(
    'phase',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdUtcMeta = const VerificationMeta(
    'createdUtc',
  );
  @override
  late final GeneratedColumn<int> createdUtc = GeneratedColumn<int>(
    'created_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, phase, payloadJson, createdUtc];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'restore_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<RestoreOperationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('phase')) {
      context.handle(
        _phaseMeta,
        phase.isAcceptableOrUnknown(data['phase']!, _phaseMeta),
      );
    } else if (isInserting) {
      context.missing(_phaseMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('created_utc')) {
      context.handle(
        _createdUtcMeta,
        createdUtc.isAcceptableOrUnknown(data['created_utc']!, _createdUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_createdUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RestoreOperationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RestoreOperationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      phase: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phase'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      createdUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_utc'],
      )!,
    );
  }

  @override
  $RestoreOperationsTable createAlias(String alias) {
    return $RestoreOperationsTable(attachedDatabase, alias);
  }
}

class RestoreOperationRow extends DataClass
    implements Insertable<RestoreOperationRow> {
  final String id;
  final String phase;
  final String payloadJson;
  final int createdUtc;
  const RestoreOperationRow({
    required this.id,
    required this.phase,
    required this.payloadJson,
    required this.createdUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['phase'] = Variable<String>(phase);
    map['payload_json'] = Variable<String>(payloadJson);
    map['created_utc'] = Variable<int>(createdUtc);
    return map;
  }

  RestoreOperationsCompanion toCompanion(bool nullToAbsent) {
    return RestoreOperationsCompanion(
      id: Value(id),
      phase: Value(phase),
      payloadJson: Value(payloadJson),
      createdUtc: Value(createdUtc),
    );
  }

  factory RestoreOperationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RestoreOperationRow(
      id: serializer.fromJson<String>(json['id']),
      phase: serializer.fromJson<String>(json['phase']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      createdUtc: serializer.fromJson<int>(json['createdUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'phase': serializer.toJson<String>(phase),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'createdUtc': serializer.toJson<int>(createdUtc),
    };
  }

  RestoreOperationRow copyWith({
    String? id,
    String? phase,
    String? payloadJson,
    int? createdUtc,
  }) => RestoreOperationRow(
    id: id ?? this.id,
    phase: phase ?? this.phase,
    payloadJson: payloadJson ?? this.payloadJson,
    createdUtc: createdUtc ?? this.createdUtc,
  );
  RestoreOperationRow copyWithCompanion(RestoreOperationsCompanion data) {
    return RestoreOperationRow(
      id: data.id.present ? data.id.value : this.id,
      phase: data.phase.present ? data.phase.value : this.phase,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      createdUtc: data.createdUtc.present
          ? data.createdUtc.value
          : this.createdUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RestoreOperationRow(')
          ..write('id: $id, ')
          ..write('phase: $phase, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdUtc: $createdUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, phase, payloadJson, createdUtc);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RestoreOperationRow &&
          other.id == this.id &&
          other.phase == this.phase &&
          other.payloadJson == this.payloadJson &&
          other.createdUtc == this.createdUtc);
}

class RestoreOperationsCompanion extends UpdateCompanion<RestoreOperationRow> {
  final Value<String> id;
  final Value<String> phase;
  final Value<String> payloadJson;
  final Value<int> createdUtc;
  final Value<int> rowid;
  const RestoreOperationsCompanion({
    this.id = const Value.absent(),
    this.phase = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.createdUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RestoreOperationsCompanion.insert({
    required String id,
    required String phase,
    required String payloadJson,
    required int createdUtc,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       phase = Value(phase),
       payloadJson = Value(payloadJson),
       createdUtc = Value(createdUtc);
  static Insertable<RestoreOperationRow> custom({
    Expression<String>? id,
    Expression<String>? phase,
    Expression<String>? payloadJson,
    Expression<int>? createdUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (phase != null) 'phase': phase,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (createdUtc != null) 'created_utc': createdUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RestoreOperationsCompanion copyWith({
    Value<String>? id,
    Value<String>? phase,
    Value<String>? payloadJson,
    Value<int>? createdUtc,
    Value<int>? rowid,
  }) {
    return RestoreOperationsCompanion(
      id: id ?? this.id,
      phase: phase ?? this.phase,
      payloadJson: payloadJson ?? this.payloadJson,
      createdUtc: createdUtc ?? this.createdUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (phase.present) {
      map['phase'] = Variable<String>(phase.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (createdUtc.present) {
      map['created_utc'] = Variable<int>(createdUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RestoreOperationsCompanion(')
          ..write('id: $id, ')
          ..write('phase: $phase, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdUtc: $createdUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DiagnosticRecordsTable extends DiagnosticRecords
    with TableInfo<$DiagnosticRecordsTable, DiagnosticRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DiagnosticRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurredUtcMeta = const VerificationMeta(
    'occurredUtc',
  );
  @override
  late final GeneratedColumn<int> occurredUtc = GeneratedColumn<int>(
    'occurred_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _levelMeta = const VerificationMeta('level');
  @override
  late final GeneratedColumn<String> level = GeneratedColumn<String>(
    'level',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptIdMeta = const VerificationMeta(
    'attemptId',
  );
  @override
  late final GeneratedColumn<String> attemptId = GeneratedColumn<String>(
    'attempt_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentBytesMeta = const VerificationMeta(
    'contentBytes',
  );
  @override
  late final GeneratedColumn<int> contentBytes = GeneratedColumn<int>(
    'content_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    occurredUtc,
    kind,
    level,
    code,
    entityId,
    batchId,
    attemptId,
    payloadJson,
    contentBytes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'diagnostic_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<DiagnosticRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('occurred_utc')) {
      context.handle(
        _occurredUtcMeta,
        occurredUtc.isAcceptableOrUnknown(
          data['occurred_utc']!,
          _occurredUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_occurredUtcMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('level')) {
      context.handle(
        _levelMeta,
        level.isAcceptableOrUnknown(data['level']!, _levelMeta),
      );
    } else if (isInserting) {
      context.missing(_levelMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    }
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    }
    if (data.containsKey('attempt_id')) {
      context.handle(
        _attemptIdMeta,
        attemptId.isAcceptableOrUnknown(data['attempt_id']!, _attemptIdMeta),
      );
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('content_bytes')) {
      context.handle(
        _contentBytesMeta,
        contentBytes.isAcceptableOrUnknown(
          data['content_bytes']!,
          _contentBytesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentBytesMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DiagnosticRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DiagnosticRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      occurredUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}occurred_utc'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      level: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}level'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      ),
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      ),
      attemptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attempt_id'],
      ),
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      contentBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}content_bytes'],
      )!,
    );
  }

  @override
  $DiagnosticRecordsTable createAlias(String alias) {
    return $DiagnosticRecordsTable(attachedDatabase, alias);
  }
}

class DiagnosticRow extends DataClass implements Insertable<DiagnosticRow> {
  final String id;
  final int occurredUtc;
  final String kind;
  final String level;
  final String code;
  final String? entityId;
  final String? batchId;
  final String? attemptId;
  final String payloadJson;
  final int contentBytes;
  const DiagnosticRow({
    required this.id,
    required this.occurredUtc,
    required this.kind,
    required this.level,
    required this.code,
    this.entityId,
    this.batchId,
    this.attemptId,
    required this.payloadJson,
    required this.contentBytes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['occurred_utc'] = Variable<int>(occurredUtc);
    map['kind'] = Variable<String>(kind);
    map['level'] = Variable<String>(level);
    map['code'] = Variable<String>(code);
    if (!nullToAbsent || entityId != null) {
      map['entity_id'] = Variable<String>(entityId);
    }
    if (!nullToAbsent || batchId != null) {
      map['batch_id'] = Variable<String>(batchId);
    }
    if (!nullToAbsent || attemptId != null) {
      map['attempt_id'] = Variable<String>(attemptId);
    }
    map['payload_json'] = Variable<String>(payloadJson);
    map['content_bytes'] = Variable<int>(contentBytes);
    return map;
  }

  DiagnosticRecordsCompanion toCompanion(bool nullToAbsent) {
    return DiagnosticRecordsCompanion(
      id: Value(id),
      occurredUtc: Value(occurredUtc),
      kind: Value(kind),
      level: Value(level),
      code: Value(code),
      entityId: entityId == null && nullToAbsent
          ? const Value.absent()
          : Value(entityId),
      batchId: batchId == null && nullToAbsent
          ? const Value.absent()
          : Value(batchId),
      attemptId: attemptId == null && nullToAbsent
          ? const Value.absent()
          : Value(attemptId),
      payloadJson: Value(payloadJson),
      contentBytes: Value(contentBytes),
    );
  }

  factory DiagnosticRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DiagnosticRow(
      id: serializer.fromJson<String>(json['id']),
      occurredUtc: serializer.fromJson<int>(json['occurredUtc']),
      kind: serializer.fromJson<String>(json['kind']),
      level: serializer.fromJson<String>(json['level']),
      code: serializer.fromJson<String>(json['code']),
      entityId: serializer.fromJson<String?>(json['entityId']),
      batchId: serializer.fromJson<String?>(json['batchId']),
      attemptId: serializer.fromJson<String?>(json['attemptId']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      contentBytes: serializer.fromJson<int>(json['contentBytes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'occurredUtc': serializer.toJson<int>(occurredUtc),
      'kind': serializer.toJson<String>(kind),
      'level': serializer.toJson<String>(level),
      'code': serializer.toJson<String>(code),
      'entityId': serializer.toJson<String?>(entityId),
      'batchId': serializer.toJson<String?>(batchId),
      'attemptId': serializer.toJson<String?>(attemptId),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'contentBytes': serializer.toJson<int>(contentBytes),
    };
  }

  DiagnosticRow copyWith({
    String? id,
    int? occurredUtc,
    String? kind,
    String? level,
    String? code,
    Value<String?> entityId = const Value.absent(),
    Value<String?> batchId = const Value.absent(),
    Value<String?> attemptId = const Value.absent(),
    String? payloadJson,
    int? contentBytes,
  }) => DiagnosticRow(
    id: id ?? this.id,
    occurredUtc: occurredUtc ?? this.occurredUtc,
    kind: kind ?? this.kind,
    level: level ?? this.level,
    code: code ?? this.code,
    entityId: entityId.present ? entityId.value : this.entityId,
    batchId: batchId.present ? batchId.value : this.batchId,
    attemptId: attemptId.present ? attemptId.value : this.attemptId,
    payloadJson: payloadJson ?? this.payloadJson,
    contentBytes: contentBytes ?? this.contentBytes,
  );
  DiagnosticRow copyWithCompanion(DiagnosticRecordsCompanion data) {
    return DiagnosticRow(
      id: data.id.present ? data.id.value : this.id,
      occurredUtc: data.occurredUtc.present
          ? data.occurredUtc.value
          : this.occurredUtc,
      kind: data.kind.present ? data.kind.value : this.kind,
      level: data.level.present ? data.level.value : this.level,
      code: data.code.present ? data.code.value : this.code,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
      attemptId: data.attemptId.present ? data.attemptId.value : this.attemptId,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      contentBytes: data.contentBytes.present
          ? data.contentBytes.value
          : this.contentBytes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DiagnosticRow(')
          ..write('id: $id, ')
          ..write('occurredUtc: $occurredUtc, ')
          ..write('kind: $kind, ')
          ..write('level: $level, ')
          ..write('code: $code, ')
          ..write('entityId: $entityId, ')
          ..write('batchId: $batchId, ')
          ..write('attemptId: $attemptId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('contentBytes: $contentBytes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    occurredUtc,
    kind,
    level,
    code,
    entityId,
    batchId,
    attemptId,
    payloadJson,
    contentBytes,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiagnosticRow &&
          other.id == this.id &&
          other.occurredUtc == this.occurredUtc &&
          other.kind == this.kind &&
          other.level == this.level &&
          other.code == this.code &&
          other.entityId == this.entityId &&
          other.batchId == this.batchId &&
          other.attemptId == this.attemptId &&
          other.payloadJson == this.payloadJson &&
          other.contentBytes == this.contentBytes);
}

class DiagnosticRecordsCompanion extends UpdateCompanion<DiagnosticRow> {
  final Value<String> id;
  final Value<int> occurredUtc;
  final Value<String> kind;
  final Value<String> level;
  final Value<String> code;
  final Value<String?> entityId;
  final Value<String?> batchId;
  final Value<String?> attemptId;
  final Value<String> payloadJson;
  final Value<int> contentBytes;
  final Value<int> rowid;
  const DiagnosticRecordsCompanion({
    this.id = const Value.absent(),
    this.occurredUtc = const Value.absent(),
    this.kind = const Value.absent(),
    this.level = const Value.absent(),
    this.code = const Value.absent(),
    this.entityId = const Value.absent(),
    this.batchId = const Value.absent(),
    this.attemptId = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.contentBytes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DiagnosticRecordsCompanion.insert({
    required String id,
    required int occurredUtc,
    required String kind,
    required String level,
    required String code,
    this.entityId = const Value.absent(),
    this.batchId = const Value.absent(),
    this.attemptId = const Value.absent(),
    required String payloadJson,
    required int contentBytes,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       occurredUtc = Value(occurredUtc),
       kind = Value(kind),
       level = Value(level),
       code = Value(code),
       payloadJson = Value(payloadJson),
       contentBytes = Value(contentBytes);
  static Insertable<DiagnosticRow> custom({
    Expression<String>? id,
    Expression<int>? occurredUtc,
    Expression<String>? kind,
    Expression<String>? level,
    Expression<String>? code,
    Expression<String>? entityId,
    Expression<String>? batchId,
    Expression<String>? attemptId,
    Expression<String>? payloadJson,
    Expression<int>? contentBytes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (occurredUtc != null) 'occurred_utc': occurredUtc,
      if (kind != null) 'kind': kind,
      if (level != null) 'level': level,
      if (code != null) 'code': code,
      if (entityId != null) 'entity_id': entityId,
      if (batchId != null) 'batch_id': batchId,
      if (attemptId != null) 'attempt_id': attemptId,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (contentBytes != null) 'content_bytes': contentBytes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DiagnosticRecordsCompanion copyWith({
    Value<String>? id,
    Value<int>? occurredUtc,
    Value<String>? kind,
    Value<String>? level,
    Value<String>? code,
    Value<String?>? entityId,
    Value<String?>? batchId,
    Value<String?>? attemptId,
    Value<String>? payloadJson,
    Value<int>? contentBytes,
    Value<int>? rowid,
  }) {
    return DiagnosticRecordsCompanion(
      id: id ?? this.id,
      occurredUtc: occurredUtc ?? this.occurredUtc,
      kind: kind ?? this.kind,
      level: level ?? this.level,
      code: code ?? this.code,
      entityId: entityId ?? this.entityId,
      batchId: batchId ?? this.batchId,
      attemptId: attemptId ?? this.attemptId,
      payloadJson: payloadJson ?? this.payloadJson,
      contentBytes: contentBytes ?? this.contentBytes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (occurredUtc.present) {
      map['occurred_utc'] = Variable<int>(occurredUtc.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (level.present) {
      map['level'] = Variable<String>(level.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (attemptId.present) {
      map['attempt_id'] = Variable<String>(attemptId.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (contentBytes.present) {
      map['content_bytes'] = Variable<int>(contentBytes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DiagnosticRecordsCompanion(')
          ..write('id: $id, ')
          ..write('occurredUtc: $occurredUtc, ')
          ..write('kind: $kind, ')
          ..write('level: $level, ')
          ..write('code: $code, ')
          ..write('entityId: $entityId, ')
          ..write('batchId: $batchId, ')
          ..write('attemptId: $attemptId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('contentBytes: $contentBytes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LibraryDatabase extends GeneratedDatabase {
  _$LibraryDatabase(QueryExecutor e) : super(e);
  $LibraryDatabaseManager get managers => $LibraryDatabaseManager(this);
  late final $UploadBatchesTable uploadBatches = $UploadBatchesTable(this);
  late final $UploadProcessingJobsTable uploadProcessingJobs =
      $UploadProcessingJobsTable(this);
  late final $UploadPublicationsTable uploadPublications =
      $UploadPublicationsTable(this);
  late final $UploadAttemptsTable uploadAttempts = $UploadAttemptsTable(this);
  late final $RemoteUploadResultsTable remoteUploadResults =
      $RemoteUploadResultsTable(this);
  late final $UploadResultOperationsTable uploadResultOperations =
      $UploadResultOperationsTable(this);
  late final $UploadEventsTable uploadEvents = $UploadEventsTable(this);
  late final $ProviderTargetsTable providerTargets = $ProviderTargetsTable(
    this,
  );
  late final $CredentialOperationsTable credentialOperations =
      $CredentialOperationsTable(this);
  late final $VersionsTable versions = $VersionsTable(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $AssetsTable assets = $AssetsTable(this);
  late final $DeviceCopiesTable deviceCopies = $DeviceCopiesTable(this);
  late final $ProcessedOutputsTable processedOutputs = $ProcessedOutputsTable(
    this,
  );
  late final $ImportOperationsTable importOperations = $ImportOperationsTable(
    this,
  );
  late final $TagsTable tags = $TagsTable(this);
  late final $AssetTagsTable assetTags = $AssetTagsTable(this);
  late final $FileLeasesTable fileLeases = $FileLeasesTable(this);
  late final $VersionReferencesTable versionReferences =
      $VersionReferencesTable(this);
  late final $PurgeOperationsTable purgeOperations = $PurgeOperationsTable(
    this,
  );
  late final $LibraryMetadataTable libraryMetadata = $LibraryMetadataTable(
    this,
  );
  late final $OutputReferencesTable outputReferences = $OutputReferencesTable(
    this,
  );
  late final $OutputLeasesTable outputLeases = $OutputLeasesTable(this);
  late final $SavedOutputOriginsTable savedOutputOrigins =
      $SavedOutputOriginsTable(this);
  late final $RestoredOutputOriginsTable restoredOutputOrigins =
      $RestoredOutputOriginsTable(this);
  late final $ImportedUploadHistoriesTable importedUploadHistories =
      $ImportedUploadHistoriesTable(this);
  late final $RestoreOperationsTable restoreOperations =
      $RestoreOperationsTable(this);
  late final $DiagnosticRecordsTable diagnosticRecords =
      $DiagnosticRecordsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    uploadBatches,
    uploadProcessingJobs,
    uploadPublications,
    uploadAttempts,
    remoteUploadResults,
    uploadResultOperations,
    uploadEvents,
    providerTargets,
    credentialOperations,
    versions,
    categories,
    assets,
    deviceCopies,
    processedOutputs,
    importOperations,
    tags,
    assetTags,
    fileLeases,
    versionReferences,
    purgeOperations,
    libraryMetadata,
    outputReferences,
    outputLeases,
    savedOutputOrigins,
    restoredOutputOrigins,
    importedUploadHistories,
    restoreOperations,
    diagnosticRecords,
  ];
}

typedef $$UploadBatchesTableCreateCompanionBuilder =
    UploadBatchesCompanion Function({
      required String id,
      required String intentId,
      required int createdUtc,
      Value<bool> paused,
      Value<int> rowid,
    });
typedef $$UploadBatchesTableUpdateCompanionBuilder =
    UploadBatchesCompanion Function({
      Value<String> id,
      Value<String> intentId,
      Value<int> createdUtc,
      Value<bool> paused,
      Value<int> rowid,
    });

final class $$UploadBatchesTableReferences
    extends
        BaseReferences<_$LibraryDatabase, $UploadBatchesTable, UploadBatchRow> {
  $$UploadBatchesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<
    $UploadProcessingJobsTable,
    List<UploadProcessingJobRow>
  >
  _uploadProcessingJobsRefsTable(_$LibraryDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.uploadProcessingJobs,
        aliasName: 'upload_batches__id__upload_processing_jobs__batch_id',
      );

  $$UploadProcessingJobsTableProcessedTableManager
  get uploadProcessingJobsRefs {
    final manager = $$UploadProcessingJobsTableTableManager(
      $_db,
      $_db.uploadProcessingJobs,
    ).filter((f) => f.batchId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _uploadProcessingJobsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $UploadPublicationsTable,
    List<UploadPublicationRow>
  >
  _uploadPublicationsRefsTable(_$LibraryDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.uploadPublications,
        aliasName: 'upload_batches__id__upload_publications__batch_id',
      );

  $$UploadPublicationsTableProcessedTableManager get uploadPublicationsRefs {
    final manager = $$UploadPublicationsTableTableManager(
      $_db,
      $_db.uploadPublications,
    ).filter((f) => f.batchId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _uploadPublicationsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$UploadBatchesTableFilterComposer
    extends Composer<_$LibraryDatabase, $UploadBatchesTable> {
  $$UploadBatchesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get intentId => $composableBuilder(
    column: $table.intentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get paused => $composableBuilder(
    column: $table.paused,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> uploadProcessingJobsRefs(
    Expression<bool> Function($$UploadProcessingJobsTableFilterComposer f) f,
  ) {
    final $$UploadProcessingJobsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.uploadProcessingJobs,
      getReferencedColumn: (t) => t.batchId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UploadProcessingJobsTableFilterComposer(
            $db: $db,
            $table: $db.uploadProcessingJobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> uploadPublicationsRefs(
    Expression<bool> Function($$UploadPublicationsTableFilterComposer f) f,
  ) {
    final $$UploadPublicationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.uploadPublications,
      getReferencedColumn: (t) => t.batchId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UploadPublicationsTableFilterComposer(
            $db: $db,
            $table: $db.uploadPublications,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$UploadBatchesTableOrderingComposer
    extends Composer<_$LibraryDatabase, $UploadBatchesTable> {
  $$UploadBatchesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get intentId => $composableBuilder(
    column: $table.intentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get paused => $composableBuilder(
    column: $table.paused,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UploadBatchesTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $UploadBatchesTable> {
  $$UploadBatchesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get intentId =>
      $composableBuilder(column: $table.intentId, builder: (column) => column);

  GeneratedColumn<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get paused =>
      $composableBuilder(column: $table.paused, builder: (column) => column);

  Expression<T> uploadProcessingJobsRefs<T extends Object>(
    Expression<T> Function($$UploadProcessingJobsTableAnnotationComposer a) f,
  ) {
    final $$UploadProcessingJobsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.uploadProcessingJobs,
          getReferencedColumn: (t) => t.batchId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$UploadProcessingJobsTableAnnotationComposer(
                $db: $db,
                $table: $db.uploadProcessingJobs,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> uploadPublicationsRefs<T extends Object>(
    Expression<T> Function($$UploadPublicationsTableAnnotationComposer a) f,
  ) {
    final $$UploadPublicationsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.uploadPublications,
          getReferencedColumn: (t) => t.batchId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$UploadPublicationsTableAnnotationComposer(
                $db: $db,
                $table: $db.uploadPublications,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$UploadBatchesTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $UploadBatchesTable,
          UploadBatchRow,
          $$UploadBatchesTableFilterComposer,
          $$UploadBatchesTableOrderingComposer,
          $$UploadBatchesTableAnnotationComposer,
          $$UploadBatchesTableCreateCompanionBuilder,
          $$UploadBatchesTableUpdateCompanionBuilder,
          (UploadBatchRow, $$UploadBatchesTableReferences),
          UploadBatchRow,
          PrefetchHooks Function({
            bool uploadProcessingJobsRefs,
            bool uploadPublicationsRefs,
          })
        > {
  $$UploadBatchesTableTableManager(
    _$LibraryDatabase db,
    $UploadBatchesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UploadBatchesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UploadBatchesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UploadBatchesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> intentId = const Value.absent(),
                Value<int> createdUtc = const Value.absent(),
                Value<bool> paused = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UploadBatchesCompanion(
                id: id,
                intentId: intentId,
                createdUtc: createdUtc,
                paused: paused,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String intentId,
                required int createdUtc,
                Value<bool> paused = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UploadBatchesCompanion.insert(
                id: id,
                intentId: intentId,
                createdUtc: createdUtc,
                paused: paused,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$UploadBatchesTable, UploadBatchRow>(table),
                  $$UploadBatchesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                uploadProcessingJobsRefs = false,
                uploadPublicationsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (uploadProcessingJobsRefs) db.uploadProcessingJobs,
                    if (uploadPublicationsRefs) db.uploadPublications,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (uploadProcessingJobsRefs)
                        await $_getPrefetchedData<
                          UploadBatchRow,
                          $UploadBatchesTable,
                          UploadProcessingJobRow
                        >(
                          currentTable: table,
                          referencedTable: $$UploadBatchesTableReferences
                              ._uploadProcessingJobsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$UploadBatchesTableReferences(
                                db,
                                table,
                                p0,
                              ).uploadProcessingJobsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.batchId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (uploadPublicationsRefs)
                        await $_getPrefetchedData<
                          UploadBatchRow,
                          $UploadBatchesTable,
                          UploadPublicationRow
                        >(
                          currentTable: table,
                          referencedTable: $$UploadBatchesTableReferences
                              ._uploadPublicationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$UploadBatchesTableReferences(
                                db,
                                table,
                                p0,
                              ).uploadPublicationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.batchId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$UploadBatchesTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $UploadBatchesTable,
      UploadBatchRow,
      $$UploadBatchesTableFilterComposer,
      $$UploadBatchesTableOrderingComposer,
      $$UploadBatchesTableAnnotationComposer,
      $$UploadBatchesTableCreateCompanionBuilder,
      $$UploadBatchesTableUpdateCompanionBuilder,
      (UploadBatchRow, $$UploadBatchesTableReferences),
      UploadBatchRow,
      PrefetchHooks Function({
        bool uploadProcessingJobsRefs,
        bool uploadPublicationsRefs,
      })
    >;
typedef $$UploadProcessingJobsTableCreateCompanionBuilder =
    UploadProcessingJobsCompanion Function({
      required String id,
      required String batchId,
      required String policyKey,
      required String requestJson,
      required String state,
      Value<String?> outputId,
      Value<String?> message,
      required int createdUtc,
      required int updatedUtc,
      Value<int> rowid,
    });
typedef $$UploadProcessingJobsTableUpdateCompanionBuilder =
    UploadProcessingJobsCompanion Function({
      Value<String> id,
      Value<String> batchId,
      Value<String> policyKey,
      Value<String> requestJson,
      Value<String> state,
      Value<String?> outputId,
      Value<String?> message,
      Value<int> createdUtc,
      Value<int> updatedUtc,
      Value<int> rowid,
    });

final class $$UploadProcessingJobsTableReferences
    extends
        BaseReferences<
          _$LibraryDatabase,
          $UploadProcessingJobsTable,
          UploadProcessingJobRow
        > {
  $$UploadProcessingJobsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $UploadBatchesTable _batchIdTable(_$LibraryDatabase db) => db
      .uploadBatches
      .createAlias('upload_processing_jobs__batch_id__upload_batches__id');

  $$UploadBatchesTableProcessedTableManager get batchId {
    final $_column = $_itemColumn<String>('batch_id')!;

    final manager = $$UploadBatchesTableTableManager(
      $_db,
      $_db.uploadBatches,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_batchIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<
    $UploadPublicationsTable,
    List<UploadPublicationRow>
  >
  _uploadPublicationsRefsTable(
    _$LibraryDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.uploadPublications,
    aliasName:
        'upload_processing_jobs__id__upload_publications__processing_job_id',
  );

  $$UploadPublicationsTableProcessedTableManager get uploadPublicationsRefs {
    final manager =
        $$UploadPublicationsTableTableManager(
          $_db,
          $_db.uploadPublications,
        ).filter(
          (f) => f.processingJobId.id.sqlEquals($_itemColumn<String>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _uploadPublicationsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$UploadProcessingJobsTableFilterComposer
    extends Composer<_$LibraryDatabase, $UploadProcessingJobsTable> {
  $$UploadProcessingJobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get policyKey => $composableBuilder(
    column: $table.policyKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requestJson => $composableBuilder(
    column: $table.requestJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get outputId => $composableBuilder(
    column: $table.outputId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedUtc => $composableBuilder(
    column: $table.updatedUtc,
    builder: (column) => ColumnFilters(column),
  );

  $$UploadBatchesTableFilterComposer get batchId {
    final $$UploadBatchesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.batchId,
      referencedTable: $db.uploadBatches,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UploadBatchesTableFilterComposer(
            $db: $db,
            $table: $db.uploadBatches,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> uploadPublicationsRefs(
    Expression<bool> Function($$UploadPublicationsTableFilterComposer f) f,
  ) {
    final $$UploadPublicationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.uploadPublications,
      getReferencedColumn: (t) => t.processingJobId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UploadPublicationsTableFilterComposer(
            $db: $db,
            $table: $db.uploadPublications,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$UploadProcessingJobsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $UploadProcessingJobsTable> {
  $$UploadProcessingJobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get policyKey => $composableBuilder(
    column: $table.policyKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requestJson => $composableBuilder(
    column: $table.requestJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get outputId => $composableBuilder(
    column: $table.outputId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedUtc => $composableBuilder(
    column: $table.updatedUtc,
    builder: (column) => ColumnOrderings(column),
  );

  $$UploadBatchesTableOrderingComposer get batchId {
    final $$UploadBatchesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.batchId,
      referencedTable: $db.uploadBatches,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UploadBatchesTableOrderingComposer(
            $db: $db,
            $table: $db.uploadBatches,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$UploadProcessingJobsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $UploadProcessingJobsTable> {
  $$UploadProcessingJobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get policyKey =>
      $composableBuilder(column: $table.policyKey, builder: (column) => column);

  GeneratedColumn<String> get requestJson => $composableBuilder(
    column: $table.requestJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get outputId =>
      $composableBuilder(column: $table.outputId, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);

  GeneratedColumn<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedUtc => $composableBuilder(
    column: $table.updatedUtc,
    builder: (column) => column,
  );

  $$UploadBatchesTableAnnotationComposer get batchId {
    final $$UploadBatchesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.batchId,
      referencedTable: $db.uploadBatches,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UploadBatchesTableAnnotationComposer(
            $db: $db,
            $table: $db.uploadBatches,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> uploadPublicationsRefs<T extends Object>(
    Expression<T> Function($$UploadPublicationsTableAnnotationComposer a) f,
  ) {
    final $$UploadPublicationsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.uploadPublications,
          getReferencedColumn: (t) => t.processingJobId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$UploadPublicationsTableAnnotationComposer(
                $db: $db,
                $table: $db.uploadPublications,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$UploadProcessingJobsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $UploadProcessingJobsTable,
          UploadProcessingJobRow,
          $$UploadProcessingJobsTableFilterComposer,
          $$UploadProcessingJobsTableOrderingComposer,
          $$UploadProcessingJobsTableAnnotationComposer,
          $$UploadProcessingJobsTableCreateCompanionBuilder,
          $$UploadProcessingJobsTableUpdateCompanionBuilder,
          (UploadProcessingJobRow, $$UploadProcessingJobsTableReferences),
          UploadProcessingJobRow,
          PrefetchHooks Function({bool batchId, bool uploadPublicationsRefs})
        > {
  $$UploadProcessingJobsTableTableManager(
    _$LibraryDatabase db,
    $UploadProcessingJobsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UploadProcessingJobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UploadProcessingJobsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$UploadProcessingJobsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> batchId = const Value.absent(),
                Value<String> policyKey = const Value.absent(),
                Value<String> requestJson = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> outputId = const Value.absent(),
                Value<String?> message = const Value.absent(),
                Value<int> createdUtc = const Value.absent(),
                Value<int> updatedUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UploadProcessingJobsCompanion(
                id: id,
                batchId: batchId,
                policyKey: policyKey,
                requestJson: requestJson,
                state: state,
                outputId: outputId,
                message: message,
                createdUtc: createdUtc,
                updatedUtc: updatedUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String batchId,
                required String policyKey,
                required String requestJson,
                required String state,
                Value<String?> outputId = const Value.absent(),
                Value<String?> message = const Value.absent(),
                required int createdUtc,
                required int updatedUtc,
                Value<int> rowid = const Value.absent(),
              }) => UploadProcessingJobsCompanion.insert(
                id: id,
                batchId: batchId,
                policyKey: policyKey,
                requestJson: requestJson,
                state: state,
                outputId: outputId,
                message: message,
                createdUtc: createdUtc,
                updatedUtc: updatedUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $UploadProcessingJobsTable,
                    UploadProcessingJobRow
                  >(table),
                  $$UploadProcessingJobsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({batchId = false, uploadPublicationsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (uploadPublicationsRefs) db.uploadPublications,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (batchId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.batchId,
                            referencedTable:
                                $$UploadProcessingJobsTableReferences
                                    ._batchIdTable(db),
                            referencedColumn:
                                $$UploadProcessingJobsTableReferences
                                    ._batchIdTable(db)
                                    .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (uploadPublicationsRefs)
                        await $_getPrefetchedData<
                          UploadProcessingJobRow,
                          $UploadProcessingJobsTable,
                          UploadPublicationRow
                        >(
                          currentTable: table,
                          referencedTable: $$UploadProcessingJobsTableReferences
                              ._uploadPublicationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$UploadProcessingJobsTableReferences(
                                db,
                                table,
                                p0,
                              ).uploadPublicationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.processingJobId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$UploadProcessingJobsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $UploadProcessingJobsTable,
      UploadProcessingJobRow,
      $$UploadProcessingJobsTableFilterComposer,
      $$UploadProcessingJobsTableOrderingComposer,
      $$UploadProcessingJobsTableAnnotationComposer,
      $$UploadProcessingJobsTableCreateCompanionBuilder,
      $$UploadProcessingJobsTableUpdateCompanionBuilder,
      (UploadProcessingJobRow, $$UploadProcessingJobsTableReferences),
      UploadProcessingJobRow,
      PrefetchHooks Function({bool batchId, bool uploadPublicationsRefs})
    >;
typedef $$UploadPublicationsTableCreateCompanionBuilder =
    UploadPublicationsCompanion Function({
      required String id,
      required String batchId,
      Value<String?> processingJobId,
      required int position,
      required String inputJson,
      required String targetJson,
      required String targetId,
      required String versionDigest,
      required int byteCount,
      required String policyKey,
      required String state,
      Value<int> attemptCount,
      Value<int> generation,
      Value<bool> userPaused,
      Value<String?> waitReason,
      Value<int?> retryDelayMicros,
      Value<int> accumulatedRunningMicros,
      Value<String?> currentAttemptId,
      Value<String?> resultId,
      Value<String?> message,
      required int createdUtc,
      required int updatedUtc,
      Value<int> rowid,
    });
typedef $$UploadPublicationsTableUpdateCompanionBuilder =
    UploadPublicationsCompanion Function({
      Value<String> id,
      Value<String> batchId,
      Value<String?> processingJobId,
      Value<int> position,
      Value<String> inputJson,
      Value<String> targetJson,
      Value<String> targetId,
      Value<String> versionDigest,
      Value<int> byteCount,
      Value<String> policyKey,
      Value<String> state,
      Value<int> attemptCount,
      Value<int> generation,
      Value<bool> userPaused,
      Value<String?> waitReason,
      Value<int?> retryDelayMicros,
      Value<int> accumulatedRunningMicros,
      Value<String?> currentAttemptId,
      Value<String?> resultId,
      Value<String?> message,
      Value<int> createdUtc,
      Value<int> updatedUtc,
      Value<int> rowid,
    });

final class $$UploadPublicationsTableReferences
    extends
        BaseReferences<
          _$LibraryDatabase,
          $UploadPublicationsTable,
          UploadPublicationRow
        > {
  $$UploadPublicationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $UploadBatchesTable _batchIdTable(_$LibraryDatabase db) => db
      .uploadBatches
      .createAlias('upload_publications__batch_id__upload_batches__id');

  $$UploadBatchesTableProcessedTableManager get batchId {
    final $_column = $_itemColumn<String>('batch_id')!;

    final manager = $$UploadBatchesTableTableManager(
      $_db,
      $_db.uploadBatches,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_batchIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $UploadProcessingJobsTable _processingJobIdTable(
    _$LibraryDatabase db,
  ) => db.uploadProcessingJobs.createAlias(
    'upload_publications__processing_job_id__upload_processing_jobs__id',
  );

  $$UploadProcessingJobsTableProcessedTableManager? get processingJobId {
    final $_column = $_itemColumn<String>('processing_job_id');
    if ($_column == null) return null;
    final manager = $$UploadProcessingJobsTableTableManager(
      $_db,
      $_db.uploadProcessingJobs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_processingJobIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$UploadAttemptsTable, List<UploadAttempt>>
  _uploadAttemptsRefsTable(_$LibraryDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.uploadAttempts,
        aliasName: 'upload_publications__id__upload_attempts__item_id',
      );

  $$UploadAttemptsTableProcessedTableManager get uploadAttemptsRefs {
    final manager = $$UploadAttemptsTableTableManager(
      $_db,
      $_db.uploadAttempts,
    ).filter((f) => f.itemId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_uploadAttemptsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$UploadEventsTable, List<UploadEvent>>
  _uploadEventsRefsTable(_$LibraryDatabase db) => MultiTypedResultKey.fromTable(
    db.uploadEvents,
    aliasName: 'upload_publications__id__upload_events__item_id',
  );

  $$UploadEventsTableProcessedTableManager get uploadEventsRefs {
    final manager = $$UploadEventsTableTableManager(
      $_db,
      $_db.uploadEvents,
    ).filter((f) => f.itemId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_uploadEventsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$UploadPublicationsTableFilterComposer
    extends Composer<_$LibraryDatabase, $UploadPublicationsTable> {
  $$UploadPublicationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inputJson => $composableBuilder(
    column: $table.inputJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetJson => $composableBuilder(
    column: $table.targetJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get versionDigest => $composableBuilder(
    column: $table.versionDigest,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteCount => $composableBuilder(
    column: $table.byteCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get policyKey => $composableBuilder(
    column: $table.policyKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get userPaused => $composableBuilder(
    column: $table.userPaused,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get waitReason => $composableBuilder(
    column: $table.waitReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryDelayMicros => $composableBuilder(
    column: $table.retryDelayMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get accumulatedRunningMicros => $composableBuilder(
    column: $table.accumulatedRunningMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentAttemptId => $composableBuilder(
    column: $table.currentAttemptId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resultId => $composableBuilder(
    column: $table.resultId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedUtc => $composableBuilder(
    column: $table.updatedUtc,
    builder: (column) => ColumnFilters(column),
  );

  $$UploadBatchesTableFilterComposer get batchId {
    final $$UploadBatchesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.batchId,
      referencedTable: $db.uploadBatches,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UploadBatchesTableFilterComposer(
            $db: $db,
            $table: $db.uploadBatches,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UploadProcessingJobsTableFilterComposer get processingJobId {
    final $$UploadProcessingJobsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.processingJobId,
      referencedTable: $db.uploadProcessingJobs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UploadProcessingJobsTableFilterComposer(
            $db: $db,
            $table: $db.uploadProcessingJobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> uploadAttemptsRefs(
    Expression<bool> Function($$UploadAttemptsTableFilterComposer f) f,
  ) {
    final $$UploadAttemptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.uploadAttempts,
      getReferencedColumn: (t) => t.itemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UploadAttemptsTableFilterComposer(
            $db: $db,
            $table: $db.uploadAttempts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> uploadEventsRefs(
    Expression<bool> Function($$UploadEventsTableFilterComposer f) f,
  ) {
    final $$UploadEventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.uploadEvents,
      getReferencedColumn: (t) => t.itemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UploadEventsTableFilterComposer(
            $db: $db,
            $table: $db.uploadEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$UploadPublicationsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $UploadPublicationsTable> {
  $$UploadPublicationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inputJson => $composableBuilder(
    column: $table.inputJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetJson => $composableBuilder(
    column: $table.targetJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get versionDigest => $composableBuilder(
    column: $table.versionDigest,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteCount => $composableBuilder(
    column: $table.byteCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get policyKey => $composableBuilder(
    column: $table.policyKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get userPaused => $composableBuilder(
    column: $table.userPaused,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get waitReason => $composableBuilder(
    column: $table.waitReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryDelayMicros => $composableBuilder(
    column: $table.retryDelayMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get accumulatedRunningMicros => $composableBuilder(
    column: $table.accumulatedRunningMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentAttemptId => $composableBuilder(
    column: $table.currentAttemptId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resultId => $composableBuilder(
    column: $table.resultId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedUtc => $composableBuilder(
    column: $table.updatedUtc,
    builder: (column) => ColumnOrderings(column),
  );

  $$UploadBatchesTableOrderingComposer get batchId {
    final $$UploadBatchesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.batchId,
      referencedTable: $db.uploadBatches,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UploadBatchesTableOrderingComposer(
            $db: $db,
            $table: $db.uploadBatches,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UploadProcessingJobsTableOrderingComposer get processingJobId {
    final $$UploadProcessingJobsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.processingJobId,
          referencedTable: $db.uploadProcessingJobs,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$UploadProcessingJobsTableOrderingComposer(
                $db: $db,
                $table: $db.uploadProcessingJobs,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$UploadPublicationsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $UploadPublicationsTable> {
  $$UploadPublicationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get inputJson =>
      $composableBuilder(column: $table.inputJson, builder: (column) => column);

  GeneratedColumn<String> get targetJson => $composableBuilder(
    column: $table.targetJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);

  GeneratedColumn<String> get versionDigest => $composableBuilder(
    column: $table.versionDigest,
    builder: (column) => column,
  );

  GeneratedColumn<int> get byteCount =>
      $composableBuilder(column: $table.byteCount, builder: (column) => column);

  GeneratedColumn<String> get policyKey =>
      $composableBuilder(column: $table.policyKey, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get userPaused => $composableBuilder(
    column: $table.userPaused,
    builder: (column) => column,
  );

  GeneratedColumn<String> get waitReason => $composableBuilder(
    column: $table.waitReason,
    builder: (column) => column,
  );

  GeneratedColumn<int> get retryDelayMicros => $composableBuilder(
    column: $table.retryDelayMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get accumulatedRunningMicros => $composableBuilder(
    column: $table.accumulatedRunningMicros,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currentAttemptId => $composableBuilder(
    column: $table.currentAttemptId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get resultId =>
      $composableBuilder(column: $table.resultId, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);

  GeneratedColumn<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedUtc => $composableBuilder(
    column: $table.updatedUtc,
    builder: (column) => column,
  );

  $$UploadBatchesTableAnnotationComposer get batchId {
    final $$UploadBatchesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.batchId,
      referencedTable: $db.uploadBatches,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UploadBatchesTableAnnotationComposer(
            $db: $db,
            $table: $db.uploadBatches,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UploadProcessingJobsTableAnnotationComposer get processingJobId {
    final $$UploadProcessingJobsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.processingJobId,
          referencedTable: $db.uploadProcessingJobs,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$UploadProcessingJobsTableAnnotationComposer(
                $db: $db,
                $table: $db.uploadProcessingJobs,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  Expression<T> uploadAttemptsRefs<T extends Object>(
    Expression<T> Function($$UploadAttemptsTableAnnotationComposer a) f,
  ) {
    final $$UploadAttemptsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.uploadAttempts,
      getReferencedColumn: (t) => t.itemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UploadAttemptsTableAnnotationComposer(
            $db: $db,
            $table: $db.uploadAttempts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> uploadEventsRefs<T extends Object>(
    Expression<T> Function($$UploadEventsTableAnnotationComposer a) f,
  ) {
    final $$UploadEventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.uploadEvents,
      getReferencedColumn: (t) => t.itemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UploadEventsTableAnnotationComposer(
            $db: $db,
            $table: $db.uploadEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$UploadPublicationsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $UploadPublicationsTable,
          UploadPublicationRow,
          $$UploadPublicationsTableFilterComposer,
          $$UploadPublicationsTableOrderingComposer,
          $$UploadPublicationsTableAnnotationComposer,
          $$UploadPublicationsTableCreateCompanionBuilder,
          $$UploadPublicationsTableUpdateCompanionBuilder,
          (UploadPublicationRow, $$UploadPublicationsTableReferences),
          UploadPublicationRow,
          PrefetchHooks Function({
            bool batchId,
            bool processingJobId,
            bool uploadAttemptsRefs,
            bool uploadEventsRefs,
          })
        > {
  $$UploadPublicationsTableTableManager(
    _$LibraryDatabase db,
    $UploadPublicationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UploadPublicationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UploadPublicationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UploadPublicationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> batchId = const Value.absent(),
                Value<String?> processingJobId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> inputJson = const Value.absent(),
                Value<String> targetJson = const Value.absent(),
                Value<String> targetId = const Value.absent(),
                Value<String> versionDigest = const Value.absent(),
                Value<int> byteCount = const Value.absent(),
                Value<String> policyKey = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<int> generation = const Value.absent(),
                Value<bool> userPaused = const Value.absent(),
                Value<String?> waitReason = const Value.absent(),
                Value<int?> retryDelayMicros = const Value.absent(),
                Value<int> accumulatedRunningMicros = const Value.absent(),
                Value<String?> currentAttemptId = const Value.absent(),
                Value<String?> resultId = const Value.absent(),
                Value<String?> message = const Value.absent(),
                Value<int> createdUtc = const Value.absent(),
                Value<int> updatedUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UploadPublicationsCompanion(
                id: id,
                batchId: batchId,
                processingJobId: processingJobId,
                position: position,
                inputJson: inputJson,
                targetJson: targetJson,
                targetId: targetId,
                versionDigest: versionDigest,
                byteCount: byteCount,
                policyKey: policyKey,
                state: state,
                attemptCount: attemptCount,
                generation: generation,
                userPaused: userPaused,
                waitReason: waitReason,
                retryDelayMicros: retryDelayMicros,
                accumulatedRunningMicros: accumulatedRunningMicros,
                currentAttemptId: currentAttemptId,
                resultId: resultId,
                message: message,
                createdUtc: createdUtc,
                updatedUtc: updatedUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String batchId,
                Value<String?> processingJobId = const Value.absent(),
                required int position,
                required String inputJson,
                required String targetJson,
                required String targetId,
                required String versionDigest,
                required int byteCount,
                required String policyKey,
                required String state,
                Value<int> attemptCount = const Value.absent(),
                Value<int> generation = const Value.absent(),
                Value<bool> userPaused = const Value.absent(),
                Value<String?> waitReason = const Value.absent(),
                Value<int?> retryDelayMicros = const Value.absent(),
                Value<int> accumulatedRunningMicros = const Value.absent(),
                Value<String?> currentAttemptId = const Value.absent(),
                Value<String?> resultId = const Value.absent(),
                Value<String?> message = const Value.absent(),
                required int createdUtc,
                required int updatedUtc,
                Value<int> rowid = const Value.absent(),
              }) => UploadPublicationsCompanion.insert(
                id: id,
                batchId: batchId,
                processingJobId: processingJobId,
                position: position,
                inputJson: inputJson,
                targetJson: targetJson,
                targetId: targetId,
                versionDigest: versionDigest,
                byteCount: byteCount,
                policyKey: policyKey,
                state: state,
                attemptCount: attemptCount,
                generation: generation,
                userPaused: userPaused,
                waitReason: waitReason,
                retryDelayMicros: retryDelayMicros,
                accumulatedRunningMicros: accumulatedRunningMicros,
                currentAttemptId: currentAttemptId,
                resultId: resultId,
                message: message,
                createdUtc: createdUtc,
                updatedUtc: updatedUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$UploadPublicationsTable, UploadPublicationRow>(
                    table,
                  ),
                  $$UploadPublicationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                batchId = false,
                processingJobId = false,
                uploadAttemptsRefs = false,
                uploadEventsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (uploadAttemptsRefs) db.uploadAttempts,
                    if (uploadEventsRefs) db.uploadEvents,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (batchId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.batchId,
                            referencedTable: $$UploadPublicationsTableReferences
                                ._batchIdTable(db),
                            referencedColumn:
                                $$UploadPublicationsTableReferences
                                    ._batchIdTable(db)
                                    .id,
                          ) as T;
                        }
                        if (processingJobId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.processingJobId,
                            referencedTable: $$UploadPublicationsTableReferences
                                ._processingJobIdTable(db),
                            referencedColumn:
                                $$UploadPublicationsTableReferences
                                    ._processingJobIdTable(db)
                                    .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (uploadAttemptsRefs)
                        await $_getPrefetchedData<
                          UploadPublicationRow,
                          $UploadPublicationsTable,
                          UploadAttempt
                        >(
                          currentTable: table,
                          referencedTable: $$UploadPublicationsTableReferences
                              ._uploadAttemptsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$UploadPublicationsTableReferences(
                                db,
                                table,
                                p0,
                              ).uploadAttemptsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.itemId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (uploadEventsRefs)
                        await $_getPrefetchedData<
                          UploadPublicationRow,
                          $UploadPublicationsTable,
                          UploadEvent
                        >(
                          currentTable: table,
                          referencedTable: $$UploadPublicationsTableReferences
                              ._uploadEventsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$UploadPublicationsTableReferences(
                                db,
                                table,
                                p0,
                              ).uploadEventsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.itemId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$UploadPublicationsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $UploadPublicationsTable,
      UploadPublicationRow,
      $$UploadPublicationsTableFilterComposer,
      $$UploadPublicationsTableOrderingComposer,
      $$UploadPublicationsTableAnnotationComposer,
      $$UploadPublicationsTableCreateCompanionBuilder,
      $$UploadPublicationsTableUpdateCompanionBuilder,
      (UploadPublicationRow, $$UploadPublicationsTableReferences),
      UploadPublicationRow,
      PrefetchHooks Function({
        bool batchId,
        bool processingJobId,
        bool uploadAttemptsRefs,
        bool uploadEventsRefs,
      })
    >;
typedef $$UploadAttemptsTableCreateCompanionBuilder =
    UploadAttemptsCompanion Function({
      required String id,
      required String itemId,
      required int generation,
      required int targetGeneration,
      required int startedUtc,
      Value<bool> requestMayHaveStarted,
      Value<int?> endedUtc,
      Value<String?> outcome,
      Value<int> rowid,
    });
typedef $$UploadAttemptsTableUpdateCompanionBuilder =
    UploadAttemptsCompanion Function({
      Value<String> id,
      Value<String> itemId,
      Value<int> generation,
      Value<int> targetGeneration,
      Value<int> startedUtc,
      Value<bool> requestMayHaveStarted,
      Value<int?> endedUtc,
      Value<String?> outcome,
      Value<int> rowid,
    });

final class $$UploadAttemptsTableReferences
    extends
        BaseReferences<_$LibraryDatabase, $UploadAttemptsTable, UploadAttempt> {
  $$UploadAttemptsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $UploadPublicationsTable _itemIdTable(_$LibraryDatabase db) => db
      .uploadPublications
      .createAlias('upload_attempts__item_id__upload_publications__id');

  $$UploadPublicationsTableProcessedTableManager get itemId {
    final $_column = $_itemColumn<String>('item_id')!;

    final manager = $$UploadPublicationsTableTableManager(
      $_db,
      $_db.uploadPublications,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_itemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$UploadAttemptsTableFilterComposer
    extends Composer<_$LibraryDatabase, $UploadAttemptsTable> {
  $$UploadAttemptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get targetGeneration => $composableBuilder(
    column: $table.targetGeneration,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedUtc => $composableBuilder(
    column: $table.startedUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get requestMayHaveStarted => $composableBuilder(
    column: $table.requestMayHaveStarted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endedUtc => $composableBuilder(
    column: $table.endedUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnFilters(column),
  );

  $$UploadPublicationsTableFilterComposer get itemId {
    final $$UploadPublicationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.uploadPublications,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UploadPublicationsTableFilterComposer(
            $db: $db,
            $table: $db.uploadPublications,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$UploadAttemptsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $UploadAttemptsTable> {
  $$UploadAttemptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get targetGeneration => $composableBuilder(
    column: $table.targetGeneration,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedUtc => $composableBuilder(
    column: $table.startedUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get requestMayHaveStarted => $composableBuilder(
    column: $table.requestMayHaveStarted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endedUtc => $composableBuilder(
    column: $table.endedUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnOrderings(column),
  );

  $$UploadPublicationsTableOrderingComposer get itemId {
    final $$UploadPublicationsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.uploadPublications,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UploadPublicationsTableOrderingComposer(
            $db: $db,
            $table: $db.uploadPublications,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$UploadAttemptsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $UploadAttemptsTable> {
  $$UploadAttemptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => column,
  );

  GeneratedColumn<int> get targetGeneration => $composableBuilder(
    column: $table.targetGeneration,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startedUtc => $composableBuilder(
    column: $table.startedUtc,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get requestMayHaveStarted => $composableBuilder(
    column: $table.requestMayHaveStarted,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endedUtc =>
      $composableBuilder(column: $table.endedUtc, builder: (column) => column);

  GeneratedColumn<String> get outcome =>
      $composableBuilder(column: $table.outcome, builder: (column) => column);

  $$UploadPublicationsTableAnnotationComposer get itemId {
    final $$UploadPublicationsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.itemId,
          referencedTable: $db.uploadPublications,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$UploadPublicationsTableAnnotationComposer(
                $db: $db,
                $table: $db.uploadPublications,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$UploadAttemptsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $UploadAttemptsTable,
          UploadAttempt,
          $$UploadAttemptsTableFilterComposer,
          $$UploadAttemptsTableOrderingComposer,
          $$UploadAttemptsTableAnnotationComposer,
          $$UploadAttemptsTableCreateCompanionBuilder,
          $$UploadAttemptsTableUpdateCompanionBuilder,
          (UploadAttempt, $$UploadAttemptsTableReferences),
          UploadAttempt,
          PrefetchHooks Function({bool itemId})
        > {
  $$UploadAttemptsTableTableManager(
    _$LibraryDatabase db,
    $UploadAttemptsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UploadAttemptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UploadAttemptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UploadAttemptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> itemId = const Value.absent(),
                Value<int> generation = const Value.absent(),
                Value<int> targetGeneration = const Value.absent(),
                Value<int> startedUtc = const Value.absent(),
                Value<bool> requestMayHaveStarted = const Value.absent(),
                Value<int?> endedUtc = const Value.absent(),
                Value<String?> outcome = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UploadAttemptsCompanion(
                id: id,
                itemId: itemId,
                generation: generation,
                targetGeneration: targetGeneration,
                startedUtc: startedUtc,
                requestMayHaveStarted: requestMayHaveStarted,
                endedUtc: endedUtc,
                outcome: outcome,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String itemId,
                required int generation,
                required int targetGeneration,
                required int startedUtc,
                Value<bool> requestMayHaveStarted = const Value.absent(),
                Value<int?> endedUtc = const Value.absent(),
                Value<String?> outcome = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UploadAttemptsCompanion.insert(
                id: id,
                itemId: itemId,
                generation: generation,
                targetGeneration: targetGeneration,
                startedUtc: startedUtc,
                requestMayHaveStarted: requestMayHaveStarted,
                endedUtc: endedUtc,
                outcome: outcome,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$UploadAttemptsTable, UploadAttempt>(table),
                  $$UploadAttemptsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({itemId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (itemId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.itemId,
                        referencedTable: $$UploadAttemptsTableReferences
                            ._itemIdTable(db),
                        referencedColumn: $$UploadAttemptsTableReferences
                            ._itemIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$UploadAttemptsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $UploadAttemptsTable,
      UploadAttempt,
      $$UploadAttemptsTableFilterComposer,
      $$UploadAttemptsTableOrderingComposer,
      $$UploadAttemptsTableAnnotationComposer,
      $$UploadAttemptsTableCreateCompanionBuilder,
      $$UploadAttemptsTableUpdateCompanionBuilder,
      (UploadAttempt, $$UploadAttemptsTableReferences),
      UploadAttempt,
      PrefetchHooks Function({bool itemId})
    >;
typedef $$RemoteUploadResultsTableCreateCompanionBuilder =
    RemoteUploadResultsCompanion Function({
      required String id,
      required String attemptId,
      required String inputJson,
      required String targetJson,
      required String targetId,
      required String versionDigest,
      required int byteCount,
      required String policyKey,
      required String remoteId,
      required String directUrl,
      Value<String?> viewerUrl,
      required int confirmedUtc,
      required bool late,
      Value<String?> secretReference,
      Value<bool> managementAvailable,
      Value<String> linkState,
      Value<String?> linkReason,
      Value<int?> linkCheckedUtc,
      Value<int?> lastAccessibleUtc,
      Value<int> probeGeneration,
      Value<int?> probeHttpStatus,
      Value<int> rowid,
    });
typedef $$RemoteUploadResultsTableUpdateCompanionBuilder =
    RemoteUploadResultsCompanion Function({
      Value<String> id,
      Value<String> attemptId,
      Value<String> inputJson,
      Value<String> targetJson,
      Value<String> targetId,
      Value<String> versionDigest,
      Value<int> byteCount,
      Value<String> policyKey,
      Value<String> remoteId,
      Value<String> directUrl,
      Value<String?> viewerUrl,
      Value<int> confirmedUtc,
      Value<bool> late,
      Value<String?> secretReference,
      Value<bool> managementAvailable,
      Value<String> linkState,
      Value<String?> linkReason,
      Value<int?> linkCheckedUtc,
      Value<int?> lastAccessibleUtc,
      Value<int> probeGeneration,
      Value<int?> probeHttpStatus,
      Value<int> rowid,
    });

class $$RemoteUploadResultsTableFilterComposer
    extends Composer<_$LibraryDatabase, $RemoteUploadResultsTable> {
  $$RemoteUploadResultsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attemptId => $composableBuilder(
    column: $table.attemptId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inputJson => $composableBuilder(
    column: $table.inputJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetJson => $composableBuilder(
    column: $table.targetJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get versionDigest => $composableBuilder(
    column: $table.versionDigest,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteCount => $composableBuilder(
    column: $table.byteCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get policyKey => $composableBuilder(
    column: $table.policyKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get directUrl => $composableBuilder(
    column: $table.directUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get viewerUrl => $composableBuilder(
    column: $table.viewerUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get confirmedUtc => $composableBuilder(
    column: $table.confirmedUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get late => $composableBuilder(
    column: $table.late,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get secretReference => $composableBuilder(
    column: $table.secretReference,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get managementAvailable => $composableBuilder(
    column: $table.managementAvailable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get linkState => $composableBuilder(
    column: $table.linkState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get linkReason => $composableBuilder(
    column: $table.linkReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get linkCheckedUtc => $composableBuilder(
    column: $table.linkCheckedUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastAccessibleUtc => $composableBuilder(
    column: $table.lastAccessibleUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get probeGeneration => $composableBuilder(
    column: $table.probeGeneration,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get probeHttpStatus => $composableBuilder(
    column: $table.probeHttpStatus,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RemoteUploadResultsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $RemoteUploadResultsTable> {
  $$RemoteUploadResultsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attemptId => $composableBuilder(
    column: $table.attemptId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inputJson => $composableBuilder(
    column: $table.inputJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetJson => $composableBuilder(
    column: $table.targetJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get versionDigest => $composableBuilder(
    column: $table.versionDigest,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteCount => $composableBuilder(
    column: $table.byteCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get policyKey => $composableBuilder(
    column: $table.policyKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get directUrl => $composableBuilder(
    column: $table.directUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get viewerUrl => $composableBuilder(
    column: $table.viewerUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get confirmedUtc => $composableBuilder(
    column: $table.confirmedUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get late => $composableBuilder(
    column: $table.late,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get secretReference => $composableBuilder(
    column: $table.secretReference,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get managementAvailable => $composableBuilder(
    column: $table.managementAvailable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get linkState => $composableBuilder(
    column: $table.linkState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get linkReason => $composableBuilder(
    column: $table.linkReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get linkCheckedUtc => $composableBuilder(
    column: $table.linkCheckedUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastAccessibleUtc => $composableBuilder(
    column: $table.lastAccessibleUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get probeGeneration => $composableBuilder(
    column: $table.probeGeneration,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get probeHttpStatus => $composableBuilder(
    column: $table.probeHttpStatus,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RemoteUploadResultsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $RemoteUploadResultsTable> {
  $$RemoteUploadResultsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get attemptId =>
      $composableBuilder(column: $table.attemptId, builder: (column) => column);

  GeneratedColumn<String> get inputJson =>
      $composableBuilder(column: $table.inputJson, builder: (column) => column);

  GeneratedColumn<String> get targetJson => $composableBuilder(
    column: $table.targetJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);

  GeneratedColumn<String> get versionDigest => $composableBuilder(
    column: $table.versionDigest,
    builder: (column) => column,
  );

  GeneratedColumn<int> get byteCount =>
      $composableBuilder(column: $table.byteCount, builder: (column) => column);

  GeneratedColumn<String> get policyKey =>
      $composableBuilder(column: $table.policyKey, builder: (column) => column);

  GeneratedColumn<String> get remoteId =>
      $composableBuilder(column: $table.remoteId, builder: (column) => column);

  GeneratedColumn<String> get directUrl =>
      $composableBuilder(column: $table.directUrl, builder: (column) => column);

  GeneratedColumn<String> get viewerUrl =>
      $composableBuilder(column: $table.viewerUrl, builder: (column) => column);

  GeneratedColumn<int> get confirmedUtc => $composableBuilder(
    column: $table.confirmedUtc,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get late =>
      $composableBuilder(column: $table.late, builder: (column) => column);

  GeneratedColumn<String> get secretReference => $composableBuilder(
    column: $table.secretReference,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get managementAvailable => $composableBuilder(
    column: $table.managementAvailable,
    builder: (column) => column,
  );

  GeneratedColumn<String> get linkState =>
      $composableBuilder(column: $table.linkState, builder: (column) => column);

  GeneratedColumn<String> get linkReason => $composableBuilder(
    column: $table.linkReason,
    builder: (column) => column,
  );

  GeneratedColumn<int> get linkCheckedUtc => $composableBuilder(
    column: $table.linkCheckedUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastAccessibleUtc => $composableBuilder(
    column: $table.lastAccessibleUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get probeGeneration => $composableBuilder(
    column: $table.probeGeneration,
    builder: (column) => column,
  );

  GeneratedColumn<int> get probeHttpStatus => $composableBuilder(
    column: $table.probeHttpStatus,
    builder: (column) => column,
  );
}

class $$RemoteUploadResultsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $RemoteUploadResultsTable,
          RemoteUploadResultRow,
          $$RemoteUploadResultsTableFilterComposer,
          $$RemoteUploadResultsTableOrderingComposer,
          $$RemoteUploadResultsTableAnnotationComposer,
          $$RemoteUploadResultsTableCreateCompanionBuilder,
          $$RemoteUploadResultsTableUpdateCompanionBuilder,
          (
            RemoteUploadResultRow,
            BaseReferences<
              _$LibraryDatabase,
              $RemoteUploadResultsTable,
              RemoteUploadResultRow
            >,
          ),
          RemoteUploadResultRow,
          PrefetchHooks Function()
        > {
  $$RemoteUploadResultsTableTableManager(
    _$LibraryDatabase db,
    $RemoteUploadResultsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RemoteUploadResultsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RemoteUploadResultsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$RemoteUploadResultsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> attemptId = const Value.absent(),
                Value<String> inputJson = const Value.absent(),
                Value<String> targetJson = const Value.absent(),
                Value<String> targetId = const Value.absent(),
                Value<String> versionDigest = const Value.absent(),
                Value<int> byteCount = const Value.absent(),
                Value<String> policyKey = const Value.absent(),
                Value<String> remoteId = const Value.absent(),
                Value<String> directUrl = const Value.absent(),
                Value<String?> viewerUrl = const Value.absent(),
                Value<int> confirmedUtc = const Value.absent(),
                Value<bool> late = const Value.absent(),
                Value<String?> secretReference = const Value.absent(),
                Value<bool> managementAvailable = const Value.absent(),
                Value<String> linkState = const Value.absent(),
                Value<String?> linkReason = const Value.absent(),
                Value<int?> linkCheckedUtc = const Value.absent(),
                Value<int?> lastAccessibleUtc = const Value.absent(),
                Value<int> probeGeneration = const Value.absent(),
                Value<int?> probeHttpStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RemoteUploadResultsCompanion(
                id: id,
                attemptId: attemptId,
                inputJson: inputJson,
                targetJson: targetJson,
                targetId: targetId,
                versionDigest: versionDigest,
                byteCount: byteCount,
                policyKey: policyKey,
                remoteId: remoteId,
                directUrl: directUrl,
                viewerUrl: viewerUrl,
                confirmedUtc: confirmedUtc,
                late: late,
                secretReference: secretReference,
                managementAvailable: managementAvailable,
                linkState: linkState,
                linkReason: linkReason,
                linkCheckedUtc: linkCheckedUtc,
                lastAccessibleUtc: lastAccessibleUtc,
                probeGeneration: probeGeneration,
                probeHttpStatus: probeHttpStatus,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String attemptId,
                required String inputJson,
                required String targetJson,
                required String targetId,
                required String versionDigest,
                required int byteCount,
                required String policyKey,
                required String remoteId,
                required String directUrl,
                Value<String?> viewerUrl = const Value.absent(),
                required int confirmedUtc,
                required bool late,
                Value<String?> secretReference = const Value.absent(),
                Value<bool> managementAvailable = const Value.absent(),
                Value<String> linkState = const Value.absent(),
                Value<String?> linkReason = const Value.absent(),
                Value<int?> linkCheckedUtc = const Value.absent(),
                Value<int?> lastAccessibleUtc = const Value.absent(),
                Value<int> probeGeneration = const Value.absent(),
                Value<int?> probeHttpStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RemoteUploadResultsCompanion.insert(
                id: id,
                attemptId: attemptId,
                inputJson: inputJson,
                targetJson: targetJson,
                targetId: targetId,
                versionDigest: versionDigest,
                byteCount: byteCount,
                policyKey: policyKey,
                remoteId: remoteId,
                directUrl: directUrl,
                viewerUrl: viewerUrl,
                confirmedUtc: confirmedUtc,
                late: late,
                secretReference: secretReference,
                managementAvailable: managementAvailable,
                linkState: linkState,
                linkReason: linkReason,
                linkCheckedUtc: linkCheckedUtc,
                lastAccessibleUtc: lastAccessibleUtc,
                probeGeneration: probeGeneration,
                probeHttpStatus: probeHttpStatus,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RemoteUploadResultsTable, RemoteUploadResultRow>(
                    table,
                  ),
                  BaseReferences<
                    _$LibraryDatabase,
                    $RemoteUploadResultsTable,
                    RemoteUploadResultRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RemoteUploadResultsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $RemoteUploadResultsTable,
      RemoteUploadResultRow,
      $$RemoteUploadResultsTableFilterComposer,
      $$RemoteUploadResultsTableOrderingComposer,
      $$RemoteUploadResultsTableAnnotationComposer,
      $$RemoteUploadResultsTableCreateCompanionBuilder,
      $$RemoteUploadResultsTableUpdateCompanionBuilder,
      (
        RemoteUploadResultRow,
        BaseReferences<
          _$LibraryDatabase,
          $RemoteUploadResultsTable,
          RemoteUploadResultRow
        >,
      ),
      RemoteUploadResultRow,
      PrefetchHooks Function()
    >;
typedef $$UploadResultOperationsTableCreateCompanionBuilder =
    UploadResultOperationsCompanion Function({
      required String id,
      required String attemptId,
      required String proposalJson,
      Value<String?> secretReference,
      required int createdUtc,
      Value<int> rowid,
    });
typedef $$UploadResultOperationsTableUpdateCompanionBuilder =
    UploadResultOperationsCompanion Function({
      Value<String> id,
      Value<String> attemptId,
      Value<String> proposalJson,
      Value<String?> secretReference,
      Value<int> createdUtc,
      Value<int> rowid,
    });

class $$UploadResultOperationsTableFilterComposer
    extends Composer<_$LibraryDatabase, $UploadResultOperationsTable> {
  $$UploadResultOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attemptId => $composableBuilder(
    column: $table.attemptId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get proposalJson => $composableBuilder(
    column: $table.proposalJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get secretReference => $composableBuilder(
    column: $table.secretReference,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UploadResultOperationsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $UploadResultOperationsTable> {
  $$UploadResultOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attemptId => $composableBuilder(
    column: $table.attemptId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get proposalJson => $composableBuilder(
    column: $table.proposalJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get secretReference => $composableBuilder(
    column: $table.secretReference,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UploadResultOperationsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $UploadResultOperationsTable> {
  $$UploadResultOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get attemptId =>
      $composableBuilder(column: $table.attemptId, builder: (column) => column);

  GeneratedColumn<String> get proposalJson => $composableBuilder(
    column: $table.proposalJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get secretReference => $composableBuilder(
    column: $table.secretReference,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => column,
  );
}

class $$UploadResultOperationsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $UploadResultOperationsTable,
          UploadResultOperation,
          $$UploadResultOperationsTableFilterComposer,
          $$UploadResultOperationsTableOrderingComposer,
          $$UploadResultOperationsTableAnnotationComposer,
          $$UploadResultOperationsTableCreateCompanionBuilder,
          $$UploadResultOperationsTableUpdateCompanionBuilder,
          (
            UploadResultOperation,
            BaseReferences<
              _$LibraryDatabase,
              $UploadResultOperationsTable,
              UploadResultOperation
            >,
          ),
          UploadResultOperation,
          PrefetchHooks Function()
        > {
  $$UploadResultOperationsTableTableManager(
    _$LibraryDatabase db,
    $UploadResultOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UploadResultOperationsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$UploadResultOperationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$UploadResultOperationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> attemptId = const Value.absent(),
                Value<String> proposalJson = const Value.absent(),
                Value<String?> secretReference = const Value.absent(),
                Value<int> createdUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UploadResultOperationsCompanion(
                id: id,
                attemptId: attemptId,
                proposalJson: proposalJson,
                secretReference: secretReference,
                createdUtc: createdUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String attemptId,
                required String proposalJson,
                Value<String?> secretReference = const Value.absent(),
                required int createdUtc,
                Value<int> rowid = const Value.absent(),
              }) => UploadResultOperationsCompanion.insert(
                id: id,
                attemptId: attemptId,
                proposalJson: proposalJson,
                secretReference: secretReference,
                createdUtc: createdUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $UploadResultOperationsTable,
                    UploadResultOperation
                  >(table),
                  BaseReferences<
                    _$LibraryDatabase,
                    $UploadResultOperationsTable,
                    UploadResultOperation
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UploadResultOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $UploadResultOperationsTable,
      UploadResultOperation,
      $$UploadResultOperationsTableFilterComposer,
      $$UploadResultOperationsTableOrderingComposer,
      $$UploadResultOperationsTableAnnotationComposer,
      $$UploadResultOperationsTableCreateCompanionBuilder,
      $$UploadResultOperationsTableUpdateCompanionBuilder,
      (
        UploadResultOperation,
        BaseReferences<
          _$LibraryDatabase,
          $UploadResultOperationsTable,
          UploadResultOperation
        >,
      ),
      UploadResultOperation,
      PrefetchHooks Function()
    >;
typedef $$UploadEventsTableCreateCompanionBuilder =
    UploadEventsCompanion Function({
      required String id,
      required String itemId,
      Value<String?> attemptId,
      required String state,
      required String reason,
      required int createdUtc,
      Value<int> rowid,
    });
typedef $$UploadEventsTableUpdateCompanionBuilder =
    UploadEventsCompanion Function({
      Value<String> id,
      Value<String> itemId,
      Value<String?> attemptId,
      Value<String> state,
      Value<String> reason,
      Value<int> createdUtc,
      Value<int> rowid,
    });

final class $$UploadEventsTableReferences
    extends BaseReferences<_$LibraryDatabase, $UploadEventsTable, UploadEvent> {
  $$UploadEventsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $UploadPublicationsTable _itemIdTable(_$LibraryDatabase db) => db
      .uploadPublications
      .createAlias('upload_events__item_id__upload_publications__id');

  $$UploadPublicationsTableProcessedTableManager get itemId {
    final $_column = $_itemColumn<String>('item_id')!;

    final manager = $$UploadPublicationsTableTableManager(
      $_db,
      $_db.uploadPublications,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_itemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$UploadEventsTableFilterComposer
    extends Composer<_$LibraryDatabase, $UploadEventsTable> {
  $$UploadEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attemptId => $composableBuilder(
    column: $table.attemptId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnFilters(column),
  );

  $$UploadPublicationsTableFilterComposer get itemId {
    final $$UploadPublicationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.uploadPublications,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UploadPublicationsTableFilterComposer(
            $db: $db,
            $table: $db.uploadPublications,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$UploadEventsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $UploadEventsTable> {
  $$UploadEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attemptId => $composableBuilder(
    column: $table.attemptId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnOrderings(column),
  );

  $$UploadPublicationsTableOrderingComposer get itemId {
    final $$UploadPublicationsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.uploadPublications,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UploadPublicationsTableOrderingComposer(
            $db: $db,
            $table: $db.uploadPublications,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$UploadEventsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $UploadEventsTable> {
  $$UploadEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get attemptId =>
      $composableBuilder(column: $table.attemptId, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => column,
  );

  $$UploadPublicationsTableAnnotationComposer get itemId {
    final $$UploadPublicationsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.itemId,
          referencedTable: $db.uploadPublications,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$UploadPublicationsTableAnnotationComposer(
                $db: $db,
                $table: $db.uploadPublications,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$UploadEventsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $UploadEventsTable,
          UploadEvent,
          $$UploadEventsTableFilterComposer,
          $$UploadEventsTableOrderingComposer,
          $$UploadEventsTableAnnotationComposer,
          $$UploadEventsTableCreateCompanionBuilder,
          $$UploadEventsTableUpdateCompanionBuilder,
          (UploadEvent, $$UploadEventsTableReferences),
          UploadEvent,
          PrefetchHooks Function({bool itemId})
        > {
  $$UploadEventsTableTableManager(
    _$LibraryDatabase db,
    $UploadEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UploadEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UploadEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UploadEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> itemId = const Value.absent(),
                Value<String?> attemptId = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String> reason = const Value.absent(),
                Value<int> createdUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UploadEventsCompanion(
                id: id,
                itemId: itemId,
                attemptId: attemptId,
                state: state,
                reason: reason,
                createdUtc: createdUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String itemId,
                Value<String?> attemptId = const Value.absent(),
                required String state,
                required String reason,
                required int createdUtc,
                Value<int> rowid = const Value.absent(),
              }) => UploadEventsCompanion.insert(
                id: id,
                itemId: itemId,
                attemptId: attemptId,
                state: state,
                reason: reason,
                createdUtc: createdUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$UploadEventsTable, UploadEvent>(table),
                  $$UploadEventsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({itemId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (itemId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.itemId,
                        referencedTable: $$UploadEventsTableReferences
                            ._itemIdTable(db),
                        referencedColumn: $$UploadEventsTableReferences
                            ._itemIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$UploadEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $UploadEventsTable,
      UploadEvent,
      $$UploadEventsTableFilterComposer,
      $$UploadEventsTableOrderingComposer,
      $$UploadEventsTableAnnotationComposer,
      $$UploadEventsTableCreateCompanionBuilder,
      $$UploadEventsTableUpdateCompanionBuilder,
      (UploadEvent, $$UploadEventsTableReferences),
      UploadEvent,
      PrefetchHooks Function({bool itemId})
    >;
typedef $$ProviderTargetsTableCreateCompanionBuilder =
    ProviderTargetsCompanion Function({
      required String id,
      required String service,
      required String alias,
      required bool enabled,
      required bool selectedByDefault,
      required bool anonymous,
      required String health,
      Value<String?> secretReference,
      Value<bool> removed,
      Value<int> generation,
      required int createdUtc,
      required int modifiedUtc,
      Value<int> rowid,
    });
typedef $$ProviderTargetsTableUpdateCompanionBuilder =
    ProviderTargetsCompanion Function({
      Value<String> id,
      Value<String> service,
      Value<String> alias,
      Value<bool> enabled,
      Value<bool> selectedByDefault,
      Value<bool> anonymous,
      Value<String> health,
      Value<String?> secretReference,
      Value<bool> removed,
      Value<int> generation,
      Value<int> createdUtc,
      Value<int> modifiedUtc,
      Value<int> rowid,
    });

final class $$ProviderTargetsTableReferences
    extends
        BaseReferences<
          _$LibraryDatabase,
          $ProviderTargetsTable,
          ProviderTargetRow
        > {
  $$ProviderTargetsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<
    $CredentialOperationsTable,
    List<CredentialOperation>
  >
  _credentialOperationsRefsTable(_$LibraryDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.credentialOperations,
        aliasName: 'provider_targets__id__credential_operations__target_id',
      );

  $$CredentialOperationsTableProcessedTableManager
  get credentialOperationsRefs {
    final manager = $$CredentialOperationsTableTableManager(
      $_db,
      $_db.credentialOperations,
    ).filter((f) => f.targetId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _credentialOperationsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ProviderTargetsTableFilterComposer
    extends Composer<_$LibraryDatabase, $ProviderTargetsTable> {
  $$ProviderTargetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get service => $composableBuilder(
    column: $table.service,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get selectedByDefault => $composableBuilder(
    column: $table.selectedByDefault,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get anonymous => $composableBuilder(
    column: $table.anonymous,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get health => $composableBuilder(
    column: $table.health,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get secretReference => $composableBuilder(
    column: $table.secretReference,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get removed => $composableBuilder(
    column: $table.removed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get modifiedUtc => $composableBuilder(
    column: $table.modifiedUtc,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> credentialOperationsRefs(
    Expression<bool> Function($$CredentialOperationsTableFilterComposer f) f,
  ) {
    final $$CredentialOperationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.credentialOperations,
      getReferencedColumn: (t) => t.targetId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CredentialOperationsTableFilterComposer(
            $db: $db,
            $table: $db.credentialOperations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProviderTargetsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $ProviderTargetsTable> {
  $$ProviderTargetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get service => $composableBuilder(
    column: $table.service,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get selectedByDefault => $composableBuilder(
    column: $table.selectedByDefault,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get anonymous => $composableBuilder(
    column: $table.anonymous,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get health => $composableBuilder(
    column: $table.health,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get secretReference => $composableBuilder(
    column: $table.secretReference,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get removed => $composableBuilder(
    column: $table.removed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get modifiedUtc => $composableBuilder(
    column: $table.modifiedUtc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProviderTargetsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $ProviderTargetsTable> {
  $$ProviderTargetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get service =>
      $composableBuilder(column: $table.service, builder: (column) => column);

  GeneratedColumn<String> get alias =>
      $composableBuilder(column: $table.alias, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<bool> get selectedByDefault => $composableBuilder(
    column: $table.selectedByDefault,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get anonymous =>
      $composableBuilder(column: $table.anonymous, builder: (column) => column);

  GeneratedColumn<String> get health =>
      $composableBuilder(column: $table.health, builder: (column) => column);

  GeneratedColumn<String> get secretReference => $composableBuilder(
    column: $table.secretReference,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get removed =>
      $composableBuilder(column: $table.removed, builder: (column) => column);

  GeneratedColumn<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get modifiedUtc => $composableBuilder(
    column: $table.modifiedUtc,
    builder: (column) => column,
  );

  Expression<T> credentialOperationsRefs<T extends Object>(
    Expression<T> Function($$CredentialOperationsTableAnnotationComposer a) f,
  ) {
    final $$CredentialOperationsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.credentialOperations,
          getReferencedColumn: (t) => t.targetId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CredentialOperationsTableAnnotationComposer(
                $db: $db,
                $table: $db.credentialOperations,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ProviderTargetsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $ProviderTargetsTable,
          ProviderTargetRow,
          $$ProviderTargetsTableFilterComposer,
          $$ProviderTargetsTableOrderingComposer,
          $$ProviderTargetsTableAnnotationComposer,
          $$ProviderTargetsTableCreateCompanionBuilder,
          $$ProviderTargetsTableUpdateCompanionBuilder,
          (ProviderTargetRow, $$ProviderTargetsTableReferences),
          ProviderTargetRow,
          PrefetchHooks Function({bool credentialOperationsRefs})
        > {
  $$ProviderTargetsTableTableManager(
    _$LibraryDatabase db,
    $ProviderTargetsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProviderTargetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProviderTargetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProviderTargetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> service = const Value.absent(),
                Value<String> alias = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<bool> selectedByDefault = const Value.absent(),
                Value<bool> anonymous = const Value.absent(),
                Value<String> health = const Value.absent(),
                Value<String?> secretReference = const Value.absent(),
                Value<bool> removed = const Value.absent(),
                Value<int> generation = const Value.absent(),
                Value<int> createdUtc = const Value.absent(),
                Value<int> modifiedUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProviderTargetsCompanion(
                id: id,
                service: service,
                alias: alias,
                enabled: enabled,
                selectedByDefault: selectedByDefault,
                anonymous: anonymous,
                health: health,
                secretReference: secretReference,
                removed: removed,
                generation: generation,
                createdUtc: createdUtc,
                modifiedUtc: modifiedUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String service,
                required String alias,
                required bool enabled,
                required bool selectedByDefault,
                required bool anonymous,
                required String health,
                Value<String?> secretReference = const Value.absent(),
                Value<bool> removed = const Value.absent(),
                Value<int> generation = const Value.absent(),
                required int createdUtc,
                required int modifiedUtc,
                Value<int> rowid = const Value.absent(),
              }) => ProviderTargetsCompanion.insert(
                id: id,
                service: service,
                alias: alias,
                enabled: enabled,
                selectedByDefault: selectedByDefault,
                anonymous: anonymous,
                health: health,
                secretReference: secretReference,
                removed: removed,
                generation: generation,
                createdUtc: createdUtc,
                modifiedUtc: modifiedUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProviderTargetsTable, ProviderTargetRow>(table),
                  $$ProviderTargetsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({credentialOperationsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (credentialOperationsRefs) db.credentialOperations,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (credentialOperationsRefs)
                    await $_getPrefetchedData<
                      ProviderTargetRow,
                      $ProviderTargetsTable,
                      CredentialOperation
                    >(
                      currentTable: table,
                      referencedTable: $$ProviderTargetsTableReferences
                          ._credentialOperationsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ProviderTargetsTableReferences(
                            db,
                            table,
                            p0,
                          ).credentialOperationsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.targetId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ProviderTargetsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $ProviderTargetsTable,
      ProviderTargetRow,
      $$ProviderTargetsTableFilterComposer,
      $$ProviderTargetsTableOrderingComposer,
      $$ProviderTargetsTableAnnotationComposer,
      $$ProviderTargetsTableCreateCompanionBuilder,
      $$ProviderTargetsTableUpdateCompanionBuilder,
      (ProviderTargetRow, $$ProviderTargetsTableReferences),
      ProviderTargetRow,
      PrefetchHooks Function({bool credentialOperationsRefs})
    >;
typedef $$CredentialOperationsTableCreateCompanionBuilder =
    CredentialOperationsCompanion Function({
      required String id,
      required String targetId,
      required String action,
      required String proposalJson,
      Value<String?> newReference,
      Value<String?> oldReference,
      required int createdUtc,
      Value<int> rowid,
    });
typedef $$CredentialOperationsTableUpdateCompanionBuilder =
    CredentialOperationsCompanion Function({
      Value<String> id,
      Value<String> targetId,
      Value<String> action,
      Value<String> proposalJson,
      Value<String?> newReference,
      Value<String?> oldReference,
      Value<int> createdUtc,
      Value<int> rowid,
    });

final class $$CredentialOperationsTableReferences
    extends
        BaseReferences<
          _$LibraryDatabase,
          $CredentialOperationsTable,
          CredentialOperation
        > {
  $$CredentialOperationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ProviderTargetsTable _targetIdTable(_$LibraryDatabase db) => db
      .providerTargets
      .createAlias('credential_operations__target_id__provider_targets__id');

  $$ProviderTargetsTableProcessedTableManager get targetId {
    final $_column = $_itemColumn<String>('target_id')!;

    final manager = $$ProviderTargetsTableTableManager(
      $_db,
      $_db.providerTargets,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_targetIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CredentialOperationsTableFilterComposer
    extends Composer<_$LibraryDatabase, $CredentialOperationsTable> {
  $$CredentialOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get proposalJson => $composableBuilder(
    column: $table.proposalJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get newReference => $composableBuilder(
    column: $table.newReference,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get oldReference => $composableBuilder(
    column: $table.oldReference,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnFilters(column),
  );

  $$ProviderTargetsTableFilterComposer get targetId {
    final $$ProviderTargetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.targetId,
      referencedTable: $db.providerTargets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProviderTargetsTableFilterComposer(
            $db: $db,
            $table: $db.providerTargets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CredentialOperationsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $CredentialOperationsTable> {
  $$CredentialOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get proposalJson => $composableBuilder(
    column: $table.proposalJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get newReference => $composableBuilder(
    column: $table.newReference,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get oldReference => $composableBuilder(
    column: $table.oldReference,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProviderTargetsTableOrderingComposer get targetId {
    final $$ProviderTargetsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.targetId,
      referencedTable: $db.providerTargets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProviderTargetsTableOrderingComposer(
            $db: $db,
            $table: $db.providerTargets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CredentialOperationsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $CredentialOperationsTable> {
  $$CredentialOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get proposalJson => $composableBuilder(
    column: $table.proposalJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get newReference => $composableBuilder(
    column: $table.newReference,
    builder: (column) => column,
  );

  GeneratedColumn<String> get oldReference => $composableBuilder(
    column: $table.oldReference,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => column,
  );

  $$ProviderTargetsTableAnnotationComposer get targetId {
    final $$ProviderTargetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.targetId,
      referencedTable: $db.providerTargets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProviderTargetsTableAnnotationComposer(
            $db: $db,
            $table: $db.providerTargets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CredentialOperationsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $CredentialOperationsTable,
          CredentialOperation,
          $$CredentialOperationsTableFilterComposer,
          $$CredentialOperationsTableOrderingComposer,
          $$CredentialOperationsTableAnnotationComposer,
          $$CredentialOperationsTableCreateCompanionBuilder,
          $$CredentialOperationsTableUpdateCompanionBuilder,
          (CredentialOperation, $$CredentialOperationsTableReferences),
          CredentialOperation,
          PrefetchHooks Function({bool targetId})
        > {
  $$CredentialOperationsTableTableManager(
    _$LibraryDatabase db,
    $CredentialOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CredentialOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CredentialOperationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CredentialOperationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> targetId = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<String> proposalJson = const Value.absent(),
                Value<String?> newReference = const Value.absent(),
                Value<String?> oldReference = const Value.absent(),
                Value<int> createdUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CredentialOperationsCompanion(
                id: id,
                targetId: targetId,
                action: action,
                proposalJson: proposalJson,
                newReference: newReference,
                oldReference: oldReference,
                createdUtc: createdUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String targetId,
                required String action,
                required String proposalJson,
                Value<String?> newReference = const Value.absent(),
                Value<String?> oldReference = const Value.absent(),
                required int createdUtc,
                Value<int> rowid = const Value.absent(),
              }) => CredentialOperationsCompanion.insert(
                id: id,
                targetId: targetId,
                action: action,
                proposalJson: proposalJson,
                newReference: newReference,
                oldReference: oldReference,
                createdUtc: createdUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CredentialOperationsTable, CredentialOperation>(
                    table,
                  ),
                  $$CredentialOperationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({targetId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (targetId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.targetId,
                        referencedTable: $$CredentialOperationsTableReferences
                            ._targetIdTable(db),
                        referencedColumn: $$CredentialOperationsTableReferences
                            ._targetIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CredentialOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $CredentialOperationsTable,
      CredentialOperation,
      $$CredentialOperationsTableFilterComposer,
      $$CredentialOperationsTableOrderingComposer,
      $$CredentialOperationsTableAnnotationComposer,
      $$CredentialOperationsTableCreateCompanionBuilder,
      $$CredentialOperationsTableUpdateCompanionBuilder,
      (CredentialOperation, $$CredentialOperationsTableReferences),
      CredentialOperation,
      PrefetchHooks Function({bool targetId})
    >;
typedef $$VersionsTableCreateCompanionBuilder = VersionsCompanion Function({
  required String id,
  required String digest,
  required int byteCount,
  required String format,
  required int width,
  required int height,
  required int frameCount,
  required int orientation,
  Value<int> rowid,
});
typedef $$VersionsTableUpdateCompanionBuilder = VersionsCompanion Function({
  Value<String> id,
  Value<String> digest,
  Value<int> byteCount,
  Value<String> format,
  Value<int> width,
  Value<int> height,
  Value<int> frameCount,
  Value<int> orientation,
  Value<int> rowid,
});

final class $$VersionsTableReferences
    extends BaseReferences<_$LibraryDatabase, $VersionsTable, VersionRow> {
  $$VersionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$AssetsTable, List<AssetRow>> _assetsRefsTable(
    _$LibraryDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.assets,
    aliasName: 'versions__id__assets__version_id',
  );

  $$AssetsTableProcessedTableManager get assetsRefs {
    final manager = $$AssetsTableTableManager(
      $_db,
      $_db.assets,
    ).filter((f) => f.versionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_assetsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$DeviceCopiesTable, List<CopyRow>>
  _deviceCopiesRefsTable(_$LibraryDatabase db) => MultiTypedResultKey.fromTable(
    db.deviceCopies,
    aliasName: 'versions__id__device_copies__version_id',
  );

  $$DeviceCopiesTableProcessedTableManager get deviceCopiesRefs {
    final manager = $$DeviceCopiesTableTableManager(
      $_db,
      $_db.deviceCopies,
    ).filter((f) => f.versionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_deviceCopiesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ProcessedOutputsTable, List<ProcessedOutputRow>>
  _processedOutputsRefsTable(_$LibraryDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.processedOutputs,
        aliasName: 'versions__id__processed_outputs__saved_version_id',
      );

  $$ProcessedOutputsTableProcessedTableManager get processedOutputsRefs {
    final manager = $$ProcessedOutputsTableTableManager(
      $_db,
      $_db.processedOutputs,
    ).filter((f) => f.savedVersionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _processedOutputsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$FileLeasesTable, List<FileLease>>
  _fileLeasesRefsTable(_$LibraryDatabase db) => MultiTypedResultKey.fromTable(
    db.fileLeases,
    aliasName: 'versions__id__file_leases__version_id',
  );

  $$FileLeasesTableProcessedTableManager get fileLeasesRefs {
    final manager = $$FileLeasesTableTableManager(
      $_db,
      $_db.fileLeases,
    ).filter((f) => f.versionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_fileLeasesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$VersionReferencesTable, List<VersionReference>>
  _versionReferencesRefsTable(_$LibraryDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.versionReferences,
        aliasName: 'versions__id__version_references__version_id',
      );

  $$VersionReferencesTableProcessedTableManager get versionReferencesRefs {
    final manager = $$VersionReferencesTableTableManager(
      $_db,
      $_db.versionReferences,
    ).filter((f) => f.versionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _versionReferencesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PurgeOperationsTable, List<PurgeOperation>>
  _purgeOperationsRefsTable(_$LibraryDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.purgeOperations,
        aliasName: 'versions__id__purge_operations__version_id',
      );

  $$PurgeOperationsTableProcessedTableManager get purgeOperationsRefs {
    final manager = $$PurgeOperationsTableTableManager(
      $_db,
      $_db.purgeOperations,
    ).filter((f) => f.versionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _purgeOperationsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SavedOutputOriginsTable, List<SavedOutputOrigin>>
  _savedOutputOriginsRefsTable(_$LibraryDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.savedOutputOrigins,
        aliasName: 'versions__id__saved_output_origins__version_id',
      );

  $$SavedOutputOriginsTableProcessedTableManager get savedOutputOriginsRefs {
    final manager = $$SavedOutputOriginsTableTableManager(
      $_db,
      $_db.savedOutputOrigins,
    ).filter((f) => f.versionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _savedOutputOriginsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $RestoredOutputOriginsTable,
    List<RestoredOutputOrigin>
  >
  _restoredOutputOriginsRefsTable(_$LibraryDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.restoredOutputOrigins,
        aliasName: 'versions__id__restored_output_origins__version_id',
      );

  $$RestoredOutputOriginsTableProcessedTableManager
  get restoredOutputOriginsRefs {
    final manager = $$RestoredOutputOriginsTableTableManager(
      $_db,
      $_db.restoredOutputOrigins,
    ).filter((f) => f.versionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _restoredOutputOriginsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$VersionsTableFilterComposer
    extends Composer<_$LibraryDatabase, $VersionsTable> {
  $$VersionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get digest => $composableBuilder(
    column: $table.digest,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteCount => $composableBuilder(
    column: $table.byteCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get frameCount => $composableBuilder(
    column: $table.frameCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orientation => $composableBuilder(
    column: $table.orientation,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> assetsRefs(
    Expression<bool> Function($$AssetsTableFilterComposer f) f,
  ) {
    final $$AssetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.versionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableFilterComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> deviceCopiesRefs(
    Expression<bool> Function($$DeviceCopiesTableFilterComposer f) f,
  ) {
    final $$DeviceCopiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.deviceCopies,
      getReferencedColumn: (t) => t.versionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DeviceCopiesTableFilterComposer(
            $db: $db,
            $table: $db.deviceCopies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> processedOutputsRefs(
    Expression<bool> Function($$ProcessedOutputsTableFilterComposer f) f,
  ) {
    final $$ProcessedOutputsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.processedOutputs,
      getReferencedColumn: (t) => t.savedVersionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProcessedOutputsTableFilterComposer(
            $db: $db,
            $table: $db.processedOutputs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> fileLeasesRefs(
    Expression<bool> Function($$FileLeasesTableFilterComposer f) f,
  ) {
    final $$FileLeasesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.fileLeases,
      getReferencedColumn: (t) => t.versionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FileLeasesTableFilterComposer(
            $db: $db,
            $table: $db.fileLeases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> versionReferencesRefs(
    Expression<bool> Function($$VersionReferencesTableFilterComposer f) f,
  ) {
    final $$VersionReferencesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.versionReferences,
      getReferencedColumn: (t) => t.versionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionReferencesTableFilterComposer(
            $db: $db,
            $table: $db.versionReferences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> purgeOperationsRefs(
    Expression<bool> Function($$PurgeOperationsTableFilterComposer f) f,
  ) {
    final $$PurgeOperationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.purgeOperations,
      getReferencedColumn: (t) => t.versionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PurgeOperationsTableFilterComposer(
            $db: $db,
            $table: $db.purgeOperations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> savedOutputOriginsRefs(
    Expression<bool> Function($$SavedOutputOriginsTableFilterComposer f) f,
  ) {
    final $$SavedOutputOriginsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.savedOutputOrigins,
      getReferencedColumn: (t) => t.versionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SavedOutputOriginsTableFilterComposer(
            $db: $db,
            $table: $db.savedOutputOrigins,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> restoredOutputOriginsRefs(
    Expression<bool> Function($$RestoredOutputOriginsTableFilterComposer f) f,
  ) {
    final $$RestoredOutputOriginsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.restoredOutputOrigins,
          getReferencedColumn: (t) => t.versionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$RestoredOutputOriginsTableFilterComposer(
                $db: $db,
                $table: $db.restoredOutputOrigins,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$VersionsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $VersionsTable> {
  $$VersionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get digest => $composableBuilder(
    column: $table.digest,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteCount => $composableBuilder(
    column: $table.byteCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get frameCount => $composableBuilder(
    column: $table.frameCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orientation => $composableBuilder(
    column: $table.orientation,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VersionsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $VersionsTable> {
  $$VersionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get digest =>
      $composableBuilder(column: $table.digest, builder: (column) => column);

  GeneratedColumn<int> get byteCount =>
      $composableBuilder(column: $table.byteCount, builder: (column) => column);

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<int> get frameCount => $composableBuilder(
    column: $table.frameCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get orientation => $composableBuilder(
    column: $table.orientation,
    builder: (column) => column,
  );

  Expression<T> assetsRefs<T extends Object>(
    Expression<T> Function($$AssetsTableAnnotationComposer a) f,
  ) {
    final $$AssetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.versionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableAnnotationComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> deviceCopiesRefs<T extends Object>(
    Expression<T> Function($$DeviceCopiesTableAnnotationComposer a) f,
  ) {
    final $$DeviceCopiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.deviceCopies,
      getReferencedColumn: (t) => t.versionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DeviceCopiesTableAnnotationComposer(
            $db: $db,
            $table: $db.deviceCopies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> processedOutputsRefs<T extends Object>(
    Expression<T> Function($$ProcessedOutputsTableAnnotationComposer a) f,
  ) {
    final $$ProcessedOutputsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.processedOutputs,
      getReferencedColumn: (t) => t.savedVersionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProcessedOutputsTableAnnotationComposer(
            $db: $db,
            $table: $db.processedOutputs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> fileLeasesRefs<T extends Object>(
    Expression<T> Function($$FileLeasesTableAnnotationComposer a) f,
  ) {
    final $$FileLeasesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.fileLeases,
      getReferencedColumn: (t) => t.versionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FileLeasesTableAnnotationComposer(
            $db: $db,
            $table: $db.fileLeases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> versionReferencesRefs<T extends Object>(
    Expression<T> Function($$VersionReferencesTableAnnotationComposer a) f,
  ) {
    final $$VersionReferencesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.versionReferences,
          getReferencedColumn: (t) => t.versionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$VersionReferencesTableAnnotationComposer(
                $db: $db,
                $table: $db.versionReferences,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> purgeOperationsRefs<T extends Object>(
    Expression<T> Function($$PurgeOperationsTableAnnotationComposer a) f,
  ) {
    final $$PurgeOperationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.purgeOperations,
      getReferencedColumn: (t) => t.versionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PurgeOperationsTableAnnotationComposer(
            $db: $db,
            $table: $db.purgeOperations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> savedOutputOriginsRefs<T extends Object>(
    Expression<T> Function($$SavedOutputOriginsTableAnnotationComposer a) f,
  ) {
    final $$SavedOutputOriginsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.savedOutputOrigins,
          getReferencedColumn: (t) => t.versionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SavedOutputOriginsTableAnnotationComposer(
                $db: $db,
                $table: $db.savedOutputOrigins,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> restoredOutputOriginsRefs<T extends Object>(
    Expression<T> Function($$RestoredOutputOriginsTableAnnotationComposer a) f,
  ) {
    final $$RestoredOutputOriginsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.restoredOutputOrigins,
          getReferencedColumn: (t) => t.versionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$RestoredOutputOriginsTableAnnotationComposer(
                $db: $db,
                $table: $db.restoredOutputOrigins,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$VersionsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $VersionsTable,
          VersionRow,
          $$VersionsTableFilterComposer,
          $$VersionsTableOrderingComposer,
          $$VersionsTableAnnotationComposer,
          $$VersionsTableCreateCompanionBuilder,
          $$VersionsTableUpdateCompanionBuilder,
          (VersionRow, $$VersionsTableReferences),
          VersionRow,
          PrefetchHooks Function({
            bool assetsRefs,
            bool deviceCopiesRefs,
            bool processedOutputsRefs,
            bool fileLeasesRefs,
            bool versionReferencesRefs,
            bool purgeOperationsRefs,
            bool savedOutputOriginsRefs,
            bool restoredOutputOriginsRefs,
          })
        > {
  $$VersionsTableTableManager(_$LibraryDatabase db, $VersionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VersionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VersionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VersionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> digest = const Value.absent(),
                Value<int> byteCount = const Value.absent(),
                Value<String> format = const Value.absent(),
                Value<int> width = const Value.absent(),
                Value<int> height = const Value.absent(),
                Value<int> frameCount = const Value.absent(),
                Value<int> orientation = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VersionsCompanion(
                id: id,
                digest: digest,
                byteCount: byteCount,
                format: format,
                width: width,
                height: height,
                frameCount: frameCount,
                orientation: orientation,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String digest,
                required int byteCount,
                required String format,
                required int width,
                required int height,
                required int frameCount,
                required int orientation,
                Value<int> rowid = const Value.absent(),
              }) => VersionsCompanion.insert(
                id: id,
                digest: digest,
                byteCount: byteCount,
                format: format,
                width: width,
                height: height,
                frameCount: frameCount,
                orientation: orientation,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$VersionsTable, VersionRow>(table),
                  $$VersionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                assetsRefs = false,
                deviceCopiesRefs = false,
                processedOutputsRefs = false,
                fileLeasesRefs = false,
                versionReferencesRefs = false,
                purgeOperationsRefs = false,
                savedOutputOriginsRefs = false,
                restoredOutputOriginsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (assetsRefs) db.assets,
                    if (deviceCopiesRefs) db.deviceCopies,
                    if (processedOutputsRefs) db.processedOutputs,
                    if (fileLeasesRefs) db.fileLeases,
                    if (versionReferencesRefs) db.versionReferences,
                    if (purgeOperationsRefs) db.purgeOperations,
                    if (savedOutputOriginsRefs) db.savedOutputOrigins,
                    if (restoredOutputOriginsRefs) db.restoredOutputOrigins,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (assetsRefs)
                        await $_getPrefetchedData<
                          VersionRow,
                          $VersionsTable,
                          AssetRow
                        >(
                          currentTable: table,
                          referencedTable: $$VersionsTableReferences
                              ._assetsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$VersionsTableReferences(
                                db,
                                table,
                                p0,
                              ).assetsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.versionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (deviceCopiesRefs)
                        await $_getPrefetchedData<
                          VersionRow,
                          $VersionsTable,
                          CopyRow
                        >(
                          currentTable: table,
                          referencedTable: $$VersionsTableReferences
                              ._deviceCopiesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$VersionsTableReferences(
                                db,
                                table,
                                p0,
                              ).deviceCopiesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.versionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (processedOutputsRefs)
                        await $_getPrefetchedData<
                          VersionRow,
                          $VersionsTable,
                          ProcessedOutputRow
                        >(
                          currentTable: table,
                          referencedTable: $$VersionsTableReferences
                              ._processedOutputsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$VersionsTableReferences(
                                db,
                                table,
                                p0,
                              ).processedOutputsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.savedVersionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (fileLeasesRefs)
                        await $_getPrefetchedData<
                          VersionRow,
                          $VersionsTable,
                          FileLease
                        >(
                          currentTable: table,
                          referencedTable: $$VersionsTableReferences
                              ._fileLeasesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$VersionsTableReferences(
                                db,
                                table,
                                p0,
                              ).fileLeasesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.versionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (versionReferencesRefs)
                        await $_getPrefetchedData<
                          VersionRow,
                          $VersionsTable,
                          VersionReference
                        >(
                          currentTable: table,
                          referencedTable: $$VersionsTableReferences
                              ._versionReferencesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$VersionsTableReferences(
                                db,
                                table,
                                p0,
                              ).versionReferencesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.versionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (purgeOperationsRefs)
                        await $_getPrefetchedData<
                          VersionRow,
                          $VersionsTable,
                          PurgeOperation
                        >(
                          currentTable: table,
                          referencedTable: $$VersionsTableReferences
                              ._purgeOperationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$VersionsTableReferences(
                                db,
                                table,
                                p0,
                              ).purgeOperationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.versionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (savedOutputOriginsRefs)
                        await $_getPrefetchedData<
                          VersionRow,
                          $VersionsTable,
                          SavedOutputOrigin
                        >(
                          currentTable: table,
                          referencedTable: $$VersionsTableReferences
                              ._savedOutputOriginsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$VersionsTableReferences(
                                db,
                                table,
                                p0,
                              ).savedOutputOriginsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.versionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (restoredOutputOriginsRefs)
                        await $_getPrefetchedData<
                          VersionRow,
                          $VersionsTable,
                          RestoredOutputOrigin
                        >(
                          currentTable: table,
                          referencedTable: $$VersionsTableReferences
                              ._restoredOutputOriginsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$VersionsTableReferences(
                                db,
                                table,
                                p0,
                              ).restoredOutputOriginsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.versionId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$VersionsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $VersionsTable,
      VersionRow,
      $$VersionsTableFilterComposer,
      $$VersionsTableOrderingComposer,
      $$VersionsTableAnnotationComposer,
      $$VersionsTableCreateCompanionBuilder,
      $$VersionsTableUpdateCompanionBuilder,
      (VersionRow, $$VersionsTableReferences),
      VersionRow,
      PrefetchHooks Function({
        bool assetsRefs,
        bool deviceCopiesRefs,
        bool processedOutputsRefs,
        bool fileLeasesRefs,
        bool versionReferencesRefs,
        bool purgeOperationsRefs,
        bool savedOutputOriginsRefs,
        bool restoredOutputOriginsRefs,
      })
    >;
typedef $$CategoriesTableCreateCompanionBuilder = CategoriesCompanion Function({
  required String id,
  required String name,
  required String nameKey,
  Value<int> rowid,
});
typedef $$CategoriesTableUpdateCompanionBuilder = CategoriesCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> nameKey,
  Value<int> rowid,
});

final class $$CategoriesTableReferences
    extends BaseReferences<_$LibraryDatabase, $CategoriesTable, CategoryRow> {
  $$CategoriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$AssetsTable, List<AssetRow>> _assetsRefsTable(
    _$LibraryDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.assets,
    aliasName: 'categories__id__assets__category',
  );

  $$AssetsTableProcessedTableManager get assetsRefs {
    final manager = $$AssetsTableTableManager(
      $_db,
      $_db.assets,
    ).filter((f) => f.category.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_assetsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CategoriesTableFilterComposer
    extends Composer<_$LibraryDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameKey => $composableBuilder(
    column: $table.nameKey,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> assetsRefs(
    Expression<bool> Function($$AssetsTableFilterComposer f) f,
  ) {
    final $$AssetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.category,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableFilterComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$LibraryDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameKey => $composableBuilder(
    column: $table.nameKey,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get nameKey =>
      $composableBuilder(column: $table.nameKey, builder: (column) => column);

  Expression<T> assetsRefs<T extends Object>(
    Expression<T> Function($$AssetsTableAnnotationComposer a) f,
  ) {
    final $$AssetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.category,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableAnnotationComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $CategoriesTable,
          CategoryRow,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (CategoryRow, $$CategoriesTableReferences),
          CategoryRow,
          PrefetchHooks Function({bool assetsRefs})
        > {
  $$CategoriesTableTableManager(_$LibraryDatabase db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> nameKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion(
                id: id,
                name: name,
                nameKey: nameKey,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String nameKey,
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion.insert(
                id: id,
                name: name,
                nameKey: nameKey,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CategoriesTable, CategoryRow>(table),
                  $$CategoriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({assetsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (assetsRefs) db.assets],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (assetsRefs)
                    await $_getPrefetchedData<
                      CategoryRow,
                      $CategoriesTable,
                      AssetRow
                    >(
                      currentTable: table,
                      referencedTable: $$CategoriesTableReferences
                          ._assetsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$CategoriesTableReferences(db, table, p0).assetsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.category == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $CategoriesTable,
      CategoryRow,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (CategoryRow, $$CategoriesTableReferences),
      CategoryRow,
      PrefetchHooks Function({bool assetsRefs})
    >;
typedef $$AssetsTableCreateCompanionBuilder = AssetsCompanion Function({
  required String id,
  required String displayName,
  required String versionId,
  required int importedUtc,
  required int updatedUtc,
  required String sourceType,
  Value<bool> favorite,
  Value<String?> category,
  Value<bool> recycled,
  Value<int?> recycledUtc,
  Value<int> rowid,
});
typedef $$AssetsTableUpdateCompanionBuilder = AssetsCompanion Function({
  Value<String> id,
  Value<String> displayName,
  Value<String> versionId,
  Value<int> importedUtc,
  Value<int> updatedUtc,
  Value<String> sourceType,
  Value<bool> favorite,
  Value<String?> category,
  Value<bool> recycled,
  Value<int?> recycledUtc,
  Value<int> rowid,
});

final class $$AssetsTableReferences
    extends BaseReferences<_$LibraryDatabase, $AssetsTable, AssetRow> {
  $$AssetsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $VersionsTable _versionIdTable(_$LibraryDatabase db) =>
      db.versions.createAlias('assets__version_id__versions__id');

  $$VersionsTableProcessedTableManager get versionId {
    final $_column = $_itemColumn<String>('version_id')!;

    final manager = $$VersionsTableTableManager(
      $_db,
      $_db.versions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_versionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $CategoriesTable _categoryTable(_$LibraryDatabase db) =>
      db.categories.createAlias('assets__category__categories__id');

  $$CategoriesTableProcessedTableManager? get category {
    final $_column = $_itemColumn<String>('category');
    if ($_column == null) return null;
    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$AssetTagsTable, List<AssetTag>>
  _assetTagsRefsTable(_$LibraryDatabase db) => MultiTypedResultKey.fromTable(
    db.assetTags,
    aliasName: 'assets__id__asset_tags__asset_id',
  );

  $$AssetTagsTableProcessedTableManager get assetTagsRefs {
    final manager = $$AssetTagsTableTableManager(
      $_db,
      $_db.assetTags,
    ).filter((f) => f.assetId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_assetTagsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$AssetsTableFilterComposer
    extends Composer<_$LibraryDatabase, $AssetsTable> {
  $$AssetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get importedUtc => $composableBuilder(
    column: $table.importedUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedUtc => $composableBuilder(
    column: $table.updatedUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get recycled => $composableBuilder(
    column: $table.recycled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recycledUtc => $composableBuilder(
    column: $table.recycledUtc,
    builder: (column) => ColumnFilters(column),
  );

  $$VersionsTableFilterComposer get versionId {
    final $$VersionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.versionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableFilterComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CategoriesTableFilterComposer get category {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.category,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> assetTagsRefs(
    Expression<bool> Function($$AssetTagsTableFilterComposer f) f,
  ) {
    final $$AssetTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assetTags,
      getReferencedColumn: (t) => t.assetId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetTagsTableFilterComposer(
            $db: $db,
            $table: $db.assetTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AssetsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $AssetsTable> {
  $$AssetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get importedUtc => $composableBuilder(
    column: $table.importedUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedUtc => $composableBuilder(
    column: $table.updatedUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get recycled => $composableBuilder(
    column: $table.recycled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recycledUtc => $composableBuilder(
    column: $table.recycledUtc,
    builder: (column) => ColumnOrderings(column),
  );

  $$VersionsTableOrderingComposer get versionId {
    final $$VersionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.versionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableOrderingComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CategoriesTableOrderingComposer get category {
    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.category,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssetsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $AssetsTable> {
  $$AssetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get importedUtc => $composableBuilder(
    column: $table.importedUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedUtc => $composableBuilder(
    column: $table.updatedUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get favorite =>
      $composableBuilder(column: $table.favorite, builder: (column) => column);

  GeneratedColumn<bool> get recycled =>
      $composableBuilder(column: $table.recycled, builder: (column) => column);

  GeneratedColumn<int> get recycledUtc => $composableBuilder(
    column: $table.recycledUtc,
    builder: (column) => column,
  );

  $$VersionsTableAnnotationComposer get versionId {
    final $$VersionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.versionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableAnnotationComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CategoriesTableAnnotationComposer get category {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.category,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> assetTagsRefs<T extends Object>(
    Expression<T> Function($$AssetTagsTableAnnotationComposer a) f,
  ) {
    final $$AssetTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assetTags,
      getReferencedColumn: (t) => t.assetId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.assetTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AssetsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $AssetsTable,
          AssetRow,
          $$AssetsTableFilterComposer,
          $$AssetsTableOrderingComposer,
          $$AssetsTableAnnotationComposer,
          $$AssetsTableCreateCompanionBuilder,
          $$AssetsTableUpdateCompanionBuilder,
          (AssetRow, $$AssetsTableReferences),
          AssetRow,
          PrefetchHooks Function({
            bool versionId,
            bool category,
            bool assetTagsRefs,
          })
        > {
  $$AssetsTableTableManager(_$LibraryDatabase db, $AssetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AssetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AssetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String> versionId = const Value.absent(),
                Value<int> importedUtc = const Value.absent(),
                Value<int> updatedUtc = const Value.absent(),
                Value<String> sourceType = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<bool> recycled = const Value.absent(),
                Value<int?> recycledUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssetsCompanion(
                id: id,
                displayName: displayName,
                versionId: versionId,
                importedUtc: importedUtc,
                updatedUtc: updatedUtc,
                sourceType: sourceType,
                favorite: favorite,
                category: category,
                recycled: recycled,
                recycledUtc: recycledUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String displayName,
                required String versionId,
                required int importedUtc,
                required int updatedUtc,
                required String sourceType,
                Value<bool> favorite = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<bool> recycled = const Value.absent(),
                Value<int?> recycledUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssetsCompanion.insert(
                id: id,
                displayName: displayName,
                versionId: versionId,
                importedUtc: importedUtc,
                updatedUtc: updatedUtc,
                sourceType: sourceType,
                favorite: favorite,
                category: category,
                recycled: recycled,
                recycledUtc: recycledUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AssetsTable, AssetRow>(table),
                  $$AssetsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({versionId = false, category = false, assetTagsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [if (assetTagsRefs) db.assetTags],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (versionId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.versionId,
                            referencedTable: $$AssetsTableReferences
                                ._versionIdTable(db),
                            referencedColumn: $$AssetsTableReferences
                                ._versionIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (category) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.category,
                            referencedTable: $$AssetsTableReferences
                                ._categoryTable(db),
                            referencedColumn: $$AssetsTableReferences
                                ._categoryTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (assetTagsRefs)
                        await $_getPrefetchedData<
                          AssetRow,
                          $AssetsTable,
                          AssetTag
                        >(
                          currentTable: table,
                          referencedTable: $$AssetsTableReferences
                              ._assetTagsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AssetsTableReferences(
                                db,
                                table,
                                p0,
                              ).assetTagsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.assetId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$AssetsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $AssetsTable,
      AssetRow,
      $$AssetsTableFilterComposer,
      $$AssetsTableOrderingComposer,
      $$AssetsTableAnnotationComposer,
      $$AssetsTableCreateCompanionBuilder,
      $$AssetsTableUpdateCompanionBuilder,
      (AssetRow, $$AssetsTableReferences),
      AssetRow,
      PrefetchHooks Function({
        bool versionId,
        bool category,
        bool assetTagsRefs,
      })
    >;
typedef $$DeviceCopiesTableCreateCompanionBuilder =
    DeviceCopiesCompanion Function({
      required String id,
      required String versionId,
      required String relativePath,
      Value<String> availability,
      Value<int?> verifiedUtc,
      Value<int> rowid,
    });
typedef $$DeviceCopiesTableUpdateCompanionBuilder =
    DeviceCopiesCompanion Function({
      Value<String> id,
      Value<String> versionId,
      Value<String> relativePath,
      Value<String> availability,
      Value<int?> verifiedUtc,
      Value<int> rowid,
    });

final class $$DeviceCopiesTableReferences
    extends BaseReferences<_$LibraryDatabase, $DeviceCopiesTable, CopyRow> {
  $$DeviceCopiesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $VersionsTable _versionIdTable(_$LibraryDatabase db) =>
      db.versions.createAlias('device_copies__version_id__versions__id');

  $$VersionsTableProcessedTableManager get versionId {
    final $_column = $_itemColumn<String>('version_id')!;

    final manager = $$VersionsTableTableManager(
      $_db,
      $_db.versions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_versionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DeviceCopiesTableFilterComposer
    extends Composer<_$LibraryDatabase, $DeviceCopiesTable> {
  $$DeviceCopiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get availability => $composableBuilder(
    column: $table.availability,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get verifiedUtc => $composableBuilder(
    column: $table.verifiedUtc,
    builder: (column) => ColumnFilters(column),
  );

  $$VersionsTableFilterComposer get versionId {
    final $$VersionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.versionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableFilterComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DeviceCopiesTableOrderingComposer
    extends Composer<_$LibraryDatabase, $DeviceCopiesTable> {
  $$DeviceCopiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get availability => $composableBuilder(
    column: $table.availability,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get verifiedUtc => $composableBuilder(
    column: $table.verifiedUtc,
    builder: (column) => ColumnOrderings(column),
  );

  $$VersionsTableOrderingComposer get versionId {
    final $$VersionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.versionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableOrderingComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DeviceCopiesTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $DeviceCopiesTable> {
  $$DeviceCopiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get availability => $composableBuilder(
    column: $table.availability,
    builder: (column) => column,
  );

  GeneratedColumn<int> get verifiedUtc => $composableBuilder(
    column: $table.verifiedUtc,
    builder: (column) => column,
  );

  $$VersionsTableAnnotationComposer get versionId {
    final $$VersionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.versionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableAnnotationComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DeviceCopiesTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $DeviceCopiesTable,
          CopyRow,
          $$DeviceCopiesTableFilterComposer,
          $$DeviceCopiesTableOrderingComposer,
          $$DeviceCopiesTableAnnotationComposer,
          $$DeviceCopiesTableCreateCompanionBuilder,
          $$DeviceCopiesTableUpdateCompanionBuilder,
          (CopyRow, $$DeviceCopiesTableReferences),
          CopyRow,
          PrefetchHooks Function({bool versionId})
        > {
  $$DeviceCopiesTableTableManager(
    _$LibraryDatabase db,
    $DeviceCopiesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DeviceCopiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DeviceCopiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DeviceCopiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> versionId = const Value.absent(),
                Value<String> relativePath = const Value.absent(),
                Value<String> availability = const Value.absent(),
                Value<int?> verifiedUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DeviceCopiesCompanion(
                id: id,
                versionId: versionId,
                relativePath: relativePath,
                availability: availability,
                verifiedUtc: verifiedUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String versionId,
                required String relativePath,
                Value<String> availability = const Value.absent(),
                Value<int?> verifiedUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DeviceCopiesCompanion.insert(
                id: id,
                versionId: versionId,
                relativePath: relativePath,
                availability: availability,
                verifiedUtc: verifiedUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DeviceCopiesTable, CopyRow>(table),
                  $$DeviceCopiesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({versionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (versionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.versionId,
                        referencedTable: $$DeviceCopiesTableReferences
                            ._versionIdTable(db),
                        referencedColumn: $$DeviceCopiesTableReferences
                            ._versionIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DeviceCopiesTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $DeviceCopiesTable,
      CopyRow,
      $$DeviceCopiesTableFilterComposer,
      $$DeviceCopiesTableOrderingComposer,
      $$DeviceCopiesTableAnnotationComposer,
      $$DeviceCopiesTableCreateCompanionBuilder,
      $$DeviceCopiesTableUpdateCompanionBuilder,
      (CopyRow, $$DeviceCopiesTableReferences),
      CopyRow,
      PrefetchHooks Function({bool versionId})
    >;
typedef $$ProcessedOutputsTableCreateCompanionBuilder =
    ProcessedOutputsCompanion Function({
      required String id,
      required String displayName,
      required String state,
      required String relativePath,
      required String requestJson,
      Value<String?> versionJson,
      Value<String> warningsJson,
      Value<bool> lossy,
      Value<bool> transparencyRemoved,
      Value<bool> animationRemoved,
      required int createdUtc,
      required int expiresUtc,
      Value<String> availability,
      Value<String?> savedVersionId,
      Value<String?> failureMessage,
      Value<int> rowid,
    });
typedef $$ProcessedOutputsTableUpdateCompanionBuilder =
    ProcessedOutputsCompanion Function({
      Value<String> id,
      Value<String> displayName,
      Value<String> state,
      Value<String> relativePath,
      Value<String> requestJson,
      Value<String?> versionJson,
      Value<String> warningsJson,
      Value<bool> lossy,
      Value<bool> transparencyRemoved,
      Value<bool> animationRemoved,
      Value<int> createdUtc,
      Value<int> expiresUtc,
      Value<String> availability,
      Value<String?> savedVersionId,
      Value<String?> failureMessage,
      Value<int> rowid,
    });

final class $$ProcessedOutputsTableReferences
    extends
        BaseReferences<
          _$LibraryDatabase,
          $ProcessedOutputsTable,
          ProcessedOutputRow
        > {
  $$ProcessedOutputsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $VersionsTable _savedVersionIdTable(_$LibraryDatabase db) => db
      .versions
      .createAlias('processed_outputs__saved_version_id__versions__id');

  $$VersionsTableProcessedTableManager? get savedVersionId {
    final $_column = $_itemColumn<String>('saved_version_id');
    if ($_column == null) return null;
    final manager = $$VersionsTableTableManager(
      $_db,
      $_db.versions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_savedVersionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ImportOperationsTable, List<OperationRow>>
  _importOperationsRefsTable(_$LibraryDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.importOperations,
        aliasName: 'processed_outputs__id__import_operations__output_id',
      );

  $$ImportOperationsTableProcessedTableManager get importOperationsRefs {
    final manager = $$ImportOperationsTableTableManager(
      $_db,
      $_db.importOperations,
    ).filter((f) => f.outputId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _importOperationsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$OutputReferencesTable, List<OutputReference>>
  _outputReferencesRefsTable(_$LibraryDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.outputReferences,
        aliasName: 'processed_outputs__id__output_references__output_id',
      );

  $$OutputReferencesTableProcessedTableManager get outputReferencesRefs {
    final manager = $$OutputReferencesTableTableManager(
      $_db,
      $_db.outputReferences,
    ).filter((f) => f.outputId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _outputReferencesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$OutputLeasesTable, List<OutputLease>>
  _outputLeasesRefsTable(_$LibraryDatabase db) => MultiTypedResultKey.fromTable(
    db.outputLeases,
    aliasName: 'processed_outputs__id__output_leases__output_id',
  );

  $$OutputLeasesTableProcessedTableManager get outputLeasesRefs {
    final manager = $$OutputLeasesTableTableManager(
      $_db,
      $_db.outputLeases,
    ).filter((f) => f.outputId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_outputLeasesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ProcessedOutputsTableFilterComposer
    extends Composer<_$LibraryDatabase, $ProcessedOutputsTable> {
  $$ProcessedOutputsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requestJson => $composableBuilder(
    column: $table.requestJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get versionJson => $composableBuilder(
    column: $table.versionJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get warningsJson => $composableBuilder(
    column: $table.warningsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get lossy => $composableBuilder(
    column: $table.lossy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get transparencyRemoved => $composableBuilder(
    column: $table.transparencyRemoved,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get animationRemoved => $composableBuilder(
    column: $table.animationRemoved,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expiresUtc => $composableBuilder(
    column: $table.expiresUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get availability => $composableBuilder(
    column: $table.availability,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureMessage => $composableBuilder(
    column: $table.failureMessage,
    builder: (column) => ColumnFilters(column),
  );

  $$VersionsTableFilterComposer get savedVersionId {
    final $$VersionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.savedVersionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableFilterComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> importOperationsRefs(
    Expression<bool> Function($$ImportOperationsTableFilterComposer f) f,
  ) {
    final $$ImportOperationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.importOperations,
      getReferencedColumn: (t) => t.outputId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ImportOperationsTableFilterComposer(
            $db: $db,
            $table: $db.importOperations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> outputReferencesRefs(
    Expression<bool> Function($$OutputReferencesTableFilterComposer f) f,
  ) {
    final $$OutputReferencesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.outputReferences,
      getReferencedColumn: (t) => t.outputId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutputReferencesTableFilterComposer(
            $db: $db,
            $table: $db.outputReferences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> outputLeasesRefs(
    Expression<bool> Function($$OutputLeasesTableFilterComposer f) f,
  ) {
    final $$OutputLeasesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.outputLeases,
      getReferencedColumn: (t) => t.outputId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutputLeasesTableFilterComposer(
            $db: $db,
            $table: $db.outputLeases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProcessedOutputsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $ProcessedOutputsTable> {
  $$ProcessedOutputsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requestJson => $composableBuilder(
    column: $table.requestJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get versionJson => $composableBuilder(
    column: $table.versionJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get warningsJson => $composableBuilder(
    column: $table.warningsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get lossy => $composableBuilder(
    column: $table.lossy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get transparencyRemoved => $composableBuilder(
    column: $table.transparencyRemoved,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get animationRemoved => $composableBuilder(
    column: $table.animationRemoved,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresUtc => $composableBuilder(
    column: $table.expiresUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get availability => $composableBuilder(
    column: $table.availability,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureMessage => $composableBuilder(
    column: $table.failureMessage,
    builder: (column) => ColumnOrderings(column),
  );

  $$VersionsTableOrderingComposer get savedVersionId {
    final $$VersionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.savedVersionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableOrderingComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProcessedOutputsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $ProcessedOutputsTable> {
  $$ProcessedOutputsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get requestJson => $composableBuilder(
    column: $table.requestJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get versionJson => $composableBuilder(
    column: $table.versionJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get warningsJson => $composableBuilder(
    column: $table.warningsJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get lossy =>
      $composableBuilder(column: $table.lossy, builder: (column) => column);

  GeneratedColumn<bool> get transparencyRemoved => $composableBuilder(
    column: $table.transparencyRemoved,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get animationRemoved => $composableBuilder(
    column: $table.animationRemoved,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get expiresUtc => $composableBuilder(
    column: $table.expiresUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get availability => $composableBuilder(
    column: $table.availability,
    builder: (column) => column,
  );

  GeneratedColumn<String> get failureMessage => $composableBuilder(
    column: $table.failureMessage,
    builder: (column) => column,
  );

  $$VersionsTableAnnotationComposer get savedVersionId {
    final $$VersionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.savedVersionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableAnnotationComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> importOperationsRefs<T extends Object>(
    Expression<T> Function($$ImportOperationsTableAnnotationComposer a) f,
  ) {
    final $$ImportOperationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.importOperations,
      getReferencedColumn: (t) => t.outputId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ImportOperationsTableAnnotationComposer(
            $db: $db,
            $table: $db.importOperations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> outputReferencesRefs<T extends Object>(
    Expression<T> Function($$OutputReferencesTableAnnotationComposer a) f,
  ) {
    final $$OutputReferencesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.outputReferences,
      getReferencedColumn: (t) => t.outputId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutputReferencesTableAnnotationComposer(
            $db: $db,
            $table: $db.outputReferences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> outputLeasesRefs<T extends Object>(
    Expression<T> Function($$OutputLeasesTableAnnotationComposer a) f,
  ) {
    final $$OutputLeasesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.outputLeases,
      getReferencedColumn: (t) => t.outputId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutputLeasesTableAnnotationComposer(
            $db: $db,
            $table: $db.outputLeases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProcessedOutputsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $ProcessedOutputsTable,
          ProcessedOutputRow,
          $$ProcessedOutputsTableFilterComposer,
          $$ProcessedOutputsTableOrderingComposer,
          $$ProcessedOutputsTableAnnotationComposer,
          $$ProcessedOutputsTableCreateCompanionBuilder,
          $$ProcessedOutputsTableUpdateCompanionBuilder,
          (ProcessedOutputRow, $$ProcessedOutputsTableReferences),
          ProcessedOutputRow,
          PrefetchHooks Function({
            bool savedVersionId,
            bool importOperationsRefs,
            bool outputReferencesRefs,
            bool outputLeasesRefs,
          })
        > {
  $$ProcessedOutputsTableTableManager(
    _$LibraryDatabase db,
    $ProcessedOutputsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProcessedOutputsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProcessedOutputsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProcessedOutputsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String> relativePath = const Value.absent(),
                Value<String> requestJson = const Value.absent(),
                Value<String?> versionJson = const Value.absent(),
                Value<String> warningsJson = const Value.absent(),
                Value<bool> lossy = const Value.absent(),
                Value<bool> transparencyRemoved = const Value.absent(),
                Value<bool> animationRemoved = const Value.absent(),
                Value<int> createdUtc = const Value.absent(),
                Value<int> expiresUtc = const Value.absent(),
                Value<String> availability = const Value.absent(),
                Value<String?> savedVersionId = const Value.absent(),
                Value<String?> failureMessage = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProcessedOutputsCompanion(
                id: id,
                displayName: displayName,
                state: state,
                relativePath: relativePath,
                requestJson: requestJson,
                versionJson: versionJson,
                warningsJson: warningsJson,
                lossy: lossy,
                transparencyRemoved: transparencyRemoved,
                animationRemoved: animationRemoved,
                createdUtc: createdUtc,
                expiresUtc: expiresUtc,
                availability: availability,
                savedVersionId: savedVersionId,
                failureMessage: failureMessage,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String displayName,
                required String state,
                required String relativePath,
                required String requestJson,
                Value<String?> versionJson = const Value.absent(),
                Value<String> warningsJson = const Value.absent(),
                Value<bool> lossy = const Value.absent(),
                Value<bool> transparencyRemoved = const Value.absent(),
                Value<bool> animationRemoved = const Value.absent(),
                required int createdUtc,
                required int expiresUtc,
                Value<String> availability = const Value.absent(),
                Value<String?> savedVersionId = const Value.absent(),
                Value<String?> failureMessage = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProcessedOutputsCompanion.insert(
                id: id,
                displayName: displayName,
                state: state,
                relativePath: relativePath,
                requestJson: requestJson,
                versionJson: versionJson,
                warningsJson: warningsJson,
                lossy: lossy,
                transparencyRemoved: transparencyRemoved,
                animationRemoved: animationRemoved,
                createdUtc: createdUtc,
                expiresUtc: expiresUtc,
                availability: availability,
                savedVersionId: savedVersionId,
                failureMessage: failureMessage,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProcessedOutputsTable, ProcessedOutputRow>(
                    table,
                  ),
                  $$ProcessedOutputsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                savedVersionId = false,
                importOperationsRefs = false,
                outputReferencesRefs = false,
                outputLeasesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (importOperationsRefs) db.importOperations,
                    if (outputReferencesRefs) db.outputReferences,
                    if (outputLeasesRefs) db.outputLeases,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (savedVersionId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.savedVersionId,
                            referencedTable: $$ProcessedOutputsTableReferences
                                ._savedVersionIdTable(db),
                            referencedColumn: $$ProcessedOutputsTableReferences
                                ._savedVersionIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (importOperationsRefs)
                        await $_getPrefetchedData<
                          ProcessedOutputRow,
                          $ProcessedOutputsTable,
                          OperationRow
                        >(
                          currentTable: table,
                          referencedTable: $$ProcessedOutputsTableReferences
                              ._importOperationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProcessedOutputsTableReferences(
                                db,
                                table,
                                p0,
                              ).importOperationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.outputId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (outputReferencesRefs)
                        await $_getPrefetchedData<
                          ProcessedOutputRow,
                          $ProcessedOutputsTable,
                          OutputReference
                        >(
                          currentTable: table,
                          referencedTable: $$ProcessedOutputsTableReferences
                              ._outputReferencesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProcessedOutputsTableReferences(
                                db,
                                table,
                                p0,
                              ).outputReferencesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.outputId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (outputLeasesRefs)
                        await $_getPrefetchedData<
                          ProcessedOutputRow,
                          $ProcessedOutputsTable,
                          OutputLease
                        >(
                          currentTable: table,
                          referencedTable: $$ProcessedOutputsTableReferences
                              ._outputLeasesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProcessedOutputsTableReferences(
                                db,
                                table,
                                p0,
                              ).outputLeasesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.outputId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ProcessedOutputsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $ProcessedOutputsTable,
      ProcessedOutputRow,
      $$ProcessedOutputsTableFilterComposer,
      $$ProcessedOutputsTableOrderingComposer,
      $$ProcessedOutputsTableAnnotationComposer,
      $$ProcessedOutputsTableCreateCompanionBuilder,
      $$ProcessedOutputsTableUpdateCompanionBuilder,
      (ProcessedOutputRow, $$ProcessedOutputsTableReferences),
      ProcessedOutputRow,
      PrefetchHooks Function({
        bool savedVersionId,
        bool importOperationsRefs,
        bool outputReferencesRefs,
        bool outputLeasesRefs,
      })
    >;
typedef $$ImportOperationsTableCreateCompanionBuilder =
    ImportOperationsCompanion Function({
      required String id,
      required String assetId,
      required String versionId,
      required String copyId,
      required String stagePath,
      required String finalPath,
      required String displayName,
      required String sourceType,
      required int createdUtc,
      required String phase,
      Value<String?> digest,
      Value<int?> byteCount,
      Value<String?> format,
      Value<int?> width,
      Value<int?> height,
      Value<int?> frameCount,
      Value<int?> orientation,
      Value<String?> outputId,
      Value<int> rowid,
    });
typedef $$ImportOperationsTableUpdateCompanionBuilder =
    ImportOperationsCompanion Function({
      Value<String> id,
      Value<String> assetId,
      Value<String> versionId,
      Value<String> copyId,
      Value<String> stagePath,
      Value<String> finalPath,
      Value<String> displayName,
      Value<String> sourceType,
      Value<int> createdUtc,
      Value<String> phase,
      Value<String?> digest,
      Value<int?> byteCount,
      Value<String?> format,
      Value<int?> width,
      Value<int?> height,
      Value<int?> frameCount,
      Value<int?> orientation,
      Value<String?> outputId,
      Value<int> rowid,
    });

final class $$ImportOperationsTableReferences
    extends
        BaseReferences<
          _$LibraryDatabase,
          $ImportOperationsTable,
          OperationRow
        > {
  $$ImportOperationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ProcessedOutputsTable _outputIdTable(_$LibraryDatabase db) => db
      .processedOutputs
      .createAlias('import_operations__output_id__processed_outputs__id');

  $$ProcessedOutputsTableProcessedTableManager? get outputId {
    final $_column = $_itemColumn<String>('output_id');
    if ($_column == null) return null;
    final manager = $$ProcessedOutputsTableTableManager(
      $_db,
      $_db.processedOutputs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_outputIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ImportOperationsTableFilterComposer
    extends Composer<_$LibraryDatabase, $ImportOperationsTable> {
  $$ImportOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get versionId => $composableBuilder(
    column: $table.versionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get copyId => $composableBuilder(
    column: $table.copyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stagePath => $composableBuilder(
    column: $table.stagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get finalPath => $composableBuilder(
    column: $table.finalPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get digest => $composableBuilder(
    column: $table.digest,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteCount => $composableBuilder(
    column: $table.byteCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get frameCount => $composableBuilder(
    column: $table.frameCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orientation => $composableBuilder(
    column: $table.orientation,
    builder: (column) => ColumnFilters(column),
  );

  $$ProcessedOutputsTableFilterComposer get outputId {
    final $$ProcessedOutputsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.outputId,
      referencedTable: $db.processedOutputs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProcessedOutputsTableFilterComposer(
            $db: $db,
            $table: $db.processedOutputs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ImportOperationsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $ImportOperationsTable> {
  $$ImportOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get versionId => $composableBuilder(
    column: $table.versionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get copyId => $composableBuilder(
    column: $table.copyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stagePath => $composableBuilder(
    column: $table.stagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get finalPath => $composableBuilder(
    column: $table.finalPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get digest => $composableBuilder(
    column: $table.digest,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteCount => $composableBuilder(
    column: $table.byteCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get frameCount => $composableBuilder(
    column: $table.frameCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orientation => $composableBuilder(
    column: $table.orientation,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProcessedOutputsTableOrderingComposer get outputId {
    final $$ProcessedOutputsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.outputId,
      referencedTable: $db.processedOutputs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProcessedOutputsTableOrderingComposer(
            $db: $db,
            $table: $db.processedOutputs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ImportOperationsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $ImportOperationsTable> {
  $$ImportOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get assetId =>
      $composableBuilder(column: $table.assetId, builder: (column) => column);

  GeneratedColumn<String> get versionId =>
      $composableBuilder(column: $table.versionId, builder: (column) => column);

  GeneratedColumn<String> get copyId =>
      $composableBuilder(column: $table.copyId, builder: (column) => column);

  GeneratedColumn<String> get stagePath =>
      $composableBuilder(column: $table.stagePath, builder: (column) => column);

  GeneratedColumn<String> get finalPath =>
      $composableBuilder(column: $table.finalPath, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get phase =>
      $composableBuilder(column: $table.phase, builder: (column) => column);

  GeneratedColumn<String> get digest =>
      $composableBuilder(column: $table.digest, builder: (column) => column);

  GeneratedColumn<int> get byteCount =>
      $composableBuilder(column: $table.byteCount, builder: (column) => column);

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<int> get frameCount => $composableBuilder(
    column: $table.frameCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get orientation => $composableBuilder(
    column: $table.orientation,
    builder: (column) => column,
  );

  $$ProcessedOutputsTableAnnotationComposer get outputId {
    final $$ProcessedOutputsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.outputId,
      referencedTable: $db.processedOutputs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProcessedOutputsTableAnnotationComposer(
            $db: $db,
            $table: $db.processedOutputs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ImportOperationsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $ImportOperationsTable,
          OperationRow,
          $$ImportOperationsTableFilterComposer,
          $$ImportOperationsTableOrderingComposer,
          $$ImportOperationsTableAnnotationComposer,
          $$ImportOperationsTableCreateCompanionBuilder,
          $$ImportOperationsTableUpdateCompanionBuilder,
          (OperationRow, $$ImportOperationsTableReferences),
          OperationRow,
          PrefetchHooks Function({bool outputId})
        > {
  $$ImportOperationsTableTableManager(
    _$LibraryDatabase db,
    $ImportOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ImportOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ImportOperationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ImportOperationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> assetId = const Value.absent(),
                Value<String> versionId = const Value.absent(),
                Value<String> copyId = const Value.absent(),
                Value<String> stagePath = const Value.absent(),
                Value<String> finalPath = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String> sourceType = const Value.absent(),
                Value<int> createdUtc = const Value.absent(),
                Value<String> phase = const Value.absent(),
                Value<String?> digest = const Value.absent(),
                Value<int?> byteCount = const Value.absent(),
                Value<String?> format = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<int?> frameCount = const Value.absent(),
                Value<int?> orientation = const Value.absent(),
                Value<String?> outputId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ImportOperationsCompanion(
                id: id,
                assetId: assetId,
                versionId: versionId,
                copyId: copyId,
                stagePath: stagePath,
                finalPath: finalPath,
                displayName: displayName,
                sourceType: sourceType,
                createdUtc: createdUtc,
                phase: phase,
                digest: digest,
                byteCount: byteCount,
                format: format,
                width: width,
                height: height,
                frameCount: frameCount,
                orientation: orientation,
                outputId: outputId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String assetId,
                required String versionId,
                required String copyId,
                required String stagePath,
                required String finalPath,
                required String displayName,
                required String sourceType,
                required int createdUtc,
                required String phase,
                Value<String?> digest = const Value.absent(),
                Value<int?> byteCount = const Value.absent(),
                Value<String?> format = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<int?> frameCount = const Value.absent(),
                Value<int?> orientation = const Value.absent(),
                Value<String?> outputId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ImportOperationsCompanion.insert(
                id: id,
                assetId: assetId,
                versionId: versionId,
                copyId: copyId,
                stagePath: stagePath,
                finalPath: finalPath,
                displayName: displayName,
                sourceType: sourceType,
                createdUtc: createdUtc,
                phase: phase,
                digest: digest,
                byteCount: byteCount,
                format: format,
                width: width,
                height: height,
                frameCount: frameCount,
                orientation: orientation,
                outputId: outputId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ImportOperationsTable, OperationRow>(table),
                  $$ImportOperationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({outputId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (outputId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.outputId,
                        referencedTable: $$ImportOperationsTableReferences
                            ._outputIdTable(db),
                        referencedColumn: $$ImportOperationsTableReferences
                            ._outputIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ImportOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $ImportOperationsTable,
      OperationRow,
      $$ImportOperationsTableFilterComposer,
      $$ImportOperationsTableOrderingComposer,
      $$ImportOperationsTableAnnotationComposer,
      $$ImportOperationsTableCreateCompanionBuilder,
      $$ImportOperationsTableUpdateCompanionBuilder,
      (OperationRow, $$ImportOperationsTableReferences),
      OperationRow,
      PrefetchHooks Function({bool outputId})
    >;
typedef $$TagsTableCreateCompanionBuilder = TagsCompanion Function({
  required String id,
  required String name,
  required String nameKey,
  Value<int> rowid,
});
typedef $$TagsTableUpdateCompanionBuilder = TagsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> nameKey,
  Value<int> rowid,
});

final class $$TagsTableReferences
    extends BaseReferences<_$LibraryDatabase, $TagsTable, TagRow> {
  $$TagsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$AssetTagsTable, List<AssetTag>>
  _assetTagsRefsTable(_$LibraryDatabase db) => MultiTypedResultKey.fromTable(
    db.assetTags,
    aliasName: 'tags__id__asset_tags__tag_id',
  );

  $$AssetTagsTableProcessedTableManager get assetTagsRefs {
    final manager = $$AssetTagsTableTableManager(
      $_db,
      $_db.assetTags,
    ).filter((f) => f.tagId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_assetTagsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TagsTableFilterComposer
    extends Composer<_$LibraryDatabase, $TagsTable> {
  $$TagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameKey => $composableBuilder(
    column: $table.nameKey,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> assetTagsRefs(
    Expression<bool> Function($$AssetTagsTableFilterComposer f) f,
  ) {
    final $$AssetTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assetTags,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetTagsTableFilterComposer(
            $db: $db,
            $table: $db.assetTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TagsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $TagsTable> {
  $$TagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameKey => $composableBuilder(
    column: $table.nameKey,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TagsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $TagsTable> {
  $$TagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get nameKey =>
      $composableBuilder(column: $table.nameKey, builder: (column) => column);

  Expression<T> assetTagsRefs<T extends Object>(
    Expression<T> Function($$AssetTagsTableAnnotationComposer a) f,
  ) {
    final $$AssetTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assetTags,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.assetTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TagsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $TagsTable,
          TagRow,
          $$TagsTableFilterComposer,
          $$TagsTableOrderingComposer,
          $$TagsTableAnnotationComposer,
          $$TagsTableCreateCompanionBuilder,
          $$TagsTableUpdateCompanionBuilder,
          (TagRow, $$TagsTableReferences),
          TagRow,
          PrefetchHooks Function({bool assetTagsRefs})
        > {
  $$TagsTableTableManager(_$LibraryDatabase db, $TagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> nameKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TagsCompanion(
                id: id,
                name: name,
                nameKey: nameKey,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String nameKey,
                Value<int> rowid = const Value.absent(),
              }) => TagsCompanion.insert(
                id: id,
                name: name,
                nameKey: nameKey,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TagsTable, TagRow>(table),
                  $$TagsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({assetTagsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (assetTagsRefs) db.assetTags],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (assetTagsRefs)
                    await $_getPrefetchedData<TagRow, $TagsTable, AssetTag>(
                      currentTable: table,
                      referencedTable: $$TagsTableReferences
                          ._assetTagsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$TagsTableReferences(db, table, p0).assetTagsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.tagId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$TagsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $TagsTable,
      TagRow,
      $$TagsTableFilterComposer,
      $$TagsTableOrderingComposer,
      $$TagsTableAnnotationComposer,
      $$TagsTableCreateCompanionBuilder,
      $$TagsTableUpdateCompanionBuilder,
      (TagRow, $$TagsTableReferences),
      TagRow,
      PrefetchHooks Function({bool assetTagsRefs})
    >;
typedef $$AssetTagsTableCreateCompanionBuilder = AssetTagsCompanion Function({
  required String assetId,
  required String tagId,
  required int position,
  Value<int> rowid,
});
typedef $$AssetTagsTableUpdateCompanionBuilder = AssetTagsCompanion Function({
  Value<String> assetId,
  Value<String> tagId,
  Value<int> position,
  Value<int> rowid,
});

final class $$AssetTagsTableReferences
    extends BaseReferences<_$LibraryDatabase, $AssetTagsTable, AssetTag> {
  $$AssetTagsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $AssetsTable _assetIdTable(_$LibraryDatabase db) =>
      db.assets.createAlias('asset_tags__asset_id__assets__id');

  $$AssetsTableProcessedTableManager get assetId {
    final $_column = $_itemColumn<String>('asset_id')!;

    final manager = $$AssetsTableTableManager(
      $_db,
      $_db.assets,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_assetIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TagsTable _tagIdTable(_$LibraryDatabase db) =>
      db.tags.createAlias('asset_tags__tag_id__tags__id');

  $$TagsTableProcessedTableManager get tagId {
    final $_column = $_itemColumn<String>('tag_id')!;

    final manager = $$TagsTableTableManager(
      $_db,
      $_db.tags,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_tagIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AssetTagsTableFilterComposer
    extends Composer<_$LibraryDatabase, $AssetTagsTable> {
  $$AssetTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  $$AssetsTableFilterComposer get assetId {
    final $$AssetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableFilterComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableFilterComposer get tagId {
    final $$TagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableFilterComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssetTagsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $AssetTagsTable> {
  $$AssetTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  $$AssetsTableOrderingComposer get assetId {
    final $$AssetsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableOrderingComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableOrderingComposer get tagId {
    final $$TagsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableOrderingComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssetTagsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $AssetTagsTable> {
  $$AssetTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  $$AssetsTableAnnotationComposer get assetId {
    final $$AssetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableAnnotationComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableAnnotationComposer get tagId {
    final $$TagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableAnnotationComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssetTagsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $AssetTagsTable,
          AssetTag,
          $$AssetTagsTableFilterComposer,
          $$AssetTagsTableOrderingComposer,
          $$AssetTagsTableAnnotationComposer,
          $$AssetTagsTableCreateCompanionBuilder,
          $$AssetTagsTableUpdateCompanionBuilder,
          (AssetTag, $$AssetTagsTableReferences),
          AssetTag,
          PrefetchHooks Function({bool assetId, bool tagId})
        > {
  $$AssetTagsTableTableManager(_$LibraryDatabase db, $AssetTagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssetTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AssetTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AssetTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> assetId = const Value.absent(),
                Value<String> tagId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssetTagsCompanion(
                assetId: assetId,
                tagId: tagId,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String assetId,
                required String tagId,
                required int position,
                Value<int> rowid = const Value.absent(),
              }) => AssetTagsCompanion.insert(
                assetId: assetId,
                tagId: tagId,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AssetTagsTable, AssetTag>(table),
                  $$AssetTagsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({assetId = false, tagId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (assetId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.assetId,
                        referencedTable: $$AssetTagsTableReferences
                            ._assetIdTable(db),
                        referencedColumn: $$AssetTagsTableReferences
                            ._assetIdTable(db)
                            .id,
                      ) as T;
                    }
                    if (tagId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.tagId,
                        referencedTable: $$AssetTagsTableReferences._tagIdTable(
                          db,
                        ),
                        referencedColumn: $$AssetTagsTableReferences
                            ._tagIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$AssetTagsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $AssetTagsTable,
      AssetTag,
      $$AssetTagsTableFilterComposer,
      $$AssetTagsTableOrderingComposer,
      $$AssetTagsTableAnnotationComposer,
      $$AssetTagsTableCreateCompanionBuilder,
      $$AssetTagsTableUpdateCompanionBuilder,
      (AssetTag, $$AssetTagsTableReferences),
      AssetTag,
      PrefetchHooks Function({bool assetId, bool tagId})
    >;
typedef $$FileLeasesTableCreateCompanionBuilder = FileLeasesCompanion Function({
  required String id,
  required String versionId,
  required String ownerId,
  required String purpose,
  required int createdUtc,
  Value<int> rowid,
});
typedef $$FileLeasesTableUpdateCompanionBuilder = FileLeasesCompanion Function({
  Value<String> id,
  Value<String> versionId,
  Value<String> ownerId,
  Value<String> purpose,
  Value<int> createdUtc,
  Value<int> rowid,
});

final class $$FileLeasesTableReferences
    extends BaseReferences<_$LibraryDatabase, $FileLeasesTable, FileLease> {
  $$FileLeasesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $VersionsTable _versionIdTable(_$LibraryDatabase db) =>
      db.versions.createAlias('file_leases__version_id__versions__id');

  $$VersionsTableProcessedTableManager get versionId {
    final $_column = $_itemColumn<String>('version_id')!;

    final manager = $$VersionsTableTableManager(
      $_db,
      $_db.versions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_versionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$FileLeasesTableFilterComposer
    extends Composer<_$LibraryDatabase, $FileLeasesTable> {
  $$FileLeasesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get purpose => $composableBuilder(
    column: $table.purpose,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnFilters(column),
  );

  $$VersionsTableFilterComposer get versionId {
    final $$VersionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.versionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableFilterComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FileLeasesTableOrderingComposer
    extends Composer<_$LibraryDatabase, $FileLeasesTable> {
  $$FileLeasesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get purpose => $composableBuilder(
    column: $table.purpose,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnOrderings(column),
  );

  $$VersionsTableOrderingComposer get versionId {
    final $$VersionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.versionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableOrderingComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FileLeasesTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $FileLeasesTable> {
  $$FileLeasesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get purpose =>
      $composableBuilder(column: $table.purpose, builder: (column) => column);

  GeneratedColumn<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => column,
  );

  $$VersionsTableAnnotationComposer get versionId {
    final $$VersionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.versionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableAnnotationComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FileLeasesTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $FileLeasesTable,
          FileLease,
          $$FileLeasesTableFilterComposer,
          $$FileLeasesTableOrderingComposer,
          $$FileLeasesTableAnnotationComposer,
          $$FileLeasesTableCreateCompanionBuilder,
          $$FileLeasesTableUpdateCompanionBuilder,
          (FileLease, $$FileLeasesTableReferences),
          FileLease,
          PrefetchHooks Function({bool versionId})
        > {
  $$FileLeasesTableTableManager(_$LibraryDatabase db, $FileLeasesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FileLeasesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FileLeasesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FileLeasesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> versionId = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> purpose = const Value.absent(),
                Value<int> createdUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FileLeasesCompanion(
                id: id,
                versionId: versionId,
                ownerId: ownerId,
                purpose: purpose,
                createdUtc: createdUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String versionId,
                required String ownerId,
                required String purpose,
                required int createdUtc,
                Value<int> rowid = const Value.absent(),
              }) => FileLeasesCompanion.insert(
                id: id,
                versionId: versionId,
                ownerId: ownerId,
                purpose: purpose,
                createdUtc: createdUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FileLeasesTable, FileLease>(table),
                  $$FileLeasesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({versionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (versionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.versionId,
                        referencedTable: $$FileLeasesTableReferences
                            ._versionIdTable(db),
                        referencedColumn: $$FileLeasesTableReferences
                            ._versionIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$FileLeasesTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $FileLeasesTable,
      FileLease,
      $$FileLeasesTableFilterComposer,
      $$FileLeasesTableOrderingComposer,
      $$FileLeasesTableAnnotationComposer,
      $$FileLeasesTableCreateCompanionBuilder,
      $$FileLeasesTableUpdateCompanionBuilder,
      (FileLease, $$FileLeasesTableReferences),
      FileLease,
      PrefetchHooks Function({bool versionId})
    >;
typedef $$VersionReferencesTableCreateCompanionBuilder =
    VersionReferencesCompanion Function({
      required String id,
      required String versionId,
      required String ownerType,
      required String ownerId,
      Value<int> rowid,
    });
typedef $$VersionReferencesTableUpdateCompanionBuilder =
    VersionReferencesCompanion Function({
      Value<String> id,
      Value<String> versionId,
      Value<String> ownerType,
      Value<String> ownerId,
      Value<int> rowid,
    });

final class $$VersionReferencesTableReferences
    extends
        BaseReferences<
          _$LibraryDatabase,
          $VersionReferencesTable,
          VersionReference
        > {
  $$VersionReferencesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $VersionsTable _versionIdTable(_$LibraryDatabase db) =>
      db.versions.createAlias('version_references__version_id__versions__id');

  $$VersionsTableProcessedTableManager get versionId {
    final $_column = $_itemColumn<String>('version_id')!;

    final manager = $$VersionsTableTableManager(
      $_db,
      $_db.versions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_versionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$VersionReferencesTableFilterComposer
    extends Composer<_$LibraryDatabase, $VersionReferencesTable> {
  $$VersionReferencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerType => $composableBuilder(
    column: $table.ownerType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  $$VersionsTableFilterComposer get versionId {
    final $$VersionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.versionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableFilterComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$VersionReferencesTableOrderingComposer
    extends Composer<_$LibraryDatabase, $VersionReferencesTable> {
  $$VersionReferencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerType => $composableBuilder(
    column: $table.ownerType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  $$VersionsTableOrderingComposer get versionId {
    final $$VersionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.versionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableOrderingComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$VersionReferencesTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $VersionReferencesTable> {
  $$VersionReferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ownerType =>
      $composableBuilder(column: $table.ownerType, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  $$VersionsTableAnnotationComposer get versionId {
    final $$VersionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.versionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableAnnotationComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$VersionReferencesTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $VersionReferencesTable,
          VersionReference,
          $$VersionReferencesTableFilterComposer,
          $$VersionReferencesTableOrderingComposer,
          $$VersionReferencesTableAnnotationComposer,
          $$VersionReferencesTableCreateCompanionBuilder,
          $$VersionReferencesTableUpdateCompanionBuilder,
          (VersionReference, $$VersionReferencesTableReferences),
          VersionReference,
          PrefetchHooks Function({bool versionId})
        > {
  $$VersionReferencesTableTableManager(
    _$LibraryDatabase db,
    $VersionReferencesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VersionReferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VersionReferencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VersionReferencesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> versionId = const Value.absent(),
                Value<String> ownerType = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VersionReferencesCompanion(
                id: id,
                versionId: versionId,
                ownerType: ownerType,
                ownerId: ownerId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String versionId,
                required String ownerType,
                required String ownerId,
                Value<int> rowid = const Value.absent(),
              }) => VersionReferencesCompanion.insert(
                id: id,
                versionId: versionId,
                ownerType: ownerType,
                ownerId: ownerId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$VersionReferencesTable, VersionReference>(table),
                  $$VersionReferencesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({versionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (versionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.versionId,
                        referencedTable: $$VersionReferencesTableReferences
                            ._versionIdTable(db),
                        referencedColumn: $$VersionReferencesTableReferences
                            ._versionIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$VersionReferencesTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $VersionReferencesTable,
      VersionReference,
      $$VersionReferencesTableFilterComposer,
      $$VersionReferencesTableOrderingComposer,
      $$VersionReferencesTableAnnotationComposer,
      $$VersionReferencesTableCreateCompanionBuilder,
      $$VersionReferencesTableUpdateCompanionBuilder,
      (VersionReference, $$VersionReferencesTableReferences),
      VersionReference,
      PrefetchHooks Function({bool versionId})
    >;
typedef $$PurgeOperationsTableCreateCompanionBuilder =
    PurgeOperationsCompanion Function({
      required String id,
      required String versionId,
      required String relativePath,
      required String assetIdsJson,
      required bool removeRecords,
      required int createdUtc,
      Value<int> rowid,
    });
typedef $$PurgeOperationsTableUpdateCompanionBuilder =
    PurgeOperationsCompanion Function({
      Value<String> id,
      Value<String> versionId,
      Value<String> relativePath,
      Value<String> assetIdsJson,
      Value<bool> removeRecords,
      Value<int> createdUtc,
      Value<int> rowid,
    });

final class $$PurgeOperationsTableReferences
    extends
        BaseReferences<
          _$LibraryDatabase,
          $PurgeOperationsTable,
          PurgeOperation
        > {
  $$PurgeOperationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $VersionsTable _versionIdTable(_$LibraryDatabase db) =>
      db.versions.createAlias('purge_operations__version_id__versions__id');

  $$VersionsTableProcessedTableManager get versionId {
    final $_column = $_itemColumn<String>('version_id')!;

    final manager = $$VersionsTableTableManager(
      $_db,
      $_db.versions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_versionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PurgeOperationsTableFilterComposer
    extends Composer<_$LibraryDatabase, $PurgeOperationsTable> {
  $$PurgeOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get assetIdsJson => $composableBuilder(
    column: $table.assetIdsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get removeRecords => $composableBuilder(
    column: $table.removeRecords,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnFilters(column),
  );

  $$VersionsTableFilterComposer get versionId {
    final $$VersionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.versionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableFilterComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PurgeOperationsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $PurgeOperationsTable> {
  $$PurgeOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assetIdsJson => $composableBuilder(
    column: $table.assetIdsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get removeRecords => $composableBuilder(
    column: $table.removeRecords,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnOrderings(column),
  );

  $$VersionsTableOrderingComposer get versionId {
    final $$VersionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.versionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableOrderingComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PurgeOperationsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $PurgeOperationsTable> {
  $$PurgeOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get assetIdsJson => $composableBuilder(
    column: $table.assetIdsJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get removeRecords => $composableBuilder(
    column: $table.removeRecords,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => column,
  );

  $$VersionsTableAnnotationComposer get versionId {
    final $$VersionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.versionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableAnnotationComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PurgeOperationsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $PurgeOperationsTable,
          PurgeOperation,
          $$PurgeOperationsTableFilterComposer,
          $$PurgeOperationsTableOrderingComposer,
          $$PurgeOperationsTableAnnotationComposer,
          $$PurgeOperationsTableCreateCompanionBuilder,
          $$PurgeOperationsTableUpdateCompanionBuilder,
          (PurgeOperation, $$PurgeOperationsTableReferences),
          PurgeOperation,
          PrefetchHooks Function({bool versionId})
        > {
  $$PurgeOperationsTableTableManager(
    _$LibraryDatabase db,
    $PurgeOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PurgeOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PurgeOperationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PurgeOperationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> versionId = const Value.absent(),
                Value<String> relativePath = const Value.absent(),
                Value<String> assetIdsJson = const Value.absent(),
                Value<bool> removeRecords = const Value.absent(),
                Value<int> createdUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PurgeOperationsCompanion(
                id: id,
                versionId: versionId,
                relativePath: relativePath,
                assetIdsJson: assetIdsJson,
                removeRecords: removeRecords,
                createdUtc: createdUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String versionId,
                required String relativePath,
                required String assetIdsJson,
                required bool removeRecords,
                required int createdUtc,
                Value<int> rowid = const Value.absent(),
              }) => PurgeOperationsCompanion.insert(
                id: id,
                versionId: versionId,
                relativePath: relativePath,
                assetIdsJson: assetIdsJson,
                removeRecords: removeRecords,
                createdUtc: createdUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PurgeOperationsTable, PurgeOperation>(table),
                  $$PurgeOperationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({versionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (versionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.versionId,
                        referencedTable: $$PurgeOperationsTableReferences
                            ._versionIdTable(db),
                        referencedColumn: $$PurgeOperationsTableReferences
                            ._versionIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PurgeOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $PurgeOperationsTable,
      PurgeOperation,
      $$PurgeOperationsTableFilterComposer,
      $$PurgeOperationsTableOrderingComposer,
      $$PurgeOperationsTableAnnotationComposer,
      $$PurgeOperationsTableCreateCompanionBuilder,
      $$PurgeOperationsTableUpdateCompanionBuilder,
      (PurgeOperation, $$PurgeOperationsTableReferences),
      PurgeOperation,
      PrefetchHooks Function({bool versionId})
    >;
typedef $$LibraryMetadataTableCreateCompanionBuilder =
    LibraryMetadataCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$LibraryMetadataTableUpdateCompanionBuilder =
    LibraryMetadataCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$LibraryMetadataTableFilterComposer
    extends Composer<_$LibraryDatabase, $LibraryMetadataTable> {
  $$LibraryMetadataTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LibraryMetadataTableOrderingComposer
    extends Composer<_$LibraryDatabase, $LibraryMetadataTable> {
  $$LibraryMetadataTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LibraryMetadataTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $LibraryMetadataTable> {
  $$LibraryMetadataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$LibraryMetadataTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $LibraryMetadataTable,
          LibraryMetadataData,
          $$LibraryMetadataTableFilterComposer,
          $$LibraryMetadataTableOrderingComposer,
          $$LibraryMetadataTableAnnotationComposer,
          $$LibraryMetadataTableCreateCompanionBuilder,
          $$LibraryMetadataTableUpdateCompanionBuilder,
          (
            LibraryMetadataData,
            BaseReferences<
              _$LibraryDatabase,
              $LibraryMetadataTable,
              LibraryMetadataData
            >,
          ),
          LibraryMetadataData,
          PrefetchHooks Function()
        > {
  $$LibraryMetadataTableTableManager(
    _$LibraryDatabase db,
    $LibraryMetadataTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LibraryMetadataTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LibraryMetadataTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LibraryMetadataTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => LibraryMetadataCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => LibraryMetadataCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LibraryMetadataTable, LibraryMetadataData>(
                    table,
                  ),
                  BaseReferences<
                    _$LibraryDatabase,
                    $LibraryMetadataTable,
                    LibraryMetadataData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LibraryMetadataTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $LibraryMetadataTable,
      LibraryMetadataData,
      $$LibraryMetadataTableFilterComposer,
      $$LibraryMetadataTableOrderingComposer,
      $$LibraryMetadataTableAnnotationComposer,
      $$LibraryMetadataTableCreateCompanionBuilder,
      $$LibraryMetadataTableUpdateCompanionBuilder,
      (
        LibraryMetadataData,
        BaseReferences<
          _$LibraryDatabase,
          $LibraryMetadataTable,
          LibraryMetadataData
        >,
      ),
      LibraryMetadataData,
      PrefetchHooks Function()
    >;
typedef $$OutputReferencesTableCreateCompanionBuilder =
    OutputReferencesCompanion Function({
      required String id,
      required String outputId,
      required String ownerType,
      required String ownerId,
      Value<int> rowid,
    });
typedef $$OutputReferencesTableUpdateCompanionBuilder =
    OutputReferencesCompanion Function({
      Value<String> id,
      Value<String> outputId,
      Value<String> ownerType,
      Value<String> ownerId,
      Value<int> rowid,
    });

final class $$OutputReferencesTableReferences
    extends
        BaseReferences<
          _$LibraryDatabase,
          $OutputReferencesTable,
          OutputReference
        > {
  $$OutputReferencesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ProcessedOutputsTable _outputIdTable(_$LibraryDatabase db) => db
      .processedOutputs
      .createAlias('output_references__output_id__processed_outputs__id');

  $$ProcessedOutputsTableProcessedTableManager get outputId {
    final $_column = $_itemColumn<String>('output_id')!;

    final manager = $$ProcessedOutputsTableTableManager(
      $_db,
      $_db.processedOutputs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_outputIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$OutputReferencesTableFilterComposer
    extends Composer<_$LibraryDatabase, $OutputReferencesTable> {
  $$OutputReferencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerType => $composableBuilder(
    column: $table.ownerType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  $$ProcessedOutputsTableFilterComposer get outputId {
    final $$ProcessedOutputsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.outputId,
      referencedTable: $db.processedOutputs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProcessedOutputsTableFilterComposer(
            $db: $db,
            $table: $db.processedOutputs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OutputReferencesTableOrderingComposer
    extends Composer<_$LibraryDatabase, $OutputReferencesTable> {
  $$OutputReferencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerType => $composableBuilder(
    column: $table.ownerType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProcessedOutputsTableOrderingComposer get outputId {
    final $$ProcessedOutputsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.outputId,
      referencedTable: $db.processedOutputs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProcessedOutputsTableOrderingComposer(
            $db: $db,
            $table: $db.processedOutputs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OutputReferencesTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $OutputReferencesTable> {
  $$OutputReferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ownerType =>
      $composableBuilder(column: $table.ownerType, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  $$ProcessedOutputsTableAnnotationComposer get outputId {
    final $$ProcessedOutputsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.outputId,
      referencedTable: $db.processedOutputs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProcessedOutputsTableAnnotationComposer(
            $db: $db,
            $table: $db.processedOutputs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OutputReferencesTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $OutputReferencesTable,
          OutputReference,
          $$OutputReferencesTableFilterComposer,
          $$OutputReferencesTableOrderingComposer,
          $$OutputReferencesTableAnnotationComposer,
          $$OutputReferencesTableCreateCompanionBuilder,
          $$OutputReferencesTableUpdateCompanionBuilder,
          (OutputReference, $$OutputReferencesTableReferences),
          OutputReference,
          PrefetchHooks Function({bool outputId})
        > {
  $$OutputReferencesTableTableManager(
    _$LibraryDatabase db,
    $OutputReferencesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutputReferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutputReferencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutputReferencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> outputId = const Value.absent(),
                Value<String> ownerType = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutputReferencesCompanion(
                id: id,
                outputId: outputId,
                ownerType: ownerType,
                ownerId: ownerId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String outputId,
                required String ownerType,
                required String ownerId,
                Value<int> rowid = const Value.absent(),
              }) => OutputReferencesCompanion.insert(
                id: id,
                outputId: outputId,
                ownerType: ownerType,
                ownerId: ownerId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OutputReferencesTable, OutputReference>(table),
                  $$OutputReferencesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({outputId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (outputId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.outputId,
                        referencedTable: $$OutputReferencesTableReferences
                            ._outputIdTable(db),
                        referencedColumn: $$OutputReferencesTableReferences
                            ._outputIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$OutputReferencesTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $OutputReferencesTable,
      OutputReference,
      $$OutputReferencesTableFilterComposer,
      $$OutputReferencesTableOrderingComposer,
      $$OutputReferencesTableAnnotationComposer,
      $$OutputReferencesTableCreateCompanionBuilder,
      $$OutputReferencesTableUpdateCompanionBuilder,
      (OutputReference, $$OutputReferencesTableReferences),
      OutputReference,
      PrefetchHooks Function({bool outputId})
    >;
typedef $$OutputLeasesTableCreateCompanionBuilder =
    OutputLeasesCompanion Function({
      required String id,
      required String outputId,
      required String ownerId,
      Value<int> rowid,
    });
typedef $$OutputLeasesTableUpdateCompanionBuilder =
    OutputLeasesCompanion Function({
      Value<String> id,
      Value<String> outputId,
      Value<String> ownerId,
      Value<int> rowid,
    });

final class $$OutputLeasesTableReferences
    extends BaseReferences<_$LibraryDatabase, $OutputLeasesTable, OutputLease> {
  $$OutputLeasesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ProcessedOutputsTable _outputIdTable(_$LibraryDatabase db) => db
      .processedOutputs
      .createAlias('output_leases__output_id__processed_outputs__id');

  $$ProcessedOutputsTableProcessedTableManager get outputId {
    final $_column = $_itemColumn<String>('output_id')!;

    final manager = $$ProcessedOutputsTableTableManager(
      $_db,
      $_db.processedOutputs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_outputIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$OutputLeasesTableFilterComposer
    extends Composer<_$LibraryDatabase, $OutputLeasesTable> {
  $$OutputLeasesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  $$ProcessedOutputsTableFilterComposer get outputId {
    final $$ProcessedOutputsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.outputId,
      referencedTable: $db.processedOutputs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProcessedOutputsTableFilterComposer(
            $db: $db,
            $table: $db.processedOutputs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OutputLeasesTableOrderingComposer
    extends Composer<_$LibraryDatabase, $OutputLeasesTable> {
  $$OutputLeasesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProcessedOutputsTableOrderingComposer get outputId {
    final $$ProcessedOutputsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.outputId,
      referencedTable: $db.processedOutputs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProcessedOutputsTableOrderingComposer(
            $db: $db,
            $table: $db.processedOutputs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OutputLeasesTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $OutputLeasesTable> {
  $$OutputLeasesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  $$ProcessedOutputsTableAnnotationComposer get outputId {
    final $$ProcessedOutputsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.outputId,
      referencedTable: $db.processedOutputs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProcessedOutputsTableAnnotationComposer(
            $db: $db,
            $table: $db.processedOutputs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OutputLeasesTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $OutputLeasesTable,
          OutputLease,
          $$OutputLeasesTableFilterComposer,
          $$OutputLeasesTableOrderingComposer,
          $$OutputLeasesTableAnnotationComposer,
          $$OutputLeasesTableCreateCompanionBuilder,
          $$OutputLeasesTableUpdateCompanionBuilder,
          (OutputLease, $$OutputLeasesTableReferences),
          OutputLease,
          PrefetchHooks Function({bool outputId})
        > {
  $$OutputLeasesTableTableManager(
    _$LibraryDatabase db,
    $OutputLeasesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutputLeasesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutputLeasesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutputLeasesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> outputId = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutputLeasesCompanion(
                id: id,
                outputId: outputId,
                ownerId: ownerId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String outputId,
                required String ownerId,
                Value<int> rowid = const Value.absent(),
              }) => OutputLeasesCompanion.insert(
                id: id,
                outputId: outputId,
                ownerId: ownerId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OutputLeasesTable, OutputLease>(table),
                  $$OutputLeasesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({outputId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (outputId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.outputId,
                        referencedTable: $$OutputLeasesTableReferences
                            ._outputIdTable(db),
                        referencedColumn: $$OutputLeasesTableReferences
                            ._outputIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$OutputLeasesTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $OutputLeasesTable,
      OutputLease,
      $$OutputLeasesTableFilterComposer,
      $$OutputLeasesTableOrderingComposer,
      $$OutputLeasesTableAnnotationComposer,
      $$OutputLeasesTableCreateCompanionBuilder,
      $$OutputLeasesTableUpdateCompanionBuilder,
      (OutputLease, $$OutputLeasesTableReferences),
      OutputLease,
      PrefetchHooks Function({bool outputId})
    >;
typedef $$SavedOutputOriginsTableCreateCompanionBuilder =
    SavedOutputOriginsCompanion Function({
      required String outputId,
      required String versionId,
      required String requestJson,
      required int createdUtc,
      Value<int> rowid,
    });
typedef $$SavedOutputOriginsTableUpdateCompanionBuilder =
    SavedOutputOriginsCompanion Function({
      Value<String> outputId,
      Value<String> versionId,
      Value<String> requestJson,
      Value<int> createdUtc,
      Value<int> rowid,
    });

final class $$SavedOutputOriginsTableReferences
    extends
        BaseReferences<
          _$LibraryDatabase,
          $SavedOutputOriginsTable,
          SavedOutputOrigin
        > {
  $$SavedOutputOriginsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $VersionsTable _versionIdTable(_$LibraryDatabase db) =>
      db.versions.createAlias('saved_output_origins__version_id__versions__id');

  $$VersionsTableProcessedTableManager get versionId {
    final $_column = $_itemColumn<String>('version_id')!;

    final manager = $$VersionsTableTableManager(
      $_db,
      $_db.versions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_versionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SavedOutputOriginsTableFilterComposer
    extends Composer<_$LibraryDatabase, $SavedOutputOriginsTable> {
  $$SavedOutputOriginsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get outputId => $composableBuilder(
    column: $table.outputId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requestJson => $composableBuilder(
    column: $table.requestJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnFilters(column),
  );

  $$VersionsTableFilterComposer get versionId {
    final $$VersionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.versionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableFilterComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SavedOutputOriginsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $SavedOutputOriginsTable> {
  $$SavedOutputOriginsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get outputId => $composableBuilder(
    column: $table.outputId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requestJson => $composableBuilder(
    column: $table.requestJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnOrderings(column),
  );

  $$VersionsTableOrderingComposer get versionId {
    final $$VersionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.versionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableOrderingComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SavedOutputOriginsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $SavedOutputOriginsTable> {
  $$SavedOutputOriginsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get outputId =>
      $composableBuilder(column: $table.outputId, builder: (column) => column);

  GeneratedColumn<String> get requestJson => $composableBuilder(
    column: $table.requestJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => column,
  );

  $$VersionsTableAnnotationComposer get versionId {
    final $$VersionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.versionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableAnnotationComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SavedOutputOriginsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $SavedOutputOriginsTable,
          SavedOutputOrigin,
          $$SavedOutputOriginsTableFilterComposer,
          $$SavedOutputOriginsTableOrderingComposer,
          $$SavedOutputOriginsTableAnnotationComposer,
          $$SavedOutputOriginsTableCreateCompanionBuilder,
          $$SavedOutputOriginsTableUpdateCompanionBuilder,
          (SavedOutputOrigin, $$SavedOutputOriginsTableReferences),
          SavedOutputOrigin,
          PrefetchHooks Function({bool versionId})
        > {
  $$SavedOutputOriginsTableTableManager(
    _$LibraryDatabase db,
    $SavedOutputOriginsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedOutputOriginsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedOutputOriginsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedOutputOriginsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> outputId = const Value.absent(),
                Value<String> versionId = const Value.absent(),
                Value<String> requestJson = const Value.absent(),
                Value<int> createdUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavedOutputOriginsCompanion(
                outputId: outputId,
                versionId: versionId,
                requestJson: requestJson,
                createdUtc: createdUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String outputId,
                required String versionId,
                required String requestJson,
                required int createdUtc,
                Value<int> rowid = const Value.absent(),
              }) => SavedOutputOriginsCompanion.insert(
                outputId: outputId,
                versionId: versionId,
                requestJson: requestJson,
                createdUtc: createdUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SavedOutputOriginsTable, SavedOutputOrigin>(
                    table,
                  ),
                  $$SavedOutputOriginsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({versionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (versionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.versionId,
                        referencedTable: $$SavedOutputOriginsTableReferences
                            ._versionIdTable(db),
                        referencedColumn: $$SavedOutputOriginsTableReferences
                            ._versionIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SavedOutputOriginsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $SavedOutputOriginsTable,
      SavedOutputOrigin,
      $$SavedOutputOriginsTableFilterComposer,
      $$SavedOutputOriginsTableOrderingComposer,
      $$SavedOutputOriginsTableAnnotationComposer,
      $$SavedOutputOriginsTableCreateCompanionBuilder,
      $$SavedOutputOriginsTableUpdateCompanionBuilder,
      (SavedOutputOrigin, $$SavedOutputOriginsTableReferences),
      SavedOutputOrigin,
      PrefetchHooks Function({bool versionId})
    >;
typedef $$RestoredOutputOriginsTableCreateCompanionBuilder =
    RestoredOutputOriginsCompanion Function({
      required String outputId,
      required String versionId,
      required String snapshotJson,
      Value<int> rowid,
    });
typedef $$RestoredOutputOriginsTableUpdateCompanionBuilder =
    RestoredOutputOriginsCompanion Function({
      Value<String> outputId,
      Value<String> versionId,
      Value<String> snapshotJson,
      Value<int> rowid,
    });

final class $$RestoredOutputOriginsTableReferences
    extends
        BaseReferences<
          _$LibraryDatabase,
          $RestoredOutputOriginsTable,
          RestoredOutputOrigin
        > {
  $$RestoredOutputOriginsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $VersionsTable _versionIdTable(_$LibraryDatabase db) => db.versions
      .createAlias('restored_output_origins__version_id__versions__id');

  $$VersionsTableProcessedTableManager get versionId {
    final $_column = $_itemColumn<String>('version_id')!;

    final manager = $$VersionsTableTableManager(
      $_db,
      $_db.versions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_versionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RestoredOutputOriginsTableFilterComposer
    extends Composer<_$LibraryDatabase, $RestoredOutputOriginsTable> {
  $$RestoredOutputOriginsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get outputId => $composableBuilder(
    column: $table.outputId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshotJson => $composableBuilder(
    column: $table.snapshotJson,
    builder: (column) => ColumnFilters(column),
  );

  $$VersionsTableFilterComposer get versionId {
    final $$VersionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.versionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableFilterComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RestoredOutputOriginsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $RestoredOutputOriginsTable> {
  $$RestoredOutputOriginsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get outputId => $composableBuilder(
    column: $table.outputId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshotJson => $composableBuilder(
    column: $table.snapshotJson,
    builder: (column) => ColumnOrderings(column),
  );

  $$VersionsTableOrderingComposer get versionId {
    final $$VersionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.versionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableOrderingComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RestoredOutputOriginsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $RestoredOutputOriginsTable> {
  $$RestoredOutputOriginsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get outputId =>
      $composableBuilder(column: $table.outputId, builder: (column) => column);

  GeneratedColumn<String> get snapshotJson => $composableBuilder(
    column: $table.snapshotJson,
    builder: (column) => column,
  );

  $$VersionsTableAnnotationComposer get versionId {
    final $$VersionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.versionId,
      referencedTable: $db.versions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VersionsTableAnnotationComposer(
            $db: $db,
            $table: $db.versions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RestoredOutputOriginsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $RestoredOutputOriginsTable,
          RestoredOutputOrigin,
          $$RestoredOutputOriginsTableFilterComposer,
          $$RestoredOutputOriginsTableOrderingComposer,
          $$RestoredOutputOriginsTableAnnotationComposer,
          $$RestoredOutputOriginsTableCreateCompanionBuilder,
          $$RestoredOutputOriginsTableUpdateCompanionBuilder,
          (RestoredOutputOrigin, $$RestoredOutputOriginsTableReferences),
          RestoredOutputOrigin,
          PrefetchHooks Function({bool versionId})
        > {
  $$RestoredOutputOriginsTableTableManager(
    _$LibraryDatabase db,
    $RestoredOutputOriginsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RestoredOutputOriginsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$RestoredOutputOriginsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$RestoredOutputOriginsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> outputId = const Value.absent(),
                Value<String> versionId = const Value.absent(),
                Value<String> snapshotJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RestoredOutputOriginsCompanion(
                outputId: outputId,
                versionId: versionId,
                snapshotJson: snapshotJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String outputId,
                required String versionId,
                required String snapshotJson,
                Value<int> rowid = const Value.absent(),
              }) => RestoredOutputOriginsCompanion.insert(
                outputId: outputId,
                versionId: versionId,
                snapshotJson: snapshotJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $RestoredOutputOriginsTable,
                    RestoredOutputOrigin
                  >(table),
                  $$RestoredOutputOriginsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({versionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (versionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.versionId,
                        referencedTable: $$RestoredOutputOriginsTableReferences
                            ._versionIdTable(db),
                        referencedColumn: $$RestoredOutputOriginsTableReferences
                            ._versionIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$RestoredOutputOriginsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $RestoredOutputOriginsTable,
      RestoredOutputOrigin,
      $$RestoredOutputOriginsTableFilterComposer,
      $$RestoredOutputOriginsTableOrderingComposer,
      $$RestoredOutputOriginsTableAnnotationComposer,
      $$RestoredOutputOriginsTableCreateCompanionBuilder,
      $$RestoredOutputOriginsTableUpdateCompanionBuilder,
      (RestoredOutputOrigin, $$RestoredOutputOriginsTableReferences),
      RestoredOutputOrigin,
      PrefetchHooks Function({bool versionId})
    >;
typedef $$ImportedUploadHistoriesTableCreateCompanionBuilder =
    ImportedUploadHistoriesCompanion Function({
      required String id,
      required String batchId,
      required int position,
      required String snapshotJson,
      Value<int> rowid,
    });
typedef $$ImportedUploadHistoriesTableUpdateCompanionBuilder =
    ImportedUploadHistoriesCompanion Function({
      Value<String> id,
      Value<String> batchId,
      Value<int> position,
      Value<String> snapshotJson,
      Value<int> rowid,
    });

class $$ImportedUploadHistoriesTableFilterComposer
    extends Composer<_$LibraryDatabase, $ImportedUploadHistoriesTable> {
  $$ImportedUploadHistoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshotJson => $composableBuilder(
    column: $table.snapshotJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ImportedUploadHistoriesTableOrderingComposer
    extends Composer<_$LibraryDatabase, $ImportedUploadHistoriesTable> {
  $$ImportedUploadHistoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshotJson => $composableBuilder(
    column: $table.snapshotJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ImportedUploadHistoriesTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $ImportedUploadHistoriesTable> {
  $$ImportedUploadHistoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get batchId =>
      $composableBuilder(column: $table.batchId, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get snapshotJson => $composableBuilder(
    column: $table.snapshotJson,
    builder: (column) => column,
  );
}

class $$ImportedUploadHistoriesTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $ImportedUploadHistoriesTable,
          ImportedUploadHistory,
          $$ImportedUploadHistoriesTableFilterComposer,
          $$ImportedUploadHistoriesTableOrderingComposer,
          $$ImportedUploadHistoriesTableAnnotationComposer,
          $$ImportedUploadHistoriesTableCreateCompanionBuilder,
          $$ImportedUploadHistoriesTableUpdateCompanionBuilder,
          (
            ImportedUploadHistory,
            BaseReferences<
              _$LibraryDatabase,
              $ImportedUploadHistoriesTable,
              ImportedUploadHistory
            >,
          ),
          ImportedUploadHistory,
          PrefetchHooks Function()
        > {
  $$ImportedUploadHistoriesTableTableManager(
    _$LibraryDatabase db,
    $ImportedUploadHistoriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ImportedUploadHistoriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ImportedUploadHistoriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ImportedUploadHistoriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> batchId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> snapshotJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ImportedUploadHistoriesCompanion(
                id: id,
                batchId: batchId,
                position: position,
                snapshotJson: snapshotJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String batchId,
                required int position,
                required String snapshotJson,
                Value<int> rowid = const Value.absent(),
              }) => ImportedUploadHistoriesCompanion.insert(
                id: id,
                batchId: batchId,
                position: position,
                snapshotJson: snapshotJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $ImportedUploadHistoriesTable,
                    ImportedUploadHistory
                  >(table),
                  BaseReferences<
                    _$LibraryDatabase,
                    $ImportedUploadHistoriesTable,
                    ImportedUploadHistory
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ImportedUploadHistoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $ImportedUploadHistoriesTable,
      ImportedUploadHistory,
      $$ImportedUploadHistoriesTableFilterComposer,
      $$ImportedUploadHistoriesTableOrderingComposer,
      $$ImportedUploadHistoriesTableAnnotationComposer,
      $$ImportedUploadHistoriesTableCreateCompanionBuilder,
      $$ImportedUploadHistoriesTableUpdateCompanionBuilder,
      (
        ImportedUploadHistory,
        BaseReferences<
          _$LibraryDatabase,
          $ImportedUploadHistoriesTable,
          ImportedUploadHistory
        >,
      ),
      ImportedUploadHistory,
      PrefetchHooks Function()
    >;
typedef $$RestoreOperationsTableCreateCompanionBuilder =
    RestoreOperationsCompanion Function({
      required String id,
      required String phase,
      required String payloadJson,
      required int createdUtc,
      Value<int> rowid,
    });
typedef $$RestoreOperationsTableUpdateCompanionBuilder =
    RestoreOperationsCompanion Function({
      Value<String> id,
      Value<String> phase,
      Value<String> payloadJson,
      Value<int> createdUtc,
      Value<int> rowid,
    });

class $$RestoreOperationsTableFilterComposer
    extends Composer<_$LibraryDatabase, $RestoreOperationsTable> {
  $$RestoreOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RestoreOperationsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $RestoreOperationsTable> {
  $$RestoreOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RestoreOperationsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $RestoreOperationsTable> {
  $$RestoreOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get phase =>
      $composableBuilder(column: $table.phase, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdUtc => $composableBuilder(
    column: $table.createdUtc,
    builder: (column) => column,
  );
}

class $$RestoreOperationsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $RestoreOperationsTable,
          RestoreOperationRow,
          $$RestoreOperationsTableFilterComposer,
          $$RestoreOperationsTableOrderingComposer,
          $$RestoreOperationsTableAnnotationComposer,
          $$RestoreOperationsTableCreateCompanionBuilder,
          $$RestoreOperationsTableUpdateCompanionBuilder,
          (
            RestoreOperationRow,
            BaseReferences<
              _$LibraryDatabase,
              $RestoreOperationsTable,
              RestoreOperationRow
            >,
          ),
          RestoreOperationRow,
          PrefetchHooks Function()
        > {
  $$RestoreOperationsTableTableManager(
    _$LibraryDatabase db,
    $RestoreOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RestoreOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RestoreOperationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RestoreOperationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> phase = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int> createdUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RestoreOperationsCompanion(
                id: id,
                phase: phase,
                payloadJson: payloadJson,
                createdUtc: createdUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String phase,
                required String payloadJson,
                required int createdUtc,
                Value<int> rowid = const Value.absent(),
              }) => RestoreOperationsCompanion.insert(
                id: id,
                phase: phase,
                payloadJson: payloadJson,
                createdUtc: createdUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RestoreOperationsTable, RestoreOperationRow>(
                    table,
                  ),
                  BaseReferences<
                    _$LibraryDatabase,
                    $RestoreOperationsTable,
                    RestoreOperationRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RestoreOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $RestoreOperationsTable,
      RestoreOperationRow,
      $$RestoreOperationsTableFilterComposer,
      $$RestoreOperationsTableOrderingComposer,
      $$RestoreOperationsTableAnnotationComposer,
      $$RestoreOperationsTableCreateCompanionBuilder,
      $$RestoreOperationsTableUpdateCompanionBuilder,
      (
        RestoreOperationRow,
        BaseReferences<
          _$LibraryDatabase,
          $RestoreOperationsTable,
          RestoreOperationRow
        >,
      ),
      RestoreOperationRow,
      PrefetchHooks Function()
    >;
typedef $$DiagnosticRecordsTableCreateCompanionBuilder =
    DiagnosticRecordsCompanion Function({
      required String id,
      required int occurredUtc,
      required String kind,
      required String level,
      required String code,
      Value<String?> entityId,
      Value<String?> batchId,
      Value<String?> attemptId,
      required String payloadJson,
      required int contentBytes,
      Value<int> rowid,
    });
typedef $$DiagnosticRecordsTableUpdateCompanionBuilder =
    DiagnosticRecordsCompanion Function({
      Value<String> id,
      Value<int> occurredUtc,
      Value<String> kind,
      Value<String> level,
      Value<String> code,
      Value<String?> entityId,
      Value<String?> batchId,
      Value<String?> attemptId,
      Value<String> payloadJson,
      Value<int> contentBytes,
      Value<int> rowid,
    });

class $$DiagnosticRecordsTableFilterComposer
    extends Composer<_$LibraryDatabase, $DiagnosticRecordsTable> {
  $$DiagnosticRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get occurredUtc => $composableBuilder(
    column: $table.occurredUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attemptId => $composableBuilder(
    column: $table.attemptId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get contentBytes => $composableBuilder(
    column: $table.contentBytes,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DiagnosticRecordsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $DiagnosticRecordsTable> {
  $$DiagnosticRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get occurredUtc => $composableBuilder(
    column: $table.occurredUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attemptId => $composableBuilder(
    column: $table.attemptId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get contentBytes => $composableBuilder(
    column: $table.contentBytes,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DiagnosticRecordsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $DiagnosticRecordsTable> {
  $$DiagnosticRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get occurredUtc => $composableBuilder(
    column: $table.occurredUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get batchId =>
      $composableBuilder(column: $table.batchId, builder: (column) => column);

  GeneratedColumn<String> get attemptId =>
      $composableBuilder(column: $table.attemptId, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get contentBytes => $composableBuilder(
    column: $table.contentBytes,
    builder: (column) => column,
  );
}

class $$DiagnosticRecordsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $DiagnosticRecordsTable,
          DiagnosticRow,
          $$DiagnosticRecordsTableFilterComposer,
          $$DiagnosticRecordsTableOrderingComposer,
          $$DiagnosticRecordsTableAnnotationComposer,
          $$DiagnosticRecordsTableCreateCompanionBuilder,
          $$DiagnosticRecordsTableUpdateCompanionBuilder,
          (
            DiagnosticRow,
            BaseReferences<
              _$LibraryDatabase,
              $DiagnosticRecordsTable,
              DiagnosticRow
            >,
          ),
          DiagnosticRow,
          PrefetchHooks Function()
        > {
  $$DiagnosticRecordsTableTableManager(
    _$LibraryDatabase db,
    $DiagnosticRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DiagnosticRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DiagnosticRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DiagnosticRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> occurredUtc = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> level = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String?> entityId = const Value.absent(),
                Value<String?> batchId = const Value.absent(),
                Value<String?> attemptId = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int> contentBytes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiagnosticRecordsCompanion(
                id: id,
                occurredUtc: occurredUtc,
                kind: kind,
                level: level,
                code: code,
                entityId: entityId,
                batchId: batchId,
                attemptId: attemptId,
                payloadJson: payloadJson,
                contentBytes: contentBytes,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int occurredUtc,
                required String kind,
                required String level,
                required String code,
                Value<String?> entityId = const Value.absent(),
                Value<String?> batchId = const Value.absent(),
                Value<String?> attemptId = const Value.absent(),
                required String payloadJson,
                required int contentBytes,
                Value<int> rowid = const Value.absent(),
              }) => DiagnosticRecordsCompanion.insert(
                id: id,
                occurredUtc: occurredUtc,
                kind: kind,
                level: level,
                code: code,
                entityId: entityId,
                batchId: batchId,
                attemptId: attemptId,
                payloadJson: payloadJson,
                contentBytes: contentBytes,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DiagnosticRecordsTable, DiagnosticRow>(table),
                  BaseReferences<
                    _$LibraryDatabase,
                    $DiagnosticRecordsTable,
                    DiagnosticRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DiagnosticRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $DiagnosticRecordsTable,
      DiagnosticRow,
      $$DiagnosticRecordsTableFilterComposer,
      $$DiagnosticRecordsTableOrderingComposer,
      $$DiagnosticRecordsTableAnnotationComposer,
      $$DiagnosticRecordsTableCreateCompanionBuilder,
      $$DiagnosticRecordsTableUpdateCompanionBuilder,
      (
        DiagnosticRow,
        BaseReferences<
          _$LibraryDatabase,
          $DiagnosticRecordsTable,
          DiagnosticRow
        >,
      ),
      DiagnosticRow,
      PrefetchHooks Function()
    >;

class $LibraryDatabaseManager {
  final _$LibraryDatabase _db;
  $LibraryDatabaseManager(this._db);
  $$UploadBatchesTableTableManager get uploadBatches =>
      $$UploadBatchesTableTableManager(_db, _db.uploadBatches);
  $$UploadProcessingJobsTableTableManager get uploadProcessingJobs =>
      $$UploadProcessingJobsTableTableManager(_db, _db.uploadProcessingJobs);
  $$UploadPublicationsTableTableManager get uploadPublications =>
      $$UploadPublicationsTableTableManager(_db, _db.uploadPublications);
  $$UploadAttemptsTableTableManager get uploadAttempts =>
      $$UploadAttemptsTableTableManager(_db, _db.uploadAttempts);
  $$RemoteUploadResultsTableTableManager get remoteUploadResults =>
      $$RemoteUploadResultsTableTableManager(_db, _db.remoteUploadResults);
  $$UploadResultOperationsTableTableManager get uploadResultOperations =>
      $$UploadResultOperationsTableTableManager(
        _db,
        _db.uploadResultOperations,
      );
  $$UploadEventsTableTableManager get uploadEvents =>
      $$UploadEventsTableTableManager(_db, _db.uploadEvents);
  $$ProviderTargetsTableTableManager get providerTargets =>
      $$ProviderTargetsTableTableManager(_db, _db.providerTargets);
  $$CredentialOperationsTableTableManager get credentialOperations =>
      $$CredentialOperationsTableTableManager(_db, _db.credentialOperations);
  $$VersionsTableTableManager get versions =>
      $$VersionsTableTableManager(_db, _db.versions);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$AssetsTableTableManager get assets =>
      $$AssetsTableTableManager(_db, _db.assets);
  $$DeviceCopiesTableTableManager get deviceCopies =>
      $$DeviceCopiesTableTableManager(_db, _db.deviceCopies);
  $$ProcessedOutputsTableTableManager get processedOutputs =>
      $$ProcessedOutputsTableTableManager(_db, _db.processedOutputs);
  $$ImportOperationsTableTableManager get importOperations =>
      $$ImportOperationsTableTableManager(_db, _db.importOperations);
  $$TagsTableTableManager get tags => $$TagsTableTableManager(_db, _db.tags);
  $$AssetTagsTableTableManager get assetTags =>
      $$AssetTagsTableTableManager(_db, _db.assetTags);
  $$FileLeasesTableTableManager get fileLeases =>
      $$FileLeasesTableTableManager(_db, _db.fileLeases);
  $$VersionReferencesTableTableManager get versionReferences =>
      $$VersionReferencesTableTableManager(_db, _db.versionReferences);
  $$PurgeOperationsTableTableManager get purgeOperations =>
      $$PurgeOperationsTableTableManager(_db, _db.purgeOperations);
  $$LibraryMetadataTableTableManager get libraryMetadata =>
      $$LibraryMetadataTableTableManager(_db, _db.libraryMetadata);
  $$OutputReferencesTableTableManager get outputReferences =>
      $$OutputReferencesTableTableManager(_db, _db.outputReferences);
  $$OutputLeasesTableTableManager get outputLeases =>
      $$OutputLeasesTableTableManager(_db, _db.outputLeases);
  $$SavedOutputOriginsTableTableManager get savedOutputOrigins =>
      $$SavedOutputOriginsTableTableManager(_db, _db.savedOutputOrigins);
  $$RestoredOutputOriginsTableTableManager get restoredOutputOrigins =>
      $$RestoredOutputOriginsTableTableManager(_db, _db.restoredOutputOrigins);
  $$ImportedUploadHistoriesTableTableManager get importedUploadHistories =>
      $$ImportedUploadHistoriesTableTableManager(
        _db,
        _db.importedUploadHistories,
      );
  $$RestoreOperationsTableTableManager get restoreOperations =>
      $$RestoreOperationsTableTableManager(_db, _db.restoreOperations);
  $$DiagnosticRecordsTableTableManager get diagnosticRecords =>
      $$DiagnosticRecordsTableTableManager(_db, _db.diagnosticRecords);
}
