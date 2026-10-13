import 'package:wendelin_core/wendelin_core.dart';

/// An [Integration] with the user's „sensibel“ mark instead of its own
/// (concept: integrations „können als sensibel markiert werden“).
final class SensitivityOverride implements Integration {
  /// Wraps [inner] with [sensitive].
  SensitivityOverride(this.inner, {required this.sensitive});

  /// The wrapped integration.
  final Integration inner;

  @override
  final bool sensitive;

  @override
  String get id => inner.id;

  @override
  String get displayName => inner.displayName;

  @override
  String get iconId => inner.iconId;

  @override
  Set<AppPlatform> get platforms => inner.platforms;

  @override
  Future<Availability> checkAvailability() => inner.checkAvailability();

  @override
  List<SetupStep> get setup => inner.setup;

  @override
  Future<SetupState> setupState() => inner.setupState();

  @override
  List<Tool> get tools => inner.tools;
}

/// The integration itself, without a [SensitivityOverride].
Integration unwrapIntegration(Integration integration) =>
    integration is SensitivityOverride ? integration.inner : integration;
