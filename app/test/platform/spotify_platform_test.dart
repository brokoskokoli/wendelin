import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform/platform.dart';
import 'package:wendelin/platform/spotify_platform.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

const _intentChannel = MethodChannel(
  'dev.fluttercommunity.plus/android_intent',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  // ignore: deprecated_member_use, AndroidIntent expects the legacy Platform.
  final android = FakePlatform(operatingSystem: 'android');
  final launched = <Map<Object?, Object?>>[];
  Set<String> refuse = {};

  setUp(() {
    launched.clear();
    refuse = {};
    messenger.setMockMethodCallHandler(_intentChannel, (call) async {
      final args = call.arguments as Map<Object?, Object?>;
      if (refuse.contains(args['action'])) {
        throw PlatformException(code: 'ActivityNotFound');
      }
      launched.add(args);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(_intentChannel, null));

  group('IntentSpotifyLauncher', () {
    test('weckt Spotify mit spotify: an das Spotify-Paket', () async {
      expect(await IntentSpotifyLauncher(platform: android).wake(), isTrue);
      expect(launched.single['data'], 'spotify:');
      expect(launched.single['package'], 'com.spotify.music');
    });

    test('Intent abgelehnt: Start über den Launcher-Eintrag', () async {
      refuse = {'action_view'};
      expect(await IntentSpotifyLauncher(platform: android).wake(), isTrue);
      expect(launched.single['action'], 'action_main');
      expect(launched.single['category'], 'category_launcher');
    });

    test('Spotify nicht installiert: false', () async {
      refuse = {'action_view', 'action_main'};
      expect(await IntentSpotifyLauncher(platform: android).wake(), isFalse);
    });

    test('nicht Android: false', () async {
      // ignore: deprecated_member_use, AndroidIntent expects the legacy Platform.
      final ios = FakePlatform(operatingSystem: 'ios');
      expect(await IntentSpotifyLauncher(platform: ios).wake(), isFalse);
    });
  });

  group('ChannelSpotifyAuthBrowser', () {
    const auth = MethodChannel('app.wendelin/auth');
    tearDown(() => messenger.setMockMethodCallHandler(auth, null));

    test('reicht die Rückleitung durch', () async {
      messenger.setMockMethodCallHandler(
        auth,
        (_) async => 'app.wendelin://oauth/spotify?code=c&state=s',
      );
      final back = await const ChannelSpotifyAuthBrowser().authorize(
        Uri.parse('https://accounts.spotify.com/authorize?state=s'),
        spotifyRedirect,
      );
      expect(back.queryParameters['code'], 'c');
    });

    test(
      'Fehler des Browsers werden zu typisierten Fehlern ohne Text',
      () async {
        for (final (code, expected) in [
          ('no_browser', SpotifyBrowserFailure.noBrowser),
          ('cancelled', SpotifyBrowserFailure.cancelled),
          ('state_mismatch', SpotifyBrowserFailure.stateMismatch),
          ('bad_args', SpotifyBrowserFailure.failed),
        ]) {
          messenger.setMockMethodCallHandler(
            auth,
            (_) async => throw PlatformException(code: code),
          );
          await expectLater(
            const ChannelSpotifyAuthBrowser().authorize(
              Uri.parse('https://accounts.spotify.com/authorize?state=s'),
              spotifyRedirect,
            ),
            throwsA(
              isA<SpotifyBrowserException>().having(
                (e) => e.failure,
                'failure',
                expected,
              ),
            ),
            reason: code,
          );
        }
      },
    );
  });
}
