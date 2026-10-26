# Plattformkanäle

Kotlin unter `app/android/app/src/main/kotlin/app/wendelin/`. Kanalnamen sind Konstanten in `app/lib/platform/channels.dart` und `CHANNEL` in der Kotlin-Klasse. **Das Manifest `app/channels.json` listet je Kanal Dart-/Kotlin-Dateien, Methoden (Richtung, Argumentschlüssel, Rückgabeart); `tool/check_channels.dart` (Gate) vergleicht es per Textanalyse mit beiden Seiten** (Methode nur auf einer Seite, Argumentschlüssel nur auf einer Seite, Kanal ohne Manifest-Eintrag und umgekehrt sind Fehler mit Datei und Zeile).

Die Logik ohne Android-Abhängigkeit liegt in reinen Kotlin-Klassen mit JVM-Unit-Tests (`app/android/app/src/test/kotlin/app/wendelin/`, Gate-Schritt `kotlin-unit`): `ChannelArgs.kt` (Argumentprüfung), `CalendarRows.kt` (Zeilen → Maps, Zeitzonen, Dauer, Filter), `VaultTree.kt` (`VaultResolver`: Pfade, Ordner anlegen, Lesen/Schreiben auf einem `VaultTree`), `OAuthRedirect.kt` (Redirect-Prüfung). Die Android-Seite dazu: `CalendarStore.kt`, `SafVaultTree.kt`.

**Die Tabelle der Kanäle** (Dart-Dateien, Kotlin-Dateien, Methoden mit Argumentschlüsseln je Richtung) **wird aus `app/channels.json` erzeugt:** [generated/channels.md](generated/channels.md) (`dart run tool/gen_docs.dart`, im Gate geprüft). Ein neuer Kanal erscheint dort nach dem Eintrag im Manifest; hier steht keine zweite Tabelle.
