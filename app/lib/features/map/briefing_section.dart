import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/muklog_repository.dart';
import '../../data/providers.dart';
import '../../models/place.dart';
import '../../models/social.dart';
import 'briefing_state.dart';

/// AI 지역 브리핑 (README 6.6): 주변 상권 탭 + 문장 목록 + 브리핑에 나온 식당 카드.
///
/// 상권은 "이 지역 브리핑 보기"를 누른 시점의 지도 화면 가운데에서 가까운 순이다.
/// 문장은 서버(LLM 또는 템플릿)가 만든 그대로 쓰되, 읽기 쉽게
/// '식당 이름'은 굵게, #태그는 문장 아래 작은 태그로 떼어 낸다.
class BriefingSection extends ConsumerWidget {
  const BriefingSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final areas = ref.watch(nearbyAreasProvider);
    final area = ref.watch(briefingAreaProvider).valueOrNull;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(area == null ? '친구 브리핑' : '$area 친구 브리핑', style: text.titleMedium),
      const SizedBox(height: 2),
      Text('지도에서 보던 곳 주변 상권과 동네예요. 친구들이 남긴 기록으로 정리했어요', style: text.bodySmall),
      const SizedBox(height: 12),
      areas.when(
        loading: () => const SizedBox(height: 36),
        error: (e, _) => Text('주변 상권을 불러오지 못했어요. $e', style: text.bodyMedium),
        data: (list) => _AreaPicker(areas: list, selected: area),
      ),
      const SizedBox(height: 16),
      if (area != null)
        ref.watch(briefingProvider(area)).when(
              loading: () => const _BriefingSkeleton(),
              error: (e, _) => Text('브리핑을 불러오지 못했어요. $e', style: text.bodyMedium),
              data: (b) => _BriefingBody(briefing: b),
            ),
    ]);
  }
}

/// 주변 상권 탭. 가까운 순으로 옆으로 넘기며 고른다. 친구 기록이 없는 상권은 흐리게 보인다.
class _AreaPicker extends ConsumerWidget {
  const _AreaPicker({required this.areas, required this.selected});
  final List<AreaInfo> areas;
  final String? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: areas.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final a = areas[i];
          final on = a.name == selected;
          final color = on ? Palette.ink : (a.recordCount == 0 ? Palette.inkMuted : Palette.inkSoft);
          return GestureDetector(
            onTap: () => ref.read(selectedAreaProvider.notifier).state = a.name,
            child: AnimatedContainer(
              duration: motionFast,
              curve: motionCurve,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? Palette.raised : Palette.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: on ? Palette.inkMuted.withValues(alpha: 0.4) : Palette.hairline),
              ),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: a.name),
                  if (a.isDong) TextSpan(text: ' 동네', style: text.bodySmall),
                  TextSpan(
                    text: '  ${a.distanceKm.toStringAsFixed(1)}km',
                    style: text.bodySmall!.copyWith(fontFeatures: tabular),
                  ),
                ]),
                style: text.labelLarge!.copyWith(color: color),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BriefingBody extends StatelessWidget {
  const _BriefingBody({required this.briefing});
  final Briefing briefing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final lines = briefing.sentences.map(_BriefingLine.parse).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        decoration: BoxDecoration(
          color: Palette.page,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.hairline),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final line in lines) _SentenceRow(line: line),
        ]),
      ),
      if (briefing.places.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text('브리핑에 나온 곳', style: text.bodyMedium),
        const SizedBox(height: 8),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: briefing.places.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) => _PickCard(item: briefing.places[i]),
          ),
        ),
      ],
    ]);
  }
}

/// 한 문장: 앞의 점 + 본문(식당 이름 굵게) + 아래 태그.
class _SentenceRow extends StatelessWidget {
  const _SentenceRow({required this.line});
  final _BriefingLine line;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final body = text.bodyLarge!.copyWith(height: 24 / 15, color: Palette.ink);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 9, right: 10),
          decoration: const BoxDecoration(color: Palette.ember, shape: BoxShape.circle),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(
              TextSpan(children: [
                for (final part in line.parts)
                  TextSpan(
                    text: part.text,
                    style: part.isName ? const TextStyle(fontWeight: FontWeight.w600) : null,
                  ),
              ]),
              style: body,
            ),
            if (line.tags.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (final t in line.tags)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Palette.raised, borderRadius: BorderRadius.circular(4)),
                    child: Text('#$t', style: text.bodySmall!.copyWith(color: Palette.inkSoft)),
                  ),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// 브리핑에 나온 식당 카드. 누르면 식당 상세로.
class _PickCard extends StatelessWidget {
  const _PickCard({required this.item});
  final ScoredPlace item;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final place = item.place;
    return Material(
      color: Palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Palette.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/place/${place.id}'),
        child: SizedBox(
          width: 184,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(place.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyLarge!.copyWith(fontWeight: FontWeight.w500)),
                    Text('${categoryLabel(place.category)} · ${place.area}', style: text.bodySmall),
                  ]),
                ),
                if (place.revisitTotal >= 2) VisitStamp(count: place.revisitTotal, size: 32),
              ]),
              const Spacer(),
              Text(item.reason ?? place.tags.map((t) => '#$t').join(' '),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 요약을 기다리는 동안 문장 자리를 흐린 줄로 보여 준다 (LLM 요약은 10초 넘게 걸릴 수 있다).
class _BriefingSkeleton extends StatelessWidget {
  const _BriefingSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double widthFactor) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: widthFactor,
          child: Container(
            height: 12,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: Palette.raised, borderRadius: BorderRadius.circular(6)),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      decoration: BoxDecoration(
        color: Palette.page,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        bar(1),
        bar(0.86),
        bar(0.62),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text('친구들의 기록을 요약하고 있어요', style: Theme.of(context).textTheme.bodySmall),
        ),
      ]),
    );
  }
}

/// 브리핑 문장 한 줄을 화면용으로 나눈 것.
class _BriefingLine {
  _BriefingLine(this.parts, this.tags);

  final List<({String text, bool isName})> parts;
  final List<String> tags;

  static final _tag = RegExp(r'#([^\s#]+)');
  static final _quoted = RegExp(r"'([^']+)'");

  /// "'서교 순댓국'은 민수님이 4번 다녀간 곳이에요. #노포 #혼밥"
  /// → 본문 ["서교 순댓국"(굵게), "은 민수님이 4번 다녀간 곳이에요."], 태그 [노포, 혼밥]
  factory _BriefingLine.parse(String sentence) {
    final tags = [for (final m in _tag.allMatches(sentence)) m.group(1)!];
    final body = sentence.replaceAll(_tag, '').trim();
    final parts = <({String text, bool isName})>[];
    var last = 0;
    for (final m in _quoted.allMatches(body)) {
      if (m.start > last) parts.add((text: body.substring(last, m.start), isName: false));
      parts.add((text: m.group(1)!, isName: true));
      last = m.end;
    }
    if (last < body.length) parts.add((text: body.substring(last), isName: false));
    return _BriefingLine(parts, tags);
  }
}
