import 'package:test/test.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

typedef _Case = ({String template, Map<String, Object?> args, String? url});

void main() {
  group('URL-Vorlage: Ausdehnung (Tabelle)', () {
    // url == null: InvalidArgumentsException erwartet.
    final cases = <String, _Case>{
      'fester Pfad ohne Platzhalter': (
        template: 'https://ha.example.org/api/states',
        args: {},
        url: 'https://ha.example.org/api/states',
      ),
      'Pfadwert als Segment': (
        template: 'https://ha.example.org/api/states/{entity}',
        args: {'entity': 'light.kitchen'},
        url: 'https://ha.example.org/api/states/light.kitchen',
      ),
      'Leerzeichen im Pfad kodiert': (
        template: 'https://h.example.org/notes/{title}',
        args: {'title': 'Mein Tag'},
        url: 'https://h.example.org/notes/Mein%20Tag',
      ),
      'Unicode im Pfad (UTF-8 kodiert)': (
        template: 'https://h.example.org/n/{t}',
        args: {'t': 'Grüße 😀'},
        url: 'https://h.example.org/n/Gr%C3%BC%C3%9Fe%20%F0%9F%98%80',
      ),
      '? und # im Pfadwert kodiert': (
        template: 'https://h.example.org/n/{t}',
        args: {'t': 'a?b#c'},
        url: 'https://h.example.org/n/a%3Fb%23c',
      ),
      '%2F im Pfadwert wird doppelt kodiert': (
        template: 'https://h.example.org/n/{t}',
        args: {'t': '..%2Fadmin'},
        url: 'https://h.example.org/n/..%252Fadmin',
      ),
      '/ im Pfadwert abgelehnt': (
        template: 'https://h.example.org/n/{t}',
        args: {'t': 'a/b'},
        url: null,
      ),
      'Backslash im Pfadwert abgelehnt': (
        template: 'https://h.example.org/n/{t}',
        args: {'t': r'a\b'},
        url: null,
      ),
      '.. als Pfadwert abgelehnt': (
        template: 'https://h.example.org/a/{t}/b',
        args: {'t': '..'},
        url: null,
      ),
      '. als Pfadwert abgelehnt': (
        template: 'https://h.example.org/a/{t}',
        args: {'t': '.'},
        url: null,
      ),
      'Literal plus Wert ergibt ..': (
        template: 'https://h.example.org/a/.{t}',
        args: {'t': '.'},
        url: null,
      ),
      'Punkte innerhalb eines Werts erlaubt': (
        template: 'https://h.example.org/a/{t}',
        args: {'t': 'v1..2'},
        url: 'https://h.example.org/a/v1..2',
      ),
      'leerer Pfadwert abgelehnt': (
        template: 'https://h.example.org/a/{t}',
        args: {'t': ''},
        url: null,
      ),
      'fehlendes Pfadargument': (
        template: 'https://h.example.org/a/{t}',
        args: {},
        url: null,
      ),
      'Zahl und Wahrheitswert im Pfad': (
        template: 'https://h.example.org/{n}/{b}/{d}',
        args: {'n': 42, 'b': true, 'd': 30.0},
        url: 'https://h.example.org/42/true/30',
      ),
      'Liste im Pfad abgelehnt': (
        template: 'https://h.example.org/{n}',
        args: {
          'n': [1, 2],
        },
        url: null,
      ),
      'Query-Wert URL-kodiert': (
        template: 'https://h.example.org/s?q={q}&lang=de',
        args: {'q': 'a&b=c d+ü'},
        url: 'https://h.example.org/s?q=a%26b%3Dc+d%2B%C3%BC&lang=de',
      ),
      'Query: # kann keinen Anker erzeugen': (
        template: 'https://h.example.org/s?q={q}',
        args: {'q': 'x#frag'},
        url: 'https://h.example.org/s?q=x%23frag',
      ),
      'optionaler Query-Parameter fällt weg': (
        template: 'https://h.example.org/s?q={q}&limit={limit}',
        args: {'q': 'milch'},
        url: 'https://h.example.org/s?q=milch',
      ),
      'eingebetteter Query-Platzhalter fehlt': (
        template: 'https://h.example.org/s?q=prefix-{q}',
        args: {},
        url: null,
      ),
      'Query-Flag ohne Wert bleibt': (
        template: 'https://h.example.org/s?raw&x={x}',
        args: {'x': 1},
        url: 'https://h.example.org/s?raw&x=1',
      ),
      'Port der Vorlage bleibt': (
        template: 'http://192.168.178.20:8123/api/{p}',
        args: {'p': 'config'},
        url: 'http://192.168.178.20:8123/api/config',
      ),
      'Host aus Argument unmöglich: @host im Pfad': (
        template: 'https://h.example.org/{p}',
        args: {'p': '@evil.example'},
        url: 'https://h.example.org/%40evil.example',
      ),
      'Host aus Argument unmöglich: //host im Pfad': (
        template: 'https://h.example.org/x{p}',
        args: {'p': '//evil.example'},
        url: null,
      ),
      'Host aus Argument unmöglich: volle URL im Query': (
        template: 'https://h.example.org/r?to={p}',
        args: {'p': 'https://evil.example/'},
        url: 'https://h.example.org/r?to=https%3A%2F%2Fevil.example%2F',
      ),
    };
    for (final MapEntry(key: name, value: c) in cases.entries) {
      test(name, () {
        final t = UrlTemplate.parse(c.template);
        if (c.url == null) {
          expect(
            () => t.expand(c.args),
            throwsA(isA<InvalidArgumentsException>()),
          );
        } else {
          final uri = t.expand(c.args);
          expect(uri.toString(), c.url);
          expect(uri.origin, t.origin.origin);
        }
      });
    }
  });

  group('URL-Vorlage: Parsen', () {
    final invalid = <String, String>{
      'Platzhalter im Host': 'https://{host}/api',
      'Platzhalter als Subdomain': 'https://{tenant}.example.org/api',
      'Platzhalter im Port': 'https://h.example.org:{port}/api',
      'Platzhalter im Schema': '{scheme}://h.example.org/',
      'ganze URL als Platzhalter': '{url}',
      'Zugangsdaten': 'https://user:pw@h.example.org/',
      'Platzhalter im Query-Namen': 'https://h.example.org/?{k}=1',
      'Anker': 'https://h.example.org/a#{x}',
      'ftp': 'ftp://h.example.org/',
      'kaputter Platzhalter': 'https://h.example.org/{a-b}',
      'offene Klammer': 'https://h.example.org/{a',
      'Leerzeichen': 'https://h.example.org/a b',
      'Zeilenumbruch': 'https://h.example.org/a\nb',
      'kein Host': 'https:///api',
      'leer': '  ',
      'relativ': '/api/{x}',
    };
    for (final MapEntry(key: name, value: template) in invalid.entries) {
      test('abgelehnt: $name', () {
        expect(() => UrlTemplate.parse(template), throwsFormatException);
      });
    }

    test('zu lange URL', () {
      expect(
        () => UrlTemplate.parse('https://h.example.org/${'a' * 2100}'),
        throwsFormatException,
      );
    });

    test('Platzhalter in Pfad und Query werden gesammelt', () {
      final t = UrlTemplate.parse(
        'https://h.example.org/a/{x}/b{y}c?q={z}&fix=1&flag',
      );
      expect(t.placeholders, {'x', 'y', 'z'});
      expect(t.origin, Uri.parse('https://h.example.org'));
    });

    test('Host wird klein geschrieben', () {
      expect(
        UrlTemplate.parse('HTTPS://H.Example.ORG/x').origin.toString(),
        'https://h.example.org',
      );
    });
  });

  group('Header-Vorlagen', () {
    test(
      'Platzhalter eingesetzt, fehlender Ein-Platzhalter-Header fällt weg',
      () {
        final h = expandHeaders(
          {'X-Room': '{room}', 'X-Mode': 'fix', 'X-Opt': '{opt}'},
          {'room': 'Küche'.replaceAll('ü', 'ue')},
        );
        expect(h, {'X-Room': 'Kueche', 'X-Mode': 'fix'});
      },
    );

    for (final bad in [
      'a\r\nX-Evil: 1',
      'a\nb',
      'a\rb',
      'a\u0000b',
      'a\u007fb',
    ]) {
      test('Header-Injection abgelehnt: ${bad.codeUnits}', () {
        expect(
          () => expandHeaders({'X-Room': '{room}'}, {'room': bad}),
          throwsA(
            isA<InvalidArgumentsException>().having(
              (e) => e.message,
              'message',
              contains('Zeilenumbrüche'),
            ),
          ),
        );
      });
    }

    test('Nicht-ASCII im Header abgelehnt', () {
      expect(
        () => expandHeaders({'X-Room': '{room}'}, {'room': 'Küche'}),
        throwsA(isA<InvalidArgumentsException>()),
      );
    });

    test('eingebetteter fehlender Platzhalter ist ein Fehler', () {
      expect(
        () => expandHeaders({'X-Room': 'r-{room}'}, {}),
        throwsA(isA<InvalidArgumentsException>()),
      );
    });
  });

  group('JSON-Body typgerecht', () {
    final template = <String, Object?>{
      'entity_id': '{entity}',
      'brightness': '{level}',
      'on': '{on}',
      'tags': '{tags}',
      'meta': '{meta}',
      'note': 'Hallo {name}!',
      'fixed': 7,
      'list': ['{entity}', '{missing}', 1],
      'nested': {'x': '{missing}', 'y': null},
    };

    test('Werte behalten ihren Typ, kein String-Zusammenbau', () {
      final body = expandJsonBody(template, {
        'entity': 'light.kitchen',
        'level': 128,
        'on': false,
        'tags': ['a', 'b'],
        'meta': {'k': 1.5},
        'name': 'Welt',
      });
      expect(body, {
        'entity_id': 'light.kitchen',
        'brightness': 128,
        'on': false,
        'tags': ['a', 'b'],
        'meta': {'k': 1.5},
        'note': 'Hallo Welt!',
        'fixed': 7,
        'list': ['light.kitchen', 1],
        'nested': {'y': null},
      });
    });

    test(
      'Anführungszeichen im Wert bleiben ein String (keine JSON-Injection)',
      () {
        final body = expandJsonBody(
          {'a': '{v}', 'b': 'x{v}'},
          {'v': '", "admin": true, "x": "'},
        );
        expect(body, {
          'a': '", "admin": true, "x": "',
          'b': 'x", "admin": true, "x": "',
        });
      },
    );

    test('Top-Level-Platzhalter fehlt → Fehler', () {
      expect(
        () => expandJsonBody('{payload}', {}),
        throwsA(isA<InvalidArgumentsException>()),
      );
      expect(expandJsonBody('{payload}', {'payload': 3}), 3);
    });

    test('eingebetteter Platzhalter mit Objekt → Fehler', () {
      expect(
        () => expandJsonBody(
          {'a': 'x{v}'},
          {
            'v': {'k': 1},
          },
        ),
        throwsA(isA<InvalidArgumentsException>()),
      );
    });

    test('Formular-Body kodiert und lässt fehlende weg', () {
      expect(
        expandFormBody(
          {'q': '{q}', 'n': 3, 'b': true, 'opt': '{opt}', 'x': 'a {q}'},
          {'q': 'a&b ü'},
        ),
        'q=a%26b+%C3%BC&n=3&b=true&x=a+a%26b+%C3%BC',
      );
    });
  });
}
