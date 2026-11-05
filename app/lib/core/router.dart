import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'widgets.dart';
import '../features/dislikes/dislikes_screen.dart';
import '../features/friend/friend_compare_screen.dart';
import '../features/map/map_screen.dart';
import '../features/onboarding/balance_game_screen.dart';
import '../features/party/party_mode_screen.dart';
import '../features/place/place_detail_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/ranking/ranking_screen.dart';
import '../features/record/place_search_screen.dart';
import '../features/record/record_form_screen.dart';
import '../features/shell/home_shell.dart';

/// 밸런스 게임 온보딩을 마쳤는지.
/// TODO(auth): 로그인 연동 후 서버 프로필(또는 로컬 저장소)에서 읽어 오기
final onboardedProvider = StateProvider<bool>((ref) => false);

final routerProvider = Provider<GoRouter>((ref) {
  // 온보딩 상태가 바뀌면 redirect를 다시 평가한다.
  final refresh = ValueNotifier(0);
  ref.listen(onboardedProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    // 웹은 브라우저 주소가 initialLocation보다 우선하므로, 온보딩 진입은 redirect로 보장한다.
    redirect: (_, state) {
      final onboarded = ref.read(onboardedProvider);
      final atOnboarding = state.matchedLocation == '/onboarding';
      if (!onboarded && !atOnboarding) return '/onboarding';
      if (onboarded && atOnboarding) return '/';
      return null;
    },
    routes: [
      GoRoute(
          path: '/onboarding', builder: (_, __) => const ReadableWidth(child: BalanceGameScreen())),
      ShellRoute(
        builder: (_, state, child) =>
            HomeShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', builder: (_, __) => const MapScreen()),
          GoRoute(path: '/party', builder: (_, __) => const ReadableWidth(child: PartyModeScreen())),
          GoRoute(path: '/profile', builder: (_, __) => const ReadableWidth(child: ProfileScreen())),
        ],
      ),
      GoRoute(
        path: '/place/:id',
        builder: (_, state) =>
            ReadableWidth(child: PlaceDetailScreen(placeId: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/friend/:id',
        builder: (_, state) =>
            ReadableWidth(child: FriendCompareScreen(friendId: state.pathParameters['id']!)),
      ),
      GoRoute(path: '/record/search', builder: (_, __) => const ReadableWidth(child: PlaceSearchScreen())),
      GoRoute(path: '/ranking', builder: (_, __) => const ReadableWidth(child: RankingScreen())),
      GoRoute(path: '/dislikes', builder: (_, __) => const ReadableWidth(child: DislikesScreen())),
      GoRoute(
        path: '/record/new',
        builder: (_, state) => ReadableWidth(
          child: RecordFormScreen(
            placeId: state.uri.queryParameters['placeId']!,
            inspiredByRecordId: state.uri.queryParameters['inspiredBy'],
            fromSearch: state.uri.queryParameters['from'] == 'search',
          ),
        ),
      ),
    ],
  );
});
