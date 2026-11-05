import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../models/taste_vector.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final friends = ref.watch(friendsProvider).valueOrNull ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('프로필')),
      body: me.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('프로필을 불러오지 못했어요\n$e')),
        data: (me) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              leading: CircleAvatar(
                  radius: 28, backgroundImage: NetworkImage(me.avatarUrl)),
              title: Text(me.nickname),
              subtitle: Text(
                  '맛 신뢰 온도 ${me.trustTemp.toStringAsFixed(1)}℃ · ${me.level}'
                  '${me.title == null ? '' : ' · ${me.title}'}'),
            ),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/ranking'),
                  icon: const Icon(Icons.emoji_events_outlined),
                  label: const Text('미식가 랭킹'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/dislikes'),
                  icon: const Icon(Icons.block),
                  label: const Text('불호 · 알레르기'),
                ),
              ),
            ]),
            const Divider(height: 32),
            Text('나의 입맛', style: Theme.of(context).textTheme.titleMedium),
            // TODO(ui): 레이더 차트로 교체
            _TasteBars(taste: me.taste),
            const Divider(height: 32),
            Text('친구와의 입맛 커플링', style: Theme.of(context).textTheme.titleMedium),
            for (final f in [...friends]..sort((a, b) => me.taste
                .couplePercent(b.taste)
                .compareTo(me.taste.couplePercent(a.taste))))
              ListTile(
                leading:
                    CircleAvatar(backgroundImage: NetworkImage(f.avatarUrl)),
                title: Text(f.nickname),
                subtitle: Text(
                    '${f.trustTemp.toStringAsFixed(1)}℃${f.title == null ? '' : ' · ${f.title}'}'),
                trailing: Text('${me.taste.couplePercent(f.taste)}%',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                onTap: () => context.push('/friend/${f.id}'),
              ),
          ],
        ),
      ),
    );
  }
}

class _TasteBars extends StatelessWidget {
  const _TasteBars({required this.taste});
  final TasteVector taste;

  @override
  Widget build(BuildContext context) {
    final values = taste.toList();
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(children: [
      for (var i = 0; i < values.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(width: 72, child: Text(TasteVector.labels[i])),
            SizedBox(
                width: 72,
                child: Text(TasteVector.poles[i].$1,
                    style: small, textAlign: TextAlign.end)),
            const SizedBox(width: 8),
            Expanded(
                child: LinearProgressIndicator(value: (values[i] + 1) / 2)),
            const SizedBox(width: 8),
            SizedBox(
                width: 96,
                child: Text(TasteVector.poles[i].$2,
                    style: small, maxLines: 1, softWrap: false)),
          ]),
        ),
    ]);
  }
}
