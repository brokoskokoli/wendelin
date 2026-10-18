import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/di/profiles.dart';
import 'package:wendelin/di/tee_restrictions.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/ui/attestation/stage_explanations.dart';
import 'package:wendelin/ui/settings/attestation_explain_screen.dart';
import 'package:wendelin/ui/settings/attestation_log_detail.dart';
import 'package:wendelin/ui/settings/privacy_screen.dart';
import 'package:wendelin/ui/settings/providers_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../support/test_env.dart';
import 'integrations_screen_test.dart' show settle;
import 'other_screens_test.dart' show pumpPage, profile;

AttestationRecord _rec(String id, List<StageRecord> stages, {String? model}) =>
    AttestationRecord(
      model: model,
      logId: id,
      at: testNow,
      profileId: 'phala',
      kind: AttestationRecordKind.session,
      status: AttestationStatus.green,
      stages: stages,
    );

void main() {
  testWidgets('Datenschutz und Logs: Reihenfolge und Zwischenüberschrift', (
    tester,
  ) async {
    await pumpPage(tester, TestEnv(), const PrivacyScreen());
    double y(String t) => tester.getTopLeft(find.text(t).first).dy;
    final order = [
      y('Bildschirminhalt schützen'),
      y('Aufbewahrung'),
      y('Prüfprotokoll'),
      y('Allgemeines Prüfprotokoll'),
      y('TEE-Prüfprotokoll'),
    ];
    expect(order, [...order]..sort());
    expect(order.toSet(), hasLength(5));
  });

  group('Einschränkungen', () {
    test('nur „nur protokolliert“ zählt, GPU-Zeile nicht', () {
      expect(
        restrictionStages([
          (stage: 'provenance', result: 'info', detail: null),
          (stage: 'gpu', result: 'info', detail: null),
          (stage: 'tcb', result: 'warn', detail: null),
          (stage: 'quote', result: 'fail', detail: null),
          (stage: 'nonce', result: 'pass', detail: null),
        ]),
        {'provenance'},
      );
    });

    testWidgets('Akzeptanz gilt nur für das akzeptierte Modell', (
      tester,
    ) async {
      final env = TestEnv();
      await env.storage.attestations.add(
        _rec('m1', const [
          StageRecord('keyset.endorsement', 'info'),
        ], model: 'modell-a'),
      );
      await env.storage.attestations.add(
        _rec('m2', const [
          StageRecord('keyset.endorsement', 'info'),
        ], model: 'modell-b'),
      );
      await acceptRestrictions(env.storage.settings, 'phala', 'modell-a', {
        'keyset.endorsement',
      });
      // The old profile-only value does not count for any model.
      await env.storage.settings.set(SettingKey.json('tee.accepted.phala'), {
        'stages': ['keyset.endorsement'],
      });
      final c = await pumpPage(
        tester,
        env,
        const AttestationLogDetailScreen(logId: 'm1'),
      );
      expect(await c.read(openRestrictionsProvider('m1').future), isEmpty);
      expect(await c.read(openRestrictionsProvider('m2').future), {
        'keyset.endorsement',
      });
    });

    test(
      'Bedeutung von „Anfrage nicht verschlüsselt“ hängt von tls.spki ab',
      () {
        expect(
          stageMeaning(
            AppLocalizationsDe(),
            'e2ee.request',
            'info',
            tlsResult: 'pass',
          ),
          contains('geprüfte Verbindung'),
        );
        expect(
          stageMeaning(
            AppLocalizationsDe(),
            'e2ee.request',
            'info',
            tlsResult: 'info',
          ),
          contains('nicht an den Nachweis gebunden'),
        );
      },
    );

    testWidgets('Details, Akzeptieren, geänderte Einschränkung erneut', (
      tester,
    ) async {
      final env = TestEnv();
      await env.storage.attestations.add(
        _rec('l1', const [
          StageRecord('quote', 'pass'),
          StageRecord(
            'keyset.endorsement',
            'info',
            detail: 'keine Endorsement',
          ),
        ]),
      );
      final c = await pumpPage(
        tester,
        env,
        const AttestationLogDetailScreen(logId: 'l1'),
      );
      // Not accepted yet: the log points it out, the chat shield is grey.
      expect(find.byKey(const ValueKey('openRestrictions')), findsOneWidget);
      expect(await c.read(openRestrictionsProvider('l1').future), {
        'keyset.endorsement',
      });

      await tester.tap(find.text('Details'));
      await settle(tester);
      expect(find.byType(AttestationExplainScreen), findsOneWidget);
      expect(find.textContaining('Geprüft wird:'), findsWidgets);
      expect(find.textContaining('Bedeutung:'), findsWidgets);
      expect(find.textContaining('kein Fehler'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('acceptRestrictions')));
      await settle(tester);
      expect(find.byKey(const ValueKey('restrictionNotice')), findsNothing);
      expect(await c.read(openRestrictionsProvider('l1').future), isEmpty);

      // A new restriction (provenance is only logged now) is open again.
      await env.storage.attestations.add(
        _rec('l2', const [
          StageRecord('keyset.endorsement', 'info'),
          StageRecord('provenance', 'info'),
        ]),
      );
      expect(await c.read(openRestrictionsProvider('l2').future), {
        'provenance',
      });
      // Failures and warnings are never covered by an acceptance.
      await env.storage.attestations.add(
        _rec('l3', const [
          StageRecord('tcb', 'warn'),
          StageRecord('quote', 'fail'),
        ]),
      );
      expect(await c.read(openRestrictionsProvider('l3').future), isEmpty);
    });
  });

  testWidgets('manueller Modellwechsel beginnt ein neues Gespräch', (
    tester,
  ) async {
    final env = TestEnv(storedProfiles: true);
    for (final id in ['a', 'b']) {
      await env.storage.providerProfiles.save(profile(id));
    }
    await env.storage.providerProfiles.setDefault('a');
    final c = await pumpPage(tester, env, const ProvidersScreen());
    c.read(agentControllerProvider.notifier).addNotice('Hinweis');
    expect(
      c.read(agentControllerProvider).entries.any((e) => e is NoticeEntry),
      isTrue,
    );

    // Declined: nothing changes.
    await tester.tap(find.text('Als Standard'));
    await settle(tester);
    expect(find.text('Neues Gespräch beginnen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await settle(tester);
    expect((await c.read(profilesProvider.future)).defaultId, 'a');
    expect(
      c.read(agentControllerProvider).entries.any((e) => e is NoticeEntry),
      isTrue,
    );

    await tester.tap(find.text('Als Standard'));
    await settle(tester);
    await tester.tap(find.text('Wechseln'));
    await settle(tester);
    expect((await c.read(profilesProvider.future)).defaultId, 'b');
    expect(
      c.read(agentControllerProvider).entries.whereType<NoticeEntry>(),
      isEmpty,
    );
  });

  testWidgets('laufende Antwort: Wechsel bricht ab und beginnt neu', (
    tester,
  ) async {
    final env = TestEnv(storedProfiles: true);
    for (final id in ['a', 'b']) {
      await env.storage.providerProfiles.save(profile(id));
    }
    await env.storage.providerProfiles.setDefault('a');
    final c = await pumpPage(tester, env, const ProvidersScreen());
    final agent = c.read(agentControllerProvider.notifier)
      ..addNotice('Hinweis');
    agent.seed(c.read(agentControllerProvider).copyWith(running: true));

    await tester.tap(find.text('Als Standard'));
    await settle(tester);
    expect(find.textContaining('laufende'), findsOneWidget);
    await tester.tap(find.text('Wechseln'));
    await settle(tester);
    // Not switched while the answer still runs, history untouched.
    expect((await c.read(profilesProvider.future)).defaultId, 'a');
    // The run ends: now the new conversation begins and the model switches.
    agent.seed(c.read(agentControllerProvider).copyWith(running: false));
    await settle(tester);
    expect((await c.read(profilesProvider.future)).defaultId, 'b');
    expect(
      c.read(agentControllerProvider).entries.whereType<NoticeEntry>(),
      isEmpty,
    );
  });

  testWidgets('leerer Verlauf: Wechsel ohne Rückfrage', (tester) async {
    final env = TestEnv(storedProfiles: true);
    for (final id in ['a', 'b']) {
      await env.storage.providerProfiles.save(profile(id));
    }
    await env.storage.providerProfiles.setDefault('a');
    final c = await pumpPage(tester, env, const ProvidersScreen());
    await tester.tap(find.text('Als Standard'));
    await settle(tester);
    expect(find.text('Neues Gespräch beginnen?'), findsNothing);
    expect((await c.read(profilesProvider.future)).defaultId, 'b');
  });

  testWidgets('Golden Details-Seite', tags: ['golden'], (tester) async {
    await pumpPage(
      tester,
      TestEnv(),
      const AttestationExplainScreen(
        profileId: 'phala',
        stages: [
          (stage: 'quote', result: 'pass', detail: null),
          (
            stage: 'keyset.endorsement',
            result: 'info',
            detail: 'keine Endorsement',
          ),
          (
            stage: 'provenance',
            result: 'info',
            detail: 'keine Liste hinterlegt',
          ),
          (stage: 'tcb', result: 'warn', detail: 'Update ausstehend'),
        ],
      ),
    );
    await expectLater(
      find.byType(AttestationExplainScreen),
      matchesGoldenFile('goldens/attestation_explain.png'),
    );
  });
}
