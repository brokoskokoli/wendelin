// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get agentNoticeCancelled => 'Abgebrochen.';

  @override
  String get agentNoticeGpuFailed =>
      'GPU-Prüfung fehlgeschlagen. Details im Prüfprotokoll.';

  @override
  String get agentNoticeGpuNoEvidence =>
      'Dieses Modell liefert keinen GPU-Nachweis. Tippe auf Ohne GPU-Prüfung senden.';

  @override
  String agentNoticeProfileBroken(Object e) {
    return 'Provider-Profil fehlerhaft: $e';
  }

  @override
  String get agentNoticeRecheckFailed =>
      'Die neue Prüfung ist nicht bestanden. Details im Prüfprotokoll.';

  @override
  String get agentNoticeRequestEmpty => 'Die Anfrage ist leer.';

  @override
  String get agentNoticeRequestRunning => 'Es läuft schon eine Anfrage.';

  @override
  String get agentNoticeSetupFirst => 'Bitte zuerst einen Provider einrichten.';

  @override
  String get agentNoticeStartFailed => 'Die Anfrage konnte nicht starten.';

  @override
  String agentNoticeUndoFailed(Object e) {
    return 'Rückgängig hat nicht geklappt: $e';
  }

  @override
  String get assistantAnotherService => 'einen anderen Dienst';

  @override
  String get assistantChangeInAndroid => 'In Android ändern';

  @override
  String get assistantDefaultHint =>
      'Langer Druck auf die Power-Taste oder die Assistenten-Geste öffnet Wendelin über jeder App.';

  @override
  String get assistantDefaultTitle => 'Standard-Assistent';

  @override
  String get assistantInactiveDefault =>
      'Android verweist für andere Apps auf Wendelin, die Spracherkennung ist aber aus (Schalter aus). Andere Apps bekommen dann einen Fehler.';

  @override
  String get assistantInactiveNotDefault =>
      'Android verweist für andere Apps auf Wendelin, die Spracherkennung ist aber aus: Wendelin ist nicht Standard-Assistent. Andere Apps bekommen dann einen Fehler.';

  @override
  String get assistantIsDefault => 'Wendelin ist Standard-Assistent';

  @override
  String get assistantNameHint =>
      'Name und Persönlichkeit gehen als Teil der Anweisungen an das Modell.';

  @override
  String get assistantNameLabel => 'Wie soll Wendelin dich nennen?';

  @override
  String get assistantNotAvailable => 'Auf diesem Gerät nicht verfügbar';

  @override
  String get assistantNotDefault => 'Nicht als Standard-Assistent gesetzt';

  @override
  String get assistantOfferRecognizer =>
      'Als Spracherkennung für andere Apps anbieten';

  @override
  String assistantOfferRecognizerUnavailable(String reason) {
    return 'Als Spracherkennung für andere Apps anbieten, $reason';
  }

  @override
  String assistantOtherForNowDefault(String app) {
    return 'Android nutzt für andere Apps derzeit $app. Ob Android nach dem Einschalten zu Wendelin wechselt, hängt vom Gerät ab.';
  }

  @override
  String assistantOtherForNowNotDefault(String app) {
    return 'Android nutzt für andere Apps derzeit $app. Das kann sich ändern, sobald Wendelin Standard-Assistent ist.';
  }

  @override
  String assistantOtherRecognizer(String app) {
    return 'Android nutzt für andere Apps $app. Das lässt sich auf diesem Gerät nicht umstellen.';
  }

  @override
  String get assistantPersonaLabel =>
      'Persönlichkeit, z. B. „antworte knapp und locker“';

  @override
  String get assistantRecognizerActiveDetail =>
      'Android nutzt Wendelin für die Spracheingabe anderer Apps. Whisper erkennt auf dem Gerät, Aufnahmen werden nicht gespeichert.';

  @override
  String get assistantRecognizerActiveHint =>
      'Android nutzt Wendelin für die Spracheingabe anderer Apps.';

  @override
  String get assistantRecognizerUnknownDetail =>
      'Solange Wendelin Standard-Assistent ist, können andere Apps die Spracheingabe nutzen. Whisper erkennt auf dem Gerät, Aufnahmen werden nicht gespeichert.';

  @override
  String get assistantSetDefault => 'Als Standard-Assistent setzen';

  @override
  String get assistantSetLabel => 'gesetzt';

  @override
  String get assistantSwitchHint =>
      'Wechselst du später zu einem anderen Assistenten (oder „Keiner“), antwortet die Spracherkennung von Wendelin anderen Apps nicht mehr. Wähle die Spracheingabe dann in den Android-Einstellungen neu, meist unter Apps → Standard-Apps → Digitaler Assistent.';

  @override
  String get conversationOfferHint =>
      'Das lässt sich jederzeit unter Einstellungen → Sprache ändern.';

  @override
  String get conversationOfferQuestion =>
      'Soll ich nach meinen Antworten standardmäßig weiter zuhören?';

  @override
  String reducerBudgetUsed(String name, String spent, String budget) {
    return 'Budget von $name: $spent von $budget verbraucht.';
  }

  @override
  String reducerHandedOver(String name) {
    return 'an $name übergeben';
  }

  @override
  String get reducerSpokenFallback =>
      'Vorgelesen wurde die angezeigte Fassung.';

  @override
  String get reducerVerificationFailed =>
      'Die Antwort des Anbieters konnte nicht geprüft werden.';

  @override
  String get attCheckFailed => 'Prüfung fehlgeschlagen';

  @override
  String get attChecking => 'wird geprüft';

  @override
  String get attE2eeKeyNote =>
      'Alle Inhalte werden mit diesem geprüften Schlüssel verschlüsselt. Die Verschlüsselung endet im Gateway des Anbieters (geprüfte Enklave), nicht im Modell selbst. Bei NEAR AI endet sie im geprüften Modell. Bei Tinfoil endet sie im geprüften Router, der sie an das Modell weitergibt.';

  @override
  String get attExplainAccept => 'Akzeptieren';

  @override
  String attExplainChecked(String what) {
    return 'Geprüft wird: $what';
  }

  @override
  String get attExplainIntro =>
      'Was Wendelin prüft, was dabei herauskam und was das für deine Sicherheit heißt.';

  @override
  String attExplainMeaning(String v) {
    return 'Bedeutung: $v';
  }

  @override
  String attExplainRestrictionsDetail(String v) {
    return '$v: nur protokolliert. Wenn du das akzeptierst, zeigt der Chat dafür keinen Hinweis mehr.';
  }

  @override
  String get attExplainRestrictionsTitle => 'Einschränkungen dieses Anbieters';

  @override
  String attExplainResult(String detail) {
    return 'Ergebnis: $detail';
  }

  @override
  String attExplainStageLine(String label, String result) {
    return '$label · $result';
  }

  @override
  String get attExplainTitle => 'Details zur Prüfung';

  @override
  String get attFailedText =>
      'Die Antwort konnte nicht als unverändert aus der geprüften Umgebung bestätigt werden, zum Beispiel wegen eines Signaturfehlers oder abweichender Prüfsummen. Das kann auf eine Manipulation hindeuten. Vertraue der Antwort nicht. Der Anbieter ist gesperrt, bis du ihn neu prüfst.';

  @override
  String get attFinishBudgetLabel => 'Budget pro Monat in \$ (optional)';

  @override
  String get attFinishImagesNo => '✕ Bilder';

  @override
  String get attFinishImagesYes => '✓ Bilder';

  @override
  String get attFinishModelChecked => 'Modell geprüft';

  @override
  String attFinishPercentOfBudget(int v) {
    return '$v % des Budgets';
  }

  @override
  String get attFinishPrivacyLevel => 'Datenschutzstufe';

  @override
  String attFinishRestrictionNote(String v) {
    return '$v. Das liefert der Anbieter nicht oder Wendelin prüft es nicht, es wird nur protokolliert. Mit „Speichern“ akzeptierst du das. Sobald etwas Neues dazukommt, weist Wendelin erneut darauf hin. Mehr unter „Details“.';
  }

  @override
  String get attFinishTeeYes => '✓ TEE';

  @override
  String get attFinishToolsNo => '✕ Tools';

  @override
  String get attFinishToolsYes => '✓ Tools';

  @override
  String get attFinishWarnFrom => 'Warnen ab';

  @override
  String get attFloorCorruptText =>
      'Die gespeicherte Untergrenze für die Release-Version dieses Anbieters ist beschädigt. Ohne sie lässt sich ein Rückschritt auf ältere, unsichere Software nicht ausschließen. Deshalb bleibt die Prüfung gesperrt, ein erneutes Prüfen ändert daran nichts. Sende nichts Vertrauliches. Abhilfe schafft nur das Zurücksetzen der App-Daten. Danach wird der erste Kontakt wieder ohne Rückschrittschutz geprüft.';

  @override
  String get attFloorCorruptTitle =>
      'Gespeicherter Rückschrittschutz beschädigt';

  @override
  String get attGpuFailedLabel => 'GPU-Prüfung fehlgeschlagen';

  @override
  String attGpuFailedText(String v) {
    return 'Die GPU-Prüfung über NVIDIA ist fehlgeschlagen.$v Die nächste Anfrage an dieses Modell wird vorher geprüft.';
  }

  @override
  String get attGpuFailedTitle => 'GPU-Prüfung fehlgeschlagen';

  @override
  String get attGpuUnavailableLabel => 'GPU-Prüfung nicht möglich';

  @override
  String attGpuUnavailableText(String v) {
    return 'Die GPU-Prüfung über NVIDIA war nicht möglich.$v Die nächste Anfrage an dieses Modell wird vorher geprüft.';
  }

  @override
  String get attGpuUnavailableTitle => 'GPU-Prüfung nicht möglich';

  @override
  String get attLogCommit => 'Commit';

  @override
  String get attLogKeysetDigest => 'Keyset-Digest';

  @override
  String get attLogModel => 'Modell';

  @override
  String get attLogNewRestriction => 'Neue Einschränkung';

  @override
  String attLogNewRestrictionDetail(String v) {
    return '$v: nur protokolliert und noch nicht von dir akzeptiert. Unter „Details“ kannst du das ansehen und akzeptieren.';
  }

  @override
  String get attLogNoEntry => 'Zu dieser Antwort gibt es noch keinen Eintrag.';

  @override
  String get attLogParticulars => 'Angaben';

  @override
  String get attLogProvider => 'Anbieter';

  @override
  String get attLogReasonCode => 'Grundcode';

  @override
  String get attLogReceiptId => 'Quittungs-ID';

  @override
  String get attLogRecheck => 'Neu prüfen';

  @override
  String get attLogRecheckFailed => 'Die neue Prüfung ist nicht bestanden.';

  @override
  String get attLogRechecked =>
      'Anbieter neu geprüft, die Sperre ist aufgehoben.';

  @override
  String get attLogResultPerStep => 'Ergebnis je Stufe';

  @override
  String attLogScreenCommitLine(String repoCommit) {
    return 'Commit $repoCommit';
  }

  @override
  String get attLogScreenDeleteBody =>
      'Alle Einträge des Prüfprotokolls werden gelöscht. Das lässt sich nicht rückgängig machen.';

  @override
  String get attLogScreenDeleteLog => 'Prüfprotokoll löschen';

  @override
  String get attLogScreenDeleteTitle => 'Prüfprotokoll löschen?';

  @override
  String get attLogScreenDeleted => 'Gelöscht.';

  @override
  String get attLogScreenExportJson => 'Als JSON exportieren';

  @override
  String get attLogScreenFilterAll => 'Alle';

  @override
  String get attLogScreenFilterGreen => 'Geprüft';

  @override
  String get attLogScreenFilterRed => 'Fehlgeschlagen';

  @override
  String get attLogScreenFilterUnconfirmed => 'Nicht bestätigt';

  @override
  String get attLogScreenFilterYellow => 'Wird geprüft';

  @override
  String attLogScreenGpuTitle(String v) {
    return 'GPU · $v';
  }

  @override
  String get attLogScreenIntro =>
      'Wendelin prüft Anbieter mit geschützter Umgebung (TEE) und jede Antwort. Hier steht, was geprüft wurde. Nie Inhalte, nur Ids, Prüfsummen und Ergebnisse.';

  @override
  String get attLogScreenNoEntries => 'Keine Einträge.';

  @override
  String attLogScreenReceiptTitle(String v, String providerName) {
    return '$v · $providerName';
  }

  @override
  String get attLogScreenRecheckAttest => 'Neu attestieren';

  @override
  String get attLogScreenRechecked =>
      'Neu attestiert, eine Sperre ist aufgehoben.';

  @override
  String get attLogScreenSessionGreen => 'Sitzung geprüft';

  @override
  String get attLogScreenSessionRed => 'Sitzung fehlgeschlagen';

  @override
  String attLogScreenSessionTitle(String providerName) {
    return 'Sitzung · $providerName';
  }

  @override
  String get attLogScreenSessionUnconfirmed => 'Sitzung nicht bestätigt';

  @override
  String get attLogScreenSessionYellow => 'Sitzung nicht prüfbar';

  @override
  String get attLogTime => 'Zeit';

  @override
  String get attLogTitle => 'Prüfprotokoll';

  @override
  String get attLogTitle2 => 'Prüfprotokoll';

  @override
  String get attMismatchText =>
      'Der Nachweis der Sitzung passt nicht zur signierten Quittung dieser Antwort. Vertraue der Antwort nicht. Der Anbieter ist gesperrt, bis du ihn neu prüfst.';

  @override
  String get attMismatchTitle => 'Möglicher Manipulationsversuch';

  @override
  String attReasonLead(String reason, String v) {
    return ' Grund: $reason$v';
  }

  @override
  String get attReceiptMissing => 'Quittung fehlt';

  @override
  String get attReceiptMissingText =>
      'Der Anbieter hat zu dieser Antwort keine Quittungs-Kennung geliefert.';

  @override
  String get attReceiptNotFound => 'Quittung nicht gefunden';

  @override
  String get attReceiptNotFoundText =>
      'Der Anbieter kennt die Quittung dieser Antwort nicht (noch nicht geschrieben oder abgelaufen).';

  @override
  String get attReceiptRejectedLabel => 'Quittung abgelehnt';

  @override
  String get attReceiptRejectedText =>
      'Der Anbieter hat den Abruf der Quittung abgelehnt (zum Beispiel wegen zu vieler Anfragen). Die Antwort ist nicht bestätigt, es gibt aber keinen Hinweis auf eine Manipulation. Prüfe den Anbieter neu.';

  @override
  String get attReceiptRejectedTitle => 'Quittungsabruf vom Anbieter abgelehnt';

  @override
  String get attReceiptUnreachable => 'Quittung nicht erreichbar';

  @override
  String get attReceiptUnreachableText =>
      'Die Quittung dieser Antwort konnte wegen eines Netz- oder Serverfehlers nicht abgerufen werden.';

  @override
  String get attRelaunchText =>
      'Der Hersteller empfiehlt dem Betreiber, die geschützte Umgebung neu zu starten, damit ein Sicherheits-Update wirksam wird. Das ist kein Hinweis auf eine Manipulation. Prüfe später erneut.';

  @override
  String get attRelaunchTitle => 'Neustart der TEE beim Betreiber empfohlen';

  @override
  String get attResponseWord => 'Antwort';

  @override
  String get attRestrictionOpen => 'geprüft, neue Einschränkung';

  @override
  String get attResultInfo => 'nur protokolliert';

  @override
  String get attResultUnavailable => 'nicht abrufbar';

  @override
  String get attResultWarn => 'Hinweis';

  @override
  String get attRevokedText =>
      'Der Hersteller hat die Hardware-Plattform des Betreibers als unsicher zurückgezogen. Sende nichts Vertrauliches, bis der Betreiber sie ersetzt hat.';

  @override
  String get attRevokedTitle => 'Plattform des Betreibers zurückgezogen';

  @override
  String get attRollbackText =>
      'Der Anbieter meldet eine ältere Software-Version als die, die hier schon einmal geprüft wurde. Das kann ein Zurückspielen alter, verwundbarer Software oder alter Daten sein. Die Anfrage wurde nicht gesendet. Sende nichts Vertrauliches und prüfe später erneut.';

  @override
  String get attRollbackTitle => 'Ältere Software-Version als zuvor geprüft';

  @override
  String get attSBindHpke => 'Verschlüsselungsschlüssel gebunden';

  @override
  String get attSCompose => 'Compose-Hash';

  @override
  String get attSE2eeKey => 'E2EE-Schlüssel geprüft';

  @override
  String get attSE2eeKeyset => 'Schlüsselsatz der Antwort';

  @override
  String get attSE2eeRequest => 'Verschlüsselung der Anfrage';

  @override
  String get attSE2eeResponse => 'Entschlüsselung der Antwort';

  @override
  String get attSEventLog => 'Ereignisprotokoll';

  @override
  String get attSFreshness => 'Frische';

  @override
  String get attSGateway => 'Gateway des Anbieters';

  @override
  String get attSGpu => 'GPU-Evidenz';

  @override
  String get attSGpuEvidence => 'GPU-Nachweis des Anbieters';

  @override
  String get attSKeysetDigest => 'Schlüsselsatz (Digest)';

  @override
  String get attSKeysetSignature => 'Schlüsselsatz-Signatur';

  @override
  String get attSMeasurement => 'Messwert = Release';

  @override
  String get attSNoReceipt => 'Quittung je Antwort';

  @override
  String get attSNonce => 'Nonce gebunden';

  @override
  String get attSProvenance => 'Herkunft (Commit)';

  @override
  String get attSQuote => 'TDX-Quote (DCAP)';

  @override
  String get attSReceiptBinding => 'Quittung an Sitzung gebunden';

  @override
  String get attSReceiptEvents => 'Quittungs-Ereignisse';

  @override
  String get attSReceiptFetch => 'Quittung abgerufen';

  @override
  String get attSReceiptRequest => 'Hash der Anfrage';

  @override
  String get attSReceiptResponse => 'Hash der Antwort';

  @override
  String get attSReceiptSignature => 'Quittungs-Signatur';

  @override
  String get attSReleaseFloor => 'Kein Rückschritt';

  @override
  String get attSSigstore => 'Signiertes Release (Sigstore)';

  @override
  String get attSSnpChain => 'AMD-Zertifikatskette';

  @override
  String get attSSnpPolicy => 'Prozessor-Richtlinie';

  @override
  String get attSSnpReport => 'AMD-Hardware-Nachweis';

  @override
  String get attSTcb => 'Plattform-Sicherheitsstand (TCB)';

  @override
  String get attSTls => 'TLS-Verbindung geprüft';

  @override
  String get attSUpstream => 'Upstream-Prüfung';

  @override
  String get attSUpstreamTcb => 'Upstream-Sicherheitsstand';

  @override
  String attStagesCardAllPassed(int length) {
    return 'Alle $length Stufen bestanden';
  }

  @override
  String get attStagesCardFirst => 'Erste Attestierung';

  @override
  String get attStagesCardNotPassed => 'nicht bestanden';

  @override
  String attStagesCardSomePassed(int failed, int length, String v) {
    return '$failed von $length Stufen nicht bestanden: $v';
  }

  @override
  String get attStagesCardViewLog => 'Prüfprotokoll ansehen';

  @override
  String attStoredReason(String text, String v) {
    return ' Grund: $text$v';
  }

  @override
  String get attSummaryGreen => 'geprüft';

  @override
  String get attSummaryYellow => 'ausstehend';

  @override
  String get attTcbText =>
      'Die Hardware, auf der das Modell läuft, hat ein Sicherheits-Update des Herstellers noch nicht eingespielt. Das ist kein Hinweis auf eine Manipulation, schwächt aber den Schutz. Der Betreiber muss aktualisieren. Prüfe später erneut und sende bis dahin nichts Vertrauliches.';

  @override
  String get attTcbTitle => 'Sicherheits-Update beim Betreiber ausstehend';

  @override
  String get attUnconfirmed => 'nicht bestätigt';

  @override
  String attUnconfirmedText(String cause) {
    return '$cause Ob die Antwort aus der geprüften Umgebung stammt, ist unbestätigt. Es wurde aber auch kein Fehler festgestellt, der Anbieter bleibt nutzbar. Aktionen, die auf die geprüfte Antwort warten, laufen nicht. Prüfe den Anbieter neu.';
  }

  @override
  String get checkStatusFailed => 'fehlgeschlagen';

  @override
  String get checkStatusInfo => 'nur protokolliert';

  @override
  String get checkStatusNeutral => 'nicht bestätigt';

  @override
  String get checkStatusOk => 'geprüft';

  @override
  String get checkStatusPending => 'ausstehend';

  @override
  String get gpuBlockNoEvidenceDetail => 'Die Anfrage wurde nicht gesendet.';

  @override
  String gpuBlockNotSent(String v) {
    return 'Nicht gesendet.$v';
  }

  @override
  String get gpuModeAfter => 'Nachher';

  @override
  String get gpuModeAfterText =>
      'Die Prüfung läuft nach der Antwort. Schlägt sie fehl, warnt dich eine Benachrichtigung, die Antwort wird rot markiert, und die nächsten Anfragen an dieses Modell prüfen vorher. Modelle ohne Nachweis bekommen nur einen Hinweis.';

  @override
  String get gpuModeBefore => 'Vorher';

  @override
  String get gpuModeBeforeText =>
      'NVIDIA prüft die GPU-Nachweise, bevor deine Anfrage den Anbieter erreicht. Schlägt die Prüfung fehl oder liefert der Anbieter keinen Nachweis, wird nichts gesendet. Du kannst dann einmalig ohne GPU-Prüfung senden.';

  @override
  String get gpuModeOff => 'Aus';

  @override
  String get gpuModeOffText =>
      'Standard. Wendelin prüft nur lokal, ob die GPU-Nachweise zu deiner Anfrage gehören. Kein Aufruf an NVIDIA.';

  @override
  String gpuNoEvidenceFinishText(String hint) {
    return '$hint. Das Modell bleibt nutzbar. Was Wendelin dann tut, bestimmt die GPU-Prüfung unten: „Aus“ nichts, „Nachher“ nur ein Hinweis, „Vorher“ sendet nichts, du kannst aber einmalig ohne GPU-Prüfung senden.';
  }

  @override
  String get gpuNoEvidenceFinishTitle => 'Keine GPU-Prüfung möglich';

  @override
  String get gpuNoEvidenceHint =>
      'Keine GPU-Prüfung möglich (Anbieter liefert keinen Nachweis)';

  @override
  String gpuNoEvidenceMessage(String name) {
    return '$name liefert für dieses Modell keinen GPU-Nachweis, NVIDIA kann nichts prüfen. Weil die GPU-Prüfung auf „Vorher“ steht, wurde deine Anfrage nicht gesendet. Du kannst sie einmalig ohne GPU-Prüfung senden. Die übrigen Prüfungen bleiben aktiv.';
  }

  @override
  String get gpuNoEvidenceTitle => 'Kein GPU-Nachweis';

  @override
  String gpuNotifyFailedText(String name) {
    return 'Die GPU-Prüfung der letzten Antwort von $name ist fehlgeschlagen. Die nächste Anfrage prüft vorher. Details im Prüfprotokoll.';
  }

  @override
  String get gpuNotifyFailedTitle => 'GPU-Prüfung fehlgeschlagen';

  @override
  String get gpuSectionNote =>
      'Für „Vorher“ und „Nachher“ ruft Wendelin den Dienst von NVIDIA (nras.attestation.nvidia.com) auf. Gesendet werden nur die Nachweise der GPU, keine Inhalte deiner Anfragen oder Antworten.';

  @override
  String get gpuSectionTitle => 'GPU-Prüfung über NVIDIA';

  @override
  String get gpuToolName => 'GPU-Prüfung';

  @override
  String shieldSemantics(String label) {
    return 'TEE-Prüfung: $label';
  }

  @override
  String shieldSemanticsTap(String label) {
    return 'TEE-Prüfung: $label. Tippen für das Prüfprotokoll.';
  }

  @override
  String get stageAgeInfo => 'Das Alter wurde nur protokolliert.';

  @override
  String get stageAgePass =>
      'Der Nachweis ist aktuell und kein alter Mitschnitt.';

  @override
  String get stageAgeWhat => 'Wie alt der Nachweis ist.';

  @override
  String get stageBindHpkeInfo => 'Der Schlüssel wurde nur protokolliert.';

  @override
  String get stageBindHpkePass =>
      'Nur der geprüfte Server kann die Anfrage lesen. Der Schlüssel stammt aus dem Nachweis, nicht aus einer ungeprüften Antwort.';

  @override
  String get stageBindHpkeWhat =>
      'Ob der Schlüssel, mit dem Wendelin deine Anfrage verschlüsselt, genau der ist, der im Hardware-Nachweis steht.';

  @override
  String get stageComposeInfo =>
      'Der Hash wurde protokolliert, aber nicht gegen eine Liste vertrauenswürdiger Werte verglichen.';

  @override
  String get stageComposePass =>
      'Genau die erwarteten Programme laufen im Dienst.';

  @override
  String get stageComposeWhat =>
      'Der Compose-Hash: eine Prüfsumme der Container-Beschreibung, also welche Programme im Dienst laufen.';

  @override
  String get stageE2eeKeyInfo => 'Der Schlüssel wurde nur protokolliert.';

  @override
  String get stageE2eeKeyPass =>
      'Nur die geprüfte Umgebung kann die Anfrage entschlüsseln. Bei manchen Anbietern endet die Verschlüsselung im Gateway, nicht im Modell selbst.';

  @override
  String get stageE2eeKeyWhat =>
      'Der Schlüssel, mit dem Wendelin deine Anfrage Ende-zu-Ende verschlüsselt, stammt aus dem Hardware-Nachweis.';

  @override
  String get stageE2eeRequestInfo =>
      'Die Anfrage (oder Teile wie Tool-Aufrufe) sind nicht zusätzlich verschlüsselt, nur über die geprüfte Verbindung geschützt.';

  @override
  String get stageE2eeRequestPass =>
      'Deine Anfrage ist unterwegs für Dritte unlesbar.';

  @override
  String get stageE2eeRequestPinned =>
      'Die Anfrage (oder Teile wie Tool-Aufrufe) sind nicht zusätzlich verschlüsselt, nur über die geprüfte Verbindung geschützt.';

  @override
  String get stageE2eeRequestUnpinned =>
      'Die Anfrage (oder Teile wie Tool-Aufrufe) sind nicht zusätzlich verschlüsselt, und die Verbindung ist nicht an den Nachweis gebunden. Der Schutz ist dadurch schwächer.';

  @override
  String get stageE2eeRequestWhat =>
      'Ob die Anfrage tatsächlich verschlüsselt gesendet wurde.';

  @override
  String get stageE2eeResponseInfo =>
      'Die Entschlüsselung wurde nur protokolliert.';

  @override
  String get stageE2eeResponsePass =>
      'Die Antwort kam unverändert aus der geprüften Umgebung.';

  @override
  String get stageE2eeResponseWhat =>
      'Ob die Antwort verschlüsselt ankam und entschlüsselt werden konnte.';

  @override
  String get stageEventLogInfo =>
      'Das Ereignisprotokoll wurde nur protokolliert.';

  @override
  String get stageEventLogPass =>
      'Die gestartete Software ist lückenlos nachvollziehbar.';

  @override
  String get stageEventLogWhat =>
      'Das Ereignisprotokoll des Starts: welche Software beim Hochfahren geladen wurde. Es muss zur Hardware-Messung passen.';

  @override
  String get stageFailMeaning =>
      'Die Prüfung ist fehlgeschlagen. Das kann ein Hinweis auf eine Manipulation oder einen Fehler beim Anbieter sein. Wendelin sendet dann nichts mehr an diesen Anbieter, bis du ihn neu prüfst.';

  @override
  String get stageGatewayInfo => 'Der Gateway-Zustand wurde nur protokolliert.';

  @override
  String get stageGatewayPass =>
      'Das Gateway läuft mit aktuellem Sicherheitsstand.';

  @override
  String get stageGatewayWhat =>
      'Der Zustand des Gateways des Anbieters (Vermittler vor dem Modell).';

  @override
  String get stageGpuInfo =>
      'Die GPU wurde nicht über NVIDIA geprüft, weil die Prüfung in den Einstellungen aus ist.';

  @override
  String get stageGpuPass => 'NVIDIA bestätigt die geschützte GPU.';

  @override
  String get stageGpuWhat =>
      'Der Nachweis der Grafikkarte (NVIDIA), auf der das Modell rechnet. Optional, in den Einstellungen zuschaltbar.';

  @override
  String get stageInfoDefault =>
      'Die Stufe wird nur protokolliert, nicht als Bedingung geprüft.';

  @override
  String get stageKeyBindingInfo => 'Die Prüfsumme wurde nur protokolliert.';

  @override
  String get stageKeyBindingPass =>
      'Die Schlüssel stammen aus der geprüften Umgebung, nicht von jemandem dazwischen.';

  @override
  String get stageKeyBindingWhat =>
      'Die Prüfsumme des Schlüsselsatzes (Schlüssel, mit denen Wendelin verschlüsselt) muss im Hardware-Nachweis stehen.';

  @override
  String get stageMeasurementInfo => 'Der Messwert wurde nur protokolliert.';

  @override
  String get stageMeasurementPass =>
      'Auf dem Server läuft der veröffentlichte Code, kein anderer.';

  @override
  String get stageMeasurementWhat =>
      'Ob der Messwert des laufenden Servers genau der des neuesten signierten Releases ist.';

  @override
  String get stageNoReceiptInfo =>
      'Tinfoil stellt keine Quittung je Antwort aus. Die Antwort ist nur durch die Verschlüsselung an deine Anfrage gebunden; welches Modell sie erzeugt hat, belegt keine Quittung.';

  @override
  String get stageNoReceiptPass =>
      'Zu jeder Antwort liegt eine signierte Quittung vor.';

  @override
  String get stageNoReceiptWhat =>
      'Ob zu jeder Antwort eine signierte Quittung vorliegt, die Anfrage und Antwort belegt.';

  @override
  String get stageNonceInfo => 'Die Zahl wurde nur protokolliert.';

  @override
  String get stageNoncePass =>
      'Der Nachweis ist frisch für diese Anfrage und kein aufgezeichneter alter Nachweis.';

  @override
  String get stageNonceWhat =>
      'Eine zufällige Zahl, die Wendelin mitschickt und die im Nachweis wieder auftauchen muss.';

  @override
  String get stagePassDefault => 'Die Stufe wurde bestanden.';

  @override
  String get stageProvenanceInfo =>
      'Es gibt keine Vertrauensliste für diesen Anbieter. Wendelin protokolliert den Stand, kann aber nicht sagen, ob er vertrauenswürdig ist. Wer den Quellcode prüfen will, kann den Commit im Prüfprotokoll nachsehen.';

  @override
  String get stageProvenancePass =>
      'Die Software stammt aus einem bekannten, geprüften Stand.';

  @override
  String get stageProvenanceWhat =>
      'Die Herkunft: aus welchem Quellcode-Stand (Commit) die laufende Software gebaut wurde und ob er auf der Vertrauensliste steht.';

  @override
  String get stageQuoteInfo =>
      'Der Nachweis wurde nur protokolliert, nicht bewertet.';

  @override
  String get stageQuotePass =>
      'Der Dienst läuft nachweislich in einer echten, abgeschotteten Intel-TDX-Umgebung. Der Betreiber kann den Speicher nicht mitlesen.';

  @override
  String get stageQuoteWhat =>
      'Der Hardware-Nachweis (TDX-Quote) der geschützten Umgebung. Er ist von der CPU signiert und wird gegen die Zertifikate von Intel geprüft.';

  @override
  String get stageReceiptBindingInfo => 'Die Bindung wurde nur protokolliert.';

  @override
  String get stageReceiptBindingPass => 'Quittung und Sitzung passen zusammen.';

  @override
  String get stageReceiptBindingWhat =>
      'Ob die Quittung zur geprüften Sitzung gehört.';

  @override
  String get stageReceiptCompleteInfo =>
      'Die Ereignisse wurden nur protokolliert.';

  @override
  String get stageReceiptCompletePass => 'Die Quittung ist vollständig.';

  @override
  String get stageReceiptCompleteWhat =>
      'Ob die Quittung alle erforderlichen Ereignisse enthält.';

  @override
  String get stageReceiptFetchInfo => 'Der Abruf wurde nur protokolliert.';

  @override
  String get stageReceiptFetchPass =>
      'Der Anbieter hat die Quittung geliefert.';

  @override
  String get stageReceiptFetchWhat =>
      'Der Abruf der signierten Quittung zu dieser Antwort.';

  @override
  String get stageReceiptRequestHashInfo =>
      'Die Prüfsumme wurde nur protokolliert.';

  @override
  String get stageReceiptRequestHashPass =>
      'Der Anbieter hat genau deine Anfrage erhalten.';

  @override
  String get stageReceiptRequestHashWhat =>
      'Die Prüfsumme der Anfrage in der Quittung gegen das, was gesendet wurde.';

  @override
  String get stageReceiptResponseHashInfo =>
      'Die Prüfsumme wurde nur protokolliert.';

  @override
  String get stageReceiptResponseHashPass =>
      'Die Antwort wurde unterwegs nicht verändert.';

  @override
  String get stageReceiptResponseHashWhat =>
      'Die Prüfsumme der Antwort in der Quittung gegen das Empfangene.';

  @override
  String get stageReceiptSigInfo => 'Die Signatur wurde nur protokolliert.';

  @override
  String get stageReceiptSigPass =>
      'Die Quittung stammt aus der geprüften Umgebung.';

  @override
  String get stageReceiptSigWhat => 'Die Signatur der Quittung.';

  @override
  String get stageReleaseFloorInfo =>
      'Der Rückschrittschutz wurde nur protokolliert.';

  @override
  String get stageReleaseFloorPass =>
      'Der Server läuft mit dem bisher neuesten oder einem neueren Release.';

  @override
  String get stageReleaseFloorWhat =>
      'Ob das Release nicht älter ist als das neueste, das Wendelin je geprüft hat (Schutz vor einem Rückschritt auf alte, angreifbare Versionen).';

  @override
  String get stageResponseKeyInfo =>
      'Der Schlüsselsatz wurde nur protokolliert.';

  @override
  String get stageResponseKeyPass =>
      'Die Antwort gehört zur geprüften Sitzung.';

  @override
  String get stageResponseKeyWhat =>
      'Ob der Schlüsselsatz der Antwort zum geprüften Satz passt.';

  @override
  String get stageResultFail => 'fehlgeschlagen';

  @override
  String get stageResultPass => 'bestanden';

  @override
  String get stageSignatureInfo =>
      'Dieser Anbieter liefert keine solche Signatur. Die Bindung der Schlüssel läuft stattdessen über den Hardware-Nachweis (Prüfsumme des Schlüsselsatzes). Das ist ein etwas schwächerer Beleg, aber kein Fehler.';

  @override
  String get stageSignaturePass =>
      'Der Schlüsselsatz ist zusätzlich vom Anbieter signiert.';

  @override
  String get stageSignatureWhat =>
      'Eine zusätzliche Signatur über den Schlüsselsatz, die manche Anbieter liefern.';

  @override
  String get stageSigstoreInfo =>
      'Die Signatur des Releases wurde nur protokolliert.';

  @override
  String get stageSigstorePass =>
      'Das Release stammt aus dem Build von Tinfoil und steht öffentlich im Log.';

  @override
  String get stageSigstoreWhat =>
      'Ob das veröffentlichte Programm-Release von Tinfoil auf GitHub echt signiert und im öffentlichen Transparenzlog (Sigstore) eingetragen ist.';

  @override
  String get stageSnpChainInfo =>
      'Die Zertifikatskette wurde nur protokolliert.';

  @override
  String get stageSnpChainPass =>
      'Die Kette endet bei AMD, nicht bei einem Zertifikat, das jemand unterschoben hat.';

  @override
  String get stageSnpChainWhat =>
      'Ob das Zertifikat des Prozessors über das AMD-Zwischenzertifikat auf den in Wendelin fest hinterlegten AMD-Wurzelschlüssel zurückgeht.';

  @override
  String get stageSnpPolicyInfo => 'Die Richtlinie wurde nur protokolliert.';

  @override
  String get stageSnpPolicyPass =>
      'Die Umgebung ist nicht zum Mitlesen geöffnet und enthält keine bekannt veraltete Firmware.';

  @override
  String get stageSnpPolicyWhat =>
      'Ob die Umgebung ohne Debug-Zugang läuft und Firmware und Prozessor-Microcode mindestens so aktuell sind, wie Wendelin es verlangt (Bootloader 9, SNP 22, Microcode 80).';

  @override
  String get stageSnpReportInfo =>
      'Der Bericht des Prozessors wurde nur protokolliert.';

  @override
  String get stageSnpReportPass =>
      'Ein echter AMD-Prozessor bestätigt den Bericht. Niemand kann ihn nachträglich ändern.';

  @override
  String get stageSnpReportWhat =>
      'Der Hardware-Nachweis des Tinfoil-Servers: Bericht des AMD-Prozessors, sein Zertifikat und die Signatur darüber.';

  @override
  String get stageTcbInfo => 'Der Sicherheitsstand wurde nur protokolliert.';

  @override
  String get stageTcbPass =>
      'Die Plattform hat alle bekannten Sicherheits-Updates.';

  @override
  String get stageTcbWhat =>
      'Der Sicherheitsstand der Plattform (TCB): ob Firmware und Mikrocode auf dem aktuellen Stand sind.';

  @override
  String get stageTlsInfo =>
      'Das Zertifikat der Verbindung wurde nicht mit dem Nachweis verglichen. Dann hängt der Schutz allein an der Ende-zu-Ende-Verschlüsselung.';

  @override
  String get stageTlsPass =>
      'Die Verbindung endet in der geprüften Umgebung, niemand kann sich dazwischenschalten.';

  @override
  String get stageTlsWhat =>
      'Ob die Netzwerkverbindung genau zu dem Schlüssel führt, der im Hardware-Nachweis steht (Pinning).';

  @override
  String get stageUnavailableMeaning =>
      'Die Prüfung konnte nicht abgeschlossen werden (zum Beispiel wegen des Netzes). Sie wird später wiederholt. Bis dahin ist die Stufe unbestätigt.';

  @override
  String get stageUpstreamInfo =>
      'Die Upstream-Prüfung wurde nur protokolliert.';

  @override
  String get stageUpstreamPass =>
      'Auch das Modell hinter dem Gateway wurde nachweislich geprüft.';

  @override
  String get stageUpstreamTcbInfo => 'Der Stand wurde nur protokolliert.';

  @override
  String get stageUpstreamTcbPass =>
      'Auch diese Plattform ist auf aktuellem Stand.';

  @override
  String get stageUpstreamTcbWhat =>
      'Der Sicherheitsstand der Plattform hinter dem Gateway.';

  @override
  String get stageUpstreamWhat =>
      'Ob das Gateway bestätigt, dass das Modell dahinter in einer geprüften Umgebung lief.';

  @override
  String get stageWarnMeaning =>
      'Die Prüfung ist bestanden, aber mit einem Hinweis (zum Beispiel ein ausstehendes Sicherheits-Update des Betreibers). Das schwächt den Schutz etwas. Es bleibt im Prüfprotokoll sichtbar.';

  @override
  String get bringApiError => 'Fehler – Schnittstelle nicht erreichbar';

  @override
  String get bringApp => 'Bring!-App';

  @override
  String get bringChecking => 'Prüfe …';

  @override
  String get bringConnected => 'Verbunden';

  @override
  String get bringEmail => 'E-Mail';

  @override
  String get bringFine => 'in Ordnung';

  @override
  String get bringInstalled => 'Installiert';

  @override
  String get bringIntro =>
      'Inoffizielle Schnittstelle: Bring! hat sie nicht für andere Apps freigegeben, sie kann jederzeit brechen. Du meldest dich einmal an; E-Mail und Passwort werden nicht gespeichert, nur die Sitzung (Tokens) bleibt im sicheren Speicher des Geräts.';

  @override
  String get bringNeedCredentials => 'Bitte E-Mail und Passwort eingeben.';

  @override
  String get bringNotInstalled => 'Nicht installiert';

  @override
  String get bringPassword => 'Passwort';

  @override
  String get bringReachable => 'Bring! ist wieder erreichbar.';

  @override
  String get bringReauthError =>
      'Bring!: Anmeldung abgelaufen. Bitte neu anmelden.';

  @override
  String get bringReconnect => 'Erneut verbinden';

  @override
  String get bringShareSend => 'An Bring! senden';

  @override
  String get bringShareSent => 'An Bring! gesendet';

  @override
  String get bringShareUnreachable => 'Bring! nicht erreichbar';

  @override
  String get bringSignOutBody => 'Die Sitzung wird vom Gerät gelöscht.';

  @override
  String get bringSignOutTitle => 'Bei Bring! abmelden?';

  @override
  String get bringSigningIn => 'Anmelden …';

  @override
  String get bringStatusAvailable => 'Angemeldet, Integration ausgeschaltet';

  @override
  String get bringStatusSetup => 'Login fehlt';

  @override
  String get bringStatusUnavailable => 'Nicht verfügbar';

  @override
  String get bringStatusUnknown => 'Unbekannt';

  @override
  String get bringUnknown => 'Unbekannt';

  @override
  String get add => 'Hinzufügen';

  @override
  String get allow => 'Erlauben';

  @override
  String get appLanguageDetail =>
      'Sprache der Oberfläche; unabhängig von Spracheingabe und -ausgabe';

  @override
  String get appLanguageIntro =>
      'Wähle die Sprache der Oberfläche. Sie gilt für die ganze App und das Overlay. Welche Sprache du sprichst und hörst, stellst du unter „Sprache“ ein.';

  @override
  String get appLanguageSystem => 'System';

  @override
  String get appLanguageSystemDetail => 'Folgt der Sprache des Telefons';

  @override
  String get appLanguageTitle => 'App-Sprache';

  @override
  String get appName => 'Wendelin';

  @override
  String get back => 'Zurück';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get close => 'Schließen';

  @override
  String get confirmCardNeedsConfirm => 'Braucht deine Bestätigung';

  @override
  String confirmCardToolLevel(String toolName, String level) {
    return '$toolName · Stufe $level';
  }

  @override
  String get confirmCardWarning => 'Warnung';

  @override
  String get confirmed => 'Bestätigt';

  @override
  String get copy => 'Kopieren';

  @override
  String get delete => 'Löschen';

  @override
  String get deny => 'Ablehnen';

  @override
  String get details => 'Details';

  @override
  String get done => 'Fertig';

  @override
  String get edit => 'Bearbeiten';

  @override
  String get error => 'Fehler';

  @override
  String get export => 'Exportieren';

  @override
  String get followUpListening => 'Ich höre noch zu …';

  @override
  String get import => 'Importieren';

  @override
  String get later => 'Später';

  @override
  String get momentPlease => 'Moment …';

  @override
  String get name => 'Name';

  @override
  String get next => 'Weiter';

  @override
  String get no => 'Nein';

  @override
  String get off => 'Aus';

  @override
  String get ok => 'OK';

  @override
  String get on => 'An';

  @override
  String get open => 'Öffnen';

  @override
  String get remove => 'Entfernen';

  @override
  String get reset => 'Zurücksetzen';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get save => 'Speichern';

  @override
  String get search => 'Suchen';

  @override
  String get selected => 'gewählt';

  @override
  String get send => 'Senden';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get share => 'Teilen';

  @override
  String get start => 'Starten';

  @override
  String get test => 'Testen';

  @override
  String get understood => 'Verstanden';

  @override
  String get yes => 'Ja';

  @override
  String get confCallTitle => 'Anrufen?';

  @override
  String get confHintVoiceCall => 'Sag „anrufen“ oder „abbrechen“';

  @override
  String get confHintVoiceEdited =>
      'Du hast den Text geändert: bitte per Tipp absenden';

  @override
  String get confHintVoiceSms => 'Sag „absenden“ oder „abbrechen“';

  @override
  String get confNoCancel => 'Abbrechen';

  @override
  String get confSmsNoText => 'Die Nachricht darf nicht leer sein.';

  @override
  String get confSmsTextLabel => 'Nachricht';

  @override
  String get confSmsTitle => 'SMS absenden?';

  @override
  String confSmsTo(String name) {
    return 'An $name';
  }

  @override
  String get confYesCall => 'Anrufen';

  @override
  String get confYesSend => 'Absenden';

  @override
  String get integrationsContactsRationale =>
      'Wendelin braucht Zugriff auf deine Kontakte, um Nummern nach Namen zu finden, und die Rechte für SMS und Telefon. Android fragt dich gleich danach. Wendelin sendet nie eine SMS und ruft nie an, ohne dass du vorher die Vorschau mit Name und Nummer bestätigt hast (per Tipp oder mit „ja“). Bei gesperrtem Gerät geht beides nie. Ohne Telefonrecht öffnet Wendelin nur den Wählbildschirm.';

  @override
  String get batteryAllow => 'Keine Einschränkung erlauben';

  @override
  String get batteryChecklistNote =>
      'Android lässt diese Einstellungen nicht auslesen. Das ist eine Checkliste, kein Status.';

  @override
  String get batteryHuaweiBody =>
      'Stelle „App-Start“ für Wendelin auf „Manuell verwalten“ und erlaube Autostart, Zweitstart und Hintergrundaktivität.';

  @override
  String get batteryHuaweiTitle => 'Huawei / Honor';

  @override
  String get batteryOnePlusBody =>
      'Erlaube Wendelin den Autostart und stelle die Akku-Optimierung für Wendelin auf „Nicht optimieren“ (Einstellungen → Apps → Wendelin → Akku).';

  @override
  String get batteryOnePlusTitle => 'OnePlus';

  @override
  String get batteryOpenSettings => 'Akku-Einstellungen öffnen';

  @override
  String get batteryOptimizedDetail =>
      'Android kann Wendelin im Hintergrund beenden. Nach längerer Pause öffnet die Power-Taste den Assistenten dann womöglich nicht, bis du die App einmal geöffnet hast.';

  @override
  String get batteryOptimizedTitle => 'Akku-Optimierung aktiv';

  @override
  String get batteryReliable => 'Zuverlässig öffnen';

  @override
  String get batterySamsungBody =>
      'Nimm Wendelin aus „Schlafende Apps“ heraus und stelle den Akku für Wendelin auf „Nicht eingeschränkt“ (Einstellungen → Akku → Hintergrundnutzungsgrenzen).';

  @override
  String get batterySamsungTitle => 'Samsung';

  @override
  String get batterySettingsNotOpened =>
      'Die Systemeinstellungen ließen sich nicht öffnen.';

  @override
  String get batteryStandbyDetail =>
      'Android verzögert Starts im Hintergrund für selten genutzte Apps. Öffne Wendelin ab und zu oder erlaube „Keine Einschränkung“.';

  @override
  String get batteryStandbyRare => 'App-Standby: selten genutzt';

  @override
  String get batteryStandbyRestricted => 'App-Standby: eingeschränkt';

  @override
  String get batteryVendorSettings => 'Einstellungen des Herstellers öffnen';

  @override
  String get batteryXiaomiBody =>
      'Schalte für Wendelin „Autostart“ ein und stelle den Akkusparer für Wendelin auf „Keine Einschränkungen“ (Einstellungen → Apps → Berechtigungen → Autostart; Einstellungen → Apps → Wendelin → Akkusparer).';

  @override
  String get batteryXiaomiTitle => 'Xiaomi / HyperOS / MIUI';

  @override
  String get devDemoMode => 'Demo-Modus (ohne Provider)';

  @override
  String get devDemoModeLabel => 'Demo-Modus';

  @override
  String get devGallery => 'Design-Galerie';

  @override
  String get devSection => 'Entwicklung';

  @override
  String integrationsErrDenied(String service) {
    return '$service: Zugang abgelehnt oder abgelaufen · pausiert';
  }

  @override
  String integrationsErrFailed(String service) {
    return '$service: unerwartete Antwort · pausiert';
  }

  @override
  String integrationsErrUnavailable(String service) {
    return '$service ist nicht erreichbar · pausiert';
  }

  @override
  String get haAddressLabel => 'Adresse';

  @override
  String get haAlwaysConfirm => 'Immer bestätigen';

  @override
  String get haAlwaysConfirmHelp =>
      'Wendelin fragt vor jedem Schalten nach (z. B. Herd, Ofen).';

  @override
  String haAlwaysConfirmSemantics(String name, String label) {
    return '$name: $label';
  }

  @override
  String haApproved(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Geräte freigegeben',
      one: '1 Gerät freigegeben',
    );
    return '$_temp0';
  }

  @override
  String get haConnect => 'Verbinden';

  @override
  String get haConnected => 'Verbunden';

  @override
  String get haConnecting => 'Verbinde …';

  @override
  String get haDevices => 'Geräte freigeben';

  @override
  String get haDevicesHelp =>
      'Nur die gewählten Geräte kennt Wendelin. Schlösser, Alarmanlagen und Tore fragen immer vorher nach.';

  @override
  String get haDisconnect => 'Trennen';

  @override
  String get haDisconnectMessage =>
      'Adresse, Token und die Auswahl der Geräte werden vom Gerät gelöscht.';

  @override
  String get haDisconnectTitle => 'Home Assistant trennen?';

  @override
  String haEntityAlwaysAsks(String entityId) {
    return '$entityId · fragt immer nach';
  }

  @override
  String get haErrorTitle => 'Fehler – nicht erreichbar';

  @override
  String get haFastPath => 'Einfache Befehle sofort ausführen';

  @override
  String get haFastPathHelp =>
      '„Rollo Wohnzimmer runter“ oder „Küche Deckenlicht aus“ führt Wendelin ohne KI aus, mit denselben Regeln. Schlösser, Alarmanlagen, Tore und Geräte mit „Immer bestätigen“ gehen nie so. Bei Unklarem fragt wie bisher die KI.';

  @override
  String get haFilter => 'Geräte filtern';

  @override
  String get haFound => 'Gefunden';

  @override
  String get haGone => 'Nicht mehr in Home Assistant';

  @override
  String get haHttpNote =>
      'Unverschlüsseltes http ist nur im Heimnetz, über Tailscale (100.x, *.ts.net) und bei *.local erlaubt, sonst nur https. Über Tailscale wird nichts automatisch gefunden: Adresse von Hand eingeben.';

  @override
  String get haInputMissing => 'Bitte Adresse und Token eingeben.';

  @override
  String get haIntro =>
      'Wendelin steuert deine freigegebenen Geräte über die Schnittstelle deines Home Assistant. Nur im Heimnetz oder über Tailscale. Adresse und Token bleiben im sicheren Speicher des Geräts.';

  @override
  String get haNoAsk => 'Ohne Rückfrage';

  @override
  String get haNoAskHelp =>
      'Wendelin bewegt dieses Rollo ohne Nachfrage (mit Rückgängig). Nur für Rollos, Jalousien, Markisen und Vorhänge; Garagentore und Türen fragen immer.';

  @override
  String get haNoDevices => 'Keine Geräte gefunden.';

  @override
  String get haNoRoom => 'Ohne Raum';

  @override
  String get haNothingFound =>
      'Nichts gefunden. Adresse von Hand eingeben (bei Tailscale nötig).';

  @override
  String get haReachable => 'Home Assistant ist erreichbar.';

  @override
  String get haReload => 'Geräte neu laden';

  @override
  String get haRemoveGone => 'Entfernen';

  @override
  String get haSearch => 'Im WLAN suchen';

  @override
  String get haSearching => 'Suche …';

  @override
  String get haTitle => 'Home Assistant';

  @override
  String get haTokenHelp =>
      'In Home Assistant: Profil → Sicherheit → Langlebige Zugriffstokens.';

  @override
  String get haTokenLabel => 'Long-Lived Access Token';

  @override
  String get httpArgsAddArg => '+ Argument';

  @override
  String get httpArgsArgs => 'Argumente';

  @override
  String get httpArgsCustomSchema => 'Eigenes JSON-Schema';

  @override
  String get httpArgsCustomSchemaDetail => 'Statt der einfachen Liste';

  @override
  String get httpArgsCustomSchemaSem => 'Eigenes JSON-Schema';

  @override
  String get httpArgsDescription => 'Beschreibung';

  @override
  String get httpArgsRemoveArg => 'Argument entfernen';

  @override
  String get httpArgsRequired => 'Pflicht';

  @override
  String httpArgsRequiredNamed(String name) {
    return 'Pflicht $name';
  }

  @override
  String get httpArgsSchema => 'JSON-Schema';

  @override
  String get httpAuthAddSecretHeader => '+ Geheimer Header';

  @override
  String get httpAuthKeepStored => 'Leer lassen behält den gespeicherten';

  @override
  String get httpAuthRemoveSecretHeader => 'Geheimen Header entfernen';

  @override
  String get httpAuthSecretHeader => 'Geheimer Header, z. B. X-Api-Key';

  @override
  String httpAuthStored(String redactedSecret) {
    return '$redactedSecret gespeichert';
  }

  @override
  String httpEditorDeleteBody(String v) {
    return '„http__$v“ und seine gespeicherten Secrets werden gelöscht.';
  }

  @override
  String get httpEditorDeleteTitle => 'HTTP-Tool löschen?';

  @override
  String get httpEditorNewTool => 'Neues HTTP-Tool';

  @override
  String get httpEditorTool => 'HTTP-Tool';

  @override
  String httpPhUnknown(String v) {
    return '$v unbekannt';
  }

  @override
  String get httpRunAskElse => 'Sonst fragt Wendelin vor jedem Aufruf nach';

  @override
  String get httpRunExecution => 'Ausführung';

  @override
  String get httpRunHomeTarget => 'Heimnetz-Ziel';

  @override
  String get httpRunHomeTargetDetail =>
      'Darf auf private Adressen zeigen, dann auch http';

  @override
  String get httpRunHomeTargetSem => 'Heimnetz-Ziel';

  @override
  String httpRunLevel(String verb, String name) {
    return 'Stufe (Vorschlag für $verb: $name)';
  }

  @override
  String get httpRunNoAsk => 'Ohne Nachfrage ausführen (kein Rückgängig)';

  @override
  String get httpRunNoAskSem => 'Ohne Nachfrage ausführen';

  @override
  String get httpRunOnlyWrite => 'Nur bei POST/PUT/PATCH mit Stufe write';

  @override
  String get httpRunSensitiveDetail =>
      'Nur an Provider ab der Stufe für sensible Integrationen';

  @override
  String get httpRunTimeout => 'Zeitlimit in Sekunden';

  @override
  String get httpSrcAddHeader => '+ Header';

  @override
  String httpSrcBodyHelp(String example) {
    return '$example wird typgerecht ersetzt; leer = kein Body';
  }

  @override
  String get httpSrcBodyTemplate => 'Body-Vorlage (JSON)';

  @override
  String get httpSrcForm => 'Formular';

  @override
  String get httpSrcHeader => 'Header';

  @override
  String get httpSrcHeaderDetail =>
      'Nicht geheim; Tokens gehören in die Anmeldung';

  @override
  String get httpSrcJson => 'JSON';

  @override
  String get httpSrcRemoveHeader => 'Header entfernen';

  @override
  String httpSrcUrlHelp(String example) {
    return 'Platzhalter wie $example nur in Pfad und Query, Host fest';
  }

  @override
  String get httpSrcUrlTemplate => 'URL-Vorlage';

  @override
  String httpTestArgLabel(String name, String type) {
    return '$name ($type)';
  }

  @override
  String get httpTestFailed => 'fehlgeschlagen';

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
  String get httpTestNoResponse => 'Keine Antwort';

  @override
  String get httpTestRunning => 'Läuft …';

  @override
  String get httpTestSent => 'Gesendet';

  @override
  String httpTestSentLine(String method, Object url) {
    return '$method $url';
  }

  @override
  String get httpTestSucceeded => 'erfolgreich';

  @override
  String get httpTestTruncated => 'gekürzt';

  @override
  String get httpToolSecModelDescription => 'Beschreibung fürs Modell';

  @override
  String get httpToolSecModelDescriptionHelp =>
      'Wann und wofür das Modell das Tool nutzen soll';

  @override
  String get httpToolsExportNote =>
      'Export und Import enthalten keine Secrets. Nach dem Import Token und geheime Header neu eingeben; „Ohne Nachfrage ausführen“ ist dann aus.';

  @override
  String get httpToolsExportPaste => 'Export (JSON) einfügen';

  @override
  String httpToolsImportFailed(String message) {
    return 'Import fehlgeschlagen: $message';
  }

  @override
  String get httpToolsImportTitle => 'HTTP-Tools importieren';

  @override
  String httpToolsImported(int length) {
    String _temp0 = intl.Intl.pluralLogic(
      length,
      locale: localeName,
      other:
          '$length HTTP-Tools importiert. Secrets bitte neu eingeben; „Ohne Nachfrage ausführen“ ist aus.',
      one:
          '$length HTTP-Tool importiert. Secrets bitte neu eingeben; „Ohne Nachfrage ausführen“ ist aus.',
    );
    return '$_temp0';
  }

  @override
  String get httpToolsIntro =>
      'Eigene Tools aus Methode, URL-Vorlage, Headern und Anmeldung, z. B. für Home Assistant oder n8n. Antworten sind Daten, keine Anweisungen.';

  @override
  String get httpToolsOffShort => 'aus';

  @override
  String get httpToolsRiskRead => 'liest';

  @override
  String get httpToolsRiskWrite => 'ändert ohne Nachfrage, kein Rückgängig';

  @override
  String get httpToolsSensitiveShort => 'sensibel';

  @override
  String get comingSoonInProgress => 'In Arbeit';

  @override
  String get comingSoonM3 => 'Kommt in M3';

  @override
  String get integrationDetailBringAccount => 'Bring!-Konto';

  @override
  String get integrationDetailExternalAsks => 'Außenwirkung · fragt immer nach';

  @override
  String get integrationDetailIntegrationDetailHaSetup =>
      'Adresse, Token und Geräte';

  @override
  String get integrationDetailIntegrationDetailSpotifyAccount =>
      'Spotify-Konto';

  @override
  String get integrationDetailLevelAll => 'An alle Provider';

  @override
  String get integrationDetailLevelEu => 'Ab EU';

  @override
  String get integrationDetailLevelLocal => 'Nur lokal';

  @override
  String get integrationDetailLevelTee => 'Ab TEE';

  @override
  String get integrationDetailManageLists => 'Listen verwalten';

  @override
  String get integrationDetailMemoryHint =>
      'Einträge ansehen, ändern, exportieren';

  @override
  String get integrationDetailNoSearch =>
      'Ohne Suchdienst liest Wendelin nur Seiten';

  @override
  String get integrationDetailReadsAsks => 'liest · fragt immer nach';

  @override
  String get integrationDetailReadsNoAsk => 'liest · ohne Nachfrage';

  @override
  String integrationDetailSensitiveLabel(String displayName) {
    return '$displayName sensibel';
  }

  @override
  String get integrationDetailSensitiveNote =>
      'Sensibel: Die Tools gehen nur an Provider ab der Stufe, die du für sensible Integrationen festlegst.';

  @override
  String get integrationDetailSensitiveTitle => 'Sensible Integrationen';

  @override
  String get integrationDetailSetUpSearch => 'Suchdienst einrichten';

  @override
  String get integrationDetailTapTool =>
      'Tippe auf ein Tool, um „Immer nachfragen“ ein- oder auszuschalten.';

  @override
  String get integrationDetailTitle => 'Integration';

  @override
  String get integrationDetailVaultDaily => 'Vault und Tagesnotizen';

  @override
  String get integrationDetailViewMemory => 'Gedächtnis ansehen';

  @override
  String get integrationDetailWritesAsks => 'ändert · fragt immer nach';

  @override
  String get integrationDetailWritesNoUndo =>
      'ändert · ohne Nachfrage, kein Rückgängig';

  @override
  String get integrationDetailWritesUndo =>
      'ändert · ohne Nachfrage, 10 s rückgängig';

  @override
  String integrationTileActiveDetail(String detail) {
    return 'Aktiv · $detail';
  }

  @override
  String get integrationTileAvailable => 'Verfügbar';

  @override
  String get integrationTileInStore => 'Im Store';

  @override
  String get integrationTileOnlyFrom => 'Nur an Provider ab';

  @override
  String get integrationTileSetupNeeded => 'Einrichtung nötig';

  @override
  String get integrationsAddHttp => '+ HTTP-Tool';

  @override
  String get integrationsAddMcp => '+ MCP-Server';

  @override
  String get integrationsAppMissing => 'App nicht installiert';

  @override
  String get integrationsCalendarRationale =>
      'Wendelin braucht Zugriff auf deine Kalender, um Termine zu lesen, anzulegen und zu ändern. Android fragt dich gleich danach. Löschen fragt Wendelin immer vorher nach.';

  @override
  String get integrationsHintBring =>
      'Bring!-App fehlt: kein Ausweg über „Teilen“';

  @override
  String get integrationsHintObsidian =>
      'Obsidian-App fehlt: Öffnen in Obsidian geht nicht';

  @override
  String get integrationsHintSpotify =>
      'Spotify-App fehlt: Wiedergabe nur auf anderen Geräten';

  @override
  String get integrationsIntro =>
      'Nur aktive Integrationen gehen ans Modell. Ausgeschaltete kosten keine Tokens.';

  @override
  String get integrationsOwn => 'Eigene Integrationen';

  @override
  String get integrationsPaused => 'pausiert';

  @override
  String integrationsPausedError(String service) {
    return '$service: Zugang abgelehnt oder unerwartete Antwort · pausiert';
  }

  @override
  String get integrationsPermission => 'Berechtigung';

  @override
  String get integrationsPermission2 => 'Berechtigung';

  @override
  String integrationsReachable(String displayName) {
    return '$displayName ist wieder erreichbar.';
  }

  @override
  String integrationsRejected(String reason) {
    return 'Abgewiesen: $reason';
  }

  @override
  String integrationsTools(int tools) {
    return '$tools Tools';
  }

  @override
  String get reconnectBringShare =>
      'Ausweg: Artikel über „Teilen“ an die Bring!-App schicken.';

  @override
  String reconnectErrDenied(String service) {
    return '$service: Zugang abgelehnt oder nicht eingerichtet. Bitte die Zugangsdaten prüfen.';
  }

  @override
  String reconnectErrFailed(String service) {
    return '$service: Die Verbindung ist fehlgeschlagen (unerwartete Antwort).';
  }

  @override
  String reconnectErrOther(String service) {
    return '$service: Die Verbindung ist fehlgeschlagen.';
  }

  @override
  String reconnectErrUnavailable(String service) {
    return '$service ist nicht erreichbar oder antwortet nicht. Später erneut versuchen.';
  }

  @override
  String get listsAccessLost => 'Kein Zugriff mehr – Datei neu auswählen';

  @override
  String get listsAdd => '+ Liste';

  @override
  String get listsAliases => 'Andere Namen, mit Komma getrennt (optional)';

  @override
  String listsAlso(String v) {
    return 'auch: $v';
  }

  @override
  String get listsChooseFile => 'Datei wählen';

  @override
  String get listsDeleteBody =>
      'Die Liste verschwindet aus Wendelin. Die Datei bleibt erhalten.';

  @override
  String get listsDeleteList => 'Liste löschen';

  @override
  String listsDeleteTitle(String name) {
    return '„$name“ löschen?';
  }

  @override
  String get listsEditList => 'Liste bearbeiten';

  @override
  String get listsFile => 'Datei';

  @override
  String get listsIntro =>
      'Jede Liste ist eine Markdown-Datei auf dem Gerät (z. B. im Obsidian-Vault). Einträge stehen dort als „- [ ] …“.';

  @override
  String get listsListFallback => 'Liste';

  @override
  String get listsNameHint => 'Name, z. B. Einkaufen';

  @override
  String get listsNeedNameFile => 'Name und Datei sind nötig.';

  @override
  String get listsNewFile => 'Neue Datei';

  @override
  String get listsNewList => 'Neue Liste';

  @override
  String get listsNoAliases => 'Ohne Aliase';

  @override
  String get listsNoFile => 'Noch keine Datei';

  @override
  String listsSection(String section) {
    return 'Abschnitt „$section“';
  }

  @override
  String get listsSectionLabel =>
      'Abschnitt in der Datei, z. B. Todo (optional)';

  @override
  String get listsTaskDefault => 'Standard-Aufgabenliste';

  @override
  String get listsTaskDefaultDetail =>
      'Aufgaben mit Fälligkeit landen hier, wenn keine Liste genannt wird.';

  @override
  String get integrationsLocationRationale =>
      'Damit Wendelin sagen kann, wo du bist, und Entfernungen und Navigation vorbereiten kann, braucht es den Standortzugriff. Android fragt dich gleich danach. Wendelin fragt den Standort nur, wenn du danach fragst (nie im Hintergrund), schickt ihn nicht an Cloud-Modelle unterhalb deiner Datenschutzstufe und schreibt ihn nicht ins Prüfprotokoll. „Ungefähr“ reicht für Ortsnamen und Luftlinie.';

  @override
  String confHandOverDetail(String toName, String fromName) {
    return '$toName hat eine niedrigere Datenschutzstufe als $fromName. Deine Anfrage und der bisherige Verlauf gehen dann dorthin.';
  }

  @override
  String confHandOverTitle(String toName) {
    return 'An $toName übergeben?';
  }

  @override
  String get confHintTap => 'Antworte per Tipp';

  @override
  String get confHintVoice => 'Sag einfach „ja“ oder „nein“';

  @override
  String confMoreLines(int rest) {
    return '… $rest weitere Zeilen';
  }

  @override
  String get confYesHandOver => 'Ja, übergeben';

  @override
  String get mainCancelListening => 'Zuhören abbrechen';

  @override
  String get mainCheckProvider => 'Provider prüfen';

  @override
  String mainCostLabel(String costLabel) {
    return 'Kosten $costLabel';
  }

  @override
  String mainCostToday(String v) {
    return 'heute $v';
  }

  @override
  String get mainDeleteEventTitle => 'Termin löschen?';

  @override
  String mainFollowUpCountdown(String followUpListeningText, int seconds) {
    return '$followUpListeningText $seconds s';
  }

  @override
  String mainGpuBlockMessage(String name, String v) {
    return 'Die GPU-Prüfung von $name über NVIDIA ist fehlgeschlagen oder nicht möglich.$v Deine Anfrage wurde nicht gesendet. Du kannst sie einmalig ohne GPU-Prüfung senden. Die übrigen Prüfungen bleiben aktiv.';
  }

  @override
  String get mainGpuCheckFailedTitle => 'GPU-Prüfung nicht bestanden';

  @override
  String get mainListening => 'Ich höre zu …';

  @override
  String get mainMicCancelAnswer => 'Antwort abbrechen';

  @override
  String get mainMicHearing =>
      'Wendelin hört mit: „Wendelin“ sagen oder tippen';

  @override
  String get mainMicSpeak => 'Sprechen';

  @override
  String get mainMicStopListening => 'Zuhören beenden';

  @override
  String get mainMicStopSpeech => 'Sprachausgabe stoppen';

  @override
  String get mainMicUnavailable => 'Mikrofon nicht verfügbar';

  @override
  String get mainNeedsModel =>
      'Wendelin braucht ein Sprachmodell. Richte einen Provider mit deinem API-Key ein, danach kannst du loslegen.';

  @override
  String get mainNewConversation => 'Neues Gespräch';

  @override
  String get mainNoKeep => 'Nein, behalten';

  @override
  String get mainNoProviderYet => 'Noch kein Provider eingerichtet';

  @override
  String mainProviderProfileUnusable(String error) {
    return 'Das Provider-Profil lässt sich nicht verwenden: $error';
  }

  @override
  String get mainReallyDeleteTitle => 'Wirklich löschen?';

  @override
  String get mainSendWithoutGpuCheck => 'Ohne GPU-Prüfung senden';

  @override
  String get mainSetUpProvider => 'Provider einrichten';

  @override
  String get mainShouldIDoThat => 'Soll ich das tun?';

  @override
  String get mainStartDemo => 'Demo ohne Provider starten';

  @override
  String get mainToday => 'Heute';

  @override
  String get mainTypeInstead => 'Schreiben statt sprechen';

  @override
  String get mainViewRouting => 'Routing ansehen';

  @override
  String get mainYesDelete => 'Ja, löschen';

  @override
  String get mainYesDoIt => 'Ja, ausführen';

  @override
  String get mainYesterday => 'Gestern';

  @override
  String get overlayCloseAssistant => 'Assistent schließen';

  @override
  String get overlayEnd => 'Beenden';

  @override
  String get overlayFollowUpComing =>
      'Gesprächsmodus aus · in den Einstellungen einschaltbar';

  @override
  String overlayFollowUpWindow(int seconds) {
    return 'Hört noch $seconds s zu · „Stopp“ beendet';
  }

  @override
  String get overlayKeepTalking => 'Weiter sprechen';

  @override
  String get overlayLockedText =>
      'Auf dem Sperrbildschirm zeigt und sagt Wendelin nichts aus deinen Daten. Nur die Taschenlampe geht auch gesperrt. Alles andere erst nach dem Entsperren.';

  @override
  String get overlayLockedTitle => 'Gerät entsperren';

  @override
  String get overlayTextInput => 'Texteingabe';

  @override
  String get overlayUnlock => 'Entsperren';

  @override
  String get overlayUnlockCancelled =>
      'Entsperren abgebrochen. Deine Anfrage wurde verworfen.';

  @override
  String privateBannerConfidential(String since) {
    return 'Vertraulich: Gedächtnis genutzt (seit $since)';
  }

  @override
  String privateBannerPrivate(String since) {
    return 'Unterhaltung privat (seit $since)';
  }

  @override
  String privateEscalationMemory(String since, String toName) {
    return 'Die Unterhaltung nutzt dein Gedächtnis (seit $since). Mit „Ja“ sieht $toName den bisherigen Verlauf, aber nicht das Gedächtnis selbst.';
  }

  @override
  String privateEscalationPrivate(String since, String toName) {
    return 'Die Unterhaltung ist privat (seit $since). Mit „Ja“ sieht $toName auch ihre privaten Teile.';
  }

  @override
  String retryOfferDetail(String fromName, String toName) {
    return '$fromName antwortet gerade nicht. $toName schützt deine Daten mindestens so gut. Schon ausgeführte Aktionen werden nicht wiederholt, nur die Antwort wird neu angefragt.';
  }

  @override
  String retryOfferSpoken(String fromName, String toName) {
    return '$fromName antwortet nicht. Mit $toName nochmal? Ja oder nein?';
  }

  @override
  String retryOfferTitle(String toName) {
    return 'Mit $toName nochmal?';
  }

  @override
  String retryOfferYes(String toName) {
    return 'Mit $toName nochmal?';
  }

  @override
  String get switchTopicBody =>
      'Beim Wechsel des Modells beginnt ein neues Gespräch. Der aktuelle Verlauf wird beendet (im Verlauf bleibt er abrufbar).';

  @override
  String get switchTopicBodyRunning =>
      'Beim Wechsel des Modells beginnt ein neues Gespräch. Die laufende Antwort wird abgebrochen und der aktuelle Verlauf beendet (im Verlauf bleibt er abrufbar).';

  @override
  String get switchTopicSwitch => 'Wechseln';

  @override
  String get switchTopicTitle => 'Neues Gespräch beginnen?';

  @override
  String get mcpAddClientId => 'Client-ID (optional)';

  @override
  String get mcpAddClientIdHint =>
      'Leer lassen: Wendelin registriert sich selbst beim Server';

  @override
  String get mcpAddConfirmAll => 'Alle Tools bestätigen';

  @override
  String get mcpAddConfirmAllHint => 'Jeder Aufruf fragt nach';

  @override
  String get mcpAddCustom => 'Eigener Server';

  @override
  String get mcpAddHeaderLabel => 'Header, z. B. X-Api-Key';

  @override
  String get mcpAddProblem => 'Problem';

  @override
  String get mcpAddSensitive => 'Sensibel';

  @override
  String get mcpAddSensitiveHint =>
      'Tools nur an Provider ab der eingestellten Stufe';

  @override
  String get mcpAddServerAddress => 'Adresse';

  @override
  String get mcpAddServerInsecure =>
      'Unverschlüsselt (http): nur im Heimnetz oder über Tailscale erlaubt';

  @override
  String get mcpAddServerIntro =>
      'Wähle eine Vorlage oder trage einen eigenen Server ein. Erreichbar über https oder im Heimnetz (Tailscale, WireGuard).';

  @override
  String get mcpAddServerTestConnection => 'Verbindung prüfen';

  @override
  String get mcpAddServerTitle => 'Server hinzufügen';

  @override
  String get mcpAddSignIn => 'Anmeldung';

  @override
  String get mcpAddTokenHint => 'Wird nie wieder angezeigt';

  @override
  String get mcpAddValue => 'Wert';

  @override
  String get mcpAddValueHint => 'Wird nie wieder angezeigt';

  @override
  String get mcpCheckHeaderMissing => 'Bitte den Namen des Headers angeben.';

  @override
  String get mcpCheckNameMissing => 'Bitte einen Namen angeben.';

  @override
  String get mcpCheckPlaceholders =>
      'Bitte die Platzhalter in <…> in der Adresse ersetzen.';

  @override
  String get mcpCheckUrlIncomplete =>
      'Bitte eine vollständige Adresse angeben (https://…).';

  @override
  String get mcpDetailActive => 'Server aktiv';

  @override
  String mcpDetailActiveLabel(String name) {
    return '$name aktiv';
  }

  @override
  String get mcpDetailAuthLabel => 'Anmeldung nötig';

  @override
  String get mcpDetailBearer => 'Bearer-Token';

  @override
  String mcpDetailCheck(String v) {
    return 'Prüfung: $v';
  }

  @override
  String mcpDetailCheck2(String v) {
    return 'Prüfung: $v';
  }

  @override
  String get mcpDetailConfirmAll => 'Alle Tools bestätigen';

  @override
  String get mcpDetailConfirmAllHint =>
      'Jeder Aufruf fragt nach, egal was der Server angibt';

  @override
  String get mcpDetailDelete => 'Server löschen';

  @override
  String get mcpDetailDeleteBody =>
      'Konfiguration, Tool-Liste und alle Zugangsdaten dieses Servers werden entfernt.';

  @override
  String get mcpDetailDeleteHint =>
      'Entfernt Konfiguration, Tool-Liste und Zugangsdaten';

  @override
  String mcpDetailDeleteTitle(String name) {
    return '„$name“ löschen?';
  }

  @override
  String mcpDetailIntro(String url) {
    return 'Tool-Argumente gehen an diesen Server: $url';
  }

  @override
  String get mcpDetailIntroHint =>
      'Tippe auf ein Tool für Nachfrage und Risikostufe. MCP-Tools haben kein Rückgängig: Änderungen passieren auf dem Server.';

  @override
  String mcpDetailLastCheck(String v) {
    return 'Letzte Prüfung: $v';
  }

  @override
  String get mcpDetailNeverShown => 'Wird nie wieder angezeigt';

  @override
  String get mcpDetailNoTools => 'Noch keine Tools';

  @override
  String get mcpDetailNoToolsHint => 'Server einschalten oder neu laden';

  @override
  String get mcpDetailOauthHint => 'OAuth-Anmeldung im Browser';

  @override
  String mcpDetailReplaceHeader(String header) {
    return 'Header $header ersetzen';
  }

  @override
  String get mcpDetailReplaceToken => 'Token ersetzen';

  @override
  String get mcpDetailSensitive => 'Sensibel';

  @override
  String get mcpDetailSensitiveHint =>
      'Persönliche Daten: Tools nur an Provider ab der eingestellten Stufe';

  @override
  String mcpDetailSensitiveLabel(String name) {
    return '$name sensibel';
  }

  @override
  String get mcpDetailSignIn => 'Anmelden';

  @override
  String get mcpDetailSignInAgain => 'Neu anmelden';

  @override
  String get mcpDetailSignOut => 'Abmelden';

  @override
  String get mcpDetailSignOutHint => 'Vergisst die Tokens auf diesem Gerät';

  @override
  String get mcpDetailTools => 'Tools';

  @override
  String get mcpDetailUnreachableLabel => 'nicht erreichbar';

  @override
  String mcpDetailValueFor(String header) {
    return 'Wert für $header';
  }

  @override
  String get mcpDetailValueNeverShown => 'Wert wird nie wieder angezeigt';

  @override
  String get mcpLabelsAlwaysAsks => 'fragt immer nach';

  @override
  String get mcpLabelsAsksNoUndo => 'fragt nach · kein Rückgängig';

  @override
  String get mcpLabelsAuthAfterSave =>
      'Anmeldung nötig – nach dem Speichern anmelden';

  @override
  String get mcpLabelsAuthCheck => 'Anmeldung nötig – Token oder Header prüfen';

  @override
  String get mcpLabelsAuthRequired => 'Anmeldung nötig';

  @override
  String get mcpLabelsChanges => 'ändert';

  @override
  String get mcpLabelsCredentialsMissing => 'Zugangsdaten fehlen';

  @override
  String get mcpLabelsExternal => 'Außenwirkung';

  @override
  String get mcpLabelsHintDestructive => 'Server: destruktiv (destructiveHint)';

  @override
  String get mcpLabelsHintNonDestructive =>
      'Server: ändert, nicht destruktiv (destructiveHint: false)';

  @override
  String get mcpLabelsHintNone =>
      'Server: keine Angabe – gilt als Außenwirkung';

  @override
  String get mcpLabelsHintReadOnly => 'Server: nur lesend (readOnlyHint)';

  @override
  String get mcpLabelsNetworkHint => 'Tailscale/WireGuard aktiv?';

  @override
  String get mcpLabelsNoAsk => 'ohne Nachfrage';

  @override
  String get mcpLabelsNoAskNoUndo => 'ohne Nachfrage · kein Rückgängig';

  @override
  String get mcpLabelsNotChecked => 'Noch nicht geprüft';

  @override
  String get mcpLabelsOneTool => '1 Tool';

  @override
  String get mcpLabelsProtocolError => 'kein gültiger MCP-Server';

  @override
  String mcpLabelsProtocolErrorDetail(String v) {
    return 'Kein gültiger MCP-Server: $v';
  }

  @override
  String get mcpLabelsProtocolErrorShort => 'Kein gültiger MCP-Server';

  @override
  String get mcpLabelsReachable => 'Erreichbar';

  @override
  String get mcpLabelsReads => 'liest';

  @override
  String get mcpLabelsReload => 'Neu laden';

  @override
  String get mcpLabelsReplaceToken => 'Token ersetzen';

  @override
  String get mcpLabelsSetUp => 'Einrichten';

  @override
  String get mcpLabelsSignIn => 'Anmelden';

  @override
  String get mcpLabelsSignInAgain => 'Neu anmelden';

  @override
  String get mcpLabelsSignInMissing => 'Anmeldung fehlt';

  @override
  String mcpLabelsTools(int tools) {
    return '$tools Tools';
  }

  @override
  String get mcpLabelsUnreachable => 'nicht erreichbar';

  @override
  String mcpLabelsUnreachableDetail(String v, String mcpUnreachableHint) {
    return 'Nicht erreichbar: $v. $mcpUnreachableHint';
  }

  @override
  String mcpLabelsUnreachableShort(String mcpUnreachableHint) {
    return 'Nicht erreichbar · $mcpUnreachableHint';
  }

  @override
  String mcpSecretCheck(String v) {
    return 'Prüfung: $v';
  }

  @override
  String get mcpSecretSaved => 'Gespeichert';

  @override
  String mcpSecretSignInFailed(String message) {
    return 'Anmeldung fehlgeschlagen: $message';
  }

  @override
  String mcpSecretSignInOnServer(String name) {
    return '„$name“: auf der Serverseite anmelden';
  }

  @override
  String get mcpSecretSignedIn => 'Angemeldet';

  @override
  String get mcpServersAdd => '+ Server';

  @override
  String get mcpServersContent => 'Inhalt der Exportdatei';

  @override
  String get mcpServersExportHint => 'Serverliste ohne Tokens und Passwörter';

  @override
  String get mcpServersImportHint => 'Zugangsdaten werden neu abgefragt';

  @override
  String get mcpServersImportTitle => 'Serverliste importieren';

  @override
  String mcpServersImported(int length) {
    return '$length Server importiert (ausgeschaltet)';
  }

  @override
  String get mcpServersImportedOne => '1 Server importiert (ausgeschaltet)';

  @override
  String get mcpServersIntro =>
      'Tools von MCP-Servern, z. B. auf dem Homeserver über Tailscale. Tool-Argumente gehen an den jeweiligen Server.';

  @override
  String get mcpServersNone => 'Noch kein Server';

  @override
  String get mcpServersNoneHint =>
      'Vorlage wählen oder eigene Adresse eintragen';

  @override
  String get mcpToolAlwaysAsk => 'Immer nachfragen';

  @override
  String get mcpToolAlwaysAsk2 => 'Immer nachfragen';

  @override
  String get mcpToolAlwaysAskHint => 'jeder Aufruf wird bestätigt';

  @override
  String get mcpToolConfirmAllOn =>
      '„Alle Tools bestätigen“ ist an: jeder Aufruf fragt nach.';

  @override
  String get mcpToolDefaultNoUndo => 'Standard: kein Rückgängig möglich';

  @override
  String mcpToolEffective(String v) {
    return 'Wirksam: $v';
  }

  @override
  String get mcpToolExternalAsks =>
      'Außenwirkung: fragt immer nach, das lässt sich nicht lockern.';

  @override
  String get mcpToolNoAsk => 'Ohne Nachfrage';

  @override
  String get mcpToolNoAsk2 => 'Ohne Nachfrage';

  @override
  String get mcpToolNoUndoNow =>
      'Kein Rückgängig: die Änderung passiert sofort auf dem Server';

  @override
  String get mcpToolReadsOnly => 'liest nur';

  @override
  String mcpToolServerChecked(String v) {
    return 'Nur vom Server geprüft: $v';
  }

  @override
  String toolChipSemantics(String toolName, String status) {
    return 'Tool $toolName, $status';
  }

  @override
  String toolResultUndoCountdown(int seconds) {
    return 'Rückgängig · $seconds s';
  }

  @override
  String toolResultUndoSemantics(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds Sekunden',
      one: '$seconds Sekunde',
    );
    return 'Rückgängig, noch $_temp0';
  }

  @override
  String get toolResultUndone => 'Rückgängig gemacht';

  @override
  String get toolTlsEncrypted => 'Tools Ende-zu-Ende-verschlüsselt';

  @override
  String get toolTlsHint =>
      'Tool-Aufrufe sind über die geprüfte Verbindung bis in die Enklave geschützt, aber nicht zusätzlich verschlüsselt.';

  @override
  String get integrationsMediaRationale =>
      'Damit Wendelin sagen kann, was läuft, und im Hörbuch oder Podcast spulen kann, braucht es den „Benachrichtigungszugriff“. Android öffnet gleich die Seite dazu: Wendelin in der Liste wählen und einschalten (bei neueren Android-Versionen vorher in den App-Infos „Eingeschränkte Einstellungen zulassen“ wählen). Wendelin liest keine Benachrichtigungen, nur die Medienwiedergabe. Pause, Weiter und Zurück gehen auch ohne.';

  @override
  String get obsIndexBuilding => 'Index wird aufgebaut …';

  @override
  String obsIndexBuildingProgress(int indexed, int pending) {
    return 'Index wird aufgebaut: $indexed Notizen, noch $pending';
  }

  @override
  String obsIndexCurrent(String notes) {
    return '$notes im Index · aktuell';
  }

  @override
  String obsIndexIncomplete(String error) {
    return 'Index unvollständig: $error';
  }

  @override
  String get obsIndexNotBuilt => 'Noch nicht aufgebaut';

  @override
  String obsIndexNotes(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Notizen',
      one: '1 Notiz',
    );
    return '$_temp0';
  }

  @override
  String obsIndexPartial(String notes) {
    return '$notes im Index · Vault zu groß, nur teilweise';
  }

  @override
  String obsIndexUnreadable(String notes, int failed) {
    return '$notes im Index · $failed nicht lesbar';
  }

  @override
  String get obsidianAccessGranted => 'Zugriff erteilt';

  @override
  String get obsidianAccessGranted2 => 'Zugriff erteilt';

  @override
  String get obsidianAccessLost => 'Kein Zugriff mehr – Ordner neu wählen';

  @override
  String get obsidianBuildIndex => 'Index aufbauen';

  @override
  String get obsidianChooseFolder => 'Wähle den Ordner deines Obsidian-Vaults';

  @override
  String get obsidianChooseOther => 'Anderen Ordner wählen';

  @override
  String get obsidianChooseVaultFolder => 'Vault-Ordner wählen';

  @override
  String get obsidianDailyNotes => 'Tagesnotizen';

  @override
  String get obsidianDailySaved => 'Tagesnotizen gespeichert.';

  @override
  String get obsidianDateFormat => 'Datumsformat wie in Obsidian';

  @override
  String get obsidianFolder => 'Ordner';

  @override
  String get obsidianFolderHint =>
      'Leer lassen = Vault-Wurzel. Neue Tagesnotizen landen in diesem Ordner.';

  @override
  String get obsidianIndexBuilding => 'Index wird aufgebaut';

  @override
  String get obsidianIndexHint =>
      'Wird automatisch aktualisiert (beim Start und vor jeder Suche). Der Knopf ist nur für den ersten Aufbau nötig.';

  @override
  String get obsidianIntro =>
      'Wendelin liest und ergänzt Notizen direkt im Vault-Ordner. Sync bleibt bei Obsidian Sync, Syncthing oder Git.';

  @override
  String get obsidianNoAccess => 'kein Zugriff';

  @override
  String get obsidianNoVault => 'Kein Vault gewählt';

  @override
  String get obsidianRemoveBody =>
      'Wendelin verliert den Zugriff auf den Ordner. Die Notizen selbst bleiben unverändert.';

  @override
  String get obsidianRemoveTitle => 'Vault entfernen?';

  @override
  String get obsidianRemoveVault => 'Vault entfernen';

  @override
  String get obsidianSaveDaily => 'Tagesnotizen speichern';

  @override
  String get obsidianSearchIndex => 'Suchindex';

  @override
  String get obsidianTemplate => 'Vorlage (optional)';

  @override
  String get obsidianTemplateHint => 'Vorlagen/Tagesnotiz';

  @override
  String obsidianToday(String path) {
    return 'Heute: $path';
  }

  @override
  String obsidianUnusable(String message) {
    return 'Nicht verwendbar: $message';
  }

  @override
  String obsidianUnusable2(String message) {
    return 'Nicht verwendbar: $message';
  }

  @override
  String get obsidianVault => 'Vault';

  @override
  String get onboardingConversation => 'Gespräch';

  @override
  String get onboardingConversationIntro =>
      'Soll Wendelin nach seinen Antworten kurz weiter zuhören, damit du ohne Tippen nachfragen kannst? Das lässt sich jederzeit unter Einstellungen → Sprache ändern.';

  @override
  String get onboardingDemoNoProvider => 'Demo ohne Provider';

  @override
  String get onboardingInterfaceLanguage => 'App-Sprache der Oberfläche';

  @override
  String get onboardingKeepListening => 'Ja, weiter zuhören';

  @override
  String get onboardingLanguageModel => 'Sprachmodell';

  @override
  String get onboardingLearnAndEnable => 'Einlernen und einschalten';

  @override
  String get onboardingPermissionsIntro =>
      'Schalte nur ein, was du brauchst. Berechtigungen fragt Android erst jetzt beim Einschalten.';

  @override
  String get onboardingProviderIntro =>
      'Wendelin braucht einen Provider, z. B. Claude mit deinem API-Key oder ein eigenes Modell auf dem Homeserver.';

  @override
  String get onboardingSetUpAnotherProvider => 'Weiteren Provider einrichten';

  @override
  String get onboardingSkip => 'Überspringen';

  @override
  String get onboardingTapOnly => 'Nein, nur nach Tippen';

  @override
  String get onboardingWakeIntro =>
      'Wendelin kann auf „Wendelin“ hören, auch wenn das Telefon liegt. Dafür lernt er zuerst deine Stimme (etwa 3 Minuten). Das geht auch später in den Einstellungen.';

  @override
  String get onboardingWakeWord => 'Aktivierungswort';

  @override
  String get onboardingWelcome => 'Willkommen';

  @override
  String get onboardingWelcomeIntro =>
      'Wendelin ist dein Sprachassistent. In sechs Schritten ist er eingerichtet. Welche Sprache sprichst du mit ihm?';

  @override
  String get onboardingWhatMayWendelinDo => 'Was darf Wendelin?';

  @override
  String get auditEntrySession => 'Sitzung';

  @override
  String get auditEntryVerifications => 'Prüfungen dieser Sitzung';

  @override
  String get auditLogIntro =>
      'Was Wendelin getan hat. Nie Schlüssel. Der Export enthält keine Texte, nur Zeiten, Arten und Ergebnisse.';

  @override
  String get auditLogTitle => 'Prüfprotokoll';

  @override
  String get memoryCatFact => 'Fakt';

  @override
  String get memoryCatPerson => 'Person';

  @override
  String get memoryCatPreference => 'Vorliebe';

  @override
  String get memoryCatProject => 'Projekt';

  @override
  String memoryDeleteTooltip(String text) {
    return 'Löschen: $text';
  }

  @override
  String get memoryEditTitle => 'Eintrag ändern';

  @override
  String get memoryExportMd => 'Als Markdown exportieren';

  @override
  String get memoryForget => 'Vergessen';

  @override
  String get memoryForgetTitle => 'Eintrag vergessen?';

  @override
  String memoryFromPrivate(String label) {
    return 'Aus einer privaten Anfrage: geht nur an Provider ab $label.';
  }

  @override
  String get memoryIntro =>
      'Wendelin merkt sich nur, worum du ausdrücklich bittest. Passwörter, PINs, Karten- und Kontonummern werden nie gespeichert.';

  @override
  String get memoryLift => 'Aufheben';

  @override
  String memoryLiftBody(String text, String level) {
    return '„$text“ stammt aus einer privaten Anfrage und geht bisher nur an Provider ab $level. Danach können ihn alle Provider sehen, die das Gedächtnis sehen dürfen.';
  }

  @override
  String get memoryLiftLimit => 'Untergrenze aufheben';

  @override
  String get memoryLiftTitle => 'Untergrenze aufheben?';

  @override
  String get memoryNone => 'Noch keine Einträge.';

  @override
  String memoryPrivateFrom(String v, String label) {
    return '$v · privat, nur ab $label';
  }

  @override
  String get memoryTitle => 'Gedächtnis';

  @override
  String get privacyLevelEu => 'EU';

  @override
  String get privacyLevelLocal => 'lokal';

  @override
  String privacyLevelSemantics(String text, String level) {
    return '$text, Datenschutzstufe $level';
  }

  @override
  String get privacyLevelStandard => 'Standard';

  @override
  String get privacyLevelTee => 'TEE';

  @override
  String privacyScreenDays(int d) {
    return '$d Tage';
  }

  @override
  String get privacyScreenDeleteAll => 'Alles löschen';

  @override
  String get privacyScreenDeleteAllBody =>
      'Alle Gesprächsverläufe, das Prüfprotokoll und die eingelernten Stimmen (Aktivierungswort) werden gelöscht. Das lässt sich nicht rückgängig machen. Gedächtnis und Einstellungen bleiben.';

  @override
  String get privacyScreenDeleteAllTitle => 'Alles löschen?';

  @override
  String get privacyScreenDeleteHistory => 'Verläufe und Protokoll löschen';

  @override
  String privacyScreenEntries(int n) {
    return '$n Einträge';
  }

  @override
  String get privacyScreenGeneralLog => 'Allgemeines Prüfprotokoll';

  @override
  String get privacyScreenIntro =>
      'Verläufe und Prüfprotokoll bleiben auf dem Gerät. Ältere Einträge löscht Wendelin automatisch.';

  @override
  String get privacyScreenKindConfirmation => 'Bestätigung';

  @override
  String get privacyScreenKindEscalation => 'Eskalation';

  @override
  String get privacyScreenKindRequest => 'Anfrage';

  @override
  String get privacyScreenKindTool => 'Tool';

  @override
  String get privacyScreenKindVerification => 'Prüfung';

  @override
  String get privacyScreenManyEntries => '200+ Einträge';

  @override
  String get privacyScreenOneEntry => '1 Eintrag';

  @override
  String get privacyScreenOneYear => '1 Jahr';

  @override
  String get privacyScreenProtectScreen => 'Bildschirminhalt schützen';

  @override
  String get privacyScreenProtectScreenHint =>
      'Keine Screenshots, im App-Wechsler verdeckt. Das Assistenten-Overlay ist immer geschützt.';

  @override
  String get privacyScreenRetention => 'Aufbewahrung';

  @override
  String get privacyScreenTeeLog => 'TEE-Prüfprotokoll';

  @override
  String get privacyScreenTeeLogHint =>
      'Prüfung der Anbieter mit geschützter Umgebung, GPU-Prüfung über NVIDIA';

  @override
  String privacyScreenUndone(String v, String v2) {
    return '$v · rückgängig · $v2';
  }

  @override
  String get areaAssistant => 'Assistent';

  @override
  String get areaAssistantDetail =>
      'Standard-Assistent, dein Name, Persönlichkeit';

  @override
  String get areaCosts => 'Kosten';

  @override
  String get areaCostsDetail => 'Heute und im Monat je Provider';

  @override
  String get areaHttpTools => 'HTTP-Tools';

  @override
  String get areaHttpToolsDetail => 'Eigene Tools definieren und testen';

  @override
  String get areaIntegrations => 'Integrationen';

  @override
  String get areaIntegrationsDetail => 'Was Wendelin darf, Tools, Risikostufen';

  @override
  String get areaMcp => 'MCP-Server';

  @override
  String get areaMcpDetail => 'Server, Anmeldung, Status, Tools';

  @override
  String get areaPrivacy => 'Datenschutz und Logs';

  @override
  String get areaPrivacyDetail => 'Aufbewahrung, Prüfprotokoll, Export';

  @override
  String get areaProvider => 'Provider';

  @override
  String get areaProviderDetail => 'Profile, Standard, Budget';

  @override
  String get areaRouting => 'Routing';

  @override
  String get areaRoutingDetail => 'Regeln, Testfeld, Import und Export';

  @override
  String get areaSpeech => 'Sprache';

  @override
  String get areaSpeechDetail => 'Spracherkennung, Stimme, Tempo';

  @override
  String get costsIntro => 'Nach den Preisen im Modellkatalog, in US-Dollar.';

  @override
  String costsMonth(String v) {
    return 'Monat $v';
  }

  @override
  String get costsNoProviders => 'Noch keine Provider.';

  @override
  String costsOfBudget(String v) {
    return 'von $v';
  }

  @override
  String costsToday(String v) {
    return 'heute $v';
  }

  @override
  String providerChipLevel(String level) {
    return 'Datenschutzstufe $level';
  }

  @override
  String providerChipReceipt(String status) {
    return 'Quittung $status';
  }

  @override
  String providerChipSemantics(String name) {
    return 'Provider $name';
  }

  @override
  String get providerModelRecommendedBadge => 'Empfohlen';

  @override
  String providerModelRecommendedReason(
    String hits,
    String runs,
    String p50,
    String date,
  ) {
    return '$hits von $runs Testläufen richtig, typisch $p50 s, gemessen am $date';
  }

  @override
  String get providerModelRecommendedWeaker =>
      'Das beste Modell dieses Anbieters, aber schwächer als bei Phala und Tinfoil.';

  @override
  String get providerSetupBudgetFormat =>
      'Budget: Betrag in Dollar, z. B. 5 oder 2,50';

  @override
  String get providerSetupConnected => 'Verbindung steht';

  @override
  String get providerSetupConnectedEnterModel =>
      'Verbindung steht. Bitte die Modell-ID eingeben.';

  @override
  String providerSetupConnectedModels(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Verbindung steht, $n Modelle gefunden.',
      one: 'Verbindung steht, 1 Modell gefunden.',
    );
    return '$_temp0';
  }

  @override
  String get providerSetupConnectionFailed => 'Verbindung fehlgeschlagen';

  @override
  String get providerSetupEditTitle => 'Provider bearbeiten';

  @override
  String get providerSetupIntroCredentials =>
      'Der Key wird nur im sicheren Speicher des Geräts abgelegt.';

  @override
  String get providerSetupIntroFinish =>
      'Datenschutzstufe und optional ein Monatsbudget.';

  @override
  String get providerSetupIntroModel => 'Wähle das Standardmodell.';

  @override
  String get providerSetupIntroTemplate =>
      'Wähle, mit wem Wendelin sprechen soll.';

  @override
  String providerSetupModelListFailed(String reason) {
    return 'Modellliste nicht verfügbar ($reason). Bitte die Modell-ID eingeben.';
  }

  @override
  String get providerSetupModelListUnavailable => 'Modellliste nicht verfügbar';

  @override
  String get providerSetupModelUnusable => 'Modell nicht nutzbar';

  @override
  String providerSetupModelsFound(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Modelle gefunden',
      one: '1 Modell gefunden',
    );
    return '$_temp0';
  }

  @override
  String get providerSetupNoModelList =>
      'Keine Modellliste. Bitte die Modell-ID eingeben.';

  @override
  String get providerSetupProviderSetupApiKeyOptional => 'API-Key (optional)';

  @override
  String get providerSetupProviderSetupBaseUrl => 'Base-URL';

  @override
  String get providerSetupProviderSetupCreateKey =>
      'Key beim Anbieter erstellen';

  @override
  String get providerSetupProviderSetupModelId => 'Modell-ID';

  @override
  String get providerSetupProviderSetupModels => 'Modelle';

  @override
  String get providerSetupProviderSetupOtherTemplate => 'Andere Vorlage';

  @override
  String get providerSetupProviderSetupProbeModel => 'Modell prüfen';

  @override
  String get providerSetupProviderSetupTestConnection => 'Verbindung testen';

  @override
  String get providerSetupProviderSetupTesting => 'Teste …';

  @override
  String get providersAdd => '+ Provider';

  @override
  String providersBudget(String v) {
    return 'Budget $v/Monat';
  }

  @override
  String get providersChoice => 'Anbieterwahl';

  @override
  String get providersDeleteBody =>
      'Profil und gespeicherter Key werden entfernt.';

  @override
  String providersDeleteTitle(String name) {
    return '„$name“ löschen?';
  }

  @override
  String providersError(String error) {
    return 'Fehler: $error';
  }

  @override
  String get providersIntro =>
      'Der Standard bekommt jede Anfrage, für die keine Routing-Regel greift. Scheitert er, sagt Wendelin das klar und wechselt nie von selbst zu einem anderen Anbieter.';

  @override
  String get providersMakeDefault => 'Als Standard';

  @override
  String get providersNone => 'Noch kein Provider eingerichtet.';

  @override
  String get providersProfiles => 'Profile';

  @override
  String get providersRoutingHint => 'Regeln für die Wahl des Anbieters';

  @override
  String get targetPickerApply => 'Übernehmen';

  @override
  String get targetPickerProfile => 'Profil';

  @override
  String targetPickerProfileGone(String profileId) {
    return 'Profil „$profileId“ gibt es nicht mehr.';
  }

  @override
  String get quickSwitchCurrent => 'aktuell';

  @override
  String get quickSwitchHint =>
      'Die Auswahl beendet das Gespräch und startet ein neues.';

  @override
  String quickSwitchItemSemantics(String name, String level) {
    return '$name, $level';
  }

  @override
  String get quickSwitchSemanticsAction => 'Agent wechseln';

  @override
  String get quickSwitchTitle => 'Agent wechseln';

  @override
  String get condBuilderAddCondition => '+ Bedingung';

  @override
  String get condBuilderAddConditionInGroup => '+ Bedingung in Gruppe';

  @override
  String get condBuilderAddGroup => '+ Gruppe';

  @override
  String get condBuilderAll => 'alle (und)';

  @override
  String get condBuilderAny => 'eine (oder)';

  @override
  String get condBuilderApplies => 'Es gilt';

  @override
  String get condBuilderCategory => 'Kategorie';

  @override
  String get condBuilderConfidenceBelow => 'Sicherheit unter';

  @override
  String get condBuilderEmptyGroup => 'Eine Gruppe ist leer.';

  @override
  String condBuilderFail(String label, String m) {
    return '$label: $m';
  }

  @override
  String get condBuilderFrom => 'von (HH:MM)';

  @override
  String get condBuilderGroup => 'Gruppe';

  @override
  String get condBuilderLanguages => 'Sprachen';

  @override
  String get condBuilderLanguagesHint => 'de, fr';

  @override
  String get condBuilderMetered => 'mobile Daten';

  @override
  String get condBuilderMoreChars => 'Mehr Zeichen als';

  @override
  String get condBuilderNeedCategory => 'Kategorie eingeben.';

  @override
  String get condBuilderNeedLang => 'Sprachkürzel eingeben (de, fr …).';

  @override
  String get condBuilderNeedLength => 'Zeichenzahl eingeben.';

  @override
  String get condBuilderNeedPattern => 'Muster eingeben.';

  @override
  String get condBuilderNeedThreshold => 'Schwelle zwischen 0 und 1 eingeben.';

  @override
  String get condBuilderNeedTime => 'Uhrzeit als HH:MM eingeben.';

  @override
  String get condBuilderNeedWord => 'mindestens ein Wort eingeben.';

  @override
  String get condBuilderPattern => 'Muster (auf normalisiertem Text)';

  @override
  String get condBuilderRemoveCondition => 'Bedingung entfernen';

  @override
  String get condBuilderRemoveGroup => 'Gruppe entfernen';

  @override
  String get condBuilderSentenceStart =>
      'Wörter am Satzanfang, durch Komma getrennt';

  @override
  String get condBuilderSentenceStartHint => 'Claude';

  @override
  String get condBuilderTo => 'bis (HH:MM)';

  @override
  String get condBuilderUnknownType => 'unbekannter Typ.';

  @override
  String get condBuilderWords => 'Wörter, durch Komma getrennt';

  @override
  String get condBuilderWordsHint => 'privat, vertraulich';

  @override
  String get routingAllDay => 'ganztags';

  @override
  String routingApplies(String target, String private) {
    return 'greift → $target$private';
  }

  @override
  String get routingCondAnd => 'und';

  @override
  String get routingCondImage => 'Mit Bild';

  @override
  String get routingCondKeyword => 'Schlüsselwort';

  @override
  String get routingCondLanguage => 'Sprache';

  @override
  String get routingCondLong => 'Lange Eingabe';

  @override
  String get routingCondNetwork => 'Netz';

  @override
  String get routingCondNot => 'nicht';

  @override
  String get routingCondOr => 'oder';

  @override
  String get routingCondPrefix => 'Präfix';

  @override
  String get routingCondPrivate => 'Privat';

  @override
  String get routingCondRegex => 'Regulärer Ausdruck';

  @override
  String get routingCondTime => 'Zeitfenster';

  @override
  String get routingCondTool => 'Braucht Tool';

  @override
  String get routingCondUncertain => 'Unsichere Erkennung';

  @override
  String get routingDefault => 'Standard';

  @override
  String routingDeleted(String profileId) {
    return '$profileId (gelöscht)';
  }

  @override
  String routingImportBody(int length, int before) {
    return '$length Regeln ersetzen die bisherigen $before. Erst mit „Ersetzen“ wird etwas geändert.';
  }

  @override
  String routingImportDefaultMissing(String profileId) {
    return 'Das Standardprofil „$profileId“ gibt es hier nicht; der bisherige Standard bleibt.';
  }

  @override
  String get routingImportEscalations =>
      'Die Datei enthält Eskalationsketten. Sie wurden übersprungen: Wendelin wechselt nie von selbst das Modell.';

  @override
  String get routingImportReplace => 'Ersetzen';

  @override
  String get routingImportTitle => 'Regeln importieren?';

  @override
  String routingPrivateRuleNotice(String target) {
    return 'Neu: Regel „Privat“ – Anfragen mit „privat“, „vertraulich“ … gehen an $target.';
  }

  @override
  String get routingPrivateSuffix => ' · privat';

  @override
  String routingRuleN(int n) {
    return 'Regel $n';
  }

  @override
  String get routingScreenAddRule => '+ Regel hinzufügen';

  @override
  String get routingScreenDefaultTarget => 'Standardziel';

  @override
  String get routingScreenFirstWins => 'Erste passende Regel gewinnt';

  @override
  String routingScreenImportFailed(String message) {
    return 'Import nicht möglich: $message';
  }

  @override
  String routingScreenMoveRule(String name) {
    return 'Regel „$name“ verschieben';
  }

  @override
  String get routingScreenNeedsProvider =>
      'Routing braucht einen Provider. Richte zuerst einen ein.';

  @override
  String routingScreenReadError(String error) {
    return 'Die Regeln lassen sich nicht lesen: $error';
  }

  @override
  String get routingScreenResetBody =>
      'Die gespeicherten Regeln werden verworfen und aus den Provider-Einstellungen neu angelegt.';

  @override
  String get routingScreenResetRules => 'Regeln zurücksetzen';

  @override
  String get routingScreenResetTitle => 'Regeln zurücksetzen?';

  @override
  String routingScreenRuleOff(String name) {
    return '$name (aus)';
  }

  @override
  String routingScreenSkipped(String name, String v) {
    return '„$name“ übersprungen: $v';
  }

  @override
  String get routingScreenTestHint => 'Welche Regel greift für diesen Satz?';

  @override
  String get routingScreenTestSentence => 'Testsatz';

  @override
  String get routingSkipDisabled => 'ausgeschaltet';

  @override
  String get routingSkipInvalid => 'ungültig';

  @override
  String get routingSkipNoMatch => 'passt nicht';

  @override
  String get routingSkipProfileDisabled => 'Profil deaktiviert';

  @override
  String get routingSkipProfileMissing => 'Profil gelöscht';

  @override
  String get routingSkipProfileUnavailable => 'Profil nicht verfügbar';

  @override
  String get routingWeekdayFri => 'Fr';

  @override
  String get routingWeekdayMon => 'Mo';

  @override
  String get routingWeekdaySat => 'Sa';

  @override
  String get routingWeekdaySun => 'So';

  @override
  String get routingWeekdayThu => 'Do';

  @override
  String get routingWeekdayTue => 'Di';

  @override
  String get routingWeekdayWed => 'Mi';

  @override
  String get ruleEditorActive => 'Aktiv';

  @override
  String get ruleEditorActiveLabel => 'Regel aktiv';

  @override
  String get ruleEditorCondition => 'Bedingung';

  @override
  String get ruleEditorDeleteBody =>
      'Anfragen, die bisher diese Regel genommen haben, prüfen die nächsten Regeln bzw. gehen an den Standard.';

  @override
  String get ruleEditorDeleteRule => 'Regel löschen';

  @override
  String ruleEditorDeleteTitle(String v) {
    return 'Regel „$v“ löschen?';
  }

  @override
  String get ruleEditorEditRule => 'Regel bearbeiten';

  @override
  String get ruleEditorNeedModel => 'Bitte ein Modell eingeben.';

  @override
  String get ruleEditorNeedName => 'Bitte einen Namen eingeben.';

  @override
  String get ruleEditorNewRule => 'Neue Regel';

  @override
  String get ruleEditorRebuild => 'Neu aufbauen';

  @override
  String get ruleEditorRule => 'Regel';

  @override
  String get ruleEditorStripTrigger => 'Auslöser entfernen';

  @override
  String get ruleEditorStripTriggerHint =>
      'Präfix, Schlüsselwort oder Treffer gehen nicht ans Modell; im Verlauf bleibt der Satz vollständig.';

  @override
  String get ruleEditorStripTriggerLabel => 'Auslöser entfernen';

  @override
  String get ruleEditorTarget => 'Ziel';

  @override
  String get ruleEditorTooDeep =>
      'Diese Bedingung ist tiefer verschachtelt, als der Editor sie bearbeiten kann. Sie bleibt unverändert erhalten.';

  @override
  String get ruleTileMove => 'Verschieben';

  @override
  String ruleTileSemanticsLevel(String level) {
    return 'Datenschutzstufe $level,';
  }

  @override
  String get speakerAdd => 'Person einlernen';

  @override
  String get speakerAddDetail =>
      'Fünf kurze Sätze vorlesen, die Aufnahmen werden nicht gespeichert.';

  @override
  String get speakerAddNeedsModel => 'Lade zuerst das Modell.';

  @override
  String speakerDeleteBody(String name) {
    return '$name wird mit allen gespeicherten Stimmmerkmalen und ihren Unterhaltungen gelöscht.';
  }

  @override
  String speakerDeleteBodyMemory(String name, int count) {
    return '$name wird mit allen gespeicherten Stimmmerkmalen, ihren Unterhaltungen und $count Einträgen im eigenen Gedächtnis gelöscht. Das Standard-Gedächtnis bleibt unverändert.';
  }

  @override
  String get speakerDeleteConfirm => 'Löschen';

  @override
  String speakerDeleteSemantic(String name) {
    return '$name löschen';
  }

  @override
  String get speakerDeleteTitle => 'Person löschen?';

  @override
  String get speakerDone => 'Fertig';

  @override
  String get speakerEnrollIntro =>
      'Lies jeden Satz in normaler Lautstärke vor. Aus der Aufnahme wird nur ein Stimmmerkmal berechnet, das Audio wird verworfen.';

  @override
  String get speakerEnrollTitle => 'Person einlernen';

  @override
  String get speakerErrFailed =>
      'Das Modell konnte die Aufnahmen nicht auswerten. Ist es vollständig geladen?';

  @override
  String get speakerErrInconsistent =>
      'Die Sätze klangen nicht nach derselben Person oder es war zu laut. Nichts wurde gespeichert, bitte noch einmal in ruhiger Umgebung.';

  @override
  String get speakerErrTooFew => 'Es fehlen Aufnahmen.';

  @override
  String get speakerErrTooShort =>
      'Eine Aufnahme war zu kurz. Bitte noch einmal.';

  @override
  String get speakerIntro =>
      'Wendelin kann erkennen, wer spricht. Das Ergebnis steht dem Assistenten als Information zur Verfügung.';

  @override
  String get speakerModelSection => 'Modell';

  @override
  String get speakerNameLabel => 'Name';

  @override
  String get speakerNext => 'Weiter';

  @override
  String get speakerNoMic =>
      'Ohne Mikrofon-Zugriff kann keine Person eingelernt werden.';

  @override
  String get speakerNobody => 'Noch niemand eingelernt.';

  @override
  String get speakerPeople => 'Personen';

  @override
  String get speakerPersonAddress => 'Anrede';

  @override
  String get speakerPersonAddressHint =>
      'So spricht Wendelin dich an. Leer: der eingelernte Name.';

  @override
  String get speakerPersonAgent => 'Agent';

  @override
  String get speakerPersonAgentDefault => 'Standard-Agent';

  @override
  String get speakerPersonAgentDetail =>
      'Nur ein anderes Ziel statt des Standards. Regeln und Datenschutz gelten weiter.';

  @override
  String get speakerPersonDelete => 'Person löschen';

  @override
  String get speakerPersonMemory => 'Gedächtnis';

  @override
  String get speakerPersonMemoryOpen => 'Einträge ansehen';

  @override
  String get speakerPersonMemoryOwn => 'Eigenes Gedächtnis';

  @override
  String get speakerPersonMemoryOwnDetail =>
      'Merkt sich Dinge nur für diese Person.';

  @override
  String get speakerPersonMemoryShared => 'Standard-Gedächtnis';

  @override
  String get speakerPersonMemorySharedDetail =>
      'Nutzt die bisherigen Einträge gemeinsam mit allen, die nicht erkannt werden.';

  @override
  String get speakerPersonRetrain => 'Neu einlernen';

  @override
  String get speakerPersonRetrainDetail => 'Fünf Sätze noch einmal vorlesen.';

  @override
  String get speakerProcessing => 'Wird ausgewertet …';

  @override
  String get speakerRecordCutOff =>
      'Zu früh angefangen, bitte den Satz noch einmal.';

  @override
  String get speakerRecordNoSpeech => 'Nichts gehört, bitte noch einmal.';

  @override
  String get speakerRecordTooLong =>
      'Zu lang oder zu laut im Hintergrund, bitte noch einmal.';

  @override
  String get speakerRecordTooQuiet => 'Zu leise, bitte lauter.';

  @override
  String get speakerResultClamped =>
      'Die Schwelle wurde auf einen sicheren Wert begrenzt.';

  @override
  String speakerResultScores(String mean, String min, String threshold) {
    return 'Gleichmäßigkeit $mean, schwächster Satz $min, Schwelle $threshold.';
  }

  @override
  String get speakerResultTitle => 'Eingelernt';

  @override
  String get speakerRetry => 'Noch einmal';

  @override
  String get speakerRowDetail =>
      'Erkennt, wer spricht (Name, Modell, Personen).';

  @override
  String get speakerRowTitle => 'Sprechererkennung';

  @override
  String get speakerSayNow => 'Lies den Satz jetzt laut vor:';

  @override
  String get speakerSentence1 =>
      'Heute Morgen habe ich einen Spaziergang durch den Park gemacht.';

  @override
  String get speakerSentence2 =>
      'Bitte erinnere mich morgen um neun Uhr an den Termin beim Arzt.';

  @override
  String get speakerSentence3 =>
      'Im Garten blühen die ersten Blumen, und die Sonne scheint warm.';

  @override
  String get speakerSentence4 =>
      'Kannst du mir sagen, wie das Wetter am Wochenende wird?';

  @override
  String get speakerSentence5 =>
      'Zum Abendessen gibt es heute Suppe mit frischem Brot.';

  @override
  String speakerSentenceOf(int n, int total) {
    return 'Satz $n von $total';
  }

  @override
  String get speakerSwitch => 'Sprechererkennung';

  @override
  String get speakerSwitchHint =>
      'Die Stimme ist keine sichere Anmeldung: Ähnliche oder nachgemachte Stimmen können verwechselt werden. Gespeichert werden nur verschlüsselte Stimmmerkmale, keine Aufnahmen.';

  @override
  String get speakerSwitchLabel => 'Sprechererkennung ein oder aus';

  @override
  String get speakerTitle => 'Sprechererkennung';

  @override
  String get spotifyAppNote =>
      'Die Spotify-App wird gebraucht, damit Wendelin auf diesem Handy abspielen kann: Läuft sie nicht, startet Wendelin sie. Auf anderen Geräten (Lautsprecher, Computer) spielt Wendelin auch ohne sie.';

  @override
  String get spotifyAppTitle => 'Spotify-App';

  @override
  String get spotifyClientIdLabel => 'Client-ID';

  @override
  String get spotifyClientIdMissing => 'Bitte die Client-ID eintragen.';

  @override
  String get spotifyCopied => 'Adresse kopiert.';

  @override
  String get spotifyCopyRedirect => 'Adresse kopieren';

  @override
  String get spotifyErrAccessDenied =>
      'Anmeldung abgebrochen: Zugriff nicht erlaubt.';

  @override
  String get spotifyErrCancelled => 'Anmeldung abgebrochen.';

  @override
  String get spotifyErrDenied => 'Spotify hat die Anmeldung abgelehnt.';

  @override
  String get spotifyErrFailed => 'Anmeldung bei Spotify nicht möglich.';

  @override
  String get spotifyErrInvalidClientId =>
      'Die Client-ID besteht aus 32 Zeichen (Ziffern und Buchstaben a–f). Bitte aus dem Entwickler-Dashboard kopieren.';

  @override
  String get spotifyErrNoBrowser =>
      'Kein Browser installiert, in dem die Anmeldung laufen kann.';

  @override
  String get spotifyErrNoCode => 'Spotify hat keinen Code geschickt.';

  @override
  String get spotifyErrRejected =>
      'Spotify hat die Anmeldung abgelehnt. Client-ID prüfen und darauf achten, dass das eigene Konto unter „User Management“ steht.';

  @override
  String get spotifyErrStateMismatch =>
      'Anmeldung abgelehnt: Die Antwort von Spotify gehört nicht zu dieser Anmeldung (z. B. ein alter Browser-Tab). Bitte die Anmeldung neu starten und im neuen Tab zu Ende führen.';

  @override
  String get spotifyErrUnavailable =>
      'Spotify ist nicht erreichbar. Später erneut versuchen.';

  @override
  String get spotifyFailed =>
      'Fehler – Anmeldung abgelaufen oder Spotify nicht erreichbar';

  @override
  String get spotifyGuideStep1 =>
      '1. Auf developer.spotify.com/dashboard mit dem Spotify-Konto anmelden und „Create app“ wählen.';

  @override
  String spotifyGuideStep2(String redirect) {
    return '2. Name und Beschreibung frei wählen. Als „Redirect URI“ genau diese Adresse eintragen: $redirect';
  }

  @override
  String get spotifyGuideStep3 =>
      '3. Bei „Which API/SDKs are you planning to use?“ „Web API“ ankreuzen und speichern.';

  @override
  String get spotifyGuideStep4 =>
      '4. Unter „Settings“ die „Client ID“ kopieren und unten eintragen. Im Entwicklungsmodus muss das eigene Konto unter „User Management“ stehen.';

  @override
  String get spotifyGuideTitle => 'Entwickler-App anlegen';

  @override
  String get spotifyIntro =>
      'Wendelin steuert Spotify über die offizielle Schnittstelle. Dafür braucht es ein Spotify-Premium-Konto und eine eigene (kostenlose) Entwickler-App von dir. Client-ID und Anmeldung bleiben im sicheren Speicher des Geräts.';

  @override
  String get spotifyReconnected => 'Spotify ist wieder erreichbar.';

  @override
  String get spotifyRetrying => 'Prüfe …';

  @override
  String get spotifySignIn => 'Bei Spotify anmelden';

  @override
  String get spotifySignOut => 'Abmelden';

  @override
  String get spotifySignOutMessage =>
      'Client-ID und Anmeldung werden vom Gerät gelöscht.';

  @override
  String get spotifySignOutTitle => 'Von Spotify abmelden?';

  @override
  String get spotifySignedIn => 'Angemeldet';

  @override
  String get spotifySigningIn => 'Anmelden …';

  @override
  String get spotifyStateActive => 'Angemeldet · Aktiv';

  @override
  String get spotifyStateLoginMissing => 'Login fehlt';

  @override
  String get spotifyStateOff => 'Angemeldet, Integration ausgeschaltet';

  @override
  String get spotifyStateUnavailable => 'Nicht verfügbar';

  @override
  String get spotifyTitle => 'Spotify';

  @override
  String get stationAllDay => 'ganztägig';

  @override
  String get stationEnd => 'Beenden';

  @override
  String get stationEndHint => 'Zum Beenden entsperrst du das Telefon.';

  @override
  String get stationEvents => 'Termine';

  @override
  String stationHour(int hour) {
    return '$hour Uhr';
  }

  @override
  String get stationNoEvents => 'Keine Termine in Sicht.';

  @override
  String get stationNoTasks => 'Keine fälligen Aufgaben.';

  @override
  String get stationOverdue => 'überfällig';

  @override
  String get stationPlaybackSlot => 'Wiedergabe';

  @override
  String get stationQuietFrom => 'Beginn der Ruhezeit';

  @override
  String get stationQuietSection => 'Ruhezeiten';

  @override
  String get stationQuietTo => 'Ende der Ruhezeit';

  @override
  String get stationScreenAlways => 'Immer an, gedimmt';

  @override
  String get stationScreenAlwaysDetail =>
      'Helligkeit nach Umgebungslicht, der Inhalt wandert leicht gegen Einbrennen.';

  @override
  String get stationScreenDaytime => 'Tagsüber an, in den Ruhezeiten aus';

  @override
  String get stationScreenDaytimeDetail =>
      'Eine Berührung weckt die Station kurz.';

  @override
  String get stationScreenSection => 'Bildschirm';

  @override
  String get stationScreenTouch => 'Aus, an bei Wake Word oder Berührung';

  @override
  String get stationScreenTouchDetail =>
      'Der Bildschirm schaltet sich nach der üblichen Zeit aus.';

  @override
  String get stationSectionsIntro =>
      'Was die Station zeigt. Uhr und Datum sind immer da. Termine und Aufgaben erscheinen mit Titeln.';

  @override
  String get stationSectionsSection => 'Anzeige';

  @override
  String get stationSettingsDetail =>
      'Bildschirm, Ruhezeiten, angezeigte Bereiche';

  @override
  String get stationSettingsIntro =>
      'Das Handy liegt am Ladegerät und zeigt Uhr, Datum und mehr. Der Modus startet nur von Hand und endet nur mit Entsperren.';

  @override
  String get stationSlotSoon => 'folgt';

  @override
  String get stationStart => 'Stationsmodus starten';

  @override
  String get stationTasks => 'Aufgaben';

  @override
  String get stationTilesSlot => 'Smart Home';

  @override
  String get stationTitle => 'Stationsmodus';

  @override
  String get stationWeather => 'Wetter';

  @override
  String get googleTasksApiError =>
      'Fehler – Google nicht erreichbar oder Anmeldung abgelehnt';

  @override
  String get googleTasksCancel => 'Abbrechen';

  @override
  String get googleTasksChecking => 'Prüfe …';

  @override
  String get googleTasksClientId => 'Client-ID';

  @override
  String get googleTasksClientSecret => 'Client-Secret';

  @override
  String get googleTasksErrAccessDenied =>
      'Anmeldung abgebrochen: Zugriff nicht erlaubt (Ist dein Konto im Cloud-Projekt als Testnutzer eingetragen?).';

  @override
  String get googleTasksErrCancelled => 'Anmeldung abgebrochen.';

  @override
  String get googleTasksErrClientRejected =>
      'Google lehnt Client-ID oder Client-Secret ab. Bitte beides prüfen.';

  @override
  String get googleTasksErrDenied => 'Google hat die Anmeldung abgelehnt.';

  @override
  String get googleTasksErrFailed => 'Die Anmeldung ist fehlgeschlagen.';

  @override
  String get googleTasksErrInvalidClientId =>
      'Die Client-ID endet auf „.apps.googleusercontent.com“. Bitte aus der Google Cloud Console kopieren (OAuth-Client Typ „Desktop“).';

  @override
  String get googleTasksErrMissingSecret =>
      'Bitte das Client-Secret des OAuth-Clients eintragen (ohne Leerzeichen).';

  @override
  String get googleTasksErrNoBrowser => 'Es ist kein Browser installiert.';

  @override
  String get googleTasksErrNoCode => 'Google hat keinen Code geschickt.';

  @override
  String get googleTasksErrNoRefreshToken =>
      'Google hat kein Refresh-Token geschickt. Bitte den Zugriff von Wendelin unter myaccount.google.com/permissions entfernen und neu anmelden.';

  @override
  String get googleTasksErrReceiver =>
      'Der lokale Empfänger für die Anmeldung lässt sich nicht starten.';

  @override
  String get googleTasksErrTimeout =>
      'Zeitüberschreitung: Im Browser kam keine Antwort von Google an. Bitte erneut anmelden.';

  @override
  String get googleTasksErrUnavailable =>
      'Google ist nicht erreichbar. Bitte später erneut versuchen.';

  @override
  String get googleTasksFine => 'in Ordnung';

  @override
  String get googleTasksGuideNote =>
      'Im Testmodus läuft die Anmeldung nach 7 Tagen ab; dann hier erneut anmelden. Google warnt bei der Anmeldung vor einer „nicht verifizierten App“ (es ist dein eigenes Projekt): „Weiter“ wählen und „Aufgaben ansehen und verwalten“ erlauben.';

  @override
  String get googleTasksGuideStep1 =>
      '1. In console.cloud.google.com ein Projekt anlegen (oder ein eigenes wählen).';

  @override
  String get googleTasksGuideStep2 =>
      '2. Unter „APIs & Dienste → Bibliothek“ die „Google Tasks API“ aktivieren.';

  @override
  String get googleTasksGuideStep3 =>
      '3. Unter „Google Auth Platform“ (früher „OAuth-Zustimmungsbildschirm“) die Zielgruppe „Extern“ im Testmodus lassen und das eigene Google-Konto als Testnutzer eintragen.';

  @override
  String get googleTasksGuideStep4 =>
      '4. Unter „Clients“ (früher „Anmeldedaten“) einen OAuth-Client vom Typ „Desktop-App“ anlegen. Client-ID und Client-Secret kopieren und unten eintragen.';

  @override
  String get googleTasksGuideTitle => 'Google-Cloud-Projekt einrichten';

  @override
  String get googleTasksIntro =>
      'Google-Aufgaben mit deinem eigenen Cloud-Projekt, ohne Google-Play-Dienste. Die Anmeldung läuft im Browser; Client-ID, Client-Secret und Anmeldung bleiben im sicheren Speicher des Geräts und werden nie angezeigt oder protokolliert. Aufgabenlisten dienen als Listen; Google kennt nur ein Fälligkeitsdatum, keine Uhrzeit und keine Priorität.';

  @override
  String get googleTasksNeedClient =>
      'Bitte Client-ID und Client-Secret eintragen.';

  @override
  String get googleTasksReachable => 'Google Tasks ist erreichbar.';

  @override
  String get googleTasksSignIn => 'Bei Google anmelden';

  @override
  String get googleTasksSignInWaiting => 'Warte auf Google …';

  @override
  String get googleTasksSignOutBody =>
      'Die Anmeldung wird bei Google widerrufen (soweit erreichbar), Client-ID, Client-Secret und Token werden vom Gerät gelöscht.';

  @override
  String get googleTasksSignOutTitle => 'Google Tasks trennen?';

  @override
  String get googleTasksStatusAvailable =>
      'Verbunden, Integration ausgeschaltet';

  @override
  String get googleTasksStatusSetup => 'Anmeldung fehlt';

  @override
  String get googleTasksStatusUnavailable => 'Nicht verfügbar';

  @override
  String get googleTasksStatusUnknown => 'Unbekannt';

  @override
  String get integrationDetailGoogleTasksAccount => 'Google-Konto';

  @override
  String get integrationDetailTodoistAccount => 'Todoist-Konto';

  @override
  String get todoistApiError =>
      'Fehler – Todoist nicht erreichbar oder Token abgelehnt';

  @override
  String get todoistChecking => 'Prüfe …';

  @override
  String get todoistConnect => 'Verbinden';

  @override
  String get todoistConnecting => 'Verbinde …';

  @override
  String get todoistErrDenied =>
      'Todoist hat den Token abgelehnt (ungültig oder widerrufen).';

  @override
  String get todoistErrFailed =>
      'Die Verbindung zu Todoist ist fehlgeschlagen.';

  @override
  String get todoistErrUnavailable =>
      'Todoist ist nicht erreichbar. Bitte später erneut versuchen.';

  @override
  String get todoistFine => 'in Ordnung';

  @override
  String get todoistIntro =>
      'Todoist-Aufgaben per persönlichem API-Token. Den Token findest du in Todoist unter Einstellungen → Integrationen → Entwickler. Er bleibt im sicheren Speicher des Geräts und wird nie angezeigt oder protokolliert. Projekte dienen als Listen.';

  @override
  String get todoistNeedToken => 'Bitte den API-Token eintragen.';

  @override
  String get todoistReachable => 'Todoist ist erreichbar.';

  @override
  String get todoistSignOutBody =>
      'Der Token wird vom Gerät gelöscht. In Todoist kannst du ihn zusätzlich widerrufen.';

  @override
  String get todoistSignOutTitle => 'Todoist trennen?';

  @override
  String get todoistStatusAvailable => 'Verbunden, Integration ausgeschaltet';

  @override
  String get todoistStatusSetup => 'Token fehlt';

  @override
  String get todoistStatusUnavailable => 'Nicht verfügbar';

  @override
  String get todoistStatusUnknown => 'Unbekannt';

  @override
  String get todoistToken => 'API-Token';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'Français';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get modelRowDeleteBody =>
      'Das Modell wird vom Gerät entfernt und muss vor der nächsten Nutzung neu geladen werden.';

  @override
  String modelRowDeleteTitle(String displayName) {
    return '$displayName löschen?';
  }

  @override
  String modelRowLoaded(String size) {
    return '$size · geladen';
  }

  @override
  String modelRowNotLoaded(String size) {
    return '$size · nicht geladen';
  }

  @override
  String modelRowProgressOf(String displayName) {
    return 'Fortschritt $displayName';
  }

  @override
  String modelRowRam(String ram) {
    return 'Arbeitsspeicher ca. $ram';
  }

  @override
  String get modelRowRecommended => '(empfohlen)';

  @override
  String get modelRowResume => 'Fortsetzen';

  @override
  String modelRowStarted(String size) {
    return '$size · angefangen';
  }

  @override
  String get voiceConvAdvanced => 'Erweitert';

  @override
  String get voiceConvBargeInUnavailable =>
      'Nicht verfügbar: Dafür braucht Wendelin das Wake-Word-Modell, das noch nicht eingebaut ist.';

  @override
  String get voiceConvBargeKeywords => 'Schlüsselwörter';

  @override
  String get voiceConvBargeSpeech => 'Beliebige Sprache (experimentell)';

  @override
  String get voiceConvCustomBarge =>
      'Eigene Einstellung für das Unterbrechen aktiv (unter „Erweitert“ zurücksetzbar).';

  @override
  String get voiceConvInterrupt => 'Unterbrechen während der Antwort';

  @override
  String get voiceConvInterruptHint =>
      'Mit „Wendelin“ unterbrichst du die Sprachausgabe.';

  @override
  String get voiceConvKeepListening => 'Weiter zuhören nach der Antwort';

  @override
  String get voiceConvKeepListeningDetail =>
      'Nach der gesprochenen Antwort bleibt das Mikrofon kurz offen, du kannst ohne Tippen nachfragen. „Danke“ oder „Stopp“ beendet.';

  @override
  String get voiceConvKeepListeningLabel => 'Weiter zuhören nach der Antwort';

  @override
  String get voiceDownloadAnd => ' und ';

  @override
  String voiceDownloadBundled(String displayName, String v) {
    return '$displayName gehört dazu ($v) und wird mitgeladen. „small“ erkennt Deutsch, Französisch und Namen deutlich besser. „base“ ist schnell und für schwache Geräte gedacht. Weitere Modelle: Einstellungen → Sprache.';
  }

  @override
  String get voiceDownloadContinueInBackground => 'Im Hintergrund weiterladen';

  @override
  String get voiceDownloadContinueLoading => 'Weiterladen';

  @override
  String get voiceDownloadIntro =>
      'Wendelin erkennt Sprache auf dem Gerät, ohne Internet und ohne Google. Wähle das Modell und lade es einmal, am besten im WLAN.';

  @override
  String get voiceDownloadLoad => 'Laden';

  @override
  String get voiceDownloadLoadAgain => 'Erneut laden';

  @override
  String get voiceDownloadLoading => 'Lädt …';

  @override
  String voiceDownloadLoadingPercent(String v) {
    return 'Lädt … $v %';
  }

  @override
  String voiceDownloadLoadingPercentOf(String v, String size) {
    return 'Lädt … $v % von $size';
  }

  @override
  String voiceDownloadPreselectedBase(String v) {
    return 'Vorausgewählt ist „base“, weil das Gerät wenig Arbeitsspeicher hat ($v GB). „small“ braucht beim Erkennen deutlich mehr Speicher.';
  }

  @override
  String get voiceDownloadProgressLabel => 'Fortschritt Spracherkennung';

  @override
  String get voiceDownloadReady => 'Bereit';

  @override
  String voiceDownloadSizeLoaded(String size) {
    return '$size · geladen';
  }

  @override
  String voiceDownloadSizeMb(String v) {
    return '$v MB';
  }

  @override
  String voiceDownloadSizePartial(String size) {
    return '$size · angefangen';
  }

  @override
  String voiceDownloadStillNeeded(String v) {
    return 'Noch nötig: $v';
  }

  @override
  String get voiceDownloadTitle => 'Spracherkennung laden';

  @override
  String get voiceDownloadUnpacking => 'Wird entpackt …';

  @override
  String get voiceErrorGeneric =>
      'Sprache hat nicht geklappt. Bitte versuche es noch einmal.';

  @override
  String get voiceErrorMicBusy =>
      'Das Mikrofon war noch belegt. Bitte sprich noch einmal.';

  @override
  String get voiceErrorModelBroken =>
      'Das Sprachmodell ist beschädigt. Bitte lade es neu (Einstellungen → Sprache).';

  @override
  String get voiceErrorModelMissing =>
      'Ein Sprachmodell ist noch nicht geladen (Einstellungen → Sprache).';

  @override
  String get voiceMetricsClear => 'Liste leeren';

  @override
  String get voiceMetricsEmpty =>
      'Noch keine Messwerte. Sprich einen Befehl oder spiele eine Stimmprobe ab.';

  @override
  String get voiceMetricsIntro =>
      'Die letzten Äußerungen dieser Sitzung: Rechenzeit (Latenz), Echtzeitfaktor (Rechenzeit je Audiozeit, kleiner ist schneller) und Speicher der App. Nur Zahlen, keine Inhalte.';

  @override
  String voiceMetricsRow(String latency, String audio, String rtf, String ram) {
    return '$latency ms für $audio ms Audio · RTF $rtf · RAM $ram';
  }

  @override
  String get voiceMetricsStt => 'Erkennung';

  @override
  String get voiceMetricsTts => 'Sprachausgabe';

  @override
  String get voiceScreenAutomatic => 'Automatisch';

  @override
  String get voiceScreenAutomaticDetail => 'Systemstimme, sonst Offline-Stimme';

  @override
  String get voiceScreenDetectAuto => 'Automatisch erkennen';

  @override
  String get voiceScreenFineTuning => 'Feinabstimmung';

  @override
  String get voiceScreenFixedLanguageHint =>
      'Mit fester Sprache erkennt Whisper kurze Sätze zuverlässiger.';

  @override
  String get voiceScreenIntro =>
      'Wendelin erkennt Sprache auf dem Gerät (Whisper). Die Modelle werden einmal geladen und bleiben auf dem Gerät.';

  @override
  String get voiceScreenKeepModel => 'Modell im Speicher halten';

  @override
  String get voiceScreenKeepModelHint =>
      'Erkennung und Stimme bleiben geladen: schnellere Antworten, aber dauerhaft mehr Arbeitsspeicher. Bei Speicherknappheit gibt Wendelin sie frei.';

  @override
  String get voiceScreenKeepModelLabel => 'Modell im Speicher halten';

  @override
  String get voiceScreenLanguageDefault => 'Standard der Sprache';

  @override
  String get voiceScreenLanguageDefaultChip => 'Standard der Sprache';

  @override
  String get voiceScreenLearnsVoice => 'Wendelin lernt deine Stimme';

  @override
  String get voiceScreenLearnsVoiceDetail =>
      'Einlernen, kalibrieren und ausprobieren';

  @override
  String voiceScreenLikeApp(String v) {
    return 'Wie die App ($v)';
  }

  @override
  String get voiceScreenListen => 'Probe hören';

  @override
  String get voiceScreenMetrics => 'Messwerte';

  @override
  String get voiceScreenMetricsDetail =>
      'Zeit, Echtzeitfaktor und Speicher je Äußerung';

  @override
  String get voiceScreenMicrophone => 'Mikrofon';

  @override
  String get voiceScreenMicrophoneTitle => 'Mikrofon';

  @override
  String get voiceScreenMinSpeech => 'Mindestsprechdauer';

  @override
  String get voiceScreenMinSpeechDetail =>
      'Kürzere Geräusche (Klicks, Atmer) werden ignoriert.';

  @override
  String get voiceScreenModelLicenses => 'Lizenzen der Sprachmodelle';

  @override
  String voiceScreenMs(int v) {
    return '$v ms';
  }

  @override
  String get voiceScreenNoOfflineVoice =>
      'Keine Offline-Stimme für diese Sprache geladen – Wendelin spricht mit der Systemstimme.';

  @override
  String get voiceScreenNoSpeech =>
      'Keine Sprachausgabe verfügbar: Antworten erscheinen nur auf dem Bildschirm. Lade eine Offline-Stimme.';

  @override
  String get voiceScreenNoSystemVoice =>
      'Keine Systemstimme installiert – Wendelin spricht mit der Offline-Stimme.';

  @override
  String get voiceScreenNotAllowed => 'nicht erlaubt';

  @override
  String get voiceScreenOfflineVoice => 'Offline-Stimme';

  @override
  String get voiceScreenOfflineVoices => 'Offline-Stimmen';

  @override
  String get voiceScreenRecognition => 'Spracherkennung';

  @override
  String get voiceScreenRecognitionHint =>
      'Für die Spracheingabe braucht Wendelin das gewählte Whisper-Modell und die Sprachaktivitätserkennung.';

  @override
  String voiceScreenRecommendSmall(String v) {
    return 'Empfohlen: small (genauer), $v laden.';
  }

  @override
  String get voiceScreenSensitivity => 'Empfindlichkeit der Spracherkennung';

  @override
  String get voiceScreenSensitivityDetail =>
      'Schwelle von Silero VAD: niedriger hört leiser, höher ignoriert mehr Geräusche.';

  @override
  String get voiceScreenSpeaksOffline =>
      'Wendelin spricht mit der Offline-Stimme.';

  @override
  String get voiceScreenSpeaksSystem =>
      'Wendelin spricht mit der Systemstimme.';

  @override
  String get voiceScreenSpeechOutput => 'Sprachausgabe';

  @override
  String get voiceScreenSpokenLanguage => 'Gesprochene Sprache';

  @override
  String get voiceScreenSystemVoice => 'Systemstimme';

  @override
  String get voiceScreenSystemVoiceTitle => 'Systemstimme';

  @override
  String get voiceScreenTempo => 'Tempo';

  @override
  String get voiceScreenVoice => 'Stimme';

  @override
  String get voiceScreenVoiceAndTempo => 'Stimme und Tempo';

  @override
  String voiceScreenVoiceLanguage(String v, String language) {
    return '$v ($language)';
  }

  @override
  String get voiceScreenVoices => 'Stimmen';

  @override
  String get voiceScreenVoicesDetail =>
      'Je Sprache eine weibliche und eine männliche Stimme';

  @override
  String get voiceSpokenAlwaysDetail =>
      'Wendelin schreibt zuerst einen kurzen Sprechtext und liest ihn immer vor, auch nach Inhalten aus dem Web oder von Dritten.';

  @override
  String get voiceSpokenAlwaysTitle => 'Immer eigene Sprechfassung';

  @override
  String get voiceSpokenAlwaysWarning =>
      'Was vorgelesen wird, kann von dem abweichen, was auf dem Bildschirm steht.';

  @override
  String get voiceSpokenCheckedDetail =>
      'Nach Inhalten aus dem Web oder von Dritten prüft ein weiterer Modellaufruf, ob Sprechtext und Antwort übereinstimmen. Die Sprachausgabe beginnt dann etwas später und kostet etwas mehr.';

  @override
  String get voiceSpokenCheckedTitle => 'Mit KI-Prüfung';

  @override
  String get voiceSpokenOffDetail =>
      'Wendelin liest die angezeigte Antwort vor, nur für die Aussprache aufbereitet.';

  @override
  String get voiceSpokenProtectedDetail =>
      'Eigener Sprechtext, aber nach Inhalten aus dem Web oder von Dritten liest Wendelin die angezeigte Antwort vor.';

  @override
  String get voiceSpokenProtectedTitle => 'Geschützt';

  @override
  String voiceSpokenSemantic(String label) {
    return 'Sprechfassung $label';
  }

  @override
  String get voiceSpokenTitle => 'Sprechfassung';

  @override
  String get voiceUnavailableHint =>
      'Spracherkennung laden: Einstellungen → Sprache';

  @override
  String get voiceVoicesIntro =>
      'Wähle je Sprache die Offline-Stimme. Nur geladene Stimmen belegen Speicher; nicht gebrauchte kannst du löschen.';

  @override
  String voiceVoicesNotLoaded(String v) {
    return 'Gewählte Stimme nicht geladen – es spricht $v.';
  }

  @override
  String get voiceVoicesPreparing => 'Probe wird vorbereitet …';

  @override
  String get voiceVoicesSampleFailed =>
      'Probe nicht möglich – die Stimme hat nicht gesprochen.';

  @override
  String get voiceVoicesSpeaker => 'Sprecher';

  @override
  String get voiceVoicesStopSample => 'Probe beenden';

  @override
  String bargeDebugDefaultSuffix(String v) {
    return '$v (Standard)';
  }

  @override
  String get bargeDebugExtraThreshold => 'Zusätzliche Schwelle';

  @override
  String get bargeDebugHelpCommunication =>
      'Kommunikation + AEC (Standard): Das Handy rechnet die eigene Ausgabe aus dem Mikrofon heraus. Wendelin hört sich selbst kaum, dein Wort kommt aber etwas leiser an.';

  @override
  String get bargeDebugHelpMargin =>
      'Die Schwelle legt fest, wie genau ein Wort passen muss. Höher (0,05, Standard): weniger Fehlalarme, dafür wird dein Wort öfter überhört. Niedriger (0,00 oder -0,05): das Wort wird leichter erkannt, dafür gibt es mehr Fehlalarme.';

  @override
  String get bargeDebugHelpRecognition =>
      'Erkennung, ohne AEC: keine Echo-Unterdrückung. Dein Wort kommt klar an, aber die laufende Ansage übertönt es oft, und Wendelin kann sich selbst hören.';

  @override
  String get bargeDebugHelpRecognitionAec =>
      'Erkennung + AEC: wie Standard, aber mit dem Mikrofon der Spracherkennung. Hilft auf Geräten, bei denen das Standard-Mikrofon dein Wort zu stark dämpft.';

  @override
  String get bargeDebugIntro =>
      'Damit stellst du ein, wie empfindlich „Wendelin“ während der Antwort erkannt wird. Die Änderung gilt ab der nächsten gesprochenen Antwort.';

  @override
  String get bargeDebugMicCommunication => 'Kommunikation + AEC (Standard)';

  @override
  String get bargeDebugMicDuring => 'Mikrofon während der Antwort';

  @override
  String get bargeDebugMicRecognition => 'Erkennung, ohne AEC';

  @override
  String get bargeDebugMicRecognitionAec => 'Erkennung + AEC';

  @override
  String get bargeDebugTitle => 'Erweitert: Unterbrechen';

  @override
  String get micAllowTitle => 'Mikrofon erlauben?';

  @override
  String get micAndroidSettings => 'Android-Einstellungen';

  @override
  String get micExplanation =>
      'Wendelin hört nur zu, nachdem du ihn ausgelöst hast (Mikrofontaste oder Assistent). Die Aufnahme wird auf dem Gerät in Text umgewandelt und verlässt es nicht; nur der erkannte Text geht an deinen Provider.';

  @override
  String get micNotNow => 'Nicht jetzt';

  @override
  String micOnlyText(String v) {
    return 'Ohne Mikrofon geht nur Text. $v';
  }

  @override
  String get micSettingsHint =>
      'In den Android-Einstellungen unter Apps → Wendelin erlauben.';

  @override
  String get speechCommunicationHelp =>
      'Die Antwort läuft wie ein Anruf über den Lautsprecher, damit „Wendelin“ sicherer erkannt wird. Nebenwirkungen: Es gilt die Anruf-Lautstärke, der Klang ist dünner, und mit Bluetooth-Geräten kann die Wiedergabe umschalten. Mit Kopfhörern bleibt die Ausgabe dort. Gilt ab der nächsten Antwort.';

  @override
  String get speechCommunicationTitle =>
      'Antwort als Gesprächston (bessere Echo-Unterdrückung)';

  @override
  String get wakeCalibrateCancelled => 'Abgebrochen. Es wurde nichts geändert.';

  @override
  String get wakeCalibrateDone => 'Kalibriert.';

  @override
  String wakeCalibrateFailed(Object error) {
    return 'Gescheitert: $error';
  }

  @override
  String get wakeCalibrateFinishNow => 'Jetzt beenden';

  @override
  String get wakeCalibrateIntro =>
      'Leg das Handy hin und red normal weiter. Wendelin hört mit (Mikrofonanzeige an), merkt sich aber nur Zahlenwerte, kein Audio und keinen Text. Ab und zu piept es: Sag dann „Wendelin“.';

  @override
  String get wakeCalibrateMicPreparing => 'Mikrofon wird vorbereitet …';

  @override
  String wakeCalibrateMinutesLeft(int v) {
    return 'Noch $v min';
  }

  @override
  String get wakeCalibrateNoMic =>
      'Ohne Mikrofon kann Wendelin nicht kalibrieren.';

  @override
  String get wakeCalibrateNotDistinct =>
      'Deine Aufnahmen heben sich nicht vom Hintergrund ab. Lerne deine Stimme bitte noch einmal ein. Die alte Schwelle bleibt.';

  @override
  String get wakeCalibrateProgressLabel => 'Fortschritt Kalibrieren';

  @override
  String wakeCalibratePrompts(int answered, int prompts) {
    return 'Aufforderungen: $answered von $prompts beantwortet';
  }

  @override
  String wakeCalibrateResult(String v, String v2, int v3) {
    return 'Schwelle $v · geschätzt $v2 Fehlalarme pro Stunde (vor der Nachprüfung) · $v3 % deiner Aufnahmen erkannt.';
  }

  @override
  String get wakeCalibrateTitle => 'Kalibrieren';

  @override
  String get wakeCalibrateUnusable => 'Nicht verwertbar.';

  @override
  String get wakeDetectorAuto => 'Automatisch';

  @override
  String get wakeDetectorAutoHint =>
      'Handy: deine Stimme (Vorlagen). Station: das trainierte Modell.';

  @override
  String get wakeDetectorModel => 'Trainiertes Modell';

  @override
  String get wakeDetectorModelHint =>
      'Erkennt „Wendelin“ ohne Einlernen. Braucht den Download.';

  @override
  String wakeDetectorModelNeeded(String v) {
    return 'Das trainierte Modell wird für diese Einstellung benötigt: $v.';
  }

  @override
  String get wakeDetectorTemplates => 'Vorlagen deiner Stimme';

  @override
  String get wakeDetectorTemplatesHint =>
      'Vergleicht mit deinen Aufnahmen. Braucht das Einlernen.';

  @override
  String get wakeDetectorTitle => 'Erkennung';

  @override
  String get wakeEnrollAllThere => 'Alle Aufnahmen sind da.';

  @override
  String wakeEnrollFailed(Object error) {
    return 'Das Einlernen ist gescheitert: $error';
  }

  @override
  String get wakeEnrollHeard => 'Gehört.';

  @override
  String get wakeEnrollInconsistent =>
      'Diese Aufnahme passte nicht zu den anderen und wurde entfernt. Bitte noch einmal.';

  @override
  String wakeEnrollIntro(String word) {
    return 'Sag „$word“, wenn du dran bist. Aus jeder Aufnahme behält Wendelin nur Zahlenwerte; das Audio wird sofort verworfen.';
  }

  @override
  String get wakeEnrollMicPreparing => 'Mikrofon wird vorbereitet …';

  @override
  String get wakeEnrollNoMic =>
      'Ohne Mikrofon kann Wendelin deine Stimme nicht lernen.';

  @override
  String get wakeEnrollNoSpeech => 'Nichts gehört. Noch einmal bitte.';

  @override
  String wakeEnrollNotWord(String word) {
    return 'Nicht als „$word“ erkannt. Bitte noch einmal.';
  }

  @override
  String get wakeEnrollProcessing => 'Wird verarbeitet …';

  @override
  String wakeEnrollProgress(int accepted, int target) {
    return '$accepted von $target';
  }

  @override
  String get wakeEnrollProgressLabel => 'Fortschritt Einlernen';

  @override
  String get wakeEnrollPrompt0 => 'Sprich normal, das Handy nah vor dir.';

  @override
  String get wakeEnrollPrompt1 => 'Jetzt aus ein bis zwei Metern Abstand.';

  @override
  String get wakeEnrollPrompt2 => 'Jetzt leise, wie abends im Zimmer.';

  @override
  String get wakeEnrollPrompt3 =>
      'Wie du es im Alltag sagst, gern aus einer anderen Ecke.';

  @override
  String wakeEnrollRejected(int count) {
    return '$count abgelehnt';
  }

  @override
  String wakeEnrollSaveWith(int accepted) {
    return 'Mit $accepted Aufnahmen speichern';
  }

  @override
  String wakeEnrollSayNow(String word) {
    return 'Sag jetzt: „$word“';
  }

  @override
  String get wakeEnrollTitle => 'Stimme einlernen';

  @override
  String get wakeEnrollTooEarly =>
      'Zu früh angefangen. Warte kurz und sprich dann.';

  @override
  String wakeEnrollTooLong(String word) {
    return 'Zu lang. Nur „$word“, bitte.';
  }

  @override
  String get wakeEnrollTooQuiet => 'Zu leise. Bitte etwas lauter.';

  @override
  String get wakeEnrollUnchecked =>
      'Die Prüfung ist gerade nicht möglich (Spracherkennung nicht bereit). Bitte noch einmal.';

  @override
  String get wakeExplainBatteryBody =>
      'Das ständige Zuhören kostet Akku. Standard ist deshalb „Nur beim Laden“.';

  @override
  String get wakeExplainBatteryExemptBody =>
      'Damit Android den Dienst nicht beendet, sollte Wendelin von der Akku-Optimierung ausgenommen sein.';

  @override
  String get wakeExplainBatteryExemptTitle => 'Akku-Optimierung ausnehmen?';

  @override
  String get wakeExplainBatteryTitle => 'Akku';

  @override
  String wakeExplainChecklist(String v, String v2) {
    return '$v: $v2';
  }

  @override
  String get wakeExplainEnable => 'Einschalten';

  @override
  String get wakeExplainEnableTitle => 'Aktivierungswort einschalten?';

  @override
  String get wakeExplainExempt => 'Ausnehmen';

  @override
  String get wakeExplainLocalBody =>
      'Die Erkennung des Wortes läuft auf dem Gerät. Was du nach „Wendelin“ sagst, wird als Text an den gewählten KI-Anbieter geschickt. Audio wird weder gesendet noch gespeichert.';

  @override
  String get wakeExplainLocalTitle => 'Zuhören bleibt auf dem Gerät';

  @override
  String get wakeExplainMicDotBody =>
      'Android zeigt den grünen Punkt für das Mikrofon, solange der Dienst zuhört.';

  @override
  String get wakeExplainMicDotTitle => 'Mikrofon-Punkt';

  @override
  String get wakeExplainPersistentBody =>
      'Solange Wendelin zuhört, zeigt Android eine Benachrichtigung. Ab Android 14 kannst du sie wegwischen, der Dienst läuft dann weiter. Ohne die Berechtigung für Benachrichtigungen zeigt Android keine; Wendelin hört trotzdem zu.';

  @override
  String get wakeExplainPersistentTitle => 'Dauerhafte Benachrichtigung';

  @override
  String get wakeModelsLoadModel => 'Sprachmodell laden';

  @override
  String wakeModelsNeedsModel(String v) {
    return 'Dafür muss zuerst das Sprachmodell geladen werden ($v).';
  }

  @override
  String wakeModelsVerifyNeeds(String v) {
    return 'Für die Nachprüfung Sprachmodell laden ($v).';
  }

  @override
  String get wakeServiceSectionAlways => 'Immer';

  @override
  String get wakeServiceSectionAlwaysHint => 'Kostet spürbar Akku.';

  @override
  String get wakeServiceSectionBackground => 'Zuhören im Hintergrund';

  @override
  String get wakeServiceSectionChime => 'Bestätigungston';

  @override
  String get wakeServiceSectionChimeDetail =>
      'Ein kurzer Ton, wenn Wendelin das Wort erkannt hat.';

  @override
  String get wakeServiceSectionChooseAssistant => 'Assistenten wählen';

  @override
  String get wakeServiceSectionEnable => 'Aktivierungswort einschalten';

  @override
  String get wakeServiceSectionEnableDetail =>
      'Wendelin hört im Hintergrund auf „Wendelin“.';

  @override
  String get wakeServiceSectionEndedEngine =>
      'Beendet: Die Erkennung ist ausgefallen';

  @override
  String get wakeServiceSectionEndedModel =>
      'Beendet: Ein Modell für die Wake-Erkennung fehlt';

  @override
  String get wakeServiceSectionEndedNoPermission =>
      'Beendet: Mikrofon-Berechtigung fehlt';

  @override
  String get wakeServiceSectionEndedNoRole =>
      'Beendet: Wendelin ist nicht mehr dein Assistent';

  @override
  String get wakeServiceSectionEndedNotCharging =>
      'Beendet: Das Gerät lädt nicht mehr';

  @override
  String get wakeServiceSectionEndedPaused => 'Beendet: pausiert';

  @override
  String get wakeServiceSectionEndedSystem => 'Vom System beendet';

  @override
  String get wakeServiceSectionEndedTimeout =>
      'Vom System beendet (Zeitlimit von Android)';

  @override
  String get wakeServiceSectionEnrollFirst => 'Erst Stimme einlernen';

  @override
  String get wakeServiceSectionEnrollFirstBody =>
      'Ohne eingelernte Stimme erkennt Wendelin das Aktivierungswort nicht.';

  @override
  String get wakeServiceSectionNotAssistant =>
      'Wendelin ist nicht dein Assistent';

  @override
  String get wakeServiceSectionNotAssistantBody =>
      'Android erlaubt das Zuhören im Hintergrund nur dem Standard-Assistenten. Wähle Wendelin als Assistenten.';

  @override
  String get wakeServiceSectionOnlyCharging => 'Nur beim Laden';

  @override
  String get wakeServiceSectionOnlyChargingHint =>
      'Schont den Akku (Standard).';

  @override
  String get wakeServiceSectionPausedLoading =>
      'Pausiert: wartet auf das Laden';

  @override
  String wakeServiceSectionPausedUntil(String v) {
    return 'Pausiert bis $v';
  }

  @override
  String get wakeServiceSectionRunning => 'Läuft';

  @override
  String get wakeServiceSectionSettingsFail =>
      'Die Systemeinstellungen ließen sich nicht öffnen.';

  @override
  String get wakeServiceSectionSoundCheck => 'Ton und Prüfung';

  @override
  String get wakeServiceSectionStatus => 'Status';

  @override
  String get wakeServiceSectionToEnroll => 'Zum Einlernen';

  @override
  String get wakeServiceSectionWhen => 'Wann zuhören?';

  @override
  String get wakeServiceSectionWhisper => 'Nachprüfung mit Whisper';

  @override
  String get wakeServiceSectionWhisperDetail =>
      'Wendelin hört nur zu, wenn Whisper „Wendelin“ bestätigt. Schalte es aus, wenn es mit deiner Stimme zu streng ist; dann gibt es mehr Fehlauslösungen.';

  @override
  String wakeTestAgo(String v, int inSeconds) {
    return '$v · $inSeconds s';
  }

  @override
  String wakeTestBest(String v, String v2) {
    return '$v · höchste Ähnlichkeit $v2';
  }

  @override
  String wakeTestCandidate(String v) {
    return 'Kandidat · Ähnlichkeit $v';
  }

  @override
  String get wakeTestConfirmed => 'Nachprüfung: bestätigt';

  @override
  String wakeTestFailed(Object error) {
    return 'Gescheitert: $error';
  }

  @override
  String get wakeTestIntro =>
      'Sag „Wendelin“. Hier erscheinen Treffer, ohne dass das Overlay aufgeht. „Kandidat“ ist die Stimme, „bestätigt“ die Nachprüfung mit Whisper.';

  @override
  String get wakeTestListening => 'Hört zu';

  @override
  String get wakeTestMicPreparing => 'Mikrofon wird vorbereitet …';

  @override
  String get wakeTestNoHit => 'Noch kein Treffer.';

  @override
  String get wakeTestNoMic => 'Ohne Mikrofon geht der Test nicht.';

  @override
  String get wakeTestRejected => 'Nachprüfung: nicht bestätigt';

  @override
  String get wakeTestStopped => 'Angehalten';

  @override
  String get wakeTestTitle => 'Ausprobieren';

  @override
  String get wakeTestUnavailable => 'Nachprüfung: nicht möglich (kein Whisper)';

  @override
  String get wakeTestVerifying => 'Nachprüfung läuft …';

  @override
  String wakeWordActionsFor(String v) {
    return 'Aktionen für $v';
  }

  @override
  String get wakeWordCalibrate => 'Kalibrieren (30 min, empfohlen)';

  @override
  String get wakeWordDeleteAll => 'Alle Stimmen löschen';

  @override
  String get wakeWordDeleteAllBody =>
      'Wendelin vergisst alle eingelernten Stimmen. Du kannst sie später neu einlernen.';

  @override
  String get wakeWordDeleteAllTitle => 'Alle Stimmen löschen?';

  @override
  String get wakeWordEnroll => 'Stimme einlernen';

  @override
  String get wakeWordEnrollMore => 'Weitere Person einlernen';

  @override
  String get wakeWordFeatureModels => 'Merkmalsmodelle';

  @override
  String get wakeWordIntro =>
      'Wendelin lernt deine Stimme: Du sagst „Wendelin“ etwa 15 Mal, danach erkennt er es auch im Alltag. Gespeichert werden nur Zahlenwerte, verschlüsselt auf dem Gerät. Audio wird nie gespeichert.';

  @override
  String get wakeWordLearned => 'Gelernte Stimmen';

  @override
  String get wakeWordNameOptional => 'Name (optional)';

  @override
  String get wakeWordNeedsModel =>
      'Dafür muss zuerst das Sprachmodell geladen werden.';

  @override
  String get wakeWordNoVoice => 'Noch keine Stimme';

  @override
  String get wakeWordNoVoiceHint =>
      'Lerne mit „Stimme einlernen“ deine Stimme ein.';

  @override
  String wakeWordPerson(int number) {
    return 'Person $number';
  }

  @override
  String wakeWordRecordingsThreshold(int length, String v) {
    return '$length Aufnahmen · Schwelle $v';
  }

  @override
  String get wakeWordRetrain => 'Neu einlernen';

  @override
  String wakeWordTemplatesFew(int count) {
    return 'Nur $count brauchbare Aufnahmen übrig. Bitte neu einlernen.';
  }

  @override
  String get wakeWordTemplatesMissing =>
      'Vorlagen fehlen. Bitte neu einlernen.';

  @override
  String get wakeWordTemplatesOutdated =>
      'Die Vorlagen sind veraltet (der Vergleich wurde verbessert). Bitte neu einlernen.';

  @override
  String get wakeWordTryNow => 'Jetzt ausprobieren';

  @override
  String get wakeWordWhoCalibrate => 'Wen kalibrieren?';

  @override
  String get wakeWordWhoJoins => 'Wer kommt dazu?';

  @override
  String get wakeWordWhoSpeaks => 'Wer spricht?';

  @override
  String get weatherHomeHelp =>
      'Wird genutzt, wenn du keinen Ort nennst und der Standort nicht bekannt ist. Leer lassen = kein Heimatort.';

  @override
  String get weatherHomeLabel => 'Heimatort, z. B. Kiel';

  @override
  String get weatherIntro =>
      'Alle Wetterdienste sind kostenlos und brauchen keinen Schlüssel. Meeresdaten (Wellen, Wassertemperatur) kommen immer von Open-Meteo.';

  @override
  String get weatherKindBrightSkyDetail => 'Daten des Deutschen Wetterdienstes';

  @override
  String get weatherKindMetNorwayDetail =>
      'Norwegischer Wetterdienst, weltweit';

  @override
  String get weatherKindOpenMeteoDetail => 'Standard, weltweit';

  @override
  String weatherNotFound(String name) {
    return 'Ort „$name“ nicht gefunden.';
  }

  @override
  String get weatherSearchFailed =>
      'Ortssuche nicht erreichbar, später erneut.';

  @override
  String get weatherSetupDetail =>
      'Dienst wählen, Ort für „Wetter hier“ festlegen';

  @override
  String get weatherSetupTitle => 'Wetterdienst und Heimatort';

  @override
  String get weatherTitle => 'Wetter und Meer';

  @override
  String get webSearchAddress => 'Adresse, z. B. https://search.example.org';

  @override
  String get webSearchAddressMissing =>
      'Bitte die Adresse der Instanz angeben.';

  @override
  String get webSearchApiKey => 'API-Key';

  @override
  String get webSearchIntro =>
      'Ohne Suchdienst kann Wendelin nur Seiten lesen, deren Adresse du nennst.';

  @override
  String get webSearchKeyMissing => 'Bitte den API-Key eingeben.';

  @override
  String get webSearchKeySaved => 'Key gespeichert – leer lassen behält ihn';

  @override
  String get webSearchNone => 'Kein Suchdienst';

  @override
  String get webSearchOwnInstance => 'SearXNG (eigene Instanz)';

  @override
  String get webSearchTitle => 'Web-Suche';
}
