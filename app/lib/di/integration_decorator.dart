import 'package:wendelin_core/wendelin_core.dart';

/// An [Integration] that wraps [inner] and changes one aspect of it (the
/// „sensibel“ mark, an app requirement, …). Everything else is passed on.
abstract base class IntegrationDecorator implements Integration {
  /// Wraps [inner].
  IntegrationDecorator(this.inner);

  /// The wrapped integration.
  final Integration inner;

  @override
  String get id => inner.id;

  @override
  String get displayName => inner.displayName;

  @override
  String get iconId => inner.iconId;

  @override
  Set<AppPlatform> get platforms => inner.platforms;

  @override
  bool get sensitive => inner.sensitive;

  @override
  Future<Availability> checkAvailability() => inner.checkAvailability();

  @override
  List<SetupStep> get setup => inner.setup;

  @override
  Future<SetupState> setupState() => inner.setupState();

  @override
  List<Tool> get tools => inner.tools;
}

/// The integration itself, without any [IntegrationDecorator].
Integration unwrapIntegration(Integration integration) {
  var i = integration;
  while (i is IntegrationDecorator) {
    i = i.inner;
  }
  return i;
}
