import 'package:flutter/widgets.dart';

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
  const MukMap({super.key, required this.pins, required this.onPinTap});

  final List<MukMapPin> pins;
  final PinTapCallback onPinTap;

  @override
  Widget build(BuildContext context) =>
      platform.buildPlatformMap(pins, onPinTap);
}
