import '../messages/content_block.dart';

/// Where the foreign (untrusted) content of a conversation came from
/// (WP201, ADR 0023). Fail-closed: anything that cannot be assigned safely
/// is [UnknownOrigin].
///
/// Lattice used by [merge]: `none` is the neutral element, equal servers stay
/// that server, everything else (two different servers, or any unknown part)
/// collapses to [UnknownOrigin], which absorbs everything.
sealed class ContentOrigin {
  const ContentOrigin();

  /// No foreign content seen so far.
  static const ContentOrigin none = NoOrigin();

  /// Foreign content of unknown or mixed origin (web, mail, HTTP tools,
  /// provider blocks, several servers, no safe assignment).
  static const ContentOrigin unknown = UnknownOrigin();

  /// Foreign content that came only from the MCP server [serverId] (the
  /// stable `McpServerConfig.id`, never the display name or the slug).
  const factory ContentOrigin.server(String serverId) = ServerOrigin;

  /// Combines the origin of everything seen so far with [other]:
  /// `none + X = X`, `X + X = X`, `X + Y = unknown`, `* + unknown = unknown`.
  ContentOrigin merge(ContentOrigin other) => switch ((this, other)) {
    (NoOrigin(), final o) => o,
    (final o, NoOrigin()) => o,
    (UnknownOrigin(), _) || (_, UnknownOrigin()) => unknown,
    (ServerOrigin(serverId: final a), ServerOrigin(serverId: final b))
        when a == b =>
      this,
    _ => unknown,
  };
}

/// No foreign content.
final class NoOrigin extends ContentOrigin {
  /// Creates the value (use [ContentOrigin.none]).
  const NoOrigin();

  @override
  bool operator ==(Object other) => other is NoOrigin;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'ContentOrigin.none';
}

/// Foreign content of unknown or mixed origin.
final class UnknownOrigin extends ContentOrigin {
  /// Creates the value (use [ContentOrigin.unknown]).
  const UnknownOrigin();

  @override
  bool operator ==(Object other) => other is UnknownOrigin;

  @override
  int get hashCode => 1;

  @override
  String toString() => 'ContentOrigin.unknown';
}

/// Foreign content of exactly one MCP server.
final class ServerOrigin extends ContentOrigin {
  /// Creates the value for [serverId].
  const ServerOrigin(this.serverId);

  /// Stable id of the server.
  final String serverId;

  @override
  bool operator ==(Object other) =>
      other is ServerOrigin && other.serverId == serverId;

  @override
  int get hashCode => Object.hash(2, serverId);

  @override
  String toString() => 'ContentOrigin.server($serverId)';
}

/// Tools that name where their (foreign) results come from. A tool without
/// this interface counts as [ContentOrigin.unknown] (fail-closed). The same
/// value also marks the tool as belonging to that server: after foreign
/// content of server X only a tool whose [contentOrigin] is X skips the
/// minimum confirmation.
abstract interface class ContentOriginAware {
  /// Origin of this tool's results; for an MCP tool the server's stable id,
  /// never the tool or display name.
  ContentOrigin get contentOrigin;
}

/// Tools whose origin depends on one result (meta tool `tools__search`,
/// which repeats descriptions of other tools). Takes precedence over
/// [ContentOriginAware]. Fail-closed: unreadable content answers
/// [ContentOrigin.unknown].
abstract interface class ResultOriginAware {
  /// Origin of the successful result [content].
  ContentOrigin resultOrigin(List<ContentBlock> content);
}

/// Origin of the results of [tool] (fail-closed: [ContentOrigin.unknown]
/// without [ContentOriginAware]).
ContentOrigin contentOriginOf(Object tool) =>
    tool is ContentOriginAware ? tool.contentOrigin : ContentOrigin.unknown;
