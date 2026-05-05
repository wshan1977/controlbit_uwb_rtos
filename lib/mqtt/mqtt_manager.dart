import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../models/mqtt_config.dart';

class RangeReading {
  RangeReading({
    required this.src,
    required this.mac,
    required this.tagId,
    required this.ranges,
    required this.receivedAt,
  });

  final String src;
  final String mac;
  final int tagId;
  final List<int> ranges;
  final DateTime receivedAt;

  double get averageRange {
    if (ranges.isEmpty) return 0;
    return ranges.reduce((a, b) => a + b) / ranges.length;
  }
}

typedef RangeHandler = void Function(RangeReading reading);
typedef StatusHandler = void Function(String status);

class MqttManager {
  MqttManager(this.config, {String? clientId})
      : clientId = clientId ??
            'rtls_dashboard_${DateTime.now().millisecondsSinceEpoch}';

  final MqttConfig config;
  final String clientId;

  late MqttClient _client;
  RangeHandler? _onRange;
  StatusHandler? _onStatus;
  StreamSubscription? _sub;
  String _lastStatus = 'idle';

  String get status => _lastStatus;
  bool get isConnected =>
      _client.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connect({
    RangeHandler? onRange,
    StatusHandler? onStatus,
  }) async {
    _onRange = onRange;
    _onStatus = onStatus;
    _client = _buildClient();
    _client.logging(on: true);
    _client.setProtocolV311();
    _client.keepAlivePeriod = 20;
    _client.autoReconnect = true;
    _client.onConnected = _onConnected;
    _client.onDisconnected = _onDisconnected;
    _client.onSubscribed = (t) => _setStatus('subscribed: $t');
    _client.onSubscribeFail = (t) => _setStatus('subscribe FAIL: $t');

    // MQTT 3.1.1 (ProtocolName="MQTT", Version=4) — HiveMQ가 요구.
    // setProtocolV311()만 부르고 ConnectMessage를 새로 만들면 기본값(MQIsdp v3)
    // 으로 덮어써져서 CONNACK 없이 끊김. 그래서 메시지에도 직접 명시한다.
    final connMsg = MqttConnectMessage()
        .withProtocolName('MQTT')
        .withProtocolVersion(4)
        .withClientIdentifier(clientId)
        .startClean();
    _client.connectionMessage = connMsg;

    final scheme = config.useTls ? 'wss' : 'ws';
    final endpoint = kIsWeb
        ? '$scheme://${config.host}:${config.wsPort}${config.wsPath}'
        : '${config.useTls ? "ssl" : "tcp"}://${config.host}:${config.tcpPort}';
    _setStatus('connecting → $endpoint');

    try {
      await _client.connect();
      _setStatus(
          'connect() returned (state=${_client.connectionStatus?.state})');
    } catch (e, st) {
      _setStatus('connect ERROR: $e');
      debugPrint('[MQTT] connect error: $e\n$st');
      _client.disconnect();
    }
  }

  MqttClient _buildClient() {
    if (kIsWeb) {
      final scheme = config.useTls ? 'wss' : 'ws';
      final url = '$scheme://${config.host}${config.wsPath}';
      final c = MqttBrowserClient.withPort(url, clientId, config.wsPort);
      c.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
      return c;
    }
    final c = MqttServerClient(config.host, clientId);
    c.port = config.tcpPort;
    c.secure = config.useTls;
    return c;
  }

  void _onConnected() {
    _setStatus('connected, subscribing → ${config.topic}');
    _client.subscribe(config.topic, MqttQos.atMostOnce);
    _sub?.cancel();
    _sub = _client.updates?.listen(_handleMessages);
  }

  void _onDisconnected() {
    _setStatus('disconnected');
    _sub?.cancel();
    _sub = null;
  }

  void _setStatus(String s) {
    _lastStatus = s;
    debugPrint('[MQTT] $s');
    _onStatus?.call(s);
  }

  void _handleMessages(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final recMess = event.payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(
        recMess.payload.message,
      );
      debugPrint('[MQTT] ${event.topic}: $payload');
      final reading = _parse(event.topic, payload);
      if (reading != null) _onRange?.call(reading);
    }
  }

  RangeReading? _parse(String topic, String payload) {
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final topicSrc = topic.split('/').last;
      final srcRaw = (data['src'] as String?) ?? topicSrc;
      final mac = (data['mac'] as String?) ?? '';
      final tagId = (data['id'] as num?)?.toInt();
      final rangesAny = data['range'];
      if (tagId == null || rangesAny is! List) return null;

      final ranges =
          rangesAny.map((v) => (v as num).toInt()).toList(growable: false);
      if (ranges.length != 8) return null;

      return RangeReading(
        src: srcRaw,
        mac: mac,
        tagId: tagId,
        ranges: ranges,
        receivedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[MQTT] parse error: $e');
      return null;
    }
  }

  void disconnect() {
    _sub?.cancel();
    _sub = null;
    try {
      _client.disconnect();
    } catch (_) {}
  }
}
