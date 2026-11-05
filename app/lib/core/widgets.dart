import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'config.dart';
import 'theme.dart';

/// 단골 도장. 재방문 횟수를 노포 쿠폰 도장처럼 찍는다. 먹로그 전체에서 재방문은 이 모양으로만 보여 준다.
class VisitStamp extends StatelessWidget {
  const VisitStamp({super.key, required this.count, this.size = 36});

  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -8 * math.pi / 180,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Palette.card,
          border: Border.all(color: Palette.ember, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Container(
          width: size - 6,
          height: size - 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Palette.ember.withValues(alpha: 0.5), width: 0.75),
          ),
          alignment: Alignment.center,
          child: Text(
            '$count회',
            style: TextStyle(
              fontSize: size * 0.3,
              height: 1,
              fontWeight: FontWeight.w600,
              color: Palette.ember,
              fontFeatures: tabular,
            ),
          ),
        ),
      ),
    );
  }
}

/// 맛 신뢰 온도 게이지 (README 7.3). 30~50℃ 눈금 위에 레벨 구간과 현재 온도를 표시한다.
class TrustGauge extends StatelessWidget {
  const TrustGauge({super.key, required this.temp, required this.level});

  final double temp;
  final String level;

  static const _min = 30.0, _max = 50.0;
  /// 레벨이 바뀌는 온도 (동네 맛잘알 · 지역 감별사 · 먹로그 마스터)
  static const _marks = [36.5, 40.0, 45.0];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ratio = ((temp - _min) / (_max - _min)).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Palette.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('맛 신뢰 온도', style: text.bodyMedium),
          const Spacer(),
          Text(level, style: text.bodyMedium),
        ]),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: temp.toStringAsFixed(1)),
            TextSpan(text: '℃', style: text.titleLarge!.copyWith(color: Palette.ember)),
          ]),
          style: text.displaySmall!.copyWith(color: Palette.ember, fontFeatures: tabular),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth;
          double x(double v) => (v - _min) / (_max - _min) * w;
          return SizedBox(
            height: 36,
            child: Stack(clipBehavior: Clip.none, children: [
              // 30℃에서 50℃까지의 눈금 바탕
              Positioned(
                left: 0,
                right: 0,
                top: 6,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(color: Palette.raised, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              Positioned(
                left: 0,
                top: 6,
                child: Container(
                  width: math.max(8, w * ratio),
                  height: 8,
                  decoration: BoxDecoration(color: Palette.ember, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              for (final v in _marks) ...[
                Positioned(
                  left: x(v) - 0.5,
                  top: 2,
                  child: Container(width: 1, height: 16, color: Palette.ink.withValues(alpha: 0.25)),
                ),
                Positioned(
                  left: x(v) - 20,
                  width: 40,
                  top: 22,
                  child: Text(v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1),
                      textAlign: TextAlign.center, style: text.bodySmall!.copyWith(fontFeatures: tabular)),
                ),
              ],
            ]),
          );
        }),
      ]),
    );
  }
}

/// 얼굴 사진. 종이 위에 붙인 사진처럼 흰 테두리를 두른다.
class Face extends StatelessWidget {
  const Face({super.key, required this.url, this.size = 40});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size >= 40 ? 2.5 : 2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Palette.card,
        boxShadow: const [BoxShadow(color: Color(0x1A1F1A15), blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: ClipOval(
        child: url == null
            ? const ColoredBox(color: Palette.raised)
            : Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Palette.raised)),
      ),
    );
  }
}

/// -1 ~ +1 축 위의 점 하나 또는 둘 (내 입맛, 친구 입맛).
class TasteAxis extends StatelessWidget {
  const TasteAxis({super.key, required this.low, required this.high, required this.me, this.them});

  final String low;
  final String high;
  final double me;
  final double? them;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    Widget dot(Color fill, {bool ring = false}) => Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: ring ? Palette.inkSoft : Palette.card, width: 2),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (context, box) {
        double x(double v) => (v.clamp(-1.0, 1.0) + 1) / 2 * (box.maxWidth - 14);
        return SizedBox(
          height: 14,
          child: Stack(children: [
            Positioned(left: 7, right: 7, top: 6, child: Container(height: 2, color: Palette.raised)),
            Positioned(left: box.maxWidth / 2 - 0.5, top: 3, child: Container(width: 1, height: 8, color: Palette.hairline)),
            if (them != null) Positioned(left: x(them!), child: dot(Palette.card, ring: true)),
            Positioned(left: x(me), child: dot(Palette.ember)),
          ]),
        );
      }),
      const SizedBox(height: 4),
      Row(children: [Text(low, style: small), const Spacer(), Text(high, style: small)]),
    ]);
  }
}

/// 이 폭 이상이면 PC 레이아웃 (세로 내비게이션 · 지도 옆 패널 · 가운데 정렬 화면).
const wideBreakpoint = 900.0;

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= wideBreakpoint;

/// 넓은 화면에서 글줄이 너무 길어지지 않게 가운데 [maxWidth] 폭으로 맞춘다. 좁은 화면에서는 그대로.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({super.key, required this.child, this.maxWidth = 560});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Palette.page,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      ),
    );
  }
}

/// 기록 사진 썸네일. 서버 경로(/uploads/...)는 서버 주소를 붙이고, 목 데이터의 data: URL은 바로 그린다.
class PhotoThumb extends StatelessWidget {
  const PhotoThumb({super.key, required this.url, this.size = 72, this.onTap});

  final String url;
  final double size;
  final VoidCallback? onTap;

  static ImageProvider providerFor(String url) {
    if (url.startsWith('data:')) return MemoryImage(UriData.parse(url).contentAsBytes());
    final full = url.startsWith('/') ? '${AppConfig.apiBaseUrl}$url' : url;
    return NetworkImage(full);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image(
          image: providerFor(url),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: size,
            height: size,
            color: Palette.raised,
            child: const Icon(Icons.broken_image_outlined, size: 20, color: Palette.inkMuted),
          ),
        ),
      ),
    );
  }
}
