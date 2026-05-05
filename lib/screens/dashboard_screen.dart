import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../mqtt/mqtt_manager.dart';
import '../providers/position_provider.dart';
import 'anchor_setup_screen.dart';
import 'map_view.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('UWB Range Dashboard'),
          actions: [
            const _ConnectionBadge(),
            IconButton(
              tooltip: '앵커 설정',
              icon: const Icon(Icons.location_on_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const AnchorSetupScreen()),
              ),
            ),
            IconButton(
              tooltip: '연결 설정',
              icon: const Icon(Icons.settings),
              onPressed: () => context.read<PositionProvider>().disconnect(),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.map_outlined), text: 'Map'),
              Tab(icon: Icon(Icons.list_alt), text: 'Data'),
            ],
          ),
        ),
        body: Consumer<PositionProvider>(
          builder: (_, p, __) {
            return Column(
              children: [
                Container(
                  width: double.infinity,
                  color: p.isConnected
                      ? Colors.green.shade900
                      : Colors.red.shade900,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  child: Text(
                    'STATUS: ${p.status}   |   '
                    'anchors: ${p.anchors.length}   '
                    'tags: ${p.byTag.length}   '
                    'positioned: ${p.tagPositions.length}',
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
                const Expanded(
                  child: TabBarView(
                    children: [
                      MapView(),
                      _DataTab(),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DataTab extends StatelessWidget {
  const _DataTab();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PositionProvider>();
    if (p.latestBySrc.isEmpty) {
      return const Center(child: Text('대기 중… (uwb/range/+)'));
    }
    return Row(
      children: [
        Expanded(flex: 2, child: _AnchorList(latest: p.latestBySrc)),
        const VerticalDivider(width: 1),
        Expanded(flex: 3, child: _TagView(byTag: p.byTag)),
      ],
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge();

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<PositionProvider>().isConnected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.circle,
              size: 12, color: connected ? Colors.greenAccent : Colors.red),
          const SizedBox(width: 6),
          Text(connected ? 'CONNECTED' : 'OFFLINE'),
        ],
      ),
    );
  }
}

class _AnchorList extends StatelessWidget {
  const _AnchorList({required this.latest});
  final Map<String, RangeReading> latest;

  @override
  Widget build(BuildContext context) {
    final keys = latest.keys.toList()..sort();
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: keys.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = latest[keys[i]]!;
        return Card(
          child: ListTile(
            leading: CircleAvatar(child: Text(r.src)),
            title: Text('src=${r.src}  tag=${r.tagId}'),
            subtitle: Text(
              'mac=${r.mac}\n'
              'avg=${r.averageRange.toStringAsFixed(1)}  '
              'range=${r.ranges.join(",")}',
            ),
            trailing: Text(_age(r.receivedAt),
                style: const TextStyle(fontSize: 12)),
          ),
        );
      },
    );
  }

  String _age(DateTime t) {
    final ms = DateTime.now().difference(t).inMilliseconds;
    if (ms < 1000) return '${ms}ms';
    return '${(ms / 1000).toStringAsFixed(1)}s';
  }
}

class _TagView extends StatelessWidget {
  const _TagView({required this.byTag});
  final Map<int, Map<String, RangeReading>> byTag;

  @override
  Widget build(BuildContext context) {
    if (byTag.isEmpty) {
      return const Center(child: Text('태그 데이터 없음'));
    }
    final positions = context.watch<PositionProvider>().tagPositions;
    final tagIds = byTag.keys.toList()..sort();
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: tagIds.length,
      itemBuilder: (_, i) {
        final tagId = tagIds[i];
        final byAnchor = byTag[tagId]!;
        final entries = byAnchor.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        final pos = positions[tagId];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Tag #$tagId',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    if (pos != null)
                      Text(
                        '(${pos.dx.toStringAsFixed(1)}, '
                        '${pos.dy.toStringAsFixed(1)})',
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontFamily: 'monospace',
                        ),
                      )
                    else
                      const Text('위치 미산출',
                          style: TextStyle(color: Colors.white38)),
                  ],
                ),
                const SizedBox(height: 8),
                ...entries.map((e) {
                  final r = e.value;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                            width: 56,
                            child: Text(r.src,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold))),
                        Expanded(
                          child: Text(
                              'avg ${r.averageRange.toStringAsFixed(1)}'
                              '   [${r.ranges.join(", ")}]'),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}
