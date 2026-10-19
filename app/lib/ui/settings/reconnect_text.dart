import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../../l10n/l10n.dart';

/// Brand names are not translated.
String _serviceName(String service) => switch (service) {
  'spotify' => 'Spotify',
  'bring' => 'Bring!',
  'todoist' => 'Todoist',
  'gtasks' => 'Google Tasks',
  'ha' => 'Home Assistant',
  _ => service,
};

/// The user-facing text of a failed „Erneut versuchen“ in the app language.
/// The German `message` of the failure is for the model and logs only.
String reconnectFailureText(AppLocalizations l, ReconnectFailure f) {
  final name = _serviceName(f.service);
  return switch (f.kind) {
    PortErrorKind.permissionDenied => l.reconnectErrDenied(name),
    PortErrorKind.unavailable => l.reconnectErrUnavailable(name),
    _ => l.reconnectErrFailed(name),
  };
}

/// Hint shown after a retry: the failure text or [reachable] on success.
String reconnectHint(
  AppLocalizations l,
  ReconnectFailure? failure,
  String reachable,
) => failure == null ? reachable : reconnectFailureText(l, failure);
