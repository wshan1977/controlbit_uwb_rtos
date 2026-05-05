import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/mqtt_config.dart';
import '../providers/position_provider.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _host;
  late TextEditingController _tcpPort;
  late TextEditingController _wsPort;
  late TextEditingController _wsPath;
  late TextEditingController _topic;
  bool _useTls = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _host = TextEditingController();
    _tcpPort = TextEditingController();
    _wsPort = TextEditingController();
    _wsPath = TextEditingController();
    _topic = TextEditingController();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final cfg = await MqttConfig.load();
    if (!mounted) return;
    setState(() {
      _host.text = cfg.host;
      _tcpPort.text = cfg.tcpPort.toString();
      _wsPort.text = cfg.wsPort.toString();
      _wsPath.text = cfg.wsPath;
      _topic.text = cfg.topic;
      _useTls = cfg.useTls;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _host.dispose();
    _tcpPort.dispose();
    _wsPort.dispose();
    _wsPath.dispose();
    _topic.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    final cfg = MqttConfig(
      host: _host.text.trim(),
      tcpPort: int.parse(_tcpPort.text),
      wsPort: int.parse(_wsPort.text),
      wsPath: _wsPath.text.trim(),
      useTls: _useTls,
      topic: _topic.text.trim(),
    );
    await cfg.save();
    if (!mounted) return;
    await context.read<PositionProvider>().connect(cfg);
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? '필수' : null;

  String? _port(String? v) {
    if (v == null || v.isEmpty) return '필수';
    final n = int.tryParse(v);
    if (n == null || n <= 0 || n > 65535) return '1-65535';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('MQTT 연결 설정')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _host,
                    decoration: const InputDecoration(
                      labelText: 'Host',
                      hintText: 'broker.hivemq.com',
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _tcpPort,
                          decoration: const InputDecoration(
                            labelText: 'TCP Port (모바일/데스크톱)',
                          ),
                          keyboardType: TextInputType.number,
                          validator: _port,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _wsPort,
                          decoration: const InputDecoration(
                            labelText: 'WS Port (웹)',
                          ),
                          keyboardType: TextInputType.number,
                          validator: _port,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _wsPath,
                    decoration: const InputDecoration(
                      labelText: 'WS Path',
                      hintText: '/mqtt',
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _topic,
                    decoration: const InputDecoration(
                      labelText: 'Topic',
                      hintText: 'uwb/range/+',
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('TLS 사용 (wss / ssl)'),
                    subtitle: const Text(
                        'HiveMQ 공용 브로커는 보통 TLS(8884) 권장'),
                    value: _useTls,
                    onChanged: (v) => setState(() => _useTls = v),
                  ),
                  const SizedBox(height: 24),
                  Consumer<PositionProvider>(
                    builder: (_, p, __) {
                      final connecting = p.status.startsWith('connecting');
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton.icon(
                            onPressed: connecting ? null : _connect,
                            icon: connecting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.link),
                            label: Text(connecting ? '연결 중…' : 'Connect'),
                          ),
                          if (p.status != 'idle') ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'STATUS: ${p.status}',
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 12),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
