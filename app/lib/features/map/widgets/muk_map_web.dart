import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../../../core/config.dart';
import '../../../models/place.dart';
import 'muk_map_types.dart';
import 'pin_clustering.dart';
import 'preview_map.dart';
import 'zoom_buttons.dart';

// ── 네이버 지도 JavaScript SDK v3 바인딩 ───────────────────────────────
// https://navermaps.github.io/maps.js.ncp/docs/

@JS('naver.maps.Map')
extension type _NMap._(JSObject _) implements JSObject {
  external _NMap(web.HTMLElement element, _MapOptions options);
  external void setCenter(_NLatLng center);
  external _NLatLng getCenter();
  external num getZoom();
  external void setZoom(num zoom, [bool effect]);
  external _NProjection getProjection();
}

@JS('naver.maps.LatLng')
extension type _NLatLng._(JSObject _) implements JSObject {
  external _NLatLng(double lat, double lng);
  external num lat();
  external num lng();
}

@JS('naver.maps.Point')
extension type _NPoint._(JSObject _) implements JSObject {
  external _NPoint(num x, num y);
  external num get x;
  external num get y;
}

/// 좌표 ↔ 화면 픽셀 변환. 현재 줌 기준의 지도 픽셀 좌표를 준다.
extension type _NProjection._(JSObject _) implements JSObject {
  external _NPoint fromCoordToOffset(_NLatLng coord);
}

@JS('naver.maps.Size')
extension type _NSize._(JSObject _) implements JSObject {
  external _NSize(num width, num height);
}

@JS('naver.maps.Marker')
extension type _NMarker._(JSObject _) implements JSObject {
  external _NMarker(_MarkerOptions options);
  external void setMap(_NMap? map);
  external void setPosition(_NLatLng position);
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
/// 네이버 지도 인증 실패 여부. 콘솔에 등록하지 않은 주소(예: 매번 바뀌는 ngrok 주소)로 열면 true가 되고,
/// 지도는 임시 지도로 바뀐다.
final _authFailed = ValueNotifier(false);

Future<void> initMapSdk() async {
  if (!AppConfig.hasNaverMap) return;
  // SDK가 인증 실패 시 부르는 전역 함수 (https://navermaps.github.io/maps.js.ncp/docs/tutorial-2-Getting-Started.html)
  globalContext['navermap_authFailure'] = (() {
    web.console.warn('네이버 지도 인증 실패: 이 주소가 콘솔의 Web 서비스 URL에 등록되어 있는지 확인하세요'.toJS);
    _authFailed.value = true;
  }).toJS;
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

Widget buildPlatformMap(
    List<MukMapPin> pins, PinTapCallback onPinTap, LatLng center, LatLng? me, ValueChanged<LatLng>? onCameraIdle) {
  if (!AppConfig.hasNaverMap) {
    return PreviewMap(pins: pins, onPinTap: onPinTap, center: center, me: me, onCameraIdle: onCameraIdle);
  }
  return ValueListenableBuilder(
    valueListenable: _authFailed,
    builder: (context, failed, _) => failed
        ? PreviewMap(pins: pins, onPinTap: onPinTap, center: center, me: me, onCameraIdle: onCameraIdle)
        : _NaverWebMap(pins: pins, onPinTap: onPinTap, center: center, me: me, onCameraIdle: onCameraIdle),
  );
}

// ── 지도 위젯 ───────────────────────────────────────────────────────

class _NaverWebMap extends StatefulWidget {
  const _NaverWebMap({required this.pins, required this.onPinTap, required this.center, this.me, this.onCameraIdle});

  final List<MukMapPin> pins;
  final PinTapCallback onPinTap;
  final LatLng center;
  final LatLng? me;
  final ValueChanged<LatLng>? onCameraIdle;

  @override
  State<_NaverWebMap> createState() => _NaverWebMapState();
}

class _NaverWebMapState extends State<_NaverWebMap> {
  static var _nextId = 0;
  late final String _viewType = 'muklog-naver-map-${_nextId++}';
  late final web.HTMLDivElement _container;
  _NMap? _map;
  final _markers = <_NMarker>[];
  _NMarker? _meMarker;

  static _NLatLng _n(LatLng p) => _NLatLng(p.lat, p.lng);

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
          center: _n(widget.center),
          zoom: defaultMapZoom,
          gl: _useCustomStyle,
          customStyleId: _useCustomStyle ? AppConfig.naverMapStyleId : null,
        ),
      );
      _syncMarkers();
      _syncMe();
      _addListener(_map!, 'idle', ((JSAny? _) {
        _syncMarkers();
        final c = _map!.getCenter();
        widget.onCameraIdle?.call(LatLng(c.lat().toDouble(), c.lng().toDouble()));
      }).toJS);
      _trigger(_map!, 'resize');
    }).toJS);
  }

  /// 내 위치 점. 네이버 지도 모바일의 기본 표시처럼 흰 테두리의 파란 점.
  void _syncMe() {
    final map = _map;
    if (map == null) return;
    final me = widget.me;
    if (me == null) {
      _meMarker?.setMap(null);
      _meMarker = null;
      return;
    }
    if (_meMarker != null) {
      _meMarker!.setPosition(_n(me));
      return;
    }
    _meMarker = _NMarker(_MarkerOptions(
      position: _n(me),
      map: map,
      icon: _HtmlIcon(
        content: '<div title="내 위치" style="width:16px;height:16px;border-radius:50%;background:#2F6FEB;'
            'border:3px solid #fff;box-shadow:0 0 0 6px rgba(47,111,235,.18),0 1px 3px rgba(0,0,0,.25)"></div>',
        size: _NSize(22, 22),
        anchor: _NPoint(11, 11),
      ),
    ));
  }

  @override
  void didUpdateWidget(covariant _NaverWebMap old) {
    super.didUpdateWidget(old);
    if (old.pins != widget.pins) _syncMarkers();
    if (old.me != widget.me) _syncMe();
    if (old.center != widget.center) {
      _map?.setCenter(_n(widget.center));
      _map?.setZoom(defaultMapZoom, true);
    }
  }

  void _syncMarkers() {
    final map = _map;
    if (map == null) return;
    for (final m in _markers) {
      m.setMap(null);
    }
    _markers.clear();

    // 축소해서 핀이 겹치면 하나로 묶는다. 지도가 멈출 때마다('idle') 현재 줌으로 다시 묶는다.
    final projection = map.getProjection();
    final groups = groupPins(widget.pins, (p) {
      final o = projection.fromCoordToOffset(_n(p.location));
      return Offset(o.x.toDouble(), o.y.toDouble());
    });

    for (final g in groups) {
      final _NMarker marker;
      if (g.isCluster) {
        final lat = g.pins.fold(0.0, (a, p) => a + p.location.lat) / g.pins.length;
        final lng = g.pins.fold(0.0, (a, p) => a + p.location.lng) / g.pins.length;
        const s = ClusterPin.size;
        marker = _NMarker(_MarkerOptions(
          position: _NLatLng(lat, lng),
          map: map,
          icon: _HtmlIcon(content: _clusterHtml(g.pins.length), size: _NSize(s, s), anchor: _NPoint(s / 2, s / 2)),
        ));
        // 묶음을 누르면 그 자리로 두 단계 확대한다.
        _addListener(marker, 'click', ((JSAny? _) {
          map.setCenter(_NLatLng(lat, lng));
          map.setZoom(map.getZoom().round() + 2, true);
        }).toJS);
      } else {
        final pin = g.pins.single;
        final size = FacePin.markerSize;
        marker = _NMarker(_MarkerOptions(
          position: _n(pin.location),
          map: map,
          // 앵커 = 첫 번째 얼굴 원의 가운데
          icon: _HtmlIcon(
            content: _facePinHtml(pin),
            size: _NSize(size.width, size.height),
            anchor: _NPoint(size.width / 2, FacePin.faceCenterY),
          ),
        ));
        _addListener(marker, 'click', ((JSAny? _) {
          widget.onPinTap(pin.placeId);
        }).toJS);
      }
      _markers.add(marker);
    }
  }

  @override
  void dispose() {
    _meMarker?.setMap(null);
    for (final m in _markers) {
      m.setMap(null);
    }
    super.dispose();
  }

  /// 마우스 휠·두 손가락 확대는 네이버 지도가 기본으로 처리한다. 버튼은 한 단계씩.
  void _zoomBy(int delta) {
    final map = _map;
    if (map == null) return;
    map.setZoom(map.getZoom().round() + delta, true);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      HtmlElementView(
        viewType: _viewType, onPlatformViewCreated: (_) => _createMap()),
      ZoomButtonsPosition(child: ZoomButtons(onZoomIn: () => _zoomBy(1), onZoomOut: () => _zoomBy(-1))),
    ]);
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
  // FacePin의 위쪽 여백(도장이 튀어나오는 자리)과 맞춘다.
  final topInset = FacePin.faceCenterY - 22;
  final stamp = pin.visits >= 2
      ? '<div style="position:absolute;right:-6px;top:-8px;width:25px;height:25px;border-radius:50%;'
          'border:1.5px solid #C2461A;background:#FDFAF5;color:#C2461A;font-size:8.5px;font-weight:600;'
          'display:flex;align-items:center;justify-content:center;transform:rotate(-8deg);'
          'font-variant-numeric:tabular-nums">${pin.visits}회</div>'
      : '';
  final facesWidth = 44 + (faces.length - 1) * 20 + (pin.visits >= 2 ? 16 : 0);
  return '<div style="width:${FacePin.markerSize.width}px;display:flex;flex-direction:column;'
      'align-items:center;cursor:pointer;padding-top:${topInset}px;font-family:\'IBM Plex Sans KR\',sans-serif">'
      '<div style="position:relative;width:${facesWidth}px;height:44px">$imgs$stamp</div>'
      '<div style="margin-top:4px;max-width:128px;padding:4px 8px;background:#FDFAF5;border-radius:6px;'
      'border:1px solid rgba(31,26,21,.08);font-size:12px;font-weight:500;color:#1F1A15;'
      'white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${_escape(pin.label)}</div>'
      '</div>';
}

/// 묶음 핀 HTML (ClusterPin 위젯과 같은 모양).
String _clusterHtml(int count) {
  const s = ClusterPin.size;
  return '<div style="width:${s}px;height:${s}px;box-sizing:border-box;border-radius:50%;'
      'background:#FDFAF5;border:2px solid #C2461A;box-shadow:0 2px 6px rgba(31,26,21,.15);'
      'display:flex;align-items:center;justify-content:center;cursor:pointer;color:#C2461A;'
      'font-family:\'IBM Plex Sans KR\',sans-serif;font-variant-numeric:tabular-nums">'
      '<span style="font-size:18px;font-weight:600;line-height:1">$count</span>'
      '<span style="font-size:11px;font-weight:500">곳</span></div>';
}

/// 사용자 입력(식당 이름 등)이 HTML로 해석되지 않도록 이스케이프한다.
String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
