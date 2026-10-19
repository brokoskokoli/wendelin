import 'package:wendelin_core/wendelin_core.dart';

import '../common/chat_wire.dart';
import '../common/exchange_tap.dart';
import 'attestation_types.dart';

/// A [ChatWireCodec] that encrypts to the key of the attested session of
/// exactly one `AttestedProvider` (Phala: `PhalaE2eeChannel`, NEAR AI:
/// `NearE2eeChannel`). Every request of such a provider must go through one.
abstract interface class SessionBoundChannel implements ChatWireCodec {
  /// Whether an `AttestedProvider` has taken this channel.
  bool get bound;

  /// Whether tool definitions, calls and results are end-to-end encrypted
  /// too (NEAR AI); Phala v2 leaves them to the pinned TLS (ADR 0018).
  bool get encryptsTools;

  /// Called by the `AttestedProvider`: where the current session comes from.
  /// Throws a [StateError] if the channel is already bound.
  void bind(AttestedSession? Function() session, Clock clock);
}

/// Implemented by an `AttestationVerifier` whose receipts are not announced
/// by an `x-receipt-id` header (NEAR AI: the chat id inside the answer).
abstract interface class ReceiptIdSource {
  /// The receipt id of the finished exchange [record], or `null`.
  String? receiptIdOf(ExchangeRecord record);
}

/// Implemented by an `AttestationVerifier` of a provider that issues **no
/// receipt per answer** (Tinfoil, ADR 0020). `AttestedProvider` then does
/// not ask for one (no `x-receipt-id`, no retries): each answer of the
/// attested session is green with the stage `receipt.none` (information)
/// in the audit log. The answer itself is bound to the request by the AEAD
/// of the end-to-end encryption.
abstract interface class ReceiptFreeVerifier {
  /// Secret-free note for the audit log entry of each answer.
  String get noReceiptNote;
}
