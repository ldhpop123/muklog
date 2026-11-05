import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../../../core/config.dart';
import 'muk_map_types.dart';
import 'preview_map.dart';

Future<void> initMapSdk() async {
  if (!AppConfig.hasNaverMap) return;
  await FlutterNaverMap().init(
    clientId: AppConfig.naverMapClientId,
    onAuthFailed: (e) => debugPrint('네이버 지도 인증 실패: $e'),
  );
}

Widget buildPlatformMap(List<MukMapPin> pins, PinTapCallback onPinTap) {
  if (!AppConfig.hasNaverMap) return PreviewMap(pins: pins, onPinTap: onPinTap);
  return _NaverMobileMap(pins: pins, onPinTap: onPinTap);
}

class _NaverMobileMap extends StatefulWidget {
  const _NaverMobileMap({required this.pins, required this.onPinTap});

  final List<MukMapPin> pins;
  final PinTapCallback onPinTap;

  @override
  State<_NaverMobileMap> createState() => _NaverMobileMapState();
}

class _NaverMobileMapState extends State<_NaverMobileMap> {
  NaverMapController? _controller;

  @override
  void didUpdateWidget(covariant _NaverMobileMap old) {
    super.didUpdateWidget(old);
    if (old.pins != widget.pins) _syncMarkers();
  }

  Future<void> _syncMarkers() async {
    final controller = _controller;
    if (controller == null) return;

    // 얼굴 사진을 먼저 받아 두어야 위젯을 이미지로 찍을 때 빈 원이 나오지 않는다.
    final urls = widget.pins.expand((p) => p.avatarUrls.take(3)).toSet();
    await Future.wait(urls.map((u) => precacheImage(NetworkImage(u), context)));
    if (!mounted) return;

    final markers = <NMarker>{};
    for (final pin in widget.pins) {
      final icon = await NOverlayImage.fromWidget(
        widget: FacePin(pin: pin),
        size: FacePin.markerSize,
        context: context,
      );
      if (!mounted) return;
      final marker = NMarker(
        id: pin.placeId,
        position: NLatLng(pin.location.lat, pin.location.lng),
        icon: icon,
      );
      marker.setOnTapListener((_) => widget.onPinTap(pin.placeId));
      markers.add(marker);
    }

    await controller.clearOverlays(type: NOverlayType.marker);
    await controller.addOverlayAll(markers);
  }

  @override
  Widget build(BuildContext context) {
    return NaverMap(
      options: NaverMapViewOptions(
        initialCameraPosition: NCameraPosition(
          target: NLatLng(defaultMapCenter.lat, defaultMapCenter.lng),
          zoom: defaultMapZoom,
        ),
        // 먹로그는 친구 추천만 보여 준다. 네이버 장소 심볼(식당·가게 이름 등)은 숨기고 탭도 막는다.
        symbolScale: 0,
        consumeSymbolTapEvents: false,
      ),
      onMapReady: (controller) {
        _controller = controller;
        _syncMarkers();
      },
    );
  }
}
