import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../models/taste_vector.dart';

class _Question {
  const _Question(this.left, this.right, this.dimension);
  final String left;
  final String right;

  /// 이 문항이 정하는 차원 (TasteVector.toList() 인덱스).
  /// 왼쪽 선택 = -1 쪽, 오른쪽 선택 = +1 쪽.
  final int dimension;
}

const _questions = [
  _Question('슴슴한 평양냉면', '자극적인 함흥냉면', 0),
  _Question('순한 맛 떡볶이', '불닭급 매운 떡볶이', 1),
  _Question('30년 된 노포', '깔끔한 인스타 감성', 2),
  _Question('비싸도 맛있으면 OK', '가성비가 최고', 3),
  _Question('엄마 손맛 한식', '이국적인 양식·아시안', 4),
];

/// Cold Start 해결용 밸런스 게임 온보딩 (README 6.2).
class BalanceGameScreen extends ConsumerStatefulWidget {
  const BalanceGameScreen({super.key});

  @override
  ConsumerState<BalanceGameScreen> createState() => _BalanceGameScreenState();
}

class _BalanceGameScreenState extends ConsumerState<BalanceGameScreen> {
  final _answers = List<double>.filled(5, 0);
  var _step = 0;

  Future<void> _choose(double v) async {
    _answers[_questions[_step].dimension] = v;
    if (_step < _questions.length - 1) {
      setState(() => _step++);
      return;
    }
    await ref
        .read(repositoryProvider)
        .saveOnboarding(TasteVector.fromList(_answers));
    ref.invalidate(meProvider);
    ref.invalidate(recommendProvider);
    // router의 redirect가 지도 화면으로 보낸다.
    ref.read(authProvider.notifier).markOnboarded();
  }

  @override
  Widget build(BuildContext context) {
    final q = _questions[_step];
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const BrandLogo(size: 24),
                const Spacer(),
                Text('${_step + 1} / ${_questions.length}',
                    style: text.bodyMedium!.copyWith(fontFeatures: tabular)),
              ]),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: (_step + 1) / _questions.length,
                  minHeight: 3,
                  color: Palette.ember,
                ),
              ),
              const SizedBox(height: 40),
              Text(TasteVector.labels[q.dimension], style: text.bodyMedium),
              const SizedBox(height: 4),
              Text('둘 중 하나만 고른다면', style: text.headlineSmall),
              const SizedBox(height: 8),
              Text('고른 답으로 첫 입맛 지도를 그려요. 기록이 쌓이면 더 정확해져요', style: text.bodyMedium),
              const SizedBox(height: 32),
              Expanded(
                child: _ChoiceCard(
                  label: q.left,
                  pole: TasteVector.poles[q.dimension].$1,
                  onTap: () => _choose(-1),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(children: [
                  const Expanded(child: Divider(height: 1)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('또는', style: text.bodySmall),
                  ),
                  const Expanded(child: Divider(height: 1)),
                ]),
              ),
              Expanded(
                child: _ChoiceCard(
                  label: q.right,
                  pole: TasteVector.poles[q.dimension].$2,
                  onTap: () => _choose(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.label, required this.pole, required this.onTap});
  final String label;
  final String pole;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: Palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Palette.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: Palette.raised.withValues(alpha: 0.5),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(label, style: text.headlineSmall),
              const SizedBox(height: 4),
              Text(pole, style: text.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
