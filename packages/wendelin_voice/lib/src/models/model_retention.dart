/// Release reason of Android's `onTrimMemory` (WP103). It is the only
/// reason that frees the models although „Modell im Speicher halten“ is on.
const memoryPressureReason = 'memory';

/// Whether the loaded recognizer and voice models may be freed for
/// [reason] (`idle`, `overlay-close`, `release`, [memoryPressureReason], …)
/// with the setting `VoiceSettings.keepModelLoaded` at [keepLoaded].
///
/// With the setting on, only memory pressure frees them; replacing the
/// model after a change of the choice is not a release of this kind (it
/// does not go through here).
bool mayReleaseModels(String reason, {required bool keepLoaded}) =>
    !keepLoaded || reason == memoryPressureReason;
