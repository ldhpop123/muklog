import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/location.dart';
import '../../data/providers.dart';
import '../../models/place.dart';
import 'widgets/muk_map_types.dart';

/// 지금 보고 있는 지도 화면의 가운데. 지도가 멈출 때마다 갱신된다.
final mapViewCenterProvider = StateProvider<LatLng?>((ref) => null);

/// 브리핑 기준점. "이 지역 브리핑 보기"를 누를 때만 바뀐다. null이면 처음 지도 가운데(내 위치 또는 홍대).
final briefingCenterProvider = StateProvider<LatLng?>((ref) => null);

/// 브리핑 기준점에서 가까운 상권 (친구 기록이 없어도 포함).
final nearbyAreasProvider = FutureProvider<List<AreaInfo>>((ref) async {
  final center = ref.watch(briefingCenterProvider) ??
      await ref.watch(searchCenterProvider.future) ??
      defaultMapCenter;
  return ref.watch(repositoryProvider).nearbyAreas(center, limit: 5);
});

/// 사용자가 탭에서 고른 상권. null이면 가장 가까운 상권.
final selectedAreaProvider = StateProvider<String?>((ref) => null);

/// 실제로 브리핑을 보여 줄 상권 이름.
final briefingAreaProvider = FutureProvider<String?>((ref) async {
  final areas = await ref.watch(nearbyAreasProvider.future);
  final picked = ref.watch(selectedAreaProvider);
  if (picked != null && areas.any((a) => a.name == picked)) return picked;
  return areas.isEmpty ? null : areas.first.name;
});

/// 지도가 브리핑 기준점에서 이만큼 벗어나면 "이 지역 브리핑 보기" 버튼을 띄운다.
const briefingRefreshDistanceKm = 0.3;
