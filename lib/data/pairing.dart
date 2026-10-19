// Pairing with powerpilot-server. The admin page hands out a link
// (PowerPilotHardware docs/cloud.md, "Pairing"):
//   powerpilot://pair?url=<server URL>&token=<token>[&device=<device ID>]
// Values are URL-encoded, in any order; unknown parameters are ignored.
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final _deviceId = RegExp(r'^[a-z0-9-]{1,32}$');

bool validDeviceId(String s) => _deviceId.hasMatch(s);

class PairingLink {
  const PairingLink({required this.server, required this.token, this.device});

  final Uri server;
  final String token;

  /// The UPS to open first, if the link names one.
  final String? device;

  /// Throws a [FormatException] whose message can be shown as is.
  static PairingLink parse(String text) {
    final link = Uri.tryParse(text.trim());
    if (link == null || link.scheme != 'powerpilot' || link.host != 'pair') {
      throw const FormatException("That isn't a PowerPilot pairing link. It starts with powerpilot://pair");
    }
    final q = link.queryParameters;
    final server = Uri.tryParse(q['url'] ?? '');
    if (server == null || server.host.isEmpty) {
      throw const FormatException('The link has no server address');
    }
    // The token travels with every request, so never in the clear.
    if (server.scheme != 'https') {
      throw const FormatException('The server address must start with https://');
    }
    final token = q['token'] ?? '';
    if (token.isEmpty) throw const FormatException('The link has no token');
    final device = q['device'];
    if (device != null && device.isNotEmpty && !validDeviceId(device)) {
      throw const FormatException('The link names a device ID that isn\'t valid');
    }
    return PairingLink(
      server: Uri(scheme: server.scheme, host: server.host, port: server.hasPort ? server.port : null, path: server.path),
      token: token,
      device: device == null || device.isEmpty ? null : device,
    );
  }
}

/// What this phone is paired with: a server and one of its UPSes, or the demo.
class Pairing {
  const Pairing.cloud({required Uri this.server, required String this.token, required String this.device}) : demo = false;
  const Pairing.demo() : demo = true, server = null, token = null, device = null;

  final bool demo;
  final Uri? server;
  final String? token;
  final String? device;

  String toJson() => jsonEncode(demo ? {'mode': 'demo'} : {'mode': 'cloud', 'url': server.toString(), 'token': token, 'device': device});

  static Pairing? fromJson(String? text) {
    if (text == null) return null;
    try {
      final j = jsonDecode(text) as Map<String, dynamic>;
      if (j['mode'] == 'demo') return const Pairing.demo();
      final url = Uri.tryParse(j['url'] as String? ?? '');
      final token = j['token'] as String? ?? '';
      final device = j['device'] as String? ?? '';
      if (url == null || token.isEmpty || !validDeviceId(device)) return null;
      return Pairing.cloud(server: url, token: token, device: device);
    } on Object {
      return null;
    }
  }
}

/// Keeps the pairing in the Keychain (iOS) or the Keystore (Android).
class PairingStore {
  const PairingStore([
    this._storage = const FlutterSecureStorage(iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device)),
  ]);

  final FlutterSecureStorage _storage;
  static const _key = 'pairing';

  Future<Pairing?> load() async => Pairing.fromJson(await _storage.read(key: _key));

  Future<void> save(Pairing p) => _storage.write(key: _key, value: p.toJson());

  Future<void> clear() => _storage.delete(key: _key);
}
