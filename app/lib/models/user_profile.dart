import 'taste_vector.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.nickname,
    required this.avatarUrl,
    required this.taste,
    this.trustTemp = 36.5,
    this.level = defaultLevel,
    this.title,
    this.onboarded = true,
  });

  static const defaultLevel = '새내기 먹로거';

  final String id;
  final String nickname;
  final String avatarUrl;
  final TasteVector taste;

  /// 맛 신뢰 온도 (README 7장). 기본값 36.5℃.
  final double trustTemp;

  /// 온도 구간별 레벨 (README 7.3). 예: "동네 맛잘알"
  final String level;

  /// 칭호. 예: "홍대 국밥 감별사"
  final String? title;

  /// 밸런스 게임으로 첫 취향을 저장했는지. false면 로그인 후 온보딩으로 보낸다.
  final bool onboarded;

  UserProfile copyWith({TasteVector? taste, bool? onboarded}) => UserProfile(
        id: id,
        nickname: nickname,
        avatarUrl: avatarUrl,
        taste: taste ?? this.taste,
        trustTemp: trustTemp,
        level: level,
        title: title,
        onboarded: onboarded ?? this.onboarded,
      );

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        nickname: json['nickname'] as String,
        avatarUrl: json['avatar_url'] as String,
        taste: TasteVector.fromJson(json['taste'] as Map<String, dynamic>),
        trustTemp: (json['trust_temp'] as num?)?.toDouble() ?? 36.5,
        level: json['level'] as String? ?? defaultLevel,
        title: json['title'] as String?,
        // 필드가 없는 예전 서버 응답이면 온보딩을 강제하지 않는다
        onboarded: json['onboarded'] as bool? ?? true,
      );
}
