import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../models/anchor.dart';
import '../models/mqtt_config.dart';
import '../mqtt/mqtt_manager.dart';
import '../services/trilateration.dart';

class PositionProvider extends ChangeNotifier {
  PositionProvider() {
    _loadAnchors();
  }

  MqttManager? _mqtt;
  MqttConfig? _config;

  final Map<String, RangeReading> _latestBySrc = <String, RangeReading>{};
  final Map<int, Map<String, RangeReading>> _byTag =
      <int, Map<String, RangeReading>>{};
  // 태그별 가장 최근 메시지 (Map view의 거리 표시용)
  final Map<int, RangeReading> _latestPerTag = <int, RangeReading>{};

  List<Anchor> _anchors = const [];
  final Map<int, Offset> _tagPositions = <int, Offset>{};

  String _status = 'idle';

  Map<String, RangeReading> get latestBySrc => Map.unmodifiable(_latestBySrc);
  Map<int, Map<String, RangeReading>> get byTag => Map.unmodifiable(_byTag);
  Map<int, RangeReading> get latestPerTag => Map.unmodifiable(_latestPerTag);
  List<Anchor> get anchors => List.unmodifiable(_anchors);
  Map<int, Offset> get tagPositions => Map.unmodifiable(_tagPositions);
  String get status => _status;
  bool get isConnected => _mqtt?.isConnected ?? false;
  MqttConfig? get config => _config;

  Future<void> _loadAnchors() async {
    _anchors = await AnchorRepo.load();
    notifyListeners();
  }

  Future<void> setAnchors(List<Anchor> list) async {
    _anchors = List.of(list);
    await AnchorRepo.save(_anchors);
    _recomputeAll();
    notifyListeners();
  }

  Future<void> connect(MqttConfig config) async {
    _mqtt?.disconnect();
    _latestBySrc.clear();
    _byTag.clear();
    _tagPositions.clear();

    _config = config;
    _mqtt = MqttManager(config);
    _status = 'connecting…';
    notifyListeners();

    await _mqtt!.connect(onRange: _onRange, onStatus: _onStatus);
    notifyListeners();
  }

  void disconnect() {
    _mqtt?.disconnect();
    _mqtt = null;
    _config = null;
    _latestBySrc.clear();
    _byTag.clear();
    _tagPositions.clear();
    _status = 'idle';
    notifyListeners();
  }

  void _onStatus(String s) {
    _status = s;
    notifyListeners();
  }

  void _onRange(RangeReading r) {
    _latestBySrc[r.src] = r;
    _latestPerTag[r.tagId] = r;
    final perTag = _byTag.putIfAbsent(r.tagId, () => <String, RangeReading>{});
    perTag[r.src] = r;
    _recomputeFromMessage(r);
    notifyListeners();
  }

  /// 한 메시지 안에 들어 있는 range[] 배열은 모든 앵커의 거리.
  /// range[anchor.index] 가 그 앵커 ↔ 태그(reading.tagId) 거리.
  /// 실제 사용 거리 = range[index] + anchor.calibration (음수면 빼는 효과).
  void _recomputeFromMessage(RangeReading reading) {
    if (_anchors.isEmpty) return;

    final pts = <TrilatPoint>[];
    for (final a in _anchors) {
      if (a.index < 0 || a.index >= reading.ranges.length) continue;
      final r = reading.ranges[a.index];
      // raw sanity 필터: 0 초과, 30000 미만. 단위가 cm면 ~300m, mm면 30m 커버.
      if (r <= 0 || r >= 30000) continue;
      final d = r + a.calibration;
      if (d <= 0) continue; // 캘리브로 음수가 되면 무효
      pts.add(TrilatPoint(a.x, a.y, d));
    }

    if (pts.length < 3) return;
    final pos = solveLsTrilateration(pts);
    if (pos != null) {
      _tagPositions[reading.tagId] = pos;
    }
  }

  /// 모든 태그 재계산 (앵커 좌표 변경 시 호출).
  void _recomputeAll() {
    _tagPositions.clear();
    for (final perSrc in _byTag.values) {
      for (final reading in perSrc.values) {
        _recomputeFromMessage(reading);
      }
    }
  }

  @override
  void dispose() {
    _mqtt?.disconnect();
    super.dispose();
  }
}
