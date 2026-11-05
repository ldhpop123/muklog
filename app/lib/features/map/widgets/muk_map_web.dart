import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../../../core/config.dart';
import 'muk_map_types.dart';
import 'preview_map.dart';

// ── 네이버 지도 JavaScript SDK v3 바인딩 ───────────────────────────────
// https://navermaps.github.io/maps.js.ncp/docs/

@JS('naver.maps.Map')
extension type _NMap._(JSObject _) implements JSObject {
  external _NMap(web.HTMLElement element, _MapOptions options);
}

@JS('naver.maps.LatLng')
extension type _NLatLng._(JSObject _) implements JSObject {
  external _NLatLng(double lat, double lng);
}

@JS('naver.maps.Point')
extension type _NPoint._(JSObject _) implements JSObject {
  external _NPoint(num x, num y);
}

@JS('naver.maps.Size')
extension type _NSize._(JSObject _) implements JSObject {
  external _NSize(num width, num height);
}

@JS('naver.maps.Marker')
extension type _NMarker._(JSObject _) implements JSObject {
  external _NMarker(_MarkerOptions options);
  external void setMap(_NMap? map);
}

@JS('naver.maps.Event.addListener')
external JSObject _addListener(
    JSObject target, String eventName, JSFunction listener);

@JS('naver.maps.Event.trigger')
external void _trigger(JSObject target, String eventName);

extension type _MapOptions._(JSObject _) implements JSObject {
  external factory _MapOptions(
      {_NLatLng center, num zoom, bool gl, String? customStyleId});
}

extension type _HtmlIcon._(JSObject _) implements JSObject {
  external factory _HtmlIcon({String content, _NSize size, _NPoint anchor});
}

extension type _MarkerOptions._(JSObject _) implements JSObject {
  external factory _MarkerOptions(
      {_NLatLng position, _NMap map, _HtmlIcon icon});
}

// ── SDK 로드 ────────────────────────────────────────────────────────

/// 먹로그는 친구 추천만 보여 준다. 웹 기본(래스터) 지도는 네이버 장소 이름이 타일에 박혀 있으므로,
/// POI를 끈 커스텀 스타일(Style Editor)이 있으면 GL 벡터 지도로 띄워 장소 라벨을 숨긴다.
bool get _useCustomStyle => AppConfig.naverMapStyleId.isNotEmpty;

/// index.html을 고치지 않도록 Client ID를 넣은 SDK 스크립트를 런타임에 붙인다.
Future<void> initMapSdk() async {
  if (!AppConfig.hasNaverMap) return;
  final done = Completer<void>();
  final script = web.HTMLScriptElement()
    ..src = 'https://oapi.map.naver.com/openapi/v3/maps.js'
        '?ncpKeyId=${Uri.encodeQueryComponent(AppConfig.naverMapClientId)}'
        '${_useCustomStyle ? '&submodules=gl' : ''}';
  script.onload = ((web.Event _) {
    done.complete();
  }).toJS;
  script.onerror = ((web.Event _) {
    done.completeError(StateError('네이버 지도 SDK를 불러오지 못했습니다.'));
  }).toJS;
  web.document.head!.appendChild(script);
  return done.future;
}

Widget buildPlatformMap(List<MukMapPin> pins, PinTapCallback onPinTap) {
  if (!AppConfig.hasNaverMap) return PreviewMap(pins: pins, onPinTap: onPinTap);
  return _NaverWebMap(pins: pins, onPinTap: onPinTap);
}

// ── 지도 위젯 ───────────────────────────────────────────────────────

class _NaverWebMap extends StatefulWidget {
  const _NaverWebMap({required this.pins, required this.onPinTap});

  final List<MukMapPin> pins;
  final PinTapCallback onPinTap;

  @override
  State<_NaverWebMap> createState() => _NaverWebMapState();
}

class _NaverWebMapState extends State<_NaverWebMap> {
  static var _nextId = 0;
  late final String _viewType = 'muklog-naver-map-${_nextId++}';
  late final web.HTMLDivElement _container;
  _NMap? _map;
  final _markers = <_NMarker>[];

  @override
  void initState() {
    super.initState();
    _container = web.HTMLDivElement()
      ..style.width = '100%'
      ..style.height = '100%';
    ui_web.platformViewRegistry
        .registerViewFactory(_viewType, (int _) => _container);
  }

  void _createMap() {
    // 컨테이너가 DOM에 붙고 크기가 잡힌 다음 프레임에 지도를 만든다.
    web.window.requestAnimationFrame(((num _) {
      if (!mounted) return;
      _map = _NMap(
        _container,
        _MapOptions(
          center: _NLatLng(defaultMapCenter.lat, defaultMapCenter.lng),
          zoom: defaultMapZoom,
          gl: _useCustomStyle,
          customStyleId: _useCustomStyle ? AppConfig.naverMapStyleId : null,
        ),
      );
      _syncMarkers();
    }).toJS);
  }

  @override
  void didUpdateWidget(covariant _NaverWebMap old) {
    super.didUpdateWidget(old);
    if (old.pins != widget.pins) _syncMarkers();
  }

  void _syncMarkers() {
    final map = _map;
    if (map == null) return;
    for (final m in _markers) {
      m.setMap(null);
    }
    _markers.clear();

    for (final pin in widget.pins) {
      final size = FacePin.markerSize;
      final marker = _NMarker(_MarkerOptions(
        position: _NLatLng(pin.location.lat, pin.location.lng),
        map: map,
        // 앵커 = 첫 번째 얼굴 원의 중심 아래쪽
        icon: _HtmlIcon(
          content: _facePinHtml(pin),
          size: _NSize(size.width, size.height),
          anchor: _NPoint(size.width / 2, 44),
        ),
      ));
      _addListener(
          marker,
          'click',
          ((JSAny? _) {
            widget.onPinTap(pin.placeId);
          }).toJS);
      _markers.add(marker);
    }
    _trigger(map, 'resize');
  }

  @override
  void dispose() {
    for (final m in _markers) {
      m.setMap(null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(
        viewType: _viewType, onPlatformViewCreated: (_) => _createMap());
  }
}

/// 모바일 FacePin 위젯과 같은 모양의 HTML 마커 (흰 테두리 얼굴 + 단골 도장 + 이름표).
String _facePinHtml(MukMapPin pin) {
  final faces = pin.avatarUrls.take(3).toList();
  final imgs = [
    for (var i = 0; i < faces.length; i++)
      '<img src="${_escape(faces[i])}" style="position:absolute;left:${i * 20}px;top:0;'
          'width:39px;height:39px;border-radius:50%;border:2.5px solid #FDFAF5;object-fit:cover;'
          'background:#EFE7DB;box-shadow:0 1px 3px rgba(31,26,21,.1)">'
  ].join();
  final stamp = pin.visits >= 2
      ? '<div style="position:absolute;right:-6px;top:-8px;width:25px;height:25px;border-radius:50%;'
          'border:1.5px solid #C2461A;background:#FDFAF5;color:#C2461A;font-size:8.5px;font-weight:600;'
          'display:flex;align-items:center;justify-content:center;transform:rotate(-8deg);'
          'font-variant-numeric:tabular-nums">${pin.visits}회</div>'
      : '';
  final facesWidth = 44 + (faces.length - 1) * 20 + (pin.visits >= 2 ? 16 : 0);
  return '<div style="width:${FacePin.markerSize.width}px;display:flex;flex-direction:column;'
      'align-items:center;cursor:pointer;font-family:\'IBM Plex Sans KR\',sans-serif">'
      '<div style="position:relative;width:${facesWidth}px;height:44px">$imgs$stamp</div>'
      '<div style="margin-top:4px;max-width:128px;padding:4px 8px;background:#FDFAF5;border-radius:6px;'
      'border:1px solid rgba(31,26,21,.08);font-size:12px;font-weight:500;color:#1F1A15;'
      'white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${_escape(pin.label)}</div>'
      '</div>';
}

/// 사용자 입력(식당 이름 등)이 HTML로 해석되지 않도록 이스케이프한다.
String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
