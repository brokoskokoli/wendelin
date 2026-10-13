import 'dart:io';

import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

void main() {
  vaultPortContract(() {
    final port = FakeVaultPort();
    return (
      port: port,
      reopen: () => FakeVaultPort(files: port.files),
      dispose: null,
    );
  }, name: 'FakeVaultPort');

  vaultPortContract(() {
    final dir = Directory.systemTemp.createTempSync('vault_contract');
    return (
      port: FileSystemVaultPort(dir),
      reopen: () => FileSystemVaultPort(dir),
      dispose: () => dir.deleteSync(recursive: true),
    );
  }, name: 'FileSystemVaultPort');

  noteIndexPortContract(FakeNoteIndex.new, name: 'FakeNoteIndex');
}
