import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/muklog_repository.dart';
import '../../data/providers.dart';

/// 파티 모드: 함께 갈 친구를 고르면 모두 만족할 교집합 장소를 추천 (README 6.5).
class PartyModeScreen extends ConsumerStatefulWidget {
  const PartyModeScreen({super.key});

  @override
  ConsumerState<PartyModeScreen> createState() => _PartyModeScreenState();
}

class _PartyModeScreenState extends ConsumerState<PartyModeScreen> {
  final _selected = <String>{};
  List<ScoredPlace>? _results;

  Future<void> _run() async {
    final r =
        await ref.read(repositoryProvider).partyRecommend(_selected.toList());
    setState(() => _results = r.take(3).toList());
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider).valueOrNull ?? [];
    final me = ref.watch(meProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('파티 모드')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('누구와 함께 가나요?'),
          for (final f in friends)
            CheckboxListTile(
              value: _selected.contains(f.id),
              onChanged: (on) => setState(
                  () => on! ? _selected.add(f.id) : _selected.remove(f.id)),
              secondary:
                  CircleAvatar(backgroundImage: NetworkImage(f.avatarUrl)),
              title: Text(f.nickname),
              subtitle: me == null
                  ? null
                  : Text('나와 입맛 ${me.taste.couplePercent(f.taste)}%'),
            ),
          Text('구성원 누구든 불호·알레르기로 등록한 곳은 빼고 추천해요.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _selected.isEmpty ? null : _run,
            child: const Text('교집합 맛집 찾기'),
          ),
          if (_results != null) ...[
            const Divider(height: 32),
            for (final s in _results!)
              Card(
                child: ListTile(
                  title: Text(s.place.name),
                  subtitle: Text(s.reason ?? ''),
                  onTap: () => context.push('/place/${s.place.id}'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
