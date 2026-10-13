import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../common/port_exception.dart';
import 'fetch_guard.dart';
import 'html_text.dart';
import 'web_search_backend.dart' show orCancel;

/// A fetched page as text.
@immutable
final class FetchedPage {
  /// Creates a fetched page.
  const FetchedPage({
    required this.url,
    required this.text,
    required this.contentType,
    this.title,
    this.truncated = false,
  });

  /// Final URL after redirects.
  final Uri url;

  /// Page title (HTML only).
  final String? title;

  /// Plain text (HTML converted).
  final String text;

  /// MIME type without parameters, e.g. `text/html`.
  final String contentType;

  /// Whether the body was cut at the size limit.
  final bool truncated;
}

/// Fetches web pages as text with guard rails:
///
/// - only `http`/`https`; no local or private targets (loopback, 10.x,
///   172.16–31.x, 192.168.x, link-local, CGNAT, IPv6 ULA …) unless the host
///   is in [allowedHosts]; checked again for every redirect hop;
/// - at most [maxBytes] of body are read (the rest is dropped, the page is
///   marked as truncated);
/// - only text content (HTML, plain text, JSON, XML); HTML becomes text.
///
/// Limitation: the address check resolves the host itself; the HTTP client
/// resolves again (DNS rebinding with very short TTLs is not fully
/// prevented).
final class WebFetcher {
  /// Creates a fetcher. [resolve] defaults to [InternetAddress.lookup].
  WebFetcher({
    required this._client,
    Set<String> allowedHosts = const {},
    this.maxBytes = 2 * 1024 * 1024,
    this.maxRedirects = 5,
    this.timeout = const Duration(seconds: 20),
    HostResolver? resolve,
  }) : allowedHosts = {for (final h in allowedHosts) h.toLowerCase()},
       _resolve = resolve ?? InternetAddress.lookup;

  final http.Client _client;
  final HostResolver _resolve;

  /// Hosts exempt from the private-network block (e.g. the home server).
  final Set<String> allowedHosts;

  /// Size limit of the body in bytes (default 2 MB).
  final int maxBytes;

  /// Most redirects followed.
  final int maxRedirects;

  /// Time limit per request.
  final Duration timeout;

  /// Fetches [url]; throws `PortException` (rejected, unavailable,
  /// unsupported, failed) or [CancelledException].
  Future<FetchedPage> fetch(Uri url, {CancelToken? cancel}) async {
    var current = url;
    for (var hop = 0; ; hop++) {
      cancel?.throwIfCancelled();
      await checkFetchTarget(
        current,
        allowedHosts: allowedHosts,
        resolve: _resolve,
      );
      cancel?.throwIfCancelled();
      final request = http.Request('GET', current)
        ..followRedirects = false
        ..headers['Accept'] =
            'text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.5';
      final http.StreamedResponse response;
      try {
        response = await orCancel(
          _client.send(request).timeout(timeout),
          cancel,
        );
      } on TimeoutException {
        throw const PortException(
          PortErrorKind.unavailable,
          'Seite antwortet nicht (Zeitüberschreitung)',
        );
      } on http.ClientException {
        throw const PortException(
          PortErrorKind.unavailable,
          'Seite ist nicht erreichbar',
        );
      } on SocketException {
        throw const PortException(
          PortErrorKind.unavailable,
          'Seite ist nicht erreichbar',
        );
      }
      final status = response.statusCode;
      if (status >= 300 && status < 400 && status != 304) {
        final location = response.headers['location'];
        await response.stream.listen(null).cancel();
        if (location == null) {
          throw const PortException(
            PortErrorKind.failed,
            'Weiterleitung ohne Ziel',
          );
        }
        if (hop >= maxRedirects) {
          throw const PortException(
            PortErrorKind.failed,
            'Zu viele Weiterleitungen',
          );
        }
        current = current.resolve(location);
        continue;
      }
      if (status < 200 || status >= 300) {
        await response.stream.listen(null).cancel();
        throw PortException(
          status == 404 || status == 410
              ? PortErrorKind.notFound
              : PortErrorKind.unavailable,
          'Seite antwortet mit Status $status',
        );
      }
      return _read(current, response, cancel);
    }
  }

  Future<FetchedPage> _read(
    Uri url,
    http.StreamedResponse response,
    CancelToken? cancel,
  ) async {
    final contentType = response.headers['content-type'] ?? '';
    final mime = contentType.split(';').first.trim().toLowerCase();
    final isHtml = mime == 'text/html' || mime == 'application/xhtml+xml';
    final isText =
        mime.isEmpty ||
        mime.startsWith('text/') ||
        mime == 'application/json' ||
        mime == 'application/xml' ||
        mime.endsWith('+json') ||
        mime.endsWith('+xml');
    if (!isHtml && !isText) {
      await response.stream.listen(null).cancel();
      throw PortException(
        PortErrorKind.unsupported,
        'Inhaltstyp „$mime“ wird nicht unterstützt (nur Text und HTML)',
      );
    }
    final body = await orCancel(_readLimited(response.stream), cancel);
    final charset = RegExp(
      r'charset=([^;\s]+)',
      caseSensitive: false,
    ).firstMatch(contentType)?[1]?.toLowerCase().replaceAll('"', '');
    final decoded = switch (charset) {
      'iso-8859-1' ||
      'latin1' ||
      'windows-1252' ||
      'us-ascii' => latin1.decode(body.bytes),
      _ => utf8.decode(body.bytes, allowMalformed: true),
    };
    final sniffHtml =
        mime.isEmpty && decoded.trimLeft().toLowerCase().startsWith('<');
    if (isHtml || sniffHtml) {
      final page = htmlToText(decoded);
      return FetchedPage(
        url: url,
        title: page.title,
        text: page.text,
        contentType: mime.isEmpty ? 'text/html' : mime,
        truncated: body.truncated,
      );
    }
    return FetchedPage(
      url: url,
      text: decoded,
      contentType: mime.isEmpty ? 'text/plain' : mime,
      truncated: body.truncated,
    );
  }

  Future<({List<int> bytes, bool truncated})> _readLimited(
    Stream<List<int>> stream,
  ) async {
    final bytes = <int>[];
    final done = Completer<bool>();
    late final StreamSubscription<List<int>> sub;
    sub = stream.listen(
      (chunk) {
        final room = maxBytes - bytes.length;
        if (chunk.length > room) {
          bytes.addAll(chunk.take(room));
          unawaited(sub.cancel());
          if (!done.isCompleted) done.complete(true);
        } else {
          bytes.addAll(chunk);
        }
      },
      onError: (Object e) {
        if (!done.isCompleted) {
          done.completeError(
            const PortException(
              PortErrorKind.unavailable,
              'Verbindung abgebrochen',
            ),
          );
        }
      },
      onDone: () {
        if (!done.isCompleted) done.complete(false);
      },
      cancelOnError: true,
    );
    final truncated = await done.future.timeout(
      timeout,
      onTimeout: () {
        unawaited(sub.cancel());
        throw const PortException(
          PortErrorKind.unavailable,
          'Seite antwortet nicht (Zeitüberschreitung)',
        );
      },
    );
    return (bytes: bytes, truncated: truncated);
  }
}
