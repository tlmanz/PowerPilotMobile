// The demo: a simulated UPS behind the same interface as the server, ported
// from PowerPilot's js/sources/mock.js. By default it cycles through mains, a
// 50-second outage and recovery. It also makes up a month of logbook.
import 'dart:async';
import 'dart:math' as math;

import '../models/ups.dart';
import '../ui/format.dart' show elapsed, ymd;
import 'cloud_source.dart' show ApiError;
import 'source.dart';

const _ratedW = 1200.0;
const _ratedVA = 2000;
const _packV = 24.0;

/// The same Peukert estimate the service uses, so both sources look alike.
double? runtimeMinutes(double chargePct, double loadW, int batteryAh) {
  if (loadW <= 0) return null;
  final amps = loadW / (_packV * 0.85);
  final hours = 20 * math.pow(batteryAh / (amps * 20), 1.15);
  return math.min(hours * 60 * chargePct / 100, 480).toDouble();
}

class MockSource implements UpsSource {
  /// [scenario] is cycle, ac, battery, bypass or fault.
  MockSource({this.scenario = 'cycle', this.interval = const Duration(seconds: 2), math.Random? random}) : _rnd = random ?? math.Random();

  final String scenario;
  final Duration interval;
  final math.Random _rnd;

  SourceSink? _sink;
  Timer? _timer;
  final _started = DateTime.now();

  double _input = 231, _output = 230, _load = 42, _battery = 78, _pf = 0.84;
  bool _beeper = true, _muted = false, _lowNotified = false;
  double _testLeft = 0;
  double? _shutdownIn, _restoreIn;
  bool _outletsOff = false;
  String? _mode;
  DateTime _batterySince = DateTime.now();
  TestResult? _lastTest;
  UpsSettings _settings = const UpsSettings();
  final List<UpsEvent> _sessionEvents = [];
  final List<UpsEvent> _pending = [];
  final List<Sample> _history = [];
  final Map<String, ({List<Reading> readings, List<UpsEvent> events})> _days = {};

  static const device = UpsDevice(
    brand: 'Prolink',
    model: 'PRO2000SFCU',
    protocol: 'Simulated',
    connection: 'demo',
    ratedVA: _ratedVA,
    ratedW: 1200,
    appVersion: 'demo',
  );

  @override
  String get label => 'Demo';

  @override
  bool get isDemo => true;

  double _clamp(double v, double lo, double hi) => math.min(hi, math.max(lo, v));
  double _walk(double v, double step, double lo, double hi) => _clamp(v + (_rnd.nextDouble() - 0.5) * 2 * step, lo, hi);

  void _event(String kind, String level, String message) {
    final e = UpsEvent(id: 'demo-${_sessionEvents.length}', time: DateTime.now(), kind: kind, level: level, message: message);
    _sessionEvents.add(e);
    _pending.add(e);
  }

  String _scenarioMode(double elapsed) {
    if (scenario != 'cycle') return scenario == 'bypass' ? 'bypass' : scenario;
    final t = elapsed % 240;
    return t >= 150 && t < 200 ? 'battery' : 'ac';
  }

  /// Starting again after the app was in the background keeps the session's
  /// events and history, as a server would.
  @override
  void start(SourceSink sink) {
    _sink = sink;
    if (_history.isEmpty) {
      _history.addAll(_seedHistory());
      _event('connection', 'good', 'Connected to the demo UPS');
    }
    _step(send: false);
    _pending.clear();
    sink.onState(
      DeviceState(
        device: device,
        snapshot: _last,
        history: List.of(_history),
        events: [..._logFor(DateTime.now()).events, ..._sessionEvents],
        settings: _settings,
        lastTest: _lastTest,
        online: true,
        lastSeen: DateTime.now(),
      ),
    );
    sink.onLink(true);
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _step());
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  late Snapshot _last;
  late Sample _lastSample;

  DateTime? _lastStep;

  void _step({bool send = true}) {
    // Commands step the simulation too, so time is what really passed.
    final now = DateTime.now();
    final dt = _lastStep == null ? 0.0 : now.difference(_lastStep!).inMilliseconds / 1000;
    _lastStep = now;
    if (_shutdownIn != null) {
      _shutdownIn = _shutdownIn! - dt;
      if (_shutdownIn! <= 0) {
        _shutdownIn = null;
        _outletsOff = true;
        _event('shutdown', 'warn', 'Outlets turned off');
      }
    }
    if (_outletsOff && _restoreIn != null) {
      _restoreIn = _restoreIn! - dt;
      if (_restoreIn! <= 0) {
        _restoreIn = null;
        _outletsOff = false;
        _event('shutdown', 'good', 'Outlets turned back on');
      }
    }
    if (_testLeft > 0) {
      _testLeft -= dt;
      if (_testLeft <= 0) {
        _testLeft = 0;
        _lastTest = TestResult(kind: 'test', started: _lastTest!.started, ended: DateTime.now(), result: 'passed');
        _event('self_test', 'good', 'UPS self-test completed (passed)');
      }
    }

    final base = _scenarioMode(DateTime.now().difference(_started).inMilliseconds / 1000);
    final mode = _outletsOff ? 'standby' : (_testLeft > 0 && base == 'ac' ? 'test' : base);
    final onBattery = mode == 'battery';
    final off = mode == 'standby' || mode == 'fault';

    _input = onBattery ? 0 : _walk(_input == 0 ? 231 : _input, 0.8, 224, 238);
    _output = off ? 0 : _walk(_output == 0 ? 230 : _output, 0.4, 228.5, 231.5);
    _load = off ? 0 : _walk(_load == 0 ? 42 : _load, 1.5, 30, 55);
    _battery = onBattery || mode == 'test' ? _clamp(_battery - 0.35, 0, 100) : _clamp(_battery + 0.08, 0, 100);
    _pf = _walk(_pf, 0.005, 0.8, 0.9);

    // Transitions raise events, as the service does.
    if (mode != _mode) {
      if (mode == 'battery') {
        _batterySince = DateTime.now();
        _event('utility_lost', 'alert', 'Utility power lost');
        _event('on_battery', 'warn', 'Running on battery');
      } else if (_mode == 'battery') {
        _event('utility_restored', 'good', 'Utility power restored after ${elapsed(DateTime.now().difference(_batterySince))}');
        _event('battery_charging', 'info', 'Battery charging');
        _lowNotified = false;
      }
      if (mode == 'fault') _event('fault', 'alert', 'The UPS reports a fault');
      if (mode == 'bypass') _event('info', 'warn', 'UPS switched to bypass');
      _mode = mode;
    }
    final low = onBattery && _battery < _settings.lowBatteryPercent;
    if (low && !_lowNotified) {
      _lowNotified = true;
      _event(
        'low_battery',
        'alert',
        'Battery charge is ${_battery.toStringAsFixed(1)}%, below your ${_settings.lowBatteryPercent}% alert level',
      );
    }
    final alarmCondition = onBattery || low || mode == 'fault' || _load >= 100;
    if (_muted && !alarmCondition) {
      _muted = false;
      _beeper = true;
      _event('alarm_unmuted', 'info', 'Alarm unmuted: the alarm condition cleared');
    }

    _last = _snapshot(low: low);
    _lastSample = Sample(
      t: DateTime.now(),
      input: _input,
      output: _output,
      load: _load,
      batt: _batteryVolts,
      freq: _last.status!.frequency,
      charge: _battery,
    );
    _history.add(_lastSample);
    final cut = DateTime.now().subtract(const Duration(hours: 1));
    _history.removeWhere((s) => s.t.isBefore(cut));
    if (!send) return;
    final events = List<UpsEvent>.of(_pending);
    _pending.clear();
    _sink?.onUpdate(StreamUpdate(snapshot: _last, sample: _lastSample, events: events, settings: _settings, lastTest: _lastTest));
  }

  double get _batteryVolts => 21 + _battery * 0.055;

  Snapshot _snapshot({bool low = false}) {
    final mode = _mode ?? 'ac';
    final watts = _load / 100 * _ratedW;
    final charging = mode != 'battery' && mode != 'test' && _battery < 99.5;
    final state = low
        ? 'low'
        : mode == 'battery' || mode == 'test'
        ? 'discharging'
        : charging
        ? 'charging'
        : 'full';
    return Snapshot(
      connected: true,
      updatedAt: DateTime.now(),
      status: UpsStatus(
        inputVoltage: _input,
        outputVoltage: _output,
        loadPercent: _load,
        frequency: 50 + (_rnd.nextDouble() - 0.5) * 0.2,
        batteryVoltage: _batteryVolts,
        onBattery: mode == 'battery',
        batteryLow: low,
        // Bypass shows as AVR on an online UPS, as the real one would report it.
        avrActive: mode == 'bypass',
        fault: mode == 'fault',
        lineInteractive: mode != 'bypass',
        testRunning: mode == 'test',
        shutdownActive: _shutdownIn != null,
        beeperOn: _beeper,
      ),
      ratings: const Ratings(voltage: 230, current: 8, batteryVoltage: _packV, frequency: 50),
      charge: _battery,
      runtimeMin: runtimeMinutes(_battery, math.max(watts, 12), _settings.batteryAh),
      loadW: watts,
      loadVA: watts / _pf,
      mode: switch (mode) {
        'ac' || 'bypass' => 'line',
        _ => mode,
      },
      batteryState: state,
      onBatterySec: mode == 'battery' ? DateTime.now().difference(_batterySince).inMilliseconds / 1000 : 0,
      alarmActive: mode == 'battery' || mode == 'fault' || low,
      alarmMuted: _muted,
    );
  }

  List<Sample> _seedHistory() {
    final now = DateTime.now();
    return List.generate(120, (i) {
      final k = i / 120;
      return Sample(
        t: now.subtract(Duration(seconds: (120 - i) * 30)),
        input: 231 + math.sin(k * 9) * 2.5 + (_rnd.nextDouble() - 0.5),
        output: 230 + (_rnd.nextDouble() - 0.5) * 0.8,
        load: 40 + math.sin(k * 5) * 6 + (_rnd.nextDouble() - 0.5) * 3,
        batt: 21 + math.min(100, 70 + k * 8) * 0.055,
        freq: 50,
        charge: math.min(100, 70 + k * 8),
      );
    });
  }

  @override
  Future<String> command(String id, {double minutes = 0, int restoreAfter = 0}) async {
    switch (id) {
      case 'beeper.on':
        _beeper = true;
        _muted = false;
        _event('alarm', 'info', 'UPS alarm turned on');
      case 'beeper.off':
        _beeper = false;
        _muted = false;
        _event('alarm', 'info', 'UPS alarm turned off');
      case 'alarm.mute':
        if (_mode != 'battery' && _mode != 'fault') throw const ApiError('No alarm is sounding; use UPS alarm to turn it off');
        _beeper = false;
        _muted = true;
        _event('alarm_muted', 'info', 'Alarm muted until the current condition clears');
      case 'alarm.unmute':
        _beeper = true;
        _muted = false;
        _event('alarm_unmuted', 'info', 'Alarm unmuted');
      case 'test.quick':
        if (_mode != 'ac') throw const ApiError('Self-tests can only run on mains power');
        _testLeft = 10;
        _lastTest = TestResult(kind: 'test', started: DateTime.now(), result: 'running');
        _event('self_test', 'info', 'Battery self-test started');
      case 'test.cancel':
        _testLeft = 0;
        if (_lastTest case final t?) {
          _lastTest = TestResult(kind: 'test', started: t.started, ended: DateTime.now(), result: 'cancelled');
        }
        _event('self_test', 'info', 'Cancelled the battery self-test');
      case 'shutdown':
        if (!(minutes >= 0.2 && minutes <= 10)) throw const ApiError('Shutdown delay must be 0.2–0.9 or 1–10 minutes');
        _shutdownIn = minutes * 60;
        _restoreIn = restoreAfter > 0 ? restoreAfter * 60.0 : null;
        _event('shutdown', 'warn', 'Outlet shutdown is counting down');
      case 'shutdown.cancel':
        _shutdownIn = null;
        _outletsOff = false;
        _event('shutdown', 'info', 'Outlet shutdown ended or was cancelled');
      default:
        throw ApiError('Invalid command: unknown command "$id"');
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    _step();
    return '(demo)';
  }

  @override
  Future<UpsSettings> saveSettings(UpsSettings settings) async {
    final problem = settings.validate();
    if (problem != null) throw ApiError(problem);
    _settings = settings;
    _event('info', 'info', 'Settings updated');
    _step();
    return settings;
  }

  @override
  Future<void> refresh() async => _step();

  // The made-up logbook: one outage on some days, a self-test on others, and
  // readings every minute. The same date always makes the same day.

  ({List<Reading> readings, List<UpsEvent> events}) _logFor(DateTime day) {
    final date = ymd(day);
    final today = date == ymd(DateTime.now());
    if (!today && _days.containsKey(date)) return _days[date]!;

    final rnd = math.Random(date.hashCode);
    final start = DateTime(day.year, day.month, day.day);
    final end = today ? _started : start.add(const Duration(days: 1));
    final minutes = end.difference(start).inMinutes;

    // Today always has an outage, so the day's summary has something to show.
    int? outageAt, outageLen;
    if (today ? minutes > 90 : rnd.nextDouble() < 0.3) {
      outageAt = today ? minutes ~/ 3 : 60 + rnd.nextInt(1300);
      outageLen = 5 + rnd.nextInt(20);
    }
    final testAt = !today && rnd.nextDouble() < 0.15 ? 10 : null;

    final events = <UpsEvent>[];
    UpsEvent ev(int minute, String kind, String level, String message) => UpsEvent(
      // Unique per event: a self-test starts and passes in the same minute.
      id: '$date-${events.length}',
      time: start.add(Duration(minutes: minute)),
      kind: kind,
      level: level,
      message: message,
    );
    if (testAt != null) {
      events.add(ev(testAt, 'self_test', 'info', 'Battery self-test started'));
      events.add(ev(testAt, 'self_test', 'good', 'UPS self-test completed (passed)'));
    }
    if (outageAt != null) {
      events.add(ev(outageAt, 'utility_lost', 'alert', 'Utility power lost'));
      events.add(ev(outageAt, 'on_battery', 'warn', 'Running on battery'));
      events.add(ev(outageAt + outageLen!, 'utility_restored', 'good', 'Utility power restored after $outageLen min'));
      events.add(ev(outageAt + outageLen, 'battery_charging', 'info', 'Battery charging'));
    }

    final readings = <Reading>[];
    var charge = 100.0;
    for (var m = 0; m < minutes; m++) {
      final h = m / 60;
      final battery = outageAt != null && m >= outageAt && m < outageAt + outageLen!;
      charge = battery ? math.max(5, charge - 1.8) : math.min(100, charge + 0.3);
      final input = battery ? 0.0 : 231 + math.sin(h / 24 * 2 * math.pi) * 3 + (rnd.nextDouble() - 0.5) * 2;
      final load = 38 + math.sin((h - 9) / 24 * 2 * math.pi) * 8 + (rnd.nextDouble() - 0.5) * 4;
      readings.add(
        Reading(
          t: start.add(Duration(minutes: m)),
          mode: battery ? 'battery' : 'line',
          input: input,
          inputMin: battery ? 0 : input - rnd.nextDouble() * 2,
          inputMax: battery ? 0 : input + rnd.nextDouble() * 2,
          output: 230 + (rnd.nextDouble() - 0.5) * 0.8,
          load: load,
          loadMax: load + rnd.nextDouble() * 5,
          batt: 21 + charge * 0.055,
          freq: battery ? 0 : 50 + (rnd.nextDouble() - 0.5) * 0.1,
          charge: charge,
        ),
      );
    }
    final log = (readings: readings, events: events);
    if (!today) _days[date] = log;
    return log;
  }

  DateTime _parse(String date) {
    final p = date.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  @override
  Future<List<LogDay>> logDays() async {
    final now = DateTime.now();
    return [
      for (var i = 0; i < 30; i++)
        () {
          final d = DateTime(now.year, now.month, now.day - i);
          final n = i == 0 ? _logFor(d).events.length + _sessionEvents.length : _logFor(d).events.length;
          return LogDay(date: ymd(d), events: n, readings: true);
        }(),
    ];
  }

  @override
  Future<List<UpsEvent>> logEvents(String date) async {
    final today = date == ymd(DateTime.now());
    return [..._logFor(_parse(date)).events, if (today) ..._sessionEvents];
  }

  @override
  Future<List<Reading>> logReadings(String date) async => _logFor(_parse(date)).readings;

  @override
  Future<String> exportCsv(String kind, String from, String to) async {
    final out = StringBuffer();
    final first = _parse(from), last = _parse(to);
    if (kind == 'events') {
      out.writeln('time,kind,level,message');
    } else {
      out.writeln('time,mode,in,in_min,in_max,out,load,load_max,batt,charge,freq');
    }
    for (var d = first; !d.isAfter(last); d = DateTime(d.year, d.month, d.day + 1)) {
      if (kind == 'events') {
        for (final e in await logEvents(ymd(d))) {
          out.writeln('${e.time.toIso8601String()},${e.kind},${e.level},"${e.message.replaceAll('"', '""')}"');
        }
      } else {
        for (final r in _logFor(d).readings) {
          String f(double v) => v.toStringAsFixed(1);
          out.writeln(
            '${r.t.toIso8601String()},${r.mode},${f(r.input)},${f(r.inputMin)},${f(r.inputMax)},'
            '${f(r.output)},${f(r.load)},${f(r.loadMax)},${f(r.batt)},${r.charge == null ? '' : f(r.charge!)},${f(r.freq)}',
          );
        }
      }
    }
    return out.toString();
  }
}
