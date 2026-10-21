import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/preference_models.dart';
import '../../di/preferences.dart';
import '../../l10n/l10n.dart';
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
      showHint(context, context.l10n.wakeServiceSectionSettingsFail);
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
    required AppLocalizations l,
    required bool isDefault,
    required RecognitionServiceStatus recognizer,
    required bool offered,
    required bool elsewhere,
  }) => SectionCard(
    children: [
      SettingsRow(
        key: const ValueKey('recognizerRow'),
        title: l.assistantOfferRecognizer,
        detail: switch (recognizer.state) {
          RecognitionServiceState.other when elsewhere =>
            '${l.assistantNotAvailable}. '
                '${l.assistantOtherRecognizer(recognizer.appName ?? l.assistantAnotherService)}',
          RecognitionServiceState.other =>
            isDefault
                ? l.assistantOtherForNowDefault(
                    recognizer.appName ?? l.assistantAnotherService,
                  )
                : l.assistantOtherForNowNotDefault(
                    recognizer.appName ?? l.assistantAnotherService,
                  ),
          RecognitionServiceState.inactive =>
            isDefault
                ? l.assistantInactiveDefault
                : l.assistantInactiveNotDefault,
          RecognitionServiceState.active => l.assistantRecognizerActiveDetail,
          RecognitionServiceState.unknown => l.assistantRecognizerUnknownDetail,
        },
        // The stored choice stays; Android decides here.
        trailing: Opacity(
          opacity: elsewhere ? WOpacity.inactive : 1,
          child: WSwitch(
            value: offered,
            semanticLabel: elsewhere
                ? l.assistantOfferRecognizerUnavailable(l.assistantNotAvailable)
                : l.assistantOfferRecognizer,
            onChanged: elsewhere ? null : (on) => unawaited(_setOffered(on)),
          ),
        ),
      ),
    ],
  );

  Widget _defaultAssistant({
    required AppLocalizations l,
    required bool isDefault,
    required RecognitionServiceStatus recognizer,
    required bool offered,
    required bool elsewhere,
  }) => SettingsSection(
    title: l.assistantDefaultTitle,
    children: [
      SectionCard(
        children: [
          SettingsRow(
            title: isDefault ? l.assistantIsDefault : l.assistantNotDefault,
            detail: l.assistantDefaultHint,
            trailing: isDefault
                ? CheckStatusIcon(
                    CheckStatus.ok,
                    semanticLabel: l.assistantSetLabel,
                  )
                : null,
          ),
        ],
      ),
      if (isDefault)
        LinkButton(
          l.assistantChangeInAndroid,
          onPressed: () => unawaited(_openSystemSettings()),
        )
      else
        PrimaryButton(
          l.assistantSetDefault,
          onPressed: () => unawaited(_openSystemSettings()),
        ),
      _recognizerCard(
        l: l,
        isDefault: isDefault,
        recognizer: recognizer,
        offered: offered,
        elsewhere: elsewhere,
      ),
      if (!elsewhere) InfoBox(l.assistantSwitchHint),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
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
      title: l.areaAssistant,
      children: [
        _defaultAssistant(
          l: l,
          isDefault: isDefault,
          recognizer: recognizer,
          offered: offered,
          elsewhere: elsewhere,
        ),
        // Only with something to say, so the column adds no empty gap.
        if (ref.watch(batteryStatusProvider).value?.hasHints ?? false)
          const BatteryHints(),
        InfoBox(l.assistantNameHint),
        TextField(
          controller: _name,
          style: WText.body,
          decoration: InputDecoration(labelText: l.assistantNameLabel),
        ),
        TextField(
          key: const ValueKey('persona'),
          controller: _persona,
          style: WText.body,
          // Two lines to start, grows while typing up to five.
          minLines: 2,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(labelText: l.assistantPersonaLabel),
        ),
        PrimaryButton(l.save, onPressed: () => unawaited(_save())),
      ],
    );
  }
}
