import 'package:flutter/widgets.dart';

import '../../../models/place.dart';
import 'muk_map_types.dart';
import 'muk_map_stub.dart'
    if (dart.library.io) 'muk_map_mobile.dart'
    if (dart.library.js_interop) 'muk_map_web.dart' as platform;

export 'muk_map_types.dart';

/// 지도 SDK 초기화. `runApp` 전에 한 번 호출한다.
Future<void> initMukMap() => platform.initMapSdk();

/// 플랫폼 공통 지도 위젯.
///
/// 다른 화면은 이 위젯만 사용한다. 실제 구현은 조건부 import로 갈린다.
/// - Android·iOS: `muk_map_mobile.dart` (flutter_naver_map 플러그인)
/// - Web: `muk_map_web.dart` (네이버 지도 JavaScript SDK + HtmlElementView)
/// NAVER_MAP_CLIENT_ID가 없으면 양쪽 모두 임시 지도(PreviewMap)를 쓴다.
class MukMap extends StatelessWidget {
  const MukMap({
    super.key,
    required this.pins,
    required this.onPinTap,
    required this.center,
    this.me,
    this.onCameraIdle,
  });

  final List<MukMapPin> pins;
  final PinTapCallback onPinTap;

  /// 지도 가운데. 내 주변 보기면 내 위치.
  final LatLng center;

  /// 내 현재 위치. 있으면 지도에 내 위치 점을 찍는다.
  final LatLng? me;

  /// 지도가 움직임을 멈출 때마다 화면 가운데 좌표를 알려 준다 ("이 지역 브리핑 보기"용).
  final ValueChanged<LatLng>? onCameraIdle;

  @override
  Widget build(BuildContext context) => platform.buildPlatformMap(pins, onPinTap, center, me, onCameraIdle);
}
