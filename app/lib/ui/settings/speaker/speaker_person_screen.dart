import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart' show ProviderProfile;
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../../di/profiles.dart';
import '../../../di/providers.dart';
import '../../../di/speaker_providers.dart';
import '../../../l10n/l10n.dart';
import '../../design/design.dart';
import '../memory_screen.dart';
import '../settings_page.dart';
import 'speaker_enroll_screen.dart';

/// Longest address kept (it goes into the system prompt).
const maxAddressChars = 40;

/// Einstellungen → Sprache → Sprechererkennung → Person (WP92b): address
/// (replaces the user name in the prompt), own or default memory, own agent
/// instead of the global default, enrolling again and deleting.
class SpeakerPersonScreen extends ConsumerStatefulWidget {
  /// Creates the screen for the person [personId].
  const SpeakerPersonScreen({super.key, required this.personId});

  /// Id of the person's voice profile.
  final String personId;

  @override
  ConsumerState<SpeakerPersonScreen> createState() => _PersonState();
}

class _PersonState extends ConsumerState<SpeakerPersonScreen> {
  final _address = TextEditingController();
  var _loaded = false;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  PersonSettings _settings() =>
      ref.read(personSettingsProvider).value?[widget.personId] ??
      PersonSettings(personId: widget.personId);

  Future<void> _change(PersonSettings next) =>
      ref.read(personSettingsProvider.notifier).change(next);

  Future<void> _saveAddress() {
    // One short line: it goes into the system prompt.
    final text = _address.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final cut = text.length > maxAddressChars
        ? text.substring(0, maxAddressChars)
        : text;
    return _change(
      cut.isEmpty
          ? _settings().copyWith(clearAddress: true)
          : _settings().copyWith(address: cut),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final people = ref.watch(speakerProfilesProvider).value ?? const [];
    final person = people.where((p) => p.id == widget.personId).firstOrNull;
    final settingsAsync = ref.watch(personSettingsProvider);
    if (person == null || settingsAsync.isLoading) {
      return SettingsPage(title: l.speakerPeople, children: const []);
    }
    final settings = settingsAsync.value?[widget.personId] ?? _settings();
    if (!_loaded) {
      _loaded = true;
      _address.text = settings.address ?? '';
    }
    final profiles = ref.watch(profilesProvider).value?.profiles ?? const [];
    final agentName = profiles
        .where((p) => p.id == settings.agentProfileId)
        .firstOrNull
        ?.name;
    return SettingsPage(
      title: person.name,
      children: [
        SettingsSection(
          title: l.speakerPersonAddress,
          children: [
            SettingsRow(title: l.speakerPersonAddressHint),
            TextField(
              key: const ValueKey('personAddress'),
              controller: _address,
              maxLength: maxAddressChars,
              decoration: InputDecoration(hintText: person.name),
              onChanged: (_) => unawaited(_saveAddress()),
            ),
          ],
        ),
        SettingsSection(
          title: l.speakerPersonMemory,
          children: [
            SettingsRow(
              key: const ValueKey('personMemoryOwn'),
              title: l.speakerPersonMemoryOwn,
              detail: l.speakerPersonMemoryOwnDetail,
              trailing: WSwitch(
                value: !settings.sharedMemory,
                semanticLabel: l.speakerPersonMemoryOwn,
                onChanged: (own) =>
                    unawaited(_change(settings.copyWith(sharedMemory: !own))),
              ),
            ),
            if (settings.sharedMemory)
              SettingsRow(
                detail: l.speakerPersonMemorySharedDetail,
                title: l.speakerPersonMemoryShared,
              )
            else
              SettingsRow(
                title: l.speakerPersonMemoryOpen,
                onTap: () => unawaited(
                  Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => MemoryScreen(owner: settings.memoryOwner),
                    ),
                  ),
                ),
              ),
          ],
        ),
        SettingsSection(
          title: l.speakerPersonAgent,
          children: [
            SettingsRow(
              key: const ValueKey('personAgent'),
              title: agentName ?? l.speakerPersonAgentDefault,
              detail: l.speakerPersonAgentDetail,
              onTap: () => unawaited(_pickAgent(profiles, settings)),
            ),
          ],
        ),
        SettingsSection(
          title: person.name,
          children: [
            SettingsRow(
              title: l.speakerPersonRetrain,
              detail: l.speakerPersonRetrainDetail,
              onTap: () => unawaited(
                Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => SpeakerEnrollScreen(
                      name: person.name,
                      personId: person.id,
                    ),
                  ),
                ),
              ),
            ),
            SettingsRow(
              key: const ValueKey('personDelete'),
              title: l.speakerPersonDelete,
              onTap: () => unawaited(_delete(person, settings)),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickAgent(
    List<ProviderProfile> profiles,
    PersonSettings settings,
  ) async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: WColors.surface,
        title: Text(context.l10n.speakerPersonAgent, style: WText.label),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(''),
            child: Text(
              context.l10n.speakerPersonAgentDefault,
              style: WText.body,
            ),
          ),
          for (final p in profiles)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(p.id),
              child: Text(p.name, style: WText.body),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    await _change(
      chosen.isEmpty
          ? settings.copyWith(clearAgent: true)
          : settings.copyWith(agentProfileId: chosen),
    );
  }

  Future<void> _delete(SpeakerProfile person, PersonSettings settings) async {
    final l = context.l10n;
    final count = settings.sharedMemory
        ? 0
        : await ref
              .read(storageProvider)
              .memory
              .count(owner: settings.memoryOwner);
    if (!mounted) return;
    final ok = await confirm(
      context,
      title: l.speakerDeleteTitle,
      message: count == 0
          ? l.speakerDeleteBody(person.name)
          : l.speakerDeleteBodyMemory(person.name, count),
      yes: l.speakerDeleteConfirm,
    );
    if (!ok) return;
    await ref.read(speakerProfilesProvider.notifier).remove(person.id);
    if (mounted) Navigator.of(context).pop();
  }
}
