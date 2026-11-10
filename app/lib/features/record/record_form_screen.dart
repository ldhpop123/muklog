import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../data/muklog_repository.dart';
import '../../data/providers.dart';
import '../../models/place.dart';
import '../../models/visit_record.dart';
import '../map/briefing_state.dart' show moveMapArea;
import '../map/map_screen.dart' show mapPinsProvider;
import '../place/place_detail_screen.dart';

const _tagOptions = ['노포', '아재입맛', '혼밥', '안주맛집', '데이트', '가성비', '매운맛', '감성'];

/// 한 기록에 붙일 수 있는 사진 수 (서버도 같은 상한)
const maxRecordPhotos = 4;

class RecordFormScreen extends ConsumerStatefulWidget {
  const RecordFormScreen({super.key, required this.placeId, this.inspiredByRecordId, this.fromSearch = false});

  final String placeId;
  final String? inspiredByRecordId;

  /// 식당 검색에서 왔으면 저장 후 식당 상세로, 식당 상세에서 왔으면 그냥 돌아간다.
  final bool fromSearch;

  @override
  ConsumerState<RecordFormScreen> createState() => _RecordFormScreenState();
}

class _PickedPhoto {
  _PickedPhoto(this.bytes, this.name);
  final Uint8List bytes;
  final String name;
}

class _RecordFormScreenState extends ConsumerState<RecordFormScreen> {
  final _memo = TextEditingController();
  final _tags = <String>{};
  final _photos = <_PickedPhoto>[];
  var _rating = 4.0;
  var _visibility = RecordVisibility.friends;
  String? _status; // 저장 중 진행 문구. null이면 저장 중이 아님

  @override
  void dispose() {
    _memo.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final left = maxRecordPhotos - _photos.length;
    if (left <= 0) return;
    final picked = await ImagePicker().pickMultiImage(limit: left, maxWidth: 1600, imageQuality: 85);
    final loaded = [
      for (final x in picked.take(left)) _PickedPhoto(await x.readAsBytes(), x.name),
    ];
    if (mounted) setState(() => _photos.addAll(loaded));
  }

  Future<void> _save() async {
    final repo = ref.read(repositoryProvider);
    try {
      final me = await ref.read(meProvider.future);
      final urls = <String>[];
      for (var i = 0; i < _photos.length; i++) {
        setState(() => _status = '사진 올리는 중 ${i + 1}/${_photos.length}');
        urls.add(await repo.uploadPhoto(_photos[i].bytes, _photos[i].name));
      }
      setState(() => _status = '저장 중');
      await repo.createRecord(VisitRecord(
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
        photoUrls: urls,
      ));
    } on MuklogException catch (e) {
      // 예: 볼 수 없는 기록을 "보고 왔어요"로 지정 (서버 400), 사진 형식·크기 거절
      if (!mounted) return;
      setState(() => _status = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    // 지도로 돌아가면 방금 기록한 식당이 보이도록 (내 위치에서 먼 곳이어도)
    final place = ref.read(placesProvider).valueOrNull?.where((p) => p.id == widget.placeId).firstOrNull;
    if (place != null) moveMapArea(ref, place.location);
    ref.invalidate(placeRecordsProvider(widget.placeId));
    ref.invalidate(recommendProvider);
    ref.invalidate(placesProvider);
    ref.invalidate(mapPinsProvider);
    if (!mounted) return;
    if (widget.fromSearch) {
      context.pushReplacement('/place/${widget.placeId}');
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final place = ref.watch(placesProvider).valueOrNull?.where((p) => p.id == widget.placeId).firstOrNull;
    final saving = _status != null;
    return Scaffold(
      appBar: AppBar(title: const Text('방문 기록')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          if (place != null) ...[
            Text(place.name, style: text.headlineSmall),
            const SizedBox(height: 2),
            Text('${categoryLabel(place.category)} · ${place.area}', style: text.bodyMedium),
            const SizedBox(height: 20),
          ],
          if (widget.inspiredByRecordId != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Palette.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Palette.hairline),
              ),
              child: Row(children: [
                const Icon(Icons.thumb_up_alt_outlined, size: 18, color: Palette.inkSoft),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('친구 기록을 보고 다녀왔어요', style: text.bodyLarge),
                    Text('내 평가가 그 친구의 맛 신뢰 온도에 반영돼요', style: text.bodySmall),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 20),
          ],
          _label('사진', '${_photos.length}/$maxRecordPhotos', text),
          const SizedBox(height: 8),
          SizedBox(
            height: 88,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (var i = 0; i < _photos.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(clipBehavior: Clip.none, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(_photos[i].bytes, width: 88, height: 88, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: saving ? null : () => setState(() => _photos.removeAt(i)),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(color: Color(0x991F1A15), shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ]),
                ),
              if (_photos.length < maxRecordPhotos)
                InkWell(
                  onTap: saving ? null : _pickPhotos,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: Palette.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Palette.hairline),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.add_photo_alternate_outlined, size: 22, color: Palette.inkSoft),
                      const SizedBox(height: 4),
                      Text('사진 추가', style: text.bodySmall),
                    ]),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 24),
          _label('평점', _rating.toStringAsFixed(1), text),
          Slider(
            value: _rating,
            min: 1,
            max: 5,
            divisions: 8,
            onChanged: saving ? null : (v) => setState(() => _rating = v),
          ),
          const SizedBox(height: 8),
          _label('메모', null, text),
          const SizedBox(height: 8),
          TextField(
            controller: _memo,
            enabled: !saving,
            maxLines: 4,
            decoration: const InputDecoration(hintText: '솔직하게 남겨 주세요. 예: 간이 슴슴하고 오래된 노포 느낌'),
          ),
          const SizedBox(height: 24),
          _label('태그', null, text),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in _tagOptions)
              FilterChip(
                label: Text('#$t'),
                selected: _tags.contains(t),
                onSelected: saving ? null : (on) => setState(() => on ? _tags.add(t) : _tags.remove(t)),
              ),
          ]),
          const SizedBox(height: 24),
          _label('공개 범위', null, text),
          const SizedBox(height: 8),
          SegmentedButton<RecordVisibility>(
            segments: const [
              ButtonSegment(value: RecordVisibility.private, label: Text('나만')),
              ButtonSegment(value: RecordVisibility.friends, label: Text('친구')),
              ButtonSegment(value: RecordVisibility.public, label: Text('전체')),
            ],
            selected: {_visibility},
            onSelectionChanged: saving ? null : (s) => setState(() => _visibility = s.first),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: saving ? null : _save,
            child: Text(_status ?? '기록 남기기'),
          ),
        ],
      ),
    );
  }

  Widget _label(String title, String? trailing, TextTheme text) => Row(children: [
        Text(title, style: text.titleSmall),
        const Spacer(),
        if (trailing != null) Text(trailing, style: text.bodyMedium!.copyWith(fontFeatures: tabular)),
      ]);
}
