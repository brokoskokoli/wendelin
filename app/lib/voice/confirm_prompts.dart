import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../agent/conversation_state.dart';
import '../ui/screens/labels.dart';

/// Whether a spoken „yes“ to [question] must be strict (1–2 yes words):
/// `external` tools and escalations below the privacy level.
bool strictAnswer(PendingQuestion question) => switch (question) {
  ToolQuestion(:final event) => event.risk == RiskLevel.external,
  EscalationQuestion() => true,
};

/// Spoken question for an open confirmation, in [language] (de/fr/en);
/// names the action.
String confirmationPrompt(PendingQuestion question, String? language) {
  final lang = VoiceTexts.of(language).language;
  return switch (question) {
    ToolQuestion(:final event) => switch (lang) {
      'fr' => '${_actionFr(event.call.name)} Oui ou non ?',
      'en' => '${_actionEn(event.call.name)} Yes or no?',
      _ => '${confirmationTexts(event.call.name).title} Ja oder nein?',
    },
    EscalationQuestion(:final toName) => switch (lang) {
      'fr' => 'Transmettre à $toName ? Oui ou non ?',
      'en' => 'Hand over to $toName? Yes or no?',
      _ => 'An $toName übergeben? Ja oder nein?',
    },
  };
}

String _spokenTool(String tool) =>
    tool.replaceAll('__', ' ').replaceAll('_', ' ');

bool _deletes(String tool) => RegExp('delete|remove|clear|forget')
    .hasMatch(tool.contains('__') ? tool.substring(tool.indexOf('__')) : tool);

String _actionFr(String tool) => switch (tool) {
  'calendar__delete_event' => 'Supprimer le rendez-vous ?',
  'obsidian__replace_section' => 'Remplacer la section de la note ?',
  'lists__clear_completed' => 'Supprimer les éléments terminés ?',
  _ when _deletes(tool) => 'Supprimer : ${_spokenTool(tool)} ?',
  _ => 'Exécuter : ${_spokenTool(tool)} ?',
};

String _actionEn(String tool) => switch (tool) {
  'calendar__delete_event' => 'Delete the appointment?',
  'obsidian__replace_section' => 'Replace the section of the note?',
  'lists__clear_completed' => 'Clear the completed items?',
  _ when _deletes(tool) => 'Delete: ${_spokenTool(tool)}?',
  _ => 'Run: ${_spokenTool(tool)}?',
};

/// Spoken request to repeat an unclear answer.
String repeatPrompt(String? language) =>
    switch (VoiceTexts.of(language).language) {
      'fr' => 'Dis oui ou non, s’il te plaît.',
      'en' => 'Please say yes or no.',
      _ => 'Bitte sag ja oder nein.',
    };

/// Spoken note that the open confirmation now needs a tap (B7).
String tapAnswerPrompt(String? language) =>
    switch (VoiceTexts.of(language).language) {
      'fr' => 'Réponds en touchant l’écran, s’il te plaît.',
      'en' => 'Please answer with a tap.',
      _ => 'Antworte bitte per Tipp.',
    };
