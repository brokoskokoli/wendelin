/// Obsidian vault integration: ports, note index, read and write tools.
///
/// Entry point of one integration; `wendelin_integrations.dart` re-exports it.
library;

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
