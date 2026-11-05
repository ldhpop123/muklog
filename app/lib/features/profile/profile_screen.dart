import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../models/taste_vector.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final friends = ref.watch(friendsProvider).valueOrNull ?? [];
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('프로필')),
      body: me.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('프로필을 불러오지 못했어요. $e')),
        data: (me) {
          final sorted = [...friends]
            ..sort((a, b) => me.taste.couplePercent(b.taste).compareTo(me.taste.couplePercent(a.taste)));
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Row(children: [
                Face(url: me.avatarUrl, size: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(me.nickname, style: text.titleLarge),
                    const SizedBox(height: 2),
                    Text(me.title ?? '아직 칭호가 없어요', style: text.bodyMedium),
                  ]),
                ),
              ]),
              const SizedBox(height: 20),
              TrustGauge(temp: me.trustTemp, level: me.level),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/ranking'),
                    icon: const Icon(Icons.emoji_events_outlined, size: 18),
                    label: const Text('미식가 랭킹'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/dislikes'),
                    icon: const Icon(Icons.block, size: 18),
                    label: const Text('불호 · 알레르기'),
                  ),
                ),
              ]),
              const SizedBox(height: 32),
              Text('나의 입맛', style: text.titleMedium),
              const SizedBox(height: 16),
              for (var i = 0; i < TasteVector.labels.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 72, child: Text(TasteVector.labels[i], style: text.bodyLarge)),
                    Expanded(
                      child: TasteAxis(
                        low: TasteVector.poles[i].$1,
                        high: TasteVector.poles[i].$2,
                        me: me.taste.toList()[i],
                      ),
                    ),
                  ]),
                ),
              const SizedBox(height: 16),
              Text('친구와의 입맛 커플링', style: text.titleMedium),
              const SizedBox(height: 4),
              for (final f in sorted)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => context.push('/friend/${f.id}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(children: [
                      Face(url: f.avatarUrl, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(f.nickname, style: text.bodyLarge),
                          Text(
                            '${f.trustTemp.toStringAsFixed(1)}℃ · ${f.title ?? f.level}',
                            style: text.bodyMedium!.copyWith(fontFeatures: tabular),
                          ),
                        ]),
                      ),
                      Text('${me.taste.couplePercent(f.taste)}%',
                          style: text.titleLarge!.copyWith(fontFeatures: tabular)),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, size: 18, color: Palette.inkMuted),
                    ]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
