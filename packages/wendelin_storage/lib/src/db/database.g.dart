// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class NoteFts extends Table
    with TableInfo<NoteFts, NoteFt>, VirtualTableInfo<NoteFts, NoteFt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  NoteFts(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
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
  List<GeneratedColumn> get $columns => [path, title, body];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_fts';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteFt> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
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
  NoteFt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteFt(
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
    );
  }

  @override
  NoteFts createAlias(String alias) {
    return NoteFts(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
  @override
  String get moduleAndArgs =>
      'fts5(path, title, body, tokenize = \'unicode61 remove_diacritics 2\')';
}

class NoteFt extends DataClass implements Insertable<NoteFt> {
  final String path;
  final String title;
  final String body;
  const NoteFt({required this.path, required this.title, required this.body});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['path'] = Variable<String>(path);
    map['title'] = Variable<String>(title);
    map['body'] = Variable<String>(body);
    return map;
  }

  NoteFtsCompanion toCompanion(bool nullToAbsent) {
    return NoteFtsCompanion(
      path: Value(path),
      title: Value(title),
      body: Value(body),
    );
  }

  factory NoteFt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteFt(
      path: serializer.fromJson<String>(json['path']),
      title: serializer.fromJson<String>(json['title']),
      body: serializer.fromJson<String>(json['body']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'path': serializer.toJson<String>(path),
      'title': serializer.toJson<String>(title),
      'body': serializer.toJson<String>(body),
    };
  }

  NoteFt copyWith({String? path, String? title, String? body}) => NoteFt(
    path: path ?? this.path,
    title: title ?? this.title,
    body: body ?? this.body,
  );
  NoteFt copyWithCompanion(NoteFtsCompanion data) {
    return NoteFt(
      path: data.path.present ? data.path.value : this.path,
      title: data.title.present ? data.title.value : this.title,
      body: data.body.present ? data.body.value : this.body,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteFt(')
          ..write('path: $path, ')
          ..write('title: $title, ')
          ..write('body: $body')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(path, title, body);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteFt &&
          other.path == this.path &&
          other.title == this.title &&
          other.body == this.body);
}

class NoteFtsCompanion extends UpdateCompanion<NoteFt> {
  final Value<String> path;
  final Value<String> title;
  final Value<String> body;
  final Value<int> rowid;
  const NoteFtsCompanion({
    this.path = const Value.absent(),
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NoteFtsCompanion.insert({
    required String path,
    required String title,
    required String body,
    this.rowid = const Value.absent(),
  }) : path = Value(path),
       title = Value(title),
       body = Value(body);
  static Insertable<NoteFt> custom({
    Expression<String>? path,
    Expression<String>? title,
    Expression<String>? body,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (path != null) 'path': path,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NoteFtsCompanion copyWith({
    Value<String>? path,
    Value<String>? title,
    Value<String>? body,
    Value<int>? rowid,
  }) {
    return NoteFtsCompanion(
      path: path ?? this.path,
      title: title ?? this.title,
      body: body ?? this.body,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
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
    return (StringBuffer('NoteFtsCompanion(')
          ..write('path: $path, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
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
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('app'),
  );
  static const VerificationMeta _personMeta = const VerificationMeta('person');
  @override
  late final GeneratedColumn<String> person = GeneratedColumn<String>(
    'person',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    startedAt,
    lastActivityAt,
    title,
    origin,
    person,
  ];
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
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    }
    if (data.containsKey('person')) {
      context.handle(
        _personMeta,
        person.isAcceptableOrUnknown(data['person']!, _personMeta),
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
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin'],
      )!,
      person: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}person'],
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

  /// Which engine opened the session (`app` or `overlay`, WP67).
  final String origin;

  /// Opaque id of the person whose conversation this is (v6, WP92b), `null`
  /// for the default. Never exported or logged.
  final String? person;
  const SessionRow({
    required this.id,
    required this.startedAt,
    required this.lastActivityAt,
    this.title,
    required this.origin,
    this.person,
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
    map['origin'] = Variable<String>(origin);
    if (!nullToAbsent || person != null) {
      map['person'] = Variable<String>(person);
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
      origin: Value(origin),
      person: person == null && nullToAbsent
          ? const Value.absent()
          : Value(person),
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
      origin: serializer.fromJson<String>(json['origin']),
      person: serializer.fromJson<String?>(json['person']),
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
      'origin': serializer.toJson<String>(origin),
      'person': serializer.toJson<String?>(person),
    };
  }

  SessionRow copyWith({
    String? id,
    DateTime? startedAt,
    DateTime? lastActivityAt,
    Value<String?> title = const Value.absent(),
    String? origin,
    Value<String?> person = const Value.absent(),
  }) => SessionRow(
    id: id ?? this.id,
    startedAt: startedAt ?? this.startedAt,
    lastActivityAt: lastActivityAt ?? this.lastActivityAt,
    title: title.present ? title.value : this.title,
    origin: origin ?? this.origin,
    person: person.present ? person.value : this.person,
  );
  SessionRow copyWithCompanion(SessionsCompanion data) {
    return SessionRow(
      id: data.id.present ? data.id.value : this.id,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      lastActivityAt: data.lastActivityAt.present
          ? data.lastActivityAt.value
          : this.lastActivityAt,
      title: data.title.present ? data.title.value : this.title,
      origin: data.origin.present ? data.origin.value : this.origin,
      person: data.person.present ? data.person.value : this.person,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionRow(')
          ..write('id: $id, ')
          ..write('startedAt: $startedAt, ')
          ..write('lastActivityAt: $lastActivityAt, ')
          ..write('title: $title, ')
          ..write('origin: $origin, ')
          ..write('person: $person')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, startedAt, lastActivityAt, title, origin, person);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionRow &&
          other.id == this.id &&
          other.startedAt == this.startedAt &&
          other.lastActivityAt == this.lastActivityAt &&
          other.title == this.title &&
          other.origin == this.origin &&
          other.person == this.person);
}

class SessionsCompanion extends UpdateCompanion<SessionRow> {
  final Value<String> id;
  final Value<DateTime> startedAt;
  final Value<DateTime> lastActivityAt;
  final Value<String?> title;
  final Value<String> origin;
  final Value<String?> person;
  final Value<int> rowid;
  const SessionsCompanion({
    this.id = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.lastActivityAt = const Value.absent(),
    this.title = const Value.absent(),
    this.origin = const Value.absent(),
    this.person = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionsCompanion.insert({
    required String id,
    required DateTime startedAt,
    required DateTime lastActivityAt,
    this.title = const Value.absent(),
    this.origin = const Value.absent(),
    this.person = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       startedAt = Value(startedAt),
       lastActivityAt = Value(lastActivityAt);
  static Insertable<SessionRow> custom({
    Expression<String>? id,
    Expression<int>? startedAt,
    Expression<int>? lastActivityAt,
    Expression<String>? title,
    Expression<String>? origin,
    Expression<String>? person,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (startedAt != null) 'started_at': startedAt,
      if (lastActivityAt != null) 'last_activity_at': lastActivityAt,
      if (title != null) 'title': title,
      if (origin != null) 'origin': origin,
      if (person != null) 'person': person,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionsCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? startedAt,
    Value<DateTime>? lastActivityAt,
    Value<String?>? title,
    Value<String>? origin,
    Value<String?>? person,
    Value<int>? rowid,
  }) {
    return SessionsCompanion(
      id: id ?? this.id,
      startedAt: startedAt ?? this.startedAt,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      title: title ?? this.title,
      origin: origin ?? this.origin,
      person: person ?? this.person,
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
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (person.present) {
      map['person'] = Variable<String>(person.value);
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
          ..write('origin: $origin, ')
          ..write('person: $person, ')
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
  static const VerificationMeta _privacyFloorMeta = const VerificationMeta(
    'privacyFloor',
  );
  @override
  late final GeneratedColumn<String> privacyFloor = GeneratedColumn<String>(
    'privacy_floor',
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
    privacyFloor,
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
    if (data.containsKey('privacy_floor')) {
      context.handle(
        _privacyFloorMeta,
        privacyFloor.isAcceptableOrUnknown(
          data['privacy_floor']!,
          _privacyFloorMeta,
        ),
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
      privacyFloor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}privacy_floor'],
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

  /// `PrivacyLevel.name` of a privately routed turn (v3), else null.
  final String? privacyFloor;
  const MessageRow({
    required this.id,
    required this.sessionId,
    required this.seq,
    required this.role,
    required this.contentJson,
    required this.createdAt,
    this.profileId,
    this.modelId,
    this.privacyFloor,
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
    if (!nullToAbsent || privacyFloor != null) {
      map['privacy_floor'] = Variable<String>(privacyFloor);
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
      privacyFloor: privacyFloor == null && nullToAbsent
          ? const Value.absent()
          : Value(privacyFloor),
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
      privacyFloor: serializer.fromJson<String?>(json['privacyFloor']),
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
      'privacyFloor': serializer.toJson<String?>(privacyFloor),
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
    Value<String?> privacyFloor = const Value.absent(),
  }) => MessageRow(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    seq: seq ?? this.seq,
    role: role ?? this.role,
    contentJson: contentJson ?? this.contentJson,
    createdAt: createdAt ?? this.createdAt,
    profileId: profileId.present ? profileId.value : this.profileId,
    modelId: modelId.present ? modelId.value : this.modelId,
    privacyFloor: privacyFloor.present ? privacyFloor.value : this.privacyFloor,
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
      privacyFloor: data.privacyFloor.present
          ? data.privacyFloor.value
          : this.privacyFloor,
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
          ..write('modelId: $modelId, ')
          ..write('privacyFloor: $privacyFloor')
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
    privacyFloor,
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
          other.modelId == this.modelId &&
          other.privacyFloor == this.privacyFloor);
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
  final Value<String?> privacyFloor;
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
    this.privacyFloor = const Value.absent(),
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
    this.privacyFloor = const Value.absent(),
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
    Expression<String>? privacyFloor,
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
      if (privacyFloor != null) 'privacy_floor': privacyFloor,
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
    Value<String?>? privacyFloor,
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
      privacyFloor: privacyFloor ?? this.privacyFloor,
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
    if (privacyFloor.present) {
      map['privacy_floor'] = Variable<String>(privacyFloor.value);
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
          ..write('privacyFloor: $privacyFloor, ')
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
  late final GeneratedColumnWithTypeConverter<StoredMemoryCategory, String>
  category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<StoredMemoryCategory>($MemoryEntriesTable.$convertercategory);
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
  static const VerificationMeta _privacyFloorMeta = const VerificationMeta(
    'privacyFloor',
  );
  @override
  late final GeneratedColumn<String> privacyFloor = GeneratedColumn<String>(
    'privacy_floor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ownerMeta = const VerificationMeta('owner');
  @override
  late final GeneratedColumn<String> owner = GeneratedColumn<String>(
    'owner',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    body,
    category,
    source,
    createdAt,
    lastUsedAt,
    privacyFloor,
    owner,
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
    if (data.containsKey('privacy_floor')) {
      context.handle(
        _privacyFloorMeta,
        privacyFloor.isAcceptableOrUnknown(
          data['privacy_floor']!,
          _privacyFloorMeta,
        ),
      );
    }
    if (data.containsKey('owner')) {
      context.handle(
        _ownerMeta,
        owner.isAcceptableOrUnknown(data['owner']!, _ownerMeta),
      );
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
      privacyFloor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}privacy_floor'],
      ),
      owner: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner'],
      )!,
    );
  }

  @override
  $MemoryEntriesTable createAlias(String alias) {
    return $MemoryEntriesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<StoredMemoryCategory, String, String>
  $convertercategory = const EnumNameConverter<StoredMemoryCategory>(
    StoredMemoryCategory.values,
  );
  static TypeConverter<DateTime, int> $convertercreatedAt = epochMicros;
  static TypeConverter<DateTime, int> $converterlastUsedAt = epochMicros;
}

class MemoryRow extends DataClass implements Insertable<MemoryRow> {
  final String id;

  /// The remembered text. Named `body` (not `text`) because drift's
  /// schema-dump code generator cannot name a column getter `text`.
  final String body;
  final StoredMemoryCategory category;
  final String source;
  final DateTime createdAt;
  final DateTime lastUsedAt;

  /// `PrivacyLevel.name` if saved by a private run (v3), else null.
  final String? privacyFloor;

  /// Memory namespace (v6, WP92b): `''` = the default memory, otherwise the
  /// namespace of one person. Every query filters on it.
  final String owner;
  const MemoryRow({
    required this.id,
    required this.body,
    required this.category,
    required this.source,
    required this.createdAt,
    required this.lastUsedAt,
    this.privacyFloor,
    required this.owner,
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
    if (!nullToAbsent || privacyFloor != null) {
      map['privacy_floor'] = Variable<String>(privacyFloor);
    }
    map['owner'] = Variable<String>(owner);
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
      privacyFloor: privacyFloor == null && nullToAbsent
          ? const Value.absent()
          : Value(privacyFloor),
      owner: Value(owner),
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
      privacyFloor: serializer.fromJson<String?>(json['privacyFloor']),
      owner: serializer.fromJson<String>(json['owner']),
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
      'privacyFloor': serializer.toJson<String?>(privacyFloor),
      'owner': serializer.toJson<String>(owner),
    };
  }

  MemoryRow copyWith({
    String? id,
    String? body,
    StoredMemoryCategory? category,
    String? source,
    DateTime? createdAt,
    DateTime? lastUsedAt,
    Value<String?> privacyFloor = const Value.absent(),
    String? owner,
  }) => MemoryRow(
    id: id ?? this.id,
    body: body ?? this.body,
    category: category ?? this.category,
    source: source ?? this.source,
    createdAt: createdAt ?? this.createdAt,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    privacyFloor: privacyFloor.present ? privacyFloor.value : this.privacyFloor,
    owner: owner ?? this.owner,
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
      privacyFloor: data.privacyFloor.present
          ? data.privacyFloor.value
          : this.privacyFloor,
      owner: data.owner.present ? data.owner.value : this.owner,
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
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('privacyFloor: $privacyFloor, ')
          ..write('owner: $owner')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    body,
    category,
    source,
    createdAt,
    lastUsedAt,
    privacyFloor,
    owner,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MemoryRow &&
          other.id == this.id &&
          other.body == this.body &&
          other.category == this.category &&
          other.source == this.source &&
          other.createdAt == this.createdAt &&
          other.lastUsedAt == this.lastUsedAt &&
          other.privacyFloor == this.privacyFloor &&
          other.owner == this.owner);
}

class MemoryEntriesCompanion extends UpdateCompanion<MemoryRow> {
  final Value<String> id;
  final Value<String> body;
  final Value<StoredMemoryCategory> category;
  final Value<String> source;
  final Value<DateTime> createdAt;
  final Value<DateTime> lastUsedAt;
  final Value<String?> privacyFloor;
  final Value<String> owner;
  final Value<int> rowid;
  const MemoryEntriesCompanion({
    this.id = const Value.absent(),
    this.body = const Value.absent(),
    this.category = const Value.absent(),
    this.source = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.privacyFloor = const Value.absent(),
    this.owner = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MemoryEntriesCompanion.insert({
    required String id,
    required String body,
    required StoredMemoryCategory category,
    required String source,
    required DateTime createdAt,
    required DateTime lastUsedAt,
    this.privacyFloor = const Value.absent(),
    this.owner = const Value.absent(),
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
    Expression<String>? privacyFloor,
    Expression<String>? owner,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (body != null) 'body': body,
      if (category != null) 'category': category,
      if (source != null) 'source': source,
      if (createdAt != null) 'created_at': createdAt,
      if (lastUsedAt != null) 'last_used_at': lastUsedAt,
      if (privacyFloor != null) 'privacy_floor': privacyFloor,
      if (owner != null) 'owner': owner,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MemoryEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? body,
    Value<StoredMemoryCategory>? category,
    Value<String>? source,
    Value<DateTime>? createdAt,
    Value<DateTime>? lastUsedAt,
    Value<String?>? privacyFloor,
    Value<String>? owner,
    Value<int>? rowid,
  }) {
    return MemoryEntriesCompanion(
      id: id ?? this.id,
      body: body ?? this.body,
      category: category ?? this.category,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      privacyFloor: privacyFloor ?? this.privacyFloor,
      owner: owner ?? this.owner,
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
    if (privacyFloor.present) {
      map['privacy_floor'] = Variable<String>(privacyFloor.value);
    }
    if (owner.present) {
      map['owner'] = Variable<String>(owner.value);
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
          ..write('privacyFloor: $privacyFloor, ')
          ..write('owner: $owner, ')
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

class $NoteFilesTable extends NoteFiles
    with TableInfo<$NoteFilesTable, NoteFileRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteFilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> modifiedAt =
      GeneratedColumn<int>(
        'modified_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($NoteFilesTable.$convertermodifiedAt);
  @override
  List<GeneratedColumn> get $columns => [path, title, modifiedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_files';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteFileRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {path};
  @override
  NoteFileRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteFileRow(
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      modifiedAt: $NoteFilesTable.$convertermodifiedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}modified_at'],
        )!,
      ),
    );
  }

  @override
  $NoteFilesTable createAlias(String alias) {
    return $NoteFilesTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $convertermodifiedAt = epochMicros;
}

class NoteFileRow extends DataClass implements Insertable<NoteFileRow> {
  /// Vault-relative path.
  final String path;
  final String title;

  /// Modification time of the file when it was indexed.
  final DateTime modifiedAt;
  const NoteFileRow({
    required this.path,
    required this.title,
    required this.modifiedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['path'] = Variable<String>(path);
    map['title'] = Variable<String>(title);
    {
      map['modified_at'] = Variable<int>(
        $NoteFilesTable.$convertermodifiedAt.toSql(modifiedAt),
      );
    }
    return map;
  }

  NoteFilesCompanion toCompanion(bool nullToAbsent) {
    return NoteFilesCompanion(
      path: Value(path),
      title: Value(title),
      modifiedAt: Value(modifiedAt),
    );
  }

  factory NoteFileRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteFileRow(
      path: serializer.fromJson<String>(json['path']),
      title: serializer.fromJson<String>(json['title']),
      modifiedAt: serializer.fromJson<DateTime>(json['modifiedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'path': serializer.toJson<String>(path),
      'title': serializer.toJson<String>(title),
      'modifiedAt': serializer.toJson<DateTime>(modifiedAt),
    };
  }

  NoteFileRow copyWith({String? path, String? title, DateTime? modifiedAt}) =>
      NoteFileRow(
        path: path ?? this.path,
        title: title ?? this.title,
        modifiedAt: modifiedAt ?? this.modifiedAt,
      );
  NoteFileRow copyWithCompanion(NoteFilesCompanion data) {
    return NoteFileRow(
      path: data.path.present ? data.path.value : this.path,
      title: data.title.present ? data.title.value : this.title,
      modifiedAt: data.modifiedAt.present
          ? data.modifiedAt.value
          : this.modifiedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteFileRow(')
          ..write('path: $path, ')
          ..write('title: $title, ')
          ..write('modifiedAt: $modifiedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(path, title, modifiedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteFileRow &&
          other.path == this.path &&
          other.title == this.title &&
          other.modifiedAt == this.modifiedAt);
}

class NoteFilesCompanion extends UpdateCompanion<NoteFileRow> {
  final Value<String> path;
  final Value<String> title;
  final Value<DateTime> modifiedAt;
  final Value<int> rowid;
  const NoteFilesCompanion({
    this.path = const Value.absent(),
    this.title = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NoteFilesCompanion.insert({
    required String path,
    required String title,
    required DateTime modifiedAt,
    this.rowid = const Value.absent(),
  }) : path = Value(path),
       title = Value(title),
       modifiedAt = Value(modifiedAt);
  static Insertable<NoteFileRow> custom({
    Expression<String>? path,
    Expression<String>? title,
    Expression<int>? modifiedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (path != null) 'path': path,
      if (title != null) 'title': title,
      if (modifiedAt != null) 'modified_at': modifiedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NoteFilesCompanion copyWith({
    Value<String>? path,
    Value<String>? title,
    Value<DateTime>? modifiedAt,
    Value<int>? rowid,
  }) {
    return NoteFilesCompanion(
      path: path ?? this.path,
      title: title ?? this.title,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (modifiedAt.present) {
      map['modified_at'] = Variable<int>(
        $NoteFilesTable.$convertermodifiedAt.toSql(modifiedAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteFilesCompanion(')
          ..write('path: $path, ')
          ..write('title: $title, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AttestationLogTable extends AttestationLog
    with TableInfo<$AttestationLogTable, AttestationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AttestationLogTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _logIdMeta = const VerificationMeta('logId');
  @override
  late final GeneratedColumn<String> logId = GeneratedColumn<String>(
    'log_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> at =
      GeneratedColumn<int>(
        'at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($AttestationLogTable.$converterat);
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
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const VerificationMeta _stepIdMeta = const VerificationMeta('stepId');
  @override
  late final GeneratedColumn<String> stepId = GeneratedColumn<String>(
    'step_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _receiptIdMeta = const VerificationMeta(
    'receiptId',
  );
  @override
  late final GeneratedColumn<String> receiptId = GeneratedColumn<String>(
    'receipt_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _workloadKeysetDigestMeta =
      const VerificationMeta('workloadKeysetDigest');
  @override
  late final GeneratedColumn<String> workloadKeysetDigest =
      GeneratedColumn<String>(
        'workload_keyset_digest',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _workloadIdMeta = const VerificationMeta(
    'workloadId',
  );
  @override
  late final GeneratedColumn<String> workloadId = GeneratedColumn<String>(
    'workload_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _repoCommitMeta = const VerificationMeta(
    'repoCommit',
  );
  @override
  late final GeneratedColumn<String> repoCommit = GeneratedColumn<String>(
    'repo_commit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _composeHashMeta = const VerificationMeta(
    'composeHash',
  );
  @override
  late final GeneratedColumn<String> composeHash = GeneratedColumn<String>(
    'compose_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stagesJsonMeta = const VerificationMeta(
    'stagesJson',
  );
  @override
  late final GeneratedColumn<String> stagesJson = GeneratedColumn<String>(
    'stages_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tcbStatusMeta = const VerificationMeta(
    'tcbStatus',
  );
  @override
  late final GeneratedColumn<String> tcbStatus = GeneratedColumn<String>(
    'tcb_status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reasonCodeMeta = const VerificationMeta(
    'reasonCode',
  );
  @override
  late final GeneratedColumn<String> reasonCode = GeneratedColumn<String>(
    'reason_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    logId,
    at,
    profileId,
    model,
    kind,
    sessionId,
    stepId,
    receiptId,
    workloadKeysetDigest,
    workloadId,
    repoCommit,
    composeHash,
    status,
    stagesJson,
    tcbStatus,
    reasonCode,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'attestation_log';
  @override
  VerificationContext validateIntegrity(
    Insertable<AttestationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('log_id')) {
      context.handle(
        _logIdMeta,
        logId.isAcceptableOrUnknown(data['log_id']!, _logIdMeta),
      );
    } else if (isInserting) {
      context.missing(_logIdMeta);
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    }
    if (data.containsKey('step_id')) {
      context.handle(
        _stepIdMeta,
        stepId.isAcceptableOrUnknown(data['step_id']!, _stepIdMeta),
      );
    }
    if (data.containsKey('receipt_id')) {
      context.handle(
        _receiptIdMeta,
        receiptId.isAcceptableOrUnknown(data['receipt_id']!, _receiptIdMeta),
      );
    }
    if (data.containsKey('workload_keyset_digest')) {
      context.handle(
        _workloadKeysetDigestMeta,
        workloadKeysetDigest.isAcceptableOrUnknown(
          data['workload_keyset_digest']!,
          _workloadKeysetDigestMeta,
        ),
      );
    }
    if (data.containsKey('workload_id')) {
      context.handle(
        _workloadIdMeta,
        workloadId.isAcceptableOrUnknown(data['workload_id']!, _workloadIdMeta),
      );
    }
    if (data.containsKey('repo_commit')) {
      context.handle(
        _repoCommitMeta,
        repoCommit.isAcceptableOrUnknown(data['repo_commit']!, _repoCommitMeta),
      );
    }
    if (data.containsKey('compose_hash')) {
      context.handle(
        _composeHashMeta,
        composeHash.isAcceptableOrUnknown(
          data['compose_hash']!,
          _composeHashMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('stages_json')) {
      context.handle(
        _stagesJsonMeta,
        stagesJson.isAcceptableOrUnknown(data['stages_json']!, _stagesJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_stagesJsonMeta);
    }
    if (data.containsKey('tcb_status')) {
      context.handle(
        _tcbStatusMeta,
        tcbStatus.isAcceptableOrUnknown(data['tcb_status']!, _tcbStatusMeta),
      );
    }
    if (data.containsKey('reason_code')) {
      context.handle(
        _reasonCodeMeta,
        reasonCode.isAcceptableOrUnknown(data['reason_code']!, _reasonCodeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AttestationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AttestationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      logId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}log_id'],
      )!,
      at: $AttestationLogTable.$converterat.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}at'],
        )!,
      ),
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      ),
      stepId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}step_id'],
      ),
      receiptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_id'],
      ),
      workloadKeysetDigest: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workload_keyset_digest'],
      ),
      workloadId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workload_id'],
      ),
      repoCommit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}repo_commit'],
      ),
      composeHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}compose_hash'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      stagesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stages_json'],
      )!,
      tcbStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tcb_status'],
      ),
      reasonCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason_code'],
      ),
    );
  }

  @override
  $AttestationLogTable createAlias(String alias) {
    return $AttestationLogTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterat = epochMicros;
}

class AttestationRow extends DataClass implements Insertable<AttestationRow> {
  final int id;

  /// Id the agent event `AttestationStatusChanged.logId` refers to.
  final String logId;
  final DateTime at;
  final String profileId;
  final String? model;

  /// `session`, `receipt` or `gpu`.
  final String kind;
  final String? sessionId;
  final String? stepId;
  final String? receiptId;
  final String? workloadKeysetDigest;
  final String? workloadId;
  final String? repoCommit;

  /// Compose hash or image digest.
  final String? composeHash;

  /// `AttestationStatus.name`.
  final String status;

  /// JSON list of `{stage, result, detail?, code?}`.
  final String stagesJson;
  final String? tcbStatus;
  final String? reasonCode;
  const AttestationRow({
    required this.id,
    required this.logId,
    required this.at,
    required this.profileId,
    this.model,
    required this.kind,
    this.sessionId,
    this.stepId,
    this.receiptId,
    this.workloadKeysetDigest,
    this.workloadId,
    this.repoCommit,
    this.composeHash,
    required this.status,
    required this.stagesJson,
    this.tcbStatus,
    this.reasonCode,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['log_id'] = Variable<String>(logId);
    {
      map['at'] = Variable<int>($AttestationLogTable.$converterat.toSql(at));
    }
    map['profile_id'] = Variable<String>(profileId);
    if (!nullToAbsent || model != null) {
      map['model'] = Variable<String>(model);
    }
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<String>(sessionId);
    }
    if (!nullToAbsent || stepId != null) {
      map['step_id'] = Variable<String>(stepId);
    }
    if (!nullToAbsent || receiptId != null) {
      map['receipt_id'] = Variable<String>(receiptId);
    }
    if (!nullToAbsent || workloadKeysetDigest != null) {
      map['workload_keyset_digest'] = Variable<String>(workloadKeysetDigest);
    }
    if (!nullToAbsent || workloadId != null) {
      map['workload_id'] = Variable<String>(workloadId);
    }
    if (!nullToAbsent || repoCommit != null) {
      map['repo_commit'] = Variable<String>(repoCommit);
    }
    if (!nullToAbsent || composeHash != null) {
      map['compose_hash'] = Variable<String>(composeHash);
    }
    map['status'] = Variable<String>(status);
    map['stages_json'] = Variable<String>(stagesJson);
    if (!nullToAbsent || tcbStatus != null) {
      map['tcb_status'] = Variable<String>(tcbStatus);
    }
    if (!nullToAbsent || reasonCode != null) {
      map['reason_code'] = Variable<String>(reasonCode);
    }
    return map;
  }

  AttestationLogCompanion toCompanion(bool nullToAbsent) {
    return AttestationLogCompanion(
      id: Value(id),
      logId: Value(logId),
      at: Value(at),
      profileId: Value(profileId),
      model: model == null && nullToAbsent
          ? const Value.absent()
          : Value(model),
      kind: Value(kind),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      stepId: stepId == null && nullToAbsent
          ? const Value.absent()
          : Value(stepId),
      receiptId: receiptId == null && nullToAbsent
          ? const Value.absent()
          : Value(receiptId),
      workloadKeysetDigest: workloadKeysetDigest == null && nullToAbsent
          ? const Value.absent()
          : Value(workloadKeysetDigest),
      workloadId: workloadId == null && nullToAbsent
          ? const Value.absent()
          : Value(workloadId),
      repoCommit: repoCommit == null && nullToAbsent
          ? const Value.absent()
          : Value(repoCommit),
      composeHash: composeHash == null && nullToAbsent
          ? const Value.absent()
          : Value(composeHash),
      status: Value(status),
      stagesJson: Value(stagesJson),
      tcbStatus: tcbStatus == null && nullToAbsent
          ? const Value.absent()
          : Value(tcbStatus),
      reasonCode: reasonCode == null && nullToAbsent
          ? const Value.absent()
          : Value(reasonCode),
    );
  }

  factory AttestationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AttestationRow(
      id: serializer.fromJson<int>(json['id']),
      logId: serializer.fromJson<String>(json['logId']),
      at: serializer.fromJson<DateTime>(json['at']),
      profileId: serializer.fromJson<String>(json['profileId']),
      model: serializer.fromJson<String?>(json['model']),
      kind: serializer.fromJson<String>(json['kind']),
      sessionId: serializer.fromJson<String?>(json['sessionId']),
      stepId: serializer.fromJson<String?>(json['stepId']),
      receiptId: serializer.fromJson<String?>(json['receiptId']),
      workloadKeysetDigest: serializer.fromJson<String?>(
        json['workloadKeysetDigest'],
      ),
      workloadId: serializer.fromJson<String?>(json['workloadId']),
      repoCommit: serializer.fromJson<String?>(json['repoCommit']),
      composeHash: serializer.fromJson<String?>(json['composeHash']),
      status: serializer.fromJson<String>(json['status']),
      stagesJson: serializer.fromJson<String>(json['stagesJson']),
      tcbStatus: serializer.fromJson<String?>(json['tcbStatus']),
      reasonCode: serializer.fromJson<String?>(json['reasonCode']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'logId': serializer.toJson<String>(logId),
      'at': serializer.toJson<DateTime>(at),
      'profileId': serializer.toJson<String>(profileId),
      'model': serializer.toJson<String?>(model),
      'kind': serializer.toJson<String>(kind),
      'sessionId': serializer.toJson<String?>(sessionId),
      'stepId': serializer.toJson<String?>(stepId),
      'receiptId': serializer.toJson<String?>(receiptId),
      'workloadKeysetDigest': serializer.toJson<String?>(workloadKeysetDigest),
      'workloadId': serializer.toJson<String?>(workloadId),
      'repoCommit': serializer.toJson<String?>(repoCommit),
      'composeHash': serializer.toJson<String?>(composeHash),
      'status': serializer.toJson<String>(status),
      'stagesJson': serializer.toJson<String>(stagesJson),
      'tcbStatus': serializer.toJson<String?>(tcbStatus),
      'reasonCode': serializer.toJson<String?>(reasonCode),
    };
  }

  AttestationRow copyWith({
    int? id,
    String? logId,
    DateTime? at,
    String? profileId,
    Value<String?> model = const Value.absent(),
    String? kind,
    Value<String?> sessionId = const Value.absent(),
    Value<String?> stepId = const Value.absent(),
    Value<String?> receiptId = const Value.absent(),
    Value<String?> workloadKeysetDigest = const Value.absent(),
    Value<String?> workloadId = const Value.absent(),
    Value<String?> repoCommit = const Value.absent(),
    Value<String?> composeHash = const Value.absent(),
    String? status,
    String? stagesJson,
    Value<String?> tcbStatus = const Value.absent(),
    Value<String?> reasonCode = const Value.absent(),
  }) => AttestationRow(
    id: id ?? this.id,
    logId: logId ?? this.logId,
    at: at ?? this.at,
    profileId: profileId ?? this.profileId,
    model: model.present ? model.value : this.model,
    kind: kind ?? this.kind,
    sessionId: sessionId.present ? sessionId.value : this.sessionId,
    stepId: stepId.present ? stepId.value : this.stepId,
    receiptId: receiptId.present ? receiptId.value : this.receiptId,
    workloadKeysetDigest: workloadKeysetDigest.present
        ? workloadKeysetDigest.value
        : this.workloadKeysetDigest,
    workloadId: workloadId.present ? workloadId.value : this.workloadId,
    repoCommit: repoCommit.present ? repoCommit.value : this.repoCommit,
    composeHash: composeHash.present ? composeHash.value : this.composeHash,
    status: status ?? this.status,
    stagesJson: stagesJson ?? this.stagesJson,
    tcbStatus: tcbStatus.present ? tcbStatus.value : this.tcbStatus,
    reasonCode: reasonCode.present ? reasonCode.value : this.reasonCode,
  );
  AttestationRow copyWithCompanion(AttestationLogCompanion data) {
    return AttestationRow(
      id: data.id.present ? data.id.value : this.id,
      logId: data.logId.present ? data.logId.value : this.logId,
      at: data.at.present ? data.at.value : this.at,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      model: data.model.present ? data.model.value : this.model,
      kind: data.kind.present ? data.kind.value : this.kind,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      stepId: data.stepId.present ? data.stepId.value : this.stepId,
      receiptId: data.receiptId.present ? data.receiptId.value : this.receiptId,
      workloadKeysetDigest: data.workloadKeysetDigest.present
          ? data.workloadKeysetDigest.value
          : this.workloadKeysetDigest,
      workloadId: data.workloadId.present
          ? data.workloadId.value
          : this.workloadId,
      repoCommit: data.repoCommit.present
          ? data.repoCommit.value
          : this.repoCommit,
      composeHash: data.composeHash.present
          ? data.composeHash.value
          : this.composeHash,
      status: data.status.present ? data.status.value : this.status,
      stagesJson: data.stagesJson.present
          ? data.stagesJson.value
          : this.stagesJson,
      tcbStatus: data.tcbStatus.present ? data.tcbStatus.value : this.tcbStatus,
      reasonCode: data.reasonCode.present
          ? data.reasonCode.value
          : this.reasonCode,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AttestationRow(')
          ..write('id: $id, ')
          ..write('logId: $logId, ')
          ..write('at: $at, ')
          ..write('profileId: $profileId, ')
          ..write('model: $model, ')
          ..write('kind: $kind, ')
          ..write('sessionId: $sessionId, ')
          ..write('stepId: $stepId, ')
          ..write('receiptId: $receiptId, ')
          ..write('workloadKeysetDigest: $workloadKeysetDigest, ')
          ..write('workloadId: $workloadId, ')
          ..write('repoCommit: $repoCommit, ')
          ..write('composeHash: $composeHash, ')
          ..write('status: $status, ')
          ..write('stagesJson: $stagesJson, ')
          ..write('tcbStatus: $tcbStatus, ')
          ..write('reasonCode: $reasonCode')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    logId,
    at,
    profileId,
    model,
    kind,
    sessionId,
    stepId,
    receiptId,
    workloadKeysetDigest,
    workloadId,
    repoCommit,
    composeHash,
    status,
    stagesJson,
    tcbStatus,
    reasonCode,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AttestationRow &&
          other.id == this.id &&
          other.logId == this.logId &&
          other.at == this.at &&
          other.profileId == this.profileId &&
          other.model == this.model &&
          other.kind == this.kind &&
          other.sessionId == this.sessionId &&
          other.stepId == this.stepId &&
          other.receiptId == this.receiptId &&
          other.workloadKeysetDigest == this.workloadKeysetDigest &&
          other.workloadId == this.workloadId &&
          other.repoCommit == this.repoCommit &&
          other.composeHash == this.composeHash &&
          other.status == this.status &&
          other.stagesJson == this.stagesJson &&
          other.tcbStatus == this.tcbStatus &&
          other.reasonCode == this.reasonCode);
}

class AttestationLogCompanion extends UpdateCompanion<AttestationRow> {
  final Value<int> id;
  final Value<String> logId;
  final Value<DateTime> at;
  final Value<String> profileId;
  final Value<String?> model;
  final Value<String> kind;
  final Value<String?> sessionId;
  final Value<String?> stepId;
  final Value<String?> receiptId;
  final Value<String?> workloadKeysetDigest;
  final Value<String?> workloadId;
  final Value<String?> repoCommit;
  final Value<String?> composeHash;
  final Value<String> status;
  final Value<String> stagesJson;
  final Value<String?> tcbStatus;
  final Value<String?> reasonCode;
  const AttestationLogCompanion({
    this.id = const Value.absent(),
    this.logId = const Value.absent(),
    this.at = const Value.absent(),
    this.profileId = const Value.absent(),
    this.model = const Value.absent(),
    this.kind = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.stepId = const Value.absent(),
    this.receiptId = const Value.absent(),
    this.workloadKeysetDigest = const Value.absent(),
    this.workloadId = const Value.absent(),
    this.repoCommit = const Value.absent(),
    this.composeHash = const Value.absent(),
    this.status = const Value.absent(),
    this.stagesJson = const Value.absent(),
    this.tcbStatus = const Value.absent(),
    this.reasonCode = const Value.absent(),
  });
  AttestationLogCompanion.insert({
    this.id = const Value.absent(),
    required String logId,
    required DateTime at,
    required String profileId,
    this.model = const Value.absent(),
    required String kind,
    this.sessionId = const Value.absent(),
    this.stepId = const Value.absent(),
    this.receiptId = const Value.absent(),
    this.workloadKeysetDigest = const Value.absent(),
    this.workloadId = const Value.absent(),
    this.repoCommit = const Value.absent(),
    this.composeHash = const Value.absent(),
    required String status,
    required String stagesJson,
    this.tcbStatus = const Value.absent(),
    this.reasonCode = const Value.absent(),
  }) : logId = Value(logId),
       at = Value(at),
       profileId = Value(profileId),
       kind = Value(kind),
       status = Value(status),
       stagesJson = Value(stagesJson);
  static Insertable<AttestationRow> custom({
    Expression<int>? id,
    Expression<String>? logId,
    Expression<int>? at,
    Expression<String>? profileId,
    Expression<String>? model,
    Expression<String>? kind,
    Expression<String>? sessionId,
    Expression<String>? stepId,
    Expression<String>? receiptId,
    Expression<String>? workloadKeysetDigest,
    Expression<String>? workloadId,
    Expression<String>? repoCommit,
    Expression<String>? composeHash,
    Expression<String>? status,
    Expression<String>? stagesJson,
    Expression<String>? tcbStatus,
    Expression<String>? reasonCode,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (logId != null) 'log_id': logId,
      if (at != null) 'at': at,
      if (profileId != null) 'profile_id': profileId,
      if (model != null) 'model': model,
      if (kind != null) 'kind': kind,
      if (sessionId != null) 'session_id': sessionId,
      if (stepId != null) 'step_id': stepId,
      if (receiptId != null) 'receipt_id': receiptId,
      if (workloadKeysetDigest != null)
        'workload_keyset_digest': workloadKeysetDigest,
      if (workloadId != null) 'workload_id': workloadId,
      if (repoCommit != null) 'repo_commit': repoCommit,
      if (composeHash != null) 'compose_hash': composeHash,
      if (status != null) 'status': status,
      if (stagesJson != null) 'stages_json': stagesJson,
      if (tcbStatus != null) 'tcb_status': tcbStatus,
      if (reasonCode != null) 'reason_code': reasonCode,
    });
  }

  AttestationLogCompanion copyWith({
    Value<int>? id,
    Value<String>? logId,
    Value<DateTime>? at,
    Value<String>? profileId,
    Value<String?>? model,
    Value<String>? kind,
    Value<String?>? sessionId,
    Value<String?>? stepId,
    Value<String?>? receiptId,
    Value<String?>? workloadKeysetDigest,
    Value<String?>? workloadId,
    Value<String?>? repoCommit,
    Value<String?>? composeHash,
    Value<String>? status,
    Value<String>? stagesJson,
    Value<String?>? tcbStatus,
    Value<String?>? reasonCode,
  }) {
    return AttestationLogCompanion(
      id: id ?? this.id,
      logId: logId ?? this.logId,
      at: at ?? this.at,
      profileId: profileId ?? this.profileId,
      model: model ?? this.model,
      kind: kind ?? this.kind,
      sessionId: sessionId ?? this.sessionId,
      stepId: stepId ?? this.stepId,
      receiptId: receiptId ?? this.receiptId,
      workloadKeysetDigest: workloadKeysetDigest ?? this.workloadKeysetDigest,
      workloadId: workloadId ?? this.workloadId,
      repoCommit: repoCommit ?? this.repoCommit,
      composeHash: composeHash ?? this.composeHash,
      status: status ?? this.status,
      stagesJson: stagesJson ?? this.stagesJson,
      tcbStatus: tcbStatus ?? this.tcbStatus,
      reasonCode: reasonCode ?? this.reasonCode,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (logId.present) {
      map['log_id'] = Variable<String>(logId.value);
    }
    if (at.present) {
      map['at'] = Variable<int>(
        $AttestationLogTable.$converterat.toSql(at.value),
      );
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (stepId.present) {
      map['step_id'] = Variable<String>(stepId.value);
    }
    if (receiptId.present) {
      map['receipt_id'] = Variable<String>(receiptId.value);
    }
    if (workloadKeysetDigest.present) {
      map['workload_keyset_digest'] = Variable<String>(
        workloadKeysetDigest.value,
      );
    }
    if (workloadId.present) {
      map['workload_id'] = Variable<String>(workloadId.value);
    }
    if (repoCommit.present) {
      map['repo_commit'] = Variable<String>(repoCommit.value);
    }
    if (composeHash.present) {
      map['compose_hash'] = Variable<String>(composeHash.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (stagesJson.present) {
      map['stages_json'] = Variable<String>(stagesJson.value);
    }
    if (tcbStatus.present) {
      map['tcb_status'] = Variable<String>(tcbStatus.value);
    }
    if (reasonCode.present) {
      map['reason_code'] = Variable<String>(reasonCode.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AttestationLogCompanion(')
          ..write('id: $id, ')
          ..write('logId: $logId, ')
          ..write('at: $at, ')
          ..write('profileId: $profileId, ')
          ..write('model: $model, ')
          ..write('kind: $kind, ')
          ..write('sessionId: $sessionId, ')
          ..write('stepId: $stepId, ')
          ..write('receiptId: $receiptId, ')
          ..write('workloadKeysetDigest: $workloadKeysetDigest, ')
          ..write('workloadId: $workloadId, ')
          ..write('repoCommit: $repoCommit, ')
          ..write('composeHash: $composeHash, ')
          ..write('status: $status, ')
          ..write('stagesJson: $stagesJson, ')
          ..write('tcbStatus: $tcbStatus, ')
          ..write('reasonCode: $reasonCode')
          ..write(')'))
        .toString();
  }
}

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

abstract class _$WendelinDatabase extends GeneratedDatabase {
  _$WendelinDatabase(QueryExecutor e) : super(e);
  late final NoteFts noteFts = NoteFts(this);
  late final $SessionsTable sessions = $SessionsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $MemoryEntriesTable memoryEntries = $MemoryEntriesTable(this);
  late final $AuditLogTable auditLog = $AuditLogTable(this);
  late final $ProviderProfilesTable providerProfiles = $ProviderProfilesTable(
    this,
  );
  late final $UsageRecordsTable usageRecords = $UsageRecordsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $NoteFilesTable noteFiles = $NoteFilesTable(this);
  late final $AttestationLogTable attestationLog = $AttestationLogTable(this);
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
  late final Index attestationLogAt = Index(
    'attestation_log_at',
    'CREATE INDEX attestation_log_at ON attestation_log (at)',
  );
  late final Index attestationLogSession = Index(
    'attestation_log_session',
    'CREATE INDEX attestation_log_session ON attestation_log (session_id)',
  );
  late final MemoryFts memoryFts = MemoryFts(this);
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
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    noteFts,
    sessions,
    messages,
    memoryEntries,
    auditLog,
    providerProfiles,
    usageRecords,
    settings,
    noteFiles,
    attestationLog,
    sessionsLastActivity,
    messagesSessionSeq,
    auditLogAt,
    usageRecordsProfileAt,
    usageRecordsAt,
    attestationLogAt,
    attestationLogSession,
    memoryFts,
    memoryEntriesAi,
    memoryEntriesAd,
    memoryEntriesAu,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('messages', kind: UpdateKind.delete)],
    ),
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
  ]);
}
