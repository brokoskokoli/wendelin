// Selbsttests der Leitplanken (WP109) und der Prüfwerkzeuge, gebündelt für
// tool/self_test.dart (hält dessen Größe).
import 'channel_self_test.dart';
import 'ci_self_test.dart';
import 'claude_hooks_self_test.dart';
import 'cleanup_self_test.dart';
import 'doc_check_self_test.dart';
import 'git_guards_self_test.dart';
import 'ratchet_self_test.dart';
import 'self_check.dart';

Future<void> guardChecks(SelfCheck t) async {
  channelChecks(t);
  docCheckChecks(t);
  kotlinUnitChecks(t);
  kotlinReportsClearChecks(t);
  ratchetChecks(t);
  gitGuardsChecks(t);
  cleanupChecks(t);
  await claudeHooksChecks(t);
  ciChecks(t);
}
