/// Fakes for code built on `wendelin_providers`: [FakeAttestationCrypto]
/// and [FakeGpuAttestationVerifier] for the TEE attestation. Does not depend on `package:test`.
library;

export 'src/tee/fake_attestation_crypto.dart';
export 'src/tee/fake_e2ee_service.dart';
export 'src/tee/fake_gpu_verifier.dart';
export 'src/tee/fake_sigstore_crypto.dart';
export 'src/tee/fake_snp_crypto.dart';
export 'src/tee/near/fake_near_service.dart';
export 'src/tee/near/near_reference.dart';
