/// Fakes for code built on `wendelin_storage`: [InMemorySecretStore] and
/// [openInMemoryStorage].
///
/// Does **not** depend on `package:test`, so the app may use it in
/// production code (demo mode). Tests import `testing.dart`, which also
/// exports the contract suites.
library;

export 'testing/in_memory_secret_store.dart';
export 'testing/in_memory_storage.dart';
