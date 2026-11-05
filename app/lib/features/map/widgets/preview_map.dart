import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../models/place.dart';
import 'muk_map_types.dart';
import 'pin_clustering.dart';
import 'zoom_buttons.dart';

/// 실제 지도 SDK를 붙이기 전까지 쓰는 임시 지도.
/// 종이 위 골목 지도처럼 그리고, 핀 좌표를 화면 영역에 비례 배치해 얼굴 핀 UI를 확인할 수 있다.
/// 두 손가락·마우스 휠·버튼으로 확대하고 끌어서 옮긴다. 확대해도 얼굴 핀 크기는 그대로다.
class PreviewMap extends StatefulWidget {
  const PreviewMap({
    super.key,
    required this.pins,
    required this.onPinTap,
    required this.center,
    this.me,
    this.onCameraIdle,
  });

  final List<MukMapPin> pins;
  final PinTapCallback onPinTap;
  final LatLng center;
  final LatLng? me;
  final ValueChanged<LatLng>? onCameraIdle;

  @override
  State<PreviewMap> createState() => _PreviewMapState();
}

class _PreviewMapState extends State<PreviewMap> {
  static const _minScale = 0.3, _maxScale = 6.0;
  final _zoom = TransformationController();
  /// 버튼으로 확대할 때의 기준점: 필터 바와 추천 시트 사이, 보이는 지도의 가운데
  Offset _focal = Offset.zero;

  /// 화면 점 → 좌표 변환 (확대 전 배치 기준). build에서 갱신한다.
  LatLng Function(Offset base)? _unproject;

  /// 보이는 지도 가운데의 좌표를 알린다 (확대·이동을 거꾸로 되돌려 계산).
  void _reportCenter() {
    final unproject = _unproject, cb = widget.onCameraIdle;
    if (unproject == null || cb == null) return;
    final inverse = Matrix4.inverted(_zoom.value);
    cb(unproject(MatrixUtils.transformPoint(inverse, _focal)));
  }

  @override
  void didUpdateWidget(covariant PreviewMap old) {
    super.didUpdateWidget(old);
    // 기준 위치가 바뀌면(내 위치 ↔ 전체 보기) 확대를 처음으로 되돌린다.
    if (old.center != widget.center) _zoom.value = Matrix4.identity();
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  /// [focal](기본: 보이는 지도의 가운데)을 기준으로 [factor]배 확대·축소한다.
  void _zoomBy(double factor, [Offset? focal]) {
    final m = _zoom.value;
    final scale = m.getMaxScaleOnAxis();
    final target = (scale * factor).clamp(_minScale, _maxScale);
    final k = target / scale;
    final c = focal ?? _focal;
    _zoom.value = Matrix4.translationValues(c.dx, c.dy, 0)
      ..multiply(Matrix4.diagonal3Values(k, k, 1))
      ..multiply(Matrix4.translationValues(-c.dx, -c.dy, 0))
      ..multiply(m);
    _reportCenter();
  }

  @override
  Widget build(BuildContext context) {
    final pins = widget.pins, me = widget.me, center = widget.center;
    // 내 위치가 지도 가운데(내 주변 보기)면 내 위치도 화면 안에 들어오게 범위에 넣는다.
    final showMe = me != null && me == center;
    final points = [for (final p in pins) p.location, if (showMe) me];
    if (points.isEmpty) points.add(center);
    final lats = points.map((p) => p.lat);
    final lngs = points.map((p) => p.lng);
    final minLat = lats.reduce(math.min);
    final maxLat = lats.reduce(math.max);
    final minLng = lngs.reduce(math.min);
    final maxLng = lngs.reduce(math.max);
    double norm(double v, double lo, double hi) => hi == lo ? 0.5 : (v - lo) / (hi - lo);

    return LayoutBuilder(builder: (context, box) {
      // 핀이 가장자리에서 잘리지 않고, 위쪽 필터 바와 아래쪽 추천 시트(화면의 약 30%)에 가리지 않게 여백을 둔다.
      // 넓은 화면은 추천이 옆 패널이라 아래 여백이 필요 없다.
      final half = FacePin.markerSize.width / 2;
      final left = half + 16, top = 72.0, bottom = isWide(context) ? 48.0 : box.maxHeight * 0.35;
      final w = box.maxWidth - left * 2, h = box.maxHeight - top - bottom - FacePin.markerSize.height;
      _focal = Offset(box.maxWidth / 2, (top + box.maxHeight - bottom) / 2);
      _unproject = (o) => LatLng(
            maxLat - (o.dy - top - FacePin.faceCenterY) / h * (maxLat - minLat),
            minLng + (o.dx - left) / w * (maxLng - minLng),
          );
      // 확대 전 화면에서 좌표가 놓일 점 (얼굴 원의 가운데). 위도는 위로 갈수록 커지므로 뒤집는다.
      Offset spot(LatLng p) => Offset(left + norm(p.lng, minLng, maxLng) * w,
          top + (1 - norm(p.lat, minLat, maxLat)) * h + FacePin.faceCenterY);

      return Stack(children: [
        // 축소하면 그린 지도 바깥이 드러나므로 같은 종이색으로 채운다.
        const Positioned.fill(child: ColoredBox(color: Palette.mapPaper)),
        InteractiveViewer(
          transformationController: _zoom,
          minScale: _minScale,
          maxScale: _maxScale,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          onInteractionEnd: (_) => _reportCenter(),
          child: SizedBox.fromSize(
            size: box.biggest,
            child: const ColoredBox(
              color: Palette.mapPaper,
              child: CustomPaint(painter: _StreetsPainter()),
            ),
          ),
        ),
        // 핀은 지도와 따로 그려서, 확대하면 자리만 옮기고 크기는 유지한다.
        AnimatedBuilder(
          animation: _zoom,
          builder: (context, _) {
            Offset at(LatLng p) => MatrixUtils.transformPoint(_zoom.value, spot(p));
            // 축소해서 핀이 겹치면 하나로 묶고 몇 곳인지 보여 준다. 묶음을 누르면 그 자리로 확대한다.
            final groups = groupPins(pins, (p) => at(p.location));
            return Stack(children: [
              if (showMe)
                Positioned(left: at(me).dx - 11, top: at(me).dy - 11, child: const _MeDot()),
              for (final g in groups)
                if (g.isCluster)
                  Positioned(
                    left: g.offset.dx - ClusterPin.size / 2,
                    top: g.offset.dy - ClusterPin.size / 2,
                    child: ClusterPin(count: g.pins.length, onTap: () => _zoomBy(2, g.offset)),
                  )
                else
                  Positioned(
                    left: g.offset.dx - half,
                    top: g.offset.dy - FacePin.faceCenterY,
                    width: FacePin.markerSize.width,
                    child: FacePin(pin: g.pins.single, onTap: () => widget.onPinTap(g.pins.single.placeId)),
                  ),
            ]);
          },
        ),
        ZoomButtonsPosition(
          child: ZoomButtons(onZoomIn: () => _zoomBy(1.6), onZoomOut: () => _zoomBy(1 / 1.6)),
        ),
      ]);
    });
  }
}

/// 골목길 느낌의 옅은 선. 매번 같은 모양으로 그린다.
class _StreetsPainter extends CustomPainter {
  const _StreetsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final road = Paint()
      ..color = Palette.mapStreet
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final w = size.width, h = size.height;

    // 큰길 두 개
    road.strokeWidth = 14;
    canvas.drawPath(
        Path()
          ..moveTo(-20, h * 0.62)
          ..cubicTo(w * 0.3, h * 0.55, w * 0.6, h * 0.7, w + 20, h * 0.58),
        road);
    canvas.drawPath(
        Path()
          ..moveTo(w * 0.42, -20)
          ..cubicTo(w * 0.47, h * 0.3, w * 0.36, h * 0.6, w * 0.5, h + 20),
        road);

    // 골목
    road.strokeWidth = 5;
    final rnd = math.Random(7);
    for (var i = 0; i < 14; i++) {
      final y = h * (i + 0.5) / 14;
      final x0 = rnd.nextDouble() * w * 0.4;
      canvas.drawLine(Offset(x0, y), Offset(x0 + w * (0.25 + rnd.nextDouble() * 0.4), y + (rnd.nextDouble() - 0.5) * 40), road);
    }
    for (var i = 0; i < 9; i++) {
      final x = w * (i + 0.5) / 9;
      final y0 = rnd.nextDouble() * h * 0.5;
      canvas.drawLine(Offset(x, y0), Offset(x + (rnd.nextDouble() - 0.5) * 30, y0 + h * (0.2 + rnd.nextDouble() * 0.3)), road);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 친구 얼굴이 겹쳐진 핀 + 식당 이름 + 단골 도장.
/// 네이티브 지도에서는 이 위젯을 이미지로 찍어 마커 아이콘으로 쓴다(onTap 없음).
class FacePin extends StatelessWidget {
  const FacePin({super.key, required this.pin, this.onTap});

  final MukMapPin pin;
  final VoidCallback? onTap;

  /// 도장이 얼굴 위로 튀어나오는 만큼 위쪽에 둔 여백. 이미지로 찍을 때 도장이 잘리지 않게 한다.
  static const _topInset = 12.0;

  /// 마커 이미지로 찍을 때의 크기. 얼굴 3개(84) + 도장 · 이름표 최대 너비(128) ·
  /// 높이(위 여백 12 + 얼굴 44 + 4 + 이름표 약 26 + 여유 6).
  static const markerSize = Size(128, 92);

  /// 좌표가 가리키는 점: 얼굴 원의 가운데.
  static const faceCenterY = _topInset + 22;

  @override
  Widget build(BuildContext context) {
    final faces = pin.avatarUrls.take(3).toList();
    final facesWidth = 44.0 + (faces.length - 1) * 20;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(top: _topInset),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: facesWidth + (pin.visits >= 2 ? 16 : 0),
            height: 44,
            child: Stack(clipBehavior: Clip.none, children: [
              for (var i = 0; i < faces.length; i++)
                Positioned(left: i * 20.0, child: Face(url: faces[i], size: 44)),
              if (pin.visits >= 2)
                Positioned(right: -6, top: -8, child: VisitStamp(count: pin.visits, size: 28)),
            ]),
          ),
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxWidth: 128),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Palette.card,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Palette.hairline),
            ),
            child: Text(pin.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium!.copyWith(color: Palette.ink)),
          ),
        ]),
      ),
    );
  }
}

/// 겹친 핀을 묶은 핀. 몇 곳이 모였는지 숫자로 보여 준다.
/// 네이티브 지도에서는 이미지로 찍어 묶음 마커 아이콘으로 쓴다.
class ClusterPin extends StatelessWidget {
  const ClusterPin({super.key, required this.count, this.onTap, this.plus = false});

  final int count;
  final VoidCallback? onTap;

  /// true면 "20+곳"처럼 그 이상이라는 뜻으로 표시 (미리 만든 아이콘 수에 상한이 있을 때)
  final bool plus;

  static const size = 52.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Palette.card,
          border: Border.all(color: Palette.ember, width: 2),
          boxShadow: const [BoxShadow(color: Color(0x261F1A15), blurRadius: 6, offset: Offset(0, 2))],
        ),
        alignment: Alignment.center,
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: plus ? '$count+' : '$count'),
            const TextSpan(text: '곳', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
          ]),
          style: const TextStyle(
            fontSize: 18,
            height: 1,
            fontWeight: FontWeight.w600,
            color: Palette.ember,
            fontFeatures: tabular,
          ),
        ),
      ),
    );
  }
}

/// 내 위치 점 (흰 테두리의 파란 점).
class _MeDot extends StatelessWidget {
  const _MeDot();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '내 위치',
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Palette.myLocation.withValues(alpha: 0.18),
        ),
        alignment: Alignment.center,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Palette.myLocation,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 3, offset: Offset(0, 1))],
          ),
        ),
      ),
    );
  }
}
