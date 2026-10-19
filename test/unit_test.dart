import 'package:flutter_test/flutter_test.dart';
import 'package:powerpilot/data/cloud_source.dart';
import 'package:powerpilot/data/mock_source.dart';
import 'package:powerpilot/data/pairing.dart';
import 'package:powerpilot/data/source.dart';
import 'package:powerpilot/models/ups.dart';
import 'package:powerpilot/models/ups_view.dart';
import 'package:powerpilot/ui/format.dart';

Json _snapshot({String mode = 'line', Json status = const {}, Json extra = const {}}) => {
  'connected': true,
  'updated_at': '2026-10-19T01:47:00Z',
  'status': {
    'input_voltage': 231.0,
    'output_voltage': 230.0,
    'load_percent': 41.6,
    'frequency': 50.0,
    'battery_voltage': 26.7,
    'temperature': null,
    'on_battery': false,
    'battery_low': false,
    'avr_active': false,
    'fault': false,
    'line_interactive': true,
    'test_running': false,
    'shutdown_active': false,
    'beeper_on': true,
    ...status,
  },
  'ratings': {'voltage': 230, 'current': 8, 'battery_voltage': 24, 'frequency': 50},
  'charge': 90.0,
  'runtime_min': 42.5,
  'load_w': 499.2,
  'load_va': 585.0,
  'mode': mode,
  'battery_state': 'charging',
  'alarm_active': false,
  'alarm_muted': false,
  ...extra,
};

UpsView _view(Json snap) => UpsView.from(const UpsDevice(), Snapshot.fromJson(snap), const UpsSettings(), null);

class _Sink implements SourceSink {
  DeviceState? state;
  final updates = <StreamUpdate>[];
  @override
  void onState(DeviceState s) => state = s;
  @override
  void onUpdate(StreamUpdate u) => updates.add(u);
  @override
  void onLink(bool up, [String error = '']) {}
}

void main() {
  group('format', () {
    test('numbers have thousands separators', () {
      expect(number(2000), '2,000');
      expect(number(1234567.891, 1), '1,234,567.9');
      expect(number(999), '999');
      expect(number(-0.04, 1), '0.0');
      expect(number(-1500), '-1,500');
    });

    test('percentages have one decimal', () {
      expect(pct(90), '90.0%');
      expect(pct(41.63), '41.6%');
    });

    test('dates are MM/DD/YY and times are 12-hour', () {
      final d = DateTime(2026, 10, 9, 13, 5, 7);
      expect(date(d), '10/09/26');
      expect(clock(d), '1:05 PM');
      expect(clock(DateTime(2026, 1, 1, 0, 10)), '12:10 AM');
      expect(dateTime(d, seconds: true), '10/09/26 1:05:07 PM');
      expect(ymd(d), '2026-10-09');
    });

    test('runtime estimates cap at 8 hours', () {
      expect(duration(null), '—');
      expect(duration(9.4), '9 min');
      expect(duration(75), '1 h 15 min');
      expect(duration(480), 'Over 8 h');
      expect(elapsed(const Duration(seconds: 30)), 'under a minute');
      expect(elapsed(const Duration(minutes: 120)), '2 h');
    });
  });

  group('models', () {
    test('a state parses, and Go zero times mean never', () {
      final s = DeviceState.fromJson({
        'device': {'brand': 'Prolink', 'model': 'PRO2000SFCU', 'connection': 'esp32', 'rated_va': 2000, 'rated_w': 1200},
        'snapshot': _snapshot(extra: {'updated_at': '0001-01-01T00:00:00Z'}),
        'history': [
          {'t': 1792432633447, 'in': 231, 'out': 230, 'load': 41.6, 'batt': 26.7, 'freq': 50, 'charge': 90},
        ],
        'events': [
          {'id': 'e1', 'time': '2026-10-19T01:47:00Z', 'kind': 'utility_lost', 'level': 'alert', 'message': 'Utility power lost'},
        ],
        'settings': {
          'low_battery_percent': 25,
          'notify': true,
          'shutdown_mac': false,
          'shutdown_after_minutes': 5,
          'battery_ah': 9,
          'log_retention_days': 90,
        },
        'last_test': null,
        'interval_ms': 5000,
        'online': false,
        'last_seen': '2026-10-19T01:56:00Z',
      });
      expect(s.device.name, 'Prolink PRO2000SFCU');
      expect(s.snapshot.updatedAt, isNull);
      expect(s.snapshot.status!.loadPercent, 41.6);
      expect(s.history.single.t.millisecondsSinceEpoch, 1792432633447);
      expect(s.events.single.key, 'e1');
      expect(s.settings.lowBatteryPercent, 25);
      expect(s.lastTest, isNull);
      expect(s.online, isFalse);
      expect(s.lastSeen, isNotNull);
    });

    test("PowerPilot's own /api/state has no online field: online", () {
      expect(DeviceState.fromJson({'snapshot': _snapshot()}).online, isTrue);
    });

    test('settings round-trip and validate with the server ranges', () {
      const s = UpsSettings(lowBatteryPercent: 30, batteryAh: 12);
      expect(UpsSettings.fromJson(s.toJson()).batteryAh, 12);
      expect(s.validate(), isNull);
      expect(s.copyWith(lowBatteryPercent: 95).validate(), contains('5% and 90%'));
      expect(s.copyWith(logRetentionDays: 4000).validate(), contains('3,650'));
    });

    test('event messages split into a title and a detail', () {
      UpsEvent e(String m) => UpsEvent(time: DateTime(2026), kind: 'info', level: 'info', message: m);
      expect(e('Utility power lost').parts, (title: 'Utility power lost', detail: null));
      expect(e('Overload: load at 105.0%').parts, (title: 'Overload', detail: 'Load at 105.0%'));
      expect(e('On battery for 5 min\nBattery 80.2% · Load 41.6% (499 W)').parts.detail, 'Battery 80.2% · Load 41.6% (499 W)');
    });
  });

  group('view', () {
    test('mains maps to AC mode', () {
      final v = _view(_snapshot());
      expect(v.mode, UpsMode.ac);
      expect(v.status, 'Online');
      expect(v.type, 'Line-interactive');
      expect(v.alarm.active, isFalse);
      expect(v.batteryPercent, 90);
    });

    test('on battery raises a warning alarm', () {
      final v = _view(_snapshot(mode: 'battery', status: {'on_battery': true, 'input_voltage': 0.0}, extra: {'on_battery_sec': 120.0}));
      expect(v.mode, UpsMode.battery);
      expect(v.onBatterySec, 120);
      expect(v.alarm.level, AlarmLevel.warning);
      expect(v.alarm.sounding, isTrue);
    });

    test('AVR on an online UPS means bypass; on a line-interactive one, regulation', () {
      expect(_view(_snapshot(status: {'avr_active': true, 'line_interactive': false})).mode, UpsMode.bypass);
      final li = _view(_snapshot(status: {'avr_active': true}));
      expect(li.mode, UpsMode.ac);
      expect(li.avr, isTrue);
    });

    test('a fault outranks the battery, and muting keeps the alarm enabled', () {
      final v = _view(
        _snapshot(mode: 'fault', status: {'fault': true, 'on_battery': true, 'beeper_on': false}, extra: {'alarm_muted': true}),
      );
      expect(v.mode, UpsMode.fault);
      expect(v.alarm.level, AlarmLevel.critical);
      expect(v.alarm.message, 'UPS fault');
      expect(v.alarm.enabled, isTrue);
      expect(v.alarm.sounding, isFalse);
    });

    test('no UPS means offline with the error', () {
      final v = _view({'connected': false, 'error': 'UPS not found', 'mode': ''});
      expect(v.connected, isFalse);
      expect(v.mode, UpsMode.offline);
      expect(v.error, 'UPS not found');
    });
  });

  group('pairing', () {
    test('a link from the admin page parses', () {
      final p = PairingLink.parse('powerpilot://pair?token=t0ken&url=https%3A%2F%2Fups.example.com&device=home&extra=1');
      expect(p.server.toString(), 'https://ups.example.com');
      expect(p.token, 't0ken');
      expect(p.device, 'home');
    });

    test('the device is optional', () {
      expect(PairingLink.parse(' powerpilot://pair?url=https://ups.example.com&token=t0ken ').device, isNull);
    });

    test('bad links are refused with a reason', () {
      expect(() => PairingLink.parse('https://ups.example.com'), throwsFormatException);
      expect(
        () => PairingLink.parse('powerpilot://pair?url=http://ups.example.com&token=t0ken'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('https'))),
      );
      expect(() => PairingLink.parse('powerpilot://pair?url=https://ups.example.com'), throwsFormatException);
      expect(() => PairingLink.parse('powerpilot://pair?url=https://ups.example.com&token=t&device=Home!'), throwsFormatException);
    });

    test('a saved pairing reads back', () {
      final p = Pairing.fromJson(Pairing.cloud(server: Uri.parse('https://ups.example.com'), token: 't0ken', device: 'home').toJson())!;
      expect(p.demo, isFalse);
      expect(p.device, 'home');
      expect(Pairing.fromJson(const Pairing.demo().toJson())!.demo, isTrue);
      expect(Pairing.fromJson('not json'), isNull);
    });
  });

  test('server-sent events: data lines make a message; pings are skipped', () async {
    final lines = Stream.fromIterable([': ok', '', 'data: {"a":1}', '', ': ping', '', 'event: cmd', 'data: x', 'data: y', '']);
    final got = await parseSse(lines).toList();
    expect(got.map((m) => (m.event, m.data)), [('message', '{"a":1}'), ('cmd', 'x\ny')]);
  });

  group('demo', () {
    test('starts with a state and follows the rules of the real commands', () async {
      final sink = _Sink();
      final mock = MockSource(scenario: 'ac', interval: const Duration(hours: 1))..start(sink);
      addTearDown(mock.stop);
      expect(sink.state!.device.model, 'PRO2000SFCU');
      expect(sink.state!.history, isNotEmpty);

      await expectLater(mock.command('alarm.mute'), throwsA(isA<ApiError>()));
      await mock.command('test.quick');
      expect(sink.updates.last.snapshot.mode, 'test');
      expect(sink.updates.last.events.map((e) => e.kind), contains('self_test'));
      await expectLater(mock.command('shutdown', minutes: 30), throwsA(isA<ApiError>()));
      await expectLater(mock.saveSettings(const UpsSettings(lowBatteryPercent: 1)), throwsA(isA<ApiError>()));
    });

    test('makes up a logbook', () async {
      final mock = MockSource();
      final days = await mock.logDays();
      expect(days, hasLength(30));
      final readings = await mock.logReadings(days[1].date);
      expect(readings, hasLength(1440));
      expect(await mock.exportCsv('events', days[6].date, days[0].date), startsWith('time,kind,level,message'));
    });

    test('estimates runtime as the service does', () {
      expect(runtimeMinutes(100, 0, 9), isNull);
      expect(runtimeMinutes(100, 12, 9), 480);
      // The design's on-battery screen: 74.5% at 499 W is about 9 min.
      expect(runtimeMinutes(74.5, 499, 9)!, closeTo(9.0, 0.2));
    });
  });
}
