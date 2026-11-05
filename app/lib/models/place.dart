import 'dart:math' as math;

import 'taste_vector.dart';

class LatLng {
  const LatLng(this.lat, this.lng);
  final double lat;
  final double lng;

  /// 두 좌표 사이 거리(km). 하버사인 (서버 taste.distance_km과 같은 식).
  double distanceKm(LatLng other) {
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(other.lat - lat), dLng = rad(other.lng - lng);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat)) * math.cos(rad(other.lat)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  @override
  bool operator ==(Object other) => other is LatLng && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);
}

class Place {
  const Place({
    required this.id,
    required this.name,
    required this.location,
    required this.area,
    required this.category,
    required this.taste,
    this.tags = const [],
    this.revisitTotal = 0,
  });

  final String id;
  final String name;
  final LatLng location;

  /// 지역 브리핑 단위. 예: "홍대"
  final String area;
  final String category;
  final TasteVector taste;
  final List<String> tags;

  /// 친구들의 총 재방문 횟수
  final int revisitTotal;

  factory Place.fromJson(Map<String, dynamic> json) => Place(
        id: json['id'] as String,
        name: json['name'] as String,
        location: LatLng(
          (json['lat'] as num).toDouble(),
          (json['lng'] as num).toDouble(),
        ),
        area: json['area'] as String? ?? '',
        category: json['category'] as String,
        taste: TasteVector.fromJson(json['taste'] as Map<String, dynamic>),
        tags: (json['tags'] as List?)?.cast<String>() ?? const [],
        revisitTotal: json['revisit_total'] as int? ?? 0,
      );
}
