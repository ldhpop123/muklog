import '../../../models/place.dart';

/// 지도에 찍을 얼굴 핀 하나. 한 식당에 다녀간 친구 얼굴을 겹쳐 보여 준다.
class MukMapPin {
  const MukMapPin({
    required this.placeId,
    required this.label,
    required this.location,
    required this.avatarUrls,
  });

  final String placeId;
  final String label;
  final LatLng location;
  final List<String> avatarUrls;
}

typedef PinTapCallback = void Function(String placeId);

/// 지도 첫 화면 중심 (홍대입구역).
const defaultMapCenter = LatLng(37.5572, 126.9245);
const defaultMapZoom = 15.0;
