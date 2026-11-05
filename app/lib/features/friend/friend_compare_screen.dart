import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../models/social.dart';
import '../../models/taste_vector.dart';

/// 친구 비교: 입맛 커플링 지수, 차원별 비교, 친구가 만족한 곳 중 내가 안 가 본 곳 (README 8.2).
class FriendCompareScreen extends ConsumerWidget {
  const FriendCompareScreen({super.key, required this.friendId});

  final String friendId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coupling = ref.watch(coupleProvider(friendId));
    return Scaffold(
      appBar: AppBar(title: const Text('입맛 비교')),
      body: coupling.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (c) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              CircleAvatar(
                  radius: 28, backgroundImage: NetworkImage(c.user.avatarUrl)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${c.user.nickname}님과 입맛',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text('같이 가 본 곳 ${c.sharedPlaceCount}곳',
                          style: Theme.of(context).textTheme.bodySmall),
                    ]),
              ),
              Text('${c.percent}%',
                  style: Theme.of(context)
                      .textTheme
                      .displaySmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ]),
            const Divider(height: 32),
            Row(children: [
              Text('차원별 비교', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              const _Legend(),
            ]),
            const SizedBox(height: 8),
            for (var i = 0; i < c.dimensions.length; i++)
              _DimensionRow(diff: c.dimensions[i], index: i),
            const Divider(height: 32),
            Text('${c.user.nickname}님이 만족한 곳, 나는 아직',
                style: Theme.of(context).textTheme.titleMedium),
            if (c.suggestions.isEmpty)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('추천할 곳이 아직 없어요')),
            for (final s in c.suggestions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.place.name),
                subtitle: Text(s.reason ?? ''),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/place/${s.place.id}'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget dot(Color c, String label) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]);
    return Row(children: [
      dot(scheme.primary, '나'),
      const SizedBox(width: 12),
      dot(scheme.tertiary, '친구')
    ]);
  }
}

/// 한 차원을 -1 ~ +1 축 위의 두 점(나, 친구)으로 보여 준다.
class _DimensionRow extends StatelessWidget {
  const _DimensionRow({required this.diff, required this.index});
  final DimensionDiff diff;
  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final (low, high) = TasteVector.poles[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(diff.label),
        const SizedBox(height: 4),
        LayoutBuilder(builder: (context, box) {
          double x(double v) => (v + 1) / 2 * (box.maxWidth - 14);
          return SizedBox(
            height: 14,
            child: Stack(children: [
              Positioned(
                left: 7,
                right: 7,
                top: 6,
                child: Container(height: 2, color: scheme.outlineVariant),
              ),
              Positioned(left: x(diff.them), child: _dot(scheme.tertiary)),
              Positioned(left: x(diff.me), child: _dot(scheme.primary)),
            ]),
          );
        }),
        Row(children: [
          Text(low, style: small),
          const Spacer(),
          Text(high, style: small)
        ]),
      ]),
    );
  }

  Widget _dot(Color c) => Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2)),
      );
}
