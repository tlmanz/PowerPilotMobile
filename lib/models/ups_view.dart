// The one UPS state every screen renders from, as PowerPilot's dashboard
// builds it (js/state.js). Sources produce the server's types; this maps them.
import 'ups.dart';

enum UpsMode { ac, battery, bypass, fault, standby, test, offline }

const _statusLabels = {
  UpsMode.ac: 'Online',
  UpsMode.battery: 'On battery',
  UpsMode.bypass: 'Bypass',
  UpsMode.fault: 'Fault',
  UpsMode.standby: 'Outlets off',
  UpsMode.test: 'Self-test',
  UpsMode.offline: 'Disconnected',
};

String statusLabel(UpsMode m) => _statusLabels[m]!;

enum AlarmLevel { none, warning, critical }

class Alarm {
  const Alarm({this.enabled = false, this.muted = false, this.level = AlarmLevel.none, this.message = ''});

  /// The beeper is on, or muted for the current alarm.
  final bool enabled;
  final bool muted;
  final AlarmLevel level;
  final String message;

  bool get active => level != AlarmLevel.none;

  /// Sounding right now: active, beeper on, not muted.
  bool get sounding => active && enabled && !muted;
}

/// deriveAlarm in js/state.js.
Alarm deriveAlarm({
  required bool onBattery,
  required bool batteryLow,
  required bool fault,
  required bool overload,
  required bool enabled,
  required bool muted,
}) {
  var level = AlarmLevel.none, message = '';
  if (fault) {
    (level, message) = (AlarmLevel.critical, 'UPS fault');
  } else if (batteryLow) {
    (level, message) = (AlarmLevel.critical, 'Battery low');
  } else if (overload) {
    (level, message) = (AlarmLevel.critical, 'Overload');
  } else if (onBattery) {
    (level, message) = (AlarmLevel.warning, 'Running on battery');
  }
  return Alarm(enabled: enabled, muted: muted, level: level, message: message);
}

enum BatteryHealth { good, replace, testing, unknown }

class UpsView {
  const UpsView({
    this.connected = false,
    this.error = '',
    this.updatedAt,
    this.device = const UpsDevice(),
    this.type = '',
    this.nominalVoltage,
    this.nominalFrequency,
    this.mode = UpsMode.offline,
    this.onBatterySec,
    this.inputVoltage,
    this.inputFrequency,
    this.outputVoltage,
    this.loadPercent,
    this.watts,
    this.va,
    this.batteryPercent,
    this.batteryVoltage,
    this.batteryNominalVoltage,
    this.batteryState = 'unknown',
    this.health = BatteryHealth.unknown,
    this.runtimeMinutes,
    this.lowThreshold = 20,
    this.lastTest,
    this.testRunning = false,
    this.temperature,
    this.avr = false,
    this.alarm = const Alarm(),
    this.shutdownPending = false,
    this.settings = const UpsSettings(),
  });

  /// The UPS answers the device (ESP32 or PowerPilot).
  final bool connected;
  final String error;
  final DateTime? updatedAt;
  final UpsDevice device;

  /// Line-interactive or Online, once the UPS has answered.
  final String type;
  final double? nominalVoltage, nominalFrequency;
  final UpsMode mode;

  /// How long the current outage has lasted.
  final double? onBatterySec;
  final double? inputVoltage, inputFrequency, outputVoltage, loadPercent, watts, va;
  final double? batteryPercent, batteryVoltage, batteryNominalVoltage;

  /// charging, discharging, full, low or unknown.
  final String batteryState;
  final BatteryHealth health;
  final double? runtimeMinutes;
  final int lowThreshold;
  final TestResult? lastTest;
  final bool testRunning;

  /// °C; null when the UPS doesn't report it (the PRO2000SFCU doesn't).
  final double? temperature;

  /// Boost/buck on a line-interactive UPS.
  final bool avr;
  final Alarm alarm;
  final bool shutdownPending;
  final UpsSettings settings;

  String get status => statusLabel(mode);

  bool get onMains => mode == UpsMode.ac || mode == UpsMode.bypass;

  /// fromLive in js/state.js.
  factory UpsView.from(UpsDevice device, Snapshot snap, UpsSettings settings, TestResult? lastTest) {
    final st = snap.connected ? snap.status : null;
    final r = snap.ratings;
    final health = switch (lastTest?.result) {
      'passed' => BatteryHealth.good,
      'failed' => BatteryHealth.replace,
      'running' => BatteryHealth.testing,
      _ => BatteryHealth.unknown,
    };
    if (st == null) {
      return UpsView(
        error: snap.error,
        updatedAt: snap.updatedAt,
        device: device,
        nominalVoltage: r?.voltage,
        nominalFrequency: r?.frequency,
        lowThreshold: settings.lowBatteryPercent,
        lastTest: lastTest,
        health: health,
        settings: settings,
      );
    }

    final base = switch (snap.mode) {
      'battery' => UpsMode.battery,
      'test' => UpsMode.test,
      'fault' => UpsMode.fault,
      'standby' => UpsMode.standby,
      _ => UpsMode.ac,
    };
    // A set AVR bit means bypass on online UPSes, but boost/buck on
    // line-interactive ones.
    final mode = base == UpsMode.ac && st.avrActive && !st.lineInteractive ? UpsMode.bypass : base;
    return UpsView(
      connected: true,
      error: snap.error,
      updatedAt: snap.updatedAt,
      device: device,
      type: st.lineInteractive ? 'Line-interactive' : 'Online',
      nominalVoltage: r?.voltage,
      nominalFrequency: r?.frequency,
      mode: mode,
      onBatterySec: st.onBattery ? snap.onBatterySec : null,
      inputVoltage: st.inputVoltage,
      inputFrequency: st.frequency,
      outputVoltage: st.outputVoltage,
      loadPercent: st.loadPercent,
      watts: snap.loadW,
      va: snap.loadVA,
      batteryPercent: snap.charge,
      batteryVoltage: st.batteryVoltage,
      batteryNominalVoltage: r?.batteryVoltage,
      batteryState: snap.batteryState.isEmpty ? 'unknown' : snap.batteryState,
      health: health,
      runtimeMinutes: snap.runtimeMin,
      lowThreshold: settings.lowBatteryPercent,
      lastTest: lastTest,
      testRunning: st.testRunning,
      temperature: st.temperature,
      avr: st.avrActive && st.lineInteractive,
      alarm: deriveAlarm(
        onBattery: st.onBattery,
        batteryLow: st.batteryLow || snap.batteryState == 'low',
        fault: st.fault,
        overload: st.loadPercent >= 100,
        enabled: st.beeperOn || snap.alarmMuted,
        muted: snap.alarmMuted,
      ),
      shutdownPending: st.shutdownActive,
      settings: settings,
    );
  }
}
