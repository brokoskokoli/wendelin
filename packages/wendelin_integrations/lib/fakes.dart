/// In-memory fakes of the integration ports: [FakeCalendarPort],
/// [FakeClipboardPort], [FakeAlarmPort], [FakeMemoryStore],
/// [FakeWebSearchBackend], [FakeListFilePort], [FakeVaultPort],
/// [FakeNoteIndex], [FakeBringApi], [FakeBringSecrets], [FakeHttpToolSecrets],
/// [FakeAppPresencePort], [FakeTorchPort], [FakeHaApi], [FakeHaSecrets],
/// [FakeHaEntityStore], [FakeHaDiscovery].
///
/// Does **not** depend on `package:test`, so the app may use it in
/// production code (demo mode). Tests import `testing.dart`, which also
/// exports the contract suites.
library;

import 'testing/fake_alarm_port.dart';
import 'testing/fake_app_presence_port.dart';
import 'testing/fake_bring_api.dart';
import 'testing/fake_calendar_port.dart';
import 'testing/fake_clipboard_port.dart';
import 'testing/fake_ha_api.dart';
import 'testing/fake_ha_secrets.dart';
import 'testing/fake_http_tool_secrets.dart';
import 'testing/fake_list_file_port.dart';
import 'testing/fake_memory_store.dart';
import 'testing/fake_note_index.dart';
import 'testing/fake_torch_port.dart';
import 'testing/fake_vault_port.dart';
import 'testing/fake_web_search_backend.dart';

export 'testing/fake_alarm_port.dart';
export 'testing/fake_app_presence_port.dart';
export 'testing/fake_bring_api.dart';
export 'testing/fake_calendar_port.dart';
export 'testing/fake_clipboard_port.dart';
export 'testing/fake_failures.dart';
export 'testing/fake_ha_api.dart';
export 'testing/fake_ha_secrets.dart';
export 'testing/fake_http_tool_secrets.dart';
export 'testing/fake_http_tool_store.dart';
export 'testing/fake_list_file_port.dart';
export 'testing/fake_memory_store.dart';
export 'testing/fake_note_index.dart';
export 'testing/fake_torch_port.dart';
export 'testing/fake_user_integrations.dart';
export 'testing/fake_vault_port.dart';
export 'testing/fake_weather.dart';
export 'testing/fake_web_search_backend.dart';
