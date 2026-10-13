/// Built-in Wendelin integrations on top of device ports: calendar,
/// clipboard, alarms, memory, web, lists, Obsidian and Bring!, plus
/// user-defined HTTP tools ([HttpToolsIntegration]).
///
/// Device access goes only through the ports ([CalendarPort],
/// [ClipboardPort], [AlarmPort], [MemoryStorePort], [ListFilePort],
/// [VaultPort], [NoteIndexPort], [AppPresencePort], and for Bring!
/// [BringApi] and [BringSecrets]); the app implements
/// them. Fakes are in `package:wendelin_integrations/fakes.dart`, contract
/// suites in `package:wendelin_integrations/testing.dart`.
library;

import 'src/alarms/alarms.dart';
import 'src/bring/bring_api.dart';
import 'src/calendar/calendar_port.dart';
import 'src/clipboard/clipboard.dart';
import 'src/common/app_presence.dart';
import 'src/http_tools/http_tools_integration.dart';
import 'src/lists/lists.dart';
import 'src/memory/memory.dart';
import 'src/obsidian/ports.dart';

export 'src/alarms/alarms.dart';
export 'src/bring/bring_api.dart';
export 'src/bring/bring_integration.dart';
export 'src/bring/bring_session.dart';
export 'src/bring/bring_tools.dart'
    show
        BringAddItemsTool,
        BringCompleteItemTool,
        BringGetItemsTool,
        BringListListsTool,
        BringRemoveItemTool,
        bringDataNotice,
        maxBringText,
        maxRecentShown;
export 'src/bring/http_bring_api.dart';
export 'src/calendar/calendar_integration.dart';
export 'src/calendar/calendar_port.dart';
export 'src/calendar/calendar_read_tools.dart';
export 'src/calendar/calendar_tools.dart'
    show CalendarToolEnv, describeEventSpan;
export 'src/calendar/calendar_write_tools.dart';
export 'src/calendar/free_slots.dart';
export 'src/clipboard/clipboard.dart';
export 'src/common/app_presence.dart';
export 'src/common/base_tool.dart' show IntegrationTool, ellipsize;
export 'src/common/data_envelope.dart';
export 'src/common/net_scope.dart';
export 'src/common/port_exception.dart';
export 'src/common/time.dart' show LocalDate, timeZoneLocation;
export 'src/common/tool_args.dart' show InvalidArgumentsException, ToolArgs;
export 'src/http_tools/http_target.dart';
export 'src/http_tools/http_template.dart'
    show UrlTemplate, expandFormBody, expandHeaders, expandJsonBody;
export 'src/http_tools/http_tool_definition.dart';
export 'src/http_tools/http_tool_runner.dart';
export 'src/http_tools/http_tools_integration.dart';
export 'src/http_tools/http_transport.dart';
export 'src/lists/lists.dart'
    show ListDefinition, ListFilePort, ListsIntegration, listDataNotice;
export 'src/lists/lists_read_tools.dart' show GetItemsTool, ListListsTool;
export 'src/lists/lists_write_tools.dart'
    show AddItemsTool, ClearCompletedTool, CompleteItemTool, RemoveItemTool;
export 'src/memory/memory.dart';
export 'src/obsidian/daily_notes.dart'
    show DailyNoteSettings, fillTemplate, formatMomentDate;
export 'src/obsidian/file_system_vault_port.dart';
export 'src/obsidian/note_indexer.dart';
export 'src/obsidian/obsidian_integration.dart'
    show
        NoteMatchKind,
        NoteResolution,
        ObsidianEnv,
        ObsidianIntegration,
        ObsidianSettings,
        OpenUri;
export 'src/obsidian/obsidian_read_tools.dart'
    show ListFolderTool, OpenNoteTool, ReadNoteTool, SearchNotesTool;
export 'src/obsidian/obsidian_tool_support.dart'
    show confirmationDiffLines, maxSectionLines, maxWriteChars, noteDataNotice;
export 'src/obsidian/obsidian_write_tools.dart'
    show
        AppendDailyNoteTool,
        AppendToNoteTool,
        CreateNoteTool,
        ReplaceSectionTool;
export 'src/obsidian/ports.dart';
export 'src/obsidian/vault_path.dart';
export 'src/web/fetch_guard.dart';
export 'src/web/web_fetcher.dart';
export 'src/web/web_integration.dart';
export 'src/web/web_search_backend.dart'
    show
        BraveSearchBackend,
        SearxngBackend,
        TavilyBackend,
        WebSearchBackend,
        WebSearchResult;
