import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../di/locked_scope.dart';
import '../di/provider_config.dart' show ProviderConfig;
import '../di/providers.dart';

/// A request refused while locked, kept only in memory until the unlock
/// (WP114, K85): the overlay runs it after a successful unlock and drops it
/// when the unlock is cancelled, the overlay closes or [lockedPendingMaxAge]
/// has passed. Never logged, never in the audit log, never stored.
///
/// WP163 B: the entry holds the wording ([call] is `null`) **or** the one
/// tool call of that request that works only unlocked ([call] set; [text]
/// then only names the request for the display after the unlock). Same
/// mechanism, same limits; the call runs once, without a model run.
final class LockedPendingRequest {
  /// Creates the pending request.
  const LockedPendingRequest(this.text, this.at, {this.call});

  /// What was said (kept in memory only).
  final String text;

  /// When it was refused.
  final DateTime at;

  /// The tool call that waits for the unlock (tool and arguments, memory
  /// only), or `null` if the wording waits.
  final ToolCallBlock? call;

  /// How long this entry waits.
  Duration get maxAge =>
      call == null ? lockedPendingMaxAge : lockedPendingCallMaxAge;
}

/// How long a refused request waits for the unlock.
const lockedPendingMaxAge = Duration(seconds: 30);

/// How long a remembered tool call waits for the unlock (WP163 B).
const lockedPendingCallMaxAge = Duration(seconds: 60);

/// The request waiting for the unlock, if any ([LockedPendingRequest]).
final lockedPendingProvider =
    NotifierProvider<LockedPending, LockedPendingRequest?>(LockedPending.new);

/// State of [lockedPendingProvider].
final class LockedPending extends Notifier<LockedPendingRequest?> {
  @override
  LockedPendingRequest? build() => null;

  /// Remembers [text] (replaces an older one).
  void keep(String text) =>
      state = LockedPendingRequest(text, ref.read(clockProvider).now());

  /// Remembers the tool [call] of the request [text] instead of the
  /// wording (replaces an older entry; WP163 B).
  void keepCall(String text, ToolCallBlock call) => state =
      LockedPendingRequest(text, ref.read(clockProvider).now(), call: call);

  /// Drops the request.
  void clear() => state = null;

  /// The entry, once; `null` if none or too old (fail closed).
  LockedPendingRequest? take() {
    final p = state;
    state = null;
    if (p == null) return null;
    final age = ref.read(clockProvider).now().difference(p.at);
    return age > p.maxAge ? null : p;
  }
}

/// A remembered tool call, armed after the real unlock (WP163 B): the next
/// run of [LockGateAgentRun] for the same request text runs exactly this call
/// through the executor instead of the model, and the arming is used up. Set
/// by the overlay, memory only.
final lockedArmedCallProvider =
    NotifierProvider<LockedArmedCall, LockedPendingRequest?>(
      LockedArmedCall.new,
    );

/// State of [lockedArmedCallProvider].
final class LockedArmedCall extends Notifier<LockedPendingRequest?> {
  @override
  LockedPendingRequest? build() => null;

  /// Arms [request] (it must hold a call).
  void arm(LockedPendingRequest request) {
    assert(request.call != null, 'only a request with a call can be armed');
    state = request;
  }

  /// Disarms.
  void clear() => state = null;

  /// The call armed for [text], once (`null` otherwise; a mismatch keeps
  /// the arming).
  ToolCallBlock? takeFor(String text) {
    final r = state;
    if (r == null || r.text != text) return null;
    state = null;
    final age = ref.read(clockProvider).now().difference(r.at);
    return age > r.maxAge ? null : r.call;
  }
}

/// The current request on the locked device and the answer to it (WP163,
/// ADR 0022 L2/L3): what the overlay may show while locked. Only what was
/// heard and what is spoken anyway; never tool names, arguments or results,
/// never a history. Memory only, not stored, not logged.
final class LockedExchange {
  /// Creates the exchange.
  const LockedExchange(this.request, {this.answer});

  /// What was said (speech-to-text result).
  final String request;

  /// What the assistant answers (also spoken); `null` while the answer is
  /// pending or when the run ended without one (cancelled).
  final String? answer;
}

/// The one current [LockedExchange] of the locked overlay, if any.
final lockedExchangeProvider =
    NotifierProvider<LockedExchangeNotifier, LockedExchange?>(
      LockedExchangeNotifier.new,
    );

/// State of [lockedExchangeProvider]; a new request replaces the old one.
final class LockedExchangeNotifier extends Notifier<LockedExchange?> {
  @override
  LockedExchange? build() => null;

  /// A new request starts (replaces request and answer of the one before).
  void begin(String request) => state = LockedExchange(request);

  /// The answer to the current request (ignored without a request).
  void answer(String text) {
    final e = state;
    if (e == null) return;
    state = LockedExchange(e.request, answer: text);
  }

  /// Drops request and answer (unlock, overlay closed).
  void clear() => state = null;
}

/// Internal error codes of [deferredCallRunnerProvider]; never spoken or
/// shown (the failure sentence is [LockedTexts.failed]).
const deferredUnavailable = 'unavailable';

/// See [deferredUnavailable].
const deferredNotRun = 'not-run';

/// Runs a call that waited for the unlock ([LockedPendingRequest.call]).
typedef DeferredCallRunner = Future<ToolOutcome> Function(ToolCallBlock call);

/// Runs the remembered call of WP163 B once, after the real unlock, through
/// the normal executor (policy of the **unlocked** device, audit as any call,
/// timeout) and without a model. A confirmation is never asked here (the
/// call was allowed without one while locked): fail-closed, declined.
final deferredCallRunnerProvider = Provider<DeferredCallRunner>((ref) {
  return (call) async {
    final ProviderConfig? providers;
    try {
      providers = await ref.read(providerConfigProvider.future);
      await ref.read(toolRegistryReadyProvider.future);
    } on Object {
      return ToolOutcome.error(deferredUnavailable);
    }
    if (providers == null) return ToolOutcome.error(deferredUnavailable);
    final registry = ref.read(toolRegistryProvider);
    final device = ref.read(deviceInfoProvider);
    final executor = ToolExecutor(
      catalog: registry.catalogFor(
        providers.lowestPrivacy,
        sessionId: lockedSessionId,
      ),
      policy: ref.read(riskPolicyProvider),
      audit: ref.read(auditRecorderProvider),
    );
    var outcome = ToolOutcome.error(deferredNotRun);
    try {
      await for (final event in executor.invokeAll(
        [call],
        ToolContext(
          sessionId: lockedSessionId,
          clock: ref.read(clockProvider),
          locale: device.locale,
          timeZone: device.timeZone,
        ),
      )) {
        switch (event) {
          case ConfirmationNeeded():
            event.respond(false);
          case ToolFinished():
            outcome = event.outcome;
          case ToolStarted():
        }
      }
    } on Object {
      outcome = ToolOutcome.error(deferredNotRun);
    }
    return outcome;
  };
});

/// The tools of the executor mark `WorksOnlyUnlocked` that start a
/// navigation: the held-back sentence then says „Zum Navigieren“, otherwise
/// the generic one (WP163 B).
const lockedNavigationTools = {'maps__navigate', 'location__navigate_to'};

/// Drops everything the lock screen keeps in memory (overlay closes): the
/// waiting request, the armed call and the shown exchange.
void dropLockedState(WidgetRef ref) {
  ref.read(lockedPendingProvider.notifier).clear();
  ref.read(lockedArmedCallProvider.notifier).clear();
  ref.read(lockedExchangeProvider.notifier).clear();
}

/// Continues the [request] that waited for the unlock via [answer] (reads it
/// aloud and answers; `false` if speech is not available). A remembered tool
/// call (WP163 B) runs once, armed for exactly this request text: the gate
/// runs it instead of a model when the run starts. Not answered: disarmed,
/// and the caller sends the request as a normal typed one.
Future<bool> answerRemembered(
  WidgetRef ref,
  LockedPendingRequest request,
  Future<bool> Function(String text) answer,
) async {
  final armed = ref.read(lockedArmedCallProvider.notifier);
  if (request.call != null) armed.arm(request);
  final spoken = await answer(request.text);
  if (!spoken) armed.clear();
  return spoken;
}
