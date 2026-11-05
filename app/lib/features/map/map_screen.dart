import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/location.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../models/place.dart';
import '../../models/social.dart';
import 'briefing_section.dart';
import 'briefing_state.dart';
import 'widgets/muk_map.dart';

const mapTagOptions = ['노포', '아재입맛', '혼밥', '안주맛집', '데이트', '가성비', '매운맛', '감성'];

/// 지도 필터: 친구 레이어(전체/친구/나) + 취향 태그.
class MapFilter {
  const MapFilter({this.layer = MapLayer.all, this.tags = const {}});
  final MapLayer layer;
  final Set<String> tags;

  MapFilter copyWith({MapLayer? layer, Set<String>? tags}) =>
      MapFilter(layer: layer ?? this.layer, tags: tags ?? this.tags);
}

final mapFilterProvider = StateProvider<MapFilter>((ref) => const MapFilter());

/// 식당마다 다녀간 친구(와 나)의 얼굴을 모은 핀 목록.
final mapPinsProvider = FutureProvider<List<MukMapPin>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  final filter = ref.watch(mapFilterProvider);
  final near = await ref.watch(searchCenterProvider.future);
  final places = await repo.places(
      tags: filter.tags.toList(), layer: filter.layer, near: near, radiusKm: nearbyRadiusKm);
  final me = await ref.watch(meProvider.future);
  final authors = {
    for (final f in await ref.watch(friendsProvider.future)) f.id: f,
    me.id: me,
  };

  final pins = <MukMapPin>[];
  for (final p in places) {
    // TODO(api): 지도 영역(bbox) 단위로 핀과 얼굴을 한 번에 받는 API로 바꾸기
    final records = await repo.recordsForPlace(p.id);
    final shown = records
        .where((r) => switch (filter.layer) {
              MapLayer.mine => r.userId == me.id,
              MapLayer.friends => r.userId != me.id,
              MapLayer.all => true,
            })
        .toList();
    // 사람마다 가장 높은 방문 회차를 더한다 (같은 사람의 기록 여러 개를 중복으로 세지 않음)
    final visitsByUser = <String, int>{};
    for (final r in shown) {
      visitsByUser[r.userId] = math.max(visitsByUser[r.userId] ?? 0, r.visitNo);
    }
    final faces = shown
        .map((r) => authors[r.userId]?.avatarUrl)
        .whereType<String>()
        .toSet()
        .toList();
    if (faces.isEmpty) continue;
    pins.add(MukMapPin(
        placeId: p.id,
        label: p.name,
        location: p.location,
        avatarUrls: faces,
        visits: visitsByUser.values.fold(0, (a, b) => a + b)));
  }
  return pins;
});

class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pins = ref.watch(mapPinsProvider);
    final location = ref.watch(myLocationProvider).valueOrNull;
    final nearMe = ref.watch(nearMeProvider);
    final me = location?.position;
    // 내 주변 보기면 내 위치, 전체 보기면 친구 기록이 모인 곳(홍대)을 가운데에 둔다.
    final center = nearMe && me != null ? me : defaultMapCenter;
    final wide = isWide(context);
    final map = Stack(children: [
      pins.when(
        data: (pins) => MukMap(
          pins: pins,
          onPinTap: (id) => context.push('/place/$id'),
          me: me,
          center: center,
          onCameraIdle: (c) => ref.read(mapViewCenterProvider.notifier).state = c,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('지도를 불러오지 못했어요. $e')),
      ),
      const Positioned(top: 8, left: 0, right: 0, child: _FilterBar()),
      Positioned(top: 104, left: 0, right: 0, child: Center(child: _BriefHereButton(fallback: center))),
      Positioned(
        top: 56,
        left: 12,
        right: 12,
        child: _LocationBanner(
          location: location,
          nearMe: nearMe,
          empty: pins.valueOrNull?.isEmpty ?? false,
        ),
      ),
      Positioned(
        right: 12,
        bottom: wide ? 24 : MediaQuery.sizeOf(context).height * 0.32 + 12,
        child: FloatingActionButton.small(
          heroTag: 'my-location',
          tooltip: '내 위치',
          backgroundColor: Palette.card,
          foregroundColor: Palette.ink,
          onPressed: () {
            ref.read(nearMeProvider.notifier).state = true;
            ref.invalidate(myLocationProvider);
          },
          child: const Icon(Icons.my_location, size: 20),
        ),
      ),
      if (!wide) const _RecommendSheet(wide: false),
    ]);
    return Scaffold(
      // 넓은 화면은 왼쪽 내비게이션에 이름이 있으므로 앱바를 생략한다.
      appBar: wide
          ? null
          : AppBar(title: const Text('먹로그'), actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton.icon(
                  onPressed: () => context.push('/record/search'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 12)),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('다녀왔어요'),
                ),
              ),
            ]),
      body: wide
          ? Row(children: [
              Expanded(child: SafeArea(child: map)),
              const SizedBox(width: 400, child: _RecommendSheet(wide: true)),
            ])
          : map,
    );
  }
}

/// 지도를 브리핑 기준점에서 멀리 옮기면 나타나는 "이 지역 브리핑 보기" 버튼.
/// 누르면 지금 화면 가운데를 기준으로 주변 상권과 브리핑을 다시 고른다.
class _BriefHereButton extends ConsumerWidget {
  const _BriefHereButton({required this.fallback});

  /// 아직 브리핑 기준점을 정한 적이 없을 때의 기준 (처음 지도 가운데)
  final LatLng fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(mapViewCenterProvider);
    final base = ref.watch(briefingCenterProvider) ?? fallback;
    final show = view != null && view.distanceKm(base) > briefingRefreshDistanceKm;
    return AnimatedSwitcher(
      duration: motionFast,
      child: !show
          ? const SizedBox.shrink()
          : Material(
              key: const ValueKey('brief-here'),
              color: Palette.ink,
              elevation: 2,
              shadowColor: const Color(0x401F1A15),
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () {
                  ref.read(briefingCenterProvider.notifier).state = view;
                  ref.read(selectedAreaProvider.notifier).state = null;
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.refresh, size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    Text('이 지역 브리핑 보기',
                        style: Theme.of(context).textTheme.labelLarge!.copyWith(color: Colors.white)),
                  ]),
                ),
              ),
            ),
    );
  }
}

/// 위치 상태 안내: 위치를 못 가져왔거나, 내 주변에 친구 기록이 없을 때만 보인다.
class _LocationBanner extends ConsumerWidget {
  const _LocationBanner({required this.location, required this.nearMe, required this.empty});

  final MyLocation? location;
  final bool nearMe;
  final bool empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    String? message;
    String? action;
    VoidCallback? onAction;
    if (location != null && location!.position == null) {
      message = '${location!.reason} · 홍대 기준으로 보여 드려요';
    } else if (location != null && nearMe && empty) {
      message = '내 주변 ${nearbyRadiusKm.toStringAsFixed(0)}km 안에 친구 기록이 없어요';
      action = '전체 보기';
      onAction = () => ref.read(nearMeProvider.notifier).state = false;
    } else if (!nearMe) {
      message = '친구 기록 전체를 보고 있어요';
      action = '내 주변';
      onAction = () => ref.read(nearMeProvider.notifier).state = true;
    }
    if (message == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.topLeft,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        decoration: BoxDecoration(
          color: Palette.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Palette.hairline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.near_me_outlined, size: 16, color: Palette.inkMuted),
          const SizedBox(width: 8),
          Flexible(child: Text(message, style: text.bodyMedium)),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: Palette.ember),
              child: Text(action),
            )
          else
            const SizedBox(width: 8, height: 36),
        ]),
      ),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(mapFilterProvider);
    final notifier = ref.read(mapFilterProvider.notifier);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        SegmentedButton<MapLayer>(
          segments: const [
            ButtonSegment(value: MapLayer.all, label: Text('전체')),
            ButtonSegment(value: MapLayer.friends, label: Text('친구')),
            ButtonSegment(value: MapLayer.mine, label: Text('나')),
          ],
          selected: {filter.layer},
          showSelectedIcon: false,
          onSelectionChanged: (s) =>
              notifier.state = filter.copyWith(layer: s.first),
        ),
        const SizedBox(width: 8),
        for (final t in mapTagOptions)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: Text('#$t'),
              selected: filter.tags.contains(t),
              onSelected: (on) => notifier.state = filter.copyWith(
                  tags:
                      on ? {...filter.tags, t} : ({...filter.tags}..remove(t))),
            ),
          ),
      ]),
    );
  }
}

/// 지도 위로 끌어올리는 시트: AI 지역 브리핑 + 개인화 추천 목록 (Fit × Trust × Context).
/// 좁은 화면은 지도 위로 끌어올리는 시트, 넓은 화면은 지도 오른쪽에 고정된 패널.
class _RecommendSheet extends ConsumerWidget {
  const _RecommendSheet({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recs = ref.watch(recommendProvider);
    final text = Theme.of(context).textTheme;

    Widget panel(ScrollController? controller) => ListView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(20, wide ? 24 : 8, 20, 24),
          children: [
            if (!wide)
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: Palette.raised,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
            const BriefingSection(),
            const Divider(height: 24),
            Text('내 입맛에 맞는 순서', style: text.titleMedium),
            const SizedBox(height: 4),
            recs.when(
              loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator())),
              error: (e, _) =>
                  Text('추천을 불러오지 못했어요. $e', style: text.bodyMedium),
              data: (items) => Column(children: [
                for (final s in items)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => context.push('/place/${s.place.id}'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.place.name, style: text.bodyLarge),
                                const SizedBox(height: 2),
                                Text(
                                    s.reason ??
                                        '${categoryLabel(s.place.category)} · ${s.place.area}',
                                    style: text.bodyMedium),
                              ]),
                        ),
                        if (s.place.revisitTotal >= 2)
                          VisitStamp(count: s.place.revisitTotal, size: 36),
                      ]),
                    ),
                  ),
              ]),
            ),
          ],
        );

    if (wide) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          color: Palette.card,
          border: Border(left: BorderSide(color: Palette.hairline)),
        ),
        child: SafeArea(child: panel(null)),
      );
    }
    return DraggableScrollableSheet(
      initialChildSize: 0.32,
      minChildSize: 0.12,
      maxChildSize: 0.85,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: Palette.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
                color: Color(0x141F1A15), blurRadius: 24, offset: Offset(0, -4))
          ],
        ),
        child: panel(controller),
      ),
    );
  }
}
