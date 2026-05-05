import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class Anchor {
  Anchor({
    required this.src,
    required this.index,
    required this.x,
    required this.y,
    this.calibration = 0,
  });

  /// 표시용 이름 (예: "A0"). 디바이스 페이로드의 src와 일치하지 않아도 됨.
  final String src;

  /// 디바이스 페이로드의 range[] 배열 인덱스. range[index]가 이 앵커의 거리.
  final int index;

  final double x;
  final double y;

  /// 거리 보정값 (단위는 range와 동일).
  /// 실제 사용 거리 = range[index] + calibration. 음수면 빼는 효과.
  final double calibration;

  /// src 끝의 숫자를 index로 자동 추출 (예: "A0" → 0, "Anchor3" → 3).
  static int? indexFromSrc(String src) {
    final m = RegExp(r'(\d+)\s*$').firstMatch(src);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  Map<String, dynamic> toJson() => {
        'src': src,
        'index': index,
        'x': x,
        'y': y,
        'cal': calibration,
      };

  factory Anchor.fromJson(Map<String, dynamic> j) => Anchor(
        src: j['src'] as String,
        index: (j['index'] as num?)?.toInt() ??
            (indexFromSrc(j['src'] as String) ?? 0),
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        calibration: (j['cal'] as num?)?.toDouble() ?? 0,
      );

  Anchor copyWith({
    String? src,
    int? index,
    double? x,
    double? y,
    double? calibration,
  }) =>
      Anchor(
        src: src ?? this.src,
        index: index ?? this.index,
        x: x ?? this.x,
        y: y ?? this.y,
        calibration: calibration ?? this.calibration,
      );
}

class AnchorRepo {
  static const _key = 'anchors';

  static Future<List<Anchor>> load() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_key);
    if (s == null || s.isEmpty) return [];
    try {
      final list = jsonDecode(s) as List;
      return list
          .map((e) => Anchor.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Anchor> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(list.map((a) => a.toJson()).toList()));
  }
}
