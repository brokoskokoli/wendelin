import 'package:flutter/material.dart';

import '../design/design.dart';

/// Page frame of the settings: back button, title, optional intro, content.
class SettingsPage extends StatelessWidget {
  /// Creates the frame.
  const SettingsPage({
    super.key,
    required this.title,
    required this.children,
    this.intro,
    this.showBack = true,
  });

  /// Page title.
  final String title;

  /// Hint under the title.
  final String? intro;

  /// Content below the title.
  final List<Widget> children;

  /// Shows the back button (off in the onboarding).
  final bool showBack;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        WSpace.screen,
        WSpace.screenTop - WSize.tapTargetInset,
        WSpace.screen,
        WSpace.xl24,
      ),
      children: [
        Row(
          spacing: WSpace.m,
          children: [
            if (showBack)
              WIconButton(
                icon: WIcons.back,
                tooltip: 'Zurück',
                onPressed: () => Navigator.of(context).maybePop(),
                iconSize: WSize.iconSmall,
              ),
            Expanded(child: Text(title, style: WText.screenTitle)),
          ],
        ),
        const SizedBox(height: WSpace.l18 - WSize.tapTargetInset),
        if (intro != null) ...[
          Text(intro!, style: WText.intro),
          const SizedBox(height: WSpace.l18),
        ],
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const SizedBox(height: WSpace.l18),
          child,
        ],
      ],
    ),
  );
}

/// Tappable row in a [SectionCard]: title, optional detail, optional
/// trailing widget.
class SettingsRow extends StatelessWidget {
  /// Creates a row.
  const SettingsRow({
    super.key,
    required this.title,
    this.detail,
    this.onTap,
    this.trailing,
    this.mono = false,
  });

  /// Title.
  final String title;

  /// Second line.
  final String? detail;

  /// Action; `null` = not tappable.
  final VoidCallback? onTap;

  /// Widget at the end (switch, chip, button).
  final Widget? trailing;

  /// Title in mono (tool names).
  final bool mono;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: WSize.listRow),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WSpace.l,
          vertical: WSpace.m,
        ),
        child: Row(
          spacing: WSpace.m,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: WSpace.xxs,
                children: [
                  Text(title, style: mono ? WText.mono : WText.label),
                  if (detail != null) Text(detail!, style: WText.detail),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    ),
  );
}

/// Section with a small heading above a [SectionCard].
class SettingsSection extends StatelessWidget {
  /// Creates a section.
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  /// Heading.
  final String title;

  /// Rows.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: WSpace.s,
    children: [
      Text(title, style: WText.sectionLabel),
      SectionCard(children: children),
    ],
  );
}

/// Large outlined button for actions below a list („+ Provider“).
class WideButton extends StatelessWidget {
  /// Creates the button.
  const WideButton(this.label, {super.key, required this.onPressed});

  /// Label.
  final String label;

  /// Action.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(WSize.buttonHeight),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WRadius.buttonLarge),
      ),
    ),
    child: Text(label),
  );
}

/// Primary button across the width („Speichern“).
class PrimaryButton extends StatelessWidget {
  /// Creates the button.
  const PrimaryButton(this.label, {super.key, required this.onPressed});

  /// Label.
  final String label;

  /// Action; `null` disables it.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(WSize.buttonHeight),
    ),
    child: Text(label),
  );
}

/// Asks a yes/no question; returns `true` for [yes].
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String yes = 'Ja',
  String no = 'Abbrechen',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: WColors.surface,
        title: Text(title, style: WText.label),
        content: Text(message, style: WText.intro),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(no),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(yes),
          ),
        ],
      ),
    ) ??
    false;

/// Short hint at the bottom of the screen.
void showHint(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
