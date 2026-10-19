import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/common.dart' show ReconnectFailure;

import '../../platform/platform_ports.dart';
import '../app_requirements.dart';

/// Registry error text of a paused integration; the UI words it per
/// service in the app language (the model never sees registry errors).
const pausedError = 'paused';

/// What an integration needs to be built.
final class IntegrationDeps {
  /// Creates the dependencies.
  const IntegrationDeps({
    required this.ports,
    required this.device,
    required this.httpClient,
    this.reportError,
    this.clearError,
    this.extras = const {},
  });

  /// Device ports (real or demo).
  final PlatformPorts ports;

  /// Locale and time zone.
  final DeviceInfo device;

  /// Shared HTTP client (web fetch).
  final http.Client httpClient;

  /// Puts the integration `id` into the error state (tools paused).
  final void Function(String id, String message)? reportError;

  /// Clears the error state of the integration `id`.
  final void Function(String id)? clearError;

  /// What the specs prepared via [IntegrationSpec.prepare], by spec id.
  final Map<String, Object?> extras;

  /// The prepared value of the spec [id], `null` if there is none (or it is `null`).
  ///
  /// Throws a [StateError] if there is a value of another type than [T].
  T? extra<T>(String id) {
    return switch (extras[id]) {
      null => null,
      final T value => value,
      final other => throw StateError(
        "Integration '$id': prepared value is "
        '${other.runtimeType}, expected $T.',
      ),
    };
  }
}

/// „Erneut versuchen“ of an integration in the error state (the tile shows
/// the localized `retry` label): [run] returns `null` on success or the
/// failure, which the UI words in the app language.
typedef IntegrationRetry = ({
  Future<ReconnectFailure?> Function(Integration integration) run,
});

/// Registration of one integration in the app: how to build it, how to
/// ask for its permission when the user enables it, and what to do when a
/// session ends.
///
/// This is the extension point for further integrations: one file under
/// `integrations/`, one line in `integrations/registry.dart` (and a port in
/// [PlatformPorts] if it needs device access). Registry, activation, session end and the
/// settings list pick it up from there. Integrations that use another app
/// name it in [requiredApp] (and its package in `<queries>`). User-defined
/// integrations (MCP, HTTP tools) come from a `UserIntegrationSource`
/// instead (ADR 0012).
final class IntegrationSpec {
  /// Creates a spec.
  const IntegrationSpec({
    required this.id,
    required this.create,
    this.requestPermission,
    this.onSessionEnd,
    this.isSupported,
    this.permissionRationale,
    this.requiredApp,
    this.retry,
    this.prepare,
    this.allowedWhileLocked = false,
  });

  /// Integration id (must match `Integration.id`).
  final String id;

  /// Builds the integration.
  final Integration Function(IntegrationDeps deps) create;

  /// Requests the OS permission when the user enables the integration;
  /// `null` if none is needed. Returns whether it was granted.
  final Future<bool> Function(IntegrationDeps deps)? requestPermission;

  /// Called with the built integration when a session ends.
  final void Function(Integration integration)? onSessionEnd;

  /// Explanation shown before [requestPermission] asks the OS.
  final String? permissionRationale;

  /// Whether the integration can be built with [IntegrationDeps] (e.g. its
  /// port exists); `null` = always.
  final bool Function(IntegrationDeps deps)? isSupported;

  /// The app the integration uses, if any: without a needed app it is
  /// „nicht verfügbar“, an optional one only adds a hint (WP25).
  final AppRequirement? requiredApp;

  /// Action of the tile in the error state instead of „Neu anmelden“
  /// (gets the unwrapped integration).
  final IntegrationRetry? retry;

  /// Reads the providers only this integration depends on (e.g. a search
  /// service). Runs inside `integrationDepsProvider`, so a change rebuilds
  /// the integrations; the result is [IntegrationDeps.extra].
  final Object? Function(Ref ref)? prepare;

  /// Whether the tools may run while the device is locked, without
  /// unlocking first (harmless own-state actions such as the flashlight).
  /// Read by `lockedCommandRunnerProvider` (WP53): only tools of such
  /// integrations run from a locally recognized command while locked.
  final bool allowedWhileLocked;
}
