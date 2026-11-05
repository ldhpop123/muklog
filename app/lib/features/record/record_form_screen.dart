import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/muklog_repository.dart';
import '../../data/providers.dart';
import '../../models/visit_record.dart';
import '../place/place_detail_screen.dart';

const _tagOptions = ['노포', '아재입맛', '혼밥', '안주맛집', '데이트', '가성비', '매운맛', '감성'];

class RecordFormScreen extends ConsumerStatefulWidget {
  const RecordFormScreen(
      {super.key, required this.placeId, this.inspiredByRecordId});

  final String placeId;
  final String? inspiredByRecordId;

  @override
  ConsumerState<RecordFormScreen> createState() => _RecordFormScreenState();
}

class _RecordFormScreenState extends ConsumerState<RecordFormScreen> {
  final _memo = TextEditingController();
  final _tags = <String>{};
  var _rating = 4.0;
  var _visibility = RecordVisibility.friends;
  var _saving = false;

  @override
  void dispose() {
    _memo.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final me = await ref.read(meProvider.future);
    // TODO(media): 사진·15초 영상 첨부
    try {
      await ref.read(repositoryProvider).createRecord(VisitRecord(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            userId: me.id,
            placeId: widget.placeId,
            rating: _rating,
            memo: _memo.text,
            visitNo: 1, // 서버가 실제 회차를 계산한다
            visitedAt: DateTime.now(),
            tags: _tags.toList(),
            visibility: _visibility,
            inspiredByRecordId: widget.inspiredByRecordId,
          ));
    } on MuklogException catch (e) {
      // 예: 볼 수 없는 기록을 "보고 왔어요"로 지정 (서버 400)
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    ref.invalidate(placeRecordsProvider(widget.placeId));
    ref.invalidate(recommendProvider);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('방문 기록')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.inspiredByRecordId != null)
            const Card(
              child: ListTile(
                leading: Icon(Icons.thumb_up_alt_outlined),
                title: Text('친구 기록을 보고 방문했어요'),
                subtitle: Text('내 평가가 그 친구의 맛 신뢰 온도에 반영돼요'),
              ),
            ),
          Text('평점 ${_rating.toStringAsFixed(1)}'),
          Slider(
            value: _rating,
            min: 1,
            max: 5,
            divisions: 8,
            onChanged: (v) => setState(() => _rating = v),
          ),
          TextField(
            controller: _memo,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '솔직하게 남겨 주세요. 예: 간이 슴슴하고 오래된 노포 느낌',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in _tagOptions)
              FilterChip(
                label: Text('#$t'),
                selected: _tags.contains(t),
                onSelected: (on) =>
                    setState(() => on ? _tags.add(t) : _tags.remove(t)),
              ),
          ]),
          const SizedBox(height: 16),
          SegmentedButton<RecordVisibility>(
            segments: const [
              ButtonSegment(value: RecordVisibility.private, label: Text('나만')),
              ButtonSegment(value: RecordVisibility.friends, label: Text('친구')),
              ButtonSegment(value: RecordVisibility.public, label: Text('전체')),
            ],
            selected: {_visibility},
            onSelectionChanged: (s) => setState(() => _visibility = s.first),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '저장 중…' : '저장'),
          ),
        ],
      ),
    );
  }
}
