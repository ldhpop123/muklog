import 'scored_place.dart';
import 'user_profile.dart';

/// 불호·알레르기 항목. 식당의 카테고리·태그·이름(부분 일치)에 걸리면 추천에서 빠진다.
class Dislike {
  const Dislike(this.target, {this.kind = DislikeKind.dislike});
  final String target;
  final DislikeKind kind;

  factory Dislike.fromJson(Map<String, dynamic> json) =>
      Dislike(json['target'] as String,
          kind: DislikeKind.fromLabel(json['kind'] as String? ?? '불호'));

  Map<String, dynamic> toJson() => {'target': target, 'kind': kind.label};
}

enum DislikeKind {
  dislike('불호'),
  allergy('알레르기');

  const DislikeKind(this.label);
  final String label;

  static DislikeKind fromLabel(String s) =>
      values.firstWhere((k) => k.label == s, orElse: () => dislike);
}

class DimensionDiff {
  const DimensionDiff(
      {required this.label, required this.me, required this.them});
  final String label;
  final double me;
  final double them;

  factory DimensionDiff.fromJson(Map<String, dynamic> json) => DimensionDiff(
        label: json['label'] as String,
        me: (json['me'] as num).toDouble(),
        them: (json['them'] as num).toDouble(),
      );
}

/// 친구 비교 화면 데이터 (GET /users/{id}/couple).
class Coupling {
  const Coupling({
    required this.user,
    required this.percent,
    required this.dimensions,
    required this.sharedPlaceCount,
    required this.suggestions,
  });

  final UserProfile user;
  final int percent;
  final List<DimensionDiff> dimensions;
  final int sharedPlaceCount;

  /// 친구가 4점 이상 줬고 내가 안 가 본 곳 (최대 3곳)
  final List<ScoredPlace> suggestions;

  factory Coupling.fromJson(Map<String, dynamic> json) => Coupling(
        user: UserProfile.fromJson(json['user'] as Map<String, dynamic>),
        percent: json['percent'] as int,
        dimensions: (json['dimensions'] as List)
            .map((d) => DimensionDiff.fromJson(d as Map<String, dynamic>))
            .toList(),
        sharedPlaceCount: json['shared_place_count'] as int,
        suggestions: (json['suggestions'] as List)
            .map((s) => ScoredPlace.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

/// AI 지역 브리핑 (GET /briefing?area=).
class Briefing {
  const Briefing(
      {required this.area,
      required this.sentences,
      required this.places,
      required this.byLlm});
  final String area;
  final List<String> sentences;
  final List<ScoredPlace> places;

  /// false면 LLM 없이 템플릿으로 만든 문장
  final bool byLlm;

  factory Briefing.fromJson(Map<String, dynamic> json) => Briefing(
        area: json['area'] as String,
        sentences: (json['sentences'] as List)
            .map((s) => (s as Map<String, dynamic>)['text'] as String)
            .toList(),
        places: (json['places'] as List)
            .map((s) => ScoredPlace.fromJson(s as Map<String, dynamic>))
            .toList(),
        byLlm: json['generated_by'] == 'llm',
      );
}

/// 랭킹 등 공개 화면용 사용자 정보. 입맛 벡터는 담지 않는다 (친구가 아닌 사람의 취향 보호).
class PublicUser {
  const PublicUser({
    required this.id,
    required this.nickname,
    required this.avatarUrl,
    required this.trustTemp,
    required this.level,
    this.title,
  });

  final String id;
  final String nickname;
  final String avatarUrl;
  final double trustTemp;
  final String level;
  final String? title;

  factory PublicUser.fromProfile(UserProfile u) => PublicUser(
      id: u.id,
      nickname: u.nickname,
      avatarUrl: u.avatarUrl,
      trustTemp: u.trustTemp,
      level: u.level,
      title: u.title);

  factory PublicUser.fromJson(Map<String, dynamic> json) => PublicUser(
        id: json['id'] as String,
        nickname: json['nickname'] as String,
        avatarUrl: json['avatar_url'] as String,
        trustTemp: (json['trust_temp'] as num).toDouble(),
        level: json['level'] as String? ?? UserProfile.defaultLevel,
        title: json['title'] as String?,
      );
}

class RankingEntry {
  const RankingEntry(this.rank, this.user);
  final int rank;
  final PublicUser user;

  factory RankingEntry.fromJson(Map<String, dynamic> json) => RankingEntry(
      json['rank'] as int,
      PublicUser.fromJson(json['user'] as Map<String, dynamic>));
}

enum RankingScope { friends, all }

enum MapLayer { all, friends, mine }
