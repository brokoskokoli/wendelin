import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/preference_models.dart';
import '../../di/preferences.dart';
import '../design/design.dart';
import 'settings_page.dart';

/// Settings → Assistent: the user's name and a personality addition for
/// the system prompt.
class AssistantScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantState();
}

class _AssistantState extends ConsumerState<AssistantScreen> {
  final _name = TextEditingController();
  final _persona = TextEditingController();

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(assistantPrefsProvider);
    _name.text = prefs.userName ?? '';
    _persona.text = prefs.persona ?? '';
  }

  @override
  void dispose() {
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
    intro: 'Beides geht als Teil der Anweisungen an das Modell.',
    children: [
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
