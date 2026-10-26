import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import 'agent_providers.dart';
import 'home_assistant.dart' show haIntegrationOf;
import 'integration_providers.dart';
import 'provider_config.dart' show ProviderConfig;

/// The tools the local lock commands run ([lockedToolName] maps a spoken
/// command to one): they are handled without a model. Alone they do not
/// start the model on a locked device, so the standard stays what it was
/// (K85, K92): everything else is refused until a user choice allows more.
const lockedCommandTools = {'flashlight__on', 'flashlight__off'};

/// What a request on a locked device may use (WP154 L2, ADR 0022): the
/// [access] it runs under and the [tools] the policy allows for it. The
/// model gets only these tools, nothing else reaches its prompt (no history,
/// no memory, no section of another tool).
final class LockedScope {
  /// Creates the scope.
  const LockedScope({required this.access, required this.tools});

  /// Lock state and voice (WP157 adds the recognized speaker).
  final AccessContext access;

  /// Names of the tools offered; for a tool that decides per device
  /// (`ha__call`) at least one device is allowed.
  final Set<String> tools;
}

/// The tools of [inner] a locked request may use: [activeSpecs] lists only
/// the [offered] ones. [lookup] still finds every tool, so a call the model
/// invents ends in the policy ("Entsperren nötig"), never in an executed
/// tool or an unknown one.
final class LockedCatalog implements ToolCatalog {
  /// Creates the view; [offered] are the tools to list.
  const LockedCatalog(this.inner, this.offered);

  /// The catalog of the target's privacy level.
  final ToolCatalog inner;

  /// The tools listed to the model.
  final List<Tool> offered;

  @override
  List<ToolSpec> activeSpecs() => [for (final t in offered) t.spec];

  @override
  Tool? lookup(String name) => inner.lookup(name);
}

/// The [LockedScope] of a request in [access]: the tools of the weakest
/// target (privacy filter as usual, K10) that the policy allows locked, the
/// Home Assistant call tool only if a device is allowed. `null` = nothing is
/// allowed (or no provider): the request is refused as before (K92).
typedef LockedScopeOf = Future<LockedScope?> Function(AccessContext access);

/// Computes the [LockedScope].
final lockedScopeProvider = Provider<LockedScopeOf>((ref) {
  return (access) async {
    final ProviderConfig? providers;
    try {
      providers = await ref.read(providerConfigProvider.future);
      await ref.read(toolRegistryReadyProvider.future);
    } on Object {
      return null; // fail-closed: nothing is checked, nothing runs
    }
    if (providers == null) return null;
    final registry = ref.read(toolRegistryProvider);
    final policy = ref.read(riskPolicyProvider);
    final session = ref.read(sessionManagerProvider).currentId ?? '';
    final ha = haIntegrationOf(ref.read(integrationsProvider));
    final names = <String>{};
    for (final tool in registry.activeToolsFor(providers.lowestPrivacy)) {
      if (policy.decide(tool, session, access: access).action !=
          PolicyAction.allow) {
        continue;
      }
      if (tool is LevelPerDeviceTool &&
          (ha == null || !await ha.anyAllowedWhileLocked(access))) {
        continue;
      }
      names.add(tool.name);
    }
    // Only the local commands: no model (as before).
    return names.difference(lockedCommandTools).isEmpty
        ? null
        : LockedScope(access: access, tools: names);
  };
});
