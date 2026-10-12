import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// Snapshot of a registered integration for the settings UI.
@immutable
final class IntegrationInfo {
  /// Creates a snapshot.
  const IntegrationInfo({
    required this.integration,
    required this.status,
    required this.enabled,
    required this.availability,
    required this.setup,
    this.error,
  });

  /// The integration itself.
  final Integration integration;

  /// Derived state (see [IntegrationInfo.deriveStatus]).
  final IntegrationStatus status;

  /// Whether the user switched it on.
  final bool enabled;

  /// Last availability check (unavailable until the first check finished).
  final Availability availability;

  /// Last setup check.
  final SetupState setup;

  /// Current failure (German text), e.g. „Anmeldung abgelaufen“.
  final String? error;

  /// Integration id.
  String get id => integration.id;

  /// Status from availability, activation, failure and setup, in this
  /// order: unavailable devices win, a switched-off integration is just
  /// `available`, a failure pauses an enabled one, then missing setup.
  static IntegrationStatus deriveStatus({
    required bool available,
    required bool enabled,
    required bool hasError,
    required bool setupComplete,
  }) {
    if (!available) return IntegrationStatus.unavailable;
    if (!enabled) return IntegrationStatus.available;
    if (hasError) return IntegrationStatus.error;
    if (!setupComplete) return IntegrationStatus.setupRequired;
    return IntegrationStatus.active;
  }

  @override
  String toString() => 'IntegrationInfo($id, ${status.name})';
}
