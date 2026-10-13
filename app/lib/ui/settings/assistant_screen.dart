import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/preference_models.dart';
import '../../di/preferences.dart';
import '../../platform/assistant_platform.dart';
import '../../voice/recognizer_config.dart';
import '../design/design.dart';
import 'settings_page.dart';

/// Whether Wendelin is the default assistant right now.
final defaultAssistantProvider = FutureProvider<bool>(
  (ref) => ref.watch(assistantPlatformProvider).isDefaultAssistant(),
);

/// Settings → Assistent: Wendelin as default assistant (link to the system
/// settings), the speech recognizer for other apps, the user's name and a
/// personality addition for the system prompt.
class AssistantScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantState();
}

class _AssistantState extends ConsumerState<AssistantScreen> {
  final _name = TextEditingController();
  final _persona = TextEditingController();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(assistantPrefsProvider);
    _name.text = prefs.userName ?? '';
    _persona.text = prefs.persona ?? '';
    // Back from the system settings: check the status again.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(defaultAssistantProvider),
    );
  }

  Future<void> _openSystemSettings() async {
    final opened = await ref
        .read(assistantPlatformProvider)
        .openAssistantSettings();
    if (!opened && mounted) {
      showHint(context, 'Die Systemeinstellungen ließen sich nicht öffnen.');
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _name.dispose();
    _persona.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref
        .read(assistantPrefsProvider.notifier)
        .set(AssistantPrefs(userName: _name.text, persona: _persona.text));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => SettingsPage(
    title: 'Assistent',
    children: [
      SettingsSection(
        title: 'Standard-Assistent',
        children: [
          SectionCard(
            children: [
              SettingsRow(
                title: switch (ref.watch(defaultAssistantProvider).value) {
                  true => 'Wendelin ist Standard-Assistent',
                  _ => 'Nicht als Standard-Assistent gesetzt',
                },
                detail:
                    'Langer Druck auf die Power-Taste oder die '
                    'Assistenten-Geste öffnet Wendelin über jeder App.',
                trailing: ref.watch(defaultAssistantProvider).value == true
                    ? const CheckStatusIcon(
                        CheckStatus.ok,
                        semanticLabel: 'gesetzt',
                      )
                    : null,
              ),
            ],
          ),
          PrimaryButton(
            'Als Standard-Assistent setzen',
            onPressed: () => unawaited(_openSystemSettings()),
          ),
          Text(
            'Android öffnet die Auswahl „Standard-App für digitalen '
            'Assistenten“. Dort Wendelin wählen.',
            style: WText.caption,
          ),
          SectionCard(
            children: [
              SettingsRow(
                title: 'Als Spracherkennung für andere Apps anbieten',
                detail:
                    'Solange Wendelin Standard-Assistent ist, können andere '
                    'Apps die Spracheingabe nutzen. Whisper erkennt auf dem '
                    'Gerät, Aufnahmen werden nicht gespeichert.',
                trailing: WSwitch(
                  value: ref.watch(recognizerOfferedProvider).value ?? true,
                  semanticLabel: 'Als Spracherkennung für andere Apps anbieten',
                  onChanged: (on) => unawaited(
                    ref
                        .read(recognizerOfferedProvider.notifier)
                        .set(offered: on),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      Text(
        'Name und Persönlichkeit gehen als Teil der Anweisungen an das '
        'Modell.',
        style: WText.intro,
      ),
      TextField(
        controller: _name,
        style: WText.body,
        decoration: const InputDecoration(
          labelText: 'Wie soll Wendelin dich nennen?',
        ),
      ),
      TextField(
        controller: _persona,
        style: WText.body,
        maxLines: null,
        decoration: const InputDecoration(
          labelText: 'Persönlichkeit, z. B. „antworte knapp und locker“',
        ),
      ),
      PrimaryButton('Speichern', onPressed: () => unawaited(_save())),
    ],
  );
}
