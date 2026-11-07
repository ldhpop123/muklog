import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth.dart';
import 'widgets.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/splash_screen.dart';
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

final routerProvider = Provider<GoRouter>((ref) {
  // 로그인·온보딩 상태가 바뀌면 redirect를 다시 평가한다.
  final refresh = ValueNotifier(0);
  ref.listen(authProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    // 저장된 세션 확인 중 → 시작 화면, 로그아웃 → 로그인, 취향 미설정 → 밸런스 게임, 나머지 → 원래 가려던 곳.
    // 웹은 브라우저 주소가 initialLocation보다 우선하므로, 화면 진입은 redirect로 보장한다.
    redirect: (_, state) {
      final auth = ref.read(authProvider);
      final at = state.matchedLocation;
      const entry = {'/splash', '/login', '/onboarding'};
      if (auth.isLoading && !auth.hasValue) return at == '/splash' ? null : '/splash';
      final user = auth.valueOrNull;
      if (user == null) return at == '/login' ? null : '/login';
      if (!user.onboarded) return at == '/onboarding' ? null : '/onboarding';
      return entry.contains(at) ? '/' : null;
    },
    routes: [
      GoRoute(
          path: '/onboarding', builder: (_, __) => const ReadableWidth(child: BalanceGameScreen())),
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
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
