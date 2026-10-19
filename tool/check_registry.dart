// Prüft Registry und Barrel auf Listendisziplin (siehe src/registry_lint.dart).
//   dart run tool/check_registry.dart [--fix]
import 'dart:io';

import 'src/registry_lint.dart';

void main(List<String> args) =>
    exitCode = runRegistryCheck(fix: args.contains('--fix'));
