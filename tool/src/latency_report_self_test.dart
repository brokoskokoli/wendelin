// Selbsttest der Latenz-Auswertung (WP120) mit einem Beispiel-Log.
import 'latency_report.dart';
import 'self_check.dart';

const _log = '''
10-21 10:00:00.000 I/flutter (1): Wendelin/voice: other engine=app x=1
10-21 10:00:01.000 I/flutter (1): Wendelin/voice: latency engine=app stt=300 calls=1 tools=0 m1_req=300 m1_first=900 m1_done=1000 tts1=1000 syn_end=1200 audio_first=1250 audio_last=3000 sentences=2 s1_syn=150 s2_syn=200 s2_gap=100
10-21 10:00:02.000 I/flutter (1): Wendelin/voice: latency engine=app stt=500 calls=1 tools=0 m1_req=500 m1_first=1100 m1_done=1500 tts1=1500 syn_end=1700 audio_first=1800 audio_last=3500 sentences=1 s1_syn=170
10-21 10:00:03.000 I/flutter (1): Wendelin/voice: latency engine=app stt=400 calls=1 tools=0 m1_req=400 m1_first=1000 m1_done=1200 tts1=1200 syn_end=1400 audio_first=1500 audio_last=2800 sentences=1 s1_syn=160
''';

void latencyReportChecks(SelfCheck t) {
  t.group('Latenz-Auswertung');
  final f = parseLatencyLine(
    'I/flutter: Wendelin/voice: latency engine=app stt=300 calls=1 s2_gap=100',
  );
  t.eq(f, {'stt': 300, 'calls': 1, 's2_gap': 100}, 'Zeile geparst');
  t.eq(parseLatencyLine('Wendelin/voice: other engine=app x=1'), null, 'fremd');
  t.eq(percentile([1000, 1500, 1200], 50), 1200, 'p50 nearest-rank');
  t.eq(percentile([1000, 1500, 1200], 90), 1500, 'p90 nearest-rank');
  final report = latencyReport(_log);
  t.eq(report.contains('Anfragen: 3'), true, 'drei Anfragen');
  final first = report
      .split('\n')
      .firstWhere((l) => l.startsWith('audio_first-stt'));
  // 950, 1300, 1100 -> p50 1100, p90 1300.
  t.eq(first.trim().split(RegExp(r'\s+')), [
    'audio_first-stt',
    '3',
    '1100',
    '1300',
  ], 'abgeleitet');
  final gap = report.split('\n').firstWhere((l) => l.startsWith('s2_gap'));
  t.eq(gap.trim().split(RegExp(r'\s+')), [
    's2_gap',
    '1',
    '100',
    '100',
  ], 's2_gap');
  t.eq(latencyReport('nichts').contains('Keine Zeilen'), true, 'leer');
}
