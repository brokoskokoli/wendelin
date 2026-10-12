// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class MemoryFts extends Table
    with TableInfo<MemoryFts, MemoryFt>, VirtualTableInfo<MemoryFts, MemoryFt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  MemoryFts(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  late final GeneratedColumn<String> entryId = GeneratedColumn<String>(
    'entry_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [entryId, body];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'memory_fts';
  @override
  VerificationContext validateIntegrity(
    Insertable<MemoryFt> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entryIdMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  MemoryFt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MemoryFt(
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_id'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
    );
  }

  @override
  MemoryFts createAlias(String alias) {
    return MemoryFts(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
  @override
  String get moduleAndArgs =>
      'fts5(entry_id UNINDEXED, body, tokenize = \'unicode61 remove_diacritics 2\')';
}

class MemoryFt extends DataClass implements Insertable<MemoryFt> {
  final String entryId;
  final String body;
  const MemoryFt({required this.entryId, required this.body});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entry_id'] = Variable<String>(entryId);
    map['body'] = Variable<String>(body);
    return map;
  }

  MemoryFtsCompanion toCompanion(bool nullToAbsent) {
    return MemoryFtsCompanion(entryId: Value(entryId), body: Value(body));
  }

  factory MemoryFt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MemoryFt(
      entryId: serializer.fromJson<String>(json['entry_id']),
      body: serializer.fromJson<String>(json['body']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entry_id': serializer.toJson<String>(entryId),
      'body': serializer.toJson<String>(body),
    };
  }

  MemoryFt copyWith({String? entryId, String? body}) =>
      MemoryFt(entryId: entryId ?? this.entryId, body: body ?? this.body);
  MemoryFt copyWithCompanion(MemoryFtsCompanion data) {
    return MemoryFt(
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      body: data.body.present ? data.body.value : this.body,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MemoryFt(')
          ..write('entryId: $entryId, ')
          ..write('body: $body')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(entryId, body);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MemoryFt &&
          other.entryId == this.entryId &&
          other.body == this.body);
}

class MemoryFtsCompanion extends UpdateCompanion<MemoryFt> {
  final Value<String> entryId;
  final Value<String> body;
  final Value<int> rowid;
  const MemoryFtsCompanion({
    this.entryId = const Value.absent(),
    this.body = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MemoryFtsCompanion.insert({
    required String entryId,
    required String body,
    this.rowid = const Value.absent(),
  }) : entryId = Value(entryId),
       body = Value(body);
  static Insertable<MemoryFt> custom({
    Expression<String>? entryId,
    Expression<String>? body,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entryId != null) 'entry_id': entryId,
      if (body != null) 'body': body,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MemoryFtsCompanion copyWith({
    Value<String>? entryId,
    Value<String>? body,
    Value<int>? rowid,
  }) {
    return MemoryFtsCompanion(
      entryId: entryId ?? this.entryId,
      body: body ?? this.body,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entryId.present) {
      map['entry_id'] = Variable<String>(entryId.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MemoryFtsCompanion(')
          ..write('entryId: $entryId, ')
          ..write('body: $body, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MemoryEntriesTable extends MemoryEntries
    with TableInfo<$MemoryEntriesTable, MemoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MemoryEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<MemoryCategory, String> category =
      GeneratedColumn<String>(
        'category',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<MemoryCategory>($MemoryEntriesTable.$convertercategory);
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> createdAt =
      GeneratedColumn<int>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($MemoryEntriesTable.$convertercreatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> lastUsedAt =
      GeneratedColumn<int>(
        'last_used_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($MemoryEntriesTable.$converterlastUsedAt);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    body,
    category,
    source,
    createdAt,
    lastUsedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'memory_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<MemoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MemoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MemoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      category: $MemoryEntriesTable.$convertercategory.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}category'],
        )!,
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      createdAt: $MemoryEntriesTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      lastUsedAt: $MemoryEntriesTable.$converterlastUsedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}last_used_at'],
        )!,
      ),
    );
  }

  @override
  $MemoryEntriesTable createAlias(String alias) {
    return $MemoryEntriesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<MemoryCategory, String, String> $convertercategory =
      const EnumNameConverter<MemoryCategory>(MemoryCategory.values);
  static TypeConverter<DateTime, int> $convertercreatedAt = epochMicros;
  static TypeConverter<DateTime, int> $converterlastUsedAt = epochMicros;
}

class MemoryRow extends DataClass implements Insertable<MemoryRow> {
  final String id;

  /// The remembered text. Named `body` (not `text`) because drift's
  /// schema-dump code generator cannot name a column getter `text`.
  final String body;
  final MemoryCategory category;
  final String source;
  final DateTime createdAt;
  final DateTime lastUsedAt;
  const MemoryRow({
    required this.id,
    required this.body,
    required this.category,
    required this.source,
    required this.createdAt,
    required this.lastUsedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['body'] = Variable<String>(body);
    {
      map['category'] = Variable<String>(
        $MemoryEntriesTable.$convertercategory.toSql(category),
      );
    }
    map['source'] = Variable<String>(source);
    {
      map['created_at'] = Variable<int>(
        $MemoryEntriesTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    {
      map['last_used_at'] = Variable<int>(
        $MemoryEntriesTable.$converterlastUsedAt.toSql(lastUsedAt),
      );
    }
    return map;
  }

  MemoryEntriesCompanion toCompanion(bool nullToAbsent) {
    return MemoryEntriesCompanion(
      id: Value(id),
      body: Value(body),
      category: Value(category),
      source: Value(source),
      createdAt: Value(createdAt),
      lastUsedAt: Value(lastUsedAt),
    );
  }

  factory MemoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MemoryRow(
      id: serializer.fromJson<String>(json['id']),
      body: serializer.fromJson<String>(json['body']),
      category: $MemoryEntriesTable.$convertercategory.fromJson(
        serializer.fromJson<String>(json['category']),
      ),
      source: serializer.fromJson<String>(json['source']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastUsedAt: serializer.fromJson<DateTime>(json['lastUsedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'body': serializer.toJson<String>(body),
      'category': serializer.toJson<String>(
        $MemoryEntriesTable.$convertercategory.toJson(category),
      ),
      'source': serializer.toJson<String>(source),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastUsedAt': serializer.toJson<DateTime>(lastUsedAt),
    };
  }

  MemoryRow copyWith({
    String? id,
    String? body,
    MemoryCategory? category,
    String? source,
    DateTime? createdAt,
    DateTime? lastUsedAt,
  }) => MemoryRow(
    id: id ?? this.id,
    body: body ?? this.body,
    category: category ?? this.category,
    source: source ?? this.source,
    createdAt: createdAt ?? this.createdAt,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
  );
  MemoryRow copyWithCompanion(MemoryEntriesCompanion data) {
    return MemoryRow(
      id: data.id.present ? data.id.value : this.id,
      body: data.body.present ? data.body.value : this.body,
      category: data.category.present ? data.category.value : this.category,
      source: data.source.present ? data.source.value : this.source,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastUsedAt: data.lastUsedAt.present
          ? data.lastUsedAt.value
          : this.lastUsedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MemoryRow(')
          ..write('id: $id, ')
          ..write('body: $body, ')
          ..write('category: $category, ')
          ..write('source: $source, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastUsedAt: $lastUsedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, body, category, source, createdAt, lastUsedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MemoryRow &&
          other.id == this.id &&
          other.body == this.body &&
          other.category == this.category &&
          other.source == this.source &&
          other.createdAt == this.createdAt &&
          other.lastUsedAt == this.lastUsedAt);
}

class MemoryEntriesCompanion extends UpdateCompanion<MemoryRow> {
  final Value<String> id;
  final Value<String> body;
  final Value<MemoryCategory> category;
  final Value<String> source;
  final Value<DateTime> createdAt;
  final Value<DateTime> lastUsedAt;
  final Value<int> rowid;
  const MemoryEntriesCompanion({
    this.id = const Value.absent(),
    this.body = const Value.absent(),
    this.category = const Value.absent(),
    this.source = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MemoryEntriesCompanion.insert({
    required String id,
    required String body,
    required MemoryCategory category,
    required String source,
    required DateTime createdAt,
    required DateTime lastUsedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       body = Value(body),
       category = Value(category),
       source = Value(source),
       createdAt = Value(createdAt),
       lastUsedAt = Value(lastUsedAt);
  static Insertable<MemoryRow> custom({
    Expression<String>? id,
    Expression<String>? body,
    Expression<String>? category,
    Expression<String>? source,
    Expression<int>? createdAt,
    Expression<int>? lastUsedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (body != null) 'body': body,
      if (category != null) 'category': category,
      if (source != null) 'source': source,
      if (createdAt != null) 'created_at': createdAt,
      if (lastUsedAt != null) 'last_used_at': lastUsedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MemoryEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? body,
    Value<MemoryCategory>? category,
    Value<String>? source,
    Value<DateTime>? createdAt,
    Value<DateTime>? lastUsedAt,
    Value<int>? rowid,
  }) {
    return MemoryEntriesCompanion(
      id: id ?? this.id,
      body: body ?? this.body,
      category: category ?? this.category,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(
        $MemoryEntriesTable.$convertercategory.toSql(category.value),
      );
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(
        $MemoryEntriesTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (lastUsedAt.present) {
      map['last_used_at'] = Variable<int>(
        $MemoryEntriesTable.$converterlastUsedAt.toSql(lastUsedAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MemoryEntriesCompanion(')
          ..write('id: $id, ')
          ..write('body: $body, ')
          ..write('category: $category, ')
          ..write('source: $source, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionsTable extends Sessions
    with TableInfo<$SessionsTable, SessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> startedAt =
      GeneratedColumn<int>(
        'started_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($SessionsTable.$converterstartedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> lastActivityAt =
      GeneratedColumn<int>(
        'last_activity_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($SessionsTable.$converterlastActivityAt);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, startedAt, lastActivityAt, title];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      startedAt: $SessionsTable.$converterstartedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}started_at'],
        )!,
      ),
      lastActivityAt: $SessionsTable.$converterlastActivityAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}last_activity_at'],
        )!,
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
    );
  }

  @override
  $SessionsTable createAlias(String alias) {
    return $SessionsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterstartedAt = epochMicros;
  static TypeConverter<DateTime, int> $converterlastActivityAt = epochMicros;
}

class SessionRow extends DataClass implements Insertable<SessionRow> {
  final String id;
  final DateTime startedAt;
  final DateTime lastActivityAt;
  final String? title;
  const SessionRow({
    required this.id,
    required this.startedAt,
    required this.lastActivityAt,
    this.title,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    {
      map['started_at'] = Variable<int>(
        $SessionsTable.$converterstartedAt.toSql(startedAt),
      );
    }
    {
      map['last_activity_at'] = Variable<int>(
        $SessionsTable.$converterlastActivityAt.toSql(lastActivityAt),
      );
    }
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    return map;
  }

  SessionsCompanion toCompanion(bool nullToAbsent) {
    return SessionsCompanion(
      id: Value(id),
      startedAt: Value(startedAt),
      lastActivityAt: Value(lastActivityAt),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
    );
  }

  factory SessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionRow(
      id: serializer.fromJson<String>(json['id']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      lastActivityAt: serializer.fromJson<DateTime>(json['lastActivityAt']),
      title: serializer.fromJson<String?>(json['title']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'lastActivityAt': serializer.toJson<DateTime>(lastActivityAt),
      'title': serializer.toJson<String?>(title),
    };
  }

  SessionRow copyWith({
    String? id,
    DateTime? startedAt,
    DateTime? lastActivityAt,
    Value<String?> title = const Value.absent(),
  }) => SessionRow(
    id: id ?? this.id,
    startedAt: startedAt ?? this.startedAt,
    lastActivityAt: lastActivityAt ?? this.lastActivityAt,
    title: title.present ? title.value : this.title,
  );
  SessionRow copyWithCompanion(SessionsCompanion data) {
    return SessionRow(
      id: data.id.present ? data.id.value : this.id,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      lastActivityAt: data.lastActivityAt.present
          ? data.lastActivityAt.value
          : this.lastActivityAt,
      title: data.title.present ? data.title.value : this.title,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionRow(')
          ..write('id: $id, ')
          ..write('startedAt: $startedAt, ')
          ..write('lastActivityAt: $lastActivityAt, ')
          ..write('title: $title')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, startedAt, lastActivityAt, title);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionRow &&
          other.id == this.id &&
          other.startedAt == this.startedAt &&
          other.lastActivityAt == this.lastActivityAt &&
          other.title == this.title);
}

class SessionsCompanion extends UpdateCompanion<SessionRow> {
  final Value<String> id;
  final Value<DateTime> startedAt;
  final Value<DateTime> lastActivityAt;
  final Value<String?> title;
  final Value<int> rowid;
  const SessionsCompanion({
    this.id = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.lastActivityAt = const Value.absent(),
    this.title = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionsCompanion.insert({
    required String id,
    required DateTime startedAt,
    required DateTime lastActivityAt,
    this.title = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       startedAt = Value(startedAt),
       lastActivityAt = Value(lastActivityAt);
  static Insertable<SessionRow> custom({
    Expression<String>? id,
    Expression<int>? startedAt,
    Expression<int>? lastActivityAt,
    Expression<String>? title,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (startedAt != null) 'started_at': startedAt,
      if (lastActivityAt != null) 'last_activity_at': lastActivityAt,
      if (title != null) 'title': title,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionsCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? startedAt,
    Value<DateTime>? lastActivityAt,
    Value<String?>? title,
    Value<int>? rowid,
  }) {
    return SessionsCompanion(
      id: id ?? this.id,
      startedAt: startedAt ?? this.startedAt,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      title: title ?? this.title,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<int>(
        $SessionsTable.$converterstartedAt.toSql(startedAt.value),
      );
    }
    if (lastActivityAt.present) {
      map['last_activity_at'] = Variable<int>(
        $SessionsTable.$converterlastActivityAt.toSql(lastActivityAt.value),
      );
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionsCompanion(')
          ..write('id: $id, ')
          ..write('startedAt: $startedAt, ')
          ..write('lastActivityAt: $lastActivityAt, ')
          ..write('title: $title, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages
    with TableInfo<$MessagesTable, MessageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentJsonMeta = const VerificationMeta(
    'contentJson',
  );
  @override
  late final GeneratedColumn<String> contentJson = GeneratedColumn<String>(
    'content_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> createdAt =
      GeneratedColumn<int>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($MessagesTable.$convertercreatedAt);
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelIdMeta = const VerificationMeta(
    'modelId',
  );
  @override
  late final GeneratedColumn<String> modelId = GeneratedColumn<String>(
    'model_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    seq,
    role,
    contentJson,
    createdAt,
    profileId,
    modelId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    } else if (isInserting) {
      context.missing(_seqMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('content_json')) {
      context.handle(
        _contentJsonMeta,
        contentJson.isAcceptableOrUnknown(
          data['content_json']!,
          _contentJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentJsonMeta);
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    }
    if (data.containsKey('model_id')) {
      context.handle(
        _modelIdMeta,
        modelId.isAcceptableOrUnknown(data['model_id']!, _modelIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MessageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      contentJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_json'],
      )!,
      createdAt: $MessagesTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      ),
      modelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_id'],
      ),
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $convertercreatedAt = epochMicros;
}

class MessageRow extends DataClass implements Insertable<MessageRow> {
  final String id;
  final String sessionId;
  final int seq;
  final String role;

  /// `Message.toJson()['content']`, JSON-encoded.
  final String contentJson;
  final DateTime createdAt;
  final String? profileId;
  final String? modelId;
  const MessageRow({
    required this.id,
    required this.sessionId,
    required this.seq,
    required this.role,
    required this.contentJson,
    required this.createdAt,
    this.profileId,
    this.modelId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['seq'] = Variable<int>(seq);
    map['role'] = Variable<String>(role);
    map['content_json'] = Variable<String>(contentJson);
    {
      map['created_at'] = Variable<int>(
        $MessagesTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    if (!nullToAbsent || profileId != null) {
      map['profile_id'] = Variable<String>(profileId);
    }
    if (!nullToAbsent || modelId != null) {
      map['model_id'] = Variable<String>(modelId);
    }
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      seq: Value(seq),
      role: Value(role),
      contentJson: Value(contentJson),
      createdAt: Value(createdAt),
      profileId: profileId == null && nullToAbsent
          ? const Value.absent()
          : Value(profileId),
      modelId: modelId == null && nullToAbsent
          ? const Value.absent()
          : Value(modelId),
    );
  }

  factory MessageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageRow(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      seq: serializer.fromJson<int>(json['seq']),
      role: serializer.fromJson<String>(json['role']),
      contentJson: serializer.fromJson<String>(json['contentJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      profileId: serializer.fromJson<String?>(json['profileId']),
      modelId: serializer.fromJson<String?>(json['modelId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'seq': serializer.toJson<int>(seq),
      'role': serializer.toJson<String>(role),
      'contentJson': serializer.toJson<String>(contentJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'profileId': serializer.toJson<String?>(profileId),
      'modelId': serializer.toJson<String?>(modelId),
    };
  }

  MessageRow copyWith({
    String? id,
    String? sessionId,
    int? seq,
    String? role,
    String? contentJson,
    DateTime? createdAt,
    Value<String?> profileId = const Value.absent(),
    Value<String?> modelId = const Value.absent(),
  }) => MessageRow(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    seq: seq ?? this.seq,
    role: role ?? this.role,
    contentJson: contentJson ?? this.contentJson,
    createdAt: createdAt ?? this.createdAt,
    profileId: profileId.present ? profileId.value : this.profileId,
    modelId: modelId.present ? modelId.value : this.modelId,
  );
  MessageRow copyWithCompanion(MessagesCompanion data) {
    return MessageRow(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      seq: data.seq.present ? data.seq.value : this.seq,
      role: data.role.present ? data.role.value : this.role,
      contentJson: data.contentJson.present
          ? data.contentJson.value
          : this.contentJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      modelId: data.modelId.present ? data.modelId.value : this.modelId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageRow(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('seq: $seq, ')
          ..write('role: $role, ')
          ..write('contentJson: $contentJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('profileId: $profileId, ')
          ..write('modelId: $modelId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    seq,
    role,
    contentJson,
    createdAt,
    profileId,
    modelId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageRow &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.seq == this.seq &&
          other.role == this.role &&
          other.contentJson == this.contentJson &&
          other.createdAt == this.createdAt &&
          other.profileId == this.profileId &&
          other.modelId == this.modelId);
}

class MessagesCompanion extends UpdateCompanion<MessageRow> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<int> seq;
  final Value<String> role;
  final Value<String> contentJson;
  final Value<DateTime> createdAt;
  final Value<String?> profileId;
  final Value<String?> modelId;
  final Value<int> rowid;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.seq = const Value.absent(),
    this.role = const Value.absent(),
    this.contentJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.profileId = const Value.absent(),
    this.modelId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String id,
    required String sessionId,
    required int seq,
    required String role,
    required String contentJson,
    required DateTime createdAt,
    this.profileId = const Value.absent(),
    this.modelId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       seq = Value(seq),
       role = Value(role),
       contentJson = Value(contentJson),
       createdAt = Value(createdAt);
  static Insertable<MessageRow> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<int>? seq,
    Expression<String>? role,
    Expression<String>? contentJson,
    Expression<int>? createdAt,
    Expression<String>? profileId,
    Expression<String>? modelId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (seq != null) 'seq': seq,
      if (role != null) 'role': role,
      if (contentJson != null) 'content_json': contentJson,
      if (createdAt != null) 'created_at': createdAt,
      if (profileId != null) 'profile_id': profileId,
      if (modelId != null) 'model_id': modelId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<int>? seq,
    Value<String>? role,
    Value<String>? contentJson,
    Value<DateTime>? createdAt,
    Value<String?>? profileId,
    Value<String?>? modelId,
    Value<int>? rowid,
  }) {
    return MessagesCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      seq: seq ?? this.seq,
      role: role ?? this.role,
      contentJson: contentJson ?? this.contentJson,
      createdAt: createdAt ?? this.createdAt,
      profileId: profileId ?? this.profileId,
      modelId: modelId ?? this.modelId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (contentJson.present) {
      map['content_json'] = Variable<String>(contentJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(
        $MessagesTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (modelId.present) {
      map['model_id'] = Variable<String>(modelId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('seq: $seq, ')
          ..write('role: $role, ')
          ..write('contentJson: $contentJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('profileId: $profileId, ')
          ..write('modelId: $modelId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AuditLogTable extends AuditLog with TableInfo<$AuditLogTable, AuditRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AuditLogTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> at =
      GeneratedColumn<int>(
        'at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($AuditLogTable.$converterat);
  @override
  late final GeneratedColumnWithTypeConverter<AuditKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<AuditKind>($AuditLogTable.$converterkind);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
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
  @override
  List<GeneratedColumn> get $columns => [id, at, kind, sessionId, payloadJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'audit_log';
  @override
  VerificationContext validateIntegrity(
    Insertable<AuditRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AuditRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AuditRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      at: $AuditLogTable.$converterat.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}at'],
        )!,
      ),
      kind: $AuditLogTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      ),
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
    );
  }

  @override
  $AuditLogTable createAlias(String alias) {
    return $AuditLogTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterat = epochMicros;
  static JsonTypeConverter2<AuditKind, String, String> $converterkind =
      const EnumNameConverter<AuditKind>(AuditKind.values);
}

class AuditRow extends DataClass implements Insertable<AuditRow> {
  final int id;
  final DateTime at;
  final AuditKind kind;
  final String? sessionId;
  final String payloadJson;
  const AuditRow({
    required this.id,
    required this.at,
    required this.kind,
    this.sessionId,
    required this.payloadJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    {
      map['at'] = Variable<int>($AuditLogTable.$converterat.toSql(at));
    }
    {
      map['kind'] = Variable<String>($AuditLogTable.$converterkind.toSql(kind));
    }
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<String>(sessionId);
    }
    map['payload_json'] = Variable<String>(payloadJson);
    return map;
  }

  AuditLogCompanion toCompanion(bool nullToAbsent) {
    return AuditLogCompanion(
      id: Value(id),
      at: Value(at),
      kind: Value(kind),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      payloadJson: Value(payloadJson),
    );
  }

  factory AuditRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AuditRow(
      id: serializer.fromJson<int>(json['id']),
      at: serializer.fromJson<DateTime>(json['at']),
      kind: $AuditLogTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      sessionId: serializer.fromJson<String?>(json['sessionId']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'at': serializer.toJson<DateTime>(at),
      'kind': serializer.toJson<String>(
        $AuditLogTable.$converterkind.toJson(kind),
      ),
      'sessionId': serializer.toJson<String?>(sessionId),
      'payloadJson': serializer.toJson<String>(payloadJson),
    };
  }

  AuditRow copyWith({
    int? id,
    DateTime? at,
    AuditKind? kind,
    Value<String?> sessionId = const Value.absent(),
    String? payloadJson,
  }) => AuditRow(
    id: id ?? this.id,
    at: at ?? this.at,
    kind: kind ?? this.kind,
    sessionId: sessionId.present ? sessionId.value : this.sessionId,
    payloadJson: payloadJson ?? this.payloadJson,
  );
  AuditRow copyWithCompanion(AuditLogCompanion data) {
    return AuditRow(
      id: data.id.present ? data.id.value : this.id,
      at: data.at.present ? data.at.value : this.at,
      kind: data.kind.present ? data.kind.value : this.kind,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AuditRow(')
          ..write('id: $id, ')
          ..write('at: $at, ')
          ..write('kind: $kind, ')
          ..write('sessionId: $sessionId, ')
          ..write('payloadJson: $payloadJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, at, kind, sessionId, payloadJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuditRow &&
          other.id == this.id &&
          other.at == this.at &&
          other.kind == this.kind &&
          other.sessionId == this.sessionId &&
          other.payloadJson == this.payloadJson);
}

class AuditLogCompanion extends UpdateCompanion<AuditRow> {
  final Value<int> id;
  final Value<DateTime> at;
  final Value<AuditKind> kind;
  final Value<String?> sessionId;
  final Value<String> payloadJson;
  const AuditLogCompanion({
    this.id = const Value.absent(),
    this.at = const Value.absent(),
    this.kind = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.payloadJson = const Value.absent(),
  });
  AuditLogCompanion.insert({
    this.id = const Value.absent(),
    required DateTime at,
    required AuditKind kind,
    this.sessionId = const Value.absent(),
    required String payloadJson,
  }) : at = Value(at),
       kind = Value(kind),
       payloadJson = Value(payloadJson);
  static Insertable<AuditRow> custom({
    Expression<int>? id,
    Expression<int>? at,
    Expression<String>? kind,
    Expression<String>? sessionId,
    Expression<String>? payloadJson,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (at != null) 'at': at,
      if (kind != null) 'kind': kind,
      if (sessionId != null) 'session_id': sessionId,
      if (payloadJson != null) 'payload_json': payloadJson,
    });
  }

  AuditLogCompanion copyWith({
    Value<int>? id,
    Value<DateTime>? at,
    Value<AuditKind>? kind,
    Value<String?>? sessionId,
    Value<String>? payloadJson,
  }) {
    return AuditLogCompanion(
      id: id ?? this.id,
      at: at ?? this.at,
      kind: kind ?? this.kind,
      sessionId: sessionId ?? this.sessionId,
      payloadJson: payloadJson ?? this.payloadJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (at.present) {
      map['at'] = Variable<int>($AuditLogTable.$converterat.toSql(at.value));
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $AuditLogTable.$converterkind.toSql(kind.value),
      );
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AuditLogCompanion(')
          ..write('id: $id, ')
          ..write('at: $at, ')
          ..write('kind: $kind, ')
          ..write('sessionId: $sessionId, ')
          ..write('payloadJson: $payloadJson')
          ..write(')'))
        .toString();
  }
}

class $ProviderProfilesTable extends ProviderProfiles
    with TableInfo<$ProviderProfilesTable, ProfileRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProviderProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, json];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'provider_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProfileRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProfileRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProfileRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
    );
  }

  @override
  $ProviderProfilesTable createAlias(String alias) {
    return $ProviderProfilesTable(attachedDatabase, alias);
  }
}

class ProfileRow extends DataClass implements Insertable<ProfileRow> {
  final String id;
  final String json;
  const ProfileRow({required this.id, required this.json});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['json'] = Variable<String>(json);
    return map;
  }

  ProviderProfilesCompanion toCompanion(bool nullToAbsent) {
    return ProviderProfilesCompanion(id: Value(id), json: Value(json));
  }

  factory ProfileRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProfileRow(
      id: serializer.fromJson<String>(json['id']),
      json: serializer.fromJson<String>(json['json']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'json': serializer.toJson<String>(json),
    };
  }

  ProfileRow copyWith({String? id, String? json}) =>
      ProfileRow(id: id ?? this.id, json: json ?? this.json);
  ProfileRow copyWithCompanion(ProviderProfilesCompanion data) {
    return ProfileRow(
      id: data.id.present ? data.id.value : this.id,
      json: data.json.present ? data.json.value : this.json,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProfileRow(')
          ..write('id: $id, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, json);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProfileRow && other.id == this.id && other.json == this.json);
}

class ProviderProfilesCompanion extends UpdateCompanion<ProfileRow> {
  final Value<String> id;
  final Value<String> json;
  final Value<int> rowid;
  const ProviderProfilesCompanion({
    this.id = const Value.absent(),
    this.json = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProviderProfilesCompanion.insert({
    required String id,
    required String json,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       json = Value(json);
  static Insertable<ProfileRow> custom({
    Expression<String>? id,
    Expression<String>? json,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (json != null) 'json': json,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProviderProfilesCompanion copyWith({
    Value<String>? id,
    Value<String>? json,
    Value<int>? rowid,
  }) {
    return ProviderProfilesCompanion(
      id: id ?? this.id,
      json: json ?? this.json,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProviderProfilesCompanion(')
          ..write('id: $id, ')
          ..write('json: $json, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UsageRecordsTable extends UsageRecords
    with TableInfo<$UsageRecordsTable, UsageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UsageRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> at =
      GeneratedColumn<int>(
        'at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($UsageRecordsTable.$converterat);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelIdMeta = const VerificationMeta(
    'modelId',
  );
  @override
  late final GeneratedColumn<String> modelId = GeneratedColumn<String>(
    'model_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inputTokensMeta = const VerificationMeta(
    'inputTokens',
  );
  @override
  late final GeneratedColumn<int> inputTokens = GeneratedColumn<int>(
    'input_tokens',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _outputTokensMeta = const VerificationMeta(
    'outputTokens',
  );
  @override
  late final GeneratedColumn<int> outputTokens = GeneratedColumn<int>(
    'output_tokens',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedTokensMeta = const VerificationMeta(
    'cachedTokens',
  );
  @override
  late final GeneratedColumn<int> cachedTokens = GeneratedColumn<int>(
    'cached_tokens',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cacheWriteTokensMeta = const VerificationMeta(
    'cacheWriteTokens',
  );
  @override
  late final GeneratedColumn<int> cacheWriteTokens = GeneratedColumn<int>(
    'cache_write_tokens',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _costMicrosMeta = const VerificationMeta(
    'costMicros',
  );
  @override
  late final GeneratedColumn<int> costMicros = GeneratedColumn<int>(
    'cost_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    at,
    sessionId,
    profileId,
    modelId,
    inputTokens,
    outputTokens,
    cachedTokens,
    cacheWriteTokens,
    costMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'usage_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<UsageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('model_id')) {
      context.handle(
        _modelIdMeta,
        modelId.isAcceptableOrUnknown(data['model_id']!, _modelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_modelIdMeta);
    }
    if (data.containsKey('input_tokens')) {
      context.handle(
        _inputTokensMeta,
        inputTokens.isAcceptableOrUnknown(
          data['input_tokens']!,
          _inputTokensMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_inputTokensMeta);
    }
    if (data.containsKey('output_tokens')) {
      context.handle(
        _outputTokensMeta,
        outputTokens.isAcceptableOrUnknown(
          data['output_tokens']!,
          _outputTokensMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_outputTokensMeta);
    }
    if (data.containsKey('cached_tokens')) {
      context.handle(
        _cachedTokensMeta,
        cachedTokens.isAcceptableOrUnknown(
          data['cached_tokens']!,
          _cachedTokensMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cachedTokensMeta);
    }
    if (data.containsKey('cache_write_tokens')) {
      context.handle(
        _cacheWriteTokensMeta,
        cacheWriteTokens.isAcceptableOrUnknown(
          data['cache_write_tokens']!,
          _cacheWriteTokensMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cacheWriteTokensMeta);
    }
    if (data.containsKey('cost_micros')) {
      context.handle(
        _costMicrosMeta,
        costMicros.isAcceptableOrUnknown(data['cost_micros']!, _costMicrosMeta),
      );
    } else if (isInserting) {
      context.missing(_costMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UsageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UsageRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      at: $UsageRecordsTable.$converterat.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}at'],
        )!,
      ),
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      modelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_id'],
      )!,
      inputTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}input_tokens'],
      )!,
      outputTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}output_tokens'],
      )!,
      cachedTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cached_tokens'],
      )!,
      cacheWriteTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cache_write_tokens'],
      )!,
      costMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cost_micros'],
      )!,
    );
  }

  @override
  $UsageRecordsTable createAlias(String alias) {
    return $UsageRecordsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterat = epochMicros;
}

class UsageRow extends DataClass implements Insertable<UsageRow> {
  final int id;
  final DateTime at;
  final String sessionId;
  final String profileId;
  final String modelId;
  final int inputTokens;
  final int outputTokens;
  final int cachedTokens;
  final int cacheWriteTokens;
  final int costMicros;
  const UsageRow({
    required this.id,
    required this.at,
    required this.sessionId,
    required this.profileId,
    required this.modelId,
    required this.inputTokens,
    required this.outputTokens,
    required this.cachedTokens,
    required this.cacheWriteTokens,
    required this.costMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    {
      map['at'] = Variable<int>($UsageRecordsTable.$converterat.toSql(at));
    }
    map['session_id'] = Variable<String>(sessionId);
    map['profile_id'] = Variable<String>(profileId);
    map['model_id'] = Variable<String>(modelId);
    map['input_tokens'] = Variable<int>(inputTokens);
    map['output_tokens'] = Variable<int>(outputTokens);
    map['cached_tokens'] = Variable<int>(cachedTokens);
    map['cache_write_tokens'] = Variable<int>(cacheWriteTokens);
    map['cost_micros'] = Variable<int>(costMicros);
    return map;
  }

  UsageRecordsCompanion toCompanion(bool nullToAbsent) {
    return UsageRecordsCompanion(
      id: Value(id),
      at: Value(at),
      sessionId: Value(sessionId),
      profileId: Value(profileId),
      modelId: Value(modelId),
      inputTokens: Value(inputTokens),
      outputTokens: Value(outputTokens),
      cachedTokens: Value(cachedTokens),
      cacheWriteTokens: Value(cacheWriteTokens),
      costMicros: Value(costMicros),
    );
  }

  factory UsageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UsageRow(
      id: serializer.fromJson<int>(json['id']),
      at: serializer.fromJson<DateTime>(json['at']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      profileId: serializer.fromJson<String>(json['profileId']),
      modelId: serializer.fromJson<String>(json['modelId']),
      inputTokens: serializer.fromJson<int>(json['inputTokens']),
      outputTokens: serializer.fromJson<int>(json['outputTokens']),
      cachedTokens: serializer.fromJson<int>(json['cachedTokens']),
      cacheWriteTokens: serializer.fromJson<int>(json['cacheWriteTokens']),
      costMicros: serializer.fromJson<int>(json['costMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'at': serializer.toJson<DateTime>(at),
      'sessionId': serializer.toJson<String>(sessionId),
      'profileId': serializer.toJson<String>(profileId),
      'modelId': serializer.toJson<String>(modelId),
      'inputTokens': serializer.toJson<int>(inputTokens),
      'outputTokens': serializer.toJson<int>(outputTokens),
      'cachedTokens': serializer.toJson<int>(cachedTokens),
      'cacheWriteTokens': serializer.toJson<int>(cacheWriteTokens),
      'costMicros': serializer.toJson<int>(costMicros),
    };
  }

  UsageRow copyWith({
    int? id,
    DateTime? at,
    String? sessionId,
    String? profileId,
    String? modelId,
    int? inputTokens,
    int? outputTokens,
    int? cachedTokens,
    int? cacheWriteTokens,
    int? costMicros,
  }) => UsageRow(
    id: id ?? this.id,
    at: at ?? this.at,
    sessionId: sessionId ?? this.sessionId,
    profileId: profileId ?? this.profileId,
    modelId: modelId ?? this.modelId,
    inputTokens: inputTokens ?? this.inputTokens,
    outputTokens: outputTokens ?? this.outputTokens,
    cachedTokens: cachedTokens ?? this.cachedTokens,
    cacheWriteTokens: cacheWriteTokens ?? this.cacheWriteTokens,
    costMicros: costMicros ?? this.costMicros,
  );
  UsageRow copyWithCompanion(UsageRecordsCompanion data) {
    return UsageRow(
      id: data.id.present ? data.id.value : this.id,
      at: data.at.present ? data.at.value : this.at,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      modelId: data.modelId.present ? data.modelId.value : this.modelId,
      inputTokens: data.inputTokens.present
          ? data.inputTokens.value
          : this.inputTokens,
      outputTokens: data.outputTokens.present
          ? data.outputTokens.value
          : this.outputTokens,
      cachedTokens: data.cachedTokens.present
          ? data.cachedTokens.value
          : this.cachedTokens,
      cacheWriteTokens: data.cacheWriteTokens.present
          ? data.cacheWriteTokens.value
          : this.cacheWriteTokens,
      costMicros: data.costMicros.present
          ? data.costMicros.value
          : this.costMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UsageRow(')
          ..write('id: $id, ')
          ..write('at: $at, ')
          ..write('sessionId: $sessionId, ')
          ..write('profileId: $profileId, ')
          ..write('modelId: $modelId, ')
          ..write('inputTokens: $inputTokens, ')
          ..write('outputTokens: $outputTokens, ')
          ..write('cachedTokens: $cachedTokens, ')
          ..write('cacheWriteTokens: $cacheWriteTokens, ')
          ..write('costMicros: $costMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    at,
    sessionId,
    profileId,
    modelId,
    inputTokens,
    outputTokens,
    cachedTokens,
    cacheWriteTokens,
    costMicros,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UsageRow &&
          other.id == this.id &&
          other.at == this.at &&
          other.sessionId == this.sessionId &&
          other.profileId == this.profileId &&
          other.modelId == this.modelId &&
          other.inputTokens == this.inputTokens &&
          other.outputTokens == this.outputTokens &&
          other.cachedTokens == this.cachedTokens &&
          other.cacheWriteTokens == this.cacheWriteTokens &&
          other.costMicros == this.costMicros);
}

class UsageRecordsCompanion extends UpdateCompanion<UsageRow> {
  final Value<int> id;
  final Value<DateTime> at;
  final Value<String> sessionId;
  final Value<String> profileId;
  final Value<String> modelId;
  final Value<int> inputTokens;
  final Value<int> outputTokens;
  final Value<int> cachedTokens;
  final Value<int> cacheWriteTokens;
  final Value<int> costMicros;
  const UsageRecordsCompanion({
    this.id = const Value.absent(),
    this.at = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.profileId = const Value.absent(),
    this.modelId = const Value.absent(),
    this.inputTokens = const Value.absent(),
    this.outputTokens = const Value.absent(),
    this.cachedTokens = const Value.absent(),
    this.cacheWriteTokens = const Value.absent(),
    this.costMicros = const Value.absent(),
  });
  UsageRecordsCompanion.insert({
    this.id = const Value.absent(),
    required DateTime at,
    required String sessionId,
    required String profileId,
    required String modelId,
    required int inputTokens,
    required int outputTokens,
    required int cachedTokens,
    required int cacheWriteTokens,
    required int costMicros,
  }) : at = Value(at),
       sessionId = Value(sessionId),
       profileId = Value(profileId),
       modelId = Value(modelId),
       inputTokens = Value(inputTokens),
       outputTokens = Value(outputTokens),
       cachedTokens = Value(cachedTokens),
       cacheWriteTokens = Value(cacheWriteTokens),
       costMicros = Value(costMicros);
  static Insertable<UsageRow> custom({
    Expression<int>? id,
    Expression<int>? at,
    Expression<String>? sessionId,
    Expression<String>? profileId,
    Expression<String>? modelId,
    Expression<int>? inputTokens,
    Expression<int>? outputTokens,
    Expression<int>? cachedTokens,
    Expression<int>? cacheWriteTokens,
    Expression<int>? costMicros,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (at != null) 'at': at,
      if (sessionId != null) 'session_id': sessionId,
      if (profileId != null) 'profile_id': profileId,
      if (modelId != null) 'model_id': modelId,
      if (inputTokens != null) 'input_tokens': inputTokens,
      if (outputTokens != null) 'output_tokens': outputTokens,
      if (cachedTokens != null) 'cached_tokens': cachedTokens,
      if (cacheWriteTokens != null) 'cache_write_tokens': cacheWriteTokens,
      if (costMicros != null) 'cost_micros': costMicros,
    });
  }

  UsageRecordsCompanion copyWith({
    Value<int>? id,
    Value<DateTime>? at,
    Value<String>? sessionId,
    Value<String>? profileId,
    Value<String>? modelId,
    Value<int>? inputTokens,
    Value<int>? outputTokens,
    Value<int>? cachedTokens,
    Value<int>? cacheWriteTokens,
    Value<int>? costMicros,
  }) {
    return UsageRecordsCompanion(
      id: id ?? this.id,
      at: at ?? this.at,
      sessionId: sessionId ?? this.sessionId,
      profileId: profileId ?? this.profileId,
      modelId: modelId ?? this.modelId,
      inputTokens: inputTokens ?? this.inputTokens,
      outputTokens: outputTokens ?? this.outputTokens,
      cachedTokens: cachedTokens ?? this.cachedTokens,
      cacheWriteTokens: cacheWriteTokens ?? this.cacheWriteTokens,
      costMicros: costMicros ?? this.costMicros,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (at.present) {
      map['at'] = Variable<int>(
        $UsageRecordsTable.$converterat.toSql(at.value),
      );
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (modelId.present) {
      map['model_id'] = Variable<String>(modelId.value);
    }
    if (inputTokens.present) {
      map['input_tokens'] = Variable<int>(inputTokens.value);
    }
    if (outputTokens.present) {
      map['output_tokens'] = Variable<int>(outputTokens.value);
    }
    if (cachedTokens.present) {
      map['cached_tokens'] = Variable<int>(cachedTokens.value);
    }
    if (cacheWriteTokens.present) {
      map['cache_write_tokens'] = Variable<int>(cacheWriteTokens.value);
    }
    if (costMicros.present) {
      map['cost_micros'] = Variable<int>(costMicros.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsageRecordsCompanion(')
          ..write('id: $id, ')
          ..write('at: $at, ')
          ..write('sessionId: $sessionId, ')
          ..write('profileId: $profileId, ')
          ..write('modelId: $modelId, ')
          ..write('inputTokens: $inputTokens, ')
          ..write('outputTokens: $outputTokens, ')
          ..write('cachedTokens: $cachedTokens, ')
          ..write('cacheWriteTokens: $cacheWriteTokens, ')
          ..write('costMicros: $costMicros')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings
    with TableInfo<$SettingsTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueJsonMeta = const VerificationMeta(
    'valueJson',
  );
  @override
  late final GeneratedColumn<String> valueJson = GeneratedColumn<String>(
    'value_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, valueJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
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
    if (data.containsKey('value_json')) {
      context.handle(
        _valueJsonMeta,
        valueJson.isAcceptableOrUnknown(data['value_json']!, _valueJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_valueJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      valueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_json'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String key;
  final String valueJson;
  const SettingRow({required this.key, required this.valueJson});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value_json'] = Variable<String>(valueJson);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), valueJson: Value(valueJson));
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      key: serializer.fromJson<String>(json['key']),
      valueJson: serializer.fromJson<String>(json['valueJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'valueJson': serializer.toJson<String>(valueJson),
    };
  }

  SettingRow copyWith({String? key, String? valueJson}) =>
      SettingRow(key: key ?? this.key, valueJson: valueJson ?? this.valueJson);
  SettingRow copyWithCompanion(SettingsCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      valueJson: data.valueJson.present ? data.valueJson.value : this.valueJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('key: $key, ')
          ..write('valueJson: $valueJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, valueJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow &&
          other.key == this.key &&
          other.valueJson == this.valueJson);
}

class SettingsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> valueJson;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.valueJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String valueJson,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       valueJson = Value(valueJson);
  static Insertable<SettingRow> custom({
    Expression<String>? key,
    Expression<String>? valueJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (valueJson != null) 'value_json': valueJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? valueJson,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      valueJson: valueJson ?? this.valueJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (valueJson.present) {
      map['value_json'] = Variable<String>(valueJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('valueJson: $valueJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$WendelinDatabase extends GeneratedDatabase {
  _$WendelinDatabase(QueryExecutor e) : super(e);
  late final MemoryFts memoryFts = MemoryFts(this);
  late final $MemoryEntriesTable memoryEntries = $MemoryEntriesTable(this);
  late final Trigger memoryEntriesAi = Trigger(
    'CREATE TRIGGER memory_entries_ai AFTER INSERT ON memory_entries BEGIN INSERT INTO memory_fts (entry_id, body) VALUES (new.id, new.body);END',
    'memory_entries_ai',
  );
  late final Trigger memoryEntriesAd = Trigger(
    'CREATE TRIGGER memory_entries_ad AFTER DELETE ON memory_entries BEGIN DELETE FROM memory_fts WHERE entry_id = old.id;END',
    'memory_entries_ad',
  );
  late final Trigger memoryEntriesAu = Trigger(
    'CREATE TRIGGER memory_entries_au AFTER UPDATE OF body ON memory_entries BEGIN DELETE FROM memory_fts WHERE entry_id = old.id;INSERT INTO memory_fts (entry_id, body) VALUES (new.id, new.body);END',
    'memory_entries_au',
  );
  late final $SessionsTable sessions = $SessionsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $AuditLogTable auditLog = $AuditLogTable(this);
  late final $ProviderProfilesTable providerProfiles = $ProviderProfilesTable(
    this,
  );
  late final $UsageRecordsTable usageRecords = $UsageRecordsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final Index sessionsLastActivity = Index(
    'sessions_last_activity',
    'CREATE INDEX sessions_last_activity ON sessions (last_activity_at)',
  );
  late final Index messagesSessionSeq = Index(
    'messages_session_seq',
    'CREATE UNIQUE INDEX messages_session_seq ON messages (session_id, seq)',
  );
  late final Index auditLogAt = Index(
    'audit_log_at',
    'CREATE INDEX audit_log_at ON audit_log (at)',
  );
  late final Index usageRecordsProfileAt = Index(
    'usage_records_profile_at',
    'CREATE INDEX usage_records_profile_at ON usage_records (profile_id, at)',
  );
  late final Index usageRecordsAt = Index(
    'usage_records_at',
    'CREATE INDEX usage_records_at ON usage_records (at)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    memoryFts,
    memoryEntries,
    memoryEntriesAi,
    memoryEntriesAd,
    memoryEntriesAu,
    sessions,
    messages,
    auditLog,
    providerProfiles,
    usageRecords,
    settings,
    sessionsLastActivity,
    messagesSessionSeq,
    auditLogAt,
    usageRecordsProfileAt,
    usageRecordsAt,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'memory_entries',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [TableUpdate('memory_fts', kind: UpdateKind.insert)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'memory_entries',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('memory_fts', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'memory_entries',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [
        TableUpdate('memory_fts', kind: UpdateKind.delete),
        TableUpdate('memory_fts', kind: UpdateKind.insert),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('messages', kind: UpdateKind.delete)],
    ),
  ]);
}
