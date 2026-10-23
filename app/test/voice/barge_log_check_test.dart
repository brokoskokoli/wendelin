import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/barge_log.dart';

String l(String event, [String fields = '']) =>
    'I/flutter: Wendelin/voice: $event engine=overlay $fields';

void main() {
  final config = l('barge-config', 'verify=true thr=0.80');

  test('Kandidat, Gegenprüfung, Treffer: kein Befund', () {
    expect(
      bargeLogProblem([
        config,
        l('barge-cand', 'kind=wake busy=false'),
        l('barge-verify', 'result=wake ms=900'),
        l('barge-hit', 'kind=keyword-wake'),
      ], hitKind: 'keyword-wake'),
      isNull,
    );
  });

  test('Treffer ohne Gegenprüfung ist ein Befund', () {
    expect(
      bargeLogProblem([
        config,
        l('barge-cand', 'kind=wake busy=false'),
        l('barge-hit', 'kind=keyword-wake'),
      ]),
      contains('ohne passendes barge-verify'),
    );
  });

  test(
    'Treffer nach verworfenem Kandidaten (no, echo, skip) ist ein Befund',
    () {
      for (final r in ['no', 'echo', 'skip']) {
        expect(
          bargeLogProblem([
            config,
            l('barge-cand', 'kind=wake busy=false'),
            l('barge-verify', 'result=$r ms=500'),
            l('barge-hit', 'kind=keyword-wake'),
          ]),
          isNotNull,
          reason: r,
        );
      }
    },
  );

  test(
    'WP134: ein Urteil result=stop (altes Stopp-Wort) trägt keinen Treffer',
    () {
      expect(
        bargeLogProblem([
          config,
          l('barge-cand', 'kind=wake busy=false'),
          l('barge-verify', 'result=stop ms=500'),
          l('barge-hit', 'kind=keyword-wake'),
        ]),
        isNotNull,
      );
    },
  );

  test('Ein Urteil trägt nur einen Treffer', () {
    expect(
      bargeLogProblem([
        config,
        l('barge-cand', 'kind=wake busy=false'),
        l('barge-verify', 'result=wake ms=500'),
        l('barge-hit', 'kind=keyword-wake'),
        l('barge-cand', 'kind=wake busy=false'),
        l('barge-hit', 'kind=keyword-wake'),
      ]),
      contains('ohne passendes barge-verify'),
    );
  });

  test('Ein Kandidat trägt nur einen Treffer', () {
    expect(
      bargeLogProblem([
        config,
        l('barge-cand', 'kind=wake busy=false'),
        l('barge-verify', 'result=wake ms=500'),
        l('barge-hit', 'kind=keyword-wake'),
        l('barge-verify', 'result=wake ms=500'),
        l('barge-hit', 'kind=keyword-wake'),
      ]),
      contains('ohne barge-cand'),
    );
  });

  test('Ohne verify=true, ohne Treffer, falsche Art ist ein Befund', () {
    expect(bargeLogProblem([]), 'kein barge-config');
    expect(
      bargeLogProblem([l('barge-config', 'verify=false')]),
      contains('verify=true'),
    );
    expect(bargeLogProblem([config]), 'kein barge-hit');
    expect(
      bargeLogProblem([
        config,
        l('barge-cand', 'kind=wake busy=false'),
        l('barge-verify', 'result=wake ms=1'),
        l('barge-hit', 'kind=keyword-wake'),
      ], hitKind: 'keyword-andere'),
      contains('keyword-andere'),
    );
  });
}
