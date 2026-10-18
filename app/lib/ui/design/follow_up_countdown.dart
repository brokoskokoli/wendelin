import 'dart:async';

import 'package:flutter/widgets.dart';

/// Remaining whole seconds until [until] (rounded up, never negative).
int followUpSeconds(DateTime until, DateTime now) {
  final ms = until.difference(now).inMilliseconds;
  return ms <= 0 ? 0 : (ms + 999) ~/ 1000;
}

/// Rebuilds [builder] with the remaining seconds of the follow-up window
/// ([until], measured with [now]) about four times a second.
class FollowUpCountdown extends StatefulWidget {
  /// Creates the countdown.
  const FollowUpCountdown({
    super.key,
    required this.until,
    required this.now,
    required this.builder,
  });

  /// End of the follow-up window.
  final DateTime until;

  /// Current time (the app clock).
  final DateTime Function() now;

  /// Builds the display for the remaining seconds.
  final Widget Function(BuildContext context, int seconds) builder;

  @override
  State<FollowUpCountdown> createState() => _FollowUpCountdownState();
}

class _FollowUpCountdownState extends State<FollowUpCountdown> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, followUpSeconds(widget.until, widget.now()));
}
