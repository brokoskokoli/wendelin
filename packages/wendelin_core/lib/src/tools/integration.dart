import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'tool.dart';

/// A bundle of tools (e.g. calendar, Spotify) the user can enable.
///
/// Contains no Flutter types: the app maps [id] / [iconId] to icons and
/// settings pages (see ADR 0002).
abstract interface class Integration {
  /// Stable id, also the tool-name prefix (`calendar` → `calendar__…`).
  String get id;

  /// Name for the UI.
  String get displayName;

  /// Icon key the app resolves to an icon.
  String get iconId;

  /// Platforms this integration can run on.
  Set<AppPlatform> get platforms;

  /// Whether the data is personal enough that its tools may only be sent to
  /// providers meeting the configured minimum privacy level.
  bool get sensitive;

  /// Whether the integration can run on this device (app installed, OS
  /// version, …).
  Future<Availability> checkAvailability();

  /// Steps needed before the tools work (permissions, login, …).
  List<SetupStep> get setup;

  /// Which [setup] steps are still missing.
  Future<SetupState> setupState();

  /// Tools offered when the integration is active.
  List<Tool> get tools;
}

/// Result of `Integration.checkAvailability`.
@immutable
final class Availability {
  /// Creates an availability result.
  const Availability({required this.available, this.reason, this.storeUrl});

  /// Available on this device.
  static const yes = Availability(available: true);

  /// Whether the integration can be used.
  final bool available;

  /// Why not (German UI text), if unavailable.
  final String? reason;

  /// Where to install the missing app, if applicable.
  final String? storeUrl;

  @override
  bool operator ==(Object other) =>
      other is Availability &&
      other.available == available &&
      other.reason == reason &&
      other.storeUrl == storeUrl;

  @override
  int get hashCode => Object.hash(available, reason, storeUrl);

  @override
  String toString() => 'Availability($available, $reason)';
}

/// Kind of a [SetupStep].
enum SetupStepKind {
  /// OS permission (calendar, contacts, …).
  permission,

  /// Account login.
  login,

  /// Folder selection (e.g. Obsidian vault).
  folder,

  /// Other configuration.
  config,
}

/// One step needed to set up an integration.
@immutable
final class SetupStep {
  /// Creates a setup step.
  const SetupStep({
    required this.id,
    required this.kind,
    required this.label,
    this.optional = false,
  });

  /// Id, unique within the integration.
  final String id;

  /// What kind of step this is.
  final SetupStepKind kind;

  /// German UI label, e.g. „Kalenderzugriff erlauben“.
  final String label;

  /// Whether the integration works without this step (with fewer tools,
  /// e.g. web without a search service offers only `web__fetch`). An
  /// integration whose missing steps are all optional counts as active.
  final bool optional;

  @override
  bool operator ==(Object other) =>
      other is SetupStep &&
      other.id == id &&
      other.kind == kind &&
      other.label == label &&
      other.optional == optional;

  @override
  int get hashCode => Object.hash(id, kind, label, optional);

  @override
  String toString() =>
      'SetupStep($id, ${kind.name}${optional ? ', optional' : ''})';
}

/// Setup progress of an integration.
@immutable
final class SetupState {
  /// Creates a setup state from the ids of missing [SetupStep]s.
  SetupState({List<String> missingSteps = const []})
    : missingSteps = List.unmodifiable(missingSteps);

  /// Ids of steps that are not done yet.
  final List<String> missingSteps;

  /// Whether all steps are done.
  bool get complete => missingSteps.isEmpty;

  /// Whether every missing step is optional according to [steps] (the
  /// integration's `setup`). Unknown missing ids count as required.
  bool requiredComplete(Iterable<SetupStep> steps) {
    final optional = {
      for (final s in steps)
        if (s.optional) s.id,
    };
    return missingSteps.every(optional.contains);
  }

  @override
  bool operator ==(Object other) =>
      other is SetupState &&
      const ListEquality<String>().equals(other.missingSteps, missingSteps);

  @override
  int get hashCode => const ListEquality<String>().hash(missingSteps);

  @override
  String toString() => 'SetupState(missing: $missingSteps)';
}

/// State of an integration shown in the settings.
enum IntegrationStatus {
  /// App missing or platform unsupported (greyed out).
  unavailable,

  /// Usable but not enabled (switch off).
  available,

  /// Enabled but a setup step is missing (yellow).
  setupRequired,

  /// Tools are sent to the model (green).
  active,

  /// Failure, e.g. expired token; tools paused (red).
  error,
}
