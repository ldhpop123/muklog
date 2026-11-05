import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/muklog_repository.dart';
import '../../data/providers.dart';
import '../../models/social.dart';
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
final briefingAreaProvider =
    StateProvider<String>((ref) => briefingAreas.first);

/// 식당마다 다녀간 친구(와 나)의 얼굴을 모은 핀 목록.
final mapPinsProvider = FutureProvider<List<MukMapPin>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  final filter = ref.watch(mapFilterProvider);
  final places =
      await repo.places(tags: filter.tags.toList(), layer: filter.layer);
  final me = await ref.watch(meProvider.future);
  final authors = {
    for (final f in await ref.watch(friendsProvider.future)) f.id: f,
    me.id: me,
  };

  final pins = <MukMapPin>[];
  for (final p in places) {
    // TODO(api): 지도 영역(bbox) 단위로 핀과 얼굴을 한 번에 받는 API로 바꾸기
    final records = await repo.recordsForPlace(p.id);
    final faces = records
        .where((r) => switch (filter.layer) {
              MapLayer.mine => r.userId == me.id,
              MapLayer.friends => r.userId != me.id,
              MapLayer.all => true,
            })
        .map((r) => authors[r.userId]?.avatarUrl)
        .whereType<String>()
        .toSet()
        .toList();
    if (faces.isEmpty) continue;
    pins.add(MukMapPin(
        placeId: p.id, label: p.name, location: p.location, avatarUrls: faces));
  }
  return pins;
});

class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pins = ref.watch(mapPinsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('먹로그')),
      body: Stack(children: [
        pins.when(
          data: (pins) =>
              MukMap(pins: pins, onPinTap: (id) => context.push('/place/$id')),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('지도를 불러오지 못했어요\n$e')),
        ),
        const Positioned(top: 8, left: 0, right: 0, child: _FilterBar()),
        const _RecommendSheet(),
      ]),
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
          style: const ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(Colors.white)),
          onSelectionChanged: (s) =>
              notifier.state = filter.copyWith(layer: s.first),
        ),
        const SizedBox(width: 8),
        for (final t in mapTagOptions)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: Text('#$t'),
              backgroundColor: Colors.white,
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
class _RecommendSheet extends ConsumerWidget {
  const _RecommendSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final area = ref.watch(briefingAreaProvider);
    final briefing = ref.watch(briefingProvider(area));
    final recs = ref.watch(recommendProvider);
    final titleStyle = Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(fontWeight: FontWeight.w700);

    return DraggableScrollableSheet(
      initialChildSize: 0.3,
      minChildSize: 0.12,
      maxChildSize: 0.85,
      builder: (context, controller) => Material(
        elevation: 8,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            Text('친구들의 맛집 브리핑', style: titleStyle),
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              for (final a in briefingAreas)
                ChoiceChip(
                  label: Text(a),
                  selected: a == area,
                  onSelected: (_) =>
                      ref.read(briefingAreaProvider.notifier).state = a,
                ),
            ]),
            const SizedBox(height: 8),
            briefing.when(
              loading: () => const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(),
                    SizedBox(height: 6),
                    Text('친구들의 기록을 요약하고 있어요'),
                  ]),
              error: (e, _) => Text('브리핑을 불러오지 못했어요: $e'),
              data: (b) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final s in b.sentences)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(s)),
                    if (!b.byLlm)
                      Text('AI 요약 대신 기본 문장으로 보여 드려요',
                          style: Theme.of(context).textTheme.bodySmall),
                  ]),
            ),
            const Divider(height: 28),
            Text('내 입맛 맞춤 추천', style: titleStyle),
            recs.when(
              loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Text('추천을 불러오지 못했어요\n$e'),
              data: (items) => Column(children: [
                for (final s in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.place.name),
                    subtitle: Text(s.reason ?? s.place.tags.join(' · ')),
                    onTap: () => context.push('/place/${s.place.id}'),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
