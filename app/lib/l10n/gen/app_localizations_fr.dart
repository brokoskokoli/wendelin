// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get agentNoticeCancelled => 'Annulé.';

  @override
  String get agentNoticeGpuFailed =>
      'Échec de la vérification du GPU. Détails dans le journal de vérification.';

  @override
  String get agentNoticeGpuNoEvidence =>
      'Ce modèle ne fournit aucune preuve GPU. Touchez Envoyer sans vérification GPU.';

  @override
  String agentNoticeProfileBroken(Object e) {
    return 'Profil de fournisseur défectueux : $e';
  }

  @override
  String get agentNoticeRecheckFailed =>
      'La nouvelle vérification a échoué. Détails dans le journal de vérification.';

  @override
  String get agentNoticeRequestEmpty => 'La demande est vide.';

  @override
  String get agentNoticeRequestRunning => 'Une demande est déjà en cours.';

  @override
  String get agentNoticeSetupFirst => 'Configurez d’abord un fournisseur.';

  @override
  String get agentNoticeStartFailed => 'La demande n’a pas pu démarrer.';

  @override
  String agentNoticeUndoFailed(Object e) {
    return 'L’annulation n’a pas fonctionné : $e';
  }

  @override
  String get assistantAnotherService => 'un autre service';

  @override
  String get assistantChangeInAndroid => 'Modifier dans Android';

  @override
  String get assistantDefaultHint =>
      'Un appui long sur le bouton d’alimentation ou le geste de l’assistant ouvre Wendelin au-dessus de toute application.';

  @override
  String get assistantDefaultTitle => 'Assistant par défaut';

  @override
  String get assistantInactiveDefault =>
      'Android renvoie les autres applications vers Wendelin, mais la reconnaissance vocale est désactivée (interrupteur coupé). Les autres applications reçoivent alors une erreur.';

  @override
  String get assistantInactiveNotDefault =>
      'Android renvoie les autres applications vers Wendelin, mais la reconnaissance vocale est désactivée : Wendelin n’est pas l’assistant par défaut. Les autres applications reçoivent alors une erreur.';

  @override
  String get assistantIsDefault => 'Wendelin est l’assistant par défaut';

  @override
  String get assistantNameHint =>
      'Le nom et la personnalité sont transmis au modèle dans le cadre des instructions.';

  @override
  String get assistantNameLabel => 'Comment Wendelin doit-il vous appeler ?';

  @override
  String get assistantNotAvailable => 'Non disponible sur cet appareil';

  @override
  String get assistantNotDefault => 'Non défini comme assistant par défaut';

  @override
  String get assistantOfferRecognizer =>
      'Proposer comme reconnaissance vocale pour les autres applications';

  @override
  String assistantOfferRecognizerUnavailable(String reason) {
    return 'Proposer comme reconnaissance vocale pour les autres applications, $reason';
  }

  @override
  String assistantOtherForNowDefault(String app) {
    return 'Android utilise actuellement $app pour les autres applications. Le passage à Wendelin après l’activation dépend de l’appareil.';
  }

  @override
  String assistantOtherForNowNotDefault(String app) {
    return 'Android utilise actuellement $app pour les autres applications. Cela peut changer dès que Wendelin est l’assistant par défaut.';
  }

  @override
  String assistantOtherRecognizer(String app) {
    return 'Android utilise $app pour les autres applications. Cela ne peut pas être modifié sur cet appareil.';
  }

  @override
  String get assistantPersonaLabel =>
      'Personnalité, p. ex. « réponds brièvement et décontracté »';

  @override
  String get assistantRecognizerActiveDetail =>
      'Android utilise Wendelin pour la saisie vocale des autres applications. Whisper reconnaît sur l’appareil, les enregistrements ne sont pas conservés.';

  @override
  String get assistantRecognizerActiveHint =>
      'Android utilise Wendelin pour la saisie vocale des autres applications.';

  @override
  String get assistantRecognizerUnknownDetail =>
      'Tant que Wendelin est l’assistant par défaut, les autres applications peuvent utiliser la saisie vocale. Whisper reconnaît sur l’appareil, les enregistrements ne sont pas conservés.';

  @override
  String get assistantSetDefault => 'Définir comme assistant par défaut';

  @override
  String get assistantSetLabel => 'défini';

  @override
  String get assistantSwitchHint =>
      'Si vous passez plus tard à un autre assistant (ou à « Aucun »), la reconnaissance vocale de Wendelin ne répond plus aux autres applications. Choisissez alors à nouveau la saisie vocale dans les paramètres Android, en général sous Applications → Applications par défaut → Assistant numérique.';

  @override
  String get conversationOfferHint =>
      'Vous pouvez le modifier à tout moment sous Paramètres → Voix.';

  @override
  String get conversationOfferQuestion =>
      'Dois-je continuer à écouter après mes réponses par défaut ?';

  @override
  String reducerBudgetUsed(String name, String spent, String budget) {
    return 'Budget de $name : $spent sur $budget utilisé.';
  }

  @override
  String reducerHandedOver(String name) {
    return 'transmis à $name';
  }

  @override
  String get reducerSpokenFallback =>
      'La version affichée a été lue à voix haute.';

  @override
  String get reducerVerificationFailed =>
      'La réponse du fournisseur n’a pas pu être vérifiée.';

  @override
  String get attCheckFailed => 'Vérification échouée';

  @override
  String get attChecking => 'en cours de vérification';

  @override
  String get attE2eeKeyNote =>
      'Tout le contenu est chiffré avec cette clé vérifiée. Le chiffrement se termine dans la passerelle du fournisseur (enclave vérifiée), et non dans le modèle lui-même. Avec NEAR AI, il se termine dans le modèle vérifié. Avec Tinfoil, il se termine dans le routeur vérifié, qui le transmet au modèle.';

  @override
  String get attExplainAccept => 'Accepter';

  @override
  String attExplainChecked(String what) {
    return 'Ce qui est vérifié : $what';
  }

  @override
  String get attExplainIntro =>
      'Ce que Wendelin vérifie, ce qui en est ressorti et ce que cela signifie pour votre sécurité.';

  @override
  String attExplainMeaning(String v) {
    return 'Signification : $v';
  }

  @override
  String attExplainRestrictionsDetail(String v) {
    return '$v : consigné seulement. Si vous l’acceptez, la conversation n’affiche plus d’avertissement à ce sujet.';
  }

  @override
  String get attExplainRestrictionsTitle => 'Restrictions de ce fournisseur';

  @override
  String attExplainResult(String detail) {
    return 'Résultat : $detail';
  }

  @override
  String attExplainStageLine(String label, String result) {
    return '$label · $result';
  }

  @override
  String get attExplainTitle => 'Détails de la vérification';

  @override
  String get attFailedText =>
      'La réponse n’a pas pu être confirmée comme provenant sans modification de l’environnement vérifié, par exemple à cause d’une erreur de signature ou de sommes de contrôle différentes. Cela peut indiquer une manipulation. Ne faites pas confiance à la réponse. Le fournisseur est bloqué tant que vous ne l’avez pas revérifié.';

  @override
  String get attFinishBudgetLabel => 'Budget par mois en \$ (facultatif)';

  @override
  String get attFinishImagesNo => '✕ Images';

  @override
  String get attFinishImagesYes => '✓ Images';

  @override
  String get attFinishModelChecked => 'Modèle vérifié';

  @override
  String attFinishPercentOfBudget(int v) {
    return '$v % du budget';
  }

  @override
  String get attFinishPrivacyLevel => 'Niveau de confidentialité';

  @override
  String attFinishRestrictionNote(String v) {
    return '$v. Le fournisseur ne le fournit pas ou Wendelin ne le vérifie pas, c’est seulement consigné. En touchant « Enregistrer », vous l’acceptez. Dès que quelque chose de nouveau s’y ajoute, Wendelin vous le signale à nouveau. Plus d’informations sous « Détails ».';
  }

  @override
  String get attFinishTeeYes => '✓ TEE';

  @override
  String get attFinishToolsNo => '✕ Outils';

  @override
  String get attFinishToolsYes => '✓ Outils';

  @override
  String get attFinishWarnFrom => 'Avertir à partir de';

  @override
  String get attFloorCorruptText =>
      'La limite inférieure enregistrée pour la version du logiciel de ce fournisseur est endommagée. Sans elle, un retour à un logiciel plus ancien et non sûr ne peut pas être exclu ; la vérification reste donc bloquée et une nouvelle vérification n’y change rien. N’envoyez rien de confidentiel. Seule la réinitialisation des données de l’app permet d’en sortir. Ensuite, le premier contact est de nouveau vérifié sans protection contre le retour en arrière.';

  @override
  String get attFloorCorruptTitle =>
      'Protection enregistrée contre le retour en arrière endommagée';

  @override
  String get attGpuFailedLabel => 'Vérification du GPU échouée';

  @override
  String attGpuFailedText(String v) {
    return 'La vérification du GPU via NVIDIA a échoué.$v La prochaine demande vers ce modèle sera d’abord vérifiée.';
  }

  @override
  String get attGpuFailedTitle => 'Vérification du GPU échouée';

  @override
  String get attGpuUnavailableLabel => 'Vérification du GPU impossible';

  @override
  String attGpuUnavailableText(String v) {
    return 'La vérification du GPU via NVIDIA n’a pas été possible.$v La prochaine demande vers ce modèle sera d’abord vérifiée.';
  }

  @override
  String get attGpuUnavailableTitle => 'Vérification du GPU impossible';

  @override
  String get attLogCommit => 'Commit';

  @override
  String get attLogKeysetDigest => 'Empreinte de l’ensemble de clés';

  @override
  String get attLogModel => 'Modèle';

  @override
  String get attLogNewRestriction => 'Nouvelle restriction';

  @override
  String attLogNewRestrictionDetail(String v) {
    return '$v : consigné seulement et pas encore accepté par vous. Sous « Détails », vous pouvez le consulter et l’accepter.';
  }

  @override
  String get attLogNoEntry =>
      'Il n’y a pas encore d’entrée pour cette réponse.';

  @override
  String get attLogParticulars => 'Informations';

  @override
  String get attLogProvider => 'Fournisseur';

  @override
  String get attLogReasonCode => 'Code de motif';

  @override
  String get attLogReceiptId => 'ID du reçu';

  @override
  String get attLogRecheck => 'Revérifier';

  @override
  String get attLogRecheckFailed => 'La nouvelle vérification n’a pas réussi.';

  @override
  String get attLogRechecked => 'Fournisseur revérifié, le blocage est levé.';

  @override
  String get attLogResultPerStep => 'Résultat par étape';

  @override
  String attLogScreenCommitLine(String repoCommit) {
    return 'Commit $repoCommit';
  }

  @override
  String get attLogScreenDeleteBody =>
      'Toutes les entrées du journal de vérification seront supprimées. Cette action est irréversible.';

  @override
  String get attLogScreenDeleteLog => 'Supprimer le journal de vérification';

  @override
  String get attLogScreenDeleteTitle =>
      'Supprimer le journal de vérification ?';

  @override
  String get attLogScreenDeleted => 'Supprimé.';

  @override
  String get attLogScreenExportJson => 'Exporter en JSON';

  @override
  String get attLogScreenFilterAll => 'Toutes';

  @override
  String get attLogScreenFilterGreen => 'Vérifiées';

  @override
  String get attLogScreenFilterRed => 'Échouées';

  @override
  String get attLogScreenFilterUnconfirmed => 'Non confirmées';

  @override
  String get attLogScreenFilterYellow => 'En cours de vérification';

  @override
  String attLogScreenGpuTitle(String v) {
    return 'GPU · $v';
  }

  @override
  String get attLogScreenIntro =>
      'Wendelin vérifie les fournisseurs dotés d’un environnement protégé (TEE), ainsi que chaque réponse. Voici ce qui a été vérifié. Jamais de contenu, seulement des identifiants, des sommes de contrôle et des résultats.';

  @override
  String get attLogScreenNoEntries => 'Aucune entrée.';

  @override
  String attLogScreenReceiptTitle(String v, String providerName) {
    return '$v · $providerName';
  }

  @override
  String get attLogScreenRecheckAttest => 'Revérifier';

  @override
  String get attLogScreenRechecked => 'Revérifié, un blocage a été levé.';

  @override
  String get attLogScreenSessionGreen => 'Session vérifiée';

  @override
  String get attLogScreenSessionRed => 'Session échouée';

  @override
  String attLogScreenSessionTitle(String providerName) {
    return 'Session · $providerName';
  }

  @override
  String get attLogScreenSessionUnconfirmed => 'Session non confirmée';

  @override
  String get attLogScreenSessionYellow => 'Session non vérifiable';

  @override
  String get attLogTime => 'Heure';

  @override
  String get attLogTitle => 'Journal de vérification';

  @override
  String get attLogTitle2 => 'Journal de vérification';

  @override
  String get attMismatchText =>
      'L’attestation de la session ne correspond pas au reçu signé de cette réponse. Ne faites pas confiance à la réponse. Le fournisseur est bloqué tant que vous ne l’avez pas revérifié.';

  @override
  String get attMismatchTitle => 'Tentative de manipulation possible';

  @override
  String attReasonLead(String reason, String v) {
    return ' Raison : $reason$v';
  }

  @override
  String get attReceiptMissing => 'Reçu manquant';

  @override
  String get attReceiptMissingText =>
      'Le fournisseur n’a pas fourni d’identifiant de reçu pour cette réponse.';

  @override
  String get attReceiptNotFound => 'Reçu introuvable';

  @override
  String get attReceiptNotFoundText =>
      'Le fournisseur ne connaît pas le reçu de cette réponse (pas encore écrit ou expiré).';

  @override
  String get attReceiptRejectedLabel => 'Reçu refusé';

  @override
  String get attReceiptRejectedText =>
      'Le fournisseur a refusé la demande de reçu (par exemple en raison d’un trop grand nombre de requêtes). La réponse n’est pas confirmée, mais rien n’indique une manipulation. Revérifiez le fournisseur.';

  @override
  String get attReceiptRejectedTitle =>
      'Demande de reçu refusée par le fournisseur';

  @override
  String get attReceiptUnreachable => 'Reçu inaccessible';

  @override
  String get attReceiptUnreachableText =>
      'Le reçu de cette réponse n’a pas pu être récupéré à cause d’une erreur réseau ou serveur.';

  @override
  String get attRelaunchText =>
      'Le fabricant recommande à l’exploitant de redémarrer l’environnement protégé pour qu’une mise à jour de sécurité prenne effet. Ce n’est pas le signe d’une manipulation. Revérifiez plus tard.';

  @override
  String get attRelaunchTitle =>
      'Redémarrage du TEE recommandé chez l’exploitant';

  @override
  String get attResponseWord => 'Réponse';

  @override
  String get attRestrictionOpen => 'vérifié, nouvelle restriction';

  @override
  String get attResultInfo => 'consigné seulement';

  @override
  String get attResultUnavailable => 'indisponible';

  @override
  String get attResultWarn => 'avertissement';

  @override
  String get attRevokedText =>
      'Le fabricant a révoqué la plateforme matérielle de l’exploitant comme non sûre. N’envoyez rien de confidentiel tant que l’exploitant ne l’a pas remplacée.';

  @override
  String get attRevokedTitle => 'Plateforme de l’exploitant révoquée';

  @override
  String get attRollbackText =>
      'Le fournisseur signale une version du logiciel plus ancienne que celle déjà vérifiée ici. Il peut s’agir d’un logiciel ancien et vulnérable ou de données anciennes rejouées. La requête n’a pas été envoyée. N’envoyez rien de confidentiel et revérifiez plus tard.';

  @override
  String get attRollbackTitle =>
      'Version du logiciel plus ancienne que celle vérifiée';

  @override
  String get attSBindHpke => 'Clé de chiffrement liée';

  @override
  String get attSCompose => 'Hash compose';

  @override
  String get attSE2eeKey => 'Clé E2EE vérifiée';

  @override
  String get attSE2eeKeyset => 'Ensemble de clés de la réponse';

  @override
  String get attSE2eeRequest => 'Chiffrement de la demande';

  @override
  String get attSE2eeResponse => 'Déchiffrement de la réponse';

  @override
  String get attSEventLog => 'Journal d’événements';

  @override
  String get attSFreshness => 'Fraîcheur';

  @override
  String get attSGateway => 'Passerelle du fournisseur';

  @override
  String get attSGpu => 'Preuve du GPU';

  @override
  String get attSGpuEvidence => 'Preuve GPU du fournisseur';

  @override
  String get attSKeysetDigest => 'Ensemble de clés (empreinte)';

  @override
  String get attSKeysetSignature => 'Signature de l’ensemble de clés';

  @override
  String get attSMeasurement => 'Mesure = version';

  @override
  String get attSNoReceipt => 'Reçu par réponse';

  @override
  String get attSNonce => 'Nonce lié';

  @override
  String get attSProvenance => 'Provenance (commit)';

  @override
  String get attSQuote => 'Quote TDX (DCAP)';

  @override
  String get attSReceiptBinding => 'Reçu lié à la session';

  @override
  String get attSReceiptEvents => 'Événements du reçu';

  @override
  String get attSReceiptFetch => 'Reçu récupéré';

  @override
  String get attSReceiptRequest => 'Hash de la demande';

  @override
  String get attSReceiptResponse => 'Hash de la réponse';

  @override
  String get attSReceiptSignature => 'Signature du reçu';

  @override
  String get attSReleaseFloor => 'Pas de retour en arrière';

  @override
  String get attSSigstore => 'Version signée (Sigstore)';

  @override
  String get attSSnpChain => 'Chaîne de certificats AMD';

  @override
  String get attSSnpPolicy => 'Politique du processeur';

  @override
  String get attSSnpReport => 'Attestation matérielle AMD';

  @override
  String get attSTcb => 'Niveau de sécurité de la plateforme (TCB)';

  @override
  String get attSTls => 'Connexion TLS vérifiée';

  @override
  String get attSUpstream => 'Vérification en amont';

  @override
  String get attSUpstreamTcb => 'Niveau de sécurité en amont';

  @override
  String attStagesCardAllPassed(int length) {
    return 'Les $length étapes sont réussies';
  }

  @override
  String get attStagesCardFirst => 'Première attestation';

  @override
  String get attStagesCardNotPassed => 'non réussie';

  @override
  String attStagesCardSomePassed(int failed, int length, String v) {
    return 'Étapes non réussies : $failed sur $length ($v)';
  }

  @override
  String get attStagesCardViewLog => 'Voir le journal de vérification';

  @override
  String attStoredReason(String text, String v) {
    return ' Raison : $text$v';
  }

  @override
  String get attSummaryGreen => 'vérifié';

  @override
  String get attSummaryYellow => 'en attente';

  @override
  String get attTcbText =>
      'Le matériel sur lequel tourne le modèle n’a pas encore installé une mise à jour de sécurité du fabricant. Ce n’est pas le signe d’une manipulation, mais cela affaiblit la protection. L’exploitant doit faire la mise à jour. Revérifiez plus tard et n’envoyez rien de confidentiel d’ici là.';

  @override
  String get attTcbTitle =>
      'Mise à jour de sécurité en attente chez l’exploitant';

  @override
  String get attUnconfirmed => 'non confirmé';

  @override
  String attUnconfirmedText(String cause) {
    return '$cause Il n’est pas confirmé que la réponse provienne de l’environnement vérifié. Aucune erreur n’a toutefois été constatée et le fournisseur reste utilisable. Les actions qui attendent la réponse vérifiée ne s’exécutent pas. Revérifiez le fournisseur.';
  }

  @override
  String get checkStatusFailed => 'échoué';

  @override
  String get checkStatusInfo => 'simplement journalisé';

  @override
  String get checkStatusNeutral => 'non confirmé';

  @override
  String get checkStatusOk => 'vérifié';

  @override
  String get checkStatusPending => 'en attente';

  @override
  String get gpuBlockNoEvidenceDetail => 'La demande n’a pas été envoyée.';

  @override
  String gpuBlockNotSent(String v) {
    return 'Non envoyé.$v';
  }

  @override
  String get gpuModeAfter => 'Après';

  @override
  String get gpuModeAfterText =>
      'La vérification a lieu après la réponse. Si elle échoue, une notification vous avertit, la réponse est marquée en rouge et les demandes suivantes vers ce modèle sont vérifiées avant l’envoi. Les modèles sans preuve reçoivent seulement une indication.';

  @override
  String get gpuModeBefore => 'Avant';

  @override
  String get gpuModeBeforeText =>
      'NVIDIA vérifie les preuves GPU avant que votre demande n’atteigne le fournisseur. Si la vérification échoue ou si le fournisseur ne fournit aucune preuve, rien n’est envoyé. Vous pouvez alors envoyer une fois sans vérification du GPU.';

  @override
  String get gpuModeOff => 'Désactivée';

  @override
  String get gpuModeOffText =>
      'Par défaut. Wendelin vérifie uniquement en local que les preuves GPU correspondent à votre demande. Aucun appel à NVIDIA.';

  @override
  String gpuNoEvidenceFinishText(String hint) {
    return '$hint. Le modèle reste utilisable. Ce que Wendelin fait alors dépend de la vérification du GPU ci-dessous : « Désactivée » rien, « Après » seulement une indication, « Avant » n’envoie rien, mais vous pouvez envoyer une fois sans vérification du GPU.';
  }

  @override
  String get gpuNoEvidenceFinishTitle => 'Vérification du GPU impossible';

  @override
  String get gpuNoEvidenceHint =>
      'Vérification du GPU impossible (le fournisseur ne fournit aucune preuve)';

  @override
  String gpuNoEvidenceMessage(String name) {
    return '$name ne fournit aucune preuve GPU pour ce modèle, NVIDIA ne peut donc rien vérifier. Comme la vérification du GPU est réglée sur « Avant », votre demande n’a pas été envoyée. Vous pouvez l’envoyer une fois sans vérification du GPU. Les autres vérifications restent actives.';
  }

  @override
  String get gpuNoEvidenceTitle => 'Pas de preuve GPU';

  @override
  String gpuNotifyFailedText(String name) {
    return 'La vérification du GPU de la dernière réponse de $name a échoué. La demande suivante vérifie avant l’envoi. Détails dans le journal de vérification.';
  }

  @override
  String get gpuNotifyFailedTitle => 'Échec de la vérification du GPU';

  @override
  String get gpuSectionNote =>
      'Pour « Avant » et « Après », Wendelin appelle le service de NVIDIA (nras.attestation.nvidia.com). Seules les preuves du GPU sont envoyées, aucun contenu de vos demandes ou réponses.';

  @override
  String get gpuSectionTitle => 'Vérification du GPU via NVIDIA';

  @override
  String get gpuToolName => 'Vérification du GPU';

  @override
  String shieldSemantics(String label) {
    return 'Vérification TEE : $label';
  }

  @override
  String shieldSemanticsTap(String label) {
    return 'Vérification TEE : $label. Touchez pour le journal de vérification.';
  }

  @override
  String get stageAgeInfo => 'L’âge a seulement été consigné.';

  @override
  String get stageAgePass =>
      'L’attestation est actuelle et ne provient pas d’un ancien enregistrement.';

  @override
  String get stageAgeWhat => 'L’âge de l’attestation.';

  @override
  String get stageBindHpkeInfo => 'La clé a seulement été consignée.';

  @override
  String get stageBindHpkePass =>
      'Seul le serveur vérifié peut lire la demande. La clé provient de l’attestation, pas d’une réponse non vérifiée.';

  @override
  String get stageBindHpkeWhat =>
      'Si la clé avec laquelle Wendelin chiffre votre demande est exactement celle de l’attestation matérielle.';

  @override
  String get stageComposeInfo =>
      'Le hash a été consigné, mais pas comparé à une liste de valeurs de confiance.';

  @override
  String get stageComposePass =>
      'Ce sont exactement les programmes attendus qui s’exécutent dans le service.';

  @override
  String get stageComposeWhat =>
      'Le hash compose : une somme de contrôle de la description des conteneurs, c’est-à-dire des programmes qui s’exécutent dans le service.';

  @override
  String get stageE2eeKeyInfo => 'La clé a seulement été consignée.';

  @override
  String get stageE2eeKeyPass =>
      'Seul l’environnement vérifié peut déchiffrer la demande. Chez certains fournisseurs, le chiffrement se termine dans la passerelle et non dans le modèle lui-même.';

  @override
  String get stageE2eeKeyWhat =>
      'La clé avec laquelle Wendelin chiffre votre demande de bout en bout provient de l’attestation matérielle.';

  @override
  String get stageE2eeRequestInfo =>
      'La demande (ou des parties comme les appels d’outils) n’est pas chiffrée en plus, elle est seulement protégée par la connexion vérifiée.';

  @override
  String get stageE2eeRequestPass =>
      'Votre demande est illisible pour des tiers pendant son trajet.';

  @override
  String get stageE2eeRequestPinned =>
      'La demande (ou des parties comme les appels d’outils) n’est pas chiffrée en plus, elle est seulement protégée par la connexion vérifiée.';

  @override
  String get stageE2eeRequestUnpinned =>
      'La demande (ou des parties comme les appels d’outils) n’est pas chiffrée en plus, et la connexion n’est pas liée à l’attestation. La protection est donc plus faible.';

  @override
  String get stageE2eeRequestWhat =>
      'Si la demande a réellement été envoyée chiffrée.';

  @override
  String get stageE2eeResponseInfo =>
      'Le déchiffrement a seulement été consigné.';

  @override
  String get stageE2eeResponsePass =>
      'La réponse provient sans modification de l’environnement vérifié.';

  @override
  String get stageE2eeResponseWhat =>
      'Si la réponse est arrivée chiffrée et a pu être déchiffrée.';

  @override
  String get stageEventLogInfo =>
      'Le journal d’événements a seulement été consigné.';

  @override
  String get stageEventLogPass =>
      'Le logiciel démarré est traçable sans lacune.';

  @override
  String get stageEventLogWhat =>
      'Le journal d’événements du démarrage : quels logiciels ont été chargés au démarrage. Il doit correspondre à la mesure matérielle.';

  @override
  String get stageFailMeaning =>
      'La vérification a échoué. Cela peut indiquer une manipulation ou un défaut chez le fournisseur. Wendelin n’envoie alors plus rien à ce fournisseur tant que vous ne l’avez pas revérifié.';

  @override
  String get stageGatewayInfo =>
      'L’état de la passerelle a seulement été consigné.';

  @override
  String get stageGatewayPass =>
      'La passerelle fonctionne avec un niveau de sécurité à jour.';

  @override
  String get stageGatewayWhat =>
      'L’état de la passerelle du fournisseur (l’intermédiaire placé devant le modèle).';

  @override
  String get stageGpuInfo =>
      'Le GPU n’a pas été vérifié auprès de NVIDIA car la vérification est désactivée dans les paramètres.';

  @override
  String get stageGpuPass => 'NVIDIA confirme que le GPU est protégé.';

  @override
  String get stageGpuWhat =>
      'L’attestation de la carte graphique (NVIDIA) sur laquelle tourne le modèle. Facultative, activable dans les paramètres.';

  @override
  String get stageInfoDefault =>
      'L’étape est seulement consignée, elle n’est pas vérifiée comme condition.';

  @override
  String get stageKeyBindingInfo =>
      'La somme de contrôle a seulement été consignée.';

  @override
  String get stageKeyBindingPass =>
      'Les clés proviennent de l’environnement vérifié, pas d’un intermédiaire.';

  @override
  String get stageKeyBindingWhat =>
      'La somme de contrôle de l’ensemble de clés (les clés avec lesquelles Wendelin chiffre) doit figurer dans l’attestation matérielle.';

  @override
  String get stageMeasurementInfo => 'La mesure a seulement été consignée.';

  @override
  String get stageMeasurementPass =>
      'Le serveur exécute le code publié, aucun autre.';

  @override
  String get stageMeasurementWhat =>
      'Si la mesure du serveur en cours d’exécution est exactement celle de la dernière version signée.';

  @override
  String get stageNoReceiptInfo =>
      'Tinfoil n’émet pas de reçu par réponse. La réponse n’est liée à votre demande que par le chiffrement ; aucun reçu ne prouve quel modèle l’a produite.';

  @override
  String get stageNoReceiptPass =>
      'Chaque réponse s’accompagne d’un reçu signé.';

  @override
  String get stageNoReceiptWhat =>
      'Si chaque réponse s’accompagne d’un reçu signé qui prouve la demande et la réponse.';

  @override
  String get stageNonceInfo => 'Le nombre a seulement été consigné.';

  @override
  String get stageNoncePass =>
      'L’attestation est récente pour cette demande et n’est pas une ancienne attestation enregistrée.';

  @override
  String get stageNonceWhat =>
      'Un nombre aléatoire que Wendelin envoie et qui doit réapparaître dans l’attestation.';

  @override
  String get stagePassDefault => 'L’étape est réussie.';

  @override
  String get stageProvenanceInfo =>
      'Il n’existe pas de liste de confiance pour ce fournisseur. Wendelin consigne la version mais ne peut pas dire si elle est fiable. Pour examiner le code source, consultez le commit dans le journal de vérification.';

  @override
  String get stageProvenancePass =>
      'Le logiciel provient d’une version connue et vérifiée.';

  @override
  String get stageProvenanceWhat =>
      'La provenance : de quelle version du code source (commit) le logiciel en cours d’exécution a été construit et si elle figure sur la liste de confiance.';

  @override
  String get stageQuoteInfo =>
      'L’attestation a seulement été consignée, pas évaluée.';

  @override
  String get stageQuotePass =>
      'Le service s’exécute bien dans un véritable environnement Intel TDX isolé. L’exploitant ne peut pas lire sa mémoire.';

  @override
  String get stageQuoteWhat =>
      'L’attestation matérielle (quote TDX) de l’environnement protégé. Elle est signée par le processeur et vérifiée avec les certificats d’Intel.';

  @override
  String get stageReceiptBindingInfo => 'La liaison a seulement été consignée.';

  @override
  String get stageReceiptBindingPass => 'Le reçu et la session correspondent.';

  @override
  String get stageReceiptBindingWhat =>
      'Si le reçu appartient à la session vérifiée.';

  @override
  String get stageReceiptCompleteInfo =>
      'Les événements ont seulement été consignés.';

  @override
  String get stageReceiptCompletePass => 'Le reçu est complet.';

  @override
  String get stageReceiptCompleteWhat =>
      'Si le reçu contient tous les événements requis.';

  @override
  String get stageReceiptFetchInfo =>
      'La récupération a seulement été consignée.';

  @override
  String get stageReceiptFetchPass => 'Le fournisseur a fourni le reçu.';

  @override
  String get stageReceiptFetchWhat =>
      'La récupération du reçu signé pour cette réponse.';

  @override
  String get stageReceiptRequestHashInfo =>
      'La somme de contrôle a seulement été consignée.';

  @override
  String get stageReceiptRequestHashPass =>
      'Le fournisseur a reçu exactement votre demande.';

  @override
  String get stageReceiptRequestHashWhat =>
      'La somme de contrôle de la demande dans le reçu, comparée à ce qui a été envoyé.';

  @override
  String get stageReceiptResponseHashInfo =>
      'La somme de contrôle a seulement été consignée.';

  @override
  String get stageReceiptResponseHashPass =>
      'La réponse n’a pas été modifiée pendant son trajet.';

  @override
  String get stageReceiptResponseHashWhat =>
      'La somme de contrôle de la réponse dans le reçu, comparée à ce qui a été reçu.';

  @override
  String get stageReceiptSigInfo => 'La signature a seulement été consignée.';

  @override
  String get stageReceiptSigPass =>
      'Le reçu provient de l’environnement vérifié.';

  @override
  String get stageReceiptSigWhat => 'La signature du reçu.';

  @override
  String get stageReleaseFloorInfo =>
      'La protection contre le retour en arrière a seulement été consignée.';

  @override
  String get stageReleaseFloorPass =>
      'Le serveur exécute la version la plus récente vue jusqu’ici ou une plus récente.';

  @override
  String get stageReleaseFloorWhat =>
      'Si la version n’est pas plus ancienne que la plus récente que Wendelin ait jamais vérifiée (protection contre un retour à d’anciennes versions vulnérables).';

  @override
  String get stageResponseKeyInfo =>
      'L’ensemble de clés a seulement été consigné.';

  @override
  String get stageResponseKeyPass =>
      'La réponse appartient à la session vérifiée.';

  @override
  String get stageResponseKeyWhat =>
      'Si l’ensemble de clés de la réponse correspond à l’ensemble vérifié.';

  @override
  String get stageResultFail => 'échouée';

  @override
  String get stageResultPass => 'réussie';

  @override
  String get stageSignatureInfo =>
      'Ce fournisseur ne fournit pas une telle signature. Les clés sont liées par l’attestation matérielle (somme de contrôle de l’ensemble de clés). C’est une preuve un peu plus faible, mais pas une erreur.';

  @override
  String get stageSignaturePass =>
      'L’ensemble de clés est en plus signé par le fournisseur.';

  @override
  String get stageSignatureWhat =>
      'Une signature supplémentaire de l’ensemble de clés, fournie par certains fournisseurs.';

  @override
  String get stageSigstoreInfo =>
      'La signature de la version a seulement été consignée.';

  @override
  String get stageSigstorePass =>
      'La version provient de la compilation de Tinfoil et figure publiquement dans le journal.';

  @override
  String get stageSigstoreWhat =>
      'Si la version du programme publiée par Tinfoil sur GitHub est réellement signée et inscrite dans le journal de transparence public (Sigstore).';

  @override
  String get stageSnpChainInfo =>
      'La chaîne de certificats a seulement été consignée.';

  @override
  String get stageSnpChainPass =>
      'La chaîne se termine chez AMD, pas sur un certificat glissé par quelqu’un.';

  @override
  String get stageSnpChainWhat =>
      'Si le certificat du processeur remonte, par le certificat intermédiaire AMD, jusqu’à la clé racine AMD intégrée à Wendelin.';

  @override
  String get stageSnpPolicyInfo => 'La politique a seulement été consignée.';

  @override
  String get stageSnpPolicyPass =>
      'L’environnement n’est pas ouvert à l’espionnage et ne contient aucun micrologiciel connu comme obsolète.';

  @override
  String get stageSnpPolicyWhat =>
      'Si l’environnement tourne sans accès de débogage et si le micrologiciel et le microcode du processeur sont au moins aussi récents que Wendelin l’exige (bootloader 9, SNP 22, microcode 80).';

  @override
  String get stageSnpReportInfo =>
      'Le rapport du processeur a seulement été consigné.';

  @override
  String get stageSnpReportPass =>
      'Un véritable processeur AMD garantit le rapport. Personne ne peut le modifier après coup.';

  @override
  String get stageSnpReportWhat =>
      'L’attestation matérielle du serveur Tinfoil : le rapport du processeur AMD, son certificat et la signature qui le couvre.';

  @override
  String get stageTcbInfo => 'Le niveau de sécurité a seulement été consigné.';

  @override
  String get stageTcbPass =>
      'La plateforme dispose de toutes les mises à jour de sécurité connues.';

  @override
  String get stageTcbWhat =>
      'Le niveau de sécurité de la plateforme (TCB) : si le micrologiciel et le microcode sont à jour.';

  @override
  String get stageTlsInfo =>
      'Le certificat de la connexion n’a pas été comparé à l’attestation. La protection repose alors uniquement sur le chiffrement de bout en bout.';

  @override
  String get stageTlsPass =>
      'La connexion se termine dans l’environnement vérifié ; personne ne peut s’intercaler.';

  @override
  String get stageTlsWhat =>
      'Si la connexion réseau mène exactement à la clé qui figure dans l’attestation matérielle (épinglage).';

  @override
  String get stageUnavailableMeaning =>
      'La vérification n’a pas pu être menée à terme (par exemple à cause du réseau). Elle sera répétée plus tard. D’ici là, cette étape n’est pas confirmée.';

  @override
  String get stageUpstreamInfo =>
      'La vérification en amont a seulement été consignée.';

  @override
  String get stageUpstreamPass =>
      'Le modèle derrière la passerelle a lui aussi été vérifié.';

  @override
  String get stageUpstreamTcbInfo => 'Le niveau a seulement été consigné.';

  @override
  String get stageUpstreamTcbPass => 'Cette plateforme est elle aussi à jour.';

  @override
  String get stageUpstreamTcbWhat =>
      'Le niveau de sécurité de la plateforme derrière la passerelle.';

  @override
  String get stageUpstreamWhat =>
      'Si la passerelle confirme que le modèle situé derrière elle s’exécutait dans un environnement vérifié.';

  @override
  String get stageWarnMeaning =>
      'La vérification est réussie, mais avec un avertissement (par exemple une mise à jour de sécurité en attente chez l’exploitant). Cela affaiblit un peu la protection. L’avertissement reste visible dans le journal de vérification.';

  @override
  String get bringApiError => 'Erreur – interface injoignable';

  @override
  String get bringApp => 'Application Bring!';

  @override
  String get bringChecking => 'Vérification …';

  @override
  String get bringConnected => 'Connecté';

  @override
  String get bringEmail => 'E-mail';

  @override
  String get bringFine => 'OK';

  @override
  String get bringInstalled => 'Installée';

  @override
  String get bringIntro =>
      'Interface non officielle : Bring! ne l’a pas ouverte à d’autres applications, elle peut cesser de fonctionner à tout moment. Vous vous connectez une fois ; l’e-mail et le mot de passe ne sont pas enregistrés, seule la session (jetons) reste dans le stockage sécurisé de l’appareil.';

  @override
  String get bringNeedCredentials =>
      'Veuillez saisir l’e-mail et le mot de passe.';

  @override
  String get bringNotInstalled => 'Non installée';

  @override
  String get bringPassword => 'Mot de passe';

  @override
  String get bringReachable => 'Bring! est de nouveau joignable.';

  @override
  String get bringReauthError =>
      'Bring! : connexion expirée. Reconnectez-vous.';

  @override
  String get bringReconnect => 'Se reconnecter';

  @override
  String get bringShareSend => 'Envoyer à Bring!';

  @override
  String get bringShareSent => 'Envoyé à Bring!';

  @override
  String get bringShareUnreachable => 'Bring! injoignable';

  @override
  String get bringSignOutBody => 'La session est supprimée de l’appareil.';

  @override
  String get bringSignOutTitle => 'Se déconnecter de Bring! ?';

  @override
  String get bringSigningIn => 'Connexion …';

  @override
  String get bringStatusAvailable => 'Connecté, intégration désactivée';

  @override
  String get bringStatusSetup => 'Connexion manquante';

  @override
  String get bringStatusUnavailable => 'Indisponible';

  @override
  String get bringStatusUnknown => 'Inconnu';

  @override
  String get bringUnknown => 'Inconnue';

  @override
  String get add => 'Ajouter';

  @override
  String get allow => 'Autoriser';

  @override
  String get appLanguageDetail =>
      'Langue de l’interface, indépendante de la saisie et de la sortie vocales';

  @override
  String get appLanguageIntro =>
      'Choisissez la langue de l’interface. Elle s’applique à toute l’app et à l’overlay. La langue que vous parlez et entendez se règle sous « Voix ».';

  @override
  String get appLanguageSystem => 'Système';

  @override
  String get appLanguageSystemDetail => 'Suit la langue du téléphone';

  @override
  String get appLanguageTitle => 'Langue de l’app';

  @override
  String get appName => 'Wendelin';

  @override
  String get back => 'Retour';

  @override
  String get cancel => 'Annuler';

  @override
  String get close => 'Fermer';

  @override
  String get confirmCardNeedsConfirm => 'Nécessite votre confirmation';

  @override
  String confirmCardToolLevel(String toolName, String level) {
    return '$toolName · niveau $level';
  }

  @override
  String get confirmCardWarning => 'Avertissement';

  @override
  String get confirmed => 'Confirmé';

  @override
  String get copy => 'Copier';

  @override
  String get delete => 'Supprimer';

  @override
  String get deny => 'Refuser';

  @override
  String get details => 'Détails';

  @override
  String get done => 'Terminé';

  @override
  String get edit => 'Modifier';

  @override
  String get error => 'Erreur';

  @override
  String get export => 'Exporter';

  @override
  String get followUpListening => 'J’écoute encore …';

  @override
  String get import => 'Importer';

  @override
  String get later => 'Plus tard';

  @override
  String get momentPlease => 'Un instant …';

  @override
  String get name => 'Nom';

  @override
  String get next => 'Suivant';

  @override
  String get no => 'Non';

  @override
  String get off => 'Désactivé';

  @override
  String get ok => 'OK';

  @override
  String get on => 'Activé';

  @override
  String get open => 'Ouvrir';

  @override
  String get remove => 'Retirer';

  @override
  String get reset => 'Réinitialiser';

  @override
  String get retry => 'Réessayer';

  @override
  String get save => 'Enregistrer';

  @override
  String get search => 'Rechercher';

  @override
  String get selected => 'choisi';

  @override
  String get send => 'Envoyer';

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get share => 'Partager';

  @override
  String get start => 'Démarrer';

  @override
  String get stop => 'Arrêter';

  @override
  String get test => 'Tester';

  @override
  String get understood => 'Compris';

  @override
  String get yes => 'Oui';

  @override
  String get confCallTitle => 'Appeler ?';

  @override
  String get confHintVoiceCall => 'Dis simplement « appeler » ou « annuler »';

  @override
  String get confHintVoiceEdited =>
      'Tu as modifié le texte : envoie-le en touchant l’écran';

  @override
  String get confHintVoiceSms => 'Dis simplement « envoyer » ou « annuler »';

  @override
  String get confNoCancel => 'Annuler';

  @override
  String get confSmsNoText => 'Le message ne doit pas être vide.';

  @override
  String get confSmsTextLabel => 'Message';

  @override
  String get confSmsTitle => 'Envoyer le SMS ?';

  @override
  String confSmsTo(String name) {
    return 'À $name';
  }

  @override
  String get confYesCall => 'Appeler';

  @override
  String get confYesSend => 'Envoyer';

  @override
  String get integrationsContactsRationale =>
      'Wendelin a besoin d’accéder à tes contacts pour trouver les numéros par nom, ainsi qu’aux droits SMS et téléphone. Android te le demandera ensuite. Wendelin n’envoie jamais de SMS et n’appelle jamais sans que tu aies confirmé l’aperçu avec le nom et le numéro (en touchant l’écran ou en disant « oui »). Rien de tout cela ne marche appareil verrouillé. Sans le droit téléphone, Wendelin ouvre seulement le clavier d’appel.';

  @override
  String get batteryAllow => 'Autoriser sans restriction';

  @override
  String get batteryChecklistNote =>
      'Android ne permet pas de lire ces paramètres. Il s’agit d’une liste de contrôle, pas d’un état.';

  @override
  String get batteryHuaweiBody =>
      'Réglez « Lancement des applications » pour Wendelin sur « Gérer manuellement » et autorisez le démarrage automatique, le démarrage secondaire et l’activité en arrière-plan.';

  @override
  String get batteryHuaweiTitle => 'Huawei / Honor';

  @override
  String get batteryOnePlusBody =>
      'Autorisez le démarrage automatique de Wendelin et réglez l’optimisation de la batterie sur « Ne pas optimiser » (Paramètres → Applications → Wendelin → Batterie).';

  @override
  String get batteryOnePlusTitle => 'OnePlus';

  @override
  String get batteryOpenSettings => 'Ouvrir les paramètres de la batterie';

  @override
  String get batteryOptimizedDetail =>
      'Android peut arrêter Wendelin en arrière-plan. Après une longue pause, le bouton d’alimentation risque alors de ne pas ouvrir l’assistant tant que vous n’avez pas ouvert l’application une fois.';

  @override
  String get batteryOptimizedTitle => 'Optimisation de la batterie active';

  @override
  String get batteryReliable => 'Ouvrir de façon fiable';

  @override
  String get batterySamsungBody =>
      'Retirez Wendelin des « Applications en veille » et réglez la batterie de Wendelin sur « Sans restriction » (Paramètres → Batterie → Limites d’utilisation en arrière-plan).';

  @override
  String get batterySamsungTitle => 'Samsung';

  @override
  String get batterySettingsNotOpened =>
      'Impossible d’ouvrir les paramètres système.';

  @override
  String get batteryStandbyDetail =>
      'Android retarde les démarrages en arrière-plan des applications rarement utilisées. Ouvrez Wendelin de temps en temps ou autorisez « Aucune restriction ».';

  @override
  String get batteryStandbyRare =>
      'Veille des applications : rarement utilisée';

  @override
  String get batteryStandbyRestricted => 'Veille des applications : restreinte';

  @override
  String get batteryVendorSettings => 'Ouvrir les paramètres du fabricant';

  @override
  String get batteryXiaomiBody =>
      'Activez « Démarrage automatique » pour Wendelin et réglez l’économiseur de batterie de Wendelin sur « Aucune restriction » (Paramètres → Applications → Autorisations → Démarrage automatique ; Paramètres → Applications → Wendelin → Économiseur de batterie).';

  @override
  String get batteryXiaomiTitle => 'Xiaomi / HyperOS / MIUI';

  @override
  String get devDemoMode => 'Mode démo (sans fournisseur)';

  @override
  String get devDemoModeLabel => 'Mode démo';

  @override
  String get devGallery => 'Galerie de design';

  @override
  String get devSection => 'Développement';

  @override
  String integrationsErrDenied(String service) {
    return '$service : accès refusé ou expiré · en pause';
  }

  @override
  String integrationsErrFailed(String service) {
    return '$service : réponse inattendue · en pause';
  }

  @override
  String integrationsErrUnavailable(String service) {
    return '$service est injoignable · en pause';
  }

  @override
  String get haAddressLabel => 'Adresse';

  @override
  String get haAlwaysConfirm => 'Toujours confirmer';

  @override
  String get haAlwaysConfirmHelp =>
      'Wendelin demande confirmation avant chaque commande (p. ex. cuisinière, four).';

  @override
  String haAlwaysConfirmSemantics(String name, String label) {
    return '$name : $label';
  }

  @override
  String haApproved(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n appareils autorisés',
      one: '1 appareil autorisé',
    );
    return '$_temp0';
  }

  @override
  String get haConnect => 'Connecter';

  @override
  String get haConnected => 'Connecté';

  @override
  String get haConnecting => 'Connexion …';

  @override
  String get haDevices => 'Autoriser des appareils';

  @override
  String get haDevicesHelp =>
      'Wendelin ne connaît que les appareils choisis. Les serrures, alarmes et portails demandent toujours confirmation avant.';

  @override
  String get haDisconnect => 'Déconnecter';

  @override
  String get haDisconnectMessage =>
      'L’adresse, le jeton et la sélection des appareils sont supprimés de l’appareil.';

  @override
  String get haDisconnectTitle => 'Déconnecter Home Assistant ?';

  @override
  String haEntityAlwaysAsks(String entityId) {
    return '$entityId · demande toujours';
  }

  @override
  String get haErrorTitle => 'Erreur – injoignable';

  @override
  String get haFilter => 'Filtrer les appareils';

  @override
  String get haFound => 'Trouvés';

  @override
  String get haHttpNote =>
      'Le http non chiffré n’est autorisé que sur le réseau local, via Tailscale (100.x, *.ts.net) et pour *.local, sinon uniquement https. Rien n’est détecté automatiquement via Tailscale : saisissez l’adresse à la main.';

  @override
  String get haInputMissing => 'Saisissez l’adresse et le jeton.';

  @override
  String get haIntro =>
      'Wendelin pilote vos appareils autorisés via l’interface de votre Home Assistant. Uniquement sur le réseau local ou via Tailscale. L’adresse et le jeton restent dans le stockage sécurisé de l’appareil.';

  @override
  String get haNoDevices => 'Aucun appareil trouvé.';

  @override
  String get haNoRoom => 'Sans pièce';

  @override
  String get haNothingFound =>
      'Rien trouvé. Saisissez l’adresse à la main (nécessaire avec Tailscale).';

  @override
  String get haReachable => 'Home Assistant est joignable.';

  @override
  String get haReload => 'Recharger les appareils';

  @override
  String get haSearch => 'Rechercher sur le Wi-Fi';

  @override
  String get haSearching => 'Recherche …';

  @override
  String get haTitle => 'Home Assistant';

  @override
  String get haTokenHelp =>
      'Dans Home Assistant : Profil → Sécurité → Jetons d’accès de longue durée.';

  @override
  String get haTokenLabel => 'Jeton d’accès de longue durée';

  @override
  String get httpArgsAddArg => '+ Argument';

  @override
  String get httpArgsArgs => 'Arguments';

  @override
  String get httpArgsCustomSchema => 'Schéma JSON personnalisé';

  @override
  String get httpArgsCustomSchemaDetail => 'Au lieu de la liste simple';

  @override
  String get httpArgsCustomSchemaSem => 'Schéma JSON personnalisé';

  @override
  String get httpArgsDescription => 'Description';

  @override
  String get httpArgsRemoveArg => 'Supprimer l’argument';

  @override
  String get httpArgsRequired => 'Obligatoire';

  @override
  String httpArgsRequiredNamed(String name) {
    return '$name obligatoire';
  }

  @override
  String get httpArgsSchema => 'Schéma JSON';

  @override
  String get httpAuthAddSecretHeader => '+ En-tête secret';

  @override
  String get httpAuthKeepStored =>
      'Laisser vide pour conserver la valeur enregistrée';

  @override
  String get httpAuthRemoveSecretHeader => 'Supprimer l’en-tête secret';

  @override
  String get httpAuthSecretHeader => 'En-tête secret, p. ex. X-Api-Key';

  @override
  String httpAuthStored(String redactedSecret) {
    return '$redactedSecret enregistré';
  }

  @override
  String httpEditorDeleteBody(String v) {
    return '« http__$v » et ses secrets enregistrés seront supprimés.';
  }

  @override
  String get httpEditorDeleteTitle => 'Supprimer l’outil HTTP ?';

  @override
  String get httpEditorNewTool => 'Nouvel outil HTTP';

  @override
  String get httpEditorTool => 'Outil HTTP';

  @override
  String httpPhUnknown(String v) {
    return '$v inconnu';
  }

  @override
  String get httpRunAskElse => 'Sinon Wendelin demande avant chaque appel';

  @override
  String get httpRunExecution => 'Exécution';

  @override
  String get httpRunHomeTarget => 'Cible du réseau local';

  @override
  String get httpRunHomeTargetDetail =>
      'Peut pointer vers des adresses privées, alors aussi en http';

  @override
  String get httpRunHomeTargetSem => 'Cible du réseau local';

  @override
  String httpRunLevel(String verb, String name) {
    return 'Niveau (suggestion pour $verb : $name)';
  }

  @override
  String get httpRunNoAsk => 'Exécuter sans demander (pas d’annulation)';

  @override
  String get httpRunNoAskSem => 'Exécuter sans demander';

  @override
  String get httpRunOnlyWrite =>
      'Uniquement pour POST/PUT/PATCH avec le niveau write';

  @override
  String get httpRunSensitiveDetail =>
      'Uniquement vers les fournisseurs au niveau des intégrations sensibles';

  @override
  String get httpRunTimeout => 'Délai en secondes';

  @override
  String get httpSrcAddHeader => '+ En-tête';

  @override
  String httpSrcBodyHelp(String example) {
    return '$example est remplacé selon le type ; vide = pas de corps';
  }

  @override
  String get httpSrcBodyTemplate => 'Modèle de corps (JSON)';

  @override
  String get httpSrcForm => 'Formulaire';

  @override
  String get httpSrcHeader => 'En-tête';

  @override
  String get httpSrcHeaderDetail =>
      'Pas secret ; les jetons vont dans la connexion';

  @override
  String get httpSrcJson => 'JSON';

  @override
  String get httpSrcRemoveHeader => 'Supprimer l’en-tête';

  @override
  String httpSrcUrlHelp(String example) {
    return 'Les espaces réservés comme $example uniquement dans le chemin et la requête, hôte fixe';
  }

  @override
  String get httpSrcUrlTemplate => 'Modèle d’URL';

  @override
  String httpTestArgLabel(String name, String type) {
    return '$name ($type)';
  }

  @override
  String get httpTestFailed => 'échoué';

  @override
  String httpTestHeaderLine(String key, String value) {
    return '$key : $value';
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
  String get httpTestNoResponse => 'Aucune réponse';

  @override
  String get httpTestRunning => 'En cours …';

  @override
  String get httpTestSent => 'Envoyé';

  @override
  String httpTestSentLine(String method, Object url) {
    return '$method $url';
  }

  @override
  String get httpTestSucceeded => 'réussi';

  @override
  String get httpTestTruncated => 'tronqué';

  @override
  String get httpToolSecModelDescription => 'Description pour le modèle';

  @override
  String get httpToolSecModelDescriptionHelp =>
      'Quand et pour quoi le modèle doit utiliser l’outil';

  @override
  String get httpToolsExportNote =>
      'L’export et l’import ne contiennent aucun secret. Après l’import, saisissez à nouveau les jetons et en-têtes secrets ; « Exécuter sans demander » est alors désactivé.';

  @override
  String get httpToolsExportPaste => 'Coller l’export (JSON)';

  @override
  String httpToolsImportFailed(String message) {
    return 'Échec de l’import : $message';
  }

  @override
  String get httpToolsImportTitle => 'Importer des outils HTTP';

  @override
  String httpToolsImported(int length) {
    String _temp0 = intl.Intl.pluralLogic(
      length,
      locale: localeName,
      other:
          '$length outils HTTP importés. Saisissez à nouveau les secrets ; « Exécuter sans demander » est désactivé.',
      one:
          '$length outil HTTP importé. Saisissez à nouveau les secrets ; « Exécuter sans demander » est désactivé.',
    );
    return '$_temp0';
  }

  @override
  String get httpToolsIntro =>
      'Outils personnalisés à partir de la méthode, du modèle d’URL, des en-têtes et de la connexion, p. ex. pour Home Assistant ou n8n. Les réponses sont des données, pas des instructions.';

  @override
  String get httpToolsOffShort => 'désactivé';

  @override
  String get httpToolsRiskRead => 'lit';

  @override
  String get httpToolsRiskWrite => 'modifie sans demander, pas d’annulation';

  @override
  String get httpToolsSensitiveShort => 'sensible';

  @override
  String get comingSoonInProgress => 'En cours';

  @override
  String get comingSoonM3 => 'Prévu pour M3';

  @override
  String get integrationDetailBringAccount => 'Compte Bring!';

  @override
  String get integrationDetailExternalAsks =>
      'Effet externe · demande toujours';

  @override
  String get integrationDetailIntegrationDetailHaSetup =>
      'Adresse, jeton et appareils';

  @override
  String get integrationDetailIntegrationDetailSpotifyAccount =>
      'Compte Spotify';

  @override
  String get integrationDetailLevelAll => 'À tous les fournisseurs';

  @override
  String get integrationDetailLevelEu => 'À partir de l’UE';

  @override
  String get integrationDetailLevelLocal => 'Local uniquement';

  @override
  String get integrationDetailLevelTee => 'À partir de TEE';

  @override
  String get integrationDetailManageLists => 'Gérer les listes';

  @override
  String get integrationDetailMemoryHint =>
      'Voir, modifier, exporter les entrées';

  @override
  String get integrationDetailNoSearch =>
      'Sans service de recherche, Wendelin ne lit que des pages';

  @override
  String get integrationDetailReadsAsks => 'lit · demande toujours';

  @override
  String get integrationDetailReadsNoAsk => 'lit · sans confirmation';

  @override
  String integrationDetailSensitiveLabel(String displayName) {
    return '$displayName sensible';
  }

  @override
  String get integrationDetailSensitiveNote =>
      'Sensible : les outils ne vont qu’aux fournisseurs du niveau défini pour les intégrations sensibles ou au-dessus.';

  @override
  String get integrationDetailSensitiveTitle => 'Intégrations sensibles';

  @override
  String get integrationDetailSetUpSearch =>
      'Configurer le service de recherche';

  @override
  String get integrationDetailTapTool =>
      'Touchez un outil pour activer ou désactiver « Toujours demander ».';

  @override
  String get integrationDetailTitle => 'Intégration';

  @override
  String get integrationDetailVaultDaily => 'Vault et notes quotidiennes';

  @override
  String get integrationDetailViewMemory => 'Voir la mémoire';

  @override
  String get integrationDetailWritesAsks => 'modifie · demande toujours';

  @override
  String get integrationDetailWritesNoUndo =>
      'modifie · sans confirmation, sans annulation';

  @override
  String get integrationDetailWritesUndo =>
      'modifie · sans confirmation, annulation 10 s';

  @override
  String integrationTileActiveDetail(String detail) {
    return 'Actif · $detail';
  }

  @override
  String get integrationTileAvailable => 'Disponible';

  @override
  String get integrationTileInStore => 'Dans le store';

  @override
  String get integrationTileOnlyFrom =>
      'Uniquement vers les fournisseurs à partir de';

  @override
  String get integrationTileSetupNeeded => 'Configuration requise';

  @override
  String get integrationsAddHttp => '+ Outil HTTP';

  @override
  String get integrationsAddMcp => '+ Serveur MCP';

  @override
  String get integrationsAppMissing => 'Application non installée';

  @override
  String get integrationsCalendarRationale =>
      'Wendelin a besoin d’accéder à vos agendas pour lire, créer et modifier des événements. Android vous le demandera juste après. Wendelin demande toujours avant de supprimer.';

  @override
  String get integrationsHintBring =>
      'Application Bring! absente : pas de repli via « Partager »';

  @override
  String get integrationsHintObsidian =>
      'Application Obsidian absente : l’ouverture dans Obsidian est impossible';

  @override
  String get integrationsHintSpotify =>
      'Application Spotify absente : lecture uniquement sur d’autres appareils';

  @override
  String get integrationsIntro =>
      'Seules les intégrations actives vont au modèle. Les intégrations désactivées ne coûtent aucun jeton.';

  @override
  String get integrationsOwn => 'Intégrations personnelles';

  @override
  String get integrationsPaused => 'en pause';

  @override
  String integrationsPausedError(String service) {
    return '$service : accès refusé ou réponse inattendue · en pause';
  }

  @override
  String get integrationsPermission => 'Autorisation';

  @override
  String get integrationsPermission2 => 'Autorisation';

  @override
  String integrationsReachable(String displayName) {
    return '$displayName est de nouveau joignable.';
  }

  @override
  String integrationsRejected(String reason) {
    return 'Refusée : $reason';
  }

  @override
  String integrationsTools(int tools) {
    return '$tools outils';
  }

  @override
  String get reconnectBringShare =>
      'Solution : envoyer les articles à l\'appli Bring! via Partager.';

  @override
  String reconnectErrDenied(String service) {
    return '$service : accès refusé ou non configuré. Vérifiez les identifiants.';
  }

  @override
  String reconnectErrFailed(String service) {
    return '$service : la connexion a échoué (réponse inattendue).';
  }

  @override
  String reconnectErrOther(String service) {
    return '$service : la connexion a échoué.';
  }

  @override
  String reconnectErrUnavailable(String service) {
    return '$service est injoignable ou ne répond pas. Réessayez plus tard.';
  }

  @override
  String get listsAccessLost =>
      'Plus d’accès – choisissez à nouveau le fichier';

  @override
  String get listsAdd => '+ Liste';

  @override
  String get listsAliases =>
      'Autres noms, séparés par des virgules (facultatif)';

  @override
  String listsAlso(String v) {
    return 'aussi : $v';
  }

  @override
  String get listsChooseFile => 'Choisir un fichier';

  @override
  String get listsDeleteBody =>
      'La liste disparaît de Wendelin. Le fichier est conservé.';

  @override
  String get listsDeleteList => 'Supprimer la liste';

  @override
  String listsDeleteTitle(String name) {
    return 'Supprimer « $name » ?';
  }

  @override
  String get listsEditList => 'Modifier la liste';

  @override
  String get listsFile => 'Fichier';

  @override
  String get listsIntro =>
      'Chaque liste est un fichier Markdown sur l’appareil (p. ex. dans le vault Obsidian). Les entrées y figurent sous la forme « - [ ] … ».';

  @override
  String get listsListFallback => 'Liste';

  @override
  String get listsNameHint => 'Nom, p. ex. Courses';

  @override
  String get listsNeedNameFile => 'Le nom et le fichier sont obligatoires.';

  @override
  String get listsNewFile => 'Nouveau fichier';

  @override
  String get listsNewList => 'Nouvelle liste';

  @override
  String get listsNoAliases => 'Sans alias';

  @override
  String get listsNoFile => 'Pas encore de fichier';

  @override
  String listsSection(String section) {
    return 'Section « $section »';
  }

  @override
  String get listsSectionLabel =>
      'Section dans le fichier, p. ex. Todo (facultatif)';

  @override
  String get listsTaskDefault => 'Liste de tâches par défaut';

  @override
  String get listsTaskDefaultDetail =>
      'Les tâches avec échéance arrivent ici si aucune liste n’est indiquée.';

  @override
  String get integrationsLocationRationale =>
      'Pour vous dire où vous êtes et préparer distances et navigation, Wendelin a besoin de l’accès à la position. Android vous le demande ensuite. Wendelin ne lit la position que si vous le demandez (jamais en arrière-plan), ne l’envoie pas à des modèles cloud en dessous de votre niveau de confidentialité et ne l’écrit pas dans le journal d’audit. « Approximative » suffit pour les noms de lieux et la distance à vol d’oiseau.';

  @override
  String confHandOverDetail(String toName, String fromName) {
    return '$toName a un niveau de confidentialité plus bas que $fromName. Votre demande et l’historique de la conversation y seront alors transmis.';
  }

  @override
  String confHandOverTitle(String toName) {
    return 'Transmettre à $toName ?';
  }

  @override
  String get confHintTap => 'Répondez d’un toucher';

  @override
  String get confHintVoice => 'Dites simplement « oui » ou « non »';

  @override
  String confMoreLines(int rest) {
    return '… $rest lignes de plus';
  }

  @override
  String get confYesHandOver => 'Oui, transmettre';

  @override
  String get mainCancelListening => 'Arrêter l’écoute';

  @override
  String get mainCheckProvider => 'Vérifier le fournisseur';

  @override
  String mainCostLabel(String costLabel) {
    return 'Coût $costLabel';
  }

  @override
  String mainCostToday(String v) {
    return 'aujourd’hui $v';
  }

  @override
  String get mainDeleteEventTitle => 'Supprimer l’événement ?';

  @override
  String mainFollowUpCountdown(String followUpListeningText, int seconds) {
    return '$followUpListeningText $seconds s';
  }

  @override
  String mainGpuBlockMessage(String name, String v) {
    return 'La vérification du GPU de $name via NVIDIA a échoué ou n’est pas possible.$v Votre demande n’a pas été envoyée. Vous pouvez l’envoyer une fois sans vérification du GPU. Les autres vérifications restent actives.';
  }

  @override
  String get mainGpuCheckFailedTitle => 'Échec de la vérification du GPU';

  @override
  String get mainListening => 'J’écoute …';

  @override
  String get mainMicCancelAnswer => 'Annuler la réponse';

  @override
  String get mainMicSpeak => 'Parler';

  @override
  String get mainMicStopListening => 'Arrêter l’écoute';

  @override
  String get mainMicStopSpeech => 'Arrêter la lecture vocale';

  @override
  String get mainMicUnavailable => 'Microphone indisponible';

  @override
  String get mainNeedsModel =>
      'Wendelin a besoin d’un modèle de langage. Configurez un fournisseur avec votre clé API, puis vous pourrez commencer.';

  @override
  String get mainNewConversation => 'Nouvelle conversation';

  @override
  String get mainNoKeep => 'Non, garder';

  @override
  String get mainNoProviderYet => 'Aucun fournisseur configuré';

  @override
  String mainProviderProfileUnusable(String error) {
    return 'Le profil du fournisseur est inutilisable : $error';
  }

  @override
  String get mainReallyDeleteTitle => 'Vraiment supprimer ?';

  @override
  String get mainSendWithoutGpuCheck => 'Envoyer sans vérification du GPU';

  @override
  String get mainSetUpProvider => 'Configurer un fournisseur';

  @override
  String get mainShouldIDoThat => 'Dois-je le faire ?';

  @override
  String get mainStartDemo => 'Lancer la démo sans fournisseur';

  @override
  String get mainToday => 'Aujourd’hui';

  @override
  String get mainTypeInstead => 'Écrire au lieu de parler';

  @override
  String get mainViewRouting => 'Voir le routage';

  @override
  String get mainYesDelete => 'Oui, supprimer';

  @override
  String get mainYesDoIt => 'Oui, exécuter';

  @override
  String get mainYesterday => 'Hier';

  @override
  String get overlayCloseAssistant => 'Fermer l’assistant';

  @override
  String get overlayEnd => 'Terminer';

  @override
  String get overlayFollowUpComing =>
      'Mode conversation désactivé · activable dans les paramètres';

  @override
  String overlayFollowUpWindow(int seconds) {
    return 'À l’écoute encore $seconds s · « Stop » termine';
  }

  @override
  String get overlayKeepTalking => 'Continuer à parler';

  @override
  String get overlayLockedText =>
      'Sur l’écran de verrouillage, Wendelin n’affiche ni ne dit rien de vos données. Seule la lampe de poche fonctionne aussi verrouillé. Tout le reste seulement après le déverrouillage.';

  @override
  String get overlayLockedTitle => 'Déverrouiller l’appareil';

  @override
  String get overlayTextInput => 'Saisie de texte';

  @override
  String get overlayUnlock => 'Déverrouiller';

  @override
  String privateBannerConfidential(String since) {
    return 'Confidentiel : mémoire utilisée (depuis $since)';
  }

  @override
  String privateBannerPrivate(String since) {
    return 'Conversation privée (depuis $since)';
  }

  @override
  String privateEscalationMemory(String since, String toName) {
    return 'La conversation utilise votre mémoire (depuis $since). Avec « Oui », $toName voit l’historique jusqu’ici, mais pas la mémoire elle-même.';
  }

  @override
  String privateEscalationPrivate(String since, String toName) {
    return 'La conversation est privée (depuis $since). Avec « Oui », $toName voit aussi ses parties privées.';
  }

  @override
  String get switchTopicBody =>
      'Changer de modèle démarre une nouvelle conversation. L’historique actuel est terminé (il reste consultable dans l’historique).';

  @override
  String get switchTopicBodyRunning =>
      'Changer de modèle démarre une nouvelle conversation. La réponse en cours est interrompue et l’historique actuel est terminé (il reste consultable dans l’historique).';

  @override
  String get switchTopicSwitch => 'Changer';

  @override
  String get switchTopicTitle => 'Commencer une nouvelle conversation ?';

  @override
  String get mcpAddClientId => 'ID client (facultatif)';

  @override
  String get mcpAddClientIdHint =>
      'Laisser vide : Wendelin s’enregistre lui-même auprès du serveur';

  @override
  String get mcpAddConfirmAll => 'Confirmer tous les outils';

  @override
  String get mcpAddConfirmAllHint => 'Chaque appel demande confirmation';

  @override
  String get mcpAddCustom => 'Serveur personnalisé';

  @override
  String get mcpAddHeaderLabel => 'En-tête, p. ex. X-Api-Key';

  @override
  String get mcpAddProblem => 'Problème';

  @override
  String get mcpAddSensitive => 'Sensible';

  @override
  String get mcpAddSensitiveHint =>
      'Outils seulement pour les fournisseurs au niveau défini ou au-dessus';

  @override
  String get mcpAddServerAddress => 'Adresse';

  @override
  String get mcpAddServerInsecure =>
      'Non chiffré (http) : autorisé uniquement dans le réseau domestique ou via Tailscale';

  @override
  String get mcpAddServerIntro =>
      'Choisissez un modèle ou saisissez votre propre serveur. Joignable via https ou dans le réseau domestique (Tailscale, WireGuard).';

  @override
  String get mcpAddServerTestConnection => 'Tester la connexion';

  @override
  String get mcpAddServerTitle => 'Ajouter un serveur';

  @override
  String get mcpAddSignIn => 'Connexion';

  @override
  String get mcpAddTokenHint => 'Ne sera plus jamais affiché';

  @override
  String get mcpAddValue => 'Valeur';

  @override
  String get mcpAddValueHint => 'Ne sera plus jamais affiché';

  @override
  String get mcpCheckHeaderMissing => 'Veuillez indiquer le nom de l’en-tête.';

  @override
  String get mcpCheckNameMissing => 'Veuillez indiquer un nom.';

  @override
  String get mcpCheckPlaceholders =>
      'Veuillez remplacer les espaces réservés entre <…> dans l’adresse.';

  @override
  String get mcpCheckUrlIncomplete =>
      'Veuillez indiquer une adresse complète (https://…).';

  @override
  String get mcpDetailActive => 'Serveur actif';

  @override
  String mcpDetailActiveLabel(String name) {
    return '$name actif';
  }

  @override
  String get mcpDetailAuthLabel => 'Connexion requise';

  @override
  String get mcpDetailBearer => 'Jeton Bearer';

  @override
  String mcpDetailCheck(String v) {
    return 'Vérification : $v';
  }

  @override
  String mcpDetailCheck2(String v) {
    return 'Vérification : $v';
  }

  @override
  String get mcpDetailConfirmAll => 'Confirmer tous les outils';

  @override
  String get mcpDetailConfirmAllHint =>
      'Chaque appel demande confirmation, quoi que déclare le serveur';

  @override
  String get mcpDetailDelete => 'Supprimer le serveur';

  @override
  String get mcpDetailDeleteBody =>
      'La configuration, la liste d’outils et tous les identifiants de ce serveur seront supprimés.';

  @override
  String get mcpDetailDeleteHint =>
      'Supprimez la configuration, la liste d’outils et les identifiants';

  @override
  String mcpDetailDeleteTitle(String name) {
    return 'Supprimer « $name » ?';
  }

  @override
  String mcpDetailIntro(String url) {
    return 'Les arguments des outils sont envoyés à ce serveur : $url';
  }

  @override
  String get mcpDetailIntroHint =>
      'Touchez un outil pour la confirmation et le niveau de risque. Les outils MCP n’ont pas d’annulation : les modifications ont lieu sur le serveur.';

  @override
  String mcpDetailLastCheck(String v) {
    return 'Dernière vérification : $v';
  }

  @override
  String get mcpDetailNeverShown => 'Ne sera plus jamais affiché';

  @override
  String get mcpDetailNoTools => 'Aucun outil pour l’instant';

  @override
  String get mcpDetailNoToolsHint => 'Activez le serveur ou rechargez';

  @override
  String get mcpDetailOauthHint => 'Connexion OAuth dans le navigateur';

  @override
  String mcpDetailReplaceHeader(String header) {
    return 'Remplacer l’en-tête $header';
  }

  @override
  String get mcpDetailReplaceToken => 'Remplacer le jeton';

  @override
  String get mcpDetailSensitive => 'Sensible';

  @override
  String get mcpDetailSensitiveHint =>
      'Données personnelles : outils seulement pour les fournisseurs au niveau défini ou au-dessus';

  @override
  String mcpDetailSensitiveLabel(String name) {
    return '$name sensible';
  }

  @override
  String get mcpDetailSignIn => 'Se connecter';

  @override
  String get mcpDetailSignInAgain => 'Se reconnecter';

  @override
  String get mcpDetailSignOut => 'Se déconnecter';

  @override
  String get mcpDetailSignOutHint => 'Oubliez les jetons sur cet appareil';

  @override
  String get mcpDetailTools => 'Outils';

  @override
  String get mcpDetailUnreachableLabel => 'injoignable';

  @override
  String mcpDetailValueFor(String header) {
    return 'Valeur pour $header';
  }

  @override
  String get mcpDetailValueNeverShown =>
      'La valeur ne sera plus jamais affichée';

  @override
  String get mcpLabelsAlwaysAsks => 'demande toujours';

  @override
  String get mcpLabelsAsksNoUndo => 'demande · sans annulation';

  @override
  String get mcpLabelsAuthAfterSave =>
      'Connexion requise – connectez-vous après l’enregistrement';

  @override
  String get mcpLabelsAuthCheck =>
      'Connexion requise – vérifiez le jeton ou l’en-tête';

  @override
  String get mcpLabelsAuthRequired => 'Connexion requise';

  @override
  String get mcpLabelsChanges => 'modifie';

  @override
  String get mcpLabelsCredentialsMissing => 'Identifiants manquants';

  @override
  String get mcpLabelsExternal => 'Effet externe';

  @override
  String get mcpLabelsHintDestructive =>
      'Serveur : destructif (destructiveHint)';

  @override
  String get mcpLabelsHintNonDestructive =>
      'Serveur : modifie, non destructif (destructiveHint: false)';

  @override
  String get mcpLabelsHintNone =>
      'Serveur : aucune indication – traité comme effet externe';

  @override
  String get mcpLabelsHintReadOnly => 'Serveur : lecture seule (readOnlyHint)';

  @override
  String get mcpLabelsNetworkHint => 'Tailscale/WireGuard est-il actif ?';

  @override
  String get mcpLabelsNoAsk => 'sans confirmation';

  @override
  String get mcpLabelsNoAskNoUndo => 'sans confirmation · sans annulation';

  @override
  String get mcpLabelsNotChecked => 'Pas encore vérifié';

  @override
  String get mcpLabelsOneTool => '1 outil';

  @override
  String get mcpLabelsProtocolError => 'serveur MCP non valide';

  @override
  String mcpLabelsProtocolErrorDetail(String v) {
    return 'Serveur MCP non valide : $v';
  }

  @override
  String get mcpLabelsProtocolErrorShort => 'Serveur MCP non valide';

  @override
  String get mcpLabelsReachable => 'Joignable';

  @override
  String get mcpLabelsReads => 'lit';

  @override
  String get mcpLabelsReload => 'Recharger';

  @override
  String get mcpLabelsReplaceToken => 'Remplacer le jeton';

  @override
  String get mcpLabelsSetUp => 'Configurer';

  @override
  String get mcpLabelsSignIn => 'Se connecter';

  @override
  String get mcpLabelsSignInAgain => 'Se reconnecter';

  @override
  String get mcpLabelsSignInMissing => 'Connexion manquante';

  @override
  String mcpLabelsTools(int tools) {
    return '$tools outils';
  }

  @override
  String get mcpLabelsUnreachable => 'injoignable';

  @override
  String mcpLabelsUnreachableDetail(String v, String mcpUnreachableHint) {
    return 'Injoignable : $v. $mcpUnreachableHint';
  }

  @override
  String mcpLabelsUnreachableShort(String mcpUnreachableHint) {
    return 'Injoignable · $mcpUnreachableHint';
  }

  @override
  String mcpSecretCheck(String v) {
    return 'Vérification : $v';
  }

  @override
  String get mcpSecretSaved => 'Enregistré';

  @override
  String mcpSecretSignInFailed(String message) {
    return 'Échec de la connexion : $message';
  }

  @override
  String mcpSecretSignInOnServer(String name) {
    return '« $name » : connectez-vous côté serveur';
  }

  @override
  String get mcpSecretSignedIn => 'Connecté';

  @override
  String get mcpServersAdd => '+ Serveur';

  @override
  String get mcpServersContent => 'Contenu du fichier d’export';

  @override
  String get mcpServersExportHint =>
      'Liste de serveurs sans jetons ni mots de passe';

  @override
  String get mcpServersImportHint => 'Les identifiants seront redemandés';

  @override
  String get mcpServersImportTitle => 'Importer la liste de serveurs';

  @override
  String mcpServersImported(int length) {
    return '$length serveurs importés (désactivés)';
  }

  @override
  String get mcpServersImportedOne => '1 serveur importé (désactivé)';

  @override
  String get mcpServersIntro =>
      'Outils de serveurs MCP, p. ex. sur le serveur domestique via Tailscale. Les arguments des outils sont envoyés au serveur concerné.';

  @override
  String get mcpServersNone => 'Aucun serveur pour l’instant';

  @override
  String get mcpServersNoneHint =>
      'Choisissez un modèle ou saisissez votre propre adresse';

  @override
  String get mcpToolAlwaysAsk => 'Toujours demander';

  @override
  String get mcpToolAlwaysAsk2 => 'Toujours demander';

  @override
  String get mcpToolAlwaysAskHint => 'chaque appel est confirmé';

  @override
  String get mcpToolConfirmAllOn =>
      '« Confirmer tous les outils » est activé : chaque appel demande confirmation.';

  @override
  String get mcpToolDefaultNoUndo => 'Par défaut : annulation impossible';

  @override
  String mcpToolEffective(String v) {
    return 'Effectif : $v';
  }

  @override
  String get mcpToolExternalAsks =>
      'Effet externe : demande toujours, cela ne peut pas être assoupli.';

  @override
  String get mcpToolNoAsk => 'Sans confirmation';

  @override
  String get mcpToolNoAsk2 => 'Sans confirmation';

  @override
  String get mcpToolNoUndoNow =>
      'Pas d’annulation : la modification a lieu immédiatement sur le serveur';

  @override
  String get mcpToolReadsOnly => 'lecture seule';

  @override
  String mcpToolServerChecked(String v) {
    return 'Vérifié uniquement par le serveur : $v';
  }

  @override
  String toolChipSemantics(String toolName, String status) {
    return 'Outil $toolName, $status';
  }

  @override
  String toolResultUndoCountdown(int seconds) {
    return 'Annuler · $seconds s';
  }

  @override
  String toolResultUndoSemantics(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds secondes',
      one: '$seconds seconde',
    );
    return 'Annuler, encore $_temp0';
  }

  @override
  String get toolResultUndone => 'Annulé';

  @override
  String get toolTlsEncrypted => 'Outils chiffrés de bout en bout';

  @override
  String get toolTlsHint =>
      'Les appels d’outils sont protégés par la connexion vérifiée jusqu’à l’enclave, mais pas chiffrés en plus.';

  @override
  String get integrationsMediaRationale =>
      'Pour vous dire ce qui est en cours de lecture et avancer ou reculer dans un livre audio ou un podcast, Wendelin a besoin de « l’accès aux notifications ». Android ouvre ensuite cette page : choisissez Wendelin dans la liste et activez-le (sur les versions récentes d’Android, choisissez d’abord « Autoriser les paramètres restreints » dans les infos de l’appli). Wendelin ne lit pas les notifications, seulement la lecture multimédia. Pause, reprise et retour fonctionnent aussi sans.';

  @override
  String get obsIndexBuilding => 'Création de l’index …';

  @override
  String obsIndexBuildingProgress(int indexed, int pending) {
    return 'Création de l’index : $indexed notes, encore $pending';
  }

  @override
  String obsIndexCurrent(String notes) {
    return '$notes dans l’index · à jour';
  }

  @override
  String obsIndexIncomplete(String error) {
    return 'Index incomplet : $error';
  }

  @override
  String get obsIndexNotBuilt => 'Pas encore créé';

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
    return '$notes dans l’index · coffre trop grand, seulement en partie';
  }

  @override
  String obsIndexUnreadable(String notes, int failed) {
    return '$notes dans l’index · $failed illisibles';
  }

  @override
  String get obsidianAccessGranted => 'Accès accordé';

  @override
  String get obsidianAccessGranted2 => 'Accès accordé';

  @override
  String get obsidianAccessLost =>
      'Plus d’accès – choisissez à nouveau le dossier';

  @override
  String get obsidianBuildIndex => 'Construire l’index';

  @override
  String get obsidianChooseFolder =>
      'Choisissez le dossier de votre vault Obsidian';

  @override
  String get obsidianChooseOther => 'Choisir un autre dossier';

  @override
  String get obsidianChooseVaultFolder => 'Choisir le dossier du vault';

  @override
  String get obsidianDailyNotes => 'Notes quotidiennes';

  @override
  String get obsidianDailySaved => 'Notes quotidiennes enregistrées.';

  @override
  String get obsidianDateFormat => 'Format de date comme dans Obsidian';

  @override
  String get obsidianFolder => 'Dossier';

  @override
  String get obsidianFolderHint =>
      'Laisser vide = racine du vault. Les nouvelles notes quotidiennes vont dans ce dossier.';

  @override
  String get obsidianIndexBuilding => 'L’index est en cours de construction';

  @override
  String get obsidianIndexHint =>
      'Mis à jour automatiquement (au démarrage et avant chaque recherche). Le bouton n’est nécessaire que pour la première construction.';

  @override
  String get obsidianIntro =>
      'Wendelin lit et complète les notes directement dans le dossier du vault. La synchronisation reste assurée par Obsidian Sync, Syncthing ou Git.';

  @override
  String get obsidianNoAccess => 'pas d’accès';

  @override
  String get obsidianNoVault => 'Aucun vault choisi';

  @override
  String get obsidianRemoveBody =>
      'Wendelin perd l’accès au dossier. Les notes elles-mêmes restent inchangées.';

  @override
  String get obsidianRemoveTitle => 'Retirer le vault ?';

  @override
  String get obsidianRemoveVault => 'Retirer le vault';

  @override
  String get obsidianSaveDaily => 'Enregistrer les notes quotidiennes';

  @override
  String get obsidianSearchIndex => 'Index de recherche';

  @override
  String get obsidianTemplate => 'Modèle (facultatif)';

  @override
  String get obsidianTemplateHint => 'Modèles/Note quotidienne';

  @override
  String obsidianToday(String path) {
    return 'Aujourd’hui : $path';
  }

  @override
  String obsidianUnusable(String message) {
    return 'Inutilisable : $message';
  }

  @override
  String obsidianUnusable2(String message) {
    return 'Inutilisable : $message';
  }

  @override
  String get obsidianVault => 'Vault';

  @override
  String get onboardingConversation => 'Conversation';

  @override
  String get onboardingConversationIntro =>
      'Wendelin doit-il continuer à écouter brièvement après ses réponses, pour que vous puissiez poser une question sans toucher l’écran ? Vous pouvez modifier ce réglage à tout moment sous Paramètres → Voix.';

  @override
  String get onboardingDemoNoProvider => 'Démo sans fournisseur';

  @override
  String get onboardingInterfaceLanguage =>
      'Langue de l’interface de l’application';

  @override
  String get onboardingKeepListening => 'Oui, continuer à écouter';

  @override
  String get onboardingLanguageModel => 'Modèle de langage';

  @override
  String get onboardingLearnAndEnable => 'Entraîner et activer';

  @override
  String get onboardingPermissionsIntro =>
      'N’activez que ce dont vous avez besoin. Android ne demande les autorisations qu’au moment où vous les activez.';

  @override
  String get onboardingProviderIntro =>
      'Wendelin a besoin d’un fournisseur, par exemple Claude avec votre clé d’API ou votre propre modèle sur un serveur personnel.';

  @override
  String get onboardingSetUpAnotherProvider =>
      'Configurer un autre fournisseur';

  @override
  String get onboardingSkip => 'Passer';

  @override
  String get onboardingTapOnly => 'Non, seulement après un appui';

  @override
  String get onboardingWakeIntro =>
      'Wendelin peut écouter « Wendelin » même quand le téléphone est posé. Pour cela, il apprend d’abord votre voix (environ 3 minutes). Vous pouvez aussi le faire plus tard dans les paramètres.';

  @override
  String get onboardingWakeWord => 'Mot d’activation';

  @override
  String get onboardingWelcome => 'Bienvenue';

  @override
  String get onboardingWelcomeIntro =>
      'Wendelin est votre assistant vocal. La configuration se fait en six étapes. Quelle langue parlez-vous avec lui ?';

  @override
  String get onboardingWhatMayWendelinDo => 'Que peut faire Wendelin ?';

  @override
  String get auditEntrySession => 'Session';

  @override
  String get auditEntryVerifications => 'Vérifications de cette session';

  @override
  String get auditLogIntro =>
      'Ce que Wendelin a fait. Jamais de clés. L’export ne contient pas de textes, seulement des heures, des types et des résultats.';

  @override
  String get auditLogTitle => 'Journal d’audit';

  @override
  String get memoryCatFact => 'Fait';

  @override
  String get memoryCatPerson => 'Personne';

  @override
  String get memoryCatPreference => 'Préférence';

  @override
  String get memoryCatProject => 'Projet';

  @override
  String memoryDeleteTooltip(String text) {
    return 'Supprimer : $text';
  }

  @override
  String get memoryEditTitle => 'Modifier l’entrée';

  @override
  String get memoryExportMd => 'Exporter en Markdown';

  @override
  String get memoryForget => 'Oublier';

  @override
  String get memoryForgetTitle => 'Oublier l’entrée ?';

  @override
  String memoryFromPrivate(String label) {
    return 'Issu d’une demande privée : n’est transmis qu’aux fournisseurs à partir de $label.';
  }

  @override
  String get memoryIntro =>
      'Wendelin ne retient que ce que vous demandez expressément. Les mots de passe, codes PIN, numéros de carte et de compte ne sont jamais enregistrés.';

  @override
  String get memoryLift => 'Lever';

  @override
  String memoryLiftBody(String text, String level) {
    return '« $text » provient d’une demande privée et n’est transmis jusqu’ici qu’aux fournisseurs à partir de $level. Ensuite, tous les fournisseurs autorisés à voir la mémoire pourront le voir.';
  }

  @override
  String get memoryLiftLimit => 'Lever la limite inférieure';

  @override
  String get memoryLiftTitle => 'Lever la limite inférieure ?';

  @override
  String get memoryNone => 'Aucune entrée pour l’instant.';

  @override
  String memoryPrivateFrom(String v, String label) {
    return '$v · privé, seulement à partir de $label';
  }

  @override
  String get memoryTitle => 'Mémoire';

  @override
  String get privacyLevelEu => 'UE';

  @override
  String get privacyLevelLocal => 'local';

  @override
  String privacyLevelSemantics(String text, String level) {
    return '$text, niveau de confidentialité $level';
  }

  @override
  String get privacyLevelStandard => 'Standard';

  @override
  String get privacyLevelTee => 'TEE';

  @override
  String privacyScreenDays(int d) {
    return '$d jours';
  }

  @override
  String get privacyScreenDeleteAll => 'Tout supprimer';

  @override
  String get privacyScreenDeleteAllBody =>
      'Tous les historiques de conversation, le journal de vérification et les voix entraînées (mot d’activation) seront supprimés. Cette action est irréversible. La mémoire et les paramètres sont conservés.';

  @override
  String get privacyScreenDeleteAllTitle => 'Tout supprimer ?';

  @override
  String get privacyScreenDeleteHistory =>
      'Supprimer les historiques et le journal';

  @override
  String privacyScreenEntries(int n) {
    return '$n entrées';
  }

  @override
  String get privacyScreenGeneralLog => 'Journal de vérification général';

  @override
  String get privacyScreenIntro =>
      'Les historiques et le journal de vérification restent sur l’appareil. Wendelin supprime automatiquement les entrées plus anciennes.';

  @override
  String get privacyScreenKindConfirmation => 'Confirmation';

  @override
  String get privacyScreenKindEscalation => 'Escalade';

  @override
  String get privacyScreenKindRequest => 'Demande';

  @override
  String get privacyScreenKindTool => 'Outil';

  @override
  String get privacyScreenKindVerification => 'Vérification';

  @override
  String get privacyScreenManyEntries => '200+ entrées';

  @override
  String get privacyScreenOneEntry => '1 entrée';

  @override
  String get privacyScreenOneYear => '1 an';

  @override
  String get privacyScreenProtectScreen => 'Protéger le contenu de l’écran';

  @override
  String get privacyScreenProtectScreenHint =>
      'Pas de captures d’écran, masqué dans le sélecteur d’applications. L’overlay de l’assistant est toujours protégé.';

  @override
  String get privacyScreenRetention => 'Conservation';

  @override
  String get privacyScreenTeeLog => 'Journal de vérification TEE';

  @override
  String get privacyScreenTeeLogHint =>
      'Vérification des fournisseurs avec environnement protégé, vérification du GPU via NVIDIA';

  @override
  String privacyScreenUndone(String v, String v2) {
    return '$v · annulé · $v2';
  }

  @override
  String get areaAssistant => 'Assistant';

  @override
  String get areaAssistantDetail =>
      'Assistant par défaut, votre nom, personnalité';

  @override
  String get areaCosts => 'Coûts';

  @override
  String get areaCostsDetail => 'Aujourd’hui et ce mois, par fournisseur';

  @override
  String get areaHttpTools => 'Outils HTTP';

  @override
  String get areaHttpToolsDetail => 'Définir et tester vos propres outils';

  @override
  String get areaIntegrations => 'Intégrations';

  @override
  String get areaIntegrationsDetail =>
      'Ce que Wendelin peut faire, outils, niveaux de risque';

  @override
  String get areaMcp => 'Serveurs MCP';

  @override
  String get areaMcpDetail => 'Serveurs, connexion, état, outils';

  @override
  String get areaPrivacy => 'Confidentialité et journaux';

  @override
  String get areaPrivacyDetail => 'Conservation, journal d’audit, export';

  @override
  String get areaProvider => 'Fournisseurs';

  @override
  String get areaProviderDetail => 'Profils, par défaut, budget';

  @override
  String get areaRouting => 'Routage';

  @override
  String get areaRoutingDetail => 'Règles, zone de test, import et export';

  @override
  String get areaSpeech => 'Voix';

  @override
  String get areaSpeechDetail => 'Reconnaissance vocale, voix, débit';

  @override
  String get costsIntro =>
      'D’après les prix du catalogue de modèles, en dollars américains.';

  @override
  String costsMonth(String v) {
    return 'mois $v';
  }

  @override
  String get costsNoProviders => 'Aucun fournisseur pour l’instant.';

  @override
  String costsOfBudget(String v) {
    return 'sur $v';
  }

  @override
  String costsToday(String v) {
    return 'aujourd’hui $v';
  }

  @override
  String providerChipLevel(String level) {
    return 'Niveau de confidentialité $level';
  }

  @override
  String providerChipReceipt(String status) {
    return 'Reçu $status';
  }

  @override
  String providerChipSemantics(String name) {
    return 'Fournisseur $name';
  }

  @override
  String get providerSetupBudgetFormat =>
      'Budget : montant en dollars, p. ex. 5 ou 2,50';

  @override
  String get providerSetupConnected => 'Connexion établie';

  @override
  String get providerSetupConnectedEnterModel =>
      'Connexion établie. Veuillez saisir l’ID du modèle.';

  @override
  String providerSetupConnectedModels(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Connexion établie, $n modèles trouvés.',
      one: 'Connexion établie, 1 modèle trouvé.',
    );
    return '$_temp0';
  }

  @override
  String get providerSetupConnectionFailed => 'Échec de la connexion';

  @override
  String get providerSetupEditTitle => 'Modifier le fournisseur';

  @override
  String get providerSetupIntroCredentials =>
      'La clé n’est stockée que dans le stockage sécurisé de l’appareil.';

  @override
  String get providerSetupIntroFinish =>
      'Niveau de confidentialité et, en option, un budget mensuel.';

  @override
  String get providerSetupIntroModel => 'Choisissez le modèle par défaut.';

  @override
  String get providerSetupIntroTemplate =>
      'Choisissez avec qui Wendelin doit parler.';

  @override
  String providerSetupModelListFailed(String reason) {
    return 'Liste des modèles indisponible ($reason). Veuillez saisir l’ID du modèle.';
  }

  @override
  String get providerSetupModelListUnavailable =>
      'Liste de modèles indisponible';

  @override
  String get providerSetupModelUnusable => 'Modèle inutilisable';

  @override
  String providerSetupModelsFound(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n modèles trouvés',
      one: '1 modèle trouvé',
    );
    return '$_temp0';
  }

  @override
  String get providerSetupNoModelList =>
      'Pas de liste de modèles. Veuillez saisir l’ID du modèle.';

  @override
  String get providerSetupProviderSetupApiKeyOptional =>
      'Clé d’API (facultative)';

  @override
  String get providerSetupProviderSetupBaseUrl => 'URL de base';

  @override
  String get providerSetupProviderSetupCreateKey =>
      'Créer la clé chez le fournisseur';

  @override
  String get providerSetupProviderSetupModelId => 'ID du modèle';

  @override
  String get providerSetupProviderSetupModels => 'Modèles';

  @override
  String get providerSetupProviderSetupOtherTemplate => 'Autre modèle';

  @override
  String get providerSetupProviderSetupProbeModel => 'Vérifier le modèle';

  @override
  String get providerSetupProviderSetupTestConnection => 'Tester la connexion';

  @override
  String get providerSetupProviderSetupTesting => 'Test en cours …';

  @override
  String get providersAdd => '+ Fournisseur';

  @override
  String providersBudget(String v) {
    return 'Budget $v/mois';
  }

  @override
  String get providersChoice => 'Choix du fournisseur';

  @override
  String get providersDeleteBody =>
      'Le profil et la clé enregistrée sont supprimés.';

  @override
  String providersDeleteTitle(String name) {
    return 'Supprimer « $name » ?';
  }

  @override
  String providersError(String error) {
    return 'Erreur : $error';
  }

  @override
  String get providersIntro =>
      'Le fournisseur par défaut reçoit toute demande pour laquelle aucune règle de routage ne s’applique. S’il échoue, Wendelin le dit clairement et ne passe jamais de lui-même à un autre fournisseur.';

  @override
  String get providersMakeDefault => 'Définir par défaut';

  @override
  String get providersNone => 'Aucun fournisseur configuré pour l’instant.';

  @override
  String get providersProfiles => 'Profils';

  @override
  String get providersRoutingHint => 'Règles pour le choix du fournisseur';

  @override
  String get targetPickerApply => 'Appliquer';

  @override
  String get targetPickerProfile => 'Profil';

  @override
  String targetPickerProfileGone(String profileId) {
    return 'Le profil « $profileId » n’existe plus.';
  }

  @override
  String get quickSwitchCurrent => 'actuel';

  @override
  String get quickSwitchHint =>
      'Le choix termine cette conversation et en commence une nouvelle.';

  @override
  String quickSwitchItemSemantics(String name, String level) {
    return '$name, $level';
  }

  @override
  String get quickSwitchSemanticsAction => 'Changer d\'agent';

  @override
  String get quickSwitchTitle => 'Changer d\'agent';

  @override
  String get condBuilderAddCondition => '+ Condition';

  @override
  String get condBuilderAddConditionInGroup => '+ Condition dans le groupe';

  @override
  String get condBuilderAddGroup => '+ Groupe';

  @override
  String get condBuilderAll => 'toutes (et)';

  @override
  String get condBuilderAny => 'une au moins (ou)';

  @override
  String get condBuilderApplies => 'Condition';

  @override
  String get condBuilderCategory => 'Catégorie';

  @override
  String get condBuilderConfidenceBelow => 'Confiance inférieure à';

  @override
  String get condBuilderEmptyGroup => 'Un groupe est vide.';

  @override
  String condBuilderFail(String label, String m) {
    return '$label : $m';
  }

  @override
  String get condBuilderFrom => 'de (HH:MM)';

  @override
  String get condBuilderGroup => 'Groupe';

  @override
  String get condBuilderLanguages => 'Langues';

  @override
  String get condBuilderLanguagesHint => 'de, fr';

  @override
  String get condBuilderMetered => 'données mobiles';

  @override
  String get condBuilderMoreChars => 'Plus de caractères que';

  @override
  String get condBuilderNeedCategory => 'saisissez une catégorie.';

  @override
  String get condBuilderNeedLang => 'saisissez un code de langue (de, fr …).';

  @override
  String get condBuilderNeedLength => 'saisissez un nombre de caractères.';

  @override
  String get condBuilderNeedPattern => 'saisissez un motif.';

  @override
  String get condBuilderNeedThreshold => 'saisissez un seuil entre 0 et 1.';

  @override
  String get condBuilderNeedTime => 'saisissez une heure au format HH:MM.';

  @override
  String get condBuilderNeedWord => 'saisissez au moins un mot.';

  @override
  String get condBuilderPattern => 'Motif (sur le texte normalisé)';

  @override
  String get condBuilderRemoveCondition => 'Supprimer la condition';

  @override
  String get condBuilderRemoveGroup => 'Supprimer le groupe';

  @override
  String get condBuilderSentenceStart =>
      'Mots en début de phrase, séparés par des virgules';

  @override
  String get condBuilderSentenceStartHint => 'Claude';

  @override
  String get condBuilderTo => 'à (HH:MM)';

  @override
  String get condBuilderUnknownType => 'type inconnu.';

  @override
  String get condBuilderWords => 'Mots, séparés par des virgules';

  @override
  String get condBuilderWordsHint => 'privé, confidentiel';

  @override
  String get routingAllDay => 'toute la journée';

  @override
  String routingApplies(String target, String private) {
    return 's’applique → $target$private';
  }

  @override
  String get routingCondAnd => 'et';

  @override
  String get routingCondImage => 'Avec image';

  @override
  String get routingCondKeyword => 'Mot-clé';

  @override
  String get routingCondLanguage => 'Langue';

  @override
  String get routingCondLong => 'Saisie longue';

  @override
  String get routingCondNetwork => 'Réseau';

  @override
  String get routingCondNot => 'non';

  @override
  String get routingCondOr => 'ou';

  @override
  String get routingCondPrefix => 'Préfixe';

  @override
  String get routingCondPrivate => 'Privé';

  @override
  String get routingCondRegex => 'Expression régulière';

  @override
  String get routingCondTime => 'Plage horaire';

  @override
  String get routingCondTool => 'Nécessite un outil';

  @override
  String get routingCondUncertain => 'Reconnaissance incertaine';

  @override
  String get routingDefault => 'Par défaut';

  @override
  String routingDeleted(String profileId) {
    return '$profileId (supprimé)';
  }

  @override
  String routingImportBody(int length, int before) {
    return '$length règles remplacent les $before précédentes. Rien ne change avant d’appuyer sur « Remplacer ».';
  }

  @override
  String routingImportDefaultMissing(String profileId) {
    return 'Le profil par défaut « $profileId » n’existe pas ici ; l’ancien reste en vigueur.';
  }

  @override
  String get routingImportEscalations =>
      'Le fichier contient des chaînes d’escalade. Elles ont été ignorées : Wendelin ne change jamais de modèle de lui-même.';

  @override
  String get routingImportReplace => 'Remplacer';

  @override
  String get routingImportTitle => 'Importer les règles ?';

  @override
  String routingPrivateRuleNotice(String target) {
    return 'Nouveau : règle « Privé » – les demandes avec « privé », « confidentiel » … vont à $target.';
  }

  @override
  String get routingPrivateSuffix => ' · privé';

  @override
  String routingRuleN(int n) {
    return 'Règle $n';
  }

  @override
  String get routingScreenAddRule => '+ Ajouter une règle';

  @override
  String get routingScreenDefaultTarget => 'Cible par défaut';

  @override
  String get routingScreenFirstWins =>
      'La première règle correspondante l’emporte';

  @override
  String routingScreenImportFailed(String message) {
    return 'Import impossible : $message';
  }

  @override
  String routingScreenMoveRule(String name) {
    return 'Déplacer la règle « $name »';
  }

  @override
  String get routingScreenNeedsProvider =>
      'Le routage nécessite un fournisseur. Configurez-en un d’abord.';

  @override
  String routingScreenReadError(String error) {
    return 'Impossible de lire les règles : $error';
  }

  @override
  String get routingScreenResetBody =>
      'Les règles enregistrées sont supprimées et recréées à partir des paramètres des fournisseurs.';

  @override
  String get routingScreenResetRules => 'Réinitialiser les règles';

  @override
  String get routingScreenResetTitle => 'Réinitialiser les règles ?';

  @override
  String routingScreenRuleOff(String name) {
    return '$name (désactivée)';
  }

  @override
  String routingScreenSkipped(String name, String v) {
    return '« $name » ignorée : $v';
  }

  @override
  String get routingScreenTestHint =>
      'Quelle règle s’applique à cette phrase ?';

  @override
  String get routingScreenTestSentence => 'Phrase de test';

  @override
  String get routingSkipDisabled => 'désactivée';

  @override
  String get routingSkipInvalid => 'invalide';

  @override
  String get routingSkipNoMatch => 'ne correspond pas';

  @override
  String get routingSkipProfileDisabled => 'profil désactivé';

  @override
  String get routingSkipProfileMissing => 'profil supprimé';

  @override
  String get routingSkipProfileUnavailable => 'profil indisponible';

  @override
  String get routingWeekdayFri => 'ven';

  @override
  String get routingWeekdayMon => 'lun';

  @override
  String get routingWeekdaySat => 'sam';

  @override
  String get routingWeekdaySun => 'dim';

  @override
  String get routingWeekdayThu => 'jeu';

  @override
  String get routingWeekdayTue => 'mar';

  @override
  String get routingWeekdayWed => 'mer';

  @override
  String get ruleEditorActive => 'Actif';

  @override
  String get ruleEditorActiveLabel => 'Règle active';

  @override
  String get ruleEditorCondition => 'Condition';

  @override
  String get ruleEditorDeleteBody =>
      'Les demandes qui utilisaient cette règle vérifient les règles suivantes ou vont vers la valeur par défaut.';

  @override
  String get ruleEditorDeleteRule => 'Supprimer la règle';

  @override
  String ruleEditorDeleteTitle(String v) {
    return 'Supprimer la règle « $v » ?';
  }

  @override
  String get ruleEditorEditRule => 'Modifier la règle';

  @override
  String get ruleEditorNeedModel => 'Veuillez saisir un modèle.';

  @override
  String get ruleEditorNeedName => 'Veuillez saisir un nom.';

  @override
  String get ruleEditorNewRule => 'Nouvelle règle';

  @override
  String get ruleEditorRebuild => 'Reconstruire';

  @override
  String get ruleEditorRule => 'Règle';

  @override
  String get ruleEditorStripTrigger => 'Retirer le déclencheur';

  @override
  String get ruleEditorStripTriggerHint =>
      'Le préfixe, le mot-clé ou la correspondance ne vont pas au modèle ; la phrase reste complète dans l’historique.';

  @override
  String get ruleEditorStripTriggerLabel => 'Retirer le déclencheur';

  @override
  String get ruleEditorTarget => 'Cible';

  @override
  String get ruleEditorTooDeep =>
      'Cette condition est imbriquée plus profondément que l’éditeur ne peut la modifier. Elle reste inchangée.';

  @override
  String get ruleTileMove => 'Déplacer';

  @override
  String ruleTileSemanticsLevel(String level) {
    return 'Niveau de confidentialité $level,';
  }

  @override
  String get speakerAdd => 'Enregistrer une personne';

  @override
  String get speakerAddDetail =>
      'Lire cinq courtes phrases ; les enregistrements ne sont pas conservés.';

  @override
  String get speakerAddNeedsModel => 'Télécharge d\'abord le modèle.';

  @override
  String speakerDeleteBody(String name) {
    return '$name est supprimé(e) avec toutes les caractéristiques vocales enregistrées et ses conversations.';
  }

  @override
  String speakerDeleteBodyMemory(String name, int count) {
    return '$name est supprimé(e) avec toutes les caractéristiques vocales, ses conversations et $count entrées de sa mémoire propre. La mémoire par défaut reste inchangée.';
  }

  @override
  String get speakerDeleteConfirm => 'Supprimer';

  @override
  String speakerDeleteSemantic(String name) {
    return 'Supprimer $name';
  }

  @override
  String get speakerDeleteTitle => 'Supprimer la personne ?';

  @override
  String get speakerDone => 'Terminé';

  @override
  String get speakerEnrollIntro =>
      'Lis chaque phrase à voix normale. Seule une caractéristique vocale est calculée, l\'audio est supprimé.';

  @override
  String get speakerEnrollTitle => 'Enregistrer une personne';

  @override
  String get speakerErrFailed =>
      'Le modèle n\'a pas pu analyser les enregistrements. Est-il entièrement téléchargé ?';

  @override
  String get speakerErrInconsistent =>
      'Les phrases ne semblaient pas venir de la même personne, ou il y avait trop de bruit. Rien n\'a été enregistré ; réessaie au calme.';

  @override
  String get speakerErrTooFew => 'Il manque des enregistrements.';

  @override
  String get speakerErrTooShort =>
      'Un enregistrement était trop court. Réessaie.';

  @override
  String get speakerIntro =>
      'Wendelin peut reconnaître qui parle. Le résultat est transmis à l\'assistant à titre d\'information.';

  @override
  String get speakerModelSection => 'Modèle';

  @override
  String get speakerNameLabel => 'Nom';

  @override
  String get speakerNext => 'Suivant';

  @override
  String get speakerNoMic =>
      'Sans accès au microphone, personne ne peut être enregistré.';

  @override
  String get speakerNobody => 'Personne n\'est encore enregistré.';

  @override
  String get speakerPeople => 'Personnes';

  @override
  String get speakerPersonAddress => 'Appellation';

  @override
  String get speakerPersonAddressHint =>
      'Comment Wendelin s\'adresse à vous. Vide : le nom enregistré.';

  @override
  String get speakerPersonAgent => 'Agent';

  @override
  String get speakerPersonAgentDefault => 'Agent par défaut';

  @override
  String get speakerPersonAgentDetail =>
      'Seulement une autre cible à la place de celle par défaut. Les règles et la confidentialité restent valables.';

  @override
  String get speakerPersonDelete => 'Supprimer la personne';

  @override
  String get speakerPersonMemory => 'Mémoire';

  @override
  String get speakerPersonMemoryOpen => 'Voir les entrées';

  @override
  String get speakerPersonMemoryOwn => 'Mémoire propre';

  @override
  String get speakerPersonMemoryOwnDetail =>
      'Ne retient des choses que pour cette personne.';

  @override
  String get speakerPersonMemoryShared => 'Mémoire par défaut';

  @override
  String get speakerPersonMemorySharedDetail =>
      'Partage les entrées existantes avec tous ceux qui ne sont pas reconnus.';

  @override
  String get speakerPersonRetrain => 'Réenregistrer';

  @override
  String get speakerPersonRetrainDetail => 'Relire les cinq phrases.';

  @override
  String get speakerProcessing => 'Analyse en cours …';

  @override
  String get speakerRecordCutOff => 'Commencé trop tôt, relis la phrase.';

  @override
  String get speakerRecordNoSpeech => 'Rien entendu, réessaie.';

  @override
  String get speakerRecordTooLong =>
      'Trop long ou trop de bruit de fond, réessaie.';

  @override
  String get speakerRecordTooQuiet => 'Trop bas, parle plus fort.';

  @override
  String get speakerResultClamped => 'Le seuil a été limité à une valeur sûre.';

  @override
  String speakerResultScores(String mean, String min, String threshold) {
    return 'Régularité $mean, phrase la plus faible $min, seuil $threshold.';
  }

  @override
  String get speakerResultTitle => 'Enregistré';

  @override
  String get speakerRetry => 'Réessayer';

  @override
  String get speakerRowDetail =>
      'Reconnaît qui parle (nom, modèle, personnes).';

  @override
  String get speakerRowTitle => 'Reconnaissance du locuteur';

  @override
  String get speakerSayNow => 'Lis cette phrase à voix haute :';

  @override
  String get speakerSentence1 =>
      'Ce matin, j\'ai fait une promenade dans le parc.';

  @override
  String get speakerSentence2 =>
      'Rappelle-moi demain à neuf heures le rendez-vous chez le médecin.';

  @override
  String get speakerSentence3 =>
      'Les premières fleurs s\'ouvrent dans le jardin et le soleil est chaud.';

  @override
  String get speakerSentence4 =>
      'Peux-tu me dire quel temps il fera ce week-end ?';

  @override
  String get speakerSentence5 =>
      'Ce soir, au dîner, il y a de la soupe avec du pain frais.';

  @override
  String speakerSentenceOf(int n, int total) {
    return 'Phrase $n sur $total';
  }

  @override
  String get speakerSwitch => 'Reconnaissance du locuteur';

  @override
  String get speakerSwitchHint =>
      'La voix n\'est pas une authentification sûre : des voix proches ou imitées peuvent être confondues. Seules des caractéristiques vocales chiffrées sont conservées, jamais des enregistrements.';

  @override
  String get speakerSwitchLabel =>
      'Reconnaissance du locuteur activée ou désactivée';

  @override
  String get speakerTitle => 'Reconnaissance du locuteur';

  @override
  String get spotifyAppNote =>
      'L’application Spotify est nécessaire pour que Wendelin puisse lire sur ce téléphone : si elle ne tourne pas, Wendelin la démarre. Sur d’autres appareils (enceintes, ordinateur), Wendelin lit aussi sans elle.';

  @override
  String get spotifyAppTitle => 'Application Spotify';

  @override
  String get spotifyClientIdLabel => 'Identifiant client';

  @override
  String get spotifyClientIdMissing => 'Saisissez l’identifiant client.';

  @override
  String get spotifyCopied => 'Adresse copiée.';

  @override
  String get spotifyCopyRedirect => 'Copier l’adresse';

  @override
  String get spotifyErrAccessDenied =>
      'Connexion annulée : accès non autorisé.';

  @override
  String get spotifyErrCancelled => 'Connexion annulée.';

  @override
  String get spotifyErrDenied => 'Spotify a refusé la connexion.';

  @override
  String get spotifyErrFailed => 'Connexion à Spotify impossible.';

  @override
  String get spotifyErrInvalidClientId =>
      'L’ID client comporte 32 caractères (chiffres et lettres a–f). Copiez-le depuis le tableau de bord développeur.';

  @override
  String get spotifyErrNoBrowser =>
      'Aucun navigateur n’est installé pour effectuer la connexion.';

  @override
  String get spotifyErrNoCode => 'Spotify n’a pas envoyé de code.';

  @override
  String get spotifyErrRejected =>
      'Spotify a refusé la connexion. Vérifiez l’ID client et que votre compte figure sous « User Management ».';

  @override
  String get spotifyErrStateMismatch =>
      'Connexion refusée : la réponse de Spotify ne correspond pas à cette connexion (p. ex. un ancien onglet du navigateur). Relancez la connexion et terminez-la dans le nouvel onglet.';

  @override
  String get spotifyErrUnavailable =>
      'Spotify est injoignable. Réessayez plus tard.';

  @override
  String get spotifyFailed =>
      'Erreur – connexion expirée ou Spotify injoignable';

  @override
  String get spotifyGuideStep1 =>
      '1. Connectez-vous sur developer.spotify.com/dashboard avec votre compte Spotify et choisissez « Create app ».';

  @override
  String spotifyGuideStep2(String redirect) {
    return '2. Choisissez librement un nom et une description. Saisissez exactement cette adresse comme « Redirect URI » : $redirect';
  }

  @override
  String get spotifyGuideStep3 =>
      '3. Sous « Which API/SDKs are you planning to use? », cochez « Web API » et enregistrez.';

  @override
  String get spotifyGuideStep4 =>
      '4. Sous « Settings », copiez le « Client ID » et saisissez-le ci-dessous. En mode développement, votre propre compte doit figurer sous « User Management ».';

  @override
  String get spotifyGuideTitle => 'Créer une application développeur';

  @override
  String get spotifyIntro =>
      'Wendelin pilote Spotify via l’interface officielle. Cela nécessite un compte Spotify Premium et votre propre application développeur (gratuite). L’identifiant client et la connexion restent dans le stockage sécurisé de l’appareil.';

  @override
  String get spotifyReconnected => 'Spotify est de nouveau joignable.';

  @override
  String get spotifyRetrying => 'Vérification …';

  @override
  String get spotifySignIn => 'Se connecter à Spotify';

  @override
  String get spotifySignOut => 'Se déconnecter';

  @override
  String get spotifySignOutMessage =>
      'L’identifiant client et la connexion sont supprimés de l’appareil.';

  @override
  String get spotifySignOutTitle => 'Se déconnecter de Spotify ?';

  @override
  String get spotifySignedIn => 'Connecté';

  @override
  String get spotifySigningIn => 'Connexion …';

  @override
  String get spotifyStateActive => 'Connecté · Actif';

  @override
  String get spotifyStateLoginMissing => 'Connexion manquante';

  @override
  String get spotifyStateOff => 'Connecté, intégration désactivée';

  @override
  String get spotifyStateUnavailable => 'Non disponible';

  @override
  String get spotifyTitle => 'Spotify';

  @override
  String get stationAllDay => 'toute la journée';

  @override
  String get stationEnd => 'Terminer';

  @override
  String get stationEndHint => 'Déverrouille le téléphone pour terminer.';

  @override
  String get stationEvents => 'Rendez-vous';

  @override
  String stationHour(int hour) {
    return '$hour h';
  }

  @override
  String get stationNoEvents => 'Aucun rendez-vous à venir.';

  @override
  String get stationNoTasks => 'Aucune tâche due.';

  @override
  String get stationOverdue => 'en retard';

  @override
  String get stationPlaybackSlot => 'Lecture';

  @override
  String get stationQuietFrom => 'Début des heures calmes';

  @override
  String get stationQuietSection => 'Heures calmes';

  @override
  String get stationQuietTo => 'Fin des heures calmes';

  @override
  String get stationScreenAlways => 'Toujours allumé, atténué';

  @override
  String get stationScreenAlwaysDetail =>
      'La luminosité suit la lumière ambiante, le contenu se déplace légèrement contre la rémanence.';

  @override
  String get stationScreenDaytime => 'Allumé le jour, éteint aux heures calmes';

  @override
  String get stationScreenDaytimeDetail =>
      'Un toucher réveille la station un instant.';

  @override
  String get stationScreenSection => 'Écran';

  @override
  String get stationScreenTouch => 'Éteint, allumé par mot d’éveil ou toucher';

  @override
  String get stationScreenTouchDetail =>
      'L’écran s’éteint après le délai habituel.';

  @override
  String get stationSectionsIntro =>
      'Ce que la station affiche. L’heure et la date sont toujours là. Rendez-vous et tâches apparaissent avec leurs titres.';

  @override
  String get stationSectionsSection => 'Affichage';

  @override
  String get stationSettingsDetail => 'Écran, heures calmes, zones affichées';

  @override
  String get stationSettingsIntro =>
      'Le téléphone est sur le chargeur et affiche l’heure, la date et plus. Le mode ne démarre qu’à la main et ne se termine qu’après déverrouillage.';

  @override
  String get stationSlotSoon => 'bientôt';

  @override
  String get stationStart => 'Démarrer le mode station';

  @override
  String get stationTasks => 'Tâches';

  @override
  String get stationTilesSlot => 'Maison connectée';

  @override
  String get stationTitle => 'Mode station';

  @override
  String get stationWeather => 'Météo';

  @override
  String get googleTasksApiError =>
      'Erreur – Google injoignable ou connexion refusée';

  @override
  String get googleTasksCancel => 'Annuler';

  @override
  String get googleTasksChecking => 'Vérification …';

  @override
  String get googleTasksClientId => 'ID client';

  @override
  String get googleTasksClientSecret => 'Secret client';

  @override
  String get googleTasksErrAccessDenied =>
      'Connexion annulée : accès non autorisé (votre compte est-il enregistré comme utilisateur test dans le projet Cloud ?).';

  @override
  String get googleTasksErrCancelled => 'Connexion annulée.';

  @override
  String get googleTasksErrClientRejected =>
      'Google refuse l’ID client ou le secret client. Veuillez vérifier les deux.';

  @override
  String get googleTasksErrDenied => 'Google a refusé la connexion.';

  @override
  String get googleTasksErrFailed => 'La connexion a échoué.';

  @override
  String get googleTasksErrInvalidClientId =>
      'L’ID client se termine par « .apps.googleusercontent.com ». Copiez-le depuis la console Google Cloud (client OAuth de type « Application de bureau »).';

  @override
  String get googleTasksErrMissingSecret =>
      'Veuillez saisir le secret client OAuth (sans espaces).';

  @override
  String get googleTasksErrNoBrowser => 'Aucun navigateur n’est installé.';

  @override
  String get googleTasksErrNoCode => 'Google n’a envoyé aucun code.';

  @override
  String get googleTasksErrNoRefreshToken =>
      'Google n’a pas envoyé de jeton d’actualisation. Retirez l’accès de Wendelin sur myaccount.google.com/permissions et reconnectez-vous.';

  @override
  String get googleTasksErrReceiver =>
      'Le récepteur local pour la connexion n’a pas pu démarrer.';

  @override
  String get googleTasksErrTimeout =>
      'Délai dépassé : aucune réponse de Google n’est arrivée dans le navigateur. Veuillez vous reconnecter.';

  @override
  String get googleTasksErrUnavailable =>
      'Google est inaccessible. Veuillez réessayer plus tard.';

  @override
  String get googleTasksFine => 'OK';

  @override
  String get googleTasksGuideNote =>
      'En mode test, la connexion expire après 7 jours ; reconnectez-vous alors ici. Google signale une « application non validée » (c’est votre propre projet) : choisissez « Continuer » et autorisez l’accès aux tâches.';

  @override
  String get googleTasksGuideStep1 =>
      '1. Dans console.cloud.google.com, créez un projet (ou choisissez le vôtre).';

  @override
  String get googleTasksGuideStep2 =>
      '2. Sous « API et services → Bibliothèque », activez l’« API Google Tasks ».';

  @override
  String get googleTasksGuideStep3 =>
      '3. Sous « Google Auth Platform » (anciennement « écran de consentement OAuth »), gardez le public « Externe » en mode test et ajoutez votre compte Google comme utilisateur test.';

  @override
  String get googleTasksGuideStep4 =>
      '4. Sous « Clients » (anciennement « Identifiants »), créez un client OAuth de type « Application de bureau ». Copiez l’ID client et le secret client et saisissez-les ci-dessous.';

  @override
  String get googleTasksGuideTitle => 'Configurer un projet Google Cloud';

  @override
  String get googleTasksIntro =>
      'Tâches Google avec votre propre projet Cloud, sans services Google Play. La connexion se fait dans le navigateur ; ID client, secret client et connexion restent dans le stockage sécurisé de l’appareil et ne sont jamais affichés ni journalisés. Les listes de tâches servent de listes ; Google ne connaît qu’une date d’échéance, ni heure ni priorité.';

  @override
  String get googleTasksNeedClient =>
      'Veuillez saisir l’ID client et le secret client.';

  @override
  String get googleTasksReachable => 'Google Tasks est joignable.';

  @override
  String get googleTasksSignIn => 'Se connecter à Google';

  @override
  String get googleTasksSignInWaiting => 'En attente de Google …';

  @override
  String get googleTasksSignOutBody =>
      'La connexion est révoquée chez Google (si joignable) ; ID client, secret client et jeton sont supprimés de l’appareil.';

  @override
  String get googleTasksSignOutTitle => 'Déconnecter Google Tasks ?';

  @override
  String get googleTasksStatusAvailable => 'Connecté, intégration désactivée';

  @override
  String get googleTasksStatusSetup => 'Connexion manquante';

  @override
  String get googleTasksStatusUnavailable => 'Indisponible';

  @override
  String get googleTasksStatusUnknown => 'Inconnu';

  @override
  String get integrationDetailGoogleTasksAccount => 'Compte Google';

  @override
  String get integrationDetailTodoistAccount => 'Compte Todoist';

  @override
  String get todoistApiError => 'Erreur – Todoist injoignable ou jeton refusé';

  @override
  String get todoistChecking => 'Vérification …';

  @override
  String get todoistConnect => 'Connecter';

  @override
  String get todoistConnecting => 'Connexion …';

  @override
  String get todoistErrDenied =>
      'Todoist a refusé le jeton (invalide ou révoqué).';

  @override
  String get todoistErrFailed => 'La connexion à Todoist a échoué.';

  @override
  String get todoistErrUnavailable =>
      'Todoist est inaccessible. Veuillez réessayer plus tard.';

  @override
  String get todoistFine => 'OK';

  @override
  String get todoistIntro =>
      'Tâches Todoist avec votre jeton d’API personnel. Vous le trouvez dans Todoist sous Paramètres → Intégrations → Développeur. Il reste dans le stockage sécurisé de l’appareil et n’est jamais affiché ni journalisé. Les projets servent de listes.';

  @override
  String get todoistNeedToken => 'Veuillez saisir le jeton d’API.';

  @override
  String get todoistReachable => 'Todoist est de nouveau joignable.';

  @override
  String get todoistSignOutBody =>
      'Le jeton est supprimé de l’appareil. Vous pouvez aussi le révoquer dans Todoist.';

  @override
  String get todoistSignOutTitle => 'Déconnecter Todoist ?';

  @override
  String get todoistStatusAvailable => 'Connecté, intégration désactivée';

  @override
  String get todoistStatusSetup => 'Jeton manquant';

  @override
  String get todoistStatusUnavailable => 'Indisponible';

  @override
  String get todoistStatusUnknown => 'Inconnu';

  @override
  String get todoistToken => 'Jeton d’API';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'Français';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get modelRowDeleteBody =>
      'Le modèle est supprimé de l’appareil et doit être téléchargé à nouveau avant la prochaine utilisation.';

  @override
  String modelRowDeleteTitle(String displayName) {
    return 'Supprimer $displayName ?';
  }

  @override
  String modelRowLoaded(String size) {
    return '$size · téléchargé';
  }

  @override
  String modelRowNotLoaded(String size) {
    return '$size · non téléchargé';
  }

  @override
  String modelRowProgressOf(String displayName) {
    return 'Progression $displayName';
  }

  @override
  String modelRowRam(String ram) {
    return 'Mémoire d’environ $ram';
  }

  @override
  String get modelRowResume => 'Reprendre';

  @override
  String modelRowStarted(String size) {
    return '$size · partiellement téléchargé';
  }

  @override
  String get voiceConvAdvanced => 'Avancé';

  @override
  String get voiceConvBargeInUnavailable =>
      'Indisponible : Wendelin a besoin pour cela du modèle de mot d’activation, qui n’est pas encore intégré.';

  @override
  String get voiceConvBargeKeywords => 'Mots-clés';

  @override
  String get voiceConvBargeSpeech => 'Toute parole (expérimental)';

  @override
  String get voiceConvCustomBarge =>
      'Un réglage personnalisé pour l’interruption est actif (réinitialisable sous « Avancé »).';

  @override
  String get voiceConvInterrupt => 'Interrompre pendant la réponse';

  @override
  String get voiceConvInterruptHint =>
      'Avec « Wendelin » ou « Stop », vous interrompez la sortie vocale.';

  @override
  String get voiceConvKeepListening => 'Continuer à écouter après la réponse';

  @override
  String get voiceConvKeepListeningDetail =>
      'Après la réponse parlée, le microphone reste brièvement ouvert et vous pouvez poser une question sans toucher l’écran. « Merci » ou « Stop » y met fin.';

  @override
  String get voiceConvKeepListeningLabel =>
      'Continuer à écouter après la réponse';

  @override
  String get voiceDownloadAnd => ' et ';

  @override
  String voiceDownloadBundled(String displayName, String v) {
    return '$displayName en fait partie ($v) et est téléchargé aussi. « small » reconnaît bien mieux l’allemand, le français et les noms, et il est recommandé. « base » est rapide et prévu pour les appareils peu puissants. Autres modèles : Paramètres → Voix.';
  }

  @override
  String get voiceDownloadContinueInBackground => 'Continuer en arrière-plan';

  @override
  String get voiceDownloadContinueLoading => 'Reprendre le chargement';

  @override
  String get voiceDownloadIntro =>
      'Wendelin reconnaît la parole sur l’appareil, sans internet et sans Google. Choisissez le modèle et téléchargez-le une fois, de préférence en Wi-Fi.';

  @override
  String get voiceDownloadLoad => 'Charger';

  @override
  String get voiceDownloadLoadAgain => 'Recharger';

  @override
  String get voiceDownloadLoading => 'Chargement …';

  @override
  String voiceDownloadLoadingPercent(String v) {
    return 'Chargement … $v %';
  }

  @override
  String voiceDownloadLoadingPercentOf(String v, String size) {
    return 'Chargement … $v % sur $size';
  }

  @override
  String voiceDownloadPreselectedBase(String v) {
    return '« base » est présélectionné parce que l’appareil a peu de mémoire ($v Go). « small » demande nettement plus de mémoire pour la reconnaissance.';
  }

  @override
  String get voiceDownloadProgressLabel =>
      'Progression de la reconnaissance vocale';

  @override
  String get voiceDownloadReady => 'Prêt';

  @override
  String voiceDownloadSizeLoaded(String size) {
    return '$size · chargé';
  }

  @override
  String voiceDownloadSizeMb(String v) {
    return '$v Mo';
  }

  @override
  String voiceDownloadSizePartial(String size) {
    return '$size · partiellement chargé';
  }

  @override
  String voiceDownloadStillNeeded(String v) {
    return 'Encore nécessaire : $v';
  }

  @override
  String get voiceDownloadTitle => 'Charger la reconnaissance vocale';

  @override
  String get voiceDownloadUnpacking => 'Décompression …';

  @override
  String get voiceErrorGeneric =>
      'La voix n’a pas fonctionné. Veuillez réessayer.';

  @override
  String get voiceErrorMicBusy =>
      'Le microphone était encore occupé. Veuillez parler de nouveau.';

  @override
  String get voiceErrorModelMissing =>
      'Un modèle vocal n’est pas encore téléchargé (Paramètres → Voix).';

  @override
  String get voiceMetricsClear => 'Vider la liste';

  @override
  String get voiceMetricsEmpty =>
      'Pas encore de mesures. Dites une commande ou écoutez un échantillon de voix.';

  @override
  String get voiceMetricsIntro =>
      'Les derniers énoncés de cette session : temps de calcul (latence), facteur temps réel (temps de calcul par durée audio, plus petit = plus rapide) et mémoire de l’app. Uniquement des chiffres, aucun contenu.';

  @override
  String voiceMetricsRow(String latency, String audio, String rtf, String ram) {
    return '$latency ms pour $audio ms d’audio · RTF $rtf · RAM $ram';
  }

  @override
  String get voiceMetricsStt => 'Reconnaissance';

  @override
  String get voiceMetricsTts => 'Synthèse vocale';

  @override
  String get voiceScreenAutomatic => 'Automatique';

  @override
  String get voiceScreenAutomaticDetail =>
      'Voix du système, sinon voix hors ligne';

  @override
  String get voiceScreenDetectAuto => 'Détecter automatiquement';

  @override
  String get voiceScreenFineTuning => 'Réglages fins';

  @override
  String get voiceScreenFixedLanguageHint =>
      'Avec une langue fixe, Whisper reconnaît les phrases courtes de façon plus fiable.';

  @override
  String get voiceScreenIntro =>
      'Wendelin reconnaît la parole sur l’appareil (Whisper). Les modèles sont téléchargés une fois et restent sur l’appareil.';

  @override
  String get voiceScreenKeepModel => 'Garder le modèle en mémoire';

  @override
  String get voiceScreenKeepModelHint =>
      'La reconnaissance et la voix restent chargées : réponses plus rapides, mais davantage de mémoire en permanence. Wendelin les libère quand la mémoire manque.';

  @override
  String get voiceScreenKeepModelLabel => 'Garder le modèle en mémoire';

  @override
  String get voiceScreenLanguageDefault => 'Voix par défaut de la langue';

  @override
  String get voiceScreenLanguageDefaultChip => 'Voix par défaut de la langue';

  @override
  String get voiceScreenLearnsVoice => 'Wendelin apprend votre voix';

  @override
  String get voiceScreenLearnsVoiceDetail => 'Entraîner, calibrer et essayer';

  @override
  String voiceScreenLikeApp(String v) {
    return 'Comme l’application ($v)';
  }

  @override
  String get voiceScreenListen => 'Écouter un échantillon';

  @override
  String get voiceScreenMetrics => 'Mesures';

  @override
  String get voiceScreenMetricsDetail =>
      'Durée, facteur temps réel et mémoire par énoncé';

  @override
  String get voiceScreenMicrophone => 'Microphone';

  @override
  String get voiceScreenMicrophoneTitle => 'Microphone';

  @override
  String get voiceScreenMinSpeech => 'Durée minimale de parole';

  @override
  String get voiceScreenMinSpeechDetail =>
      'Les bruits plus courts (clics, respirations) sont ignorés.';

  @override
  String get voiceScreenModelLicenses => 'Licences des modèles vocaux';

  @override
  String voiceScreenMs(int v) {
    return '$v ms';
  }

  @override
  String get voiceScreenNoOfflineVoice =>
      'Aucune voix hors ligne n’est chargée pour cette langue – Wendelin parle avec la voix du système.';

  @override
  String get voiceScreenNoSpeech =>
      'Aucune sortie vocale disponible : les réponses s’affichent seulement à l’écran. Téléchargez une voix hors ligne.';

  @override
  String get voiceScreenNoSystemVoice =>
      'Aucune voix système n’est installée – Wendelin parle avec la voix hors ligne.';

  @override
  String get voiceScreenNotAllowed => 'non autorisé';

  @override
  String get voiceScreenOfflineVoice => 'Voix hors ligne';

  @override
  String get voiceScreenOfflineVoices => 'Voix hors ligne';

  @override
  String get voiceScreenOverlay => 'Overlay de l’assistant';

  @override
  String get voiceScreenRecognition => 'Reconnaissance vocale';

  @override
  String get voiceScreenRecognitionHint =>
      'Pour la saisie vocale, Wendelin a besoin du modèle Whisper choisi et de la détection d’activité vocale.';

  @override
  String voiceScreenRecommendSmall(String v) {
    return 'Recommandé : small (plus précis), télécharger $v.';
  }

  @override
  String get voiceScreenSensitivity =>
      'Sensibilité de la reconnaissance vocale';

  @override
  String get voiceScreenSensitivityDetail =>
      'Seuil de Silero VAD : plus bas capte les sons plus faibles, plus haut ignore davantage de bruit.';

  @override
  String get voiceScreenSpeaksOffline =>
      'Wendelin parle avec la voix hors ligne.';

  @override
  String get voiceScreenSpeaksSystem =>
      'Wendelin parle avec la voix du système.';

  @override
  String get voiceScreenSpeechOutput => 'Sortie vocale';

  @override
  String get voiceScreenSpokenLanguage => 'Langue parlée';

  @override
  String get voiceScreenStopClosesOverlay => '« Stop » ferme l’overlay';

  @override
  String get voiceScreenStopClosesOverlayHint =>
      'Si vous dites « Stop », Wendelin affiche brièvement « Annulé » et ferme l’overlay.';

  @override
  String get voiceScreenStopClosesOverlayLabel => '« Stop » ferme l’overlay';

  @override
  String get voiceScreenSystemVoice => 'Voix du système';

  @override
  String get voiceScreenSystemVoiceTitle => 'Voix du système';

  @override
  String get voiceScreenTempo => 'Débit';

  @override
  String get voiceScreenVoice => 'Voix';

  @override
  String get voiceScreenVoiceAndTempo => 'Voix et débit';

  @override
  String voiceScreenVoiceLanguage(String v, String language) {
    return '$v ($language)';
  }

  @override
  String get voiceScreenVoices => 'Voix';

  @override
  String get voiceScreenVoicesDetail =>
      'Une voix féminine et une voix masculine par langue';

  @override
  String get voiceSpokenAlwaysDetail =>
      'Wendelin rédige d’abord un court texte parlé et le lit toujours, même après des contenus du web ou de tiers.';

  @override
  String get voiceSpokenAlwaysTitle => 'Toujours une version parlée dédiée';

  @override
  String get voiceSpokenAlwaysWarning =>
      'Ce qui est lu à voix haute peut différer de ce qui est affiché à l’écran.';

  @override
  String get voiceSpokenCheckedDetail =>
      'Après des contenus du web ou de tiers, un autre appel au modèle vérifie que le texte parlé et la réponse concordent. La sortie vocale démarre alors un peu plus tard et coûte un peu plus.';

  @override
  String get voiceSpokenCheckedTitle => 'Avec vérification par l’IA';

  @override
  String get voiceSpokenOffDetail =>
      'Wendelin lit à voix haute la réponse affichée, simplement préparée pour la prononciation.';

  @override
  String get voiceSpokenProtectedDetail =>
      'Texte parlé dédié, mais après des contenus du web ou de tiers, Wendelin lit à voix haute la réponse affichée.';

  @override
  String get voiceSpokenProtectedTitle => 'Protégée';

  @override
  String voiceSpokenSemantic(String label) {
    return 'Version parlée $label';
  }

  @override
  String get voiceSpokenTitle => 'Version parlée';

  @override
  String get voiceUnavailableHint =>
      'Télécharger la reconnaissance vocale : Paramètres → Voix';

  @override
  String get voiceVoicesIntro =>
      'Choisissez la voix hors ligne pour chaque langue. Seules les voix téléchargées occupent de la mémoire ; vous pouvez supprimer celles dont vous n’avez pas besoin.';

  @override
  String voiceVoicesNotLoaded(String v) {
    return 'La voix choisie n’est pas téléchargée – c’est $v qui parle.';
  }

  @override
  String get voiceVoicesPreparing => 'Préparation de l’échantillon …';

  @override
  String get voiceVoicesSampleFailed =>
      'Échantillon impossible – la voix n’a pas parlé.';

  @override
  String get voiceVoicesSpeaker => 'Voix';

  @override
  String get voiceVoicesStopSample => 'Arrêter l’échantillon';

  @override
  String bargeDebugDefaultSuffix(String v) {
    return '$v (par défaut)';
  }

  @override
  String get bargeDebugExtraThreshold => 'Seuil supplémentaire';

  @override
  String get bargeDebugHelpCommunication =>
      'Communication + AEC (par défaut) : le téléphone soustrait sa propre sortie du signal du microphone. Wendelin s’entend à peine, mais votre mot arrive un peu plus faiblement.';

  @override
  String get bargeDebugHelpMargin =>
      'Le seuil détermine la précision avec laquelle un mot doit correspondre. Plus haut (0,05, par défaut) : moins de fausses alertes, mais votre mot est plus souvent manqué. Plus bas (0,00 ou -0,05) : le mot est reconnu plus facilement, mais il y a plus de fausses alertes.';

  @override
  String get bargeDebugHelpRecognition =>
      'Reconnaissance, sans AEC : pas d’annulation d’écho. Votre mot arrive clairement, mais l’annonce en cours le couvre souvent, et Wendelin peut s’entendre.';

  @override
  String get bargeDebugHelpRecognitionAec =>
      'Reconnaissance + AEC : comme par défaut, mais avec le microphone de la reconnaissance vocale. Utile sur les appareils où le microphone par défaut atténue trop votre mot.';

  @override
  String get bargeDebugIntro =>
      'Règle la sensibilité avec laquelle « Wendelin » et « Stop » sont reconnus pendant la réponse. La modification s’applique à partir de la prochaine réponse parlée.';

  @override
  String get bargeDebugMicCommunication => 'Communication + AEC (par défaut)';

  @override
  String get bargeDebugMicDuring => 'Microphone pendant la réponse';

  @override
  String get bargeDebugMicRecognition => 'Reconnaissance, sans AEC';

  @override
  String get bargeDebugMicRecognitionAec => 'Reconnaissance + AEC';

  @override
  String get bargeDebugTitle => 'Avancé : interruption';

  @override
  String get micAllowTitle => 'Autoriser le microphone ?';

  @override
  String get micAndroidSettings => 'Paramètres Android';

  @override
  String get micExplanation =>
      'Wendelin n’écoute qu’après que vous l’avez déclenché (bouton du microphone ou assistant). L’enregistrement est converti en texte sur l’appareil et ne le quitte pas ; seul le texte reconnu est envoyé à votre fournisseur.';

  @override
  String get micNotNow => 'Pas maintenant';

  @override
  String micOnlyText(String v) {
    return 'Sans microphone, seul le texte fonctionne. $v';
  }

  @override
  String get micSettingsHint =>
      'Autorisez-le dans les paramètres Android sous Applications → Wendelin.';

  @override
  String get wakeCalibrateCancelled => 'Annulé. Rien n’a été modifié.';

  @override
  String get wakeCalibrateDone => 'Calibré.';

  @override
  String wakeCalibrateFailed(Object error) {
    return 'Échec : $error';
  }

  @override
  String get wakeCalibrateFinishNow => 'Terminer maintenant';

  @override
  String get wakeCalibrateIntro =>
      'Posez le téléphone et continuez à parler normalement. Wendelin écoute (indicateur du microphone allumé) mais ne retient que des valeurs numériques, ni audio ni texte. De temps en temps, il bipe : dites alors « Wendelin ».';

  @override
  String get wakeCalibrateMicPreparing => 'Préparation du microphone …';

  @override
  String wakeCalibrateMinutesLeft(int v) {
    return 'Encore $v min';
  }

  @override
  String get wakeCalibrateNoMic =>
      'Sans microphone, Wendelin ne peut pas calibrer.';

  @override
  String get wakeCalibrateNotDistinct =>
      'Vos enregistrements ne se distinguent pas du bruit de fond. Veuillez entraîner de nouveau votre voix. L’ancien seuil est conservé.';

  @override
  String get wakeCalibrateProgressLabel => 'Progression de la calibration';

  @override
  String wakeCalibratePrompts(int answered, int prompts) {
    return 'Sollicitations : $answered sur $prompts répondues';
  }

  @override
  String wakeCalibrateResult(String v, String v2, int v3) {
    return 'Seuil $v · $v2 fausses alertes par heure estimées (avant la vérification) · $v3 % de vos enregistrements reconnus.';
  }

  @override
  String get wakeCalibrateTitle => 'Calibrer';

  @override
  String get wakeCalibrateUnusable => 'Inutilisable.';

  @override
  String get wakeEnrollAllThere => 'Tous les enregistrements sont là.';

  @override
  String wakeEnrollFailed(Object error) {
    return 'L’entraînement a échoué : $error';
  }

  @override
  String get wakeEnrollHeard => 'Entendu.';

  @override
  String wakeEnrollIntro(String word) {
    return 'Dites « $word » quand c’est votre tour. De chaque enregistrement, Wendelin ne garde que des valeurs numériques ; l’audio est immédiatement supprimé.';
  }

  @override
  String get wakeEnrollMicPreparing => 'Préparation du microphone …';

  @override
  String get wakeEnrollNoMic =>
      'Sans microphone, Wendelin ne peut pas apprendre votre voix.';

  @override
  String get wakeEnrollNoSpeech =>
      'Rien entendu. Encore une fois, s’il vous plaît.';

  @override
  String get wakeEnrollProcessing => 'Traitement en cours …';

  @override
  String wakeEnrollProgress(int accepted, int target) {
    return '$accepted sur $target';
  }

  @override
  String get wakeEnrollProgressLabel => 'Progression de l’entraînement';

  @override
  String get wakeEnrollPrompt0 =>
      'Parlez normalement, le téléphone près de vous.';

  @override
  String get wakeEnrollPrompt1 => 'Maintenant à un ou deux mètres de distance.';

  @override
  String get wakeEnrollPrompt2 =>
      'Maintenant à voix basse, comme le soir dans votre chambre.';

  @override
  String get wakeEnrollPrompt3 =>
      'Comme vous le dites au quotidien, par exemple depuis un autre coin.';

  @override
  String wakeEnrollSaveWith(int accepted) {
    return 'Enregistrer avec $accepted enregistrements';
  }

  @override
  String wakeEnrollSayNow(String word) {
    return 'Dites maintenant : « $word »';
  }

  @override
  String get wakeEnrollTitle => 'Entraîner la voix';

  @override
  String get wakeEnrollTitleStop => 'Entraîner « Stop »';

  @override
  String get wakeEnrollTooEarly =>
      'Commencé trop tôt. Attendez un instant, puis parlez.';

  @override
  String wakeEnrollTooLong(String word) {
    return 'Trop long. Seulement « $word », s’il vous plaît.';
  }

  @override
  String get wakeEnrollTooQuiet =>
      'Trop bas. Un peu plus fort, s’il vous plaît.';

  @override
  String get wakeExplainBatteryBody =>
      'L’écoute permanente consomme de la batterie. Le réglage par défaut est donc « Seulement en charge ».';

  @override
  String get wakeExplainBatteryExemptBody =>
      'Pour qu’Android n’arrête pas le service, Wendelin devrait être exclu de l’optimisation de la batterie.';

  @override
  String get wakeExplainBatteryExemptTitle =>
      'Exclure de l’optimisation de la batterie ?';

  @override
  String get wakeExplainBatteryTitle => 'Batterie';

  @override
  String wakeExplainChecklist(String v, String v2) {
    return '$v : $v2';
  }

  @override
  String get wakeExplainEnable => 'Activer';

  @override
  String get wakeExplainEnableTitle => 'Activer le mot d’activation ?';

  @override
  String get wakeExplainExempt => 'Exclure';

  @override
  String get wakeExplainLocalBody =>
      'La reconnaissance du mot se fait sur l’appareil. Ce que vous dites après « Wendelin » est envoyé sous forme de texte au fournisseur d’IA choisi. L’audio n’est ni envoyé ni enregistré.';

  @override
  String get wakeExplainLocalTitle => 'L’écoute reste sur l’appareil';

  @override
  String get wakeExplainMicDotBody =>
      'Android affiche le point vert du microphone tant que le service écoute.';

  @override
  String get wakeExplainMicDotTitle => 'Point du microphone';

  @override
  String get wakeExplainPersistentBody =>
      'Tant que Wendelin écoute, Android affiche une notification. À partir d’Android 14, vous pouvez la balayer ; le service continue. Sans l’autorisation pour les notifications, Android n’en affiche pas ; Wendelin écoute quand même.';

  @override
  String get wakeExplainPersistentTitle => 'Notification permanente';

  @override
  String get wakeModelsLoadModel => 'Charger le modèle vocal';

  @override
  String wakeModelsNeedsModel(String v) {
    return 'Le modèle vocal doit d’abord être chargé ($v).';
  }

  @override
  String wakeModelsVerifyNeeds(String v) {
    return 'Pour la revérification, chargez le modèle vocal ($v).';
  }

  @override
  String get wakeServiceSectionAlways => 'Toujours';

  @override
  String get wakeServiceSectionAlwaysHint => 'Consomme nettement la batterie.';

  @override
  String get wakeServiceSectionBackground => 'Écoute en arrière-plan';

  @override
  String get wakeServiceSectionChime => 'Son de confirmation';

  @override
  String get wakeServiceSectionChimeDetail =>
      'Un bref son quand Wendelin a reconnu le mot.';

  @override
  String get wakeServiceSectionChooseAssistant => 'Choisir l’assistant';

  @override
  String get wakeServiceSectionEnable => 'Activer le mot d’activation';

  @override
  String get wakeServiceSectionEnableDetail =>
      'Wendelin écoute en arrière-plan le mot « Wendelin ».';

  @override
  String get wakeServiceSectionEndedEngine =>
      'Arrêté : la reconnaissance a échoué';

  @override
  String get wakeServiceSectionEndedNoPermission =>
      'Arrêté : autorisation du microphone manquante';

  @override
  String get wakeServiceSectionEndedNoRole =>
      'Arrêté : Wendelin n’est plus votre assistant';

  @override
  String get wakeServiceSectionEndedNotCharging =>
      'Arrêté : l’appareil ne charge plus';

  @override
  String get wakeServiceSectionEndedPaused => 'Arrêté : en pause';

  @override
  String get wakeServiceSectionEndedSystem => 'Arrêté par le système';

  @override
  String get wakeServiceSectionEndedTimeout =>
      'Arrêté par le système (limite de temps d’Android)';

  @override
  String get wakeServiceSectionEnrollFirst => 'Entraînez d’abord votre voix';

  @override
  String get wakeServiceSectionEnrollFirstBody =>
      'Sans voix entraînée, Wendelin ne reconnaît pas le mot d’activation.';

  @override
  String get wakeServiceSectionNotAssistant =>
      'Wendelin n’est pas votre assistant';

  @override
  String get wakeServiceSectionNotAssistantBody =>
      'Android n’autorise l’écoute en arrière-plan qu’à l’assistant par défaut. Choisissez Wendelin comme assistant.';

  @override
  String get wakeServiceSectionOnlyCharging => 'Seulement en charge';

  @override
  String get wakeServiceSectionOnlyChargingHint =>
      'Économise la batterie (par défaut).';

  @override
  String get wakeServiceSectionPausedLoading =>
      'En pause : attend le chargement';

  @override
  String wakeServiceSectionPausedUntil(String v) {
    return 'En pause jusqu’à $v';
  }

  @override
  String get wakeServiceSectionRunning => 'En cours';

  @override
  String get wakeServiceSectionSettingsFail =>
      'Impossible d’ouvrir les paramètres système.';

  @override
  String get wakeServiceSectionSoundCheck => 'Son et vérification';

  @override
  String get wakeServiceSectionStatus => 'État';

  @override
  String get wakeServiceSectionToEnroll => 'Lancer l’entraînement';

  @override
  String get wakeServiceSectionWhen => 'Quand écouter ?';

  @override
  String get wakeServiceSectionWhisper => 'Vérification avec Whisper';

  @override
  String get wakeServiceSectionWhisperDetail =>
      'Wendelin n’écoute que si Whisper confirme « Wendelin ». Désactivez-le s’il est trop strict pour votre voix ; il y aura alors plus de faux déclenchements.';

  @override
  String wakeTestAgo(String v, int inSeconds) {
    return '$v · $inSeconds s';
  }

  @override
  String wakeTestBest(String v, String v2) {
    return '$v · similarité maximale $v2';
  }

  @override
  String wakeTestCandidate(String v) {
    return 'Candidat · similarité $v';
  }

  @override
  String get wakeTestConfirmed => 'Vérification : confirmée';

  @override
  String wakeTestFailed(Object error) {
    return 'Échec : $error';
  }

  @override
  String get wakeTestIntro =>
      'Dites « Wendelin ». Les détections s’affichent ici sans que l’overlay s’ouvre. « Candidat » est la voix, « confirmé » la vérification avec Whisper.';

  @override
  String get wakeTestListening => 'À l’écoute';

  @override
  String get wakeTestMicPreparing => 'Préparation du microphone …';

  @override
  String get wakeTestNoHit => 'Pas encore de détection.';

  @override
  String get wakeTestNoMic => 'Le test ne fonctionne pas sans microphone.';

  @override
  String get wakeTestRejected => 'Vérification : non confirmée';

  @override
  String get wakeTestStopped => 'Arrêté';

  @override
  String get wakeTestTitle => 'Essayer';

  @override
  String get wakeTestUnavailable =>
      'Vérification : impossible (pas de Whisper)';

  @override
  String get wakeTestVerifying => 'Vérification en cours …';

  @override
  String wakeWordActionsFor(String v) {
    return 'Actions pour $v';
  }

  @override
  String get wakeWordCalibrate => 'Calibrer (30 min, recommandé)';

  @override
  String get wakeWordDeleteAll => 'Supprimer toutes les voix';

  @override
  String get wakeWordDeleteAllBody =>
      'Wendelin oublie toutes les voix entraînées. Vous pourrez les entraîner de nouveau plus tard.';

  @override
  String get wakeWordDeleteAllTitle => 'Supprimer toutes les voix ?';

  @override
  String get wakeWordEnroll => 'Entraîner la voix';

  @override
  String get wakeWordEnrollMore => 'Entraîner une autre personne';

  @override
  String get wakeWordFeatureModels => 'Modèles de caractéristiques';

  @override
  String get wakeWordInterrupt => 'Interrompre avec « Stop »';

  @override
  String get wakeWordIntro =>
      'Wendelin apprend votre voix : vous dites « Wendelin » environ 15 fois, ensuite il le reconnaît aussi au quotidien. Seules des valeurs numériques sont enregistrées, chiffrées sur l’appareil. L’audio n’est jamais enregistré.';

  @override
  String get wakeWordLearned => 'Voix entraînées';

  @override
  String get wakeWordNameOptional => 'Nom (facultatif)';

  @override
  String get wakeWordNeedsModel => 'Le modèle vocal doit d’abord être chargé.';

  @override
  String get wakeWordNoVoice => 'Aucune voix pour l’instant';

  @override
  String get wakeWordNoVoiceHint =>
      'Entraînez votre voix avec « Entraîner la voix ».';

  @override
  String wakeWordPerson(int number) {
    return 'Personne $number';
  }

  @override
  String wakeWordRecordingsThreshold(int length, String v, String v2) {
    return '$length enregistrements · seuil $v$v2';
  }

  @override
  String get wakeWordRetrain => 'Entraîner de nouveau';

  @override
  String get wakeWordRetrainStop => 'Entraîner « Stop » de nouveau';

  @override
  String get wakeWordStopLearned =>
      '« Stop » est entraîné : vous pouvez interrompre l’annonce avec « Stop » seul.';

  @override
  String get wakeWordStopNotLearned =>
      'Sans « Stop » entraîné, seul « Wendelin, stop » interrompt l’annonce. Entraînez « Stop » pour pouvoir interrompre l’annonce avec ce seul mot.';

  @override
  String get wakeWordStopOnlySpeaking =>
      '« Stop » ne fonctionne que pendant que Wendelin parle et que l’interruption est réglée sur « Mots-clés ». En arrière-plan, « Stop » ne déclenche rien.';

  @override
  String get wakeWordTemplatesMissing =>
      'Modèles manquants. Veuillez entraîner de nouveau.';

  @override
  String get wakeWordTrainStop => 'Entraîner « Stop »';

  @override
  String get wakeWordTryNow => 'Essayer maintenant';

  @override
  String get wakeWordWhoCalibrate => 'Qui calibrer ?';

  @override
  String get wakeWordWhoJoins => 'Qui s’ajoute ?';

  @override
  String get wakeWordWhoSpeaks => 'Qui parle ?';

  @override
  String get wakeWordWhoStop => 'Qui entraîne « Stop » ?';

  @override
  String get weatherHomeHelp =>
      'Utilisé lorsque vous ne nommez aucun lieu et que la position est inconnue. Laisser vide = pas de lieu de résidence.';

  @override
  String get weatherHomeLabel => 'Lieu de résidence, p. ex. Kiel';

  @override
  String get weatherIntro =>
      'Tous les services météo sont gratuits et sans clé. Les données maritimes (vagues, température de l’eau) viennent toujours d’Open-Meteo.';

  @override
  String get weatherKindBrightSkyDetail =>
      'Données du service météorologique allemand';

  @override
  String get weatherKindMetNorwayDetail =>
      'Service météorologique norvégien, mondial';

  @override
  String get weatherKindOpenMeteoDetail => 'Par défaut, mondial';

  @override
  String weatherNotFound(String name) {
    return 'Lieu « $name » introuvable.';
  }

  @override
  String get weatherSearchFailed =>
      'Recherche de lieu injoignable, réessayez plus tard.';

  @override
  String get weatherSetupDetail =>
      'Choisir un service, définir le lieu pour « météo ici »';

  @override
  String get weatherSetupTitle => 'Service météo et lieu de résidence';

  @override
  String get weatherTitle => 'Météo et mer';

  @override
  String get webSearchAddress => 'Adresse, p. ex. https://search.example.org';

  @override
  String get webSearchAddressMissing =>
      'Veuillez indiquer l’adresse de l’instance.';

  @override
  String get webSearchApiKey => 'Clé API';

  @override
  String get webSearchIntro =>
      'Sans service de recherche, Wendelin ne peut lire que les pages dont vous donnez l’adresse.';

  @override
  String get webSearchKeyMissing => 'Veuillez saisir la clé API.';

  @override
  String get webSearchKeySaved =>
      'Clé enregistrée – laisser vide pour la conserver';

  @override
  String get webSearchNone => 'Aucun service de recherche';

  @override
  String get webSearchOwnInstance => 'SearXNG (instance personnelle)';

  @override
  String get webSearchTitle => 'Recherche web';
}
