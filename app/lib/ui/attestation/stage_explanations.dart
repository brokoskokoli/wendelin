import '../../l10n/l10n.dart';

/// What one check stage does and what its outcome means (WP78). Plain
/// words for the „Details“ page; the result of the check itself comes from
/// the log, not from here.
final class StageExplanation {
  /// Creates the explanation.
  const StageExplanation({
    required this.what,
    required this.ifPass,
    required this.ifInfo,
  });

  /// What is checked.
  final String what;

  /// What a pass means for security.
  final String ifPass;

  /// What it means when the stage is only logged (the provider does not
  /// deliver it, or the app does not check it).
  final String ifInfo;
}

/// Explanation of [stage] (stage id such as `quote`), or `null` if unknown.
StageExplanation? stageExplanationFor(AppLocalizations l, String stage) =>
    _explanations(l)[stage];

/// What a result of [stage] means: [result] is `pass`, `info`, `warn`,
/// `fail` or `unavailable`.
///
/// [tlsResult] is the result of the `tls.spki` stage of the same check: the
/// meaning of an unencrypted request depends on whether the connection is
/// pinned to the attestation.
String stageMeaning(
  AppLocalizations l,
  String stage,
  String result, {
  String? tlsResult,
}) {
  final e = _explanations(l)[stage];
  if (stage == 'e2ee.request' && result == 'info') {
    return tlsResult == 'pass'
        ? l.stageE2eeRequestPinned
        : l.stageE2eeRequestUnpinned;
  }
  return switch (result) {
    'pass' => e?.ifPass ?? l.stagePassDefault,
    'info' => e?.ifInfo ?? l.stageInfoDefault,
    'warn' => l.stageWarnMeaning,
    'unavailable' => l.stageUnavailableMeaning,
    _ => l.stageFailMeaning,
  };
}

Map<String, StageExplanation> _explanations(AppLocalizations l) => {
  'quote': StageExplanation(
    what: l.stageQuoteWhat,
    ifPass: l.stageQuotePass,
    ifInfo: l.stageQuoteInfo,
  ),
  'tcb': StageExplanation(
    what: l.stageTcbWhat,
    ifPass: l.stageTcbPass,
    ifInfo: l.stageTcbInfo,
  ),
  'nonce': StageExplanation(
    what: l.stageNonceWhat,
    ifPass: l.stageNoncePass,
    ifInfo: l.stageNonceInfo,
  ),
  'keyset.digest': StageExplanation(
    what: l.stageKeyBindingWhat,
    ifPass: l.stageKeyBindingPass,
    ifInfo: l.stageKeyBindingInfo,
  ),
  'keyset.endorsement': StageExplanation(
    what: l.stageSignatureWhat,
    ifPass: l.stageSignaturePass,
    ifInfo: l.stageSignatureInfo,
  ),
  'freshness': StageExplanation(
    what: l.stageAgeWhat,
    ifPass: l.stageAgePass,
    ifInfo: l.stageAgeInfo,
  ),
  'eventlog': StageExplanation(
    what: l.stageEventLogWhat,
    ifPass: l.stageEventLogPass,
    ifInfo: l.stageEventLogInfo,
  ),
  'compose': StageExplanation(
    what: l.stageComposeWhat,
    ifPass: l.stageComposePass,
    ifInfo: l.stageComposeInfo,
  ),
  'provenance': StageExplanation(
    what: l.stageProvenanceWhat,
    ifPass: l.stageProvenancePass,
    ifInfo: l.stageProvenanceInfo,
  ),
  'tls.spki': StageExplanation(
    what: l.stageTlsWhat,
    ifPass: l.stageTlsPass,
    ifInfo: l.stageTlsInfo,
  ),
  'e2ee.key': StageExplanation(
    what: l.stageE2eeKeyWhat,
    ifPass: l.stageE2eeKeyPass,
    ifInfo: l.stageE2eeKeyInfo,
  ),
  'e2ee.request': StageExplanation(
    what: l.stageE2eeRequestWhat,
    ifPass: l.stageE2eeRequestPass,
    ifInfo: l.stageE2eeRequestInfo,
  ),
  'e2ee.response': StageExplanation(
    what: l.stageE2eeResponseWhat,
    ifPass: l.stageE2eeResponsePass,
    ifInfo: l.stageE2eeResponseInfo,
  ),
  'e2ee.keyset': StageExplanation(
    what: l.stageResponseKeyWhat,
    ifPass: l.stageResponseKeyPass,
    ifInfo: l.stageResponseKeyInfo,
  ),
  'gateway': StageExplanation(
    what: l.stageGatewayWhat,
    ifPass: l.stageGatewayPass,
    ifInfo: l.stageGatewayInfo,
  ),
  'gpu': StageExplanation(
    what: l.stageGpuWhat,
    ifPass: l.stageGpuPass,
    ifInfo: l.stageGpuInfo,
  ),
  'snp.report': StageExplanation(
    what: l.stageSnpReportWhat,
    ifPass: l.stageSnpReportPass,
    ifInfo: l.stageSnpReportInfo,
  ),
  'snp.chain': StageExplanation(
    what: l.stageSnpChainWhat,
    ifPass: l.stageSnpChainPass,
    ifInfo: l.stageSnpChainInfo,
  ),
  'snp.policy': StageExplanation(
    what: l.stageSnpPolicyWhat,
    ifPass: l.stageSnpPolicyPass,
    ifInfo: l.stageSnpPolicyInfo,
  ),
  'bind.hpke': StageExplanation(
    what: l.stageBindHpkeWhat,
    ifPass: l.stageBindHpkePass,
    ifInfo: l.stageBindHpkeInfo,
  ),
  'sigstore.release': StageExplanation(
    what: l.stageSigstoreWhat,
    ifPass: l.stageSigstorePass,
    ifInfo: l.stageSigstoreInfo,
  ),
  'measurement': StageExplanation(
    what: l.stageMeasurementWhat,
    ifPass: l.stageMeasurementPass,
    ifInfo: l.stageMeasurementInfo,
  ),
  'release.floor': StageExplanation(
    what: l.stageReleaseFloorWhat,
    ifPass: l.stageReleaseFloorPass,
    ifInfo: l.stageReleaseFloorInfo,
  ),
  'receipt.none': StageExplanation(
    what: l.stageNoReceiptWhat,
    ifPass: l.stageNoReceiptPass,
    ifInfo: l.stageNoReceiptInfo,
  ),
  'receipt.fetch': StageExplanation(
    what: l.stageReceiptFetchWhat,
    ifPass: l.stageReceiptFetchPass,
    ifInfo: l.stageReceiptFetchInfo,
  ),
  'receipt.signature': StageExplanation(
    what: l.stageReceiptSigWhat,
    ifPass: l.stageReceiptSigPass,
    ifInfo: l.stageReceiptSigInfo,
  ),
  'receipt.binding': StageExplanation(
    what: l.stageReceiptBindingWhat,
    ifPass: l.stageReceiptBindingPass,
    ifInfo: l.stageReceiptBindingInfo,
  ),
  'receipt.request': StageExplanation(
    what: l.stageReceiptRequestHashWhat,
    ifPass: l.stageReceiptRequestHashPass,
    ifInfo: l.stageReceiptRequestHashInfo,
  ),
  'receipt.response': StageExplanation(
    what: l.stageReceiptResponseHashWhat,
    ifPass: l.stageReceiptResponseHashPass,
    ifInfo: l.stageReceiptResponseHashInfo,
  ),
  'receipt.upstream': StageExplanation(
    what: l.stageUpstreamWhat,
    ifPass: l.stageUpstreamPass,
    ifInfo: l.stageUpstreamInfo,
  ),
  'receipt.upstream.tcb': StageExplanation(
    what: l.stageUpstreamTcbWhat,
    ifPass: l.stageUpstreamTcbPass,
    ifInfo: l.stageUpstreamTcbInfo,
  ),
  'receipt.events': StageExplanation(
    what: l.stageReceiptCompleteWhat,
    ifPass: l.stageReceiptCompletePass,
    ifInfo: l.stageReceiptCompleteInfo,
  ),
};
