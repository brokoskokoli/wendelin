import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// HTTP client for MCP servers: pooled keep-alive sockets are closed after
/// [idleTimeout] (dart:io keeps them 15 s), so a server restart is noticed
/// sooner. The ordinary rules (system trust store, URL checks in the client)
/// stay unchanged.
http.Client newMcpHttpClient({
  Duration idleTimeout = const Duration(seconds: 2),
}) => IOClient(HttpClient()..idleTimeout = idleTimeout);
