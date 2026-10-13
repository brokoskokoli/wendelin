/// Built-in Wendelin integrations on top of device ports: calendar,
/// clipboard, alarms, memory, web, lists and Obsidian.
///
/// Device access goes only through the ports ([CalendarPort],
/// [ClipboardPort], [AlarmPort], [MemoryStorePort], [ListFilePort],
/// [VaultPort], [NoteIndexPort]); the app implements
/// them. Fakes are in `package:wendelin_integrations/fakes.dart`, contract
/// suites in `package:wendelin_integrations/testing.dart`.
library;

import 'src/alarms/alarms.dart';
import 'src/calendar/calendar_port.dart';
import 'src/clipboard/clipboard.dart';
import 'src/lists/lists.dart';
import 'src/memory/memory.dart';
import 'src/obsidian/ports.dart';

export 'src/alarms/alarms.dart';
export 'src/calendar/calendar_integration.dart';
export 'src/calendar/calendar_port.dart';
export 'src/calendar/calendar_tools.dart';
export 'src/calendar/free_slots.dart';
export 'src/clipboard/clipboard.dart';
export 'src/common/base_tool.dart' show IntegrationTool;
export 'src/common/port_exception.dart';
export 'src/common/time.dart' show LocalDate, timeZoneLocation;
export 'src/common/tool_args.dart' show InvalidArgumentsException, ToolArgs;
export 'src/lists/lists.dart'
    show
        AddItemsTool,
        ClearCompletedTool,
        CompleteItemTool,
        GetItemsTool,
        ListDefinition,
        ListFilePort,
        ListListsTool,
        ListsIntegration,
        RemoveItemTool,
        listDataNotice;
export 'src/memory/memory.dart';
export 'src/obsidian/daily_notes.dart'
    show DailyNoteSettings, fillTemplate, formatMomentDate;
export 'src/obsidian/file_system_vault_port.dart';
export 'src/obsidian/note_indexer.dart';
export 'src/obsidian/obsidian_integration.dart'
    show ObsidianEnv, ObsidianIntegration, ObsidianSettings, OpenUri;
export 'src/obsidian/obsidian_tools.dart'
    show
        AppendDailyNoteTool,
        AppendToNoteTool,
        CreateNoteTool,
        ListFolderTool,
        OpenNoteTool,
        ReadNoteTool,
        ReplaceSectionTool,
        SearchNotesTool,
        maxSectionLines,
        maxWriteChars,
        noteDataNotice;
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
