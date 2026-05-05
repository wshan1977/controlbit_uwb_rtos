import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint;

class TrilatPoint {
  const TrilatPoint(this.x, this.y, this.distance);
  final double x;
  final double y;
  final double distance;
}

/// Least-squares trilateration. 레퍼런스 SolveLsTrilateration 포팅.
///
/// 수치 안정성을 위해 첫 앵커를 origin으로 평행이동한 좌표계에서 풀고,
/// 결과에 origin을 더해 복원. (수학적으로는 비-shift 버전과 동일한 답.)
///
/// outlier 처리 (scale-invariant): 푼 후 각 앵커의 잔차를 본다.
/// 최대 잔차가 median 잔차의 [robustFactor]배를 넘으면 그 앵커가 outlier로 판정,
/// 빼고 재계산. 최소 3개가 남을 때까지 [maxIter]번 반복.
/// 단위(cm/mm/m)와 무관하게 동작.
Offset? solveLsTrilateration(
  List<TrilatPoint> points, {
  double robustFactor = 3.0,
  int maxIter = 4,
}) {
  var pts = List.of(points);
  Offset? best;

  for (int iter = 0; iter < maxIter; iter++) {
    if (pts.length < 3) return best;
    final pos = _solveOnce(pts);
    if (pos == null) return best;
    best = pos;

    if (pts.length <= 3) return pos; // 3개 이하면 outlier 제거 불가

    // 잔차 계산
    final residuals = <double>[];
    for (final p in pts) {
      final dx = pos.dx - p.x;
      final dy = pos.dy - p.y;
      final est = math.sqrt(dx * dx + dy * dy);
      residuals.add((est - p.distance).abs());
    }

    final sorted = List.of(residuals)..sort();
    final median = sorted[sorted.length ~/ 2];
    final maxR = sorted.last;
    final worstIdx = residuals.indexOf(maxR);

    // outlier 판정: median의 robustFactor배 초과 (median이 0에 가까우면 작은 floor 사용)
    final threshold =
        math.max(median * robustFactor, median + 1); // median=0 보호
    if (maxR <= threshold) return pos;

    debugPrint('[Trilat] outlier reject: '
        '(${pts[worstIdx].x.toStringAsFixed(1)},${pts[worstIdx].y.toStringAsFixed(1)})'
        ' d=${pts[worstIdx].distance.toStringAsFixed(1)} '
        'residual=${maxR.toStringAsFixed(1)} (median=${median.toStringAsFixed(1)})');
    pts = List.of(pts)..removeAt(worstIdx);
  }
  return best;
}

/// 1회 LS 풀이 (origin shift 적용).
Offset? _solveOnce(List<TrilatPoint> points) {
  if (points.length < 3) return null;

  final ox = points[0].x;
  final oy = points[0].y;
  final d0 = points[0].distance;

  double a11 = 0, a12 = 0, a21 = 0, a22 = 0;
  double b1 = 0, b2 = 0;

  for (int k = 1; k < points.length; k++) {
    final p = points[k];
    final xi = p.x - ox;
    final yi = p.y - oy;
    final di = p.distance;

    final ai1 = 2.0 * xi;
    final ai2 = 2.0 * yi;
    final bi = (xi * xi + yi * yi - di * di) - (-d0 * d0);

    a11 += ai1 * ai1;
    a12 += ai1 * ai2;
    a21 += ai2 * ai1;
    a22 += ai2 * ai2;

    b1 += ai1 * bi;
    b2 += ai2 * bi;
  }

  final det = a11 * a22 - a12 * a21;
  if (det.abs() < 1e-12) {
    debugPrint('[Trilat] singular (det≈0). 앵커가 일직선?');
    return null;
  }

  final xs = (a22 * b1 - a12 * b2) / det;
  final ys = (-a21 * b1 + a11 * b2) / det;
  final x = xs + ox;
  final y = ys + oy;

  final inputDesc = points
      .map((p) =>
          '(${p.x.toStringAsFixed(1)},${p.y.toStringAsFixed(1)},d=${p.distance.toStringAsFixed(1)})')
      .join(' ');
  debugPrint(
      '[Trilat] in: $inputDesc → out: (${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})');

  return Offset(x, y);
}

/// 8개 샘플에서 유효 거리만 골라 평균 (현재 미사용; 추후 노이즈 평균용).
double? meanValidRange(List<int> samples,
    {double minValid = 0, double maxValid = 1000}) {
  final valid = samples.where((r) => r > minValid && r < maxValid).toList();
  if (valid.isEmpty) return null;
  return valid.reduce((a, b) => a + b) / valid.length;
}
