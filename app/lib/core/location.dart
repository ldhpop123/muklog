import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../models/place.dart';

/// 현재 위치를 가져온 결과. 못 가져오면 [position]이 null이고 [reason]에 사용자에게 보여 줄 이유가 담긴다.
class MyLocation {
  const MyLocation(this.position, [this.reason]);
  final LatLng? position;
  final String? reason;
}

/// 내 주변으로 볼 반경 (km)
const nearbyRadiusKm = 3.0;

/// 현재 위치. 다시 가져오려면 invalidate 한다 (지도 화면의 "내 위치" 버튼).
/// 웹은 브라우저 위치 권한을 쓰므로 https(또는 localhost)에서만 동작한다.
final myLocationProvider = FutureProvider<MyLocation>((ref) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const MyLocation(null, '기기 위치 서비스가 꺼져 있어요');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return const MyLocation(null, '위치 권한이 없어요');
    }
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(locationSettings: _settings());
    } on TimeoutException {
      // 실내·에뮬레이터처럼 새 위치가 늦게 잡히면 마지막으로 알려진 위치를 쓴다 (웹은 지원하지 않음).
      pos = kIsWeb ? null : await Geolocator.getLastKnownPosition();
    }
    if (pos == null) return const MyLocation(null, '현재 위치를 가져오지 못했어요');
    return MyLocation(LatLng(pos.latitude, pos.longitude));
  } catch (_) {
    return const MyLocation(null, '현재 위치를 가져오지 못했어요');
  }
});

/// true면 지도·추천을 내 주변([nearbyRadiusKm]) 기준으로 보여 준다. false면 전체 기록.
final nearMeProvider = StateProvider<bool>((ref) => true);

/// 지도·추천의 기준 위치. 내 주변 보기가 켜져 있고 위치를 가져왔을 때만 값이 있다.
final searchCenterProvider = FutureProvider<LatLng?>((ref) async {
  if (!ref.watch(nearMeProvider)) return null;
  return (await ref.watch(myLocationProvider.future)).position;
});

LocationSettings _settings() {
  const timeLimit = Duration(seconds: 10);
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    // Google 위치 서비스(Fused)가 늦거나 없는 기기·에뮬레이터에서도 GPS를 직접 읽는다.
    return AndroidSettings(
      accuracy: LocationAccuracy.medium,
      timeLimit: timeLimit,
      forceLocationManager: true,
    );
  }
  return const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: timeLimit);
}
