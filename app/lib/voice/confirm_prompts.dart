import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../agent/conversation_state.dart';
import '../agent/outgoing_preview.dart';
import '../l10n/gen/app_localizations_de.dart';
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
  final outgoing = outgoingPreviewOf(question);
  return switch (question) {
    _ when outgoing != null => _outgoingPrompt(outgoing, lang),
    ToolQuestion(:final event) when _replaceSection(event) != null => () {
      // Names the note the confirmation resolved (B8).
      final (:note, :section) = _replaceSection(event)!;
      return switch (lang) {
        'fr' => 'Dans $note, remplacer la section $section, d’accord ?',
        'en' => 'In $note, replace the section $section, shall I?',
        _ => 'In $note den Abschnitt $section ersetzen, soll ich?',
      };
    }(),
    ToolQuestion(:final event) => switch (lang) {
      'fr' => '${_actionFr(event.call.name)} Oui ou non ?',
      'en' => '${_actionEn(event.call.name)} Yes or no?',
      _ =>
        '${confirmationTexts(AppLocalizationsDe(), event.call.name).title} Ja oder nein?',
    },
    EscalationQuestion(:final toName) => switch (lang) {
      'fr' => 'Transmettre à $toName ? Oui ou non ?',
      'en' => 'Hand over to $toName? Yes or no?',
      _ => 'An $toName übergeben? Ja oder nein?',
    },
  };
}

/// „Nachricht an X: …“ + „Soll ich sie absenden?“ or „Anruf bei X. Soll ich
/// anrufen?“ (WP85): the text is read exactly as shown in the preview.
String _outgoingPrompt(OutgoingPreview p, String lang) => switch (p.kind) {
  OutgoingKind.sms => switch (lang) {
    'fr' => 'Message à ${p.name} : ${p.text}. Je l’envoie ?',
    'en' => 'Message to ${p.name}: ${p.text}. Shall I send it?',
    _ => 'Nachricht an ${p.name}: ${p.text}. Soll ich sie absenden?',
  },
  OutgoingKind.call => switch (lang) {
    'fr' => 'Appel à ${p.name}. Je l’appelle ?',
    'en' => 'Call to ${p.name}. Shall I call?',
    _ => 'Anruf bei ${p.name}. Soll ich anrufen?',
  },
};

final _replaceText = RegExp(
  '^Abschnitt „(.+)“ in „(.+)“ ersetzen:',
  multiLine: true,
);

/// Note title and section of the confirmation text of
/// `obsidian__replace_section` (`prepareConfirmation` of WP31/B8).
({String note, String section})? _replaceSection(ConfirmationRequired event) {
  if (event.call.name != 'obsidian__replace_section') return null;
  final m = _replaceText.firstMatch(event.description);
  if (m == null) return null;
  final path = m.group(2)!;
  final name = path.substring(path.lastIndexOf('/') + 1);
  final note = name.toLowerCase().endsWith('.md')
      ? name.substring(0, name.length - 3)
      : name;
  return (note: note, section: m.group(1)!);
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

/// Spoken request to repeat an unclear answer; before an SMS or call
/// ([outgoing]) it names the words that count.
String repeatPrompt(String? language, {OutgoingKind? outgoing}) =>
    switch ((VoiceTexts.of(language).language, outgoing)) {
      ('fr', OutgoingKind.sms) => 'Dis « envoyer » ou « annuler ».',
      ('en', OutgoingKind.sms) => 'Please say “send” or “cancel”.',
      (_, OutgoingKind.sms) => 'Bitte sag „absenden“ oder „abbrechen“.',
      ('fr', OutgoingKind.call) => 'Dis « appeler » ou « annuler ».',
      ('en', OutgoingKind.call) => 'Please say “call” or “cancel”.',
      (_, OutgoingKind.call) => 'Bitte sag „anrufen“ oder „abbrechen“.',
      ('fr', null) => 'Dis oui ou non, s’il te plaît.',
      ('en', null) => 'Please say yes or no.',
      _ => 'Bitte sag ja oder nein.',
    };

/// Spoken note that the open confirmation now needs a tap (B7).
String tapAnswerPrompt(String? language) =>
    switch (VoiceTexts.of(language).language) {
      'fr' => 'Réponds en touchant l’écran, s’il te plaît.',
      'en' => 'Please answer with a tap.',
      _ => 'Antworte bitte per Tipp.',
    };

/// „Zurückgenommen.“ after an undo, in the language of the request (B9).
String undoneText(String? language) =>
    switch (VoiceTexts.of(language).language) {
      'fr' => 'Annulé.',
      'en' => 'Undone.',
      _ => 'Zurückgenommen.',
    };

/// „Abgebrochen.“ after a stop word or a tap on an empty request.
const cancelledText = 'Abgebrochen.';
