import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/preference_models.dart';
import '../../di/preferences.dart';
import '../../platform/assistant_platform.dart';
import '../../voice/recognizer_config.dart';
import '../design/design.dart';
import 'battery_hints.dart';
import 'settings_page.dart';

/// Whether Wendelin is the default assistant right now.
final defaultAssistantProvider = FutureProvider<bool>(
  (ref) => ref.watch(assistantPlatformProvider).isDefaultAssistant(),
);

/// Which speech recognizer Android gives other apps right now (B12).
final recognitionServiceProvider = FutureProvider<RecognitionServiceStatus>(
  (ref) => ref.watch(assistantPlatformProvider).recognitionService(),
);

/// Label of a setting Android does not let Wendelin take on this device.
const notAvailableOnDevice = 'Auf diesem Gerät nicht verfügbar';

/// State line when Android gives other apps' speech input to Wendelin.
const recognizerActiveHint =
    'Android nutzt Wendelin für die Spracheingabe anderer Apps.';

/// Hint when Android keeps another speech recognizer for other apps
/// although Wendelin is assistant and offers itself.
String otherRecognizerHint(String? appName) =>
    'Android nutzt für andere Apps ${appName ?? 'einen anderen Dienst'}. '
    'Das lässt sich auf diesem Gerät nicht umstellen.';

/// Hint when another speech recognizer is set while Wendelin does not
/// (yet) take part: no assistant role, or not offered.
String otherRecognizerForNowHint(String? appName, {required bool isDefault}) =>
    'Android nutzt für andere Apps derzeit '
    '${appName ?? 'einen anderen Dienst'}. '
    '${isDefault ? 'Ob Android nach dem Einschalten zu Wendelin wechselt, '
              'hängt vom Gerät ab.' : 'Das kann sich ändern, sobald Wendelin '
              'Standard-Assistent ist.'}';

/// Hint when Android names Wendelin but its recognizer is off.
String inactiveRecognizerHint({required bool isDefault}) =>
    'Android verweist für andere Apps auf Wendelin, die Spracherkennung ist '
    'aber aus${isDefault ? ' (Schalter aus).' : ': Wendelin ist nicht '
              'Standard-Assistent.'} Andere Apps bekommen dann einen Fehler.';

/// Hint below „Als Spracherkennung anbieten“: Android keeps the system
/// speech recognizer on Wendelin after the assistant is switched, and it
/// then no longer answers (ADR 0006 §2).
const assistantSwitchHint =
    'Wechselst du später zu einem anderen Assistenten (oder „Keiner“), '
    'antwortet die Spracherkennung von Wendelin anderen Apps nicht mehr. '
    'Wähle die Spracheingabe dann in den Android-Einstellungen neu, meist '
    'unter Apps → Standard-Apps → Digitaler Assistent.';

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
      onResume: () => ref
        ..invalidate(defaultAssistantProvider)
        ..invalidate(recognitionServiceProvider),
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

  /// Switches the offer; Android may then name another recognizer.
  Future<void> _setOffered(bool on) async {
    await ref.read(recognizerOfferedProvider.notifier).set(offered: on);
    ref.invalidate(recognitionServiceProvider);
  }

  Future<void> _save() async {
    await ref
        .read(assistantPrefsProvider.notifier)
        .set(AssistantPrefs(userName: _name.text, persona: _persona.text));
    if (mounted) Navigator.of(context).pop();
  }

  Widget _recognizerCard({
    required bool isDefault,
    required RecognitionServiceStatus recognizer,
    required bool offered,
    required bool elsewhere,
  }) => SectionCard(
    children: [
      SettingsRow(
        key: const ValueKey('recognizerRow'),
        title: 'Als Spracherkennung für andere Apps anbieten',
        detail: switch (recognizer.state) {
          RecognitionServiceState.other when elsewhere =>
            '$notAvailableOnDevice. '
                '${otherRecognizerHint(recognizer.appName)}',
          RecognitionServiceState.other => otherRecognizerForNowHint(
            recognizer.appName,
            isDefault: isDefault,
          ),
          RecognitionServiceState.inactive => inactiveRecognizerHint(
            isDefault: isDefault,
          ),
          RecognitionServiceState.active =>
            '$recognizerActiveHint Whisper erkennt auf dem Gerät, '
                'Aufnahmen werden nicht gespeichert.',
          RecognitionServiceState.unknown =>
            'Solange Wendelin Standard-Assistent ist, können '
                'andere Apps die Spracheingabe nutzen. Whisper '
                'erkennt auf dem Gerät, Aufnahmen werden nicht '
                'gespeichert.',
        },
        // The stored choice stays; Android decides here.
        trailing: Opacity(
          opacity: elsewhere ? WOpacity.inactive : 1,
          child: WSwitch(
            value: offered,
            semanticLabel: elsewhere
                ? 'Als Spracherkennung für andere Apps anbieten, '
                      '$notAvailableOnDevice'
                : 'Als Spracherkennung für andere Apps anbieten',
            onChanged: elsewhere ? null : (on) => unawaited(_setOffered(on)),
          ),
        ),
      ),
    ],
  );

  Widget _defaultAssistant({
    required bool isDefault,
    required RecognitionServiceStatus recognizer,
    required bool offered,
    required bool elsewhere,
  }) => SettingsSection(
    title: 'Standard-Assistent',
    children: [
      SectionCard(
        children: [
          SettingsRow(
            title: isDefault
                ? 'Wendelin ist Standard-Assistent'
                : 'Nicht als Standard-Assistent gesetzt',
            detail:
                'Langer Druck auf die Power-Taste oder die '
                'Assistenten-Geste öffnet Wendelin über jeder App.',
            trailing: isDefault
                ? const CheckStatusIcon(
                    CheckStatus.ok,
                    semanticLabel: 'gesetzt',
                  )
                : null,
          ),
        ],
      ),
      if (isDefault)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: () => unawaited(_openSystemSettings()),
            style: TextButton.styleFrom(
              foregroundColor: WColors.link,
              minimumSize: const Size(WSize.touchMin, WSize.touchMin),
            ),
            child: const Text('In Android ändern'),
          ),
        )
      else
        PrimaryButton(
          'Als Standard-Assistent setzen',
          onPressed: () => unawaited(_openSystemSettings()),
        ),
      _recognizerCard(
        isDefault: isDefault,
        recognizer: recognizer,
        offered: offered,
        elsewhere: elsewhere,
      ),
      if (!elsewhere) Text(assistantSwitchHint, style: WText.caption),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final isDefault = ref.watch(defaultAssistantProvider).value == true;
    final recognizer =
        ref.watch(recognitionServiceProvider).value ??
        RecognitionServiceStatus.unknown;
    final offered = ref.watch(recognizerOfferedProvider).value ?? true;
    // Locked only when Wendelin takes part and Android still keeps another
    // service; before (no role, switched off) the value may still change,
    // and a stored „off“ must stay switchable.
    final elsewhere =
        recognizer.state == RecognitionServiceState.other &&
        isDefault &&
        offered;
    return SettingsPage(
      title: 'Assistent',
      children: [
        _defaultAssistant(
          isDefault: isDefault,
          recognizer: recognizer,
          offered: offered,
          elsewhere: elsewhere,
        ),
        // Only with something to say, so the column adds no empty gap.
        if (ref.watch(batteryStatusProvider).value?.hasHints ?? false)
          const BatteryHints(),
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
          key: const ValueKey('persona'),
          controller: _persona,
          style: WText.body,
          // Two lines to start, grows while typing up to five.
          minLines: 2,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            labelText: 'Persönlichkeit, z. B. „antworte knapp und locker“',
          ),
        ),
        PrimaryButton('Speichern', onPressed: () => unawaited(_save())),
      ],
    );
  }
}
