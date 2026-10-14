import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

export 'package:wendelin_integrations/wendelin_integrations.dart'
    show unwrapIntegration;

/// An [Integration] with the user's „sensibel“ mark instead of its own
/// (concept: integrations „können als sensibel markiert werden“).
final class SensitivityOverride extends IntegrationDecorator {
  /// Wraps [inner] with [sensitive].
  SensitivityOverride(super.inner, {required this.sensitive});

  @override
  final bool sensitive;
}
