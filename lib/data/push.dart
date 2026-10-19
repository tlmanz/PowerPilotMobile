// Push notifications. powerpilot-server sends them through Firebase Cloud
// Messaging (its internal/push); the phone only asks permission and hands the
// server its FCM token. Android only for now.
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PushMessage {
  const PushMessage({required this.title, required this.body, this.kind, this.device});

  final String title, body;

  /// The server's data: the event kind, and the UPS it's about.
  final String? kind, device;
}

/// The phone's side of push: Firebase, or nothing (tests, other platforms).
abstract interface class PushPlatform {
  /// Whether this build can do push: Android, with Firebase's config.
  Future<bool> init();

  /// Asks for permission when needed (Android 13+); true when allowed.
  Future<bool> requestPermission();

  Future<String?> token();
  Stream<String> get tokenRefresh;

  /// Invalidates this phone's token, so nothing sent to it arrives, even if
  /// the server never hears that push was turned off.
  Future<void> deleteToken();

  /// A notification that arrived while the app was open, which Android
  /// doesn't show by itself.
  Stream<PushMessage> get foreground;

  /// A notification that was tapped while the app was in the background.
  Stream<PushMessage> get opened;

  /// The notification whose tap started the app, if any.
  Future<PushMessage?> initialOpened();
}

class FirebasePushPlatform implements PushPlatform {
  bool _ready = false;

  static PushMessage _from(RemoteMessage m) => PushMessage(
    title: m.notification?.title ?? 'PowerPilot',
    body: m.notification?.body ?? '',
    kind: m.data['kind'] as String?,
    device: m.data['device'] as String?,
  );

  @override
  Future<bool> init() async {
    if (!Platform.isAndroid) return false;
    try {
      // Reads google-services.json, compiled in by its Gradle plugin; a build
      // without it has no Firebase app, and this throws.
      await Firebase.initializeApp();
      _ready = true;
    } on Object {
      _ready = false;
    }
    return _ready;
  }

  @override
  Future<bool> requestPermission() async {
    final s = await FirebaseMessaging.instance.requestPermission();
    return s.authorizationStatus == AuthorizationStatus.authorized || s.authorizationStatus == AuthorizationStatus.provisional;
  }

  // The registration token, which the server sends to through FCM HTTP v1's
  // `message.token`. firebase_messaging 17 deprecates these for register()'s
  // installation IDs, a different send target; keep the token until the
  // server moves too.

  @override
  // ignore: deprecated_member_use
  Future<String?> token() => FirebaseMessaging.instance.getToken();

  @override
  // ignore: deprecated_member_use
  Stream<String> get tokenRefresh => _ready ? FirebaseMessaging.instance.onTokenRefresh : const Stream.empty();

  @override
  Future<void> deleteToken() async {
    // ignore: deprecated_member_use
    if (_ready) await FirebaseMessaging.instance.deleteToken();
  }

  @override
  Stream<PushMessage> get foreground => _ready ? FirebaseMessaging.onMessage.map(_from) : const Stream.empty();

  @override
  Stream<PushMessage> get opened => _ready ? FirebaseMessaging.onMessageOpenedApp.map(_from) : const Stream.empty();

  @override
  Future<PushMessage?> initialOpened() async {
    if (!_ready) return null;
    final m = await FirebaseMessaging.instance.getInitialMessage();
    return m == null ? null : _from(m);
  }
}

/// What the phone chose, and the FCM token it last registered.
class PushPrefs {
  const PushPrefs({this.enabled = false, this.outageUpdates = false, this.token});

  final bool enabled, outageUpdates;
  final String? token;
}

/// Keeps the push choices with the pairing, in the Keychain or Keystore.
class PushPrefsStore {
  const PushPrefsStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;
  static const _key = 'push';

  Future<PushPrefs> load() async {
    try {
      final j = jsonDecode(await _storage.read(key: _key) ?? '{}') as Map<String, dynamic>;
      return PushPrefs(enabled: j['enabled'] == true, outageUpdates: j['outage_updates'] == true, token: j['token'] as String?);
    } on Object {
      // Unreadable (or no storage, as in tests): start with push off.
      return const PushPrefs();
    }
  }

  Future<void> save(PushPrefs p) =>
      _storage.write(key: _key, value: jsonEncode({'enabled': p.enabled, 'outage_updates': p.outageUpdates, 'token': p.token}));
}
