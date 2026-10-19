import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/contacts.dart' show SmsDraftEdits;

import '../../agent/outgoing_preview.dart';
import '../../di/sms_drafts.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';

/// Preview before an SMS is sent or a call is placed (WP85): recipient with
/// name and number and, for an SMS, the editable text. „Absenden“ /
/// „Anrufen“ is the only way (besides a clear spoken yes) to do it; the text
/// shown in the field is the text that is sent.
class OutgoingPreviewCard extends ConsumerStatefulWidget {
  /// Creates the card; [answer] gets `true` for send/call.
  const OutgoingPreviewCard({
    super.key,
    required this.preview,
    required this.answer,
  });

  /// What is about to happen.
  final OutgoingPreview preview;

  /// Receives the user's decision.
  final void Function(bool yes) answer;

  @override
  ConsumerState<OutgoingPreviewCard> createState() =>
      _OutgoingPreviewCardState();
}

class _OutgoingPreviewCardState extends ConsumerState<OutgoingPreviewCard> {
  late final TextEditingController _text = TextEditingController(
    text: widget.preview.text,
  );
  late final SmsDraftEdits _edits;
  bool _approved = false;

  OutgoingPreview get _p => widget.preview;
  bool get _sms => _p.kind == OutgoingKind.sms;
  bool get _blank => _sms && _text.text.trim().isEmpty;

  @override
  void initState() {
    super.initState();
    _edits = ref.read(smsDraftEditsProvider);
    _text.addListener(_onEdited);
  }

  void _onEdited() {
    // The edit is recorded as typed, so a spoken „ja“ cannot confirm a text
    // the user changed and never heard (see `OutgoingPreview` in the voice
    // confirmation).
    _edits.set(_p.number, _p.text, _text.text.trim());
    setState(() {});
  }

  @override
  void dispose() {
    // Not approved (declined, dismissed, answered by voice or replaced): the
    // edit must not leak into a later message with the same text.
    if (!_approved) {
      _edits.discard(_p.number, _p.text);
    }
    _text.dispose();
    super.dispose();
  }

  void _yes() {
    if (_blank) return;
    _approved = true;
    widget.answer(true);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ConfirmationCard(
      title: _sms ? l.confSmsTitle : l.confCallTitle,
      subject: _p.known ? _p.name : null,
      detail: _p.number,
      detailWidget: _sms
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: WSpace.s,
              children: [
                Text(_p.number, style: WText.detail),
                TextField(
                  key: const ValueKey('smsText'),
                  controller: _text,
                  minLines: 2,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: l.confSmsTextLabel,
                    errorText: _blank ? l.confSmsNoText : null,
                  ),
                ),
              ],
            )
          : null,
      toolName: _p.kind.tool,
      risk: RiskLevel.external,
      onYes: _blank ? null : _yes,
      onNo: () => widget.answer(false),
      yesLabel: _sms ? l.confYesSend : l.confYesCall,
      noLabel: l.confNoCancel,
    );
  }
}
