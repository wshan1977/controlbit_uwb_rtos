import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/anchor.dart';
import '../mqtt/mqtt_manager.dart';
import '../providers/position_provider.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final TransformationController _ctrl = TransformationController();
  bool _showDistances = true;
  bool _editMode = false;

  /// 드래그 중일 때만 non-null. 저장된 앵커 리스트의 사본을 임시 보관.
  List<Anchor>? _draftAnchors;
  int? _draggingIndex;

  void _zoom(double factor) {
    final m = Matrix4.copy(_ctrl.value)..scale(factor);
    _ctrl.value = m;
  }

  void _fit() {
    _ctrl.value = Matrix4.identity();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PositionProvider>();
    final originalAnchors = p.anchors;
    if (originalAnchors.length < 3) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '앵커가 ${originalAnchors.length}개 등록됐습니다. '
            '위치 계산을 위해선 최소 3개가 필요합니다.\n\n'
            '상단 📍 아이콘으로 좌표를 등록하세요.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    final displayAnchors = _draftAnchors ?? originalAnchors;

    return LayoutBuilder(
      builder: (context, constraints) {
        // bbox는 항상 "저장된" 앵커 기준으로 잠가둠. 드래그 중에도 스케일이 안 바뀌어
        // 다른 앵커들이 떨리지 않고, 드래그 중인 앵커만 커서 따라 움직인다.
        double minX = double.infinity, maxX = -double.infinity;
        double minY = double.infinity, maxY = -double.infinity;
        for (final a in originalAnchors) {
          if (a.x < minX) minX = a.x;
          if (a.x > maxX) maxX = a.x;
          if (a.y < minY) minY = a.y;
          if (a.y > maxY) maxY = a.y;
        }
        if (maxX - minX < 1) {
          minX -= 1;
          maxX += 1;
        }
        if (maxY - minY < 1) {
          minY -= 1;
          maxY += 1;
        }
        const padding = 80.0;
        final w = constraints.maxWidth - padding * 2;
        final h = constraints.maxHeight - padding * 2;
        final scale = (w / (maxX - minX)) < (h / (maxY - minY))
            ? w / (maxX - minX)
            : h / (maxY - minY);

        Offset toScreen(double x, double y) => Offset(
              padding + (x - minX) * scale,
              constraints.maxHeight - padding - (y - minY) * scale,
            );

        int? hitTestIndex(Offset local) {
          // localPosition은 GestureDetector(InteractiveViewer 자식) 안의 좌표라
          // InteractiveViewer 변환은 이미 빠진 child-space 좌표.
          for (int i = 0; i < displayAnchors.length; i++) {
            final a = displayAnchors[i];
            final sp = toScreen(a.x, a.y);
            if ((sp - local).distance <= 18) return i;
          }
          return null;
        }

        return Stack(
          children: [
            InteractiveViewer(
              transformationController: _ctrl,
              minScale: 0.1,
              maxScale: 20,
              panEnabled: !_editMode, // 편집 모드일 때 InteractiveViewer 팬 비활성
              boundaryMargin: const EdgeInsets.all(2000),
              child: SizedBox.expand(
                child: GestureDetector(
                  onPanStart: !_editMode
                      ? null
                      : (d) {
                          final idx = hitTestIndex(d.localPosition);
                          if (idx != null) {
                            setState(() {
                              _draftAnchors = List.of(originalAnchors);
                              _draggingIndex = idx;
                            });
                          }
                        },
                  onPanUpdate: !_editMode
                      ? null
                      : (d) {
                          if (_draggingIndex == null) return;
                          // 화면 delta → world delta. y축은 화면이 아래가 +라
                          // world 좌표(위가 +)로 변환할 때 부호 반전.
                          final viewScale = _ctrl.value.getMaxScaleOnAxis();
                          final dx = d.delta.dx / scale / viewScale;
                          final dy = -d.delta.dy / scale / viewScale;
                          setState(() {
                            final a = _draftAnchors![_draggingIndex!];
                            _draftAnchors![_draggingIndex!] = a.copyWith(
                              x: a.x + dx,
                              y: a.y + dy,
                            );
                          });
                        },
                  onPanEnd: !_editMode
                      ? null
                      : (_) {
                          if (_draggingIndex == null || _draftAnchors == null) {
                            return;
                          }
                          final draft = _draftAnchors!;
                          // 드래그 끝 → 저장 (자동 _recomputeAll)
                          context
                              .read<PositionProvider>()
                              .setAnchors(draft);
                          setState(() {
                            _draftAnchors = null;
                            _draggingIndex = null;
                          });
                        },
                  child: MouseRegion(
                    cursor: _editMode
                        ? SystemMouseCursors.move
                        : SystemMouseCursors.basic,
                    child: CustomPaint(
                      painter: _MapPainter(
                        anchors: displayAnchors,
                        tagPositions: p.tagPositions,
                        latestPerTag: p.latestPerTag,
                        showDistances: _showDistances,
                        bboxMinX: minX,
                        bboxMinY: minY,
                        bboxMaxX: maxX,
                        bboxMaxY: maxY,
                        editMode: _editMode,
                        draggingIndex: _draggingIndex,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 우상단 토글들
            Positioned(
              right: 12,
              top: 12,
              child: Material(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('거리 표시',
                              style: TextStyle(fontSize: 12)),
                          Switch(
                            value: _showDistances,
                            onChanged: (v) =>
                                setState(() => _showDistances = v),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('앵커 이동',
                              style: TextStyle(fontSize: 12)),
                          Switch(
                            value: _editMode,
                            onChanged: (v) {
                              setState(() {
                                _editMode = v;
                                if (!v) {
                                  _draftAnchors = null;
                                  _draggingIndex = null;
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 우하단 줌
            Positioned(
              right: 12,
              bottom: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'zin',
                    tooltip: '확대',
                    onPressed: () => _zoom(1.25),
                    child: const Icon(Icons.add),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'zout',
                    tooltip: '축소',
                    onPressed: () => _zoom(0.8),
                    child: const Icon(Icons.remove),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'zfit',
                    tooltip: '원래대로',
                    onPressed: _fit,
                    child: const Icon(Icons.center_focus_strong),
                  ),
                ],
              ),
            ),
            if (p.byTag.isNotEmpty &&
                p.tagPositions.length < p.byTag.length)
              Positioned(
                left: 12,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '위치 미산출 태그 ${p.byTag.length - p.tagPositions.length}개',
                    style: const TextStyle(
                        color: Colors.amberAccent, fontSize: 11),
                  ),
                ),
              ),
            if (_editMode)
              Positioned(
                left: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '편집 모드: 앵커를 잡고 드래그하면 좌표가 변경됩니다',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.anchors,
    required this.tagPositions,
    required this.latestPerTag,
    required this.showDistances,
    required this.bboxMinX,
    required this.bboxMinY,
    required this.bboxMaxX,
    required this.bboxMaxY,
    required this.editMode,
    required this.draggingIndex,
  });

  final List<Anchor> anchors;
  final Map<int, Offset> tagPositions;
  final Map<int, RangeReading> latestPerTag;
  final bool showDistances;
  final double bboxMinX, bboxMinY, bboxMaxX, bboxMaxY;
  final bool editMode;
  final int? draggingIndex;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF101418),
    );
    if (anchors.isEmpty) return;

    const padding = 80.0;
    final w = size.width - padding * 2;
    final h = size.height - padding * 2;
    final dx = bboxMaxX - bboxMinX;
    final dy = bboxMaxY - bboxMinY;
    final scale = (w / dx) < (h / dy) ? w / dx : h / dy;

    Offset toScreen(double x, double y) => Offset(
          padding + (x - bboxMinX) * scale,
          size.height - padding - (y - bboxMinY) * scale,
        );

    _drawGrid(canvas, size, scale, padding);
    _drawAxes(canvas, size, padding);

    if (showDistances) {
      final linePaint = Paint()
        ..color = Colors.cyanAccent.withValues(alpha: 0.5)
        ..strokeWidth = 1.5;
      for (final tagEntry in tagPositions.entries) {
        final tagId = tagEntry.key;
        final tagPos = toScreen(tagEntry.value.dx, tagEntry.value.dy);
        final reading = latestPerTag[tagId];
        if (reading == null) continue;
        for (final a in anchors) {
          if (a.index < 0 || a.index >= reading.ranges.length) continue;
          final raw = reading.ranges[a.index];
          if (raw <= 0 || raw >= 1000) continue;
          final calibrated = raw + a.calibration;
          if (calibrated <= 0) continue;
          final ancPos = toScreen(a.x, a.y);
          _drawDashedLine(canvas, ancPos, tagPos, linePaint);
          final label = a.calibration == 0
              ? raw.toString()
              : '${calibrated.toStringAsFixed(0)} (raw $raw)';
          _drawDistanceLabel(canvas, ancPos, tagPos, label);
        }
      }
    }

    // 앵커
    final ancFill = Paint()..color = Colors.blueAccent;
    for (int i = 0; i < anchors.length; i++) {
      final a = anchors[i];
      final p = toScreen(a.x, a.y);
      final isDragging = i == draggingIndex;
      final ancStroke = Paint()
        ..color = isDragging
            ? Colors.amberAccent
            : (editMode ? Colors.greenAccent : Colors.white)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isDragging ? 3 : 2;
      final rect = Rect.fromCenter(center: p, width: 16, height: 16);
      canvas.drawRect(rect, ancFill);
      canvas.drawRect(rect, ancStroke);
      _label(
        canvas,
        '${a.src}[${a.index}] '
        '(${a.x.toStringAsFixed(0)},${a.y.toStringAsFixed(0)})',
        p + const Offset(12, -8),
        Colors.lightBlueAccent,
      );
    }

    // 태그
    final tagFill = Paint()..color = Colors.cyanAccent;
    final tagStroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final entry in tagPositions.entries) {
      final p = toScreen(entry.value.dx, entry.value.dy);
      canvas.drawCircle(p, 10, tagFill);
      canvas.drawCircle(p, 10, tagStroke);
      _label(
          canvas,
          'Tag #${entry.key} '
          '(${entry.value.dx.toStringAsFixed(1)},'
          '${entry.value.dy.toStringAsFixed(1)})',
          p + const Offset(14, -10),
          Colors.cyanAccent);
    }

    _label(
      canvas,
      'fit scale: ${scale.toStringAsFixed(2)} px/unit   '
      'anchor view: [${bboxMinX.toStringAsFixed(0)},${bboxMinY.toStringAsFixed(0)}] '
      '~ [${bboxMaxX.toStringAsFixed(0)},${bboxMaxY.toStringAsFixed(0)}]',
      Offset(12, size.height - 24),
      Colors.white60,
    );
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint,
      {double dashWidth = 6, double gapWidth = 4}) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 1) return;
    final ux = dx / length;
    final uy = dy / length;
    final step = dashWidth + gapWidth;
    final n = (length / step).floor();
    for (int i = 0; i < n; i++) {
      final s = i * step;
      final e = s + dashWidth;
      canvas.drawLine(
        Offset(p1.dx + ux * s, p1.dy + uy * s),
        Offset(p1.dx + ux * e, p1.dy + uy * e),
        paint,
      );
    }
  }

  void _drawDistanceLabel(
      Canvas canvas, Offset p1, Offset p2, String text) {
    final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.cyanAccent,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final bg = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final w = tp.width + 6;
    final h = tp.height + 2;
    final rect = Rect.fromCenter(center: mid, width: w, height: h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      bg,
    );
    tp.paint(canvas, Offset(mid.dx - tp.width / 2, mid.dy - tp.height / 2));
  }

  void _drawGrid(Canvas canvas, Size size, double scale, double padding) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    final stepUnit = _niceGridStep(50 / scale);
    final step = stepUnit * scale;
    for (double x = padding; x < size.width - padding; x += step) {
      canvas.drawLine(
          Offset(x, padding), Offset(x, size.height - padding), paint);
    }
    for (double y = padding; y < size.height - padding; y += step) {
      canvas.drawLine(
          Offset(padding, y), Offset(size.width - padding, y), paint);
    }
  }

  double _niceGridStep(double approx) {
    final magnitudes = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000];
    for (final m in magnitudes) {
      if (m >= approx) return m.toDouble();
    }
    return 5000;
  }

  void _drawAxes(Canvas canvas, Size size, double padding) {
    final paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    canvas.drawLine(Offset(padding, size.height - padding),
        Offset(size.width - padding, size.height - padding), paint);
    canvas.drawLine(
        Offset(padding, padding), Offset(padding, size.height - padding), paint);
  }

  void _label(Canvas canvas, String text, Offset pos, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      old.anchors != anchors ||
      old.tagPositions != tagPositions ||
      old.latestPerTag != latestPerTag ||
      old.showDistances != showDistances ||
      old.editMode != editMode ||
      old.draggingIndex != draggingIndex ||
      old.bboxMinX != bboxMinX ||
      old.bboxMinY != bboxMinY ||
      old.bboxMaxX != bboxMaxX ||
      old.bboxMaxY != bboxMaxY;
}

