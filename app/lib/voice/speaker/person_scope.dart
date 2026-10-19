import 'package:flutter/foundation.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// What a request gets from the person who spoke it (WP92b): address for the
/// prompt, memory namespace and the person's own agent. Everything is the
/// same as before for an unknown speaker and the typed chat
/// ([PersonScope.standard]).
@immutable
final class PersonScope {
  /// Creates the scope of person [personId].
  const PersonScope({
    this.personId,
    this.memoryOwner = '',
    this.address,
    this.agentProfileId,
  });

  /// The default: no person, default memory, global default agent,
  /// `assistant.userName`.
  static const standard = PersonScope();

  /// Id of the person, `null` for [standard]. Only an opaque key.
  final String? personId;

  /// Memory namespace (`''` = default memory).
  final String memoryOwner;

  /// How the assistant addresses the person; `null` = `assistant.userName`.
  final String? address;

  /// Provider profile of the person's agent, `null` = the global default.
  final String? agentProfileId;

  /// Whether this is the default scope.
  bool get isStandard => personId == null;

  @override
  bool operator ==(Object other) =>
      other is PersonScope &&
      other.personId == personId &&
      other.memoryOwner == memoryOwner &&
      other.address == address &&
      other.agentProfileId == agentProfileId;

  @override
  int get hashCode =>
      Object.hash(personId, memoryOwner, address, agentProfileId);

  /// Never contains id, address or namespace (they can reach logs).
  @override
  String toString() => 'PersonScope(${isStandard ? 'standard' : 'person'})';
}

/// Turns the id of a recognized person into its [PersonScope].
final class PersonScopeResolver {
  /// Creates the resolver on the voice profiles and the person settings.
  PersonScopeResolver({required this.profiles, required this.settings});

  /// Enrolled persons (name for the address fallback).
  final SpeakerProfileStore profiles;

  /// Per-person settings.
  final PersonSettingsStore settings;

  /// The scope of [personId]; [PersonScope.standard] for `null`, a person
  /// that no longer exists or any read error (never blocks a request).
  Future<PersonScope> scopeOf(String? personId) async {
    if (personId == null) return PersonScope.standard;
    try {
      final profile = (await profiles.load())
          .where((p) => p.id == personId)
          .firstOrNull;
      if (profile == null) return PersonScope.standard;
      final s =
          (await settings.load())[personId] ??
          PersonSettings(personId: personId);
      final address = s.address?.trim();
      return PersonScope(
        personId: personId,
        memoryOwner: s.memoryOwner,
        address: address == null || address.isEmpty
            ? profile.name.trim()
            : address,
        agentProfileId: s.agentProfileId,
      );
    } on Object {
      return PersonScope.standard;
    }
  }
}
