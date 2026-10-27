import 'package:flutter/foundation.dart';

/// Reports an error of an agent request to the Flutter error handler.
void reportAgentError(Object error, StackTrace stack) =>
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'wendelin',
        context: ErrorDescription('in der Agent-Anfrage'),
      ),
    );
