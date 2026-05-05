import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/position_provider.dart';
import 'screens/connection_screen.dart';
import 'screens/dashboard_screen.dart';

void main() {
  runApp(const RtlsApp());
}

class RtlsApp extends StatelessWidget {
  const RtlsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PositionProvider(),
      child: MaterialApp(
        title: 'RTLS Dashboard',
        theme: ThemeData.dark(useMaterial3: true),
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PositionProvider>();
    // config가 설정돼 있으면 대시보드, 아니면 연결 화면
    if (p.config == null) return const ConnectionScreen();
    return const DashboardScreen();
  }
}
