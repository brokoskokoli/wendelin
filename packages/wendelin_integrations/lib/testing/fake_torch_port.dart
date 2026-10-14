import '../src/common/port_exception.dart';
import '../src/flashlight/flashlight.dart';
import 'fake_failures.dart';

/// In-memory [TorchPort]. With [available] `false` there is no LED: [set]
/// throws `unsupported` like a device without flash.
final class FakeTorchPort with FakeFailures implements TorchPort {
  /// Creates the fake.
  FakeTorchPort({this.available = true, this.on = false});

  /// Whether the device has a flash LED.
  bool available;

  /// Whether the torch is on (can be flipped to simulate the system tile).
  bool on;

  @override
  Future<bool> isAvailable() async {
    enter('isAvailable');
    return available;
  }

  @override
  Future<bool> state() async {
    enter('state');
    return available && on;
  }

  @override
  Future<void> set(bool on) async {
    enter('set');
    if (!available) {
      throw const PortException(
        PortErrorKind.unsupported,
        'Dieses Gerät hat keine Taschenlampe (Blitz-LED).',
      );
    }
    this.on = on;
  }
}
