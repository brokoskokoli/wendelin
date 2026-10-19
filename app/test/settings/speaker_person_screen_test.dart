import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/speaker_providers.dart';
import 'package:wendelin/ui/design/design.dart' show WSwitch;
import 'package:wendelin/ui/settings/speaker/speaker_person_screen.dart';
import 'package:wendelin/voice/speaker/person_storage.dart';
import 'package:wendelin/voice/speaker/speaker_storage.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../agent/person_scope_test.dart' show testProfile;
import '../support/test_env.dart';
import '../ui/helpers.dart';
import 'integrations_screen_test.dart' show settle;
import 'speaker_screen_test.dart' show speakerEnv;

Future<ProviderContainer> pump(
  WidgetTester tester,
  TestEnv env, {
  PersonSettings? settings,
}) async {
  await SecretSpeakerProfileStore(env.secrets).save(testProfile('pa', 'Anna'));
  if (settings != null) {
    await SecretPersonSettingsStore(env.secrets).save(settings);
  }
  await env.storage.providerProfiles.save(
    ProviderProfile(
      id: 'claude',
      name: 'Claude API',
      type: ProviderType.anthropic,
      defaultModel: 'm',
      privacy: PrivacyLevel.standard,
      authMethod: ApiKeyAuth('provider.claude.apiKey'),
    ),
  );
  setView(tester, const Size(390, 2000));
  await tester.pumpWidget(
    env.app(home: const SpeakerPersonScreen(personId: 'pa')),
  );
  await settle(tester);
  return ProviderScope.containerOf(
    tester.element(find.byType(SpeakerPersonScreen)),
  );
}

Future<PersonSettings> stored(TestEnv env) async =>
    (await SecretPersonSettingsStore(env.secrets).load())['pa'] ??
    const PersonSettings(personId: 'pa');

void main() {
  testWidgets('neue Person: eigenes Gedächtnis, Standard-Agent, Name als '
      'Anrede-Hinweis', (tester) async {
    final env = speakerEnv();
    await pump(tester, env);
    expect(
      tester
          .widget<WSwitch>(
            find.descendant(
              of: find.byKey(const ValueKey('personMemoryOwn')),
              matching: find.byType(WSwitch),
            ),
          )
          .value,
      isTrue,
    );
    expect(find.text('Standard-Agent'), findsOneWidget);
    expect(find.text('Anna'), findsWidgets);
  });

  testWidgets('Anrede wird verschlüsselt gespeichert, Leer = eingelernter '
      'Name, zu lang wird gekürzt', (tester) async {
    final env = speakerEnv();
    await pump(tester, env);
    await tester.enterText(find.byKey(const ValueKey('personAddress')), 'Anni');
    await settle(tester);
    expect((await stored(env)).address, 'Anni');
    expect(await env.secrets.listKeys(), contains('speaker.persons'));
    await tester.enterText(
      find.byKey(const ValueKey('personAddress')),
      'x' * 60,
    );
    await settle(tester);
    expect((await stored(env)).address, hasLength(maxAddressChars));
    await tester.enterText(find.byKey(const ValueKey('personAddress')), '  ');
    await settle(tester);
    expect((await stored(env)).address, isNull);
  });

  testWidgets('Gedächtnis umschalten: Standard-Gedächtnis statt eigenem', (
    tester,
  ) async {
    final env = speakerEnv();
    await pump(tester, env);
    expect(find.text('Einträge ansehen'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('personMemoryOwn')),
        matching: find.byType(WSwitch),
      ),
    );
    await settle(tester);
    expect((await stored(env)).sharedMemory, isTrue);
    expect((await stored(env)).memoryOwner, '');
    expect(find.text('Einträge ansehen'), findsNothing);
  });

  testWidgets('Agent wählen und zurück zum Standard; globaler Standard '
      'bleibt', (tester) async {
    final env = speakerEnv();
    await env.storage.providerProfiles.save(
      ProviderProfile(
        id: 'main',
        name: 'Haupt',
        type: ProviderType.anthropic,
        defaultModel: 'm',
        privacy: PrivacyLevel.standard,
        authMethod: ApiKeyAuth('provider.main.apiKey'),
      ),
    );
    await env.storage.providerProfiles.setDefault('main');
    await pump(tester, env);
    await tester.tap(find.byKey(const ValueKey('personAgent')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claude API').last);
    await settle(tester);
    expect((await stored(env)).agentProfileId, 'claude');
    expect(find.text('Claude API'), findsOneWidget);
    expect((await env.storage.providerProfiles.defaultProfile())?.id, 'main');
    await tester.tap(find.byKey(const ValueKey('personAgent')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Standard-Agent').last);
    await settle(tester);
    expect((await stored(env)).agentProfileId, isNull);
  });

  testWidgets('Löschen nennt die Zahl der Einträge und lässt das Standard-'
      'Gedächtnis unangetastet', (tester) async {
    final env = speakerEnv();
    for (final (owner, text) in const [
      ('', 'Standard'),
      ('p:pa', 'Anna eins'),
      ('p:pa', 'Anna zwei'),
    ]) {
      await env.storage.memory.save(
        text,
        category: StoredMemoryCategory.fact,
        source: 'user',
        owner: owner,
      );
    }
    final c = await pump(tester, env);
    await tester.tap(find.text('Person löschen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 Einträgen'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Löschen'),
      ),
    );
    await settle(tester);
    expect(await env.storage.memory.count(owner: 'p:pa'), 0);
    expect(await env.storage.memory.count(), 1);
    expect(await c.read(speakerProfilesProvider.future), isEmpty);
    expect(await env.secrets.listKeys(), isEmpty);
  });

  testWidgets('Löschen mit Standard-Gedächtnis: der Dialog zählt trotzdem '
      'die Einträge des eigenen Namespace', (tester) async {
    final env = speakerEnv();
    await env.storage.memory.save(
      'Anna alt',
      category: StoredMemoryCategory.fact,
      source: 'user',
      owner: 'p:pa',
    );
    await pump(
      tester,
      env,
      settings: const PersonSettings(personId: 'pa', sharedMemory: true),
    );
    await tester.tap(find.text('Person löschen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 Einträgen'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Abbrechen'),
      ),
    );
    await settle(tester);
    expect((await SecretSpeakerProfileStore(env.secrets).load()), hasLength(1));
  });
}
