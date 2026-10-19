/// Test support for the integration ports: everything from `fakes.dart`
/// plus the contract suites every port implementation must pass
/// (`calendarPortContract`, `clipboardPortContract`, `alarmPortContract`,
/// `memoryStoreContract`, `webSearchBackendContract`, `listFilePortContract`,
/// `vaultPortContract`, `noteIndexPortContract`, `bringApiContract`, `haApiContract`,
/// `httpToolSecretsContract`, `appPresencePortContract`, `torchPortContract`,
/// `mediaControlPortContract`).
///
/// Depends on `package:test`; import it only from tests.
library;

export 'fakes.dart';
export 'testing/alarm_port_contract.dart';
export 'testing/app_presence_port_contract.dart';
export 'testing/bring_api_contract.dart';
export 'testing/calendar_port_contract.dart';
export 'testing/clipboard_port_contract.dart';
export 'testing/ha_api_contract.dart';
export 'testing/http_tool_secrets_contract.dart';
export 'testing/list_file_port_contract.dart';
export 'testing/media_control_port_contract.dart';
export 'testing/memory_store_contract.dart';
export 'testing/note_index_port_contract.dart';
export 'testing/torch_port_contract.dart';
export 'testing/vault_port_contract.dart';
export 'testing/weather_service_contract.dart';
export 'testing/web_search_backend_contract.dart';
