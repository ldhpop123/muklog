import 'package:flutter/material.dart';

import 'muk_map_types.dart';

/// 실제 지도 SDK를 붙이기 전까지 쓰는 임시 지도.
/// 핀 좌표를 화면 영역에 비례 배치해 얼굴 핀 UI를 미리 확인할 수 있다.
class PreviewMap extends StatelessWidget {
  const PreviewMap({super.key, required this.pins, required this.onPinTap});

  final List<MukMapPin> pins;
  final PinTapCallback onPinTap;

  @override
  Widget build(BuildContext context) {
    if (pins.isEmpty) return const Center(child: Text('표시할 핀이 없어요'));

    final lats = pins.map((p) => p.location.lat);
    final lngs = pins.map((p) => p.location.lng);
    final minLat = lats.reduce((a, b) => a < b ? a : b);
    final maxLat = lats.reduce((a, b) => a > b ? a : b);
    final minLng = lngs.reduce((a, b) => a < b ? a : b);
    final maxLng = lngs.reduce((a, b) => a > b ? a : b);
    double norm(double v, double lo, double hi) =>
        hi == lo ? 0.5 : (v - lo) / (hi - lo);

    return LayoutBuilder(builder: (context, box) {
      // 핀이 가장자리에서 잘리지 않고, 위쪽 필터 바와 아래쪽 추천 시트(화면의 약 30%)에 가리지 않게 여백을 둔다.
      final half = FacePin.markerSize.width / 2;
      final left = half + 16, top = 72.0, bottom = box.maxHeight * 0.35;
      final w = box.maxWidth - left * 2,
          h = box.maxHeight - top - bottom - FacePin.markerSize.height;
      return Container(
        color: const Color(0xFFEFEDE6),
        child: Stack(children: [
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

/// 친구 얼굴이 겹쳐진 핀 + 식당 이름.
/// 네이티브 지도에서는 이 위젯을 이미지로 찍어 마커 아이콘으로 쓴다(onTap 없음).
class FacePin extends StatelessWidget {
  const FacePin({super.key, required this.pin, this.onTap});

  final MukMapPin pin;
  final VoidCallback? onTap;

  /// 마커 이미지로 찍을 때의 크기. 얼굴 3개(76) · 이름표 최대 너비(120) · 높이(40 + 2 + 이름표)를 담는다.
  static const markerSize = Size(120, 64);

  @override
  Widget build(BuildContext context) {
    final faces = pin.avatarUrls.take(3).toList();
    final color = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 40.0 + (faces.length - 1) * 18,
          height: 40,
          child: Stack(children: [
            for (var i = 0; i < faces.length; i++)
              Positioned(
                left: i * 18.0,
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: color,
                  child: CircleAvatar(
                      radius: 17, backgroundImage: NetworkImage(faces[i])),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 2),
        Container(
          constraints: const BoxConstraints(maxWidth: 120),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(6)),
          child: Text(pin.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.black)),
        ),
      ]),
    );
  }
}
