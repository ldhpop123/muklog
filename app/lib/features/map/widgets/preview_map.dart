import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import 'muk_map_types.dart';

/// 실제 지도 SDK를 붙이기 전까지 쓰는 임시 지도.
/// 종이 위 골목 지도처럼 그리고, 핀 좌표를 화면 영역에 비례 배치해 얼굴 핀 UI를 확인할 수 있다.
class PreviewMap extends StatelessWidget {
  const PreviewMap({super.key, required this.pins, required this.onPinTap});

  final List<MukMapPin> pins;
  final PinTapCallback onPinTap;

  @override
  Widget build(BuildContext context) {
    final lats = pins.map((p) => p.location.lat);
    final lngs = pins.map((p) => p.location.lng);
    final minLat = pins.isEmpty ? 0.0 : lats.reduce(math.min);
    final maxLat = pins.isEmpty ? 0.0 : lats.reduce(math.max);
    final minLng = pins.isEmpty ? 0.0 : lngs.reduce(math.min);
    final maxLng = pins.isEmpty ? 0.0 : lngs.reduce(math.max);
    double norm(double v, double lo, double hi) => hi == lo ? 0.5 : (v - lo) / (hi - lo);

    return LayoutBuilder(builder: (context, box) {
      // 핀이 가장자리에서 잘리지 않고, 위쪽 필터 바와 아래쪽 추천 시트(화면의 약 30%)에 가리지 않게 여백을 둔다.
      // 넓은 화면은 추천이 옆 패널이라 아래 여백이 필요 없다.
      final half = FacePin.markerSize.width / 2;
      final left = half + 16, top = 72.0, bottom = isWide(context) ? 48.0 : box.maxHeight * 0.35;
      final w = box.maxWidth - left * 2, h = box.maxHeight - top - bottom - FacePin.markerSize.height;
      return ColoredBox(
        color: Palette.mapPaper,
        child: Stack(children: [
          const Positioned.fill(child: CustomPaint(painter: _StreetsPainter())),
          if (pins.isEmpty)
            Center(child: Text('조건에 맞는 친구 기록이 없어요', style: Theme.of(context).textTheme.bodyMedium)),
          for (final pin in pins)
            Positioned(
              left: left + norm(pin.location.lng, minLng, maxLng) * w - half,
              // 위도는 위로 갈수록 커지므로 뒤집는다.
              top: top + (1 - norm(pin.location.lat, minLat, maxLat)) * h,
              width: FacePin.markerSize.width,
              child: FacePin(pin: pin, onTap: () => onPinTap(pin.placeId)),
            ),
        ]),
      );
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

  /// 마커 이미지로 찍을 때의 크기. 얼굴 3개(84) + 도장 · 이름표 최대 너비(128) · 높이(얼굴 44 + 4 + 이름표 24).
  static const markerSize = Size(128, 72);

  @override
  Widget build(BuildContext context) {
    final faces = pin.avatarUrls.take(3).toList();
    final facesWidth = 44.0 + (faces.length - 1) * 20;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
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
    );
  }
}
