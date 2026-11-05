import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../models/place.dart';
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
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/record/new?placeId=$placeId'),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('다녀왔어요'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(place.name, style: text.headlineSmall),
                const SizedBox(height: 4),
                Text('${categoryLabel(place.category)} · ${place.area}', style: text.bodyMedium),
                const SizedBox(height: 8),
                Text(place.tags.map((t) => '#$t').join('  '), style: text.bodyMedium!.copyWith(color: Palette.ink)),
              ]),
            ),
            if (place.revisitTotal >= 2) VisitStamp(count: place.revisitTotal, size: 56),
          ]),
          if (me != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Palette.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Palette.hairline),
              ),
              child: Row(children: [
                Expanded(child: Text('내 입맛과 맞는 정도', style: text.bodyMedium)),
                Text('${me.taste.couplePercent(place.taste)}%',
                    style: text.titleLarge!.copyWith(color: Palette.ember, fontFeatures: tabular)),
              ]),
            ),
          ],
          const SizedBox(height: 32),
          Text('다녀간 사람들의 기록', style: text.titleMedium),
          const SizedBox(height: 8),
          records.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('기록을 불러오지 못했어요. $e', style: text.bodyMedium),
            data: (rs) => Column(children: [
              for (final r in rs)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Face(url: authors[r.userId]?.avatarUrl, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(r.userId == me?.id ? '나' : authors[r.userId]?.nickname ?? '알 수 없음',
                              style: text.bodyLarge!.copyWith(fontWeight: FontWeight.w500)),
                          const SizedBox(width: 8),
                          const Icon(Icons.star_rounded, size: 16, color: Palette.ember),
                          const SizedBox(width: 2),
                          Text(r.rating.toStringAsFixed(1),
                              style: text.bodyMedium!.copyWith(color: Palette.ink, fontFeatures: tabular)),
                        ]),
                        if (r.memo.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(r.memo, style: text.bodyLarge),
                        ],
                        if (r.photoUrls.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final url in r.photoUrls)
                              PhotoThumb(url: url, size: 72, onTap: () => _showPhoto(context, url)),
                          ]),
                        ],
                        // "이 기록 보고 왔어요" → 방문 후 기록에 inspiredBy로 연결 (맛 신뢰 온도).
                        // 내 기록에는 달 수 없다 (서버도 거절).
                        if (r.userId != me?.id)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Palette.inkSoft,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => context.push('/record/new?placeId=$placeId&inspiredBy=${r.id}'),
                            icon: const Icon(Icons.thumb_up_alt_outlined, size: 16),
                            label: const Text('이 기록 보고 다녀왔어요'),
                          ),
                      ]),
                    ),
                    if (r.visitNo >= 2) VisitStamp(count: r.visitNo),
                  ]),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// 사진을 화면 가득 보여 준다. 두 손가락으로 확대할 수 있다.
void _showPhoto(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    barrierColor: const Color(0xE61F1A15),
    builder: (context) => GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: InteractiveViewer(
        maxScale: 4,
        child: Center(child: Image(image: PhotoThumb.providerFor(url), fit: BoxFit.contain)),
      ),
    ),
  );
}
