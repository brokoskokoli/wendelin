import 'package:test/test.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'fixtures.dart';

/// Concept test strategy: „Routing: Tabellentests Satz → erwartete Regel“.
/// Uses the concept example rules and the real keyword matcher.
void main() {
  const strong = 'Starkes Modell';
  const private = 'Privat';
  const offline = 'Offline';
  const notes = 'Notizen umschreiben';
  const fallback = RuleSet.defaultReason;

  const off = NetworkState.offline;
  const metered = NetworkState.metered;

  final cases = <(String, String, NetworkState?)>[
    // de
    ('Claude, wie wird das Wetter?', strong, null),
    ('claude wie wird das wetter', strong, null),
    ('CLAUDE: Fasse das zusammen.', strong, null),
    ('Fable, schreib mir ein Gedicht', strong, null),
    ('„Claude“, was ist heute los?', strong, null),
    ('  …Claude!!! Hilfe', strong, null),
    ('Frag mal Claude, wie spät es ist', fallback, null),
    ('Claudia, wie geht es dir?', fallback, null),
    ('Das ist privat: mein Arzttermin', private, null),
    ('Trag privat ein, dass ich zum Arzt muss', private, null),
    ('PRIVAT! Kontostand notieren', private, null),
    ('Erklär mir die Privatsphäre-Einstellungen', fallback, null),
    ('Wie wird das Wetter?', offline, off),
    ('Claude, hilf mir', strong, off),
    ('Das ist privat', private, off),
    ('Wie wird das Wetter?', fallback, metered),
    ('Schreib meine Notiz zum Projekt um', notes, null),
    ('Ergänze die Notiz Einkauf um Milch', notes, null),
    ('Lies mir die Notiz Einkauf vor', fallback, null),
    ('Denk gründlich nach über den Umzug', fallback, null),
    ('Wie spät ist es?', fallback, null),
    ('', fallback, null),
    // fr
    ('Claude, quelle heure est-il ?', strong, null),
    ('Fable : écris un poème', strong, null),
    ("C'est privé : mon rendez-vous chez le médecin", private, null),
    ('Réécris ma note sur le projet', notes, null),
    ('Demande à Claude la météo', fallback, null),
    ('Quelle heure est-il ?', offline, off),
    ('Quel temps fait-il ?', fallback, null),
    // en
    ("Claude, what's the weather like?", strong, null),
    ('fable... write a haiku', strong, null),
    ('This is private: my bank reminder', private, null),
    ('Confidential: salary talk tomorrow', private, null),
    ('Rewrite my note about the trip', notes, null),
    ('Edit the Obsidian note shopping', notes, null),
    ('Ask Claude about the weather', fallback, null),
    ('What time is it?', offline, off),
    ('Think hard about this', fallback, null),
  ];

  test('at least 30 cases', () => expect(cases.length, greaterThan(30)));

  for (final (text, rule, network) in cases) {
    final net = network ?? NetworkState.online;
    test('„$text“ (${net.name}) → $rule', () {
      final resolver = conceptResolver(network: FixedNetworkStatus(net));
      final r = resolver.resolve(UserInput(text: text));
      expect(r.reason, rule);
      final d = explain(
        conceptRules(),
        ctxFor(text, network: net, matcher: KeywordToolCategoryMatcher()),
      );
      expect(d.reason, rule, reason: 'explain agrees with the resolver');
    });
  }

  test('targets and privacy floor of the concept rules', () {
    final resolver = conceptResolver();
    Resolution go(String t) => resolver.resolve(UserInput(text: t));
    expect(go('Claude, hallo').modelId, 'claude-opus');
    expect(go('Claude, hallo').privacyFloor, isNull);
    final p = go('privat: hallo');
    expect((p.profileId, p.modelId), ('phala', 'glm-small'));
    expect(p.privacyFloor, PrivacyLevel.tee);
    expect(go('Schreib die Notiz um').modelId, 'claude-sonnet');
    expect(go('hallo').modelId, 'glm-small');
  });
}
