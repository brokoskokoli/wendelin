import 'package:wendelin_core/wendelin_core.dart';

import 'integration_decorator.dart';

export 'integration_decorator.dart' show unwrapIntegration;

/// An [Integration] with the user's „sensibel“ mark instead of its own
/// (concept: integrations „können als sensibel markiert werden“).
final class SensitivityOverride extends IntegrationDecorator {
  /// Wraps [inner] with [sensitive].
  SensitivityOverride(super.inner, {required this.sensitive});

  @override
  final bool sensitive;
}
