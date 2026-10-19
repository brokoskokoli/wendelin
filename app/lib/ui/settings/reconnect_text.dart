import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../../di/integrations/integration_spec.dart'
    show pausedError, reauthError;
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
    PortErrorKind.failed => l.reconnectErrFailed(name),
    _ => l.reconnectErrOther(name),
  };
}

/// Error line of an integration in the app language: the pause marker the
/// specs report becomes a localized text, other messages stay as they are.
String? integrationErrorText(AppLocalizations l, String id, String? error) =>
    switch (error) {
      pausedError => l.integrationsPausedError(_serviceName(id)),
      reauthError => l.bringReauthError,
      _ => error,
    };

/// Hint shown after a retry: the failure text or [reachable] on success.
String reconnectHint(
  AppLocalizations l,
  ReconnectFailure? failure,
  String reachable,
) => failure == null ? reachable : reconnectFailureText(l, failure);

/// [reconnectHint] for Bring!: a failed retry also names the way out
/// (share the items to the Bring! app).
String bringReconnectHint(
  AppLocalizations l,
  ReconnectFailure? failure,
  String reachable,
) => failure == null
    ? reachable
    : '${reconnectFailureText(l, failure)} ${l.reconnectBringShare}';
