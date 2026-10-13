import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../platform/saf_list_file_port.dart';
import 'preferences.dart';
import 'providers.dart';

/// File picker for list files (SAF; replaceable in tests).
final documentPickerProvider = Provider<DocumentPicker>(
  (ref) => const DocumentPicker(),
);

/// Ids of the lists whose file grant is gone („Datei neu auswählen“).
final listsWithoutAccessProvider = FutureProvider.autoDispose<Set<String>>(
  (ref) => listsWithoutAccess(
    ref.watch(documentPickerProvider),
    ref.watch(listDefinitionsProvider),
  ),
);

/// Ids of [lists] for which no persisted read/write grant is held. On a
/// platform without SAF nothing can be checked and nothing is reported.
Future<Set<String>> listsWithoutAccess(
  DocumentPicker picker,
  List<ListDefinition> lists,
) async {
  final missing = <String>{};
  for (final list in lists) {
    try {
      if (!await picker.hasAccess(list.target)) missing.add(list.id);
    } on PortException catch (e) {
      if (e.kind != PortErrorKind.unsupported) missing.add(list.id);
    }
  }
  return missing;
}

/// Marks the lists integration as failed while a list file must be picked
/// again, and clears that state once all files are accessible.
void reportListAccess(
  ToolRegistry registry,
  List<ListDefinition> lists,
  Set<String> missing,
) {
  if (!registry.integrations.any((i) => i.id == 'lists')) return;
  if (missing.isEmpty) {
    if (registry.info('lists').error != null) registry.clearError('lists');
    return;
  }
  final names = [
    for (final l in lists)
      if (missing.contains(l.id)) l.name,
  ];
  registry.reportError('lists', 'Datei neu auswählen: ${names.join(', ')}');
}

/// Checks the list files (app start, after editing lists) and updates the
/// integration state.
Future<void> checkListAccess(WidgetRef ref) async {
  final lists = ref.read(listDefinitionsProvider);
  final registry = ref.read(toolRegistryProvider);
  final missing = await listsWithoutAccess(
    ref.read(documentPickerProvider),
    lists,
  );
  reportListAccess(registry, lists, missing);
}
