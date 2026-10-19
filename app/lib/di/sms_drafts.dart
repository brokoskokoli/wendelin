import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_integrations/contacts.dart';

/// Texts the user changed in the SMS preview. Shared by the preview (writes)
/// and the `sms__compose` tool (reads when confirmed), so the text that was
/// confirmed is the text that is sent. Only the UI writes here.
final smsDraftEditsProvider = Provider<SmsDraftEdits>((ref) => SmsDraftEdits());
