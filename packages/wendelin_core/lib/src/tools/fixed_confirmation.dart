import 'package:meta/meta.dart';

import 'confirmation_texts/de.dart';
import 'confirmation_texts/en.dart';
import 'confirmation_texts/fr.dart';
import 'confirmation_texts/language.dart';

export 'confirmation_texts/language.dart' show ConfirmationLanguage;

/// Optional capability of a [Tool] (WP122): the tool has fixed confirmation
/// sentences, so a successful call can end the request without a second
/// model call. Default: no template, the model words the answer.
///
/// The tool puts the sentence of an outcome into `ToolOutcome.fixed`
/// (built from the result of the call, not from the model's arguments). A
/// tool lists every key it may use in [confirmationKeys]; the completeness
/// test checks them in every language of [confirmationLanguages]. Only for
/// tools whose success is unambiguous: read tools never get one.
abstract interface class FixedConfirmationTool {
  /// All template keys the tool's outcomes may use (including `#one`
  /// variants, see [ConfirmationSentence]).
  Set<String> get confirmationKeys;
}

/// A confirmation sentence that is not worded yet: the template [key] plus
/// the [params] to fill in. Rendered per language by [renderConfirmation].
///
/// Param values: `String`, `int`, `List<String>` (spoken as „A, B und C“),
/// `Duration`, `Set<int>` (weekdays, 1 = Monday) and `DateTime` (wall-clock
/// time, fields as shown).
///
/// A param `count` (`int`) selects the template `<key>#one` when it is 1,
/// if that exists (singular/plural verb).
@immutable
final class ConfirmationSentence {
  /// Creates a sentence for template [key].
  const ConfirmationSentence(this.key, [this.params = const {}]);

  /// Template key, e.g. `bring.added`.
  final String key;

  /// Values for the `{name}` placeholders of the template.
  final Map<String, Object> params;

  @override
  String toString() => 'ConfirmationSentence($key)';
}

/// Languages with confirmation templates, by language code.
const confirmationLanguages = <String, ConfirmationLanguage>{
  'de': confirmationDe,
  'en': confirmationEn,
  'fr': confirmationFr,
};

/// The sentence for [sentence] in [languageTag] (`de-DE`, `fr`; `null` =
/// German like the rest of the agent texts), or `null` if the language has
/// no templates or the template is missing/incomplete: the caller then
/// lets the model answer.
String? renderConfirmation(ConfirmationSentence sentence, String? languageTag) {
  final code = (languageTag ?? 'de').toLowerCase().split(RegExp('[-_]')).first;
  final lang = confirmationLanguages[code];
  if (lang == null) return null;
  final count = sentence.params['count'];
  final one = count == 1 ? lang.templates['${sentence.key}#one'] : null;
  final template = one ?? lang.templates[sentence.key];
  if (template == null) return null;
  var missing = false;
  final text = template.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
    final value = sentence.params[m[1]];
    if (value == null) {
      missing = true;
      return '';
    }
    return lang.format(value);
  });
  return missing ? null : text;
}

/// Several [sentences] one after the other, separated by a space.
String joinConfirmations(Iterable<String> sentences) => sentences.join(' ');
