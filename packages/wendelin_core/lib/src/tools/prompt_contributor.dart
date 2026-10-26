import '../safety/security_level.dart';

/// Optional capability of a `Tool` (WP135 A): the tool adds a section to the
/// system prompt of a request, e.g. the approved smart-home devices, so the
/// model need not call a listing tool first.
///
/// The section is data that depends on the tool being offered to the current
/// target: the agent only puts it into the prompt of a model call whose
/// catalog contains the tool (privacy level per target, K10). A tool must
/// treat everything it puts into the text as untrusted data (shorten it,
/// one line per entry) and never include what its own tools protect.
abstract interface class PromptContributor {
  /// The prompt section for a request with [requestText], or `null` for
  /// none. Never throws: a failure means no section.
  ///
  /// [access] is the lock state of the request: while locked, the section
  /// names only what a locked call may do (WP154 L2) and points to no
  /// listing tool.
  Future<String?> promptSection(
    String requestText, {
    AccessContext access = AccessContext.unlocked,
  });
}
