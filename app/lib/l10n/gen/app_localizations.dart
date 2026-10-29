import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('fr'),
  ];

  /// No description provided for @devArchiveDelete.
  ///
  /// In de, this message translates to:
  /// **'Archiv löschen'**
  String get devArchiveDelete;

  /// No description provided for @devArchiveDeleteMessage.
  ///
  /// In de, this message translates to:
  /// **'Alle gesammelten Weckwort-Aufnahmen ({cases} Einträge, {size}) werden gelöscht. Das lässt sich nicht rückgängig machen.'**
  String devArchiveDeleteMessage(int cases, String size);

  /// No description provided for @devArchiveDeleteTitle.
  ///
  /// In de, this message translates to:
  /// **'Archiv löschen?'**
  String get devArchiveDeleteTitle;

  /// No description provided for @devArchiveDeleteToo.
  ///
  /// In de, this message translates to:
  /// **'Mitlöschen'**
  String get devArchiveDeleteToo;

  /// No description provided for @devArchiveDeleted.
  ///
  /// In de, this message translates to:
  /// **'Archiv gelöscht'**
  String get devArchiveDeleted;

  /// No description provided for @devArchiveEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Einträge'**
  String get devArchiveEmpty;

  /// No description provided for @devArchiveKeep.
  ///
  /// In de, this message translates to:
  /// **'Behalten'**
  String get devArchiveKeep;

  /// No description provided for @devArchiveOffMessage.
  ///
  /// In de, this message translates to:
  /// **'Die kurzlebigen Aufnahmen sind gelöscht. Das Weckwort-Archiv ({cases} Einträge, {size}) kann bleiben oder mit gelöscht werden.'**
  String devArchiveOffMessage(int cases, String size);

  /// No description provided for @devArchiveOffTitle.
  ///
  /// In de, this message translates to:
  /// **'Weckwort-Archiv mitlöschen?'**
  String get devArchiveOffTitle;

  /// No description provided for @devArchiveSummary.
  ///
  /// In de, this message translates to:
  /// **'{cases} Einträge, {size}'**
  String devArchiveSummary(int cases, String size);

  /// No description provided for @devArchiveTitle.
  ///
  /// In de, this message translates to:
  /// **'Weckwort-Archiv'**
  String get devArchiveTitle;

  /// No description provided for @agentNoticeCancelled.
  ///
  /// In de, this message translates to:
  /// **'Abgebrochen.'**
  String get agentNoticeCancelled;

  /// No description provided for @agentNoticeGpuFailed.
  ///
  /// In de, this message translates to:
  /// **'GPU-Prüfung fehlgeschlagen. Details im Prüfprotokoll.'**
  String get agentNoticeGpuFailed;

  /// No description provided for @agentNoticeGpuNoEvidence.
  ///
  /// In de, this message translates to:
  /// **'Dieses Modell liefert keinen GPU-Nachweis. Tippe auf Ohne GPU-Prüfung senden.'**
  String get agentNoticeGpuNoEvidence;

  /// No description provided for @agentNoticeProfileBroken.
  ///
  /// In de, this message translates to:
  /// **'Provider-Profil fehlerhaft: {e}'**
  String agentNoticeProfileBroken(Object e);

  /// No description provided for @agentNoticeRecheckFailed.
  ///
  /// In de, this message translates to:
  /// **'Die neue Prüfung ist nicht bestanden. Details im Prüfprotokoll.'**
  String get agentNoticeRecheckFailed;

  /// No description provided for @agentNoticeRequestEmpty.
  ///
  /// In de, this message translates to:
  /// **'Die Anfrage ist leer.'**
  String get agentNoticeRequestEmpty;

  /// No description provided for @agentNoticeRequestRunning.
  ///
  /// In de, this message translates to:
  /// **'Es läuft schon eine Anfrage.'**
  String get agentNoticeRequestRunning;

  /// No description provided for @agentNoticeSetupFirst.
  ///
  /// In de, this message translates to:
  /// **'Bitte zuerst einen Provider einrichten.'**
  String get agentNoticeSetupFirst;

  /// No description provided for @agentNoticeStartFailed.
  ///
  /// In de, this message translates to:
  /// **'Die Anfrage konnte nicht starten.'**
  String get agentNoticeStartFailed;

  /// No description provided for @agentNoticeUndoFailed.
  ///
  /// In de, this message translates to:
  /// **'Rückgängig hat nicht geklappt: {e}'**
  String agentNoticeUndoFailed(Object e);

  /// No description provided for @assistantAnotherService.
  ///
  /// In de, this message translates to:
  /// **'einen anderen Dienst'**
  String get assistantAnotherService;

  /// No description provided for @assistantChangeInAndroid.
  ///
  /// In de, this message translates to:
  /// **'In Android ändern'**
  String get assistantChangeInAndroid;

  /// No description provided for @assistantDefaultHint.
  ///
  /// In de, this message translates to:
  /// **'Langer Druck auf die Power-Taste oder die Assistenten-Geste öffnet Wendelin über jeder App.'**
  String get assistantDefaultHint;

  /// No description provided for @assistantDefaultTitle.
  ///
  /// In de, this message translates to:
  /// **'Standard-Assistent'**
  String get assistantDefaultTitle;

  /// No description provided for @assistantInactiveDefault.
  ///
  /// In de, this message translates to:
  /// **'Android verweist für andere Apps auf Wendelin, die Spracherkennung ist aber aus (Schalter aus). Andere Apps bekommen dann einen Fehler.'**
  String get assistantInactiveDefault;

  /// No description provided for @assistantInactiveNotDefault.
  ///
  /// In de, this message translates to:
  /// **'Android verweist für andere Apps auf Wendelin, die Spracherkennung ist aber aus: Wendelin ist nicht Standard-Assistent. Andere Apps bekommen dann einen Fehler.'**
  String get assistantInactiveNotDefault;

  /// No description provided for @assistantIsDefault.
  ///
  /// In de, this message translates to:
  /// **'Wendelin ist Standard-Assistent'**
  String get assistantIsDefault;

  /// No description provided for @assistantNameHint.
  ///
  /// In de, this message translates to:
  /// **'Name und Persönlichkeit gehen als Teil der Anweisungen an das Modell.'**
  String get assistantNameHint;

  /// No description provided for @assistantNameLabel.
  ///
  /// In de, this message translates to:
  /// **'Wie soll Wendelin dich nennen?'**
  String get assistantNameLabel;

  /// No description provided for @assistantNotAvailable.
  ///
  /// In de, this message translates to:
  /// **'Auf diesem Gerät nicht verfügbar'**
  String get assistantNotAvailable;

  /// No description provided for @assistantNotDefault.
  ///
  /// In de, this message translates to:
  /// **'Nicht als Standard-Assistent gesetzt'**
  String get assistantNotDefault;

  /// No description provided for @assistantOfferRecognizer.
  ///
  /// In de, this message translates to:
  /// **'Als Spracherkennung für andere Apps anbieten'**
  String get assistantOfferRecognizer;

  /// No description provided for @assistantOfferRecognizerUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Als Spracherkennung für andere Apps anbieten, {reason}'**
  String assistantOfferRecognizerUnavailable(String reason);

  /// No description provided for @assistantOtherForNowDefault.
  ///
  /// In de, this message translates to:
  /// **'Android nutzt für andere Apps derzeit {app}. Ob Android nach dem Einschalten zu Wendelin wechselt, hängt vom Gerät ab.'**
  String assistantOtherForNowDefault(String app);

  /// No description provided for @assistantOtherForNowNotDefault.
  ///
  /// In de, this message translates to:
  /// **'Android nutzt für andere Apps derzeit {app}. Das kann sich ändern, sobald Wendelin Standard-Assistent ist.'**
  String assistantOtherForNowNotDefault(String app);

  /// No description provided for @assistantOtherRecognizer.
  ///
  /// In de, this message translates to:
  /// **'Android nutzt für andere Apps {app}. Das lässt sich auf diesem Gerät nicht umstellen.'**
  String assistantOtherRecognizer(String app);

  /// No description provided for @assistantPersonaLabel.
  ///
  /// In de, this message translates to:
  /// **'Persönlichkeit, z. B. „antworte knapp und locker“'**
  String get assistantPersonaLabel;

  /// No description provided for @assistantRecognizerActiveDetail.
  ///
  /// In de, this message translates to:
  /// **'Android nutzt Wendelin für die Spracheingabe anderer Apps. Whisper erkennt auf dem Gerät, Aufnahmen werden nicht gespeichert.'**
  String get assistantRecognizerActiveDetail;

  /// No description provided for @assistantRecognizerActiveHint.
  ///
  /// In de, this message translates to:
  /// **'Android nutzt Wendelin für die Spracheingabe anderer Apps.'**
  String get assistantRecognizerActiveHint;

  /// No description provided for @assistantRecognizerUnknownDetail.
  ///
  /// In de, this message translates to:
  /// **'Solange Wendelin Standard-Assistent ist, können andere Apps die Spracheingabe nutzen. Whisper erkennt auf dem Gerät, Aufnahmen werden nicht gespeichert.'**
  String get assistantRecognizerUnknownDetail;

  /// No description provided for @assistantSetDefault.
  ///
  /// In de, this message translates to:
  /// **'Als Standard-Assistent setzen'**
  String get assistantSetDefault;

  /// No description provided for @assistantSetLabel.
  ///
  /// In de, this message translates to:
  /// **'gesetzt'**
  String get assistantSetLabel;

  /// No description provided for @assistantSwitchHint.
  ///
  /// In de, this message translates to:
  /// **'Wechselst du später zu einem anderen Assistenten (oder „Keiner“), antwortet die Spracherkennung von Wendelin anderen Apps nicht mehr. Wähle die Spracheingabe dann in den Android-Einstellungen neu, meist unter Apps → Standard-Apps → Digitaler Assistent.'**
  String get assistantSwitchHint;

  /// No description provided for @conversationOfferHint.
  ///
  /// In de, this message translates to:
  /// **'Das lässt sich jederzeit unter Einstellungen → Sprache ändern.'**
  String get conversationOfferHint;

  /// No description provided for @conversationOfferQuestion.
  ///
  /// In de, this message translates to:
  /// **'Soll ich nach meinen Antworten standardmäßig weiter zuhören?'**
  String get conversationOfferQuestion;

  /// No description provided for @reducerBudgetUsed.
  ///
  /// In de, this message translates to:
  /// **'Budget von {name}: {spent} von {budget} verbraucht.'**
  String reducerBudgetUsed(String name, String spent, String budget);

  /// No description provided for @reducerHandedOver.
  ///
  /// In de, this message translates to:
  /// **'an {name} übergeben'**
  String reducerHandedOver(String name);

  /// No description provided for @reducerSpokenFallback.
  ///
  /// In de, this message translates to:
  /// **'Vorgelesen wurde die angezeigte Fassung.'**
  String get reducerSpokenFallback;

  /// No description provided for @reducerVerificationFailed.
  ///
  /// In de, this message translates to:
  /// **'Die Antwort des Anbieters konnte nicht geprüft werden.'**
  String get reducerVerificationFailed;

  /// No description provided for @attCheckFailed.
  ///
  /// In de, this message translates to:
  /// **'Prüfung fehlgeschlagen'**
  String get attCheckFailed;

  /// No description provided for @attChecking.
  ///
  /// In de, this message translates to:
  /// **'wird geprüft'**
  String get attChecking;

  /// No description provided for @attE2eeKeyNote.
  ///
  /// In de, this message translates to:
  /// **'Alle Inhalte werden mit diesem geprüften Schlüssel verschlüsselt. Die Verschlüsselung endet im Gateway des Anbieters (geprüfte Enklave), nicht im Modell selbst. Bei NEAR AI endet sie im geprüften Modell. Bei Tinfoil endet sie im geprüften Router, der sie an das Modell weitergibt.'**
  String get attE2eeKeyNote;

  /// No description provided for @attExplainAccept.
  ///
  /// In de, this message translates to:
  /// **'Akzeptieren'**
  String get attExplainAccept;

  /// No description provided for @attExplainChecked.
  ///
  /// In de, this message translates to:
  /// **'Geprüft wird: {what}'**
  String attExplainChecked(String what);

  /// No description provided for @attExplainIntro.
  ///
  /// In de, this message translates to:
  /// **'Was Wendelin prüft, was dabei herauskam und was das für deine Sicherheit heißt.'**
  String get attExplainIntro;

  /// No description provided for @attExplainMeaning.
  ///
  /// In de, this message translates to:
  /// **'Bedeutung: {v}'**
  String attExplainMeaning(String v);

  /// No description provided for @attExplainRestrictionsDetail.
  ///
  /// In de, this message translates to:
  /// **'{v}: nur protokolliert. Wenn du das akzeptierst, zeigt der Chat dafür keinen Hinweis mehr.'**
  String attExplainRestrictionsDetail(String v);

  /// No description provided for @attExplainRestrictionsTitle.
  ///
  /// In de, this message translates to:
  /// **'Einschränkungen dieses Anbieters'**
  String get attExplainRestrictionsTitle;

  /// No description provided for @attExplainResult.
  ///
  /// In de, this message translates to:
  /// **'Ergebnis: {detail}'**
  String attExplainResult(String detail);

  /// No description provided for @attExplainStageLine.
  ///
  /// In de, this message translates to:
  /// **'{label} · {result}'**
  String attExplainStageLine(String label, String result);

  /// No description provided for @attExplainTitle.
  ///
  /// In de, this message translates to:
  /// **'Details zur Prüfung'**
  String get attExplainTitle;

  /// No description provided for @attFailedText.
  ///
  /// In de, this message translates to:
  /// **'Die Antwort konnte nicht als unverändert aus der geprüften Umgebung bestätigt werden, zum Beispiel wegen eines Signaturfehlers oder abweichender Prüfsummen. Das kann auf eine Manipulation hindeuten. Vertraue der Antwort nicht. Der Anbieter ist gesperrt, bis du ihn neu prüfst.'**
  String get attFailedText;

  /// No description provided for @attFinishBudgetLabel.
  ///
  /// In de, this message translates to:
  /// **'Budget pro Monat in \$ (optional)'**
  String get attFinishBudgetLabel;

  /// No description provided for @attFinishImagesNo.
  ///
  /// In de, this message translates to:
  /// **'✕ Bilder'**
  String get attFinishImagesNo;

  /// No description provided for @attFinishImagesYes.
  ///
  /// In de, this message translates to:
  /// **'✓ Bilder'**
  String get attFinishImagesYes;

  /// No description provided for @attFinishModelChecked.
  ///
  /// In de, this message translates to:
  /// **'Modell geprüft'**
  String get attFinishModelChecked;

  /// No description provided for @attFinishPercentOfBudget.
  ///
  /// In de, this message translates to:
  /// **'{v} % des Budgets'**
  String attFinishPercentOfBudget(int v);

  /// No description provided for @attFinishPrivacyLevel.
  ///
  /// In de, this message translates to:
  /// **'Datenschutzstufe'**
  String get attFinishPrivacyLevel;

  /// No description provided for @attFinishRestrictionNote.
  ///
  /// In de, this message translates to:
  /// **'{v}. Das liefert der Anbieter nicht oder Wendelin prüft es nicht, es wird nur protokolliert. Mit „Speichern“ akzeptierst du das. Sobald etwas Neues dazukommt, weist Wendelin erneut darauf hin. Mehr unter „Details“.'**
  String attFinishRestrictionNote(String v);

  /// No description provided for @attFinishTeeYes.
  ///
  /// In de, this message translates to:
  /// **'✓ TEE'**
  String get attFinishTeeYes;

  /// No description provided for @attFinishToolsNo.
  ///
  /// In de, this message translates to:
  /// **'✕ Tools'**
  String get attFinishToolsNo;

  /// No description provided for @attFinishToolsYes.
  ///
  /// In de, this message translates to:
  /// **'✓ Tools'**
  String get attFinishToolsYes;

  /// No description provided for @attFinishWarnFrom.
  ///
  /// In de, this message translates to:
  /// **'Warnen ab'**
  String get attFinishWarnFrom;

  /// No description provided for @attFloorCorruptText.
  ///
  /// In de, this message translates to:
  /// **'Die gespeicherte Untergrenze für die Release-Version dieses Anbieters ist beschädigt. Ohne sie lässt sich ein Rückschritt auf ältere, unsichere Software nicht ausschließen. Deshalb bleibt die Prüfung gesperrt, ein erneutes Prüfen ändert daran nichts. Sende nichts Vertrauliches. Abhilfe schafft nur das Zurücksetzen der App-Daten. Danach wird der erste Kontakt wieder ohne Rückschrittschutz geprüft.'**
  String get attFloorCorruptText;

  /// No description provided for @attFloorCorruptTitle.
  ///
  /// In de, this message translates to:
  /// **'Gespeicherter Rückschrittschutz beschädigt'**
  String get attFloorCorruptTitle;

  /// No description provided for @attGpuFailedLabel.
  ///
  /// In de, this message translates to:
  /// **'GPU-Prüfung fehlgeschlagen'**
  String get attGpuFailedLabel;

  /// No description provided for @attGpuFailedText.
  ///
  /// In de, this message translates to:
  /// **'Die GPU-Prüfung über NVIDIA ist fehlgeschlagen.{v} Die nächste Anfrage an dieses Modell wird vorher geprüft.'**
  String attGpuFailedText(String v);

  /// No description provided for @attGpuFailedTitle.
  ///
  /// In de, this message translates to:
  /// **'GPU-Prüfung fehlgeschlagen'**
  String get attGpuFailedTitle;

  /// No description provided for @attGpuUnavailableLabel.
  ///
  /// In de, this message translates to:
  /// **'GPU-Prüfung nicht möglich'**
  String get attGpuUnavailableLabel;

  /// No description provided for @attGpuUnavailableText.
  ///
  /// In de, this message translates to:
  /// **'Die GPU-Prüfung über NVIDIA war nicht möglich.{v} Die nächste Anfrage an dieses Modell wird vorher geprüft.'**
  String attGpuUnavailableText(String v);

  /// No description provided for @attGpuUnavailableTitle.
  ///
  /// In de, this message translates to:
  /// **'GPU-Prüfung nicht möglich'**
  String get attGpuUnavailableTitle;

  /// No description provided for @attLogCommit.
  ///
  /// In de, this message translates to:
  /// **'Commit'**
  String get attLogCommit;

  /// No description provided for @attLogKeysetDigest.
  ///
  /// In de, this message translates to:
  /// **'Keyset-Digest'**
  String get attLogKeysetDigest;

  /// No description provided for @attLogModel.
  ///
  /// In de, this message translates to:
  /// **'Modell'**
  String get attLogModel;

  /// No description provided for @attLogNewRestriction.
  ///
  /// In de, this message translates to:
  /// **'Neue Einschränkung'**
  String get attLogNewRestriction;

  /// No description provided for @attLogNewRestrictionDetail.
  ///
  /// In de, this message translates to:
  /// **'{v}: nur protokolliert und noch nicht von dir akzeptiert. Unter „Details“ kannst du das ansehen und akzeptieren.'**
  String attLogNewRestrictionDetail(String v);

  /// No description provided for @attLogNoEntry.
  ///
  /// In de, this message translates to:
  /// **'Zu dieser Antwort gibt es noch keinen Eintrag.'**
  String get attLogNoEntry;

  /// No description provided for @attLogParticulars.
  ///
  /// In de, this message translates to:
  /// **'Angaben'**
  String get attLogParticulars;

  /// No description provided for @attLogProvider.
  ///
  /// In de, this message translates to:
  /// **'Anbieter'**
  String get attLogProvider;

  /// No description provided for @attLogReasonCode.
  ///
  /// In de, this message translates to:
  /// **'Grundcode'**
  String get attLogReasonCode;

  /// No description provided for @attLogReceiptId.
  ///
  /// In de, this message translates to:
  /// **'Quittungs-ID'**
  String get attLogReceiptId;

  /// No description provided for @attLogRecheck.
  ///
  /// In de, this message translates to:
  /// **'Neu prüfen'**
  String get attLogRecheck;

  /// No description provided for @attLogRecheckFailed.
  ///
  /// In de, this message translates to:
  /// **'Die neue Prüfung ist nicht bestanden.'**
  String get attLogRecheckFailed;

  /// No description provided for @attLogRechecked.
  ///
  /// In de, this message translates to:
  /// **'Anbieter neu geprüft, die Sperre ist aufgehoben.'**
  String get attLogRechecked;

  /// No description provided for @attLogResultPerStep.
  ///
  /// In de, this message translates to:
  /// **'Ergebnis je Stufe'**
  String get attLogResultPerStep;

  /// No description provided for @attLogScreenCommitLine.
  ///
  /// In de, this message translates to:
  /// **'Commit {repoCommit}'**
  String attLogScreenCommitLine(String repoCommit);

  /// No description provided for @attLogScreenDeleteBody.
  ///
  /// In de, this message translates to:
  /// **'Alle Einträge des Prüfprotokolls werden gelöscht. Das lässt sich nicht rückgängig machen.'**
  String get attLogScreenDeleteBody;

  /// No description provided for @attLogScreenDeleteLog.
  ///
  /// In de, this message translates to:
  /// **'Prüfprotokoll löschen'**
  String get attLogScreenDeleteLog;

  /// No description provided for @attLogScreenDeleteTitle.
  ///
  /// In de, this message translates to:
  /// **'Prüfprotokoll löschen?'**
  String get attLogScreenDeleteTitle;

  /// No description provided for @attLogScreenDeleted.
  ///
  /// In de, this message translates to:
  /// **'Gelöscht.'**
  String get attLogScreenDeleted;

  /// No description provided for @attLogScreenExportJson.
  ///
  /// In de, this message translates to:
  /// **'Als JSON exportieren'**
  String get attLogScreenExportJson;

  /// No description provided for @attLogScreenFilterAll.
  ///
  /// In de, this message translates to:
  /// **'Alle'**
  String get attLogScreenFilterAll;

  /// No description provided for @attLogScreenFilterGreen.
  ///
  /// In de, this message translates to:
  /// **'Geprüft'**
  String get attLogScreenFilterGreen;

  /// No description provided for @attLogScreenFilterRed.
  ///
  /// In de, this message translates to:
  /// **'Fehlgeschlagen'**
  String get attLogScreenFilterRed;

  /// No description provided for @attLogScreenFilterUnconfirmed.
  ///
  /// In de, this message translates to:
  /// **'Nicht bestätigt'**
  String get attLogScreenFilterUnconfirmed;

  /// No description provided for @attLogScreenFilterYellow.
  ///
  /// In de, this message translates to:
  /// **'Wird geprüft'**
  String get attLogScreenFilterYellow;

  /// No description provided for @attLogScreenGpuTitle.
  ///
  /// In de, this message translates to:
  /// **'GPU · {v}'**
  String attLogScreenGpuTitle(String v);

  /// No description provided for @attLogScreenIntro.
  ///
  /// In de, this message translates to:
  /// **'Wendelin prüft Anbieter mit geschützter Umgebung (TEE) und jede Antwort. Hier steht, was geprüft wurde. Nie Inhalte, nur Ids, Prüfsummen und Ergebnisse.'**
  String get attLogScreenIntro;

  /// No description provided for @attLogScreenNoEntries.
  ///
  /// In de, this message translates to:
  /// **'Keine Einträge.'**
  String get attLogScreenNoEntries;

  /// No description provided for @attLogScreenReceiptTitle.
  ///
  /// In de, this message translates to:
  /// **'{v} · {providerName}'**
  String attLogScreenReceiptTitle(String v, String providerName);

  /// No description provided for @attLogScreenRecheckAttest.
  ///
  /// In de, this message translates to:
  /// **'Neu attestieren'**
  String get attLogScreenRecheckAttest;

  /// No description provided for @attLogScreenRechecked.
  ///
  /// In de, this message translates to:
  /// **'Neu attestiert, eine Sperre ist aufgehoben.'**
  String get attLogScreenRechecked;

  /// No description provided for @attLogScreenSessionGreen.
  ///
  /// In de, this message translates to:
  /// **'Sitzung geprüft'**
  String get attLogScreenSessionGreen;

  /// No description provided for @attLogScreenSessionRed.
  ///
  /// In de, this message translates to:
  /// **'Sitzung fehlgeschlagen'**
  String get attLogScreenSessionRed;

  /// No description provided for @attLogScreenSessionTitle.
  ///
  /// In de, this message translates to:
  /// **'Sitzung · {providerName}'**
  String attLogScreenSessionTitle(String providerName);

  /// No description provided for @attLogScreenSessionUnconfirmed.
  ///
  /// In de, this message translates to:
  /// **'Sitzung nicht bestätigt'**
  String get attLogScreenSessionUnconfirmed;

  /// No description provided for @attLogScreenSessionYellow.
  ///
  /// In de, this message translates to:
  /// **'Sitzung nicht prüfbar'**
  String get attLogScreenSessionYellow;

  /// No description provided for @attLogTime.
  ///
  /// In de, this message translates to:
  /// **'Zeit'**
  String get attLogTime;

  /// No description provided for @attLogTitle.
  ///
  /// In de, this message translates to:
  /// **'Prüfprotokoll'**
  String get attLogTitle;

  /// No description provided for @attLogTitle2.
  ///
  /// In de, this message translates to:
  /// **'Prüfprotokoll'**
  String get attLogTitle2;

  /// No description provided for @attMismatchText.
  ///
  /// In de, this message translates to:
  /// **'Der Nachweis der Sitzung passt nicht zur signierten Quittung dieser Antwort. Vertraue der Antwort nicht. Der Anbieter ist gesperrt, bis du ihn neu prüfst.'**
  String get attMismatchText;

  /// No description provided for @attMismatchTitle.
  ///
  /// In de, this message translates to:
  /// **'Möglicher Manipulationsversuch'**
  String get attMismatchTitle;

  /// No description provided for @attReasonLead.
  ///
  /// In de, this message translates to:
  /// **' Grund: {reason}{v}'**
  String attReasonLead(String reason, String v);

  /// No description provided for @attReceiptMissing.
  ///
  /// In de, this message translates to:
  /// **'Quittung fehlt'**
  String get attReceiptMissing;

  /// No description provided for @attReceiptMissingText.
  ///
  /// In de, this message translates to:
  /// **'Der Anbieter hat zu dieser Antwort keine Quittungs-Kennung geliefert.'**
  String get attReceiptMissingText;

  /// No description provided for @attReceiptNotFound.
  ///
  /// In de, this message translates to:
  /// **'Quittung nicht gefunden'**
  String get attReceiptNotFound;

  /// No description provided for @attReceiptNotFoundText.
  ///
  /// In de, this message translates to:
  /// **'Der Anbieter kennt die Quittung dieser Antwort nicht (noch nicht geschrieben oder abgelaufen).'**
  String get attReceiptNotFoundText;

  /// No description provided for @attReceiptRejectedLabel.
  ///
  /// In de, this message translates to:
  /// **'Quittung abgelehnt'**
  String get attReceiptRejectedLabel;

  /// No description provided for @attReceiptRejectedText.
  ///
  /// In de, this message translates to:
  /// **'Der Anbieter hat den Abruf der Quittung abgelehnt (zum Beispiel wegen zu vieler Anfragen). Die Antwort ist nicht bestätigt, es gibt aber keinen Hinweis auf eine Manipulation. Prüfe den Anbieter neu.'**
  String get attReceiptRejectedText;

  /// No description provided for @attReceiptRejectedTitle.
  ///
  /// In de, this message translates to:
  /// **'Quittungsabruf vom Anbieter abgelehnt'**
  String get attReceiptRejectedTitle;

  /// No description provided for @attReceiptUnreachable.
  ///
  /// In de, this message translates to:
  /// **'Quittung nicht erreichbar'**
  String get attReceiptUnreachable;

  /// No description provided for @attReceiptUnreachableText.
  ///
  /// In de, this message translates to:
  /// **'Die Quittung dieser Antwort konnte wegen eines Netz- oder Serverfehlers nicht abgerufen werden.'**
  String get attReceiptUnreachableText;

  /// No description provided for @attRelaunchText.
  ///
  /// In de, this message translates to:
  /// **'Der Hersteller empfiehlt dem Betreiber, die geschützte Umgebung neu zu starten, damit ein Sicherheits-Update wirksam wird. Das ist kein Hinweis auf eine Manipulation. Prüfe später erneut.'**
  String get attRelaunchText;

  /// No description provided for @attRelaunchTitle.
  ///
  /// In de, this message translates to:
  /// **'Neustart der TEE beim Betreiber empfohlen'**
  String get attRelaunchTitle;

  /// No description provided for @attResponseWord.
  ///
  /// In de, this message translates to:
  /// **'Antwort'**
  String get attResponseWord;

  /// No description provided for @attRestrictionOpen.
  ///
  /// In de, this message translates to:
  /// **'geprüft, neue Einschränkung'**
  String get attRestrictionOpen;

  /// No description provided for @attResultInfo.
  ///
  /// In de, this message translates to:
  /// **'nur protokolliert'**
  String get attResultInfo;

  /// No description provided for @attResultUnavailable.
  ///
  /// In de, this message translates to:
  /// **'nicht abrufbar'**
  String get attResultUnavailable;

  /// No description provided for @attResultWarn.
  ///
  /// In de, this message translates to:
  /// **'Hinweis'**
  String get attResultWarn;

  /// No description provided for @attRevokedText.
  ///
  /// In de, this message translates to:
  /// **'Der Hersteller hat die Hardware-Plattform des Betreibers als unsicher zurückgezogen. Sende nichts Vertrauliches, bis der Betreiber sie ersetzt hat.'**
  String get attRevokedText;

  /// No description provided for @attRevokedTitle.
  ///
  /// In de, this message translates to:
  /// **'Plattform des Betreibers zurückgezogen'**
  String get attRevokedTitle;

  /// No description provided for @attRollbackText.
  ///
  /// In de, this message translates to:
  /// **'Der Anbieter meldet eine ältere Software-Version als die, die hier schon einmal geprüft wurde. Das kann ein Zurückspielen alter, verwundbarer Software oder alter Daten sein. Die Anfrage wurde nicht gesendet. Sende nichts Vertrauliches und prüfe später erneut.'**
  String get attRollbackText;

  /// No description provided for @attRollbackTitle.
  ///
  /// In de, this message translates to:
  /// **'Ältere Software-Version als zuvor geprüft'**
  String get attRollbackTitle;

  /// No description provided for @attSBindHpke.
  ///
  /// In de, this message translates to:
  /// **'Verschlüsselungsschlüssel gebunden'**
  String get attSBindHpke;

  /// No description provided for @attSCompose.
  ///
  /// In de, this message translates to:
  /// **'Compose-Hash'**
  String get attSCompose;

  /// No description provided for @attSE2eeKey.
  ///
  /// In de, this message translates to:
  /// **'E2EE-Schlüssel geprüft'**
  String get attSE2eeKey;

  /// No description provided for @attSE2eeKeyset.
  ///
  /// In de, this message translates to:
  /// **'Schlüsselsatz der Antwort'**
  String get attSE2eeKeyset;

  /// No description provided for @attSE2eeRequest.
  ///
  /// In de, this message translates to:
  /// **'Verschlüsselung der Anfrage'**
  String get attSE2eeRequest;

  /// No description provided for @attSE2eeResponse.
  ///
  /// In de, this message translates to:
  /// **'Entschlüsselung der Antwort'**
  String get attSE2eeResponse;

  /// No description provided for @attSEventLog.
  ///
  /// In de, this message translates to:
  /// **'Ereignisprotokoll'**
  String get attSEventLog;

  /// No description provided for @attSFreshness.
  ///
  /// In de, this message translates to:
  /// **'Frische'**
  String get attSFreshness;

  /// No description provided for @attSGateway.
  ///
  /// In de, this message translates to:
  /// **'Gateway des Anbieters'**
  String get attSGateway;

  /// No description provided for @attSGpu.
  ///
  /// In de, this message translates to:
  /// **'GPU-Evidenz'**
  String get attSGpu;

  /// No description provided for @attSGpuEvidence.
  ///
  /// In de, this message translates to:
  /// **'GPU-Nachweis des Anbieters'**
  String get attSGpuEvidence;

  /// No description provided for @attSKeysetDigest.
  ///
  /// In de, this message translates to:
  /// **'Schlüsselsatz (Digest)'**
  String get attSKeysetDigest;

  /// No description provided for @attSKeysetSignature.
  ///
  /// In de, this message translates to:
  /// **'Schlüsselsatz-Signatur'**
  String get attSKeysetSignature;

  /// No description provided for @attSMeasurement.
  ///
  /// In de, this message translates to:
  /// **'Messwert = Release'**
  String get attSMeasurement;

  /// No description provided for @attSNoReceipt.
  ///
  /// In de, this message translates to:
  /// **'Quittung je Antwort'**
  String get attSNoReceipt;

  /// No description provided for @attSNonce.
  ///
  /// In de, this message translates to:
  /// **'Nonce gebunden'**
  String get attSNonce;

  /// No description provided for @attSProvenance.
  ///
  /// In de, this message translates to:
  /// **'Herkunft (Commit)'**
  String get attSProvenance;

  /// No description provided for @attSQuote.
  ///
  /// In de, this message translates to:
  /// **'TDX-Quote (DCAP)'**
  String get attSQuote;

  /// No description provided for @attSReceiptBinding.
  ///
  /// In de, this message translates to:
  /// **'Quittung an Sitzung gebunden'**
  String get attSReceiptBinding;

  /// No description provided for @attSReceiptEvents.
  ///
  /// In de, this message translates to:
  /// **'Quittungs-Ereignisse'**
  String get attSReceiptEvents;

  /// No description provided for @attSReceiptFetch.
  ///
  /// In de, this message translates to:
  /// **'Quittung abgerufen'**
  String get attSReceiptFetch;

  /// No description provided for @attSReceiptRequest.
  ///
  /// In de, this message translates to:
  /// **'Hash der Anfrage'**
  String get attSReceiptRequest;

  /// No description provided for @attSReceiptResponse.
  ///
  /// In de, this message translates to:
  /// **'Hash der Antwort'**
  String get attSReceiptResponse;

  /// No description provided for @attSReceiptSignature.
  ///
  /// In de, this message translates to:
  /// **'Quittungs-Signatur'**
  String get attSReceiptSignature;

  /// No description provided for @attSReleaseFloor.
  ///
  /// In de, this message translates to:
  /// **'Kein Rückschritt'**
  String get attSReleaseFloor;

  /// No description provided for @attSSigstore.
  ///
  /// In de, this message translates to:
  /// **'Signiertes Release (Sigstore)'**
  String get attSSigstore;

  /// No description provided for @attSSnpChain.
  ///
  /// In de, this message translates to:
  /// **'AMD-Zertifikatskette'**
  String get attSSnpChain;

  /// No description provided for @attSSnpPolicy.
  ///
  /// In de, this message translates to:
  /// **'Prozessor-Richtlinie'**
  String get attSSnpPolicy;

  /// No description provided for @attSSnpReport.
  ///
  /// In de, this message translates to:
  /// **'AMD-Hardware-Nachweis'**
  String get attSSnpReport;

  /// No description provided for @attSTcb.
  ///
  /// In de, this message translates to:
  /// **'Plattform-Sicherheitsstand (TCB)'**
  String get attSTcb;

  /// No description provided for @attSTls.
  ///
  /// In de, this message translates to:
  /// **'TLS-Verbindung geprüft'**
  String get attSTls;

  /// No description provided for @attSUpstream.
  ///
  /// In de, this message translates to:
  /// **'Upstream-Prüfung'**
  String get attSUpstream;

  /// No description provided for @attSUpstreamTcb.
  ///
  /// In de, this message translates to:
  /// **'Upstream-Sicherheitsstand'**
  String get attSUpstreamTcb;

  /// No description provided for @attStagesCardAllPassed.
  ///
  /// In de, this message translates to:
  /// **'Alle {length} Stufen bestanden'**
  String attStagesCardAllPassed(int length);

  /// No description provided for @attStagesCardFirst.
  ///
  /// In de, this message translates to:
  /// **'Erste Attestierung'**
  String get attStagesCardFirst;

  /// No description provided for @attStagesCardNotPassed.
  ///
  /// In de, this message translates to:
  /// **'nicht bestanden'**
  String get attStagesCardNotPassed;

  /// No description provided for @attStagesCardSomePassed.
  ///
  /// In de, this message translates to:
  /// **'{failed} von {length} Stufen nicht bestanden: {v}'**
  String attStagesCardSomePassed(int failed, int length, String v);

  /// No description provided for @attStagesCardViewLog.
  ///
  /// In de, this message translates to:
  /// **'Prüfprotokoll ansehen'**
  String get attStagesCardViewLog;

  /// No description provided for @attStoredReason.
  ///
  /// In de, this message translates to:
  /// **' Grund: {text}{v}'**
  String attStoredReason(String text, String v);

  /// No description provided for @attSummaryGreen.
  ///
  /// In de, this message translates to:
  /// **'geprüft'**
  String get attSummaryGreen;

  /// No description provided for @attSummaryYellow.
  ///
  /// In de, this message translates to:
  /// **'ausstehend'**
  String get attSummaryYellow;

  /// No description provided for @attTcbText.
  ///
  /// In de, this message translates to:
  /// **'Die Hardware, auf der das Modell läuft, hat ein Sicherheits-Update des Herstellers noch nicht eingespielt. Das ist kein Hinweis auf eine Manipulation, schwächt aber den Schutz. Der Betreiber muss aktualisieren. Prüfe später erneut und sende bis dahin nichts Vertrauliches.'**
  String get attTcbText;

  /// No description provided for @attTcbTitle.
  ///
  /// In de, this message translates to:
  /// **'Sicherheits-Update beim Betreiber ausstehend'**
  String get attTcbTitle;

  /// No description provided for @attUnconfirmed.
  ///
  /// In de, this message translates to:
  /// **'nicht bestätigt'**
  String get attUnconfirmed;

  /// No description provided for @attUnconfirmedText.
  ///
  /// In de, this message translates to:
  /// **'{cause} Ob die Antwort aus der geprüften Umgebung stammt, ist unbestätigt. Es wurde aber auch kein Fehler festgestellt, der Anbieter bleibt nutzbar. Aktionen, die auf die geprüfte Antwort warten, laufen nicht. Prüfe den Anbieter neu.'**
  String attUnconfirmedText(String cause);

  /// No description provided for @checkStatusFailed.
  ///
  /// In de, this message translates to:
  /// **'fehlgeschlagen'**
  String get checkStatusFailed;

  /// No description provided for @checkStatusInfo.
  ///
  /// In de, this message translates to:
  /// **'nur protokolliert'**
  String get checkStatusInfo;

  /// No description provided for @checkStatusNeutral.
  ///
  /// In de, this message translates to:
  /// **'nicht bestätigt'**
  String get checkStatusNeutral;

  /// No description provided for @checkStatusOk.
  ///
  /// In de, this message translates to:
  /// **'geprüft'**
  String get checkStatusOk;

  /// No description provided for @checkStatusPending.
  ///
  /// In de, this message translates to:
  /// **'ausstehend'**
  String get checkStatusPending;

  /// No description provided for @gpuBlockNoEvidenceDetail.
  ///
  /// In de, this message translates to:
  /// **'Die Anfrage wurde nicht gesendet.'**
  String get gpuBlockNoEvidenceDetail;

  /// No description provided for @gpuBlockNotSent.
  ///
  /// In de, this message translates to:
  /// **'Nicht gesendet.{v}'**
  String gpuBlockNotSent(String v);

  /// No description provided for @gpuModeAfter.
  ///
  /// In de, this message translates to:
  /// **'Nachher'**
  String get gpuModeAfter;

  /// No description provided for @gpuModeAfterText.
  ///
  /// In de, this message translates to:
  /// **'Die Prüfung läuft nach der Antwort. Schlägt sie fehl, warnt dich eine Benachrichtigung, die Antwort wird rot markiert, und die nächsten Anfragen an dieses Modell prüfen vorher. Modelle ohne Nachweis bekommen nur einen Hinweis.'**
  String get gpuModeAfterText;

  /// No description provided for @gpuModeBefore.
  ///
  /// In de, this message translates to:
  /// **'Vorher'**
  String get gpuModeBefore;

  /// No description provided for @gpuModeBeforeText.
  ///
  /// In de, this message translates to:
  /// **'NVIDIA prüft die GPU-Nachweise, bevor deine Anfrage den Anbieter erreicht. Schlägt die Prüfung fehl oder liefert der Anbieter keinen Nachweis, wird nichts gesendet. Du kannst dann einmalig ohne GPU-Prüfung senden.'**
  String get gpuModeBeforeText;

  /// No description provided for @gpuModeOff.
  ///
  /// In de, this message translates to:
  /// **'Aus'**
  String get gpuModeOff;

  /// No description provided for @gpuModeOffText.
  ///
  /// In de, this message translates to:
  /// **'Standard. Wendelin prüft nur lokal, ob die GPU-Nachweise zu deiner Anfrage gehören. Kein Aufruf an NVIDIA.'**
  String get gpuModeOffText;

  /// No description provided for @gpuNoEvidenceFinishText.
  ///
  /// In de, this message translates to:
  /// **'{hint}. Das Modell bleibt nutzbar. Was Wendelin dann tut, bestimmt die GPU-Prüfung unten: „Aus“ nichts, „Nachher“ nur ein Hinweis, „Vorher“ sendet nichts, du kannst aber einmalig ohne GPU-Prüfung senden.'**
  String gpuNoEvidenceFinishText(String hint);

  /// No description provided for @gpuNoEvidenceFinishTitle.
  ///
  /// In de, this message translates to:
  /// **'Keine GPU-Prüfung möglich'**
  String get gpuNoEvidenceFinishTitle;

  /// No description provided for @gpuNoEvidenceHint.
  ///
  /// In de, this message translates to:
  /// **'Keine GPU-Prüfung möglich (Anbieter liefert keinen Nachweis)'**
  String get gpuNoEvidenceHint;

  /// No description provided for @gpuNoEvidenceMessage.
  ///
  /// In de, this message translates to:
  /// **'{name} liefert für dieses Modell keinen GPU-Nachweis, NVIDIA kann nichts prüfen. Weil die GPU-Prüfung auf „Vorher“ steht, wurde deine Anfrage nicht gesendet. Du kannst sie einmalig ohne GPU-Prüfung senden. Die übrigen Prüfungen bleiben aktiv.'**
  String gpuNoEvidenceMessage(String name);

  /// No description provided for @gpuNoEvidenceTitle.
  ///
  /// In de, this message translates to:
  /// **'Kein GPU-Nachweis'**
  String get gpuNoEvidenceTitle;

  /// No description provided for @gpuNotifyFailedText.
  ///
  /// In de, this message translates to:
  /// **'Die GPU-Prüfung der letzten Antwort von {name} ist fehlgeschlagen. Die nächste Anfrage prüft vorher. Details im Prüfprotokoll.'**
  String gpuNotifyFailedText(String name);

  /// No description provided for @gpuNotifyFailedTitle.
  ///
  /// In de, this message translates to:
  /// **'GPU-Prüfung fehlgeschlagen'**
  String get gpuNotifyFailedTitle;

  /// No description provided for @gpuSectionNote.
  ///
  /// In de, this message translates to:
  /// **'Für „Vorher“ und „Nachher“ ruft Wendelin den Dienst von NVIDIA (nras.attestation.nvidia.com) auf. Gesendet werden nur die Nachweise der GPU, keine Inhalte deiner Anfragen oder Antworten.'**
  String get gpuSectionNote;

  /// No description provided for @gpuSectionTitle.
  ///
  /// In de, this message translates to:
  /// **'GPU-Prüfung über NVIDIA'**
  String get gpuSectionTitle;

  /// No description provided for @gpuToolName.
  ///
  /// In de, this message translates to:
  /// **'GPU-Prüfung'**
  String get gpuToolName;

  /// No description provided for @shieldSemantics.
  ///
  /// In de, this message translates to:
  /// **'TEE-Prüfung: {label}'**
  String shieldSemantics(String label);

  /// No description provided for @shieldSemanticsTap.
  ///
  /// In de, this message translates to:
  /// **'TEE-Prüfung: {label}. Tippen für das Prüfprotokoll.'**
  String shieldSemanticsTap(String label);

  /// No description provided for @stageAgeInfo.
  ///
  /// In de, this message translates to:
  /// **'Das Alter wurde nur protokolliert.'**
  String get stageAgeInfo;

  /// No description provided for @stageAgePass.
  ///
  /// In de, this message translates to:
  /// **'Der Nachweis ist aktuell und kein alter Mitschnitt.'**
  String get stageAgePass;

  /// No description provided for @stageAgeWhat.
  ///
  /// In de, this message translates to:
  /// **'Wie alt der Nachweis ist.'**
  String get stageAgeWhat;

  /// No description provided for @stageBindHpkeInfo.
  ///
  /// In de, this message translates to:
  /// **'Der Schlüssel wurde nur protokolliert.'**
  String get stageBindHpkeInfo;

  /// No description provided for @stageBindHpkePass.
  ///
  /// In de, this message translates to:
  /// **'Nur der geprüfte Server kann die Anfrage lesen. Der Schlüssel stammt aus dem Nachweis, nicht aus einer ungeprüften Antwort.'**
  String get stageBindHpkePass;

  /// No description provided for @stageBindHpkeWhat.
  ///
  /// In de, this message translates to:
  /// **'Ob der Schlüssel, mit dem Wendelin deine Anfrage verschlüsselt, genau der ist, der im Hardware-Nachweis steht.'**
  String get stageBindHpkeWhat;

  /// No description provided for @stageComposeInfo.
  ///
  /// In de, this message translates to:
  /// **'Der Hash wurde protokolliert, aber nicht gegen eine Liste vertrauenswürdiger Werte verglichen.'**
  String get stageComposeInfo;

  /// No description provided for @stageComposePass.
  ///
  /// In de, this message translates to:
  /// **'Genau die erwarteten Programme laufen im Dienst.'**
  String get stageComposePass;

  /// No description provided for @stageComposeWhat.
  ///
  /// In de, this message translates to:
  /// **'Der Compose-Hash: eine Prüfsumme der Container-Beschreibung, also welche Programme im Dienst laufen.'**
  String get stageComposeWhat;

  /// No description provided for @stageE2eeKeyInfo.
  ///
  /// In de, this message translates to:
  /// **'Der Schlüssel wurde nur protokolliert.'**
  String get stageE2eeKeyInfo;

  /// No description provided for @stageE2eeKeyPass.
  ///
  /// In de, this message translates to:
  /// **'Nur die geprüfte Umgebung kann die Anfrage entschlüsseln. Bei manchen Anbietern endet die Verschlüsselung im Gateway, nicht im Modell selbst.'**
  String get stageE2eeKeyPass;

  /// No description provided for @stageE2eeKeyWhat.
  ///
  /// In de, this message translates to:
  /// **'Der Schlüssel, mit dem Wendelin deine Anfrage Ende-zu-Ende verschlüsselt, stammt aus dem Hardware-Nachweis.'**
  String get stageE2eeKeyWhat;

  /// No description provided for @stageE2eeRequestInfo.
  ///
  /// In de, this message translates to:
  /// **'Die Anfrage (oder Teile wie Tool-Aufrufe) sind nicht zusätzlich verschlüsselt, nur über die geprüfte Verbindung geschützt.'**
  String get stageE2eeRequestInfo;

  /// No description provided for @stageE2eeRequestPass.
  ///
  /// In de, this message translates to:
  /// **'Deine Anfrage ist unterwegs für Dritte unlesbar.'**
  String get stageE2eeRequestPass;

  /// No description provided for @stageE2eeRequestPinned.
  ///
  /// In de, this message translates to:
  /// **'Die Anfrage (oder Teile wie Tool-Aufrufe) sind nicht zusätzlich verschlüsselt, nur über die geprüfte Verbindung geschützt.'**
  String get stageE2eeRequestPinned;

  /// No description provided for @stageE2eeRequestUnpinned.
  ///
  /// In de, this message translates to:
  /// **'Die Anfrage (oder Teile wie Tool-Aufrufe) sind nicht zusätzlich verschlüsselt, und die Verbindung ist nicht an den Nachweis gebunden. Der Schutz ist dadurch schwächer.'**
  String get stageE2eeRequestUnpinned;

  /// No description provided for @stageE2eeRequestWhat.
  ///
  /// In de, this message translates to:
  /// **'Ob die Anfrage tatsächlich verschlüsselt gesendet wurde.'**
  String get stageE2eeRequestWhat;

  /// No description provided for @stageE2eeResponseInfo.
  ///
  /// In de, this message translates to:
  /// **'Die Entschlüsselung wurde nur protokolliert.'**
  String get stageE2eeResponseInfo;

  /// No description provided for @stageE2eeResponsePass.
  ///
  /// In de, this message translates to:
  /// **'Die Antwort kam unverändert aus der geprüften Umgebung.'**
  String get stageE2eeResponsePass;

  /// No description provided for @stageE2eeResponseWhat.
  ///
  /// In de, this message translates to:
  /// **'Ob die Antwort verschlüsselt ankam und entschlüsselt werden konnte.'**
  String get stageE2eeResponseWhat;

  /// No description provided for @stageEventLogInfo.
  ///
  /// In de, this message translates to:
  /// **'Das Ereignisprotokoll wurde nur protokolliert.'**
  String get stageEventLogInfo;

  /// No description provided for @stageEventLogPass.
  ///
  /// In de, this message translates to:
  /// **'Die gestartete Software ist lückenlos nachvollziehbar.'**
  String get stageEventLogPass;

  /// No description provided for @stageEventLogWhat.
  ///
  /// In de, this message translates to:
  /// **'Das Ereignisprotokoll des Starts: welche Software beim Hochfahren geladen wurde. Es muss zur Hardware-Messung passen.'**
  String get stageEventLogWhat;

  /// No description provided for @stageFailMeaning.
  ///
  /// In de, this message translates to:
  /// **'Die Prüfung ist fehlgeschlagen. Das kann ein Hinweis auf eine Manipulation oder einen Fehler beim Anbieter sein. Wendelin sendet dann nichts mehr an diesen Anbieter, bis du ihn neu prüfst.'**
  String get stageFailMeaning;

  /// No description provided for @stageGatewayInfo.
  ///
  /// In de, this message translates to:
  /// **'Der Gateway-Zustand wurde nur protokolliert.'**
  String get stageGatewayInfo;

  /// No description provided for @stageGatewayPass.
  ///
  /// In de, this message translates to:
  /// **'Das Gateway läuft mit aktuellem Sicherheitsstand.'**
  String get stageGatewayPass;

  /// No description provided for @stageGatewayWhat.
  ///
  /// In de, this message translates to:
  /// **'Der Zustand des Gateways des Anbieters (Vermittler vor dem Modell).'**
  String get stageGatewayWhat;

  /// No description provided for @stageGpuInfo.
  ///
  /// In de, this message translates to:
  /// **'Die GPU wurde nicht über NVIDIA geprüft, weil die Prüfung in den Einstellungen aus ist.'**
  String get stageGpuInfo;

  /// No description provided for @stageGpuPass.
  ///
  /// In de, this message translates to:
  /// **'NVIDIA bestätigt die geschützte GPU.'**
  String get stageGpuPass;

  /// No description provided for @stageGpuWhat.
  ///
  /// In de, this message translates to:
  /// **'Der Nachweis der Grafikkarte (NVIDIA), auf der das Modell rechnet. Optional, in den Einstellungen zuschaltbar.'**
  String get stageGpuWhat;

  /// No description provided for @stageInfoDefault.
  ///
  /// In de, this message translates to:
  /// **'Die Stufe wird nur protokolliert, nicht als Bedingung geprüft.'**
  String get stageInfoDefault;

  /// No description provided for @stageKeyBindingInfo.
  ///
  /// In de, this message translates to:
  /// **'Die Prüfsumme wurde nur protokolliert.'**
  String get stageKeyBindingInfo;

  /// No description provided for @stageKeyBindingPass.
  ///
  /// In de, this message translates to:
  /// **'Die Schlüssel stammen aus der geprüften Umgebung, nicht von jemandem dazwischen.'**
  String get stageKeyBindingPass;

  /// No description provided for @stageKeyBindingWhat.
  ///
  /// In de, this message translates to:
  /// **'Die Prüfsumme des Schlüsselsatzes (Schlüssel, mit denen Wendelin verschlüsselt) muss im Hardware-Nachweis stehen.'**
  String get stageKeyBindingWhat;

  /// No description provided for @stageMeasurementInfo.
  ///
  /// In de, this message translates to:
  /// **'Der Messwert wurde nur protokolliert.'**
  String get stageMeasurementInfo;

  /// No description provided for @stageMeasurementPass.
  ///
  /// In de, this message translates to:
  /// **'Auf dem Server läuft der veröffentlichte Code, kein anderer.'**
  String get stageMeasurementPass;

  /// No description provided for @stageMeasurementWhat.
  ///
  /// In de, this message translates to:
  /// **'Ob der Messwert des laufenden Servers genau der des neuesten signierten Releases ist.'**
  String get stageMeasurementWhat;

  /// No description provided for @stageNoReceiptInfo.
  ///
  /// In de, this message translates to:
  /// **'Tinfoil stellt keine Quittung je Antwort aus. Die Antwort ist nur durch die Verschlüsselung an deine Anfrage gebunden; welches Modell sie erzeugt hat, belegt keine Quittung.'**
  String get stageNoReceiptInfo;

  /// No description provided for @stageNoReceiptPass.
  ///
  /// In de, this message translates to:
  /// **'Zu jeder Antwort liegt eine signierte Quittung vor.'**
  String get stageNoReceiptPass;

  /// No description provided for @stageNoReceiptWhat.
  ///
  /// In de, this message translates to:
  /// **'Ob zu jeder Antwort eine signierte Quittung vorliegt, die Anfrage und Antwort belegt.'**
  String get stageNoReceiptWhat;

  /// No description provided for @stageNonceInfo.
  ///
  /// In de, this message translates to:
  /// **'Die Zahl wurde nur protokolliert.'**
  String get stageNonceInfo;

  /// No description provided for @stageNoncePass.
  ///
  /// In de, this message translates to:
  /// **'Der Nachweis ist frisch für diese Anfrage und kein aufgezeichneter alter Nachweis.'**
  String get stageNoncePass;

  /// No description provided for @stageNonceWhat.
  ///
  /// In de, this message translates to:
  /// **'Eine zufällige Zahl, die Wendelin mitschickt und die im Nachweis wieder auftauchen muss.'**
  String get stageNonceWhat;

  /// No description provided for @stagePassDefault.
  ///
  /// In de, this message translates to:
  /// **'Die Stufe wurde bestanden.'**
  String get stagePassDefault;

  /// No description provided for @stageProvenanceInfo.
  ///
  /// In de, this message translates to:
  /// **'Es gibt keine Vertrauensliste für diesen Anbieter. Wendelin protokolliert den Stand, kann aber nicht sagen, ob er vertrauenswürdig ist. Wer den Quellcode prüfen will, kann den Commit im Prüfprotokoll nachsehen.'**
  String get stageProvenanceInfo;

  /// No description provided for @stageProvenancePass.
  ///
  /// In de, this message translates to:
  /// **'Die Software stammt aus einem bekannten, geprüften Stand.'**
  String get stageProvenancePass;

  /// No description provided for @stageProvenanceWhat.
  ///
  /// In de, this message translates to:
  /// **'Die Herkunft: aus welchem Quellcode-Stand (Commit) die laufende Software gebaut wurde und ob er auf der Vertrauensliste steht.'**
  String get stageProvenanceWhat;

  /// No description provided for @stageQuoteInfo.
  ///
  /// In de, this message translates to:
  /// **'Der Nachweis wurde nur protokolliert, nicht bewertet.'**
  String get stageQuoteInfo;

  /// No description provided for @stageQuotePass.
  ///
  /// In de, this message translates to:
  /// **'Der Dienst läuft nachweislich in einer echten, abgeschotteten Intel-TDX-Umgebung. Der Betreiber kann den Speicher nicht mitlesen.'**
  String get stageQuotePass;

  /// No description provided for @stageQuoteWhat.
  ///
  /// In de, this message translates to:
  /// **'Der Hardware-Nachweis (TDX-Quote) der geschützten Umgebung. Er ist von der CPU signiert und wird gegen die Zertifikate von Intel geprüft.'**
  String get stageQuoteWhat;

  /// No description provided for @stageReceiptBindingInfo.
  ///
  /// In de, this message translates to:
  /// **'Die Bindung wurde nur protokolliert.'**
  String get stageReceiptBindingInfo;

  /// No description provided for @stageReceiptBindingPass.
  ///
  /// In de, this message translates to:
  /// **'Quittung und Sitzung passen zusammen.'**
  String get stageReceiptBindingPass;

  /// No description provided for @stageReceiptBindingWhat.
  ///
  /// In de, this message translates to:
  /// **'Ob die Quittung zur geprüften Sitzung gehört.'**
  String get stageReceiptBindingWhat;

  /// No description provided for @stageReceiptCompleteInfo.
  ///
  /// In de, this message translates to:
  /// **'Die Ereignisse wurden nur protokolliert.'**
  String get stageReceiptCompleteInfo;

  /// No description provided for @stageReceiptCompletePass.
  ///
  /// In de, this message translates to:
  /// **'Die Quittung ist vollständig.'**
  String get stageReceiptCompletePass;

  /// No description provided for @stageReceiptCompleteWhat.
  ///
  /// In de, this message translates to:
  /// **'Ob die Quittung alle erforderlichen Ereignisse enthält.'**
  String get stageReceiptCompleteWhat;

  /// No description provided for @stageReceiptFetchInfo.
  ///
  /// In de, this message translates to:
  /// **'Der Abruf wurde nur protokolliert.'**
  String get stageReceiptFetchInfo;

  /// No description provided for @stageReceiptFetchPass.
  ///
  /// In de, this message translates to:
  /// **'Der Anbieter hat die Quittung geliefert.'**
  String get stageReceiptFetchPass;

  /// No description provided for @stageReceiptFetchWhat.
  ///
  /// In de, this message translates to:
  /// **'Der Abruf der signierten Quittung zu dieser Antwort.'**
  String get stageReceiptFetchWhat;

  /// No description provided for @stageReceiptRequestHashInfo.
  ///
  /// In de, this message translates to:
  /// **'Die Prüfsumme wurde nur protokolliert.'**
  String get stageReceiptRequestHashInfo;

  /// No description provided for @stageReceiptRequestHashPass.
  ///
  /// In de, this message translates to:
  /// **'Der Anbieter hat genau deine Anfrage erhalten.'**
  String get stageReceiptRequestHashPass;

  /// No description provided for @stageReceiptRequestHashWhat.
  ///
  /// In de, this message translates to:
  /// **'Die Prüfsumme der Anfrage in der Quittung gegen das, was gesendet wurde.'**
  String get stageReceiptRequestHashWhat;

  /// No description provided for @stageReceiptResponseHashInfo.
  ///
  /// In de, this message translates to:
  /// **'Die Prüfsumme wurde nur protokolliert.'**
  String get stageReceiptResponseHashInfo;

  /// No description provided for @stageReceiptResponseHashPass.
  ///
  /// In de, this message translates to:
  /// **'Die Antwort wurde unterwegs nicht verändert.'**
  String get stageReceiptResponseHashPass;

  /// No description provided for @stageReceiptResponseHashWhat.
  ///
  /// In de, this message translates to:
  /// **'Die Prüfsumme der Antwort in der Quittung gegen das Empfangene.'**
  String get stageReceiptResponseHashWhat;

  /// No description provided for @stageReceiptSigInfo.
  ///
  /// In de, this message translates to:
  /// **'Die Signatur wurde nur protokolliert.'**
  String get stageReceiptSigInfo;

  /// No description provided for @stageReceiptSigPass.
  ///
  /// In de, this message translates to:
  /// **'Die Quittung stammt aus der geprüften Umgebung.'**
  String get stageReceiptSigPass;

  /// No description provided for @stageReceiptSigWhat.
  ///
  /// In de, this message translates to:
  /// **'Die Signatur der Quittung.'**
  String get stageReceiptSigWhat;

  /// No description provided for @stageReleaseFloorInfo.
  ///
  /// In de, this message translates to:
  /// **'Der Rückschrittschutz wurde nur protokolliert.'**
  String get stageReleaseFloorInfo;

  /// No description provided for @stageReleaseFloorPass.
  ///
  /// In de, this message translates to:
  /// **'Der Server läuft mit dem bisher neuesten oder einem neueren Release.'**
  String get stageReleaseFloorPass;

  /// No description provided for @stageReleaseFloorWhat.
  ///
  /// In de, this message translates to:
  /// **'Ob das Release nicht älter ist als das neueste, das Wendelin je geprüft hat (Schutz vor einem Rückschritt auf alte, angreifbare Versionen).'**
  String get stageReleaseFloorWhat;

  /// No description provided for @stageResponseKeyInfo.
  ///
  /// In de, this message translates to:
  /// **'Der Schlüsselsatz wurde nur protokolliert.'**
  String get stageResponseKeyInfo;

  /// No description provided for @stageResponseKeyPass.
  ///
  /// In de, this message translates to:
  /// **'Die Antwort gehört zur geprüften Sitzung.'**
  String get stageResponseKeyPass;

  /// No description provided for @stageResponseKeyWhat.
  ///
  /// In de, this message translates to:
  /// **'Ob der Schlüsselsatz der Antwort zum geprüften Satz passt.'**
  String get stageResponseKeyWhat;

  /// No description provided for @stageResultFail.
  ///
  /// In de, this message translates to:
  /// **'fehlgeschlagen'**
  String get stageResultFail;

  /// No description provided for @stageResultPass.
  ///
  /// In de, this message translates to:
  /// **'bestanden'**
  String get stageResultPass;

  /// No description provided for @stageSignatureInfo.
  ///
  /// In de, this message translates to:
  /// **'Dieser Anbieter liefert keine solche Signatur. Die Bindung der Schlüssel läuft stattdessen über den Hardware-Nachweis (Prüfsumme des Schlüsselsatzes). Das ist ein etwas schwächerer Beleg, aber kein Fehler.'**
  String get stageSignatureInfo;

  /// No description provided for @stageSignaturePass.
  ///
  /// In de, this message translates to:
  /// **'Der Schlüsselsatz ist zusätzlich vom Anbieter signiert.'**
  String get stageSignaturePass;

  /// No description provided for @stageSignatureWhat.
  ///
  /// In de, this message translates to:
  /// **'Eine zusätzliche Signatur über den Schlüsselsatz, die manche Anbieter liefern.'**
  String get stageSignatureWhat;

  /// No description provided for @stageSigstoreInfo.
  ///
  /// In de, this message translates to:
  /// **'Die Signatur des Releases wurde nur protokolliert.'**
  String get stageSigstoreInfo;

  /// No description provided for @stageSigstorePass.
  ///
  /// In de, this message translates to:
  /// **'Das Release stammt aus dem Build von Tinfoil und steht öffentlich im Log.'**
  String get stageSigstorePass;

  /// No description provided for @stageSigstoreWhat.
  ///
  /// In de, this message translates to:
  /// **'Ob das veröffentlichte Programm-Release von Tinfoil auf GitHub echt signiert und im öffentlichen Transparenzlog (Sigstore) eingetragen ist.'**
  String get stageSigstoreWhat;

  /// No description provided for @stageSnpChainInfo.
  ///
  /// In de, this message translates to:
  /// **'Die Zertifikatskette wurde nur protokolliert.'**
  String get stageSnpChainInfo;

  /// No description provided for @stageSnpChainPass.
  ///
  /// In de, this message translates to:
  /// **'Die Kette endet bei AMD, nicht bei einem Zertifikat, das jemand unterschoben hat.'**
  String get stageSnpChainPass;

  /// No description provided for @stageSnpChainWhat.
  ///
  /// In de, this message translates to:
  /// **'Ob das Zertifikat des Prozessors über das AMD-Zwischenzertifikat auf den in Wendelin fest hinterlegten AMD-Wurzelschlüssel zurückgeht.'**
  String get stageSnpChainWhat;

  /// No description provided for @stageSnpPolicyInfo.
  ///
  /// In de, this message translates to:
  /// **'Die Richtlinie wurde nur protokolliert.'**
  String get stageSnpPolicyInfo;

  /// No description provided for @stageSnpPolicyPass.
  ///
  /// In de, this message translates to:
  /// **'Die Umgebung ist nicht zum Mitlesen geöffnet und enthält keine bekannt veraltete Firmware.'**
  String get stageSnpPolicyPass;

  /// No description provided for @stageSnpPolicyWhat.
  ///
  /// In de, this message translates to:
  /// **'Ob die Umgebung ohne Debug-Zugang läuft und Firmware und Prozessor-Microcode mindestens so aktuell sind, wie Wendelin es verlangt (Bootloader 9, SNP 22, Microcode 80).'**
  String get stageSnpPolicyWhat;

  /// No description provided for @stageSnpReportInfo.
  ///
  /// In de, this message translates to:
  /// **'Der Bericht des Prozessors wurde nur protokolliert.'**
  String get stageSnpReportInfo;

  /// No description provided for @stageSnpReportPass.
  ///
  /// In de, this message translates to:
  /// **'Ein echter AMD-Prozessor bestätigt den Bericht. Niemand kann ihn nachträglich ändern.'**
  String get stageSnpReportPass;

  /// No description provided for @stageSnpReportWhat.
  ///
  /// In de, this message translates to:
  /// **'Der Hardware-Nachweis des Tinfoil-Servers: Bericht des AMD-Prozessors, sein Zertifikat und die Signatur darüber.'**
  String get stageSnpReportWhat;

  /// No description provided for @stageTcbInfo.
  ///
  /// In de, this message translates to:
  /// **'Der Sicherheitsstand wurde nur protokolliert.'**
  String get stageTcbInfo;

  /// No description provided for @stageTcbPass.
  ///
  /// In de, this message translates to:
  /// **'Die Plattform hat alle bekannten Sicherheits-Updates.'**
  String get stageTcbPass;

  /// No description provided for @stageTcbWhat.
  ///
  /// In de, this message translates to:
  /// **'Der Sicherheitsstand der Plattform (TCB): ob Firmware und Mikrocode auf dem aktuellen Stand sind.'**
  String get stageTcbWhat;

  /// No description provided for @stageTlsInfo.
  ///
  /// In de, this message translates to:
  /// **'Das Zertifikat der Verbindung wurde nicht mit dem Nachweis verglichen. Dann hängt der Schutz allein an der Ende-zu-Ende-Verschlüsselung.'**
  String get stageTlsInfo;

  /// No description provided for @stageTlsPass.
  ///
  /// In de, this message translates to:
  /// **'Die Verbindung endet in der geprüften Umgebung, niemand kann sich dazwischenschalten.'**
  String get stageTlsPass;

  /// No description provided for @stageTlsWhat.
  ///
  /// In de, this message translates to:
  /// **'Ob die Netzwerkverbindung genau zu dem Schlüssel führt, der im Hardware-Nachweis steht (Pinning).'**
  String get stageTlsWhat;

  /// No description provided for @stageUnavailableMeaning.
  ///
  /// In de, this message translates to:
  /// **'Die Prüfung konnte nicht abgeschlossen werden (zum Beispiel wegen des Netzes). Sie wird später wiederholt. Bis dahin ist die Stufe unbestätigt.'**
  String get stageUnavailableMeaning;

  /// No description provided for @stageUpstreamInfo.
  ///
  /// In de, this message translates to:
  /// **'Die Upstream-Prüfung wurde nur protokolliert.'**
  String get stageUpstreamInfo;

  /// No description provided for @stageUpstreamPass.
  ///
  /// In de, this message translates to:
  /// **'Auch das Modell hinter dem Gateway wurde nachweislich geprüft.'**
  String get stageUpstreamPass;

  /// No description provided for @stageUpstreamTcbInfo.
  ///
  /// In de, this message translates to:
  /// **'Der Stand wurde nur protokolliert.'**
  String get stageUpstreamTcbInfo;

  /// No description provided for @stageUpstreamTcbPass.
  ///
  /// In de, this message translates to:
  /// **'Auch diese Plattform ist auf aktuellem Stand.'**
  String get stageUpstreamTcbPass;

  /// No description provided for @stageUpstreamTcbWhat.
  ///
  /// In de, this message translates to:
  /// **'Der Sicherheitsstand der Plattform hinter dem Gateway.'**
  String get stageUpstreamTcbWhat;

  /// No description provided for @stageUpstreamWhat.
  ///
  /// In de, this message translates to:
  /// **'Ob das Gateway bestätigt, dass das Modell dahinter in einer geprüften Umgebung lief.'**
  String get stageUpstreamWhat;

  /// No description provided for @stageWarnMeaning.
  ///
  /// In de, this message translates to:
  /// **'Die Prüfung ist bestanden, aber mit einem Hinweis (zum Beispiel ein ausstehendes Sicherheits-Update des Betreibers). Das schwächt den Schutz etwas. Es bleibt im Prüfprotokoll sichtbar.'**
  String get stageWarnMeaning;

  /// No description provided for @bringApiError.
  ///
  /// In de, this message translates to:
  /// **'Fehler – Schnittstelle nicht erreichbar'**
  String get bringApiError;

  /// No description provided for @bringApp.
  ///
  /// In de, this message translates to:
  /// **'Bring!-App'**
  String get bringApp;

  /// No description provided for @bringChecking.
  ///
  /// In de, this message translates to:
  /// **'Prüfe …'**
  String get bringChecking;

  /// No description provided for @bringConnected.
  ///
  /// In de, this message translates to:
  /// **'Verbunden'**
  String get bringConnected;

  /// No description provided for @bringEmail.
  ///
  /// In de, this message translates to:
  /// **'E-Mail'**
  String get bringEmail;

  /// No description provided for @bringFine.
  ///
  /// In de, this message translates to:
  /// **'in Ordnung'**
  String get bringFine;

  /// No description provided for @bringInstalled.
  ///
  /// In de, this message translates to:
  /// **'Installiert'**
  String get bringInstalled;

  /// No description provided for @bringIntro.
  ///
  /// In de, this message translates to:
  /// **'Inoffizielle Schnittstelle: Bring! hat sie nicht für andere Apps freigegeben, sie kann jederzeit brechen. Du meldest dich einmal an; E-Mail und Passwort werden nicht gespeichert, nur die Sitzung (Tokens) bleibt im sicheren Speicher des Geräts.'**
  String get bringIntro;

  /// No description provided for @bringNeedCredentials.
  ///
  /// In de, this message translates to:
  /// **'Bitte E-Mail und Passwort eingeben.'**
  String get bringNeedCredentials;

  /// No description provided for @bringNotInstalled.
  ///
  /// In de, this message translates to:
  /// **'Nicht installiert'**
  String get bringNotInstalled;

  /// No description provided for @bringPassword.
  ///
  /// In de, this message translates to:
  /// **'Passwort'**
  String get bringPassword;

  /// No description provided for @bringReachable.
  ///
  /// In de, this message translates to:
  /// **'Bring! ist wieder erreichbar.'**
  String get bringReachable;

  /// No description provided for @bringReauthError.
  ///
  /// In de, this message translates to:
  /// **'Bring!: Anmeldung abgelaufen. Bitte neu anmelden.'**
  String get bringReauthError;

  /// No description provided for @bringReconnect.
  ///
  /// In de, this message translates to:
  /// **'Erneut verbinden'**
  String get bringReconnect;

  /// No description provided for @bringShareSend.
  ///
  /// In de, this message translates to:
  /// **'An Bring! senden'**
  String get bringShareSend;

  /// No description provided for @bringShareSent.
  ///
  /// In de, this message translates to:
  /// **'An Bring! gesendet'**
  String get bringShareSent;

  /// No description provided for @bringShareUnreachable.
  ///
  /// In de, this message translates to:
  /// **'Bring! nicht erreichbar'**
  String get bringShareUnreachable;

  /// No description provided for @bringSignOutBody.
  ///
  /// In de, this message translates to:
  /// **'Die Sitzung wird vom Gerät gelöscht.'**
  String get bringSignOutBody;

  /// No description provided for @bringSignOutTitle.
  ///
  /// In de, this message translates to:
  /// **'Bei Bring! abmelden?'**
  String get bringSignOutTitle;

  /// No description provided for @bringSigningIn.
  ///
  /// In de, this message translates to:
  /// **'Anmelden …'**
  String get bringSigningIn;

  /// No description provided for @bringStatusAvailable.
  ///
  /// In de, this message translates to:
  /// **'Angemeldet, Integration ausgeschaltet'**
  String get bringStatusAvailable;

  /// No description provided for @bringStatusSetup.
  ///
  /// In de, this message translates to:
  /// **'Login fehlt'**
  String get bringStatusSetup;

  /// No description provided for @bringStatusUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Nicht verfügbar'**
  String get bringStatusUnavailable;

  /// No description provided for @bringStatusUnknown.
  ///
  /// In de, this message translates to:
  /// **'Unbekannt'**
  String get bringStatusUnknown;

  /// No description provided for @bringUnknown.
  ///
  /// In de, this message translates to:
  /// **'Unbekannt'**
  String get bringUnknown;

  /// No description provided for @add.
  ///
  /// In de, this message translates to:
  /// **'Hinzufügen'**
  String get add;

  /// No description provided for @allow.
  ///
  /// In de, this message translates to:
  /// **'Erlauben'**
  String get allow;

  /// No description provided for @appLanguageDetail.
  ///
  /// In de, this message translates to:
  /// **'Sprache der Oberfläche; unabhängig von Spracheingabe und -ausgabe'**
  String get appLanguageDetail;

  /// No description provided for @appLanguageIntro.
  ///
  /// In de, this message translates to:
  /// **'Wähle die Sprache der Oberfläche. Sie gilt für die ganze App und das Overlay. Welche Sprache du sprichst und hörst, stellst du unter „Sprache“ ein.'**
  String get appLanguageIntro;

  /// No description provided for @appLanguageSystem.
  ///
  /// In de, this message translates to:
  /// **'System'**
  String get appLanguageSystem;

  /// No description provided for @appLanguageSystemDetail.
  ///
  /// In de, this message translates to:
  /// **'Folgt der Sprache des Telefons'**
  String get appLanguageSystemDetail;

  /// No description provided for @appLanguageTitle.
  ///
  /// In de, this message translates to:
  /// **'App-Sprache'**
  String get appLanguageTitle;

  /// No description provided for @appName.
  ///
  /// In de, this message translates to:
  /// **'Wendelin'**
  String get appName;

  /// Tooltip des Zurück-Knopfs
  ///
  /// In de, this message translates to:
  /// **'Zurück'**
  String get back;

  /// No description provided for @cancel.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In de, this message translates to:
  /// **'Schließen'**
  String get close;

  /// No description provided for @confirmCardNeedsConfirm.
  ///
  /// In de, this message translates to:
  /// **'Braucht deine Bestätigung'**
  String get confirmCardNeedsConfirm;

  /// No description provided for @confirmCardToolLevel.
  ///
  /// In de, this message translates to:
  /// **'{toolName} · Stufe {level}'**
  String confirmCardToolLevel(String toolName, String level);

  /// No description provided for @confirmCardWarning.
  ///
  /// In de, this message translates to:
  /// **'Warnung'**
  String get confirmCardWarning;

  /// No description provided for @confirmed.
  ///
  /// In de, this message translates to:
  /// **'Bestätigt'**
  String get confirmed;

  /// No description provided for @copy.
  ///
  /// In de, this message translates to:
  /// **'Kopieren'**
  String get copy;

  /// No description provided for @delete.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get delete;

  /// No description provided for @deny.
  ///
  /// In de, this message translates to:
  /// **'Ablehnen'**
  String get deny;

  /// No description provided for @details.
  ///
  /// In de, this message translates to:
  /// **'Details'**
  String get details;

  /// No description provided for @done.
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get done;

  /// No description provided for @edit.
  ///
  /// In de, this message translates to:
  /// **'Bearbeiten'**
  String get edit;

  /// No description provided for @error.
  ///
  /// In de, this message translates to:
  /// **'Fehler'**
  String get error;

  /// No description provided for @export.
  ///
  /// In de, this message translates to:
  /// **'Exportieren'**
  String get export;

  /// No description provided for @followUpListening.
  ///
  /// In de, this message translates to:
  /// **'Ich höre noch zu …'**
  String get followUpListening;

  /// No description provided for @import.
  ///
  /// In de, this message translates to:
  /// **'Importieren'**
  String get import;

  /// No description provided for @later.
  ///
  /// In de, this message translates to:
  /// **'Später'**
  String get later;

  /// No description provided for @momentPlease.
  ///
  /// In de, this message translates to:
  /// **'Moment …'**
  String get momentPlease;

  /// No description provided for @name.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @next.
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get next;

  /// No description provided for @no.
  ///
  /// In de, this message translates to:
  /// **'Nein'**
  String get no;

  /// No description provided for @off.
  ///
  /// In de, this message translates to:
  /// **'Aus'**
  String get off;

  /// No description provided for @ok.
  ///
  /// In de, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @on.
  ///
  /// In de, this message translates to:
  /// **'An'**
  String get on;

  /// No description provided for @open.
  ///
  /// In de, this message translates to:
  /// **'Öffnen'**
  String get open;

  /// No description provided for @remove.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get remove;

  /// No description provided for @reset.
  ///
  /// In de, this message translates to:
  /// **'Zurücksetzen'**
  String get reset;

  /// No description provided for @retry.
  ///
  /// In de, this message translates to:
  /// **'Erneut versuchen'**
  String get retry;

  /// No description provided for @save.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get save;

  /// No description provided for @search.
  ///
  /// In de, this message translates to:
  /// **'Suchen'**
  String get search;

  /// No description provided for @selected.
  ///
  /// In de, this message translates to:
  /// **'gewählt'**
  String get selected;

  /// No description provided for @send.
  ///
  /// In de, this message translates to:
  /// **'Senden'**
  String get send;

  /// No description provided for @settingsTitle.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get settingsTitle;

  /// No description provided for @share.
  ///
  /// In de, this message translates to:
  /// **'Teilen'**
  String get share;

  /// No description provided for @start.
  ///
  /// In de, this message translates to:
  /// **'Starten'**
  String get start;

  /// No description provided for @test.
  ///
  /// In de, this message translates to:
  /// **'Testen'**
  String get test;

  /// No description provided for @understood.
  ///
  /// In de, this message translates to:
  /// **'Verstanden'**
  String get understood;

  /// No description provided for @yes.
  ///
  /// In de, this message translates to:
  /// **'Ja'**
  String get yes;

  /// No description provided for @confCallTitle.
  ///
  /// In de, this message translates to:
  /// **'Anrufen?'**
  String get confCallTitle;

  /// No description provided for @confHintVoiceCall.
  ///
  /// In de, this message translates to:
  /// **'Sag „anrufen“ oder „abbrechen“'**
  String get confHintVoiceCall;

  /// No description provided for @confHintVoiceEdited.
  ///
  /// In de, this message translates to:
  /// **'Du hast den Text geändert: bitte per Tipp absenden'**
  String get confHintVoiceEdited;

  /// No description provided for @confHintVoiceSms.
  ///
  /// In de, this message translates to:
  /// **'Sag „absenden“ oder „abbrechen“'**
  String get confHintVoiceSms;

  /// No description provided for @confNoCancel.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get confNoCancel;

  /// No description provided for @confSmsNoText.
  ///
  /// In de, this message translates to:
  /// **'Die Nachricht darf nicht leer sein.'**
  String get confSmsNoText;

  /// No description provided for @confSmsTextLabel.
  ///
  /// In de, this message translates to:
  /// **'Nachricht'**
  String get confSmsTextLabel;

  /// No description provided for @confSmsTitle.
  ///
  /// In de, this message translates to:
  /// **'SMS absenden?'**
  String get confSmsTitle;

  /// No description provided for @confSmsTo.
  ///
  /// In de, this message translates to:
  /// **'An {name}'**
  String confSmsTo(String name);

  /// No description provided for @confYesCall.
  ///
  /// In de, this message translates to:
  /// **'Anrufen'**
  String get confYesCall;

  /// No description provided for @confYesSend.
  ///
  /// In de, this message translates to:
  /// **'Absenden'**
  String get confYesSend;

  /// No description provided for @integrationsContactsRationale.
  ///
  /// In de, this message translates to:
  /// **'Wendelin braucht Zugriff auf deine Kontakte, um Nummern nach Namen zu finden, und die Rechte für SMS und Telefon. Android fragt dich gleich danach. Wendelin sendet nie eine SMS und ruft nie an, ohne dass du vorher die Vorschau mit Name und Nummer bestätigt hast (per Tipp oder mit „ja“). Bei gesperrtem Gerät geht beides nie. Ohne Telefonrecht öffnet Wendelin nur den Wählbildschirm. Sperrt Android die SMS-Freigabe, erklärt Wendelin danach, wie du sie erlaubst.'**
  String get integrationsContactsRationale;

  /// No description provided for @developerModeActiveHint.
  ///
  /// In de, this message translates to:
  /// **'Entwicklermodus an – erweitertes Logging'**
  String get developerModeActiveHint;

  /// No description provided for @developerModeOff.
  ///
  /// In de, this message translates to:
  /// **'Entwicklermodus aus'**
  String get developerModeOff;

  /// No description provided for @developerModeOn.
  ///
  /// In de, this message translates to:
  /// **'Entwicklermodus an'**
  String get developerModeOn;

  /// No description provided for @developerModeStepsToOff.
  ///
  /// In de, this message translates to:
  /// **'Noch {n}× tippen, um den Entwicklermodus auszuschalten'**
  String developerModeStepsToOff(int n);

  /// No description provided for @developerModeStepsToOn.
  ///
  /// In de, this message translates to:
  /// **'Noch {n}× tippen, um den Entwicklermodus einzuschalten'**
  String developerModeStepsToOn(int n);

  /// No description provided for @batteryAllow.
  ///
  /// In de, this message translates to:
  /// **'Keine Einschränkung erlauben'**
  String get batteryAllow;

  /// No description provided for @batteryChecklistNote.
  ///
  /// In de, this message translates to:
  /// **'Android lässt diese Einstellungen nicht auslesen. Das ist eine Checkliste, kein Status.'**
  String get batteryChecklistNote;

  /// No description provided for @batteryHuaweiBody.
  ///
  /// In de, this message translates to:
  /// **'Stelle „App-Start“ für Wendelin auf „Manuell verwalten“ und erlaube Autostart, Zweitstart und Hintergrundaktivität.'**
  String get batteryHuaweiBody;

  /// No description provided for @batteryHuaweiTitle.
  ///
  /// In de, this message translates to:
  /// **'Huawei / Honor'**
  String get batteryHuaweiTitle;

  /// No description provided for @batteryOnePlusBody.
  ///
  /// In de, this message translates to:
  /// **'Erlaube Wendelin den Autostart und stelle die Akku-Optimierung für Wendelin auf „Nicht optimieren“ (Einstellungen → Apps → Wendelin → Akku).'**
  String get batteryOnePlusBody;

  /// No description provided for @batteryOnePlusTitle.
  ///
  /// In de, this message translates to:
  /// **'OnePlus'**
  String get batteryOnePlusTitle;

  /// No description provided for @batteryOpenSettings.
  ///
  /// In de, this message translates to:
  /// **'Akku-Einstellungen öffnen'**
  String get batteryOpenSettings;

  /// No description provided for @batteryOptimizedDetail.
  ///
  /// In de, this message translates to:
  /// **'Android kann Wendelin im Hintergrund beenden. Nach längerer Pause öffnet die Power-Taste den Assistenten dann womöglich nicht, bis du die App einmal geöffnet hast.'**
  String get batteryOptimizedDetail;

  /// No description provided for @batteryOptimizedTitle.
  ///
  /// In de, this message translates to:
  /// **'Akku-Optimierung aktiv'**
  String get batteryOptimizedTitle;

  /// No description provided for @batteryReliable.
  ///
  /// In de, this message translates to:
  /// **'Zuverlässig öffnen'**
  String get batteryReliable;

  /// No description provided for @batterySamsungBody.
  ///
  /// In de, this message translates to:
  /// **'Nimm Wendelin aus „Schlafende Apps“ heraus und stelle den Akku für Wendelin auf „Nicht eingeschränkt“ (Einstellungen → Akku → Hintergrundnutzungsgrenzen).'**
  String get batterySamsungBody;

  /// No description provided for @batterySamsungTitle.
  ///
  /// In de, this message translates to:
  /// **'Samsung'**
  String get batterySamsungTitle;

  /// No description provided for @batterySettingsNotOpened.
  ///
  /// In de, this message translates to:
  /// **'Die Systemeinstellungen ließen sich nicht öffnen.'**
  String get batterySettingsNotOpened;

  /// No description provided for @batteryStandbyDetail.
  ///
  /// In de, this message translates to:
  /// **'Android verzögert Starts im Hintergrund für selten genutzte Apps. Öffne Wendelin ab und zu oder erlaube „Keine Einschränkung“.'**
  String get batteryStandbyDetail;

  /// No description provided for @batteryStandbyRare.
  ///
  /// In de, this message translates to:
  /// **'App-Standby: selten genutzt'**
  String get batteryStandbyRare;

  /// No description provided for @batteryStandbyRestricted.
  ///
  /// In de, this message translates to:
  /// **'App-Standby: eingeschränkt'**
  String get batteryStandbyRestricted;

  /// No description provided for @batteryVendorSettings.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen des Herstellers öffnen'**
  String get batteryVendorSettings;

  /// No description provided for @batteryXiaomiBody.
  ///
  /// In de, this message translates to:
  /// **'Schalte für Wendelin „Autostart“ ein und stelle den Akkusparer für Wendelin auf „Keine Einschränkungen“ (Einstellungen → Apps → Berechtigungen → Autostart; Einstellungen → Apps → Wendelin → Akkusparer).'**
  String get batteryXiaomiBody;

  /// No description provided for @batteryXiaomiTitle.
  ///
  /// In de, this message translates to:
  /// **'Xiaomi / HyperOS / MIUI'**
  String get batteryXiaomiTitle;

  /// No description provided for @devDemoMode.
  ///
  /// In de, this message translates to:
  /// **'Demo-Modus (ohne Provider)'**
  String get devDemoMode;

  /// No description provided for @devDemoModeLabel.
  ///
  /// In de, this message translates to:
  /// **'Demo-Modus'**
  String get devDemoModeLabel;

  /// No description provided for @devGallery.
  ///
  /// In de, this message translates to:
  /// **'Design-Galerie'**
  String get devGallery;

  /// No description provided for @devSection.
  ///
  /// In de, this message translates to:
  /// **'Entwicklung'**
  String get devSection;

  /// No description provided for @integrationsErrDenied.
  ///
  /// In de, this message translates to:
  /// **'{service}: Zugang abgelehnt oder abgelaufen · pausiert'**
  String integrationsErrDenied(String service);

  /// No description provided for @integrationsErrFailed.
  ///
  /// In de, this message translates to:
  /// **'{service}: unerwartete Antwort · pausiert'**
  String integrationsErrFailed(String service);

  /// No description provided for @integrationsErrUnavailable.
  ///
  /// In de, this message translates to:
  /// **'{service} ist nicht erreichbar · pausiert'**
  String integrationsErrUnavailable(String service);

  /// No description provided for @gpuEvidenceUnverified.
  ///
  /// In de, this message translates to:
  /// **'GPU-Nachweis konnte nicht geprüft werden. Die GPU-Prüfung ist hier nicht wählbar und bleibt „Aus“; die übrigen Prüfungen bleiben aktiv. Die Auswahl erscheint, wenn die Prüfung beim Bearbeiten des Profils gelingt.'**
  String get gpuEvidenceUnverified;

  /// No description provided for @gpuNoEvidenceFinishHidden.
  ///
  /// In de, this message translates to:
  /// **'{hint}. Das Modell bleibt nutzbar. Die GPU-Prüfung ist hier nicht wählbar und bleibt „Aus“; die übrigen Prüfungen bleiben aktiv.'**
  String gpuNoEvidenceFinishHidden(String hint);

  /// No description provided for @haAddressLabel.
  ///
  /// In de, this message translates to:
  /// **'Adresse'**
  String get haAddressLabel;

  /// No description provided for @haApproved.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, one{1 Gerät freigegeben} other{{n} Geräte freigegeben}}'**
  String haApproved(int n);

  /// No description provided for @haConnect.
  ///
  /// In de, this message translates to:
  /// **'Verbinden'**
  String get haConnect;

  /// No description provided for @haConnected.
  ///
  /// In de, this message translates to:
  /// **'Verbunden'**
  String get haConnected;

  /// No description provided for @haConnecting.
  ///
  /// In de, this message translates to:
  /// **'Verbinde …'**
  String get haConnecting;

  /// No description provided for @haDevices.
  ///
  /// In de, this message translates to:
  /// **'Geräte freigeben'**
  String get haDevices;

  /// No description provided for @haDevicesHelp.
  ///
  /// In de, this message translates to:
  /// **'Nur die gewählten Geräte kennt Wendelin. Schlösser, Alarmanlagen und Tore fragen immer vorher nach.'**
  String get haDevicesHelp;

  /// No description provided for @haDisconnect.
  ///
  /// In de, this message translates to:
  /// **'Trennen'**
  String get haDisconnect;

  /// No description provided for @haDisconnectMessage.
  ///
  /// In de, this message translates to:
  /// **'Adresse, Token und die Auswahl der Geräte werden vom Gerät gelöscht.'**
  String get haDisconnectMessage;

  /// No description provided for @haDisconnectTitle.
  ///
  /// In de, this message translates to:
  /// **'Home Assistant trennen?'**
  String get haDisconnectTitle;

  /// No description provided for @haErrorTitle.
  ///
  /// In de, this message translates to:
  /// **'Fehler – nicht erreichbar'**
  String get haErrorTitle;

  /// No description provided for @haFastPath.
  ///
  /// In de, this message translates to:
  /// **'Einfache Befehle sofort ausführen'**
  String get haFastPath;

  /// No description provided for @haFastPathHelp.
  ///
  /// In de, this message translates to:
  /// **'„Rollo Wohnzimmer runter“ oder „Küche Deckenlicht aus“ führt Wendelin ohne KI aus, mit denselben Regeln. Schlösser, Alarmanlagen, Tore und Geräte der Stufe D gehen nie so. Bei Unklarem fragt wie bisher die KI.'**
  String get haFastPathHelp;

  /// No description provided for @haFilter.
  ///
  /// In de, this message translates to:
  /// **'Geräte filtern'**
  String get haFilter;

  /// No description provided for @haFound.
  ///
  /// In de, this message translates to:
  /// **'Gefunden'**
  String get haFound;

  /// No description provided for @haGone.
  ///
  /// In de, this message translates to:
  /// **'Nicht mehr in Home Assistant'**
  String get haGone;

  /// No description provided for @haHttpNote.
  ///
  /// In de, this message translates to:
  /// **'Unverschlüsseltes http ist nur im Heimnetz, über Tailscale (100.x, *.ts.net) und bei *.local erlaubt, sonst nur https. Über Tailscale wird nichts automatisch gefunden: Adresse von Hand eingeben.'**
  String get haHttpNote;

  /// No description provided for @haInputMissing.
  ///
  /// In de, this message translates to:
  /// **'Bitte Adresse und Token eingeben.'**
  String get haInputMissing;

  /// No description provided for @haIntro.
  ///
  /// In de, this message translates to:
  /// **'Wendelin steuert deine freigegebenen Geräte über die Schnittstelle deines Home Assistant. Nur im Heimnetz oder über Tailscale. Adresse und Token bleiben im sicheren Speicher des Geräts.'**
  String get haIntro;

  /// No description provided for @haNoDevices.
  ///
  /// In de, this message translates to:
  /// **'Keine Geräte gefunden.'**
  String get haNoDevices;

  /// No description provided for @haNoRoom.
  ///
  /// In de, this message translates to:
  /// **'Ohne Raum'**
  String get haNoRoom;

  /// No description provided for @haNothingFound.
  ///
  /// In de, this message translates to:
  /// **'Nichts gefunden. Adresse von Hand eingeben (bei Tailscale nötig).'**
  String get haNothingFound;

  /// No description provided for @haReachable.
  ///
  /// In de, this message translates to:
  /// **'Home Assistant ist erreichbar.'**
  String get haReachable;

  /// No description provided for @haReload.
  ///
  /// In de, this message translates to:
  /// **'Geräte neu laden'**
  String get haReload;

  /// No description provided for @haRemoveGone.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get haRemoveGone;

  /// No description provided for @haSearch.
  ///
  /// In de, this message translates to:
  /// **'Im WLAN suchen'**
  String get haSearch;

  /// No description provided for @haSearching.
  ///
  /// In de, this message translates to:
  /// **'Suche …'**
  String get haSearching;

  /// No description provided for @haTitle.
  ///
  /// In de, this message translates to:
  /// **'Home Assistant'**
  String get haTitle;

  /// No description provided for @haTokenHelp.
  ///
  /// In de, this message translates to:
  /// **'In Home Assistant: Profil → Sicherheit → Langlebige Zugriffstokens.'**
  String get haTokenHelp;

  /// No description provided for @haTokenLabel.
  ///
  /// In de, this message translates to:
  /// **'Long-Lived Access Token'**
  String get haTokenLabel;

  /// No description provided for @httpArgsAddArg.
  ///
  /// In de, this message translates to:
  /// **'+ Argument'**
  String get httpArgsAddArg;

  /// No description provided for @httpArgsArgs.
  ///
  /// In de, this message translates to:
  /// **'Argumente'**
  String get httpArgsArgs;

  /// No description provided for @httpArgsCustomSchema.
  ///
  /// In de, this message translates to:
  /// **'Eigenes JSON-Schema'**
  String get httpArgsCustomSchema;

  /// No description provided for @httpArgsCustomSchemaDetail.
  ///
  /// In de, this message translates to:
  /// **'Statt der einfachen Liste'**
  String get httpArgsCustomSchemaDetail;

  /// No description provided for @httpArgsCustomSchemaSem.
  ///
  /// In de, this message translates to:
  /// **'Eigenes JSON-Schema'**
  String get httpArgsCustomSchemaSem;

  /// No description provided for @httpArgsDescription.
  ///
  /// In de, this message translates to:
  /// **'Beschreibung'**
  String get httpArgsDescription;

  /// No description provided for @httpArgsRemoveArg.
  ///
  /// In de, this message translates to:
  /// **'Argument entfernen'**
  String get httpArgsRemoveArg;

  /// No description provided for @httpArgsRequired.
  ///
  /// In de, this message translates to:
  /// **'Pflicht'**
  String get httpArgsRequired;

  /// No description provided for @httpArgsRequiredNamed.
  ///
  /// In de, this message translates to:
  /// **'Pflicht {name}'**
  String httpArgsRequiredNamed(String name);

  /// No description provided for @httpArgsSchema.
  ///
  /// In de, this message translates to:
  /// **'JSON-Schema'**
  String get httpArgsSchema;

  /// No description provided for @httpAuthAddSecretHeader.
  ///
  /// In de, this message translates to:
  /// **'+ Geheimer Header'**
  String get httpAuthAddSecretHeader;

  /// No description provided for @httpAuthKeepStored.
  ///
  /// In de, this message translates to:
  /// **'Leer lassen behält den gespeicherten'**
  String get httpAuthKeepStored;

  /// No description provided for @httpAuthRemoveSecretHeader.
  ///
  /// In de, this message translates to:
  /// **'Geheimen Header entfernen'**
  String get httpAuthRemoveSecretHeader;

  /// No description provided for @httpAuthSecretHeader.
  ///
  /// In de, this message translates to:
  /// **'Geheimer Header, z. B. X-Api-Key'**
  String get httpAuthSecretHeader;

  /// No description provided for @httpAuthStored.
  ///
  /// In de, this message translates to:
  /// **'{redactedSecret} gespeichert'**
  String httpAuthStored(String redactedSecret);

  /// No description provided for @httpEditorDeleteBody.
  ///
  /// In de, this message translates to:
  /// **'„http__{v}“ und seine gespeicherten Secrets werden gelöscht.'**
  String httpEditorDeleteBody(String v);

  /// No description provided for @httpEditorDeleteTitle.
  ///
  /// In de, this message translates to:
  /// **'HTTP-Tool löschen?'**
  String get httpEditorDeleteTitle;

  /// No description provided for @httpEditorNewTool.
  ///
  /// In de, this message translates to:
  /// **'Neues HTTP-Tool'**
  String get httpEditorNewTool;

  /// No description provided for @httpEditorTool.
  ///
  /// In de, this message translates to:
  /// **'HTTP-Tool'**
  String get httpEditorTool;

  /// No description provided for @httpPhUnknown.
  ///
  /// In de, this message translates to:
  /// **'{v} unbekannt'**
  String httpPhUnknown(String v);

  /// No description provided for @httpRunAskElse.
  ///
  /// In de, this message translates to:
  /// **'Sonst fragt Wendelin vor jedem Aufruf nach'**
  String get httpRunAskElse;

  /// No description provided for @httpRunExecution.
  ///
  /// In de, this message translates to:
  /// **'Ausführung'**
  String get httpRunExecution;

  /// No description provided for @httpRunHomeTarget.
  ///
  /// In de, this message translates to:
  /// **'Heimnetz-Ziel'**
  String get httpRunHomeTarget;

  /// No description provided for @httpRunHomeTargetDetail.
  ///
  /// In de, this message translates to:
  /// **'Darf auf private Adressen zeigen, dann auch http'**
  String get httpRunHomeTargetDetail;

  /// No description provided for @httpRunHomeTargetSem.
  ///
  /// In de, this message translates to:
  /// **'Heimnetz-Ziel'**
  String get httpRunHomeTargetSem;

  /// No description provided for @httpRunLevel.
  ///
  /// In de, this message translates to:
  /// **'Risiko (Vorschlag für {verb}: {name})'**
  String httpRunLevel(String verb, String name);

  /// No description provided for @httpRunNoAsk.
  ///
  /// In de, this message translates to:
  /// **'Ohne Nachfrage ausführen (kein Rückgängig)'**
  String get httpRunNoAsk;

  /// No description provided for @httpRunNoAskSem.
  ///
  /// In de, this message translates to:
  /// **'Ohne Nachfrage ausführen'**
  String get httpRunNoAskSem;

  /// No description provided for @httpRunOnlyWrite.
  ///
  /// In de, this message translates to:
  /// **'Nur bei POST/PUT/PATCH mit Stufe write'**
  String get httpRunOnlyWrite;

  /// No description provided for @httpRunSensitiveDetail.
  ///
  /// In de, this message translates to:
  /// **'Nur an Provider ab der Stufe für sensible Integrationen'**
  String get httpRunSensitiveDetail;

  /// No description provided for @httpRunTimeout.
  ///
  /// In de, this message translates to:
  /// **'Zeitlimit in Sekunden'**
  String get httpRunTimeout;

  /// No description provided for @httpRunUntrusted.
  ///
  /// In de, this message translates to:
  /// **'Kann unsichere Inhalte enthalten'**
  String get httpRunUntrusted;

  /// No description provided for @httpRunUntrustedDetail.
  ///
  /// In de, this message translates to:
  /// **'Antworten können Texte Dritter enthalten. Danach fragt Wendelin vor Aufrufen mit Netzziel nach. Nur für eigene Dienste mit bekannten Daten ausschalten.'**
  String get httpRunUntrustedDetail;

  /// No description provided for @httpSrcAddHeader.
  ///
  /// In de, this message translates to:
  /// **'+ Header'**
  String get httpSrcAddHeader;

  /// No description provided for @httpSrcBodyHelp.
  ///
  /// In de, this message translates to:
  /// **'{example} wird typgerecht ersetzt; leer = kein Body'**
  String httpSrcBodyHelp(String example);

  /// No description provided for @httpSrcBodyTemplate.
  ///
  /// In de, this message translates to:
  /// **'Body-Vorlage (JSON)'**
  String get httpSrcBodyTemplate;

  /// No description provided for @httpSrcForm.
  ///
  /// In de, this message translates to:
  /// **'Formular'**
  String get httpSrcForm;

  /// No description provided for @httpSrcHeader.
  ///
  /// In de, this message translates to:
  /// **'Header'**
  String get httpSrcHeader;

  /// No description provided for @httpSrcHeaderDetail.
  ///
  /// In de, this message translates to:
  /// **'Nicht geheim; Tokens gehören in die Anmeldung'**
  String get httpSrcHeaderDetail;

  /// No description provided for @httpSrcJson.
  ///
  /// In de, this message translates to:
  /// **'JSON'**
  String get httpSrcJson;

  /// No description provided for @httpSrcRemoveHeader.
  ///
  /// In de, this message translates to:
  /// **'Header entfernen'**
  String get httpSrcRemoveHeader;

  /// No description provided for @httpSrcUrlHelp.
  ///
  /// In de, this message translates to:
  /// **'Platzhalter wie {example} nur in Pfad und Query, Host fest'**
  String httpSrcUrlHelp(String example);

  /// No description provided for @httpSrcUrlTemplate.
  ///
  /// In de, this message translates to:
  /// **'URL-Vorlage'**
  String get httpSrcUrlTemplate;

  /// No description provided for @httpTestArgLabel.
  ///
  /// In de, this message translates to:
  /// **'{name} ({type})'**
  String httpTestArgLabel(String name, String type);

  /// No description provided for @httpTestFailed.
  ///
  /// In de, this message translates to:
  /// **'fehlgeschlagen'**
  String get httpTestFailed;

  /// No description provided for @httpTestHeaderLine.
  ///
  /// In de, this message translates to:
  /// **'{key}: {value}'**
  String httpTestHeaderLine(String key, String value);

  /// No description provided for @httpTestHttpStatus.
  ///
  /// In de, this message translates to:
  /// **'HTTP {status}'**
  String httpTestHttpStatus(int status);

  /// No description provided for @httpTestMs.
  ///
  /// In de, this message translates to:
  /// **'{ms} ms'**
  String httpTestMs(int ms);

  /// No description provided for @httpTestNoResponse.
  ///
  /// In de, this message translates to:
  /// **'Keine Antwort'**
  String get httpTestNoResponse;

  /// No description provided for @httpTestRunning.
  ///
  /// In de, this message translates to:
  /// **'Läuft …'**
  String get httpTestRunning;

  /// No description provided for @httpTestSent.
  ///
  /// In de, this message translates to:
  /// **'Gesendet'**
  String get httpTestSent;

  /// No description provided for @httpTestSentLine.
  ///
  /// In de, this message translates to:
  /// **'{method} {url}'**
  String httpTestSentLine(String method, Object url);

  /// No description provided for @httpTestSucceeded.
  ///
  /// In de, this message translates to:
  /// **'erfolgreich'**
  String get httpTestSucceeded;

  /// No description provided for @httpTestTruncated.
  ///
  /// In de, this message translates to:
  /// **'gekürzt'**
  String get httpTestTruncated;

  /// No description provided for @httpToolSecModelDescription.
  ///
  /// In de, this message translates to:
  /// **'Beschreibung fürs Modell'**
  String get httpToolSecModelDescription;

  /// No description provided for @httpToolSecModelDescriptionHelp.
  ///
  /// In de, this message translates to:
  /// **'Wann und wofür das Modell das Tool nutzen soll'**
  String get httpToolSecModelDescriptionHelp;

  /// No description provided for @httpToolsExportNote.
  ///
  /// In de, this message translates to:
  /// **'Export und Import enthalten keine Secrets. Nach dem Import Token und geheime Header neu eingeben; „Ohne Nachfrage ausführen“ ist dann aus.'**
  String get httpToolsExportNote;

  /// No description provided for @httpToolsExportPaste.
  ///
  /// In de, this message translates to:
  /// **'Export (JSON) einfügen'**
  String get httpToolsExportPaste;

  /// No description provided for @httpToolsImportFailed.
  ///
  /// In de, this message translates to:
  /// **'Import fehlgeschlagen: {message}'**
  String httpToolsImportFailed(String message);

  /// No description provided for @httpToolsImportTitle.
  ///
  /// In de, this message translates to:
  /// **'HTTP-Tools importieren'**
  String get httpToolsImportTitle;

  /// No description provided for @httpToolsImported.
  ///
  /// In de, this message translates to:
  /// **'{length, plural, one{{length} HTTP-Tool importiert. Secrets bitte neu eingeben; „Ohne Nachfrage ausführen“ ist aus.} other{{length} HTTP-Tools importiert. Secrets bitte neu eingeben; „Ohne Nachfrage ausführen“ ist aus.}}'**
  String httpToolsImported(int length);

  /// No description provided for @httpToolsIntro.
  ///
  /// In de, this message translates to:
  /// **'Eigene Tools aus Methode, URL-Vorlage, Headern und Anmeldung, z. B. für Home Assistant oder n8n. Antworten sind Daten, keine Anweisungen.'**
  String get httpToolsIntro;

  /// No description provided for @httpToolsOffShort.
  ///
  /// In de, this message translates to:
  /// **'aus'**
  String get httpToolsOffShort;

  /// No description provided for @httpToolsRiskRead.
  ///
  /// In de, this message translates to:
  /// **'liest'**
  String get httpToolsRiskRead;

  /// No description provided for @httpToolsRiskWrite.
  ///
  /// In de, this message translates to:
  /// **'ändert ohne Nachfrage, kein Rückgängig'**
  String get httpToolsRiskWrite;

  /// No description provided for @httpToolsSensitiveShort.
  ///
  /// In de, this message translates to:
  /// **'sensibel'**
  String get httpToolsSensitiveShort;

  /// No description provided for @comingSoonInProgress.
  ///
  /// In de, this message translates to:
  /// **'In Arbeit'**
  String get comingSoonInProgress;

  /// No description provided for @comingSoonM3.
  ///
  /// In de, this message translates to:
  /// **'Kommt in M3'**
  String get comingSoonM3;

  /// No description provided for @integrationDetailBringAccount.
  ///
  /// In de, this message translates to:
  /// **'Bring!-Konto'**
  String get integrationDetailBringAccount;

  /// No description provided for @integrationDetailExternalAsks.
  ///
  /// In de, this message translates to:
  /// **'Außenwirkung · fragt immer nach'**
  String get integrationDetailExternalAsks;

  /// No description provided for @integrationDetailExternalNoAsk.
  ///
  /// In de, this message translates to:
  /// **'Außenwirkung · ohne Nachfrage (Stufe gelockert)'**
  String get integrationDetailExternalNoAsk;

  /// No description provided for @integrationDetailIntegrationDetailHaSetup.
  ///
  /// In de, this message translates to:
  /// **'Adresse, Token und Geräte'**
  String get integrationDetailIntegrationDetailHaSetup;

  /// No description provided for @integrationDetailIntegrationDetailSpotifyAccount.
  ///
  /// In de, this message translates to:
  /// **'Spotify-Konto'**
  String get integrationDetailIntegrationDetailSpotifyAccount;

  /// No description provided for @integrationDetailLevelAll.
  ///
  /// In de, this message translates to:
  /// **'An alle Provider'**
  String get integrationDetailLevelAll;

  /// No description provided for @integrationDetailLevelEu.
  ///
  /// In de, this message translates to:
  /// **'Ab EU'**
  String get integrationDetailLevelEu;

  /// No description provided for @integrationDetailLevelLocal.
  ///
  /// In de, this message translates to:
  /// **'Nur lokal'**
  String get integrationDetailLevelLocal;

  /// No description provided for @integrationDetailLevelTee.
  ///
  /// In de, this message translates to:
  /// **'Ab TEE'**
  String get integrationDetailLevelTee;

  /// No description provided for @integrationDetailManageLists.
  ///
  /// In de, this message translates to:
  /// **'Listen verwalten'**
  String get integrationDetailManageLists;

  /// No description provided for @integrationDetailMemoryHint.
  ///
  /// In de, this message translates to:
  /// **'Einträge ansehen, ändern, exportieren'**
  String get integrationDetailMemoryHint;

  /// No description provided for @integrationDetailNoSearch.
  ///
  /// In de, this message translates to:
  /// **'Ohne Suchdienst liest Wendelin nur Seiten'**
  String get integrationDetailNoSearch;

  /// No description provided for @integrationDetailReadsAsks.
  ///
  /// In de, this message translates to:
  /// **'liest · fragt immer nach'**
  String get integrationDetailReadsAsks;

  /// No description provided for @integrationDetailReadsNoAsk.
  ///
  /// In de, this message translates to:
  /// **'liest · ohne Nachfrage'**
  String get integrationDetailReadsNoAsk;

  /// No description provided for @integrationDetailSensitiveLabel.
  ///
  /// In de, this message translates to:
  /// **'{displayName} sensibel'**
  String integrationDetailSensitiveLabel(String displayName);

  /// No description provided for @integrationDetailSensitiveNote.
  ///
  /// In de, this message translates to:
  /// **'Sensibel: Die Tools gehen nur an Provider ab der Stufe, die du für sensible Integrationen festlegst.'**
  String get integrationDetailSensitiveNote;

  /// No description provided for @integrationDetailSensitiveTitle.
  ///
  /// In de, this message translates to:
  /// **'Sensible Integrationen'**
  String get integrationDetailSensitiveTitle;

  /// No description provided for @integrationDetailSetUpSearch.
  ///
  /// In de, this message translates to:
  /// **'Suchdienst einrichten'**
  String get integrationDetailSetUpSearch;

  /// No description provided for @integrationDetailTapTool.
  ///
  /// In de, this message translates to:
  /// **'Unter „Details“ legst du je Tool die Sicherheitsstufe fest (A bis D).'**
  String get integrationDetailTapTool;

  /// No description provided for @integrationDetailTitle.
  ///
  /// In de, this message translates to:
  /// **'Integration'**
  String get integrationDetailTitle;

  /// No description provided for @integrationDetailVaultDaily.
  ///
  /// In de, this message translates to:
  /// **'Vault und Tagesnotizen'**
  String get integrationDetailVaultDaily;

  /// No description provided for @integrationDetailViewMemory.
  ///
  /// In de, this message translates to:
  /// **'Gedächtnis ansehen'**
  String get integrationDetailViewMemory;

  /// No description provided for @integrationDetailWritesAsks.
  ///
  /// In de, this message translates to:
  /// **'ändert · fragt immer nach'**
  String get integrationDetailWritesAsks;

  /// No description provided for @integrationDetailWritesNoUndo.
  ///
  /// In de, this message translates to:
  /// **'ändert · ohne Nachfrage, kein Rückgängig'**
  String get integrationDetailWritesNoUndo;

  /// No description provided for @integrationDetailWritesUndo.
  ///
  /// In de, this message translates to:
  /// **'ändert · ohne Nachfrage, 10 s rückgängig'**
  String get integrationDetailWritesUndo;

  /// No description provided for @integrationTileActiveDetail.
  ///
  /// In de, this message translates to:
  /// **'Aktiv · {detail}'**
  String integrationTileActiveDetail(String detail);

  /// No description provided for @integrationTileAvailable.
  ///
  /// In de, this message translates to:
  /// **'Verfügbar'**
  String get integrationTileAvailable;

  /// No description provided for @integrationTileInStore.
  ///
  /// In de, this message translates to:
  /// **'Im Store'**
  String get integrationTileInStore;

  /// No description provided for @integrationTileOnlyFrom.
  ///
  /// In de, this message translates to:
  /// **'Nur an Provider ab'**
  String get integrationTileOnlyFrom;

  /// No description provided for @integrationTileSetupNeeded.
  ///
  /// In de, this message translates to:
  /// **'Einrichtung nötig'**
  String get integrationTileSetupNeeded;

  /// No description provided for @integrationsAddHttp.
  ///
  /// In de, this message translates to:
  /// **'+ HTTP-Tool'**
  String get integrationsAddHttp;

  /// No description provided for @integrationsAddMcp.
  ///
  /// In de, this message translates to:
  /// **'+ MCP-Server'**
  String get integrationsAddMcp;

  /// No description provided for @integrationsAppMissing.
  ///
  /// In de, this message translates to:
  /// **'App nicht installiert'**
  String get integrationsAppMissing;

  /// No description provided for @integrationsCalendarRationale.
  ///
  /// In de, this message translates to:
  /// **'Wendelin braucht Zugriff auf deine Kalender, um Termine zu lesen, anzulegen und zu ändern. Android fragt dich gleich danach. Löschen fragt Wendelin immer vorher nach.'**
  String get integrationsCalendarRationale;

  /// No description provided for @integrationsHintBring.
  ///
  /// In de, this message translates to:
  /// **'Bring!-App fehlt: kein Ausweg über „Teilen“'**
  String get integrationsHintBring;

  /// No description provided for @integrationsHintObsidian.
  ///
  /// In de, this message translates to:
  /// **'Obsidian-App fehlt: Öffnen in Obsidian geht nicht'**
  String get integrationsHintObsidian;

  /// No description provided for @integrationsHintSpotify.
  ///
  /// In de, this message translates to:
  /// **'Spotify-App fehlt: Wiedergabe nur auf anderen Geräten'**
  String get integrationsHintSpotify;

  /// No description provided for @integrationsIntro.
  ///
  /// In de, this message translates to:
  /// **'Nur aktive Integrationen gehen ans Modell. Ausgeschaltete kosten keine Tokens.'**
  String get integrationsIntro;

  /// No description provided for @integrationsOwn.
  ///
  /// In de, this message translates to:
  /// **'Eigene Integrationen'**
  String get integrationsOwn;

  /// No description provided for @integrationsPaused.
  ///
  /// In de, this message translates to:
  /// **'pausiert'**
  String get integrationsPaused;

  /// No description provided for @integrationsPausedError.
  ///
  /// In de, this message translates to:
  /// **'{service}: Zugang abgelehnt oder unerwartete Antwort · pausiert'**
  String integrationsPausedError(String service);

  /// No description provided for @integrationsPermission.
  ///
  /// In de, this message translates to:
  /// **'Berechtigung'**
  String get integrationsPermission;

  /// No description provided for @integrationsPermission2.
  ///
  /// In de, this message translates to:
  /// **'Berechtigung'**
  String get integrationsPermission2;

  /// No description provided for @integrationsReachable.
  ///
  /// In de, this message translates to:
  /// **'{displayName} ist wieder erreichbar.'**
  String integrationsReachable(String displayName);

  /// No description provided for @integrationsRejected.
  ///
  /// In de, this message translates to:
  /// **'Abgewiesen: {reason}'**
  String integrationsRejected(String reason);

  /// No description provided for @integrationsTools.
  ///
  /// In de, this message translates to:
  /// **'{tools} Tools'**
  String integrationsTools(int tools);

  /// No description provided for @reconnectBringShare.
  ///
  /// In de, this message translates to:
  /// **'Ausweg: Artikel über „Teilen“ an die Bring!-App schicken.'**
  String get reconnectBringShare;

  /// No description provided for @reconnectErrDenied.
  ///
  /// In de, this message translates to:
  /// **'{service}: Zugang abgelehnt oder nicht eingerichtet. Bitte die Zugangsdaten prüfen.'**
  String reconnectErrDenied(String service);

  /// No description provided for @reconnectErrFailed.
  ///
  /// In de, this message translates to:
  /// **'{service}: Die Verbindung ist fehlgeschlagen (unerwartete Antwort).'**
  String reconnectErrFailed(String service);

  /// No description provided for @reconnectErrOther.
  ///
  /// In de, this message translates to:
  /// **'{service}: Die Verbindung ist fehlgeschlagen.'**
  String reconnectErrOther(String service);

  /// No description provided for @reconnectErrUnavailable.
  ///
  /// In de, this message translates to:
  /// **'{service} ist nicht erreichbar oder antwortet nicht. Später erneut versuchen.'**
  String reconnectErrUnavailable(String service);

  /// No description provided for @levelDetails.
  ///
  /// In de, this message translates to:
  /// **'Details'**
  String get levelDetails;

  /// No description provided for @levelHelpA.
  ///
  /// In de, this message translates to:
  /// **'Immer, auch bei gesperrtem Gerät und ohne erkannte Stimme.'**
  String get levelHelpA;

  /// No description provided for @levelHelpB.
  ///
  /// In de, this message translates to:
  /// **'Bei erkannter Stimme (auch gesperrt) oder entsperrtem Gerät.'**
  String get levelHelpB;

  /// No description provided for @levelHelpC.
  ///
  /// In de, this message translates to:
  /// **'Nur bei entsperrtem Gerät.'**
  String get levelHelpC;

  /// No description provided for @levelHelpD.
  ///
  /// In de, this message translates to:
  /// **'Entsperrt und mit Bestätigung auf dem Display.'**
  String get levelHelpD;

  /// No description provided for @levelKindClimate.
  ///
  /// In de, this message translates to:
  /// **'Klima'**
  String get levelKindClimate;

  /// No description provided for @levelKindCover.
  ///
  /// In de, this message translates to:
  /// **'Rollos'**
  String get levelKindCover;

  /// No description provided for @levelKindIntro.
  ///
  /// In de, this message translates to:
  /// **'Gilt für alle Geräte einer Art, die keine eigene Stufe haben. Schloss, Alarm, Garage, Tor und Tür gibt es nur je Gerät (Home-Assistant-Einrichtung). Eine eigene Gerätestufe gewinnt immer. Szenen mit unbekannten Mitgliedern laufen höchstens auf Stufe C, Szenen mit kritischem Mitglied nie niedriger als dieses.'**
  String get levelKindIntro;

  /// No description provided for @levelKindLight.
  ///
  /// In de, this message translates to:
  /// **'Licht'**
  String get levelKindLight;

  /// No description provided for @levelKindLoading.
  ///
  /// In de, this message translates to:
  /// **'Lädt …'**
  String get levelKindLoading;

  /// No description provided for @levelKindMedia.
  ///
  /// In de, this message translates to:
  /// **'Medien'**
  String get levelKindMedia;

  /// No description provided for @levelKindScene.
  ///
  /// In de, this message translates to:
  /// **'Szenen'**
  String get levelKindScene;

  /// No description provided for @levelKindSummaryCover.
  ///
  /// In de, this message translates to:
  /// **'Standard: D (Rollos mit altem „ohne Rückfrage“: C)'**
  String get levelKindSummaryCover;

  /// No description provided for @levelKindSwitch.
  ///
  /// In de, this message translates to:
  /// **'Schalter'**
  String get levelKindSwitch;

  /// No description provided for @levelKindTitle.
  ///
  /// In de, this message translates to:
  /// **'Stufe je Geräteart'**
  String get levelKindTitle;

  /// No description provided for @levelLegacyRemove.
  ///
  /// In de, this message translates to:
  /// **'Altes „Immer bestätigen“ entfernen (das Gerät bestimmt die Stufe)'**
  String get levelLegacyRemove;

  /// No description provided for @levelRefCall.
  ///
  /// In de, this message translates to:
  /// **'Die Stufe legst du je Geräteart fest (unten) oder je Gerät in der Home-Assistant-Einrichtung.'**
  String get levelRefCall;

  /// No description provided for @levelRefSecure.
  ///
  /// In de, this message translates to:
  /// **'Schloss, Alarm, Garage, Tor und Tür: Stufe je Gerät in der Home-Assistant-Einrichtung. Rollos: siehe „Stufe je Geräteart“.'**
  String get levelRefSecure;

  /// No description provided for @levelRestore.
  ///
  /// In de, this message translates to:
  /// **'Standard wiederherstellen'**
  String get levelRestore;

  /// No description provided for @levelSemantics.
  ///
  /// In de, this message translates to:
  /// **'{name}: Stufe {level}'**
  String levelSemantics(String name, String level);

  /// No description provided for @levelStateChanged.
  ///
  /// In de, this message translates to:
  /// **'geändert'**
  String get levelStateChanged;

  /// No description provided for @levelStateDefault.
  ///
  /// In de, this message translates to:
  /// **'Standard'**
  String get levelStateDefault;

  /// No description provided for @levelSummary.
  ///
  /// In de, this message translates to:
  /// **'Stufe {level} · {state}'**
  String levelSummary(String level, String state);

  /// No description provided for @levelSummaryKind.
  ///
  /// In de, this message translates to:
  /// **'Stufe {level} · von Geräteart'**
  String levelSummaryKind(String level);

  /// No description provided for @levelSummaryKindScene.
  ///
  /// In de, this message translates to:
  /// **'Höchstens Stufe {level} · von Geräteart, je nach Mitgliedern'**
  String levelSummaryKindScene(String level);

  /// No description provided for @levelSummaryScene.
  ///
  /// In de, this message translates to:
  /// **'Standard: je nach Mitgliedern'**
  String get levelSummaryScene;

  /// No description provided for @levelWarnConfirm.
  ///
  /// In de, this message translates to:
  /// **'Trotzdem ändern'**
  String get levelWarnConfirm;

  /// No description provided for @levelWarnDeviceMessage.
  ///
  /// In de, this message translates to:
  /// **'Schloss, Alarm, Tor oder Tür lassen sich dann ohne Bestätigung bedienen, bei Stufe A sogar bei gesperrtem Gerät. Die Verantwortung liegt bei dir.'**
  String get levelWarnDeviceMessage;

  /// No description provided for @levelWarnKindCover.
  ///
  /// In de, this message translates to:
  /// **'Alle Rollos dieser Art lassen sich dann ohne Bestätigung bewegen, bei Stufe A sogar bei gesperrtem Gerät. Garage, Tor und Tür sind davon ausgenommen. Die Verantwortung liegt bei dir.'**
  String get levelWarnKindCover;

  /// No description provided for @levelWarnKindSwitch.
  ///
  /// In de, this message translates to:
  /// **'Schalter können Steckdosen und damit Geräte wie Heizung oder Herd schalten. Bei Stufe A geht das sogar bei gesperrtem Gerät. Die Verantwortung liegt bei dir.'**
  String get levelWarnKindSwitch;

  /// No description provided for @levelWarnPersonalMessage.
  ///
  /// In de, this message translates to:
  /// **'Dieses Tool liest oder verändert persönliche Inhalte. Bei Stufe A läuft es sogar bei gesperrtem Gerät mit jeder Stimme, bei Stufe B mit einer erkannten Stimme (eine Aufnahme kann täuschen). Die Verantwortung liegt bei dir.'**
  String get levelWarnPersonalMessage;

  /// No description provided for @levelWarnTitle.
  ///
  /// In de, this message translates to:
  /// **'Weniger Schutz?'**
  String get levelWarnTitle;

  /// No description provided for @levelWarnToolMessage.
  ///
  /// In de, this message translates to:
  /// **'Dieses Tool wirkt nach außen und kann dann ohne Bestätigung laufen, bei Stufe A sogar bei gesperrtem Gerät. Die Verantwortung liegt bei dir.'**
  String get levelWarnToolMessage;

  /// No description provided for @listsAccessLost.
  ///
  /// In de, this message translates to:
  /// **'Kein Zugriff mehr – Datei neu auswählen'**
  String get listsAccessLost;

  /// No description provided for @listsAdd.
  ///
  /// In de, this message translates to:
  /// **'+ Liste'**
  String get listsAdd;

  /// No description provided for @listsAliases.
  ///
  /// In de, this message translates to:
  /// **'Andere Namen, mit Komma getrennt (optional)'**
  String get listsAliases;

  /// No description provided for @listsAlso.
  ///
  /// In de, this message translates to:
  /// **'auch: {v}'**
  String listsAlso(String v);

  /// No description provided for @listsChooseFile.
  ///
  /// In de, this message translates to:
  /// **'Datei wählen'**
  String get listsChooseFile;

  /// No description provided for @listsDeleteBody.
  ///
  /// In de, this message translates to:
  /// **'Die Liste verschwindet aus Wendelin. Die Datei bleibt erhalten.'**
  String get listsDeleteBody;

  /// No description provided for @listsDeleteList.
  ///
  /// In de, this message translates to:
  /// **'Liste löschen'**
  String get listsDeleteList;

  /// No description provided for @listsDeleteTitle.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ löschen?'**
  String listsDeleteTitle(String name);

  /// No description provided for @listsEditList.
  ///
  /// In de, this message translates to:
  /// **'Liste bearbeiten'**
  String get listsEditList;

  /// No description provided for @listsFile.
  ///
  /// In de, this message translates to:
  /// **'Datei'**
  String get listsFile;

  /// No description provided for @listsIntro.
  ///
  /// In de, this message translates to:
  /// **'Jede Liste ist eine Markdown-Datei auf dem Gerät (z. B. im Obsidian-Vault). Einträge stehen dort als „- [ ] …“.'**
  String get listsIntro;

  /// No description provided for @listsListFallback.
  ///
  /// In de, this message translates to:
  /// **'Liste'**
  String get listsListFallback;

  /// No description provided for @listsNameHint.
  ///
  /// In de, this message translates to:
  /// **'Name, z. B. Einkaufen'**
  String get listsNameHint;

  /// No description provided for @listsNeedNameFile.
  ///
  /// In de, this message translates to:
  /// **'Name und Datei sind nötig.'**
  String get listsNeedNameFile;

  /// No description provided for @listsNewFile.
  ///
  /// In de, this message translates to:
  /// **'Neue Datei'**
  String get listsNewFile;

  /// No description provided for @listsNewList.
  ///
  /// In de, this message translates to:
  /// **'Neue Liste'**
  String get listsNewList;

  /// No description provided for @listsNoAliases.
  ///
  /// In de, this message translates to:
  /// **'Ohne Aliase'**
  String get listsNoAliases;

  /// No description provided for @listsNoFile.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Datei'**
  String get listsNoFile;

  /// No description provided for @listsSection.
  ///
  /// In de, this message translates to:
  /// **'Abschnitt „{section}“'**
  String listsSection(String section);

  /// No description provided for @listsSectionLabel.
  ///
  /// In de, this message translates to:
  /// **'Abschnitt in der Datei, z. B. Todo (optional)'**
  String get listsSectionLabel;

  /// No description provided for @listsTaskDefault.
  ///
  /// In de, this message translates to:
  /// **'Standard-Aufgabenliste'**
  String get listsTaskDefault;

  /// No description provided for @listsTaskDefaultDetail.
  ///
  /// In de, this message translates to:
  /// **'Aufgaben mit Fälligkeit landen hier, wenn keine Liste genannt wird.'**
  String get listsTaskDefaultDetail;

  /// No description provided for @integrationsLocationRationale.
  ///
  /// In de, this message translates to:
  /// **'Damit Wendelin sagen kann, wo du bist, und Entfernungen und Navigation vorbereiten kann, braucht es den Standortzugriff. Android fragt dich gleich danach. Wendelin fragt den Standort nur, wenn du danach fragst (nie im Hintergrund), schickt ihn nicht an Cloud-Modelle unterhalb deiner Datenschutzstufe und schreibt ihn nicht ins Prüfprotokoll. „Ungefähr“ reicht für Ortsnamen und Luftlinie.'**
  String get integrationsLocationRationale;

  /// No description provided for @confHandOverDetail.
  ///
  /// In de, this message translates to:
  /// **'{toName} hat eine niedrigere Datenschutzstufe als {fromName}. Deine Anfrage und der bisherige Verlauf gehen dann dorthin.'**
  String confHandOverDetail(String toName, String fromName);

  /// No description provided for @confHandOverTitle.
  ///
  /// In de, this message translates to:
  /// **'An {toName} übergeben?'**
  String confHandOverTitle(String toName);

  /// No description provided for @confHintTap.
  ///
  /// In de, this message translates to:
  /// **'Antworte per Tipp'**
  String get confHintTap;

  /// No description provided for @confHintVoice.
  ///
  /// In de, this message translates to:
  /// **'Sag einfach „ja“ oder „nein“'**
  String get confHintVoice;

  /// No description provided for @confMoreLines.
  ///
  /// In de, this message translates to:
  /// **'… {rest} weitere Zeilen'**
  String confMoreLines(int rest);

  /// No description provided for @confYesHandOver.
  ///
  /// In de, this message translates to:
  /// **'Ja, übergeben'**
  String get confYesHandOver;

  /// No description provided for @mainCancelListening.
  ///
  /// In de, this message translates to:
  /// **'Zuhören abbrechen'**
  String get mainCancelListening;

  /// No description provided for @mainCheckProvider.
  ///
  /// In de, this message translates to:
  /// **'Provider prüfen'**
  String get mainCheckProvider;

  /// No description provided for @mainCostLabel.
  ///
  /// In de, this message translates to:
  /// **'Kosten {costLabel}'**
  String mainCostLabel(String costLabel);

  /// No description provided for @mainCostToday.
  ///
  /// In de, this message translates to:
  /// **'heute {v}'**
  String mainCostToday(String v);

  /// No description provided for @mainDeleteEventTitle.
  ///
  /// In de, this message translates to:
  /// **'Termin löschen?'**
  String get mainDeleteEventTitle;

  /// No description provided for @mainFollowUpCountdown.
  ///
  /// In de, this message translates to:
  /// **'{followUpListeningText} {seconds} s'**
  String mainFollowUpCountdown(String followUpListeningText, int seconds);

  /// No description provided for @mainGpuBlockMessage.
  ///
  /// In de, this message translates to:
  /// **'Die GPU-Prüfung von {name} über NVIDIA ist fehlgeschlagen oder nicht möglich.{v} Deine Anfrage wurde nicht gesendet. Du kannst sie einmalig ohne GPU-Prüfung senden. Die übrigen Prüfungen bleiben aktiv.'**
  String mainGpuBlockMessage(String name, String v);

  /// No description provided for @mainGpuCheckFailedTitle.
  ///
  /// In de, this message translates to:
  /// **'GPU-Prüfung nicht bestanden'**
  String get mainGpuCheckFailedTitle;

  /// No description provided for @mainListening.
  ///
  /// In de, this message translates to:
  /// **'Ich höre zu …'**
  String get mainListening;

  /// No description provided for @mainMicCancelAnswer.
  ///
  /// In de, this message translates to:
  /// **'Antwort abbrechen'**
  String get mainMicCancelAnswer;

  /// No description provided for @mainMicHearing.
  ///
  /// In de, this message translates to:
  /// **'Wendelin hört mit: „Hey Wendelin“ sagen oder tippen'**
  String get mainMicHearing;

  /// No description provided for @mainMicSpeak.
  ///
  /// In de, this message translates to:
  /// **'Sprechen'**
  String get mainMicSpeak;

  /// No description provided for @mainMicStopListening.
  ///
  /// In de, this message translates to:
  /// **'Zuhören beenden'**
  String get mainMicStopListening;

  /// No description provided for @mainMicStopSpeech.
  ///
  /// In de, this message translates to:
  /// **'Sprachausgabe stoppen'**
  String get mainMicStopSpeech;

  /// No description provided for @mainMicUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Mikrofon nicht verfügbar'**
  String get mainMicUnavailable;

  /// No description provided for @mainNeedsModel.
  ///
  /// In de, this message translates to:
  /// **'Wendelin braucht ein Sprachmodell. Richte einen Provider mit deinem API-Key ein, danach kannst du loslegen.'**
  String get mainNeedsModel;

  /// No description provided for @mainNewConversation.
  ///
  /// In de, this message translates to:
  /// **'Neues Gespräch'**
  String get mainNewConversation;

  /// No description provided for @mainNoKeep.
  ///
  /// In de, this message translates to:
  /// **'Nein, behalten'**
  String get mainNoKeep;

  /// No description provided for @mainNoProviderYet.
  ///
  /// In de, this message translates to:
  /// **'Noch kein Provider eingerichtet'**
  String get mainNoProviderYet;

  /// No description provided for @mainProviderProfileUnusable.
  ///
  /// In de, this message translates to:
  /// **'Das Provider-Profil lässt sich nicht verwenden: {error}'**
  String mainProviderProfileUnusable(String error);

  /// No description provided for @mainReallyDeleteTitle.
  ///
  /// In de, this message translates to:
  /// **'Wirklich löschen?'**
  String get mainReallyDeleteTitle;

  /// No description provided for @mainSendWithoutGpuCheck.
  ///
  /// In de, this message translates to:
  /// **'Ohne GPU-Prüfung senden'**
  String get mainSendWithoutGpuCheck;

  /// No description provided for @mainSetUpProvider.
  ///
  /// In de, this message translates to:
  /// **'Provider einrichten'**
  String get mainSetUpProvider;

  /// No description provided for @mainShouldIDoThat.
  ///
  /// In de, this message translates to:
  /// **'Soll ich das tun?'**
  String get mainShouldIDoThat;

  /// No description provided for @mainStartDemo.
  ///
  /// In de, this message translates to:
  /// **'Demo ohne Provider starten'**
  String get mainStartDemo;

  /// No description provided for @mainToday.
  ///
  /// In de, this message translates to:
  /// **'Heute'**
  String get mainToday;

  /// No description provided for @mainTypeInstead.
  ///
  /// In de, this message translates to:
  /// **'Schreiben statt sprechen'**
  String get mainTypeInstead;

  /// No description provided for @mainViewRouting.
  ///
  /// In de, this message translates to:
  /// **'Routing ansehen'**
  String get mainViewRouting;

  /// No description provided for @mainYesDelete.
  ///
  /// In de, this message translates to:
  /// **'Ja, löschen'**
  String get mainYesDelete;

  /// No description provided for @mainYesDoIt.
  ///
  /// In de, this message translates to:
  /// **'Ja, ausführen'**
  String get mainYesDoIt;

  /// No description provided for @mainYesterday.
  ///
  /// In de, this message translates to:
  /// **'Gestern'**
  String get mainYesterday;

  /// No description provided for @overlayCloseAssistant.
  ///
  /// In de, this message translates to:
  /// **'Assistent schließen'**
  String get overlayCloseAssistant;

  /// No description provided for @overlayEnd.
  ///
  /// In de, this message translates to:
  /// **'Beenden'**
  String get overlayEnd;

  /// No description provided for @overlayFollowUpComing.
  ///
  /// In de, this message translates to:
  /// **'Gesprächsmodus aus · in den Einstellungen einschaltbar'**
  String get overlayFollowUpComing;

  /// No description provided for @overlayFollowUpWindow.
  ///
  /// In de, this message translates to:
  /// **'Hört noch {seconds} s zu · „Stopp“ beendet'**
  String overlayFollowUpWindow(int seconds);

  /// No description provided for @overlayKeepTalking.
  ///
  /// In de, this message translates to:
  /// **'Weiter sprechen'**
  String get overlayKeepTalking;

  /// No description provided for @overlayTextInput.
  ///
  /// In de, this message translates to:
  /// **'Texteingabe'**
  String get overlayTextInput;

  /// No description provided for @overlayUnlock.
  ///
  /// In de, this message translates to:
  /// **'Entsperren'**
  String get overlayUnlock;

  /// No description provided for @overlayUnlockCancelled.
  ///
  /// In de, this message translates to:
  /// **'Entsperren abgebrochen. Deine Anfrage wurde verworfen.'**
  String get overlayUnlockCancelled;

  /// No description provided for @privateBannerConfidential.
  ///
  /// In de, this message translates to:
  /// **'Vertraulich: Gedächtnis genutzt (seit {since})'**
  String privateBannerConfidential(String since);

  /// No description provided for @privateBannerPrivate.
  ///
  /// In de, this message translates to:
  /// **'Unterhaltung privat (seit {since})'**
  String privateBannerPrivate(String since);

  /// No description provided for @privateEscalationMemory.
  ///
  /// In de, this message translates to:
  /// **'Die Unterhaltung nutzt dein Gedächtnis (seit {since}). Mit „Ja“ sieht {toName} den bisherigen Verlauf, aber nicht das Gedächtnis selbst.'**
  String privateEscalationMemory(String since, String toName);

  /// No description provided for @privateEscalationPrivate.
  ///
  /// In de, this message translates to:
  /// **'Die Unterhaltung ist privat (seit {since}). Mit „Ja“ sieht {toName} auch ihre privaten Teile.'**
  String privateEscalationPrivate(String since, String toName);

  /// No description provided for @retryOfferDetail.
  ///
  /// In de, this message translates to:
  /// **'{fromName} antwortet gerade nicht. {toName} schützt deine Daten mindestens so gut. Schon ausgeführte Aktionen werden nicht wiederholt, nur die Antwort wird neu angefragt.'**
  String retryOfferDetail(String fromName, String toName);

  /// No description provided for @retryOfferSpoken.
  ///
  /// In de, this message translates to:
  /// **'{fromName} antwortet nicht. Mit {toName} nochmal? Ja oder nein?'**
  String retryOfferSpoken(String fromName, String toName);

  /// No description provided for @retryOfferTitle.
  ///
  /// In de, this message translates to:
  /// **'Mit {toName} nochmal?'**
  String retryOfferTitle(String toName);

  /// No description provided for @retryOfferYes.
  ///
  /// In de, this message translates to:
  /// **'Mit {toName} nochmal?'**
  String retryOfferYes(String toName);

  /// No description provided for @switchTopicBody.
  ///
  /// In de, this message translates to:
  /// **'Beim Wechsel des Modells beginnt ein neues Gespräch. Der aktuelle Verlauf wird beendet (im Verlauf bleibt er abrufbar).'**
  String get switchTopicBody;

  /// No description provided for @switchTopicBodyRunning.
  ///
  /// In de, this message translates to:
  /// **'Beim Wechsel des Modells beginnt ein neues Gespräch. Die laufende Antwort wird abgebrochen und der aktuelle Verlauf beendet (im Verlauf bleibt er abrufbar).'**
  String get switchTopicBodyRunning;

  /// No description provided for @switchTopicSwitch.
  ///
  /// In de, this message translates to:
  /// **'Wechseln'**
  String get switchTopicSwitch;

  /// No description provided for @switchTopicTitle.
  ///
  /// In de, this message translates to:
  /// **'Neues Gespräch beginnen?'**
  String get switchTopicTitle;

  /// No description provided for @mcpAddClientId.
  ///
  /// In de, this message translates to:
  /// **'Client-ID (optional)'**
  String get mcpAddClientId;

  /// No description provided for @mcpAddClientIdHint.
  ///
  /// In de, this message translates to:
  /// **'Leer lassen: Wendelin registriert sich selbst beim Server'**
  String get mcpAddClientIdHint;

  /// No description provided for @mcpAddConfirmAll.
  ///
  /// In de, this message translates to:
  /// **'Alle Tools bestätigen'**
  String get mcpAddConfirmAll;

  /// No description provided for @mcpAddConfirmAllHint.
  ///
  /// In de, this message translates to:
  /// **'Jeder Aufruf fragt nach'**
  String get mcpAddConfirmAllHint;

  /// No description provided for @mcpAddCustom.
  ///
  /// In de, this message translates to:
  /// **'Eigener Server'**
  String get mcpAddCustom;

  /// No description provided for @mcpAddHeaderLabel.
  ///
  /// In de, this message translates to:
  /// **'Header, z. B. X-Api-Key'**
  String get mcpAddHeaderLabel;

  /// No description provided for @mcpAddProblem.
  ///
  /// In de, this message translates to:
  /// **'Problem'**
  String get mcpAddProblem;

  /// No description provided for @mcpAddSensitive.
  ///
  /// In de, this message translates to:
  /// **'Sensibel'**
  String get mcpAddSensitive;

  /// No description provided for @mcpAddSensitiveHint.
  ///
  /// In de, this message translates to:
  /// **'Tools nur an Provider ab der eingestellten Stufe'**
  String get mcpAddSensitiveHint;

  /// No description provided for @mcpAddServerAddress.
  ///
  /// In de, this message translates to:
  /// **'Adresse'**
  String get mcpAddServerAddress;

  /// No description provided for @mcpAddServerInsecure.
  ///
  /// In de, this message translates to:
  /// **'Unverschlüsselt (http): nur im Heimnetz oder über Tailscale erlaubt'**
  String get mcpAddServerInsecure;

  /// No description provided for @mcpAddServerIntro.
  ///
  /// In de, this message translates to:
  /// **'Wähle eine Vorlage oder trage einen eigenen Server ein. Erreichbar über https oder im Heimnetz (Tailscale, WireGuard).'**
  String get mcpAddServerIntro;

  /// No description provided for @mcpAddServerTestConnection.
  ///
  /// In de, this message translates to:
  /// **'Verbindung prüfen'**
  String get mcpAddServerTestConnection;

  /// No description provided for @mcpAddServerTitle.
  ///
  /// In de, this message translates to:
  /// **'Server hinzufügen'**
  String get mcpAddServerTitle;

  /// No description provided for @mcpAddSignIn.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung'**
  String get mcpAddSignIn;

  /// No description provided for @mcpAddTokenHint.
  ///
  /// In de, this message translates to:
  /// **'Wird nie wieder angezeigt'**
  String get mcpAddTokenHint;

  /// No description provided for @mcpAddValue.
  ///
  /// In de, this message translates to:
  /// **'Wert'**
  String get mcpAddValue;

  /// No description provided for @mcpAddValueHint.
  ///
  /// In de, this message translates to:
  /// **'Wird nie wieder angezeigt'**
  String get mcpAddValueHint;

  /// No description provided for @mcpCheckHeaderMissing.
  ///
  /// In de, this message translates to:
  /// **'Bitte den Namen des Headers angeben.'**
  String get mcpCheckHeaderMissing;

  /// No description provided for @mcpCheckNameMissing.
  ///
  /// In de, this message translates to:
  /// **'Bitte einen Namen angeben.'**
  String get mcpCheckNameMissing;

  /// No description provided for @mcpCheckPlaceholders.
  ///
  /// In de, this message translates to:
  /// **'Bitte die Platzhalter in <…> in der Adresse ersetzen.'**
  String get mcpCheckPlaceholders;

  /// No description provided for @mcpCheckUrlIncomplete.
  ///
  /// In de, this message translates to:
  /// **'Bitte eine vollständige Adresse angeben (https://…).'**
  String get mcpCheckUrlIncomplete;

  /// No description provided for @mcpDetailActive.
  ///
  /// In de, this message translates to:
  /// **'Server aktiv'**
  String get mcpDetailActive;

  /// No description provided for @mcpDetailActiveLabel.
  ///
  /// In de, this message translates to:
  /// **'{name} aktiv'**
  String mcpDetailActiveLabel(String name);

  /// No description provided for @mcpDetailAuthLabel.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung nötig'**
  String get mcpDetailAuthLabel;

  /// No description provided for @mcpDetailBearer.
  ///
  /// In de, this message translates to:
  /// **'Bearer-Token'**
  String get mcpDetailBearer;

  /// No description provided for @mcpDetailCheck.
  ///
  /// In de, this message translates to:
  /// **'Prüfung: {v}'**
  String mcpDetailCheck(String v);

  /// No description provided for @mcpDetailCheck2.
  ///
  /// In de, this message translates to:
  /// **'Prüfung: {v}'**
  String mcpDetailCheck2(String v);

  /// No description provided for @mcpDetailConfirmAll.
  ///
  /// In de, this message translates to:
  /// **'Alle Tools bestätigen'**
  String get mcpDetailConfirmAll;

  /// No description provided for @mcpDetailConfirmAllHint.
  ///
  /// In de, this message translates to:
  /// **'Jeder Aufruf fragt nach, egal was der Server angibt'**
  String get mcpDetailConfirmAllHint;

  /// No description provided for @mcpDetailDelete.
  ///
  /// In de, this message translates to:
  /// **'Server löschen'**
  String get mcpDetailDelete;

  /// No description provided for @mcpDetailDeleteBody.
  ///
  /// In de, this message translates to:
  /// **'Konfiguration, Tool-Liste und alle Zugangsdaten dieses Servers werden entfernt.'**
  String get mcpDetailDeleteBody;

  /// No description provided for @mcpDetailDeleteHint.
  ///
  /// In de, this message translates to:
  /// **'Entfernt Konfiguration, Tool-Liste und Zugangsdaten'**
  String get mcpDetailDeleteHint;

  /// No description provided for @mcpDetailDeleteTitle.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ löschen?'**
  String mcpDetailDeleteTitle(String name);

  /// No description provided for @mcpDetailIntro.
  ///
  /// In de, this message translates to:
  /// **'Tool-Argumente gehen an diesen Server: {url}'**
  String mcpDetailIntro(String url);

  /// No description provided for @mcpDetailIntroHint.
  ///
  /// In de, this message translates to:
  /// **'Tippe auf ein Tool für Nachfrage und Risikostufe. MCP-Tools haben kein Rückgängig: Änderungen passieren auf dem Server.'**
  String get mcpDetailIntroHint;

  /// No description provided for @mcpDetailLastCheck.
  ///
  /// In de, this message translates to:
  /// **'Letzte Prüfung: {v}'**
  String mcpDetailLastCheck(String v);

  /// No description provided for @mcpDetailNeverShown.
  ///
  /// In de, this message translates to:
  /// **'Wird nie wieder angezeigt'**
  String get mcpDetailNeverShown;

  /// No description provided for @mcpDetailNoTools.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Tools'**
  String get mcpDetailNoTools;

  /// No description provided for @mcpDetailNoToolsHint.
  ///
  /// In de, this message translates to:
  /// **'Server einschalten oder neu laden'**
  String get mcpDetailNoToolsHint;

  /// No description provided for @mcpDetailOauthHint.
  ///
  /// In de, this message translates to:
  /// **'OAuth-Anmeldung im Browser'**
  String get mcpDetailOauthHint;

  /// No description provided for @mcpDetailReplaceHeader.
  ///
  /// In de, this message translates to:
  /// **'Header {header} ersetzen'**
  String mcpDetailReplaceHeader(String header);

  /// No description provided for @mcpDetailReplaceToken.
  ///
  /// In de, this message translates to:
  /// **'Token ersetzen'**
  String get mcpDetailReplaceToken;

  /// No description provided for @mcpDetailSensitive.
  ///
  /// In de, this message translates to:
  /// **'Sensibel'**
  String get mcpDetailSensitive;

  /// No description provided for @mcpDetailSensitiveHint.
  ///
  /// In de, this message translates to:
  /// **'Persönliche Daten: Tools nur an Provider ab der eingestellten Stufe'**
  String get mcpDetailSensitiveHint;

  /// No description provided for @mcpDetailSensitiveLabel.
  ///
  /// In de, this message translates to:
  /// **'{name} sensibel'**
  String mcpDetailSensitiveLabel(String name);

  /// No description provided for @mcpDetailSignIn.
  ///
  /// In de, this message translates to:
  /// **'Anmelden'**
  String get mcpDetailSignIn;

  /// No description provided for @mcpDetailSignInAgain.
  ///
  /// In de, this message translates to:
  /// **'Neu anmelden'**
  String get mcpDetailSignInAgain;

  /// No description provided for @mcpDetailSignOut.
  ///
  /// In de, this message translates to:
  /// **'Abmelden'**
  String get mcpDetailSignOut;

  /// No description provided for @mcpDetailSignOutHint.
  ///
  /// In de, this message translates to:
  /// **'Vergisst die Tokens auf diesem Gerät'**
  String get mcpDetailSignOutHint;

  /// No description provided for @mcpDetailTools.
  ///
  /// In de, this message translates to:
  /// **'Tools'**
  String get mcpDetailTools;

  /// No description provided for @mcpDetailUnreachableLabel.
  ///
  /// In de, this message translates to:
  /// **'nicht erreichbar'**
  String get mcpDetailUnreachableLabel;

  /// No description provided for @mcpDetailUntrusted.
  ///
  /// In de, this message translates to:
  /// **'Kann unsichere Inhalte enthalten'**
  String get mcpDetailUntrusted;

  /// No description provided for @mcpDetailUntrustedHint.
  ///
  /// In de, this message translates to:
  /// **'Antworten können Texte Dritter enthalten. Danach fragt Wendelin vor Aufrufen mit Netzziel nach. Nur für eigene Dienste mit bekannten Daten ausschalten.'**
  String get mcpDetailUntrustedHint;

  /// No description provided for @mcpDetailValueFor.
  ///
  /// In de, this message translates to:
  /// **'Wert für {header}'**
  String mcpDetailValueFor(String header);

  /// No description provided for @mcpDetailValueNeverShown.
  ///
  /// In de, this message translates to:
  /// **'Wert wird nie wieder angezeigt'**
  String get mcpDetailValueNeverShown;

  /// No description provided for @mcpLabelsAlwaysAsks.
  ///
  /// In de, this message translates to:
  /// **'fragt immer nach'**
  String get mcpLabelsAlwaysAsks;

  /// No description provided for @mcpLabelsAsksNoUndo.
  ///
  /// In de, this message translates to:
  /// **'fragt nach · kein Rückgängig'**
  String get mcpLabelsAsksNoUndo;

  /// No description provided for @mcpLabelsAuthAfterSave.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung nötig – nach dem Speichern anmelden'**
  String get mcpLabelsAuthAfterSave;

  /// No description provided for @mcpLabelsAuthCheck.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung nötig – Token oder Header prüfen'**
  String get mcpLabelsAuthCheck;

  /// No description provided for @mcpLabelsAuthRequired.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung nötig'**
  String get mcpLabelsAuthRequired;

  /// No description provided for @mcpLabelsChanges.
  ///
  /// In de, this message translates to:
  /// **'ändert'**
  String get mcpLabelsChanges;

  /// No description provided for @mcpLabelsCredentialsMissing.
  ///
  /// In de, this message translates to:
  /// **'Zugangsdaten fehlen'**
  String get mcpLabelsCredentialsMissing;

  /// No description provided for @mcpLabelsExternal.
  ///
  /// In de, this message translates to:
  /// **'Außenwirkung'**
  String get mcpLabelsExternal;

  /// No description provided for @mcpLabelsHintDestructive.
  ///
  /// In de, this message translates to:
  /// **'Server: destruktiv (destructiveHint)'**
  String get mcpLabelsHintDestructive;

  /// No description provided for @mcpLabelsHintNonDestructive.
  ///
  /// In de, this message translates to:
  /// **'Server: ändert, nicht destruktiv (destructiveHint: false)'**
  String get mcpLabelsHintNonDestructive;

  /// No description provided for @mcpLabelsHintNone.
  ///
  /// In de, this message translates to:
  /// **'Server: keine Angabe – gilt als Außenwirkung'**
  String get mcpLabelsHintNone;

  /// No description provided for @mcpLabelsHintReadOnly.
  ///
  /// In de, this message translates to:
  /// **'Server: nur lesend (readOnlyHint)'**
  String get mcpLabelsHintReadOnly;

  /// No description provided for @mcpLabelsNetworkHint.
  ///
  /// In de, this message translates to:
  /// **'Tailscale/WireGuard aktiv?'**
  String get mcpLabelsNetworkHint;

  /// No description provided for @mcpLabelsNoAsk.
  ///
  /// In de, this message translates to:
  /// **'ohne Nachfrage'**
  String get mcpLabelsNoAsk;

  /// No description provided for @mcpLabelsNoAskNoUndo.
  ///
  /// In de, this message translates to:
  /// **'ohne Nachfrage · kein Rückgängig'**
  String get mcpLabelsNoAskNoUndo;

  /// No description provided for @mcpLabelsNotChecked.
  ///
  /// In de, this message translates to:
  /// **'Noch nicht geprüft'**
  String get mcpLabelsNotChecked;

  /// No description provided for @mcpLabelsOneTool.
  ///
  /// In de, this message translates to:
  /// **'1 Tool'**
  String get mcpLabelsOneTool;

  /// No description provided for @mcpLabelsProtocolError.
  ///
  /// In de, this message translates to:
  /// **'kein gültiger MCP-Server'**
  String get mcpLabelsProtocolError;

  /// No description provided for @mcpLabelsProtocolErrorDetail.
  ///
  /// In de, this message translates to:
  /// **'Kein gültiger MCP-Server: {v}'**
  String mcpLabelsProtocolErrorDetail(String v);

  /// No description provided for @mcpLabelsProtocolErrorShort.
  ///
  /// In de, this message translates to:
  /// **'Kein gültiger MCP-Server'**
  String get mcpLabelsProtocolErrorShort;

  /// No description provided for @mcpLabelsReachable.
  ///
  /// In de, this message translates to:
  /// **'Erreichbar'**
  String get mcpLabelsReachable;

  /// No description provided for @mcpLabelsReads.
  ///
  /// In de, this message translates to:
  /// **'liest'**
  String get mcpLabelsReads;

  /// No description provided for @mcpLabelsReload.
  ///
  /// In de, this message translates to:
  /// **'Neu laden'**
  String get mcpLabelsReload;

  /// No description provided for @mcpLabelsReplaceToken.
  ///
  /// In de, this message translates to:
  /// **'Token ersetzen'**
  String get mcpLabelsReplaceToken;

  /// No description provided for @mcpLabelsSetUp.
  ///
  /// In de, this message translates to:
  /// **'Einrichten'**
  String get mcpLabelsSetUp;

  /// No description provided for @mcpLabelsSignIn.
  ///
  /// In de, this message translates to:
  /// **'Anmelden'**
  String get mcpLabelsSignIn;

  /// No description provided for @mcpLabelsSignInAgain.
  ///
  /// In de, this message translates to:
  /// **'Neu anmelden'**
  String get mcpLabelsSignInAgain;

  /// No description provided for @mcpLabelsSignInMissing.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung fehlt'**
  String get mcpLabelsSignInMissing;

  /// No description provided for @mcpLabelsTools.
  ///
  /// In de, this message translates to:
  /// **'{tools} Tools'**
  String mcpLabelsTools(int tools);

  /// No description provided for @mcpLabelsUnreachable.
  ///
  /// In de, this message translates to:
  /// **'nicht erreichbar'**
  String get mcpLabelsUnreachable;

  /// No description provided for @mcpLabelsUnreachableDetail.
  ///
  /// In de, this message translates to:
  /// **'Nicht erreichbar: {v}. {mcpUnreachableHint}'**
  String mcpLabelsUnreachableDetail(String v, String mcpUnreachableHint);

  /// No description provided for @mcpLabelsUnreachableShort.
  ///
  /// In de, this message translates to:
  /// **'Nicht erreichbar · {mcpUnreachableHint}'**
  String mcpLabelsUnreachableShort(String mcpUnreachableHint);

  /// No description provided for @mcpSecretCheck.
  ///
  /// In de, this message translates to:
  /// **'Prüfung: {v}'**
  String mcpSecretCheck(String v);

  /// No description provided for @mcpSecretSaved.
  ///
  /// In de, this message translates to:
  /// **'Gespeichert'**
  String get mcpSecretSaved;

  /// No description provided for @mcpSecretSignInFailed.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung fehlgeschlagen: {message}'**
  String mcpSecretSignInFailed(String message);

  /// No description provided for @mcpSecretSignInOnServer.
  ///
  /// In de, this message translates to:
  /// **'„{name}“: auf der Serverseite anmelden'**
  String mcpSecretSignInOnServer(String name);

  /// No description provided for @mcpSecretSignedIn.
  ///
  /// In de, this message translates to:
  /// **'Angemeldet'**
  String get mcpSecretSignedIn;

  /// No description provided for @mcpServersAdd.
  ///
  /// In de, this message translates to:
  /// **'+ Server'**
  String get mcpServersAdd;

  /// No description provided for @mcpServersContent.
  ///
  /// In de, this message translates to:
  /// **'Inhalt der Exportdatei'**
  String get mcpServersContent;

  /// No description provided for @mcpServersExportHint.
  ///
  /// In de, this message translates to:
  /// **'Serverliste ohne Tokens und Passwörter'**
  String get mcpServersExportHint;

  /// No description provided for @mcpServersImportHint.
  ///
  /// In de, this message translates to:
  /// **'Zugangsdaten werden neu abgefragt'**
  String get mcpServersImportHint;

  /// No description provided for @mcpServersImportTitle.
  ///
  /// In de, this message translates to:
  /// **'Serverliste importieren'**
  String get mcpServersImportTitle;

  /// No description provided for @mcpServersImported.
  ///
  /// In de, this message translates to:
  /// **'{length} Server importiert (ausgeschaltet)'**
  String mcpServersImported(int length);

  /// No description provided for @mcpServersImportedOne.
  ///
  /// In de, this message translates to:
  /// **'1 Server importiert (ausgeschaltet)'**
  String get mcpServersImportedOne;

  /// No description provided for @mcpServersIntro.
  ///
  /// In de, this message translates to:
  /// **'Tools von MCP-Servern, z. B. auf dem Homeserver über Tailscale. Tool-Argumente gehen an den jeweiligen Server.'**
  String get mcpServersIntro;

  /// No description provided for @mcpServersNone.
  ///
  /// In de, this message translates to:
  /// **'Noch kein Server'**
  String get mcpServersNone;

  /// No description provided for @mcpServersNoneHint.
  ///
  /// In de, this message translates to:
  /// **'Vorlage wählen oder eigene Adresse eintragen'**
  String get mcpServersNoneHint;

  /// No description provided for @mcpToolAlwaysAsk.
  ///
  /// In de, this message translates to:
  /// **'Immer nachfragen'**
  String get mcpToolAlwaysAsk;

  /// No description provided for @mcpToolAlwaysAsk2.
  ///
  /// In de, this message translates to:
  /// **'Immer nachfragen'**
  String get mcpToolAlwaysAsk2;

  /// No description provided for @mcpToolAlwaysAskHint.
  ///
  /// In de, this message translates to:
  /// **'jeder Aufruf wird bestätigt'**
  String get mcpToolAlwaysAskHint;

  /// No description provided for @mcpToolConfirmAllOn.
  ///
  /// In de, this message translates to:
  /// **'„Alle Tools bestätigen“ ist an: jeder Aufruf fragt nach.'**
  String get mcpToolConfirmAllOn;

  /// No description provided for @mcpToolDefaultNoUndo.
  ///
  /// In de, this message translates to:
  /// **'Standard: kein Rückgängig möglich'**
  String get mcpToolDefaultNoUndo;

  /// No description provided for @mcpToolEffective.
  ///
  /// In de, this message translates to:
  /// **'Wirksam: {v}'**
  String mcpToolEffective(String v);

  /// No description provided for @mcpToolExternalAsks.
  ///
  /// In de, this message translates to:
  /// **'Außenwirkung: fragt immer nach, das lässt sich nicht lockern.'**
  String get mcpToolExternalAsks;

  /// No description provided for @mcpToolNoAsk.
  ///
  /// In de, this message translates to:
  /// **'Ohne Nachfrage'**
  String get mcpToolNoAsk;

  /// No description provided for @mcpToolNoAsk2.
  ///
  /// In de, this message translates to:
  /// **'Ohne Nachfrage'**
  String get mcpToolNoAsk2;

  /// No description provided for @mcpToolNoUndoNow.
  ///
  /// In de, this message translates to:
  /// **'Kein Rückgängig: die Änderung passiert sofort auf dem Server'**
  String get mcpToolNoUndoNow;

  /// No description provided for @mcpToolReadsOnly.
  ///
  /// In de, this message translates to:
  /// **'liest nur'**
  String get mcpToolReadsOnly;

  /// No description provided for @mcpToolServerChecked.
  ///
  /// In de, this message translates to:
  /// **'Nur vom Server geprüft: {v}'**
  String mcpToolServerChecked(String v);

  /// No description provided for @toolChipSemantics.
  ///
  /// In de, this message translates to:
  /// **'Tool {toolName}, {status}'**
  String toolChipSemantics(String toolName, String status);

  /// No description provided for @toolResultUndoCountdown.
  ///
  /// In de, this message translates to:
  /// **'Rückgängig · {seconds} s'**
  String toolResultUndoCountdown(int seconds);

  /// No description provided for @toolResultUndoSemantics.
  ///
  /// In de, this message translates to:
  /// **'Rückgängig, noch {seconds, plural, one{{seconds} Sekunde} other{{seconds} Sekunden}}'**
  String toolResultUndoSemantics(int seconds);

  /// No description provided for @toolResultUndone.
  ///
  /// In de, this message translates to:
  /// **'Rückgängig gemacht'**
  String get toolResultUndone;

  /// No description provided for @toolTlsEncrypted.
  ///
  /// In de, this message translates to:
  /// **'Tools Ende-zu-Ende-verschlüsselt'**
  String get toolTlsEncrypted;

  /// No description provided for @toolTlsHint.
  ///
  /// In de, this message translates to:
  /// **'Tool-Aufrufe sind über die geprüfte Verbindung bis in die Enklave geschützt, aber nicht zusätzlich verschlüsselt.'**
  String get toolTlsHint;

  /// No description provided for @integrationsMediaRationale.
  ///
  /// In de, this message translates to:
  /// **'Damit Wendelin sagen kann, was läuft, und im Hörbuch oder Podcast spulen kann, braucht es den „Benachrichtigungszugriff“. Android öffnet gleich die Seite dazu: Wendelin in der Liste wählen und einschalten (sperrt Android die Freigabe, erklärt Wendelin danach, wie du sie erlaubst). Wendelin liest keine Benachrichtigungen, nur die Medienwiedergabe. Pause, Weiter und Zurück gehen auch ohne.'**
  String get integrationsMediaRationale;

  /// No description provided for @navigationAppDefault.
  ///
  /// In de, this message translates to:
  /// **'Standard (Google Maps, sonst Waze)'**
  String get navigationAppDefault;

  /// No description provided for @navigationAppHelp.
  ///
  /// In de, this message translates to:
  /// **'Welche App „Navigiere zu …“ öffnet. Nennst du im Befehl eine App („mit Waze“), gilt sie. Ist die gewählte App nicht eingeschaltet oder nicht installiert, meldet Wendelin das, statt eine andere zu öffnen.'**
  String get navigationAppHelp;

  /// No description provided for @navigationAppTitle.
  ///
  /// In de, this message translates to:
  /// **'Navigations-App'**
  String get navigationAppTitle;

  /// No description provided for @obsIndexBuilding.
  ///
  /// In de, this message translates to:
  /// **'Index wird aufgebaut …'**
  String get obsIndexBuilding;

  /// No description provided for @obsIndexBuildingProgress.
  ///
  /// In de, this message translates to:
  /// **'Index wird aufgebaut: {indexed} Notizen, noch {pending}'**
  String obsIndexBuildingProgress(int indexed, int pending);

  /// No description provided for @obsIndexCurrent.
  ///
  /// In de, this message translates to:
  /// **'{notes} im Index · aktuell'**
  String obsIndexCurrent(String notes);

  /// No description provided for @obsIndexIncomplete.
  ///
  /// In de, this message translates to:
  /// **'Index unvollständig: {error}'**
  String obsIndexIncomplete(String error);

  /// No description provided for @obsIndexNotBuilt.
  ///
  /// In de, this message translates to:
  /// **'Noch nicht aufgebaut'**
  String get obsIndexNotBuilt;

  /// No description provided for @obsIndexNotes.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, one{1 Notiz} other{{n} Notizen}}'**
  String obsIndexNotes(int n);

  /// No description provided for @obsIndexPartial.
  ///
  /// In de, this message translates to:
  /// **'{notes} im Index · Vault zu groß, nur teilweise'**
  String obsIndexPartial(String notes);

  /// No description provided for @obsIndexUnreadable.
  ///
  /// In de, this message translates to:
  /// **'{notes} im Index · {failed} nicht lesbar'**
  String obsIndexUnreadable(String notes, int failed);

  /// No description provided for @obsidianAccessGranted.
  ///
  /// In de, this message translates to:
  /// **'Zugriff erteilt'**
  String get obsidianAccessGranted;

  /// No description provided for @obsidianAccessGranted2.
  ///
  /// In de, this message translates to:
  /// **'Zugriff erteilt'**
  String get obsidianAccessGranted2;

  /// No description provided for @obsidianAccessLost.
  ///
  /// In de, this message translates to:
  /// **'Kein Zugriff mehr – Ordner neu wählen'**
  String get obsidianAccessLost;

  /// No description provided for @obsidianBuildIndex.
  ///
  /// In de, this message translates to:
  /// **'Index aufbauen'**
  String get obsidianBuildIndex;

  /// No description provided for @obsidianChooseFolder.
  ///
  /// In de, this message translates to:
  /// **'Wähle den Ordner deines Obsidian-Vaults'**
  String get obsidianChooseFolder;

  /// No description provided for @obsidianChooseOther.
  ///
  /// In de, this message translates to:
  /// **'Anderen Ordner wählen'**
  String get obsidianChooseOther;

  /// No description provided for @obsidianChooseVaultFolder.
  ///
  /// In de, this message translates to:
  /// **'Vault-Ordner wählen'**
  String get obsidianChooseVaultFolder;

  /// No description provided for @obsidianDailyNotes.
  ///
  /// In de, this message translates to:
  /// **'Tagesnotizen'**
  String get obsidianDailyNotes;

  /// No description provided for @obsidianDailySaved.
  ///
  /// In de, this message translates to:
  /// **'Tagesnotizen gespeichert.'**
  String get obsidianDailySaved;

  /// No description provided for @obsidianDateFormat.
  ///
  /// In de, this message translates to:
  /// **'Datumsformat wie in Obsidian'**
  String get obsidianDateFormat;

  /// No description provided for @obsidianFolder.
  ///
  /// In de, this message translates to:
  /// **'Ordner'**
  String get obsidianFolder;

  /// No description provided for @obsidianFolderHint.
  ///
  /// In de, this message translates to:
  /// **'Leer lassen = Vault-Wurzel. Neue Tagesnotizen landen in diesem Ordner.'**
  String get obsidianFolderHint;

  /// No description provided for @obsidianIndexBuilding.
  ///
  /// In de, this message translates to:
  /// **'Index wird aufgebaut'**
  String get obsidianIndexBuilding;

  /// No description provided for @obsidianIndexHint.
  ///
  /// In de, this message translates to:
  /// **'Wird automatisch aktualisiert (beim Start und vor jeder Suche). Der Knopf ist nur für den ersten Aufbau nötig.'**
  String get obsidianIndexHint;

  /// No description provided for @obsidianIntro.
  ///
  /// In de, this message translates to:
  /// **'Wendelin liest und ergänzt Notizen direkt im Vault-Ordner. Sync bleibt bei Obsidian Sync, Syncthing oder Git.'**
  String get obsidianIntro;

  /// No description provided for @obsidianNoAccess.
  ///
  /// In de, this message translates to:
  /// **'kein Zugriff'**
  String get obsidianNoAccess;

  /// No description provided for @obsidianNoVault.
  ///
  /// In de, this message translates to:
  /// **'Kein Vault gewählt'**
  String get obsidianNoVault;

  /// No description provided for @obsidianRemoveBody.
  ///
  /// In de, this message translates to:
  /// **'Wendelin verliert den Zugriff auf den Ordner. Die Notizen selbst bleiben unverändert.'**
  String get obsidianRemoveBody;

  /// No description provided for @obsidianRemoveTitle.
  ///
  /// In de, this message translates to:
  /// **'Vault entfernen?'**
  String get obsidianRemoveTitle;

  /// No description provided for @obsidianRemoveVault.
  ///
  /// In de, this message translates to:
  /// **'Vault entfernen'**
  String get obsidianRemoveVault;

  /// No description provided for @obsidianSaveDaily.
  ///
  /// In de, this message translates to:
  /// **'Tagesnotizen speichern'**
  String get obsidianSaveDaily;

  /// No description provided for @obsidianSearchIndex.
  ///
  /// In de, this message translates to:
  /// **'Suchindex'**
  String get obsidianSearchIndex;

  /// No description provided for @obsidianTemplate.
  ///
  /// In de, this message translates to:
  /// **'Vorlage (optional)'**
  String get obsidianTemplate;

  /// No description provided for @obsidianTemplateHint.
  ///
  /// In de, this message translates to:
  /// **'Vorlagen/Tagesnotiz'**
  String get obsidianTemplateHint;

  /// No description provided for @obsidianToday.
  ///
  /// In de, this message translates to:
  /// **'Heute: {path}'**
  String obsidianToday(String path);

  /// No description provided for @obsidianUnusable.
  ///
  /// In de, this message translates to:
  /// **'Nicht verwendbar: {message}'**
  String obsidianUnusable(String message);

  /// No description provided for @obsidianUnusable2.
  ///
  /// In de, this message translates to:
  /// **'Nicht verwendbar: {message}'**
  String obsidianUnusable2(String message);

  /// No description provided for @obsidianVault.
  ///
  /// In de, this message translates to:
  /// **'Vault'**
  String get obsidianVault;

  /// No description provided for @onboardingConversation.
  ///
  /// In de, this message translates to:
  /// **'Gespräch'**
  String get onboardingConversation;

  /// No description provided for @onboardingConversationIntro.
  ///
  /// In de, this message translates to:
  /// **'Soll Wendelin nach seinen Antworten kurz weiter zuhören, damit du ohne Tippen nachfragen kannst? Das lässt sich jederzeit unter Einstellungen → Sprache ändern.'**
  String get onboardingConversationIntro;

  /// No description provided for @onboardingDemoNoProvider.
  ///
  /// In de, this message translates to:
  /// **'Demo ohne Provider'**
  String get onboardingDemoNoProvider;

  /// No description provided for @onboardingInterfaceLanguage.
  ///
  /// In de, this message translates to:
  /// **'App-Sprache der Oberfläche'**
  String get onboardingInterfaceLanguage;

  /// No description provided for @onboardingKeepListening.
  ///
  /// In de, this message translates to:
  /// **'Ja, weiter zuhören'**
  String get onboardingKeepListening;

  /// No description provided for @onboardingLanguageModel.
  ///
  /// In de, this message translates to:
  /// **'Sprachmodell'**
  String get onboardingLanguageModel;

  /// No description provided for @onboardingLearnAndEnable.
  ///
  /// In de, this message translates to:
  /// **'Einlernen und einschalten'**
  String get onboardingLearnAndEnable;

  /// No description provided for @onboardingPermissionsIntro.
  ///
  /// In de, this message translates to:
  /// **'Schalte nur ein, was du brauchst. Berechtigungen fragt Android erst jetzt beim Einschalten.'**
  String get onboardingPermissionsIntro;

  /// No description provided for @onboardingProviderIntro.
  ///
  /// In de, this message translates to:
  /// **'Wendelin braucht einen Provider, z. B. Claude mit deinem API-Key oder ein eigenes Modell auf dem Homeserver.'**
  String get onboardingProviderIntro;

  /// No description provided for @onboardingSetUpAnotherProvider.
  ///
  /// In de, this message translates to:
  /// **'Weiteren Provider einrichten'**
  String get onboardingSetUpAnotherProvider;

  /// No description provided for @onboardingSkip.
  ///
  /// In de, this message translates to:
  /// **'Überspringen'**
  String get onboardingSkip;

  /// No description provided for @onboardingTapOnly.
  ///
  /// In de, this message translates to:
  /// **'Nein, nur nach Tippen'**
  String get onboardingTapOnly;

  /// No description provided for @onboardingWakeIntro.
  ///
  /// In de, this message translates to:
  /// **'Wendelin kann auf „Hey Wendelin“ hören, auch wenn das Telefon liegt. Dafür lernt er zuerst deine Stimme (etwa 3 Minuten). Das geht auch später in den Einstellungen.'**
  String get onboardingWakeIntro;

  /// No description provided for @onboardingWakeWord.
  ///
  /// In de, this message translates to:
  /// **'Aktivierungswort'**
  String get onboardingWakeWord;

  /// No description provided for @onboardingWelcome.
  ///
  /// In de, this message translates to:
  /// **'Willkommen'**
  String get onboardingWelcome;

  /// No description provided for @onboardingWelcomeIntro.
  ///
  /// In de, this message translates to:
  /// **'Wendelin ist dein Sprachassistent. In sechs Schritten ist er eingerichtet. Welche Sprache sprichst du mit ihm?'**
  String get onboardingWelcomeIntro;

  /// No description provided for @onboardingWhatMayWendelinDo.
  ///
  /// In de, this message translates to:
  /// **'Was darf Wendelin?'**
  String get onboardingWhatMayWendelinDo;

  /// No description provided for @auditEntrySession.
  ///
  /// In de, this message translates to:
  /// **'Sitzung'**
  String get auditEntrySession;

  /// No description provided for @auditEntryVerifications.
  ///
  /// In de, this message translates to:
  /// **'Prüfungen dieser Sitzung'**
  String get auditEntryVerifications;

  /// No description provided for @auditLogIntro.
  ///
  /// In de, this message translates to:
  /// **'Was Wendelin getan hat. Nie Schlüssel. Der Export enthält keine Texte, nur Zeiten, Arten und Ergebnisse.'**
  String get auditLogIntro;

  /// No description provided for @auditLogTitle.
  ///
  /// In de, this message translates to:
  /// **'Prüfprotokoll'**
  String get auditLogTitle;

  /// No description provided for @memoryCatFact.
  ///
  /// In de, this message translates to:
  /// **'Fakt'**
  String get memoryCatFact;

  /// No description provided for @memoryCatPerson.
  ///
  /// In de, this message translates to:
  /// **'Person'**
  String get memoryCatPerson;

  /// No description provided for @memoryCatPreference.
  ///
  /// In de, this message translates to:
  /// **'Vorliebe'**
  String get memoryCatPreference;

  /// No description provided for @memoryCatProject.
  ///
  /// In de, this message translates to:
  /// **'Projekt'**
  String get memoryCatProject;

  /// No description provided for @memoryDeleteTooltip.
  ///
  /// In de, this message translates to:
  /// **'Löschen: {text}'**
  String memoryDeleteTooltip(String text);

  /// No description provided for @memoryEditTitle.
  ///
  /// In de, this message translates to:
  /// **'Eintrag ändern'**
  String get memoryEditTitle;

  /// No description provided for @memoryExportMd.
  ///
  /// In de, this message translates to:
  /// **'Als Markdown exportieren'**
  String get memoryExportMd;

  /// No description provided for @memoryForget.
  ///
  /// In de, this message translates to:
  /// **'Vergessen'**
  String get memoryForget;

  /// No description provided for @memoryForgetTitle.
  ///
  /// In de, this message translates to:
  /// **'Eintrag vergessen?'**
  String get memoryForgetTitle;

  /// No description provided for @memoryFromPrivate.
  ///
  /// In de, this message translates to:
  /// **'Aus einer privaten Anfrage: geht nur an Provider ab {label}.'**
  String memoryFromPrivate(String label);

  /// No description provided for @memoryIntro.
  ///
  /// In de, this message translates to:
  /// **'Wendelin merkt sich nur, worum du ausdrücklich bittest. Passwörter, PINs, Karten- und Kontonummern werden nie gespeichert.'**
  String get memoryIntro;

  /// No description provided for @memoryLift.
  ///
  /// In de, this message translates to:
  /// **'Aufheben'**
  String get memoryLift;

  /// No description provided for @memoryLiftBody.
  ///
  /// In de, this message translates to:
  /// **'„{text}“ stammt aus einer privaten Anfrage und geht bisher nur an Provider ab {level}. Danach können ihn alle Provider sehen, die das Gedächtnis sehen dürfen.'**
  String memoryLiftBody(String text, String level);

  /// No description provided for @memoryLiftLimit.
  ///
  /// In de, this message translates to:
  /// **'Untergrenze aufheben'**
  String get memoryLiftLimit;

  /// No description provided for @memoryLiftTitle.
  ///
  /// In de, this message translates to:
  /// **'Untergrenze aufheben?'**
  String get memoryLiftTitle;

  /// No description provided for @memoryNone.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Einträge.'**
  String get memoryNone;

  /// No description provided for @memoryPrivateFrom.
  ///
  /// In de, this message translates to:
  /// **'{v} · privat, nur ab {label}'**
  String memoryPrivateFrom(String v, String label);

  /// No description provided for @memoryTitle.
  ///
  /// In de, this message translates to:
  /// **'Gedächtnis'**
  String get memoryTitle;

  /// No description provided for @privacyLevelEu.
  ///
  /// In de, this message translates to:
  /// **'EU'**
  String get privacyLevelEu;

  /// No description provided for @privacyLevelLocal.
  ///
  /// In de, this message translates to:
  /// **'lokal'**
  String get privacyLevelLocal;

  /// No description provided for @privacyLevelSemantics.
  ///
  /// In de, this message translates to:
  /// **'{text}, Datenschutzstufe {level}'**
  String privacyLevelSemantics(String text, String level);

  /// No description provided for @privacyLevelStandard.
  ///
  /// In de, this message translates to:
  /// **'Standard'**
  String get privacyLevelStandard;

  /// No description provided for @privacyLevelTee.
  ///
  /// In de, this message translates to:
  /// **'TEE'**
  String get privacyLevelTee;

  /// No description provided for @privacyScreenDays.
  ///
  /// In de, this message translates to:
  /// **'{d} Tage'**
  String privacyScreenDays(int d);

  /// No description provided for @privacyScreenDeleteAll.
  ///
  /// In de, this message translates to:
  /// **'Alles löschen'**
  String get privacyScreenDeleteAll;

  /// No description provided for @privacyScreenDeleteAllBody.
  ///
  /// In de, this message translates to:
  /// **'Alle Gesprächsverläufe, das Prüfprotokoll und die eingelernten Stimmen (Aktivierungswort) werden gelöscht. Das lässt sich nicht rückgängig machen. Gedächtnis und Einstellungen bleiben.'**
  String get privacyScreenDeleteAllBody;

  /// No description provided for @privacyScreenDeleteAllTitle.
  ///
  /// In de, this message translates to:
  /// **'Alles löschen?'**
  String get privacyScreenDeleteAllTitle;

  /// No description provided for @privacyScreenDeleteHistory.
  ///
  /// In de, this message translates to:
  /// **'Verläufe und Protokoll löschen'**
  String get privacyScreenDeleteHistory;

  /// No description provided for @privacyScreenEntries.
  ///
  /// In de, this message translates to:
  /// **'{n} Einträge'**
  String privacyScreenEntries(int n);

  /// No description provided for @privacyScreenGeneralLog.
  ///
  /// In de, this message translates to:
  /// **'Allgemeines Prüfprotokoll'**
  String get privacyScreenGeneralLog;

  /// No description provided for @privacyScreenIntro.
  ///
  /// In de, this message translates to:
  /// **'Verläufe und Prüfprotokoll bleiben auf dem Gerät. Ältere Einträge löscht Wendelin automatisch.'**
  String get privacyScreenIntro;

  /// No description provided for @privacyScreenKindConfirmation.
  ///
  /// In de, this message translates to:
  /// **'Bestätigung'**
  String get privacyScreenKindConfirmation;

  /// No description provided for @privacyScreenKindEscalation.
  ///
  /// In de, this message translates to:
  /// **'Eskalation'**
  String get privacyScreenKindEscalation;

  /// No description provided for @privacyScreenKindRequest.
  ///
  /// In de, this message translates to:
  /// **'Anfrage'**
  String get privacyScreenKindRequest;

  /// No description provided for @privacyScreenKindTool.
  ///
  /// In de, this message translates to:
  /// **'Tool'**
  String get privacyScreenKindTool;

  /// No description provided for @privacyScreenKindVerification.
  ///
  /// In de, this message translates to:
  /// **'Prüfung'**
  String get privacyScreenKindVerification;

  /// No description provided for @privacyScreenManyEntries.
  ///
  /// In de, this message translates to:
  /// **'200+ Einträge'**
  String get privacyScreenManyEntries;

  /// No description provided for @privacyScreenOneEntry.
  ///
  /// In de, this message translates to:
  /// **'1 Eintrag'**
  String get privacyScreenOneEntry;

  /// No description provided for @privacyScreenOneYear.
  ///
  /// In de, this message translates to:
  /// **'1 Jahr'**
  String get privacyScreenOneYear;

  /// No description provided for @privacyScreenProtectScreen.
  ///
  /// In de, this message translates to:
  /// **'Bildschirminhalt schützen'**
  String get privacyScreenProtectScreen;

  /// No description provided for @privacyScreenProtectScreenHint.
  ///
  /// In de, this message translates to:
  /// **'Keine Screenshots, im App-Wechsler verdeckt. Das Assistenten-Overlay ist immer geschützt.'**
  String get privacyScreenProtectScreenHint;

  /// No description provided for @privacyScreenRetention.
  ///
  /// In de, this message translates to:
  /// **'Aufbewahrung'**
  String get privacyScreenRetention;

  /// No description provided for @privacyScreenTeeLog.
  ///
  /// In de, this message translates to:
  /// **'TEE-Prüfprotokoll'**
  String get privacyScreenTeeLog;

  /// No description provided for @privacyScreenTeeLogHint.
  ///
  /// In de, this message translates to:
  /// **'Prüfung der Anbieter mit geschützter Umgebung, GPU-Prüfung über NVIDIA'**
  String get privacyScreenTeeLogHint;

  /// No description provided for @privacyScreenUndone.
  ///
  /// In de, this message translates to:
  /// **'{v} · rückgängig · {v2}'**
  String privacyScreenUndone(String v, String v2);

  /// No description provided for @areaAssistant.
  ///
  /// In de, this message translates to:
  /// **'Assistent'**
  String get areaAssistant;

  /// No description provided for @areaAssistantDetail.
  ///
  /// In de, this message translates to:
  /// **'Standard-Assistent, dein Name, Persönlichkeit'**
  String get areaAssistantDetail;

  /// No description provided for @areaCosts.
  ///
  /// In de, this message translates to:
  /// **'Kosten'**
  String get areaCosts;

  /// No description provided for @areaCostsDetail.
  ///
  /// In de, this message translates to:
  /// **'Heute und im Monat je Provider'**
  String get areaCostsDetail;

  /// No description provided for @areaHttpTools.
  ///
  /// In de, this message translates to:
  /// **'HTTP-Tools'**
  String get areaHttpTools;

  /// No description provided for @areaIntegrations.
  ///
  /// In de, this message translates to:
  /// **'Integrationen'**
  String get areaIntegrations;

  /// No description provided for @areaIntegrationsDetail.
  ///
  /// In de, this message translates to:
  /// **'Was Wendelin darf, Tools, Risikostufen'**
  String get areaIntegrationsDetail;

  /// No description provided for @areaMcp.
  ///
  /// In de, this message translates to:
  /// **'MCP-Server'**
  String get areaMcp;

  /// No description provided for @areaPrivacy.
  ///
  /// In de, this message translates to:
  /// **'Datenschutz und Logs'**
  String get areaPrivacy;

  /// No description provided for @areaPrivacyDetail.
  ///
  /// In de, this message translates to:
  /// **'Aufbewahrung, Prüfprotokoll, Export'**
  String get areaPrivacyDetail;

  /// No description provided for @areaProvider.
  ///
  /// In de, this message translates to:
  /// **'Provider'**
  String get areaProvider;

  /// No description provided for @areaProviderDetail.
  ///
  /// In de, this message translates to:
  /// **'Profile, Standard, Budget'**
  String get areaProviderDetail;

  /// No description provided for @areaRouting.
  ///
  /// In de, this message translates to:
  /// **'Routing'**
  String get areaRouting;

  /// No description provided for @areaRoutingDetail.
  ///
  /// In de, this message translates to:
  /// **'Regeln, Testfeld, Import und Export'**
  String get areaRoutingDetail;

  /// No description provided for @areaSpeech.
  ///
  /// In de, this message translates to:
  /// **'Sprache'**
  String get areaSpeech;

  /// No description provided for @areaSpeechDetail.
  ///
  /// In de, this message translates to:
  /// **'Spracherkennung, Stimme, Tempo'**
  String get areaSpeechDetail;

  /// No description provided for @areaWakeWord.
  ///
  /// In de, this message translates to:
  /// **'Aktivierungswort'**
  String get areaWakeWord;

  /// No description provided for @areaWakeWordDetail.
  ///
  /// In de, this message translates to:
  /// **'Hey Wendelin einlernen, Modell, Dienst'**
  String get areaWakeWordDetail;

  /// No description provided for @costsIntro.
  ///
  /// In de, this message translates to:
  /// **'Nach den Preisen im Modellkatalog, in US-Dollar.'**
  String get costsIntro;

  /// No description provided for @costsMonth.
  ///
  /// In de, this message translates to:
  /// **'Monat {v}'**
  String costsMonth(String v);

  /// No description provided for @costsNoProviders.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Provider.'**
  String get costsNoProviders;

  /// No description provided for @costsOfBudget.
  ///
  /// In de, this message translates to:
  /// **'von {v}'**
  String costsOfBudget(String v);

  /// No description provided for @costsToday.
  ///
  /// In de, this message translates to:
  /// **'heute {v}'**
  String costsToday(String v);

  /// No description provided for @providerChipLevel.
  ///
  /// In de, this message translates to:
  /// **'Datenschutzstufe {level}'**
  String providerChipLevel(String level);

  /// No description provided for @providerChipReceipt.
  ///
  /// In de, this message translates to:
  /// **'Quittung {status}'**
  String providerChipReceipt(String status);

  /// No description provided for @providerChipSemantics.
  ///
  /// In de, this message translates to:
  /// **'Provider {name}'**
  String providerChipSemantics(String name);

  /// No description provided for @providerModelRecommendedBadge.
  ///
  /// In de, this message translates to:
  /// **'Empfohlen'**
  String get providerModelRecommendedBadge;

  /// No description provided for @providerModelRecommendedReason.
  ///
  /// In de, this message translates to:
  /// **'{hits} von {runs} Testläufen richtig, typisch {p50} s, gemessen am {date}'**
  String providerModelRecommendedReason(
    String hits,
    String runs,
    String p50,
    String date,
  );

  /// No description provided for @providerModelRecommendedWeaker.
  ///
  /// In de, this message translates to:
  /// **'Das beste Modell dieses Anbieters, aber schwächer als bei Phala und Tinfoil.'**
  String get providerModelRecommendedWeaker;

  /// No description provided for @providerSetupBudgetFormat.
  ///
  /// In de, this message translates to:
  /// **'Budget: Betrag in Dollar, z. B. 5 oder 2,50'**
  String get providerSetupBudgetFormat;

  /// No description provided for @providerSetupConnected.
  ///
  /// In de, this message translates to:
  /// **'Verbindung steht'**
  String get providerSetupConnected;

  /// No description provided for @providerSetupConnectedEnterModel.
  ///
  /// In de, this message translates to:
  /// **'Verbindung steht. Bitte die Modell-ID eingeben.'**
  String get providerSetupConnectedEnterModel;

  /// No description provided for @providerSetupConnectedModels.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, one{Verbindung steht, 1 Modell gefunden.} other{Verbindung steht, {n} Modelle gefunden.}}'**
  String providerSetupConnectedModels(int n);

  /// No description provided for @providerSetupConnectionFailed.
  ///
  /// In de, this message translates to:
  /// **'Verbindung fehlgeschlagen'**
  String get providerSetupConnectionFailed;

  /// No description provided for @providerSetupEditTitle.
  ///
  /// In de, this message translates to:
  /// **'Provider bearbeiten'**
  String get providerSetupEditTitle;

  /// No description provided for @providerSetupIntroCredentials.
  ///
  /// In de, this message translates to:
  /// **'Der Key wird nur im sicheren Speicher des Geräts abgelegt.'**
  String get providerSetupIntroCredentials;

  /// No description provided for @providerSetupIntroFinish.
  ///
  /// In de, this message translates to:
  /// **'Datenschutzstufe und optional ein Monatsbudget.'**
  String get providerSetupIntroFinish;

  /// No description provided for @providerSetupIntroModel.
  ///
  /// In de, this message translates to:
  /// **'Wähle das Standardmodell.'**
  String get providerSetupIntroModel;

  /// No description provided for @providerSetupIntroTemplate.
  ///
  /// In de, this message translates to:
  /// **'Wähle, mit wem Wendelin sprechen soll.'**
  String get providerSetupIntroTemplate;

  /// No description provided for @providerSetupModelListFailed.
  ///
  /// In de, this message translates to:
  /// **'Modellliste nicht verfügbar ({reason}). Bitte die Modell-ID eingeben.'**
  String providerSetupModelListFailed(String reason);

  /// No description provided for @providerSetupModelListUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Modellliste nicht verfügbar'**
  String get providerSetupModelListUnavailable;

  /// No description provided for @providerSetupModelUnusable.
  ///
  /// In de, this message translates to:
  /// **'Modell nicht nutzbar'**
  String get providerSetupModelUnusable;

  /// No description provided for @providerSetupModelsFound.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, one{1 Modell gefunden} other{{n} Modelle gefunden}}'**
  String providerSetupModelsFound(int n);

  /// No description provided for @providerSetupNoModelList.
  ///
  /// In de, this message translates to:
  /// **'Keine Modellliste. Bitte die Modell-ID eingeben.'**
  String get providerSetupNoModelList;

  /// No description provided for @providerSetupProviderSetupApiKeyOptional.
  ///
  /// In de, this message translates to:
  /// **'API-Key (optional)'**
  String get providerSetupProviderSetupApiKeyOptional;

  /// No description provided for @providerSetupProviderSetupBaseUrl.
  ///
  /// In de, this message translates to:
  /// **'Base-URL'**
  String get providerSetupProviderSetupBaseUrl;

  /// No description provided for @providerSetupProviderSetupCreateKey.
  ///
  /// In de, this message translates to:
  /// **'Key beim Anbieter erstellen'**
  String get providerSetupProviderSetupCreateKey;

  /// No description provided for @providerSetupProviderSetupModelId.
  ///
  /// In de, this message translates to:
  /// **'Modell-ID'**
  String get providerSetupProviderSetupModelId;

  /// No description provided for @providerSetupProviderSetupModels.
  ///
  /// In de, this message translates to:
  /// **'Modelle'**
  String get providerSetupProviderSetupModels;

  /// No description provided for @providerSetupProviderSetupOtherTemplate.
  ///
  /// In de, this message translates to:
  /// **'Andere Vorlage'**
  String get providerSetupProviderSetupOtherTemplate;

  /// No description provided for @providerSetupProviderSetupProbeModel.
  ///
  /// In de, this message translates to:
  /// **'Modell prüfen'**
  String get providerSetupProviderSetupProbeModel;

  /// No description provided for @providerSetupProviderSetupTestConnection.
  ///
  /// In de, this message translates to:
  /// **'Verbindung testen'**
  String get providerSetupProviderSetupTestConnection;

  /// No description provided for @providerSetupProviderSetupTesting.
  ///
  /// In de, this message translates to:
  /// **'Teste …'**
  String get providerSetupProviderSetupTesting;

  /// No description provided for @providersAdd.
  ///
  /// In de, this message translates to:
  /// **'+ Provider'**
  String get providersAdd;

  /// No description provided for @providersAdvanced.
  ///
  /// In de, this message translates to:
  /// **'Erweiterte Einstellungen'**
  String get providersAdvanced;

  /// No description provided for @providersBudget.
  ///
  /// In de, this message translates to:
  /// **'Budget {v}/Monat'**
  String providersBudget(String v);

  /// No description provided for @providersDeleteBody.
  ///
  /// In de, this message translates to:
  /// **'Profil und gespeicherter Key werden entfernt.'**
  String get providersDeleteBody;

  /// No description provided for @providersDeleteTitle.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ löschen?'**
  String providersDeleteTitle(String name);

  /// No description provided for @providersError.
  ///
  /// In de, this message translates to:
  /// **'Fehler: {error}'**
  String providersError(String error);

  /// No description provided for @providersMakeDefault.
  ///
  /// In de, this message translates to:
  /// **'Als Standard'**
  String get providersMakeDefault;

  /// No description provided for @providersNone.
  ///
  /// In de, this message translates to:
  /// **'Noch kein Provider eingerichtet.'**
  String get providersNone;

  /// No description provided for @providersProfiles.
  ///
  /// In de, this message translates to:
  /// **'Profile'**
  String get providersProfiles;

  /// No description provided for @providersRoutingHint.
  ///
  /// In de, this message translates to:
  /// **'Regeln für die Wahl des Anbieters'**
  String get providersRoutingHint;

  /// No description provided for @targetPickerApply.
  ///
  /// In de, this message translates to:
  /// **'Übernehmen'**
  String get targetPickerApply;

  /// No description provided for @targetPickerProfile.
  ///
  /// In de, this message translates to:
  /// **'Profil'**
  String get targetPickerProfile;

  /// No description provided for @targetPickerProfileGone.
  ///
  /// In de, this message translates to:
  /// **'Profil „{profileId}“ gibt es nicht mehr.'**
  String targetPickerProfileGone(String profileId);

  /// No description provided for @quickSwitchCurrent.
  ///
  /// In de, this message translates to:
  /// **'aktuell'**
  String get quickSwitchCurrent;

  /// No description provided for @quickSwitchHint.
  ///
  /// In de, this message translates to:
  /// **'Die Auswahl beendet das Gespräch und startet ein neues.'**
  String get quickSwitchHint;

  /// No description provided for @quickSwitchItemSemantics.
  ///
  /// In de, this message translates to:
  /// **'{name}, {level}'**
  String quickSwitchItemSemantics(String name, String level);

  /// No description provided for @quickSwitchSemanticsAction.
  ///
  /// In de, this message translates to:
  /// **'Agent wechseln'**
  String get quickSwitchSemanticsAction;

  /// No description provided for @quickSwitchTitle.
  ///
  /// In de, this message translates to:
  /// **'Agent wechseln'**
  String get quickSwitchTitle;

  /// No description provided for @restrictedSettingsBody.
  ///
  /// In de, this message translates to:
  /// **'{what} fehlt. Hat Android gemeldet, dass diese Einstellung eingeschränkt ist bzw. aus Sicherheitsgründen nicht zugelassen wurde (Wendelin wurde aus einer Datei installiert), dann gib sie so frei:'**
  String restrictedSettingsBody(String what);

  /// No description provided for @restrictedSettingsOpenAppInfo.
  ///
  /// In de, this message translates to:
  /// **'App-Infos öffnen'**
  String get restrictedSettingsOpenAppInfo;

  /// No description provided for @restrictedSettingsSteps.
  ///
  /// In de, this message translates to:
  /// **'1. „App-Infos öffnen“ tippen.\n2. Oben rechts auf ⋮ tippen und „Eingeschränkte Einstellungen zulassen“ wählen. Der Eintrag erscheint erst nach dem ersten gescheiterten Versuch.\n3. Zurück zu Wendelin gehen und die Integration erneut einschalten.'**
  String get restrictedSettingsSteps;

  /// No description provided for @restrictedSettingsTitle.
  ///
  /// In de, this message translates to:
  /// **'Freigabe fehlt, evtl. von Android gesperrt'**
  String get restrictedSettingsTitle;

  /// No description provided for @restrictedSettingsWhatAccess.
  ///
  /// In de, this message translates to:
  /// **'Der Benachrichtigungszugriff'**
  String get restrictedSettingsWhatAccess;

  /// No description provided for @restrictedSettingsWhatSms.
  ///
  /// In de, this message translates to:
  /// **'Die SMS-Berechtigung'**
  String get restrictedSettingsWhatSms;

  /// No description provided for @condBuilderAddCondition.
  ///
  /// In de, this message translates to:
  /// **'+ Bedingung'**
  String get condBuilderAddCondition;

  /// No description provided for @condBuilderAddConditionInGroup.
  ///
  /// In de, this message translates to:
  /// **'+ Bedingung in Gruppe'**
  String get condBuilderAddConditionInGroup;

  /// No description provided for @condBuilderAddGroup.
  ///
  /// In de, this message translates to:
  /// **'+ Gruppe'**
  String get condBuilderAddGroup;

  /// No description provided for @condBuilderAll.
  ///
  /// In de, this message translates to:
  /// **'alle (und)'**
  String get condBuilderAll;

  /// No description provided for @condBuilderAny.
  ///
  /// In de, this message translates to:
  /// **'eine (oder)'**
  String get condBuilderAny;

  /// No description provided for @condBuilderApplies.
  ///
  /// In de, this message translates to:
  /// **'Es gilt'**
  String get condBuilderApplies;

  /// No description provided for @condBuilderCategory.
  ///
  /// In de, this message translates to:
  /// **'Kategorie'**
  String get condBuilderCategory;

  /// No description provided for @condBuilderConfidenceBelow.
  ///
  /// In de, this message translates to:
  /// **'Sicherheit unter'**
  String get condBuilderConfidenceBelow;

  /// No description provided for @condBuilderEmptyGroup.
  ///
  /// In de, this message translates to:
  /// **'Eine Gruppe ist leer.'**
  String get condBuilderEmptyGroup;

  /// No description provided for @condBuilderFail.
  ///
  /// In de, this message translates to:
  /// **'{label}: {m}'**
  String condBuilderFail(String label, String m);

  /// No description provided for @condBuilderFrom.
  ///
  /// In de, this message translates to:
  /// **'von (HH:MM)'**
  String get condBuilderFrom;

  /// No description provided for @condBuilderGroup.
  ///
  /// In de, this message translates to:
  /// **'Gruppe'**
  String get condBuilderGroup;

  /// No description provided for @condBuilderLanguages.
  ///
  /// In de, this message translates to:
  /// **'Sprachen'**
  String get condBuilderLanguages;

  /// No description provided for @condBuilderLanguagesHint.
  ///
  /// In de, this message translates to:
  /// **'de, fr'**
  String get condBuilderLanguagesHint;

  /// No description provided for @condBuilderMetered.
  ///
  /// In de, this message translates to:
  /// **'mobile Daten'**
  String get condBuilderMetered;

  /// No description provided for @condBuilderMoreChars.
  ///
  /// In de, this message translates to:
  /// **'Mehr Zeichen als'**
  String get condBuilderMoreChars;

  /// No description provided for @condBuilderNeedCategory.
  ///
  /// In de, this message translates to:
  /// **'Kategorie eingeben.'**
  String get condBuilderNeedCategory;

  /// No description provided for @condBuilderNeedLang.
  ///
  /// In de, this message translates to:
  /// **'Sprachkürzel eingeben (de, fr …).'**
  String get condBuilderNeedLang;

  /// No description provided for @condBuilderNeedLength.
  ///
  /// In de, this message translates to:
  /// **'Zeichenzahl eingeben.'**
  String get condBuilderNeedLength;

  /// No description provided for @condBuilderNeedPattern.
  ///
  /// In de, this message translates to:
  /// **'Muster eingeben.'**
  String get condBuilderNeedPattern;

  /// No description provided for @condBuilderNeedThreshold.
  ///
  /// In de, this message translates to:
  /// **'Schwelle zwischen 0 und 1 eingeben.'**
  String get condBuilderNeedThreshold;

  /// No description provided for @condBuilderNeedTime.
  ///
  /// In de, this message translates to:
  /// **'Uhrzeit als HH:MM eingeben.'**
  String get condBuilderNeedTime;

  /// No description provided for @condBuilderNeedWord.
  ///
  /// In de, this message translates to:
  /// **'mindestens ein Wort eingeben.'**
  String get condBuilderNeedWord;

  /// No description provided for @condBuilderPattern.
  ///
  /// In de, this message translates to:
  /// **'Muster (auf normalisiertem Text)'**
  String get condBuilderPattern;

  /// No description provided for @condBuilderRemoveCondition.
  ///
  /// In de, this message translates to:
  /// **'Bedingung entfernen'**
  String get condBuilderRemoveCondition;

  /// No description provided for @condBuilderRemoveGroup.
  ///
  /// In de, this message translates to:
  /// **'Gruppe entfernen'**
  String get condBuilderRemoveGroup;

  /// No description provided for @condBuilderSentenceStart.
  ///
  /// In de, this message translates to:
  /// **'Wörter am Satzanfang, durch Komma getrennt'**
  String get condBuilderSentenceStart;

  /// No description provided for @condBuilderSentenceStartHint.
  ///
  /// In de, this message translates to:
  /// **'Claude'**
  String get condBuilderSentenceStartHint;

  /// No description provided for @condBuilderTo.
  ///
  /// In de, this message translates to:
  /// **'bis (HH:MM)'**
  String get condBuilderTo;

  /// No description provided for @condBuilderUnknownType.
  ///
  /// In de, this message translates to:
  /// **'unbekannter Typ.'**
  String get condBuilderUnknownType;

  /// No description provided for @condBuilderWords.
  ///
  /// In de, this message translates to:
  /// **'Wörter, durch Komma getrennt'**
  String get condBuilderWords;

  /// No description provided for @condBuilderWordsHint.
  ///
  /// In de, this message translates to:
  /// **'privat, vertraulich'**
  String get condBuilderWordsHint;

  /// No description provided for @routingAllDay.
  ///
  /// In de, this message translates to:
  /// **'ganztags'**
  String get routingAllDay;

  /// No description provided for @routingApplies.
  ///
  /// In de, this message translates to:
  /// **'greift → {target}{private}'**
  String routingApplies(String target, String private);

  /// No description provided for @routingCondAnd.
  ///
  /// In de, this message translates to:
  /// **'und'**
  String get routingCondAnd;

  /// No description provided for @routingCondImage.
  ///
  /// In de, this message translates to:
  /// **'Mit Bild'**
  String get routingCondImage;

  /// No description provided for @routingCondKeyword.
  ///
  /// In de, this message translates to:
  /// **'Schlüsselwort'**
  String get routingCondKeyword;

  /// No description provided for @routingCondLanguage.
  ///
  /// In de, this message translates to:
  /// **'Sprache'**
  String get routingCondLanguage;

  /// No description provided for @routingCondLong.
  ///
  /// In de, this message translates to:
  /// **'Lange Eingabe'**
  String get routingCondLong;

  /// No description provided for @routingCondNetwork.
  ///
  /// In de, this message translates to:
  /// **'Netz'**
  String get routingCondNetwork;

  /// No description provided for @routingCondNot.
  ///
  /// In de, this message translates to:
  /// **'nicht'**
  String get routingCondNot;

  /// No description provided for @routingCondOr.
  ///
  /// In de, this message translates to:
  /// **'oder'**
  String get routingCondOr;

  /// No description provided for @routingCondPrefix.
  ///
  /// In de, this message translates to:
  /// **'Präfix'**
  String get routingCondPrefix;

  /// No description provided for @routingCondPrivate.
  ///
  /// In de, this message translates to:
  /// **'Privat'**
  String get routingCondPrivate;

  /// No description provided for @routingCondRegex.
  ///
  /// In de, this message translates to:
  /// **'Regulärer Ausdruck'**
  String get routingCondRegex;

  /// No description provided for @routingCondTime.
  ///
  /// In de, this message translates to:
  /// **'Zeitfenster'**
  String get routingCondTime;

  /// No description provided for @routingCondTool.
  ///
  /// In de, this message translates to:
  /// **'Braucht Tool'**
  String get routingCondTool;

  /// No description provided for @routingCondUncertain.
  ///
  /// In de, this message translates to:
  /// **'Unsichere Erkennung'**
  String get routingCondUncertain;

  /// No description provided for @routingDefault.
  ///
  /// In de, this message translates to:
  /// **'Standard'**
  String get routingDefault;

  /// No description provided for @routingDeleted.
  ///
  /// In de, this message translates to:
  /// **'{profileId} (gelöscht)'**
  String routingDeleted(String profileId);

  /// No description provided for @routingImportBody.
  ///
  /// In de, this message translates to:
  /// **'{length} Regeln ersetzen die bisherigen {before}. Erst mit „Ersetzen“ wird etwas geändert.'**
  String routingImportBody(int length, int before);

  /// No description provided for @routingImportDefaultMissing.
  ///
  /// In de, this message translates to:
  /// **'Das Standardprofil „{profileId}“ gibt es hier nicht; der bisherige Standard bleibt.'**
  String routingImportDefaultMissing(String profileId);

  /// No description provided for @routingImportEscalations.
  ///
  /// In de, this message translates to:
  /// **'Die Datei enthält Eskalationsketten. Sie wurden übersprungen: Wendelin wechselt nie von selbst das Modell.'**
  String get routingImportEscalations;

  /// No description provided for @routingImportReplace.
  ///
  /// In de, this message translates to:
  /// **'Ersetzen'**
  String get routingImportReplace;

  /// No description provided for @routingImportTitle.
  ///
  /// In de, this message translates to:
  /// **'Regeln importieren?'**
  String get routingImportTitle;

  /// No description provided for @routingPrivateRuleNotice.
  ///
  /// In de, this message translates to:
  /// **'Neu: Regel „Privat“ – Anfragen mit „privat“, „vertraulich“ … gehen an {target}.'**
  String routingPrivateRuleNotice(String target);

  /// No description provided for @routingPrivateSuffix.
  ///
  /// In de, this message translates to:
  /// **' · privat'**
  String get routingPrivateSuffix;

  /// No description provided for @routingRuleN.
  ///
  /// In de, this message translates to:
  /// **'Regel {n}'**
  String routingRuleN(int n);

  /// No description provided for @routingScreenAddRule.
  ///
  /// In de, this message translates to:
  /// **'+ Regel hinzufügen'**
  String get routingScreenAddRule;

  /// No description provided for @routingScreenDefaultTarget.
  ///
  /// In de, this message translates to:
  /// **'Standardziel'**
  String get routingScreenDefaultTarget;

  /// No description provided for @routingScreenFirstWins.
  ///
  /// In de, this message translates to:
  /// **'Erste passende Regel gewinnt'**
  String get routingScreenFirstWins;

  /// No description provided for @routingScreenImportFailed.
  ///
  /// In de, this message translates to:
  /// **'Import nicht möglich: {message}'**
  String routingScreenImportFailed(String message);

  /// No description provided for @routingScreenMoveRule.
  ///
  /// In de, this message translates to:
  /// **'Regel „{name}“ verschieben'**
  String routingScreenMoveRule(String name);

  /// No description provided for @routingScreenNeedsProvider.
  ///
  /// In de, this message translates to:
  /// **'Routing braucht einen Provider. Richte zuerst einen ein.'**
  String get routingScreenNeedsProvider;

  /// No description provided for @routingScreenReadError.
  ///
  /// In de, this message translates to:
  /// **'Die Regeln lassen sich nicht lesen: {error}'**
  String routingScreenReadError(String error);

  /// No description provided for @routingScreenResetBody.
  ///
  /// In de, this message translates to:
  /// **'Die gespeicherten Regeln werden verworfen und aus den Provider-Einstellungen neu angelegt.'**
  String get routingScreenResetBody;

  /// No description provided for @routingScreenResetRules.
  ///
  /// In de, this message translates to:
  /// **'Regeln zurücksetzen'**
  String get routingScreenResetRules;

  /// No description provided for @routingScreenResetTitle.
  ///
  /// In de, this message translates to:
  /// **'Regeln zurücksetzen?'**
  String get routingScreenResetTitle;

  /// No description provided for @routingScreenRuleOff.
  ///
  /// In de, this message translates to:
  /// **'{name} (aus)'**
  String routingScreenRuleOff(String name);

  /// No description provided for @routingScreenSkipped.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ übersprungen: {v}'**
  String routingScreenSkipped(String name, String v);

  /// No description provided for @routingScreenTestHint.
  ///
  /// In de, this message translates to:
  /// **'Welche Regel greift für diesen Satz?'**
  String get routingScreenTestHint;

  /// No description provided for @routingScreenTestSentence.
  ///
  /// In de, this message translates to:
  /// **'Testsatz'**
  String get routingScreenTestSentence;

  /// No description provided for @routingSkipDisabled.
  ///
  /// In de, this message translates to:
  /// **'ausgeschaltet'**
  String get routingSkipDisabled;

  /// No description provided for @routingSkipInvalid.
  ///
  /// In de, this message translates to:
  /// **'ungültig'**
  String get routingSkipInvalid;

  /// No description provided for @routingSkipNoMatch.
  ///
  /// In de, this message translates to:
  /// **'passt nicht'**
  String get routingSkipNoMatch;

  /// No description provided for @routingSkipProfileDisabled.
  ///
  /// In de, this message translates to:
  /// **'Profil deaktiviert'**
  String get routingSkipProfileDisabled;

  /// No description provided for @routingSkipProfileMissing.
  ///
  /// In de, this message translates to:
  /// **'Profil gelöscht'**
  String get routingSkipProfileMissing;

  /// No description provided for @routingSkipProfileUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Profil nicht verfügbar'**
  String get routingSkipProfileUnavailable;

  /// No description provided for @routingWeekdayFri.
  ///
  /// In de, this message translates to:
  /// **'Fr'**
  String get routingWeekdayFri;

  /// No description provided for @routingWeekdayMon.
  ///
  /// In de, this message translates to:
  /// **'Mo'**
  String get routingWeekdayMon;

  /// No description provided for @routingWeekdaySat.
  ///
  /// In de, this message translates to:
  /// **'Sa'**
  String get routingWeekdaySat;

  /// No description provided for @routingWeekdaySun.
  ///
  /// In de, this message translates to:
  /// **'So'**
  String get routingWeekdaySun;

  /// No description provided for @routingWeekdayThu.
  ///
  /// In de, this message translates to:
  /// **'Do'**
  String get routingWeekdayThu;

  /// No description provided for @routingWeekdayTue.
  ///
  /// In de, this message translates to:
  /// **'Di'**
  String get routingWeekdayTue;

  /// No description provided for @routingWeekdayWed.
  ///
  /// In de, this message translates to:
  /// **'Mi'**
  String get routingWeekdayWed;

  /// No description provided for @ruleEditorActive.
  ///
  /// In de, this message translates to:
  /// **'Aktiv'**
  String get ruleEditorActive;

  /// No description provided for @ruleEditorActiveLabel.
  ///
  /// In de, this message translates to:
  /// **'Regel aktiv'**
  String get ruleEditorActiveLabel;

  /// No description provided for @ruleEditorCondition.
  ///
  /// In de, this message translates to:
  /// **'Bedingung'**
  String get ruleEditorCondition;

  /// No description provided for @ruleEditorDeleteBody.
  ///
  /// In de, this message translates to:
  /// **'Anfragen, die bisher diese Regel genommen haben, prüfen die nächsten Regeln bzw. gehen an den Standard.'**
  String get ruleEditorDeleteBody;

  /// No description provided for @ruleEditorDeleteRule.
  ///
  /// In de, this message translates to:
  /// **'Regel löschen'**
  String get ruleEditorDeleteRule;

  /// No description provided for @ruleEditorDeleteTitle.
  ///
  /// In de, this message translates to:
  /// **'Regel „{v}“ löschen?'**
  String ruleEditorDeleteTitle(String v);

  /// No description provided for @ruleEditorEditRule.
  ///
  /// In de, this message translates to:
  /// **'Regel bearbeiten'**
  String get ruleEditorEditRule;

  /// No description provided for @ruleEditorNeedModel.
  ///
  /// In de, this message translates to:
  /// **'Bitte ein Modell eingeben.'**
  String get ruleEditorNeedModel;

  /// No description provided for @ruleEditorNeedName.
  ///
  /// In de, this message translates to:
  /// **'Bitte einen Namen eingeben.'**
  String get ruleEditorNeedName;

  /// No description provided for @ruleEditorNewRule.
  ///
  /// In de, this message translates to:
  /// **'Neue Regel'**
  String get ruleEditorNewRule;

  /// No description provided for @ruleEditorRebuild.
  ///
  /// In de, this message translates to:
  /// **'Neu aufbauen'**
  String get ruleEditorRebuild;

  /// No description provided for @ruleEditorRule.
  ///
  /// In de, this message translates to:
  /// **'Regel'**
  String get ruleEditorRule;

  /// No description provided for @ruleEditorStripTrigger.
  ///
  /// In de, this message translates to:
  /// **'Auslöser entfernen'**
  String get ruleEditorStripTrigger;

  /// No description provided for @ruleEditorStripTriggerHint.
  ///
  /// In de, this message translates to:
  /// **'Präfix, Schlüsselwort oder Treffer gehen nicht ans Modell; im Verlauf bleibt der Satz vollständig.'**
  String get ruleEditorStripTriggerHint;

  /// No description provided for @ruleEditorStripTriggerLabel.
  ///
  /// In de, this message translates to:
  /// **'Auslöser entfernen'**
  String get ruleEditorStripTriggerLabel;

  /// No description provided for @ruleEditorTarget.
  ///
  /// In de, this message translates to:
  /// **'Ziel'**
  String get ruleEditorTarget;

  /// No description provided for @ruleEditorTooDeep.
  ///
  /// In de, this message translates to:
  /// **'Diese Bedingung ist tiefer verschachtelt, als der Editor sie bearbeiten kann. Sie bleibt unverändert erhalten.'**
  String get ruleEditorTooDeep;

  /// No description provided for @ruleTileMove.
  ///
  /// In de, this message translates to:
  /// **'Verschieben'**
  String get ruleTileMove;

  /// No description provided for @ruleTileSemanticsLevel.
  ///
  /// In de, this message translates to:
  /// **'Datenschutzstufe {level},'**
  String ruleTileSemanticsLevel(String level);

  /// No description provided for @speakerAdd.
  ///
  /// In de, this message translates to:
  /// **'Person einlernen'**
  String get speakerAdd;

  /// No description provided for @speakerAddDetail.
  ///
  /// In de, this message translates to:
  /// **'Fünf kurze Sätze vorlesen, die Aufnahmen werden nicht gespeichert.'**
  String get speakerAddDetail;

  /// No description provided for @speakerAddNeedsModel.
  ///
  /// In de, this message translates to:
  /// **'Lade zuerst das Modell.'**
  String get speakerAddNeedsModel;

  /// No description provided for @speakerDeleteBody.
  ///
  /// In de, this message translates to:
  /// **'{name} wird mit allen gespeicherten Stimmmerkmalen und ihren Unterhaltungen gelöscht.'**
  String speakerDeleteBody(String name);

  /// No description provided for @speakerDeleteBodyMemory.
  ///
  /// In de, this message translates to:
  /// **'{name} wird mit allen gespeicherten Stimmmerkmalen, ihren Unterhaltungen und {count} Einträgen im eigenen Gedächtnis gelöscht. Das Standard-Gedächtnis bleibt unverändert.'**
  String speakerDeleteBodyMemory(String name, int count);

  /// No description provided for @speakerDeleteConfirm.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get speakerDeleteConfirm;

  /// No description provided for @speakerDeleteSemantic.
  ///
  /// In de, this message translates to:
  /// **'{name} löschen'**
  String speakerDeleteSemantic(String name);

  /// No description provided for @speakerDeleteTitle.
  ///
  /// In de, this message translates to:
  /// **'Person löschen?'**
  String get speakerDeleteTitle;

  /// No description provided for @speakerDone.
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get speakerDone;

  /// No description provided for @speakerEnrollIntro.
  ///
  /// In de, this message translates to:
  /// **'Lies jeden Satz in normaler Lautstärke vor. Aus der Aufnahme wird nur ein Stimmmerkmal berechnet, das Audio wird verworfen.'**
  String get speakerEnrollIntro;

  /// No description provided for @speakerEnrollTitle.
  ///
  /// In de, this message translates to:
  /// **'Person einlernen'**
  String get speakerEnrollTitle;

  /// No description provided for @speakerErrFailed.
  ///
  /// In de, this message translates to:
  /// **'Das Modell konnte die Aufnahmen nicht auswerten. Ist es vollständig geladen?'**
  String get speakerErrFailed;

  /// No description provided for @speakerErrInconsistent.
  ///
  /// In de, this message translates to:
  /// **'Die Sätze klangen nicht nach derselben Person oder es war zu laut. Nichts wurde gespeichert, bitte noch einmal in ruhiger Umgebung.'**
  String get speakerErrInconsistent;

  /// No description provided for @speakerErrTooFew.
  ///
  /// In de, this message translates to:
  /// **'Es fehlen Aufnahmen.'**
  String get speakerErrTooFew;

  /// No description provided for @speakerErrTooShort.
  ///
  /// In de, this message translates to:
  /// **'Eine Aufnahme war zu kurz. Bitte noch einmal.'**
  String get speakerErrTooShort;

  /// No description provided for @speakerIntro.
  ///
  /// In de, this message translates to:
  /// **'Wendelin kann erkennen, wer spricht. Das Ergebnis steht dem Assistenten als Information zur Verfügung.'**
  String get speakerIntro;

  /// No description provided for @speakerModelSection.
  ///
  /// In de, this message translates to:
  /// **'Modell'**
  String get speakerModelSection;

  /// No description provided for @speakerNameLabel.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get speakerNameLabel;

  /// No description provided for @speakerNext.
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get speakerNext;

  /// No description provided for @speakerNoMic.
  ///
  /// In de, this message translates to:
  /// **'Ohne Mikrofon-Zugriff kann keine Person eingelernt werden.'**
  String get speakerNoMic;

  /// No description provided for @speakerNobody.
  ///
  /// In de, this message translates to:
  /// **'Noch niemand eingelernt.'**
  String get speakerNobody;

  /// No description provided for @speakerPeople.
  ///
  /// In de, this message translates to:
  /// **'Personen'**
  String get speakerPeople;

  /// No description provided for @speakerPersonAddress.
  ///
  /// In de, this message translates to:
  /// **'Anrede'**
  String get speakerPersonAddress;

  /// No description provided for @speakerPersonAddressHint.
  ///
  /// In de, this message translates to:
  /// **'So spricht Wendelin dich an. Leer: der eingelernte Name.'**
  String get speakerPersonAddressHint;

  /// No description provided for @speakerPersonAgent.
  ///
  /// In de, this message translates to:
  /// **'Agent'**
  String get speakerPersonAgent;

  /// No description provided for @speakerPersonAgentDefault.
  ///
  /// In de, this message translates to:
  /// **'Standard-Agent'**
  String get speakerPersonAgentDefault;

  /// No description provided for @speakerPersonAgentDetail.
  ///
  /// In de, this message translates to:
  /// **'Nur ein anderes Ziel statt des Standards. Regeln und Datenschutz gelten weiter.'**
  String get speakerPersonAgentDetail;

  /// No description provided for @speakerPersonDelete.
  ///
  /// In de, this message translates to:
  /// **'Person löschen'**
  String get speakerPersonDelete;

  /// No description provided for @speakerPersonMemory.
  ///
  /// In de, this message translates to:
  /// **'Gedächtnis'**
  String get speakerPersonMemory;

  /// No description provided for @speakerPersonMemoryOpen.
  ///
  /// In de, this message translates to:
  /// **'Einträge ansehen'**
  String get speakerPersonMemoryOpen;

  /// No description provided for @speakerPersonMemoryOwn.
  ///
  /// In de, this message translates to:
  /// **'Eigenes Gedächtnis'**
  String get speakerPersonMemoryOwn;

  /// No description provided for @speakerPersonMemoryOwnDetail.
  ///
  /// In de, this message translates to:
  /// **'Merkt sich Dinge nur für diese Person.'**
  String get speakerPersonMemoryOwnDetail;

  /// No description provided for @speakerPersonMemoryShared.
  ///
  /// In de, this message translates to:
  /// **'Standard-Gedächtnis'**
  String get speakerPersonMemoryShared;

  /// No description provided for @speakerPersonMemorySharedDetail.
  ///
  /// In de, this message translates to:
  /// **'Nutzt die bisherigen Einträge gemeinsam mit allen, die nicht erkannt werden.'**
  String get speakerPersonMemorySharedDetail;

  /// No description provided for @speakerPersonRetrain.
  ///
  /// In de, this message translates to:
  /// **'Neu einlernen'**
  String get speakerPersonRetrain;

  /// No description provided for @speakerPersonRetrainDetail.
  ///
  /// In de, this message translates to:
  /// **'Fünf Sätze noch einmal vorlesen.'**
  String get speakerPersonRetrainDetail;

  /// No description provided for @speakerProcessing.
  ///
  /// In de, this message translates to:
  /// **'Wird ausgewertet …'**
  String get speakerProcessing;

  /// No description provided for @speakerRecordCutOff.
  ///
  /// In de, this message translates to:
  /// **'Zu früh angefangen, bitte den Satz noch einmal.'**
  String get speakerRecordCutOff;

  /// No description provided for @speakerRecordNoSpeech.
  ///
  /// In de, this message translates to:
  /// **'Nichts gehört, bitte noch einmal.'**
  String get speakerRecordNoSpeech;

  /// No description provided for @speakerRecordTooLong.
  ///
  /// In de, this message translates to:
  /// **'Zu lang oder zu laut im Hintergrund, bitte noch einmal.'**
  String get speakerRecordTooLong;

  /// No description provided for @speakerRecordTooQuiet.
  ///
  /// In de, this message translates to:
  /// **'Zu leise, bitte lauter.'**
  String get speakerRecordTooQuiet;

  /// No description provided for @speakerResultClamped.
  ///
  /// In de, this message translates to:
  /// **'Die Schwelle wurde auf einen sicheren Wert begrenzt.'**
  String get speakerResultClamped;

  /// No description provided for @speakerResultScores.
  ///
  /// In de, this message translates to:
  /// **'Gleichmäßigkeit {mean}, schwächster Satz {min}, Schwelle {threshold}.'**
  String speakerResultScores(String mean, String min, String threshold);

  /// No description provided for @speakerResultTitle.
  ///
  /// In de, this message translates to:
  /// **'Eingelernt'**
  String get speakerResultTitle;

  /// No description provided for @speakerRetry.
  ///
  /// In de, this message translates to:
  /// **'Noch einmal'**
  String get speakerRetry;

  /// No description provided for @speakerRowDetail.
  ///
  /// In de, this message translates to:
  /// **'Erkennt, wer spricht (Name, Modell, Personen).'**
  String get speakerRowDetail;

  /// No description provided for @speakerRowTitle.
  ///
  /// In de, this message translates to:
  /// **'Sprechererkennung'**
  String get speakerRowTitle;

  /// No description provided for @speakerSayNow.
  ///
  /// In de, this message translates to:
  /// **'Lies den Satz jetzt laut vor:'**
  String get speakerSayNow;

  /// No description provided for @speakerSentence1.
  ///
  /// In de, this message translates to:
  /// **'Heute Morgen habe ich einen Spaziergang durch den Park gemacht.'**
  String get speakerSentence1;

  /// No description provided for @speakerSentence2.
  ///
  /// In de, this message translates to:
  /// **'Bitte erinnere mich morgen um neun Uhr an den Termin beim Arzt.'**
  String get speakerSentence2;

  /// No description provided for @speakerSentence3.
  ///
  /// In de, this message translates to:
  /// **'Im Garten blühen die ersten Blumen, und die Sonne scheint warm.'**
  String get speakerSentence3;

  /// No description provided for @speakerSentence4.
  ///
  /// In de, this message translates to:
  /// **'Kannst du mir sagen, wie das Wetter am Wochenende wird?'**
  String get speakerSentence4;

  /// No description provided for @speakerSentence5.
  ///
  /// In de, this message translates to:
  /// **'Zum Abendessen gibt es heute Suppe mit frischem Brot.'**
  String get speakerSentence5;

  /// No description provided for @speakerSentenceOf.
  ///
  /// In de, this message translates to:
  /// **'Satz {n} von {total}'**
  String speakerSentenceOf(int n, int total);

  /// No description provided for @speakerSwitch.
  ///
  /// In de, this message translates to:
  /// **'Sprechererkennung'**
  String get speakerSwitch;

  /// No description provided for @speakerSwitchHint.
  ///
  /// In de, this message translates to:
  /// **'Die Stimme ist keine sichere Anmeldung: Ähnliche oder nachgemachte Stimmen können verwechselt werden. Gespeichert werden nur verschlüsselte Stimmmerkmale, keine Aufnahmen.'**
  String get speakerSwitchHint;

  /// No description provided for @speakerSwitchLabel.
  ///
  /// In de, this message translates to:
  /// **'Sprechererkennung ein oder aus'**
  String get speakerSwitchLabel;

  /// No description provided for @speakerTitle.
  ///
  /// In de, this message translates to:
  /// **'Sprechererkennung'**
  String get speakerTitle;

  /// No description provided for @spotifyAppNote.
  ///
  /// In de, this message translates to:
  /// **'Die Spotify-App wird gebraucht, damit Wendelin auf diesem Handy abspielen kann: Läuft sie nicht, startet Wendelin sie. Auf anderen Geräten (Lautsprecher, Computer) spielt Wendelin auch ohne sie.'**
  String get spotifyAppNote;

  /// No description provided for @spotifyAppTitle.
  ///
  /// In de, this message translates to:
  /// **'Spotify-App'**
  String get spotifyAppTitle;

  /// No description provided for @spotifyClientIdLabel.
  ///
  /// In de, this message translates to:
  /// **'Client-ID'**
  String get spotifyClientIdLabel;

  /// No description provided for @spotifyClientIdMissing.
  ///
  /// In de, this message translates to:
  /// **'Bitte die Client-ID eintragen.'**
  String get spotifyClientIdMissing;

  /// No description provided for @spotifyCopied.
  ///
  /// In de, this message translates to:
  /// **'Adresse kopiert.'**
  String get spotifyCopied;

  /// No description provided for @spotifyCopyRedirect.
  ///
  /// In de, this message translates to:
  /// **'Adresse kopieren'**
  String get spotifyCopyRedirect;

  /// No description provided for @spotifyErrAccessDenied.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung abgebrochen: Zugriff nicht erlaubt.'**
  String get spotifyErrAccessDenied;

  /// No description provided for @spotifyErrCancelled.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung abgebrochen.'**
  String get spotifyErrCancelled;

  /// No description provided for @spotifyErrDenied.
  ///
  /// In de, this message translates to:
  /// **'Spotify hat die Anmeldung abgelehnt.'**
  String get spotifyErrDenied;

  /// No description provided for @spotifyErrFailed.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung bei Spotify nicht möglich.'**
  String get spotifyErrFailed;

  /// No description provided for @spotifyErrInvalidClientId.
  ///
  /// In de, this message translates to:
  /// **'Die Client-ID besteht aus 32 Zeichen (Ziffern und Buchstaben a–f). Bitte aus dem Entwickler-Dashboard kopieren.'**
  String get spotifyErrInvalidClientId;

  /// No description provided for @spotifyErrNoBrowser.
  ///
  /// In de, this message translates to:
  /// **'Kein Browser installiert, in dem die Anmeldung laufen kann.'**
  String get spotifyErrNoBrowser;

  /// No description provided for @spotifyErrNoCode.
  ///
  /// In de, this message translates to:
  /// **'Spotify hat keinen Code geschickt.'**
  String get spotifyErrNoCode;

  /// No description provided for @spotifyErrRejected.
  ///
  /// In de, this message translates to:
  /// **'Spotify hat die Anmeldung abgelehnt. Client-ID prüfen und darauf achten, dass das eigene Konto unter „User Management“ steht.'**
  String get spotifyErrRejected;

  /// No description provided for @spotifyErrStateMismatch.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung abgelehnt: Die Antwort von Spotify gehört nicht zu dieser Anmeldung (z. B. ein alter Browser-Tab). Bitte die Anmeldung neu starten und im neuen Tab zu Ende führen.'**
  String get spotifyErrStateMismatch;

  /// No description provided for @spotifyErrUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Spotify ist nicht erreichbar. Später erneut versuchen.'**
  String get spotifyErrUnavailable;

  /// No description provided for @spotifyFailed.
  ///
  /// In de, this message translates to:
  /// **'Fehler – Anmeldung abgelaufen oder Spotify nicht erreichbar'**
  String get spotifyFailed;

  /// No description provided for @spotifyGuideStep1.
  ///
  /// In de, this message translates to:
  /// **'1. Auf developer.spotify.com/dashboard mit dem Spotify-Konto anmelden und „Create app“ wählen.'**
  String get spotifyGuideStep1;

  /// No description provided for @spotifyGuideStep2.
  ///
  /// In de, this message translates to:
  /// **'2. Name und Beschreibung frei wählen. Als „Redirect URI“ genau diese Adresse eintragen: {redirect}'**
  String spotifyGuideStep2(String redirect);

  /// No description provided for @spotifyGuideStep3.
  ///
  /// In de, this message translates to:
  /// **'3. Bei „Which API/SDKs are you planning to use?“ „Web API“ ankreuzen und speichern.'**
  String get spotifyGuideStep3;

  /// No description provided for @spotifyGuideStep4.
  ///
  /// In de, this message translates to:
  /// **'4. Unter „Settings“ die „Client ID“ kopieren und unten eintragen. Im Entwicklungsmodus muss das eigene Konto unter „User Management“ stehen.'**
  String get spotifyGuideStep4;

  /// No description provided for @spotifyGuideTitle.
  ///
  /// In de, this message translates to:
  /// **'Entwickler-App anlegen'**
  String get spotifyGuideTitle;

  /// No description provided for @spotifyIntro.
  ///
  /// In de, this message translates to:
  /// **'Wendelin steuert Spotify über die offizielle Schnittstelle. Dafür braucht es ein Spotify-Premium-Konto und eine eigene (kostenlose) Entwickler-App von dir. Client-ID und Anmeldung bleiben im sicheren Speicher des Geräts.'**
  String get spotifyIntro;

  /// No description provided for @spotifyReconnected.
  ///
  /// In de, this message translates to:
  /// **'Spotify ist wieder erreichbar.'**
  String get spotifyReconnected;

  /// No description provided for @spotifyRetrying.
  ///
  /// In de, this message translates to:
  /// **'Prüfe …'**
  String get spotifyRetrying;

  /// No description provided for @spotifySignIn.
  ///
  /// In de, this message translates to:
  /// **'Bei Spotify anmelden'**
  String get spotifySignIn;

  /// No description provided for @spotifySignOut.
  ///
  /// In de, this message translates to:
  /// **'Abmelden'**
  String get spotifySignOut;

  /// No description provided for @spotifySignOutMessage.
  ///
  /// In de, this message translates to:
  /// **'Client-ID und Anmeldung werden vom Gerät gelöscht.'**
  String get spotifySignOutMessage;

  /// No description provided for @spotifySignOutTitle.
  ///
  /// In de, this message translates to:
  /// **'Von Spotify abmelden?'**
  String get spotifySignOutTitle;

  /// No description provided for @spotifySignedIn.
  ///
  /// In de, this message translates to:
  /// **'Angemeldet'**
  String get spotifySignedIn;

  /// No description provided for @spotifySigningIn.
  ///
  /// In de, this message translates to:
  /// **'Anmelden …'**
  String get spotifySigningIn;

  /// No description provided for @spotifyStateActive.
  ///
  /// In de, this message translates to:
  /// **'Angemeldet · Aktiv'**
  String get spotifyStateActive;

  /// No description provided for @spotifyStateLoginMissing.
  ///
  /// In de, this message translates to:
  /// **'Login fehlt'**
  String get spotifyStateLoginMissing;

  /// No description provided for @spotifyStateOff.
  ///
  /// In de, this message translates to:
  /// **'Angemeldet, Integration ausgeschaltet'**
  String get spotifyStateOff;

  /// No description provided for @spotifyStateUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Nicht verfügbar'**
  String get spotifyStateUnavailable;

  /// No description provided for @spotifyTitle.
  ///
  /// In de, this message translates to:
  /// **'Spotify'**
  String get spotifyTitle;

  /// No description provided for @stationAllDay.
  ///
  /// In de, this message translates to:
  /// **'ganztägig'**
  String get stationAllDay;

  /// No description provided for @stationEnd.
  ///
  /// In de, this message translates to:
  /// **'Beenden'**
  String get stationEnd;

  /// No description provided for @stationEndHint.
  ///
  /// In de, this message translates to:
  /// **'Zum Beenden entsperrst du das Telefon.'**
  String get stationEndHint;

  /// No description provided for @stationEvents.
  ///
  /// In de, this message translates to:
  /// **'Termine'**
  String get stationEvents;

  /// No description provided for @stationHour.
  ///
  /// In de, this message translates to:
  /// **'{hour} Uhr'**
  String stationHour(int hour);

  /// No description provided for @stationNoEvents.
  ///
  /// In de, this message translates to:
  /// **'Keine Termine in Sicht.'**
  String get stationNoEvents;

  /// No description provided for @stationNoTasks.
  ///
  /// In de, this message translates to:
  /// **'Keine fälligen Aufgaben.'**
  String get stationNoTasks;

  /// No description provided for @stationOverdue.
  ///
  /// In de, this message translates to:
  /// **'überfällig'**
  String get stationOverdue;

  /// No description provided for @stationPlaybackSlot.
  ///
  /// In de, this message translates to:
  /// **'Wiedergabe'**
  String get stationPlaybackSlot;

  /// No description provided for @stationQuietFrom.
  ///
  /// In de, this message translates to:
  /// **'Beginn der Ruhezeit'**
  String get stationQuietFrom;

  /// No description provided for @stationQuietSection.
  ///
  /// In de, this message translates to:
  /// **'Ruhezeiten'**
  String get stationQuietSection;

  /// No description provided for @stationQuietTo.
  ///
  /// In de, this message translates to:
  /// **'Ende der Ruhezeit'**
  String get stationQuietTo;

  /// No description provided for @stationScreenAlways.
  ///
  /// In de, this message translates to:
  /// **'Immer an, gedimmt'**
  String get stationScreenAlways;

  /// No description provided for @stationScreenAlwaysDetail.
  ///
  /// In de, this message translates to:
  /// **'Helligkeit nach Umgebungslicht, der Inhalt wandert leicht gegen Einbrennen.'**
  String get stationScreenAlwaysDetail;

  /// No description provided for @stationScreenDaytime.
  ///
  /// In de, this message translates to:
  /// **'Tagsüber an, in den Ruhezeiten aus'**
  String get stationScreenDaytime;

  /// No description provided for @stationScreenDaytimeDetail.
  ///
  /// In de, this message translates to:
  /// **'Eine Berührung weckt die Station kurz.'**
  String get stationScreenDaytimeDetail;

  /// No description provided for @stationScreenSection.
  ///
  /// In de, this message translates to:
  /// **'Bildschirm'**
  String get stationScreenSection;

  /// No description provided for @stationScreenTouch.
  ///
  /// In de, this message translates to:
  /// **'Aus, an bei Wake Word oder Berührung'**
  String get stationScreenTouch;

  /// No description provided for @stationScreenTouchDetail.
  ///
  /// In de, this message translates to:
  /// **'Der Bildschirm schaltet sich nach der üblichen Zeit aus.'**
  String get stationScreenTouchDetail;

  /// No description provided for @stationSectionsIntro.
  ///
  /// In de, this message translates to:
  /// **'Was die Station zeigt. Uhr und Datum sind immer da. Termine und Aufgaben erscheinen mit Titeln.'**
  String get stationSectionsIntro;

  /// No description provided for @stationSectionsSection.
  ///
  /// In de, this message translates to:
  /// **'Anzeige'**
  String get stationSectionsSection;

  /// No description provided for @stationSettingsDetail.
  ///
  /// In de, this message translates to:
  /// **'Bildschirm, Ruhezeiten, angezeigte Bereiche'**
  String get stationSettingsDetail;

  /// No description provided for @stationSettingsIntro.
  ///
  /// In de, this message translates to:
  /// **'Das Handy liegt am Ladegerät und zeigt Uhr, Datum und mehr. Der Modus startet nur von Hand und endet nur mit Entsperren.'**
  String get stationSettingsIntro;

  /// No description provided for @stationSlotSoon.
  ///
  /// In de, this message translates to:
  /// **'folgt'**
  String get stationSlotSoon;

  /// No description provided for @stationStart.
  ///
  /// In de, this message translates to:
  /// **'Stationsmodus starten'**
  String get stationStart;

  /// No description provided for @stationTasks.
  ///
  /// In de, this message translates to:
  /// **'Aufgaben'**
  String get stationTasks;

  /// No description provided for @stationTilesSlot.
  ///
  /// In de, this message translates to:
  /// **'Smart Home'**
  String get stationTilesSlot;

  /// No description provided for @stationTitle.
  ///
  /// In de, this message translates to:
  /// **'Stationsmodus'**
  String get stationTitle;

  /// No description provided for @stationWeather.
  ///
  /// In de, this message translates to:
  /// **'Wetter'**
  String get stationWeather;

  /// No description provided for @googleTasksApiError.
  ///
  /// In de, this message translates to:
  /// **'Fehler – Google nicht erreichbar oder Anmeldung abgelehnt'**
  String get googleTasksApiError;

  /// No description provided for @googleTasksCancel.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get googleTasksCancel;

  /// No description provided for @googleTasksChecking.
  ///
  /// In de, this message translates to:
  /// **'Prüfe …'**
  String get googleTasksChecking;

  /// No description provided for @googleTasksClientId.
  ///
  /// In de, this message translates to:
  /// **'Client-ID'**
  String get googleTasksClientId;

  /// No description provided for @googleTasksClientSecret.
  ///
  /// In de, this message translates to:
  /// **'Client-Secret'**
  String get googleTasksClientSecret;

  /// No description provided for @googleTasksErrAccessDenied.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung abgebrochen: Zugriff nicht erlaubt (Ist dein Konto im Cloud-Projekt als Testnutzer eingetragen?).'**
  String get googleTasksErrAccessDenied;

  /// No description provided for @googleTasksErrCancelled.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung abgebrochen.'**
  String get googleTasksErrCancelled;

  /// No description provided for @googleTasksErrClientRejected.
  ///
  /// In de, this message translates to:
  /// **'Google lehnt Client-ID oder Client-Secret ab. Bitte beides prüfen.'**
  String get googleTasksErrClientRejected;

  /// No description provided for @googleTasksErrDenied.
  ///
  /// In de, this message translates to:
  /// **'Google hat die Anmeldung abgelehnt.'**
  String get googleTasksErrDenied;

  /// No description provided for @googleTasksErrFailed.
  ///
  /// In de, this message translates to:
  /// **'Die Anmeldung ist fehlgeschlagen.'**
  String get googleTasksErrFailed;

  /// No description provided for @googleTasksErrInvalidClientId.
  ///
  /// In de, this message translates to:
  /// **'Die Client-ID endet auf „.apps.googleusercontent.com“. Bitte aus der Google Cloud Console kopieren (OAuth-Client Typ „Desktop“).'**
  String get googleTasksErrInvalidClientId;

  /// No description provided for @googleTasksErrMissingSecret.
  ///
  /// In de, this message translates to:
  /// **'Bitte das Client-Secret des OAuth-Clients eintragen (ohne Leerzeichen).'**
  String get googleTasksErrMissingSecret;

  /// No description provided for @googleTasksErrNoBrowser.
  ///
  /// In de, this message translates to:
  /// **'Es ist kein Browser installiert.'**
  String get googleTasksErrNoBrowser;

  /// No description provided for @googleTasksErrNoCode.
  ///
  /// In de, this message translates to:
  /// **'Google hat keinen Code geschickt.'**
  String get googleTasksErrNoCode;

  /// No description provided for @googleTasksErrNoRefreshToken.
  ///
  /// In de, this message translates to:
  /// **'Google hat kein Refresh-Token geschickt. Bitte den Zugriff von Wendelin unter myaccount.google.com/permissions entfernen und neu anmelden.'**
  String get googleTasksErrNoRefreshToken;

  /// No description provided for @googleTasksErrReceiver.
  ///
  /// In de, this message translates to:
  /// **'Der lokale Empfänger für die Anmeldung lässt sich nicht starten.'**
  String get googleTasksErrReceiver;

  /// No description provided for @googleTasksErrTimeout.
  ///
  /// In de, this message translates to:
  /// **'Zeitüberschreitung: Im Browser kam keine Antwort von Google an. Bitte erneut anmelden.'**
  String get googleTasksErrTimeout;

  /// No description provided for @googleTasksErrUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Google ist nicht erreichbar. Bitte später erneut versuchen.'**
  String get googleTasksErrUnavailable;

  /// No description provided for @googleTasksFine.
  ///
  /// In de, this message translates to:
  /// **'in Ordnung'**
  String get googleTasksFine;

  /// No description provided for @googleTasksGuideNote.
  ///
  /// In de, this message translates to:
  /// **'Im Testmodus läuft die Anmeldung nach 7 Tagen ab; dann hier erneut anmelden. Google warnt bei der Anmeldung vor einer „nicht verifizierten App“ (es ist dein eigenes Projekt): „Weiter“ wählen und „Aufgaben ansehen und verwalten“ erlauben.'**
  String get googleTasksGuideNote;

  /// No description provided for @googleTasksGuideStep1.
  ///
  /// In de, this message translates to:
  /// **'1. In console.cloud.google.com ein Projekt anlegen (oder ein eigenes wählen).'**
  String get googleTasksGuideStep1;

  /// No description provided for @googleTasksGuideStep2.
  ///
  /// In de, this message translates to:
  /// **'2. Unter „APIs & Dienste → Bibliothek“ die „Google Tasks API“ aktivieren.'**
  String get googleTasksGuideStep2;

  /// No description provided for @googleTasksGuideStep3.
  ///
  /// In de, this message translates to:
  /// **'3. Unter „Google Auth Platform“ (früher „OAuth-Zustimmungsbildschirm“) die Zielgruppe „Extern“ im Testmodus lassen und das eigene Google-Konto als Testnutzer eintragen.'**
  String get googleTasksGuideStep3;

  /// No description provided for @googleTasksGuideStep4.
  ///
  /// In de, this message translates to:
  /// **'4. Unter „Clients“ (früher „Anmeldedaten“) einen OAuth-Client vom Typ „Desktop-App“ anlegen. Client-ID und Client-Secret kopieren und unten eintragen.'**
  String get googleTasksGuideStep4;

  /// No description provided for @googleTasksGuideTitle.
  ///
  /// In de, this message translates to:
  /// **'Google-Cloud-Projekt einrichten'**
  String get googleTasksGuideTitle;

  /// No description provided for @googleTasksIntro.
  ///
  /// In de, this message translates to:
  /// **'Google-Aufgaben mit deinem eigenen Cloud-Projekt, ohne Google-Play-Dienste. Die Anmeldung läuft im Browser; Client-ID, Client-Secret und Anmeldung bleiben im sicheren Speicher des Geräts und werden nie angezeigt oder protokolliert. Aufgabenlisten dienen als Listen; Google kennt nur ein Fälligkeitsdatum, keine Uhrzeit und keine Priorität.'**
  String get googleTasksIntro;

  /// No description provided for @googleTasksNeedClient.
  ///
  /// In de, this message translates to:
  /// **'Bitte Client-ID und Client-Secret eintragen.'**
  String get googleTasksNeedClient;

  /// No description provided for @googleTasksReachable.
  ///
  /// In de, this message translates to:
  /// **'Google Tasks ist erreichbar.'**
  String get googleTasksReachable;

  /// No description provided for @googleTasksSignIn.
  ///
  /// In de, this message translates to:
  /// **'Bei Google anmelden'**
  String get googleTasksSignIn;

  /// No description provided for @googleTasksSignInWaiting.
  ///
  /// In de, this message translates to:
  /// **'Warte auf Google …'**
  String get googleTasksSignInWaiting;

  /// No description provided for @googleTasksSignOutBody.
  ///
  /// In de, this message translates to:
  /// **'Die Anmeldung wird bei Google widerrufen (soweit erreichbar), Client-ID, Client-Secret und Token werden vom Gerät gelöscht.'**
  String get googleTasksSignOutBody;

  /// No description provided for @googleTasksSignOutTitle.
  ///
  /// In de, this message translates to:
  /// **'Google Tasks trennen?'**
  String get googleTasksSignOutTitle;

  /// No description provided for @googleTasksStatusAvailable.
  ///
  /// In de, this message translates to:
  /// **'Verbunden, Integration ausgeschaltet'**
  String get googleTasksStatusAvailable;

  /// No description provided for @googleTasksStatusSetup.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung fehlt'**
  String get googleTasksStatusSetup;

  /// No description provided for @googleTasksStatusUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Nicht verfügbar'**
  String get googleTasksStatusUnavailable;

  /// No description provided for @googleTasksStatusUnknown.
  ///
  /// In de, this message translates to:
  /// **'Unbekannt'**
  String get googleTasksStatusUnknown;

  /// No description provided for @integrationDetailGoogleTasksAccount.
  ///
  /// In de, this message translates to:
  /// **'Google-Konto'**
  String get integrationDetailGoogleTasksAccount;

  /// No description provided for @integrationDetailTodoistAccount.
  ///
  /// In de, this message translates to:
  /// **'Todoist-Konto'**
  String get integrationDetailTodoistAccount;

  /// No description provided for @todoistApiError.
  ///
  /// In de, this message translates to:
  /// **'Fehler – Todoist nicht erreichbar oder Token abgelehnt'**
  String get todoistApiError;

  /// No description provided for @todoistChecking.
  ///
  /// In de, this message translates to:
  /// **'Prüfe …'**
  String get todoistChecking;

  /// No description provided for @todoistConnect.
  ///
  /// In de, this message translates to:
  /// **'Verbinden'**
  String get todoistConnect;

  /// No description provided for @todoistConnecting.
  ///
  /// In de, this message translates to:
  /// **'Verbinde …'**
  String get todoistConnecting;

  /// No description provided for @todoistErrDenied.
  ///
  /// In de, this message translates to:
  /// **'Todoist hat den Token abgelehnt (ungültig oder widerrufen).'**
  String get todoistErrDenied;

  /// No description provided for @todoistErrFailed.
  ///
  /// In de, this message translates to:
  /// **'Die Verbindung zu Todoist ist fehlgeschlagen.'**
  String get todoistErrFailed;

  /// No description provided for @todoistErrUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Todoist ist nicht erreichbar. Bitte später erneut versuchen.'**
  String get todoistErrUnavailable;

  /// No description provided for @todoistFine.
  ///
  /// In de, this message translates to:
  /// **'in Ordnung'**
  String get todoistFine;

  /// No description provided for @todoistIntro.
  ///
  /// In de, this message translates to:
  /// **'Todoist-Aufgaben per persönlichem API-Token. Den Token findest du in Todoist unter Einstellungen → Integrationen → Entwickler. Er bleibt im sicheren Speicher des Geräts und wird nie angezeigt oder protokolliert. Projekte dienen als Listen.'**
  String get todoistIntro;

  /// No description provided for @todoistNeedToken.
  ///
  /// In de, this message translates to:
  /// **'Bitte den API-Token eintragen.'**
  String get todoistNeedToken;

  /// No description provided for @todoistReachable.
  ///
  /// In de, this message translates to:
  /// **'Todoist ist erreichbar.'**
  String get todoistReachable;

  /// No description provided for @todoistSignOutBody.
  ///
  /// In de, this message translates to:
  /// **'Der Token wird vom Gerät gelöscht. In Todoist kannst du ihn zusätzlich widerrufen.'**
  String get todoistSignOutBody;

  /// No description provided for @todoistSignOutTitle.
  ///
  /// In de, this message translates to:
  /// **'Todoist trennen?'**
  String get todoistSignOutTitle;

  /// No description provided for @todoistStatusAvailable.
  ///
  /// In de, this message translates to:
  /// **'Verbunden, Integration ausgeschaltet'**
  String get todoistStatusAvailable;

  /// No description provided for @todoistStatusSetup.
  ///
  /// In de, this message translates to:
  /// **'Token fehlt'**
  String get todoistStatusSetup;

  /// No description provided for @todoistStatusUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Nicht verfügbar'**
  String get todoistStatusUnavailable;

  /// No description provided for @todoistStatusUnknown.
  ///
  /// In de, this message translates to:
  /// **'Unbekannt'**
  String get todoistStatusUnknown;

  /// No description provided for @todoistToken.
  ///
  /// In de, this message translates to:
  /// **'API-Token'**
  String get todoistToken;

  /// No description provided for @languageEnglish.
  ///
  /// In de, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageFrench.
  ///
  /// In de, this message translates to:
  /// **'Français'**
  String get languageFrench;

  /// No description provided for @languageGerman.
  ///
  /// In de, this message translates to:
  /// **'Deutsch'**
  String get languageGerman;

  /// No description provided for @modelRowDeleteBody.
  ///
  /// In de, this message translates to:
  /// **'Das Modell wird vom Gerät entfernt und muss vor der nächsten Nutzung neu geladen werden.'**
  String get modelRowDeleteBody;

  /// No description provided for @modelRowDeleteTitle.
  ///
  /// In de, this message translates to:
  /// **'{displayName} löschen?'**
  String modelRowDeleteTitle(String displayName);

  /// No description provided for @modelRowLoaded.
  ///
  /// In de, this message translates to:
  /// **'{size} · geladen'**
  String modelRowLoaded(String size);

  /// No description provided for @modelRowNotLoaded.
  ///
  /// In de, this message translates to:
  /// **'{size} · nicht geladen'**
  String modelRowNotLoaded(String size);

  /// No description provided for @modelRowProgressOf.
  ///
  /// In de, this message translates to:
  /// **'Fortschritt {displayName}'**
  String modelRowProgressOf(String displayName);

  /// No description provided for @modelRowRam.
  ///
  /// In de, this message translates to:
  /// **'Arbeitsspeicher ca. {ram}'**
  String modelRowRam(String ram);

  /// No description provided for @modelRowRecommended.
  ///
  /// In de, this message translates to:
  /// **'(empfohlen)'**
  String get modelRowRecommended;

  /// No description provided for @modelRowResume.
  ///
  /// In de, this message translates to:
  /// **'Fortsetzen'**
  String get modelRowResume;

  /// No description provided for @modelRowStarted.
  ///
  /// In de, this message translates to:
  /// **'{size} · angefangen'**
  String modelRowStarted(String size);

  /// No description provided for @voiceConvAdvanced.
  ///
  /// In de, this message translates to:
  /// **'Erweitert'**
  String get voiceConvAdvanced;

  /// No description provided for @voiceConvBargeInUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Nicht verfügbar: Dafür braucht Wendelin das Wake-Word-Modell, das noch nicht eingebaut ist.'**
  String get voiceConvBargeInUnavailable;

  /// No description provided for @voiceConvBargeKeywords.
  ///
  /// In de, this message translates to:
  /// **'Schlüsselwörter'**
  String get voiceConvBargeKeywords;

  /// No description provided for @voiceConvBargeSpeech.
  ///
  /// In de, this message translates to:
  /// **'Beliebige Sprache (experimentell)'**
  String get voiceConvBargeSpeech;

  /// No description provided for @voiceConvCustomBarge.
  ///
  /// In de, this message translates to:
  /// **'Eigene Einstellung für das Unterbrechen aktiv (unter „Erweitert“ zurücksetzbar).'**
  String get voiceConvCustomBarge;

  /// No description provided for @voiceConvInterrupt.
  ///
  /// In de, this message translates to:
  /// **'Unterbrechen während der Antwort'**
  String get voiceConvInterrupt;

  /// No description provided for @voiceConvInterruptHint.
  ///
  /// In de, this message translates to:
  /// **'Mit „Hey Wendelin“ unterbrichst du die Sprachausgabe.'**
  String get voiceConvInterruptHint;

  /// No description provided for @voiceConvKeepListening.
  ///
  /// In de, this message translates to:
  /// **'Weiter zuhören nach der Antwort'**
  String get voiceConvKeepListening;

  /// No description provided for @voiceConvKeepListeningDetail.
  ///
  /// In de, this message translates to:
  /// **'Nach der gesprochenen Antwort bleibt das Mikrofon kurz offen, du kannst ohne Tippen nachfragen. „Danke“ oder „Stopp“ beendet.'**
  String get voiceConvKeepListeningDetail;

  /// No description provided for @voiceConvKeepListeningLabel.
  ///
  /// In de, this message translates to:
  /// **'Weiter zuhören nach der Antwort'**
  String get voiceConvKeepListeningLabel;

  /// No description provided for @voiceDownloadAnd.
  ///
  /// In de, this message translates to:
  /// **' und '**
  String get voiceDownloadAnd;

  /// No description provided for @voiceDownloadBundled.
  ///
  /// In de, this message translates to:
  /// **'{displayName} gehört dazu ({v}) und wird mitgeladen. „small“ erkennt Deutsch, Französisch und Namen deutlich besser. „base“ ist schnell und für schwache Geräte gedacht. Weitere Modelle: Einstellungen → Sprache.'**
  String voiceDownloadBundled(String displayName, String v);

  /// No description provided for @voiceDownloadContinueInBackground.
  ///
  /// In de, this message translates to:
  /// **'Im Hintergrund weiterladen'**
  String get voiceDownloadContinueInBackground;

  /// No description provided for @voiceDownloadContinueLoading.
  ///
  /// In de, this message translates to:
  /// **'Weiterladen'**
  String get voiceDownloadContinueLoading;

  /// No description provided for @voiceDownloadIntro.
  ///
  /// In de, this message translates to:
  /// **'Wendelin erkennt Sprache auf dem Gerät, ohne Internet und ohne Google. Wähle das Modell und lade es einmal, am besten im WLAN.'**
  String get voiceDownloadIntro;

  /// No description provided for @voiceDownloadLoad.
  ///
  /// In de, this message translates to:
  /// **'Laden'**
  String get voiceDownloadLoad;

  /// No description provided for @voiceDownloadLoadAgain.
  ///
  /// In de, this message translates to:
  /// **'Erneut laden'**
  String get voiceDownloadLoadAgain;

  /// No description provided for @voiceDownloadLoading.
  ///
  /// In de, this message translates to:
  /// **'Lädt …'**
  String get voiceDownloadLoading;

  /// No description provided for @voiceDownloadLoadingPercent.
  ///
  /// In de, this message translates to:
  /// **'Lädt … {v} %'**
  String voiceDownloadLoadingPercent(String v);

  /// No description provided for @voiceDownloadLoadingPercentOf.
  ///
  /// In de, this message translates to:
  /// **'Lädt … {v} % von {size}'**
  String voiceDownloadLoadingPercentOf(String v, String size);

  /// No description provided for @voiceDownloadPreselectedBase.
  ///
  /// In de, this message translates to:
  /// **'Vorausgewählt ist „base“, weil das Gerät wenig Arbeitsspeicher hat ({v} GB). „small“ braucht beim Erkennen deutlich mehr Speicher.'**
  String voiceDownloadPreselectedBase(String v);

  /// No description provided for @voiceDownloadProgressLabel.
  ///
  /// In de, this message translates to:
  /// **'Fortschritt Spracherkennung'**
  String get voiceDownloadProgressLabel;

  /// No description provided for @voiceDownloadReady.
  ///
  /// In de, this message translates to:
  /// **'Bereit'**
  String get voiceDownloadReady;

  /// No description provided for @voiceDownloadSizeLoaded.
  ///
  /// In de, this message translates to:
  /// **'{size} · geladen'**
  String voiceDownloadSizeLoaded(String size);

  /// No description provided for @voiceDownloadSizeMb.
  ///
  /// In de, this message translates to:
  /// **'{v} MB'**
  String voiceDownloadSizeMb(String v);

  /// No description provided for @voiceDownloadSizePartial.
  ///
  /// In de, this message translates to:
  /// **'{size} · angefangen'**
  String voiceDownloadSizePartial(String size);

  /// No description provided for @voiceDownloadStillNeeded.
  ///
  /// In de, this message translates to:
  /// **'Noch nötig: {v}'**
  String voiceDownloadStillNeeded(String v);

  /// No description provided for @voiceDownloadTitle.
  ///
  /// In de, this message translates to:
  /// **'Spracherkennung laden'**
  String get voiceDownloadTitle;

  /// No description provided for @voiceDownloadUnpacking.
  ///
  /// In de, this message translates to:
  /// **'Wird entpackt …'**
  String get voiceDownloadUnpacking;

  /// No description provided for @voiceErrorGeneric.
  ///
  /// In de, this message translates to:
  /// **'Sprache hat nicht geklappt. Bitte versuche es noch einmal.'**
  String get voiceErrorGeneric;

  /// No description provided for @voiceErrorMicBusy.
  ///
  /// In de, this message translates to:
  /// **'Das Mikrofon war noch belegt. Bitte sprich noch einmal.'**
  String get voiceErrorMicBusy;

  /// No description provided for @voiceErrorModelBroken.
  ///
  /// In de, this message translates to:
  /// **'Das Sprachmodell ist beschädigt. Bitte lade es neu (Einstellungen → Sprache).'**
  String get voiceErrorModelBroken;

  /// No description provided for @voiceErrorModelMissing.
  ///
  /// In de, this message translates to:
  /// **'Ein Sprachmodell ist noch nicht geladen (Einstellungen → Sprache).'**
  String get voiceErrorModelMissing;

  /// No description provided for @voiceMetricsClear.
  ///
  /// In de, this message translates to:
  /// **'Liste leeren'**
  String get voiceMetricsClear;

  /// No description provided for @voiceMetricsEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Messwerte. Sprich einen Befehl oder spiele eine Stimmprobe ab.'**
  String get voiceMetricsEmpty;

  /// No description provided for @voiceMetricsIntro.
  ///
  /// In de, this message translates to:
  /// **'Die letzten Äußerungen dieser Sitzung: Rechenzeit (Latenz), Echtzeitfaktor (Rechenzeit je Audiozeit, kleiner ist schneller) und Speicher der App. Nur Zahlen, keine Inhalte.'**
  String get voiceMetricsIntro;

  /// No description provided for @voiceMetricsRow.
  ///
  /// In de, this message translates to:
  /// **'{latency} ms für {audio} ms Audio · RTF {rtf} · RAM {ram}'**
  String voiceMetricsRow(String latency, String audio, String rtf, String ram);

  /// No description provided for @voiceMetricsStt.
  ///
  /// In de, this message translates to:
  /// **'Erkennung'**
  String get voiceMetricsStt;

  /// No description provided for @voiceMetricsTts.
  ///
  /// In de, this message translates to:
  /// **'Sprachausgabe'**
  String get voiceMetricsTts;

  /// No description provided for @voiceScreenAutomatic.
  ///
  /// In de, this message translates to:
  /// **'Automatisch'**
  String get voiceScreenAutomatic;

  /// No description provided for @voiceScreenAutomaticDetail.
  ///
  /// In de, this message translates to:
  /// **'Systemstimme, sonst Offline-Stimme'**
  String get voiceScreenAutomaticDetail;

  /// No description provided for @voiceScreenDetectAuto.
  ///
  /// In de, this message translates to:
  /// **'Automatisch erkennen'**
  String get voiceScreenDetectAuto;

  /// No description provided for @voiceScreenFineTuning.
  ///
  /// In de, this message translates to:
  /// **'Feinabstimmung'**
  String get voiceScreenFineTuning;

  /// No description provided for @voiceScreenFixedLanguageHint.
  ///
  /// In de, this message translates to:
  /// **'Mit fester Sprache erkennt Whisper kurze Sätze zuverlässiger.'**
  String get voiceScreenFixedLanguageHint;

  /// No description provided for @voiceScreenIntro.
  ///
  /// In de, this message translates to:
  /// **'Wendelin erkennt Sprache auf dem Gerät (Whisper). Die Modelle werden einmal geladen und bleiben auf dem Gerät.'**
  String get voiceScreenIntro;

  /// No description provided for @voiceScreenKeepModel.
  ///
  /// In de, this message translates to:
  /// **'Modell im Speicher halten'**
  String get voiceScreenKeepModel;

  /// No description provided for @voiceScreenKeepModelHint.
  ///
  /// In de, this message translates to:
  /// **'Erkennung und Stimme bleiben geladen: schnellere Antworten, aber dauerhaft mehr Arbeitsspeicher. Bei Speicherknappheit gibt Wendelin sie frei.'**
  String get voiceScreenKeepModelHint;

  /// No description provided for @voiceScreenKeepModelLabel.
  ///
  /// In de, this message translates to:
  /// **'Modell im Speicher halten'**
  String get voiceScreenKeepModelLabel;

  /// No description provided for @voiceScreenLanguageDefault.
  ///
  /// In de, this message translates to:
  /// **'Standard der Sprache'**
  String get voiceScreenLanguageDefault;

  /// No description provided for @voiceScreenLanguageDefaultChip.
  ///
  /// In de, this message translates to:
  /// **'Standard der Sprache'**
  String get voiceScreenLanguageDefaultChip;

  /// No description provided for @voiceScreenLikeApp.
  ///
  /// In de, this message translates to:
  /// **'Wie die App ({v})'**
  String voiceScreenLikeApp(String v);

  /// No description provided for @voiceScreenListen.
  ///
  /// In de, this message translates to:
  /// **'Probe hören'**
  String get voiceScreenListen;

  /// No description provided for @voiceScreenMetrics.
  ///
  /// In de, this message translates to:
  /// **'Messwerte'**
  String get voiceScreenMetrics;

  /// No description provided for @voiceScreenMetricsDetail.
  ///
  /// In de, this message translates to:
  /// **'Zeit, Echtzeitfaktor und Speicher je Äußerung'**
  String get voiceScreenMetricsDetail;

  /// No description provided for @voiceScreenMicrophone.
  ///
  /// In de, this message translates to:
  /// **'Mikrofon'**
  String get voiceScreenMicrophone;

  /// No description provided for @voiceScreenMicrophoneTitle.
  ///
  /// In de, this message translates to:
  /// **'Mikrofon'**
  String get voiceScreenMicrophoneTitle;

  /// No description provided for @voiceScreenMinSpeech.
  ///
  /// In de, this message translates to:
  /// **'Mindestsprechdauer'**
  String get voiceScreenMinSpeech;

  /// No description provided for @voiceScreenMinSpeechDetail.
  ///
  /// In de, this message translates to:
  /// **'Kürzere Geräusche (Klicks, Atmer) werden ignoriert.'**
  String get voiceScreenMinSpeechDetail;

  /// No description provided for @voiceScreenModelLicenses.
  ///
  /// In de, this message translates to:
  /// **'Lizenzen der Sprachmodelle'**
  String get voiceScreenModelLicenses;

  /// No description provided for @voiceScreenMs.
  ///
  /// In de, this message translates to:
  /// **'{v} ms'**
  String voiceScreenMs(int v);

  /// No description provided for @voiceScreenNoOfflineVoice.
  ///
  /// In de, this message translates to:
  /// **'Keine Offline-Stimme für diese Sprache geladen – Wendelin spricht mit der Systemstimme.'**
  String get voiceScreenNoOfflineVoice;

  /// No description provided for @voiceScreenNoSpeech.
  ///
  /// In de, this message translates to:
  /// **'Keine Sprachausgabe verfügbar: Antworten erscheinen nur auf dem Bildschirm. Lade eine Offline-Stimme.'**
  String get voiceScreenNoSpeech;

  /// No description provided for @voiceScreenNoSystemVoice.
  ///
  /// In de, this message translates to:
  /// **'Keine Systemstimme installiert – Wendelin spricht mit der Offline-Stimme.'**
  String get voiceScreenNoSystemVoice;

  /// No description provided for @voiceScreenNotAllowed.
  ///
  /// In de, this message translates to:
  /// **'nicht erlaubt'**
  String get voiceScreenNotAllowed;

  /// No description provided for @voiceScreenOfflineVoice.
  ///
  /// In de, this message translates to:
  /// **'Offline-Stimme'**
  String get voiceScreenOfflineVoice;

  /// No description provided for @voiceScreenOfflineVoices.
  ///
  /// In de, this message translates to:
  /// **'Offline-Stimmen'**
  String get voiceScreenOfflineVoices;

  /// No description provided for @voiceScreenRecognition.
  ///
  /// In de, this message translates to:
  /// **'Spracherkennung'**
  String get voiceScreenRecognition;

  /// No description provided for @voiceScreenRecognitionHint.
  ///
  /// In de, this message translates to:
  /// **'Für die Spracheingabe braucht Wendelin das gewählte Whisper-Modell und die Sprachaktivitätserkennung.'**
  String get voiceScreenRecognitionHint;

  /// No description provided for @voiceScreenRecommendSmall.
  ///
  /// In de, this message translates to:
  /// **'Empfohlen: small (genauer), {v} laden.'**
  String voiceScreenRecommendSmall(String v);

  /// No description provided for @voiceScreenSensitivity.
  ///
  /// In de, this message translates to:
  /// **'Empfindlichkeit der Spracherkennung'**
  String get voiceScreenSensitivity;

  /// No description provided for @voiceScreenSensitivityDetail.
  ///
  /// In de, this message translates to:
  /// **'Schwelle von Silero VAD: niedriger hört leiser, höher ignoriert mehr Geräusche.'**
  String get voiceScreenSensitivityDetail;

  /// No description provided for @voiceScreenSpeaksOffline.
  ///
  /// In de, this message translates to:
  /// **'Wendelin spricht mit der Offline-Stimme.'**
  String get voiceScreenSpeaksOffline;

  /// No description provided for @voiceScreenSpeaksSystem.
  ///
  /// In de, this message translates to:
  /// **'Wendelin spricht mit der Systemstimme.'**
  String get voiceScreenSpeaksSystem;

  /// No description provided for @voiceScreenSpeechOutput.
  ///
  /// In de, this message translates to:
  /// **'Sprachausgabe'**
  String get voiceScreenSpeechOutput;

  /// No description provided for @voiceScreenSpokenLanguage.
  ///
  /// In de, this message translates to:
  /// **'Gesprochene Sprache'**
  String get voiceScreenSpokenLanguage;

  /// No description provided for @voiceScreenSystemVoice.
  ///
  /// In de, this message translates to:
  /// **'Systemstimme'**
  String get voiceScreenSystemVoice;

  /// No description provided for @voiceScreenSystemVoiceTitle.
  ///
  /// In de, this message translates to:
  /// **'Systemstimme'**
  String get voiceScreenSystemVoiceTitle;

  /// No description provided for @voiceScreenTempo.
  ///
  /// In de, this message translates to:
  /// **'Tempo'**
  String get voiceScreenTempo;

  /// No description provided for @voiceScreenVoice.
  ///
  /// In de, this message translates to:
  /// **'Stimme'**
  String get voiceScreenVoice;

  /// No description provided for @voiceScreenVoiceAndTempo.
  ///
  /// In de, this message translates to:
  /// **'Stimme und Tempo'**
  String get voiceScreenVoiceAndTempo;

  /// No description provided for @voiceScreenVoiceLanguage.
  ///
  /// In de, this message translates to:
  /// **'{v} ({language})'**
  String voiceScreenVoiceLanguage(String v, String language);

  /// No description provided for @voiceScreenVoices.
  ///
  /// In de, this message translates to:
  /// **'Stimmen'**
  String get voiceScreenVoices;

  /// No description provided for @voiceScreenVoicesDetail.
  ///
  /// In de, this message translates to:
  /// **'Je Sprache eine weibliche und eine männliche Stimme'**
  String get voiceScreenVoicesDetail;

  /// No description provided for @voiceSpokenAlwaysDetail.
  ///
  /// In de, this message translates to:
  /// **'Wendelin schreibt zuerst einen kurzen Sprechtext und liest ihn immer vor, auch nach Inhalten aus dem Web oder von Dritten.'**
  String get voiceSpokenAlwaysDetail;

  /// No description provided for @voiceSpokenAlwaysTitle.
  ///
  /// In de, this message translates to:
  /// **'Immer eigene Sprechfassung'**
  String get voiceSpokenAlwaysTitle;

  /// No description provided for @voiceSpokenAlwaysWarning.
  ///
  /// In de, this message translates to:
  /// **'Was vorgelesen wird, kann von dem abweichen, was auf dem Bildschirm steht.'**
  String get voiceSpokenAlwaysWarning;

  /// No description provided for @voiceSpokenCheckedDetail.
  ///
  /// In de, this message translates to:
  /// **'Nach Inhalten aus dem Web oder von Dritten prüft ein weiterer Modellaufruf, ob Sprechtext und Antwort übereinstimmen. Die Sprachausgabe beginnt dann etwas später und kostet etwas mehr.'**
  String get voiceSpokenCheckedDetail;

  /// No description provided for @voiceSpokenCheckedTitle.
  ///
  /// In de, this message translates to:
  /// **'Mit KI-Prüfung'**
  String get voiceSpokenCheckedTitle;

  /// No description provided for @voiceSpokenOffDetail.
  ///
  /// In de, this message translates to:
  /// **'Wendelin liest die angezeigte Antwort vor, nur für die Aussprache aufbereitet.'**
  String get voiceSpokenOffDetail;

  /// No description provided for @voiceSpokenProtectedDetail.
  ///
  /// In de, this message translates to:
  /// **'Eigener Sprechtext, aber nach Inhalten aus dem Web oder von Dritten liest Wendelin die angezeigte Antwort vor.'**
  String get voiceSpokenProtectedDetail;

  /// No description provided for @voiceSpokenProtectedTitle.
  ///
  /// In de, this message translates to:
  /// **'Geschützt'**
  String get voiceSpokenProtectedTitle;

  /// No description provided for @voiceSpokenSemantic.
  ///
  /// In de, this message translates to:
  /// **'Sprechfassung {label}'**
  String voiceSpokenSemantic(String label);

  /// No description provided for @voiceSpokenTitle.
  ///
  /// In de, this message translates to:
  /// **'Sprechfassung'**
  String get voiceSpokenTitle;

  /// No description provided for @voiceUnavailableHint.
  ///
  /// In de, this message translates to:
  /// **'Spracherkennung laden: Einstellungen → Sprache'**
  String get voiceUnavailableHint;

  /// No description provided for @voiceVoicesIntro.
  ///
  /// In de, this message translates to:
  /// **'Wähle je Sprache die Offline-Stimme. Nur geladene Stimmen belegen Speicher; nicht gebrauchte kannst du löschen.'**
  String get voiceVoicesIntro;

  /// No description provided for @voiceVoicesNotLoaded.
  ///
  /// In de, this message translates to:
  /// **'Gewählte Stimme nicht geladen – es spricht {v}.'**
  String voiceVoicesNotLoaded(String v);

  /// No description provided for @voiceVoicesPreparing.
  ///
  /// In de, this message translates to:
  /// **'Probe wird vorbereitet …'**
  String get voiceVoicesPreparing;

  /// No description provided for @voiceVoicesSampleFailed.
  ///
  /// In de, this message translates to:
  /// **'Probe nicht möglich – die Stimme hat nicht gesprochen.'**
  String get voiceVoicesSampleFailed;

  /// No description provided for @voiceVoicesSpeaker.
  ///
  /// In de, this message translates to:
  /// **'Sprecher'**
  String get voiceVoicesSpeaker;

  /// No description provided for @voiceVoicesStopSample.
  ///
  /// In de, this message translates to:
  /// **'Probe beenden'**
  String get voiceVoicesStopSample;

  /// No description provided for @bargeDebugDefaultSuffix.
  ///
  /// In de, this message translates to:
  /// **'{v} (Standard)'**
  String bargeDebugDefaultSuffix(String v);

  /// No description provided for @bargeDebugExtraThreshold.
  ///
  /// In de, this message translates to:
  /// **'Zusätzliche Schwelle'**
  String get bargeDebugExtraThreshold;

  /// No description provided for @bargeDebugHelpCommunication.
  ///
  /// In de, this message translates to:
  /// **'Kommunikation + AEC (Standard): Das Handy rechnet die eigene Ausgabe aus dem Mikrofon heraus. Wendelin hört sich selbst kaum, dein Wort kommt aber etwas leiser an.'**
  String get bargeDebugHelpCommunication;

  /// No description provided for @bargeDebugHelpMargin.
  ///
  /// In de, this message translates to:
  /// **'Die Schwelle legt fest, wie genau ein Wort passen muss. Höher (0,05, Standard): weniger Fehlalarme, dafür wird dein Wort öfter überhört. Niedriger (0,00 oder -0,05): das Wort wird leichter erkannt, dafür gibt es mehr Fehlalarme.'**
  String get bargeDebugHelpMargin;

  /// No description provided for @bargeDebugHelpRecognition.
  ///
  /// In de, this message translates to:
  /// **'Erkennung, ohne AEC: keine Echo-Unterdrückung. Dein Wort kommt klar an, aber die laufende Ansage übertönt es oft, und Wendelin kann sich selbst hören.'**
  String get bargeDebugHelpRecognition;

  /// No description provided for @bargeDebugHelpRecognitionAec.
  ///
  /// In de, this message translates to:
  /// **'Erkennung + AEC: wie Standard, aber mit dem Mikrofon der Spracherkennung. Hilft auf Geräten, bei denen das Standard-Mikrofon dein Wort zu stark dämpft.'**
  String get bargeDebugHelpRecognitionAec;

  /// No description provided for @bargeDebugIntro.
  ///
  /// In de, this message translates to:
  /// **'Damit stellst du ein, wie empfindlich „Hey Wendelin“ während der Antwort erkannt wird. Die Änderung gilt ab der nächsten gesprochenen Antwort.'**
  String get bargeDebugIntro;

  /// No description provided for @bargeDebugMicCommunication.
  ///
  /// In de, this message translates to:
  /// **'Kommunikation + AEC (Standard)'**
  String get bargeDebugMicCommunication;

  /// No description provided for @bargeDebugMicDuring.
  ///
  /// In de, this message translates to:
  /// **'Mikrofon während der Antwort'**
  String get bargeDebugMicDuring;

  /// No description provided for @bargeDebugMicRecognition.
  ///
  /// In de, this message translates to:
  /// **'Erkennung, ohne AEC'**
  String get bargeDebugMicRecognition;

  /// No description provided for @bargeDebugMicRecognitionAec.
  ///
  /// In de, this message translates to:
  /// **'Erkennung + AEC'**
  String get bargeDebugMicRecognitionAec;

  /// No description provided for @bargeDebugTitle.
  ///
  /// In de, this message translates to:
  /// **'Erweitert: Unterbrechen'**
  String get bargeDebugTitle;

  /// No description provided for @hotwordsBonusHelp.
  ///
  /// In de, this message translates to:
  /// **'Wie stark Namen aus deinen Kontakten und Begriffen bei der Spracherkennung bevorzugt werden. Höher: Namen werden öfter getroffen, dafür tauchen sie auch in Rauschen oder abgeschnittenem Ton auf. Niedriger: weniger falsche Namen. Der Erkenner wird beim Wechsel neu geladen.'**
  String get hotwordsBonusHelp;

  /// No description provided for @hotwordsBonusTitle.
  ///
  /// In de, this message translates to:
  /// **'Bonus Hinweisbegriffe'**
  String get hotwordsBonusTitle;

  /// No description provided for @micAllowTitle.
  ///
  /// In de, this message translates to:
  /// **'Mikrofon erlauben?'**
  String get micAllowTitle;

  /// No description provided for @micAndroidSettings.
  ///
  /// In de, this message translates to:
  /// **'Android-Einstellungen'**
  String get micAndroidSettings;

  /// No description provided for @micExplanation.
  ///
  /// In de, this message translates to:
  /// **'Wendelin hört nur zu, nachdem du ihn ausgelöst hast (Mikrofontaste oder Assistent). Die Aufnahme wird auf dem Gerät in Text umgewandelt und verlässt es nicht; nur der erkannte Text geht an deinen Provider.'**
  String get micExplanation;

  /// No description provided for @micNotNow.
  ///
  /// In de, this message translates to:
  /// **'Nicht jetzt'**
  String get micNotNow;

  /// No description provided for @micOnlyText.
  ///
  /// In de, this message translates to:
  /// **'Ohne Mikrofon geht nur Text. {v}'**
  String micOnlyText(String v);

  /// No description provided for @micSettingsHint.
  ///
  /// In de, this message translates to:
  /// **'In den Android-Einstellungen unter Apps → Wendelin erlauben.'**
  String get micSettingsHint;

  /// No description provided for @wakeCalibrateCancelled.
  ///
  /// In de, this message translates to:
  /// **'Abgebrochen. Es wurde nichts geändert.'**
  String get wakeCalibrateCancelled;

  /// No description provided for @wakeCalibrateDone.
  ///
  /// In de, this message translates to:
  /// **'Kalibriert.'**
  String get wakeCalibrateDone;

  /// No description provided for @wakeCalibrateFailed.
  ///
  /// In de, this message translates to:
  /// **'Gescheitert: {error}'**
  String wakeCalibrateFailed(Object error);

  /// No description provided for @wakeCalibrateFinishNow.
  ///
  /// In de, this message translates to:
  /// **'Jetzt beenden'**
  String get wakeCalibrateFinishNow;

  /// No description provided for @wakeCalibrateIntro.
  ///
  /// In de, this message translates to:
  /// **'Leg das Handy hin und red normal weiter. Wendelin hört mit (Mikrofonanzeige an), merkt sich aber nur Zahlenwerte, kein Audio und keinen Text. Ab und zu piept es: Sag dann „Hey Wendelin“.'**
  String get wakeCalibrateIntro;

  /// No description provided for @wakeCalibrateMicPreparing.
  ///
  /// In de, this message translates to:
  /// **'Mikrofon wird vorbereitet …'**
  String get wakeCalibrateMicPreparing;

  /// No description provided for @wakeCalibrateMinutesLeft.
  ///
  /// In de, this message translates to:
  /// **'Noch {v} min'**
  String wakeCalibrateMinutesLeft(int v);

  /// No description provided for @wakeCalibrateNoMic.
  ///
  /// In de, this message translates to:
  /// **'Ohne Mikrofon kann Wendelin nicht kalibrieren.'**
  String get wakeCalibrateNoMic;

  /// No description provided for @wakeCalibrateNotDistinct.
  ///
  /// In de, this message translates to:
  /// **'Deine Aufnahmen heben sich nicht vom Hintergrund ab. Lerne deine Stimme bitte noch einmal ein. Die alte Schwelle bleibt.'**
  String get wakeCalibrateNotDistinct;

  /// No description provided for @wakeCalibrateProgressLabel.
  ///
  /// In de, this message translates to:
  /// **'Fortschritt Kalibrieren'**
  String get wakeCalibrateProgressLabel;

  /// No description provided for @wakeCalibratePrompts.
  ///
  /// In de, this message translates to:
  /// **'Aufforderungen: {answered} von {prompts} beantwortet'**
  String wakeCalibratePrompts(int answered, int prompts);

  /// No description provided for @wakeCalibrateResult.
  ///
  /// In de, this message translates to:
  /// **'Schwelle {v} · geschätzt {v2} Fehlalarme pro Stunde (vor der Nachprüfung) · {v3} % deiner Aufnahmen erkannt.'**
  String wakeCalibrateResult(String v, String v2, int v3);

  /// No description provided for @wakeCalibrateTitle.
  ///
  /// In de, this message translates to:
  /// **'Kalibrieren'**
  String get wakeCalibrateTitle;

  /// No description provided for @wakeCalibrateUnusable.
  ///
  /// In de, this message translates to:
  /// **'Nicht verwertbar.'**
  String get wakeCalibrateUnusable;

  /// No description provided for @wakeDetectorAuto.
  ///
  /// In de, this message translates to:
  /// **'Automatisch'**
  String get wakeDetectorAuto;

  /// No description provided for @wakeDetectorAutoHint.
  ///
  /// In de, this message translates to:
  /// **'Handy: deine Stimme (Vorlagen). Station: das trainierte Modell.'**
  String get wakeDetectorAutoHint;

  /// No description provided for @wakeDetectorModel.
  ///
  /// In de, this message translates to:
  /// **'Trainiertes Modell'**
  String get wakeDetectorModel;

  /// No description provided for @wakeDetectorModelHint.
  ///
  /// In de, this message translates to:
  /// **'Erkennt das Aktivierungswort ohne Einlernen. Braucht den Download.'**
  String get wakeDetectorModelHint;

  /// No description provided for @wakeDetectorModelNeeded.
  ///
  /// In de, this message translates to:
  /// **'Das trainierte Modell wird für diese Einstellung benötigt: {v}.'**
  String wakeDetectorModelNeeded(String v);

  /// No description provided for @wakeDetectorNothingToHear.
  ///
  /// In de, this message translates to:
  /// **'Ohne das Modell hört nur deine eingelernte Stimme zu, und die fehlt. Lade das Modell oder lerne deine Stimme ein, sonst bleibt das Wake Word aus.'**
  String get wakeDetectorNothingToHear;

  /// No description provided for @wakeDetectorNothingToHearAuto.
  ///
  /// In de, this message translates to:
  /// **'Automatisch hört auf dem Telefon mit deiner eingelernten Stimme, und die fehlt. Lerne deine Stimme ein oder wähle „Trainiertes Modell“, sonst bleibt das Wake Word aus.'**
  String get wakeDetectorNothingToHearAuto;

  /// No description provided for @wakeDetectorTemplates.
  ///
  /// In de, this message translates to:
  /// **'Vorlagen deiner Stimme'**
  String get wakeDetectorTemplates;

  /// No description provided for @wakeDetectorTemplatesHint.
  ///
  /// In de, this message translates to:
  /// **'Vergleicht mit deinen Aufnahmen. Braucht das Einlernen.'**
  String get wakeDetectorTemplatesHint;

  /// No description provided for @wakeDetectorTitle.
  ///
  /// In de, this message translates to:
  /// **'Erkennung'**
  String get wakeDetectorTitle;

  /// No description provided for @wakeEnrollAllThere.
  ///
  /// In de, this message translates to:
  /// **'Alle Aufnahmen sind da.'**
  String get wakeEnrollAllThere;

  /// No description provided for @wakeEnrollFailed.
  ///
  /// In de, this message translates to:
  /// **'Das Einlernen ist gescheitert: {error}'**
  String wakeEnrollFailed(Object error);

  /// No description provided for @wakeEnrollHeard.
  ///
  /// In de, this message translates to:
  /// **'Gehört.'**
  String get wakeEnrollHeard;

  /// No description provided for @wakeEnrollInconsistent.
  ///
  /// In de, this message translates to:
  /// **'Diese Aufnahme passte nicht zu den anderen und wurde entfernt. Bitte noch einmal.'**
  String get wakeEnrollInconsistent;

  /// No description provided for @wakeEnrollIntro.
  ///
  /// In de, this message translates to:
  /// **'Sag „{word}“, wenn du dran bist. Aus jeder Aufnahme behält Wendelin nur Zahlenwerte; das Audio wird sofort verworfen.'**
  String wakeEnrollIntro(String word);

  /// No description provided for @wakeEnrollMicPreparing.
  ///
  /// In de, this message translates to:
  /// **'Mikrofon wird vorbereitet …'**
  String get wakeEnrollMicPreparing;

  /// No description provided for @wakeEnrollMissingHey.
  ///
  /// In de, this message translates to:
  /// **'Bitte „{word}“ sagen, nicht nur den Namen.'**
  String wakeEnrollMissingHey(String word);

  /// No description provided for @wakeEnrollNoMic.
  ///
  /// In de, this message translates to:
  /// **'Ohne Mikrofon kann Wendelin deine Stimme nicht lernen.'**
  String get wakeEnrollNoMic;

  /// No description provided for @wakeEnrollNoRecognizer.
  ///
  /// In de, this message translates to:
  /// **'Spracherkennung fehlt: Ohne sie kann „Hey Wendelin“ beim Einlernen nicht geprüft werden. Bitte lade unter Einstellungen → Sprache ein Erkennungsmodell.'**
  String get wakeEnrollNoRecognizer;

  /// No description provided for @wakeEnrollNoSpeech.
  ///
  /// In de, this message translates to:
  /// **'Nichts gehört. Noch einmal bitte.'**
  String get wakeEnrollNoSpeech;

  /// No description provided for @wakeEnrollNotWord.
  ///
  /// In de, this message translates to:
  /// **'Nicht erkannt. Bitte noch einmal mit „{word}“.'**
  String wakeEnrollNotWord(String word);

  /// No description provided for @wakeEnrollProcessing.
  ///
  /// In de, this message translates to:
  /// **'Wird verarbeitet …'**
  String get wakeEnrollProcessing;

  /// No description provided for @wakeEnrollProgress.
  ///
  /// In de, this message translates to:
  /// **'{accepted} von {target}'**
  String wakeEnrollProgress(int accepted, int target);

  /// No description provided for @wakeEnrollProgressLabel.
  ///
  /// In de, this message translates to:
  /// **'Fortschritt Einlernen'**
  String get wakeEnrollProgressLabel;

  /// No description provided for @wakeEnrollPrompt0.
  ///
  /// In de, this message translates to:
  /// **'Sprich normal, das Handy etwa 0,5–1 m vor dir.'**
  String get wakeEnrollPrompt0;

  /// No description provided for @wakeEnrollPrompt1.
  ///
  /// In de, this message translates to:
  /// **'Jetzt aus ein bis zwei Metern Abstand.'**
  String get wakeEnrollPrompt1;

  /// No description provided for @wakeEnrollPrompt2.
  ///
  /// In de, this message translates to:
  /// **'Jetzt leise, wie abends im Zimmer.'**
  String get wakeEnrollPrompt2;

  /// No description provided for @wakeEnrollPrompt3.
  ///
  /// In de, this message translates to:
  /// **'Wie du es im Alltag sagst, gern aus einer anderen Ecke.'**
  String get wakeEnrollPrompt3;

  /// No description provided for @wakeEnrollQuietTip.
  ///
  /// In de, this message translates to:
  /// **'Mehrmals nichts oder zu leise gehört: Geh näher ans Handy (etwa 0,5–1 m), such einen ruhigeren Raum und sprich normal laut.'**
  String get wakeEnrollQuietTip;

  /// No description provided for @wakeEnrollRejected.
  ///
  /// In de, this message translates to:
  /// **'{count} abgelehnt'**
  String wakeEnrollRejected(int count);

  /// No description provided for @wakeEnrollSaveWith.
  ///
  /// In de, this message translates to:
  /// **'Mit {accepted} Aufnahmen speichern'**
  String wakeEnrollSaveWith(int accepted);

  /// No description provided for @wakeEnrollSayNow.
  ///
  /// In de, this message translates to:
  /// **'Sag jetzt: „{word}“'**
  String wakeEnrollSayNow(String word);

  /// No description provided for @wakeEnrollSetupHint.
  ///
  /// In de, this message translates to:
  /// **'Ruhiger Raum, normal laut sprechen, etwa 0,5–1 m vom Handy entfernt.'**
  String get wakeEnrollSetupHint;

  /// No description provided for @wakeEnrollSpokenWord.
  ///
  /// In de, this message translates to:
  /// **'Hey {name}'**
  String wakeEnrollSpokenWord(String name);

  /// No description provided for @wakeEnrollTitle.
  ///
  /// In de, this message translates to:
  /// **'Stimme einlernen'**
  String get wakeEnrollTitle;

  /// No description provided for @wakeEnrollTooEarly.
  ///
  /// In de, this message translates to:
  /// **'Zu früh angefangen. Warte kurz und sprich dann.'**
  String get wakeEnrollTooEarly;

  /// No description provided for @wakeEnrollTooLong.
  ///
  /// In de, this message translates to:
  /// **'Zu lang. Nur „{word}“, bitte.'**
  String wakeEnrollTooLong(String word);

  /// No description provided for @wakeEnrollTooQuiet.
  ///
  /// In de, this message translates to:
  /// **'Zu leise – bitte näher ans Handy.'**
  String get wakeEnrollTooQuiet;

  /// No description provided for @wakeEnrollUnchecked.
  ///
  /// In de, this message translates to:
  /// **'Die Prüfung ist gerade nicht möglich (Spracherkennung nicht bereit). Bitte noch einmal.'**
  String get wakeEnrollUnchecked;

  /// No description provided for @wakeExplainBatteryBody.
  ///
  /// In de, this message translates to:
  /// **'Das ständige Zuhören kostet Akku. Standard ist deshalb „Nur beim Laden“.'**
  String get wakeExplainBatteryBody;

  /// No description provided for @wakeExplainBatteryExemptBody.
  ///
  /// In de, this message translates to:
  /// **'Damit Android den Dienst nicht beendet, sollte Wendelin von der Akku-Optimierung ausgenommen sein.'**
  String get wakeExplainBatteryExemptBody;

  /// No description provided for @wakeExplainBatteryExemptTitle.
  ///
  /// In de, this message translates to:
  /// **'Akku-Optimierung ausnehmen?'**
  String get wakeExplainBatteryExemptTitle;

  /// No description provided for @wakeExplainBatteryTitle.
  ///
  /// In de, this message translates to:
  /// **'Akku'**
  String get wakeExplainBatteryTitle;

  /// No description provided for @wakeExplainChecklist.
  ///
  /// In de, this message translates to:
  /// **'{v}: {v2}'**
  String wakeExplainChecklist(String v, String v2);

  /// No description provided for @wakeExplainEnable.
  ///
  /// In de, this message translates to:
  /// **'Einschalten'**
  String get wakeExplainEnable;

  /// No description provided for @wakeExplainEnableTitle.
  ///
  /// In de, this message translates to:
  /// **'Aktivierungswort einschalten?'**
  String get wakeExplainEnableTitle;

  /// No description provided for @wakeExplainExempt.
  ///
  /// In de, this message translates to:
  /// **'Ausnehmen'**
  String get wakeExplainExempt;

  /// No description provided for @wakeExplainLocalBody.
  ///
  /// In de, this message translates to:
  /// **'Die Erkennung des Wortes läuft auf dem Gerät. Was du nach „Hey Wendelin“ sagst, wird als Text an den gewählten KI-Anbieter geschickt. Audio wird weder gesendet noch gespeichert.'**
  String get wakeExplainLocalBody;

  /// No description provided for @wakeExplainLocalTitle.
  ///
  /// In de, this message translates to:
  /// **'Zuhören bleibt auf dem Gerät'**
  String get wakeExplainLocalTitle;

  /// No description provided for @wakeExplainMicDotBody.
  ///
  /// In de, this message translates to:
  /// **'Android zeigt den grünen Punkt für das Mikrofon, solange der Dienst zuhört.'**
  String get wakeExplainMicDotBody;

  /// No description provided for @wakeExplainMicDotTitle.
  ///
  /// In de, this message translates to:
  /// **'Mikrofon-Punkt'**
  String get wakeExplainMicDotTitle;

  /// No description provided for @wakeExplainPersistentBody.
  ///
  /// In de, this message translates to:
  /// **'Solange Wendelin zuhört, zeigt Android eine Benachrichtigung. Ab Android 14 kannst du sie wegwischen, der Dienst läuft dann weiter. Ohne die Berechtigung für Benachrichtigungen zeigt Android keine; Wendelin hört trotzdem zu.'**
  String get wakeExplainPersistentBody;

  /// No description provided for @wakeExplainPersistentTitle.
  ///
  /// In de, this message translates to:
  /// **'Dauerhafte Benachrichtigung'**
  String get wakeExplainPersistentTitle;

  /// No description provided for @wakeModelsLoadModel.
  ///
  /// In de, this message translates to:
  /// **'Sprachmodell laden'**
  String get wakeModelsLoadModel;

  /// No description provided for @wakeModelsNeedsModel.
  ///
  /// In de, this message translates to:
  /// **'Dafür muss zuerst das Sprachmodell geladen werden ({v}).'**
  String wakeModelsNeedsModel(String v);

  /// No description provided for @wakeModelsVerifyNeeds.
  ///
  /// In de, this message translates to:
  /// **'Für die Nachprüfung Sprachmodell laden ({v}).'**
  String wakeModelsVerifyNeeds(String v);

  /// No description provided for @wakeNotifChannelDesc.
  ///
  /// In de, this message translates to:
  /// **'Zeigt, dass Wendelin auf „Hey Wendelin“ hört.'**
  String get wakeNotifChannelDesc;

  /// No description provided for @wakeNotifEnded.
  ///
  /// In de, this message translates to:
  /// **'Das Aktivierungswort wurde beendet ({reason}). Tippe, um es wieder einzuschalten.'**
  String wakeNotifEnded(String reason);

  /// No description provided for @wakeNotifGapAction.
  ///
  /// In de, this message translates to:
  /// **'Modell laden'**
  String get wakeNotifGapAction;

  /// No description provided for @wakeNotifGapNoSeqAction.
  ///
  /// In de, this message translates to:
  /// **'Neu einlernen'**
  String get wakeNotifGapNoSeqAction;

  /// No description provided for @wakeNotifGapNoSeqText.
  ///
  /// In de, this message translates to:
  /// **'Aktivierungswort kann nicht sicher geprüft werden – bitte neu einlernen'**
  String get wakeNotifGapNoSeqText;

  /// No description provided for @wakeNotifGapText.
  ///
  /// In de, this message translates to:
  /// **'Aktivierungswort kann nicht geprüft werden – Erkennungsmodell laden'**
  String get wakeNotifGapText;

  /// No description provided for @wakeNotifListeningText.
  ///
  /// In de, this message translates to:
  /// **'Das Mikrofon ist an. Audio bleibt auf dem Gerät.'**
  String get wakeNotifListeningText;

  /// No description provided for @wakeNotifListeningTitle.
  ///
  /// In de, this message translates to:
  /// **'Wendelin hört auf „Hey Wendelin“'**
  String get wakeNotifListeningTitle;

  /// No description provided for @wakeNotifNoRole.
  ///
  /// In de, this message translates to:
  /// **'Wendelin muss der Assistent sein, damit das Aktivierungswort nach einem Neustart laufen kann.'**
  String get wakeNotifNoRole;

  /// No description provided for @wakeNotifOff.
  ///
  /// In de, this message translates to:
  /// **'Aus'**
  String get wakeNotifOff;

  /// No description provided for @wakeNotifPause.
  ///
  /// In de, this message translates to:
  /// **'Pause 1 h'**
  String get wakeNotifPause;

  /// No description provided for @wakeNotifPausedText.
  ///
  /// In de, this message translates to:
  /// **'Bis {time} Uhr, das Mikrofon ist frei.'**
  String wakeNotifPausedText(String time);

  /// No description provided for @wakeNotifPausedTitle.
  ///
  /// In de, this message translates to:
  /// **'Wendelin pausiert'**
  String get wakeNotifPausedTitle;

  /// No description provided for @wakeNotifReenableAction.
  ///
  /// In de, this message translates to:
  /// **'Wieder einschalten'**
  String get wakeNotifReenableAction;

  /// No description provided for @wakeNotifReenableTitle.
  ///
  /// In de, this message translates to:
  /// **'Aktivierungswort ist aus'**
  String get wakeNotifReenableTitle;

  /// No description provided for @wakeNotifResume.
  ///
  /// In de, this message translates to:
  /// **'Fortsetzen'**
  String get wakeNotifResume;

  /// No description provided for @wakeServiceSectionAlways.
  ///
  /// In de, this message translates to:
  /// **'Immer'**
  String get wakeServiceSectionAlways;

  /// No description provided for @wakeServiceSectionAlwaysHint.
  ///
  /// In de, this message translates to:
  /// **'Kostet spürbar Akku.'**
  String get wakeServiceSectionAlwaysHint;

  /// No description provided for @wakeServiceSectionBackground.
  ///
  /// In de, this message translates to:
  /// **'Zuhören im Hintergrund'**
  String get wakeServiceSectionBackground;

  /// No description provided for @wakeServiceSectionChime.
  ///
  /// In de, this message translates to:
  /// **'Bestätigungston'**
  String get wakeServiceSectionChime;

  /// No description provided for @wakeServiceSectionChimeDetail.
  ///
  /// In de, this message translates to:
  /// **'Ein kurzer Ton, wenn Wendelin das Wort erkannt hat.'**
  String get wakeServiceSectionChimeDetail;

  /// No description provided for @wakeServiceSectionChooseAssistant.
  ///
  /// In de, this message translates to:
  /// **'Assistenten wählen'**
  String get wakeServiceSectionChooseAssistant;

  /// No description provided for @wakeServiceSectionEnable.
  ///
  /// In de, this message translates to:
  /// **'Aktivierungswort einschalten'**
  String get wakeServiceSectionEnable;

  /// No description provided for @wakeServiceSectionEnableDetail.
  ///
  /// In de, this message translates to:
  /// **'Wendelin hört im Hintergrund auf „Hey Wendelin“. Im Stationsmodus ist es immer an.'**
  String get wakeServiceSectionEnableDetail;

  /// No description provided for @wakeServiceSectionEndedEngine.
  ///
  /// In de, this message translates to:
  /// **'Beendet: Die Erkennung ist ausgefallen'**
  String get wakeServiceSectionEndedEngine;

  /// No description provided for @wakeServiceSectionEndedModel.
  ///
  /// In de, this message translates to:
  /// **'Beendet: Ein Modell für die Wake-Erkennung fehlt'**
  String get wakeServiceSectionEndedModel;

  /// No description provided for @wakeServiceSectionEndedNoPermission.
  ///
  /// In de, this message translates to:
  /// **'Beendet: Mikrofon-Berechtigung fehlt'**
  String get wakeServiceSectionEndedNoPermission;

  /// No description provided for @wakeServiceSectionEndedNoRole.
  ///
  /// In de, this message translates to:
  /// **'Beendet: Wendelin ist nicht mehr dein Assistent'**
  String get wakeServiceSectionEndedNoRole;

  /// No description provided for @wakeServiceSectionEndedNotCharging.
  ///
  /// In de, this message translates to:
  /// **'Beendet: Das Gerät lädt nicht mehr'**
  String get wakeServiceSectionEndedNotCharging;

  /// No description provided for @wakeServiceSectionEndedPaused.
  ///
  /// In de, this message translates to:
  /// **'Beendet: pausiert'**
  String get wakeServiceSectionEndedPaused;

  /// No description provided for @wakeServiceSectionEndedSystem.
  ///
  /// In de, this message translates to:
  /// **'Vom System beendet'**
  String get wakeServiceSectionEndedSystem;

  /// No description provided for @wakeServiceSectionEndedTimeout.
  ///
  /// In de, this message translates to:
  /// **'Vom System beendet (Zeitlimit von Android)'**
  String get wakeServiceSectionEndedTimeout;

  /// No description provided for @wakeServiceSectionEnrollFirst.
  ///
  /// In de, this message translates to:
  /// **'Erst Stimme einlernen'**
  String get wakeServiceSectionEnrollFirst;

  /// No description provided for @wakeServiceSectionEnrollFirstBody.
  ///
  /// In de, this message translates to:
  /// **'Ohne eingelernte Stimme erkennt Wendelin das Aktivierungswort nicht.'**
  String get wakeServiceSectionEnrollFirstBody;

  /// No description provided for @wakeServiceSectionNotAssistant.
  ///
  /// In de, this message translates to:
  /// **'Wendelin ist nicht dein Assistent'**
  String get wakeServiceSectionNotAssistant;

  /// No description provided for @wakeServiceSectionNotAssistantBody.
  ///
  /// In de, this message translates to:
  /// **'Android erlaubt das Zuhören im Hintergrund nur dem Standard-Assistenten. Wähle Wendelin als Assistenten.'**
  String get wakeServiceSectionNotAssistantBody;

  /// No description provided for @wakeServiceSectionOnlyCharging.
  ///
  /// In de, this message translates to:
  /// **'Nur beim Laden'**
  String get wakeServiceSectionOnlyCharging;

  /// No description provided for @wakeServiceSectionOnlyChargingHint.
  ///
  /// In de, this message translates to:
  /// **'Schont den Akku (Standard).'**
  String get wakeServiceSectionOnlyChargingHint;

  /// No description provided for @wakeServiceSectionPausedLoading.
  ///
  /// In de, this message translates to:
  /// **'Pausiert: wartet auf das Laden'**
  String get wakeServiceSectionPausedLoading;

  /// No description provided for @wakeServiceSectionPausedUntil.
  ///
  /// In de, this message translates to:
  /// **'Pausiert bis {v}'**
  String wakeServiceSectionPausedUntil(String v);

  /// No description provided for @wakeServiceSectionRunning.
  ///
  /// In de, this message translates to:
  /// **'Läuft'**
  String get wakeServiceSectionRunning;

  /// No description provided for @wakeServiceSectionSettingsFail.
  ///
  /// In de, this message translates to:
  /// **'Die Systemeinstellungen ließen sich nicht öffnen.'**
  String get wakeServiceSectionSettingsFail;

  /// No description provided for @wakeServiceSectionSoundCheck.
  ///
  /// In de, this message translates to:
  /// **'Ton und Prüfung'**
  String get wakeServiceSectionSoundCheck;

  /// No description provided for @wakeServiceSectionStatus.
  ///
  /// In de, this message translates to:
  /// **'Status'**
  String get wakeServiceSectionStatus;

  /// No description provided for @wakeServiceSectionToEnroll.
  ///
  /// In de, this message translates to:
  /// **'Zum Einlernen'**
  String get wakeServiceSectionToEnroll;

  /// No description provided for @wakeServiceSectionWhen.
  ///
  /// In de, this message translates to:
  /// **'Wann zuhören?'**
  String get wakeServiceSectionWhen;

  /// No description provided for @wakeServiceSectionWhisper.
  ///
  /// In de, this message translates to:
  /// **'Nachprüfung (Stufe 2)'**
  String get wakeServiceSectionWhisper;

  /// No description provided for @wakeServiceSectionWhisperDetail.
  ///
  /// In de, this message translates to:
  /// **'Wendelin hört nur zu, wenn die Nachprüfung das Aktivierungswort bestätigt. Sie umfasst die ganze Stufe 2: Prüfer B, Parakeet oder Whisper, je nachdem, was eingelernt und geladen ist. Schalte sie aus, wenn sie mit deiner Stimme zu streng ist; dann gibt es mehr Fehlauslösungen.'**
  String get wakeServiceSectionWhisperDetail;

  /// No description provided for @wakeStage2GapLoad.
  ///
  /// In de, this message translates to:
  /// **'Erkennungsmodell laden'**
  String get wakeStage2GapLoad;

  /// No description provided for @wakeStage2GapNotice.
  ///
  /// In de, this message translates to:
  /// **'Die zweite Prüfung kann nicht entscheiden: Für „Hey Wendelin“ fehlt ein Erkennungsmodell, und die eingelernte Stimme hat noch keine Folgen für den Prüfer. Treffer werden deshalb verworfen. Lade das Erkennungsmodell oder lerne die Stimme neu ein.'**
  String get wakeStage2GapNotice;

  /// No description provided for @wakeStage2NoSeqEnroll.
  ///
  /// In de, this message translates to:
  /// **'Aktivierungswort neu einlernen'**
  String get wakeStage2NoSeqEnroll;

  /// No description provided for @wakeStage2NoSeqNotice.
  ///
  /// In de, this message translates to:
  /// **'Die zweite Prüfung ist unsicher: Die eingelernte Stimme hat noch keine Folgen für den Prüfer, und es wird nur das Erkennungsmodell gefragt. Das kann echte Rufe verwerfen. Lerne das Aktivierungswort neu ein.'**
  String get wakeStage2NoSeqNotice;

  /// No description provided for @wakeTestAgo.
  ///
  /// In de, this message translates to:
  /// **'{v} · {inSeconds} s'**
  String wakeTestAgo(String v, int inSeconds);

  /// No description provided for @wakeTestBest.
  ///
  /// In de, this message translates to:
  /// **'{v} · höchste Ähnlichkeit {v2}'**
  String wakeTestBest(String v, String v2);

  /// No description provided for @wakeTestCandidate.
  ///
  /// In de, this message translates to:
  /// **'Kandidat · Ähnlichkeit {v}'**
  String wakeTestCandidate(String v);

  /// No description provided for @wakeTestConfirmed.
  ///
  /// In de, this message translates to:
  /// **'Nachprüfung: bestätigt'**
  String get wakeTestConfirmed;

  /// No description provided for @wakeTestDecidedBy.
  ///
  /// In de, this message translates to:
  /// **'{v} (Befehlserkennung: {who})'**
  String wakeTestDecidedBy(String v, String who);

  /// No description provided for @wakeTestFailed.
  ///
  /// In de, this message translates to:
  /// **'Gescheitert: {error}'**
  String wakeTestFailed(Object error);

  /// No description provided for @wakeTestIntro.
  ///
  /// In de, this message translates to:
  /// **'Sag „Hey Wendelin“. Hier erscheinen Treffer, ohne dass das Overlay aufgeht. „Kandidat“ ist die Stimme. „Bestätigt“ heißt: Die Befehlserkennung (Parakeet oder Whisper) hat das Aktivierungswort gehört. Das ist nicht die Nachprüfung (Stufe 2) des Dienstes; sie kann strenger sein.'**
  String get wakeTestIntro;

  /// No description provided for @wakeTestListening.
  ///
  /// In de, this message translates to:
  /// **'Hört zu'**
  String get wakeTestListening;

  /// No description provided for @wakeTestMicPreparing.
  ///
  /// In de, this message translates to:
  /// **'Mikrofon wird vorbereitet …'**
  String get wakeTestMicPreparing;

  /// No description provided for @wakeTestNoHit.
  ///
  /// In de, this message translates to:
  /// **'Noch kein Treffer.'**
  String get wakeTestNoHit;

  /// No description provided for @wakeTestNoMic.
  ///
  /// In de, this message translates to:
  /// **'Ohne Mikrofon geht der Test nicht.'**
  String get wakeTestNoMic;

  /// No description provided for @wakeTestRejected.
  ///
  /// In de, this message translates to:
  /// **'Nachprüfung: nicht bestätigt'**
  String get wakeTestRejected;

  /// No description provided for @wakeTestStopped.
  ///
  /// In de, this message translates to:
  /// **'Angehalten'**
  String get wakeTestStopped;

  /// No description provided for @wakeTestTitle.
  ///
  /// In de, this message translates to:
  /// **'Ausprobieren'**
  String get wakeTestTitle;

  /// No description provided for @wakeTestUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Nachprüfung: nicht möglich (Erkenner nicht geladen)'**
  String get wakeTestUnavailable;

  /// No description provided for @wakeTestVerifierParakeet.
  ///
  /// In de, this message translates to:
  /// **'Parakeet'**
  String get wakeTestVerifierParakeet;

  /// No description provided for @wakeTestVerifierWhisper.
  ///
  /// In de, this message translates to:
  /// **'Whisper'**
  String get wakeTestVerifierWhisper;

  /// No description provided for @wakeTestVerifying.
  ///
  /// In de, this message translates to:
  /// **'Nachprüfung läuft …'**
  String get wakeTestVerifying;

  /// No description provided for @wakeWordActionsFor.
  ///
  /// In de, this message translates to:
  /// **'Aktionen für {v}'**
  String wakeWordActionsFor(String v);

  /// No description provided for @wakeWordCalibrate.
  ///
  /// In de, this message translates to:
  /// **'Kalibrieren (30 min, empfohlen)'**
  String get wakeWordCalibrate;

  /// No description provided for @wakeWordDeleteAll.
  ///
  /// In de, this message translates to:
  /// **'Alle Stimmen löschen'**
  String get wakeWordDeleteAll;

  /// No description provided for @wakeWordDeleteAllBody.
  ///
  /// In de, this message translates to:
  /// **'Wendelin vergisst alle eingelernten Stimmen. Du kannst sie später neu einlernen.'**
  String get wakeWordDeleteAllBody;

  /// No description provided for @wakeWordDeleteAllTitle.
  ///
  /// In de, this message translates to:
  /// **'Alle Stimmen löschen?'**
  String get wakeWordDeleteAllTitle;

  /// No description provided for @wakeWordEnroll.
  ///
  /// In de, this message translates to:
  /// **'Stimme einlernen'**
  String get wakeWordEnroll;

  /// No description provided for @wakeWordEnrollMore.
  ///
  /// In de, this message translates to:
  /// **'Weitere Person einlernen'**
  String get wakeWordEnrollMore;

  /// No description provided for @wakeWordFeatureModels.
  ///
  /// In de, this message translates to:
  /// **'Merkmalsmodelle'**
  String get wakeWordFeatureModels;

  /// No description provided for @wakeWordIntro.
  ///
  /// In de, this message translates to:
  /// **'Wendelin lernt deine Stimme: Du sagst „Hey Wendelin“ etwa 15 Mal, danach erkennt er es auch im Alltag. Gespeichert werden nur Zahlenwerte, verschlüsselt auf dem Gerät. Audio wird nie gespeichert.'**
  String get wakeWordIntro;

  /// No description provided for @wakeWordLearned.
  ///
  /// In de, this message translates to:
  /// **'Gelernte Stimmen'**
  String get wakeWordLearned;

  /// No description provided for @wakeWordNameOptional.
  ///
  /// In de, this message translates to:
  /// **'Name (optional)'**
  String get wakeWordNameOptional;

  /// No description provided for @wakeWordNeedsModel.
  ///
  /// In de, this message translates to:
  /// **'Dafür muss zuerst das Sprachmodell geladen werden.'**
  String get wakeWordNeedsModel;

  /// No description provided for @wakeWordNoVoice.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Stimme'**
  String get wakeWordNoVoice;

  /// No description provided for @wakeWordNoVoiceHint.
  ///
  /// In de, this message translates to:
  /// **'Lerne mit „Stimme einlernen“ deine Stimme ein.'**
  String get wakeWordNoVoiceHint;

  /// No description provided for @wakeWordPerson.
  ///
  /// In de, this message translates to:
  /// **'Person {number}'**
  String wakeWordPerson(int number);

  /// No description provided for @wakeWordRecordingsThreshold.
  ///
  /// In de, this message translates to:
  /// **'{length} Aufnahmen · Schwelle {v}'**
  String wakeWordRecordingsThreshold(int length, String v);

  /// No description provided for @wakeWordRelearnForVerifier.
  ///
  /// In de, this message translates to:
  /// **'Neu einlernen für den Prüfer.'**
  String get wakeWordRelearnForVerifier;

  /// No description provided for @wakeWordRetrain.
  ///
  /// In de, this message translates to:
  /// **'Neu einlernen'**
  String get wakeWordRetrain;

  /// No description provided for @wakeWordTemplatesFew.
  ///
  /// In de, this message translates to:
  /// **'Nur {count} brauchbare Aufnahmen übrig. Bitte neu einlernen.'**
  String wakeWordTemplatesFew(int count);

  /// No description provided for @wakeWordTemplatesMissing.
  ///
  /// In de, this message translates to:
  /// **'Vorlagen fehlen. Bitte neu einlernen.'**
  String get wakeWordTemplatesMissing;

  /// No description provided for @wakeWordTemplatesOutdated.
  ///
  /// In de, this message translates to:
  /// **'Die Vorlagen sind veraltet (der Vergleich wurde verbessert). Bitte neu einlernen.'**
  String get wakeWordTemplatesOutdated;

  /// No description provided for @wakeWordTryNow.
  ///
  /// In de, this message translates to:
  /// **'Jetzt ausprobieren'**
  String get wakeWordTryNow;

  /// No description provided for @wakeWordWhoCalibrate.
  ///
  /// In de, this message translates to:
  /// **'Wen kalibrieren?'**
  String get wakeWordWhoCalibrate;

  /// No description provided for @wakeWordWhoJoins.
  ///
  /// In de, this message translates to:
  /// **'Wer kommt dazu?'**
  String get wakeWordWhoJoins;

  /// No description provided for @wakeWordWhoSpeaks.
  ///
  /// In de, this message translates to:
  /// **'Wer spricht?'**
  String get wakeWordWhoSpeaks;

  /// No description provided for @weatherHomeHelp.
  ///
  /// In de, this message translates to:
  /// **'Wird genutzt, wenn du keinen Ort nennst und der Standort nicht bekannt ist. Leer lassen = kein Heimatort.'**
  String get weatherHomeHelp;

  /// No description provided for @weatherHomeLabel.
  ///
  /// In de, this message translates to:
  /// **'Heimatort, z. B. Kiel'**
  String get weatherHomeLabel;

  /// No description provided for @weatherIntro.
  ///
  /// In de, this message translates to:
  /// **'Alle Wetterdienste sind kostenlos und brauchen keinen Schlüssel. Meeresdaten (Wellen, Wassertemperatur) kommen immer von Open-Meteo.'**
  String get weatherIntro;

  /// No description provided for @weatherKindBrightSkyDetail.
  ///
  /// In de, this message translates to:
  /// **'Daten des Deutschen Wetterdienstes'**
  String get weatherKindBrightSkyDetail;

  /// No description provided for @weatherKindMetNorwayDetail.
  ///
  /// In de, this message translates to:
  /// **'Norwegischer Wetterdienst, weltweit'**
  String get weatherKindMetNorwayDetail;

  /// No description provided for @weatherKindOpenMeteoDetail.
  ///
  /// In de, this message translates to:
  /// **'Standard, weltweit'**
  String get weatherKindOpenMeteoDetail;

  /// No description provided for @weatherNotFound.
  ///
  /// In de, this message translates to:
  /// **'Ort „{name}“ nicht gefunden.'**
  String weatherNotFound(String name);

  /// No description provided for @weatherSearchFailed.
  ///
  /// In de, this message translates to:
  /// **'Ortssuche nicht erreichbar, später erneut.'**
  String get weatherSearchFailed;

  /// No description provided for @weatherSetupDetail.
  ///
  /// In de, this message translates to:
  /// **'Dienst wählen, Ort für „Wetter hier“ festlegen'**
  String get weatherSetupDetail;

  /// No description provided for @weatherSetupTitle.
  ///
  /// In de, this message translates to:
  /// **'Wetterdienst und Heimatort'**
  String get weatherSetupTitle;

  /// No description provided for @weatherTitle.
  ///
  /// In de, this message translates to:
  /// **'Wetter und Meer'**
  String get weatherTitle;

  /// No description provided for @webSearchAddress.
  ///
  /// In de, this message translates to:
  /// **'Adresse, z. B. https://search.example.org'**
  String get webSearchAddress;

  /// No description provided for @webSearchAddressMissing.
  ///
  /// In de, this message translates to:
  /// **'Bitte die Adresse der Instanz angeben.'**
  String get webSearchAddressMissing;

  /// No description provided for @webSearchApiKey.
  ///
  /// In de, this message translates to:
  /// **'API-Key'**
  String get webSearchApiKey;

  /// No description provided for @webSearchIntro.
  ///
  /// In de, this message translates to:
  /// **'Ohne Suchdienst kann Wendelin nur Seiten lesen, deren Adresse du nennst.'**
  String get webSearchIntro;

  /// No description provided for @webSearchKeyMissing.
  ///
  /// In de, this message translates to:
  /// **'Bitte den API-Key eingeben.'**
  String get webSearchKeyMissing;

  /// No description provided for @webSearchKeySaved.
  ///
  /// In de, this message translates to:
  /// **'Key gespeichert – leer lassen behält ihn'**
  String get webSearchKeySaved;

  /// No description provided for @webSearchNone.
  ///
  /// In de, this message translates to:
  /// **'Kein Suchdienst'**
  String get webSearchNone;

  /// No description provided for @webSearchOwnInstance.
  ///
  /// In de, this message translates to:
  /// **'SearXNG (eigene Instanz)'**
  String get webSearchOwnInstance;

  /// No description provided for @webSearchTitle.
  ///
  /// In de, this message translates to:
  /// **'Web-Suche'**
  String get webSearchTitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
