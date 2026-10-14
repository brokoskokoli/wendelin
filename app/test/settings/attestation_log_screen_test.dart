import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/agent_providers.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/attestation_providers.dart';
import 'package:wendelin/di/provider_config.dart';
import 'package:wendelin/ui/design/design.dart' show ToolTlsHint;
import 'package:wendelin/ui/settings/attestation_log_detail.dart';
import 'package:wendelin/ui/settings/attestation_log_screen.dart';
import 'package:wendelin_agent/wendelin_agent.dart' show ProviderTarget;
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart' show GpuCheckMode;
import 'package:wendelin_storage/wendelin_storage.dart';

import '../support/tee_app_support.dart';
import '../support/test_env.dart';
import '../ui/helpers.dart';
import 'integrations_screen_test.dart' show settle;
import 'other_screens_test.dart' show ExportLog, exportingEnv, pumpPage;

AttestationRecord _record(
  String id,
  AttestationStatus status, {
  AttestationRecordKind kind = AttestationRecordKind.receipt,
  String? reason,
  int minute = 0,
  String profileId = 'phala',
  bool e2eeFailed = false,
}) => AttestationRecord(
  logId: id,
  at: testNow.add(Duration(minutes: minute)),
  profileId: profileId,
  model: 'z-ai/glm-5.3-flash',
  kind: kind,
  status: status,
  receiptId: kind == AttestationRecordKind.receipt ? 'rcpt_01J9X4QF' : null,
  workloadKeysetDigest: 'sha256:4d0c…a17f',
  repoCommit: 'abc123',
  reasonCode: reason,
  stages: [
    const StageRecord('quote', 'pass'),
    const StageRecord('nonce', 'pass'),
    const StageRecord('tls.spki', 'pass'),
    StageRecord(
      'e2ee.key',
      e2eeFailed ? 'fail' : 'pass',
      detail: e2eeFailed ? 'Schlüssel fehlt' : null,
    ),
    StageRecord(
      'receipt.upstream.tcb',
      status == AttestationStatus.red ? 'fail' : 'pass',
      detail: status == AttestationStatus.red ? 'TCB veraltet' : null,
      code: reason,
    ),
  ],
);

Future<void> _seed(TestEnv env) async {
  final log = env.storage.attestations;
  await log.add(_record('l1', AttestationStatus.green, minute: 1));
  await log.add(_record('l2', AttestationStatus.yellow, minute: 2));
  await log.add(
    _record(
      'l3',
      AttestationStatus.red,
      minute: 3,
      reason: 'upstream_tcb_out_of_date',
    ),
  );
  await log.add(
    _record(
      'l0',
      AttestationStatus.green,
      kind: AttestationRecordKind.session,
      minute: 0,
    ),
  );
}

void main() {
  testWidgets('Liste: Einträge mit Ergebnis, Filter nach Status', (
    tester,
  ) async {
    final env = TestEnv();
    await _seed(env);
    await pumpPage(tester, env, const AttestationLogScreen());
    expect(find.textContaining('rcpt_01J9X4QF'), findsNWidgets(3));
    expect(find.textContaining('Sitzung · '), findsOneWidget);
    await tester.tap(find.text('Fehlgeschlagen'));
    await tester.pump();
    expect(find.textContaining('rcpt_01J9X4QF'), findsOneWidget);
    expect(find.textContaining('fehlgeschlagen ·'), findsOneWidget);
    await tester.tap(find.text('Wird geprüft'));
    await tester.pump();
    expect(find.textContaining('ausstehend'), findsOneWidget);
    await tester.ensureVisible(find.text('Alle'));
    await tester.tap(find.text('Alle'));
    await tester.pump();
    expect(find.textContaining('rcpt_01J9X4QF'), findsNWidgets(3));
  });

  testWidgets('Sitzungskarte mit Stufen und „Neu attestieren“', (tester) async {
    final env = TestEnv();
    await _seed(env);
    await pumpPage(tester, env, const AttestationLogScreen());
    expect(find.text('phala'), findsOneWidget);
    expect(find.text('Sitzung geprüft'), findsOneWidget);
    expect(find.text('TDX-Quote (DCAP)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Neu attestieren'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Neu attestieren'), findsOneWidget);
  });

  testWidgets('„Neu attestieren“ prüft nur das Profil der eigenen Karte', (
    tester,
  ) async {
    final env = TestEnv();
    await _seed(env);
    await env.storage.attestations.add(
      _record(
        's2',
        AttestationStatus.green,
        kind: AttestationRecordKind.session,
        minute: 5,
        profileId: 'phala2',
      ),
    );
    final first = ScriptedVerifier();
    final second = ScriptedVerifier();
    final container = await pumpPage(tester, env, const AttestationLogScreen());
    final hub = container.read(attestationHubProvider)
      ..register(
        'phala',
        scriptedTee(verifier: first, gateway: ScriptedGateway()),
      )
      ..register(
        'phala2',
        scriptedTee(verifier: second, gateway: ScriptedGateway()),
      );
    expect(hub.isLocked('phala2'), isFalse);
    expect(find.text('Neu attestieren'), findsNWidgets(2));
    final button = find.byKey(const ValueKey('reattest-phala2'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await settle(tester);
    expect(second.attests, 1);
    expect(first.attests, 0, reason: 'nur dieses Profil');
    final other = find.byKey(const ValueKey('reattest-phala'));
    await tester.ensureVisible(other);
    await tester.tap(other);
    await settle(tester);
    expect(first.attests, 1);
    expect(second.attests, 1);
  });

  testWidgets('Tippen öffnet das Detail mit Ergebnis je Stufe und Grund', (
    tester,
  ) async {
    final env = TestEnv();
    await _seed(env);
    await pumpPage(tester, env, const AttestationLogScreen());
    await tester.tap(find.textContaining('fehlgeschlagen ·'));
    await settle(tester);
    expect(
      find.text('Sicherheits-Update beim Betreiber ausstehend'),
      findsOneWidget,
    );
    expect(find.textContaining('TDX-Quote (DCAP) · bestanden'), findsOneWidget);
    expect(
      find.textContaining('Upstream-Sicherheitsstand · fehlgeschlagen'),
      findsOneWidget,
    );
    expect(find.text('TCB veraltet'), findsOneWidget);
    expect(find.text('rcpt_01J9X4QF'), findsOneWidget);
    expect(find.text('sha256:4d0c…a17f'), findsOneWidget);
  });

  testWidgets('Detail: Stufe „E2EE-Schlüssel geprüft“ neben TLS, mit '
      'Erklärtext und Tool-Hinweis', (tester) async {
    final env = TestEnv();
    await _seed(env);
    await pumpPage(tester, env, const AttestationLogDetailScreen(logId: 'l1'));
    await settle(tester);
    expect(
      find.textContaining('TLS-Verbindung geprüft · bestanden'),
      findsOneWidget,
    );
    expect(
      find.textContaining('E2EE-Schlüssel geprüft · bestanden'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Verschlüsselung endet im Gateway des Anbieters'),
      findsOneWidget,
    );
    expect(find.textContaining('nicht im Modell selbst'), findsOneWidget);
    expect(find.text(ToolTlsHint.text), findsOneWidget);
  });

  testWidgets('Detail: fehlgeschlagene Verschlüsselung ist rot benannt', (
    tester,
  ) async {
    final env = TestEnv();
    await env.storage.attestations.add(
      _record('e1', AttestationStatus.red, e2eeFailed: true),
    );
    await pumpPage(tester, env, const AttestationLogDetailScreen(logId: 'e1'));
    await settle(tester);
    expect(
      find.textContaining('E2EE-Schlüssel geprüft · fehlgeschlagen'),
      findsOneWidget,
    );
    expect(find.textContaining('Schlüssel fehlt'), findsOneWidget);
  });

  testWidgets('Profil ohne Tools: kein Tool-Hinweis in Detail und Karte', (
    tester,
  ) async {
    final config = ProviderConfig(
      primary: ProviderTarget(
        profileId: 'phala',
        modelId: 'm',
        provider: FakeLlmProvider(
          const [],
          caps: const ProviderCapabilities(tools: false, streaming: true),
        ),
        privacy: PrivacyLevel.standard,
      ),
    );
    final env = TestEnv(
      extraOverrides: [
        providerConfigProvider.overrideWith((ref) async => config),
      ],
    );
    await _seed(env);
    await pumpPage(tester, env, const AttestationLogDetailScreen(logId: 'l1'));
    await settle(tester);
    expect(find.text(ToolTlsHint.text), findsNothing);
    await pumpPage(tester, env, const AttestationLogScreen());
    expect(find.text(ToolTlsHint.text), findsNothing);
  });

  testWidgets('Sitzungskarte zeigt den Tool-Hinweis immer', (tester) async {
    final env = TestEnv();
    await _seed(env);
    await pumpPage(tester, env, const AttestationLogScreen());
    expect(find.text(ToolTlsHint.text), findsOneWidget);
  });

  testWidgets('Detail: unbekannte Id zeigt einen Hinweis', (tester) async {
    final env = TestEnv();
    await pumpPage(tester, env, const AttestationLogDetailScreen(logId: 'x'));
    expect(find.textContaining('noch keinen Eintrag'), findsOneWidget);
  });

  testWidgets('Export: JSON ohne Inhalte und ohne Keys, Löschen leert', (
    tester,
  ) async {
    final log = ExportLog();
    final env = exportingEnv(log);
    const secret = 'testschluessel-widget-0123456789-GEHEIM';
    await env.secrets.write('provider.phala.apiKey', secret);
    await _seed(env);
    await pumpPage(tester, env, const AttestationLogScreen());
    await tester.scrollUntilVisible(
      find.text('Als JSON exportieren'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Als JSON exportieren'));
    await settle(tester);
    final (name, mime, content) = log.files.single;
    expect(name, 'wendelin-tee-pruefprotokoll.json');
    expect(mime, 'application/json');
    final json = jsonDecode(content) as Map<String, Object?>;
    expect((json['entries']! as List), hasLength(4));
    expect(content, isNot(contains(secret)));
    // Nur Ids, Hashes und Ergebnisse: keine Felder für Prompt oder Antwort.
    for (final entry
        in (json['entries']! as List).cast<Map<String, Object?>>()) {
      expect(
        entry.keys,
        everyElement(
          isIn(const {
            'logId',
            'at',
            'profileId',
            'model',
            'kind',
            'sessionId',
            'stepId',
            'receiptId',
            'workloadKeysetDigest',
            'workloadId',
            'repoCommit',
            'composeHash',
            'status',
            'stages',
            'tcbStatus',
            'reasonCode',
          }),
        ),
      );
    }
    await tester.tap(find.text('Prüfprotokoll löschen'));
    await settle(tester);
    await tester.tap(find.text('Löschen'));
    await settle(tester);
    expect(await env.storage.attestations.latest(), isEmpty);
    expect(find.text('Keine Einträge.'), findsOneWidget);
  });

  group('GPU-Prüfung über NVIDIA', () {
    testWidgets('Standard aus; Erklärung nennt NVIDIA und keine Inhalte', (
      tester,
    ) async {
      final env = TestEnv();
      final c = await pumpPage(tester, env, const AttestationLogScreen());
      expect(c.read(gpuCheckModeProvider), GpuCheckMode.off);
      expect(find.text('GPU-Prüfung über NVIDIA'), findsOneWidget);
      expect(
        find.textContaining('keine Inhalte deiner Anfragen'),
        findsOneWidget,
      );
      expect(find.text('Aus'), findsOneWidget);
      expect(find.text('Vorher'), findsOneWidget);
      expect(find.text('Nachher'), findsOneWidget);
    });

    testWidgets('Wahl wird gespeichert und an die Provider weitergegeben', (
      tester,
    ) async {
      final env = TestEnv();
      final c = await pumpPage(tester, env, const AttestationLogScreen());
      await tester.tap(find.text('Vorher'));
      await settle(tester);
      expect(c.read(gpuCheckModeProvider), GpuCheckMode.before);
      expect(c.read(attestationHubProvider).gpuMode, GpuCheckMode.before);
      expect(await env.storage.settings.get(AppSettings.gpuCheck), 'before');
      expect(env.notifier.permissionRequests, 0);
    });

    testWidgets('„Nachher“ bittet um die Benachrichtigungs-Berechtigung', (
      tester,
    ) async {
      final env = TestEnv();
      env.notifier.granted = false;
      final c = await pumpPage(tester, env, const AttestationLogScreen());
      await tester.tap(find.text('Nachher'));
      await settle(tester);
      expect(env.notifier.permissionRequests, 1);
      expect(c.read(gpuCheckModeProvider), GpuCheckMode.after);
      expect(await env.storage.settings.get(AppSettings.gpuCheck), 'after');
    });
  });

  testWidgets('Golden Prüfprotokoll-Liste und Detail', tags: ['golden'], (
    tester,
  ) async {
    final env = TestEnv();
    await _seed(env);
    setView(tester, const Size(390, 1500));
    await tester.pumpWidget(
      env.app(
        home: const RepaintBoundary(
          key: goldenKey,
          child: AttestationLogScreen(),
        ),
      ),
    );
    await settle(tester);
    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/attestation_log_liste.png'),
    );
    await tester.pumpWidget(
      env.app(
        home: const RepaintBoundary(
          key: goldenKey,
          child: AttestationLogDetailScreen(logId: 'l3'),
        ),
      ),
    );
    await settle(tester);
    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/attestation_log_detail.png'),
    );
    await env.storage.attestations.add(
      _record('e9', AttestationStatus.red, e2eeFailed: true, minute: 9),
    );
    await tester.pumpWidget(
      env.app(
        home: const RepaintBoundary(
          key: goldenKey,
          child: AttestationLogDetailScreen(logId: 'e9'),
        ),
      ),
    );
    await settle(tester);
    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/attestation_log_detail_e2ee_failed.png'),
    );
  });
}
