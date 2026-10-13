import 'package:wendelin_integrations/testing.dart';

import 'bring_server.dart';

void main() {
  bringApiContract(() {
    final api = FakeBringApi();
    return (api: api, expireTokens: api.expireTokens);
  }, name: 'FakeBringApi');

  bringApiContract(() {
    final server = BringServer();
    return (api: server.api(), expireTokens: server.expireTokens);
  }, name: 'HttpBringApi gegen nachgebaute Bring!-API (Fixtures)');
}
