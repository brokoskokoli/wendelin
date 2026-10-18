import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/preferences.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import 'settings_page.dart';

/// Choice of the app UI language (WP79): system, Deutsch, English, Français.
/// Independent of the speech languages under „Sprache“.
class AppLanguageScreen extends ConsumerWidget {
  /// Creates the screen.
  const AppLanguageScreen({super.key});

  /// The offered codes in display order.
  static const codes = [uiLanguageSystem, 'de', 'en', 'fr'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final current = ref.watch(uiLanguageProvider);
    final names = {
      uiLanguageSystem: l.appLanguageSystem,
      'de': l.languageGerman,
      'en': l.languageEnglish,
      'fr': l.languageFrench,
    };
    return SettingsPage(
      title: l.appLanguageTitle,
      intro: l.appLanguageIntro,
      children: [
        SectionCard(
          children: [
            for (final code in codes)
              SettingsRow(
                title: names[code]!,
                detail: code == uiLanguageSystem
                    ? l.appLanguageSystemDetail
                    : null,
                onTap: () =>
                    unawaited(ref.read(uiLanguageProvider.notifier).set(code)),
                trailing: current == code
                    ? CheckStatusIcon(CheckStatus.ok, semanticLabel: l.selected)
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}
