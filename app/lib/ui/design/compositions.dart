// Nachbauten der Entwurfs-Screens mit Beispieldaten (für Galerie und
// Golden-Tests). Keine Logik; die echten Screens verdrahtet WP08.

import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../theme/app_theme.dart';
import 'assistant_text.dart';
import 'confirmation_card.dart';
import 'escalation_divider.dart';
import 'icons.dart';
import 'integration_tile.dart';
import 'logo.dart';
import 'meta_chip.dart';
import 'mic_button.dart';
import 'provider_chip.dart';
import 'section_card.dart';
import 'sheet_parts.dart';
import 'tool_chip.dart';
import 'user_bubble.dart';

void _noop() {}

/// Antwortblock des Assistenten: Tool-Chips über dem Text, max. 92 % breit.
class _AnswerGroup extends StatelessWidget {
  const _AnswerGroup({required this.tools, required this.answer});

  final List<String> tools;
  final Widget answer;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    widthFactor: WSize.answerMaxFraction,
    alignment: AlignmentDirectional.centerStart,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: WSpace.s,
      children: [
        Wrap(
          spacing: WSpace.xs6,
          runSpacing: WSpace.xs6,
          children: [for (final t in tools) ToolChip(t)],
        ),
        answer,
      ],
    ),
  );
}

/// Screen „Hauptbildschirm“ (docs/design/screens/hauptbildschirm.html).
class MainScreenSample extends StatelessWidget {
  /// Erstellt den Nachbau.
  const MainScreenSample({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WSpace.screen,
              WSpace.screenTop - WSize.tapTargetInset,
              WSpace.screen,
              WSpace.m - WSize.tapTargetInset,
            ),
            child: Row(
              children: [
                const WendelinMark(size: WSize.markHeader),
                const SizedBox(width: WSpace.s10),
                const WendelinWordmark(),
                const Spacer(),
                WIconButton(
                  icon: WIcons.settings,
                  tooltip: 'Einstellungen',
                  onPressed: _noop,
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(
              WSpace.screen,
              0,
              WSpace.screen,
              WSpace.m,
            ),
            child: Wrap(
              spacing: WSpace.s,
              runSpacing: WSpace.s,
              children: [
                ProviderChip(
                  name: 'Phala · GLM klein',
                  level: PrivacyLevel.tee,
                ),
                MetaChip('heute 0,03 €'),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: WSpace.screen,
                vertical: WSpace.s,
              ),
              children: [
                for (final w in <Widget>[
                  Text(
                    'Heute · 08:12',
                    style: WText.mono,
                    textAlign: TextAlign.center,
                  ),
                  const UserBubble('Wie wird das Meer morgen früh?'),
                  const _AnswerGroup(
                    tools: ['weather__marine_forecast'],
                    answer: AssistantText(
                      'Ruhig: 0,4 m Welle, Dünung aus Südwest, Wasser 19 °C. '
                      'Gute Bedingungen fürs Tauchen.',
                    ),
                  ),
                  const UserBubble(
                    'Claude, fass meine Notizen zum Tauchkurs zusammen und '
                    'häng es an die Tagesnotiz.',
                  ),
                  const EscalationDivider('an Claude Sonnet übergeben'),
                  const _AnswerGroup(
                    tools: [
                      'obsidian__search_notes',
                      'obsidian__append_daily_note',
                    ],
                    answer: AssistantText(
                      'Fünf Punkte aus drei Notizen, angehängt unter '
                      '„Tauchen“ in der Tagesnotiz vom 12.10.',
                      linkLabel: 'Notiz öffnen',
                      onLinkTap: _noop,
                    ),
                  ),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: WSpace.m14),
                    child: w,
                  ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: WColors.surface, width: WSize.divider),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                WSpace.l,
                WSpace.m,
                WSpace.l,
                WSpace.xxl,
              ),
              child: Row(
                spacing: WSpace.m,
                children: [
                  Expanded(
                    child: TextField(
                      style: WText.body,
                      decoration: const InputDecoration(
                        hintText: 'Schreiben statt sprechen',
                      ),
                    ),
                  ),
                  MicButton(
                    state: MicState.idle,
                    onPressed: _noop,
                    compact: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Grauer Hintergrund, der „irgendeine andere App“ hinter dem Sheet andeutet.
class _SheetBackdrop extends StatelessWidget {
  const _SheetBackdrop({required this.sheetHeight, required this.sheet});

  final double sheetHeight;
  final Widget sheet;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: WColors.line,
      child: Column(
        children: [
          const Spacer(),
          SizedBox(
            height: sheetHeight,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: WColors.ink,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(WRadius.sheet),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  WSpace.screen,
                  WSpace.m14,
                  WSpace.screen,
                  WSpace.xxl,
                ),
                child: sheet,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Screen „Bestätigung“ (docs/design/screens/bestaetigung.html).
class ConfirmationSheetSample extends StatelessWidget {
  /// Erstellt den Nachbau.
  const ConfirmationSheetSample({super.key});

  /// Höhe des Sheets in der Vorlage.
  static const sheetHeight = 520.0;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: _SheetBackdrop(
        sheetHeight: sheetHeight,
        sheet: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WSpace.l18,
          children: [
            const SheetDragHandle(),
            const SheetHeader(
              trailing: ProviderChip(
                name: 'Claude Haiku',
                level: PrivacyLevel.standard,
              ),
            ),
            Text(
              '„Lösch den Zahnarzttermin am Donnerstag.“',
              style: WText.quote,
            ),
            const Expanded(
              child: ConfirmationCard(
                title: 'Termin löschen?',
                subject: 'Zahnarzt Dr. Weber',
                detail: 'Do 15.10. · 08:30–09:15 · Kalender Familie',
                toolName: 'calendar__delete_event',
                risk: RiskLevel.external,
                onYes: _noop,
                onNo: _noop,
                yesLabel: 'Ja, löschen',
                noLabel: 'Nein, behalten',
                expand: true,
              ),
            ),
            const VoiceHint('Sag einfach „ja“ oder „nein“'),
          ],
        ),
      ),
    );
  }
}

/// Screen „Integrationen“ (docs/design/screens/integrationen.html).
class IntegrationsSample extends StatelessWidget {
  /// Erstellt den Nachbau.
  const IntegrationsSample({super.key});

  @override
  Widget build(BuildContext context) {
    void toggle(bool _) {}
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.fromLTRB(
          WSpace.screen,
          WSpace.screenTop - WSize.tapTargetInset,
          WSpace.screen,
          WSpace.xl24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              spacing: WSpace.m,
              children: [
                WIconButton(
                  icon: WIcons.back,
                  tooltip: 'Zurück',
                  onPressed: _noop,
                  iconSize: WSize.iconSmall,
                ),
                Text('Integrationen', style: WText.screenTitle),
              ],
            ),
            const SizedBox(height: WSpace.l18 - WSize.tapTargetInset),
            Text(
              'Nur aktive Integrationen gehen ans Modell. '
              'Ausgeschaltete kosten keine Tokens.',
              style: WText.intro,
            ),
            const SizedBox(height: WSpace.l18),
            SectionCard(
              children: [
                IntegrationTile(
                  name: 'Kalender',
                  icon: WIcons.calendar,
                  status: IntegrationStatus.active,
                  detail: '6 Tools',
                  onToggle: toggle,
                ),
                IntegrationTile(
                  name: 'Obsidian',
                  icon: WIcons.note,
                  status: IntegrationStatus.active,
                  detail: 'Vault „Leben“',
                  onToggle: toggle,
                ),
                const IntegrationTile(
                  name: 'Bring! Einkaufsliste',
                  icon: WIcons.cart,
                  status: IntegrationStatus.setupRequired,
                  detail: 'Login fehlt',
                  onAction: _noop,
                ),
                const IntegrationTile(
                  name: 'Spotify',
                  icon: WIcons.music,
                  status: IntegrationStatus.error,
                  detail: 'Token abgelaufen · pausiert',
                  onAction: _noop,
                ),
                IntegrationTile(
                  name: 'Wetter und Meer',
                  icon: WIcons.waves,
                  status: IntegrationStatus.available,
                  onToggle: toggle,
                ),
                IntegrationTile(
                  name: 'Kontakte',
                  icon: WIcons.person,
                  status: IntegrationStatus.available,
                  sensitive: true,
                  minPrivacy: PrivacyLevel.tee,
                  onToggle: toggle,
                ),
                const IntegrationTile(
                  name: 'Todoist',
                  icon: WIcons.task,
                  status: IntegrationStatus.unavailable,
                  detail: 'App nicht installiert',
                  onStore: _noop,
                ),
              ],
            ),
            const SizedBox(height: WSpace.l18),
            Row(
              spacing: WSpace.m,
              children: [
                for (final label in ['+ MCP-Server', '+ HTTP-Tool'])
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _noop,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(WSize.buttonHeight),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            WRadius.buttonLarge,
                          ),
                        ),
                      ),
                      child: Text(label),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
