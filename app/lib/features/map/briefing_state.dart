import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/location.dart';
import '../../data/providers.dart';
import '../../models/place.dart';
import 'widgets/muk_map_types.dart';

/// 지금 보고 있는 지도 화면의 가운데. 지도가 멈출 때마다 갱신된다.
final mapViewCenterProvider = StateProvider<LatLng?>((ref) => null);

/// 지역 기준점. 브리핑과 지도 핀을 이 주변으로 불러온다.
/// "이 지역 브리핑 보기"를 누르거나 기록을 남겼을 때만 바뀐다. null이면 내 위치(없으면 홍대).
final briefingCenterProvider = StateProvider<LatLng?>((ref) => null);

/// 지도 카메라를 옮길 곳. 기록을 남긴 식당처럼 특정 위치를 보여 줘야 할 때만 값이 있다.
final mapFocusProvider = StateProvider<LatLng?>((ref) => null);

/// 지역 기준점과 카메라를 [at]으로 옮긴다. null이면 내 위치 기준으로 되돌린다.
void moveMapArea(WidgetRef ref, LatLng? at) {
  ref.read(mapFocusProvider.notifier).state = at;
  ref.read(briefingCenterProvider.notifier).state = at;
  ref.read(selectedAreaProvider.notifier).state = null;
}

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
