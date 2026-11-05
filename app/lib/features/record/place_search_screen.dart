import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/location.dart';
import '../../core/theme.dart';
import '../../data/muklog_repository.dart';
import '../../data/providers.dart';
import '../../models/place.dart';

/// "다녀왔어요" 첫 단계: 다녀온 식당을 검색해서 고른다.
/// 결과는 서버가 네이버 지역 검색으로 가져온 이름·업종·주소·좌표뿐이고, 네이버 평점·리뷰는 보여 주지 않는다.
class PlaceSearchScreen extends ConsumerStatefulWidget {
  const PlaceSearchScreen({super.key});

  @override
  ConsumerState<PlaceSearchScreen> createState() => _PlaceSearchScreenState();
}

class _PlaceSearchScreenState extends ConsumerState<PlaceSearchScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<PlaceCandidate>? _results;
  String? _error;
  var _loading = false;
  var _picking = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _results = null);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final near = ref.read(myLocationProvider).valueOrNull?.position;
      final r = await ref.read(repositoryProvider).searchPlaces(q, near: near);
      if (!mounted || q != _query.text) return; // 더 새 검색어가 있으면 버린다
      setState(() => _results = r);
    } on MuklogException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick(PlaceCandidate c) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final placeId = c.placeId ?? (await ref.read(repositoryProvider).createPlace(c)).id;
      ref.invalidate(placesProvider);
      if (mounted) context.pushReplacement('/record/new?placeId=$placeId&from=search');
    } on MuklogException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final near = ref.watch(myLocationProvider).valueOrNull?.position;
    return Scaffold(
      appBar: AppBar(title: const Text('어디 다녀왔어요?')),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: TextField(
            controller: _query,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: _search,
            decoration: InputDecoration(
              hintText: '식당 이름이나 메뉴',
              prefixIcon: const Icon(Icons.search, size: 20, color: Palette.inkMuted),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
            ),
          ),
        ),
        if (_picking) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _body(text, near)),
      ]),
    );
  }

  Widget _body(TextTheme text, LatLng? near) {
    if (_error != null) {
      return Padding(padding: const EdgeInsets.all(20), child: Text(_error!, style: text.bodyMedium));
    }
    final results = _results;
    if (results == null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text('다녀온 식당을 찾아서 골라 주세요. 먹로그에 없는 곳이면 새로 등록돼요', style: text.bodyMedium),
      );
    }
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text("'${_query.text}' 검색 결과가 없어요", style: text.bodyMedium),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: results.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 12, endIndent: 12),
      itemBuilder: (context, i) {
        final c = results[i];
        final km = near == null ? null : c.location.distanceKm(near);
        return ListTile(
          onTap: _picking ? null : () => _pick(c),
          title: Text(c.name, style: text.bodyLarge!.copyWith(fontWeight: FontWeight.w500)),
          subtitle: Text(
            [categoryLabel(c.category), c.address, if (km != null) '${km.toStringAsFixed(1)}km'].join(' · '),
            style: text.bodyMedium!.copyWith(fontFeatures: tabular),
          ),
          trailing: c.placeId != null
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Palette.raised, borderRadius: BorderRadius.circular(6)),
                  child: Text('먹로그에 있는 곳', style: text.bodySmall!.copyWith(color: Palette.inkSoft)),
                )
              : const Icon(Icons.chevron_right, size: 18, color: Palette.inkMuted),
        );
      },
    );
  }
}
