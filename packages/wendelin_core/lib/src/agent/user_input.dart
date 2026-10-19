import 'package:meta/meta.dart';

import '../messages/content_block.dart';

/// How the user entered a request.
enum InputSource {
  /// Typed.
  text,

  /// Spoken and transcribed.
  voice,
}

/// One user request handed to `AgentRun.run`.
@immutable
final class UserInput {
  /// Creates a user input; [images] are copied unmodifiable.
  UserInput({
    required this.text,
    List<ImageBlock> images = const [],
    this.source = InputSource.text,
    this.sttConfidence,
    this.language,
    this.requestEscalation = false,
    this.speakerId,
  }) : images = List.unmodifiable(images);

  /// The request text (transcript for voice input).
  final String text;

  /// Attached images.
  final List<ImageBlock> images;

  /// Typed or spoken.
  final InputSource source;

  /// Speech recognition confidence 0.0–1.0 (voice only).
  final double? sttConfidence;

  /// Detected or chosen language as BCP 47 tag (e.g. `de`).
  final String? language;

  /// The user explicitly asked for a stronger model ("nochmal mit Claude",
  /// "das war falsch"); the agent escalates (concept: Routing → Eskalation).
  final bool requestEscalation;

  /// Id of the recognized person (WP92b), `null` = unknown speaker or typed.
  /// Only an opaque key: it never reaches logs, audit or exports.
  final String? speakerId;

  @override
  String toString() =>
      'UserInput(${source.name}, "$text", ${images.length} images)';
}
