import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Answers of the Spotify Web API as documented at
/// developer.spotify.com/documentation/web-api (names and ids made up; no
/// real account data). Shape of the fields matches the real responses.
const searchTrackJson = {
  'tracks': {
    'items': [
      {
        'type': 'track',
        'name': 'Bohemian Rhapsody',
        'uri': 'spotify:track:4u7EnebtmKWzUH433cf5Qv',
        'artists': [
          {'name': 'Queen'},
        ],
        'album': {'name': 'A Night at the Opera'},
      },
      {
        'type': 'track',
        'name': 'Somebody to Love',
        'uri': 'spotify:track:7hQJA50XrCWABAu5v6QZ4i',
        'artists': [
          {'name': 'Queen'},
          {'name': 'George Michael'},
        ],
      },
    ],
  },
};

const searchAllJson = {
  ...searchTrackJson,
  'albums': {
    'items': [
      {
        'name': 'A Night at the Opera',
        'uri': 'spotify:album:6X9k3iKZrQK3SDKpOZnB7M',
        'artists': [
          {'name': 'Queen'},
        ],
      },
    ],
  },
  'artists': {
    'items': [
      {'name': 'Queen', 'uri': 'spotify:artist:1dfeR4HaWDbWqFHLkxsg1d'},
    ],
  },
  'playlists': {
    'items': [
      null,
      {
        'name': 'This Is Queen',
        'uri': 'spotify:playlist:37i9dQZF1DXcBWIGoYBM5M',
        'owner': {'display_name': 'Spotify'},
      },
      {'name': 'kaputt', 'uri': 'https://evil.example/x'},
    ],
  },
};

const playbackJson = {
  'is_playing': true,
  'progress_ms': 61000,
  'device': {
    'id': 'dev1',
    'name': 'Pixel 8',
    'is_active': true,
    'is_restricted': false,
    'type': 'Smartphone',
  },
  'context': {'type': 'album', 'uri': 'spotify:album:6X9k3iKZrQK3SDKpOZnB7M'},
  'item': {
    'type': 'track',
    'name': 'Bohemian Rhapsody',
    'uri': 'spotify:track:4u7EnebtmKWzUH433cf5Qv',
    'artists': [
      {'name': 'Queen'},
    ],
    'album': {'name': 'A Night at the Opera'},
  },
};

const devicesJson = {
  'devices': [
    {
      'id': 'dev1',
      'name': 'Pixel 8',
      'is_active': false,
      'is_restricted': false,
    },
    {'id': 'dev2', 'name': 'Echo', 'is_active': false, 'is_restricted': true},
    {'name': 'ohne Id'},
  ],
};

const tokenJson = {
  'access_token': 'BQDnew-access',
  'token_type': 'Bearer',
  'expires_in': 3600,
  'refresh_token': 'AQDnew-refresh',
  'scope': 'user-read-playback-state user-modify-playback-state',
};

Map<String, Object?> errorJson(int status, String message, [String? reason]) =>
    {
      'error': {'status': status, 'message': message, 'reason': ?reason},
    };

/// A request seen by [SpotifyServer].
class Seen {
  Seen(this.request, this.body);
  final http.BaseRequest request;
  final String body;
  String get method => request.method;
  Uri get url => request.url;
  Map<String, String> get headers => request.headers;
  Map<String, String> get form => Uri.splitQueryString(body);
  Object? get json => body.isEmpty ? null : jsonDecode(body);
}

/// A scripted Spotify: [handler] answers every request.
class SpotifyServer {
  SpotifyServer(this.handler);

  final http.Response Function(Seen request) handler;
  final List<Seen> requests = [];

  http.Client get client => MockClient((r) async {
    final seen = Seen(r, r.body);
    requests.add(seen);
    return handler(seen);
  });

  HttpSpotifyApi api({Clock? clock, void Function(String)? log}) =>
      HttpSpotifyApi(
        client: client,
        clock: clock ?? const SystemClock(),
        log: log,
      );
}

http.Response jsonResponse(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
