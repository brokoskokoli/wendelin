import 'package:wendelin_core/wendelin_core.dart';

import '../common/base_tool.dart';
import '../common/port_exception.dart';
import '../common/tool_args.dart';

/// The camera flash LED used as a flashlight.
///
/// Implementations throw `PortException` with a short German text for
/// „no LED“ (`unsupported`), „camera in use“ (`unavailable`) and thermal
/// shutdown (`unavailable`). Must pass `torchPortContract`.
abstract interface class TorchPort {
  /// Whether the device has a flash LED that can be used as a torch.
  Future<bool> isAvailable();

  /// Whether the torch is currently on (also when switched by the system
  /// tile).
  Future<bool> state();

  /// Switches the torch on or off.
  Future<void> set(bool on);
}

/// Flashlight integration: `flashlight__on`, `flashlight__off`,
/// `flashlight__toggle`.
final class FlashlightIntegration implements Integration {
  /// Creates the integration on [port].
  FlashlightIntegration(this.port);

  /// Device flash LED.
  final TorchPort port;

  @override
  String get id => 'flashlight';

  @override
  String get displayName => 'Taschenlampe';

  @override
  String get iconId => 'flashlight';

  @override
  Set<AppPlatform> get platforms => const {AppPlatform.android};

  /// The torch state is no personal data.
  @override
  bool get sensitive => false;

  /// Always available: a missing LED shows up as a tool error, so the
  /// user gets an explanation instead of silently missing tools.
  @override
  Future<Availability> checkAvailability() async => Availability.yes;

  @override
  List<SetupStep> get setup => const [];

  @override
  Future<SetupState> setupState() async => SetupState();

  @override
  late final List<Tool> tools = List.unmodifiable(<Tool>[
    FlashlightTool(port, name: 'flashlight__on', mode: TorchMode.on),
    FlashlightTool(port, name: 'flashlight__off', mode: TorchMode.off),
    FlashlightTool(port, name: 'flashlight__toggle', mode: TorchMode.toggle),
  ]);
}

/// What a [FlashlightTool] does.
enum TorchMode {
  /// Switch on.
  on,

  /// Switch off.
  off,

  /// Invert the current state.
  toggle,
}

/// `flashlight__on`, `flashlight__off`, `flashlight__toggle` (write, undo
/// restores the previous state). The result holds only the own state.
final class FlashlightTool extends IntegrationTool
    implements
        TrustedContentSource,
        FixedConfirmationTool,
        DefaultLevelTool,
        NoNetworkTarget {
  /// Creates a tool of the given [mode].
  const FlashlightTool(this.port, {required this.name, required this.mode});

  /// Device flash LED.
  final TorchPort port;

  /// What the tool does.
  final TorchMode mode;

  @override
  final String name;

  @override
  String get description => switch (mode) {
    TorchMode.on => 'Turn the flashlight (torch) on.',
    TorchMode.off => 'Turn the flashlight (torch) off.',
    TorchMode.toggle =>
      'Switch the flashlight (torch): on if it is off, off if it is on.',
  };

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{},
    'required': <String>[],
  };

  @override
  RiskLevel get risk => RiskLevel.write;

  /// Standard **A** for `on` and `off` (WP154 L2, the approval list of
  /// K85): the tool only changes the torch of this phone. It reads no
  /// personal data, sends nothing, affects nobody else, needs no permission
  /// prompt and shows its effect at once; the other mode undoes it. That is
  /// what the locked command always ran, so nothing changes without the
  /// user's choice. `toggle` stays C: no spoken command ever reached it
  /// locked. The user may change each tool (A–D).
  @override
  SecurityLevel get defaultLevel =>
      mode == TorchMode.toggle ? SecurityLevel.c : SecurityLevel.a;

  @override
  Set<String> get confirmationKeys => const {'flashlight.on', 'flashlight.off'};

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    if (!await port.isAvailable()) {
      throw const PortException(
        PortErrorKind.unsupported,
        'Dieses Gerät hat keine Taschenlampe (Blitz-LED).',
      );
    }
    final previous = await port.state();
    final target = switch (mode) {
      TorchMode.on => true,
      TorchMode.off => false,
      TorchMode.toggle => !previous,
    };
    if (target != previous) await port.set(target);
    final text = target
        ? 'Die Taschenlampe ist an.'
        : 'Die Taschenlampe ist aus.';
    return ToolOutcome.text(
      previous == target ? '$text (war schon so)' : text,
      summary: target ? 'Taschenlampe an' : 'Taschenlampe aus',
      fixed: ConfirmationSentence(target ? 'flashlight.on' : 'flashlight.off'),
      undo: previous == target
          ? null
          : UndoAction(
              label: previous
                  ? 'Taschenlampe wieder einschalten'
                  : 'Taschenlampe wieder ausschalten',
              run: () => port.set(previous),
            ),
    );
  }

  @override
  String describe(ToolArgs args) => switch (mode) {
    TorchMode.on => 'Taschenlampe einschalten',
    TorchMode.off => 'Taschenlampe ausschalten',
    TorchMode.toggle => 'Taschenlampe umschalten',
  };

  @override
  String get fallbackDescription => describe(const ToolArgs({}));
}
