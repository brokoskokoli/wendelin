import 'package:meta/meta.dart';

/// What a recognized person gets besides the voice (WP92b): how the
/// assistant addresses them, whether they have their own memory, and which
/// provider profile answers them. The key is the id of the person's
/// `SpeakerProfile`. Unknown speakers and the typed chat have no
/// [PersonSettings]: they behave as before (default memory, global default
/// agent, `assistant.userName`).
@immutable
final class PersonSettings {
  /// Creates the settings of person [personId].
  const PersonSettings({
    required this.personId,
    this.address,
    this.sharedMemory = false,
    this.agentProfileId,
  });

  /// Id of the person's `SpeakerProfile`.
  final String personId;

  /// How the assistant addresses the person (replaces `assistant.userName`
  /// in the prompt); `null` or blank = the name the person said when
  /// enrolling.
  final String? address;

  /// `true`: the person uses the default memory („Standard-Gedächtnis“,
  /// today's entries); `false` (default): an own memory namespace.
  final bool sharedMemory;

  /// Provider profile id of the person's agent, `null` = the global default.
  /// Only a target instead of the default: routing rules, privacy floor and
  /// taint still apply.
  final String? agentProfileId;

  /// Memory namespace: `''` = default memory, otherwise one per person.
  String get memoryOwner => sharedMemory ? '' : ownerOf(personId);

  /// The own namespace of [personId].
  static String ownerOf(String personId) => 'p:$personId';

  /// Copy with changes (`address` and `agentProfileId` can be cleared).
  PersonSettings copyWith({
    String? address,
    bool clearAddress = false,
    bool? sharedMemory,
    String? agentProfileId,
    bool clearAgent = false,
  }) => PersonSettings(
    personId: personId,
    address: clearAddress ? null : address ?? this.address,
    sharedMemory: sharedMemory ?? this.sharedMemory,
    agentProfileId: clearAgent ? null : agentProfileId ?? this.agentProfileId,
  );

  /// JSON for the encrypted store.
  Map<String, Object?> toJson() => {
    'personId': personId,
    if (address != null) 'address': address,
    'sharedMemory': sharedMemory,
    if (agentProfileId != null) 'agentProfileId': agentProfileId,
  };

  /// Reads [toJson]; `null` if [json] is malformed.
  static PersonSettings? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['personId'];
    if (id is! String || id.isEmpty) return null;
    final address = json['address'];
    final agent = json['agentProfileId'];
    return PersonSettings(
      personId: id,
      address: address is String ? address : null,
      sharedMemory: json['sharedMemory'] == true,
      agentProfileId: agent is String && agent.isNotEmpty ? agent : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PersonSettings &&
      other.personId == personId &&
      other.address == address &&
      other.sharedMemory == sharedMemory &&
      other.agentProfileId == agentProfileId;

  @override
  int get hashCode =>
      Object.hash(personId, address, sharedMemory, agentProfileId);

  /// Never contains the address or the id (they can reach logs).
  @override
  String toString() => 'PersonSettings(shared=$sharedMemory)';
}

/// Persistent store of [PersonSettings]. The app keeps them encrypted next
/// to the voice profiles (the address is a name).
abstract interface class PersonSettingsStore {
  /// All settings by person id (malformed entries are skipped).
  Future<Map<String, PersonSettings>> load();

  /// Adds or replaces the settings of `settings.personId`.
  Future<void> save(PersonSettings settings);

  /// Removes the settings of [personId] (no error if absent).
  Future<void> delete(String personId);

  /// Removes everything.
  Future<void> clear();
}
