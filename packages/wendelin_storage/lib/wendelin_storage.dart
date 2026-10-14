/// Wendelin storage: local SQLite database (drift) with repositories for
/// conversations, memory, the note search index, audit log, provider
/// profiles, usage and settings, plus the [SecretStore] interface.
///
/// No drift types appear in this API except the `QueryExecutor` taken by
/// [WendelinStorage]. Fakes: `package:wendelin_storage/fakes.dart`;
/// contract suites: `package:wendelin_storage/testing.dart`.
library;

export 'src/model/attestation_record.dart';
export 'src/model/audit_entry.dart';
export 'src/model/conversation.dart';
export 'src/model/note_search_hit.dart';
export 'src/model/setting_key.dart';
export 'src/model/stored_memory.dart';
export 'src/model/usage_record.dart';
export 'src/redaction.dart'
    show
        looksLikeSecretKey,
        redactSecretValues,
        redactSecrets,
        redactedValue,
        shouldRedactField;
export 'src/repositories/repositories.dart';
export 'src/scoped_secret_store.dart';
export 'src/secret_store.dart';
export 'src/sensitive_content.dart';
export 'src/storage.dart';
