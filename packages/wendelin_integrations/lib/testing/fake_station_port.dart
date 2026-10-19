import '../src/station/station.dart';
import 'fake_failures.dart';

/// In-memory [StationPort]: counts the starts.
final class FakeStationPort with FakeFailures implements StationPort {
  /// Creates the fake.
  FakeStationPort({this.locked = false});

  /// Whether the device is locked.
  bool locked;

  /// How often [start] was called.
  int starts = 0;

  @override
  Future<bool> isLocked() async {
    enter('isLocked');
    return locked;
  }

  @override
  Future<void> start() async {
    enter('start');
    starts++;
  }
}
