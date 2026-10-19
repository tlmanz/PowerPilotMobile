// App state: what the phone is paired with, and the live state of that UPS.
// Screens read them through AppScope and UpsScope and rebuild on changes.
import 'package:flutter/widgets.dart';

import '../data/cloud_source.dart';
import '../data/mock_source.dart';
import '../data/pairing.dart';
import '../data/source.dart';
import '../models/ups.dart';
import '../models/ups_view.dart';

const _historySpan = Duration(hours: 1);
const _maxEvents = 200;

class UpsController extends ChangeNotifier implements SourceSink {
  UpsController(this.source);

  final UpsSource source;

  UpsDevice device = const UpsDevice();
  Snapshot snapshot = const Snapshot();
  UpsSettings settings = const UpsSettings();
  TestResult? lastTest;

  /// The last hour of samples, oldest first.
  List<Sample> history = const [];

  /// Recent events, oldest first.
  List<UpsEvent> events = const [];

  /// The device can reach the server (always true for the demo).
  bool online = true;
  DateTime? lastSeen;

  /// The first state has arrived.
  bool loaded = false;

  /// This phone can reach the server.
  bool linkUp = false;
  String linkError = '';

  bool _running = false;
  UpsView? _view;

  UpsView get view => _view ??= UpsView.from(device, snapshot, settings, lastTest);

  void start() {
    if (_running) return;
    _running = true;
    source.start(this);
  }

  void stop() {
    if (!_running) return;
    _running = false;
    source.stop();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  void _changed() {
    _view = null;
    notifyListeners();
  }

  List<Sample> _recent(Iterable<Sample> samples) {
    final cut = DateTime.now().subtract(_historySpan);
    return samples.where((s) => s.t.isAfter(cut)).toList()..sort((a, b) => a.t.compareTo(b.t));
  }

  List<UpsEvent> _merge(List<UpsEvent> into, Iterable<UpsEvent> more) {
    final seen = {for (final e in into) e.key};
    final out = [
      ...into,
      for (final e in more)
        if (seen.add(e.key)) e,
    ]..sort((a, b) => a.time.compareTo(b.time));
    return out.length > _maxEvents ? out.sublist(out.length - _maxEvents) : out;
  }

  @override
  void onState(DeviceState s) {
    device = s.device;
    snapshot = s.snapshot;
    settings = s.settings;
    lastTest = s.lastTest;
    history = _recent(s.history);
    events = _merge(const [], s.events);
    online = s.online;
    lastSeen = s.lastSeen;
    loaded = true;
    _changed();
  }

  @override
  void onUpdate(StreamUpdate u) {
    snapshot = u.snapshot;
    if (u.settings != null) settings = u.settings!;
    if (u.lastTest != null) lastTest = u.lastTest;
    online = u.online;
    if (u.online) lastSeen = DateTime.now();
    if (u.sample != null) history = _recent([...history, u.sample!]);
    if (u.events.isNotEmpty) events = _merge(events, u.events);
    _changed();
  }

  @override
  void onLink(bool up, [String error = '']) {
    if (linkUp == up && linkError == error) return;
    linkUp = up;
    linkError = error;
    _changed();
  }

  /// Runs a command; throws with a message to show if it fails.
  Future<String> command(String id, {double minutes = 0, int restoreAfter = 0}) =>
      source.command(id, minutes: minutes, restoreAfter: restoreAfter);

  Future<void> saveSettings(UpsSettings next) async {
    final problem = next.validate();
    if (problem != null) throw ApiError(problem);
    settings = await source.saveSettings(next);
    _changed();
  }

  Future<void> refresh() => source.refresh();
}

enum AppPhase { loading, unpaired, ready }

class AppController extends ChangeNotifier with WidgetsBindingObserver {
  AppController({this.store = const PairingStore(), this.demoScenario});

  final PairingStore store;

  /// Opens the demo in this scenario, whatever is saved (for development).
  final String? demoScenario;

  AppPhase phase = AppPhase.loading;
  Pairing? pairing;
  UpsController? ups;

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    Pairing? saved;
    try {
      saved = demoScenario != null ? const Pairing.demo() : await store.load();
    } on Object {
      // An unreadable Keychain entry means pairing again, not a crash.
      saved = null;
    }
    if (saved != null) {
      _open(saved);
    } else {
      phase = AppPhase.unpaired;
    }
    notifyListeners();
  }

  void _open(Pairing p) {
    ups?.dispose();
    final UpsSource source = p.demo
        ? MockSource(scenario: demoScenario ?? 'cycle')
        : CloudSource(server: p.server!, token: p.token!, deviceId: p.device!);
    ups = UpsController(source)..start();
    pairing = p;
    phase = AppPhase.ready;
  }

  Future<void> pair(Pairing p) async {
    await store.save(p);
    _open(p);
    notifyListeners();
  }

  Future<void> unpair() async {
    await store.clear();
    ups?.dispose();
    ups = null;
    pairing = null;
    phase = AppPhase.unpaired;
    notifyListeners();
  }

  /// Streams don't survive the background on a phone: stop, then start over
  /// (which loads the full state) on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden || AppLifecycleState.detached:
        ups?.stop();
      case AppLifecycleState.resumed:
        ups?.start();
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ups?.dispose();
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController super.notifier, required super.child});

  static AppController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

class UpsScope extends InheritedNotifier<UpsController> {
  const UpsScope({super.key, required UpsController super.notifier, required super.child});

  static UpsController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<UpsScope>()!.notifier!;
}
