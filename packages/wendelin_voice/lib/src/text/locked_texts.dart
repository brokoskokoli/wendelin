/// Fixed sentences of the lock screen (no content), spoken in the language of
/// the utterance like [VoiceTexts] (primary subtag; unknown falls back to
/// German).
abstract final class LockedTexts {
  /// Said for everything but a flashlight command.
  static String unlock(String? language) => switch (_lang(language)) {
    'fr' => 'Veuillez déverrouiller le téléphone.',
    'en' => 'Please unlock the phone.',
    _ => 'Bitte entsperre das Telefon.',
  };

  /// Said after a flashlight command.
  static String flashlight(String? language, {required bool on}) =>
      switch (_lang(language)) {
        'fr' => on ? 'Lampe allumée.' : 'Lampe éteinte.',
        'en' => on ? 'Flashlight on.' : 'Flashlight off.',
        _ => on ? 'Taschenlampe an.' : 'Taschenlampe aus.',
      };

  /// Said when a call that works only unlocked (WP163 B) waits for the
  /// unlock: [navigation] names the navigation, else generic.
  static String deferred(String? language, {required bool navigation}) =>
      switch (_lang(language)) {
        'fr' =>
          navigation
              ? 'Veuillez déverrouiller pour naviguer.'
              : 'Veuillez déverrouiller pour cela.',
        'en' =>
          navigation ? 'Please unlock to navigate.' : 'Please unlock for that.',
        _ =>
          navigation
              ? 'Zum Navigieren bitte entsperren.'
              : 'Dafür bitte entsperren.',
      };

  /// The command did not work (no LED, camera busy).
  static String failed(String? language) => switch (_lang(language)) {
    'fr' => 'Cela ne marche pas.',
    'en' => 'That did not work.',
    _ => 'Das hat nicht geklappt.',
  };

  static String _lang(String? language) =>
      (language ?? 'de').toLowerCase().split(RegExp('[-_]')).first;
}
