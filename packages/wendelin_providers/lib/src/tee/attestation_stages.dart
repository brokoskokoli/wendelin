import 'dart:convert';
import 'dart:typed_data';

import 'attestation_crypto.dart';
import 'attestation_types.dart';
import 'codec.dart';
import 'gateway_documents.dart';

/// The offline checks of the gateway attestation, one function per stage
/// (concept: „TEE-Provider und Attestierung“, ADR 0014). Pure given the
/// [AttestationCrypto] hash functions.
final class AttestationChecks {
  /// Creates the checks.
  AttestationChecks(this.crypto);

  /// Hash functions.
  final AttestationCrypto crypto;

  Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

  /// Maps the TCB status onto a stage result (decision 3 of M4: `OutOfDate`
  /// is red with a hint; hardening hints are yellow notes, final green).
  StageResult tcb(QuoteVerdict v) {
    final advisories = v.advisoryIds.isEmpty
        ? ''
        : ' (${v.advisoryIds.join(', ')})';
    return switch (v.tcbStatus) {
      TcbStatus.upToDate => const StageResult.pass(AttestationStage.tcb),
      TcbStatus.swHardeningNeeded ||
      TcbStatus.configurationNeeded ||
      TcbStatus.configurationAndSwHardeningNeeded => StageResult(
        AttestationStage.tcb,
        StageOutcome.warn,
        'Hinweis: ${v.tcbStatus.name}$advisories',
      ),
      TcbStatus.relaunchAdvised ||
      TcbStatus.relaunchAdvisedConfigurationNeeded => StageResult.fail(
        AttestationStage.tcb,
        'Neustart der TEE beim Betreiber empfohlen (${v.tcbStatus.name})$advisories',
        code: StageResult.tcbRelaunchAdvised,
      ),
      TcbStatus.outOfDate ||
      TcbStatus.outOfDateConfigurationNeeded ||
      TcbStatus.revoked => StageResult.fail(
        AttestationStage.tcb,
        'TCB ${v.tcbStatus.name}$advisories',
      ),
    };
  }

  /// `report_data = sha256(statement)` over the nonce and the advertised
  /// keyset digest (spec §3.2), for the document and for the quote.
  StageResult nonceBinding(
    GatewayAttestation doc,
    QuoteVerdict verdict,
    Uint8List nonce,
  ) {
    final statement =
        '{"keyset_digest":${jsonEncode(doc.keysetDigest)},'
        '"nonce":"${AttestCodec.hex(nonce)}",'
        '"purpose":"aci.report_data.v1"}';
    final expected = AttestCodec.hex(crypto.sha256(_utf8(statement)));
    final inQuote = AttestCodec.hex(verdict.reportData);
    if (verdict.reportData.length != 64 ||
        inQuote != '$expected${'0' * 64}' ||
        doc.reportData != expected) {
      return const StageResult.fail(
        AttestationStage.nonceBinding,
        'report_data bindet die Nonce nicht',
      );
    }
    return const StageResult.pass(AttestationStage.nonceBinding);
  }

  /// The advertised digest equals `sha256:` + sha256(JCS(keyset)).
  StageResult keysetDigest(GatewayAttestation doc) {
    try {
      final actual = AttestCodec.prefixed(
        crypto.sha256(AttestCodec.jcsBytes(doc.keyset.raw)),
      );
      return actual == doc.keysetDigest
          ? const StageResult.pass(AttestationStage.keysetDigest)
          : const StageResult.fail(
              AttestationStage.keysetDigest,
              'Digest passt nicht zum Keyset',
            );
    } on FormatException catch (e) {
      return StageResult.fail(AttestationStage.keysetDigest, e.message);
    }
  }

  /// The API has no endorsement signature; the binding is the chain
  /// quote → report_data → keyset digest. Logged as `info`.
  StageResult keysetEndorsement(GatewayAttestation doc) => StageResult(
    AttestationStage.keysetEndorsement,
    StageOutcome.info,
    doc.hasEndorsement
        ? 'keyset_endorsement vorhanden, aber nicht spezifiziert (nicht geprüft)'
        : 'API liefert keine Endorsement; Bindung über report_data',
  );

  /// `not_after` (and `stale_after`, if present) lie after [now].
  StageResult freshness(GatewayAttestation doc, DateTime now) {
    final nowS = now.millisecondsSinceEpoch ~/ 1000;
    if (doc.keyset.notAfterEpoch <= nowS) {
      return const StageResult.fail(
        AttestationStage.freshness,
        'Keyset abgelaufen (not_after)',
      );
    }
    final stale = doc.staleAfterEpoch;
    if (stale != null && stale <= nowS) {
      return const StageResult.fail(
        AttestationStage.freshness,
        'Attestierung veraltet (stale_after)',
      );
    }
    return const StageResult.pass(AttestationStage.freshness);
  }

  /// Replays RTMR3 from the runtime events (`digest = sha384(type_le32 ":"
  /// event ":" payload)`, `rtmr = sha384(rtmr ‖ digest)`) and compares it
  /// with the verified quote.
  StageResult eventLog(GatewayAttestation doc, QuoteVerdict verdict) {
    var rtmr = Uint8List(48);
    for (final e in doc.eventLog.where((e) => e.imr == 3)) {
      final typeLe = ByteData(4)..setUint32(0, e.eventType, Endian.little);
      final recomputed = crypto.sha384(
        Uint8List.fromList([
          ...typeLe.buffer.asUint8List(),
          ...utf8.encode(':${e.event}:'),
          ...e.payload,
        ]),
      );
      if (AttestCodec.hex(recomputed) != AttestCodec.hex(e.digest)) {
        return StageResult.fail(
          AttestationStage.eventLog,
          'Digest von "${e.event}" passt nicht',
        );
      }
      rtmr = crypto.sha384(Uint8List.fromList([...rtmr, ...e.digest]));
    }
    return AttestCodec.hex(rtmr) == AttestCodec.hex(verdict.rtmr3)
        ? const StageResult.pass(AttestationStage.eventLog)
        : const StageResult.fail(
            AttestationStage.eventLog,
            'RTMR3 passt nicht zum Quote',
          );
  }

  /// `sha256(app_compose)` equals the payload of the `compose-hash` event.
  StageResult composeHash(GatewayAttestation doc) {
    final hash = AttestCodec.hex(crypto.sha256(_utf8(doc.appCompose)));
    final measured = doc.eventLog.where((e) => e.event == 'compose-hash');
    if (measured.isEmpty) {
      return const StageResult.fail(
        AttestationStage.composeHash,
        'kein compose-hash im Event-Log',
      );
    }
    return measured.any((e) => AttestCodec.hex(e.payload) == hash)
        ? StageResult.pass(AttestationStage.composeHash, hash)
        : const StageResult.fail(
            AttestationStage.composeHash,
            'app_compose passt nicht zum gemessenen Hash',
          );
  }

  /// `repo_commit` against [trusted]; empty list = only logged.
  StageResult provenance(GatewayAttestation doc, Set<String> trusted) {
    final commit = doc.repoCommit;
    if (trusted.isEmpty) {
      return StageResult(
        AttestationStage.provenance,
        StageOutcome.info,
        'Commit ${commit ?? 'unbekannt'} (keine Liste hinterlegt)',
      );
    }
    return commit != null && trusted.contains(commit)
        ? StageResult.pass(AttestationStage.provenance, commit)
        : StageResult.fail(
            AttestationStage.provenance,
            'Commit ${commit ?? 'unbekannt'} nicht vertrauenswürdig',
          );
  }

  /// Consistency of `downstream_tls_binding` with the keyset's
  /// `tls_public_keys`, and – if [observedSpki] (hex) is given – the
  /// certificate seen on the connection. A mismatch of the connection is a
  /// failure only if [enforce]; otherwise it is logged (open finding, see
  /// ADR 0014).
  StageResult tlsSpki(
    GatewayAttestation doc, {
    String? observedSpki,
    bool enforce = false,
  }) {
    final domain = doc.downstreamTlsDomain;
    final bound = doc.downstreamTlsSpki;
    final listed = domain == null ? null : doc.keyset.tlsSpkiByDomain[domain];
    if (bound != null && listed != null && bound != listed) {
      return const StageResult.fail(
        AttestationStage.tlsSpki,
        'downstream_tls_binding widerspricht dem Keyset',
      );
    }
    if (observedSpki == null) {
      return const StageResult(
        AttestationStage.tlsSpki,
        StageOutcome.info,
        'Zertifikat der Verbindung nicht geprüft',
      );
    }
    final expected = listed ?? bound;
    if (expected == null || expected != observedSpki) {
      return StageResult(
        AttestationStage.tlsSpki,
        enforce ? StageOutcome.fail : StageOutcome.info,
        'SPKI der Verbindung weicht vom Keyset ab'
        '${enforce ? '' : ' (nicht erzwungen)'}',
      );
    }
    return const StageResult.pass(AttestationStage.tlsSpki);
  }
}
