import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../di/providers.dart';

/// Stores the token usage of an agent call in the local database.
Future<void> recordAgentUsage(
  Ref ref,
  String sessionId,
  UsageReported event,
  String profileId,
  String modelId,
  Usage usage,
) async {
  await ref
      .read(storageProvider)
      .usage
      .record(
        sessionId: sessionId,
        profileId: profileId,
        modelId: modelId,
        usage: usage,
        costMicros: event.costMicros ?? 0,
      );
  ref.invalidate(todayCostProvider);
}
