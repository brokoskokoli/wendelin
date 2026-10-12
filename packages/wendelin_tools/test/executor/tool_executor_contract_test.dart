import 'package:wendelin_core/testing.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

void main() {
  // Production configuration (envelope, truncation, default policy).
  toolInvokerContract(
    (catalog) => ToolExecutor(catalog: catalog),
    name: 'ToolExecutor',
  );
}
