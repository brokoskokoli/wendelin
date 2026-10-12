import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

void main() {
  calendarPortContract(FakeCalendarPort.new, name: 'FakeCalendarPort');
  calendarPortContract(
    () => FakeCalendarPort(
      defaultId: null,
      calendars: [
        const CalendarInfo(id: 'abo', name: 'Feiertage', writable: false),
        const CalendarInfo(id: 'privat', name: 'Privat', writable: true),
      ],
    ),
    name: 'FakeCalendarPort mit schreibgeschütztem Kalender',
  );
  clipboardPortContract(FakeClipboardPort.new, name: 'FakeClipboardPort');
  alarmPortContract(FakeAlarmPort.new, name: 'FakeAlarmPort');
  alarmPortContract(
    () => FakeAlarmPort(returnsIds: false, canList: false),
    name: 'FakeAlarmPort wie Android-Intent',
  );
  alarmPortContract(
    () => FakeAlarmPort(canList: false),
    name: 'FakeAlarmPort ohne Liste',
  );
  memoryStoreContract(FakeMemoryStore.new, name: 'FakeMemoryStore');
  webSearchBackendContract((scenario) {
    final hits = [
      for (var i = 0; i < 6; i++)
        WebSearchResult(
          title: 'Treffer $i',
          url: 'https://example.org/$i',
          snippet: 'Text $i',
        ),
    ];
    return switch (scenario) {
      WebSearchScenario.results => FakeWebSearchBackend(results: hits),
      WebSearchScenario.empty => FakeWebSearchBackend(),
      WebSearchScenario.unauthorized ||
      WebSearchScenario.rateLimited => FakeWebSearchBackend(
        error: const PortException(
          PortErrorKind.unavailable,
          'Fake-Suche nicht verfügbar',
        ),
      ),
      WebSearchScenario.malformed => FakeWebSearchBackend(
        error: const PortException(PortErrorKind.failed, 'unlesbar'),
      ),
    };
  }, name: 'FakeWebSearchBackend');
}
