// PLACEHOLDER of tool/train_wake_word export (WP143 part 1) - do not edit.
//
// Mean `mu` (96 values) of the embedding frames that verifier B subtracts
// per frame before the cosine (WP137, `wake_verifier_b_mu.json`). The values
// below are zeros (= no centering) until the delivery with the real values
// replaces this file; [wakeVerifierBMuIsPlaceholder] keeps the app from
// using verifier B meanwhile.

/// Feature version ([WakeFeatureChain.featureVersion]) `mu` belongs to.
const wakeVerifierBFeatureVersion = 'oww-0.5.1-mel-emb-1';

/// Whether the values are the placeholder (the app does not use B then).
const wakeVerifierBMuIsPlaceholder = true;

/// Base64 of 96 little-endian float32 values.
const wakeVerifierBMuBase64 =
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
