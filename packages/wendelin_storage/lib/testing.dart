/// Test support for code built on `wendelin_storage`: everything from
/// `fakes.dart` plus the reusable contract suite `secretStoreContract`.
///
/// Depends on `package:test`; import it only from tests. Production code
/// (e.g. the app's demo mode) imports `package:wendelin_storage/fakes.dart`.
library;

export 'fakes.dart';
export 'testing/secret_store_contract.dart';
