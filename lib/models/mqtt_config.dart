import 'package:shared_preferences/shared_preferences.dart';

class MqttConfig {
  const MqttConfig({
    required this.host,
    this.tcpPort = 1883,
    this.wsPort = 8884,
    this.wsPath = '/mqtt',
    this.useTls = true,
    this.topic = 'uwb/range/+',
  });

  final String host;
  final int tcpPort;
  final int wsPort;
  final String wsPath;
  final bool useTls;
  final String topic;

  static const defaults = MqttConfig(host: 'broker.hivemq.com');

  MqttConfig copyWith({
    String? host,
    int? tcpPort,
    int? wsPort,
    String? wsPath,
    bool? useTls,
    String? topic,
  }) {
    return MqttConfig(
      host: host ?? this.host,
      tcpPort: tcpPort ?? this.tcpPort,
      wsPort: wsPort ?? this.wsPort,
      wsPath: wsPath ?? this.wsPath,
      useTls: useTls ?? this.useTls,
      topic: topic ?? this.topic,
    );
  }

  static const _kHost = 'mqtt.host';
  static const _kTcpPort = 'mqtt.tcpPort';
  static const _kWsPort = 'mqtt.wsPort';
  static const _kWsPath = 'mqtt.wsPath';
  static const _kUseTls = 'mqtt.useTls';
  static const _kTopic = 'mqtt.topic';

  static Future<MqttConfig> load() async {
    final p = await SharedPreferences.getInstance();
    final host = p.getString(_kHost);
    if (host == null) return defaults;
    return MqttConfig(
      host: host,
      tcpPort: p.getInt(_kTcpPort) ?? defaults.tcpPort,
      wsPort: p.getInt(_kWsPort) ?? defaults.wsPort,
      wsPath: p.getString(_kWsPath) ?? defaults.wsPath,
      useTls: p.getBool(_kUseTls) ?? defaults.useTls,
      topic: p.getString(_kTopic) ?? defaults.topic,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kHost, host);
    await p.setInt(_kTcpPort, tcpPort);
    await p.setInt(_kWsPort, wsPort);
    await p.setString(_kWsPath, wsPath);
    await p.setBool(_kUseTls, useTls);
    await p.setString(_kTopic, topic);
  }
}
