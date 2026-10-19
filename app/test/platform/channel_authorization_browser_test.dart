import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/mcp/mcp_providers.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/platform/channel_authorization_browser.dart';
import 'package:wendelin_mcp/testing.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

import '../support/mcp_support.dart';
import '../support/test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(authChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  void mock(Future<Object?> Function(MethodCall call) handler) =>
      messenger.setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        return handler(call);
      });

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('authorize gibt URL und Rückleitung an Kotlin und liefert die '
      'Rückleitung', () async {
    mock((call) async => 'app.wendelin://oauth/mcp?code=c&state=s');
    final back = await const ChannelAuthorizationBrowser().authorize(
      Uri.parse('https://as.example.org/authorize?state=s'),
      mcpRedirectUri,
    );
    expect(back.queryParameters['code'], 'c');
    expect(calls.single.method, 'authorize');
    expect(calls.single.arguments, {
      'url': 'https://as.example.org/authorize?state=s',
      'redirect': 'app.wendelin://oauth/mcp',
      'state': 's',
    });
  });

  test('open schickt nur die https-Adresse und antwortet sofort', () async {
    mock((call) async => true);
    expect(
      await const ChannelAuthorizationBrowser().open(
        Uri.parse('https://accounts.google.com/o/oauth2/v2/auth?state=s'),
      ),
      isTrue,
    );
    expect(calls.single.method, 'open');
    expect(calls.single.arguments, {
      'url': 'https://accounts.google.com/o/oauth2/v2/auth?state=s',
    });
    expect(
      () => const ChannelAuthorizationBrowser().open(
        Uri.parse('http://127.0.0.1:1/x'),
      ),
      throwsArgumentError,
    );
  });

  test('open: kein Browser oder fehlender Kanal ist false', () async {
    mock((call) async => throw PlatformException(code: 'no_browser'));
    final b = const ChannelAuthorizationBrowser();
    expect(await b.open(Uri.parse('https://example.org')), isFalse);
    messenger.setMockMethodCallHandler(channel, null);
    expect(await b.open(Uri.parse('https://example.org')), isFalse);
  });

  test('kein Browser, Abbruch, sonstiger Fehler, fehlender Kanal', () async {
    Future<AuthorizationFailure> failure() async {
      try {
        await const ChannelAuthorizationBrowser().authorize(
          Uri.parse('https://as.example.org/authorize'),
          mcpRedirectUri,
        );
      } on AuthorizationBrowserException catch (e) {
        return e.failure;
      }
      fail('keine Ausnahme');
    }

    for (final (code, expected) in [
      ('no_browser', AuthorizationFailure.noBrowser),
      ('cancelled', AuthorizationFailure.cancelled),
      ('state_mismatch', AuthorizationFailure.stateMismatch),
      ('bad_args', AuthorizationFailure.failed),
    ]) {
      mock((_) async => throw PlatformException(code: code));
      expect(await failure(), expected, reason: code);
    }
    mock((_) async => null);
    expect(await failure(), AuthorizationFailure.failed);
    messenger.setMockMethodCallHandler(channel, null);
    expect(await failure(), AuthorizationFailure.failed);
  });

  test('nur http(s)-Adressen werden geöffnet', () {
    expect(
      () => const ChannelAuthorizationBrowser().authorize(
        Uri.parse('javascript:alert(1)'),
        mcpRedirectUri,
      ),
      throwsArgumentError,
    );
  });

  test('isAvailable fragt Kotlin, Fehler gelten als „kein Browser“', () async {
    mock((_) async => true);
    expect(await const ChannelAuthorizationBrowser().isAvailable(), isTrue);
    mock((_) async => throw PlatformException(code: 'x'));
    expect(await const ChannelAuthorizationBrowser().isAvailable(), isFalse);
    messenger.setMockMethodCallHandler(channel, null);
    expect(await const ChannelAuthorizationBrowser().isAvailable(), isFalse);
  });

  test('OAuth Ende-zu-Ende über den Kanal: Redirect-Activity liefert die '
      'Rückleitung, Token landet im SecretStore', () async {
    allowRealHttp();
    final server = await FakeMcpServer.start(
      tools: homeTools(),
      auth: FakeAuthMode.oauth,
    );
    addTearDown(server.close);
    // Kotlin side: the „browser“ follows the consent, the redirect activity
    // hands the address back.
    final consent = FakeAuthorizationBrowser();
    mock((call) async {
      if (call.method == 'isAvailable') return true;
      final args = call.arguments as Map<Object?, Object?>;
      final back = await consent.authorize(
        Uri.parse(args['url']! as String),
        Uri.parse(args['redirect']! as String),
      );
      return back.toString();
    });
    final env = TestEnv(
      enabled: const {},
      extraOverrides: [
        mcpAuthorizationBrowserProvider.overrideWithValue(
          const ChannelAuthorizationBrowser(),
        ),
        mcpLogProvider.overrideWithValue((_) {}),
      ],
    );
    final c = env.container();
    addTearDown(c.dispose);
    await c.read(toolRegistryReadyProvider.future);
    final source = c.read(mcpServerSourceProvider);
    final view = await source.add(draftFor(server, auth: McpAuthKind.oauth));
    final check = await source.signIn(view.config.id);
    expect(check.status, McpReachability.reachable);
    expect(calls.map((c) => c.method), ['isAvailable', 'authorize']);
    final opened = Uri.parse(
      (calls.last.arguments as Map<Object?, Object?>)['url']! as String,
    );
    expect(opened.queryParameters['redirect_uri'], 'app.wendelin://oauth/mcp');
    expect(opened.queryParameters['code_challenge_method'], 'S256');
    final stored = await env.secrets.read(
      McpSecretRefs.oauthToken(view.config.id),
    );
    final access =
        (jsonDecode(stored!) as Map<String, Object?>)['accessToken']! as String;
    expect(server.accessTokens, contains(access));
  });

  test('kein Browser auf dem Gerät: Hinweis statt Absturz', () async {
    allowRealHttp();
    final server = await FakeMcpServer.start(auth: FakeAuthMode.oauth);
    addTearDown(server.close);
    mock((call) async => call.method == 'isAvailable' ? false : null);
    final env = TestEnv(
      enabled: const {},
      extraOverrides: [
        mcpAuthorizationBrowserProvider.overrideWithValue(
          const ChannelAuthorizationBrowser(),
        ),
        mcpLogProvider.overrideWithValue((_) {}),
      ],
    );
    final c = env.container();
    addTearDown(c.dispose);
    await c.read(toolRegistryReadyProvider.future);
    final source = c.read(mcpServerSourceProvider);
    final view = await source.add(draftFor(server, auth: McpAuthKind.oauth));
    await expectLater(
      source.signIn(view.config.id),
      throwsA(same(McpSignInException.noBrowser)),
    );
    expect(calls.map((c) => c.method), ['isAvailable']);
  });
}
