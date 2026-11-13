import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'icons.dart';

/// Zustand des Mikrofon-Buttons.
enum MicState {
  /// Bereit: Kobalt-Kreis mit Mikrofon.
  idle,

  /// Hört zu: Ring in `accentLight` am Rand, Scheibe etwas kleiner.
  listening,

  /// Verarbeitet: drei ruhende Punkte statt Mikrofon.
  thinking,

  /// Spricht: drei bewegte Punkte (Tipp stoppt die Sprachausgabe).
  speaking,

  /// Bereitet vor („Moment …“): Mikrofon mit gedämpftem Ring, solange die
  /// Sprachmodelle laden; das Mikrofon puffert schon.
  preparing,

  /// Nicht verfügbar: gedämpft, nicht antippbar.
  disabled,
}

/// Drücken-und-Halten-Geste des Mikrofon-Buttons (WP192).
class MicGesture {
  /// Erstellt die Geste.
  const MicGesture({
    required this.onDown,
    required this.onHold,
    required this.onUp,
    this.onAbort,
  });

  /// Finger runter.
  final VoidCallback onDown;

  /// Finger blieb [holdThreshold] lang unten.
  final VoidCallback onHold;

  /// Finger hoch oder Geste vom System abgebrochen; `held`: Grenze war
  /// überschritten.
  final ValueChanged<bool> onUp;

  /// Der Button wurde während eines Drucks vor der Haltegrenze entfernt
  /// (kein [onUp] mehr): nur das Halten aufheben, nichts abbrechen.
  final VoidCallback? onAbort;

  /// Ab dieser Dauer zählt der Druck als Halten (wie `kHoldThreshold`).
  static const holdThreshold = Duration(milliseconds: 450);
}

/// Runder Mikrofon-Button (72, kompakt 64) – der einzige Kobalt-Akzent.
///
/// Mit [gesture] (Pointer-Ereignisse, kein `onLongPress`): Druck startet
/// sofort, nach der Haltegrenze zeigt der Button den Haltezustand, Wegrutschen
/// beendet nichts, erst Loslassen oder Abbruch. [onPressed] bleibt die
/// Semantics-Tipp-Aktion (TalkBack) und wird nicht von physischen Tippen
/// ausgelöst, wenn [gesture] gesetzt ist.
class MicButton extends StatefulWidget {
  /// Erstellt einen Mikrofon-Button.
  const MicButton({
    super.key,
    required this.state,
    required this.onPressed,
    this.compact = false,
    this.semanticLabel,
    this.hearing = false,
    this.gesture,
  });

  /// Drücken-und-Halten; ohne: nur Tipp über [onPressed].
  final MicGesture? gesture;

  /// Zustand.
  final MicState state;

  /// Aktion bei Tipp (wird bei [MicState.disabled] ignoriert).
  final VoidCallback? onPressed;

  /// 64 statt 72 (Hauptbildschirm).
  final bool compact;

  /// Wendelin hört während der Sprachausgabe auf „Stopp“/„Wendelin“
  /// (WP113): bei [MicState.speaking] liegt ein Ring um den Knopf.
  final bool hearing;

  /// Überschreibt das Standard-Label des Zustands.
  final String? semanticLabel;

  /// Standard-Label je Zustand.
  static String labelFor(AppLocalizations l, MicState state) => switch (state) {
    MicState.idle => l.mainMicSpeak,
    MicState.listening => l.mainMicStopListening,
    MicState.thinking => l.mainMicCancelAnswer,
    MicState.speaking => l.mainMicStopSpeech,
    MicState.preparing => l.momentPlease,
    MicState.disabled => l.mainMicUnavailable,
  };

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton> {
  Timer? _timer;
  int? _pointer;
  bool _holding = false;

  MicState get state => widget.state;

  @override
  void didUpdateWidget(MicButton old) {
    super.didUpdateWidget(old);
    if (widget.state == MicState.disabled && _pointer != null) _end(_holding);
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Removed during a press: only a held recording is released (so it does
    // not hang); a plain tap must not cancel anything.
    if (_pointer != null) {
      if (_holding) {
        widget.gesture?.onUp(true);
      } else {
        widget.gesture?.onAbort?.call();
      }
    }
    super.dispose();
  }

  void _down(PointerDownEvent e) {
    final g = widget.gesture;
    if (g == null || state == MicState.disabled || _pointer != null) return;
    _pointer = e.pointer;
    g.onDown();
    _timer = Timer(MicGesture.holdThreshold, () {
      _timer = null;
      if (_pointer == null || !mounted) return;
      setState(() => _holding = true);
      widget.gesture?.onHold();
    });
  }

  void _up(PointerEvent e) {
    if (e.pointer == _pointer) _end(_holding);
  }

  void _end(bool held) {
    _timer?.cancel();
    _timer = null;
    _pointer = null;
    final g = widget.gesture;
    if (_holding && mounted) setState(() => _holding = false);
    _holding = false;
    g?.onUp(held);
  }

  @override
  Widget build(BuildContext context) {
    final onPressed = widget.onPressed;
    final compact = widget.compact;
    final hearing = widget.hearing;
    final semanticLabel = widget.semanticLabel;
    final gesture = widget.gesture;
    final extent = compact ? WSize.micButtonCompact : WSize.micButton;
    final disabled = state == MicState.disabled;
    final Widget content = switch (state) {
      MicState.thinking => const _Dots(animated: false),
      MicState.speaking => const _Dots(animated: true),
      _ => WIcon(
        WIcons.mic,
        size: compact ? WSize.micIconCompact : WSize.micIcon,
        color: disabled ? WColors.textMuted : WColors.onAccent,
      ),
    };
    final listening = state == MicState.listening;
    final preparing = state == MicState.preparing;
    final hearingRing = hearing && state == MicState.speaking;
    final holding = _holding && !disabled;
    final tooltip =
        (holding ? context.l10n.voiceReleaseToSend : semanticLabel) ??
        (hearingRing
            ? context.l10n.mainMicHearing
            : MicButton.labelFor(context.l10n, state));
    // Der Ring beim Zuhören liegt innerhalb der Fläche (72 bzw. 64): außen
    // der Ring, dann eine Lücke, innen die Kobalt-Scheibe. Kein Überstand,
    // kein Layout-Sprung zwischen den Zuständen.
    final button = CustomPaint(
      painter: listening || hearingRing || holding
          ? _ListeningPainter(WColors.accentLight)
          : preparing
          ? _ListeningPainter(
              WColors.accentLight.withValues(alpha: WOpacity.inactive),
            )
          : null,
      child: IconButton(
        // Nur Tooltip: wird auch als Semantics-Tooltip vorgelesen; ein
        // zusätzliches Label würde doppelt angesagt.
        // Mit Geste hängt der Tooltip außen (nur manuell/Hover): der
        // Long-Press-Tooltip spränge sonst beim Halten auf.
        tooltip: gesture != null ? null : tooltip,
        // Mit Geste löst der Listener den physischen Tipp aus; der
        // IconButton bleibt nur für Optik (und ist per ExcludeSemantics
        // aus dem Baum, die Tipp-Aktion hängt außen).
        onPressed: disabled
            ? null
            : gesture != null
            ? _noop
            : onPressed,
        icon: content,
        style: IconButton.styleFrom(
          fixedSize: Size.square(extent),
          padding: EdgeInsets.zero,
          backgroundColor: listening || preparing || hearingRing || holding
              ? WColors.transparent
              : WColors.accent,
          disabledBackgroundColor: WColors.surfaceRaised,
          shape: const CircleBorder(),
        ),
      ),
    );
    if (gesture == null) return button;
    return _withGesture(
      button,
      tooltip: tooltip,
      extent: extent,
      holding: holding,
    );
  }

  Widget _withGesture(
    Widget button, {
    required String tooltip,
    required double extent,
    required bool holding,
  }) {
    final disabled = state == MicState.disabled;
    final onPressed = widget.onPressed;
    return Semantics(
      button: true,
      enabled: !disabled,
      label: tooltip,
      onTap: disabled ? null : onPressed,
      excludeSemantics: true,
      child: Listener(
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            ExcludeSemantics(
              child: Tooltip(
                message: tooltip,
                triggerMode: TooltipTriggerMode.manual,
                child: button,
              ),
            ),
            if (holding) _HoldLabel(bottom: extent + WSpace.xs),
          ],
        ),
      ),
    );
  }

  static void _noop() {}
}

class _ListeningPainter extends CustomPainter {
  _ListeningPainter(this.ring);

  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas
      ..drawCircle(
        c,
        r - WSize.micRing / 2,
        Paint()
          ..color = ring
          ..style = PaintingStyle.stroke
          ..strokeWidth = WSize.micRing,
      )
      ..drawCircle(
        c,
        r - WSize.micRing - WSize.micRingGap,
        Paint()..color = WColors.accent,
      );
  }

  @override
  bool shouldRepaint(_ListeningPainter oldDelegate) => oldDelegate.ring != ring;
}

/// Drei Punkte; [animated] lässt sie nacheinander hüpfen (Sprechen).
/// Ohne Bewegung, wenn die Animationen abgeschaltet sind.
class _Dots extends StatefulWidget {
  const _Dots({required this.animated});

  final bool animated;

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final move = widget.animated && !MediaQuery.disableAnimationsOf(context);
    if (move && !_c.isAnimating) {
      unawaited(_c.repeat());
    } else if (!move && _c.isAnimating) {
      _c.stop();
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        spacing: WSpace.xs,
        children: [
          for (var i = 0; i < 3; i++)
            Transform.translate(
              offset: Offset(
                0,
                widget.animated ? -_bounce(i) * WSize.hintDot : 0,
              ),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: WColors.onAccent,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(dimension: WSize.hintDot),
              ),
            ),
        ],
      ),
    );
  }

  /// 0…1: a wave over the three dots, so the still image of „speaking“
  /// (animations off) differs from „thinking“ (dots in a row).
  double _bounce(int i) => (1 + math.sin(2 * math.pi * (_c.value - i / 3))) / 2;
}

/// „Loslassen zum Senden“ als Pille über dem Button (nimmt keine Eingaben).
class _HoldLabel extends StatelessWidget {
  const _HoldLabel({required this.bottom});

  final double bottom;

  @override
  Widget build(BuildContext context) => Positioned(
    bottom: bottom,
    child: IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: WSpace.s,
          vertical: WSpace.xs,
        ),
        decoration: BoxDecoration(
          color: WColors.surfaceRaised,
          borderRadius: BorderRadius.circular(WSpace.s),
        ),
        child: Text(
          context.l10n.voiceReleaseToSend,
          softWrap: false,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
    ),
  );
}
