import 'dart:ui';

import 'muk_map_types.dart';

/// 화면에서 가까이 겹친 핀 묶음. 핀이 하나면 묶지 않은 핀이다.
class PinGroup {
  PinGroup(this.pins, this.offset);

  final List<MukMapPin> pins;

  /// 묶음의 화면 위치 (핀들 위치의 평균)
  final Offset offset;

  bool get isCluster => pins.length > 1;
}

/// 화면 좌표 기준으로 [radius] 안에 겹치는 핀을 묶는다 (탐욕적 묶기).
/// 네이버 모바일 지도는 플러그인의 클러스터링을 쓰고, 임시 지도와 웹 지도가 이 함수를 쓴다.
List<PinGroup> groupPins(List<MukMapPin> pins, Offset Function(MukMapPin) project, {double radius = 64}) {
  final points = [for (final p in pins) (p, project(p))];
  final used = List.filled(points.length, false);
  final groups = <PinGroup>[];
  for (var i = 0; i < points.length; i++) {
    if (used[i]) continue;
    used[i] = true;
    final members = [points[i]];
    for (var j = i + 1; j < points.length; j++) {
      if (!used[j] && (points[j].$2 - points[i].$2).distance < radius) {
        used[j] = true;
        members.add(points[j]);
      }
    }
    final sum = members.fold(Offset.zero, (a, m) => a + m.$2);
    groups.add(PinGroup([for (final m in members) m.$1], sum / members.length.toDouble()));
  }
  return groups;
}
