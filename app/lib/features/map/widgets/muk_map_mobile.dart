import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../../../core/config.dart';
import '../../../models/place.dart';
import 'muk_map_types.dart';
import 'preview_map.dart';
import 'zoom_buttons.dart';

Future<void> initMapSdk() async {
  if (!AppConfig.hasNaverMap) return;
  await FlutterNaverMap().init(
    clientId: AppConfig.naverMapClientId,
    onAuthFailed: (e) => debugPrint('네이버 지도 인증 실패: $e'),
  );
}

Widget buildPlatformMap(
    List<MukMapPin> pins, PinTapCallback onPinTap, LatLng center, LatLng? me, ValueChanged<LatLng>? onCameraIdle) {
  if (!AppConfig.hasNaverMap) {
    return PreviewMap(pins: pins, onPinTap: onPinTap, center: center, me: me, onCameraIdle: onCameraIdle);
  }
  return _NaverMobileMap(pins: pins, onPinTap: onPinTap, center: center, me: me, onCameraIdle: onCameraIdle);
}

class _NaverMobileMap extends StatefulWidget {
  const _NaverMobileMap({required this.pins, required this.onPinTap, required this.center, this.me, this.onCameraIdle});

  final List<MukMapPin> pins;
  final PinTapCallback onPinTap;
  final LatLng center;
  final LatLng? me;
  final ValueChanged<LatLng>? onCameraIdle;

  @override
  State<_NaverMobileMap> createState() => _NaverMobileMapState();
}

class _NaverMobileMapState extends State<_NaverMobileMap> {
  NaverMapController? _controller;

  /// 묶음 핀 아이콘. 플러그인의 묶음 콜백은 동기라서 2곳 ~ [_maxClusterIcon]곳을 미리 이미지로 만들어 둔다.
  static const _maxClusterIcon = 20;

  /// 친구 핀은 내 위치 점보다 위
  static const _pinZIndex = 310000;
  static const _meZIndex = 150000;
  final _clusterIcons = <int, NOverlayImage>{};

  @override
  void didUpdateWidget(covariant _NaverMobileMap old) {
    super.didUpdateWidget(old);
    if (old.pins != widget.pins) _syncMarkers();
    if (old.me != widget.me) _syncMe();
    if (old.center != widget.center) {
      // 내 위치 ↔ 전체 보기로 기준이 바뀌면 기본 줌으로 맞춘다.
      _controller?.updateCamera(NCameraUpdate.withParams(target: _n(widget.center), zoom: defaultMapZoom));
    }
  }

  static NLatLng _n(LatLng p) => NLatLng(p.lat, p.lng);

  /// 네이버 지도 기본 내 위치 표시(파란 점)를 쓴다.
  void _syncMe() {
    final controller = _controller;
    if (controller == null) return;
    final overlay = controller.getLocationOverlay();
    // 친구 핀·묶음 핀(기본 200000)이 내 위치 점(기본 300000)에 가리지 않게 점을 아래로 내린다.
    overlay.setGlobalZIndex(_meZIndex);
    final me = widget.me;
    if (me != null) overlay.setPosition(_n(me));
    overlay.setIsVisible(me != null);
  }

  Future<void> _syncMarkers() async {
    final controller = _controller;
    if (controller == null) return;

    // 얼굴 사진을 먼저 받아 두어야 위젯을 이미지로 찍을 때 빈 원이 나오지 않는다.
    final urls = widget.pins.expand((p) => p.avatarUrls.take(3)).toSet();
    await Future.wait(urls.map((u) => precacheImage(NetworkImage(u), context)));
    if (!mounted) return;

    await _prepareClusterIcons();
    if (!mounted) return;

    final markers = <NClusterableMarker>{};
    for (final pin in widget.pins) {
      final icon = await NOverlayImage.fromWidget(
        widget: FacePin(pin: pin),
        size: FacePin.markerSize,
        context: context,
      );
      if (!mounted) return;
      final marker = NClusterableMarker(
        id: pin.placeId,
        position: NLatLng(pin.location.lat, pin.location.lng),
        icon: icon,
        size: FacePin.markerSize,
        // 기본 앵커(아래 가운데) 대신 얼굴 원의 가운데가 좌표에 오게 한다.
        anchor: NPoint(0.5, FacePin.faceCenterY / FacePin.markerSize.height),
      );
      marker.setGlobalZIndex(_pinZIndex);
      marker.setOnTapListener((_) => widget.onPinTap(pin.placeId));
      markers.add(marker);
    }

    await controller.clearOverlays(type: NOverlayType.clusterableMarker);
    await controller.addOverlayAll(markers);
  }

  Future<void> _prepareClusterIcons() async {
    if (_clusterIcons.isNotEmpty) return;
    for (var n = 2; n <= _maxClusterIcon; n++) {
      _clusterIcons[n] = await NOverlayImage.fromWidget(
        widget: ClusterPin(count: n, plus: n == _maxClusterIcon),
        size: const Size.square(ClusterPin.size),
        context: context,
      );
      if (!mounted) return;
    }
  }

  /// 축소해서 핀이 겹치면 플러그인이 묶음 마커를 만든다. 모양을 바꾸고, 누르면 그 자리로 두 단계 확대한다.
  void _styleCluster(NClusterInfo info, NClusterMarker marker) {
    final icon = _clusterIcons[info.size.clamp(2, _maxClusterIcon)];
    if (icon != null) {
      marker.setIcon(icon);
      marker.setSize(const Size.square(ClusterPin.size));
    }
    marker.setCaption(null);
    // 내 위치 점(전역 z 300000)보다 위에 그려서 숫자가 가리지 않게 한다.
    marker.setGlobalZIndex(_pinZIndex);
    marker.setOnTapListener((_) async {
      final controller = _controller;
      if (controller == null) return;
      final zoom = (await controller.getCameraPosition()).zoom;
      await controller.updateCamera(NCameraUpdate.withParams(target: info.position, zoom: zoom + 2)
        ..setAnimation(duration: const Duration(milliseconds: 300)));
    });
  }

  /// 네이버 기본 줌 컨트롤과 같은 방식: 정수 줌 레벨 단위로 부드럽게 움직인다.
  Future<void> _zoomBy(int delta) async {
    final controller = _controller;
    if (controller == null) return;
    final zoom = (await controller.getCameraPosition()).zoom;
    await controller.updateCamera(NCameraUpdate.withParams(zoom: (zoom.round() + delta).toDouble())
      ..setAnimation(duration: const Duration(milliseconds: 300)));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      _map(),
      ZoomButtonsPosition(child: ZoomButtons(onZoomIn: () => _zoomBy(1), onZoomOut: () => _zoomBy(-1))),
    ]);
  }

  Widget _map() {
    return NaverMap(
      options: NaverMapViewOptions(
        initialCameraPosition: NCameraPosition(
          target: _n(widget.center),
          zoom: defaultMapZoom,
        ),
        // 웹 지도와 같이 네이버 기본 표시(지하철역·건물·가게 이름 등)를 그대로 보여 준다.
        // 표시만 하고 탭은 지도가 받지 않게 한다 (네이버 장소 정보 화면으로 넘어가지 않음).
        consumeSymbolTapEvents: false,
        // 기기 언어와 상관없이 지도 글자는 한국어로 (영어 기기에서 "Yeonnam-dong 연남동"처럼 두 줄로 나오지 않게)
        locale: const Locale('ko'),
      ),
      clusterOptions: NaverMapClusteringOptions(clusterMarkerBuilder: _styleCluster),
      onCameraIdle: () async {
        final controller = _controller;
        final cb = widget.onCameraIdle;
        if (controller == null || cb == null) return;
        final t = (await controller.getCameraPosition()).target;
        cb(LatLng(t.latitude, t.longitude));
      },
      onMapReady: (controller) {
        _controller = controller;
        _syncMarkers();
        _syncMe();
      },
    );
  }
}
