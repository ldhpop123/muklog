import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router.dart';
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
    ref.read(onboardedProvider.notifier).state = true;
  }

  @override
  Widget build(BuildContext context) {
    final q = _questions[_step];
    return Scaffold(
      appBar:
          AppBar(title: Text('입맛 밸런스 게임 ${_step + 1}/${_questions.length}')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: (_step + 1) / _questions.length),
            const SizedBox(height: 32),
            Text('둘 중 하나만 고른다면?',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 32),
            Expanded(
                child: _ChoiceCard(label: q.left, onTap: () => _choose(-1))),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('VS',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            Expanded(
                child: _ChoiceCard(label: q.right, onTap: () => _choose(1))),
          ],
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(
            child:
                Text(label, style: Theme.of(context).textTheme.headlineSmall)),
      ),
    );
  }
}
