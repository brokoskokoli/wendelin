import 'dart:async';

import 'package:test/test.dart';

import '../src/common/port_exception.dart';
import '../src/flashlight/flashlight.dart';

/// Creates the [TorchPort] under test.
typedef TorchPortFactory = FutureOr<TorchPort> Function();

/// Names of the checks in [torchPortContractChecks].
abstract final class TorchPortChecks {
  /// on then off is reflected by `state`.
  static const roundTrip = 'set(true)/set(false) spiegelt sich in state';

  /// Setting the current state again is harmless.
  static const idempotent = 'gleichen Zustand erneut setzen ist harmlos';

  /// Without LED `set` throws a `PortException`, with LED `state` is false
  /// or true but never throws.
  static const noLed = 'ohne LED: PortException statt Absturz';
}

/// Reusable contract suite for every [TorchPort] implementation; registers
/// one test per entry of [torchPortContractChecks]. The torch is restored
/// to its previous state after each check. On a device without LED only the
/// error path is checked.
void torchPortContract(TorchPortFactory create, {String name = 'TorchPort'}) {
  group('$name erfüllt den TorchPort-Vertrag', () {
    torchPortContractChecks(create).forEach(test);
  });
}

/// The checks of [torchPortContract] by name ([TorchPortChecks]).
Map<String, Future<void> Function()> torchPortContractChecks(
  TorchPortFactory create,
) {
  Future<void> withLed(Future<void> Function(TorchPort p) body) async {
    final port = await create();
    if (!await port.isAvailable()) {
      await expectLater(port.set(true), throwsA(isA<PortException>()));
      return;
    }
    final saved = await port.state();
    try {
      await body(port);
    } finally {
      await port.set(saved);
    }
  }

  return {
    TorchPortChecks.roundTrip: () => withLed((p) async {
      await p.set(true);
      expect(await p.state(), isTrue);
      await p.set(false);
      expect(await p.state(), isFalse);
    }),
    TorchPortChecks.idempotent: () => withLed((p) async {
      await p.set(true);
      await p.set(true);
      expect(await p.state(), isTrue);
      await p.set(false);
      await p.set(false);
      expect(await p.state(), isFalse);
    }),
    TorchPortChecks.noLed: () async {
      final p = await create();
      if (await p.isAvailable()) {
        expect(await p.state(), isA<bool>());
      } else {
        expect(await p.state(), isFalse);
        await expectLater(p.set(true), throwsA(isA<PortException>()));
      }
    },
  };
}
