import 'package:flutter/widgets.dart';

/// Tells the settings pages whether the setup wizard (WP174) is still
/// open. As long as it is, back (arrow and system gesture) on every page
/// the wizard opened leads straight back to the wizard, also from sub
/// pages; afterwards navigation is the normal one. Sits above the
/// navigator; without it (plain page tests) nothing changes. Takes effect
/// only on pages built with `SettingsPage`, which reads this scope.
class WizardBackScope extends InheritedWidget {
  /// Creates the scope.
  const WizardBackScope({
    super.key,
    required this.active,
    required super.child,
  });

  /// The wizard is open.
  final bool active;

  /// Whether back on the page of [context] must lead to the wizard: the
  /// wizard is open and the page is not the wizard itself (the first route).
  static bool leadsToWizard(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<WizardBackScope>();
    if (scope == null || !scope.active) return false;
    return ModalRoute.of(context)?.isFirst == false;
  }

  /// Back to the wizard: closes everything above the first route.
  static void backToWizard(BuildContext context) =>
      Navigator.of(context).popUntil((route) => route.isFirst);

  @override
  bool updateShouldNotify(WizardBackScope old) => active != old.active;
}
