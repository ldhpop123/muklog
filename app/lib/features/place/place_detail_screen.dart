import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../models/user_profile.dart';
import '../../models/visit_record.dart';

final placeRecordsProvider = FutureProvider.family<List<VisitRecord>, String>(
    (ref, placeId) => ref.watch(repositoryProvider).recordsForPlace(placeId));

class PlaceDetailScreen extends ConsumerWidget {
  const PlaceDetailScreen({super.key, required this.placeId});

  final String placeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = ref
        .watch(placesProvider)
        .valueOrNull
        ?.where((p) => p.id == placeId)
        .firstOrNull;
    final me = ref.watch(meProvider).valueOrNull;
    // 기록 작성자 조회용. 내 기록도 함께 보여야 하므로 나를 포함한다.
    final authors = {
      for (final f in ref.watch(friendsProvider).valueOrNull ?? <UserProfile>[])
        f.id: f,
      if (me != null) me.id: me,
    };
    final records = ref.watch(placeRecordsProvider(placeId));

    if (place == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    }

    return Scaffold(
      appBar: AppBar(title: Text(place.name)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/record/new?placeId=$placeId'),
        icon: const Icon(Icons.edit),
        label: const Text('기록하기'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${place.category} · 친구 재방문 ${place.revisitTotal}회'),
          const SizedBox(height: 8),
          Wrap(
              spacing: 6,
              children: [for (final t in place.tags) Chip(label: Text('#$t'))]),
          if (me != null) ...[
            const SizedBox(height: 8),
            Text('나와의 예상 적합도 ${me.taste.couplePercent(place.taste)}%',
                style: Theme.of(context).textTheme.titleMedium),
          ],
          const Divider(height: 32),
          Text('친구들의 기록', style: Theme.of(context).textTheme.titleMedium),
          records.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('기록을 불러오지 못했어요\n$e'),
            data: (rs) => Column(children: [
              for (final r in rs)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundImage: authors[r.userId] == null
                        ? null
                        : NetworkImage(authors[r.userId]!.avatarUrl),
                  ),
                  title: Text(
                      '${r.userId == me?.id ? '나' : authors[r.userId]?.nickname ?? '알 수 없음'}'
                      ' · ★${r.rating} · ${r.visitNo}번째 방문'),
                  subtitle: Text(r.memo),
                  // "이 기록 보고 왔어요" → 방문 후 기록에 inspiredBy로 연결 (맛 신뢰 온도).
                  // 내 기록에는 달 수 없다 (서버도 거절).
                  trailing: r.userId == me?.id
                      ? null
                      : IconButton(
                          tooltip: '이 기록 보고 왔어요',
                          icon: const Icon(Icons.thumb_up_alt_outlined),
                          onPressed: () => context.push(
                              '/record/new?placeId=$placeId&inspiredBy=${r.id}'),
                        ),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}
