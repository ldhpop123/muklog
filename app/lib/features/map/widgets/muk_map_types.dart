import '../../../models/place.dart';

/// 지도에 찍을 얼굴 핀 하나. 한 식당에 다녀간 친구 얼굴을 겹쳐 보여 준다.
class MukMapPin {
  const MukMapPin({
    required this.placeId,
    required this.label,
    required this.location,
    required this.avatarUrls,
    this.visits = 0,
  });

  final String placeId;
  final String label;
  final LatLng location;
  final List<String> avatarUrls;

  /// 핀에 보이는 사람들의 총 방문 횟수. 2회 이상이면 단골 도장을 찍는다.
  final int visits;
}

typedef PinTapCallback = void Function(String placeId);

/// 지도 첫 화면 중심 (홍대입구역).
const defaultMapCenter = LatLng(37.5572, 126.9245);
/// 반경 3km 안의 핀이 폰 화면에 대체로 들어오는 줌 레벨
const defaultMapZoom = 14.0;
