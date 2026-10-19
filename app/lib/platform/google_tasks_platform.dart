import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'channel_authorization_browser.dart';

/// [GoogleBrowserOpener] over the OAuth channel (Custom Tab, else any
/// browser). The redirect does not come back through the channel but to the
/// local server of `GoogleTasksLogin`.
final class ChannelGoogleBrowserOpener implements GoogleBrowserOpener {
  /// Creates the adapter over [browser].
  const ChannelGoogleBrowserOpener([
    this.browser = const ChannelAuthorizationBrowser(),
  ]);

  /// The channel to the platform.
  final ChannelAuthorizationBrowser browser;

  @override
  Future<bool> open(Uri url) => browser.open(url);
}
