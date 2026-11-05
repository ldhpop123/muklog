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

/// 화면용 업종 이름. 네이버 카테고리 "한식>순대,순댓국"이나 "순대,순댓국"에서 "순대"만 남긴다.
String categoryLabel(String category) => category.split('>').last.split(',').first.trim();

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

/// 식당 검색 결과 한 건 (GET /places/search). 서버가 네이버 지역 검색을 대신 호출해 만든다.
/// 이름·업종·주소·좌표만 담고, 네이버 평점·리뷰는 담지 않는다.
class PlaceCandidate {
  const PlaceCandidate({
    required this.externalId,
    required this.name,
    required this.category,
    required this.address,
    required this.location,
    this.placeId,
  });

  final String externalId;
  final String name;
  final String category;
  final String address;
  final LatLng location;

  /// 이미 먹로그에 등록된 식당이면 그 id
  final String? placeId;

  factory PlaceCandidate.fromJson(Map<String, dynamic> json) => PlaceCandidate(
        externalId: json['external_id'] as String,
        name: json['name'] as String,
        category: json['category'] as String? ?? '',
        address: json['address'] as String? ?? '',
        location: LatLng((json['lat'] as num).toDouble(), (json['lng'] as num).toDouble()),
        placeId: json['place_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'external_id': externalId,
        'name': name,
        'category': category,
        'address': address,
        'lat': location.lat,
        'lng': location.lng,
      };
}

/// 브리핑 단위인 상권 (GET /areas). 사람들이 부르는 이름(홍대, 연남, 합정…)이다.
class AreaInfo {
  const AreaInfo({
    required this.name,
    required this.location,
    required this.distanceKm,
    required this.recordCount,
    this.isDong = false,
  });

  final String name;
  final LatLng location;

  /// 지도 화면 가운데에서의 거리
  final double distanceKm;

  /// 내가 볼 수 있는 친구 기록 수 (0이면 "아직 친구 기록이 없어요")
  final int recordCount;

  /// true면 상권이 아니라 행정동 (근처에 상권이 없을 때 서버가 대신 넣는다)
  final bool isDong;

  factory AreaInfo.fromJson(Map<String, dynamic> json) => AreaInfo(
        name: json['name'] as String,
        location: LatLng((json['lat'] as num).toDouble(), (json['lng'] as num).toDouble()),
        distanceKm: (json['distance_km'] as num).toDouble(),
        recordCount: json['record_count'] as int? ?? 0,
        isDong: json['kind'] == 'dong',
      );
}
