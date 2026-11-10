import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth.dart';
import '../core/config.dart';
import '../core/location.dart';
import '../models/place.dart';
import '../models/social.dart';
import '../models/user_profile.dart';
import 'api_muklog_repository.dart';
import 'mock_muklog_repository.dart';
import 'muklog_repository.dart';

final repositoryProvider = Provider<MuklogRepository>((ref) {
  if (AppConfig.useMock) return MockMuklogRepository();
  // 세션이 바뀌면(로그인·로그아웃) 저장소를 새로 만들어, 이를 쓰는 화면 데이터가 모두 새 사용자 기준으로 다시 불린다.
  final token = ref.watch(authTokenProvider);
  final dio = Dio(BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    // FastAPI의 list 쿼리는 tags=a&tags=b 형식이다.
    listFormat: ListFormat.multi,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      if (token != null) 'Authorization': 'Bearer $token',
    },
  ));
  dio.interceptors.add(InterceptorsWrapper(onError: (e, handler) {
    // 세션 만료: 로그인 화면으로 돌아가게 한다 (로그인 요청 자체의 401은 화면이 이유를 보여 준다)
    if (e.response?.statusCode == 401 && token != null && !e.requestOptions.path.startsWith('/auth/')) {
      ref.read(authProvider.notifier).sessionExpired();
    }
    handler.next(e);
  }));
  return ApiMuklogRepository(dio);
});

final meProvider =
    FutureProvider<UserProfile>((ref) => ref.watch(repositoryProvider).me());

final friendsProvider = FutureProvider<List<UserProfile>>(
    (ref) => ref.watch(repositoryProvider).friends());

final placesProvider = FutureProvider<List<Place>>(
    (ref) => ref.watch(repositoryProvider).places());

final recommendProvider = FutureProvider<List<ScoredPlace>>((ref) async {
  final near = await ref.watch(searchCenterProvider.future);
  return ref.watch(repositoryProvider).recommend(near: near);
});

final dislikesProvider = FutureProvider<List<Dislike>>(
    (ref) => ref.watch(repositoryProvider).dislikes());

final coupleProvider = FutureProvider.family<Coupling, String>(
    (ref, friendId) => ref.watch(repositoryProvider).couple(friendId));

final briefingProvider = FutureProvider.family<Briefing, String>(
    (ref, area) => ref.watch(repositoryProvider).briefing(area));

final rankingProvider = FutureProvider.family<List<RankingEntry>, RankingScope>(
    (ref, scope) => ref.watch(repositoryProvider).ranking(scope));
