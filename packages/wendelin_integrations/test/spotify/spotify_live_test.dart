@Tags(['live'])
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

// Live-Test gegen die echte Spotify Web API, nur mit einem vorhandenen
// Refresh-Token des Entwicklers (Login im Browser lässt sich nicht
// automatisieren):
//   set -a; . ~/.wendelin-live.env; set +a; dart test -t live --run-skipped \
//     test/spotify/spotify_live_test.dart
// Nötig: SPOTIFY_CLIENT_ID und SPOTIFY_REFRESH_TOKEN. Nichts davon wird
// ausgegeben. Der Test ist rein lesend: Token erneuern, suchen, Geräte und
// Wiedergabezustand lesen. Er startet keine Musik.

void main() {
  final clientId = Platform.environment['SPOTIFY_CLIENT_ID'] ?? '';
  final refresh = Platform.environment['SPOTIFY_REFRESH_TOKEN'] ?? '';
  final skip = clientId.isEmpty || refresh.isEmpty
      ? 'SPOTIFY_CLIENT_ID/SPOTIFY_REFRESH_TOKEN nicht gesetzt'
      : null;

  test('Token erneuern, suchen, Geräte und Zustand lesen', () async {
    final api = HttpSpotifyApi();
    final auth = await api.refresh(
      clientId,
      SpotifyAuth(
        accessToken: '',
        refreshToken: refresh,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ),
    );
    final hits = await api.search(auth, 'Queen', {SpotifyKind.artist});
    expect(hits, isNotEmpty);
    expect(spotifyUriPattern.hasMatch(hits.first.uri), isTrue);
    await api.devices(auth);
    await api.playback(auth);
  }, skip: skip);
}
