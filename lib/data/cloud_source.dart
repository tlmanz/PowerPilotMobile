// powerpilot-server's app API (PowerPilotHardware server/README.md): PowerPilot's
// local API per device under /api/devices/{d}, behind a bearer token, with a
// server-sent event stream for live updates.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../models/ups.dart';
import 'source.dart';

class ApiError implements Exception {
  const ApiError(this.message, {this.status = 0});
  final String message;
  final int status;

  @override
  String toString() => message;
}

/// One server-sent event.
class SseMessage {
  const SseMessage(this.event, this.data);
  final String event, data;
}

/// Splits an event stream's lines into messages: `data:` lines up to a blank
/// line make one; lines starting with ':' are comments, such as the pings.
Stream<SseMessage> parseSse(Stream<String> lines) async* {
  String? event;
  final data = <String>[];
  await for (final line in lines) {
    if (line.isEmpty) {
      if (data.isNotEmpty) yield SseMessage(event ?? 'message', data.join('\n'));
      event = null;
      data.clear();
      continue;
    }
    if (line.startsWith(':')) continue;
    final i = line.indexOf(':');
    final field = i < 0 ? line : line.substring(0, i);
    var value = i < 0 ? '' : line.substring(i + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    if (field == 'data') {
      data.add(value);
    } else if (field == 'event') {
      event = value;
    }
  }
}

/// Words a failed request for a person, not a log.
String describeError(Object e) => switch (e) {
  ApiError() => e.message,
  HandshakeException() => "The server's certificate isn't trusted",
  SocketException() => "Can't reach the server. Check this phone's connection.",
  TimeoutException() => "The server didn't answer in time",
  HttpException() => 'The connection to the server dropped',
  _ => e.toString(),
};

class ApiClient {
  ApiClient(this.server, this._token)
    : _http = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15)
        ..idleTimeout = const Duration(seconds: 30);

  final Uri server;
  final String _token;
  final HttpClient _http;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = server.path.endsWith('/') ? server.path.substring(0, server.path.length - 1) : server.path;
    return server.replace(path: '$base$path', queryParameters: query);
  }

  Future<HttpClientResponse> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    String accept = 'application/json',
  }) async {
    final req = await _http.openUrl(method, _uri(path, query));
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
    req.headers.set(HttpHeaders.acceptHeader, accept);
    if (body != null) {
      // The server takes only JSON bodies, even an empty one.
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    return req.close();
  }

  static String _errorText(int status, Object? data) {
    final msg = data is Map && data['error'] is String ? data['error'] as String : '';
    return switch (status) {
      401 => "The server doesn't know this phone's token. It may have been revoked: pair again.",
      403 => "This token can't read devices. Pair with a phone token from the admin page.",
      404 when msg == 'no such device' => "The server doesn't know this UPS",
      _ => msg.isNotEmpty ? msg[0].toUpperCase() + msg.substring(1) : 'The server answered $status',
    };
  }

  Future<String> _read(HttpClientResponse res, Duration timeout) => res.transform(utf8.decoder).join().timeout(timeout);

  Future<Object?> json(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final res = await _send(method, path, body: body, query: query).timeout(timeout);
    final text = await _read(res, timeout);
    Object? data;
    try {
      data = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      data = null;
    }
    if (res.statusCode >= 300) throw ApiError(_errorText(res.statusCode, data), status: res.statusCode);
    return data;
  }

  Future<String> text(String path, {Map<String, String>? query, Duration timeout = const Duration(seconds: 60)}) async {
    final res = await _send('GET', path, query: query, accept: 'text/csv').timeout(timeout);
    final text = await _read(res, timeout);
    if (res.statusCode >= 300) {
      Object? data;
      try {
        data = jsonDecode(text);
      } on FormatException {
        data = null;
      }
      throw ApiError(_errorText(res.statusCode, data), status: res.statusCode);
    }
    return text;
  }

  /// Opens an event stream. The server pings every 25 s, so a minute of
  /// silence means the connection is gone even if the socket doesn't say so.
  Future<Stream<SseMessage>> events(String path) async {
    final res = await _send('GET', path, accept: 'text/event-stream').timeout(const Duration(seconds: 20));
    if (res.statusCode >= 300) {
      final text = await _read(res, const Duration(seconds: 10));
      Object? data;
      try {
        data = jsonDecode(text);
      } on FormatException {
        data = null;
      }
      throw ApiError(_errorText(res.statusCode, data), status: res.statusCode);
    }
    final lines = res.transform(utf8.decoder).transform(const LineSplitter()).timeout(const Duration(seconds: 60));
    return parseSse(lines);
  }

  void close() => _http.close(force: true);
}

class CloudSource implements UpsSource {
  CloudSource({required this.server, required this._token, required this.deviceId});

  final Uri server;
  final String _token;
  final String deviceId;

  ApiClient? _api;
  SourceSink? _sink;
  int _generation = 0;

  String get _base => '/api/devices/$deviceId';

  ApiClient get _client => _api ??= ApiClient(server, _token);

  /// Every UPS the token can see: pairing checks the token with this.
  static Future<List<DeviceSummary>> devices(Uri server, String token) async {
    final api = ApiClient(server, token);
    try {
      final data = await api.json('GET', '/api/devices');
      return [
        for (final d in (data as List? ?? const []))
          if (d is Map<String, dynamic>) DeviceSummary.fromJson(d),
      ];
    } finally {
      api.close();
    }
  }

  @override
  String get label => deviceId;

  @override
  bool get isDemo => false;

  @override
  void start(SourceSink sink) {
    _sink = sink;
    _run(++_generation);
  }

  @override
  void stop() {
    _generation++;
    _api?.close();
    _api = null;
  }

  /// Loads the state, then follows the stream; on any failure, waits and
  /// starts over, backing off to 30 s. Loading again after a reconnect resyncs
  /// whatever the stream missed, as PowerPilot's live source does.
  Future<void> _run(int gen) async {
    var backoff = const Duration(seconds: 1);
    while (gen == _generation) {
      try {
        final st = await _client.json('GET', '$_base/state');
        if (gen != _generation) return;
        _sink?.onState(DeviceState.fromJson(st as Map<String, dynamic>));
        final stream = await _client.events('$_base/stream');
        if (gen != _generation) return;
        _sink?.onLink(true);
        backoff = const Duration(seconds: 1);
        await for (final m in stream) {
          if (gen != _generation) return;
          final data = jsonDecode(m.data);
          if (data is Map<String, dynamic>) _sink?.onUpdate(StreamUpdate.fromJson(data));
        }
        if (gen != _generation) return;
        _sink?.onLink(false, 'The connection to the server dropped');
      } catch (e) {
        if (gen != _generation) return;
        _sink?.onLink(false, describeError(e));
        // A dead client stays dead: start the next try on a fresh one.
        _api?.close();
        _api = null;
      }
      await Future<void>.delayed(backoff);
      backoff = Duration(seconds: math.min(backoff.inSeconds * 2, 30));
    }
  }

  @override
  Future<String> command(String id, {double minutes = 0, int restoreAfter = 0}) async {
    // The server waits up to 90 s for the device before giving up.
    final data = await _client.json(
      'POST',
      '$_base/command',
      body: {'id': id, if (minutes > 0) 'minutes': minutes, if (restoreAfter > 0) 'restore_after': restoreAfter},
      timeout: const Duration(seconds: 100),
    );
    return data is Map && data['sent'] is String ? data['sent'] as String : '';
  }

  @override
  Future<UpsSettings> saveSettings(UpsSettings settings) async {
    final data = await _client.json('PUT', '$_base/settings', body: settings.toJson());
    return UpsSettings.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<void> refresh() => _client.json('POST', '$_base/refresh', body: const <String, Object>{});

  @override
  Future<List<LogDay>> logDays() async {
    final data = await _client.json('GET', '$_base/logs');
    final days = data is Map ? data['days'] : null;
    return [
      for (final d in (days as List? ?? const []))
        if (d is Map<String, dynamic>) LogDay.fromJson(d),
    ];
  }

  @override
  Future<List<UpsEvent>> logEvents(String date) async {
    final data = await _client.json('GET', '$_base/logs/events', query: {'date': date});
    return [
      for (final e in (data as List? ?? const []))
        if (e is Map<String, dynamic>) UpsEvent.fromJson(e),
    ];
  }

  @override
  Future<List<Reading>> logReadings(String date) async {
    final data = await _client.json('GET', '$_base/logs/readings', query: {'date': date});
    return [
      for (final r in (data as List? ?? const []))
        if (r is Map<String, dynamic>) Reading.fromJson(r),
    ];
  }

  @override
  Future<String> exportCsv(String kind, String from, String to) =>
      _client.text('$_base/logs/export', query: {'kind': kind, 'from': from, 'to': to});
}
