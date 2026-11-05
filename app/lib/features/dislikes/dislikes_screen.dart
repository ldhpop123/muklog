import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../models/social.dart';

/// 불호·알레르기 관리. 등록한 메뉴·태그·카테고리가 걸린 식당은 내 추천과 파티 모드에서 빠진다.
class DislikesScreen extends ConsumerStatefulWidget {
  const DislikesScreen({super.key});

  @override
  ConsumerState<DislikesScreen> createState() => _DislikesScreenState();
}

class _DislikesScreenState extends ConsumerState<DislikesScreen> {
  final _input = TextEditingController();
  var _kind = DislikeKind.dislike;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _save(List<Dislike> items) async {
    await ref.read(repositoryProvider).saveDislikes(items);
    ref.invalidate(dislikesProvider);
    ref.invalidate(recommendProvider);
  }

  Future<void> _add(List<Dislike> current) async {
    final target = _input.text.trim();
    if (target.isEmpty) return;
    _input.clear();
    await _save([...current, Dislike(target, kind: _kind)]);
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(dislikesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('불호 · 알레르기')),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('등록한 메뉴·태그·카테고리가 들어간 식당은 내 추천과 파티 모드에서 빠져요. '
                '파티 모드에서는 누가 등록했는지 친구에게 보이지 않아요.'),
            const SizedBox(height: 16),
            SegmentedButton<DislikeKind>(
              segments: [
                for (final k in DislikeKind.values)
                  ButtonSegment(value: k, label: Text(k.label))
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  decoration: const InputDecoration(
                      hintText: '예: 마라, 노포, 갑각류', border: OutlineInputBorder()),
                  onSubmitted: (_) => _add(list),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                  onPressed: () => _add(list), child: const Text('추가')),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final d in list)
                InputChip(
                  avatar: Icon(
                      d.kind == DislikeKind.allergy
                          ? Icons.warning_amber
                          : Icons.block,
                      size: 18),
                  label: Text(d.target),
                  onDeleted: () => _save([...list]..remove(d)),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}
