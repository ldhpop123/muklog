import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../models/social.dart';

/// 미식가 랭킹: 맛 신뢰 온도 순 (README 7.3). 친구 랭킹 / 전체 랭킹.
class RankingScreen extends StatelessWidget {
  const RankingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('미식가 랭킹'),
          bottom: const TabBar(tabs: [Tab(text: '친구'), Tab(text: '전체')]),
        ),
        body: const TabBarView(children: [
          _RankingList(scope: RankingScope.friends),
          _RankingList(scope: RankingScope.all),
        ]),
      ),
    );
  }
}

class _RankingList extends ConsumerWidget {
  const _RankingList({required this.scope});
  final RankingScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(rankingProvider(scope));
    final myId = ref.watch(meProvider).valueOrNull?.id;
    return entries.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) => ListView(children: [
        for (final e in list)
          ListTile(
            selected: e.user.id == myId,
            leading: SizedBox(
              width: 72,
              child: Row(children: [
                SizedBox(
                    width: 24,
                    child: Text('${e.rank}',
                        style: const TextStyle(fontWeight: FontWeight.w800))),
                CircleAvatar(backgroundImage: NetworkImage(e.user.avatarUrl)),
              ]),
            ),
            title: Text(
                // 내 줄은 강조색(selected)으로 표시하고, 닉네임이 "나"가 아닐 때만 (나)를 붙인다.
                e.user.id == myId && e.user.nickname != '나'
                    ? '${e.user.nickname} (나)'
                    : e.user.nickname),
            subtitle: Text([
              e.user.level,
              if (e.user.title != null) e.user.title!
            ].join(' · ')),
            trailing: Text('${e.user.trustTemp.toStringAsFixed(1)}℃',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
      ]),
    );
  }
}
