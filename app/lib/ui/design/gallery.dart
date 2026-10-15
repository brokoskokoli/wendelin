import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'compositions.dart';
import 'design.dart';

void _noop() {}
void _toggle(bool _) {}

/// Beispieldaten für die Wellenform.
const sampleAmplitudes = [0.2, 0.5, 0.83, 0.39, 0.61, 0.22];

/// Alle Bausteine in allen Zuständen, gruppiert nach Baustein.
///
/// Jeder Eintrag ist ein Abschnitt der Galerie und zugleich ein Golden.
final Map<String, List<Widget>> gallerySections = {
  'Logo': const [
    WendelinLockup(),
    Row(
      spacing: WSpace.l,
      children: [
        WendelinMark(),
        WendelinMark(size: WSize.markHeader),
      ],
    ),
    WendelinWordmark(),
  ],
  'MicButton': [
    Wrap(
      spacing: WSpace.xxl,
      runSpacing: WSpace.xxl,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final s in MicState.values) MicButton(state: s, onPressed: _noop),
        for (final s in MicState.values)
          MicButton(state: s, onPressed: _noop, compact: true),
      ],
    ),
  ],
  'Waveform': const [
    Waveform(amplitudes: sampleAmplitudes),
    Waveform(amplitudes: [0, 0, 0, 0, 0, 0]),
    Waveform(amplitudes: [1, 1, 1, 1, 1, 1], color: WColors.textMuted),
  ],
  'PrivacyChip': [
    Wrap(
      spacing: WSpace.s,
      runSpacing: WSpace.s,
      children: [for (final l in PrivacyLevel.values) PrivacyChip(l)],
    ),
  ],
  'ProviderChip': const [
    ProviderChip(name: 'Ollama · Homeserver', level: PrivacyLevel.local),
    ProviderChip(
      name: 'Phala · GLM klein',
      level: PrivacyLevel.tee,
      status: CheckStatus.ok,
    ),
    ProviderChip(
      name: 'Phala · GLM klein',
      level: PrivacyLevel.tee,
      status: CheckStatus.pending,
    ),
    ProviderChip(
      name: 'Mistral · Large',
      level: PrivacyLevel.eu,
      status: CheckStatus.failed,
    ),
    ProviderChip(name: 'Claude Haiku', level: PrivacyLevel.standard),
    MetaChip('heute 0,03 €'),
  ],
  'CheckStatusIcon': [
    for (final s in CheckStatus.values)
      Row(
        spacing: WSpace.m,
        children: [
          CheckStatusIcon(s),
          Text(switch (s) {
            CheckStatus.ok => 'Quittung geprüft',
            CheckStatus.pending => 'Quittung ausstehend',
            CheckStatus.failed => 'Prüfung fehlgeschlagen',
            CheckStatus.info => 'Nur protokolliert',
          }, style: WText.body),
        ],
      ),
  ],
  'ToolChip': const [
    ToolChip('weather__marine_forecast'),
    ToolChip('obsidian__append_daily_note', status: CheckStatus.pending),
    ToolChip('spotify__play', status: CheckStatus.failed),
  ],
  'ToolResultCard': const [
    ToolResultCard(
      title: 'Termin angelegt',
      detail: 'Tauchen · Di 13.10. · 10:00–11:00 · Privat',
      toolName: 'calendar__create_event',
      icon: WIcons.calendar,
      onUndo: _noop,
      undoRemaining: Duration(seconds: 8),
    ),
    ToolResultCard(
      title: 'Notiz ergänzt',
      detail: 'Tagesnotiz 12.10. · Abschnitt „Tauchen“',
      toolName: 'obsidian__append_daily_note',
      icon: WIcons.note,
      onUndo: _noop,
      undoRemaining: Duration.zero,
    ),
    ToolResultCard(
      title: 'Termin angelegt',
      detail: 'Tauchen · Di 13.10. · 10:00–11:00 · Privat',
      toolName: 'calendar__create_event',
      icon: WIcons.calendar,
      undone: true,
    ),
  ],
  'ConfirmationCard': const [
    ConfirmationCard(
      title: 'Termin löschen?',
      subject: 'Zahnarzt Dr. Weber',
      detail: 'Do 15.10. · 08:30–09:15 · Kalender Familie',
      toolName: 'calendar__delete_event',
      risk: RiskLevel.external,
      onYes: _noop,
      onNo: _noop,
      yesLabel: 'Ja, löschen',
      noLabel: 'Nein, behalten',
    ),
    ConfirmationCard(
      title: 'SMS an Anna senden?',
      detail: '„Bin in 10 Minuten da.“',
      toolName: 'sms__send',
      risk: RiskLevel.external,
      onYes: _noop,
      onNo: _noop,
    ),
  ],
  'Verlauf': [
    Text('Heute · 08:12', style: WText.mono, textAlign: TextAlign.center),
    const UserBubble('Wie wird das Meer morgen früh?'),
    const AssistantText(
      'Ruhig: 0,4 m Welle, Dünung aus Südwest, Wasser 19 °C.',
      linkLabel: 'Details',
      onLinkTap: _noop,
    ),
    const EscalationDivider('an Claude Sonnet übergeben'),
    const AssistantText(
      'Erledigt. Tauchen steht morgen um 10 Uhr in deinem privaten Kalender.',
      large: true,
    ),
  ],
  'IntegrationTile': [
    const SectionCard(
      children: [
        IntegrationTile(
          name: 'Kalender',
          icon: WIcons.calendar,
          status: IntegrationStatus.active,
          detail: '6 Tools',
          onToggle: _toggle,
        ),
        IntegrationTile(
          name: 'Wetter und Meer',
          icon: WIcons.waves,
          status: IntegrationStatus.available,
          onToggle: _toggle,
        ),
        IntegrationTile(
          name: 'Kontakte',
          icon: WIcons.person,
          status: IntegrationStatus.available,
          sensitive: true,
          minPrivacy: PrivacyLevel.tee,
          onToggle: _toggle,
        ),
        IntegrationTile(
          name: 'Bring! Einkaufsliste',
          icon: WIcons.cart,
          status: IntegrationStatus.setupRequired,
          detail: 'Login fehlt',
          onAction: _noop,
        ),
        IntegrationTile(
          name: 'Spotify',
          icon: WIcons.music,
          status: IntegrationStatus.error,
          detail: 'Token abgelaufen · pausiert',
          onAction: _noop,
        ),
        IntegrationTile(
          name: 'Todoist',
          icon: WIcons.task,
          status: IntegrationStatus.unavailable,
          detail: 'App nicht installiert',
          onStore: _noop,
        ),
      ],
    ),
  ],
  'RuleTile': const [
    RuleTile(
      name: 'Starkes Modell',
      condition: 'prefix "Claude" | "Fable"',
      target: 'Opus',
      active: true,
      onTap: _noop,
    ),
    RuleTile(
      name: 'Privat',
      condition: 'keyword "privat"',
      target: 'Phala GLM',
      targetLevel: PrivacyLevel.tee,
      onTap: _noop,
    ),
    RuleTile(
      name: 'Offline',
      condition: 'network = none',
      target: 'Ollama Homeserver',
      targetLevel: PrivacyLevel.local,
      onTap: _noop,
    ),
    RuleTile(
      name: 'Notizen umschreiben',
      condition: 'needsTool obsidian.edit',
      target: 'Sonnet',
      onTap: _noop,
    ),
    RuleTile(
      name: 'Default',
      condition: 'immer',
      target: 'Phala GLM klein',
      targetLevel: PrivacyLevel.tee,
      isDefault: true,
      onTap: _noop,
    ),
  ],
  'SectionCard': [
    SectionCard(
      title: 'Standardziel',
      dividers: false,
      padding: EdgeInsets.all(WSpace.m14),
      spacing: WSpace.xs6,
      children: [Text('GLM klein', style: WText.mono)],
    ),
  ],
  'Sheet': const [
    SheetDragHandle(),
    SheetHeader(
      trailing: ProviderChip(
        name: 'Phala · GLM klein',
        level: PrivacyLevel.tee,
        status: CheckStatus.ok,
      ),
    ),
    VoiceHint('Sag einfach „ja“ oder „nein“'),
    VoiceHint('Hört noch 5 s zu · „Stopp“ beendet', dot: false),
  ],
  'Icon-Buttons': [
    Wrap(
      spacing: WSpace.l,
      runSpacing: WSpace.l,
      children: [
        WIconButton(
          icon: WIcons.settings,
          tooltip: 'Einstellungen',
          onPressed: _noop,
        ),
        WIconButton(
          icon: WIcons.back,
          tooltip: 'Zurück',
          onPressed: _noop,
          iconSize: WSize.iconSmall,
        ),
        WIconButton(
          icon: WIcons.keyboard,
          tooltip: 'Texteingabe',
          onPressed: _noop,
          shape: WIconButtonShape.round,
        ),
        WIconButton(
          icon: WIcons.close,
          tooltip: 'Beenden',
          onPressed: _noop,
          shape: WIconButtonShape.round,
          iconSize: WSize.iconSmall,
        ),
        const WSwitch(value: true, onChanged: _toggle, semanticLabel: 'An'),
        const WSwitch(value: false, onChanged: _toggle, semanticLabel: 'Aus'),
      ],
    ),
  ],
};

/// Ein Abschnitt der Galerie (Titel + Bausteine untereinander).
class GallerySection extends StatelessWidget {
  /// Erstellt einen Abschnitt.
  const GallerySection({super.key, required this.title, required this.items});

  /// Titel.
  final String title;

  /// Bausteine.
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WSpace.m,
      children: [
        Text(title, style: WText.sectionLabel),
        for (final w in items)
          Align(alignment: AlignmentDirectional.centerStart, child: w),
      ],
    );
  }
}

/// Debug-Galerie mit allen Bausteinen und den Screen-Nachbauten.
class DesignGallery extends StatelessWidget {
  /// Erstellt die Galerie.
  const DesignGallery({super.key});

  static final _screens = <String, WidgetBuilder>{
    'Hauptbildschirm': (_) => const MainScreenSample(),
    'Bestätigung': (_) => const ConfirmationSheetSample(),
    'Integrationen': (_) => const IntegrationsSample(),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(WSpace.screen),
          children: [
            Text('Design-System', style: WText.screenTitle),
            const SizedBox(height: WSpace.xl),
            for (final e in gallerySections.entries) ...[
              GallerySection(title: e.key, items: e.value),
              const SizedBox(height: WSpace.xxl),
            ],
            GallerySection(
              title: 'Screens',
              items: [
                for (final e in _screens.entries)
                  OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context)
                            .push(MaterialPageRoute<void>(builder: e.value)),
                    child: Text(e.key),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
