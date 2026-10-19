// Stand-ins so tests never reach the Keychain or Firebase: an unmocked
// platform channel can wait forever in a widget test.
import 'package:powerpilot/data/push.dart';
import 'package:powerpilot/state/controllers.dart';

class FakePushPlatform implements PushPlatform {
  FakePushPlatform({this.supported = true, this.allow = true});

  final bool supported;
  bool allow;
  String fcmToken = 'fcm_token_for_tests_0123456789';
  int deleted = 0;

  @override
  Future<bool> init() async => supported;

  @override
  Future<bool> requestPermission() async => allow;

  @override
  Future<String?> token() async => fcmToken;

  @override
  Stream<String> get tokenRefresh => const Stream.empty();

  @override
  Future<void> deleteToken() async => deleted++;

  @override
  Stream<PushMessage> get foreground => const Stream.empty();

  @override
  Stream<PushMessage> get opened => const Stream.empty();

  @override
  Future<PushMessage?> initialOpened() async => null;
}

class MemoryPushPrefs extends PushPrefsStore {
  MemoryPushPrefs();

  PushPrefs saved = const PushPrefs();

  @override
  Future<PushPrefs> load() async => saved;

  @override
  Future<void> save(PushPrefs p) async => saved = p;
}

/// A PushController on the fakes. Unsupported by default, as a build without
/// Firebase is.
PushController testPush({FakePushPlatform? platform}) =>
    PushController(platform: platform ?? FakePushPlatform(supported: false), prefs: MemoryPushPrefs());
