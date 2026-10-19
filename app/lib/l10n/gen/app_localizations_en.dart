// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get agentNoticeCancelled => 'Cancelled.';

  @override
  String get agentNoticeGpuFailed =>
      'GPU check failed. Details in the verification log.';

  @override
  String get agentNoticeGpuNoEvidence =>
      'This model provides no GPU evidence. Tap Send without GPU check.';

  @override
  String agentNoticeProfileBroken(Object e) {
    return 'Provider profile faulty: $e';
  }

  @override
  String get agentNoticeRecheckFailed =>
      'The new check was not passed. Details in the verification log.';

  @override
  String get agentNoticeRequestEmpty => 'The request is empty.';

  @override
  String get agentNoticeRequestRunning => 'A request is already running.';

  @override
  String get agentNoticeSetupFirst => 'Please set up a provider first.';

  @override
  String get agentNoticeStartFailed => 'The request could not start.';

  @override
  String agentNoticeUndoFailed(Object e) {
    return 'Undo did not work: $e';
  }

  @override
  String get assistantAnotherService => 'another service';

  @override
  String get assistantChangeInAndroid => 'Change in Android';

  @override
  String get assistantDefaultHint =>
      'A long press on the power button or the assistant gesture opens Wendelin over any app.';

  @override
  String get assistantDefaultTitle => 'Default assistant';

  @override
  String get assistantInactiveDefault =>
      'Android points other apps to Wendelin, but speech recognition is off (switch off). Other apps then get an error.';

  @override
  String get assistantInactiveNotDefault =>
      'Android points other apps to Wendelin, but speech recognition is off: Wendelin is not the default assistant. Other apps then get an error.';

  @override
  String get assistantIsDefault => 'Wendelin is the default assistant';

  @override
  String get assistantNameHint =>
      'Name and personality go to the model as part of the instructions.';

  @override
  String get assistantNameLabel => 'What should Wendelin call you?';

  @override
  String get assistantNotAvailable => 'Not available on this device';

  @override
  String get assistantNotDefault => 'Not set as default assistant';

  @override
  String get assistantOfferRecognizer =>
      'Offer as speech recognition for other apps';

  @override
  String assistantOfferRecognizerUnavailable(String reason) {
    return 'Offer as speech recognition for other apps, $reason';
  }

  @override
  String assistantOtherForNowDefault(String app) {
    return 'Android currently uses $app for other apps. Whether Android switches to Wendelin after you turn it on depends on the device.';
  }

  @override
  String assistantOtherForNowNotDefault(String app) {
    return 'Android currently uses $app for other apps. This may change as soon as Wendelin is the default assistant.';
  }

  @override
  String assistantOtherRecognizer(String app) {
    return 'Android uses $app for other apps. This cannot be changed on this device.';
  }

  @override
  String get assistantPersonaLabel =>
      'Personality, e.g. “answer briefly and casually”';

  @override
  String get assistantRecognizerActiveDetail =>
      'Android uses Wendelin for voice input of other apps. Whisper recognizes on the device, recordings are not stored.';

  @override
  String get assistantRecognizerActiveHint =>
      'Android uses Wendelin for voice input of other apps.';

  @override
  String get assistantRecognizerUnknownDetail =>
      'As long as Wendelin is the default assistant, other apps can use voice input. Whisper recognizes on the device, recordings are not stored.';

  @override
  String get assistantSetDefault => 'Set as default assistant';

  @override
  String get assistantSetLabel => 'set';

  @override
  String get assistantSwitchHint =>
      'If you later switch to another assistant (or “None”), Wendelin’s speech recognition no longer answers other apps. Then choose the voice input again in the Android settings, usually under Apps → Default apps → Digital assistant.';

  @override
  String get conversationOfferHint =>
      'You can change this at any time under Settings → Speech.';

  @override
  String get conversationOfferQuestion =>
      'Should I keep listening after my answers by default?';

  @override
  String reducerBudgetUsed(String name, String spent, String budget) {
    return 'Budget of $name: $spent of $budget used.';
  }

  @override
  String reducerHandedOver(String name) {
    return 'handed over to $name';
  }

  @override
  String get reducerSpokenFallback => 'The displayed version was read aloud.';

  @override
  String get reducerVerificationFailed =>
      'The provider’s answer could not be verified.';

  @override
  String get attCheckFailed => 'Check failed';

  @override
  String get attChecking => 'being checked';

  @override
  String get attE2eeKeyNote =>
      'All content is encrypted with this verified key. The encryption ends at the provider’s gateway (verified enclave), not in the model itself. With NEAR AI it ends in the verified model.';

  @override
  String get attExplainAccept => 'Accept';

  @override
  String attExplainChecked(String what) {
    return 'What is checked: $what';
  }

  @override
  String get attExplainIntro =>
      'What Wendelin checks, what came out of it and what it means for your security.';

  @override
  String attExplainMeaning(String v) {
    return 'Meaning: $v';
  }

  @override
  String attExplainRestrictionsDetail(String v) {
    return '$v: logged only. If you accept this, the chat no longer shows a notice for it.';
  }

  @override
  String get attExplainRestrictionsTitle => 'Restrictions of this provider';

  @override
  String attExplainResult(String detail) {
    return 'Result: $detail';
  }

  @override
  String attExplainStageLine(String label, String result) {
    return '$label · $result';
  }

  @override
  String get attExplainTitle => 'Check details';

  @override
  String get attFailedText =>
      'The response could not be confirmed as unchanged from the verified environment, for example because of a signature error or differing checksums. This may indicate tampering. Do not trust the response. The provider is blocked until you check it again.';

  @override
  String get attFinishBudgetLabel => 'Budget per month in \$ (optional)';

  @override
  String get attFinishImagesNo => '✕ Images';

  @override
  String get attFinishImagesYes => '✓ Images';

  @override
  String get attFinishModelChecked => 'Model checked';

  @override
  String attFinishPercentOfBudget(int v) {
    return '$v % of the budget';
  }

  @override
  String get attFinishPrivacyLevel => 'Privacy level';

  @override
  String attFinishRestrictionNote(String v) {
    return '$v. The provider does not deliver this or Wendelin does not check it, so it is only logged. By tapping “Save” you accept this. Whenever something new is added, Wendelin points it out again. More under “Details”.';
  }

  @override
  String get attFinishTeeYes => '✓ TEE';

  @override
  String get attFinishToolsNo => '✕ Tools';

  @override
  String get attFinishToolsYes => '✓ Tools';

  @override
  String get attFinishWarnFrom => 'Warn at';

  @override
  String get attGpuFailedLabel => 'GPU check failed';

  @override
  String attGpuFailedText(String v) {
    return 'The GPU check via NVIDIA failed.$v The next request to this model will be checked first.';
  }

  @override
  String get attGpuFailedTitle => 'GPU check failed';

  @override
  String get attGpuUnavailableLabel => 'GPU check not possible';

  @override
  String attGpuUnavailableText(String v) {
    return 'The GPU check via NVIDIA was not possible.$v The next request to this model will be checked first.';
  }

  @override
  String get attGpuUnavailableTitle => 'GPU check not possible';

  @override
  String get attLogCommit => 'Commit';

  @override
  String get attLogKeysetDigest => 'Key set digest';

  @override
  String get attLogModel => 'Model';

  @override
  String get attLogNewRestriction => 'New restriction';

  @override
  String attLogNewRestrictionDetail(String v) {
    return '$v: logged only and not yet accepted by you. Under “Details” you can view and accept this.';
  }

  @override
  String get attLogNoEntry => 'There is no entry for this response yet.';

  @override
  String get attLogParticulars => 'Details of the check';

  @override
  String get attLogProvider => 'Provider';

  @override
  String get attLogReasonCode => 'Reason code';

  @override
  String get attLogReceiptId => 'Receipt ID';

  @override
  String get attLogRecheck => 'Check again';

  @override
  String get attLogRecheckFailed => 'The new check did not pass.';

  @override
  String get attLogRechecked => 'Provider checked again, the block is lifted.';

  @override
  String get attLogResultPerStep => 'Result per step';

  @override
  String attLogScreenCommitLine(String repoCommit) {
    return 'Commit $repoCommit';
  }

  @override
  String get attLogScreenDeleteBody =>
      'All entries of the verification log will be deleted. This cannot be undone.';

  @override
  String get attLogScreenDeleteLog => 'Delete verification log';

  @override
  String get attLogScreenDeleteTitle => 'Delete verification log?';

  @override
  String get attLogScreenDeleted => 'Deleted.';

  @override
  String get attLogScreenExportJson => 'Export as JSON';

  @override
  String get attLogScreenFilterAll => 'All';

  @override
  String get attLogScreenFilterGreen => 'Verified';

  @override
  String get attLogScreenFilterRed => 'Failed';

  @override
  String get attLogScreenFilterUnconfirmed => 'Unconfirmed';

  @override
  String get attLogScreenFilterYellow => 'Being checked';

  @override
  String attLogScreenGpuTitle(String v) {
    return 'GPU · $v';
  }

  @override
  String get attLogScreenIntro =>
      'Wendelin checks providers with a protected environment (TEE), and every response. This is what was checked. Never content, only ids, checksums and results.';

  @override
  String get attLogScreenNoEntries => 'No entries.';

  @override
  String attLogScreenReceiptTitle(String v, String providerName) {
    return '$v · $providerName';
  }

  @override
  String get attLogScreenRecheckAttest => 'Check again';

  @override
  String get attLogScreenRechecked => 'Checked again, a block was lifted.';

  @override
  String get attLogScreenSessionGreen => 'Session verified';

  @override
  String get attLogScreenSessionRed => 'Session failed';

  @override
  String attLogScreenSessionTitle(String providerName) {
    return 'Session · $providerName';
  }

  @override
  String get attLogScreenSessionUnconfirmed => 'Session unconfirmed';

  @override
  String get attLogScreenSessionYellow => 'Session cannot be checked';

  @override
  String get attLogTime => 'Time';

  @override
  String get attLogTitle => 'Verification log';

  @override
  String get attLogTitle2 => 'Verification log';

  @override
  String get attMismatchText =>
      'The session’s attestation does not match the signed receipt of this response. Do not trust the response. The provider is blocked until you check it again.';

  @override
  String get attMismatchTitle => 'Possible tampering attempt';

  @override
  String attReasonLead(String reason, String v) {
    return ' Reason: $reason$v';
  }

  @override
  String get attReceiptMissing => 'Receipt missing';

  @override
  String get attReceiptMissingText =>
      'The provider did not deliver a receipt id for this response.';

  @override
  String get attReceiptNotFound => 'Receipt not found';

  @override
  String get attReceiptNotFoundText =>
      'The provider does not know the receipt of this response (not written yet or expired).';

  @override
  String get attReceiptRejectedLabel => 'Receipt rejected';

  @override
  String get attReceiptRejectedText =>
      'The provider rejected the receipt request (for example because of too many requests). The response is unconfirmed, but there is no sign of tampering. Check the provider again.';

  @override
  String get attReceiptRejectedTitle =>
      'Receipt request rejected by the provider';

  @override
  String get attReceiptUnreachable => 'Receipt unreachable';

  @override
  String get attReceiptUnreachableText =>
      'The receipt of this response could not be fetched because of a network or server error.';

  @override
  String get attRelaunchText =>
      'The manufacturer recommends that the operator restart the protected environment so that a security update takes effect. This is no sign of tampering. Check again later.';

  @override
  String get attRelaunchTitle => 'TEE restart recommended at the operator';

  @override
  String get attResponseWord => 'Response';

  @override
  String get attRestrictionOpen => 'verified, new restriction';

  @override
  String get attResultInfo => 'logged only';

  @override
  String get attResultUnavailable => 'unavailable';

  @override
  String get attResultWarn => 'warning';

  @override
  String get attRevokedText =>
      'The manufacturer has revoked the operator’s hardware platform as insecure. Send nothing confidential until the operator has replaced it.';

  @override
  String get attRevokedTitle => 'Operator platform revoked';

  @override
  String get attSCompose => 'Compose hash';

  @override
  String get attSE2eeKey => 'E2EE key verified';

  @override
  String get attSE2eeKeyset => 'Key set of the response';

  @override
  String get attSE2eeRequest => 'Request encryption';

  @override
  String get attSE2eeResponse => 'Response decryption';

  @override
  String get attSEventLog => 'Event log';

  @override
  String get attSFreshness => 'Freshness';

  @override
  String get attSGateway => 'Provider gateway';

  @override
  String get attSGpu => 'GPU evidence';

  @override
  String get attSGpuEvidence => 'GPU evidence of the provider';

  @override
  String get attSKeysetDigest => 'Key set (digest)';

  @override
  String get attSKeysetSignature => 'Key set signature';

  @override
  String get attSNonce => 'Nonce bound';

  @override
  String get attSProvenance => 'Origin (commit)';

  @override
  String get attSQuote => 'TDX quote (DCAP)';

  @override
  String get attSReceiptBinding => 'Receipt bound to session';

  @override
  String get attSReceiptEvents => 'Receipt events';

  @override
  String get attSReceiptFetch => 'Receipt fetched';

  @override
  String get attSReceiptRequest => 'Request hash';

  @override
  String get attSReceiptResponse => 'Response hash';

  @override
  String get attSReceiptSignature => 'Receipt signature';

  @override
  String get attSTcb => 'Platform security level (TCB)';

  @override
  String get attSTls => 'TLS connection verified';

  @override
  String get attSUpstream => 'Upstream check';

  @override
  String get attSUpstreamTcb => 'Upstream security level';

  @override
  String attStagesCardAllPassed(int length) {
    return 'All $length steps passed';
  }

  @override
  String get attStagesCardFirst => 'First attestation';

  @override
  String get attStagesCardNotPassed => 'did not pass';

  @override
  String attStagesCardSomePassed(int failed, int length, String v) {
    return '$failed of $length steps did not pass: $v';
  }

  @override
  String get attStagesCardViewLog => 'View verification log';

  @override
  String attStoredReason(String text, String v) {
    return ' Reason: $text$v';
  }

  @override
  String get attSummaryGreen => 'verified';

  @override
  String get attSummaryYellow => 'pending';

  @override
  String get attTcbText =>
      'The hardware the model runs on has not yet installed a security update from the manufacturer. This is no sign of tampering, but it weakens the protection. The operator has to update. Check again later and send nothing confidential until then.';

  @override
  String get attTcbTitle => 'Security update pending at the operator';

  @override
  String get attUnconfirmed => 'unconfirmed';

  @override
  String attUnconfirmedText(String cause) {
    return '$cause Whether the response comes from the verified environment is unconfirmed. However, no error was found either, and the provider stays usable. Actions waiting for the verified response do not run. Check the provider again.';
  }

  @override
  String get checkStatusFailed => 'failed';

  @override
  String get checkStatusInfo => 'only logged';

  @override
  String get checkStatusNeutral => 'not confirmed';

  @override
  String get checkStatusOk => 'verified';

  @override
  String get checkStatusPending => 'pending';

  @override
  String get gpuBlockNoEvidenceDetail => 'The request was not sent.';

  @override
  String gpuBlockNotSent(String v) {
    return 'Not sent.$v';
  }

  @override
  String get gpuModeAfter => 'After';

  @override
  String get gpuModeAfterText =>
      'The check runs after the answer. If it fails, a notification warns you, the answer is marked red, and the next requests to this model check beforehand. Models without evidence only get a note.';

  @override
  String get gpuModeBefore => 'Before';

  @override
  String get gpuModeBeforeText =>
      'NVIDIA checks the GPU evidence before your request reaches the provider. If the check fails or the provider delivers no evidence, nothing is sent. You can then send once without the GPU check.';

  @override
  String get gpuModeOff => 'Off';

  @override
  String get gpuModeOffText =>
      'Default. Wendelin only checks locally whether the GPU evidence belongs to your request. No call to NVIDIA.';

  @override
  String gpuNoEvidenceFinishText(String hint) {
    return '$hint. The model stays usable. What Wendelin then does is set by the GPU check below: “Off” nothing, “After” only a note, “Before” sends nothing, but you can send once without the GPU check.';
  }

  @override
  String get gpuNoEvidenceFinishTitle => 'No GPU check possible';

  @override
  String get gpuNoEvidenceHint =>
      'No GPU check possible (provider delivers no evidence)';

  @override
  String gpuNoEvidenceMessage(String name) {
    return '$name provides no GPU evidence for this model, so NVIDIA cannot check anything. Because the GPU check is set to “Before”, your request was not sent. You can send it once without the GPU check. The other checks stay active.';
  }

  @override
  String get gpuNoEvidenceTitle => 'No GPU evidence';

  @override
  String gpuNotifyFailedText(String name) {
    return 'The GPU check of the last answer from $name failed. The next request checks beforehand. Details in the verification log.';
  }

  @override
  String get gpuNotifyFailedTitle => 'GPU check failed';

  @override
  String get gpuSectionNote =>
      'For “Before” and “After”, Wendelin calls NVIDIA’s service (nras.attestation.nvidia.com). Only the GPU evidence is sent, no content of your requests or answers.';

  @override
  String get gpuSectionTitle => 'GPU check via NVIDIA';

  @override
  String get gpuToolName => 'GPU check';

  @override
  String shieldSemantics(String label) {
    return 'TEE check: $label';
  }

  @override
  String shieldSemanticsTap(String label) {
    return 'TEE check: $label. Tap for the verification log.';
  }

  @override
  String get stageAgeInfo => 'The age was only logged.';

  @override
  String get stageAgePass =>
      'The attestation is current and not an old recording.';

  @override
  String get stageAgeWhat => 'How old the attestation is.';

  @override
  String get stageComposeInfo =>
      'The hash was logged but not compared against a list of trusted values.';

  @override
  String get stageComposePass =>
      'Exactly the expected programs run in the service.';

  @override
  String get stageComposeWhat =>
      'The compose hash: a checksum of the container description, that is, which programs run in the service.';

  @override
  String get stageE2eeKeyInfo => 'The key was only logged.';

  @override
  String get stageE2eeKeyPass =>
      'Only the verified environment can decrypt the request. With some providers the encryption ends at the gateway, not in the model itself.';

  @override
  String get stageE2eeKeyWhat =>
      'The key Wendelin uses to encrypt your request end to end comes from the hardware attestation.';

  @override
  String get stageE2eeRequestInfo =>
      'The request (or parts such as tool calls) is not additionally encrypted, only protected by the verified connection.';

  @override
  String get stageE2eeRequestPass =>
      'Your request is unreadable to third parties on its way.';

  @override
  String get stageE2eeRequestPinned =>
      'The request (or parts such as tool calls) is not additionally encrypted, only protected by the verified connection.';

  @override
  String get stageE2eeRequestUnpinned =>
      'The request (or parts such as tool calls) is not additionally encrypted, and the connection is not bound to the attestation. This makes the protection weaker.';

  @override
  String get stageE2eeRequestWhat =>
      'Whether the request was actually sent encrypted.';

  @override
  String get stageE2eeResponseInfo => 'The decryption was only logged.';

  @override
  String get stageE2eeResponsePass =>
      'The response came unchanged from the verified environment.';

  @override
  String get stageE2eeResponseWhat =>
      'Whether the response arrived encrypted and could be decrypted.';

  @override
  String get stageEventLogInfo => 'The event log was only logged.';

  @override
  String get stageEventLogPass =>
      'The software that was started can be traced without gaps.';

  @override
  String get stageEventLogWhat =>
      'The event log of the boot: which software was loaded at startup. It must match the hardware measurement.';

  @override
  String get stageFailMeaning =>
      'The check failed. This can indicate tampering or a fault at the provider. Wendelin then sends nothing more to this provider until you check it again.';

  @override
  String get stageGatewayInfo => 'The gateway state was only logged.';

  @override
  String get stageGatewayPass =>
      'The gateway runs with an up-to-date security level.';

  @override
  String get stageGatewayWhat =>
      'The state of the provider’s gateway (the intermediary in front of the model).';

  @override
  String get stageGpuInfo =>
      'The GPU was not checked with NVIDIA because the check is turned off in the settings.';

  @override
  String get stageGpuPass => 'NVIDIA confirms the protected GPU.';

  @override
  String get stageGpuWhat =>
      'The attestation of the graphics card (NVIDIA) the model runs on. Optional, can be turned on in the settings.';

  @override
  String get stageInfoDefault =>
      'The step is only logged, not checked as a requirement.';

  @override
  String get stageKeyBindingInfo => 'The checksum was only logged.';

  @override
  String get stageKeyBindingPass =>
      'The keys come from the verified environment, not from someone in between.';

  @override
  String get stageKeyBindingWhat =>
      'The checksum of the key set (the keys Wendelin encrypts with) must appear in the hardware attestation.';

  @override
  String get stageNonceInfo => 'The number was only logged.';

  @override
  String get stageNoncePass =>
      'The attestation is fresh for this request and not an old recorded one.';

  @override
  String get stageNonceWhat =>
      'A random number that Wendelin sends along and that has to show up again in the attestation.';

  @override
  String get stagePassDefault => 'The step passed.';

  @override
  String get stageProvenanceInfo =>
      'There is no trust list for this provider. Wendelin logs the version but cannot say whether it is trustworthy. If you want to inspect the source code, look up the commit in the verification log.';

  @override
  String get stageProvenancePass =>
      'The software comes from a known, verified version.';

  @override
  String get stageProvenanceWhat =>
      'The origin: which source code version (commit) the running software was built from and whether it is on the trust list.';

  @override
  String get stageQuoteInfo =>
      'The attestation was only logged, not evaluated.';

  @override
  String get stageQuotePass =>
      'The service demonstrably runs in a genuine, isolated Intel TDX environment. The operator cannot read its memory.';

  @override
  String get stageQuoteWhat =>
      'The hardware attestation (TDX quote) of the protected environment. It is signed by the CPU and checked against Intel’s certificates.';

  @override
  String get stageReceiptBindingInfo => 'The binding was only logged.';

  @override
  String get stageReceiptBindingPass => 'Receipt and session match.';

  @override
  String get stageReceiptBindingWhat =>
      'Whether the receipt belongs to the verified session.';

  @override
  String get stageReceiptCompleteInfo => 'The events were only logged.';

  @override
  String get stageReceiptCompletePass => 'The receipt is complete.';

  @override
  String get stageReceiptCompleteWhat =>
      'Whether the receipt contains all required events.';

  @override
  String get stageReceiptFetchInfo => 'The fetch was only logged.';

  @override
  String get stageReceiptFetchPass => 'The provider delivered the receipt.';

  @override
  String get stageReceiptFetchWhat =>
      'Fetching the signed receipt for this response.';

  @override
  String get stageReceiptRequestHashInfo => 'The checksum was only logged.';

  @override
  String get stageReceiptRequestHashPass =>
      'The provider received exactly your request.';

  @override
  String get stageReceiptRequestHashWhat =>
      'The checksum of the request in the receipt compared with what was sent.';

  @override
  String get stageReceiptResponseHashInfo => 'The checksum was only logged.';

  @override
  String get stageReceiptResponseHashPass =>
      'The response was not changed on its way.';

  @override
  String get stageReceiptResponseHashWhat =>
      'The checksum of the response in the receipt compared with what was received.';

  @override
  String get stageReceiptSigInfo => 'The signature was only logged.';

  @override
  String get stageReceiptSigPass =>
      'The receipt comes from the verified environment.';

  @override
  String get stageReceiptSigWhat => 'The signature of the receipt.';

  @override
  String get stageResponseKeyInfo => 'The key set was only logged.';

  @override
  String get stageResponseKeyPass =>
      'The response belongs to the verified session.';

  @override
  String get stageResponseKeyWhat =>
      'Whether the key set of the response matches the verified set.';

  @override
  String get stageResultFail => 'failed';

  @override
  String get stageResultPass => 'passed';

  @override
  String get stageSignatureInfo =>
      'This provider does not deliver such a signature. The keys are bound through the hardware attestation instead (checksum of the key set). This is slightly weaker evidence, but not an error.';

  @override
  String get stageSignaturePass =>
      'The key set is additionally signed by the provider.';

  @override
  String get stageSignatureWhat =>
      'An additional signature over the key set that some providers deliver.';

  @override
  String get stageTcbInfo => 'The security level was only logged.';

  @override
  String get stageTcbPass => 'The platform has all known security updates.';

  @override
  String get stageTcbWhat =>
      'The security level of the platform (TCB): whether firmware and microcode are up to date.';

  @override
  String get stageTlsInfo =>
      'The connection’s certificate was not compared with the attestation. Protection then depends on end-to-end encryption alone.';

  @override
  String get stageTlsPass =>
      'The connection ends in the verified environment; nobody can get in between.';

  @override
  String get stageTlsWhat =>
      'Whether the network connection leads to exactly the key that is in the hardware attestation (pinning).';

  @override
  String get stageUnavailableMeaning =>
      'The check could not be completed (for example because of the network). It will be repeated later. Until then this step is unconfirmed.';

  @override
  String get stageUpstreamInfo => 'The upstream check was only logged.';

  @override
  String get stageUpstreamPass =>
      'The model behind the gateway was demonstrably verified as well.';

  @override
  String get stageUpstreamTcbInfo => 'The level was only logged.';

  @override
  String get stageUpstreamTcbPass => 'This platform is up to date as well.';

  @override
  String get stageUpstreamTcbWhat =>
      'The security level of the platform behind the gateway.';

  @override
  String get stageUpstreamWhat =>
      'Whether the gateway confirms that the model behind it ran in a verified environment.';

  @override
  String get stageWarnMeaning =>
      'The check passed, but with a warning (for example a pending security update at the operator). This weakens the protection somewhat. It stays visible in the verification log.';

  @override
  String get bringApiError => 'Error – interface not reachable';

  @override
  String get bringApp => 'Bring! app';

  @override
  String get bringChecking => 'Checking …';

  @override
  String get bringEmail => 'Email';

  @override
  String get bringFine => 'OK';

  @override
  String get bringInstalled => 'Installed';

  @override
  String get bringIntro =>
      'Unofficial interface: Bring! has not released it for other apps, it can break at any time. Email and password stay in the device’s secure storage.';

  @override
  String get bringNeedCredentials => 'Please enter email and password.';

  @override
  String get bringNotInstalled => 'Not installed';

  @override
  String get bringPassword => 'Password';

  @override
  String get bringReachable => 'Bring! is reachable again.';

  @override
  String get bringShareSend => 'Send to Bring!';

  @override
  String get bringShareSent => 'Sent to Bring!';

  @override
  String get bringShareUnreachable => 'Bring! unreachable';

  @override
  String get bringSignOutBody =>
      'Email, password and session are deleted from the device.';

  @override
  String get bringSignOutTitle => 'Sign out of Bring!?';

  @override
  String get bringSigningIn => 'Signing in …';

  @override
  String get bringStatusAvailable => 'Signed in, integration turned off';

  @override
  String get bringStatusSetup => 'Login missing';

  @override
  String get bringStatusUnavailable => 'Not available';

  @override
  String get bringStatusUnknown => 'Unknown';

  @override
  String get bringUnknown => 'Unknown';

  @override
  String get add => 'Add';

  @override
  String get allow => 'Allow';

  @override
  String get appLanguageDetail =>
      'Language of the interface; independent of speech input and output';

  @override
  String get appLanguageIntro =>
      'Choose the language of the interface. It applies to the whole app and the overlay. The language you speak and hear is set under “Speech”.';

  @override
  String get appLanguageSystem => 'System';

  @override
  String get appLanguageSystemDetail => 'Follows the phone’s language';

  @override
  String get appLanguageTitle => 'App language';

  @override
  String get appName => 'Wendelin';

  @override
  String get back => 'Back';

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get confirmCardNeedsConfirm => 'Needs your confirmation';

  @override
  String confirmCardToolLevel(String toolName, String level) {
    return '$toolName · level $level';
  }

  @override
  String get confirmCardWarning => 'Warning';

  @override
  String get confirmed => 'Confirmed';

  @override
  String get copy => 'Copy';

  @override
  String get delete => 'Delete';

  @override
  String get deny => 'Deny';

  @override
  String get details => 'Details';

  @override
  String get done => 'Done';

  @override
  String get edit => 'Edit';

  @override
  String get error => 'Error';

  @override
  String get export => 'Export';

  @override
  String get followUpListening => 'Still listening …';

  @override
  String get import => 'Import';

  @override
  String get later => 'Later';

  @override
  String get momentPlease => 'One moment …';

  @override
  String get name => 'Name';

  @override
  String get next => 'Next';

  @override
  String get no => 'No';

  @override
  String get off => 'Off';

  @override
  String get ok => 'OK';

  @override
  String get on => 'On';

  @override
  String get open => 'Open';

  @override
  String get remove => 'Remove';

  @override
  String get reset => 'Reset';

  @override
  String get retry => 'Try again';

  @override
  String get save => 'Save';

  @override
  String get search => 'Search';

  @override
  String get selected => 'selected';

  @override
  String get send => 'Send';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get share => 'Share';

  @override
  String get start => 'Start';

  @override
  String get stop => 'Stop';

  @override
  String get test => 'Test';

  @override
  String get understood => 'Understood';

  @override
  String get yes => 'Yes';

  @override
  String get confCallTitle => 'Call?';

  @override
  String get confHintVoiceCall => 'Just say “call” or “cancel”';

  @override
  String get confHintVoiceEdited => 'You changed the text: please tap to send';

  @override
  String get confHintVoiceSms => 'Just say “send” or “cancel”';

  @override
  String get confNoCancel => 'Cancel';

  @override
  String get confSmsNoText => 'The message must not be empty.';

  @override
  String get confSmsTextLabel => 'Message';

  @override
  String get confSmsTitle => 'Send SMS?';

  @override
  String confSmsTo(String name) {
    return 'To $name';
  }

  @override
  String get confYesCall => 'Call';

  @override
  String get confYesSend => 'Send';

  @override
  String get integrationsContactsRationale =>
      'Wendelin needs access to your contacts to find numbers by name, plus the SMS and phone permissions. Android asks you next. Wendelin never sends an SMS or places a call unless you confirmed the preview with name and number first (by tap or by saying “yes”). Neither works while the device is locked. Without the phone permission Wendelin only opens the dialer.';

  @override
  String get batteryAllow => 'Allow no restriction';

  @override
  String get batteryChecklistNote =>
      'Android does not allow reading these settings. This is a checklist, not a status.';

  @override
  String get batteryHuaweiBody =>
      'Set “App launch” for Wendelin to “Manage manually” and allow autostart, secondary launch and background activity.';

  @override
  String get batteryHuaweiTitle => 'Huawei / Honor';

  @override
  String get batteryOnePlusBody =>
      'Allow Wendelin to autostart and set the battery optimization for Wendelin to “Don’t optimize” (Settings → Apps → Wendelin → Battery).';

  @override
  String get batteryOnePlusTitle => 'OnePlus';

  @override
  String get batteryOpenSettings => 'Open battery settings';

  @override
  String get batteryOptimizedDetail =>
      'Android may stop Wendelin in the background. After a long pause the power button may then not open the assistant until you have opened the app once.';

  @override
  String get batteryOptimizedTitle => 'Battery optimization active';

  @override
  String get batteryReliable => 'Open reliably';

  @override
  String get batterySamsungBody =>
      'Remove Wendelin from “Sleeping apps” and set the battery for Wendelin to “Unrestricted” (Settings → Battery → Background usage limits).';

  @override
  String get batterySamsungTitle => 'Samsung';

  @override
  String get batterySettingsNotOpened =>
      'The system settings could not be opened.';

  @override
  String get batteryStandbyDetail =>
      'Android delays background starts for rarely used apps. Open Wendelin now and then or allow “No restriction”.';

  @override
  String get batteryStandbyRare => 'App standby: rarely used';

  @override
  String get batteryStandbyRestricted => 'App standby: restricted';

  @override
  String get batteryVendorSettings => 'Open the manufacturer’s settings';

  @override
  String get batteryXiaomiBody =>
      'Turn on “Autostart” for Wendelin and set the battery saver for Wendelin to “No restrictions” (Settings → Apps → Permissions → Autostart; Settings → Apps → Wendelin → Battery saver).';

  @override
  String get batteryXiaomiTitle => 'Xiaomi / HyperOS / MIUI';

  @override
  String get devDemoMode => 'Demo mode (no provider)';

  @override
  String get devDemoModeLabel => 'Demo mode';

  @override
  String get devGallery => 'Design gallery';

  @override
  String get devSection => 'Development';

  @override
  String get haAddressLabel => 'Address';

  @override
  String get haAlwaysConfirm => 'Always confirm';

  @override
  String get haAlwaysConfirmHelp =>
      'Wendelin asks before every switch (e.g. stove, oven).';

  @override
  String haAlwaysConfirmSemantics(String name, String label) {
    return '$name: $label';
  }

  @override
  String haApproved(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n devices approved',
      one: '1 device approved',
    );
    return '$_temp0';
  }

  @override
  String get haConnect => 'Connect';

  @override
  String get haConnected => 'Connected';

  @override
  String get haConnecting => 'Connecting …';

  @override
  String get haDevices => 'Approve devices';

  @override
  String get haDevicesHelp =>
      'Wendelin only knows the selected devices. Locks, alarm systems and gates always ask first.';

  @override
  String get haDisconnect => 'Disconnect';

  @override
  String get haDisconnectMessage =>
      'Address, token and the device selection are deleted from this device.';

  @override
  String get haDisconnectTitle => 'Disconnect Home Assistant?';

  @override
  String haEntityAlwaysAsks(String entityId) {
    return '$entityId · always asks';
  }

  @override
  String get haErrorTitle => 'Error – not reachable';

  @override
  String get haFilter => 'Filter devices';

  @override
  String get haFound => 'Found';

  @override
  String get haHttpNote =>
      'Unencrypted http is only allowed on the home network, via Tailscale (100.x, *.ts.net) and for *.local, otherwise only https. Nothing is found automatically via Tailscale: enter the address by hand.';

  @override
  String get haInputMissing => 'Please enter address and token.';

  @override
  String get haIntro =>
      'Wendelin controls your approved devices through the API of your Home Assistant. Only on the home network or via Tailscale. Address and token stay in the device’s secure storage.';

  @override
  String get haNoDevices => 'No devices found.';

  @override
  String get haNoRoom => 'No room';

  @override
  String get haNothingFound =>
      'Nothing found. Enter the address by hand (required for Tailscale).';

  @override
  String get haReachable => 'Home Assistant is reachable.';

  @override
  String get haReload => 'Reload devices';

  @override
  String get haSearch => 'Search the Wi-Fi';

  @override
  String get haSearching => 'Searching …';

  @override
  String get haTitle => 'Home Assistant';

  @override
  String get haTokenHelp =>
      'In Home Assistant: Profile → Security → Long-lived access tokens.';

  @override
  String get haTokenLabel => 'Long-lived access token';

  @override
  String get httpArgsAddArg => '+ Argument';

  @override
  String get httpArgsArgs => 'Arguments';

  @override
  String get httpArgsCustomSchema => 'Custom JSON schema';

  @override
  String get httpArgsCustomSchemaDetail => 'Instead of the simple list';

  @override
  String get httpArgsCustomSchemaSem => 'Custom JSON schema';

  @override
  String get httpArgsDescription => 'Description';

  @override
  String get httpArgsRemoveArg => 'Remove argument';

  @override
  String get httpArgsRequired => 'Required';

  @override
  String httpArgsRequiredNamed(String name) {
    return 'Required $name';
  }

  @override
  String get httpArgsSchema => 'JSON schema';

  @override
  String get httpAuthAddSecretHeader => '+ Secret header';

  @override
  String get httpAuthKeepStored => 'Leave empty to keep the stored one';

  @override
  String get httpAuthRemoveSecretHeader => 'Remove secret header';

  @override
  String get httpAuthSecretHeader => 'Secret header, e.g. X-Api-Key';

  @override
  String httpAuthStored(String redactedSecret) {
    return '$redactedSecret stored';
  }

  @override
  String httpEditorDeleteBody(String v) {
    return '“http__$v” and its stored secrets will be deleted.';
  }

  @override
  String get httpEditorDeleteTitle => 'Delete HTTP tool?';

  @override
  String get httpEditorNewTool => 'New HTTP tool';

  @override
  String get httpEditorTool => 'HTTP tool';

  @override
  String httpPhUnknown(String v) {
    return '$v unknown';
  }

  @override
  String get httpRunAskElse => 'Otherwise Wendelin asks before every call';

  @override
  String get httpRunExecution => 'Execution';

  @override
  String get httpRunHomeTarget => 'Home network target';

  @override
  String get httpRunHomeTargetDetail =>
      'May point to private addresses, then http too';

  @override
  String get httpRunHomeTargetSem => 'Home network target';

  @override
  String httpRunLevel(String verb, String name) {
    return 'Level (suggestion for $verb: $name)';
  }

  @override
  String get httpRunNoAsk => 'Run without asking (no undo)';

  @override
  String get httpRunNoAskSem => 'Run without asking';

  @override
  String get httpRunOnlyWrite => 'Only for POST/PUT/PATCH with level write';

  @override
  String get httpRunSensitiveDetail =>
      'Only to providers at the level for sensitive integrations';

  @override
  String get httpRunTimeout => 'Timeout in seconds';

  @override
  String get httpSrcAddHeader => '+ Header';

  @override
  String httpSrcBodyHelp(String example) {
    return '$example is replaced type-correctly; empty = no body';
  }

  @override
  String get httpSrcBodyTemplate => 'Body template (JSON)';

  @override
  String get httpSrcForm => 'Form';

  @override
  String get httpSrcHeader => 'Header';

  @override
  String get httpSrcHeaderDetail => 'Not secret; tokens belong in the sign-in';

  @override
  String get httpSrcJson => 'JSON';

  @override
  String get httpSrcRemoveHeader => 'Remove header';

  @override
  String httpSrcUrlHelp(String example) {
    return 'Placeholders like $example only in path and query, host fixed';
  }

  @override
  String get httpSrcUrlTemplate => 'URL template';

  @override
  String httpTestArgLabel(String name, String type) {
    return '$name ($type)';
  }

  @override
  String get httpTestFailed => 'failed';

  @override
  String httpTestHeaderLine(String key, String value) {
    return '$key: $value';
  }

  @override
  String httpTestHttpStatus(int status) {
    return 'HTTP $status';
  }

  @override
  String httpTestMs(int ms) {
    return '$ms ms';
  }

  @override
  String get httpTestNoResponse => 'No response';

  @override
  String get httpTestRunning => 'Running …';

  @override
  String get httpTestSent => 'Sent';

  @override
  String httpTestSentLine(String method, Object url) {
    return '$method $url';
  }

  @override
  String get httpTestSucceeded => 'succeeded';

  @override
  String get httpTestTruncated => 'truncated';

  @override
  String get httpToolSecModelDescription => 'Description for the model';

  @override
  String get httpToolSecModelDescriptionHelp =>
      'When and what for the model should use the tool';

  @override
  String get httpToolsExportNote =>
      'Export and import contain no secrets. After importing, re-enter tokens and secret headers; “Run without asking” is then off.';

  @override
  String get httpToolsExportPaste => 'Paste export (JSON)';

  @override
  String httpToolsImportFailed(String message) {
    return 'Import failed: $message';
  }

  @override
  String get httpToolsImportTitle => 'Import HTTP tools';

  @override
  String httpToolsImported(int length) {
    String _temp0 = intl.Intl.pluralLogic(
      length,
      locale: localeName,
      other:
          '$length HTTP tools imported. Please re-enter secrets; “Run without asking” is off.',
      one:
          '$length HTTP tool imported. Please re-enter secrets; “Run without asking” is off.',
    );
    return '$_temp0';
  }

  @override
  String get httpToolsIntro =>
      'Custom tools from method, URL template, headers and sign-in, e.g. for Home Assistant or n8n. Responses are data, not instructions.';

  @override
  String get httpToolsOffShort => 'off';

  @override
  String get httpToolsRiskRead => 'reads';

  @override
  String get httpToolsRiskWrite => 'changes without asking, no undo';

  @override
  String get httpToolsSensitiveShort => 'sensitive';

  @override
  String get comingSoonInProgress => 'In progress';

  @override
  String get comingSoonM3 => 'Coming in M3';

  @override
  String get integrationDetailBringAccount => 'Bring! account';

  @override
  String get integrationDetailExternalAsks => 'External effect · always asks';

  @override
  String get integrationDetailIntegrationDetailHaSetup =>
      'Address, token and devices';

  @override
  String get integrationDetailIntegrationDetailSpotifyAccount =>
      'Spotify account';

  @override
  String get integrationDetailLevelAll => 'To all providers';

  @override
  String get integrationDetailLevelEu => 'From EU';

  @override
  String get integrationDetailLevelLocal => 'Local only';

  @override
  String get integrationDetailLevelTee => 'From TEE';

  @override
  String get integrationDetailManageLists => 'Manage lists';

  @override
  String get integrationDetailMemoryHint => 'View, change, export entries';

  @override
  String get integrationDetailNoSearch =>
      'Without a search service Wendelin only reads pages';

  @override
  String get integrationDetailReadsAsks => 'reads · always asks';

  @override
  String get integrationDetailReadsNoAsk => 'reads · no confirmation';

  @override
  String integrationDetailSensitiveLabel(String displayName) {
    return '$displayName sensitive';
  }

  @override
  String get integrationDetailSensitiveNote =>
      'Sensitive: the tools only go to providers at or above the level you set for sensitive integrations.';

  @override
  String get integrationDetailSensitiveTitle => 'Sensitive integrations';

  @override
  String get integrationDetailSetUpSearch => 'Set up search service';

  @override
  String get integrationDetailTapTool =>
      'Tap a tool to turn “Always ask” on or off.';

  @override
  String get integrationDetailTitle => 'Integration';

  @override
  String get integrationDetailVaultDaily => 'Vault and daily notes';

  @override
  String get integrationDetailViewMemory => 'View memory';

  @override
  String get integrationDetailWritesAsks => 'changes · always asks';

  @override
  String get integrationDetailWritesNoUndo =>
      'changes · no confirmation, no undo';

  @override
  String get integrationDetailWritesUndo =>
      'changes · no confirmation, 10 s undo';

  @override
  String integrationTileActiveDetail(String detail) {
    return 'Active · $detail';
  }

  @override
  String get integrationTileAvailable => 'Available';

  @override
  String get integrationTileInStore => 'In the store';

  @override
  String get integrationTileOnlyFrom => 'Only to providers from';

  @override
  String get integrationTileSetupNeeded => 'Setup needed';

  @override
  String get integrationsAddHttp => '+ HTTP tool';

  @override
  String get integrationsAddMcp => '+ MCP server';

  @override
  String get integrationsAppMissing => 'App not installed';

  @override
  String get integrationsCalendarRationale =>
      'Wendelin needs access to your calendars to read, create and change events. Android will ask you right after this. Wendelin always asks before deleting.';

  @override
  String get integrationsHintBring =>
      'Bring! app missing: no fallback via “Share”';

  @override
  String get integrationsHintObsidian =>
      'Obsidian app missing: opening in Obsidian is not possible';

  @override
  String get integrationsHintSpotify =>
      'Spotify app missing: playback only on other devices';

  @override
  String get integrationsIntro =>
      'Only active integrations go to the model. Turned-off ones cost no tokens.';

  @override
  String get integrationsOwn => 'Own integrations';

  @override
  String get integrationsPaused => 'paused';

  @override
  String get integrationsPermission => 'Permission';

  @override
  String get integrationsPermission2 => 'Permission';

  @override
  String integrationsReachable(String displayName) {
    return '$displayName is reachable again.';
  }

  @override
  String integrationsRejected(String reason) {
    return 'Rejected: $reason';
  }

  @override
  String integrationsTools(int tools) {
    return '$tools tools';
  }

  @override
  String get listsAccessLost => 'No access any more – choose the file again';

  @override
  String get listsAdd => '+ List';

  @override
  String get listsAliases => 'Other names, separated by commas (optional)';

  @override
  String listsAlso(String v) {
    return 'also: $v';
  }

  @override
  String get listsChooseFile => 'Choose file';

  @override
  String get listsDeleteBody =>
      'The list disappears from Wendelin. The file is kept.';

  @override
  String get listsDeleteList => 'Delete list';

  @override
  String listsDeleteTitle(String name) {
    return 'Delete “$name”?';
  }

  @override
  String get listsEditList => 'Edit list';

  @override
  String get listsFile => 'File';

  @override
  String get listsIntro =>
      'Each list is a Markdown file on the device (e.g. in the Obsidian vault). Entries appear there as “- [ ] …”.';

  @override
  String get listsListFallback => 'List';

  @override
  String get listsNameHint => 'Name, e.g. Shopping';

  @override
  String get listsNeedNameFile => 'Name and file are required.';

  @override
  String get listsNewFile => 'New file';

  @override
  String get listsNewList => 'New list';

  @override
  String get listsNoAliases => 'No aliases';

  @override
  String get listsNoFile => 'No file yet';

  @override
  String listsSection(String section) {
    return 'Section “$section”';
  }

  @override
  String get listsSectionLabel => 'Section in the file, e.g. Todo (optional)';

  @override
  String get listsTaskDefault => 'Default task list';

  @override
  String get listsTaskDefaultDetail =>
      'Tasks with a due date go here when no list is named.';

  @override
  String get integrationsLocationRationale =>
      'To tell you where you are and to prepare distances and navigation, Wendelin needs location access. Android asks you next. Wendelin only reads your location when you ask for it (never in the background), does not send it to cloud models below your privacy level and does not write it to the audit log. “Approximate” is enough for place names and straight-line distance.';

  @override
  String confHandOverDetail(String toName, String fromName) {
    return '$toName has a lower privacy level than $fromName. Your request and the conversation so far will then go there.';
  }

  @override
  String confHandOverTitle(String toName) {
    return 'Hand over to $toName?';
  }

  @override
  String get confHintTap => 'Answer with a tap';

  @override
  String get confHintVoice => 'Just say “yes” or “no”';

  @override
  String confMoreLines(int rest) {
    return '… $rest more lines';
  }

  @override
  String get confYesHandOver => 'Yes, hand over';

  @override
  String get mainCancelListening => 'Stop listening';

  @override
  String get mainCheckProvider => 'Check provider';

  @override
  String mainCostLabel(String costLabel) {
    return 'Cost $costLabel';
  }

  @override
  String mainCostToday(String v) {
    return 'today $v';
  }

  @override
  String get mainDeleteEventTitle => 'Delete event?';

  @override
  String mainFollowUpCountdown(String followUpListeningText, int seconds) {
    return '$followUpListeningText $seconds s';
  }

  @override
  String mainGpuBlockMessage(String name, String v) {
    return 'The GPU check of $name via NVIDIA failed or is not possible.$v Your request was not sent. You can send it once without the GPU check. The other checks stay active.';
  }

  @override
  String get mainGpuCheckFailedTitle => 'GPU check failed';

  @override
  String get mainListening => 'Listening …';

  @override
  String get mainMicCancelAnswer => 'Cancel answer';

  @override
  String get mainMicSpeak => 'Speak';

  @override
  String get mainMicStopListening => 'Stop listening';

  @override
  String get mainMicStopSpeech => 'Stop speech output';

  @override
  String get mainMicUnavailable => 'Microphone unavailable';

  @override
  String get mainNeedsModel =>
      'Wendelin needs a language model. Set up a provider with your API key, then you can get started.';

  @override
  String get mainNewConversation => 'New conversation';

  @override
  String get mainNoKeep => 'No, keep';

  @override
  String get mainNoProviderYet => 'No provider set up yet';

  @override
  String mainProviderProfileUnusable(String error) {
    return 'The provider profile cannot be used: $error';
  }

  @override
  String get mainReallyDeleteTitle => 'Really delete?';

  @override
  String get mainSendWithoutGpuCheck => 'Send without GPU check';

  @override
  String get mainSetUpProvider => 'Set up provider';

  @override
  String get mainShouldIDoThat => 'Should I do that?';

  @override
  String get mainStartDemo => 'Start demo without provider';

  @override
  String get mainToday => 'Today';

  @override
  String get mainTypeInstead => 'Type instead of speaking';

  @override
  String get mainViewRouting => 'View routing';

  @override
  String get mainYesDelete => 'Yes, delete';

  @override
  String get mainYesDoIt => 'Yes, do it';

  @override
  String get mainYesterday => 'Yesterday';

  @override
  String get overlayCloseAssistant => 'Close assistant';

  @override
  String get overlayEnd => 'End';

  @override
  String get overlayFollowUpComing =>
      'Conversation mode off · can be turned on in settings';

  @override
  String overlayFollowUpWindow(int seconds) {
    return 'Still listening for $seconds s · “Stop” ends it';
  }

  @override
  String get overlayKeepTalking => 'Keep talking';

  @override
  String get overlayLockedText =>
      'On the lock screen Wendelin shows and says nothing from your data. Only the flashlight also works while locked. Everything else only after unlocking.';

  @override
  String get overlayLockedTitle => 'Unlock device';

  @override
  String get overlayTextInput => 'Text input';

  @override
  String get overlayUnlock => 'Unlock';

  @override
  String privateBannerConfidential(String since) {
    return 'Confidential: memory used (since $since)';
  }

  @override
  String privateBannerPrivate(String since) {
    return 'Conversation private (since $since)';
  }

  @override
  String privateEscalationMemory(String since, String toName) {
    return 'The conversation uses your memory (since $since). With “Yes” $toName sees the history so far, but not the memory itself.';
  }

  @override
  String privateEscalationPrivate(String since, String toName) {
    return 'The conversation is private (since $since). With “Yes” $toName also sees its private parts.';
  }

  @override
  String get switchTopicBody =>
      'Switching the model starts a new conversation. The current history is ended (it stays available in the history).';

  @override
  String get switchTopicBodyRunning =>
      'Switching the model starts a new conversation. The running answer is cancelled and the current history is ended (it stays available in the history).';

  @override
  String get switchTopicSwitch => 'Switch';

  @override
  String get switchTopicTitle => 'Start a new conversation?';

  @override
  String get mcpAddClientId => 'Client ID (optional)';

  @override
  String get mcpAddClientIdHint =>
      'Leave empty: Wendelin registers itself with the server';

  @override
  String get mcpAddConfirmAll => 'Confirm all tools';

  @override
  String get mcpAddConfirmAllHint => 'Every call asks';

  @override
  String get mcpAddCustom => 'Custom server';

  @override
  String get mcpAddHeaderLabel => 'Header, e.g. X-Api-Key';

  @override
  String get mcpAddProblem => 'Problem';

  @override
  String get mcpAddSensitive => 'Sensitive';

  @override
  String get mcpAddSensitiveHint =>
      'Tools only to providers at or above the set level';

  @override
  String get mcpAddServerAddress => 'Address';

  @override
  String get mcpAddServerInsecure =>
      'Unencrypted (http): only allowed in the home network or via Tailscale';

  @override
  String get mcpAddServerIntro =>
      'Choose a template or enter your own server. Reachable via https or in the home network (Tailscale, WireGuard).';

  @override
  String get mcpAddServerTestConnection => 'Test connection';

  @override
  String get mcpAddServerTitle => 'Add server';

  @override
  String get mcpAddSignIn => 'Sign-in';

  @override
  String get mcpAddTokenHint => 'Will never be shown again';

  @override
  String get mcpAddValue => 'Value';

  @override
  String get mcpAddValueHint => 'Will never be shown again';

  @override
  String get mcpCheckHeaderMissing => 'Please enter the name of the header.';

  @override
  String get mcpCheckNameMissing => 'Please enter a name.';

  @override
  String get mcpCheckPlaceholders =>
      'Please replace the placeholders in <…> in the address.';

  @override
  String get mcpCheckUrlIncomplete =>
      'Please enter a complete address (https://…).';

  @override
  String get mcpDetailActive => 'Server active';

  @override
  String mcpDetailActiveLabel(String name) {
    return '$name active';
  }

  @override
  String get mcpDetailAuthLabel => 'Sign-in required';

  @override
  String get mcpDetailBearer => 'Bearer token';

  @override
  String mcpDetailCheck(String v) {
    return 'Check: $v';
  }

  @override
  String mcpDetailCheck2(String v) {
    return 'Check: $v';
  }

  @override
  String get mcpDetailConfirmAll => 'Confirm all tools';

  @override
  String get mcpDetailConfirmAllHint =>
      'Every call asks, whatever the server states';

  @override
  String get mcpDetailDelete => 'Delete server';

  @override
  String get mcpDetailDeleteBody =>
      'Configuration, tool list and all credentials of this server will be removed.';

  @override
  String get mcpDetailDeleteHint =>
      'Removes configuration, tool list and credentials';

  @override
  String mcpDetailDeleteTitle(String name) {
    return 'Delete “$name”?';
  }

  @override
  String mcpDetailIntro(String url) {
    return 'Tool arguments go to this server: $url';
  }

  @override
  String get mcpDetailIntroHint =>
      'Tap a tool for confirmation and risk level. MCP tools have no undo: changes happen on the server.';

  @override
  String mcpDetailLastCheck(String v) {
    return 'Last check: $v';
  }

  @override
  String get mcpDetailNeverShown => 'Will never be shown again';

  @override
  String get mcpDetailNoTools => 'No tools yet';

  @override
  String get mcpDetailNoToolsHint => 'Turn the server on or reload';

  @override
  String get mcpDetailOauthHint => 'OAuth sign-in in the browser';

  @override
  String mcpDetailReplaceHeader(String header) {
    return 'Replace header $header';
  }

  @override
  String get mcpDetailReplaceToken => 'Replace token';

  @override
  String get mcpDetailSensitive => 'Sensitive';

  @override
  String get mcpDetailSensitiveHint =>
      'Personal data: tools only to providers at or above the set level';

  @override
  String mcpDetailSensitiveLabel(String name) {
    return '$name sensitive';
  }

  @override
  String get mcpDetailSignIn => 'Sign in';

  @override
  String get mcpDetailSignInAgain => 'Sign in again';

  @override
  String get mcpDetailSignOut => 'Sign out';

  @override
  String get mcpDetailSignOutHint => 'Forgets the tokens on this device';

  @override
  String get mcpDetailTools => 'Tools';

  @override
  String get mcpDetailUnreachableLabel => 'unreachable';

  @override
  String mcpDetailValueFor(String header) {
    return 'Value for $header';
  }

  @override
  String get mcpDetailValueNeverShown => 'Value will never be shown again';

  @override
  String get mcpLabelsAlwaysAsks => 'always asks';

  @override
  String get mcpLabelsAsksNoUndo => 'asks · no undo';

  @override
  String get mcpLabelsAuthAfterSave =>
      'Sign-in required – sign in after saving';

  @override
  String get mcpLabelsAuthCheck => 'Sign-in required – check token or header';

  @override
  String get mcpLabelsAuthRequired => 'Sign-in required';

  @override
  String get mcpLabelsChanges => 'changes';

  @override
  String get mcpLabelsCredentialsMissing => 'Credentials missing';

  @override
  String get mcpLabelsExternal => 'External effect';

  @override
  String get mcpLabelsHintDestructive =>
      'Server: destructive (destructiveHint)';

  @override
  String get mcpLabelsHintNonDestructive =>
      'Server: changes, not destructive (destructiveHint: false)';

  @override
  String get mcpLabelsHintNone =>
      'Server: no information – treated as external effect';

  @override
  String get mcpLabelsHintReadOnly => 'Server: read-only (readOnlyHint)';

  @override
  String get mcpLabelsNetworkHint => 'Is Tailscale/WireGuard active?';

  @override
  String get mcpLabelsNoAsk => 'no confirmation';

  @override
  String get mcpLabelsNoAskNoUndo => 'no confirmation · no undo';

  @override
  String get mcpLabelsNotChecked => 'Not checked yet';

  @override
  String get mcpLabelsOneTool => '1 tool';

  @override
  String get mcpLabelsProtocolError => 'not a valid MCP server';

  @override
  String mcpLabelsProtocolErrorDetail(String v) {
    return 'Not a valid MCP server: $v';
  }

  @override
  String get mcpLabelsProtocolErrorShort => 'Not a valid MCP server';

  @override
  String get mcpLabelsReachable => 'Reachable';

  @override
  String get mcpLabelsReads => 'reads';

  @override
  String get mcpLabelsReload => 'Reload';

  @override
  String get mcpLabelsReplaceToken => 'Replace token';

  @override
  String get mcpLabelsSetUp => 'Set up';

  @override
  String get mcpLabelsSignIn => 'Sign in';

  @override
  String get mcpLabelsSignInAgain => 'Sign in again';

  @override
  String get mcpLabelsSignInMissing => 'Sign-in missing';

  @override
  String mcpLabelsTools(int tools) {
    return '$tools tools';
  }

  @override
  String get mcpLabelsUnreachable => 'unreachable';

  @override
  String mcpLabelsUnreachableDetail(String v, String mcpUnreachableHint) {
    return 'Unreachable: $v. $mcpUnreachableHint';
  }

  @override
  String mcpLabelsUnreachableShort(String mcpUnreachableHint) {
    return 'Unreachable · $mcpUnreachableHint';
  }

  @override
  String mcpSecretCheck(String v) {
    return 'Check: $v';
  }

  @override
  String get mcpSecretSaved => 'Saved';

  @override
  String mcpSecretSignInFailed(String message) {
    return 'Sign-in failed: $message';
  }

  @override
  String mcpSecretSignInOnServer(String name) {
    return '“$name”: sign in on the server side';
  }

  @override
  String get mcpSecretSignedIn => 'Signed in';

  @override
  String get mcpServersAdd => '+ Server';

  @override
  String get mcpServersContent => 'Content of the export file';

  @override
  String get mcpServersExportHint => 'Server list without tokens and passwords';

  @override
  String get mcpServersImportHint => 'Credentials will be asked for again';

  @override
  String get mcpServersImportTitle => 'Import server list';

  @override
  String mcpServersImported(int length) {
    return '$length servers imported (turned off)';
  }

  @override
  String get mcpServersImportedOne => '1 server imported (turned off)';

  @override
  String get mcpServersIntro =>
      'Tools from MCP servers, e.g. on the home server via Tailscale. Tool arguments go to the respective server.';

  @override
  String get mcpServersNone => 'No server yet';

  @override
  String get mcpServersNoneHint =>
      'Choose a template or enter your own address';

  @override
  String get mcpToolAlwaysAsk => 'Always ask';

  @override
  String get mcpToolAlwaysAsk2 => 'Always ask';

  @override
  String get mcpToolAlwaysAskHint => 'every call is confirmed';

  @override
  String get mcpToolConfirmAllOn =>
      '“Confirm all tools” is on: every call asks.';

  @override
  String get mcpToolDefaultNoUndo => 'Default: no undo possible';

  @override
  String mcpToolEffective(String v) {
    return 'Effective: $v';
  }

  @override
  String get mcpToolExternalAsks =>
      'External effect: always asks, this cannot be relaxed.';

  @override
  String get mcpToolNoAsk => 'No confirmation';

  @override
  String get mcpToolNoAsk2 => 'No confirmation';

  @override
  String get mcpToolNoUndoNow =>
      'No undo: the change happens immediately on the server';

  @override
  String get mcpToolReadsOnly => 'reads only';

  @override
  String mcpToolServerChecked(String v) {
    return 'Only checked by the server: $v';
  }

  @override
  String toolChipSemantics(String toolName, String status) {
    return 'Tool $toolName, $status';
  }

  @override
  String toolResultUndoCountdown(int seconds) {
    return 'Undo · $seconds s';
  }

  @override
  String toolResultUndoSemantics(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds seconds',
      one: '$seconds second',
    );
    return 'Undo, $_temp0 left';
  }

  @override
  String get toolResultUndone => 'Undone';

  @override
  String get toolTlsEncrypted => 'Tools end-to-end encrypted';

  @override
  String get toolTlsHint =>
      'Tool calls are protected by the verified connection up to the enclave, but not additionally encrypted.';

  @override
  String get integrationsMediaRationale =>
      'To tell you what is playing and to skip within an audiobook or podcast, Wendelin needs “Notification access”. Android opens that page next: pick Wendelin in the list and turn it on (on newer Android versions, first choose “Allow restricted settings” in the app info). Wendelin does not read notifications, only media playback. Pause, resume and back work without it.';

  @override
  String get obsIndexBuilding => 'Building index …';

  @override
  String obsIndexBuildingProgress(int indexed, int pending) {
    return 'Building index: $indexed notes, $pending to go';
  }

  @override
  String obsIndexCurrent(String notes) {
    return '$notes in the index · up to date';
  }

  @override
  String obsIndexIncomplete(String error) {
    return 'Index incomplete: $error';
  }

  @override
  String get obsIndexNotBuilt => 'Not built yet';

  @override
  String obsIndexNotes(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n notes',
      one: '1 note',
    );
    return '$_temp0';
  }

  @override
  String obsIndexPartial(String notes) {
    return '$notes in the index · vault too large, only partly';
  }

  @override
  String obsIndexUnreadable(String notes, int failed) {
    return '$notes in the index · $failed unreadable';
  }

  @override
  String get obsidianAccessGranted => 'Access granted';

  @override
  String get obsidianAccessGranted2 => 'Access granted';

  @override
  String get obsidianAccessLost =>
      'No access any more – choose the folder again';

  @override
  String get obsidianBuildIndex => 'Build index';

  @override
  String get obsidianChooseFolder => 'Choose the folder of your Obsidian vault';

  @override
  String get obsidianChooseOther => 'Choose another folder';

  @override
  String get obsidianChooseVaultFolder => 'Choose vault folder';

  @override
  String get obsidianDailyNotes => 'Daily notes';

  @override
  String get obsidianDailySaved => 'Daily notes saved.';

  @override
  String get obsidianDateFormat => 'Date format as in Obsidian';

  @override
  String get obsidianFolder => 'Folder';

  @override
  String get obsidianFolderHint =>
      'Leave empty = vault root. New daily notes go into this folder.';

  @override
  String get obsidianIndexBuilding => 'Index is being built';

  @override
  String get obsidianIndexHint =>
      'Updated automatically (at start and before every search). The button is only needed for the first build.';

  @override
  String get obsidianIntro =>
      'Wendelin reads and adds notes directly in the vault folder. Sync stays with Obsidian Sync, Syncthing or Git.';

  @override
  String get obsidianNoAccess => 'no access';

  @override
  String get obsidianNoVault => 'No vault chosen';

  @override
  String get obsidianRemoveBody =>
      'Wendelin loses access to the folder. The notes themselves stay unchanged.';

  @override
  String get obsidianRemoveTitle => 'Remove vault?';

  @override
  String get obsidianRemoveVault => 'Remove vault';

  @override
  String get obsidianSaveDaily => 'Save daily notes';

  @override
  String get obsidianSearchIndex => 'Search index';

  @override
  String get obsidianTemplate => 'Template (optional)';

  @override
  String get obsidianTemplateHint => 'Templates/Daily note';

  @override
  String obsidianToday(String path) {
    return 'Today: $path';
  }

  @override
  String obsidianUnusable(String message) {
    return 'Not usable: $message';
  }

  @override
  String obsidianUnusable2(String message) {
    return 'Not usable: $message';
  }

  @override
  String get obsidianVault => 'Vault';

  @override
  String get onboardingConversation => 'Conversation';

  @override
  String get onboardingConversationIntro =>
      'Should Wendelin keep listening briefly after its answers, so you can follow up without tapping? You can change this any time under Settings → Voice.';

  @override
  String get onboardingDemoNoProvider => 'Demo without provider';

  @override
  String get onboardingInterfaceLanguage => 'App language of the interface';

  @override
  String get onboardingKeepListening => 'Yes, keep listening';

  @override
  String get onboardingLanguageModel => 'Language model';

  @override
  String get onboardingLearnAndEnable => 'Train and turn on';

  @override
  String get onboardingPermissionsIntro =>
      'Only turn on what you need. Android asks for permissions only now, when you switch them on.';

  @override
  String get onboardingProviderIntro =>
      'Wendelin needs a provider, for example Claude with your API key or your own model on a home server.';

  @override
  String get onboardingSetUpAnotherProvider => 'Set up another provider';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingTapOnly => 'No, only after tapping';

  @override
  String get onboardingWakeIntro =>
      'Wendelin can listen for “Wendelin” even while the phone is lying around. To do that, it first learns your voice (about 3 minutes). You can also do this later in Settings.';

  @override
  String get onboardingWakeWord => 'Wake word';

  @override
  String get onboardingWelcome => 'Welcome';

  @override
  String get onboardingWelcomeIntro =>
      'Wendelin is your voice assistant. Setup takes six steps. Which language do you speak with it?';

  @override
  String get onboardingWhatMayWendelinDo => 'What may Wendelin do?';

  @override
  String get auditEntrySession => 'Session';

  @override
  String get auditEntryVerifications => 'Verifications of this session';

  @override
  String get auditLogIntro =>
      'What Wendelin did. Never keys. The export contains no texts, only times, kinds and results.';

  @override
  String get auditLogTitle => 'Audit log';

  @override
  String get memoryCatFact => 'Fact';

  @override
  String get memoryCatPerson => 'Person';

  @override
  String get memoryCatPreference => 'Preference';

  @override
  String get memoryCatProject => 'Project';

  @override
  String memoryDeleteTooltip(String text) {
    return 'Delete: $text';
  }

  @override
  String get memoryEditTitle => 'Edit entry';

  @override
  String get memoryExportMd => 'Export as Markdown';

  @override
  String get memoryForget => 'Forget';

  @override
  String get memoryForgetTitle => 'Forget entry?';

  @override
  String memoryFromPrivate(String label) {
    return 'From a private request: only goes to providers from $label.';
  }

  @override
  String get memoryIntro =>
      'Wendelin only remembers what you explicitly ask for. Passwords, PINs, card and account numbers are never stored.';

  @override
  String get memoryLift => 'Lift';

  @override
  String memoryLiftBody(String text, String level) {
    return '“$text” comes from a private request and so far only goes to providers from $level. Afterwards all providers that may see the memory can see it.';
  }

  @override
  String get memoryLiftLimit => 'Lift lower limit';

  @override
  String get memoryLiftTitle => 'Lift the lower limit?';

  @override
  String get memoryNone => 'No entries yet.';

  @override
  String memoryPrivateFrom(String v, String label) {
    return '$v · private, only from $label';
  }

  @override
  String get memoryTitle => 'Memory';

  @override
  String get privacyLevelEu => 'EU';

  @override
  String get privacyLevelLocal => 'local';

  @override
  String privacyLevelSemantics(String text, String level) {
    return '$text, privacy level $level';
  }

  @override
  String get privacyLevelStandard => 'Standard';

  @override
  String get privacyLevelTee => 'TEE';

  @override
  String privacyScreenDays(int d) {
    return '$d days';
  }

  @override
  String get privacyScreenDeleteAll => 'Delete everything';

  @override
  String get privacyScreenDeleteAllBody =>
      'All conversation histories, the verification log and the trained voices (wake word) will be deleted. This cannot be undone. Memory and settings are kept.';

  @override
  String get privacyScreenDeleteAllTitle => 'Delete everything?';

  @override
  String get privacyScreenDeleteHistory => 'Delete histories and log';

  @override
  String privacyScreenEntries(int n) {
    return '$n entries';
  }

  @override
  String get privacyScreenGeneralLog => 'General verification log';

  @override
  String get privacyScreenIntro =>
      'Histories and the verification log stay on the device. Wendelin deletes older entries automatically.';

  @override
  String get privacyScreenKindConfirmation => 'Confirmation';

  @override
  String get privacyScreenKindEscalation => 'Escalation';

  @override
  String get privacyScreenKindRequest => 'Request';

  @override
  String get privacyScreenKindTool => 'Tool';

  @override
  String get privacyScreenKindVerification => 'Verification';

  @override
  String get privacyScreenManyEntries => '200+ entries';

  @override
  String get privacyScreenOneEntry => '1 entry';

  @override
  String get privacyScreenOneYear => '1 year';

  @override
  String get privacyScreenProtectScreen => 'Protect screen content';

  @override
  String get privacyScreenProtectScreenHint =>
      'No screenshots, hidden in the app switcher. The assistant overlay is always protected.';

  @override
  String get privacyScreenRetention => 'Retention';

  @override
  String get privacyScreenTeeLog => 'TEE verification log';

  @override
  String get privacyScreenTeeLogHint =>
      'Verification of providers with a protected environment, GPU check via NVIDIA';

  @override
  String privacyScreenUndone(String v, String v2) {
    return '$v · undone · $v2';
  }

  @override
  String get areaAssistant => 'Assistant';

  @override
  String get areaAssistantDetail => 'Default assistant, your name, personality';

  @override
  String get areaCosts => 'Costs';

  @override
  String get areaCostsDetail => 'Today and this month per provider';

  @override
  String get areaHttpTools => 'HTTP tools';

  @override
  String get areaHttpToolsDetail => 'Define and test your own tools';

  @override
  String get areaIntegrations => 'Integrations';

  @override
  String get areaIntegrationsDetail =>
      'What Wendelin may do, tools, risk levels';

  @override
  String get areaMcp => 'MCP servers';

  @override
  String get areaMcpDetail => 'Servers, sign-in, status, tools';

  @override
  String get areaPrivacy => 'Privacy and logs';

  @override
  String get areaPrivacyDetail => 'Retention, audit log, export';

  @override
  String get areaProvider => 'Providers';

  @override
  String get areaProviderDetail => 'Profiles, default, budget';

  @override
  String get areaRouting => 'Routing';

  @override
  String get areaRoutingDetail => 'Rules, test field, import and export';

  @override
  String get areaSpeech => 'Speech';

  @override
  String get areaSpeechDetail => 'Speech recognition, voice, pace';

  @override
  String get costsIntro =>
      'Based on the prices in the model catalog, in US dollars.';

  @override
  String costsMonth(String v) {
    return 'month $v';
  }

  @override
  String get costsNoProviders => 'No providers yet.';

  @override
  String costsOfBudget(String v) {
    return 'of $v';
  }

  @override
  String costsToday(String v) {
    return 'today $v';
  }

  @override
  String providerChipLevel(String level) {
    return 'Privacy level $level';
  }

  @override
  String providerChipReceipt(String status) {
    return 'Receipt $status';
  }

  @override
  String providerChipSemantics(String name) {
    return 'Provider $name';
  }

  @override
  String get providerSetupBudgetFormat =>
      'Budget: amount in dollars, e.g. 5 or 2.50';

  @override
  String get providerSetupConnected => 'Connection established';

  @override
  String get providerSetupConnectedEnterModel =>
      'Connected. Please enter the model ID.';

  @override
  String providerSetupConnectedModels(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Connected, $n models found.',
      one: 'Connected, 1 model found.',
    );
    return '$_temp0';
  }

  @override
  String get providerSetupConnectionFailed => 'Connection failed';

  @override
  String get providerSetupEditTitle => 'Edit provider';

  @override
  String get providerSetupIntroCredentials =>
      'The key is only stored in the device’s secure storage.';

  @override
  String get providerSetupIntroFinish =>
      'Privacy level and optionally a monthly budget.';

  @override
  String get providerSetupIntroModel => 'Choose the default model.';

  @override
  String get providerSetupIntroTemplate =>
      'Choose who Wendelin should talk to.';

  @override
  String providerSetupModelListFailed(String reason) {
    return 'Model list not available ($reason). Please enter the model ID.';
  }

  @override
  String get providerSetupModelListUnavailable => 'Model list not available';

  @override
  String get providerSetupModelUnusable => 'Model not usable';

  @override
  String providerSetupModelsFound(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n models found',
      one: '1 model found',
    );
    return '$_temp0';
  }

  @override
  String get providerSetupNoModelList =>
      'No model list. Please enter the model ID.';

  @override
  String get providerSetupProviderSetupApiKeyOptional => 'API key (optional)';

  @override
  String get providerSetupProviderSetupBaseUrl => 'Base URL';

  @override
  String get providerSetupProviderSetupCreateKey =>
      'Create key at the provider';

  @override
  String get providerSetupProviderSetupModelId => 'Model ID';

  @override
  String get providerSetupProviderSetupModels => 'Models';

  @override
  String get providerSetupProviderSetupOtherTemplate => 'Other template';

  @override
  String get providerSetupProviderSetupProbeModel => 'Check model';

  @override
  String get providerSetupProviderSetupTestConnection => 'Test connection';

  @override
  String get providerSetupProviderSetupTesting => 'Testing …';

  @override
  String get providersAdd => '+ Provider';

  @override
  String providersBudget(String v) {
    return 'Budget $v/month';
  }

  @override
  String get providersChoice => 'Provider choice';

  @override
  String get providersDeleteBody => 'Profile and stored key are removed.';

  @override
  String providersDeleteTitle(String name) {
    return 'Delete “$name”?';
  }

  @override
  String providersError(String error) {
    return 'Error: $error';
  }

  @override
  String get providersIntro =>
      'The default gets every request for which no routing rule applies. If it fails, Wendelin says so clearly and never switches to another provider on its own.';

  @override
  String get providersMakeDefault => 'Make default';

  @override
  String get providersNone => 'No provider set up yet.';

  @override
  String get providersProfiles => 'Profiles';

  @override
  String get providersRoutingHint => 'Rules for choosing the provider';

  @override
  String get targetPickerApply => 'Apply';

  @override
  String get targetPickerProfile => 'Profile';

  @override
  String targetPickerProfileGone(String profileId) {
    return 'Profile “$profileId” no longer exists.';
  }

  @override
  String get condBuilderAddCondition => '+ Condition';

  @override
  String get condBuilderAddConditionInGroup => '+ Condition in group';

  @override
  String get condBuilderAddGroup => '+ Group';

  @override
  String get condBuilderAll => 'all (and)';

  @override
  String get condBuilderAny => 'any (or)';

  @override
  String get condBuilderApplies => 'It applies';

  @override
  String get condBuilderCategory => 'Category';

  @override
  String get condBuilderConfidenceBelow => 'Confidence below';

  @override
  String get condBuilderEmptyGroup => 'A group is empty.';

  @override
  String condBuilderFail(String label, String m) {
    return '$label: $m';
  }

  @override
  String get condBuilderFrom => 'from (HH:MM)';

  @override
  String get condBuilderGroup => 'Group';

  @override
  String get condBuilderLanguages => 'Languages';

  @override
  String get condBuilderLanguagesHint => 'de, fr';

  @override
  String get condBuilderMetered => 'mobile data';

  @override
  String get condBuilderMoreChars => 'More characters than';

  @override
  String get condBuilderNeedCategory => 'enter a category.';

  @override
  String get condBuilderNeedLang => 'enter a language code (de, fr …).';

  @override
  String get condBuilderNeedLength => 'enter a number of characters.';

  @override
  String get condBuilderNeedPattern => 'enter a pattern.';

  @override
  String get condBuilderNeedThreshold => 'enter a threshold between 0 and 1.';

  @override
  String get condBuilderNeedTime => 'enter a time as HH:MM.';

  @override
  String get condBuilderNeedWord => 'enter at least one word.';

  @override
  String get condBuilderPattern => 'Pattern (on normalized text)';

  @override
  String get condBuilderRemoveCondition => 'Remove condition';

  @override
  String get condBuilderRemoveGroup => 'Remove group';

  @override
  String get condBuilderSentenceStart =>
      'Words at the start of the sentence, separated by commas';

  @override
  String get condBuilderSentenceStartHint => 'Claude';

  @override
  String get condBuilderTo => 'to (HH:MM)';

  @override
  String get condBuilderUnknownType => 'unknown type.';

  @override
  String get condBuilderWords => 'Words, separated by commas';

  @override
  String get condBuilderWordsHint => 'private, confidential';

  @override
  String get routingAllDay => 'all day';

  @override
  String routingApplies(String target, String private) {
    return 'applies → $target$private';
  }

  @override
  String get routingCondAnd => 'and';

  @override
  String get routingCondImage => 'With image';

  @override
  String get routingCondKeyword => 'Keyword';

  @override
  String get routingCondLanguage => 'Language';

  @override
  String get routingCondLong => 'Long input';

  @override
  String get routingCondNetwork => 'Network';

  @override
  String get routingCondNot => 'not';

  @override
  String get routingCondOr => 'or';

  @override
  String get routingCondPrefix => 'Prefix';

  @override
  String get routingCondPrivate => 'Private';

  @override
  String get routingCondRegex => 'Regular expression';

  @override
  String get routingCondTime => 'Time window';

  @override
  String get routingCondTool => 'Needs tool';

  @override
  String get routingCondUncertain => 'Uncertain recognition';

  @override
  String get routingDefault => 'Default';

  @override
  String routingDeleted(String profileId) {
    return '$profileId (deleted)';
  }

  @override
  String routingImportBody(int length, int before) {
    return '$length rules replace the previous $before. Nothing changes until you tap “Replace”.';
  }

  @override
  String routingImportDefaultMissing(String profileId) {
    return 'The default profile “$profileId” does not exist here; the previous default stays.';
  }

  @override
  String get routingImportEscalations =>
      'The file contains escalation chains. They were skipped: Wendelin never switches the model on its own.';

  @override
  String get routingImportReplace => 'Replace';

  @override
  String get routingImportTitle => 'Import rules?';

  @override
  String routingPrivateRuleNotice(String target) {
    return 'New: rule “Private” – requests with “private”, “confidential” … go to $target.';
  }

  @override
  String get routingPrivateSuffix => ' · private';

  @override
  String routingRuleN(int n) {
    return 'Rule $n';
  }

  @override
  String get routingScreenAddRule => '+ Add rule';

  @override
  String get routingScreenDefaultTarget => 'Default target';

  @override
  String get routingScreenFirstWins => 'First matching rule wins';

  @override
  String routingScreenImportFailed(String message) {
    return 'Import not possible: $message';
  }

  @override
  String routingScreenMoveRule(String name) {
    return 'Move rule “$name”';
  }

  @override
  String get routingScreenNeedsProvider =>
      'Routing needs a provider. Set one up first.';

  @override
  String routingScreenReadError(String error) {
    return 'The rules cannot be read: $error';
  }

  @override
  String get routingScreenResetBody =>
      'The saved rules are discarded and recreated from the provider settings.';

  @override
  String get routingScreenResetRules => 'Reset rules';

  @override
  String get routingScreenResetTitle => 'Reset rules?';

  @override
  String routingScreenRuleOff(String name) {
    return '$name (off)';
  }

  @override
  String routingScreenSkipped(String name, String v) {
    return '“$name” skipped: $v';
  }

  @override
  String get routingScreenTestHint => 'Which rule applies to this sentence?';

  @override
  String get routingScreenTestSentence => 'Test sentence';

  @override
  String get routingSkipDisabled => 'turned off';

  @override
  String get routingSkipInvalid => 'invalid';

  @override
  String get routingSkipNoMatch => 'does not match';

  @override
  String get routingSkipProfileDisabled => 'profile disabled';

  @override
  String get routingSkipProfileMissing => 'profile deleted';

  @override
  String get routingSkipProfileUnavailable => 'profile unavailable';

  @override
  String get routingWeekdayFri => 'Fr';

  @override
  String get routingWeekdayMon => 'Mo';

  @override
  String get routingWeekdaySat => 'Sa';

  @override
  String get routingWeekdaySun => 'Su';

  @override
  String get routingWeekdayThu => 'Th';

  @override
  String get routingWeekdayTue => 'Tu';

  @override
  String get routingWeekdayWed => 'We';

  @override
  String get ruleEditorActive => 'Active';

  @override
  String get ruleEditorActiveLabel => 'Rule active';

  @override
  String get ruleEditorCondition => 'Condition';

  @override
  String get ruleEditorDeleteBody =>
      'Requests that used this rule so far check the next rules or go to the default.';

  @override
  String get ruleEditorDeleteRule => 'Delete rule';

  @override
  String ruleEditorDeleteTitle(String v) {
    return 'Delete rule “$v”?';
  }

  @override
  String get ruleEditorEditRule => 'Edit rule';

  @override
  String get ruleEditorNeedModel => 'Please enter a model.';

  @override
  String get ruleEditorNeedName => 'Please enter a name.';

  @override
  String get ruleEditorNewRule => 'New rule';

  @override
  String get ruleEditorRebuild => 'Rebuild';

  @override
  String get ruleEditorRule => 'Rule';

  @override
  String get ruleEditorStripTrigger => 'Remove trigger';

  @override
  String get ruleEditorStripTriggerHint =>
      'Prefix, keyword or match do not go to the model; the sentence stays complete in the history.';

  @override
  String get ruleEditorStripTriggerLabel => 'Remove trigger';

  @override
  String get ruleEditorTarget => 'Target';

  @override
  String get ruleEditorTooDeep =>
      'This condition is nested deeper than the editor can edit. It stays unchanged.';

  @override
  String get ruleTileMove => 'Move';

  @override
  String ruleTileSemanticsLevel(String level) {
    return 'Privacy level $level,';
  }

  @override
  String get spotifyAppNote =>
      'The Spotify app is needed so Wendelin can play on this phone: if it is not running, Wendelin starts it. On other devices (speakers, computers) Wendelin plays without it.';

  @override
  String get spotifyAppTitle => 'Spotify app';

  @override
  String get spotifyClientIdLabel => 'Client ID';

  @override
  String get spotifyClientIdMissing => 'Please enter the client ID.';

  @override
  String get spotifyCopied => 'Address copied.';

  @override
  String get spotifyCopyRedirect => 'Copy address';

  @override
  String get spotifyFailed =>
      'Error – sign-in expired or Spotify not reachable';

  @override
  String get spotifyGuideStep1 =>
      '1. Sign in at developer.spotify.com/dashboard with your Spotify account and choose “Create app”.';

  @override
  String spotifyGuideStep2(String redirect) {
    return '2. Choose any name and description. Enter exactly this address as “Redirect URI”: $redirect';
  }

  @override
  String get spotifyGuideStep3 =>
      '3. Under “Which API/SDKs are you planning to use?” tick “Web API” and save.';

  @override
  String get spotifyGuideStep4 =>
      '4. Under “Settings” copy the “Client ID” and enter it below. In development mode your own account must be listed under “User Management”.';

  @override
  String get spotifyGuideTitle => 'Create a developer app';

  @override
  String get spotifyIntro =>
      'Wendelin controls Spotify through the official API. This needs a Spotify Premium account and your own (free) developer app. Client ID and sign-in stay in the device’s secure storage.';

  @override
  String get spotifyReconnected => 'Spotify is reachable again.';

  @override
  String get spotifyRetrying => 'Checking …';

  @override
  String get spotifySignIn => 'Sign in to Spotify';

  @override
  String get spotifySignOut => 'Sign out';

  @override
  String get spotifySignOutMessage =>
      'Client ID and sign-in are deleted from this device.';

  @override
  String get spotifySignOutTitle => 'Sign out of Spotify?';

  @override
  String get spotifySignedIn => 'Signed in';

  @override
  String get spotifySigningIn => 'Signing in …';

  @override
  String get spotifyStateActive => 'Signed in · Active';

  @override
  String get spotifyStateLoginMissing => 'Sign-in missing';

  @override
  String get spotifyStateOff => 'Signed in, integration switched off';

  @override
  String get spotifyStateUnavailable => 'Not available';

  @override
  String get spotifyTitle => 'Spotify';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'Français';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get modelRowDeleteBody =>
      'The model is removed from the device and has to be downloaded again before the next use.';

  @override
  String modelRowDeleteTitle(String displayName) {
    return 'Delete $displayName?';
  }

  @override
  String modelRowLoaded(String size) {
    return '$size · downloaded';
  }

  @override
  String modelRowNotLoaded(String size) {
    return '$size · not downloaded';
  }

  @override
  String modelRowProgressOf(String displayName) {
    return 'Progress $displayName';
  }

  @override
  String get modelRowResume => 'Resume';

  @override
  String modelRowStarted(String size) {
    return '$size · partially downloaded';
  }

  @override
  String get voiceConvAdvanced => 'Advanced';

  @override
  String get voiceConvBargeInUnavailable =>
      'Not available: Wendelin needs the wake word model for this, which is not built in yet.';

  @override
  String get voiceConvBargeKeywords => 'Keywords';

  @override
  String get voiceConvBargeSpeech => 'Any speech (experimental)';

  @override
  String get voiceConvCustomBarge =>
      'Custom setting for interrupting is active (can be reset under “Advanced”).';

  @override
  String get voiceConvInterrupt => 'Interrupt during the answer';

  @override
  String get voiceConvInterruptHint =>
      'With “Wendelin” or “Stop” you interrupt the speech output.';

  @override
  String get voiceConvKeepListening => 'Keep listening after the answer';

  @override
  String get voiceConvKeepListeningDetail =>
      'After the spoken answer the microphone stays open briefly, so you can follow up without tapping. “Thanks” or “Stop” ends it.';

  @override
  String get voiceConvKeepListeningLabel => 'Keep listening after the answer';

  @override
  String get voiceDownloadAnd => ' and ';

  @override
  String voiceDownloadBundled(String displayName, String v) {
    return '$displayName is included and is downloaded too ($v). “small” recognizes German, French and names much better and is recommended. “base” is fast and meant for weak devices. More models: Settings → Voice.';
  }

  @override
  String get voiceDownloadContinueInBackground =>
      'Keep loading in the background';

  @override
  String get voiceDownloadContinueLoading => 'Continue loading';

  @override
  String get voiceDownloadIntro =>
      'Wendelin recognizes speech on the device, without internet and without Google. Pick the model and download it once, preferably on Wi-Fi.';

  @override
  String get voiceDownloadLoad => 'Load';

  @override
  String get voiceDownloadLoadAgain => 'Load again';

  @override
  String get voiceDownloadLoading => 'Loading …';

  @override
  String voiceDownloadLoadingPercent(String v) {
    return 'Loading … $v %';
  }

  @override
  String voiceDownloadLoadingPercentOf(String v, String size) {
    return 'Loading … $v % of $size';
  }

  @override
  String voiceDownloadPreselectedBase(String v) {
    return '“base” is preselected because the device has little memory ($v GB). “small” needs much more memory while recognizing.';
  }

  @override
  String get voiceDownloadProgressLabel => 'Speech recognition progress';

  @override
  String get voiceDownloadReady => 'Ready';

  @override
  String voiceDownloadSizeLoaded(String size) {
    return '$size · loaded';
  }

  @override
  String voiceDownloadSizeMb(String v) {
    return '$v MB';
  }

  @override
  String voiceDownloadSizePartial(String size) {
    return '$size · partially loaded';
  }

  @override
  String voiceDownloadStillNeeded(String v) {
    return 'Still needed: $v';
  }

  @override
  String get voiceDownloadTitle => 'Load speech recognition';

  @override
  String get voiceDownloadUnpacking => 'Unpacking …';

  @override
  String get voiceErrorGeneric => 'Speech did not work. Please try again.';

  @override
  String get voiceErrorMicBusy =>
      'The microphone was still busy. Please speak again.';

  @override
  String get voiceErrorModelMissing =>
      'A speech model has not been downloaded yet (Settings → Speech).';

  @override
  String get voiceScreenAutomatic => 'Automatic';

  @override
  String get voiceScreenAutomaticDetail =>
      'System voice, otherwise offline voice';

  @override
  String get voiceScreenDetectAuto => 'Detect automatically';

  @override
  String get voiceScreenFineTuning => 'Fine tuning';

  @override
  String get voiceScreenFixedLanguageHint =>
      'With a fixed language Whisper recognizes short sentences more reliably.';

  @override
  String get voiceScreenIntro =>
      'Wendelin recognizes speech on the device (Whisper). The models are downloaded once and stay on the device.';

  @override
  String get voiceScreenLanguageDefault => 'Default of the language';

  @override
  String get voiceScreenLanguageDefaultChip => 'Default of the language';

  @override
  String get voiceScreenLearnsVoice => 'Wendelin learns your voice';

  @override
  String get voiceScreenLearnsVoiceDetail => 'Train, calibrate and try out';

  @override
  String voiceScreenLikeApp(String v) {
    return 'Like the app ($v)';
  }

  @override
  String get voiceScreenListen => 'Listen to a sample';

  @override
  String get voiceScreenMicrophone => 'Microphone';

  @override
  String get voiceScreenMicrophoneTitle => 'Microphone';

  @override
  String get voiceScreenMinSpeech => 'Minimum speech duration';

  @override
  String get voiceScreenMinSpeechDetail =>
      'Shorter noises (clicks, breaths) are ignored.';

  @override
  String get voiceScreenModelLicenses => 'Licenses of the speech models';

  @override
  String voiceScreenMs(int v) {
    return '$v ms';
  }

  @override
  String get voiceScreenNoOfflineVoice =>
      'No offline voice loaded for this language – Wendelin speaks with the system voice.';

  @override
  String get voiceScreenNoSpeech =>
      'No speech output available: answers only appear on the screen. Download an offline voice.';

  @override
  String get voiceScreenNoSystemVoice =>
      'No system voice installed – Wendelin speaks with the offline voice.';

  @override
  String get voiceScreenNotAllowed => 'not allowed';

  @override
  String get voiceScreenOfflineVoice => 'Offline voice';

  @override
  String get voiceScreenOfflineVoices => 'Offline voices';

  @override
  String get voiceScreenOverlay => 'Assistant overlay';

  @override
  String get voiceScreenRecognition => 'Speech recognition';

  @override
  String get voiceScreenRecognitionHint =>
      'For voice input Wendelin needs the selected Whisper model and voice activity detection.';

  @override
  String voiceScreenRecommendSmall(String v) {
    return 'Recommended: small (more accurate), download $v.';
  }

  @override
  String get voiceScreenSensitivity => 'Speech recognition sensitivity';

  @override
  String get voiceScreenSensitivityDetail =>
      'Silero VAD threshold: lower picks up quieter sounds, higher ignores more noise.';

  @override
  String get voiceScreenSpeaksOffline =>
      'Wendelin speaks with the offline voice.';

  @override
  String get voiceScreenSpeaksSystem =>
      'Wendelin speaks with the system voice.';

  @override
  String get voiceScreenSpeechOutput => 'Speech output';

  @override
  String get voiceScreenSpokenLanguage => 'Spoken language';

  @override
  String get voiceScreenStopClosesOverlay => 'Stop closes the overlay';

  @override
  String get voiceScreenStopClosesOverlayHint =>
      'If you say “Stop”, Wendelin briefly shows “Cancelled” and closes the overlay.';

  @override
  String get voiceScreenStopClosesOverlayLabel => 'Stop closes the overlay';

  @override
  String get voiceScreenSystemVoice => 'System voice';

  @override
  String get voiceScreenSystemVoiceTitle => 'System voice';

  @override
  String get voiceScreenTempo => 'Tempo';

  @override
  String get voiceScreenVoice => 'Voice';

  @override
  String get voiceScreenVoiceAndTempo => 'Voice and tempo';

  @override
  String voiceScreenVoiceLanguage(String v, String language) {
    return '$v ($language)';
  }

  @override
  String get voiceScreenVoices => 'Voices';

  @override
  String get voiceScreenVoicesDetail =>
      'One female and one male voice per language';

  @override
  String get voiceSpokenAlwaysDetail =>
      'Wendelin first writes a short spoken text and always reads that aloud, even after content from the web or from third parties.';

  @override
  String get voiceSpokenAlwaysTitle => 'Always own spoken version';

  @override
  String get voiceSpokenAlwaysWarning =>
      'What is read aloud may differ from what is on the screen.';

  @override
  String get voiceSpokenCheckedDetail =>
      'After content from the web or from third parties, another model call checks whether the spoken text and the answer match. Speech output then starts a little later and costs a little more.';

  @override
  String get voiceSpokenCheckedTitle => 'With AI check';

  @override
  String get voiceSpokenOffDetail =>
      'Wendelin reads the displayed answer aloud, only prepared for pronunciation.';

  @override
  String get voiceSpokenProtectedDetail =>
      'Own spoken text, but after content from the web or from third parties Wendelin reads the displayed answer aloud.';

  @override
  String get voiceSpokenProtectedTitle => 'Protected';

  @override
  String voiceSpokenSemantic(String label) {
    return 'Spoken version $label';
  }

  @override
  String get voiceSpokenTitle => 'Spoken version';

  @override
  String get voiceUnavailableHint =>
      'Download speech recognition: Settings → Speech';

  @override
  String get voiceVoicesIntro =>
      'Choose the offline voice for each language. Only downloaded voices use storage; you can delete the ones you do not need.';

  @override
  String voiceVoicesNotLoaded(String v) {
    return 'The chosen voice is not downloaded – $v speaks instead.';
  }

  @override
  String get voiceVoicesPreparing => 'Preparing sample …';

  @override
  String get voiceVoicesSampleFailed =>
      'Sample not possible – the voice did not speak.';

  @override
  String get voiceVoicesStopSample => 'Stop sample';

  @override
  String bargeDebugDefaultSuffix(String v) {
    return '$v (default)';
  }

  @override
  String get bargeDebugExtraThreshold => 'Additional threshold';

  @override
  String get bargeDebugHelpCommunication =>
      'Communication + AEC (default): The phone subtracts its own output from the microphone signal. Wendelin barely hears itself, but your word arrives a bit quieter.';

  @override
  String get bargeDebugHelpMargin =>
      'The threshold sets how exactly a word has to match. Higher (0.05, default): fewer false alarms, but your word is missed more often. Lower (0.00 or -0.05): the word is recognized more easily, but there are more false alarms.';

  @override
  String get bargeDebugHelpRecognition =>
      'Recognition, without AEC: no echo cancellation. Your word arrives clearly, but the running announcement often drowns it out, and Wendelin can hear itself.';

  @override
  String get bargeDebugHelpRecognitionAec =>
      'Recognition + AEC: like the default, but with the speech recognition microphone. Helps on devices where the default microphone dampens your word too much.';

  @override
  String get bargeDebugIntro =>
      'Sets how sensitively “Wendelin” and “Stop” are recognized during the answer. The change applies from the next spoken answer.';

  @override
  String get bargeDebugMicCommunication => 'Communication + AEC (default)';

  @override
  String get bargeDebugMicDuring => 'Microphone during the answer';

  @override
  String get bargeDebugMicRecognition => 'Recognition, without AEC';

  @override
  String get bargeDebugMicRecognitionAec => 'Recognition + AEC';

  @override
  String get bargeDebugTitle => 'Advanced: interrupting';

  @override
  String get micAllowTitle => 'Allow the microphone?';

  @override
  String get micAndroidSettings => 'Android settings';

  @override
  String get micExplanation =>
      'Wendelin only listens after you have triggered it (microphone button or assistant). The recording is converted to text on the device and never leaves it; only the recognized text goes to your provider.';

  @override
  String get micNotNow => 'Not now';

  @override
  String micOnlyText(String v) {
    return 'Without a microphone only text works. $v';
  }

  @override
  String get micSettingsHint =>
      'Allow it in the Android settings under Apps → Wendelin.';

  @override
  String get wakeCalibrateCancelled => 'Cancelled. Nothing was changed.';

  @override
  String get wakeCalibrateDone => 'Calibrated.';

  @override
  String wakeCalibrateFailed(Object error) {
    return 'Failed: $error';
  }

  @override
  String get wakeCalibrateFinishNow => 'Finish now';

  @override
  String get wakeCalibrateIntro =>
      'Put the phone down and keep talking normally. Wendelin listens along (microphone indicator on) but remembers only numeric values, no audio and no text. Now and then it beeps: then say “Wendelin”.';

  @override
  String get wakeCalibrateMicPreparing => 'Preparing the microphone …';

  @override
  String wakeCalibrateMinutesLeft(int v) {
    return '$v min left';
  }

  @override
  String get wakeCalibrateNoMic =>
      'Without a microphone Wendelin cannot calibrate.';

  @override
  String get wakeCalibrateNotDistinct =>
      'Your recordings do not stand out from the background. Please train your voice again. The old threshold stays.';

  @override
  String get wakeCalibrateProgressLabel => 'Calibration progress';

  @override
  String wakeCalibratePrompts(int answered, int prompts) {
    return 'Prompts: $answered of $prompts answered';
  }

  @override
  String wakeCalibrateResult(String v, String v2, int v3) {
    return 'Threshold $v · estimated $v2 false alarms per hour (before verification) · $v3 % of your recordings recognized.';
  }

  @override
  String get wakeCalibrateTitle => 'Calibrate';

  @override
  String get wakeCalibrateUnusable => 'Not usable.';

  @override
  String get wakeEnrollAllThere => 'All recordings are in.';

  @override
  String wakeEnrollFailed(Object error) {
    return 'Training failed: $error';
  }

  @override
  String get wakeEnrollHeard => 'Heard.';

  @override
  String wakeEnrollIntro(String word) {
    return 'Say “$word” when it is your turn. Wendelin keeps only numeric values from each recording; the audio is discarded immediately.';
  }

  @override
  String get wakeEnrollMicPreparing => 'Preparing the microphone …';

  @override
  String get wakeEnrollNoMic =>
      'Without a microphone Wendelin cannot learn your voice.';

  @override
  String get wakeEnrollNoSpeech => 'Heard nothing. Once more, please.';

  @override
  String get wakeEnrollProcessing => 'Processing …';

  @override
  String wakeEnrollProgress(int accepted, int target) {
    return '$accepted of $target';
  }

  @override
  String get wakeEnrollProgressLabel => 'Training progress';

  @override
  String get wakeEnrollPrompt0 =>
      'Speak normally, with the phone close to you.';

  @override
  String get wakeEnrollPrompt1 => 'Now from one to two meters away.';

  @override
  String get wakeEnrollPrompt2 =>
      'Now quietly, like in the evening in your room.';

  @override
  String get wakeEnrollPrompt3 =>
      'The way you say it every day, maybe from another corner.';

  @override
  String wakeEnrollSaveWith(int accepted) {
    return 'Save with $accepted recordings';
  }

  @override
  String wakeEnrollSayNow(String word) {
    return 'Say now: “$word”';
  }

  @override
  String get wakeEnrollTitle => 'Train voice';

  @override
  String get wakeEnrollTitleStop => 'Train “Stop”';

  @override
  String get wakeEnrollTooEarly =>
      'Started too early. Wait a moment, then speak.';

  @override
  String wakeEnrollTooLong(String word) {
    return 'Too long. Only “$word”, please.';
  }

  @override
  String get wakeEnrollTooQuiet => 'Too quiet. A bit louder, please.';

  @override
  String get wakeExplainBatteryBody =>
      'Constant listening costs battery. The default is therefore “Only while charging”.';

  @override
  String get wakeExplainBatteryExemptBody =>
      'So that Android does not stop the service, Wendelin should be exempt from battery optimization.';

  @override
  String get wakeExplainBatteryExemptTitle =>
      'Exempt from battery optimization?';

  @override
  String get wakeExplainBatteryTitle => 'Battery';

  @override
  String wakeExplainChecklist(String v, String v2) {
    return '$v: $v2';
  }

  @override
  String get wakeExplainEnable => 'Turn on';

  @override
  String get wakeExplainEnableTitle => 'Turn on wake word?';

  @override
  String get wakeExplainExempt => 'Exempt';

  @override
  String get wakeExplainLocalBody =>
      'Recognizing the word runs on the device. What you say after “Wendelin” is sent as text to the chosen AI provider. Audio is neither sent nor stored.';

  @override
  String get wakeExplainLocalTitle => 'Listening stays on the device';

  @override
  String get wakeExplainMicDotBody =>
      'Android shows the green microphone dot while the service is listening.';

  @override
  String get wakeExplainMicDotTitle => 'Microphone dot';

  @override
  String get wakeExplainPersistentBody =>
      'While Wendelin is listening, Android shows a notification. From Android 14 you can swipe it away; the service keeps running. Without the notification permission Android shows none; Wendelin still listens.';

  @override
  String get wakeExplainPersistentTitle => 'Persistent notification';

  @override
  String get wakeModelsLoadModel => 'Load speech model';

  @override
  String wakeModelsNeedsModel(String v) {
    return 'The speech model must be loaded first ($v).';
  }

  @override
  String wakeModelsVerifyNeeds(String v) {
    return 'To double-check, load the speech model ($v).';
  }

  @override
  String get wakeServiceSectionAlways => 'Always';

  @override
  String get wakeServiceSectionAlwaysHint => 'Noticeably drains the battery.';

  @override
  String get wakeServiceSectionBackground => 'Listening in the background';

  @override
  String get wakeServiceSectionChime => 'Confirmation sound';

  @override
  String get wakeServiceSectionChimeDetail =>
      'A short sound when Wendelin has recognized the word.';

  @override
  String get wakeServiceSectionChooseAssistant => 'Choose assistant';

  @override
  String get wakeServiceSectionEnable => 'Turn on wake word';

  @override
  String get wakeServiceSectionEnableDetail =>
      'Wendelin listens in the background for “Wendelin”.';

  @override
  String get wakeServiceSectionEndedEngine => 'Ended: recognition failed';

  @override
  String get wakeServiceSectionEndedNoPermission =>
      'Ended: microphone permission missing';

  @override
  String get wakeServiceSectionEndedNoRole =>
      'Ended: Wendelin is no longer your assistant';

  @override
  String get wakeServiceSectionEndedNotCharging =>
      'Ended: the device is no longer charging';

  @override
  String get wakeServiceSectionEndedPaused => 'Ended: paused';

  @override
  String get wakeServiceSectionEndedSystem => 'Ended by the system';

  @override
  String get wakeServiceSectionEndedTimeout =>
      'Ended by the system (Android time limit)';

  @override
  String get wakeServiceSectionEnrollFirst => 'Train your voice first';

  @override
  String get wakeServiceSectionEnrollFirstBody =>
      'Without a trained voice, Wendelin does not recognize the wake word.';

  @override
  String get wakeServiceSectionNotAssistant => 'Wendelin is not your assistant';

  @override
  String get wakeServiceSectionNotAssistantBody =>
      'Android only allows the default assistant to listen in the background. Choose Wendelin as your assistant.';

  @override
  String get wakeServiceSectionOnlyCharging => 'Only while charging';

  @override
  String get wakeServiceSectionOnlyChargingHint => 'Saves battery (default).';

  @override
  String get wakeServiceSectionPausedLoading =>
      'Paused: waiting for it to load';

  @override
  String wakeServiceSectionPausedUntil(String v) {
    return 'Paused until $v';
  }

  @override
  String get wakeServiceSectionRunning => 'Running';

  @override
  String get wakeServiceSectionSettingsFail =>
      'The system settings could not be opened.';

  @override
  String get wakeServiceSectionSoundCheck => 'Sound and verification';

  @override
  String get wakeServiceSectionStatus => 'Status';

  @override
  String get wakeServiceSectionToEnroll => 'Start training';

  @override
  String get wakeServiceSectionWhen => 'When to listen?';

  @override
  String get wakeServiceSectionWhisper => 'Verification with Whisper';

  @override
  String get wakeServiceSectionWhisperDetail =>
      'Wendelin only listens if Whisper confirms “Wendelin”. Turn it off if it is too strict for your voice; there will be more false triggers then.';

  @override
  String wakeTestAgo(String v, int inSeconds) {
    return '$v · $inSeconds s';
  }

  @override
  String wakeTestBest(String v, String v2) {
    return '$v · highest similarity $v2';
  }

  @override
  String wakeTestCandidate(String v) {
    return 'Candidate · similarity $v';
  }

  @override
  String get wakeTestConfirmed => 'Verification: confirmed';

  @override
  String wakeTestFailed(Object error) {
    return 'Failed: $error';
  }

  @override
  String get wakeTestIntro =>
      'Say “Wendelin”. Hits appear here without the overlay opening. “Candidate” is the voice, “confirmed” the verification with Whisper.';

  @override
  String get wakeTestListening => 'Listening';

  @override
  String get wakeTestMicPreparing => 'Preparing the microphone …';

  @override
  String get wakeTestNoHit => 'No hit yet.';

  @override
  String get wakeTestNoMic => 'The test does not work without a microphone.';

  @override
  String get wakeTestRejected => 'Verification: not confirmed';

  @override
  String get wakeTestStopped => 'Stopped';

  @override
  String get wakeTestTitle => 'Try it';

  @override
  String get wakeTestUnavailable => 'Verification: not possible (no Whisper)';

  @override
  String get wakeTestVerifying => 'Verification running …';

  @override
  String wakeWordActionsFor(String v) {
    return 'Actions for $v';
  }

  @override
  String get wakeWordCalibrate => 'Calibrate (30 min, recommended)';

  @override
  String get wakeWordDeleteAll => 'Delete all voices';

  @override
  String get wakeWordDeleteAllBody =>
      'Wendelin forgets all trained voices. You can train them again later.';

  @override
  String get wakeWordDeleteAllTitle => 'Delete all voices?';

  @override
  String get wakeWordEnroll => 'Train voice';

  @override
  String get wakeWordEnrollMore => 'Train another person';

  @override
  String get wakeWordFeatureModels => 'Feature models';

  @override
  String get wakeWordInterrupt => 'Interrupt with “Stop”';

  @override
  String get wakeWordIntro =>
      'Wendelin learns your voice: you say “Wendelin” about 15 times, after that it also recognizes it in everyday use. Only numeric values are stored, encrypted on the device. Audio is never stored.';

  @override
  String get wakeWordLearned => 'Trained voices';

  @override
  String get wakeWordNameOptional => 'Name (optional)';

  @override
  String get wakeWordNeedsModel => 'The speech model must be loaded first.';

  @override
  String get wakeWordNoVoice => 'No voice yet';

  @override
  String get wakeWordNoVoiceHint => 'Train your voice with “Train voice”.';

  @override
  String wakeWordPerson(int number) {
    return 'Person $number';
  }

  @override
  String wakeWordRecordingsThreshold(int length, String v, String v2) {
    return '$length recordings · threshold $v$v2';
  }

  @override
  String get wakeWordRetrain => 'Train again';

  @override
  String get wakeWordRetrainStop => 'Train “Stop” again';

  @override
  String get wakeWordStopLearned =>
      '“Stop” is trained: you can interrupt the announcement with “Stop” alone.';

  @override
  String get wakeWordStopNotLearned =>
      'Without a trained “Stop”, only “Wendelin, stop” interrupts the announcement. Train “Stop” so you can interrupt the announcement with the single word.';

  @override
  String get wakeWordStopOnlySpeaking =>
      '“Stop” only works while Wendelin is speaking and interruption is set to “Keywords”. In the background, “Stop” triggers nothing.';

  @override
  String get wakeWordTemplatesMissing =>
      'Templates missing. Please train again.';

  @override
  String get wakeWordTrainStop => 'Train “Stop”';

  @override
  String get wakeWordTryNow => 'Try it now';

  @override
  String get wakeWordWhoCalibrate => 'Whom to calibrate?';

  @override
  String get wakeWordWhoJoins => 'Who is joining?';

  @override
  String get wakeWordWhoSpeaks => 'Who is speaking?';

  @override
  String get wakeWordWhoStop => 'Who trains “Stop”?';

  @override
  String get weatherHomeHelp =>
      'Used when you name no place and the location is not known. Leave empty = no home place.';

  @override
  String get weatherHomeLabel => 'Home place, e.g. Kiel';

  @override
  String get weatherIntro =>
      'All weather services are free and need no key. Sea data (waves, water temperature) always comes from Open-Meteo.';

  @override
  String get weatherKindBrightSkyDetail => 'Data of the German Weather Service';

  @override
  String get weatherKindMetNorwayDetail =>
      'Norwegian weather service, worldwide';

  @override
  String get weatherKindOpenMeteoDetail => 'Default, worldwide';

  @override
  String weatherNotFound(String name) {
    return 'Place “$name” not found.';
  }

  @override
  String get weatherSearchFailed =>
      'Place search not reachable, try again later.';

  @override
  String get weatherSetupDetail =>
      'Choose a service, set the place for “weather here”';

  @override
  String get weatherSetupTitle => 'Weather service and home place';

  @override
  String get weatherTitle => 'Weather and sea';

  @override
  String get webSearchAddress => 'Address, e.g. https://search.example.org';

  @override
  String get webSearchAddressMissing =>
      'Please enter the address of the instance.';

  @override
  String get webSearchApiKey => 'API key';

  @override
  String get webSearchIntro =>
      'Without a search service Wendelin can only read pages whose address you give.';

  @override
  String get webSearchKeyMissing => 'Please enter the API key.';

  @override
  String get webSearchKeySaved => 'Key saved – leave empty to keep it';

  @override
  String get webSearchNone => 'No search service';

  @override
  String get webSearchOwnInstance => 'SearXNG (own instance)';

  @override
  String get webSearchTitle => 'Web search';
}
