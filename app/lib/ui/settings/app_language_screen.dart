import 'dart:async';

import 'package:flutter/material.dart' show ScaffoldMessenger;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/developer_mode.dart';
import '../../di/preferences.dart';
import '../../l10n/l10n.dart';
import '../../voice/dev_archive.dart';
import '../design/design.dart';
import 'dev_archive_section.dart';
import 'settings_page.dart';

/// Choice of the app UI language (WP79): system, Deutsch, English, Français.
/// Independent of the speech languages under „Sprache“.
///
/// WP148: 10 taps on „System“ switch the developer mode on or off (like
/// Android's build number); from the 7th tap a hint counts down.
class AppLanguageScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const AppLanguageScreen({super.key});

  /// Taps on „System“ that switch the developer mode.
  static const developerTaps = 10;

  /// From this tap on the hint counts down.
  static const countdownFrom = 7;

  /// The offered codes in display order.
  static const codes = [uiLanguageSystem, 'de', 'en', 'fr'];

  @override
  ConsumerState<AppLanguageScreen> createState() => _State();
}

class _State extends ConsumerState<AppLanguageScreen> {
  int _taps = 0;

  void _onTap(String code) {
    final current = ref.read(uiLanguageProvider);
    // „System“ again changes nothing (no write, no rebuild of the app).
    if (code != current) {
      unawaited(ref.read(uiLanguageProvider.notifier).set(code));
    }
    if (code != uiLanguageSystem) {
      _taps = 0;
      return;
    }
    _taps++;
    if (_taps >= AppLanguageScreen.developerTaps) {
      _taps = 0;
      final on = !ref.read(developerModeProvider);
      final l = context.l10n;
      if (on) {
        unawaited(ref.read(developerModeProvider.notifier).set(enabled: true));
        _hint(l.developerModeOn);
      } else {
        unawaited(_switchOff());
      }
    } else if (_taps >= AppLanguageScreen.countdownFrom) {
      final l = context.l10n;
      final left = AppLanguageScreen.developerTaps - _taps;
      _hint(
        ref.read(developerModeProvider)
            ? l.developerModeStepsToOff(left)
            : l.developerModeStepsToOn(left),
      );
    }
  }

  // WP155: switching off deletes the short-lived recordings; the wake archive
  // only if the user says so (asked once, and only if there is one).
  Future<void> _switchOff() async {
    final l = context.l10n;
    final stats = await devArchiveStats();
    var deleteArchive = false;
    if (stats.cases > 0 && mounted) {
      deleteArchive = await confirm(
        context,
        title: l.devArchiveOffTitle,
        message: l.devArchiveOffMessage(
          stats.cases,
          devArchiveSizeText(stats.bytes),
        ),
        yes: l.devArchiveDeleteToo,
        no: l.devArchiveKeep,
      );
    }
    await ref
        .read(developerModeProvider.notifier)
        .set(enabled: false, deleteArchive: deleteArchive);
    ref.invalidate(devArchiveStatsProvider);
    if (mounted) _hint(l.developerModeOff);
  }

  // Replaces the last hint at once, so the countdown keeps up with the taps.
  void _hint(String text) {
    ScaffoldMessenger.of(context).clearSnackBars();
    showHint(context, text);
  }

  @override
  Widget build(BuildContext context) {
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
            for (final code in AppLanguageScreen.codes)
              SettingsRow(
                title: names[code]!,
                detail: code == uiLanguageSystem
                    ? l.appLanguageSystemDetail
                    : null,
                onTap: () => _onTap(code),
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
