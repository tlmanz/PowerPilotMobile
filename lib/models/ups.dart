// The JSON powerpilot-server sends. It follows PowerPilot's Go types field for
// field (internal/monitor, internal/ups, internal/logbook, internal/settings),
// so these mirror them. Devices may leave out optional fields.

typedef Json = Map<String, dynamic>;

double? _dbl(Object? v) => v is num ? v.toDouble() : null;
double _d(Object? v) => v is num ? v.toDouble() : 0;
int _i(Object? v) => v is num ? v.toInt() : 0;
bool _b(Object? v) => v == true;
String _s(Object? v) => v is String ? v : '';
Json? _obj(Object? v) => v is Map<String, dynamic> ? v : null;

List<T> _list<T>(Object? v, T Function(Json) f) => v is List
    ? [
        for (final e in v)
          if (e is Map<String, dynamic>) f(e),
      ]
    : <T>[];

/// RFC 3339, as Go writes time.Time. Its zero value means "never".
DateTime? _time(Object? v) {
  if (v is! String || v.isEmpty || v.startsWith('0001')) return null;
  return DateTime.tryParse(v)?.toLocal();
}

DateTime _ms(Object? v) => DateTime.fromMillisecondsSinceEpoch(_i(v));

/// monitor.Device: what the UPS is and how it's reached.
class UpsDevice {
  const UpsDevice({
    this.brand = '',
    this.model = '',
    this.protocol = '',
    this.connection = '',
    this.ratedVA = 0,
    this.ratedW = 0,
    this.appVersion = '',
  });

  factory UpsDevice.fromJson(Json? j) => j == null
      ? const UpsDevice()
      : UpsDevice(
          brand: _s(j['brand']),
          model: _s(j['model']),
          protocol: _s(j['protocol']),
          connection: _s(j['connection']),
          ratedVA: _i(j['rated_va']),
          ratedW: _i(j['rated_w']),
          appVersion: _s(j['app_version']),
        );

  final String brand, model, protocol, connection, appVersion;
  final int ratedVA, ratedW;

  String get name {
    final n = '$brand $model'.trim();
    return n.isEmpty ? 'UPS' : n;
  }
}

/// ups.Ratings: the UPS's `F` reply.
class Ratings {
  const Ratings({this.voltage = 0, this.current = 0, this.batteryVoltage = 0, this.frequency = 0});

  factory Ratings.fromJson(Json j) => Ratings(
    voltage: _d(j['voltage']),
    current: _d(j['current']),
    batteryVoltage: _d(j['battery_voltage']),
    frequency: _d(j['frequency']),
  );

  final double voltage, current, batteryVoltage, frequency;
}

/// ups.Status: the UPS's `QS` reply, with its status bits.
class UpsStatus {
  const UpsStatus({
    this.inputVoltage = 0,
    this.inputFaultVoltage = 0,
    this.outputVoltage = 0,
    this.loadPercent = 0,
    this.frequency = 0,
    this.batteryVoltage = 0,
    this.temperature,
    this.onBattery = false,
    this.batteryLow = false,
    this.avrActive = false,
    this.fault = false,
    this.lineInteractive = false,
    this.testRunning = false,
    this.shutdownActive = false,
    this.beeperOn = false,
  });

  factory UpsStatus.fromJson(Json j) => UpsStatus(
    inputVoltage: _d(j['input_voltage']),
    inputFaultVoltage: _d(j['input_fault_voltage']),
    outputVoltage: _d(j['output_voltage']),
    loadPercent: _d(j['load_percent']),
    frequency: _d(j['frequency']),
    batteryVoltage: _d(j['battery_voltage']),
    temperature: _dbl(j['temperature']),
    onBattery: _b(j['on_battery']),
    batteryLow: _b(j['battery_low']),
    avrActive: _b(j['avr_active']),
    fault: _b(j['fault']),
    lineInteractive: _b(j['line_interactive']),
    testRunning: _b(j['test_running']),
    shutdownActive: _b(j['shutdown_active']),
    beeperOn: _b(j['beeper_on']),
  );

  final double inputVoltage, inputFaultVoltage, outputVoltage, loadPercent, frequency, batteryVoltage;
  final double? temperature;
  final bool onBattery, batteryLow, avrActive, fault, lineInteractive, testRunning, shutdownActive, beeperOn;
}

class RuntimePoint {
  const RuntimePoint(this.load, this.minutes);
  final double load, minutes;
}

/// monitor.Snapshot: the latest reading and what the monitor made of it.
class Snapshot {
  const Snapshot({
    this.connected = false,
    this.error = '',
    this.updatedAt,
    this.status,
    this.ratings,
    this.charge,
    this.runtimeMin,
    this.runtimeCurve = const [],
    this.loadW = 0,
    this.loadVA = 0,
    this.mode = '',
    this.batteryState = '',
    this.onBatterySec = 0,
    this.alarmActive = false,
    this.alarmMuted = false,
  });

  factory Snapshot.fromJson(Json? j) {
    if (j == null) return const Snapshot();
    final st = _obj(j['status']), r = _obj(j['ratings']);
    return Snapshot(
      connected: _b(j['connected']),
      error: _s(j['error']),
      updatedAt: _time(j['updated_at']),
      status: st == null ? null : UpsStatus.fromJson(st),
      ratings: r == null ? null : Ratings.fromJson(r),
      charge: _dbl(j['charge']),
      runtimeMin: _dbl(j['runtime_min']),
      runtimeCurve: _list(j['runtime_curve'], (p) => RuntimePoint(_d(p['load']), _d(p['min']))),
      loadW: _d(j['load_w']),
      loadVA: _d(j['load_va']),
      mode: _s(j['mode']),
      batteryState: _s(j['battery_state']),
      onBatterySec: _d(j['on_battery_sec']),
      alarmActive: _b(j['alarm_active']),
      alarmMuted: _b(j['alarm_muted']),
    );
  }

  final bool connected;
  final String error;
  final DateTime? updatedAt;
  final UpsStatus? status;
  final Ratings? ratings;
  final double? charge, runtimeMin;
  final List<RuntimePoint> runtimeCurve;
  final double loadW, loadVA, onBatterySec;

  /// line, battery, test, fault or standby.
  final String mode;

  /// charging, discharging, full or low.
  final String batteryState;
  final bool alarmActive, alarmMuted;
}

/// monitor.Sample: one point of the last hour.
class Sample {
  const Sample({required this.t, this.input = 0, this.output = 0, this.load = 0, this.batt = 0, this.freq = 0, this.charge});

  factory Sample.fromJson(Json j) => Sample(
    t: _ms(j['t']),
    input: _d(j['in']),
    output: _d(j['out']),
    load: _d(j['load']),
    batt: _d(j['batt']),
    freq: _d(j['freq']),
    charge: _dbl(j['charge']),
  );

  final DateTime t;
  final double input, output, load, batt, freq;
  final double? charge;
}

/// logbook.Reading: one minute of samples, as kept on disk.
class Reading {
  const Reading({
    required this.t,
    this.mode = 'line',
    this.input = 0,
    this.inputMin = 0,
    this.inputMax = 0,
    this.output = 0,
    this.load = 0,
    this.loadMax = 0,
    this.batt = 0,
    this.freq = 0,
    this.charge,
  });

  factory Reading.fromJson(Json j) => Reading(
    t: _ms(j['t']),
    mode: _s(j['mode']),
    input: _d(j['in']),
    inputMin: _d(j['in_min']),
    inputMax: _d(j['in_max']),
    output: _d(j['out']),
    load: _d(j['load']),
    loadMax: _d(j['load_max']),
    batt: _d(j['batt']),
    freq: _d(j['freq']),
    charge: _dbl(j['charge']),
  );

  final DateTime t;
  final String mode;
  final double input, inputMin, inputMax, output, load, loadMax, batt, freq;
  final double? charge;
}

/// monitor.Event, plus the id a device gives it.
class UpsEvent {
  const UpsEvent({this.id = '', required this.time, required this.kind, required this.level, required this.message});

  factory UpsEvent.fromJson(Json j) => UpsEvent(
    id: _s(j['id']),
    time: _time(j['time']) ?? DateTime.now(),
    kind: _s(j['kind']).isEmpty ? 'info' : _s(j['kind']),
    level: _s(j['level']).isEmpty ? 'info' : _s(j['level']),
    message: _s(j['message']),
  );

  final String id, kind, message;
  final DateTime time;

  /// info, good, warn or alert.
  final String level;

  /// Devices send events again after a reconnect: this tells repeats apart,
  /// as the server's contract.Event.Key does.
  String get key => id.isNotEmpty ? id : '${time.toUtc().toIso8601String()}|$kind|$message';

  /// The design shows a title and a detail line. A message carries both after
  /// a line break (notifications add the reading) or a colon
  /// ("Overload: load at 105.0%").
  ({String title, String? detail}) get parts {
    final nl = message.indexOf('\n');
    if (nl > 0) return (title: message.substring(0, nl), detail: message.substring(nl + 1).trim());
    final colon = message.indexOf(': ');
    if (colon > 0) {
      final d = message.substring(colon + 2);
      return (title: message.substring(0, colon), detail: d.isEmpty ? null : d[0].toUpperCase() + d.substring(1));
    }
    return (title: message, detail: null);
  }
}

/// monitor.TestResult. The server doesn't carry it yet, so it's null there.
class TestResult {
  const TestResult({required this.kind, required this.started, this.ended, required this.result});

  factory TestResult.fromJson(Json j) =>
      TestResult(kind: _s(j['kind']), started: _time(j['started']) ?? DateTime.now(), ended: _time(j['ended']), result: _s(j['result']));

  final String kind;
  final DateTime started;
  final DateTime? ended;

  /// running, passed, failed or cancelled.
  final String result;
}

/// settings.Settings, with PowerPilot's ranges.
class UpsSettings {
  const UpsSettings({
    this.lowBatteryPercent = 20,
    this.notify = true,
    this.shutdownMac = false,
    this.shutdownAfterMinutes = 5,
    this.batteryAh = 9,
    this.logRetentionDays = 90,
  });

  factory UpsSettings.fromJson(Json? j) => j == null
      ? const UpsSettings()
      : UpsSettings(
          lowBatteryPercent: _i(j['low_battery_percent']),
          notify: _b(j['notify']),
          shutdownMac: _b(j['shutdown_mac']),
          shutdownAfterMinutes: _i(j['shutdown_after_minutes']),
          batteryAh: _i(j['battery_ah']),
          logRetentionDays: _i(j['log_retention_days']),
        );

  final int lowBatteryPercent, shutdownAfterMinutes, batteryAh, logRetentionDays;
  final bool notify, shutdownMac;

  Json toJson() => {
    'low_battery_percent': lowBatteryPercent,
    'notify': notify,
    'shutdown_mac': shutdownMac,
    'shutdown_after_minutes': shutdownAfterMinutes,
    'battery_ah': batteryAh,
    'log_retention_days': logRetentionDays,
  };

  UpsSettings copyWith({
    int? lowBatteryPercent,
    bool? notify,
    bool? shutdownMac,
    int? shutdownAfterMinutes,
    int? batteryAh,
    int? logRetentionDays,
  }) => UpsSettings(
    lowBatteryPercent: lowBatteryPercent ?? this.lowBatteryPercent,
    notify: notify ?? this.notify,
    shutdownMac: shutdownMac ?? this.shutdownMac,
    shutdownAfterMinutes: shutdownAfterMinutes ?? this.shutdownAfterMinutes,
    batteryAh: batteryAh ?? this.batteryAh,
    logRetentionDays: logRetentionDays ?? this.logRetentionDays,
  );

  /// The server's own check (contract.Settings.Validate), so a bad value
  /// fails here with the same message.
  String? validate() {
    if (lowBatteryPercent < 5 || lowBatteryPercent > 90) return 'Low battery threshold must be between 5% and 90%';
    if (shutdownAfterMinutes < 1 || shutdownAfterMinutes > 240) return 'Shutdown delay must be between 1 and 240 minutes';
    if (batteryAh < 1 || batteryAh > 200) return 'Battery capacity must be between 1 and 200 Ah';
    if (logRetentionDays < 1 || logRetentionDays > 3650) return 'Logs must be kept for 1 to 3,650 days';
    return null;
  }
}

/// One day in the logbook: GET .../logs.
class LogDay {
  const LogDay({required this.date, this.events = 0, this.readings = false});

  factory LogDay.fromJson(Json j) => LogDay(date: _s(j['date']), events: _i(j['events']), readings: _b(j['readings']));

  /// 2026-10-19
  final String date;
  final int events;
  final bool readings;
}

/// GET /api/devices/{d}/state: PowerPilot's /api/state, plus online and
/// last_seen.
class DeviceState {
  const DeviceState({
    this.device = const UpsDevice(),
    this.snapshot = const Snapshot(),
    this.history = const [],
    this.events = const [],
    this.settings = const UpsSettings(),
    this.lastTest,
    this.intervalMs = 2000,
    this.online = true,
    this.lastSeen,
  });

  factory DeviceState.fromJson(Json j) {
    final t = _obj(j['last_test']);
    return DeviceState(
      device: UpsDevice.fromJson(_obj(j['device'])),
      snapshot: Snapshot.fromJson(_obj(j['snapshot'])),
      history: _list(j['history'], Sample.fromJson),
      events: _list(j['events'], UpsEvent.fromJson),
      settings: UpsSettings.fromJson(_obj(j['settings'])),
      lastTest: t == null ? null : TestResult.fromJson(t),
      intervalMs: j['interval_ms'] is num ? _i(j['interval_ms']) : 2000,
      online: j['online'] is bool ? j['online'] as bool : true,
      lastSeen: _time(j['last_seen']),
    );
  }

  final UpsDevice device;
  final Snapshot snapshot;
  final List<Sample> history;
  final List<UpsEvent> events;
  final UpsSettings settings;
  final TestResult? lastTest;
  final int intervalMs;
  final bool online;
  final DateTime? lastSeen;
}

/// One entry of GET /api/devices.
class DeviceSummary {
  const DeviceSummary({
    required this.id,
    this.online = false,
    this.lastSeen,
    this.device = const UpsDevice(),
    this.snapshot = const Snapshot(),
  });

  factory DeviceSummary.fromJson(Json j) => DeviceSummary(
    id: _s(j['id']),
    online: _b(j['online']),
    lastSeen: _time(j['last_seen']),
    device: UpsDevice.fromJson(_obj(j['device'])),
    snapshot: Snapshot.fromJson(_obj(j['snapshot'])),
  );

  final String id;
  final bool online;
  final DateTime? lastSeen;
  final UpsDevice device;
  final Snapshot snapshot;
}

/// A command's result (`cmd/result`), streamed to the apps.
class CommandResult {
  const CommandResult({required this.cmdId, required this.status, this.raw = '', this.error = ''});

  factory CommandResult.fromJson(Json j) =>
      CommandResult(cmdId: _s(j['cmd_id']), status: _s(j['status']), raw: _s(j['raw']), error: _s(j['error']));

  final String cmdId, raw, error;

  /// done, rejected, invalid, expired or failed.
  final String status;
}

/// One `data:` line of GET .../stream: PowerPilot's monitor.Update, plus
/// online and command results.
class StreamUpdate {
  const StreamUpdate({
    required this.snapshot,
    this.sample,
    this.events = const [],
    this.settings,
    this.lastTest,
    this.online = true,
    this.result,
  });

  factory StreamUpdate.fromJson(Json j) {
    final s = _obj(j['sample']), cfg = _obj(j['settings']), t = _obj(j['last_test']), r = _obj(j['result']);
    return StreamUpdate(
      snapshot: Snapshot.fromJson(_obj(j['snapshot'])),
      sample: s == null ? null : Sample.fromJson(s),
      events: _list(j['events'], UpsEvent.fromJson),
      settings: cfg == null ? null : UpsSettings.fromJson(cfg),
      lastTest: t == null ? null : TestResult.fromJson(t),
      online: j['online'] is bool ? j['online'] as bool : true,
      result: r == null ? null : CommandResult.fromJson(r),
    );
  }

  final Snapshot snapshot;
  final Sample? sample;
  final List<UpsEvent> events;
  final UpsSettings? settings;
  final TestResult? lastTest;
  final bool online;
  final CommandResult? result;
}
