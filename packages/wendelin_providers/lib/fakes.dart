/// Fakes for code built on `wendelin_providers`: [FakeAttestationCrypto]
/// and [FakeGpuAttestationVerifier] for the TEE attestation. Does not depend on `package:test`.
library;

export 'src/tee/fake_attestation_crypto.dart';
export 'src/tee/fake_gpu_verifier.dart';
