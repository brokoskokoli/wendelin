import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../design/design.dart';
import 'wizard_back.dart';

/// Page frame of the settings: back button, title, optional intro, content.
class SettingsPage extends StatelessWidget {
  /// Creates the frame.
  const SettingsPage({
    super.key,
    required this.title,
    required this.children,
    this.intro,
    this.showBack = true,
    this.centered = false,
  });

  /// Page title.
  final String title;

  /// Hint under the title.
  final String? intro;

  /// Content below the title.
  final List<Widget> children;

  /// Shows the back button (off on the first onboarding step).
  final bool showBack;

  /// Centres intro and content vertically below the title while they fit
  /// on the screen; longer content scrolls from the top (onboarding).
  final bool centered;

  static const _padding = EdgeInsets.fromLTRB(
    WSpace.screen,
    WSpace.screenTop - WSize.tapTargetInset,
    WSpace.screen,
    WSpace.xl24,
  );

  @override
  Widget build(BuildContext context) {
    final header = Row(
      spacing: WSpace.m,
      children: [
        if (showBack)
          WIconButton(
            icon: WIcons.back,
            tooltip: context.l10n.back,
            onPressed: () => Navigator.of(context).maybePop(),
            iconSize: WSize.iconSmall,
          ),
        Expanded(child: Text(title, style: WText.screenTitle)),
      ],
    );
    final content = [
      if (intro != null) ...[
        InfoBox(intro!),
        const SizedBox(height: WSpace.l18),
      ],
      for (final (i, child) in children.indexed) ...[
        if (i > 0) const SizedBox(height: WSpace.l18),
        child,
      ],
    ];
    const gap = SizedBox(height: WSpace.l18 - WSize.tapTargetInset);
    final Widget page = centered
        ? _centered(header, gap, content)
        : Scaffold(
            body: ListView(
              padding: _padding,
              children: [header, gap, ...content],
            ),
          );
    // While the setup wizard is open, back leads to it from here, also
    // from sub pages (WP174).
    final toWizard = WizardBackScope.leadsToWizard(context);
    return PopScope(
      canPop: !toWizard,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && toWizard) WizardBackScope.backToWizard(context);
      },
      child: page,
    );
  }

  Widget _centered(Widget header, Widget gap, List<Widget> content) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: _padding.copyWith(bottom: 0),
            sliver: SliverToBoxAdapter(child: Column(children: [header, gap])),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: _padding.copyWith(top: 0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: content,
              ),
            ),
          ),
        ],
      ),
    );
  }
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
      Padding(
        padding: const EdgeInsets.only(top: WSpace.xs),
        child: Text(title, style: WText.sectionTitle),
      ),
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
  String? yes,
  String? no,
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
            child: Text(no ?? context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(yes ?? context.l10n.yes),
          ),
        ],
      ),
    ) ??
    false;

/// Short hint at the bottom of the screen.
void showHint(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
