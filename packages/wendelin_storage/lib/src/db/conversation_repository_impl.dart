import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../model/conversation.dart';
import '../repositories/repositories.dart';
import 'database.dart';

/// drift implementation of [ConversationRepository].
final class DriftConversationRepository implements ConversationRepository {
  /// Creates the repository.
  DriftConversationRepository(this._db, this._clock, this._ids);

  final WendelinDatabase _db;
  final Clock _clock;
  final IdGenerator _ids;

  @override
  Future<Session> currentOrNew(
    DateTime now, {
    Duration inactivity = ConversationRepository.defaultInactivity,
    SessionOrigin origin = SessionOrigin.app,
  }) => _db.transaction(() async {
    final latest =
        await (_db.select(_db.sessions)
              ..where((s) => s.origin.equals(origin.name))
              ..orderBy([(s) => OrderingTerm.desc(s.lastActivityAt)])
              ..limit(1))
            .getSingleOrNull();
    if (latest != null && now.difference(latest.lastActivityAt) < inactivity) {
      return _session(latest);
    }
    return startNew(now, origin: origin);
  });

  @override
  Future<Session> startNew(
    DateTime now, {
    String? title,
    SessionOrigin origin = SessionOrigin.app,
  }) async {
    final row = SessionRow(
      id: _ids.next(),
      startedAt: now,
      lastActivityAt: now,
      title: title,
      origin: origin.name,
    );
    await _db.into(_db.sessions).insert(row);
    return _session(row);
  }

  @override
  Future<Session?> session(String id) async {
    final row = await (_db.select(
      _db.sessions,
    )..where((s) => s.id.equals(id))).getSingleOrNull();
    return row == null ? null : _session(row);
  }

  @override
  Future<List<Session>> sessions({int? limit, SessionOrigin? origin}) async {
    final q = _db.select(_db.sessions)
      ..where(
        (s) => origin == null
            ? const Constant(true)
            : s.origin.equals(origin.name),
      )
      ..orderBy([
        (s) => OrderingTerm.desc(s.lastActivityAt),
        (s) => OrderingTerm.desc(s.startedAt),
      ]);
    if (limit != null) q.limit(limit);
    return [for (final r in await q.get()) _session(r)];
  }

  @override
  Future<void> setTitle(String id, String? title) =>
      (_db.update(_db.sessions)..where((s) => s.id.equals(id))).write(
        SessionsCompanion(title: Value(title)),
      );

  @override
  Future<StoredMessage> append(
    String sessionId,
    Message message, {
    DateTime? at,
    String? profileId,
    String? modelId,
  }) => _db.transaction(() async {
    final createdAt = at ?? _clock.now();
    final updated =
        await (_db.update(_db.sessions)..where((s) => s.id.equals(sessionId)))
            .write(SessionsCompanion(lastActivityAt: Value(createdAt)));
    if (updated == 0) {
      throw ArgumentError.value(sessionId, 'sessionId', 'unbekannte Sitzung');
    }
    final maxSeq = _db.messages.seq.max();
    final current =
        await (_db.selectOnly(_db.messages)
              ..addColumns([maxSeq])
              ..where(_db.messages.sessionId.equals(sessionId)))
            .map((r) => r.read(maxSeq))
            .getSingle();
    final row = MessageRow(
      id: _ids.next(),
      sessionId: sessionId,
      seq: (current ?? 0) + 1,
      role: message.role.name,
      contentJson: jsonEncode(message.toJson()['content']),
      createdAt: createdAt,
      profileId: profileId,
      modelId: modelId,
      privacyFloor: message.privacyFloor?.name,
    );
    await _db.into(_db.messages).insert(row);
    return _message(row);
  });

  @override
  Future<List<StoredMessage>> messages(String sessionId) async {
    final rows =
        await (_db.select(_db.messages)
              ..where((m) => m.sessionId.equals(sessionId))
              ..orderBy([(m) => OrderingTerm.asc(m.seq)]))
            .get();
    return rows.map(_message).toList();
  }

  @override
  Future<List<StoredMessage>> lastTurns(String sessionId, int turns) async {
    if (turns <= 0) return const [];
    final turnStart =
        await (_db.select(_db.messages)
              ..where(
                (m) =>
                    m.sessionId.equals(sessionId) &
                    m.role.equals(Role.user.name),
              )
              ..orderBy([(m) => OrderingTerm.desc(m.seq)])
              ..limit(1, offset: turns - 1))
            .getSingleOrNull();
    final rows =
        await (_db.select(_db.messages)
              ..where(
                (m) =>
                    m.sessionId.equals(sessionId) &
                    m.seq.isBiggerOrEqualValue(turnStart?.seq ?? 0),
              )
              ..orderBy([(m) => OrderingTerm.asc(m.seq)]))
            .get();
    return rows.map(_message).toList();
  }

  @override
  Future<void> deleteSession(String id) =>
      (_db.delete(_db.sessions)..where((s) => s.id.equals(id))).go();

  @override
  Future<int> purgeOlderThan(Duration maxAge) {
    final cutoff = _clock.now().subtract(maxAge).microsecondsSinceEpoch;
    return (_db.delete(
      _db.sessions,
    )..where((s) => s.lastActivityAt.isSmallerThanValue(cutoff))).go();
  }

  static Session _session(SessionRow r) => Session(
    id: r.id,
    startedAt: r.startedAt,
    lastActivityAt: r.lastActivityAt,
    title: r.title,
    origin: SessionOrigin.values.byName(r.origin),
  );

  static StoredMessage _message(MessageRow r) => StoredMessage(
    id: r.id,
    sessionId: r.sessionId,
    seq: r.seq,
    message: Message.fromJson({
      'role': r.role,
      'content': jsonDecode(r.contentJson),
      'privacyFloor': r.privacyFloor,
    }),
    createdAt: r.createdAt,
    profileId: r.profileId,
    modelId: r.modelId,
  );
}
