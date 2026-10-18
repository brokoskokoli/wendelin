import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

String fixture(String name) =>
    File('test/fixtures/weather/$name').readAsStringSync();

/// Mock client answering every request with [body]/[status], recording them.
MockClient mock(List<http.Request> seen, String body, {int status = 200}) =>
    MockClient((request) async {
      seen.add(request);
      return http.Response.bytes(
        utf8.encode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

const hamburg = Place(
  name: 'Hamburg',
  latitude: 53.55073,
  longitude: 9.99302,
  timeZone: 'Europe/Berlin',
);

/// Sun 2026-10-18 13:00 Berlin, when the fixtures were recorded.
final recordedAt = DateTime.utc(2026, 10, 18, 11);

WeatherRequest request({int days = 2, int hours = 6}) => WeatherRequest(
  place: hamburg,
  zone: timeZoneLocation('Europe/Berlin'),
  now: recordedAt,
  days: days,
  hours: hours,
);
