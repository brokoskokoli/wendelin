/// Test support for code built on `wendelin_providers`: everything from
/// `fakes.dart` plus the contract suite `attestationCryptoContract`.
///
/// Depends on `package:test`; import it only from tests.
library;

export 'fakes.dart';
export 'src/tee/attestation_crypto_contract.dart';
export 'src/tee/near/near_crypto_contract.dart';
export 'src/tee/tinfoil/ehbp_crypto_contract.dart';
