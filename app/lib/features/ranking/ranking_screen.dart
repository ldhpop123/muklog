import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
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
    final text = Theme.of(context).textTheme;
    return entries.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) => ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        for (final e in list)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: e.user.id == myId ? Palette.raised : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              SizedBox(
                width: 28,
                child: Text('${e.rank}',
                    style: text.titleMedium!.copyWith(
                        color: e.rank == 1 ? Palette.ember : Palette.inkMuted, fontFeatures: tabular)),
              ),
              Face(url: e.user.avatarUrl, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // 닉네임이 "나"가 아닐 때만 (나)를 붙인다. 내 줄은 바탕색으로 구분한다.
                  Text(
                    e.user.id == myId && e.user.nickname != '나' ? '${e.user.nickname} (나)' : e.user.nickname,
                    style: text.bodyLarge,
                  ),
                  Text([e.user.level, if (e.user.title != null) e.user.title!].join(' · '),
                      style: text.bodyMedium),
                ]),
              ),
              Text('${e.user.trustTemp.toStringAsFixed(1)}℃',
                  style: text.titleMedium!.copyWith(fontFeatures: tabular)),
            ]),
          ),
      ]),
    );
  }
}
