import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../models/taste_vector.dart';

/// 친구 비교: 입맛 커플링 지수, 차원별 비교, 친구가 만족한 곳 중 내가 안 가 본 곳 (README 8.2).
class FriendCompareScreen extends ConsumerWidget {
  const FriendCompareScreen({super.key, required this.friendId});

  final String friendId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coupling = ref.watch(coupleProvider(friendId));
    final me = ref.watch(meProvider).valueOrNull;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('입맛 비교')),
      body: coupling.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (c) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Row(children: [
              SizedBox(
                width: 72,
                height: 48,
                child: Stack(children: [
                  Face(url: me?.avatarUrl, size: 48),
                  Positioned(left: 28, child: Face(url: c.user.avatarUrl, size: 48)),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('나와 ${c.user.nickname}님', style: text.titleMedium),
                  Text('같이 가 본 곳 ${c.sharedPlaceCount}곳',
                      style: text.bodyMedium!.copyWith(fontFeatures: tabular)),
                ]),
              ),
              Text('${c.percent}%',
                  style: text.displaySmall!.copyWith(color: Palette.ember, fontFeatures: tabular)),
            ]),
            const SizedBox(height: 32),
            Row(children: [
              Text('차원별 비교', style: text.titleMedium),
              const Spacer(),
              _key(Palette.ember, '나', text),
              const SizedBox(width: 12),
              _key(Palette.card, c.user.nickname, text, ring: true),
            ]),
            const SizedBox(height: 16),
            for (var i = 0; i < c.dimensions.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 72, child: Text(c.dimensions[i].label, style: text.bodyLarge)),
                  Expanded(
                    child: TasteAxis(
                      low: TasteVector.poles[i].$1,
                      high: TasteVector.poles[i].$2,
                      me: c.dimensions[i].me,
                      them: c.dimensions[i].them,
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 16),
            Text('${c.user.nickname}님은 만족했고 나는 아직인 곳', style: text.titleMedium),
            const SizedBox(height: 4),
            if (c.suggestions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('아직 추천할 곳이 없어요', style: text.bodyMedium),
              ),
            for (final s in c.suggestions)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => context.push('/place/${s.place.id}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.place.name, style: text.bodyLarge),
                        Text(s.reason ?? '', style: text.bodyMedium),
                      ]),
                    ),
                    const Icon(Icons.chevron_right, size: 18, color: Palette.inkMuted),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _key(Color fill, String label, TextTheme text, {bool ring = false}) => Row(children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: ring ? Border.all(color: Palette.inkSoft, width: 1.5) : null,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: text.bodySmall),
      ]);
}
