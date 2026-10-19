// Where UPS data comes from. Like PowerPilot's dashboard sources
// (js/sources/), every source has the same interface, so the screens never
// know which one they're showing: the server, or the built-in demo.
import '../models/ups.dart';

/// What a source reports to.
abstract interface class SourceSink {
  /// The whole state, on start and after every reconnect.
  void onState(DeviceState state);

  /// One stream update.
  void onUpdate(StreamUpdate update);

  /// Whether the source can reach its data, and why not.
  void onLink(bool up, [String error]);
}

abstract interface class UpsSource {
  /// The device ID, or "Demo" for the demo.
  String get label;
  bool get isDemo;

  void start(SourceSink sink);

  /// Stops streaming (the app went to the background, or unpaired).
  void stop();

  /// Runs a command (ups.Build's ids: beeper.on, beeper.off, alarm.mute,
  /// alarm.unmute, test.quick, test.cancel, shutdown, shutdown.cancel) and
  /// returns what was sent to the UPS.
  Future<String> command(String id, {double minutes = 0, int restoreAfter = 0});

  Future<UpsSettings> saveSettings(UpsSettings settings);

  /// Asks for the current state again.
  Future<void> refresh();

  /// Days in the logbook, newest first.
  Future<List<LogDay>> logDays();
  Future<List<UpsEvent>> logEvents(String date);
  Future<List<Reading>> logReadings(String date);

  /// One kind of log (events or readings) for a range of dates, as CSV.
  Future<String> exportCsv(String kind, String from, String to);
}
