import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Secret value that must never show up outside the secret vault.
const httpCanary = 'kanarienvogel-http-4711';

/// A definition for tests (`https://api.example.org/…`).
HttpToolDefinition testHttpTool({
  String id = 'tool-1',
  String name = 'licht',
  HttpMethod method = HttpMethod.post,
  RiskLevel? risk,
  bool autoRun = false,
  bool sensitive = false,
  AuthMethod? auth,
}) => HttpToolDefinition(
  id: id,
  name: name,
  description: 'Schaltet das Licht',
  method: method,
  urlTemplate: 'https://api.example.org/licht/{raum}',
  inputSchema: const {
    'type': 'object',
    'properties': {
      'raum': {'type': 'string'},
    },
    'required': ['raum'],
  },
  bodyTemplate: method.allowsBody ? const {'an': true} : null,
  auth:
      auth ?? CustomHeadersAuth({'X-Api-Key': httpHeaderRef(id, 'X-Api-Key')}),
  risk: risk,
  autoRun: autoRun,
  sensitive: sensitive,
);
