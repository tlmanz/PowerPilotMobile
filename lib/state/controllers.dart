// App state: what the phone is paired with, and the live state of that UPS.
// Screens read them through AppScope and UpsScope and rebuild on changes.
import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/cloud_source.dart';
import '../data/mock_source.dart';
import '../data/pairing.dart';
import '../data/push.dart';
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

/// Push notifications: whether this phone gets them, and its registration
/// with the server. Settings shows it; the shell shows what arrives.
class PushController extends ChangeNotifier {
  PushController({required this.platform, this.prefs = const PushPrefsStore()});

  final PushPlatform platform;
  final PushPrefsStore prefs;

  /// This build can do push: Android, with Firebase's config.
  bool supported = false;
  bool enabled = false;
  bool outageUpdates = false;
  bool busy = false;

  /// The phone said no; only Android's settings can change that now.
  bool blocked = false;

  /// A tapped notification started the app: the shell opens Events.
  PushMessage? launchedFrom;

  Pairing? _pairing;
  String? _token; // the FCM token the server has
  final _foreground = StreamController<PushMessage>.broadcast();
  final _opened = StreamController<PushMessage>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];

  Stream<PushMessage> get foreground => _foreground.stream;
  Stream<PushMessage> get opened => _opened.stream;

  /// Paired with a server (not the demo), in a build that can do push.
  bool get available => supported && _pairing != null && !_pairing!.demo;

  bool get demo => _pairing?.demo ?? false;

  Future<void> init() async {
    supported = await platform.init();
    final saved = await prefs.load();
    enabled = saved.enabled;
    outageUpdates = saved.outageUpdates;
    _token = saved.token;
    if (supported) {
      _subs
        ..add(platform.foreground.listen(_foreground.add))
        ..add(platform.opened.listen(_opened.add))
        ..add(platform.tokenRefresh.listen((_) => _register().ignore()));
      launchedFrom = await platform.initialOpened();
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      await prefs.save(PushPrefs(enabled: enabled, outageUpdates: outageUpdates, token: _token));
    } on Object {
      // Not saved: asked again next time, nothing worse.
    }
  }

  /// The phone is paired with p, or nothing. With push on, it registers again,
  /// so the server always has the current token.
  Future<void> attach(Pairing? p) async {
    _pairing = p;
    notifyListeners();
    if (available && enabled) {
      try {
        await _register();
      } on Object {
        // Tried again on the next start, or when the token changes.
      }
    }
  }

  /// Registers this phone's token and choices; returns whether the server can send.
  Future<bool> _register() async {
    final p = _pairing;
    if (p == null || p.demo || !enabled) return false;
    final token = await platform.token();
    if (token == null) throw const ApiError("Firebase didn't give this phone a token");
    final sending = await CloudSource.registerPush(p.server!, p.token!, fcmToken: token, outageUpdates: outageUpdates);
    final old = _token;
    _token = token;
    await _save();
    if (old != null && old != token) {
      CloudSource.unregisterPush(p.server!, p.token!, old).ignore();
    }
    return sending;
  }

  Future<String> _busyWith(Future<String> Function() f) async {
    busy = true;
    notifyListeners();
    try {
      return await f();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Turns push on or off; returns what to tell the person. Throws with a
  /// message to show when the server can't be reached.
  Future<String> setEnabled(bool on) => _busyWith(() async {
    final p = _pairing!;
    if (!on) {
      enabled = false;
      final old = _token;
      _token = null;
      await _save();
      // Deleting the token stops notifications even if the server can't be
      // told now: its next send fails, and it forgets the phone.
      await platform.deleteToken().catchError((Object _) {});
      if (old != null) await CloudSource.unregisterPush(p.server!, p.token!, old).catchError((Object _) {});
      return 'Notifications are off';
    }
    if (!await platform.requestPermission()) {
      blocked = true;
      return 'Notifications are blocked for PowerPilot. Allow them in Android settings.';
    }
    blocked = false;
    enabled = true;
    try {
      if (!await _register()) return 'Registered, but the server has no Firebase key yet, so nothing arrives';
      await CloudSource.testPush(p.server!, p.token!, _token!);
      return 'Notifications are on: a test one is on its way';
    } on Object {
      enabled = false;
      await _save();
      rethrow;
    }
  });

  Future<String> setOutageUpdates(bool on) => _busyWith(() async {
    final before = outageUpdates;
    outageUpdates = on;
    try {
      await _register();
    } on Object {
      outageUpdates = before;
      rethrow;
    }
    return on ? 'Outage updates are on: every 5 minutes on battery' : 'Outage updates are off';
  });

  /// Unpairing: the server stops notifying this phone.
  Future<void> detach() async {
    final p = _pairing, old = _token;
    _pairing = null;
    enabled = false;
    _token = null;
    await _save();
    if (p != null && !p.demo && old != null) {
      await platform.deleteToken().catchError((Object _) {});
      await CloudSource.unregisterPush(p.server!, p.token!, old).timeout(const Duration(seconds: 10)).catchError((Object _) {});
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _foreground.close();
    _opened.close();
    super.dispose();
  }
}

enum AppPhase { loading, unpaired, ready }

class AppController extends ChangeNotifier with WidgetsBindingObserver {
  AppController({this.store = const PairingStore(), this.demoScenario, PushController? push})
    : push = push ?? PushController(platform: FirebasePushPlatform());

  final PairingStore store;

  /// Opens the demo in this scenario, whatever is saved (for development).
  final String? demoScenario;

  final PushController push;

  AppPhase phase = AppPhase.loading;
  Pairing? pairing;
  UpsController? ups;

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    await push.init();
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
    // In the background: registering with the server mustn't hold up the app.
    push.attach(pairing).ignore();
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
    push.attach(p).ignore();
  }

  Future<void> unpair() async {
    await push.detach();
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
    push.dispose();
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
