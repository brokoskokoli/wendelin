import 'package:wendelin_core/wendelin_core.dart';

/// Secret reference of the bearer token of the definition [id].
String httpBearerRef(String id) => '$id.bearer';

/// Secret reference of the secret header [header] of the definition [id].
String httpHeaderRef(String id, String header) =>
    '$id.h.${header.toLowerCase()}';

/// The secret references [auth] uses.
Set<String> httpSecretRefs(AuthMethod auth) => switch (auth) {
  ApiKeyAuth(:final secretRef) => {secretRef},
  CustomHeadersAuth(:final secretRefsByHeader) => {
    ...secretRefsByHeader.values,
  },
  _ => const {},
};
