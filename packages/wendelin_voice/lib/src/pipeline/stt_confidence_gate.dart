import '../io/trigger.dart';

/// What to do with a transcript whose recognition confidence is low
/// (WP140).
enum SttGateAction {
  /// Pass it on.
  accept,

  /// Drop it and ask again („Nicht verstanden“): the user spoke on purpose.
  askAgain,

  /// Drop it and keep listening quietly: perhaps nobody spoke at all.
  dropQuietly,
}

/// Decides from [Transcript.confidence] whether a request goes to the model.
///
/// Thresholds are provisional (to be checked against real runs). A `null`
/// confidence means „no judgement“ and is never dropped. Equal to the
/// threshold passes.
final class SttConfidenceGate {
  /// Creates the gate.
  const SttConfidenceGate({
    this.handsFree = defaultHandsFree,
    this.deliberate = defaultDeliberate,
  });

  /// Default threshold without a button press (follow-up question, wake
  /// word, after a barge-in).
  static const defaultHandsFree = 0.5;

  /// Default threshold for a deliberate start (button, assistant, widget):
  /// lower, because dropping a request the user spoke on purpose is worse.
  static const defaultDeliberate = 0.3;

  /// Threshold without button press.
  final double handsFree;

  /// Threshold for a deliberate start.
  final double deliberate;

  /// The action for [confidence] in this situation.
  SttGateAction decide(
    double? confidence, {
    required bool followUp,
    TriggerKind? source,
  }) {
    if (confidence == null) return SttGateAction.accept;
    final deliberateStart =
        !followUp && source != null && source != TriggerKind.wakeWord;
    final min = deliberateStart ? deliberate : handsFree;
    if (confidence >= min) return SttGateAction.accept;
    return followUp ? SttGateAction.dropQuietly : SttGateAction.askAgain;
  }
}
