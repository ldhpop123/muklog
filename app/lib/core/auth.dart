import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/muklog_repository.dart';
import '../data/providers.dart';
import '../models/auth.dart';
import '../models/user_profile.dart';
import 'config.dart';
import 'naver_login/naver_login.dart';

/// 먹로그 세션 토큰. API 요청마다 Authorization: Bearer로 붙는다 (providers.dart의 Dio).
final authTokenProvider = StateProvider<String?>((ref) => null);

const _tokenKey = 'muklog.session';

/// 각 회사 SDK로 로그인해서, 서버에 보낼 토큰을 얻는다.
/// 카카오·네이버는 액세스 토큰, 구글은 ID 토큰.
abstract class SocialSignIn {
  Future<String> obtainToken(SocialProvider provider);
  Future<void> signOut(SocialProvider provider);
}

/// 서버 없이 화면 흐름을 확인하기 위한 가짜 로그인.
class MockSocialSignIn implements SocialSignIn {
  @override
  Future<String> obtainToken(SocialProvider provider) async =>
      'mock-${provider.name}-token';

  @override
  Future<void> signOut(SocialProvider provider) async {}
}

/// 실제 SDK 로그인. 네이버는 이 경로를 쓰지 않는다 (서버 리다이렉트 + PKCE, naver_login/).
/// TODO(auth): 구글 키가 준비되면 google_sign_in 연결.
class SdkSocialSignIn implements SocialSignIn {
  @override
  Future<String> obtainToken(SocialProvider provider) => switch (provider) {
        SocialProvider.kakao => _kakao(),
        _ => throw MuklogException('${provider.label} 로그인 설정이 아직 안 되어 있어요. 앱에 로그인 키를 넣어 주세요'),
      };

  /// 카카오톡이 있으면 카카오톡으로, 없거나 실패하면 카카오 계정(브라우저)으로 로그인한다.
  Future<String> _kakao() async {
    if (!AppConfig.hasKakao) {
      throw const MuklogException('카카오 로그인 설정이 아직 안 되어 있어요. 앱에 카카오 키를 넣어 주세요');
    }
    try {
      if (await isKakaoTalkInstalled()) {
        try {
          return (await UserApi.instance.loginWithKakaoTalk()).accessToken;
        } on PlatformException catch (e) {
          if (e.code == 'CANCELED') throw const MuklogException('카카오 로그인을 취소했어요');
          // 카카오톡에 로그인돼 있지 않은 경우 등: 카카오 계정 로그인으로 넘어간다
        }
      }
      return (await UserApi.instance.loginWithKakaoAccount()).accessToken;
    } on MuklogException {
      rethrow;
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') throw const MuklogException('카카오 로그인을 취소했어요');
      throw MuklogException('카카오 로그인을 하지 못했어요 (${e.code})');
    } on KakaoAuthException catch (e) {
      // 키 해시·클라이언트 시크릿 설정 문제는 여기서 원인이 드러난다
      throw MuklogException('카카오 로그인을 하지 못했어요 (${e.error.name}: ${e.errorDescription ?? ''})');
    } on KakaoException catch (e) {
      throw MuklogException('카카오 로그인을 하지 못했어요 (${e.runtimeType})');
    }
  }

  @override
  Future<void> signOut(SocialProvider provider) async {
    if (provider == SocialProvider.kakao && AppConfig.hasKakao) {
      try {
        await UserApi.instance.logout();
      } catch (_) {
        // 카카오 토큰이 이미 만료됐어도 먹로그 로그아웃은 진행한다
      }
    }
  }
}

final socialSignInProvider = Provider<SocialSignIn>(
    (ref) => AppConfig.useMock ? MockSocialSignIn() : SdkSocialSignIn());

/// 로그인한 사용자. null이면 로그아웃 상태. 앱을 켤 때 저장된 세션으로 자동 로그인한다.
class AuthNotifier extends AsyncNotifier<UserProfile?> {
  SocialProvider? _provider;

  @override
  Future<UserProfile?> build() async {
    // 웹: 네이버 로그인에서 돌아온 직후라면 그 결과로 로그인한다
    if (!AppConfig.useMock) {
      final pending = takePendingNaverLogin();
      if (pending != null) {
        final result = await ref.read(repositoryProvider).exchangeLoginCode(pending.$1, pending.$2);
        return _finish(result, SocialProvider.naver);
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_tokenKey);
    if (saved == null) return null;
    ref.read(authTokenProvider.notifier).state = saved;
    try {
      return await ref.read(repositoryProvider).me();
    } on MuklogException catch (e) {
      if (e.statusCode == 401) {
        await _clear();
        return null;
      }
      rethrow; // 서버가 잠시 안 될 때는 세션을 지우지 않는다
    }
  }

  Future<void> login(SocialProvider provider) async {
    final previous = state.valueOrNull;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(repositoryProvider);
      if (provider == SocialProvider.naver && !AppConfig.useMock) {
        final r = await startNaverLogin();
        // 웹은 페이지가 네이버로 넘어간다. 돌아오면 build()가 이어서 처리한다.
        if (r == null) return previous;
        return _finish(await repo.exchangeLoginCode(r.$1, r.$2), provider);
      }
      final token = await ref.read(socialSignInProvider).obtainToken(provider);
      return _finish(await repo.login(provider, token), provider);
    });
    // 실패하면 이전 상태(보통 로그아웃)로 두고, 화면은 state.error로 이유를 보여 준다
    if (state.hasError && previous != null) state = AsyncData(previous);
  }

  Future<UserProfile> _finish(
      AuthResult result, SocialProvider provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, result.accessToken);
    ref.read(authTokenProvider.notifier).state = result.accessToken;
    _provider = provider;
    return result.user;
  }

  /// 밸런스 게임을 마쳤을 때.
  void markOnboarded() {
    final user = state.valueOrNull;
    if (user != null) state = AsyncData(user.copyWith(onboarded: true));
  }

  Future<void> logout() async {
    try {
      await ref.read(repositoryProvider).logout();
    } on MuklogException {
      // 서버 세션 삭제에 실패해도 기기에서는 로그아웃한다
    }
    final p = _provider;
    if (p != null) await ref.read(socialSignInProvider).signOut(p);
    await _clear();
    state = const AsyncData(null);
  }

  /// 서버가 401을 주면 (세션 만료) 조용히 로그아웃한다.
  Future<void> sessionExpired() async {
    if (state.valueOrNull == null) return;
    await _clear();
    state = const AsyncData(null);
  }

  Future<void> _clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    ref.read(authTokenProvider.notifier).state = null;
  }
}

final authProvider =
    AsyncNotifierProvider<AuthNotifier, UserProfile?>(AuthNotifier.new);
