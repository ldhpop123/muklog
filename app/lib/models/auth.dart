import 'user_profile.dart';

/// 지원하는 소셜 로그인. 이메일·비밀번호 가입은 두지 않는다.
enum SocialProvider {
  kakao('카카오'),
  naver('네이버'),
  google('Google');

  const SocialProvider(this.label);
  final String label;
}

/// POST /auth/login 응답.
class AuthResult {
  const AuthResult({required this.accessToken, required this.user, required this.isNew});

  /// 먹로그 세션 토큰 (이후 모든 요청의 Authorization: Bearer)
  final String accessToken;
  final UserProfile user;

  /// 이번에 처음 가입한 사용자
  final bool isNew;

  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(
        accessToken: json['access_token'] as String,
        user: UserProfile.fromJson(json['user'] as Map<String, dynamic>),
        isNew: json['is_new'] as bool? ?? false,
      );
}
