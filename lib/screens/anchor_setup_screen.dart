import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/anchor.dart';
import '../providers/position_provider.dart';

class AnchorSetupScreen extends StatefulWidget {
  const AnchorSetupScreen({super.key});

  @override
  State<AnchorSetupScreen> createState() => _AnchorSetupScreenState();
}

class _AnchorSetupScreenState extends State<AnchorSetupScreen> {
  late List<_Row> _rows;

  @override
  void initState() {
    super.initState();
    final initial = context.read<PositionProvider>().anchors;
    _rows = initial.isEmpty
        ? [_Row.empty('A0'), _Row.empty('A1'), _Row.empty('A2')]
        : initial.map(_Row.fromAnchor).toList();
  }

  void _add() {
    setState(() => _rows.add(_Row.empty('A${_rows.length}')));
  }

  void _remove(int i) {
    setState(() => _rows.removeAt(i));
  }

  /// 저장 시도. 성공하면 true, 검증 실패면 false (snackbar로 안내).
  Future<bool> _trySave() async {
    final list = <Anchor>[];
    for (final r in _rows) {
      final src = r.src.text.trim();
      final x = double.tryParse(r.x.text);
      final y = double.tryParse(r.y.text);
      final calText = r.cal.text.trim();
      final cal = calText.isEmpty ? 0.0 : double.tryParse(calText);
      // index: 직접 입력값 우선, 비어있으면 src 끝 숫자에서 자동 추출
      final idxText = r.index.text.trim();
      int? index = idxText.isNotEmpty
          ? int.tryParse(idxText)
          : Anchor.indexFromSrc(src);
      if (src.isEmpty || x == null || y == null || index == null || cal == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('빈 칸 또는 숫자가 아닌 값이 있습니다')),
        );
        return false;
      }
      if (index < 0 || index > 7) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('index는 0~7 사이여야 합니다 (range[8] 인덱스)')),
        );
        return false;
      }
      list.add(Anchor(src: src, index: index, x: x, y: y, calibration: cal));
    }
    final srcs = list.map((a) => a.src).toSet();
    final indices = list.map((a) => a.index).toSet();
    if (srcs.length != list.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('src가 중복됩니다')),
      );
      return false;
    }
    if (indices.length != list.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('index가 중복됩니다')),
      );
      return false;
    }
    await context.read<PositionProvider>().setAnchors(list);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${list.length}개 앵커 저장됨'),
          duration: const Duration(milliseconds: 1200),
        ),
      );
    }
    return true;
  }

  Future<void> _saveAndClose() async {
    if (await _trySave() && mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        // 시스템/앱바 뒤로가기 시 자동 저장. 검증 실패면 화면에 머무름.
        if (didPop) return;
        final ok = await _trySave();
        if (ok && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('앵커 좌표 설정'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '앵커 추가',
            onPressed: _add,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.save),
        label: const Text('저장하고 닫기'),
        onPressed: _saveAndClose,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  '단위는 디바이스가 보내는 range 단위와 동일하게 입력하세요. '
                  '(예: range가 cm면 좌표도 cm)\n'
                  '최소 3개 앵커가 등록되어야 위치 계산이 동작합니다.',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Text('등록된 앵커: ${_rows.length}'),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: _add,
                      icon: const Icon(Icons.add),
                      label: const Text('앵커 추가'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: _rows.length,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final r = _rows[i];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: r.src,
                                decoration: const InputDecoration(
                                    labelText: 'src (예: A0)'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 60,
                              child: TextField(
                                controller: r.index,
                                decoration: const InputDecoration(
                                  labelText: 'idx',
                                  helperText: '0~7',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: r.x,
                                decoration:
                                    const InputDecoration(labelText: 'X'),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        signed: true, decimal: true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: r.y,
                                decoration:
                                    const InputDecoration(labelText: 'Y'),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        signed: true, decimal: true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: r.cal,
                                decoration: const InputDecoration(
                                  labelText: 'cal',
                                  helperText: '+ / -',
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        signed: true, decimal: true),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _remove(i),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class _Row {
  _Row(this.src, this.index, this.x, this.y, this.cal);
  factory _Row.empty(String defaultSrc) {
    final idx = Anchor.indexFromSrc(defaultSrc);
    return _Row(
      TextEditingController(text: defaultSrc),
      TextEditingController(text: idx?.toString() ?? ''),
      TextEditingController(text: '0'),
      TextEditingController(text: '0'),
      TextEditingController(text: '0'),
    );
  }
  factory _Row.fromAnchor(Anchor a) => _Row(
        TextEditingController(text: a.src),
        TextEditingController(text: a.index.toString()),
        TextEditingController(text: a.x.toString()),
        TextEditingController(text: a.y.toString()),
        TextEditingController(text: a.calibration.toString()),
      );

  final TextEditingController src;
  final TextEditingController index;
  final TextEditingController x;
  final TextEditingController y;
  final TextEditingController cal;

  void dispose() {
    src.dispose();
    index.dispose();
    x.dispose();
    y.dispose();
    cal.dispose();
  }
}
